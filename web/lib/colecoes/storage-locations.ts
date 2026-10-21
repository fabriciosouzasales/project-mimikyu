import { formatCount, pluralize } from "./acervo.ts";

/**
 * "Meus locais" (WHERE-02) — regras puras da gestão de locais físicos.
 *
 * Preparação: os contratos 5212–5219 ainda NÃO estão no LIVE; este módulo
 * só fixa a linguagem e a validação que a interface vai usar, espelhando
 * exatamente as regras do banco (nome 1–60 após aparar, tipo opcional,
 * exclusão só de local vazio e que não seja local padrão de coleção).
 * Nenhum termo técnico (Storage Container, Inventory, códigos) chega à tela.
 */

/** Mesmo limite de `chk_storage_container_name` (5213) e de 5216/5217. */
export const STORAGE_NAME_MAX = 60;

/** Nome aparado; `null` quando vazio ou acima do limite (a interface explica). */
export function normalizeStorageName(input: string): string | null {
  const name = input.trim();
  if (name.length === 0 || name.length > STORAGE_NAME_MAX) return null;
  return name;
}

/** Um local como devolvido por `get_my_storage_locations` (5219). */
export type StorageLocation = {
  id: string;
  name: string;
  kindCode: string | null;
  kindLabel: string | null;
  cardCount: number;
  defaultCollectionCount: number;
  canDelete: boolean;
};

export type StorageSummary = {
  totalCards: number;
  locatedCards: number;
  unlocatedCards: number;
  locationCount: number;
};

/** Converte uma linha da 5219 (snake_case) — `null` se o formato não bate. */
export function toStorageLocation(row: Record<string, unknown>): StorageLocation | null {
  const id = row.storage_container_id;
  const name = row.name;
  const cardCount = Number(row.card_count);
  const defaults = Number(row.default_collection_count);
  if (typeof id !== "string" || typeof name !== "string" || !Number.isFinite(cardCount) || !Number.isFinite(defaults)) {
    return null;
  }
  return {
    id,
    name,
    kindCode: typeof row.kind_code === "string" ? row.kind_code : null,
    kindLabel: typeof row.kind_label === "string" ? row.kind_label : null,
    cardCount,
    defaultCollectionCount: defaults,
    canDelete: row.can_delete === true,
  };
}

/** "Nenhum exemplar" / "1 exemplar" / "1.248 exemplares". */
export function storageCardCountLabel(count: number): string {
  return count === 0 ? "Nenhum exemplar" : pluralize(count, "exemplar", "exemplares");
}

/** Linha de apoio do local: tipo (se houver) · quantidade. */
export function storageLocationFacts(location: Pick<StorageLocation, "kindLabel" | "cardCount">): string {
  const count = storageCardCountLabel(location.cardCount);
  return location.kindLabel ? `${location.kindLabel} · ${count}` : count;
}

/** Por que um local não pode ser excluído agora (mesma regra da 5218). */
export type StorageDeleteBlock = "has_cards" | "collection_default";

export function storageDeleteBlock(
  location: Pick<StorageLocation, "cardCount" | "defaultCollectionCount">,
): StorageDeleteBlock | null {
  if (location.cardCount > 0) return "has_cards";
  if (location.defaultCollectionCount > 0) return "collection_default";
  return null;
}

export function storageDeleteBlockMessage(
  block: StorageDeleteBlock,
  location: Pick<StorageLocation, "cardCount" | "defaultCollectionCount">,
): string {
  if (block === "has_cards") {
    return `Este local guarda ${storageCardCountLabel(location.cardCount).toLowerCase()}. Para excluí-lo, ele precisa estar vazio.`;
  }
  const n = location.defaultCollectionCount;
  const which = n === 1 ? "de uma coleção" : `de ${formatCount(n)} coleções`;
  return `Este é o local padrão ${which}. Troque o local padrão em Ajustes da coleção antes de excluir.`;
}

/** Falhas que as funções 5216–5219 comunicam por código. */
export type StorageFailure =
  | "not_authenticated"
  | "invalid_name"
  | "invalid_kind"
  | "idempotency_reused"
  | "not_found"
  | "has_cards"
  | "collection_default"
  | "in_use"
  | "unavailable";

const CODE_TO_FAILURE: Record<string, StorageFailure> = {
  not_authenticated: "not_authenticated",
  INVALID_NAME: "invalid_name",
  INVALID_KIND: "invalid_kind",
  INVALID_REQUEST: "unavailable",
  IDEMPOTENCY_KEY_REUSED: "idempotency_reused",
  INVENTORY_NOT_FOUND: "unavailable",
  STORAGE_NOT_FOUND: "not_found",
  STORAGE_HAS_CARDS: "has_cards",
  STORAGE_IS_COLLECTION_DEFAULT: "collection_default",
  STORAGE_IN_USE: "in_use",
};

/** Lê o código da mensagem do erro do PostgREST (`message` = código da função). */
export function storageFailureFromError(error: { message?: string | null } | null | undefined): StorageFailure {
  const code = error?.message?.trim() ?? "";
  return CODE_TO_FAILURE[code] ?? "unavailable";
}

export function storageFailureMessage(reason: StorageFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "invalid_name":
      return `Dê um nome ao local, com até ${STORAGE_NAME_MAX} caracteres.`;
    case "invalid_kind":
      return "Esse tipo de local não está disponível. Escolha outro.";
    case "idempotency_reused":
      return "Não foi possível concluir. Recarregue a página e tente de novo.";
    case "not_found":
      return "Esse local não existe mais. A lista foi atualizada.";
    case "has_cards":
      return "Este local guarda exemplares. Para excluí-lo, ele precisa estar vazio.";
    case "collection_default":
      return "Este é o local padrão de uma coleção. Troque o local padrão em Ajustes da coleção antes de excluir.";
    case "in_use":
      return "Este local acabou de ser usado. Nada foi excluído — confira a lista.";
    case "unavailable":
      return "Não foi possível concluir agora. Nada foi alterado — tente novamente.";
  }
}
