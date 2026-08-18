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

import { createClient } from "@supabase/supabase-js";
import {
  buildErrorSummary,
  buildPricingPtaxSupabaseAdapter,
  computeReferenceDateSaoPaulo,
  decideFinalStatus,
  finalizeSyncRun,
  persistCallLog,
  type PtaxCallLogEntry,
  type PtaxSyncRunPort,
  runPtaxSync,
  sanitize,
  type SyncRunTrigger,
  tryStartSyncRun,
  type UpdateSyncRunPatch,
} from "../supabase/functions/_shared/pricing-ptax/mod.ts";
import {
  runPricingPtaxAsyncTests,
  runPricingPtaxTests,
} from "../supabase/functions/_shared/pricing-ptax/pricing-ptax.test.ts";

// ============================================================================
// 0. Parâmetros de rede. A identidade fixa da fonte cambial (FROM_CURRENCY/
//    TO_CURRENCY/RATE_SOURCE_CODE) e o ciclo de vida de pricing_sync_run/
//    pricing_sync_run_call foram extraídos para _shared/pricing-ptax/run-lifecycle.ts
//    no Incremento P13.3 — reaproveitados aqui e pela Edge Function ptax-fx-refresh,
//    sem nenhuma lógica duplicada entre os dois chamadores.
// ============================================================================

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

// ============================================================================
// 2/3. Orquestração de pricing_sync_run/pricing_sync_run_call — reaproveitada de
//    _shared/pricing-ptax/run-lifecycle.ts (Incremento P13.3): tryStartSyncRun,
//    persistCallLog, finalizeSyncRun, computeReferenceDateSaoPaulo. O adapter real
//    (buildPricingPtaxSupabaseAdapter, correção estrutural de 2026-08-18) é
//    construído uma única vez em runRealExecution() e reaproveitado para tudo —
//    nenhuma lógica duplicada neste arquivo.
// ============================================================================

// ============================================================================
// 3b. Fake mínimo da PORTA (PtaxSyncRunPort) — só para exercitar a ORQUESTRAÇÃO
//     deste adapter (tryStartSyncRun/persistCallLog/finalizeSyncRun) 100% offline no
//     --fixture-check. Nunca um fake de SupabaseClient/PostgREST — implementa
//     diretamente a porta de domínio, mesma que o adapter real
//     (supabase-adapter.ts) implementa sobre o SupabaseClient. Nunca substitui os
//     testes do núcleo compartilhado (pricing-ptax.test.ts), que já cobrem toda a
//     lógica de negócio real via fakes de fetch/repositório — este fake só grava O
//     QUE cada operação da porta recebeu e EM QUE ORDEM, para provar (correção
//     Query 3909/reordenação de telemetria, 2026-08-18): (1) insertSyncRun é
//     chamado só com o SyncRunTrigger (sem timestamp — garantido em nível de tipo);
//     (2) updateSyncRun é chamado só com UpdateSyncRunPatch (sem timestamp — idem);
//     (3) insertSyncRunCalls é sempre chamado ANTES do updateSyncRun que finaliza o
//     run; (4) falha ao persistir calls nunca termina como COMPLETED.
// ============================================================================

interface FakeRecordedCall {
  op: "insertSyncRun" | "insertSyncRunCalls" | "updateSyncRun";
  payload: unknown;
}

function buildFakePricingPtaxPort(
  recorded: FakeRecordedCall[],
  opts: { failCallInsert?: boolean } = {},
): PtaxSyncRunPort {
  return {
    findExistingRates() {
      return Promise.resolve(new Map<string, number>());
    },
    insertRate() {
      return Promise.resolve("INSERTED");
    },
    insertSyncRun(trigger: SyncRunTrigger) {
      recorded.push({ op: "insertSyncRun", payload: trigger });
      return Promise.resolve(
        { outcome: "STARTED" as const, syncRunId: "fake-sync-run-id" },
      );
    },
    insertSyncRunCalls(syncRunId: string, callLog: PtaxCallLogEntry[]) {
      recorded.push({
        op: "insertSyncRunCalls",
        payload: { syncRunId, callLog },
      });
      if (opts.failCallInsert) {
        return Promise.resolve(
          { ok: false as const, message: "INSERT_FALHOU_SIMULADO" },
        );
      }
      return Promise.resolve({ ok: true as const });
    },
    updateSyncRun(syncRunId: string, patch: UpdateSyncRunPatch) {
      recorded.push({ op: "updateSyncRun", payload: { syncRunId, patch } });
      return Promise.resolve();
    },
  };
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
      // (a) tryStartSyncRun chama port.insertSyncRun só com o SyncRunTrigger — o tipo
      // não tem campo de timestamp algum, então started_at nunca poderia ser enviado
      // mesmo que este módulo tentasse (garantido em nível de tipo, não só testado).
      const recordedA: FakeRecordedCall[] = [];
      const fakeA = buildFakePricingPtaxPort(recordedA);
      await tryStartSyncRun(fakeA, {
        triggeredBy: "MANUAL",
        confirmedBy: "fake-admin-id",
      });
      const insertRunPayload = recordedA.find(
        (c) => c.op === "insertSyncRun",
      )?.payload as SyncRunTrigger | undefined;
      assert(
        "tryStartSyncRun: chama port.insertSyncRun com o trigger exato, sem campo de timestamp (started_at nunca é enviado — Query 3909)",
        insertRunPayload !== undefined &&
          insertRunPayload.triggeredBy === "MANUAL" &&
          Object.keys(insertRunPayload).sort().join(",") ===
            "confirmedBy,triggeredBy",
      );

      // (b) finalizeSyncRun chama port.updateSyncRun só com UpdateSyncRunPatch — sem
      // campo de timestamp algum, então finished_at nunca é enviado (mesma garantia
      // de tipo).
      const recordedB: FakeRecordedCall[] = [];
      const fakeB = buildFakePricingPtaxPort(recordedB);
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
        (c) => c.op === "updateSyncRun",
      )?.payload as
        | { syncRunId: string; patch: UpdateSyncRunPatch }
        | undefined;
      assert(
        "finalizeSyncRun: chama port.updateSyncRun só com status/errorSummary/requestsMade/rateLimitHits, sem campo de timestamp (finished_at nunca é enviado — Query 3909)",
        updateRunPayload !== undefined &&
          Object.keys(updateRunPayload.patch).sort().join(",") ===
            "errorSummary,rateLimitHits,requestsMade,status",
      );

      // (c) ordem da telemetria: calls são persistidas ANTES da finalização do run.
      const recordedC: FakeRecordedCall[] = [];
      const fakeC = buildFakePricingPtaxPort(recordedC);
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
        (c) => c.op === "insertSyncRunCalls",
      );
      const runUpdateIndex = recordedC.findIndex(
        (c) => c.op === "updateSyncRun",
      );
      assert(
        "ordem da telemetria: port.insertSyncRunCalls é chamado ANTES do port.updateSyncRun que finaliza o run",
        callInsertIndex !== -1 && runUpdateIndex !== -1 &&
          callInsertIndex < runUpdateIndex,
      );

      // (d) falha ao persistir calls nunca termina como COMPLETED — mesmo padrão de
      // decisão usado em runRealExecution (persistCallLog reporta ok:false, o
      // chamador finaliza como FAILED, nunca prossegue para decideFinalStatus()).
      const recordedD: FakeRecordedCall[] = [];
      const fakeD = buildFakePricingPtaxPort(recordedD, {
        failCallInsert: true,
      });
      const callPersistResult = await persistCallLog(
        fakeD,
        "fake-sync-run-id",
        oneCall,
      );
      assert(
        "persistCallLog: reporta ok:false quando port.insertSyncRunCalls falha",
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
        .filter((c) => c.op === "updateSyncRun")
        .at(-1)?.payload as { patch: UpdateSyncRunPatch } | undefined;
      const finalStatusD = finalUpdatePayloadD?.patch.status;
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
  // Adapter de infraestrutura construído UMA ÚNICA VEZ por execução — implementa
  // PtaxSyncRunPort sobre o SupabaseClient real, reaproveitado para tudo
  // (repositório de taxas + ciclo de vida do run). Mesma função usada pela Edge
  // Function agendada (ptax-fx-refresh/index.ts) — nenhuma query duplicada.
  const port = buildPricingPtaxSupabaseAdapter(supabase);

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

      const startAttempt = await tryStartSyncRun(port, {
        triggeredBy: "MANUAL",
        confirmedBy: args.confirmedBy,
      });
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

    const result = await runPtaxSync({
      referenceDate,
      overrideStartDate: args.overrideStart ?? undefined,
      overrideEndDate: args.overrideEnd ?? undefined,
      fetchImpl: fetch,
      waitImpl: (ms: number) => new Promise((r) => setTimeout(r, ms)),
      repository: port, // PtaxSyncRunPort estende PtaxRateRepository
      dryRun: args.dryRun,
      timeoutMs: REQUEST_TIMEOUT_MS,
    });

    if (syncRunId) {
      // Requisito #4 (reordenação de telemetria, 2026-08-18): a telemetria de chamadas
      // (pricing_sync_run_call) é persistida ANTES de qualquer finalização do run — um
      // run só pode assumir status terminal depois de sua telemetria já estar gravada.
      const callPersist = await persistCallLog(
        port,
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
          port,
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
        port,
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
        port,
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
