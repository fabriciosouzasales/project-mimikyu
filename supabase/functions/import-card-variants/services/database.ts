// Project Mimikyu — Edge Function: import-card-variants
// Database Service — staging (catalog_variant_import_job/row) e
// catálogos de apoio (card_external_reference, card_set_external_
// reference, card_variant_type_external_mapping, card_variant, asset_
// source). `supabase: any` é deliberado, mesmo padrão de
// import-catalog-cards/services/database.ts: este arquivo nunca cria um
// cliente Supabase, sempre recebe um já pronto (service role).
//
// findCardSet/findExpansionGameId/findCardSetWithGame/findAssetSourceByCode
// são cópias funcionalmente idênticas às de import-catalog-cards — a
// duplicação é deliberada (Convenção #3 do projeto: sem import cruzado
// entre Edge Functions), não descuido.

export async function findCardSet(supabase: any, cardSetId: string) {
  const { data, error } = await supabase
    .from("card_set")
    .select("id, code, name, total_set_size, expansion_id")
    .eq("id", cardSetId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_QUERY_FAILED");
  }
  return data;
}

export async function findExpansionGameId(supabase: any, expansionId: string) {
  const { data, error } = await supabase
    .from("expansion")
    .select("game_id")
    .eq("id", expansionId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("EXPANSION_QUERY_FAILED");
  }
  return data?.game_id ?? null;
}

export async function findCardSetWithGame(supabase: any, cardSetId: string) {
  const cardSet = await findCardSet(supabase, cardSetId);
  if (!cardSet) return null;

  const gameId = await findExpansionGameId(supabase, cardSet.expansion_id);
  if (!gameId) {
    throw new Error("CARD_SET_GAME_NOT_FOUND");
  }

  return { ...cardSet, game_id: gameId };
}

export async function findAssetSourceByCode(supabase: any, code: string) {
  const { data, error } = await supabase.from("asset_source").select("id, code, name").eq("code", code).maybeSingle();
  if (error) {
    console.error(error);
    throw new Error("ASSET_SOURCE_QUERY_FAILED");
  }
  return data;
}

// Resolve o external_set_id do dataset-fonte a partir da referência já
// gravada por Importar Cartas (upsertCardSetExternalReference,
// import-catalog-cards) — pressuposto explícito desta frente: Importar
// Variantes pressupõe Importar Cartas já concluído para o Card Set.
export async function findCardSetExternalReference(supabase: any, cardSetId: string, assetSourceId: string) {
  const { data, error } = await supabase
    .from("card_set_external_reference")
    .select("external_set_id")
    .eq("card_set_id", cardSetId)
    .eq("asset_source_id", assetSourceId)
    .eq("is_active", true)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CARD_SET_EXTERNAL_REFERENCE_QUERY_FAILED");
  }
  return data;
}

// Mapa external_card_id (normalizado em maiúsculas) -> card_id, para
// correlacionar cada arquivo de carta do GitHub com a Card MMKYU já
// cadastrada. Comparação em maiúsculas: o formato exato de
// external_card_id não tem uma regra de caixa documentada além de
// "{external_set_id}-{localId}" — normalizar os dois lados evita uma
// falha de correlação só por diferença de caixa.
export async function listCardExternalReferencesMap(
  supabase: any,
  assetSourceId: string,
  externalSetId: string,
): Promise<Map<string, string>> {
  const { data, error } = await supabase
    .from("card_external_reference")
    .select("external_card_id, card_id")
    .eq("asset_source_id", assetSourceId)
    .eq("external_set_id", externalSetId);

  if (error) {
    console.error(error);
    throw new Error("CARD_EXTERNAL_REFERENCE_QUERY_FAILED");
  }

  return new Map<string, string>(
    (data ?? []).map((row: any) => [String(row.external_card_id).trim().toUpperCase(), row.card_id]),
  );
}

// Chave composta que replica exatamente o mecanismo de unicidade da Query
// 2140 (uq_card_variant_type_external_mapping_combo): normalized_type +
// COALESCE(normalized_foil,'') + COALESCE(normalized_subtype,'') +
// COALESCE(normalized_stamp,'{}'). normalizedStamp já deve chegar
// ORDENADO — quem chama (index.ts, para o dado da carta) e a própria
// seed (Query 2142, para os mapeamentos) seguem a mesma disciplina.
export function buildVariantComboKey(
  normalizedType: string,
  normalizedFoil: string | null,
  normalizedSubtype: string | null,
  normalizedStampSorted: string[] | null,
): string {
  return [
    normalizedType,
    normalizedFoil ?? "",
    normalizedSubtype ?? "",
    (normalizedStampSorted ?? []).join(","),
  ].join("|");
}

// Mapa chave-composta -> variant_type_id, pré-carregado uma vez por job
// (1 query) — nunca uma consulta por combinação.
export async function listVariantTypeExternalMappings(
  supabase: any,
  gameId: string,
  assetSourceId: string,
): Promise<Map<string, string>> {
  const { data, error } = await supabase
    .from("card_variant_type_external_mapping")
    .select("normalized_type, normalized_foil, normalized_subtype, normalized_stamp, variant_type_id")
    .eq("game_id", gameId)
    .eq("asset_source_id", assetSourceId);

  if (error) {
    console.error(error);
    throw new Error("CARD_VARIANT_TYPE_EXTERNAL_MAPPING_QUERY_FAILED");
  }

  return new Map<string, string>(
    (data ?? []).map((row: any) => [
      buildVariantComboKey(row.normalized_type, row.normalized_foil, row.normalized_subtype, row.normalized_stamp),
      row.variant_type_id,
    ]),
  );
}

// Mapa `${card_id}|${variant_type_id}` -> card_variant.id, para
// classificar match_status (NEW/MATCHED) sem uma consulta por linha.
// Filtrado só pelas Cards realmente correlacionadas neste job — nunca
// carrega card_variant inteiro.
export async function listExistingCardVariantsMap(
  supabase: any,
  cardIds: string[],
): Promise<Map<string, string>> {
  if (cardIds.length === 0) return new Map();

  const { data, error } = await supabase
    .from("card_variant")
    .select("id, card_id, variant_type_id")
    .in("card_id", cardIds);

  if (error) {
    console.error(error);
    throw new Error("CARD_VARIANT_QUERY_FAILED");
  }

  return new Map<string, string>(
    (data ?? []).map((row: any) => [`${row.card_id}|${row.variant_type_id}`, row.id]),
  );
}

// Cria o job já em PROCESSING (RECEIVED é instantâneo demais para
// justificar dois round-trips separados, diferente do fluxo de Importar
// Cartas onde o job pré-existe via RPC própria — aqui não há RPC/tela
// neste incremento). O índice único parcial da Query 2136
// (card_set_id, external_set_id, status não-terminal) é o mecanismo de
// idempotência: uma violação aqui significa um job já ativo para este
// Card Set, devolvida como erro específico para o chamador tratar sem
// precisar inspecionar o código do banco.
export async function createVariantJobProcessing(
  supabase: any,
  payload: { cardSetId: string; externalSetId: string; initiatedBy: string | null },
): Promise<{ job: { id: string } | null; alreadyActive: boolean }> {
  const { data, error } = await supabase
    .from("catalog_variant_import_job")
    .insert({
      card_set_id: payload.cardSetId,
      source: "TCGDEX",
      external_set_id: payload.externalSetId,
      status: "PROCESSING",
      progress_step: "RESOLVING_SOURCE",
      initiated_by: payload.initiatedBy,
    })
    .select("id")
    .single();

  if (error) {
    if (error.code === "23505") {
      return { job: null, alreadyActive: true };
    }
    console.error("VARIANT JOB CREATE ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`VARIANT_JOB_CREATE_FAILED: ${error.message}`);
  }

  return { job: data, alreadyActive: false };
}

export async function updateVariantJobProgressStep(supabase: any, jobId: string, step: string) {
  const { error } = await supabase
    .from("catalog_variant_import_job")
    .update({ progress_step: step })
    .eq("id", jobId);

  if (error) {
    console.error("VARIANT JOB PROGRESS STEP UPDATE ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`VARIANT_JOB_PROGRESS_STEP_UPDATE_FAILED: ${error.message}`);
  }
}

// Só total_rows/valid_rows/failed_rows nesta etapa — mesma disciplina de
// finalizeJobStaged (import-catalog-cards): rejected_rows/inserted_rows/
// unchanged_rows/skipped_rows são conceitos de confirmação (Incremento 3,
// não criado aqui), recalculados por agregação quando essa etapa existir.
// failed_rows aqui conta Cards que NÃO viraram linha nenhuma (falha de
// fetch do arquivo-fonte ou correlação sem correspondência em
// card_external_reference) — nunca incrementado ad hoc, somado uma única
// vez no fim do processamento do Set.
export async function finalizeVariantJobStaged(
  supabase: any,
  jobId: string,
  counts: { total_rows: number; valid_rows: number; failed_rows: number },
  errorSummary: string | null,
) {
  const { error } = await supabase
    .from("catalog_variant_import_job")
    .update({
      status: "STAGED",
      progress_step: null,
      total_rows: counts.total_rows,
      valid_rows: counts.valid_rows,
      failed_rows: counts.failed_rows,
      error_summary: errorSummary,
    })
    .eq("id", jobId);

  if (error) {
    console.error("VARIANT JOB FINALIZE STAGED ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`VARIANT_JOB_FINALIZE_STAGED_FAILED: ${error.message}`);
  }
}

export async function failVariantJob(supabase: any, jobId: string, errorSummary: string): Promise<boolean> {
  const { error } = await supabase
    .from("catalog_variant_import_job")
    .update({ status: "FAILED", progress_step: null, error_summary: errorSummary })
    .eq("id", jobId);

  if (error) {
    console.error("VARIANT JOB FAIL ERROR:", JSON.stringify(error, null, 2));
    return false;
  }
  return true;
}

export async function insertVariantImportRows(
  supabase: any,
  jobId: string,
  rows: Array<{
    card_id: string;
    raw_data: Record<string, unknown>;
    normalized_data: Record<string, unknown>;
    validation_status: string;
    match_status: string;
    decision_status: string;
    matched_variant_id: string | null;
  }>,
) {
  if (rows.length === 0) return;

  const payload = rows.map((row) => ({ job_id: jobId, ...row }));
  const { error } = await supabase.from("catalog_variant_import_row").insert(payload);

  if (error) {
    console.error("VARIANT IMPORT ROWS INSERT ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`VARIANT_IMPORT_ROWS_INSERT_FAILED: ${error.message}`);
  }
}
