import { formatCount, pluralize } from "./acervo.ts";
import { type CardConditionCode, cardConditionLabel, isCardConditionCode } from "./card-condition.ts";

/**
 * V1-16 — editar a condição física de exemplares existentes (FRONTEND-02).
 *
 * A única via de escrita é `set_my_physical_cards_condition(uuid[], text)`
 * (5364 v1.1, no LIVE desde a S4): exemplares do PRÓPRIO usuário, 1 a 500 por
 * chamada, todos ou nenhum (um exemplar alheio ou removido → nada muda),
 * grava só onde a condição muda e devolve `requested_count` (distintos) e
 * `changed_count` (os que de fato mudaram — podem ser menos, nunca se presume
 * que sejam iguais).
 *
 * Só a condição muda: preço de referência (sempre NM), local, coleção,
 * reservas, Favoritos e fichário ficam como estão (C-232/C-233). Diferente
 * do local (NS-13), não há passo de confirmação: a troca é reversível pelo
 * mesmo fluxo e não diz nada sobre onde a carta está.
 */

/** Teto da 5364, avaliado sobre o array recebido (antes da deduplicação). */
export const CONDITION_BATCH_MAX = 500;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Ids distintos e bem formados, ou `null` (não é array, vazio, inválido ou acima do teto). */
export function normalizeConditionBatch(ids: unknown): string[] | null {
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > CONDITION_BATCH_MAX) return null;
  if (!ids.every((id) => typeof id === "string" && UUID.test(id))) return null;
  return [...new Set(ids as string[])];
}

export type CopyConditionFailure =
  | "not_authenticated"
  | "invalid"
  | "invalid_condition"
  | "too_many"
  | "copies_gone"
  | "busy"
  | "unavailable";

/**
 * Traduz o erro da 5364. A função comunica por SQLSTATE e mensagens literais
 * (`authentication required`, `CONDITION_NOT_FOUND…`, `lote excede…`,
 * `…não pertencem ao inventory do chamador`); trava ocupada (`lock_timeout`
 * 5 s → 55P03) e impasse (40P01) viram "tente de novo". O texto cru nunca
 * chega ao colecionador.
 */
export function copyConditionFailureFromError(error: { code?: string | null; message?: string | null } | null | undefined): CopyConditionFailure {
  const code = error?.code ?? "";
  const message = (error?.message ?? "").toLowerCase();
  if (code === "28000" || code === "42501" || message.includes("authentication required")) return "not_authenticated";
  if (code === "55P03" || code === "40P01" || code === "40001") return "busy";
  if (message.includes("não pertencem ao inventory")) return "copies_gone";
  if (message.includes("lote excede")) return "too_many";
  if (message.includes("condition_not_found") || message.includes("condition_code é obrigatório")) return "invalid_condition";
  if (message.includes("não pode ser vazio") || message.includes("unidimensional")) return "invalid";
  return "unavailable";
}

export function copyConditionFailureMessage(reason: CopyConditionFailure): string {
  switch (reason) {
    case "not_authenticated":
      return "Sua sessão expirou. Entre novamente para continuar — nenhuma condição foi alterada.";
    case "invalid":
      return "Escolha pelo menos um exemplar.";
    case "invalid_condition":
      return "Escolha uma das condições da lista. Nenhuma condição foi alterada.";
    case "too_many":
      return `Escolha até ${formatCount(CONDITION_BATCH_MAX)} exemplares por vez.`;
    case "copies_gone":
      return "Algum exemplar escolhido não está mais no seu acervo. A lista foi atualizada. Nenhuma condição foi alterada.";
    case "busy":
      return "Esses exemplares estavam sendo alterados em outro lugar. Nenhuma condição foi alterada — tente novamente.";
    case "unavailable":
      return "Não foi possível alterar a condição agora. Nada foi alterado — tente novamente.";
  }
}

export type CopyConditionResult = { requested: number; changed: number };

/** Lê o retorno da 5364 (`TABLE(requested_count, changed_count)` → uma linha); forma inesperada → `null`. */
export function parseConditionResult(raw: unknown): CopyConditionResult | null {
  const row = Array.isArray(raw) ? raw[0] : raw;
  if (typeof row !== "object" || row === null) return null;
  const { requested_count, changed_count } = row as Record<string, unknown>;
  const requested = Number(requested_count);
  const changed = Number(changed_count);
  if (!Number.isInteger(requested) || !Number.isInteger(changed) || requested < 1 || changed < 0 || changed > requested) return null;
  return { requested, changed };
}

/** Cliente mínimo (o `createClient` do servidor) — injetável nos testes. */
export type ConditionClient = {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string | null; message?: string | null } | null }>;
};

export type SetCopiesConditionOutcome =
  | { ok: true; requested: number; changed: number; conditionCode: CardConditionCode }
  | { ok: false; reason: CopyConditionFailure; code?: string };

/**
 * Validação de formato + a única chamada à 5364. Lote inválido, acima do
 * teto ou código fora da escala param ANTES de chamar o banco. Nunca devolve
 * sucesso parcial: ou o banco confirmou o lote inteiro (`changed` ≤
 * `requested`), ou é falha.
 */
export async function setCopiesCondition(
  client: ConditionClient,
  input: { physicalCardIds: unknown; conditionCode: unknown },
): Promise<SetCopiesConditionOutcome> {
  const ids = normalizeConditionBatch(input?.physicalCardIds);
  if (ids === null) {
    const tooMany = Array.isArray(input?.physicalCardIds) && input.physicalCardIds.length > CONDITION_BATCH_MAX;
    return { ok: false, reason: tooMany ? "too_many" : "invalid" };
  }
  if (!isCardConditionCode(input.conditionCode)) return { ok: false, reason: "invalid_condition" };
  const { data, error } = await client.rpc("set_my_physical_cards_condition", {
    p_physical_card_ids: ids,
    p_condition_code: input.conditionCode,
  });
  if (error) return { ok: false, reason: copyConditionFailureFromError(error), code: error.code ?? undefined };
  const parsed = parseConditionResult(data);
  if (!parsed) return { ok: false, reason: "unavailable", code: "BAD_SHAPE" };
  return { ok: true, ...parsed, conditionCode: input.conditionCode };
}

// ---- interface (regras puras) ----

/** Assinatura das condições exibidas — base do provisório (muda quando o servidor traz outra leitura). */
export function conditionSignature(copies: readonly { physicalCardId: string; conditionCode: CardConditionCode | null }[]): string {
  return copies.map((copy) => `${copy.physicalCardId}:${copy.conditionCode ?? "-"}`).join("|");
}

/** Ids marcados que ainda NÃO estão na condição escolhida (só esses são enviados). */
export function idsToChange(
  selected: readonly string[],
  conditionOf: (id: string) => CardConditionCode | null,
  target: CardConditionCode,
): string[] {
  return selected.filter((id) => conditionOf(id) !== target);
}

/**
 * Mensagem de sucesso. Conta só o que está comprovado:
 *  - `changed` = o que o banco DE FATO mudou (`changed_count`);
 *  - os demais marcados já estavam na condição — os que a interface nem
 *    enviou (já exibidos nela) e os que o banco recebeu mas não precisou
 *    mudar (`requested - changed`: a 5364 só grava onde a condição difere).
 * `selected` = marcados no início do envio (≥ `requested`, que é o
 * subconjunto enviado e deduplicado). Contagens incoerentes são limitadas,
 * nunca extrapoladas.
 */
export function conditionApplySuccess(
  result: CopyConditionResult & { selected: number },
  target: CardConditionCode,
): string {
  const short = cardConditionLabel(target)?.short ?? target;
  const changed = Math.max(0, Math.min(result.changed, result.requested));
  const total = Math.max(result.selected, result.requested);
  const unchanged = total - changed;
  if (changed === 0) {
    return total === 1
      ? `Nenhuma condição mudou — o exemplar já estava em ${short}.`
      : `Nenhuma condição mudou — os ${formatCount(total)} exemplares marcados já estavam em ${short}.`;
  }
  const head = `${pluralize(changed, "exemplar", "exemplares")} ${changed === 1 ? "agora está" : "agora estão"} em ${short}`;
  if (unchanged === 0) return `${head}.`;
  return `${head}; ${pluralize(unchanged, "outro já estava", "outros já estavam")} nessa condição.`;
}
