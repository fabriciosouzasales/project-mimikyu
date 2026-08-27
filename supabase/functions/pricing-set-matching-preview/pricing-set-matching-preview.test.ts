// Project Mimikyu — supabase/functions/pricing-set-matching-preview/pricing-set-matching-preview.test.ts
// Suite offline (100% sem rede real, sem Deno.serve) do preview de correspondência de Set —
// P16.3 (Descoberta de Correspondência, 2026-08-25). Cobre os 9 cenários mínimos exigidos
// por Fabrício (Seção 16 do pedido) mais estrutura/roteamento HTTP e provas de zero escrita
// / orçamento de requisições. Mesmo estilo dos demais .test.ts deste diretório
// (_shared/pricing-justtcg-refresh/set-refresh-core.test.ts,
// _shared/pricing-justtcg-matching/pricing-justtcg-matching.test.ts): assert() customizado,
// fetchImpl fake injetado no JustTcgClient, sem nenhuma dependência externa.

import { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { handlePricingSetMatchingPreviewRequest, type AdminVerification, type HandlerDeps } from "./handler.ts";
import type { EligibleCardSetInfo, ExistingSetMappingInfo, SetMatchingPreviewPort } from "./port.ts";

let failures = 0;
function assert(label: string, condition: boolean): void {
  if (!condition) {
    failures++;
    console.error(`FALHOU: ${label}`);
  } else {
    console.log(`OK: ${label}`);
  }
}

// ----------------------------------------------------------------------------
// Fakes
// ----------------------------------------------------------------------------

type FakePortSeed = {
  cardSet: EligibleCardSetInfo | null;
  activeSource: { id: string; code: string } | null;
  existingMapping: ExistingSetMappingInfo | null;
};

function buildFakePort(seed: FakePortSeed): { port: SetMatchingPreviewPort; calls: string[] } {
  const calls: string[] = [];
  const port: SetMatchingPreviewPort = {
    async findCardSet(cardSetId: string) {
      calls.push(`findCardSet(${cardSetId})`);
      return seed.cardSet;
    },
    async findActivePricingSource(code: string) {
      calls.push(`findActivePricingSource(${code})`);
      return seed.activeSource;
    },
    async findExistingSetMapping(cardSetId: string, pricingSourceId: string) {
      calls.push(`findExistingSetMapping(${cardSetId},${pricingSourceId})`);
      return seed.existingMapping;
    },
  };
  return { port, calls };
}

function makeFakeFetch(
  responses: Array<{ status: number; body: unknown }>,
): { fetchImpl: typeof fetch; callCount: () => number } {
  let index = 0;
  const fetchImpl = (async (_url: string, _init?: RequestInit) => {
    const entry = responses[index] ?? responses[responses.length - 1];
    index++;
    return new Response(JSON.stringify(entry.body), { status: entry.status });
  }) as unknown as typeof fetch;
  return { fetchImpl, callCount: () => index };
}

const ADMIN_OK: AdminVerification = { ok: true, userId: "admin-1" };
const ADMIN_FORBIDDEN: AdminVerification = { ok: false, status: 403, error: "FORBIDDEN_NOT_ADMIN" };
const ADMIN_UNAUTHENTICATED: AdminVerification = { ok: false, status: 401, error: "INVALID_USER_SESSION" };

function buildDeps(
  seed: FakePortSeed,
  fetchResponses: Array<{ status: number; body: unknown }>,
  admin: AdminVerification = ADMIN_OK,
): { deps: HandlerDeps; calls: string[]; callCount: () => number } {
  const { port, calls } = buildFakePort(seed);
  const { fetchImpl, callCount } = makeFakeFetch(fetchResponses);
  const deps: HandlerDeps = {
    verifyAdmin: async () => admin,
    port,
    buildClient: () => new JustTcgClient("fake-key", fetchImpl, 1),
    logError: () => {}, // silencioso nos testes — evita poluir stdout com os logs esperados
  };
  return { deps, calls, callCount };
}

function req(body: unknown, method = "POST"): Request {
  return new Request("https://example.com/pricing-set-matching-preview", {
    method,
    headers: { "Content-Type": "application/json", Authorization: "Bearer fake-jwt" },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

const SWSH8_CARD_SET: EligibleCardSetInfo = {
  id: "0000fdc8-30fd-412f-88e7-40459092a9f1",
  code: "SWSH8",
  name: "Golpe Fusão",
  releaseDate: "2021-11-05",
  gameCode: "POKEMON",
};
const JUSTTCG_SOURCE = { id: "1ffe42af-7b16-4406-88c8-ad2d57dde6f9", code: "JUSTTCG" };

async function main() {
  // 1. Set inexistente -> SET_NOT_FOUND (404), zero chamada à JustTCG, zero leitura de
  // fonte/mapping (curto-circuito na primeira leitura).
  {
    const { deps, calls, callCount } = buildDeps(
      { cardSet: null, activeSource: null, existingMapping: null },
      [],
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: "inexistente" }), deps);
    const json = await res.json();
    assert("1. Set inexistente -> 404 SET_NOT_FOUND", res.status === 404 && json.success === false && json.error === "SET_NOT_FOUND");
    assert("1. Set inexistente -> zero chamada à JustTCG", callCount() === 0);
    assert("1. Set inexistente -> só findCardSet foi chamado", calls.length === 1 && calls[0].startsWith("findCardSet"));
  }

  // 2. Set não elegível (jogo != POKEMON) -> SET_NOT_ELIGIBLE (200, estado seguro), zero
  // chamada à JustTCG.
  {
    const naoElegivel: EligibleCardSetInfo = { ...SWSH8_CARD_SET, gameCode: "MAGIC" };
    const { deps, callCount } = buildDeps({ cardSet: naoElegivel, activeSource: null, existingMapping: null }, []);
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: naoElegivel.id }), deps);
    const json = await res.json();
    assert("2. Set não elegível -> 200 SET_NOT_ELIGIBLE", res.status === 200 && json.success === true && json.state === "SET_NOT_ELIGIBLE");
    assert("2. Set não elegível -> zero chamada à JustTCG", callCount() === 0);
  }

  // 2b. Sem fonte ativa -> NO_ACTIVE_SOURCE (200, estado seguro), zero chamada à JustTCG.
  {
    const { deps, callCount } = buildDeps({ cardSet: SWSH8_CARD_SET, activeSource: null, existingMapping: null }, []);
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert("2b. Sem fonte ativa -> 200 NO_ACTIVE_SOURCE", res.status === 200 && json.success === true && json.state === "NO_ACTIVE_SOURCE");
    assert("2b. Sem fonte ativa -> zero chamada à JustTCG", callCount() === 0);
  }

  // 3. Set UNMAPPED (sem nenhuma linha em pricing_set_mapping) e sem release_date local ->
  // NOT_FOUND com motivo explícito, zero chamada à JustTCG (nunca gasta orçamento sem base
  // de comparação).
  {
    const semData: EligibleCardSetInfo = { ...SWSH8_CARD_SET, releaseDate: null };
    const { deps, callCount } = buildDeps({ cardSet: semData, activeSource: JUSTTCG_SOURCE, existingMapping: null }, []);
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: semData.id }), deps);
    const json = await res.json();
    assert(
      "3. Set UNMAPPED sem release_date -> 200 NOT_FOUND (SET_LOCAL_SEM_RELEASE_DATE)",
      res.status === 200 && json.success === true && json.state === "NOT_FOUND" && json.evidence?.reason === "SET_LOCAL_SEM_RELEASE_DATE",
    );
    assert("3. Set UNMAPPED sem release_date -> zero chamada à JustTCG", callCount() === 0);
  }

  // 3b. Set UNMAPPED (existingMapping=null) COM release_date, mas fonte externa sem
  // correspondência -> segue para a JustTCG normalmente (prova que UNMAPPED != erro, é só
  // "nenhuma linha ainda").
  {
    const { deps, callCount } = buildDeps(
      { cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null },
      [{ status: 200, body: { data: [{ id: "outro-set", name: "Outro Set", release_date: "2020-01-01" }] } }],
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert("3b. Set UNMAPPED com release_date -> chega a consultar a JustTCG (1 chamada)", callCount() === 1);
    assert("3b. Set UNMAPPED sem correspondência externa -> NOT_FOUND", json.state === "NOT_FOUND");
  }

  // 4. Set já CONFIRMED -> ALREADY_CONFIRMED (200), zero chamada à JustTCG (mapping
  // preservado, nunca reavaliado).
  {
    const confirmed: ExistingSetMappingInfo = {
      matchStatus: "CONFIRMED",
      externalSetId: "swsh8-fusion-strike",
      externalSetName: "Fusion Strike",
      lastCheckedAt: "2026-08-20T00:00:00Z",
    };
    const { deps, callCount } = buildDeps({ cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: confirmed }, []);
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert(
      "4. Set já CONFIRMED -> 200 ALREADY_CONFIRMED com dados preservados",
      res.status === 200 && json.state === "ALREADY_CONFIRMED" && json.external_set_id === "swsh8-fusion-strike",
    );
    assert("4. Set já CONFIRMED -> zero chamada à JustTCG", callCount() === 0);
  }

  // 4b. Mapping existente mas NÃO CONFIRMED (PENDING/NOT_FOUND/REJECTED) -> NUNCA tratado
  // como ALREADY_CONFIRMED — segue para descoberta fresca.
  for (const status of ["PENDING", "NOT_FOUND", "REJECTED"]) {
    const existing: ExistingSetMappingInfo = { matchStatus: status, externalSetId: null, externalSetName: null, lastCheckedAt: null };
    const { deps, callCount } = buildDeps(
      { cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: existing },
      [{ status: 200, body: { data: [{ id: "swsh8-fusion-strike", name: "Fusion Strike", release_date: "2021-11-05" }] } }],
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert(`4b. Mapping existente ${status} -> nunca ALREADY_CONFIRMED, segue para descoberta`, json.state !== "ALREADY_CONFIRMED");
    assert(`4b. Mapping existente ${status} -> consulta a JustTCG normalmente`, callCount() === 1);
  }

  // 5. SAFE_CANDIDATE — exatamente 1 Set externo com a mesma release_date (caso real de
  // aceite: SWSH8 -> Fusion Strike).
  {
    const { deps, callCount } = buildDeps(
      { cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null },
      [{ status: 200, body: { data: [{ id: "swsh8-fusion-strike", name: "Fusion Strike", release_date: "2021-11-05" }] } }],
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert(
      "5. SAFE_CANDIDATE -> 200 com candidate correto",
      res.status === 200 && json.state === "SAFE_CANDIDATE" && json.candidate?.external_set_id === "swsh8-fusion-strike" &&
        json.local?.card_set_code === "SWSH8",
    );
    assert("5. SAFE_CANDIDATE -> exatamente 1 chamada HTTP", callCount() === 1);
  }

  // 6. AMBIGUOUS — mais de um Set externo com a mesma release_date, nunca escolhido
  // automaticamente.
  {
    const { deps } = buildDeps(
      { cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null },
      [{
        status: 200,
        body: {
          data: [
            { id: "set-a", name: "Set A", release_date: "2021-11-05" },
            { id: "set-b", name: "Set B", release_date: "2021-11-05" },
          ],
        },
      }],
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert(
      "6. AMBIGUOUS -> 200 com 2 candidatos, nenhum escolhido",
      res.status === 200 && json.state === "AMBIGUOUS" && Array.isArray(json.candidates) && json.candidates.length === 2,
    );
  }

  // 7. NOT_FOUND — zero candidatos externos com a mesma release_date.
  {
    const { deps } = buildDeps(
      { cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null },
      [{ status: 200, body: { data: [{ id: "outro", name: "Outro Set", release_date: "1999-01-01" }] } }],
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert("7. NOT_FOUND -> 200 com evidence de zero candidatos", res.status === 200 && json.state === "NOT_FOUND");
  }

  // 8. Falha JustTCG — 3 variantes distintas, NUNCA confundidas com NOT_FOUND (Seção 12).
  {
    const { deps } = buildDeps({ cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null }, [
      { status: 401, body: {} },
    ]);
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert(
      "8a. Falha JustTCG (401) -> 502 JUSTTCG_AUTH_FAILURE, nunca NOT_FOUND",
      res.status === 502 && json.success === false && json.error === "JUSTTCG_AUTH_FAILURE",
    );
  }
  {
    const { deps } = buildDeps({ cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null }, [
      { status: 500, body: {} },
    ]);
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert(
      "8b. Falha JustTCG (5xx) -> 502 JUSTTCG_TECHNICAL_FAILURE, sem detalhe cru na resposta",
      res.status === 502 && json.error === "JUSTTCG_TECHNICAL_FAILURE" && json.detail === undefined,
    );
  }
  {
    // buildClient injeta requestBudget=1 (ver PREVIEW_REQUEST_BUDGET em index.ts) — aqui
    // simulado passando um client já sem orçamento (budget 0) via override direto do deps.
    const { port } = buildFakePort({ cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null });
    const { fetchImpl } = makeFakeFetch([]);
    const deps: HandlerDeps = {
      verifyAdmin: async () => ADMIN_OK,
      port,
      buildClient: () => new JustTcgClient("fake-key", fetchImpl, 0),
      logError: () => {},
    };
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert("8c. Orçamento esgotado -> 503 JUSTTCG_BUDGET_STOPPED, nunca NOT_FOUND", res.status === 503 && json.error === "JUSTTCG_BUDGET_STOPPED");
  }

  // 9. Auth não admin — dois sub-casos (sessão inválida / autenticado mas não admin), zero
  // leitura de porta, zero chamada à JustTCG.
  {
    const { deps, calls, callCount } = buildDeps(
      { cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null },
      [],
      ADMIN_UNAUTHENTICATED,
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert("9a. Sessão inválida -> 401 INVALID_USER_SESSION", res.status === 401 && json.error === "INVALID_USER_SESSION");
    assert("9a. Sessão inválida -> zero leitura de porta/JustTCG", calls.length === 0 && callCount() === 0);
  }
  {
    const { deps, calls, callCount } = buildDeps(
      { cardSet: SWSH8_CARD_SET, activeSource: JUSTTCG_SOURCE, existingMapping: null },
      [],
      ADMIN_FORBIDDEN,
    );
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: SWSH8_CARD_SET.id }), deps);
    const json = await res.json();
    assert("9b. Autenticado mas não admin -> 403 FORBIDDEN_NOT_ADMIN", res.status === 403 && json.error === "FORBIDDEN_NOT_ADMIN");
    assert("9b. Não admin -> zero leitura de porta/JustTCG", calls.length === 0 && callCount() === 0);
  }

  // ---- Estrutura/roteamento HTTP adicional ----

  // 10. Método não POST -> 405.
  {
    const { deps } = buildDeps({ cardSet: null, activeSource: null, existingMapping: null }, []);
    const res = await handlePricingSetMatchingPreviewRequest(req(null, "GET"), deps);
    assert("10. Método GET -> 405 METHOD_NOT_ALLOWED", res.status === 405);
  }

  // 11. Corpo JSON inválido -> 400.
  {
    const { deps } = buildDeps({ cardSet: null, activeSource: null, existingMapping: null }, []);
    const badReq = new Request("https://example.com/pricing-set-matching-preview", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer fake-jwt" },
      body: "{not-json",
    });
    const res = await handlePricingSetMatchingPreviewRequest(badReq, deps);
    const json = await res.json();
    assert("11. Corpo JSON inválido -> 400 INVALID_JSON", res.status === 400 && json.error === "INVALID_JSON");
  }

  // 12. card_set_id ausente/vazio -> 400.
  {
    const { deps } = buildDeps({ cardSet: null, activeSource: null, existingMapping: null }, []);
    const res = await handlePricingSetMatchingPreviewRequest(req({ card_set_id: "  " }), deps);
    const json = await res.json();
    assert("12. card_set_id vazio -> 400 CARD_SET_ID_REQUIRED", res.status === 400 && json.error === "CARD_SET_ID_REQUIRED");
  }

  // 13. Auth verificada ANTES do corpo — corpo inválido com admin negado ainda retorna 401/403,
  // nunca 400 (prova de ordem: auth é o passo 2, corpo é o passo 3).
  {
    const { deps } = buildDeps({ cardSet: null, activeSource: null, existingMapping: null }, [], ADMIN_FORBIDDEN);
    const badReq = new Request("https://example.com/pricing-set-matching-preview", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer fake-jwt" },
      body: "{not-json",
    });
    const res = await handlePricingSetMatchingPreviewRequest(badReq, deps);
    assert("13. Auth checada antes do corpo -> 403, nunca 400 mesmo com JSON quebrado", res.status === 403);
  }

  console.log(`\n${failures === 0 ? "TODOS OS TESTES PASSARAM" : `${failures} FALHA(S)`}`);
  if (failures > 0) throw new Error(`${failures} teste(s) falharam.`);
}

Deno.test("pricing-set-matching-preview: suite offline completa (P16.3)", main);
