// Project Mimikyu — supabase/functions/justtcg-set-bootstrap/justtcg-set-bootstrap.test.ts
// Suite offline (100% sem rede real, sem Deno.serve, sem Supabase real) do HANDLER do
// dispatcher de bootstrap de Set — P16.5.4 ("wiring da Edge Function de bootstrap",
// 2026-08-26). Não reimplementa nenhuma regra de negócio: um fake mínimo de BootstrapPort
// injeta cada BootstrapExecutionResult possível (já 100% coberto por
// _shared/pricing-justtcg-bootstrap/pricing-justtcg-bootstrap.test.ts) e este arquivo só
// prova a tradução HTTP feita por handler.ts — método, autenticação, pricing_source_id
// ausente, e o switch de outcome -> status code/corpo. Mesmo estilo de teste de handler já
// usado por justtcg-price-refresh/justtcg-price-refresh.test.ts.

import { handleJusttcgSetBootstrapRequest } from "./handler.ts";
import type {
  BootstrapPhaseOutcome,
  BootstrapPort,
  BootstrapRunStatus,
  CheckpointAcquisitionResult,
  OpenBootstrapAttemptResult,
  PersistBootstrapBatchResult,
  PersistBootstrapRowInput,
  StagedCardRow,
} from "../_shared/pricing-justtcg-bootstrap/bootstrap-port.ts";
import { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";

let failures = 0;
function assert(label: string, condition: boolean): void {
  if (!condition) {
    failures++;
    console.error(`FALHOU: ${label}`);
  } else {
    console.log(`OK: ${label}`);
  }
}

const EXPECTED_SECRET = "test-secret-value";
const PRICING_SOURCE_ID = "1ffe42af-7b16-4406-88c8-ad2d57dde6f9";
const SYNC_RUN_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const PRICING_SET_MAPPING_ID = "11111111-1111-1111-1111-111111111111";
const CARD_SET_ID = "22222222-2222-2222-2222-222222222222";
const EXTERNAL_SET_ID = "swsh8-fusion-strike";

function makeFakeFetch(
  responses: Array<{ status: number; body: unknown }>,
): typeof fetch {
  let index = 0;
  return ((_url: string, _init?: RequestInit) => {
    const entry = responses[index] ?? responses[responses.length - 1];
    index++;
    return Promise.resolve(
      new Response(JSON.stringify(entry.body), { status: entry.status }),
    );
  }) as unknown as typeof fetch;
}

function buildFakePort(config: {
  openResult: OpenBootstrapAttemptResult;
  checkpointResult?: CheckpointAcquisitionResult;
  closeFinalStatus?: string;
  staging?: StagedCardRow[];
  localCards?: Array<{
    cardId: string;
    name: string;
    collectorNumber: string;
    collectorTotal: number | null;
  }>;
  persistResult?: PersistBootstrapBatchResult;
  throwOnOpen?: boolean;
  throwOnLoadStaging?: boolean;
}): BootstrapPort {
  return {
    openAttempt(_pricingSourceId: string) {
      if (config.throwOnOpen) {
        return Promise.reject(new Error("OPEN_ATTEMPT_RPC_FAILED"));
      }
      return Promise.resolve(config.openResult);
    },
    checkpointAcquisitionPage(
      _syncRunId: string,
      _newResumeOffset: number,
      _stagedCards,
    ) {
      return Promise.resolve(config.checkpointResult ?? true);
    },
    closeAttempt(
      _syncRunId: string,
      _phaseOutcome: BootstrapPhaseOutcome,
      _runStatus: BootstrapRunStatus,
      _requestsMade: number,
      _rateLimitHits: number,
      _errorSummary: string | null,
    ) {
      return Promise.resolve({
        finalStatus: config.closeFinalStatus ?? "COMPLETE",
      });
    },
    loadFullStaging(_pricingSetMappingId: string) {
      if (config.throwOnLoadStaging) {
        return Promise.reject(new Error("STAGING_READ_FAILED"));
      }
      return Promise.resolve(config.staging ?? []);
    },
    loadLocalActiveCards(_cardSetId: string) {
      return Promise.resolve(config.localCards ?? []);
    },
    persistMatchingBatch(
      _pricingSourceId: string,
      _syncRunId: string,
      rows: readonly PersistBootstrapRowInput[],
    ) {
      return Promise.resolve(
        config.persistResult ?? {
          ok: true,
          rows: rows.map((r) => ({
            cardId: r.cardId,
            action: "INSERTED",
            finalMatchStatus: r.classification === "SAFE"
              ? "CONFIRMED"
              : r.classification === "AMBIGUOUS"
              ? "PENDING"
              : "NOT_FOUND",
            identityCreated: r.classification === "SAFE",
          })),
        },
      );
    },
  };
}

function buildClientFactory(
  responses: Array<{ status: number; body: unknown }>,
): () => JustTcgClient {
  return () => new JustTcgClient("fake-key", makeFakeFetch(responses), 10);
}

function claimedAcquiring(): OpenBootstrapAttemptResult {
  return {
    outcome: "CLAIMED",
    syncRunId: SYNC_RUN_ID,
    pricingSetMappingId: PRICING_SET_MAPPING_ID,
    cardSetId: CARD_SET_ID,
    externalSetId: EXTERNAL_SET_ID,
    status: "PENDING",
    acquisitionResumeOffset: 0,
  };
}

function claimedMatching(): OpenBootstrapAttemptResult {
  return {
    outcome: "CLAIMED",
    syncRunId: SYNC_RUN_ID,
    pricingSetMappingId: PRICING_SET_MAPPING_ID,
    cardSetId: CARD_SET_ID,
    externalSetId: EXTERNAL_SET_ID,
    status: "MATCHING",
    acquisitionResumeOffset: 0,
  };
}

async function main() {
  // 1. Método != POST -> 405, Allow: POST.
  {
    const port = buildFakePort({ openResult: { outcome: "NO_CANDIDATE" } });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", { method: "GET" }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
      },
    );
    const body = await res.json();
    assert("1. método GET -> 405", res.status === 405);
    assert(
      "1. corpo error=METHOD_NOT_ALLOWED",
      body.error === "METHOD_NOT_ALLOWED",
    );
    assert("1. header Allow=POST", res.headers.get("Allow") === "POST");
  }

  // 2. apikey ausente -> 401, sem tocar o port.
  {
    const port = buildFakePort({ openResult: { outcome: "NO_CANDIDATE" } });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", { method: "POST" }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
      },
    );
    const body = await res.json();
    assert("2. apikey ausente -> 401", res.status === 401);
    assert("2. corpo error=UNAUTHORIZED", body.error === "UNAUTHORIZED");
  }

  // 3. apikey incorreto -> 401.
  {
    const port = buildFakePort({ openResult: { outcome: "NO_CANDIDATE" } });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: "wrong-secret" },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
      },
    );
    assert("3. apikey incorreto -> 401", res.status === 401);
  }

  // 4. pricingSourceId ausente -> 500 SERVER_MISCONFIGURED, mesmo com auth OK.
  {
    const port = buildFakePort({ openResult: { outcome: "NO_CANDIDATE" } });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: null,
        buildClient: buildClientFactory([]),
      },
    );
    const body = await res.json();
    assert("4. pricingSourceId ausente -> 500", res.status === 500);
    assert(
      "4. corpo error=SERVER_MISCONFIGURED",
      body.error === "SERVER_MISCONFIGURED",
    );
  }

  // 5. NO_CANDIDATE -> outcome NO_WORK, 200.
  {
    const port = buildFakePort({ openResult: { outcome: "NO_CANDIDATE" } });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
      },
    );
    const body = await res.json();
    assert("5. NO_CANDIDATE -> 200", res.status === 200);
    assert(
      "5. outcome=NO_WORK",
      body.success === true && body.outcome === "NO_WORK",
    );
  }

  // 6. SOURCE_BUSY -> 409.
  {
    const port = buildFakePort({ openResult: { outcome: "SOURCE_BUSY" } });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
      },
    );
    const body = await res.json();
    assert("6. SOURCE_BUSY -> 409", res.status === 409);
    assert(
      "6. error=CONCURRENT_SYNC_RUN_ACTIVE",
      body.error === "CONCURRENT_SYNC_RUN_ACTIVE",
    );
  }

  // 7. LEASE_LOST (checkpoint devolve false) -> 200 informativo, com syncRunId.
  {
    const port = buildFakePort({
      openResult: claimedAcquiring(),
      checkpointResult: false,
    });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([
          {
            status: 200,
            body: { data: [{ id: "c1", name: "A" }], meta: { hasMore: false } },
          },
        ]),
      },
    );
    const body = await res.json();
    assert("7. LEASE_LOST -> 200", res.status === 200);
    assert(
      "7. outcome=LEASE_LOST com syncRunId",
      body.outcome === "LEASE_LOST" && body.syncRunId === SYNC_RUN_ID,
    );
  }

  // 8. ACQUISITION_CLOSED (NO_MORE_PAGES/COMPLETED) -> 200, corpo completo.
  {
    const port = buildFakePort({
      openResult: claimedAcquiring(),
      closeFinalStatus: "MATCHING",
    });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([
          { status: 200, body: { data: [], meta: { hasMore: false } } },
        ]),
      },
    );
    const body = await res.json();
    assert("8. ACQUISITION_CLOSED sucesso -> 200", res.status === 200);
    assert(
      "8. corpo: outcome/phaseOutcome/runStatus/syncRunId corretos",
      body.success === true &&
        body.outcome === "ACQUISITION_CLOSED" &&
        body.phaseOutcome === "NO_MORE_PAGES" &&
        body.runStatus === "COMPLETED" &&
        body.syncRunId === SYNC_RUN_ID &&
        body.finalStatus === "MATCHING",
    );
  }

  // 9. ACQUISITION_CLOSED (AUTH_FAILURE/FAILED) -> 500.
  {
    const port = buildFakePort({ openResult: claimedAcquiring() });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([{ status: 401, body: {} }]),
      },
    );
    const body = await res.json();
    assert("9. AUTH_FAILURE -> 500", res.status === 500);
    assert(
      "9. corpo: success=false, runStatus=FAILED",
      body.success === false && body.runStatus === "FAILED" &&
        body.phaseOutcome === "AUTH_FAILURE",
    );
  }

  // 10. MATCHING_CLOSED (MATCHING_COMPLETE/COMPLETED) -> 200, contadores corretos.
  {
    const staging: StagedCardRow[] = [{
      externalCardId: "ext-1",
      externalNumber: "001/198",
      externalName: "Bulbasaur",
    }];
    const localCards = [{
      cardId: "card-1",
      name: "Bulbasaur",
      collectorNumber: "001",
      collectorTotal: 198,
    }];
    const port = buildFakePort({
      openResult: claimedMatching(),
      staging,
      localCards,
      closeFinalStatus: "COMPLETE",
    });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
      },
    );
    const body = await res.json();
    assert("10. MATCHING_CLOSED sucesso -> 200", res.status === 200);
    assert(
      "10. corpo: cardsSafe=1, mappingsInserted=1, identitiesCreated=1",
      body.success === true &&
        body.outcome === "MATCHING_CLOSED" &&
        body.cardsSafe === 1 &&
        body.mappingsInserted === 1 &&
        body.identitiesCreated === 1,
    );
  }

  // 11. MATCHING_CLOSED (leitura local falha -> TRANSIENT_ERROR/FAILED) -> 500.
  {
    const port = buildFakePort({
      openResult: claimedMatching(),
      throwOnLoadStaging: true,
    });
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
      },
    );
    const body = await res.json();
    assert("11. leitura local falha -> 500", res.status === 500);
    assert(
      "11. corpo: success=false, runStatus=FAILED",
      body.success === false && body.runStatus === "FAILED",
    );
  }

  // 12. Falha inesperada (port.openAttempt lança) -> 500 INTERNAL_ERROR, sem vazar detalhe.
  {
    const port = buildFakePort({
      openResult: { outcome: "NO_CANDIDATE" },
      throwOnOpen: true,
    });
    const loggedCodes: string[] = [];
    const res = await handleJusttcgSetBootstrapRequest(
      new Request("https://x/", {
        method: "POST",
        headers: { apikey: EXPECTED_SECRET },
      }),
      {
        expectedSecret: EXPECTED_SECRET,
        port,
        pricingSourceId: PRICING_SOURCE_ID,
        buildClient: buildClientFactory([]),
        logError: (code) => {
          loggedCodes.push(code);
        },
      },
    );
    const body = await res.json();
    assert("12. exceção interna -> 500", res.status === 500);
    assert("12. corpo error=INTERNAL_ERROR", body.error === "INTERNAL_ERROR");
    assert(
      "12. log sanitizado -- só o código fixo, nunca a mensagem do Error",
      loggedCodes.length === 1 &&
        loggedCodes[0] === "JUSTTCG_SET_BOOTSTRAP_INTERNAL_ERROR",
    );
  }

  console.log(
    `\n${failures === 0 ? "TODOS OS TESTES PASSARAM" : `${failures} FALHA(S)`}`,
  );
  if (failures > 0) throw new Error(`${failures} teste(s) falharam.`);
}

Deno.test(
  "justtcg-set-bootstrap: suite offline do handler (P16.5.4)",
  main,
);
