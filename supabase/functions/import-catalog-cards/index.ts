/*
Project Mimikyu
Edge Function: import-catalog-cards
Sprint 1 (2026-08-01) — deployada e validada (job SVE, 24/24 linhas VALID).
Versão 3 (2026-08-01, mesmo dia): TCGDEX_LANGUAGE corrigido de "en" para
"pt" — bug real, cartas do primeiro teste (ME5) foram cadastradas em
inglês. Versão 2 havia corrigido para "pt-br", mas testado ao vivo esse
código devolve 404 para o Set do ME5 na TCGdex (cobertura de tradução
incompleta); "pt" tem os dados completos e foi confirmado por Fabrício
como o idioma correto. Ver detalhe no comentário de TCGDEX_LANGUAGE abaixo.
Versão 4 (2026-08-01, mesmo dia): corrigido matching de raridade. Com
TCGDEX_LANGUAGE="pt", a TCGdex passou a devolver o nome da raridade em
português ("Comum", "Ultra Rara"...), mas o código comparava contra
rarity.code (inglês, "COMMON"...) — nada batia, e as 120 linhas do
primeiro reprocessamento do ME5 caíram todas em NEEDS_REVIEW (0 válidas).
Corrigido para comparar contra rarity.name (também PT), com normalização
de acentos e uma tabela de alias para os casos em que a TCGdex e o nosso
cadastro usam ordem/flexão diferentes ("Ultra Rara" vs "Rara Ultra",
"Mega Hiper Raro" vs "Mega Rara Hiper"). Mecanismo aposentado em
2026-08-06 (Versão 6 abaixo) — substituído por rarity_external_mapping.
Versão 5 (2026-08-01, mesmo dia): mesma família de bug, agora em
CATEGORY_BY_TCGDEX_VALUE — só tinha as chaves em inglês ("Pokemon"/
"Trainer"/"Energy"), mas com TCGDEX_LANGUAGE="pt" a TCGdex devolve
"Pokémon"/"Treinador"/"Energia". Cartas Treinador caíam no fallback
heurístico com confidence "LOW", forçando NEEDS_REVIEW à toa (23 linhas
do reprocessamento do ME5) mesmo com o valor final já correto. Adicionadas
as chaves em português. Ver comentário de CATEGORY_BY_TCGDEX_VALUE em
_shared/catalog-normalization/category.ts (movido nesta rodada, ver
Versão 6 abaixo).
Versão 6 (2026-08-06, cadastro self-service de Raridade): resolução de
raridade/categoria/sequência (antes em services/normalize.ts, só desta
função) extraída para _shared/catalog-normalization/ — reutilizada
também pela nova Edge Function revalidate-catalog-import-rows. A mudança
real de comportamento é a de raridade: RARITY_NAME_ALIASES (hardcoded,
exigia deploy para cada raridade nova) foi aposentada; a resolução agora
consulta rarity_external_mapping (Query 2096), cadastrável em tela
(/catalogo/raridades, "Resolver raridade"). services/normalize.ts foi
removido — resolveCollectorTotal (específico do Set da TCGdex, não do
núcleo compartilhado) mudou para services/tcgdex.ts.
Processador
TCGdex do Ciclo 2 (ADR-024): recebe um catalog_import_job (aberto por
admin_start_catalog_import(), Query 2080, com source='TCGDEX' e
external_set_id já resolvido — a localização automática do Set acontece
ANTES desta chamada, no frontend, fora desta função), busca o Set completo
na TCGdex, resolve raridade/categoria/sequência/correspondência de cada
carta, e grava em catalog_import_row — nunca em public.card diretamente
(Princípio da Fonte Canônica). Não sabe nada sobre o canal PDF.

Convenções de Edge Function do projeto (ver import-card-assets/index.ts):
1. Só existe de fato depois de `npx supabase functions new
   import-catalog-cards` — nunca criado "na mão".
3. Responsabilidade única: só TCGDEX -> staging.
6. index.ts só orquestra — SQL/TCGdex ficam em services/.
8. Cliente Supabase próprio via SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  failJob,
  findAssetSourceByCode,
  findCardSetWithGame,
  findJob,
  finalizeJobStaged,
  insertImportRows,
  listCategoriesByGameCode,
  listExistingCardsMap,
  listRarityExternalMappingsByGameAndSource,
  transitionJobToProcessing,
  updateProgressStep,
  upsertCardSetExternalReference,
} from "./services/database.ts";
import { resolveCollectorTotal, TcgdexClient, type TcgdexCardDetail } from "./services/tcgdex.ts";
import { resolveCatalogImportRow } from "../_shared/catalog-normalization/mod.ts";
import type { RequestBody } from "./types.ts";

// Idioma fixo em "pt" — não "en": nosso catálogo cadastra Cards em
// português (confirmado por Fabrício, 2026-08-01, já previsto no plano de
// implementação — `card_set` não tem dimensão de idioma própria porque o
// nome da Card "já nasce no idioma de publicação do próprio Card Set", ver
// comentário de database/schema/2060_create_catalog_import_job.sql). "en"
// era o default do TcgdexClient, usado por engano aqui sem fixar o idioma
// correto — bug corrigido nesta rodada.
//
// Não "pt-br": a documentação oficial (tcgdex.dev/errors/language-invalid)
// lista "pt", "pt-br" e "pt-pt" como três códigos de idioma distintos e
// válidos, mas a COBERTURA REAL de dados por set é o que importa na
// prática — testado ao vivo em 2026-08-01 (remediação do ME5):
// /pt-br/sets/me05 devolveu 404 (sem tradução pt-br para esse set),
// enquanto /pt/sets/me05 tem os dados completos. Fabrício confirmou "pt"
// como o correto após checar as duas URLs diretamente no navegador — a
// cobertura de "pt-br" na TCGdex é mais rala que a de "pt" genérico.
const TCGDEX_PRIMARY_LANGUAGE = "pt";
const TCGDEX_FALLBACK_LANGUAGE = "en";
const ASSET_SOURCE_CODE = "TCGDEX";
const CARD_DETAIL_BATCH_SIZE = 10;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

async function processInBatches<T, R>(
  items: T[],
  batchSize: number,
  processor: (item: T, index: number) => Promise<R>,
): Promise<R[]> {
  const results: R[] = [];
  for (let index = 0; index < items.length; index += batchSize) {
    const batch = items.slice(index, index + batchSize);
    const batchResults = await Promise.all(batch.map((item, offset) => processor(item, index + offset)));
    results.push(...batchResults);
  }
  return results;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ success: false, error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: { Allow: "POST" } });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json({ success: false, error: "INVALID_JSON" }, { status: 400 });
  }

  const jobId = body.job_id?.trim();
  if (!jobId) {
    return Response.json({ success: false, error: "JOB_ID_REQUIRED" }, { status: 400 });
  }

  let jobStarted = false;

  try {
    const job = await findJob(supabase, jobId);
    if (!job) {
      return Response.json({ success: false, error: "CATALOG_IMPORT_JOB_NOT_FOUND" }, { status: 404 });
    }
    if (job.source !== "TCGDEX") {
      return Response.json({ success: false, error: "JOB_SOURCE_NOT_TCGDEX" }, { status: 400 });
    }
    if (job.status !== "RECEIVED") {
      return Response.json({ success: false, error: `JOB_NOT_RECEIVED: status atual é ${job.status}` }, { status: 409 });
    }
    if (!job.external_set_id) {
      throw new Error("EXTERNAL_SET_ID_MISSING");
    }

    // A partir daqui o job já está PROCESSING: qualquer saída de erro passa
    // por failJob(), nunca deixa o job preso.
    jobStarted = true;
    await transitionJobToProcessing(supabase, jobId, "FETCHING_SOURCE");

    const cardSet = await findCardSetWithGame(supabase, job.card_set_id);
    if (!cardSet) throw new Error("CARD_SET_NOT_FOUND");

    // Buscado aqui (2026-08-06) — antes só era buscado depois de gravar as
    // linhas, só para a referência externa do Card Set, com fallback
    // silencioso (console.error) se não encontrado. Agora é um requisito
    // rígido: a resolução de raridade via rarity_external_mapping (Query
    // 2096) precisa de asset_source_id ANTES de montar preparedRows, não
    // depois — reaproveitado adiante para a mesma referência externa de
    // sempre, sem uma segunda consulta.
    const assetSource = await findAssetSourceByCode(supabase, ASSET_SOURCE_CODE);
    if (!assetSource) throw new Error(`ASSET_SOURCE_NOT_FOUND: ${ASSET_SOURCE_CODE}`);

let tcgdexLanguage:
  | typeof TCGDEX_PRIMARY_LANGUAGE
  | typeof TCGDEX_FALLBACK_LANGUAGE =
    TCGDEX_PRIMARY_LANGUAGE;

let tcgdex = new TcgdexClient(tcgdexLanguage);
let set;

try {
  set = await tcgdex.getSet(job.external_set_id);

  const reportedCardCount =
    set.cardCount?.official ??
    set.cardCount?.total ??
    0;

  const hasIncompleteCardList =
    reportedCardCount > 0 &&
    set.cards.length === 0;

  if (hasIncompleteCardList) {
    console.warn(
      `TCGDEX_SET_WITHOUT_CARDS: ${job.external_set_id} no idioma ${tcgdexLanguage}; tentando ${TCGDEX_FALLBACK_LANGUAGE}.`,
    );

    tcgdexLanguage = TCGDEX_FALLBACK_LANGUAGE;
    tcgdex = new TcgdexClient(tcgdexLanguage);
    set = await tcgdex.getSet(job.external_set_id);
  }
} catch (error) {
  const message =
    error instanceof Error
      ? error.message
      : String(error);

  if (message !== "TCGDEX_HTTP_404") {
    throw error;
  }

  tcgdexLanguage = TCGDEX_FALLBACK_LANGUAGE;
  tcgdex = new TcgdexClient(tcgdexLanguage);
  set = await tcgdex.getSet(job.external_set_id);
}

    await updateProgressStep(supabase, jobId, "EXTRACTING_CARDS");

    const collectorTotal = resolveCollectorTotal(set);

    // Uma chamada por carta — a listagem do Set nunca traz rarity/category/
    // dexId. Falha de UMA carta não derruba o job inteiro: vira uma linha
    // NEEDS_REVIEW com o dado mínimo do resumo, preservando as demais.
    const cardDetails = await processInBatches(
      set.cards,
      CARD_DETAIL_BATCH_SIZE,
      async (summary): Promise<{ detail: TcgdexCardDetail; fetchError: string | null }> => {
        try {
          return { detail: await tcgdex.getCard(summary.id), fetchError: null };
        } catch (error) {
          const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
          console.error(`TCGDEX getCard FAILED ${summary.id}:`, message);
          return {
            detail: { id: summary.id, localId: summary.localId, name: summary.name, category: "" },
            fetchError: `TCGDEX_CARD_DETAIL_FETCH_FAILED: ${message}`,
          };
        }
      },
    );

    // As quatro fases de resolução por carta rodam juntas, em memória, por
    // carta — não há I/O separado entre elas. progress_step ainda percorre
    // os quatro códigos em sequência, refletindo qual fase concluiu por
    // último caso o job seja consultado neste intervalo.
    await updateProgressStep(supabase, jobId, "DETECTING_RARITY");
    const rarityMappingByNormalizedValue = await listRarityExternalMappingsByGameAndSource(
      supabase,
      cardSet.game_id,
      assetSource.id,
    );
    const categoriesByCode = await listCategoriesByGameCode(supabase, cardSet.game_id);

    await updateProgressStep(supabase, jobId, "CLASSIFYING_CATEGORY");
    const existingCardsByCollectorNumber = await listExistingCardsMap(supabase, cardSet.id);

    await updateProgressStep(supabase, jobId, "VALIDATING_SEQUENCE");
    const seenCollectorNumbers = new Set<string>();
    const preparedRows = cardDetails.map(({ detail, fetchError }, index) =>
      resolveCatalogImportRow({
        rawCard: detail,
        rawData: detail as unknown as Record<string, unknown>,
        indexInSet: index,
        collectorTotal,
        rarityMappingByNormalizedValue,
        categoriesByCode,
        existingCardsByCollectorNumber,
        seenCollectorNumbers,
        extraNote: fetchError,
      })
    );

    await updateProgressStep(supabase, jobId, "MATCHING_CATALOG");
    await updateProgressStep(supabase, jobId, "PREPARING_REVIEW");

    await insertImportRows(
      supabase,
      jobId,
      preparedRows.map((row) => ({
        raw_data: row.raw_data,
        normalized_data: row.normalized_data as unknown as Record<string, unknown>,
        validation_status: row.validation_status,
        match_status: row.match_status,
        decision_status: row.decision_status,
        matched_card_id: row.matched_card_id,
      })),
    );

    // assetSource já resolvido no início da função (ver comentário acima) —
    // reaproveitado aqui, sem uma segunda consulta.
    await upsertCardSetExternalReference(supabase, {
      card_set_id: cardSet.id,
      asset_source_id: assetSource.id,
      external_set_id: job.external_set_id,
      source_url: `https://api.tcgdex.net/v2/${tcgdexLanguage}/sets/${job.external_set_id}`,
      metadata: { name: set.name, cardCount: set.cardCount ?? null },
    });

    const validRows = preparedRows.filter((r) => r.validation_status === "VALID").length;

    await finalizeJobStaged(supabase, jobId, { total_rows: preparedRows.length, valid_rows: validRows });

    return Response.json({
      success: true,
      version: "1.0.0",
      job: { id: jobId, card_set_id: cardSet.id, external_set_id: job.external_set_id },
      set: { id: set.id, name: set.name, card_count: set.cards.length },
      rows: {
        total: preparedRows.length,
        valid: validRows,
        needs_review: preparedRows.filter((r) => r.validation_status === "NEEDS_REVIEW").length,
        invalid: preparedRows.filter((r) => r.validation_status === "INVALID").length,
      },
    });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
    if (jobStarted) await failJob(supabase, jobId, message);
    return Response.json({ success: false, error: message }, { status: 500 });
  }
});