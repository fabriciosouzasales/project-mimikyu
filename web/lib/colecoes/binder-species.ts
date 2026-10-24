import type { BinderHeader, BinderPage, BinderSlot } from "./binder.ts";

/**
 * Referências de espécie nos bolsos do fichário da Pokédex
 * (POKEDEX-BINDER-SPECIES-REFERENCE, contratos 5257–5260).
 *
 * A referência é um rótulo do BOLSO — nunca carta, reserva, exemplar ou
 * progresso. Aparece só com o bolso visualmente vazio (D3: carta, reserva,
 * imagem e mesclagem têm prioridade) e só com a exibição ligada (ajuste A:
 * ocultar não apaga vínculos). Funções puras, sem rede.
 */

export type SpeciesReference = {
  nationalNumber: number;
  speciesName: string;
  /** `display_storage_path` da arte oficial (mesma fonte da Pokédex); `null` = sem arte. */
  artworkPath: string | null;
};

export type SpeciesReferenceState = {
  hasBinder: boolean;
  /** A proprietária do fichário é uma coleção Pokédex (o fichário pode ter referências). */
  isPokedexOwner: boolean;
  /** Esta coleção é a proprietária Pokédex ativa: pode aplicar/remover. */
  canManage: boolean;
  referenceCount: number;
  visible: boolean;
};

export type SpeciesReferencePreview = {
  positionsInScope: number;
  slotsTotal: number;
  pairCount: number;
  slotsLeftFree: number;
  positionsUnplaced: number;
  firstPage: number | null;
  lastPage: number | null;
  firstNumber: number | null;
  lastNumber: number | null;
  slotsWithContent: number;
  existingCount: number;
  alreadyApplied: boolean;
  planToken: string;
};

/**
 * Só fichários que podem ter referências fazem a leitura: proprietária
 * Pokédex ou convidada (a convidada pode estar num fichário de Pokédex).
 * Fichários comuns não fazem nenhuma chamada nova.
 */
export function mayHaveSpeciesReferences(header: Pick<BinderHeader, "hasBinder" | "kind" | "role">): boolean {
  return header.hasBinder && (header.kind === "POKEDEX" || header.role === "GUEST");
}

const PLAN_TOKEN = /^[0-9a-f]{64}$/;

export function isSpeciesPlanToken(value: unknown): value is string {
  return typeof value === "string" && PLAN_TOKEN.test(value);
}

function int(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function rowOf(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? (data.length === 1 ? data[0] : null) : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export function parseSpeciesReferenceState(data: unknown): SpeciesReferenceState | null {
  const row = rowOf(data);
  if (!row) return null;
  const count = int(row.reference_count);
  if (typeof row.has_binder !== "boolean" || typeof row.is_pokedex_owner !== "boolean" || typeof row.can_manage !== "boolean") return null;
  if (count === null || count < 0 || typeof row.references_visible !== "boolean") return null;
  return {
    hasBinder: row.has_binder,
    isPokedexOwner: row.is_pokedex_owner,
    canManage: row.can_manage,
    referenceCount: count,
    visible: row.references_visible,
  };
}

/** Linhas da 5259 → bolso → referência. Linha malformada invalida o lote (nunca um bolso trocado). */
export function parseSpeciesReferences(data: unknown): Map<string, SpeciesReference> | null {
  if (!Array.isArray(data)) return null;
  const out = new Map<string, SpeciesReference>();
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const row = raw as Record<string, unknown>;
    const n = int(row.national_number);
    if (typeof row.slot_id !== "string" || n === null || n < 1 || typeof row.species_name !== "string") return null;
    const path = typeof row.artwork_path === "string" && row.artwork_path.length > 0 ? row.artwork_path : null;
    out.set(row.slot_id, { nationalNumber: n, speciesName: row.species_name, artworkPath: path });
  }
  return out;
}

export function attachSpeciesReferences(pages: BinderPage[], refs: ReadonlyMap<string, SpeciesReference>): BinderPage[] {
  if (refs.size === 0) return pages;
  return pages.map((page) => ({
    ...page,
    slots: page.slots.map((slot) => {
      const ref = refs.get(slot.slotId);
      return ref ? { ...slot, speciesRef: ref } : slot;
    }),
  }));
}

/** D3: carta, reserva, imagem e mesclagem ocultam a referência enquanto ocupam o bolso. */
export function shouldShowSpeciesReference(
  slot: Pick<BinderSlot, "state" | "image" | "regionId" | "speciesRef">,
  visible: boolean,
): boolean {
  return visible && Boolean(slot.speciesRef) && slot.state === "EMPTY" && !slot.image && !slot.regionId;
}

/** Número nacional discreto: `#0001`. */
export function formatNationalNumber(n: number): string {
  return `#${String(Math.max(0, Math.trunc(n))).padStart(4, "0")}`;
}

export function speciesReferenceLabel(ref: SpeciesReference): string {
  return `bolso reservado visualmente para ${formatNationalNumber(ref.nationalNumber)} ${ref.speciesName}`;
}

export function parseSpeciesPreview(data: unknown): SpeciesReferencePreview | null {
  const row = rowOf(data);
  if (!row) return null;
  const count = (key: string): number | null => {
    const v = int(row[key]);
    return v !== null && v >= 0 ? v : null;
  };
  const positionsInScope = count("positions_in_scope");
  const slotsTotal = count("slots_total");
  const pairCount = count("pair_count");
  const slotsLeftFree = count("slots_left_free");
  const positionsUnplaced = count("positions_unplaced");
  const slotsWithContent = count("slots_with_content");
  const existingCount = count("existing_count");
  if (
    positionsInScope === null ||
    slotsTotal === null ||
    pairCount === null ||
    slotsLeftFree === null ||
    positionsUnplaced === null ||
    slotsWithContent === null ||
    existingCount === null
  ) {
    return null;
  }
  if (typeof row.already_applied !== "boolean" || !isSpeciesPlanToken(row.plan_token)) return null;
  return {
    positionsInScope,
    slotsTotal,
    pairCount,
    slotsLeftFree,
    positionsUnplaced,
    firstPage: int(row.first_page),
    lastPage: int(row.last_page),
    firstNumber: int(row.first_number),
    lastNumber: int(row.last_number),
    slotsWithContent,
    existingCount,
    alreadyApplied: row.already_applied,
    planToken: row.plan_token,
  };
}

export type SpeciesFailure =
  | "unavailable"
  | "not_found"
  | "owner_only"
  | "not_pokedex"
  | "archived"
  | "plan_changed"
  | "present"
  | "nothing"
  | "count_mismatch"
  | "lock_busy"
  | "not_authenticated"
  | "invalid"
  | "unknown";

export function classifySpeciesFailure(code: string | null | undefined, message: string | null | undefined): SpeciesFailure {
  const text = (message ?? "").trim();
  if (code === "PGRST202" || code === "42883") return "unavailable";
  if (text === "BINDER_OWNER_ONLY") return "owner_only";
  if (text === "NOT_POKEDEX_COLLECTION") return "not_pokedex";
  if (text === "COLLECTION_ARCHIVED") return "archived";
  if (text === "PLAN_CHANGED") return "plan_changed";
  if (text === "SPECIES_REFERENCES_PRESENT") return "present";
  if (text === "NOTHING_TO_APPLY") return "nothing";
  if (text === "COUNT_MISMATCH") return "count_mismatch";
  if (code === "55P03") return "lock_busy";
  if (text === "COLLECTION_NOT_FOUND" || text === "BINDER_NOT_FOUND" || code === "P0002") return "not_found";
  if (code === "28000" || text === "not_authenticated") return "not_authenticated";
  if (code === "42501") return "owner_only";
  if (code === "22023" || code === "22P02") return "invalid";
  return "unknown";
}

export function speciesFailureMessage(reason: SpeciesFailure): string {
  switch (reason) {
    case "unavailable":
      return "Os Pokémon nos bolsos ainda não estão disponíveis. Nada foi alterado.";
    case "owner_only":
      return "Os Pokémon dos bolsos são definidos pela coleção dona do fichário.";
    case "not_pokedex":
      return "Os Pokémon nos bolsos existem só nos fichários de coleções Pokédex.";
    case "archived":
      return "Reative a coleção para alterar o fichário.";
    case "plan_changed":
      return "O fichário mudou desde a prévia. Revise e confirme de novo.";
    case "present":
      return "Este fichário já tem Pokémon nos bolsos.";
    case "nothing":
      return "Não há bolsos ou Pokémon para posicionar.";
    case "count_mismatch":
      return "A quantidade mudou. Revise antes de remover.";
    case "lock_busy":
      return "O fichário está sendo alterado. Tente de novo em instantes.";
    case "not_found":
      return "Não encontramos este fichário.";
    case "not_authenticated":
      return "Sua sessão expirou. Entre de novo para continuar.";
    case "invalid":
    case "unknown":
      return "Não foi possível concluir. Nada foi alterado; tente de novo.";
  }
}

/**
 * 5260 (ajuste B): remover uma página com referências é recusado até a
 * confirmação com a contagem exata. Devolve N quando a recusa é dessa
 * natureza (para mostrar o aviso e repetir com N), senão `null`.
 */
export function speciesReferencesOnPage(message: string | null | undefined, hint: string | null | undefined): number | null {
  const fromHint = /^SPECIES_REFERENCES_ON_PAGE:(\d+)$/.exec((hint ?? "").trim());
  if (fromHint) return Number(fromHint[1]);
  const fromMessage = /^page has (\d+) species reference\(s\)/.exec((message ?? "").trim());
  return fromMessage ? Number(fromMessage[1]) : null;
}

export function pageRemovalWarning(count: number): string {
  return count === 1
    ? "Esta página mostra 1 Pokémon de referência. Ao excluí-la, essa referência deixa de existir."
    : `Esta página mostra ${count} Pokémon de referência. Ao excluí-la, essas referências deixam de existir.`;
}
