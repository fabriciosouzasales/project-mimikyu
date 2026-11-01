import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type AutoArrangeApplyResult,
  type AutoArrangeFailure,
  type AutoArrangePreview,
  type RpcErrorLike,
  classifyAutoArrangeFailure,
  isPlanToken,
  parseApply,
  parsePreview,
  writeDefinitelyNotApplied,
} from "./binder-auto-arrange.ts";
import { isCollectionId } from "./colecoes.ts";

// ---------------------------------------------------------------------------
// Organizar automaticamente (P2 UI E2) — chamadas às RPCs 5343 (prévia) e
// 5344 (aplicação), no mesmo formato das demais `*-queries.ts`: recebem o
// client da sessão do colecionador (nunca service_role) e devolvem
// { ok: true, … } | { ok: false, reason }. As Server Actions de
// fichario/actions.ts só criam o client e revalidam o cache.
//
// Regras:
// - entrada inválida é recusada antes de qualquer RPC (`invalid_argument`);
// - exatamente uma chamada por invocação: nenhum retry, nenhum caminho
//   alternativo de escrita; a aplicação só envia coleção + token (as posições
//   são recalculadas pelo banco);
// - erro do banco → classifyAutoArrangeFailure (SQLSTATE + mensagem de
//   domínio); sem SQLSTATE ou exceção de transporte → `uncertain`; resposta
//   fora do contrato → `invalid_response` (nunca sucesso aparente);
// - logs só com escopo, função, duração, código e classe/contagens: sem
//   token, sem identificadores, sem a mensagem do banco;
// - falha da aplicação diz se a escrita é sabidamente ausente
//   (`write: "not_applied"`) ou desconhecida (`write: "unknown"`, com o token
//   enviado, para a revalidação só por leitura via interpretRevalidation);
// - a revalidação de cache roda depois do sucesso e nunca o desfaz: se lançar,
//   o resultado continua sendo o da RPC (`cache: "failed"`).
// ---------------------------------------------------------------------------

export const AUTO_ARRANGE_LOG_SCOPE = "colecoes.binder_auto_arrange";
export const PREVIEW_RPC = "preview_my_binder_auto_arrange";
export const APPLY_RPC = "apply_my_binder_auto_arrange";

export type AutoArrangeFail = { ok: false; reason: AutoArrangeFailure };
export type AutoArrangePreviewOutcome = { ok: true; preview: AutoArrangePreview } | AutoArrangeFail;
export type AutoArrangeApplyFail = AutoArrangeFail & ({ write: "not_applied" } | { write: "unknown"; planToken: string });
/** Cache do fichário/coleção depois do sucesso: revalidado, não necessário (NOTHING_TO_DO) ou falhou (resultado mantido). */
export type AutoArrangeCacheState = "revalidated" | "not_needed" | "failed";
export type AutoArrangeApplyOutcome = { ok: true; result: AutoArrangeApplyResult; cache: AutoArrangeCacheState } | AutoArrangeApplyFail;

type RpcResponse = { data: unknown; error: RpcErrorLike };

function fail(fn: string, startedAt: number, code: string, reason: AutoArrangeFailure): AutoArrangeFail {
  console.error(JSON.stringify({ scope: AUTO_ARRANGE_LOG_SCOPE, fn, ms: Date.now() - startedAt, code, reason }));
  return { ok: false, reason };
}

/** Uma única chamada; exceção de transporte vira `null` (resultado desconhecido). */
async function callOnce(supabase: SupabaseClient, fn: string, args: Record<string, string>): Promise<RpcResponse | null> {
  try {
    const { data, error } = await supabase.rpc(fn, args);
    return { data, error: error ?? null };
  } catch {
    return null;
  }
}

function rpcFail(fn: string, startedAt: number, response: RpcResponse | null): AutoArrangeFail {
  if (response === null) return fail(fn, startedAt, "NO_RESPONSE", "uncertain");
  return fail(fn, startedAt, response.error?.code?.trim() || "NO_CODE", classifyAutoArrangeFailure(response.error));
}

/** Prévia (5343, STABLE, não grava). Só sob ação explícita do colecionador. */
export async function previewMyBinderAutoArrange(supabase: SupabaseClient, input: { collectionId: unknown }): Promise<AutoArrangePreviewOutcome> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "invalid_argument" };
  const startedAt = Date.now();
  const response = await callOnce(supabase, PREVIEW_RPC, { p_collection_id: input.collectionId });
  if (response === null || response.error) return rpcFail(PREVIEW_RPC, startedAt, response);
  const preview = parsePreview(response.data);
  if (!preview) return fail(PREVIEW_RPC, startedAt, "BAD_SHAPE", "invalid_response");
  return { ok: true, preview };
}

function applyFail(failure: AutoArrangeFail, planToken: string): AutoArrangeApplyFail {
  return writeDefinitelyNotApplied(failure.reason) ? { ...failure, write: "not_applied" } : { ...failure, write: "unknown", planToken };
}

/**
 * Aplicação (5344): coleção + token da prévia confirmada; nada mais vem do
 * cliente. APPLIED, ALREADY_APPLIED e NOTHING_TO_DO são sucessos distintos.
 * `revalidate` (revalidatePath das telas) roda em APPLIED e ALREADY_APPLIED;
 * uma exceção nele é registrada e não altera o resultado nem repete a RPC.
 */
export async function applyMyBinderAutoArrange(
  supabase: SupabaseClient,
  input: { collectionId: unknown; planToken: unknown },
  revalidate: () => void = () => {},
): Promise<AutoArrangeApplyOutcome> {
  if (!isCollectionId(input?.collectionId) || !isPlanToken(input?.planToken)) return { ok: false, reason: "invalid_argument", write: "not_applied" };
  const startedAt = Date.now();
  const response = await callOnce(supabase, APPLY_RPC, { p_collection_id: input.collectionId, p_plan_token: input.planToken });
  if (response === null || response.error) return applyFail(rpcFail(APPLY_RPC, startedAt, response), input.planToken);
  const result = parseApply(response.data);
  if (!result) return applyFail(fail(APPLY_RPC, startedAt, "BAD_SHAPE", "invalid_response"), input.planToken);
  console.info(
    JSON.stringify({
      scope: AUTO_ARRANGE_LOG_SCOPE,
      fn: APPLY_RPC,
      ms: Date.now() - startedAt,
      outcome: result.outcome,
      inserted: result.inserted,
      pages: result.outcome === "APPLIED" ? result.pages.length : 0,
    }),
  );
  if (result.outcome === "NOTHING_TO_DO") return { ok: true, result, cache: "not_needed" };
  try {
    revalidate();
    return { ok: true, result, cache: "revalidated" };
  } catch {
    // Sem a mensagem da exceção (pode conter o caminho com o id da coleção).
    console.error(JSON.stringify({ scope: AUTO_ARRANGE_LOG_SCOPE, fn: "revalidatePath", ms: Date.now() - startedAt, outcome: result.outcome, reason: "cache_revalidation_failed" }));
    return { ok: true, result, cache: "failed" };
  }
}
