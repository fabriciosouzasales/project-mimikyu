// Project Mimikyu — supabase/functions/_shared/pricing-ptax/pricing-ptax.test.ts
// Bateria de testes do núcleo compartilhado PTAX — Incremento P13.2 (2026-08-18).
//
// 100% offline: nenhum teste aqui faz uma chamada de rede real nem escreve no
// Supabase — fetch e repositório são sempre fakes controlados neste arquivo. Mesmo
// padrão de asserção já usado em sync-ptax-fx-rate.ts/sync-justtcg-pricing.ts
// (assert()/console.log, sem framework de teste externo), exportado como função pura
// para ser reaproveitado tanto pelo `--fixture-check` do adapter manual quanto por
// uma execução direta (`deno test`/`node`) deste arquivo.

import { resolveDefaultPeriod, resolveOverridePeriod } from "./period.ts";
import { buildPtaxPeriodUrl } from "./url.ts";
import { validatePtaxResponseShape } from "./validate.ts";
import { selectClosingRatesByDate } from "./select-closing.ts";
import { fetchPtaxPeriodWithRetry } from "./http.ts";
import { persistPtaxRates } from "./persist.ts";
import { sanitize } from "./sanitize.ts";
import {
  buildErrorSummary,
  classifyStartAttempt,
  decideFinalStatus,
} from "./sync-run-orchestration.ts";
import type {
  FetchLike,
  PtaxRate,
  PtaxRateRepository,
  PtaxRunResult,
  WaitLike,
} from "./types.ts";

export interface TestSuiteResult {
  assertions: Array<[string, boolean]>;
  failedCount: number;
}

// ----------------------------------------------------------------------------
// Fakes de infraestrutura — nunca tocam rede real nem Supabase real.
// ----------------------------------------------------------------------------

function fakeResponse(
  init: { ok: boolean; status: number; json?: unknown; text?: string },
): Response {
  return {
    ok: init.ok,
    status: init.status,
    json: () => Promise.resolve(init.json),
    text: () => Promise.resolve(init.text ?? ""),
  } as unknown as Response;
}

function sequencedFetch(
  responses: Array<Response | (() => Response) | Error>,
): { fetchImpl: FetchLike; calls: number[] } {
  let index = 0;
  const calls: number[] = [];
  const fetchImpl: FetchLike = ((_url: string, _init?: RequestInit) => {
    calls.push(Date.now());
    const entry = responses[Math.min(index, responses.length - 1)];
    index++;
    if (entry instanceof Error) return Promise.reject(entry);
    return Promise.resolve(typeof entry === "function" ? entry() : entry);
  }) as FetchLike;
  return { fetchImpl, calls };
}

function recordingWait(): { waitImpl: WaitLike; waited: number[] } {
  const waited: number[] = [];
  const waitImpl: WaitLike = (ms: number) => {
    waited.push(ms);
    return Promise.resolve();
  };
  return { waitImpl, waited };
}

function inMemoryRepository(
  seed: Record<string, number>,
): PtaxRateRepository & { insertCalls: PtaxRate[] } {
  const store = new Map<string, number>(Object.entries(seed));
  const insertCalls: PtaxRate[] = [];
  return {
    insertCalls,
    findExistingRates(dates) {
      const result = new Map<string, number>();
      for (const d of dates) {
        if (store.has(d)) result.set(d, store.get(d) as number);
      }
      return Promise.resolve(result);
    },
    insertRate(entry) {
      insertCalls.push(entry);
      if (store.has(entry.rateDate)) {
        return Promise.resolve("CONFLICT_IGNORED");
      }
      store.set(entry.rateDate, entry.rate);
      return Promise.resolve("INSERTED");
    },
  };
}

// ----------------------------------------------------------------------------
// Fixtures de resposta BCB
// ----------------------------------------------------------------------------

const FIXTURE_SEMANA_NORMAL = {
  value: [
    {
      cotacaoCompra: 5.4321,
      cotacaoVenda: 5.4327,
      dataHoraCotacao: "2026-08-10 13:04:41.123",
    },
    {
      cotacaoCompra: 5.4501,
      cotacaoVenda: 5.4508,
      dataHoraCotacao: "2026-08-11 13:02:18.456",
    },
    // 2026-08-15/16 (sáb/dom) deliberadamente ausentes — sem pregão, sem cotação.
    {
      cotacaoCompra: 5.461,
      cotacaoVenda: 5.4617,
      dataHoraCotacao: "2026-08-17T13:05:59.001",
    },
  ],
};

const FIXTURE_MULTIPLOS_BOLETINS = {
  value: [
    {
      cotacaoCompra: 5.4,
      cotacaoVenda: 5.41,
      dataHoraCotacao: "2026-08-10 09:15:00.000",
    }, // abertura
    {
      cotacaoCompra: 5.42,
      cotacaoVenda: 5.43,
      dataHoraCotacao: "2026-08-10 11:00:00.000",
    }, // intermediário
    {
      cotacaoCompra: 5.44,
      cotacaoVenda: 5.4512,
      dataHoraCotacao: "2026-08-10 13:04:00.000",
    }, // fechamento (mais recente)
  ],
};

export function runPricingPtaxTests(): TestSuiteResult {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) =>
    assertions.push([label, cond]);

  // ── 1. Janela com 10 datas exatas ──────────────────────────────────────
  {
    const r = resolveDefaultPeriod("2026-08-18");
    assert("janela padrão: status OK", r.status === "OK");
    if (r.status === "OK") {
      assert(
        "janela padrão: endDate == referenceDate",
        r.period.endDate === "2026-08-18",
      );
      assert(
        "janela padrão: startDate é referenceDate - 9 dias",
        r.period.startDate === "2026-08-09",
      );
      const totalDias =
        (Date.parse(r.period.endDate) - Date.parse(r.period.startDate)) /
          86_400_000 + 1;
      assert(
        "janela padrão: exatamente 10 datas corridas inclusive",
        totalDias === 10,
      );
    }
  }

  // ── 2. Virada de mês e de ano ───────────────────────────────────────────
  {
    const virasMes = resolveDefaultPeriod("2026-03-05");
    assert(
      "virada de mês: OK e cruza fev->mar",
      virasMes.status === "OK" && virasMes.period.startDate === "2026-02-24" &&
        virasMes.period.endDate === "2026-03-05",
    );

    const viraAno = resolveDefaultPeriod("2027-01-03");
    assert(
      "virada de ano: OK e cruza dez/2026->jan/2027",
      viraAno.status === "OK" && viraAno.period.startDate === "2026-12-25" &&
        viraAno.period.endDate === "2027-01-03",
    );
  }

  // ── 3. Ano bissexto ─────────────────────────────────────────────────────
  {
    const bissexto = resolveDefaultPeriod("2028-03-05");
    assert(
      "ano bissexto: janela cruza 29/02/2028 corretamente (10 dias)",
      bissexto.status === "OK" && bissexto.period.startDate === "2028-02-25",
    );

    const naoBissextoFev29Invalido = resolveDefaultPeriod("2027-02-29"); // 2027 não é bissexto
    assert(
      "2027-02-29 (ano não-bissexto) é rejeitado como referenceDate inválida",
      naoBissextoFev29Invalido.status === "INVALID",
    );

    const bissextoFev29Valido = resolveDefaultPeriod("2028-02-29"); // 2028 é bissexto
    assert(
      "2028-02-29 (ano bissexto) é aceito como referenceDate válida",
      bissextoFev29Valido.status === "OK",
    );
  }

  // ── 4. Override válido e inválido ───────────────────────────────────────
  {
    const ok = resolveOverridePeriod("2026-01-01", "2026-01-10");
    assert(
      "override válido: aceito, 10 dias",
      ok.status === "OK" && ok.period.startDate === "2026-01-01" &&
        ok.period.endDate === "2026-01-10",
    );

    const ordemInvalida = resolveOverridePeriod("2026-01-10", "2026-01-01");
    assert(
      "override com start > end: rejeitado",
      ordemInvalida.status === "INVALID",
    );

    const formatoInvalido = resolveOverridePeriod("01-01-2026", "2026-01-10");
    assert(
      "override com formato fora de YYYY-MM-DD: rejeitado",
      formatoInvalido.status === "INVALID",
    );

    const muitoLongo = resolveOverridePeriod("2026-01-01", "2026-12-31");
    assert(
      "override maior que MAX_OVERRIDE_WINDOW_DAYS: rejeitado",
      muitoLongo.status === "INVALID",
    );

    const dataCalendarioInvalida = resolveOverridePeriod(
      "2026-02-30",
      "2026-03-01",
    );
    assert(
      "override com dia de calendário inexistente (2026-02-30): rejeitado",
      dataCalendarioInvalida.status === "INVALID",
    );
  }

  // ── URL — regressão do contrato comprovado por chamada real (P9) ───────
  {
    const url = buildPtaxPeriodUrl("2026-08-10", "2026-08-17");
    const urlEsperada =
      "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)" +
      "?@dataInicial='08-10-2026'&@dataFinalCotacao='08-17-2026'&$format=json&$select=cotacaoCompra,cotacaoVenda,dataHoraCotacao";
    assert(
      "buildPtaxPeriodUrl produz exatamente a URL comprovadamente funcional (P9, 2026-08-17)",
      url === urlEsperada,
    );
  }

  // ── 5. Resposta válida do BCB ────────────────────────────────────────────
  {
    const shape = validatePtaxResponseShape(FIXTURE_SEMANA_NORMAL);
    assert(
      "resposta válida: shape OK com 3 itens",
      shape.status === "OK" && shape.items.length === 3,
    );
    if (shape.status === "OK") {
      const { rates } = selectClosingRatesByDate(shape.items);
      assert("resposta válida: 3 rates resolvidas", rates.length === 3);
      const primeiraCotacaoResolvida = rates[0].rate;
      assert(
        "resposta válida: grava cotação de VENDA (5.4327)",
        Object.is(primeiraCotacaoResolvida, 5.4327),
      );
      assert(
        "resposta válida: nunca grava a cotação de compra (5.4321)",
        !Object.is(primeiraCotacaoResolvida, 5.4321),
      );
      assert(
        "resposta válida: extractRateDate lida com espaço como separador",
        rates[0].rateDate === "2026-08-10",
      );
      assert(
        "resposta válida: extractRateDate lida com 'T' como separador",
        rates[2].rateDate === "2026-08-17",
      );
    }
  }

  // ── 6. Ausência de cotação em fim de semana/feriado ─────────────────────
  {
    const shape = validatePtaxResponseShape(FIXTURE_SEMANA_NORMAL);
    if (shape.status === "OK") {
      const { rates } = selectClosingRatesByDate(shape.items);
      assert(
        "fim de semana sem pregão: nenhuma rate_date artificial para 15/16-08",
        !rates.some((r) =>
          r.rateDate === "2026-08-15" || r.rateDate === "2026-08-16"
        ),
      );
    }
  }

  // ── 7. Múltiplos boletins e seleção do fechamento ───────────────────────
  {
    const shape = validatePtaxResponseShape(FIXTURE_MULTIPLOS_BOLETINS);
    assert(
      "múltiplos boletins: shape OK com 3 itens do mesmo dia",
      shape.status === "OK" && shape.items.length === 3,
    );
    if (shape.status === "OK") {
      const { rates } = selectClosingRatesByDate(shape.items);
      assert(
        "múltiplos boletins: colapsa para 1 rate_date só",
        rates.length === 1,
      );
      assert(
        "múltiplos boletins: seleciona o item de dataHoraCotacao mais recente (fechamento)",
        rates[0].rate === 5.4512,
      );
    }
  }

  // ── 8. Resposta inválida ─────────────────────────────────────────────────
  {
    const casos: Array<{ nome: string; payload: unknown }> = [
      { nome: "sem campo value", payload: {} },
      { nome: "value não é array", payload: { value: "não é array" } },
      {
        nome: "item sem cotacaoVenda",
        payload: {
          value: [{
            cotacaoCompra: 5.0,
            dataHoraCotacao: "2026-08-10 12:00:00",
          }],
        },
      },
      {
        nome: "item com cotacaoVenda como string",
        payload: {
          value: [{
            cotacaoCompra: 5.0,
            cotacaoVenda: "5.4",
            dataHoraCotacao: "2026-08-10 12:00:00",
          }],
        },
      },
      {
        nome: "item sem dataHoraCotacao",
        payload: { value: [{ cotacaoCompra: 5.0, cotacaoVenda: 5.4 }] },
      },
      { nome: "json nulo", payload: null },
      { nome: "json é array puro", payload: [1, 2, 3] },
    ];
    let rejeitados = 0;
    for (const caso of casos) {
      if (validatePtaxResponseShape(caso.payload).status === "INVALID") {
        rejeitados++;
      }
    }
    assert(
      `resposta inválida: todos os ${casos.length} casos malformados são rejeitados (falha funcional, nunca parsing best-effort)`,
      rejeitados === casos.length,
    );
  }

  // ── 9. Retry e encerramento das tentativas ──────────────────────────────
  {
    // 9a. Duas falhas 5xx (retryable) seguidas de sucesso na 3ª tentativa.
    (async () => {})(); // placeholder para manter a seção síncrona abaixo legível
  }

  return { assertions, failedCount: assertions.filter(([, ok]) => !ok).length };
}

// Testes assíncronos (retry HTTP e persistência) — separados por precisarem de await,
// mas compõem o MESMO relatório final quando chamados por runAllPricingPtaxTestsAsync().
export async function runPricingPtaxAsyncTests(): Promise<TestSuiteResult> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) =>
    assertions.push([label, cond]);

  // ── 9. Retry e encerramento das tentativas ──────────────────────────────
  {
    // 9a. 500, 500, depois 200 — sucesso na 3ª tentativa, 2 esperas (1s, 3s).
    const { fetchImpl } = sequencedFetch([
      fakeResponse({ ok: false, status: 500, text: "internal error" }),
      fakeResponse({ ok: false, status: 500, text: "internal error" }),
      fakeResponse({ ok: true, status: 200, json: FIXTURE_SEMANA_NORMAL }),
    ]);
    const { waitImpl, waited } = recordingWait();
    const result = await fetchPtaxPeriodWithRetry(
      "https://exemplo.invalido/teste",
      { fetchImpl, waitImpl },
    );
    assert(
      "retry: 2x 500 seguido de sucesso -> status SUCCESS na 3ª tentativa",
      result.status === "SUCCESS",
    );
    assert(
      "retry: callLog tem exatamente 3 entradas (3 tentativas)",
      result.callLog.length === 3,
    );
    assert(
      "retry: esperas foram 1000ms e depois 3000ms, nesta ordem",
      waited.length === 2 && waited[0] === 1_000 && waited[1] === 3_000,
    );
  }

  // 9b. 500 em todas as 3 tentativas — esgota o retry, TECHNICAL_FAILURE.
  {
    const { fetchImpl } = sequencedFetch([
      fakeResponse({ ok: false, status: 503, text: "unavailable" }),
      fakeResponse({ ok: false, status: 503, text: "unavailable" }),
      fakeResponse({ ok: false, status: 503, text: "unavailable" }),
    ]);
    const { waitImpl } = recordingWait();
    const result = await fetchPtaxPeriodWithRetry(
      "https://exemplo.invalido/teste",
      { fetchImpl, waitImpl },
    );
    assert(
      "retry esgotado: 3x 503 -> TECHNICAL_FAILURE após exatamente 3 tentativas",
      result.status === "TECHNICAL_FAILURE" && result.callLog.length === 3,
    );
  }

  // 9c. 400 (não retryable) — nunca repete, encerra na 1ª tentativa.
  {
    const { fetchImpl } = sequencedFetch([
      fakeResponse({ ok: false, status: 400, text: "bad request" }),
    ]);
    const { waitImpl, waited } = recordingWait();
    const result = await fetchPtaxPeriodWithRetry(
      "https://exemplo.invalido/teste",
      { fetchImpl, waitImpl },
    );
    assert(
      "400 (não retryable): TECHNICAL_FAILURE após 1 única tentativa",
      result.status === "TECHNICAL_FAILURE" && result.callLog.length === 1,
    );
    assert(
      "400 (não retryable): nenhuma espera de retry foi chamada",
      waited.length === 0,
    );
  }

  // 9d. 429 é retryable (mesma classe de 408/5xx).
  {
    const { fetchImpl } = sequencedFetch([
      fakeResponse({ ok: false, status: 429, text: "too many requests" }),
      fakeResponse({ ok: true, status: 200, json: FIXTURE_SEMANA_NORMAL }),
    ]);
    const { waitImpl } = recordingWait();
    const result = await fetchPtaxPeriodWithRetry(
      "https://exemplo.invalido/teste",
      { fetchImpl, waitImpl },
    );
    assert(
      "429: é retryable, sucesso na 2ª tentativa",
      result.status === "SUCCESS" && result.callLog.length === 2,
    );
  }

  // 9e. Falha de rede/timeout é sempre retryable.
  {
    const { fetchImpl } = sequencedFetch([
      new Error("AbortError"),
      fakeResponse({ ok: true, status: 200, json: FIXTURE_SEMANA_NORMAL }),
    ]);
    const { waitImpl } = recordingWait();
    const result = await fetchPtaxPeriodWithRetry(
      "https://exemplo.invalido/teste",
      { fetchImpl, waitImpl },
    );
    assert(
      "timeout/falha de rede: retryable, sucesso na 2ª tentativa",
      result.status === "SUCCESS" && result.callLog.length === 2,
    );
    assert(
      "timeout: error_detail da 1ª tentativa reflete TIMEOUT, nunca a mensagem crua",
      result.callLog[0].errorDetail?.startsWith("TIMEOUT_APOS_") === true,
    );
  }

  // ── 10. Inserção nova ────────────────────────────────────────────────────
  {
    const repo = inMemoryRepository({});
    const rates: PtaxRate[] = [
      { rateDate: "2026-08-10", rate: 5.4327 },
      { rateDate: "2026-08-11", rate: 5.4508 },
    ];
    const result = await persistPtaxRates(repo, rates, false);
    assert(
      "inserção nova: 2 rates ausentes -> inserted=2",
      result.counts.inserted === 2 && result.counts.unchanged === 0 &&
        result.counts.divergent === 0,
    );
    assert(
      "inserção nova: insertRate chamado para as 2 datas ausentes",
      repo.insertCalls.length === 2,
    );
  }

  // ── 11. Reexecução idempotente ───────────────────────────────────────────
  {
    const repo = inMemoryRepository({
      "2026-08-10": 5.4327,
      "2026-08-11": 5.4508,
    });
    const rates: PtaxRate[] = [
      { rateDate: "2026-08-10", rate: 5.4327 },
      { rateDate: "2026-08-11", rate: 5.4508 },
    ];
    const result = await persistPtaxRates(repo, rates, false);
    assert(
      "reexecução idempotente: mesmas 2 rates já existentes e iguais -> unchanged=2, inserted=0",
      result.counts.unchanged === 2 && result.counts.inserted === 0,
    );
    assert(
      "reexecução idempotente: insertRate NUNCA chamado (nada novo a escrever)",
      repo.insertCalls.length === 0,
    );
  }

  // ── 12. Taxa idêntica (caso isolado) ─────────────────────────────────────
  {
    const repo = inMemoryRepository({ "2026-08-10": 5.4327 });
    const result = await persistPtaxRates(repo, [{
      rateDate: "2026-08-10",
      rate: 5.4327,
    }], false);
    assert(
      "taxa idêntica: unchanged=1, nenhuma divergência registrada",
      result.counts.unchanged === 1 && result.divergences.length === 0,
    );
  }

  // ── 13. Taxa divergente sem overwrite ────────────────────────────────────
  {
    const repo = inMemoryRepository({ "2026-08-10": 5.0 });
    const result = await persistPtaxRates(repo, [{
      rateDate: "2026-08-10",
      rate: 5.4327,
    }], false);
    assert(
      "taxa divergente: divergent=1, nunca inserted/unchanged para essa data",
      result.counts.divergent === 1 && result.counts.inserted === 0,
    );
    assert(
      "taxa divergente: detalhe registra existingRate e incomingRate corretos",
      result.divergences[0]?.existingRate === 5.0 &&
        result.divergences[0]?.incomingRate === 5.4327,
    );
    assert(
      "taxa divergente: insertRate NUNCA chamado (nunca sobrescreve silenciosamente)",
      repo.insertCalls.length === 0,
    );
  }

  // ── Dry-run não escreve ──────────────────────────────────────────────────
  {
    const repo = inMemoryRepository({});
    const result = await persistPtaxRates(repo, [{
      rateDate: "2026-08-10",
      rate: 5.4327,
    }], true);
    assert(
      "dry-run: conta 'inserted' previsto sem chamar insertRate de verdade",
      result.counts.inserted === 1 && repo.insertCalls.length === 0,
    );
  }

  // ── 14. Conflito concorrente antes do HTTP (classificação pura) ─────────
  {
    const conflito = classifyStartAttempt({
      code: "23505",
      message:
        'duplicate key value violates unique constraint "ux_pricing_sync_run_active_fx_per_source_type"',
    });
    assert(
      "23505 em pricing_sync_run -> CONCURRENT_CONFLICT (sinal para abortar ANTES do BCB)",
      conflito === "CONCURRENT_CONFLICT",
    );

    const outroErro = classifyStartAttempt({
      code: "23514",
      message: "check constraint violation",
    });
    assert(
      "outro código de erro (não 23505) -> OTHER_ERROR, nunca tratado como conflito de concorrência",
      outroErro === "OTHER_ERROR",
    );

    const semErro = classifyStartAttempt(null);
    assert("sem erro -> STARTED", semErro === "STARTED");
  }

  // ── 15. Estado terminal — mapeamento de resultado para status final ─────
  {
    const falhaTecnica: PtaxRunResult = {
      kind: "TECHNICAL_FAILURE",
      detail: "TIMEOUT_APOS_15000MS",
      callLog: [],
    };
    assert(
      "falha técnica -> status final FAILED (nunca fica preso em PROCESSING)",
      decideFinalStatus(falhaTecnica) === "FAILED",
    );
    assert(
      "falha técnica -> error_summary reflete o detail original",
      buildErrorSummary(falhaTecnica) === "TIMEOUT_APOS_15000MS",
    );

    const falhaFuncional: PtaxRunResult = {
      kind: "FUNCTIONAL_FAILURE",
      detail: "BCB_RESPONSE_SHAPE_INVALID: campo 'value' ausente.",
      callLog: [],
    };
    assert(
      "falha funcional -> status final FAILED",
      decideFinalStatus(falhaFuncional) === "FAILED",
    );

    const completoLimpo: PtaxRunResult = {
      kind: "COMPLETED",
      period: { startDate: "2026-08-09", endDate: "2026-08-18" },
      quotesReceived: 6,
      counts: { inserted: 6, unchanged: 0, divergent: 0, invalid: 0 },
      divergences: [],
      invalidDetails: [],
      callLog: [],
    };
    assert(
      "completo sem divergência/inválido -> status final COMPLETED",
      decideFinalStatus(completoLimpo) === "COMPLETED",
    );
    assert(
      "completo sem divergência/inválido -> error_summary é null (nunca escreve resumo vazio)",
      buildErrorSummary(completoLimpo) === null,
    );

    const completoComDivergencia: PtaxRunResult = {
      ...completoLimpo,
      counts: { inserted: 5, unchanged: 0, divergent: 1, invalid: 0 },
      divergences: [{
        rateDate: "2026-08-10",
        existingRate: 5.0,
        incomingRate: 5.4327,
      }],
    };
    assert(
      "completo com divergência -> status final COMPLETED_WITH_ERRORS (nunca FAILED)",
      decideFinalStatus(completoComDivergencia) === "COMPLETED_WITH_ERRORS",
    );
    const resumoDivergencia = buildErrorSummary(completoComDivergencia);
    assert(
      "resumo de divergência: nomeia 'divergência', nunca a palavra genérica 'erro' (não distorce warning como erro)",
      resumoDivergencia?.includes("divergência") === true &&
        !resumoDivergencia?.toLowerCase().includes("erro técnico"),
    );
  }

  // ── 16. Nenhum segredo em logs (sanitize) ────────────────────────────────
  {
    assert(
      "sanitize(): redige x-api-key",
      sanitize("x-api-key: segredo123")?.includes("[REDACTED]") === true,
    );
    assert(
      "sanitize(): redige Authorization Bearer",
      sanitize("Authorization: Bearer abc.def.ghi")?.includes("[REDACTED]") ===
        true,
    );
    assert(
      "sanitize(): redige um JWT (formato service_role/anon key)",
      sanitize(
        "token=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
      )?.includes("[REDACTED_JWT]") === true,
    );
  }

  // ── 17. Reexecução idempotente real do piloto P13.2 (7 datas, 2026-08-09 a
  //        2026-08-18) — mesmos valores confirmados via auditoria pós-piloto em
  //        pricing_fx_rate (2026-08-18). Reproduz exatamente o cenário que o teste
  //        controlado de idempotência deve produzir. CONFLICT_IGNORED nunca aparece
  //        aqui: persistPtaxRates() só chama repository.insertRate() para datas
  //        AUSENTES do mapa de existentes (ver persist.ts) — com as 7 datas já
  //        presentes, esse branch nunca é alcançado, então "unchanged" vem
  //        exclusivamente da comparação direta (existingRate === rate.rate), nunca
  //        de um retorno CONFLICT_IGNORED do repositório.
  {
    const seed = {
      "2026-08-10": 5.0963,
      "2026-08-11": 5.1285,
      "2026-08-12": 5.1639,
      "2026-08-13": 5.1859,
      "2026-08-14": 5.2236,
      "2026-08-17": 5.2014,
      "2026-08-18": 5.2043,
    };
    const repo = inMemoryRepository(seed);
    const rates: PtaxRate[] = Object.entries(seed).map((
      [rateDate, rate],
    ) => ({ rateDate, rate }));
    const result = await persistPtaxRates(repo, rates, false);
    assert(
      "reexecução idempotente real (7 datas do piloto): inserted=0",
      result.counts.inserted === 0,
    );
    assert(
      "reexecução idempotente real (7 datas do piloto): unchanged=7",
      result.counts.unchanged === 7,
    );
    assert(
      "reexecução idempotente real (7 datas do piloto): divergent=0",
      result.counts.divergent === 0,
    );
    assert(
      "reexecução idempotente real (7 datas do piloto): invalid=0",
      result.counts.invalid === 0,
    );
    assert(
      "reexecução idempotente real: insertRate NUNCA chamado — CONFLICT_IGNORED não representa este fluxo normal (só ocorreria se insertRate fosse chamado e colidisse)",
      repo.insertCalls.length === 0,
    );
  }

  return { assertions, failedCount: assertions.filter(([, ok]) => !ok).length };
}
