// Project Mimikyu — supabase/functions/ptax-fx-refresh/ptax-fx-refresh.test.ts
// Bateria de testes offline da Edge Function ptax-fx-refresh — Incremento P13.3
// (2026-08-18).
//
// 100% offline: nenhum teste aqui faz uma chamada de rede real ao BCB nem escreve no
// Supabase — fetch e cliente Supabase são sempre fakes controlados neste arquivo,
// mesmo padrão já usado em _shared/pricing-ptax/pricing-ptax.test.ts. Cobre os 11
// cenários obrigatórios desta rodada: método inválido; segredo ausente/incorreto/
// correto; comparação constant-time sem early return; autenticação antes de qualquer
// banco/rede; conflito impede BCB; sucesso; idempotência; divergência; falha técnica
// sanitizada; falha ao persistir call; nenhuma exposição de segredo.

import { handlePtaxFxRefreshRequest } from "./handler.ts";
import {
  extractProvidedSecret,
  isAuthorized,
  timingSafeEqual,
} from "./auth.ts";
import type {
  FetchLike,
  PtaxCallLogEntry,
  PtaxSyncRunPort,
  SyncRunTrigger,
  UpdateSyncRunPatch,
  WaitLike,
} from "../_shared/pricing-ptax/mod.ts";
import type { TestSuiteResult } from "../_shared/pricing-ptax/pricing-ptax.test.ts";

const EXPECTED_SECRET = "segredo-de-teste-ptax-fx-refresh-nao-real";

// ----------------------------------------------------------------------------
// Fake da PORTA (PtaxSyncRunPort) — nunca um fake de SupabaseClient/PostgREST.
// Implementa diretamente a mesma porta de domínio que o adapter real
// (supabase-adapter.ts) implementa sobre o SupabaseClient — nenhum `any`, nenhum
// tipo que reproduza a API fluente do PostgREST.
// ----------------------------------------------------------------------------

interface RecordedCall {
  op:
    | "findExistingRates"
    | "insertRate"
    | "insertSyncRun"
    | "insertSyncRunCalls"
    | "updateSyncRun";
  payload: unknown;
}

interface FakePortOptions {
  conflict?: boolean; // insertSyncRun -> CONCURRENT_CONFLICT (23505 no adapter real)
  startOtherError?: boolean; // insertSyncRun -> OTHER_ERROR
  failCallInsert?: boolean; // insertSyncRunCalls -> ok:false
  existingRows?: Array<{ rate_date: string; rate: number }>; // findExistingRates
  upsertInserted?: boolean; // insertRate -> INSERTED (true) ou CONFLICT_IGNORED (false)
}

function buildFakePort(
  recorded: RecordedCall[],
  opts: FakePortOptions = {},
): PtaxSyncRunPort {
  return {
    findExistingRates(dates: readonly string[]) {
      recorded.push({ op: "findExistingRates", payload: dates });
      const result = new Map<string, number>();
      for (const row of opts.existingRows ?? []) {
        result.set(row.rate_date, row.rate);
      }
      return Promise.resolve(result);
    },
    insertRate(entry) {
      recorded.push({ op: "insertRate", payload: entry });
      const inserted = opts.upsertInserted !== false;
      return Promise.resolve(inserted ? "INSERTED" : "CONFLICT_IGNORED");
    },
    insertSyncRun(trigger: SyncRunTrigger) {
      recorded.push({ op: "insertSyncRun", payload: trigger });
      if (opts.conflict) {
        return Promise.resolve({ outcome: "CONCURRENT_CONFLICT" as const });
      }
      if (opts.startOtherError) {
        return Promise.resolve({
          outcome: "OTHER_ERROR" as const,
          message: "ERRO_SIMULADO_INSERT",
        });
      }
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

// Resposta BCB fixture — 1 cotação em 2026-08-17, dentro da janela padrão (10 dias
// terminando em 2026-08-18, ver period.ts) para o `now` fixo usado nestes testes.
const FIXTURE_UMA_COTACAO = {
  value: [
    {
      cotacaoCompra: 5.4321,
      cotacaoVenda: 5.4327,
      dataHoraCotacao: "2026-08-17 13:04:41.123",
    },
  ],
};

function fakeFetchResponse(
  init: { ok: boolean; status: number; json?: unknown; text?: string },
): Response {
  return {
    ok: init.ok,
    status: init.status,
    json: () => Promise.resolve(init.json),
    text: () => Promise.resolve(init.text ?? ""),
  } as unknown as Response;
}

function successFetch(calls: { count: number }): FetchLike {
  return ((_url: string, _init?: RequestInit) => {
    calls.count++;
    return Promise.resolve(
      fakeFetchResponse({ ok: true, status: 200, json: FIXTURE_UMA_COTACAO }),
    );
  }) as FetchLike;
}

function technicalFailureFetch(calls: { count: number }): FetchLike {
  return ((_url: string, _init?: RequestInit) => {
    calls.count++;
    // 400 não é retryable (isRetryableStatus) — falha em 1 tentativa, teste rápido.
    return Promise.resolve(
      fakeFetchResponse({ ok: false, status: 400, text: "BAD_REQUEST" }),
    );
  }) as FetchLike;
}

function neverCalledFetch(calls: { count: number }): FetchLike {
  return ((_url: string, _init?: RequestInit) => {
    calls.count++;
    throw new Error("fetchImpl NUNCA deveria ser chamado neste cenário");
  }) as FetchLike;
}

const instantWait: WaitLike = (_ms: number) => Promise.resolve();

function buildRequest(
  opts: { method?: string; apikey?: string | null } = {},
): Request {
  const headers = new Headers();
  if (opts.apikey !== null) {
    headers.set("apikey", opts.apikey ?? EXPECTED_SECRET);
  }
  return new Request(
    "https://example.supabase.co/functions/v1/ptax-fx-refresh",
    {
      method: opts.method ?? "POST",
      headers,
    },
  );
}

const FIXED_NOW = new Date("2026-08-18T15:00:00Z"); // 12:00 America/Sao_Paulo, mesmo dia civil

export async function runPtaxFxRefreshTests(): Promise<TestSuiteResult> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) =>
    assertions.push([label, cond]);

  // ── 1. Método inválido ───────────────────────────────────────────────────
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ method: "GET" }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded),
        fetchImpl: neverCalledFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    const body = await res.json();
    assert("método inválido: GET -> 405", res.status === 405);
    assert(
      "método inválido: header Allow: POST",
      res.headers.get("Allow") === "POST",
    );
    assert(
      "método inválido: nenhum acesso a banco/rede",
      recorded.length === 0 && fetchCalls.count === 0,
    );
    assert(
      "método inválido: corpo não expõe segredo",
      JSON.stringify(body).includes(EXPECTED_SECRET) === false,
    );
  }

  // ── 2. Segredo ausente ───────────────────────────────────────────────────
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: null }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded),
        fetchImpl: neverCalledFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    assert("segredo ausente: 401", res.status === 401);
    assert(
      "segredo ausente: autenticação falha antes de qualquer banco/rede",
      recorded.length === 0 && fetchCalls.count === 0,
    );
  }

  // ── 3. Segredo incorreto ─────────────────────────────────────────────────
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: "valor-errado" }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded),
        fetchImpl: neverCalledFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    assert("segredo incorreto: 401", res.status === 401);
    assert(
      "segredo incorreto: autenticação falha antes de qualquer banco/rede",
      recorded.length === 0 && fetchCalls.count === 0,
    );
  }

  // ── 3b. expectedSecret ausente no ambiente (função mal configurada) nunca autoriza ──
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: null,
        port: buildFakePort(recorded),
        fetchImpl: neverCalledFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    assert(
      "expectedSecret ausente no ambiente: nunca autoriza (401), mesmo com apikey certo por coincidência",
      res.status === 401,
    );
  }

  // ── 4. Segredo correto — chega a acessar o banco (auth passou) ──────────
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded, { existingRows: [] }),
        fetchImpl: successFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    assert(
      "segredo correto: auth passa e chega a abrir pricing_sync_run",
      recorded.some((c) => c.op === "insertSyncRun"),
    );
  }

  // ── 5. Comparação constant-time sem early return (correção estrutural) ──
  {
    assert(
      "timingSafeEqual: strings iguais -> true",
      timingSafeEqual("abc123", "abc123"),
    );
    assert(
      "timingSafeEqual: difere no primeiro byte -> false",
      !timingSafeEqual("Xbc123", "abc123"),
    );
    assert(
      "timingSafeEqual: difere no último byte -> false",
      !timingSafeEqual("abc12X", "abc123"),
    );
    assert(
      "timingSafeEqual: comprimentos diferentes -> false",
      !timingSafeEqual("abc", "abc123"),
    );
    assert("timingSafeEqual: ambas vazias -> true", timingSafeEqual("", ""));
    assert(
      "timingSafeEqual: uma vazia -> false",
      !timingSafeEqual("", "abc123"),
    );
    // Nenhum destes casos passa por um early return dependente do CONTEÚDO — o único
    // "atalho" possível é o guard sobre AUSÊNCIA de valor em isAuthorized(), nunca
    // dentro de timingSafeEqual() (ver auth.ts: o laço sempre roda até maxLen).
    assert(
      "isAuthorized: guard de ausência não depende do conteúdo do segredo esperado",
      !isAuthorized(null, EXPECTED_SECRET) &&
        !isAuthorized("qualquer-coisa", null),
    );
    assert(
      "extractProvidedSecret: lê sempre o header apikey, nunca Authorization",
      extractProvidedSecret(
        new Request("https://x.test", {
          headers: { apikey: "v1", Authorization: "Bearer outro" },
        }),
      ) === "v1",
    );
  }

  // ── 6. (coberto também em 2/3 acima) autenticação antes de banco/rede — reforço com fetch instrumentado ──
  {
    const recorded: RecordedCall[] = [];
    let fetchWasCalled = false;
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: "errado-de-novo" }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded),
        fetchImpl: (() => {
          fetchWasCalled = true;
          return Promise.reject(new Error("não deveria ser chamado"));
        }) as FetchLike,
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    assert(
      "autenticação falha: fetch (BCB) nunca é invocado",
      !fetchWasCalled && res.status === 401,
    );
  }

  // ── 7. Conflito de concorrência impede BCB — 409 ────────────────────────
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded, { conflict: true }),
        fetchImpl: neverCalledFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    const body = await res.json();
    assert("conflito 23505: 409", res.status === 409);
    assert("conflito 23505: BCB nunca é chamado", fetchCalls.count === 0);
    assert(
      "conflito 23505: port.insertSyncRun chamado com trigger SCHEDULED — o variante SCHEDULED de SyncRunTrigger não tem campo confirmedBy algum, então confirmed_by=NULL fica garantido em nível de tipo (não só testado em runtime)",
      recorded.some((c) =>
        c.op === "insertSyncRun" &&
        (c.payload as SyncRunTrigger).triggeredBy === "SCHEDULED" &&
        !("confirmedBy" in (c.payload as SyncRunTrigger))
      ),
    );
    assert(
      "conflito 23505: corpo não expõe segredo",
      JSON.stringify(body).includes(EXPECTED_SECRET) === false,
    );
  }

  // ── 7b. Erro não-23505 ao abrir o run — 500, sem tocar o BCB ────────────
  {
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort([], { startOtherError: true }),
        fetchImpl: neverCalledFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    assert(
      "erro não-23505 ao abrir run: 500 e nunca chama o BCB",
      res.status === 500 && fetchCalls.count === 0,
    );
  }

  // ── 8. Sucesso — taxa nova, uma chamada ao BCB ──────────────────────────
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded, { existingRows: [] }),
        fetchImpl: successFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    const body = await res.json();
    assert("sucesso: 200", res.status === 200);
    assert(
      "sucesso: success=true e status=COMPLETED",
      body.success === true && body.status === "COMPLETED",
    );
    assert("sucesso: counts.inserted=1", body.counts?.inserted === 1);
    assert("sucesso: uma única chamada ao BCB", fetchCalls.count === 1);
    assert(
      "sucesso: port.insertSyncRunCalls chamado ANTES do port.updateSyncRun que finaliza o run",
      (() => {
        const callIdx = recorded.findIndex((c) =>
          c.op === "insertSyncRunCalls"
        );
        const updateIdx = recorded.findIndex((c) => c.op === "updateSyncRun");
        return callIdx !== -1 && updateIdx !== -1 && callIdx < updateIdx;
      })(),
    );
    const finalUpdate = recorded.filter((c) => c.op === "updateSyncRun")
      .at(-1)?.payload as
        | { syncRunId: string; patch: UpdateSyncRunPatch }
        | undefined;
    assert(
      "sucesso: run finalizado como COMPLETED",
      finalUpdate?.patch.status === "COMPLETED",
    );
    assert(
      "sucesso: patch de updateSyncRun só tem status/errorSummary/requestsMade/rateLimitHits — sem campo de timestamp (finished_at nunca é enviado, garantido em nível de tipo)",
      finalUpdate !== undefined &&
        Object.keys(finalUpdate.patch).sort().join(",") ===
          "errorSummary,rateLimitHits,requestsMade,status",
    );
  }

  // ── 9. Idempotência — taxa já existe e é igual ──────────────────────────
  {
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort([], {
          existingRows: [{ rate_date: "2026-08-17", rate: 5.4327 }],
        }),
        fetchImpl: successFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    const body = await res.json();
    assert("idempotência: 200", res.status === 200);
    assert(
      "idempotência: status=COMPLETED (não WITH_ERRORS)",
      body.status === "COMPLETED",
    );
    assert(
      "idempotência: counts.unchanged=1, inserted=0",
      body.counts?.unchanged === 1 && body.counts?.inserted === 0,
    );
  }

  // ── 10. Divergência — taxa já existe e é diferente ──────────────────────
  {
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort([], {
          existingRows: [{ rate_date: "2026-08-17", rate: 5.9999 }],
        }),
        fetchImpl: successFetch({ count: 0 }),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    const body = await res.json();
    assert(
      "divergência: 200 (mesmo com divergência, execução HTTP é bem-sucedida)",
      res.status === 200,
    );
    assert(
      "divergência: status=COMPLETED_WITH_ERRORS",
      body.status === "COMPLETED_WITH_ERRORS",
    );
    assert(
      "divergência: counts.divergent=1, nunca sobrescreve (unchanged/inserted=0)",
      body.counts?.divergent === 1 && body.counts?.inserted === 0 &&
        body.counts?.unchanged === 0,
    );
  }

  // ── 11. Falha técnica — sanitizada, nunca detalhe cru na resposta ───────
  {
    const recorded: RecordedCall[] = [];
    const fetchCalls = { count: 0 };
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded),
        fetchImpl: technicalFailureFetch(fetchCalls),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    const bodyText = await res.text();
    const body = JSON.parse(bodyText);
    assert("falha técnica: 500", res.status === 500);
    assert(
      "falha técnica: código de erro fixo, nunca o texto cru (BAD_REQUEST)",
      body.error === "SYNC_EXECUTION_FAILED" &&
        !bodyText.includes("BAD_REQUEST"),
    );
    const finalUpdate = recorded.filter((c) => c.op === "updateSyncRun")
      .at(-1)?.payload as
        | { syncRunId: string; patch: UpdateSyncRunPatch }
        | undefined;
    assert(
      "falha técnica: run finalizado como FAILED",
      finalUpdate?.patch.status === "FAILED",
    );
  }

  // ── 12. Falha ao persistir pricing_sync_run_call — nunca termina COMPLETED ──
  {
    const recorded: RecordedCall[] = [];
    const res = await handlePtaxFxRefreshRequest(
      buildRequest({ apikey: EXPECTED_SECRET }),
      {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort(recorded, {
          failCallInsert: true,
          existingRows: [],
        }),
        fetchImpl: successFetch({ count: 0 }),
        waitImpl: instantWait,
        now: FIXED_NOW,
      },
    );
    const body = await res.json();
    assert(
      "falha ao persistir call: 500, error=CALL_LOG_PERSIST_FAILED",
      res.status === 500 && body.error === "CALL_LOG_PERSIST_FAILED",
    );
    const finalUpdate = recorded.filter((c) => c.op === "updateSyncRun")
      .at(-1)?.payload as
        | { syncRunId: string; patch: UpdateSyncRunPatch }
        | undefined;
    assert(
      "falha ao persistir call: run finaliza como FAILED, nunca COMPLETED",
      finalUpdate?.patch.status === "FAILED",
    );
  }

  // ── 13. Nenhuma exposição de segredo em nenhuma resposta ────────────────
  {
    const scenarios = await Promise.all([
      handlePtaxFxRefreshRequest(buildRequest({ method: "DELETE" }), {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort([]),
        fetchImpl: neverCalledFetch({ count: 0 }),
        waitImpl: instantWait,
        now: FIXED_NOW,
      }),
      handlePtaxFxRefreshRequest(buildRequest({ apikey: "chute-errado" }), {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort([]),
        fetchImpl: neverCalledFetch({ count: 0 }),
        waitImpl: instantWait,
        now: FIXED_NOW,
      }),
      handlePtaxFxRefreshRequest(buildRequest({ apikey: EXPECTED_SECRET }), {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort([], { conflict: true }),
        fetchImpl: neverCalledFetch({ count: 0 }),
        waitImpl: instantWait,
        now: FIXED_NOW,
      }),
      handlePtaxFxRefreshRequest(buildRequest({ apikey: EXPECTED_SECRET }), {
        expectedSecret: EXPECTED_SECRET,
        port: buildFakePort([]),
        fetchImpl: technicalFailureFetch({ count: 0 }),
        waitImpl: instantWait,
        now: FIXED_NOW,
      }),
    ]);
    let anyLeak = false;
    for (const res of scenarios) {
      const text = await res.text();
      if (text.includes(EXPECTED_SECRET)) anyLeak = true;
    }
    assert(
      "nenhuma resposta HTTP (405/401/409/500) contém o segredo esperado",
      !anyLeak,
    );
  }

  const failedCount = assertions.filter(([, ok]) => !ok).length;
  return { assertions, failedCount };
}

// ----------------------------------------------------------------------------
// Registro no runner nativo do Deno — `deno test` executa exatamente o mesmo
// harness offline acima (runPtaxFxRefreshTests), sem cenário novo e sem alterar a
// lógica das asserções. Guardado por `typeof Deno !== "undefined"` para que este
// arquivo continue importável a partir de Node (usado só para validação offline no
// sandbox de desenvolvimento) sem lançar `Deno is not defined`. Nenhuma permissão é
// requisitada: o harness é 100% offline (fetch/porta sempre fakes controlados neste
// arquivo), então `deno test` roda sem qualquer flag --allow-*.
// ----------------------------------------------------------------------------
if (typeof Deno !== "undefined") {
  Deno.test(
    "ptax-fx-refresh — suíte offline completa (11 cenários obrigatórios, harness existente)",
    async () => {
      const result = await runPtaxFxRefreshTests();
      const falhas = result.assertions.filter(([, ok]) => !ok);
      if (falhas.length > 0) {
        throw new Error(
          `${falhas.length}/${result.assertions.length} asserções falharam:\n` +
            falhas.map(([label]) => `  - ${label}`).join("\n"),
        );
      }
    },
  );
}
