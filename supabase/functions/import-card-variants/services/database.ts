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

// Sentinela de "sem perfil de impressão declarado" nas chaves compostas
// em memória. `~` (0x7E) NAO pertence ao alfabeto de um UUID canônico
// (hex + hífen), então nenhum UUID real pode colidir com ele.
//
// É o que dá, do lado do JS, a semântica de `IS NOT DISTINCT FROM` que a
// Query 2179 usa no matching triplo do confirm: NULL casa com NULL, UUID
// casa apenas com o MESMO UUID. Um `Map` comum não tem essa semântica
// sozinho — `undefined`/`null` interpolados em template string virariam
// "undefined"/"null", strings que, por azar, também seriam comparáveis
// entre si por caminhos diferentes. O sentinela explícito elimina isso.
export const NO_PRINTING_PROFILE_KEY = "~";

export function buildPrintingProfileKeyPart(printingProfileId: string | null | undefined): string {
  return printingProfileId ?? NO_PRINTING_PROFILE_KEY;
}

// Ordem canônica da assinatura de traits.
//
// O banco grava card_printing_external_mapping.traits_signature e
// card_printing_profile.traits_signature como UUID[] ORDENADO ASCENDENTE
// por trait_id (Query 2174, selo deferido) — e a Query 2176 monta a
// composição efetiva com o mesmo `ORDER BY trait_id`. Comparar aqui por
// outra ordenação (por exemplo por `code`) produziria "profile
// inexistente" para um conjunto que EXISTE, exatamente a fragilidade que
// a Seção S28 do harness eliminou do lado SQL.
//
// Para UUID em forma canônica minúscula, a ordem lexicográfica da string
// coincide com a ordem byte-a-byte do valor — daí o toLowerCase() antes
// do sort, que torna a coincidência uma garantia e não uma suposição
// sobre como a fonte devolveu o dado.
//
// DISTINCT (correção C-2, PHASE-C-EDGE-CORRECTION-01): a assinatura é um
// CONJUNTO, não uma lista. A Query 2176 canoniza com
// `ARRAY(SELECT DISTINCT t FROM unnest(v_traits) t ORDER BY t)`; sem o
// mesmo DISTINCT aqui, dois tokens de Impressão que compartilhassem um
// trait produziriam "t1,t1,t2" — uma chave que NENHUM perfil possui — e a
// Edge devolveria NO_EXACT_PROFILE para uma composição que o banco resolve
// sem hesitar. O defeito só aparece em combinação multi-token, que é
// justamente o caso que o Model C2 existe para servir.
//
// A deduplicação é inofensiva do lado do perfil: `traits_signature` já
// chega selada, distinta e ordenada (Query 2168), então aplicar Set+sort
// sobre ela é idempotente. Um único ponto de canonicalização serve aos
// dois lados da comparação — que é o que garante que eles comparem igual.
export function buildTraitsSignatureKey(traitIds: readonly string[] | null | undefined): string {
  if (!traitIds || traitIds.length === 0) return "";
  return [...new Set(traitIds.map((id) => String(id).toLowerCase()))].sort().join(",");
}

// Mapa `${card_id}|${variant_type_id}|${printing_profile_id ?? '~'}` ->
// card_variant.id, para classificar match_status (NEW/MATCHED) sem uma
// consulta por linha. Filtrado só pelas Cards realmente correlacionadas
// neste job — nunca carrega card_variant inteiro.
//
// A chave era `${card_id}|${variant_type_id}` até a PHASE C. Sem o
// perfil ela reproduz o BLOCKER B2 do lado da Edge: uma Card com
// STANDARD-sem-perfil e STANDARD-com-SHADOWLESS colidiria na mesma
// entrada e a segunda variante — REAL e DISTINTA — seria classificada
// MATCHED contra a primeira. É o mesmo defeito que a Query 2179 fechou
// no confirm com `IS NOT DISTINCT FROM`.
export async function listExistingCardVariantsMap(
  supabase: any,
  cardIds: string[],
): Promise<Map<string, string>> {
  if (cardIds.length === 0) return new Map();

  const { data, error } = await supabase
    .from("card_variant")
    .select("id, card_id, variant_type_id, printing_profile_id")
    .in("card_id", cardIds);

  if (error) {
    console.error(error);
    throw new Error("CARD_VARIANT_QUERY_FAILED");
  }

  return new Map<string, string>(
    (data ?? []).map((row: any) => [
      `${row.card_id}|${row.variant_type_id}|${buildPrintingProfileKeyPart(row.printing_profile_id)}`,
      row.id,
    ]),
  );
}

// ---------------------------------------------------------------------
// PRINTING ROUTING — dois preloads, duas queries, zero consulta por row.
// ---------------------------------------------------------------------

export type PrintingExternalMappingRow = {
  id: string;
  game_id: string;
  asset_source_id: string;
  raw_field: string;
  normalized_token: string;
  traits_signature: string[] | null;
  is_active: boolean;
};

// TODOS os mappings do Game+Fonte, ativos E inativos — em UMA query.
//
// O filtro de is_active NAO acontece aqui de propósito: a distinção entre
// "token com mapping ativo" e "token historicamente conhecido, porém sem
// mapping ativo" é justamente o que separa RESOLVED de
// NEEDS_REVIEW_INACTIVE_MAPPING (Seção S8 do harness). Filtrar no banco
// apagaria o segundo caso e o token voltaria ao residual — o que o
// reclassificaria como ACABAMENTO, recriando a explosão combinatória que
// o modelo de Printing existe para eliminar.
//
// traits_signature basta como composição: o selo (Query 2174) é DEFERIDO
// mas comita junto com o cabeçalho, então todo mapping já visível a um
// leitor externo está selado. Ler a N:N aqui seria uma query a mais sem
// nenhuma informação nova.
export async function listPrintingExternalMappings(
  supabase: any,
  gameId: string,
  assetSourceId: string,
): Promise<PrintingExternalMappingRow[]> {
  const { data, error } = await supabase
    .from("card_printing_external_mapping")
    .select("id, game_id, asset_source_id, raw_field, normalized_token, traits_signature, is_active")
    .eq("game_id", gameId)
    .eq("asset_source_id", assetSourceId);

  if (error) {
    console.error(error);
    throw new Error("CARD_PRINTING_EXTERNAL_MAPPING_QUERY_FAILED");
  }

  return (data ?? []) as PrintingExternalMappingRow[];
}

export type PrintingProfileRow = {
  id: string;
  game_id: string;
  traits_signature: string[] | null;
  is_active: boolean;
};

// Perfis ATIVOS do Game — em UMA query. Aqui o filtro de is_active é
// correto e desejado: um perfil inativo não é resolução válida, e a
// ausência de perfil exato é um estado terminal próprio (NEEDS_REVIEW,
// chave ausente), nunca um convite a criar perfil automaticamente.
export async function listActivePrintingProfiles(
  supabase: any,
  gameId: string,
): Promise<PrintingProfileRow[]> {
  const { data, error } = await supabase
    .from("card_printing_profile")
    .select("id, game_id, traits_signature, is_active")
    .eq("game_id", gameId)
    .eq("is_active", true);

  if (error) {
    console.error(error);
    throw new Error("CARD_PRINTING_PROFILE_QUERY_FAILED");
  }

  return (data ?? []) as PrintingProfileRow[];
}

export type PrintingTraitRow = {
  id: string;
  game_id: string;
  is_active: boolean;
};

// TODAS as Características de Impressão do Game — ativas E inativas — em
// UMA query (correção C-1, PHASE-C-EDGE-CORRECTION-01).
//
// Por que a Edge precisa disto: a Query 2176 tem um estado terminal
// próprio, NEEDS_REVIEW_INACTIVE_TRAIT, avaliado DEPOIS de montar a
// composição e ANTES de procurar o perfil. Sem esta leitura a Edge não
// tinha como reproduzi-lo: um trait desativado deixa o perfil que o
// contém ATIVO (nenhum guard acopla card_printing_trait.is_active a
// card_printing_profile.is_active), então a Edge resolvia com perfil e
// marcava VALID exatamente a linha que o banco recusa. A linha nasceria
// VALID e mudaria de estado na primeira ação editorial, sem que ninguém
// tivesse decidido nada sobre ela.
//
// A Query 2182 já previa este consumidor: ela concede SELECT em
// card_printing_trait ao service_role e diz, textualmente, "SÓ para saber
// is_active (estado 3: trait inativo -> NEEDS_REVIEW)". O grant existia;
// faltava exercê-lo.
//
// Só id/game_id/is_active: nome, código e ordem de exibição são assunto
// de tela administrativa, não de roteamento. Nenhuma leitura da N:N — a
// composição continua vindo das assinaturas seladas.
export async function listPrintingTraits(
  supabase: any,
  gameId: string,
): Promise<PrintingTraitRow[]> {
  const { data, error } = await supabase
    .from("card_printing_trait")
    .select("id, game_id, is_active")
    .eq("game_id", gameId);

  if (error) {
    console.error(error);
    throw new Error("CARD_PRINTING_TRAIT_QUERY_FAILED");
  }

  return (data ?? []) as PrintingTraitRow[];
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
