// Project Mimikyu — Edge Function: import-catalog-cards
// Database Service — staging (catalog_import_job/row) e catálogos de apoio
// (rarity, card_category, card, card_set_external_reference, asset_source).
// `supabase: any` é deliberado, mesmo padrão de import-card-assets/services/
// database.ts: este arquivo nunca cria um cliente Supabase, sempre recebe
// um já pronto.

export async function findJob(supabase: any, jobId: string) {
  const { data, error } = await supabase
    .from("catalog_import_job")
    .select("id, card_set_id, source, external_set_id, status, progress_step")
    .eq("id", jobId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error("CATALOG_IMPORT_JOB_QUERY_FAILED");
  }
  return data;
}

export async function transitionJobToProcessing(supabase: any, jobId: string, firstStep: string) {
  const { error } = await supabase
    .from("catalog_import_job")
    .update({ status: "PROCESSING", progress_step: firstStep })
    .eq("id", jobId);

  if (error) {
    console.error("JOB TRANSITION TO PROCESSING ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`JOB_TRANSITION_TO_PROCESSING_FAILED: ${error.message}`);
  }
}

export async function updateProgressStep(supabase: any, jobId: string, step: string) {
  const { error } = await supabase
    .from("catalog_import_job")
    .update({ progress_step: step })
    .eq("id", jobId);

  if (error) {
    console.error("JOB PROGRESS STEP UPDATE ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`JOB_PROGRESS_STEP_UPDATE_FAILED: ${error.message}`);
  }
}

export async function finalizeJobStaged(
  supabase: any,
  jobId: string,
  counts: { total_rows: number; valid_rows: number },
) {
  const { error } = await supabase
    .from("catalog_import_job")
    .update({
      status: "STAGED",
      progress_step: null,
      total_rows: counts.total_rows,
      valid_rows: counts.valid_rows,
    })
    .eq("id", jobId);

  if (error) {
    console.error("JOB FINALIZE STAGED ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`JOB_FINALIZE_STAGED_FAILED: ${error.message}`);
  }
}

export async function failJob(supabase: any, jobId: string, errorSummary: string): Promise<boolean> {
  const { error } = await supabase
    .from("catalog_import_job")
    .update({ status: "FAILED", progress_step: null, error_summary: errorSummary })
    .eq("id", jobId);

  if (error) {
    console.error("JOB FAIL ERROR:", JSON.stringify(error, null, 2));
    return false;
  }
  return true;
}

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

export async function listExistingCardsMap(supabase: any, cardSetId: string) {
  const { data, error } = await supabase
    .from("card")
    .select("id, collector_number, name, rarity_id, category_id, collector_total")
    .eq("card_set_id", cardSetId);

  if (error) {
    console.error(error);
    throw new Error("EXISTING_CARDS_QUERY_FAILED");
  }
  return new Map<string, any>((data ?? []).map((card: any) => [card.collector_number, card]));
}

export async function listRaritiesByGameCode(supabase: any, gameId: string) {
  const { data, error } = await supabase.from("rarity").select("id, code, name").eq("game_id", gameId);
  if (error) {
    console.error(error);
    throw new Error("RARITY_QUERY_FAILED");
  }
  return new Map<string, any>((data ?? []).map((r: any) => [r.code, r]));
}

export async function listCategoriesByGameCode(supabase: any, gameId: string) {
  const { data, error } = await supabase.from("card_category").select("id, code, name").eq("game_id", gameId);
  if (error) {
    console.error(error);
    throw new Error("CARD_CATEGORY_QUERY_FAILED");
  }
  return new Map<string, any>((data ?? []).map((c: any) => [c.code, c]));
}

export async function findAssetSourceByCode(supabase: any, code: string) {
  const { data, error } = await supabase.from("asset_source").select("id, code, name").eq("code", code).maybeSingle();
  if (error) {
    console.error(error);
    throw new Error("ASSET_SOURCE_QUERY_FAILED");
  }
  return data;
}

export async function insertImportRows(
  supabase: any,
  jobId: string,
  rows: Array<{
    raw_data: Record<string, unknown>;
    normalized_data: Record<string, unknown>;
    validation_status: string;
    match_status: string;
    decision_status: string;
    matched_card_id: string | null;
  }>,
) {
  if (rows.length === 0) return;

  const payload = rows.map((row) => ({ job_id: jobId, ...row }));
  const { error } = await supabase.from("catalog_import_row").insert(payload);

  if (error) {
    console.error("IMPORT ROWS INSERT ERROR:", JSON.stringify(error, null, 2));
    throw new Error(`IMPORT_ROWS_INSERT_FAILED: ${error.message}`);
  }
}

export async function upsertCardSetExternalReference(
  supabase: any,
  payload: {
    card_set_id: string;
    asset_source_id: string;
    external_set_id: string;
    source_url: string;
    metadata: Record<string, unknown>;
  },
) {
  const { error } = await supabase
    .from("card_set_external_reference")
    .upsert(
      { ...payload, is_active: true, updated_at: new Date().toISOString() },
      { onConflict: "card_set_id,asset_source_id" },
    );

  if (error) {
    console.error("CARD_SET_EXTERNAL_REFERENCE_UPSERT_FAILED:", JSON.stringify(error, null, 2));
  }
}