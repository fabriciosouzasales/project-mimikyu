// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-refresh/deadline.ts
// Deadline interno de segurança do processamento de UMA onda — correção pós-incidente
// (2026-08-21): o piloto real com WAVE_PAGE_CAP=30 estourou o wall-clock do próprio
// worker aos 150s (shutdown_reason="WallClockTime", confirmado via function_logs/
// function_edge_logs correlacionados pelo mesmo function_id — não foi apenas um timeout
// do cliente HTTP). Supabase/Mimikyu Labs está no plano Free (confirmado via Management
// API); JustTCG está no Starter Plan — os dois planos são distintos, e é o teto do worker
// do projeto Supabase que importa aqui. Run afetado:
// 6c2ca781-099d-4087-89bf-4cbd4818341c, preso em PROCESSING (requests_made=0, zero
// pricing_sync_run_call, 2401 pricing_observation e 1 pricing_product já persistidos
// antes do corte).
//
// Módulo puro — só compara timestamps já lidos pelo chamador (nenhum Date.now() direto
// aqui), para permanecer 100% testável com um relógio determinístico injetado. Produção
// (core.ts) usa Date.now como padrão quando nenhum relógio é informado.
//
// 110s escolhido com margem de segurança deliberada abaixo dos ~150s observados no
// incidente real — nunca deve ser aumentado sem reconfirmar o teto real da plataforma via
// Management API/logs, e nunca deve chegar perto dele. A verificação acontece SEMPRE
// "entre Sets" (nunca no meio do processamento de um Set) — ver core.ts,
// executePriceRefreshWave: o topo de cada iteração do laço por Set decide, antes de
// iniciar qualquer trabalho novo, se ainda há orçamento de tempo para começar o próximo
// Set.

export const WAVE_INTERNAL_DEADLINE_MS = 110_000;

// Relógio injetável — mesmo padrão de FetchLike em _shared/pricing-justtcg/types.ts:
// produção usa uma função real (Date.now), testes injetam uma função determinística
// (fake incremental ou fixa), nunca mockam o objeto global Date.
export type Clock = () => number;

export function hasExceededDeadline(
  startedAtMs: number,
  clock: Clock,
  deadlineMs: number = WAVE_INTERNAL_DEADLINE_MS,
): boolean {
  return clock() - startedAtMs >= deadlineMs;
}
