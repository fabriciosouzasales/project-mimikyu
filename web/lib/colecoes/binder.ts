import type { BinderIdentity } from "./binder-identity.ts";
import type { SpeciesReference } from "./binder-species.ts";
import { formatCollectorNumber } from "./acervo.ts";

/**
 * Fichário Digital (P2-B) — regras puras: modelos, leitura das linhas das
 * RPCs, páginas e spreads, prévia e erros de domínio. Sem banco e sem React
 * (testável com `node --test`).
 *
 * Contratos LIVE, canônicos em `database/schema/`:
 *  - 5223 `get_my_collection_binder(collection)` — cabeçalho;
 *  - 5223 `get_my_collection_binder_pages(collection, primeira, quantidade ≤ 4)`;
 *  - 5224 `preview_my_collection_binder(collection, colunas, linhas, opção)` —
 *    prévia, não grava;
 *  - 5224 `create_my_collection_binder(..., plan_token)` — montagem atômica;
 *    `PLAN_CHANGED` quando a coleção mudou desde a prévia.
 *
 * Decisões aprovadas (C-191–C-194): sete modelos, descritos em colunas ×
 * linhas; criação só com coleção ativa e local padrão do tipo Fichário físico;
 * adicionais em categoria única; a escolha de adicionais não é persistida.
 */

// ---------------------------------------------------------------------------
// Modelos
// ---------------------------------------------------------------------------

export type BinderModel = { key: BinderModelKey; columns: number; rows: number; pockets: number };

export const BINDER_MODELS = [
  { key: "2x2", columns: 2, rows: 2, pockets: 4 },
  { key: "3x3", columns: 3, rows: 3, pockets: 9 },
  { key: "3x4", columns: 3, rows: 4, pockets: 12 },
  { key: "4x3", columns: 4, rows: 3, pockets: 12 },
  { key: "4x4", columns: 4, rows: 4, pockets: 16 },
  { key: "4x5", columns: 4, rows: 5, pockets: 20 },
  { key: "5x4", columns: 5, rows: 4, pockets: 20 },
] as const;

export type BinderModelKey = "2x2" | "3x3" | "3x4" | "4x3" | "4x4" | "4x5" | "5x4";

/** O fichário de 9 bolsos é o formato físico mais comum — ponto de partida da escolha. */
export const DEFAULT_MODEL_KEY: BinderModelKey = "3x3";

export function isBinderModelKey(value: unknown): value is BinderModelKey {
  return typeof value === "string" && BINDER_MODELS.some((model) => model.key === value);
}

export function modelByKey(key: BinderModelKey): BinderModel {
  return BINDER_MODELS.find((model) => model.key === key) ?? BINDER_MODELS[1];
}

/** `null` para grades fora dos sete (fichários antigos continuam legíveis). */
export function modelFor(columns: number, rows: number): BinderModel | null {
  return BINDER_MODELS.find((model) => model.columns === columns && model.rows === rows) ?? null;
}

/** "3 × 4" — sempre colunas × linhas. */
export function modelLabel(columns: number, rows: number): string {
  return `${columns} × ${rows}`;
}

// ---------------------------------------------------------------------------
// Cabeçalho (5223)
// ---------------------------------------------------------------------------

export type CollectionKind = "SET" | "MASTER_SET" | "POKEDEX" | "FREE" | "UNKNOWN";

export type BinderHeader = {
  collectionId: string;
  collectionName: string;
  kind: CollectionKind;
  active: boolean;
  hasBinder: boolean;
  layoutId: string | null;
  columns: number | null;
  rows: number | null;
  pageCount: number;
  slotCount: number;
  filledCount: number;
  reservedCount: number;
  reservedEmptyCount: number;
  canCreate: boolean;
  /** 5223 `is_editable`: fichário existe e a coleção está ativa (arquivada = só leitura). */
  editable: boolean;
  defaultStorageName: string | null;
  defaultStorageKind: string | null;
  /**
   * 5230 (fichário compartilhado, C-195–C-197): papel desta coleção no
   * fichário — `OWNER` (proprietária), `GUEST` (convidada) ou `null` (sem
   * fichário). `filledCount`/`reserved*` continuam do fichário inteiro.
   */
  role: BinderRole | null;
  ownerCollectionId: string | null;
  ownerCollectionName: string | null;
  /** 1 + convidadas (0 sem fichário). */
  participantCount: number;
  /** Bolsos com cartas DESTA coleção. */
  ownFilledCount: number;
  /** Cartas desta coleção ainda fora dos bolsos ("Cartas disponíveis"). */
  ownUnplacedCount: number;
  /** Fichários existentes que esta coleção pode usar (só quando ainda sem fichário). */
  joinCandidateCount: number;
  /**
   * 5252 (BINDER-PHYSICAL-LOCATION): exemplares guardados no fichário físico
   * e ainda sem bolso, de QUALQUER origem ("Cartas disponíveis" com "Todas").
   * Sem a 5252, cai para `ownUnplacedCount` (contrato antigo).
   */
  availableCount: number;
  /** 5252: nome do fichário físico que este fichário digital representa. */
  binderStorageName: string | null;
  /** 5252: id do fichário físico (5247) — o local onde o cadastro pelo fichário guarda as cartas. */
  binderStorageId: string | null;
  /**
   * P3-A (5245, leitura à parte): nome próprio e logomarca do fichário. Ausente
   * ou `null` = função ainda não aplicada / sem fichário → nome da coleção
   * proprietária e logomarca exibida (`resolveIdentity`).
   */
  identity?: BinderIdentity | null;
};

export type BinderRole = "OWNER" | "GUEST";

function int(value: unknown): number | null {
  const n = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  return typeof n === "number" && Number.isInteger(n) ? n : null;
}

function kindOf(value: unknown): CollectionKind {
  return value === "SET" || value === "MASTER_SET" || value === "POKEDEX" || value === "FREE" ? value : "UNKNOWN";
}

function str(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

/** Converte a linha da 5223 — `null` quando o formato não bate (nunca adivinha). */
export function parseBinderHeader(row: unknown): BinderHeader | null {
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  if (typeof r.collection_id !== "string" || typeof r.has_binder !== "boolean") return null;
  const hasBinder = r.has_binder;
  const columns = int(r.grid_columns);
  const rows = int(r.grid_rows);
  if (hasBinder && (columns === null || rows === null || columns < 1 || rows < 1)) return null;
  return {
    collectionId: r.collection_id,
    collectionName: typeof r.collection_name === "string" ? r.collection_name : "",
    kind: kindOf(r.collection_kind),
    active: r.lifecycle_status === "ACTIVE",
    hasBinder,
    layoutId: str(r.layout_id),
    columns: hasBinder ? columns : null,
    rows: hasBinder ? rows : null,
    pageCount: int(r.page_count) ?? 0,
    slotCount: int(r.slot_count) ?? 0,
    filledCount: int(r.filled_count) ?? 0,
    reservedCount: int(r.reserved_count) ?? 0,
    reservedEmptyCount: int(r.reserved_empty_count) ?? 0,
    canCreate: r.can_create === true,
    editable: r.is_editable === true,
    defaultStorageName: str(r.default_storage_name),
    defaultStorageKind: str(r.default_storage_kind_code),
    role: hasBinder && (r.binder_role === "OWNER" || r.binder_role === "GUEST") ? r.binder_role : null,
    ownerCollectionId: str(r.owner_collection_id),
    ownerCollectionName: str(r.owner_collection_name),
    participantCount: int(r.participant_count) ?? (hasBinder ? 1 : 0),
    ownFilledCount: int(r.own_filled_count) ?? 0,
    ownUnplacedCount: int(r.own_unplaced_count) ?? 0,
    joinCandidateCount: hasBinder ? 0 : (int(r.join_candidate_count) ?? 0),
    availableCount: int(r.available_count) ?? int(r.own_unplaced_count) ?? 0,
    binderStorageName: str(r.binder_storage_name),
    binderStorageId: str(r.binder_storage_container_id),
  };
}

/** Fichário usado por mais de uma coleção (proprietária + convidadas). */
export function isSharedBinder(header: Pick<BinderHeader, "hasBinder" | "participantCount">): boolean {
  return header.hasBinder && header.participantCount > 1;
}

/**
 * Sem fichário próprio, mas já existe um fichário digital no mesmo local
 * físico (5230 `join_candidate_count`): a entrada oferece primeiro "Usar o
 * fichário existente" — nunca induz a montar outro.
 */
export function canJoinExistingBinder(header: Pick<BinderHeader, "hasBinder" | "active" | "joinCandidateCount">): boolean {
  return !header.hasBinder && header.active && header.joinCandidateCount > 0;
}

/**
 * Por que a montagem não está disponível (só quando `canCreate` é falso e
 * ainda não há fichário). A 5224 revalida tudo no servidor; isto só explica.
 */
export type CreateBlocker = "archived" | "no_default_storage" | "storage_not_binder" | "unsupported";

/**
 * O Fichário Digital espelha um fichário físico: só faz sentido oferecê-lo
 * quando a coleção já tem fichário digital ou está guardada (local padrão)
 * num local do tipo Fichário. Coleções em caixa, sem local padrão etc. não
 * exibem a entrada. `null` (leitura indisponível) não esconde nada.
 */
export function binderEntryVisible(header: BinderHeader | null): boolean {
  if (header === null) return true;
  return header.hasBinder || header.defaultStorageKind === "BINDER";
}

export function createBlocker(header: BinderHeader): CreateBlocker | null {
  if (header.hasBinder || header.canCreate) return null;
  if (!header.active) return "archived";
  if (header.kind === "UNKNOWN") return "unsupported";
  if (header.defaultStorageKind === null) return "no_default_storage";
  return "storage_not_binder";
}

export function createBlockerMessage(blocker: CreateBlocker, storageName: string | null): { title: string; body: string } {
  switch (blocker) {
    case "archived":
      return {
        title: "Coleção arquivada",
        body: "Coleções arquivadas podem ser consultadas, mas não recebem um fichário novo. Reative a coleção para montar.",
      };
    case "no_default_storage":
      return {
        title: "Defina onde esta coleção fica guardada",
        body: "O fichário digital espelha um fichário físico. Em Ajustes → Onde guardo, escolha como local padrão um local do tipo Fichário.",
      };
    case "storage_not_binder":
      return {
        title: "O local padrão não é um fichário",
        body: `${storageName ? `“${storageName}”` : "O local padrão desta coleção"} não é do tipo Fichário. Em Ajustes → Onde guardo, escolha um local do tipo Fichário para montar.`,
      };
    default:
      return {
        title: "Montagem indisponível para esta coleção",
        body: "Este tipo de coleção ainda não tem montagem automática.",
      };
  }
}

// ---------------------------------------------------------------------------
// Páginas e bolsos (5223)
// ---------------------------------------------------------------------------

export type SlotState = "EMPTY" | "RESERVED_EMPTY" | "OCCUPIED_UNPLANNED" | "OCCUPIED_MATCH" | "OCCUPIED_MISMATCH";

const SLOT_STATES = new Set<string>(["EMPTY", "RESERVED_EMPTY", "OCCUPIED_UNPLANNED", "OCCUPIED_MATCH", "OCCUPIED_MISMATCH"]);

export type BinderCardFace = {
  cardName: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  setCode: string | null;
  imagePath: string | null;
  finishCode: string | null;
  finishName: string | null;
};

export type BinderSlot = {
  slotId: string;
  row: number;
  column: number;
  locked: boolean;
  state: SlotState;
  /** Carta reservada (reserva por carta, carta + acabamento ou variante). */
  expected: BinderCardFace | null;
  /** Exemplar no bolso. */
  present: (BinderCardFace & { languageCode: string | null; variantLabel: string | null }) | null;
  /** Identidades usadas pelas ferramentas de organização (nunca exibidas). */
  assignmentId: string | null;
  allocationId: string | null;
  /** 5248: exemplar no bolso — identidade da posição (alocação pode ser nula: carta sem coleção). */
  physicalCardId?: string | null;
  expectedCardId: string | null;
  presentCardId: string | null;
  presentVariantTypeId: string | null;
  /** 5230: coleção da carta no bolso e coleção dona da reserva (fichário compartilhado). */
  presentCollectionId: string | null;
  expectedCollectionId: string | null;
  /**
   * 5234 (C-198): imagem personalizada do bolso. A 5230 continua devolvendo
   * esse bolso como EMPTY; a leitura de imagens é sobreposta depois
   * (`attachSlotImages`). Ausente/`null` = sem imagem.
   */
  image?: SlotImage | null;
  /**
   * 5223/5230: mesclagem (Layout Region) que cobre o bolso. Na primeira versão
   * (5238–5243) só existe como "imagem em 2 bolsos": o bolso não recebe carta,
   * reserva nem fixação. Ausente/`null` = bolso independente.
   */
  regionId?: string | null;
  /**
   * POKEDEX-BINDER-SPECIES-REFERENCE (5259): espécie de referência do bolso
   * (rótulo visual, nunca carta/reserva/progresso). Sobreposta depois da
   * leitura dos bolsos (`attachSpeciesReferences`). Ausente/`null` = sem referência.
   */
  speciesRef?: SpeciesReference | null;
};

/**
 * Imagem personalizada de um bolso (C-198): elemento visual do fichário,
 * nunca um exemplar — não conta em inventário, progresso nem valor.
 * `url` é assinada (1 h, bucket privado) ou uma prévia local (`blob:`).
 */
export type SlotImage = {
  path: string;
  /** Enquadramento vertical, 0 (topo) a 100 (base). */
  focalY: number;
  updatedAt: string | null;
  url: string | null;
};

/** O bolso exibe uma imagem personalizada (exclusiva com carta e reserva). */
export function hasSlotImage(slot: Pick<BinderSlot, "image">): boolean {
  return Boolean(slot.image);
}

export type BinderPage = {
  pageNumber: number;
  pageId: string;
  slots: BinderSlot[];
  /** 5241: mesclagens com imagem da página (sobrepostas depois da leitura dos bolsos). */
  regions?: RegionImage[];
};

/**
 * Imagem decorativa única de uma mesclagem (5239–5241): cobre os bolsos do
 * retângulo (primeira versão: 1 linha × 2 colunas). Elemento visual — não
 * conta em inventário, progresso nem valor.
 */
export type RegionImage = {
  regionId: string;
  row: number;
  leftColumn: number;
  height: number;
  width: number;
  path: string;
  focalX: number;
  focalY: number;
  updatedAt: string | null;
  url: string | null;
};

/** Agrupa as linhas da 5223 por página, na ordem página → linha → coluna. */
export function parseBinderPages(rows: unknown): BinderPage[] | null {
  if (!Array.isArray(rows)) return null;
  const pages = new Map<number, BinderPage>();
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const pageNumber = int(r.page_number);
    const row = int(r.row_index);
    const column = int(r.column_index);
    if (
      pageNumber === null ||
      row === null ||
      column === null ||
      typeof r.page_id !== "string" ||
      typeof r.slot_id !== "string" ||
      typeof r.slot_state !== "string" ||
      !SLOT_STATES.has(r.slot_state)
    ) {
      return null;
    }
    const expectedName = str(r.expected_card_name);
    const presentName = str(r.present_card_name);
    const slot: BinderSlot = {
      slotId: r.slot_id,
      row,
      column,
      locked: r.locked === true,
      state: r.slot_state as SlotState,
      expected:
        r.expected_card_id && expectedName
          ? {
              cardName: expectedName,
              collectorNumber: str(r.expected_collector_number),
              collectorTotal: int(r.expected_collector_total),
              setCode: str(r.expected_card_set_code),
              imagePath: str(r.expected_image_path),
              finishCode: str(r.expected_variant_type_code),
              finishName: str(r.expected_variant_type_name),
            }
          : null,
      present:
        r.physical_card_id && presentName
          ? {
              cardName: presentName,
              collectorNumber: str(r.present_collector_number),
              collectorTotal: int(r.present_collector_total),
              setCode: str(r.present_card_set_code),
              imagePath: str(r.present_image_path),
              finishCode: str(r.present_variant_type_code),
              finishName: null,
              languageCode: str(r.present_language_code),
              variantLabel: str(r.present_variant_label),
            }
          : null,
      assignmentId: str(r.assignment_id),
      allocationId: str(r.collection_allocation_id),
      physicalCardId: str(r.physical_card_id),
      expectedCardId: str(r.expected_card_id),
      presentCardId: str(r.present_card_id),
      presentVariantTypeId: str(r.present_variant_type_id),
      presentCollectionId: str(r.present_collection_id),
      expectedCollectionId: str(r.expected_collection_id),
      regionId: str(r.region_id),
    };
    let page = pages.get(pageNumber);
    if (!page) {
      page = { pageNumber, pageId: r.page_id, slots: [] };
      pages.set(pageNumber, page);
    }
    page.slots.push(slot);
  }
  const ordered = [...pages.values()].sort((a, b) => a.pageNumber - b.pageNumber);
  for (const page of ordered) page.slots.sort((a, b) => a.row - b.row || a.column - b.column);
  return ordered;
}

/** Quantas páginas a 5223 devolve por chamada (teto do contrato). */
export const PAGES_PER_READ = 4;

/** Primeira página do lote de leitura que contém `page` (lotes alinhados: 1, 5, 9…). */
export function readBatchStart(page: number): number {
  return Math.floor((Math.max(1, page) - 1) / PAGES_PER_READ) * PAGES_PER_READ + 1;
}

/**
 * Primeira página do spread que contém `page`. Com duas páginas por vista,
 * os spreads são (1–2), (3–4)…; com uma, cada página é a sua vista. Os lotes
 * de 4 contêm spreads inteiros.
 */
export function spreadStart(page: number, perView: 1 | 2): number {
  const p = Math.max(1, Math.floor(page));
  return perView === 2 ? p - ((p - 1) % 2) : p;
}

export function spreadPages(start: number, perView: 1 | 2, total: number): number[] {
  const pages: number[] = [];
  for (let page = start; page < start + perView && page <= total; page += 1) pages.push(page);
  return pages;
}

export function clampPage(page: number, total: number): number {
  if (!Number.isFinite(page) || total < 1) return 1;
  return Math.min(Math.max(1, Math.floor(page)), total);
}

/** `?pagina=` da URL → página válida (1 quando ausente ou inválida). */
export function parsePageParam(value: unknown, total: number): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const n = typeof raw === "string" && /^\d{1,6}$/.test(raw) ? Number(raw) : 1;
  return clampPage(n, total);
}

/** "Páginas 3–4 de 12" / "Página 5 de 12". */
export function spreadLabel(pages: number[], total: number): string {
  if (pages.length === 0) return `de ${total}`;
  if (pages.length === 1) return `Página ${pages[0]} de ${total}`;
  return `Páginas ${pages[0]}–${pages[pages.length - 1]} de ${total}`;
}

/** Texto acessível de um bolso — o que um leitor de tela ouve. */
export function slotDescription(slot: BinderSlot): string {
  const where = `Linha ${slot.row}, coluna ${slot.column}`;
  const face = (f: BinderCardFace) =>
    [f.cardName, f.collectorNumber ? formatCollectorNumber(f.collectorNumber, f.collectorTotal) : null, f.finishName ?? f.finishCode]
      .filter(Boolean)
      .join(", ");
  switch (slot.state) {
    case "EMPTY":
      return slot.image ? `${where}: imagem personalizada` : `${where}: bolso vazio`;
    case "RESERVED_EMPTY":
      return `${where}: reservado para ${slot.expected ? face(slot.expected) : "uma carta"}`;
    case "OCCUPIED_MISMATCH":
      return `${where}: ${slot.present ? face(slot.present) : "carta"} — diferente da reserva${slot.expected ? ` (${face(slot.expected)})` : ""}`;
    default:
      return `${where}: ${slot.present ? face(slot.present) : "carta"}`;
  }
}

// ---------------------------------------------------------------------------
// Prévia (5224)
// ---------------------------------------------------------------------------

export type ExtraPolicy = "PRINCIPAL_ONLY" | "APPEND_PAGES";

export function isExtraPolicy(value: unknown): value is ExtraPolicy {
  return value === "PRINCIPAL_ONLY" || value === "APPEND_PAGES";
}

export const BINDER_PLAN_TOKEN = /^v1:[0-9a-f]{64}$/;

export type PreviewSampleSlot = {
  row: number;
  column: number;
  state: "ASSIGNED" | "EXTRA" | "RESERVED";
  cardName: string | null;
  collectorNumber: string | null;
  finishCode: string | null;
  imagePath: string | null;
};

export type BinderPreview = {
  kind: CollectionKind;
  active: boolean;
  binderExists: boolean;
  eligible: boolean;
  columns: number;
  rows: number;
  extraPolicy: ExtraPolicy;
  tooLarge: boolean;
  maxAllocations: number;
  allocationsTotal: number;
  /** Os campos abaixo são `null` quando não há plano (fichário existe, grande demais, tipo desconhecido). */
  positionsTotal: number | null;
  positionsOwned: number | null;
  positionsReserved: number | null;
  extrasTotal: number | null;
  extrasIdentical: number | null;
  extrasOtherLanguage: number | null;
  extrasOtherVariant: number | null;
  extrasOutOfObjective: number | null;
  extrasPlaced: number | null;
  extrasUnplaced: number | null;
  pagesTotal: number | null;
  slotsTotal: number | null;
  slotsEmptyTrailing: number | null;
  sample: PreviewSampleSlot[];
  planToken: string | null;
};

function parseSample(value: unknown): PreviewSampleSlot[] {
  if (!Array.isArray(value)) return [];
  const out: PreviewSampleSlot[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const row = int(r.row);
    const column = int(r.column);
    const state = r.state === "ASSIGNED" || r.state === "EXTRA" || r.state === "RESERVED" ? r.state : null;
    if (row === null || column === null || state === null) continue;
    out.push({
      row,
      column,
      state,
      cardName: str(r.card_name),
      collectorNumber: str(r.collector_number),
      finishCode: str(r.variant_type_code),
      imagePath: str(r.image_path),
    });
  }
  return out;
}

export function parseBinderPreview(row: unknown): BinderPreview | null {
  if (!row || typeof row !== "object") return null;
  const r = row as Record<string, unknown>;
  const columns = int(r.grid_columns);
  const rows = int(r.grid_rows);
  const maxAllocations = int(r.max_allocations);
  const allocationsTotal = int(r.allocations_total);
  if (
    columns === null ||
    rows === null ||
    maxAllocations === null ||
    allocationsTotal === null ||
    typeof r.binder_exists !== "boolean" ||
    typeof r.eligible !== "boolean" ||
    typeof r.too_large !== "boolean" ||
    !isExtraPolicy(r.extra_policy)
  ) {
    return null;
  }
  const token = typeof r.plan_token === "string" && BINDER_PLAN_TOKEN.test(r.plan_token) ? r.plan_token : null;
  return {
    kind: kindOf(r.collection_kind),
    active: r.lifecycle_active === true,
    binderExists: r.binder_exists,
    eligible: r.eligible,
    columns,
    rows,
    extraPolicy: r.extra_policy,
    tooLarge: r.too_large,
    maxAllocations,
    allocationsTotal,
    positionsTotal: int(r.positions_total),
    positionsOwned: int(r.positions_owned),
    positionsReserved: int(r.positions_reserved),
    extrasTotal: int(r.extras_total),
    extrasIdentical: int(r.extras_identical),
    extrasOtherLanguage: int(r.extras_other_language),
    extrasOtherVariant: int(r.extras_other_variant),
    extrasOutOfObjective: int(r.extras_out_of_objective),
    extrasPlaced: int(r.extras_placed),
    extrasUnplaced: int(r.extras_unplaced),
    pagesTotal: int(r.pages_total),
    slotsTotal: int(r.slots_total),
    slotsEmptyTrailing: int(r.slots_empty_trailing),
    sample: parseSample(r.sample),
    planToken: token,
  };
}

/**
 * O que a prévia permite fazer, em ordem de precedência. Só `ready` libera o
 * botão de montar (e sempre com o `plan_token` desta prévia).
 */
export type PreviewVerdict = "exists" | "archived" | "not_eligible" | "too_large" | "unsupported" | "ready";

export function previewVerdict(preview: BinderPreview): PreviewVerdict {
  if (preview.binderExists) return "exists";
  if (!preview.active) return "archived";
  if (preview.tooLarge) return "too_large";
  if (preview.kind === "UNKNOWN") return "unsupported";
  if (!preview.eligible) return "not_eligible";
  if (preview.planToken === null || preview.pagesTotal === null) return "unsupported";
  return "ready";
}

export type ExtraBreakdownItem = { key: string; label: string; count: number };

/** Adicionais por categoria — só as que existem, na ordem da regra (C-193). */
export function extrasBreakdown(preview: BinderPreview): ExtraBreakdownItem[] {
  const items: ExtraBreakdownItem[] = [
    { key: "out", label: "fora do objetivo", count: preview.extrasOutOfObjective ?? 0 },
    { key: "identical", label: preview.extrasIdentical === 1 ? "cópia idêntica" : "cópias idênticas", count: preview.extrasIdentical ?? 0 },
    { key: "language", label: "em outro idioma", count: preview.extrasOtherLanguage ?? 0 },
    { key: "variant", label: preview.extrasOtherVariant === 1 ? "outra variante" : "outras variantes", count: preview.extrasOtherVariant ?? 0 },
  ];
  return items.filter((item) => item.count > 0);
}

export function positionNoun(kind: CollectionKind, count: number): string {
  if (kind === "FREE") return count === 1 ? "carta" : "cartas";
  return count === 1 ? "posição" : "posições";
}

// ---------------------------------------------------------------------------
// Erros de domínio (5223/5224)
// ---------------------------------------------------------------------------

export type BinderFailure =
  | "plan_changed"
  | "already_exists"
  | "not_eligible"
  | "archived"
  | "too_large"
  | "invalid_grid"
  | "lock_busy"
  | "not_found"
  | "not_authenticated"
  | "invalid"
  | "unknown";

export function classifyBinderFailure(code: string | null | undefined, message: string | null | undefined): BinderFailure {
  const text = (message ?? "").trim();
  if (text === "PLAN_CHANGED") return "plan_changed";
  if (text === "LAYOUT_ALREADY_EXISTS") return "already_exists";
  if (text === "NOT_ELIGIBLE") return "not_eligible";
  if (text === "COLLECTION_ARCHIVED") return "archived";
  if (code === "54000" || text === "COLLECTION_TOO_LARGE") return "too_large";
  if (text === "INVALID_GRID") return "invalid_grid";
  if (code === "55P03") return "lock_busy";
  if (code === "P0002" || text === "COLLECTION_NOT_FOUND") return "not_found";
  if (code === "28000" || code === "42501" || text === "not_authenticated") return "not_authenticated";
  if (code === "22023") return "invalid";
  return "unknown";
}

/** Mensagem para o colecionador: o que aconteceu e o que fazer. */
export function binderFailureMessage(reason: BinderFailure): string {
  switch (reason) {
    case "plan_changed":
      return "Sua coleção mudou desde a prévia. Revise os números atualizados e confirme de novo — nada foi montado.";
    case "already_exists":
      return "Esta coleção já tem um fichário. Abrindo o fichário existente.";
    case "not_eligible":
      return "O local padrão desta coleção deixou de ser um Fichário. Ajuste em Ajustes → Onde guardo e tente de novo.";
    case "archived":
      return "A coleção foi arquivada. Reative-a para montar o fichário.";
    case "too_large":
      return "Esta coleção é grande demais para montar de uma vez por enquanto. Nada foi alterado.";
    case "invalid_grid":
      return "Escolha um dos sete modelos de fichário.";
    case "lock_busy":
      return "A coleção está sendo atualizada em outra tela. Aguarde alguns segundos e tente de novo.";
    case "not_found":
      return "Não encontramos esta coleção na sua conta.";
    case "not_authenticated":
      return "Sua sessão terminou. Entre de novo para continuar.";
    case "invalid":
      return "Não foi possível entender o pedido. Recarregue a página e tente de novo.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente de novo em instantes.";
  }
}

/** Depois de cada falha: refazer a prévia (nunca repetir a escrita às cegas), abrir o fichário ou só explicar. */
export function recoveryForBinder(reason: BinderFailure): "refresh_preview" | "open_binder" | "retry_allowed" | "stop" {
  switch (reason) {
    case "plan_changed":
    case "too_large":
    case "unknown":
      return "refresh_preview";
    case "already_exists":
      return "open_binder";
    case "lock_busy":
      return "retry_allowed";
    default:
      return "stop";
  }
}

/** Rota do Fichário Digital de uma coleção (com a página quando não é a primeira). */
export function binderHref(collectionId: string, page?: number): string {
  const base = `/colecoes/colecoes/${collectionId}/fichario`;
  return page && page > 1 ? `${base}?pagina=${page}` : base;
}

// ---------------------------------------------------------------------------
// Área de trabalho: encaixe do fichário na tela (P2-B-UX-CORRECTION-01)
// ---------------------------------------------------------------------------

/** Proporção real da frente das cartas (CARD-ASPECT-01: 600 × 825 = 8 : 11). */
export const CARD_ASPECT = 11 / 8;

/**
 * Medidas do fichário em unidades da largura do bolso (w). O CSS deriva tudo
 * de `--pocket`, então mudar aqui muda o desenho inteiro de forma coerente.
 */
export const BINDER_UNITS = {
  gap: 0.05, // entre bolsos
  pagePad: 0.07, // margem interna da folha
  spine: 0.22, // lombada entre as duas folhas
  pad: 0.1, // couro e zíper em volta (spike binder-nav-01)
} as const;

/**
 * Respiro entre a grade de bolsos e o couro (P2-B-BINDER-MARGIN-01): somado à
 * margem interna da folha só no alto, embaixo e nas laterais EXTERNAS (a
 * lombada e o espaço entre cartas não mudam). Proporcional ao bolso, com piso
 * e teto em px — telas pequenas e grades densas recebem menos, um 3 × 3 em
 * desktop chega ao teto.
 */
export const BINDER_MARGIN = {
  x: { unit: 0.12, min: 8, max: 16 },
  y: { unit: 0.11, min: 6, max: 14 },
} as const;

export function binderMargins(pocket: number): { x: number; y: number } {
  const m = BINDER_MARGIN;
  const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
  if (!(pocket > 0)) return { x: 0, y: 0 };
  return { x: Math.round(clamp(pocket * m.x.unit, m.x.min, m.x.max)), y: Math.round(clamp(pocket * m.y.unit, m.y.min, m.y.max)) };
}

export type BinderFit = {
  perView: 1 | 2;
  pocket: number;
  width: number;
  height: number;
  /** Respiro extra (px) por lado: laterais externas e alto/embaixo de cada folha. */
  marginX: number;
  marginY: number;
};

function binderUnits(perView: 1 | 2, columns: number, rows: number): { kw: number; kh: number } {
  const u = BINDER_UNITS;
  return {
    kw: perView * (columns + (columns - 1) * u.gap + 2 * u.pagePad) + (perView - 1) * u.spine + 2 * u.pad,
    kh: rows * CARD_ASPECT + (rows - 1) * u.gap + 2 * u.pagePad + 2 * u.pad,
  };
}

/**
 * Bolso que cabe descontando o respiro. O respiro depende do bolso: calcula
 * sem ele, desconta o respiro desse bolso (o maior possível) e recalcula — o
 * resultado sempre cabe, porque o bolso final tem respiro menor ou igual.
 */
function pocketFor(perView: 1 | 2, columns: number, rows: number, width: number, height: number): number {
  const { kw, kh } = binderUnits(perView, columns, rows);
  const raw = Math.max(0, Math.min(width / kw, height / kh));
  const m = binderMargins(Math.min(raw, MAX_POCKET));
  return Math.max(0, Math.min((width - 2 * m.x) / kw, (height - 2 * m.y) / kh));
}

/** Bolso mínimo legível para mostrar duas páginas lado a lado. */
export const MIN_SPREAD_POCKET = 64;
/** Teto do bolso: num 2 × 2 em tela grande a carta não precisa passar disso. */
export const MAX_POCKET = 280;

/**
 * Maior fichário que cabe inteiro na área disponível (largura × altura), sem
 * rolagem, preservando a proporção das cartas e a grade do modelo. Duas
 * páginas quando permitido e o bolso continua legível; senão, uma.
 */
export function computeBinderFit(width: number, height: number, columns: number, rows: number, allowSpread: boolean): BinderFit {
  const w = Number.isFinite(width) ? Math.max(0, width) : 0;
  const h = Number.isFinite(height) ? Math.max(0, height) : 0;
  const c = Math.max(1, Math.floor(columns));
  const r = Math.max(1, Math.floor(rows));
  const perView: 1 | 2 = allowSpread && pocketFor(2, c, r, w, h) >= MIN_SPREAD_POCKET ? 2 : 1;
  const pocket = Math.floor(Math.min(pocketFor(perView, c, r, w, h), MAX_POCKET));
  const { kw, kh } = binderUnits(perView, c, r);
  const m = binderMargins(pocket);
  return {
    perView,
    pocket,
    width: Math.floor(pocket * kw) + 2 * m.x,
    height: Math.floor(pocket * kh) + 2 * m.y,
    marginX: m.x,
    marginY: m.y,
  };
}

// ---------------------------------------------------------------------------
// Organização: bolsos (contratos Binder Foundation 5128–5133)
// ---------------------------------------------------------------------------

export function isOccupied(slot: Pick<BinderSlot, "state">): boolean {
  return slot.state === "OCCUPIED_MATCH" || slot.state === "OCCUPIED_UNPLANNED" || slot.state === "OCCUPIED_MISMATCH";
}

/** Reservar o bolso para a carta que já está nele (fixa o lugar dela no plano). */
export function canReserveCurrent(slot: BinderSlot): boolean {
  return isOccupied(slot) && slot.presentCardId !== null && slot.state !== "OCCUPIED_MATCH";
}

export function hasReservation(slot: Pick<BinderSlot, "expectedCardId">): boolean {
  return slot.expectedCardId !== null;
}

export type SlotFailure =
  | "locked"
  | "source_empty"
  | "noop"
  | "archived"
  | "stale"
  | "already_placed"
  | "too_many"
  | "has_image"
  | "not_in_location"
  | "lock_busy"
  | "not_authenticated"
  | "invalid"
  | "unknown";

/** Lote máximo das RPCs de bolso (5129/5130/5133). */
export const SLOT_BATCH_MAX = 500;

/** Mensagens das RPCs 5128–5133 (P0001 com texto) → motivo estável. */
export function classifySlotFailure(code: string | null | undefined, message: string | null | undefined): SlotFailure {
  const text = (message ?? "").toLowerCase();
  if (code === "55P03") return "lock_busy";
  if (code === "28000" || text.includes("authentication required")) return "not_authenticated";
  if (text.includes("slot_has_image")) return "has_image";
  // 5250 (posicionar pelo exemplar): mensagens = códigos.
  if (text === "card_not_in_binder_location") return "not_in_location";
  if (text === "card_already_placed") return "already_placed";
  if (text === "slot_locked") return "locked";
  if (text === "physical_card_not_found" || text === "slot_not_found" || text === "binder_not_found" || text === "collection_not_found") return "stale";
  if (text.includes("(locked)")) return "locked";
  if (text.includes("origem está vazio")) return "source_empty";
  if (text.startsWith("no-op")) return "noop";
  if (text.includes("archived")) return "archived";
  if (text.includes("not found or not owned")) return "stale";
  if (text.includes("já possui slot assignment")) return "already_placed";
  if (text.includes("excede o limite")) return "too_many";
  if (code === "22023" || code === "22P02" || text.includes("layouts diferentes") || text.includes("mesmo layout") || text.includes("não pode ser")) {
    return "invalid";
  }
  return "unknown";
}

export function slotFailureMessage(reason: SlotFailure): string {
  switch (reason) {
    case "locked":
      return "Um dos bolsos está fixado. Solte o cadeado para mexer nele.";
    case "source_empty":
      return "Essa carta já não está mais naquele bolso. Atualizamos a página.";
    case "noop":
      return "A carta já está nesse bolso.";
    case "archived":
      return "A coleção está arquivada. Reative-a para organizar o fichário.";
    case "stale":
      return "O fichário mudou em outra tela. Atualizamos a página para você continuar.";
    case "already_placed":
      return "Essa carta já tem lugar no fichário.";
    case "too_many":
      return `Selecione até ${SLOT_BATCH_MAX} bolsos por vez.`;
    case "has_image":
      return "Esse bolso tem uma imagem. Remova a imagem para colocar uma carta ou fixá-lo.";
    case "not_in_location":
      return "Essa carta não está guardada neste fichário. Mude o local dela no Meu acervo para colocá-la num bolso.";
    case "lock_busy":
      return "O fichário está sendo atualizado em outra tela. Tente de novo em alguns segundos.";
    case "not_authenticated":
      return "Sua sessão terminou. Entre de novo para continuar.";
    case "invalid":
      return "Não foi possível entender o pedido. Recarregue a página e tente de novo.";
    default:
      return "Não foi possível concluir agora. Nada foi alterado — tente de novo em instantes.";
  }
}

/** Depois de uma falha, a página precisa ser relida (o estado local pode estar velho)? */
export function slotFailureNeedsReload(reason: SlotFailure): boolean {
  return (
    reason === "source_empty" ||
    reason === "stale" ||
    reason === "already_placed" ||
    reason === "unknown" ||
    reason === "locked" ||
    reason === "has_image" ||
    reason === "not_in_location"
  );
}

// ---------------------------------------------------------------------------
// Vistas do fichário: capa fechada, contracapa e spreads (spike binder-nav-01)
// ---------------------------------------------------------------------------

/**
 * Como num fichário físico (aprovado no spike binder-nav-01, Rodada 2): a
 * vista 0 é a capa fechada; ao abrir, a contracapa interna fica ao lado da
 * página 1; depois vêm os pares (2–3), (4–5)… e, se a última página cair à
 * esquerda, a contracapa traseira fecha o par. Com uma página por vista
 * (celular), a capa e depois cada página.
 */
export type ViewSide = number | "inner";

export function viewCount(perView: 1 | 2, total: number): number {
  const t = Math.max(0, Math.floor(total));
  if (t === 0) return 1;
  return perView === 1 ? 1 + t : 2 + Math.ceil((t - 1) / 2);
}

/** Vista que mostra a página (1…total). Página 0 = capa. */
export function viewForPage(page: number, perView: 1 | 2): number {
  const p = Math.max(0, Math.floor(page));
  if (p === 0) return 0;
  if (perView === 1) return p;
  return p === 1 ? 1 : Math.floor(p / 2) + 1;
}

/** Primeira página de uma vista (0 para a capa) — âncora que sobrevive à troca 1↔2 páginas. */
export function firstPageOfView(view: number, perView: 1 | 2): number {
  const v = Math.max(0, Math.floor(view));
  if (v === 0) return 0;
  if (perView === 1) return v;
  return v === 1 ? 1 : 2 * v - 2;
}

/** O que aparece em cada lado de uma vista aberta (vista ≥ 1). */
export function viewSides(view: number, perView: 1 | 2, total: number): ViewSide[] {
  const v = Math.max(1, Math.floor(view));
  if (perView === 1) return v <= total ? [v] : [];
  if (v === 1) return total >= 1 ? ["inner", 1] : [];
  const left = 2 * v - 2;
  if (left > total) return [];
  return [left, left + 1 <= total ? left + 1 : "inner"];
}

/** "Capa" / "Página 1 de 12" / "Páginas 2–3 de 12". */
export function viewLabel(view: number, perView: 1 | 2, total: number): string {
  if (view <= 0) return "Capa";
  const pages = viewSides(view, perView, total).filter((side): side is number => typeof side === "number");
  return spreadLabel(pages, total);
}

// ---------------------------------------------------------------------------
// Mudança otimista do conteúdo de um bolso (a tela relê o lote logo depois)
// ---------------------------------------------------------------------------

type SlotContent = Pick<BinderSlot, "present" | "assignmentId" | "allocationId" | "physicalCardId" | "presentCardId" | "presentVariantTypeId" | "presentCollectionId">;

function contentOf(slot: BinderSlot): SlotContent {
  return {
    present: slot.present,
    assignmentId: slot.assignmentId,
    allocationId: slot.allocationId,
    physicalCardId: slot.physicalCardId ?? null,
    presentCardId: slot.presentCardId,
    presentVariantTypeId: slot.presentVariantTypeId,
    presentCollectionId: slot.presentCollectionId,
  };
}

const EMPTY_CONTENT: SlotContent = {
  present: null,
  assignmentId: null,
  allocationId: null,
  physicalCardId: null,
  presentCardId: null,
  presentVariantTypeId: null,
  presentCollectionId: null,
};

/**
 * Estado provável depois da mudança. Aproximação local (carta igual = casa
 * com a reserva); a granularidade exata (acabamento/variante) vem da releitura
 * da 5223 logo em seguida.
 */
export function deriveSlotState(slot: Pick<BinderSlot, "present" | "presentCardId" | "expectedCardId">): SlotState {
  if (slot.present) {
    if (!slot.expectedCardId) return "OCCUPIED_UNPLANNED";
    return slot.presentCardId === slot.expectedCardId ? "OCCUPIED_MATCH" : "OCCUPIED_MISMATCH";
  }
  return slot.expectedCardId ? "RESERVED_EMPTY" : "EMPTY";
}

function withContent(slot: BinderSlot, content: SlotContent): BinderSlot {
  const next = { ...slot, ...content };
  return { ...next, state: deriveSlotState(next) };
}

/** Mover (destino vazio) ou trocar (destino ocupado) — espelho local da 5132. */
export function applyMove(from: BinderSlot, to: BinderSlot): [BinderSlot, BinderSlot] {
  return [withContent(from, contentOf(to)), withContent(to, contentOf(from))];
}

export function applyRemove(slot: BinderSlot): BinderSlot {
  return withContent(slot, EMPTY_CONTENT);
}

export function applyLock(slot: BinderSlot, locked: boolean): BinderSlot {
  return { ...slot, locked };
}

/** Reserva para a carta presente (carta + acabamento, como a montagem). */
export function applyReserveCurrent(slot: BinderSlot): BinderSlot {
  if (!slot.present || !slot.presentCardId) return slot;
  const next: BinderSlot = {
    ...slot,
    expectedCardId: slot.presentCardId,
    // 5229 (D8): sem coleção explícita, a reserva fica com a coleção da carta no bolso.
    expectedCollectionId: slot.presentCollectionId,
    expected: {
      cardName: slot.present.cardName,
      collectorNumber: slot.present.collectorNumber,
      collectorTotal: slot.present.collectorTotal,
      setCode: slot.present.setCode,
      imagePath: slot.present.imagePath,
      finishCode: slot.present.finishCode,
      finishName: slot.present.finishName,
    },
  };
  return { ...next, state: deriveSlotState(next) };
}

export function applyClearReservation(slot: BinderSlot): BinderSlot {
  const next: BinderSlot = { ...slot, expected: null, expectedCardId: null, expectedCollectionId: null };
  return { ...next, state: deriveSlotState(next) };
}

// ---------------------------------------------------------------------------
// Visão geral de páginas (P2-B-PAGE-OVERVIEW-AND-TOOL-RAIL-01)
// ---------------------------------------------------------------------------

export type PageOccupancy = { capacity: number; occupied: number; reservedMissing: number; empty: number; images: number };

/** Ocupação de uma página: cartas nos bolsos, reservas por completar e bolsos livres. */
export function pageOccupancy(page: Pick<BinderPage, "slots">): PageOccupancy {
  let occupied = 0;
  let reservedMissing = 0;
  let images = 0;
  for (const slot of page.slots) {
    if (isOccupied(slot)) occupied += 1;
    else if (slot.state === "RESERVED_EMPTY") reservedMissing += 1;
    else if (slot.image) images += 1;
  }
  const capacity = page.slots.length;
  // Bolso com imagem não está livre (não recebe carta), mas também não é carta.
  return { capacity, occupied, reservedMissing, empty: capacity - occupied - reservedMissing - images, images };
}

/** Move o item da posição `index` em `delta` posições (limitado às bordas). Não muta. */
export function moveInOrder<T>(order: readonly T[], index: number, delta: number): T[] {
  const next = [...order];
  if (index < 0 || index >= next.length) return next;
  const target = Math.min(Math.max(0, index + delta), next.length - 1);
  if (target === index) return next;
  const [item] = next.splice(index, 1);
  next.splice(target, 0, item as T);
  return next;
}

/** Troca dois itens de lugar. Não muta. */
export function swapInOrder<T>(order: readonly T[], a: number, b: number): T[] {
  const next = [...order];
  if (a < 0 || b < 0 || a >= next.length || b >= next.length || a === b) return next;
  const tmp = next[a] as T;
  next[a] = next[b] as T;
  next[b] = tmp;
  return next;
}

export function sameOrder<T>(a: readonly T[], b: readonly T[]): boolean {
  return a.length === b.length && a.every((value, index) => value === b[index]);
}

// ---------------------------------------------------------------------------
// Capacidade: adicionar páginas (5125) — P2-BINDER-CAPACITY-AND-EMPTY-SLOT-01
// ---------------------------------------------------------------------------

/**
 * Teto de páginas por pedido da interface. A unidade do contrato
 * (`add_layout_page`, 5125) é UMA página — uma face de folha; cada chamada
 * cria uma página com todos os bolsos do modelo, vazios.
 */
export const ADD_PAGES_MAX = 20;

export type AddPagesSummary = { count: number; totalAfter: number; slotsAdded: number; sheetsLabel: string };

/** O que a interface mostra antes de confirmar: total depois, bolsos novos e a equivalência em folhas físicas. */
export function addPagesSummary(count: number, columns: number, rows: number, totalPages: number): AddPagesSummary {
  const n = Math.min(ADD_PAGES_MAX, Math.max(1, Math.floor(Number.isFinite(count) ? count : 1)));
  const sheets = n / 2;
  const sheetsLabel =
    n % 2 === 0
      ? `= ${sheets} ${sheets === 1 ? "folha" : "folhas"} (frente e verso)`
      : n === 1
        ? "= meia folha (só a frente)"
        : `= ${Math.floor(sheets)} ${Math.floor(sheets) === 1 ? "folha" : "folhas"} e meia`;
  return { count: n, totalAfter: Math.max(0, totalPages) + n, slotsAdded: n * Math.max(1, columns) * Math.max(1, rows), sheetsLabel };
}

/** Mensagem depois de adicionar (parcial quando o banco recusou no meio). */
export function addPagesResultMessage(added: number, requested: number, slotsPerPage: number): string {
  const pages = added === 1 ? "1 página nova" : `${added} páginas novas`;
  const base = `${pages} no fim do fichário — ${added * slotsPerPage} bolsos vazios.`;
  return added < requested ? `Entraram ${added} de ${requested} páginas. ${base}` : base;
}

/**
 * Cadastro pelo fichário (V1-06 COMPLETE-01): tipo da coleção aberta para o
 * painel de cadastro. `null` = tipo desconhecido (a ação não aparece).
 */
export function registerKind(kind: CollectionKind): "set" | "free" | "pokedex" | null {
  if (kind === "SET" || kind === "MASTER_SET") return "set";
  if (kind === "FREE") return "free";
  if (kind === "POKEDEX") return "pokedex";
  return null;
}

/**
 * Contexto do cadastro pelo fichário. `storage` = fichário físico
 * (`collection_layout.storage_container_id`, 5247, lido pela 5252): as cartas
 * novas nascem guardadas nele e ficam elegíveis para os bolsos (5250). Um
 * fichário digital NÃO é tratado como local por si só — sem esse vínculo
 * legível, `storage` fica `null` e o painel pede a escolha explícita (NS-13).
 */
export type BinderRegisterContext = {
  kind: "set" | "free" | "pokedex";
  cardSet: { code: string; name: string } | null;
  storage: { id: string; name: string } | null;
};

export function binderRegisterContext(
  header: Pick<BinderHeader, "kind" | "binderStorageId" | "binderStorageName">,
  cardSet: { code: string; name: string } | null,
): BinderRegisterContext | null {
  const kind = registerKind(header.kind);
  if (!kind) return null;
  // Coleção de Set sem Set legível: o cadastro não teria referência — ação ausente.
  if (kind === "set" && !cardSet) return null;
  return {
    kind,
    cardSet: kind === "set" ? cardSet : null,
    storage: header.binderStorageId ? { id: header.binderStorageId, name: header.binderStorageName ?? "Fichário" } : null,
  };
}
