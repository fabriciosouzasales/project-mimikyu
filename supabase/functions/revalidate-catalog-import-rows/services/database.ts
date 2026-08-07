// Project Mimikyu — Edge Function: revalidate-catalog-import-rows
// Database Service — jobs em STAGED, catálogos de apoio
// (rarity_external_mapping, card_category, card, asset_source) e a RPC de
// persistência (public.svc_apply_catalog_import_revalidation, Query 2106).
// `supabase: any` é deliberado, mesmo padrão de import-catalog-cards/
// services/database.ts: este arquivo nunca cria um cliente Supabase,
// sempre recebe um já pronto (aqui, sempre o client de service role).
//
// findCardSet/findExpansionGameId/findCardSetWithGame,
// findAssetSourceByCode, listRarityExternalMappingsByGameAndSource,
// listCategoriesByGameCode e listExistingCardsMap duplicam
// propositalmente as versões equivalentes de import-catalog-cards/
// services/database.ts (Convenção #3 do projeto: responsabilidade única
// por função, sem import cruzado entre funções — só _shared/ é
// compartilhado). listRarityExternalMappingsByGameAndSource aqui já nasce
// na forma corrigida (duas consultas simples + junção em memória, sem
// select com relacionamento embutido do PostgREST) — ver o comentário de
// v1.1 na versão de import-catalog-cards (2026-08-07) para o porquê desse
// padrão ser obrigatório em vez do embed.

// v1.1 (2026-08-07, ampliação de escopo aprovada por Fabrício): passou a
// incluir CONFIRMING e COMPLETED_WITH_ERRORS além de STAGED. Motivo real:
// na prática, um job raramente fica parado em STAGED esperando uma
// raridade nova ser mapeada — o fluxo observado em produção (GYM1/SWSH1,
// 2026-08-07) foi aprovar e confirmar tudo pela tela de Revisão, inclusive
// linhas NEEDS_REVIEW, e só depois descobrir que a confirmação falhou
// (persistence_status FAILED) por raridade não mapeada. Esses jobs ficam
// em COMPLETED_WITH_ERRORS, fora do alcance de uma revalidação restrita a
// STAGED. Ver svc_apply_catalog_import_revalidation() (Query 2106 v1.2)
// para como as linhas destravadas (FAILED -> PENDING) voltam a ficar
// elegíveis para uma nova chamada de admin_confirm_catalog_import().
export async function listRevalidatableJobs(supabase: any, jobIds?: string[]) {
  let query = supabase
    .from("catalog_import_job")
    .select("id, card_set_id, source, status")
    .in("status", ["STAGED", "CONFIRMING", "COMPLETED_WITH_ERRORS"]);

  if (jobIds && jobIds.length > 0) {
    query = query.in("id", jobIds);
  }

  const { data, error } = await query;

  if (error) {
    console.error(error);
    throw new Error(`REVALIDATABLE_JOBS_QUERY_FAILED: ${error.message ?? error.code ?? "unknown"}`);
  }

  return (data ?? []) as { id: string; card_set_id: string; source: string; status: string }[];
}

export async function findCardSet(supabase: any, cardSetId: string) {
  const { data, error } = await supabase
    .from("card_set")
    .select("id, code, name, expansion_id")
    .eq("id", cardSetId)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error(`CARD_SET_QUERY_FAILED: ${error.message ?? error.code ?? "unknown"}`);
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
    throw new Error(`EXPANSION_QUERY_FAILED: ${error.message ?? error.code ?? "unknown"}`);
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
  const { data, error } = await supabase
    .from("asset_source")
    .select("id, code, name")
    .eq("code", code)
    .maybeSingle();

  if (error) {
    console.error(error);
    throw new Error(`ASSET_SOURCE_QUERY_FAILED: ${error.message ?? error.code ?? "unknown"}`);
  }
  return data;
}

export async function listRarityExternalMappingsByGameAndSource(
  supabase: any,
  gameId: string,
  assetSourceId: string,
) {
  const { data: mappingRows, error: mappingError } = await supabase
    .from("rarity_external_mapping")
    .select("normalized_external_value, rarity_id")
    .eq("game_id", gameId)
    .eq("asset_source_id", assetSourceId);

  if (mappingError) {
    console.error(mappingError);
    throw new Error(
      `RARITY_EXTERNAL_MAPPING_QUERY_FAILED: ${mappingError.message ?? mappingError.code ?? "unknown"}`,
    );
  }

  const rows = (mappingRows ?? []) as { normalized_external_value: string; rarity_id: string }[];
  if (rows.length === 0) return new Map<string, any>();

  const rarityIds = Array.from(new Set(rows.map((row) => row.rarity_id)));

  const { data: rarityRows, error: rarityError } = await supabase
    .from("rarity")
    .select("id, code, name")
    .in("id", rarityIds);

  if (rarityError) {
    console.error(rarityError);
    throw new Error(`RARITY_QUERY_FAILED: ${rarityError.message ?? rarityError.code ?? "unknown"}`);
  }

  const rarityById = new Map<string, any>((rarityRows ?? []).map((r: any) => [r.id, r]));

  return new Map<string, any>(
    rows
      .map((row) => [row.normalized_external_value, rarityById.get(row.rarity_id)] as const)
      .filter((entry): entry is [string, any] => Boolean(entry[1])),
  );
}

export async function listCategoriesByGameCode(supabase: any, gameId: string) {
  const { data, error } = await supabase.from("card_category").select("id, code, name").eq("game_id", gameId);
  if (error) {
    console.error(error);
    throw new Error(`CARD_CATEGORY_QUERY_FAILED: ${error.message ?? error.code ?? "unknown"}`);
  }
  return new Map<string, any>((data ?? []).map((c: any) => [c.code, c]));
}

export async function listExistingCardsMap(supabase: any, cardSetId: string) {
  const { data, error } = await supabase
    .from("card")
    .select("id, collector_number, name, rarity_id, category_id, collector_total")
    .eq("card_set_id", cardSetId);

  if (error) {
    console.error(error);
    throw new Error(`EXISTING_CARDS_QUERY_FAILED: ${error.message ?? error.code ?? "unknown"}`);
  }
  return new Map<string, any>((data ?? []).map((card: any) => [card.collector_number, card]));
}

// Ordenado por normalized_data.collector_order já armazenado — nunca
// recalculado a partir de uma nova posição na TCGdex, que exigiria uma
// chamada HTTP fora do escopo desta função (ver comentário de
// deriveCollectorOrder em _shared/catalog-normalization/resolve-row.ts).
// A posição de cada linha no array resultante é usada como indexInSet ao
// chamar resolveCatalogImportRow, preservando o mesmo desempate original
// para collector_number não numérico (ex. "TG01").
export async function listRowsForRevalidation(supabase: any, jobId: string) {
  const { data, error } = await supabase
    .from("catalog_import_row")
    .select("id, raw_data, normalized_data")
    .eq("job_id", jobId);

  if (error) {
    console.error(error);
    throw new Error(`CATALOG_IMPORT_ROW_QUERY_FAILED: ${error.message ?? error.code ?? "unknown"}`);
  }

  const rows = (data ?? []) as { id: string; raw_data: Record<string, unknown>; normalized_data: Record<string, unknown> }[];

  return rows.sort((a, b) => {
    const orderA = Number((a.normalized_data as any)?.collector_order ?? 0);
    const orderB = Number((b.normalized_data as any)?.collector_order ?? 0);
    return orderA - orderB;
  });
}

export async function applyRevalidation(
  supabase: any,
  jobId: string,
  rowUpdates: Array<{
    row_id: string;
    normalized_data: Record<string, unknown>;
    validation_status: string;
    match_status: string;
    matched_card_id: string | null;
  }>,
  actorId: string | null,
) {
  const { data, error } = await supabase.rpc("svc_apply_catalog_import_revalidation", {
    p_job_id: jobId,
    p_row_updates: rowUpdates,
    p_actor_id: actorId,
  });

  if (error) {
    console.error(error);
    throw new Error(
      `SVC_APPLY_CATALOG_IMPORT_REVALIDATION_FAILED: ${error.message ?? error.code ?? "unknown"}`,
    );
  }

  return Array.isArray(data) ? data[0] : data;
}

// Chamada com o client escopado pelo JWT do administrador (nunca com o de
// service role) — admin_confirm_catalog_import() (Query 2082) exige
// is_admin()/auth.uid() reais, mesma exigência de qualquer chamada feita
// pela própria tela de Revisão. Só é chamada quando
// svc_apply_catalog_import_revalidation() destravou pelo menos uma linha
// (FAILED -> PENDING) — nunca reimplementa a criação de Card aqui: essa
// continua sendo a única responsabilidade de admin_confirm_catalog_import()
// (Princípio da Fonte Canônica).
export async function confirmCatalogImport(userClient: any, jobId: string) {
  const { data, error } = await userClient.rpc("admin_confirm_catalog_import", {
    p_job_id: jobId,
    p_row_ids: null,
  });

  if (error) {
    console.error(error);
    throw new Error(`ADMIN_CONFIRM_CATALOG_IMPORT_FAILED: ${error.message ?? error.code ?? "unknown"}`);
  }

  return Array.isArray(data) ? data[0] : data;
}
