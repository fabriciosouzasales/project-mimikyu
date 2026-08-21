// Project Mimikyu — supabase/functions/justtcg-price-refresh/pricing-source-lookup.test.ts
// Bateria de testes offline de resolveJusttcgPricingSourceId — correção de segurança
// (2026-08-21, 2ª rodada): a função registrava `error?.message` cru em Function Logs.
//
// 100% offline: o `supabase` recebido é sempre um fake mínimo neste arquivo, reproduzindo
// só a cadeia usada pela função (.from().select().eq().maybeSingle()) — nenhum
// SupabaseClient real, nenhuma chamada de rede.

import {
  resolveJusttcgPricingSourceId,
} from "./pricing-source-lookup.ts";
import type { SanitizedLogger } from "./handler.ts";

export interface TestSuiteResult {
  assertions: Array<[string, boolean]>;
  failedCount: number;
}

const SENTINEL = "FALHA_INTERNA_COM_DETALHE_SENSIVEL_NUNCA_DEVE_VAZAR";

interface LoggedCall {
  code: string;
  context?: Readonly<Record<string, unknown>>;
}

function buildLogSpy(): { logError: SanitizedLogger; calls: LoggedCall[] } {
  const calls: LoggedCall[] = [];
  const logError: SanitizedLogger = (code, context) => {
    calls.push({ code, context });
  };
  return { logError, calls };
}

// Fake mínimo do SupabaseClient — só a cadeia exata usada por
// resolveJusttcgPricingSourceId. `maybeSingle()` é o único ponto que resolve a Promise.
function buildFakeSupabase(
  result: { data: unknown; error: unknown },
) {
  const chain = {
    from(_table: string) {
      return chain;
    },
    select(_cols: string) {
      return chain;
    },
    eq(_col: string, _value: string) {
      return chain;
    },
    maybeSingle() {
      return Promise.resolve(result);
    },
  };
  return chain;
}

export async function runPricingSourceLookupTests(): Promise<
  TestSuiteResult
> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) =>
    assertions.push([label, cond]);

  // ── 1. Sucesso — data presente, error nulo -> retorna o id, logger nunca chamado ──────
  {
    const fake = buildFakeSupabase({
      data: { id: "fake-pricing-source-id", code: "JUSTTCG", is_active: true },
      error: null,
    });
    const { logError, calls } = buildLogSpy();
    const result = await resolveJusttcgPricingSourceId(fake, logError);
    assert(
      "sucesso: retorna o id resolvido",
      result === "fake-pricing-source-id",
    );
    assert("sucesso: logger nunca chamado", calls.length === 0);
  }

  // ── 2. Não encontrado — data nulo, sem erro -> null, log sanitizado com hadError=false ──
  {
    const fake = buildFakeSupabase({ data: null, error: null });
    const { logError, calls } = buildLogSpy();
    const result = await resolveJusttcgPricingSourceId(fake, logError);
    assert("não encontrado: retorna null", result === null);
    assert(
      "não encontrado: logger chamado exatamente uma vez",
      calls.length === 1,
    );
    assert(
      "não encontrado: código fixo correto e hadError=false (nenhum outro campo)",
      calls[0].code === "JUSTTCG_PRICE_REFRESH_SOURCE_LOOKUP_FAILED" &&
        JSON.stringify(Object.keys(calls[0].context ?? {})) ===
          JSON.stringify(["hadError"]) &&
        calls[0].context?.hadError === false,
    );
  }

  // ── 3. Erro de banco com sentinela sensível -> nunca vaza (item 6: resposta, logs, telemetria) ──
  {
    // Reproduz um erro PostgREST real: message/details/hint/code, todos potencialmente
    // sensíveis (podem citar nome de coluna/constraint ou fragmento de query).
    const fakePostgrestError = {
      message: SENTINEL,
      details: SENTINEL,
      hint: SENTINEL,
      code: "42501",
    };
    const fake = buildFakeSupabase({ data: null, error: fakePostgrestError });
    const { logError, calls } = buildLogSpy();
    const result = await resolveJusttcgPricingSourceId(fake, logError);

    // (a) "resposta" — esta função não produz HTTP; a prova aplicável é que o valor
    // retornado não carrega nenhum fragmento do erro (é só `null`, nunca o objeto).
    assert(
      "erro de banco sensível: retorna null (nunca o objeto de erro ou fragmento dele)",
      result === null,
    );

    // (b) "logs" — o logger foi de fato exercitado (prova que o catch não ficou mudo) e a
    // sentinela nunca aparece em nenhuma chamada capturada.
    assert(
      "erro de banco sensível: logger foi chamado exatamente uma vez",
      calls.length === 1,
    );
    assert(
      "erro de banco sensível: sentinela NUNCA aparece em nenhuma chamada capturada do logger",
      !JSON.stringify(calls).includes(SENTINEL),
    );
    assert(
      "erro de banco sensível: log capturado contém só o código fixo e {hadError:true} — nenhum campo capaz de carregar o erro cru (message/details/hint/code/objeto)",
      calls[0].code === "JUSTTCG_PRICE_REFRESH_SOURCE_LOOKUP_FAILED" &&
        JSON.stringify(Object.keys(calls[0].context ?? {})) ===
          JSON.stringify(["hadError"]) &&
        calls[0].context?.hadError === true,
    );

    // (c) "telemetria/porta persistida" — resolveJusttcgPricingSourceId roda ANTES de
    // qualquer uso da porta (PriceRefreshRunPort); não existe pricing_sync_run/
    // pricing_sync_run_call aberto para este erro específico (o handler só chama esta
    // função para resolver pricingSourceId — se ela falhar, o handler retorna
    // SERVER_MISCONFIGURED sem nunca abrir um run, ver handler.ts passo 3). Não há canal de
    // telemetria a verificar por este caminho: a única superfície observável é o próprio
    // valor de retorno (já provado em (a) acima) e o logger (já provado em (b) acima) — daí
    // este cenário não precisar de uma terceira asserção own para "telemetria".
    assert(
      "erro de banco sensível: nenhum vestígio da sentinela em `result` ou nas chamadas do logger, únicas superfícies observáveis deste caminho",
      !JSON.stringify({ result, calls }).includes(SENTINEL),
    );
  }

  // ── 4. Erro sem `.message` (ex.: undefined/objeto vazio) -> ainda assim só código fixo ──
  {
    const fake = buildFakeSupabase({ data: null, error: {} });
    const { logError, calls } = buildLogSpy();
    const result = await resolveJusttcgPricingSourceId(fake, logError);
    assert("erro vazio: retorna null", result === null);
    assert(
      "erro vazio: mesmo comportamento sanitizado (hadError=true, sem outros campos)",
      calls.length === 1 && calls[0].context?.hadError === true &&
        JSON.stringify(Object.keys(calls[0].context ?? {})) ===
          JSON.stringify(["hadError"]),
    );
  }

  // ── 5. logError omitido -> usa o default sem lançar (defaultSanitizedLogger real) ──────
  {
    const fake = buildFakeSupabase({ data: null, error: null });
    let threw = false;
    let result: string | null = "não executado";
    try {
      result = await resolveJusttcgPricingSourceId(fake);
    } catch {
      threw = true;
    }
    assert("logError omitido: não lança (usa defaultSanitizedLogger)", !threw);
    assert("logError omitido: ainda retorna null corretamente", result === null);
  }

  const failedCount = assertions.filter(([, ok]) => !ok).length;
  return { assertions, failedCount };
}

// ----------------------------------------------------------------------------
// Registro no runner nativo do Deno — guardado por `typeof Deno !== "undefined"` para
// permanecer importável a partir de Node (validação offline no sandbox). 100% offline —
// nenhuma permissão --allow-* necessária.
// ----------------------------------------------------------------------------
if (typeof Deno !== "undefined") {
  Deno.test(
    "pricing-source-lookup — suíte offline (correção de segurança, 2026-08-21, 2ª rodada)",
    async () => {
      const result = await runPricingSourceLookupTests();
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
