/*
Project Mimikyu
Edge Function: import-card-variants
Incremento 2 do bloco Card Variant (ADR-028) — 2026-08-15.

Processador de importação de Card Variant: recebe um Card Set MMKYU,
resolve o external_set_id do dataset-fonte da TCGdex (github.com/tcgdex/
cards-database) via card_set_external_reference já gravada por Importar
Cartas, busca os arquivos de carta do Set inteiro (não carta a carta na
API pública), correlaciona cada Card externa com a Card MMKYU via
card_external_reference, extrai todas as combinações variants[], resolve
o mapeamento externo -> card_variant_type (Query 2140) e grava somente em
catalog_variant_import_row (staging) — nunca em card_variant (Princípio
da Fonte Canônica, ADR-024). Não cria RPC de confirmação, não tem UI,
não infere vintage/is_default/variant_order.

Diferença deliberada frente a import-catalog-cards: não existe ainda uma
tela/RPC que pré-crie o job com external_set_id resolvido (CV-02 — sem
tela dedicada no V1). Por isso esta function recebe { card_set_id } (não
{ job_id }) e cria o próprio catalog_variant_import_job internamente,
já em PROCESSING, resolvendo external_set_id antes do INSERT.

Fronteira de identidade — mesmo padrão já em produção em
import-catalog-cards/revalidate-catalog-import-rows (Finding 1 da
auditoria de segurança do Catálogo Editorial, 2026-08-13): verify_jwt=true
(supabase/config.toml) garante um JWT assinado válido, mas não basta
sozinho (pode ser só a anon key, sem usuário nenhum por trás). Um segundo
client, escopado pelo JWT recebido no cabeçalho Authorization, chama
auth.getUser() para confirmar uma sessão real e rpc('is_admin') para
confirmar o papel administrativo — só então o código segue para o client
de service role (`supabase`, abaixo), que nunca recebe o JWT do chamador.

Fonte dos arquivos de carta: TypeScript, não JSON (confirmado ao vivo
nesta frente). Nunca executamos esse conteúdo (eval/Function seria rodar
código de terceiro não confiável com service role — inaceitável) — ver
services/github-source.ts para o extrator estrutural por regex/
profundidade de colchetes, limitado aos 4 campos que interessam.
*/

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import {
  createVariantJobProcessing,
  failVariantJob,
  findAssetSourceByCode,
  findCardSetExternalReference,
  findCardSetWithGame,
  finalizeVariantJobStaged,
  insertVariantImportRows,
  listCardExternalReferencesMap,
  listExistingCardVariantsMap,
  listVariantTypeExternalMappings,
  buildVariantComboKey,
  updateVariantJobProgressStep,
} from "./services/database.ts";
import { resolveSetSerieName } from "./services/tcgdex.ts";
import {
  deriveLocalIdFromFilename,
  extractVariantsFromSource,
  fetchCardFileSource,
  listSetCardFiles,
} from "./services/github-source.ts";
import { normalizeExternalCatalogValue } from "../_shared/catalog-normalization/mod.ts";
import type { ExternalVariantCombo, RequestBody, ResolvedVariantRow } from "./types.ts";

const ASSET_SOURCE_CODE = "TCGDEX";
// Mesmo espírito de CARD_DETAIL_BATCH_SIZE (import-catalog-cards): lotes
// de concorrência limitada contra raw.githubusercontent.com, que não tem
// rate limit observado mas ainda assim não deve ser martelado sem limite.
const CARD_FILE_BATCH_SIZE = 10;

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Client de serviço — único usado para ler/escrever catalog_variant_import_
// job/row e os catálogos de apoio. Nunca recebe o JWT do chamador (ver
// Fronteira de identidade acima).
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

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

// Normaliza e ORDENA o array de stamp — mesma disciplina exigida pela
// Query 2140 (v1.1) para normalized_stamp: duas combinações com os mesmos
// stamps em ordem diferente na fonte precisam produzir a mesma chave.
function normalizeAndSortStamp(stamp: string[] | null): string[] | null {
  if (!stamp || stamp.length === 0) return null;
  return [...stamp].map((s) => normalizeExternalCatalogValue(s)).sort();
}

type CardFileResult = {
  externalCardId: string;
  cardId: string | null;
  combos: ExternalVariantCombo[];
  fetchError: string | null;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ success: false, error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: { Allow: "POST" } });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return Response.json({ success: false, error: "MISSING_AUTHORIZATION" }, { status: 401 });
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    console.error("IMPORT_CARD_VARIANTS_INVALID_USER_SESSION:", userError);
    return Response.json({ success: false, error: "INVALID_USER_SESSION" }, { status: 401 });
  }

  const { data: isAdminResult, error: isAdminError } = await userClient.rpc("is_admin");
  if (isAdminError || isAdminResult !== true) {
    console.error("IMPORT_CARD_VARIANTS_FORBIDDEN_NOT_ADMIN:", isAdminError);
    return Response.json({ success: false, error: "FORBIDDEN_NOT_ADMIN" }, { status: 403 });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json({ success: false, error: "INVALID_JSON" }, { status: 400 });
  }

  const cardSetId = body.card_set_id?.trim();
  if (!cardSetId) {
    return Response.json({ success: false, error: "CARD_SET_ID_REQUIRED" }, { status: 400 });
  }

  let jobId: string | null = null;

  try {
    const cardSet = await findCardSetWithGame(supabase, cardSetId);
    if (!cardSet) {
      return Response.json({ success: false, error: "CARD_SET_NOT_FOUND" }, { status: 404 });
    }

    const assetSource = await findAssetSourceByCode(supabase, ASSET_SOURCE_CODE);
    if (!assetSource) throw new Error(`ASSET_SOURCE_NOT_FOUND: ${ASSET_SOURCE_CODE}`);

    // Importar Variantes pressupõe Importar Cartas já concluído para o
    // Card Set — a referência externa precisa existir antes de qualquer
    // job ser criado (catalog_variant_import_job.external_set_id é NOT
    // NULL, não há valor a gravar sem ela).
    const externalReference = await findCardSetExternalReference(supabase, cardSetId, assetSource.id);
    if (!externalReference?.external_set_id) {
      return Response.json(
        { success: false, error: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND: rode Importar Cartas para este Card Set antes de Importar Variantes." },
        { status: 409 },
      );
    }
    const externalSetId = externalReference.external_set_id;

    const { job, alreadyActive } = await createVariantJobProcessing(supabase, {
      cardSetId,
      externalSetId,
      initiatedBy: userData.user.id,
    });
    if (alreadyActive || !job) {
      return Response.json(
        { success: false, error: "JOB_ALREADY_ACTIVE_FOR_CARD_SET: já existe uma importação de variantes em andamento ou em staging para este Card Set." },
        { status: 409 },
      );
    }

    // A partir daqui o job já existe e está em PROCESSING: qualquer saída
    // de erro passa por failVariantJob(), nunca deixa o job preso.
    jobId = job.id;

    const setSerieName = await resolveSetSerieName(externalSetId);

    await updateVariantJobProgressStep(supabase, jobId, "LISTING_SOURCE_FILES");
    const cardFiles = await listSetCardFiles(setSerieName.serieName, setSerieName.name);
    if (cardFiles.length === 0) {
      throw new Error("GITHUB_SOURCE_SET_FOLDER_EMPTY_OR_NOT_FOUND");
    }

    await updateVariantJobProgressStep(supabase, jobId, "FETCHING_CARD_FILES");
    const [cardExternalReferences, variantTypeMappings] = await Promise.all([
      listCardExternalReferencesMap(supabase, assetSource.id, externalSetId),
      listVariantTypeExternalMappings(supabase, cardSet.game_id, assetSource.id),
    ]);

    // Falha de UM arquivo (rede, 404, extração malformada) vira um
    // registro isolado com fetchError — nunca derruba o Set inteiro.
    const fileResults = await processInBatches<typeof cardFiles[number], CardFileResult>(
      cardFiles,
      CARD_FILE_BATCH_SIZE,
      async (file) => {
        const localId = deriveLocalIdFromFilename(file.name);
        const externalCardId = `${externalSetId}-${localId}`;
        const cardId = cardExternalReferences.get(externalCardId.toUpperCase()) ?? null;

        try {
          const source = await fetchCardFileSource(file.downloadUrl);
          const combos = extractVariantsFromSource(source);
          return { externalCardId, cardId, combos, fetchError: null };
        } catch (error) {
          const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
          console.error(`GITHUB_SOURCE_FETCH_FAILED ${externalCardId}:`, message);
          return { externalCardId, cardId, combos: [], fetchError: `GITHUB_SOURCE_FETCH_FAILED: ${message}` };
        }
      },
    );

    await updateVariantJobProgressStep(supabase, jobId, "CORRELATING_CARDS");

    const uncorrelated: string[] = [];
    const fetchFailed: string[] = [];
    const correlated = fileResults.filter((result) => {
      if (result.fetchError) {
        fetchFailed.push(result.externalCardId);
        return false;
      }
      if (!result.cardId) {
        uncorrelated.push(result.externalCardId);
        return false;
      }
      return true;
    });

    const correlatedCardIds = Array.from(new Set(correlated.map((r) => r.cardId as string)));
    const existingVariantsByCardAndType = await listExistingCardVariantsMap(supabase, correlatedCardIds);

    await updateVariantJobProgressStep(supabase, jobId, "RESOLVING_VARIANT_MAPPING");

    const resolvedRows: ResolvedVariantRow[] = [];
    const seenResolvedComboByCard = new Set<string>();
    let duplicateResolvedSkipped = 0;

    for (const result of correlated) {
      const cardId = result.cardId as string;

      for (const combo of result.combos) {
        const normalizedType = normalizeExternalCatalogValue(combo.type);
        const normalizedFoil = combo.foil ? normalizeExternalCatalogValue(combo.foil) : null;
        const normalizedSubtype = combo.subtype ? normalizeExternalCatalogValue(combo.subtype) : null;
        const normalizedStamp = normalizeAndSortStamp(combo.stamp);

        const comboKey = buildVariantComboKey(normalizedType, normalizedFoil, normalizedSubtype, normalizedStamp);
        const variantTypeId = variantTypeMappings.get(comboKey) ?? null;

        if (variantTypeId) {
          // Índice único parcial da Query 2138 (job_id, card_id,
          // variant_type_id) — dedup em memória evita que uma combinação
          // repetida na própria fonte derrube o INSERT em lote inteiro.
          const dedupeKey = `${cardId}|${variantTypeId}`;
          if (seenResolvedComboByCard.has(dedupeKey)) {
            duplicateResolvedSkipped++;
            continue;
          }
          seenResolvedComboByCard.add(dedupeKey);
        }

        const matchedVariantId = variantTypeId
          ? existingVariantsByCardAndType.get(`${cardId}|${variantTypeId}`) ?? null
          : null;

        resolvedRows.push({
          card_id: cardId,
          raw_data: { type: combo.type, foil: combo.foil, subtype: combo.subtype, stamp: combo.stamp },
          normalized_data: variantTypeId ? { variant_type_id: variantTypeId } : {},
          validation_status: variantTypeId ? "VALID" : "NEEDS_REVIEW",
          match_status: matchedVariantId ? "MATCHED" : "NEW",
          decision_status: matchedVariantId ? "SKIPPED" : "PENDING",
          matched_variant_id: matchedVariantId,
        });
      }
    }

    await updateVariantJobProgressStep(supabase, jobId, "PREPARING_REVIEW");
    await insertVariantImportRows(supabase, jobId, resolvedRows);

    const validRows = resolvedRows.filter((r) => r.validation_status === "VALID").length;
    const needsReviewRows = resolvedRows.filter((r) => r.validation_status === "NEEDS_REVIEW").length;
    const failedCards = uncorrelated.length + fetchFailed.length;

    const errorSummaryParts: string[] = [];
    if (uncorrelated.length > 0) errorSummaryParts.push(`CARDS_NAO_CORRELACIONADAS(${uncorrelated.length}): ${uncorrelated.slice(0, 10).join(", ")}`);
    if (fetchFailed.length > 0) errorSummaryParts.push(`ARQUIVOS_COM_FALHA_DE_FETCH(${fetchFailed.length}): ${fetchFailed.slice(0, 10).join(", ")}`);
    if (duplicateResolvedSkipped > 0) errorSummaryParts.push(`COMBINACOES_DUPLICADAS_IGNORADAS: ${duplicateResolvedSkipped}`);
    const errorSummary = errorSummaryParts.length > 0 ? errorSummaryParts.join(" | ") : null;

    await finalizeVariantJobStaged(
      supabase,
      jobId,
      { total_rows: resolvedRows.length, valid_rows: validRows, failed_rows: failedCards },
      errorSummary,
    );

    return Response.json({
      success: true,
      version: "1.0.0",
      job: { id: jobId, card_set_id: cardSetId, external_set_id: externalSetId },
      set: { serie: setSerieName.serieName, name: setSerieName.name, card_files: cardFiles.length },
      rows: {
        total: resolvedRows.length,
        valid: validRows,
        needs_review: needsReviewRows,
      },
      cards: {
        correlated: correlatedCardIds.length,
        uncorrelated: uncorrelated.length,
        fetch_failed: fetchFailed.length,
      },
      duplicate_resolved_skipped: duplicateResolvedSkipped,
    });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error ? error.message : "UNEXPECTED_ERROR";
    if (jobId) await failVariantJob(supabase, jobId, message);
    return Response.json({ success: false, error: message }, { status: 500 });
  }
});
