import { formatCount, pluralize } from "./acervo.ts";

/**
 * "Meus locais" (WHERE-02) — regras puras da gestão de locais físicos.
 *
 * Contratos 5212–5219 no LIVE desde 2026-10-21 (canônicos em database/schema/).
 * Este módulo fixa a linguagem e a validação da interface, espelhando
 * exatamente as regras do banco (nome 1–60 após aparar, tipo opcional,
 * exclusão só de local vazio e que não seja local padrão de coleção). O banco
 * reconfere tudo; aqui só se responde cedo e se fala a língua do colecionador.
 * Nenhum termo técnico (Storage Container, Inventory, códigos) chega à tela.
 */

/** Rota de "Meus locais" (WHERE-02). */
export const LOCAIS_PATH = "/colecoes/locais";

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

// ---------------------------------------------------------------------------
// Interface "Meus locais" (WHERE-02 FRONTEND IMPLEMENTATION-01)
// ---------------------------------------------------------------------------

/** Um tipo de local ativo (`storage_container_kind`, 5212). O rótulo vem do banco. */
export type StorageKind = { code: string; label: string };

/** Mesmo formato dos códigos de 5212 (maiúsculas, dígitos e `_`). */
const KIND_CODE = /^[A-Z][A-Z0-9_]{0,39}$/;

export function isStorageKindCode(value: unknown): value is string {
  return typeof value === "string" && KIND_CODE.test(value);
}

/** Converte uma linha de `storage_container_kind` — `null` se o formato não bate. */
export function toStorageKind(row: Record<string, unknown>): StorageKind | null {
  const code = row.code;
  const label = row.label;
  if (!isStorageKindCode(code) || typeof label !== "string" || label.trim() === "") return null;
  return { code, label: label.trim() };
}

/** Converte a linha de `get_my_storage_summary` (5219) — `null` se o formato não bate. */
export function toStorageSummary(row: Record<string, unknown> | null | undefined): StorageSummary | null {
  if (!row) return null;
  const totalCards = Number(row.total_cards);
  const locatedCards = Number(row.located_cards);
  const unlocatedCards = Number(row.unlocated_cards);
  const locationCount = Number(row.location_count);
  if (![totalCards, locatedCards, unlocatedCards, locationCount].every((n) => Number.isInteger(n) && n >= 0)) return null;
  return { totalCards, locatedCards, unlocatedCards, locationCount };
}

/**
 * Opções do campo "Tipo" ao editar: os tipos ativos e, se o local já usa um
 * tipo que saiu da lista (inativo), esse tipo também — a 5217 aceita manter o
 * tipo atual, e a tela nunca mostra um código no lugar do rótulo.
 */
export function kindOptionsFor(
  kinds: readonly StorageKind[],
  current: Pick<StorageLocation, "kindCode" | "kindLabel"> | null,
): StorageKind[] {
  if (!current?.kindCode || kinds.some((kind) => kind.code === current.kindCode)) return [...kinds];
  return [...kinds, { code: current.kindCode, label: current.kindLabel ?? "Tipo atual" }];
}

/** Há algo a salvar? Nome inválido nunca conta como mudança. */
export function storageEditChanged(
  location: Pick<StorageLocation, "name" | "kindCode">,
  draftName: string,
  draftKind: string | null,
): boolean {
  const name = normalizeStorageName(draftName);
  if (name === null) return false;
  return name !== location.name || (draftKind || null) !== (location.kindCode ?? null);
}

/** Selo do local que é local padrão de coleções (preferência, não localização — NS-15). */
export function storageDefaultLabel(count: number): string | null {
  if (count <= 0) return null;
  return count === 1 ? "Local padrão de 1 coleção" : `Local padrão de ${formatCount(count)} coleções`;
}

/**
 * Quantas silhuetas de carta a pilha decorativa do local mostra: 0 (vazio),
 * 1 (até 9), 2 (até 99), 3 (100 ou mais). Só leitura visual — o número exato
 * está sempre escrito ao lado.
 */
export function storageStackTier(cardCount: number): 0 | 1 | 2 | 3 {
  if (cardCount <= 0) return 0;
  if (cardCount < 10) return 1;
  if (cardCount < 100) return 2;
  return 3;
}

/** Frase de sucesso, sempre lembrando que nenhuma carta mudou de lugar. */
export function storageSuccessMessage(
  action: "created" | "renamed" | "updated" | "deleted",
  name: string,
): string {
  switch (action) {
    case "created":
      return `“${name}” foi criado. Nenhuma carta foi colocada nele automaticamente.`;
    case "renamed":
    case "updated":
      return `“${name}” foi atualizado. Nenhuma carta mudou de lugar.`;
    case "deleted":
      return `“${name}” foi excluído. Nenhuma carta foi movida ou apagada.`;
  }
}
