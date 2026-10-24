/**
 * Identidade e Centro de Controle do Fichário (P3-A) — regras puras.
 *
 * Contratos (propostos em `database/proposals/2026-10-23-p3a-binder-control-identity/`):
 *  - 5245 `get_my_binder_identity`  (leve, lido no servidor com o cabeçalho)
 *  - 5245 `get_my_binder_occupancy` (sob demanda, painel Informações)
 *  - 5245 `set_my_binder_identity`  (só a proprietária ativa)
 *  - 5246 `get_my_binder_participants`
 *
 * Antes de as funções existirem no banco (PGRST202/42883) a interface usa o
 * fallback: nome da coleção proprietária, logomarca exibida e edição
 * indisponível — o fichário continua funcionando igual.
 */

import { progressBarPercent, progressLabel, progressPercent, progressPercentText } from "./colecoes.ts";
import { isPokedexCollection } from "./pokedex.ts";

export const BINDER_NAME_MAX = 60;
/** Teto de entrada aceito pelo servidor antes de normalizar (5245 R3). */
export const BINDER_NAME_INPUT_MAX = 200;

export type BinderIdentity = {
  layoutId: string;
  role: "OWNER" | "GUEST";
  ownerCollectionId: string;
  ownerCollectionName: string;
  /** Nome gravado; `null` = sem nome próprio (usa o da coleção proprietária). */
  displayName: string | null;
  /** Nome exibido: gravado ou, na falta, o da coleção proprietária. */
  effectiveName: string;
  showBrandMark: boolean;
  /** Proprietária e coleção ativa. */
  canEdit: boolean;
};

/**
 * Identidade como a interface usa: a do banco, ou o fallback (função ainda
 * não aplicada / falha de leitura). `source` diz qual — o painel avisa.
 */
export type ResolvedIdentity = {
  name: string;
  displayName: string | null;
  showBrandMark: boolean;
  canEdit: boolean;
  source: "db" | "fallback";
};

export type BinderOccupancy = {
  columns: number;
  rows: number;
  pages: number;
  pockets: number;
  cards: number;
  images: number;
  merged: number;
  reservedEmpty: number;
  free: number;
  mergedRegions: number;
  mergedImages: number;
  participants: number;
};

export type BinderParticipant = {
  collectionId: string;
  name: string;
  role: "OWNER" | "GUEST";
  active: boolean;
  current: boolean;
  cards: number;
};

export type IdentityFailure = "invalid_name" | "owner_only" | "archived" | "not_found" | "lock_busy" | "not_authenticated" | "unavailable" | "invalid" | "unknown";

function int(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Quantos caracteres (pontos de código) — o mesmo que `char_length` no Postgres. */
export function nameLength(value: string): number {
  return Array.from(value).length;
}

/**
 * Normalização idêntica à do servidor (5245 R3): espaços internos colapsados
 * e pontas aparadas. Caractere de controle (quebra de linha, tab…) não é
 * "consertado": o nome é inválido. Vazio = volta ao nome da coleção.
 */
export function normalizeBinderName(raw: string): { ok: true; value: string | null } | { ok: false; reason: "control" | "too_long" } {
  if (nameLength(raw) > BINDER_NAME_INPUT_MAX) return { ok: false, reason: "too_long" };
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f-\u009f]/.test(raw)) return { ok: false, reason: "control" };
  const value = raw.replace(/\s+/g, " ").trim();
  if (value === "") return { ok: true, value: null };
  if (nameLength(value) > BINDER_NAME_MAX) return { ok: false, reason: "too_long" };
  return { ok: true, value };
}

export function parseBinderIdentity(data: unknown): BinderIdentity | null | "absent" {
  if (!Array.isArray(data)) return null;
  if (data.length === 0) return "absent";
  if (data.length !== 1) return null;
  const r = data[0] as Record<string, unknown> | null;
  if (!r || typeof r !== "object") return null;
  const layoutId = str(r.layout_id);
  const ownerId = str(r.owner_collection_id);
  const role = r.binder_role === "OWNER" || r.binder_role === "GUEST" ? r.binder_role : null;
  const effective = str(r.effective_name);
  if (!layoutId || !UUID.test(layoutId) || !ownerId || !role || !effective || typeof r.show_brand_mark !== "boolean") return null;
  return {
    layoutId,
    role,
    ownerCollectionId: ownerId,
    ownerCollectionName: str(r.owner_collection_name) ?? effective,
    displayName: str(r.display_name),
    effectiveName: effective,
    showBrandMark: r.show_brand_mark,
    canEdit: r.can_edit_identity === true,
  };
}

/** Resultado da gravação (5245): devolve o estado canônico já normalizado pelo banco. */
export function parseIdentityWrite(data: unknown): { displayName: string | null; effectiveName: string; showBrandMark: boolean; changed: boolean } | null {
  if (!Array.isArray(data) || data.length !== 1) return null;
  const r = data[0] as Record<string, unknown> | null;
  if (!r || typeof r !== "object") return null;
  const effective = str(r.effective_name);
  if (!effective || typeof r.show_brand_mark !== "boolean" || (r.operation !== "UPDATED" && r.operation !== "UNCHANGED")) return null;
  return { displayName: str(r.display_name), effectiveName: effective, showBrandMark: r.show_brand_mark, changed: r.operation === "UPDATED" };
}

export function parseBinderOccupancy(data: unknown): BinderOccupancy | null | "absent" {
  if (!Array.isArray(data)) return null;
  if (data.length === 0) return "absent";
  const r = data[0] as Record<string, unknown> | null;
  if (!r || typeof r !== "object") return null;
  const v = {
    columns: int(r.grid_columns),
    rows: int(r.grid_rows),
    pages: int(r.page_count),
    pockets: int(r.pocket_count),
    cards: int(r.card_pocket_count),
    images: int(r.image_pocket_count),
    merged: int(r.merged_pocket_count),
    reservedEmpty: int(r.reserved_empty_count),
    free: int(r.free_pocket_count),
    mergedRegions: int(r.merged_region_count),
    mergedImages: int(r.merged_image_count),
    participants: int(r.participant_count),
  };
  if (Object.values(v).some((x) => x === null)) return null;
  const o = v as BinderOccupancy;
  // Cada bolso conta uma vez: a soma tem de fechar (senão é dado incoerente, não "quase certo").
  if (o.cards + o.images + o.merged + o.reservedEmpty + o.free !== o.pockets) return null;
  return o;
}

export function parseBinderParticipants(data: unknown): BinderParticipant[] | null {
  if (!Array.isArray(data)) return null;
  const out: BinderParticipant[] = [];
  for (const row of data) {
    const r = row as Record<string, unknown> | null;
    if (!r || typeof r !== "object") return null;
    const id = str(r.collection_id);
    const name = typeof r.collection_name === "string" ? r.collection_name : null;
    const role = r.binder_role === "OWNER" || r.binder_role === "GUEST" ? r.binder_role : null;
    const cards = int(r.card_pocket_count);
    if (!id || name === null || !role || cards === null) return null;
    out.push({ collectionId: id, name, role, active: r.lifecycle_status === "ACTIVE", current: r.is_current === true, cards });
  }
  return out;
}

/**
 * Identidade efetiva para a interface. Sem leitura do banco: nome da coleção
 * proprietária (o da própria coleção, se ela é a proprietária), logomarca
 * exibida (padrão) e edição desligada.
 */
export function resolveIdentity(identity: BinderIdentity | null, fallback: { collectionName: string; ownerCollectionName: string | null }): ResolvedIdentity {
  if (identity) {
    return { name: identity.effectiveName, displayName: identity.displayName, showBrandMark: identity.showBrandMark, canEdit: identity.canEdit, source: "db" };
  }
  return { name: fallback.ownerCollectionName ?? fallback.collectionName, displayName: null, showBrandMark: true, canEdit: false, source: "fallback" };
}

export function classifyIdentityFailure(code: string | null | undefined, message: string | null | undefined): IdentityFailure {
  const text = (message ?? "").trim();
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (text === "INVALID_BINDER_NAME") return "invalid_name";
  if (text === "BINDER_OWNER_ONLY") return "owner_only";
  if (text === "COLLECTION_ARCHIVED") return "archived";
  if (code === "55P03") return "lock_busy";
  if (text === "COLLECTION_NOT_FOUND" || text === "BINDER_NOT_FOUND" || code === "P0002") return "not_found";
  if (code === "28000" || text === "not_authenticated") return "not_authenticated";
  if (code === "42501") return "owner_only";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}

export function identityFailureMessage(reason: IdentityFailure): string {
  switch (reason) {
    case "invalid_name":
      return "Use de 1 a 60 caracteres, sem quebras de linha.";
    case "owner_only":
      return "O nome e a contracapa são definidos pela coleção dona do fichário.";
    case "archived":
      return "A coleção está arquivada. Reative-a para editar o fichário.";
    case "not_found":
      return "Este fichário não está mais disponível. Recarregue a página.";
    case "lock_busy":
      return "O fichário está sendo alterado em outra aba. Tente de novo em instantes.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "unavailable":
      return "A identidade do fichário ainda não está disponível.";
    case "invalid":
      return "Não foi possível salvar com esses valores.";
    default:
      return "Não foi possível salvar agora. Nada foi alterado — tente de novo.";
  }
}

/** Percentual inteiro de ocupação (bolsos com carta, imagem ou mesclagem). Sem divisão por zero. */
export function occupancyPercent(o: Pick<BinderOccupancy, "pockets" | "cards" | "images" | "merged">): number {
  if (o.pockets <= 0) return 0;
  return Math.round(((o.cards + o.images + o.merged) / o.pockets) * 100);
}

/**
 * Progresso das coleções do fichário (P3A-BINDER-CONTROL-OWNER-PROGRESS-01 →
 * MULTI-COLLECTION-PROGRESS-01).
 *
 * Os números de cada coleção vêm prontos do resumo oficial dela (R1
 * `get_my_collections` → `collection_completion_summary`): posições do
 * objetivo satisfeitas sobre o total do objetivo, no critério da própria
 * coleção (Set, Master Set ou Pokédex). Uma posição conta uma vez, tenha uma
 * ou várias cópias; bolsos do fichário não entram e coleções diferentes nunca
 * se somam. Aqui só se formata e ordena — nenhuma contagem é refeita.
 */
export type BinderProgressInput = {
  name: string;
  completionPolicy: string;
  lifecycleStatus: string;
  totalPositions: number;
  satisfiedPositions: number;
  isComplete: boolean;
};

export type BinderProgressView =
  | {
      kind: "goal";
      name: string;
      archived: boolean;
      unit: "cartas" | "Pokémon";
      satisfied: number;
      total: number;
      percent: number;
      percentText: string;
      barPercent: number;
      label: string;
      complete: boolean;
    }
  | { kind: "free"; name: string; archived: boolean };

export function binderProgressView(input: BinderProgressInput): BinderProgressView {
  const archived = input.lifecycleStatus === "ARCHIVED";
  // Sem universo (Coleção livre): não há total previsto — nada de "0 de 0".
  if (!(input.totalPositions > 0)) return { kind: "free", name: input.name, archived };
  const total = input.totalPositions;
  const satisfied = Math.max(0, Math.min(input.satisfiedPositions, total));
  const unit = isPokedexCollection(input) ? "Pokémon" : "cartas";
  return {
    kind: "goal",
    name: input.name,
    archived,
    unit,
    satisfied,
    total,
    // Mesmo arredondamento da Biblioteca (piso; 100% só quando completa; "<1%").
    percent: progressPercent(satisfied, total),
    percentText: progressPercentText(satisfied, total),
    barPercent: progressBarPercent(satisfied, total),
    label: `${progressLabel(satisfied, total)} ${unit}`,
    complete: input.isComplete,
  };
}

/** Uma linha do bloco: `view: null` = progresso indisponível para esta sessão (nunca um valor inventado). */
export type BinderProgressEntry = {
  collectionId: string;
  name: string;
  role: "OWNER" | "GUEST";
  current: boolean;
  view: BinderProgressView | null;
};

const NAME_ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });

/**
 * Entradas do bloco a partir dos participantes já devolvidos por 5246 (que só
 * lista o que a sessão pode ver: a dona vê todas; uma convidada vê a dona e a
 * si mesma) e dos resumos oficiais por id. Dona sempre primeiro; convidadas
 * por nome (pt-BR, sem caixa/acento) e, no empate, por id — ordem estável.
 * Participante sem resumo correspondente fica `view: null`.
 */
export function buildBinderProgress(
  participants: readonly BinderParticipant[],
  progress: Readonly<Record<string, BinderProgressInput>>,
): BinderProgressEntry[] {
  const seen = new Set<string>();
  const entries: BinderProgressEntry[] = [];
  for (const p of participants) {
    const id = p.collectionId.toLowerCase();
    if (seen.has(id)) continue;
    seen.add(id);
    const input = Object.prototype.hasOwnProperty.call(progress, id) ? progress[id] : undefined;
    entries.push({
      collectionId: id,
      name: input?.name ?? p.name,
      role: p.role,
      current: p.current,
      view: input ? binderProgressView(input) : null,
    });
  }
  return entries.sort((a, b) => {
    if (a.role !== b.role) return a.role === "OWNER" ? -1 : 1;
    return NAME_ORDER.compare(a.name, b.name) || (a.collectionId < b.collectionId ? -1 : a.collectionId > b.collectionId ? 1 : 0);
  });
}

/** Preferências individuais do painel (navegador): aberto/fechado e seções recolhidas. */
export const CONTROL_PANEL_STORAGE_KEY = "mmkyu:binder-control:v1";
export const CONTROL_SECTIONS = ["identity", "organize", "info"] as const;
export type ControlSection = (typeof CONTROL_SECTIONS)[number];
export type ControlPanelPrefs = { open: boolean; collapsed: ControlSection[] };

export function parseControlPanelPrefs(raw: string | null): ControlPanelPrefs {
  const fallback: ControlPanelPrefs = { open: false, collapsed: [] };
  if (!raw) return fallback;
  try {
    const value = JSON.parse(raw) as unknown;
    if (!value || typeof value !== "object") return fallback;
    const v = value as Record<string, unknown>;
    const collapsed = Array.isArray(v.collapsed) ? v.collapsed.filter((s): s is ControlSection => CONTROL_SECTIONS.includes(s as ControlSection)) : [];
    return { open: v.open === true, collapsed: [...new Set(collapsed)] };
  } catch {
    return fallback;
  }
}
