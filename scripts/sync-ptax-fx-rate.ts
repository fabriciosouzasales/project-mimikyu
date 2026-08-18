/*
Project Mimikyu
Script administrativo standalone: sync-ptax-fx-rate
Incremento P13.2 — Módulo compartilhado e execução manual auditável da PTAX (2026-08-18).

Reescrita completa sobre o mesmo precedente estrutural do Incremento P9 (mesmo arquivo,
mesmo objetivo: primeiro fluxo real de ingestão de câmbio, buscando a cotação diária PTAX
USD->BRL na API oficial e pública do Banco Central e persistindo append-only em
pricing_fx_rate) — o que muda nesta rodada é ONDE a lógica mora e o QUANTO de disciplina de
execução agora envolve pricing_sync_run/pricing_sync_run_call, run_type='FX_REFRESH'.

Toda a lógica de negócio (cálculo de período, URL, HTTP com retry, validação/normalização,
seleção de fechamento, comparação com taxas existentes, persistência idempotente) foi
extraída para supabase/functions/_shared/pricing-ptax/ (núcleo puro, sem I/O de ambiente) —
este arquivo agora é só o ADAPTER MANUAL: cria o cliente Supabase real, lê variáveis de
ambiente, orquestra pricing_sync_run/pricing_sync_run_call, e chama runPtaxSync() do núcleo
compartilhado. Nenhuma lógica de negócio é duplicada aqui — a mesma função runPtaxSync()
será reaproveitada por uma futura Edge Function agendada (P13.3+), sem reescrever nada.

Arquitetura (decisão registrada, não uma Edge Function ainda): mesmo precedente de
scripts/sync-justtcg-pricing.ts — roda localmente, sob demanda, com a Service Role Key do
projeto, nunca é implantado no Supabase. "Acionado manualmente por administrador" aqui
significa que é o próprio administrador (Fabrício) quem executa este script na sua máquina.

Credencial: a API Olinda PTAX do Banco Central continua pública, sem API key. A única
credencial em jogo é a Service Role Key do Supabase (SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY),
exclusivamente por variável de ambiente, nunca argumento de linha de comando, nunca logada.

Novidades desta rodada (P13.2):
  - Janela padrão passa a ser CALCULADA (10 datas corridas terminando hoje, America/Sao_
    Paulo), não mais hardcoded — override explícito via --override-start=/--override-end=
    permite backfill manual controlado (ver MAX_OVERRIDE_WINDOW_DAYS em period.ts).
  - Execução com escrita real exige --confirmed-by=<admin_user_uuid>, exatamente como o
    conector JustTCG (P8) — a mesma trigger validate_pricing_sync_run_confirmed_by() valida
    o UUID contra admin_user.
  - Toda execução real (não dry-run) abre um pricing_sync_run com run_type='FX_REFRESH',
    triggered_by='MANUAL', pricing_source_id=NULL, fx_source_code='BCB_PTAX' — e cada
    tentativa de chamada HTTP ao BCB (incluindo retries) é registrada em
    pricing_sync_run_call, mesma disciplina de telemetria já usada pela JustTCG.
  - Concorrência: antes de qualquer chamada ao BCB, o script tenta abrir o
    pricing_sync_run — se outra execução FX_REFRESH já estiver ativa (RECEIVED/
    PROCESSING), o índice único parcial ux_pricing_sync_run_active_fx_per_source_type
    (Query 3907) rejeita o INSERT com o código Postgres 23505, e o script aborta
    IMEDIATAMENTE, sem nunca chegar a tocar a rede do BCB.
  - Retry: até 3 tentativas por chamada HTTP, esperas de 1s/3s, só para falha de
    rede/timeout/408/429/5xx — implementado no núcleo compartilhado (http.ts), não aqui.
  - Divergência (taxa já existente e diferente da recebida) nunca sobrescreve a linha
    existente — é reportada em pricing_sync_run.error_summary, nunca cria uma linha
    artificial em pricing_sync_run_call (essa tabela só registra chamadas HTTP reais).

Uso:

  # PowerShell — defina as variáveis de ambiente ANTES de rodar. NUNCA cole a Service
  # Role Key em chat/log.
  $env:SUPABASE_URL = "https://qjfutqujxrbzgrtkpgkg.supabase.co"
  $env:SUPABASE_SERVICE_ROLE_KEY = "<service_role_key>"

  # Validação offline (sempre segura, roda a bateria completa de testes do núcleo
  # compartilhado + as decisões de orquestração deste adapter, nenhuma rede, nenhuma
  # escrita no Supabase):
  deno run --allow-env scripts/sync-ptax-fx-rate.ts --fixture-check

  # Execução real, janela padrão (10 dias corridos terminando hoje):
  deno run --allow-net --allow-env scripts/sync-ptax-fx-rate.ts --confirmed-by=<admin_user_uuid>

  # Execução real, sem gravar nada (mesma Convenção #7 do projeto — validar antes de
  # executar; ainda assim NÃO cria pricing_sync_run/pricing_sync_run_call em dry-run):
  deno run --allow-net --allow-env scripts/sync-ptax-fx-rate.ts --confirmed-by=<admin_user_uuid> --dry-run

  # Backfill manual controlado (override explícito, máximo 90 dias — MAX_OVERRIDE_WINDOW_DAYS):
  deno run --allow-net --allow-env scripts/sync-ptax-fx-rate.ts --confirmed-by=<admin_user_uuid> --override-start=2026-07-01 --override-end=2026-07-31
*/

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import {
  buildErrorSummary,
  classifyStartAttempt,
  decideFinalStatus,
  type FinalSyncRunStatus,
  type PtaxCallLogEntry,
  type PtaxRate,
  type PtaxRateRepository,
  runPtaxSync,
  sanitize,
} from "../supabase/functions/_shared/pricing-ptax/mod.ts";
import {
  runPricingPtaxAsyncTests,
  runPricingPtaxTests,
} from "../supabase/functions/_shared/pricing-ptax/pricing-ptax.test.ts";

// ============================================================================
// 0. Identidade fixa da fonte cambial (P13.1 — fx_source_code, não mais só um
//    DEFAULT de coluna) e parâmetros de rede.
// ============================================================================

const FROM_CURRENCY = "USD";
const TO_CURRENCY = "BRL";
const RATE_SOURCE_CODE = "BCB_PTAX"; // pricing_fx_rate.rate_source_code E pricing_sync_run.fx_source_code
const REQUEST_TIMEOUT_MS = 15_000;

// ============================================================================
// 1. Args e ambiente
// ============================================================================

interface ParsedArgs {
  dryRun: boolean;
  fixtureCheck: boolean;
  confirmedBy: string | null;
  overrideStart: string | null;
  overrideEnd: string | null;
}

export function parseArgs(argv: string[]): ParsedArgs {
  const args: ParsedArgs = {
    dryRun: false,
    fixtureCheck: false,
    confirmedBy: null,
    overrideStart: null,
    overrideEnd: null,
  };
  for (const arg of argv) {
    if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--fixture-check") args.fixtureCheck = true;
    else if (arg.startsWith("--confirmed-by=")) {
      args.confirmedBy = arg.slice("--confirmed-by=".length);
    } else if (arg.startsWith("--override-start=")) {
      args.overrideStart = arg.slice("--override-start=".length);
    } else if (arg.startsWith("--override-end=")) {
      args.overrideEnd = arg.slice("--override-end=".length);
    }
  }
  return args;
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    console.error(`Variável de ambiente obrigatória ausente: ${name}`);
    Deno.exit(1);
  }
  return value;
}

// Data civil (YYYY-MM-DD) de America/Sao_Paulo — nunca o fuso do processo local. O
// núcleo compartilhado nunca lê o relógio do sistema diretamente (ver core.ts); é
// este adapter quem resolve "hoje" e passa como referenceDate.
export function computeReferenceDateSaoPaulo(now: Date): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  return formatter.format(now); // en-CA formata como YYYY-MM-DD diretamente
}

// ============================================================================
// 2. Repositório real (adapter sobre pricing_fx_rate) — implementa o contrato
//    PtaxRateRepository exigido pelo núcleo. Mesmo padrão .upsert(...,
//    { ignoreDuplicates: true }).select() já corrigido e validado no Incremento P9
//    (ON CONFLICT DO NOTHING real, nunca um UPDATE).
// ============================================================================

function buildSupabaseRepository(supabase: SupabaseClient): PtaxRateRepository {
  return {
    async findExistingRates(dates) {
      const result = new Map<string, number>();
      if (dates.length === 0) return result;
      const { data, error } = await supabase
        .from("pricing_fx_rate")
        .select("rate_date, rate")
        .eq("from_currency", FROM_CURRENCY)
        .eq("to_currency", TO_CURRENCY)
        .eq("rate_source_code", RATE_SOURCE_CODE)
        .in("rate_date", dates);
      if (error) {
        throw new Error(
          `PRICING_FX_RATE_QUERY_FAILED: ${sanitize(error.message)}`,
        );
      }
      for (const row of data ?? []) {
        result.set(row.rate_date as string, Number(row.rate));
      }
      return result;
    },
    async insertRate(entry: PtaxRate) {
      const { data, error } = await supabase
        .from("pricing_fx_rate")
        .upsert(
          {
            from_currency: FROM_CURRENCY,
            to_currency: TO_CURRENCY,
            rate: entry.rate,
            rate_date: entry.rateDate,
            rate_source_code: RATE_SOURCE_CODE,
          },
          {
            onConflict: "from_currency,to_currency,rate_source_code,rate_date",
            ignoreDuplicates: true,
          },
        )
        .select("rate_date");
      if (error) {
        throw new Error(
          `PRICING_FX_RATE_UPSERT_FAILED(${entry.rateDate}): ${
            sanitize(error.message)
          }`,
        );
      }
      return (data?.length ?? 0) > 0 ? "INSERTED" : "CONFLICT_IGNORED";
    },
  };
}

// ============================================================================
// 3. Orquestração de pricing_sync_run/pricing_sync_run_call
// ============================================================================

async function tryStartSyncRun(
  supabase: SupabaseClient,
  confirmedBy: string,
): Promise<
  | { status: "STARTED"; syncRunId: string }
  | { status: "CONCURRENT_CONFLICT" }
  | { status: "OTHER_ERROR"; detail: string }
> {
  // Único INSERT desta execução que pode colidir com o índice único parcial de
  // concorrência (ux_pricing_sync_run_active_fx_per_source_type, Query 3907) — de
  // propósito o PRIMEIRO efeito colateral do script, ANTES de qualquer fetch ao BCB.
  //
  // started_at NUNCA é enviado por este adapter (correção Query 3909, 2026-08-18): o
  // relógio do processo cliente (máquina local) provou-se divergente do relógio do
  // servidor na auditoria pós-piloto — o trigger trg_pricing_sync_run_server_timestamps
  // agora é a única autoridade sobre started_at, atribuindo sempre now() do próprio
  // Postgres. Mesmo que este INSERT enviasse um valor, o trigger o substituiria.
  const { data, error } = await supabase
    .from("pricing_sync_run")
    .insert({
      pricing_source_id: null,
      run_type: "FX_REFRESH",
      status: "PROCESSING",
      triggered_by: "MANUAL",
      confirmed_by: confirmedBy,
      fx_source_code: RATE_SOURCE_CODE,
    })
    .select("id")
    .single();

  const outcome = classifyStartAttempt(
    error
      ? { code: (error as { code?: string }).code, message: error.message }
      : null,
  );
  if (outcome === "CONCURRENT_CONFLICT") {
    return { status: "CONCURRENT_CONFLICT" };
  }
  if (outcome === "OTHER_ERROR") {
    return {
      status: "OTHER_ERROR",
      detail: sanitize((error as { message: string }).message) ??
        "ERRO_DESCONHECIDO",
    };
  }
  return { status: "STARTED", syncRunId: (data as { id: string }).id };
}

// Persiste pricing_sync_run_call ANTES de qualquer finalização do run (correção Query
// 3909/reordenação de telemetria, 2026-08-18) — um run só pode assumir status terminal
// depois de sua telemetria de chamadas já estar gravada. Devolve o resultado da tentativa
// em vez de lançar, para que o chamador decida como finalizar o run (nunca como
// COMPLETED se isto falhar).
async function persistCallLog(
  supabase: SupabaseClient,
  syncRunId: string,
  callLog: PtaxCallLogEntry[],
): Promise<{ ok: true } | { ok: false; detail: string }> {
  if (callLog.length === 0) return { ok: true };

  const { error } = await supabase.from("pricing_sync_run_call").insert(
    callLog.map((c: PtaxCallLogEntry) => ({
      sync_run_id: syncRunId,
      sequence_number: c.sequenceNumber,
      endpoint: c.endpoint,
      http_status_code: c.httpStatusCode,
      // outcome de pricing_sync_run_call só aceita SUCCESS/TECHNICAL_FAILURE/
      // BUDGET_STOPPED (ck_pricing_sync_run_call_outcome) — PTAX nunca usa
      // BUDGET_STOPPED (sem orçamento de requisições), então o mapeamento é direto.
      outcome: c.outcome,
      // Nunca distorcido por divergência de dado — error_detail aqui é sempre o
      // resultado bruto da CHAMADA HTTP em si (sucesso ou falha técnica), nunca
      // uma reformulação por causa de um achado de persistência (requisito #7).
      error_detail: c.errorDetail ? sanitize(c.errorDetail) : null,
      api_requests_remaining: c.apiRequestsRemaining,
    })),
  );

  if (error) {
    return {
      ok: false,
      detail: sanitize(error.message) ?? "ERRO_DESCONHECIDO",
    };
  }
  return { ok: true };
}

// Finaliza pricing_sync_run com um status JÁ DECIDIDO pelo chamador — nunca decide
// sozinho se o resultado "merece" COMPLETED, exatamente para que a regra "calls
// persistidas antes de COMPLETED" (requisito #4) fique explícita no ponto de chamada,
// não escondida aqui dentro.
//
// finished_at NUNCA é enviado por este adapter (correção Query 3909, 2026-08-18): o
// trigger trg_pricing_sync_run_server_timestamps é a única autoridade sobre finished_at,
// atribuindo now() do servidor na primeira transição para um status terminal e
// preservando o valor já gravado em qualquer atualização posterior de um run já terminal.
async function finalizeSyncRun(
  supabase: SupabaseClient,
  syncRunId: string,
  status: FinalSyncRunStatus,
  errorSummary: string | null,
  requestsMade: number,
  rateLimitHits: number,
  dryRun: boolean,
): Promise<void> {
  if (dryRun) return; // dry-run nunca cria nem finaliza pricing_sync_run/pricing_sync_run_call

  await supabase
    .from("pricing_sync_run")
    .update({
      status,
      requests_made: requestsMade,
      requests_remaining_at_end: null, // BCB não expõe orçamento de requisições
      rate_limit_hits: rateLimitHits,
      error_summary: errorSummary ? sanitize(errorSummary) : null,
    })
    .eq("id", syncRunId);
}

// ============================================================================
// 3b. Fake mínimo de client Supabase — só para exercitar a ORQUESTRAÇÃO deste
//     adapter (tryStartSyncRun/persistCallLog/finalizeSyncRun) 100% offline no
//     --fixture-check. Nunca substitui os testes do núcleo compartilhado
//     (pricing-ptax.test.ts), que já cobrem toda a lógica de negócio real via
//     fakes de fetch/repositório — este fake só grava QUAIS colunas cada
//     insert/update tentou gravar e EM QUE ORDEM, para provar (correção Query
//     3909/reordenação de telemetria, 2026-08-18): (1) started_at nunca é
//     enviado no INSERT de pricing_sync_run; (2) finished_at nunca é enviado no
//     UPDATE de pricing_sync_run; (3) pricing_sync_run_call é sempre persistida
//     ANTES do UPDATE que finaliza o run; (4) falha ao persistir calls nunca
//     termina como COMPLETED.
// ============================================================================

interface FakeRecordedCall {
  table: string;
  op: "insert" | "update";
  payload: Record<string, unknown>;
}

function buildFakeSupabaseForOrchestrationTests(
  recorded: FakeRecordedCall[],
  opts: { failCallInsert?: boolean } = {},
) {
  return {
    from(table: string) {
      return {
        insert(payload: Record<string, unknown> | Record<string, unknown>[]) {
          const single = Array.isArray(payload) ? payload[0] ?? {} : payload;
          recorded.push({ table, op: "insert", payload: single });
          const shouldFail = table === "pricing_sync_run_call" &&
            opts.failCallInsert === true;
          const outcome = shouldFail
            ? { data: null, error: { message: "INSERT_FALHOU_SIMULADO" } }
            : { data: { id: "fake-sync-run-id" }, error: null };
          return {
            select: (_cols: string) => ({
              single: () => Promise.resolve(outcome),
            }),
            then: (
              onFulfilled: (v: typeof outcome) => unknown,
              onRejected?: (e: unknown) => unknown,
            ) => Promise.resolve(outcome).then(onFulfilled, onRejected),
          };
        },
        update(payload: Record<string, unknown>) {
          recorded.push({ table, op: "update", payload });
          return {
            eq: (_c: string, _v: string) => Promise.resolve({ error: null }),
          };
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
}

// ============================================================================
// 4. Fixture-check — 100% offline: roda a bateria completa do núcleo compartilhado
//    (46 asserções, ver pricing-ptax.test.ts) + as decisões específicas deste adapter
//    (parseArgs, computeReferenceDateSaoPaulo, orquestração de timestamps/telemetria).
// ============================================================================

function runFixtureCheck() {
  console.log(
    "=== MODO FIXTURE-CHECK (offline, sem rede, sem escrita no Supabase) ===\n",
  );
  console.log("--- Bateria do núcleo compartilhado (_shared/pricing-ptax) ---");

  const syncTests = runPricingPtaxTests();
  for (const [label, ok] of syncTests.assertions) {
    console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
  }

  return runPricingPtaxAsyncTests().then(async (asyncTests) => {
    for (const [label, ok] of asyncTests.assertions) {
      console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
    }

    console.log("\n--- Decisões específicas deste adapter ---");
    const localAssertions: Array<[string, boolean]> = [];
    const assert = (label: string, cond: boolean) =>
      localAssertions.push([label, cond]);

    const argsDryRun = parseArgs([
      "--dry-run",
      "--confirmed-by=abc-123",
      "--override-start=2026-01-01",
      "--override-end=2026-01-10",
    ]);
    assert(
      "parseArgs: reconhece --dry-run, --confirmed-by=, --override-start=/--override-end= juntos",
      argsDryRun.dryRun && argsDryRun.confirmedBy === "abc-123" &&
        argsDryRun.overrideStart === "2026-01-01" &&
        argsDryRun.overrideEnd === "2026-01-10",
    );

    const argsVazio = parseArgs([]);
    assert(
      "parseArgs: sem argumentos -> tudo no default (dryRun=false, confirmedBy=null)",
      !argsVazio.dryRun && argsVazio.confirmedBy === null &&
        argsVazio.overrideStart === null,
    );

    const referencia = computeReferenceDateSaoPaulo(
      new Date("2026-08-18T02:30:00Z"),
    ); // 2026-08-17 23:30 em America/Sao_Paulo (UTC-3)
    assert(
      "computeReferenceDateSaoPaulo: 02:30 UTC vira 17/08 em America/Sao_Paulo (UTC-3), nunca a data UTC",
      referencia === "2026-08-17",
    );

    // ── Autoridade temporal do servidor e ordem da telemetria (Query 3909, 2026-08-18) ──
    {
      // (a) tryStartSyncRun nunca envia started_at — autoridade é o trigger do banco.
      const recordedA: FakeRecordedCall[] = [];
      const fakeA = buildFakeSupabaseForOrchestrationTests(recordedA);
      await tryStartSyncRun(fakeA, "fake-admin-id");
      const insertRunPayload = recordedA.find(
        (c) => c.table === "pricing_sync_run" && c.op === "insert",
      )?.payload;
      assert(
        "tryStartSyncRun: INSERT em pricing_sync_run nunca envia started_at (autoridade do servidor via trigger, Query 3909)",
        insertRunPayload !== undefined && !("started_at" in insertRunPayload),
      );

      // (b) finalizeSyncRun nunca envia finished_at — mesma autoridade do trigger.
      const recordedB: FakeRecordedCall[] = [];
      const fakeB = buildFakeSupabaseForOrchestrationTests(recordedB);
      await finalizeSyncRun(
        fakeB,
        "fake-sync-run-id",
        "COMPLETED",
        null,
        1,
        0,
        false,
      );
      const updateRunPayload = recordedB.find(
        (c) => c.table === "pricing_sync_run" && c.op === "update",
      )?.payload;
      assert(
        "finalizeSyncRun: UPDATE em pricing_sync_run nunca envia finished_at (autoridade do servidor via trigger, Query 3909)",
        updateRunPayload !== undefined && !("finished_at" in updateRunPayload),
      );

      // (c) ordem da telemetria: calls são persistidas ANTES da finalização do run.
      const recordedC: FakeRecordedCall[] = [];
      const fakeC = buildFakeSupabaseForOrchestrationTests(recordedC);
      const oneCall: PtaxCallLogEntry[] = [{
        sequenceNumber: 1,
        endpoint: "CotacaoDolarPeriodo",
        httpStatusCode: 200,
        outcome: "SUCCESS",
        errorDetail: null,
        apiRequestsRemaining: null,
      }];
      await persistCallLog(fakeC, "fake-sync-run-id", oneCall);
      await finalizeSyncRun(
        fakeC,
        "fake-sync-run-id",
        "COMPLETED",
        null,
        1,
        0,
        false,
      );
      const callInsertIndex = recordedC.findIndex(
        (c) => c.table === "pricing_sync_run_call" && c.op === "insert",
      );
      const runUpdateIndex = recordedC.findIndex(
        (c) => c.table === "pricing_sync_run" && c.op === "update",
      );
      assert(
        "ordem da telemetria: pricing_sync_run_call é persistida ANTES do UPDATE que finaliza pricing_sync_run",
        callInsertIndex !== -1 && runUpdateIndex !== -1 &&
          callInsertIndex < runUpdateIndex,
      );

      // (d) falha ao persistir calls nunca termina como COMPLETED — mesmo padrão de
      // decisão usado em runRealExecution (persistCallLog reporta ok:false, o
      // chamador finaliza como FAILED, nunca prossegue para decideFinalStatus()).
      const recordedD: FakeRecordedCall[] = [];
      const fakeD = buildFakeSupabaseForOrchestrationTests(recordedD, {
        failCallInsert: true,
      });
      const callPersistResult = await persistCallLog(
        fakeD,
        "fake-sync-run-id",
        oneCall,
      );
      assert(
        "persistCallLog: reporta ok:false quando o INSERT de pricing_sync_run_call falha",
        callPersistResult.ok === false,
      );
      if (!callPersistResult.ok) {
        await finalizeSyncRun(
          fakeD,
          "fake-sync-run-id",
          "FAILED",
          `PRICING_SYNC_RUN_CALL_INSERT_FAILED: ${callPersistResult.detail}`,
          1,
          0,
          false,
        );
      }
      const finalUpdatePayloadD = recordedD
        .filter((c) => c.table === "pricing_sync_run" && c.op === "update")
        .at(-1)?.payload;
      const finalStatusD = finalUpdatePayloadD?.status;
      assert(
        "falha ao persistir calls nunca termina como COMPLETED — finaliza como FAILED",
        Object.is(finalStatusD, "FAILED") &&
          !Object.is(finalStatusD, "COMPLETED"),
      );
    }

    for (const [label, ok] of localAssertions) {
      console.log(`  [${ok ? "OK" : "FALHOU"}] ${label}`);
    }

    const todas = [
      ...syncTests.assertions,
      ...asyncTests.assertions,
      ...localAssertions,
    ];
    const falharam = todas.filter(([, ok]) => !ok);
    console.log(
      `\n${
        falharam.length === 0
          ? "TODAS as asserções passaram"
          : `${falharam.length} asserção(ões) FALHARAM`
      } (${todas.length} no total).`,
    );
    console.log(
      "\nNenhuma chamada de rede foi feita. Nenhuma linha foi gravada no Supabase.",
    );
    console.log(
      "Piloto real NÃO executado nesta rodada — variáveis do Supabase ausentes ou --fixture-check pedido explicitamente.",
    );

    if (falharam.length > 0) Deno.exit(1);
  });
}

// ============================================================================
// 5. Execução real
// ============================================================================

async function runRealExecution(args: ParsedArgs) {
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const supabaseServiceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

  const referenceDate = computeReferenceDateSaoPaulo(new Date());
  console.log(`Data de referência (America/Sao_Paulo): ${referenceDate}`);
  if (args.overrideStart || args.overrideEnd) {
    console.log(
      `Override de período solicitado: ${args.overrideStart ?? "?"} a ${
        args.overrideEnd ?? "?"
      } (backfill manual controlado)`,
    );
  }
  if (args.dryRun) {
    console.log(
      "[DRY-RUN] Nenhuma escrita será persistida — nem em pricing_fx_rate, nem em pricing_sync_run/pricing_sync_run_call.\n",
    );
  }

  let syncRunId: string | null = null;
  let syncRunFinalized = false;

  try {
    if (!args.dryRun) {
      if (!args.confirmedBy) {
        console.error(
          "Execução real (sem --dry-run) requer --confirmed-by=<admin_user_uuid> (id de um administrador real em admin_user).",
        );
        Deno.exit(1);
      }

      const startAttempt = await tryStartSyncRun(
        supabase,
        args.confirmedBy,
      );
      if (startAttempt.status === "CONCURRENT_CONFLICT") {
        console.error(
          "Já existe uma execução FX_REFRESH ativa (RECEIVED/PROCESSING) para BCB_PTAX — abortando ANTES de qualquer chamada ao Banco Central (concorrência detectada via índice único parcial, Query 3907).",
        );
        Deno.exit(1);
      }
      if (startAttempt.status === "OTHER_ERROR") {
        console.error(
          `Falha ao abrir pricing_sync_run: ${startAttempt.detail}`,
        );
        Deno.exit(1);
      }
      syncRunId = startAttempt.syncRunId;
      console.log(
        `pricing_sync_run aberto: ${syncRunId} (run_type=FX_REFRESH, triggered_by=MANUAL, confirmed_by=${args.confirmedBy})`,
      );
    }

    const repository = buildSupabaseRepository(supabase);
    const result = await runPtaxSync({
      referenceDate,
      overrideStartDate: args.overrideStart ?? undefined,
      overrideEndDate: args.overrideEnd ?? undefined,
      fetchImpl: fetch,
      waitImpl: (ms: number) => new Promise((r) => setTimeout(r, ms)),
      repository,
      dryRun: args.dryRun,
      timeoutMs: REQUEST_TIMEOUT_MS,
    });

    if (syncRunId) {
      // Requisito #4 (reordenação de telemetria, 2026-08-18): a telemetria de chamadas
      // (pricing_sync_run_call) é persistida ANTES de qualquer finalização do run — um
      // run só pode assumir status terminal depois de sua telemetria já estar gravada.
      const callPersist = await persistCallLog(
        supabase,
        syncRunId,
        result.callLog,
      );
      const rateLimitHits = result.callLog.filter((c) =>
        c.httpStatusCode === 429
      ).length;

      if (!callPersist.ok) {
        // Falha ao persistir as calls NUNCA pode terminar como COMPLETED — finaliza
        // como FAILED, preservando sanitização de erros/segredos (mesma sanitize()
        // já usada em toda mensagem livre desta rodada).
        await finalizeSyncRun(
          supabase,
          syncRunId,
          "FAILED",
          sanitize(
            `PRICING_SYNC_RUN_CALL_INSERT_FAILED: ${callPersist.detail}`,
          ),
          result.callLog.length,
          rateLimitHits,
          args.dryRun,
        );
        syncRunFinalized = true;
        console.error(
          `Falha ao persistir pricing_sync_run_call — run finalizado como FAILED: ${callPersist.detail}`,
        );
        Deno.exit(1);
      }

      const status = decideFinalStatus(result);
      const errorSummary = buildErrorSummary(result);
      await finalizeSyncRun(
        supabase,
        syncRunId,
        status,
        errorSummary,
        result.callLog.length,
        rateLimitHits,
        args.dryRun,
      );
      syncRunFinalized = true;
    }

    console.log("\n=== Resultado da execução ===");
    if (
      result.kind === "TECHNICAL_FAILURE" ||
      result.kind === "FUNCTIONAL_FAILURE"
    ) {
      console.error(`${result.kind}: ${result.detail}`);
      Deno.exit(1);
    }

    console.log(
      `Período consultado: ${result.period.startDate} a ${result.period.endDate}`,
    );
    console.log(`Cotações recebidas do BCB: ${result.quotesReceived}`);
    console.log(JSON.stringify(result.counts, null, 2));
    if (result.divergences.length > 0) {
      console.log(
        `\nDivergências (taxa já existente mantida, NUNCA sobrescrita):`,
      );
      for (const d of result.divergences) {
        console.log(
          `  ${d.rateDate}: existente=${d.existingRate} recebido=${d.incomingRate}`,
        );
      }
    }
    if (result.invalidDetails.length > 0) {
      console.log(`\nItens inválidos ignorados:`);
      for (const inv of result.invalidDetails) {
        console.log(`  ${sanitize(inv.reason)}`);
      }
    }
  } catch (error) {
    if (syncRunId && !syncRunFinalized) {
      const message = error instanceof Error ? error.message : String(error);
      await finalizeSyncRun(
        supabase,
        syncRunId,
        "FAILED",
        sanitize(message) ?? "ERRO_DESCONHECIDO",
        0,
        0,
        args.dryRun,
      );
    }
    throw error;
  }
}

// ============================================================================
// 6. Entrypoint
// ============================================================================

async function main() {
  const args = parseArgs(Deno.args);
  const hasSupabaseEnv = !!Deno.env.get("SUPABASE_URL") &&
    !!Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (args.fixtureCheck || !hasSupabaseEnv) {
    if (!hasSupabaseEnv && !args.fixtureCheck) {
      console.log(
        "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes — executando automaticamente em modo --fixture-check.\n",
      );
    }
    await runFixtureCheck();
    return;
  }

  await runRealExecution(args);
}

if (import.meta.main) {
  await main();
}
