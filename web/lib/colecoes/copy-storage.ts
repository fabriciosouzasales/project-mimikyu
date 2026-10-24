import { formatCount, pluralize } from "./acervo.ts";

/**
 * WHERE-03 — localização física dos exemplares (regras puras).
 *
 * A única via de escrita é `set_physical_cards_storage` (5024, canônica):
 * local não nulo atribui/move; nulo limpa ("Sem localização definida");
 * 1 a 500 exemplares por chamada; atômica (um exemplar alheio no lote →
 * nada muda); idempotente por estado (repetir grava o mesmo valor).
 *
 * Princípios (C-58/C-59, NS-13, NS-15):
 *  - o local pertence ao EXEMPLAR; o local padrão de uma coleção é só uma
 *    preferência e nunca é aplicado sozinho;
 *  - toda atribuição pede confirmação explícita antes de gravar (NS-13 —
 *    ver `storageAssignConfirmation`);
 *  - mudar o local não mexe em coleção, variante, idioma, condição nem
 *    quantidade.
 */

/** Teto de `set_physical_cards_storage` (5024): avaliado sobre o array recebido. */
export const STORAGE_BATCH_MAX = 500;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** Ids distintos e bem formados, ou `null` (vazio, inválido ou acima do teto). */
export function normalizeStorageBatch(ids: unknown): string[] | null {
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > STORAGE_BATCH_MAX) return null;
  if (!ids.every((id) => typeof id === "string" && UUID.test(id))) return null;
  return [...new Set(ids as string[])];
}

/** Falhas que a 5024 comunica (mensagens de texto, sem código próprio). */
export type CopyStorageFailure =
  | "not_authenticated"
  | "invalid"
  | "too_many"
  | "storage_gone"
  | "copies_gone"
  | "binder_positioned"
  | "binder_locked"
  | "unavailable";

/**
 * Traduz o erro da 5024. A função não tem códigos: reconhece as mensagens
 * canônicas (literais preservadas pela 5138) e a FK (23503) quando o local é
 * excluído entre a validação e a escrita.
 */
export function copyStorageFailureFromError(error: { code?: string | null; message?: string | null } | null | undefined): CopyStorageFailure {
  const message = (error?.message ?? "").toLowerCase();
  // BINDER-PHYSICAL-LOCATION (5249/5256, D3): exemplar posicionado no fichário digital.
  if (message.trim() === "binder_position_confirmation_required") return "binder_positioned";
  if (message.trim() === "binder_position_locked") return "binder_locked";
  if (message.includes("authentication required")) return "not_authenticated";
  if (message.includes("lote excede")) return "too_many";
  if (message.includes("storage container not found") || message.includes("storage container does not belong")) return "storage_gone";
  if (error?.code === "23503") return "storage_gone";
  if (message.includes("não pertencem ao inventory")) return "copies_gone";
  if (message.includes("não pode ser vazio") || message.includes("unidimensional")) return "invalid";
  return "unavailable";
}

export function copyStorageFailureMessage(reason: CopyStorageFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar.";
    case "invalid":
      return "Escolha pelo menos um exemplar.";
    case "too_many":
      return `Escolha até ${formatCount(STORAGE_BATCH_MAX)} exemplares por vez.`;
    case "storage_gone":
      return "Esse local não existe mais. A lista foi atualizada — escolha outro. Nada foi alterado.";
    case "copies_gone":
      return "Algum exemplar escolhido não está mais no seu acervo. A lista foi atualizada. Nada foi alterado.";
    case "binder_positioned":
      return "Algum exemplar está num bolso do fichário digital. Ao mudar o local, ele sai do bolso (continua no acervo e na coleção). Confirme para continuar — nada foi alterado ainda.";
    case "binder_locked":
      return "Algum exemplar está num bolso fixado do fichário digital. Solte o cadeado no fichário antes de mudar o local — nada foi alterado.";
    case "unavailable":
      return "Não foi possível guardar agora. Nada foi alterado — tente novamente.";
  }
}

/** Quantos dos escolhidos já estão no destino (nada a gravar para eles). */
export function alreadyAtTarget(
  selected: readonly string[],
  storageByCopy: Readonly<Record<string, string | null>>,
  target: string | null,
): number {
  return selected.filter((id) => (storageByCopy[id] ?? null) === target).length;
}

/** Texto curto da localização atual de um exemplar. */
export function copyStorageLabel(name: string | null): string {
  return name ?? "Sem localização definida";
}

/**
 * Pedido de confirmação (NS-13). O modelo não guarda registro de que um
 * local foi confirmado, e a interface não reconhece o "Local padrão" pelo
 * nome (o nome é renomeável e não é identidade). Por isso TODA atribuição
 * pede confirmação — o que cobre, em especial, o local criado pelo CT-01.
 * Quando o destino é local padrão de coleções, a frase lembra que isso é
 * só uma preferência e não prova onde a carta está.
 */
export function storageAssignConfirmation(input: {
  count: number;
  targetName: string | null;
  targetDefaultCollectionCount: number;
}): { title: string; body: string; note: string | null; action: string } {
  const what = pluralize(input.count, "exemplar", "exemplares");
  if (input.targetName === null) {
    return {
      title: `Remover a localização de ${what}?`,
      body: `${input.count === 1 ? "Ele passa" : "Eles passam"} a aparecer como “Sem localização definida”. Nenhuma carta sai das suas coleções.`,
      note: null,
      action: "Remover localização",
    };
  }
  const defaults = input.targetDefaultCollectionCount;
  return {
    title: `Guardar ${what} em “${input.targetName}”?`,
    body: `Confirme que ${input.count === 1 ? "este exemplar está" : "estes exemplares estão"} fisicamente em “${input.targetName}”. Nenhuma carta muda de coleção.`,
    note:
      defaults > 0
        ? `“${input.targetName}” é o local padrão de ${defaults === 1 ? "uma coleção" : `${formatCount(defaults)} coleções`} — isso é só uma sugestão e não indica onde a carta está.`
        : null,
    action: "Confirmar e guardar",
  };
}

export function storageAssignSuccess(count: number, targetName: string | null): string {
  const what = pluralize(count, "exemplar", "exemplares");
  return targetName === null
    ? `${what} ${count === 1 ? "ficou" : "ficaram"} sem localização definida. Nenhuma carta mudou de coleção.`
    : `${what} ${count === 1 ? "guardado" : "guardados"} em “${targetName}”. Nenhuma carta mudou de coleção.`;
}
