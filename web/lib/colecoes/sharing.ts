import type { BinderPage, RegionImage } from "./binder.ts";
import { isSlotImagePath } from "./binder-images.ts";

/**
 * Compartilhamento de coleções (V1-12 COLLECTION-SHARING-FOUNDATION-01) —
 * regras puras do frontend. A autorização é do banco (5300–5313, proposta):
 * aqui só normalizamos entrada, lemos o formato das respostas e traduzimos
 * códigos para a linguagem do colecionador. Nada aqui decide acesso.
 *
 * Papéis neste incremento: o titular (estrutural, C-141) e o participante
 * VIEWER (C-145). EDITOR é V1-13. Visitante de coleção pública não é
 * participante (C-152).
 */

export const SHARED_COLLECTION_PATH = "/colecoes/compartilhada";

export function sharedCollectionHref(id: string, page = 1): string {
  return page > 1 ? `${SHARED_COLLECTION_PATH}/${id}?pagina=${page}` : `${SHARED_COLLECTION_PATH}/${id}`;
}

/** Cartas por página na galeria compartilhada (5313 aceita 1..96). */
export const SHARED_PAGE_SIZE = 48;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function uuid(value: unknown): string | null {
  return typeof value === "string" && UUID.test(value) ? value.toLowerCase() : null;
}
function str(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}
function num(value: unknown): number | null {
  const n = typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : NaN;
  return Number.isFinite(n) ? n : null;
}

// ---------------------------------------------------------------------------
// Entrada
// ---------------------------------------------------------------------------

/** Mesmo formato de `user_profile.username` (1000): 3–20, minúsculas, dígitos e _. */
const USERNAME = /^[a-z0-9_]{3,20}$/;

/** "  @Fulano_1 " → "fulano_1"; inválido → null (o banco normaliza igual, 5303). */
export function normalizeUsername(raw: string): string | null {
  let value = raw.trim().toLowerCase();
  if (value.startsWith("@")) value = value.slice(1);
  return USERNAME.test(value) ? value : null;
}

// ---------------------------------------------------------------------------
// Estados e rótulos
// ---------------------------------------------------------------------------

export type MembershipStatus = "PENDING" | "ACTIVE" | "DECLINED";
export type Visibility = "PRIVATE" | "PUBLIC";
export type ShareAccess = "OWNER" | "VIEWER" | "PUBLIC";

function status(value: unknown): MembershipStatus | null {
  return value === "PENDING" || value === "ACTIVE" || value === "DECLINED" ? value : null;
}
function visibility(value: unknown): Visibility | null {
  return value === "PRIVATE" || value === "PUBLIC" ? value : null;
}

/** Rótulo curto do estado (chip). */
export function statusLabel(value: MembershipStatus): string {
  if (value === "ACTIVE") return "Pode ver";
  if (value === "PENDING") return "Convite enviado";
  return "Recusou";
}

/** Papel em linguagem de colecionador (C-143: rótulo de UX ≠ estrutura). */
export const VIEWER_ROLE_LABEL = "Visualizador";
export const VIEWER_ROLE_HINT = "Vê as cartas e o progresso desta coleção. Não altera nada.";

// ---------------------------------------------------------------------------
// Respostas
// ---------------------------------------------------------------------------

export type ShareMember = {
  membershipId: string;
  username: string;
  displayName: string;
  status: MembershipStatus;
  invitedAt: string | null;
  respondedAt: string | null;
};

export type SharingState = {
  visibility: Visibility;
  archived: boolean;
  members: ShareMember[];
};

/** 5308 → painel do titular. `null` = sem acesso/formato inesperado. */
export function parseSharing(data: unknown): SharingState | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const r = data as Record<string, unknown>;
  const vis = visibility(r.visibility);
  if (!vis || !Array.isArray(r.members)) return null;
  const members: ShareMember[] = [];
  for (const raw of r.members) {
    if (!raw || typeof raw !== "object") continue;
    const m = raw as Record<string, unknown>;
    const id = uuid(m.membership_id);
    const st = status(m.status);
    const username = str(m.username);
    if (!id || !st || !username) continue;
    members.push({
      membershipId: id,
      username,
      displayName: str(m.display_name) ?? username,
      status: st,
      invitedAt: str(m.invited_at),
      respondedAt: str(m.responded_at),
    });
  }
  return { visibility: vis, archived: r.lifecycle_status === "ARCHIVED", members };
}

/** Quantos participantes e convites contam para o limite de 50 (5303). */
export const MEMBER_LIMIT = 50;
export function activeOrPending(members: readonly ShareMember[]): number {
  return members.filter((m) => m.status !== "DECLINED").length;
}

export type InviteOutcome = "INVITED" | "ALREADY_PENDING" | "REINVITED";

export function parseInvite(data: unknown): { outcome: InviteOutcome; member: ShareMember } | null {
  if (!data || typeof data !== "object") return null;
  const r = data as Record<string, unknown>;
  const outcome = r.outcome;
  const id = uuid(r.membership_id);
  const username = str(r.username);
  if ((outcome !== "INVITED" && outcome !== "ALREADY_PENDING" && outcome !== "REINVITED") || !id || !username) return null;
  return {
    outcome,
    member: {
      membershipId: id,
      username,
      displayName: str(r.display_name) ?? username,
      status: "PENDING",
      invitedAt: new Date().toISOString(),
      respondedAt: null,
    },
  };
}

export function inviteOutcomeMessage(outcome: InviteOutcome, member: Pick<ShareMember, "displayName" | "username">): string {
  const who = `${member.displayName} (@${member.username})`;
  if (outcome === "ALREADY_PENDING") return `${who} já tem um convite esperando resposta.`;
  if (outcome === "REINVITED") return `Convite enviado de novo para ${who}.`;
  return `Convite enviado para ${who}. Assim que aceitar, a coleção aparece para essa pessoa.`;
}

export type ReceivedInvite = {
  membershipId: string;
  collectionId: string;
  collectionName: string;
  completionPolicy: string | null;
  cardSetName: string | null;
  ownerDisplayName: string;
  ownerUsername: string | null;
  invitedAt: string | null;
};

/** 5309 → caixa de convites. Lista vazia em qualquer formato inesperado. */
export function parseInvites(data: unknown): ReceivedInvite[] {
  if (!Array.isArray(data)) return [];
  const out: ReceivedInvite[] = [];
  for (const raw of data) {
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const id = uuid(r.membership_id);
    const collectionId = uuid(r.collection_id);
    const name = str(r.collection_name);
    if (!id || !collectionId || !name) continue;
    out.push({
      membershipId: id,
      collectionId,
      collectionName: name,
      completionPolicy: str(r.completion_policy),
      cardSetName: str(r.card_set_name),
      ownerDisplayName: str(r.owner_display_name) ?? "Um colecionador",
      ownerUsername: str(r.owner_username),
      invitedAt: str(r.invited_at),
    });
  }
  return out;
}

export type SharedProgress = { total: number; satisfied: number; complete: boolean } | null;

function progress(r: Record<string, unknown>): SharedProgress {
  const total = num(r.total_positions);
  const satisfied = num(r.satisfied_positions);
  if (total === null || satisfied === null) return null;
  return { total, satisfied, complete: r.is_complete === true };
}

export type SharedWithMe = {
  collectionId: string;
  name: string;
  completionPolicy: string | null;
  archived: boolean;
  coverFinish: string | null;
  cardSetCode: string | null;
  cardSetName: string | null;
  ownerDisplayName: string;
  copies: number;
  progress: SharedProgress;
};

/** 5311 → "Compartilhadas comigo". */
export function parseSharedWithMe(data: unknown): SharedWithMe[] {
  if (!Array.isArray(data)) return [];
  const out: SharedWithMe[] = [];
  for (const raw of data) {
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const id = uuid(r.collection_id);
    const name = str(r.name);
    if (!id || !name) continue;
    out.push({
      collectionId: id,
      name,
      completionPolicy: str(r.completion_policy),
      archived: r.lifecycle_status === "ARCHIVED",
      coverFinish: str(r.cover_finish),
      cardSetCode: str(r.card_set_code),
      cardSetName: str(r.card_set_name),
      ownerDisplayName: str(r.owner_display_name) ?? "Um colecionador",
      copies: num(r.copies_count) ?? 0,
      progress: progress(r),
    });
  }
  return out;
}

export type SharedCollection = {
  collectionId: string;
  name: string;
  description: string | null;
  completionPolicy: string | null;
  archived: boolean;
  visibility: Visibility;
  coverFinish: string | null;
  cardSetCode: string | null;
  cardSetName: string | null;
  cardSetLogoPath: string | null;
  ownerDisplayName: string;
  access: ShareAccess;
  membershipId: string | null;
  copies: number;
  progress: SharedProgress;
};

/** 5312 → cabeçalho. `null` = sem acesso (inexistente/privada alheia/convite pendente — indistinguíveis). */
export function parseSharedCollection(data: unknown): SharedCollection | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const r = data as Record<string, unknown>;
  const id = uuid(r.collection_id);
  const name = str(r.name);
  const vis = visibility(r.visibility);
  const access = r.access === "OWNER" || r.access === "VIEWER" || r.access === "PUBLIC" ? r.access : null;
  if (!id || !name || !vis || !access) return null;
  return {
    collectionId: id,
    name,
    description: str(r.description),
    completionPolicy: str(r.completion_policy),
    archived: r.lifecycle_status === "ARCHIVED",
    visibility: vis,
    coverFinish: str(r.cover_finish),
    cardSetCode: str(r.card_set_code),
    cardSetName: str(r.card_set_name),
    cardSetLogoPath: str(r.card_set_logo_path),
    ownerDisplayName: str(r.owner_display_name) ?? "Um colecionador",
    access,
    membershipId: access === "VIEWER" ? uuid(r.membership_id) : null,
    copies: num(r.copies_count) ?? 0,
    progress: progress(r),
  };
}

export type SharedCard = {
  cardVariantId: string;
  languageCode: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  variantLabel: string | null;
  variantTypeCode: string | null;
  rarityCode: string | null;
  copies: number;
  imagePath: string | null;
};

/** 5313 → galeria. Linhas sem identidade de catálogo são descartadas. */
export function parseSharedCards(data: unknown): { items: SharedCard[]; total: number } {
  if (!Array.isArray(data)) return { items: [], total: 0 };
  const items: SharedCard[] = [];
  let total = 0;
  for (const raw of data) {
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const id = uuid(r.card_variant_id);
    const lang = str(r.language_code);
    const name = str(r.card_name);
    if (!id || !lang || !name) continue;
    total = Math.max(total, num(r.total_count) ?? 0);
    items.push({
      cardVariantId: id,
      languageCode: lang,
      cardName: name,
      collectorNumber: str(r.collector_number) ?? "",
      collectorTotal: num(r.collector_total),
      cardSetCode: str(r.card_set_code) ?? "",
      cardSetName: str(r.card_set_name) ?? "",
      variantLabel: str(r.variant_label),
      variantTypeCode: str(r.variant_type_code),
      rarityCode: str(r.rarity_code),
      copies: Math.max(1, num(r.copies_count) ?? 1),
      imagePath: str(r.image_path),
    });
  }
  return { items, total: Math.max(total, items.length) };
}

// ---------------------------------------------------------------------------
// Fichário compartilhado (V1-12 SHARING CORRECTION — 5314/5315, proposta)
// ---------------------------------------------------------------------------

export function sharedBinderHref(id: string): string {
  return `${SHARED_COLLECTION_PATH}/${id}/fichario`;
}

/**
 * Vitrine pública do fichário (V1-12 PUBLIC BINDER EXPERIENCE, 5317/5318):
 * link curto e compartilhável, sem login. Só o fichário — nunca galeria,
 * progresso ou acervo.
 */
export const PUBLIC_BINDER_PATH = "/fichario";

export function publicBinderHref(id: string, page = 0): string {
  return page > 0 ? `${PUBLIC_BINDER_PATH}/${id}?pagina=${page}` : `${PUBLIC_BINDER_PATH}/${id}`;
}

export type PublicBinder = {
  collectionId: string;
  name: string;
  completionPolicy: string | null;
  coverFinish: string | null;
  ownerDisplayName: string;
  cardSetCode: string | null;
  cardSetName: string | null;
  cardSetLogoPath: string | null;
  binderName: string | null;
  showBrandMark: boolean;
  binder: { columns: number; rows: number; pageCount: number } | null;
};

/** 5317 → vitrine. `null` = não publicada / inexistente / formato inesperado (404). */
export function parsePublicBinder(data: unknown): PublicBinder | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const r = data as Record<string, unknown>;
  const id = uuid(r.collection_id);
  const name = str(r.name);
  if (!id || !name) return null;
  let binder: PublicBinder["binder"] = null;
  if (r.has_binder === true) {
    const columns = num(r.grid_columns);
    const rows = num(r.grid_rows);
    const pageCount = num(r.page_count);
    if (!columns || !rows || columns < 1 || rows < 1 || columns > 10 || rows > 10 || pageCount === null || pageCount < 0) return null;
    binder = { columns, rows, pageCount };
  } else if (r.has_binder !== false) {
    return null;
  }
  return {
    collectionId: id,
    name,
    completionPolicy: str(r.completion_policy),
    coverFinish: str(r.cover_finish),
    ownerDisplayName: str(r.owner_display_name) ?? "Um colecionador",
    cardSetCode: str(r.card_set_code),
    cardSetName: str(r.card_set_name),
    cardSetLogoPath: str(r.card_set_logo_path),
    binderName: str(r.binder_name),
    showBrandMark: r.show_brand_mark !== false,
    binder,
  };
}

/** Páginas por leitura (5315 aceita 1..4 — mesmo teto da leitura do titular). */
export const SHARED_BINDER_PAGES_PER_READ = 4;

/**
 * Identidade do fichário vista pelo participante (5320, proposta): nome
 * próprio gravado pelo titular e logomarca. `name` nulo = sem nome próprio
 * (a interface usa o nome da coleção vista — nunca o de outra coleção).
 */
export type SharedBinderIdentity = { name: string | null; showBrandMark: boolean };

export type SharedBinder =
  | { hasBinder: false }
  | { hasBinder: true; columns: number; rows: number; pageCount: number; ownFilled: number; identity: SharedBinderIdentity | null };

/** 5314 → cabeçalho. `null` = sem acesso / formato inesperado. */
export function parseSharedBinder(data: unknown): SharedBinder | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null;
  const r = data as Record<string, unknown>;
  if (r.has_binder === false) return { hasBinder: false };
  if (r.has_binder !== true) return null;
  const columns = num(r.grid_columns);
  const rows = num(r.grid_rows);
  const pageCount = num(r.page_count);
  if (!columns || !rows || columns < 1 || rows < 1 || columns > 10 || rows > 10 || pageCount === null || pageCount < 0) return null;
  // 5320 (proposta) acrescenta `binder_name`/`show_brand_mark`; antes dela a identidade fica nula.
  const identity: SharedBinderIdentity | null =
    typeof r.show_brand_mark === "boolean"
      ? { name: typeof r.binder_name === "string" && r.binder_name.trim() !== "" ? r.binder_name.trim().slice(0, 60) : null, showBrandMark: r.show_brand_mark }
      : null;
  return { hasBinder: true, columns, rows, pageCount, ownFilled: Math.max(0, num(r.own_filled_count) ?? 0), identity };
}

/**
 * Bolso visto por quem não é titular. Só três estados (5315): carta desta
 * coleção, reserva desta coleção, vazio — "vazio" também cobre carta de
 * outra coleção do mesmo fichário, de propósito.
 */
export type SharedPocket = {
  row: number;
  column: number;
  kind: "card" | "reserve" | "empty";
  cardName: string | null;
  collectorNumber: string | null;
  collectorTotal: number | null;
  setCode: string | null;
  variantLabel: string | null;
  languageCode: string | null;
  imagePath: string | null;
};

export type SharedBinderPage = {
  pageNumber: number;
  pockets: SharedPocket[];
  /** Imagens decorativas desta página (5326/5327), já com URL assinada. Ausente = nenhuma. */
  images?: SharedBinderImage[];
};

/**
 * Imagem decorativa do fichário vista por quem não é o titular (5325–5327):
 * bolso (1×1, só eixo vertical) ou mesclagem (retângulo, dois eixos). Sem ids
 * internos — a posição na grade é a identidade. `url` nulo = assinatura
 * negada ou falhou: a imagem não é mostrada (o bolso fica vazio, nunca um
 * aviso que revele que ali existe algo).
 */
export type SharedBinderImage = {
  pageNumber: number;
  row: number;
  column: number;
  height: number;
  width: number;
  region: boolean;
  path: string;
  focalX: number;
  focalY: number;
  updatedAt: string | null;
  url: string | null;
};

/** 5326/5327 → imagens. Formato inválido em qualquer linha → `null` (leitura descartada inteira). */
export function parseSharedBinderImages(data: unknown): SharedBinderImage[] | null {
  if (!Array.isArray(data)) return null;
  const out: SharedBinderImage[] = [];
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const pageNumber = num(r.page_number);
    const row = num(r.row_index);
    const column = num(r.column_index);
    const height = num(r.height);
    const width = num(r.width);
    const focalX = num(r.focal_x);
    const focalY = num(r.focal_y);
    if (pageNumber === null || row === null || column === null || height === null || width === null || focalX === null || focalY === null) return null;
    if (pageNumber < 1 || row < 1 || column < 1 || height < 1 || width < 1 || focalX < 0 || focalX > 100 || focalY < 0 || focalY > 100) return null;
    if (typeof r.is_region !== "boolean" || !isSlotImagePath(r.storage_path)) return null;
    // Bolso é sempre 1×1; mesclagem nunca é 1×1.
    if (r.is_region === (height === 1 && width === 1)) return null;
    out.push({ pageNumber, row, column, height, width, region: r.is_region, path: r.storage_path, focalX, focalY, updatedAt: str(r.updated_at), url: null });
  }
  return out;
}

/**
 * Validade das URLs assinadas entregues a quem não é o titular (participante e
 * vitrine): 10 min. Revogar a participação ou despublicar impede NOVAS
 * assinaturas na hora (5329); uma URL já entregue vale até expirar.
 */
export const SHARED_VISUAL_URL_TTL = 600;

/** Caminho da capa enviada (5177): `<dono>/<coleção>/<arquivo>.(png|jpg|webp)`. */
const COVER_PATH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$/;
const COVER_CODE = /^[A-Z0-9]{2,6}$/;

/** 5328 → capa da própria coleção. Zero linhas (sem acesso) → `null`; campos inválidos são ignorados. */
export function parseSharedCover(data: unknown): { path: string | null; code: string | null } | null {
  const row = Array.isArray(data) ? data[0] : null;
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  const path = typeof r.cover_logo_path === "string" && COVER_PATH.test(r.cover_logo_path) ? r.cover_logo_path : null;
  const code = typeof r.cover_code === "string" && COVER_CODE.test(r.cover_code) ? r.cover_code : null;
  return { path, code };
}

/** Distribui as imagens assinadas pelas páginas do lote (só páginas presentes; imagem sem URL é descartada). */
export function attachSharedBinderImages(pages: SharedBinderPage[], images: SharedBinderImage[]): SharedBinderPage[] {
  const byPage = new Map<number, SharedBinderImage[]>();
  for (const image of images) {
    if (!image.url) continue;
    const list = byPage.get(image.pageNumber) ?? [];
    list.push(image);
    byPage.set(image.pageNumber, list);
  }
  if (byPage.size === 0) return pages;
  return pages.map((page) => {
    const list = byPage.get(page.pageNumber);
    return list && list.length > 0 ? { ...page, images: list } : page;
  });
}

function emptyPocket(row: number, column: number): SharedPocket {
  return { row, column, kind: "empty", cardName: null, collectorNumber: null, collectorTotal: null, setCode: null, variantLabel: null, languageCode: null, imagePath: null };
}

/**
 * 5315 → páginas na ordem linha → coluna, sempre com a grade completa
 * (célula ausente = bolso vazio). Linha fora da grade ou formato inválido →
 * `null` (falha de leitura, nunca uma página "parcial" silenciosa).
 */
export function parseSharedBinderPages(data: unknown, columns: number, rows: number): SharedBinderPage[] | null {
  if (!Array.isArray(data)) return null;
  const pages = new Map<number, Map<string, SharedPocket>>();
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const pageNumber = num(r.page_number);
    const row = num(r.row_index);
    const column = num(r.column_index);
    if (pageNumber === null || row === null || column === null) return null;
    if (row < 1 || row > rows || column < 1 || column > columns) return null;
    const state = r.pocket_state;
    const kind = state === "CARD" ? "card" : state === "RESERVED" ? "reserve" : state === "EMPTY" ? "empty" : null;
    if (!kind) return null;
    const cells = pages.get(pageNumber) ?? new Map<string, SharedPocket>();
    cells.set(
      `${row}:${column}`,
      kind === "empty"
        ? emptyPocket(row, column)
        : {
            row,
            column,
            kind,
            cardName: str(r.card_name),
            collectorNumber: str(r.collector_number),
            collectorTotal: num(r.collector_total),
            setCode: str(r.card_set_code),
            variantLabel: str(r.variant_label),
            languageCode: kind === "card" ? str(r.language_code) : null,
            imagePath: str(r.image_path),
          },
    );
    pages.set(pageNumber, cells);
  }
  return [...pages.entries()]
    .sort(([a], [b]) => a - b)
    .map(([pageNumber, cells]) => {
      const pockets: SharedPocket[] = [];
      for (let row = 1; row <= rows; row += 1) {
        for (let column = 1; column <= columns; column += 1) pockets.push(cells.get(`${row}:${column}`) ?? emptyPocket(row, column));
      }
      return { pageNumber, pockets };
    });
}

/** Primeira página do spread que contém `page` (spread de 2: 1–2, 3–4…; de 1: a própria). */
export function spreadFirstPage(page: number, perView: 1 | 2): number {
  const safe = Math.max(1, Math.floor(page));
  return perView === 2 ? safe - ((safe - 1) % 2) : safe;
}

/** Início do lote de leitura que contém `page` (lotes de 4: 1–4, 5–8…; alinhado aos spreads de 2). */
export function sharedBatchStart(page: number): number {
  const safe = Math.max(1, Math.floor(page));
  return safe - ((safe - 1) % SHARED_BINDER_PAGES_PER_READ);
}

/** Texto acessível de um bolso compartilhado. */
export function sharedPocketLabel(pocket: SharedPocket): string {
  const where = `Linha ${pocket.row}, coluna ${pocket.column}`;
  if (pocket.kind === "card") return `${where}: ${[pocket.cardName ?? "carta", pocket.variantLabel, pocket.languageCode].filter(Boolean).join(", ")}`;
  if (pocket.kind === "reserve") return `${where}: falta ${pocket.cardName ?? "uma carta"}`;
  return `${where}: bolso vazio`;
}

// ---------------------------------------------------------------------------
// Falhas
// ---------------------------------------------------------------------------

export type SharingFailure =
  | "not_authenticated"
  | "invalid_username"
  | "user_not_found"
  | "self"
  | "already_member"
  | "member_limit"
  | "archived"
  | "not_found"
  | "invite_not_found"
  | "not_member"
  | "unavailable"
  | "unknown";

/** Mensagens estáveis de 5303–5307 (texto do RAISE) e SQLSTATE; nada de texto cru ao usuário. */
export function classifySharingFailure(code: string | undefined, message: string | undefined): SharingFailure {
  const m = (message ?? "").trim();
  if (code === "28000" || m === "NOT_AUTHENTICATED") return "not_authenticated";
  if (m === "INVALID_USERNAME") return "invalid_username";
  if (m === "USER_NOT_FOUND") return "user_not_found";
  if (m === "CANNOT_INVITE_SELF") return "self";
  if (m === "ALREADY_MEMBER") return "already_member";
  if (m === "MEMBER_LIMIT") return "member_limit";
  if (m === "COLLECTION_ARCHIVED") return "archived";
  if (m === "COLLECTION_NOT_FOUND" || m === "MEMBERSHIP_NOT_FOUND") return "not_found";
  if (m === "INVITE_NOT_FOUND") return "invite_not_found";
  if (m === "NOT_A_MEMBER") return "not_member";
  // Função ausente (proposta ainda não aplicada) ou sem permissão.
  if (code === "PGRST202" || code === "42883" || code === "42501") return "unavailable";
  return "unknown";
}

export function sharingFailureMessage(reason: SharingFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "invalid_username":
      return "Digite o nome de usuário exato, como @colecionador (3 a 20 letras, números ou _).";
    case "user_not_found":
      return "Não encontramos ninguém com esse nome de usuário. Confira com a pessoa.";
    case "self":
      return "Esta coleção já é sua — não é preciso convidar você mesmo.";
    case "already_member":
      return "Essa pessoa já participa desta coleção.";
    case "member_limit":
      return "Esta coleção chegou ao limite de 50 pessoas entre participantes e convites.";
    case "archived":
      return "Coleção arquivada: reative-a para convidar ou torná-la pública.";
    case "not_found":
      return "Isso já não está mais aqui. Atualize a lista.";
    case "invite_not_found":
      return "Este convite não está mais disponível — pode ter sido cancelado.";
    case "not_member":
      return "Você já não participa desta coleção.";
    case "unavailable":
      return "O compartilhamento ainda não está disponível. Tente mais tarde.";
    default:
      return "Não deu certo agora. Nada foi alterado — tente de novo.";
  }
}

/**
 * Quando chegou o convite, em linguagem de gente (Inbox global): "agora",
 * "há 5 min", "há 3 h", "ontem", "há 4 dias" e, depois de uma semana, a data
 * curta ("12 out"). Data ausente ou inválida → `null` (a linha some).
 */
export function invitedAgoLabel(iso: string | null, now: number = Date.now()): string | null {
  if (!iso) return null;
  const at = new Date(iso).getTime();
  if (Number.isNaN(at)) return null;
  const minutes = Math.floor(Math.max(0, now - at) / 60_000);
  if (minutes < 1) return "agora";
  if (minutes < 60) return `há ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `há ${hours} h`;
  const days = Math.floor(hours / 24);
  if (days === 1) return "ontem";
  if (days < 7) return `há ${days} dias`;
  return new Date(at).toLocaleDateString("pt-BR", { day: "numeric", month: "short" }).replace(".", "");
}

/**
 * Página mascarada (5315) → página no formato do fichário do titular
 * (`BinderPage`), para o leitor do participante usar a MESMA folha de bolsos
 * (`PageGrid` → `BinderSlotView`) em modo só leitura (V1-12 VIEWER
 * EXPERIENCE PARITY CORRECTION-02). Só o que a 5315 entrega: nenhuma
 * identidade interna (exemplar, alocação, assinatura), nenhuma imagem
 * personalizada, nenhuma fixação — o bolso alheio já chega como vazio.
 */
export function sharedPageToBinderPage(page: SharedBinderPage): BinderPage {
  // Imagens decorativas (5326/5327): só sobre bolso vazio (o banco garante a
  // exclusividade com carta/reserva; se algo divergir, a carta vence).
  const empty = new Set(page.pockets.filter((p) => p.kind === "empty").map((p) => `${p.row}:${p.column}`));
  const slotImages = new Map<string, SharedBinderImage>();
  const regions: RegionImage[] = [];
  const regionOf = new Map<string, string>();
  for (const image of page.images ?? []) {
    if (!image.url) continue;
    if (!image.region) {
      if (empty.has(`${image.row}:${image.column}`)) slotImages.set(`${image.row}:${image.column}`, image);
      continue;
    }
    const cells: string[] = [];
    for (let r = image.row; r < image.row + image.height; r += 1) {
      for (let c = image.column; c < image.column + image.width; c += 1) cells.push(`${r}:${c}`);
    }
    if (!cells.every((cell) => empty.has(cell) && !regionOf.has(cell))) continue;
    const regionId = `shared-region:${page.pageNumber}:${image.row}:${image.column}`;
    for (const cell of cells) regionOf.set(cell, regionId);
    regions.push({
      regionId,
      row: image.row,
      leftColumn: image.column,
      height: image.height,
      width: image.width,
      path: image.path,
      focalX: image.focalX,
      focalY: image.focalY,
      updatedAt: image.updatedAt,
      url: image.url,
    });
  }
  return {
    pageNumber: page.pageNumber,
    pageId: `shared:${page.pageNumber}`,
    ...(regions.length > 0 ? { regions } : {}),
    slots: page.pockets.map((pocket) => {
      const cell = `${pocket.row}:${pocket.column}`;
      const decorative = slotImages.get(cell);
      const face = pocket.cardName
        ? {
            cardName: pocket.cardName,
            collectorNumber: pocket.collectorNumber,
            collectorTotal: pocket.collectorTotal,
            setCode: pocket.setCode,
            imagePath: pocket.imagePath,
            finishCode: null,
            finishName: pocket.variantLabel,
          }
        : null;
      const card = pocket.kind === "card" && face !== null;
      const reserve = pocket.kind === "reserve";
      return {
        slotId: `shared:${page.pageNumber}:${pocket.row}:${pocket.column}`,
        row: pocket.row,
        column: pocket.column,
        locked: false,
        state: card ? "OCCUPIED_UNPLANNED" : reserve ? "RESERVED_EMPTY" : "EMPTY",
        expected: reserve ? face : null,
        present: card ? { ...face, languageCode: pocket.languageCode, variantLabel: pocket.variantLabel } : null,
        assignmentId: null,
        allocationId: null,
        expectedCardId: null,
        presentCardId: null,
        presentVariantTypeId: null,
        presentCollectionId: null,
        expectedCollectionId: null,
        image: decorative && !regionOf.has(cell) ? { path: decorative.path, focalY: decorative.focalY, updatedAt: decorative.updatedAt, url: decorative.url } : null,
        regionId: regionOf.get(cell) ?? null,
      };
    }),
  };
}

// ---------------------------------------------------------------------------
// Grade do participante (5320, proposta) — Todas · Tenho · Faltam
// ---------------------------------------------------------------------------

/** Filtro da grade na URL da coleção compartilhada (`?ver=`), o mesmo vocabulário do titular. */
export type SharedPositionFilter = "todas" | "tenho" | "faltam";

export function sharedPositionsHref(id: string, filter: SharedPositionFilter): string {
  return filter === "todas" ? `${SHARED_COLLECTION_PATH}/${id}` : `${SHARED_COLLECTION_PATH}/${id}?ver=${filter}`;
}

/**
 * Posição do Set vista pelo participante: a mesma forma da grade do titular,
 * SEM `copiesAvailable` (acervo privado do titular — a 5320 não o devolve).
 */
export type SharedPosition = {
  cardId: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardName: string;
  imagePath: string | null;
  isSatisfied: boolean;
  copiesInCollection: number;
};

/** 5320 → página de posições. Linha sem identidade é descartada; formato inválido → `null`. */
export function parseSharedPositions(data: unknown): { items: SharedPosition[]; total: number } | null {
  if (!Array.isArray(data)) return null;
  const items: SharedPosition[] = [];
  let total = 0;
  for (const raw of data) {
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const cardId = uuid(r.card_id);
    const collectorNumber = str(r.collector_number);
    const cardName = str(r.card_name);
    if (!cardId || !collectorNumber || !cardName) continue;
    items.push({
      cardId,
      collectorNumber,
      collectorTotal: num(r.collector_total),
      cardName,
      imagePath: str(r.image_path),
      isSatisfied: r.is_satisfied === true,
      copiesInCollection: Math.max(0, num(r.copies_in_collection) ?? 0),
    });
    total = Math.max(total, num(r.total_count) ?? 0);
  }
  return { items, total };
}
