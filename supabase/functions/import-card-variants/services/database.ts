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

// =====================================================================
// FALLBACK DE CORRELAÇÃO POR LINEAGE (VARIANT-CARD-CORRELATION-FALLBACK-01,
// 2026-09-18)
//
// POR QUE ISTO EXISTE. `card_external_reference` não tem writer SQL algum
// (0 funções com INSERT nela, verificado no LIVE): quem a escreve é a Edge
// Function `import-card-assets`. Consequência medida: 34 Card Sets nunca
// rodaram Importar Imagens e, por isso, 727 Cards ficaram sem referência —
// travando Importar Variantes por um motivo que nada tem a ver com
// Variantes. Isto acoplava indevidamente Variant Import a Asset Import.
//
// POR QUE NÃO UM BACKFILL. `card_external_reference` tem `language_id`
// NOT NULL dentro das DUAS constraints de unicidade
// (uq_..._card_source_language e uq_..._source_external_language). Uma
// linha ali afirma "esta Card tem este id externo NESTE IDIOMA". O lineage
// (catalog_import_job/row) NÃO tem coluna de idioma em nenhum dos dois
// níveis — e a cobertura por idioma é desigual no LIVE (en 20.128 /
// pt-BR 11.981). Criar referências a partir do lineage obrigaria a
// inventar uma dimensão que o dado de origem não prova. Não inventamos.
//
// POR QUE O LINEAGE BASTA AQUI. A correlação de Variantes é
// language-free de ponta a ponta: o dataset-fonte no GitHub não tem
// idioma (ver services/tcgdex.ts — "en" é convenção de nome de pasta, não
// idioma de conteúdo) e `listCardExternalReferencesMap` acima nem sequer
// filtra `language_id`. Este fallback não introduz essa assimetria — ele a
// resolve, lendo uma fonte que genuinamente não tem idioma.
//
// AUTORIDADE. Este mapa é SEMPRE subordinado: quem consulta tenta primeiro
// `listCardExternalReferencesMap` e só cai aqui em ausência (ver index.ts,
// fase CORRELATING_CARDS). Lineage nunca sobrescreve referência existente.
//
// EQUIVALÊNCIA PROVADA NO LIVE (2026-09-18, read-only, 169 Sets elegíveis):
// das 16.705 Cards, 15.978 têm referência E lineage — e as duas concordam
// em 15.978/15.978, com 0 divergências. As 727 restantes têm apenas
// lineage. Ambiguidade em qualquer direção: 0. Ou seja, o fallback não é
// uma aproximação da referência; onde ambos existem, são o mesmo valor.
// =====================================================================

// Tamanho de página da leitura de lineage. O PostgREST tem um teto padrão
// de linhas por resposta que NÃO se anuncia: uma leitura que o ultrapasse
// volta truncada e silenciosamente correta em aparência — e um mapa de
// correlação truncado vira Card "uncorrelated" sem nenhum erro. Por isso a
// leitura abaixo pagina explicitamente até exaurir, em vez de confiar no
// default. Máximo observado no LIVE em 2026-09-18: 567 linhas de lineage
// em um único Set — folgado hoje, mas isso é uma MEDIÇÃO, não um contrato:
// reimportações somam linhas ao mesmo Card Set ao longo do tempo.
const LINEAGE_PAGE_SIZE = 1000;

// Guard de segurança do laço de paginação: nunca fica preso se a fonte
// devolver páginas cheias indefinidamente. 200 páginas = 200.000 linhas,
// ~350x o maior Set observado.
const LINEAGE_MAX_PAGES = 200;

/**
 * Mapa external_card_id (UPPER/TRIM) -> card_id reconstruído a partir do
 * lineage de Importar Cartas, para uso EXCLUSIVO como fallback de
 * correlação quando `card_external_reference` não existe para a Card.
 *
 * Filtros de leitura (todos obrigatórios, nenhum opcional):
 *   - catalog_import_job.source      = 'TCGDEX'
 *   - catalog_import_job.card_set_id = cardSetId
 *   - catalog_import_job.external_set_id = externalSetId
 *   - catalog_import_job.status IN ('COMPLETED','COMPLETED_WITH_ERRORS')
 *   - catalog_import_row.resulting_card_id IS NOT NULL
 *   - raw_data->>'id' não nulo e não vazio
 *
 * Guards de identidade (fail-closed, nunca "pega o primeiro"):
 *   G0  resulting_card_id precisa pertencer ao PRÓPRIO cardSetId
 *   G1  external_id -> exatamente 1 card_id
 *   G2  card_id     -> exatamente 1 external_id
 *   G3  external_id precisa começar com "<externalSetId>-"
 *   G4  qualquer ambiguidade remove a identidade inteira do mapa, dos dois
 *       lados, resultando em `uncorrelated` lá na frente
 *
 * O filtro por status terminal é o que mantém o mapa estável: job em
 * PROCESSING/STAGED ainda pode mudar de ideia sobre resulting_card_id.
 *
 * >>> POR QUE G0 EXISTE E NÃO É REDUNDANTE COM O FILTRO DO JOB <<<
 * Filtrar `catalog_import_job.card_set_id = cardSetId` prova que o JOB é do
 * Card Set certo. Não prova nada sobre o destino de cada linha:
 * `fk_catalog_import_row_resulting_card` é `REFERENCES card(id)`, ou seja,
 * garante que a Card EXISTE — jamais que ela pertence a este Card Set. Um
 * job legítimo do Set A com uma linha histórica ou corrompida apontando
 * para uma Card do Set B passaria por todos os outros guards: o job é do
 * Set A, o status é terminal, o `raw_data.id` tem o prefixo certo, e a
 * identidade é 1:1. O resultado seria uma Variante criada na Card errada,
 * em silêncio. G0 fecha exatamente esse buraco, e é o único guard aqui que
 * depende de um dado fora do par job/row.
 */
/**
 * Universo de Cards que REALMENTE pertencem a um Card Set — a AUTORIDADE
 * canônica de `public.card`, não `total_set_size`, não a contagem de
 * arquivos do GitHub, não o snapshot de `catalog_import_row`, não a
 * contagem de referências externas.
 *
 * Extraída de `listCardLineageCorrelationMap()` em SOURCE-VARIANT-SAFETY-01
 * / CORRECTION-01 porque passou a ter DOIS consumidores: o G0 do fallback de
 * lineage (pertença) e o guard de cobertura da Edge (completude). A mesma
 * leitura serve aos dois — `listCardLineageCorrelationMap` aceita o conjunto
 * já carregado no 4º parâmetro, então o número de consultas por job NÃO
 * aumentou: continua sendo UMA leitura de `card` por Set.
 *
 * Paginada e fail-closed pelo mesmo motivo do lineage: um universo truncado
 * é indistinguível de um universo completo, e aqui ele decidiria se um Set
 * inteiro é aprovado ou reprovado.
 */
export async function listCardIdsOfCardSet(
  supabase: any,
  cardSetId: string,
): Promise<Set<string>> {
  const cardIdsOfSet = new Set<string>();
  if (!cardSetId) return cardIdsOfSet;

  for (let page = 0; page < LINEAGE_MAX_PAGES; page += 1) {
    const from = page * LINEAGE_PAGE_SIZE;
    const { data, error } = await supabase
      .from("card")
      .select("id")
      .eq("card_set_id", cardSetId)
      .order("id", { ascending: true })
      .range(from, from + LINEAGE_PAGE_SIZE - 1);

    if (error) {
      console.error(error);
      throw new Error("CARD_SET_MEMBERSHIP_QUERY_FAILED");
    }

    const batch = data ?? [];
    for (const card of batch) {
      if (card?.id) cardIdsOfSet.add(card.id);
    }
    if (batch.length < LINEAGE_PAGE_SIZE) break;

    // Mesma disciplina do laço de lineage: nunca truncar em silêncio. Um
    // universo de pertença incompleto reprovaria Cards legítimas (G0
    // rejeita o que não conhece) — erro seguro, mas erro. Falhar alto.
    if (page === LINEAGE_MAX_PAGES - 1) {
      throw new Error(
        `CARD_SET_MEMBERSHIP_PAGINATION_EXHAUSTED: mais de ${LINEAGE_MAX_PAGES * LINEAGE_PAGE_SIZE} Cards no Card Set ${cardSetId}.`,
      );
    }
  }

  return cardIdsOfSet;
}

export async function listCardLineageCorrelationMap(
  supabase: any,
  cardSetId: string,
  externalSetId: string,
  // Conjunto de pertença já carregado (ou a Promise dele) — permite ao
  // chamador reaproveitar a MESMA leitura em vez de duplicá-la. Omitido,
  // a função carrega por conta própria e o comportamento é idêntico ao
  // anterior, bit a bit.
  cardIdsOfSetPrefetch?: Set<string> | Promise<Set<string>>,
): Promise<Map<string, string>> {
  const empty = new Map<string, string>();
  if (!cardSetId || !externalSetId) return empty;

  // Passo 1 — jobs elegíveis do PRÓPRIO Card Set. Ancorar em card_set_id E
  // external_set_id (e não em um só) é deliberado: são duas âncoras
  // independentes para a mesma verdade, e o LIVE de 2026-09-18 mostra
  // 0 divergências entre elas em 17.632 linhas.
  const { data: jobs, error: jobsError } = await supabase
    .from("catalog_import_job")
    .select("id")
    .eq("card_set_id", cardSetId)
    .eq("source", "TCGDEX")
    .eq("external_set_id", externalSetId)
    .in("status", ["COMPLETED", "COMPLETED_WITH_ERRORS"]);

  if (jobsError) {
    console.error(jobsError);
    throw new Error("CATALOG_IMPORT_JOB_LINEAGE_QUERY_FAILED");
  }

  const jobIds = (jobs ?? []).map((job: any) => job.id).filter(Boolean);
  if (jobIds.length === 0) return empty;

  // Passo 2 — universo de Cards que REALMENTE pertencem a este Card Set
  // (base do G0). Reaproveita a leitura já feita pelo chamador quando ela
  // existe; senão carrega por conta própria. Em ambos os casos o conjunto é
  // carregado inteiro e a checagem de pertença vira um `Set.has()` em
  // memória — nunca uma consulta por linha.
  const cardIdsOfSet = cardIdsOfSetPrefetch !== undefined
    ? await cardIdsOfSetPrefetch
    : await listCardIdsOfCardSet(supabase, cardSetId);

  if (cardIdsOfSet.size === 0) return empty;

  // Passo 3 — linhas desses jobs, paginadas até exaurir.
  const rows: Array<{ raw_data: any; resulting_card_id: string }> = [];
  for (let page = 0; page < LINEAGE_MAX_PAGES; page += 1) {
    const from = page * LINEAGE_PAGE_SIZE;
    const { data, error } = await supabase
      .from("catalog_import_row")
      .select("raw_data, resulting_card_id")
      .in("job_id", jobIds)
      .not("resulting_card_id", "is", null)
      .order("id", { ascending: true })
      .range(from, from + LINEAGE_PAGE_SIZE - 1);

    if (error) {
      console.error(error);
      throw new Error("CATALOG_IMPORT_ROW_LINEAGE_QUERY_FAILED");
    }

    const batch = data ?? [];
    rows.push(...batch);
    if (batch.length < LINEAGE_PAGE_SIZE) break;

    // Página cheia na última iteração permitida: a leitura PODE estar
    // incompleta e um mapa incompleto é indistinguível de um mapa correto.
    // Fail-closed e ruidoso, nunca truncar em silêncio.
    if (page === LINEAGE_MAX_PAGES - 1) {
      throw new Error(
        `CATALOG_IMPORT_ROW_LINEAGE_PAGINATION_EXHAUSTED: mais de ${LINEAGE_MAX_PAGES * LINEAGE_PAGE_SIZE} linhas de lineage para o Card Set ${cardSetId}.`,
      );
    }
  }

  // Passo 4 — normalização + G0 (pertença ao Card Set) + G3 (pertencimento
  // ao Set externo esperado).
  const expectedPrefix = `${String(externalSetId).trim().toUpperCase()}-`;
  const byKey = new Map<string, Set<string>>();
  const byCard = new Map<string, Set<string>>();

  for (const row of rows) {
    const cardId = row?.resulting_card_id;
    if (!cardId) continue;
    if (!cardIdsOfSet.has(cardId)) continue; // G0

    const rawId = row?.raw_data?.id;
    if (typeof rawId !== "string") continue;

    const key = rawId.trim().toUpperCase();
    if (key.length === 0) continue;
    if (!key.startsWith(expectedPrefix)) continue; // G3

    if (!byKey.has(key)) byKey.set(key, new Set<string>());
    byKey.get(key)!.add(cardId);

    if (!byCard.has(cardId)) byCard.set(cardId, new Set<string>());
    byCard.get(cardId)!.add(key);
  }

  // Passo 5 — G1/G2/G4. Só sobrevive a identidade 1:1 nas DUAS direções.
  const result = new Map<string, string>();
  for (const [key, cardIds] of byKey) {
    if (cardIds.size !== 1) continue; // G1 + G4
    const cardId = [...cardIds][0];
    if ((byCard.get(cardId)?.size ?? 0) !== 1) continue; // G2 + G4
    result.set(key, cardId);
  }

  return result;
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

// Mapas chave-composta -> variant_type_id, pré-carregados uma vez por job
// (1 query) — nunca uma consulta por combinação.
//
// >>> ESCOPO (GATE-A-REV-01) <<<
// Devolve DOIS mapas, particionados por escopo. A chave composta NÃO muda:
// o escopo separa os MAPAS, não entra na CHAVE. Assim a correspondência 1:1
// entre buildVariantComboKey() e a expressão dos índices parciais da Query
// 2191 fica preservada, e a única função já provada contra a UNIQUE não
// precisa ser reescrita.
//
// A partição é feita NO CLIENTE, de propósito. Filtrar no servidor exigiria
// `.or("external_set_id.is.null,external_set_id.eq.<valor>")` com o valor
// interpolado na gramática do PostgREST, onde vírgula e parênteses são
// ESTRUTURA e não literal — superfície de escaping que não temos como provar
// correta para todo external_set_id possível. Continua sendo UMA query por
// job; o conjunto é pequeno (70 mappings no LIVE em 2026-09-14).
export async function listVariantTypeExternalMappings(
  supabase: any,
  gameId: string,
  assetSourceId: string,
  scopeExternalSetId: string | null,
): Promise<{ globalMap: Map<string, string>; scopedMap: Map<string, string> }> {
  const { data, error } = await supabase
    .from("card_variant_type_external_mapping")
    .select("normalized_type, normalized_foil, normalized_subtype, normalized_stamp, external_set_id, variant_type_id")
    .eq("game_id", gameId)
    .eq("asset_source_id", assetSourceId);

  if (error) {
    console.error(error);
    throw new Error("CARD_VARIANT_TYPE_EXTERNAL_MAPPING_QUERY_FAILED");
  }

  const globalMap = new Map<string, string>();
  const scopedMap = new Map<string, string>();

  for (const row of (data ?? []) as any[]) {
    const key = buildVariantComboKey(
      row.normalized_type,
      row.normalized_foil,
      row.normalized_subtype,
      row.normalized_stamp,
    );
    if (row.external_set_id === null || row.external_set_id === undefined) {
      globalMap.set(key, row.variant_type_id);
    } else if (scopeExternalSetId !== null && row.external_set_id === scopeExternalSetId) {
      scopedMap.set(key, row.variant_type_id);
    }
    // Escopos de OUTROS Sets sao descartados: nunca entram em nenhum mapa.
    // E o espelho exato do isolamento provado pelo vetor P3.
  }

  return { globalMap, scopedMap };
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

// Sentinela do TERCEIRO eixo. Mesma razão, mesmo alfabeto: `~` (0x7E) não
// pertence a um UUID canônico, então nenhum UUID real colide com ele.
//
// Um sentinela SEPARADO do de Printing não é preciosismo: as duas partes
// ocupam posições distintas na chave e precisam ser lidas de forma
// independente em telemetria e log. Reaproveitar a mesma constante tornaria
// impossível distinguir "sem tiragem" de "sem contexto" ao inspecionar a
// chave crua.
export const NO_EDITION_CONTEXT_KEY = "~";

export function buildEditionContextKeyPart(
  editionContextProfileId: string | null | undefined,
): string {
  return editionContextProfileId ?? NO_EDITION_CONTEXT_KEY;
}

// IDENTIDADE CANÔNICA DE UMA VARIANTE, EM UM ÚNICO LUGAR.
//
// Card + Variant Type + Perfil de Impressão + Perfil de Contexto de Edição.
// São os QUATRO componentes que a Query 2179 compara com
// `IS NOT DISTINCT FROM` no confirm, e que a Query 2209 sela como índice
// único de identidade.
//
// POR QUE UM HELPER, E NÃO TRÊS TEMPLATES IGUAIS: esta chave é montada em
// três lugares — o dedupe de linhas resolvidas, o lookup de matching
// (MATCHED × NEW) e o mapa de variantes já existentes. Enquanto os três
// fossem literais independentes, bastava um deles esquecer um componente
// para que o mapa e o lookup deixassem de casar, em silêncio: toda linha
// viraria NEW, ou — pior — duas Variants REAIS que diferem só no eixo novo
// colidiriam na mesma entrada e a segunda seria classificada MATCHED contra
// a primeira e nunca criada. É o mesmo defeito que a Query 2179 fechou do
// lado do banco, e é bloqueante, não cosmético. Com um único construtor, a
// divergência deixa de ser possível por construção.
//
// Devolve a chave NUA. Prefixos de espaço de dedupe (`R|`) são
// responsabilidade de quem deduplica, porque pertencem ao espaço de chaves,
// não à identidade.
export function buildVariantIdentityKey(
  cardId: string,
  variantTypeId: string | null,
  printingProfileId: string | null | undefined,
  editionContextProfileId: string | null | undefined,
): string {
  return `${cardId}|${variantTypeId}|${buildPrintingProfileKeyPart(printingProfileId)}|${
    buildEditionContextKeyPart(editionContextProfileId)
  }`;
}

// TRI-STATE de normalized_data — os três desfechos das Queries 2221/2222, na
// mesma ordem.
//
//   A. Impressão resolvida + Contexto resolvido + Variant Type resolvido
//      -> as TRÊS chaves presentes, VALID.
//
//   B. Impressão e Contexto resolvidos + Variant Type NÃO resolvido
//      -> os dois perfis permanecem explícitos (JSON null ou UUID); o
//      variant_type_id é que fica de fora. NEEDS_REVIEW.
//
//   C. Impressão OU Contexto não resolvido
//      -> NENHUMA chave, NEEDS_REVIEW.
//
// O porquê de C ser mais severo do que parece: cada eixo consome os tokens
// que lhe pertencem ANTES de o resíduo seguir adiante. Se um eixo não
// resolveu, o resíduo foi derivado de uma premissa que não se sustenta, e o
// variant_type_id encontrado a partir dele é uma conclusão correta tirada de
// premissa inválida. Gravá-lo seria preservar a conclusão e jogar fora a
// dúvida.
//
// Gravar a chave do eixo 3 quando ele NÃO resolveu — ainda que como `null` —
// seria afirmar "resolvido sem contexto" sobre uma linha cujo contexto é
// indeterminado: exatamente o defeito semântico que a
// BACKFILL-SEMANTICS-CORRECTION-01 eliminou do lado SQL.
//
// Ausência nunca significa null: `jsonb_typeof` distingue os dois, `->>` não,
// e é sobre essa distinção que os índices de identidade da Query 2177 e o
// guard da Query 2179 se apoiam.
//
// Função pura, exportada, e não um bloco inline no index.ts: é o que permite
// ao teste de vetores provar `edge_emits_axis_keys` contra o código que a
// produção realmente executa, em vez de contra uma cópia.
export function buildVariantNormalizedData(
  variantTypeId: string | null,
  printingResolved: boolean,
  printingProfileId: string | null,
  editionContextResolved: boolean,
  editionContextProfileId: string | null,
): Record<string, unknown> {
  const normalizedData: Record<string, unknown> = {};
  if (printingResolved && editionContextResolved) {
    if (variantTypeId !== null) normalizedData.variant_type_id = variantTypeId;
    normalizedData.printing_profile_id = printingProfileId;
    normalizedData.edition_context_profile_id = editionContextProfileId;
  }
  return normalizedData;
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

// Mapa de IDENTIDADE CANÔNICA (buildVariantIdentityKey) -> card_variant.id,
// para classificar match_status (NEW/MATCHED) sem uma consulta por linha.
// Filtrado só pelas Cards realmente correlacionadas neste job — nunca
// carrega card_variant inteiro.
//
// A chave era `${card_id}|${variant_type_id}` até a PHASE C. Sem o
// perfil ela reproduz o BLOCKER B2 do lado da Edge: uma Card com
// STANDARD-sem-perfil e STANDARD-com-SHADOWLESS colidiria na mesma
// entrada e a segunda variante — REAL e DISTINTA — seria classificada
// MATCHED contra a primeira. É o mesmo defeito que a Query 2179 fechou
// no confirm com `IS NOT DISTINCT FROM`.
//
// PHASE C-bis: o mesmo raciocínio, um eixo adiante. Duas Variants reais da
// mesma Card que difiram só em Contexto de Edição produziriam a MESMA chave
// de três partes, e a segunda nunca seria criada. A chave passa a ter os
// QUATRO componentes — e é construída pelo MESMO helper que o dedupe e o
// lookup do index.ts usam, para que os três não possam divergir.
export async function listExistingCardVariantsMap(
  supabase: any,
  cardIds: string[],
): Promise<Map<string, string>> {
  if (cardIds.length === 0) return new Map();

  const { data, error } = await supabase
    .from("card_variant")
    .select("id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id")
    .in("card_id", cardIds);

  if (error) {
    console.error(error);
    throw new Error("CARD_VARIANT_QUERY_FAILED");
  }

  return new Map<string, string>(
    (data ?? []).map((row: any) => [
      buildVariantIdentityKey(
        row.card_id,
        row.variant_type_id,
        row.printing_profile_id,
        row.edition_context_profile_id,
      ),
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

// ---------------------------------------------------------------------
// EDITION CONTEXT ROUTING — três preloads, três queries, zero consulta por
// row. MESMO PERFIL dos preloads de Printing acima: número fixo de queries
// por JOB, jamais por linha. O roteamento inteiro acontece depois, em
// memória (services/edition-context.ts).
// ---------------------------------------------------------------------

export type EditionContextExternalMappingRow = {
  id: string;
  game_id: string;
  asset_source_id: string;
  external_set_id: string | null;
  raw_field: string;
  normalized_token: string;
  traits_signature: string[] | null;
  is_active: boolean;
};

// TODOS os mappings do Game+Fonte, ativos E inativos, COM `external_set_id`.
//
// Ativos E inativos pela mesma razão de listPrintingExternalMappings: sem o
// universo dos conhecidos não existe NEEDS_REVIEW_INACTIVE_EC_MAPPING, e o
// token voltaria ao resíduo — fail-OPEN, o achado A3 do GATE-A-01.
//
// `external_set_id` porque a precedência escopado > global é resolvida em
// memória, exatamente como a Query 2211 a resolve em SQL. Diferente do eixo
// de Impressão, este eixo TEM escopo por Set da fonte.
export async function listEditionContextExternalMappings(
  supabase: any,
  gameId: string,
  assetSourceId: string,
): Promise<EditionContextExternalMappingRow[]> {
  const { data, error } = await supabase
    .from("card_edition_context_external_mapping")
    .select(
      "id, game_id, asset_source_id, external_set_id, raw_field, normalized_token, traits_signature, is_active",
    )
    .eq("game_id", gameId)
    .eq("asset_source_id", assetSourceId);

  if (error) {
    console.error(error);
    throw new Error("CARD_EDITION_CONTEXT_EXTERNAL_MAPPING_QUERY_FAILED");
  }

  return (data ?? []) as EditionContextExternalMappingRow[];
}

export type EditionContextProfileRow = {
  id: string;
  game_id: string;
  traits_signature: string[] | null;
  is_active: boolean;
};

// Perfis do Game, ativos E inativos — SEM filtro no banco, diferente de
// listActivePrintingProfiles.
//
// A Query 2211:204-206 procura o perfil por assinatura sem filtrar
// is_active e só depois o recusa, para que o estado seja
// NEEDS_REVIEW_INACTIVE_EC_PROFILE ("existe, porém inativo") e não
// NEEDS_REVIEW_NO_EC_PROFILE ("não existe"). São dois estados distintos do
// vocabulário, e filtrar aqui apagaria o primeiro — a linha seria tratada
// como composição desconhecida, e a decisão editorial pendente ficaria
// invisível.
//
// NOME vs COMPORTAMENTO: o nome `listActive...` vem do contrato aprovado no
// readiness e é mantido para rastreabilidade, mas esta função NÃO filtra por
// is_active — de propósito, pelo motivo acima. `is_active` vem no payload e
// quem decide é `buildEditionContextIndex`, que separa
// `profileBySignature` de `inactiveProfileIds`. Quem ler só o nome vai
// supor errado; está aqui em letras grandes para que não suponha.
export async function listActiveEditionContextProfiles(
  supabase: any,
  gameId: string,
): Promise<EditionContextProfileRow[]> {
  const { data, error } = await supabase
    .from("card_edition_context_profile")
    .select("id, game_id, traits_signature, is_active")
    .eq("game_id", gameId);

  if (error) {
    console.error(error);
    throw new Error("CARD_EDITION_CONTEXT_PROFILE_QUERY_FAILED");
  }

  return (data ?? []) as EditionContextProfileRow[];
}

export type EditionContextTraitRow = {
  id: string;
  game_id: string;
  is_active: boolean;
};

// TODAS as Características de Contexto de Edição do Game — ativas E
// inativas. Mesma razão de listPrintingTraits: a Query 2211:200-202 tem um
// estado terminal próprio, NEEDS_REVIEW_INACTIVE_EC_TRAIT, avaliado DEPOIS
// de montar a composição e ANTES de procurar o perfil. Um trait desativado
// deixa o perfil que o contém ATIVO — nenhum guard acopla os dois —, então
// sem esta leitura a Edge resolveria com perfil e marcaria VALID exatamente
// a linha que o banco recusa.
export async function listEditionContextTraits(
  supabase: any,
  gameId: string,
): Promise<EditionContextTraitRow[]> {
  const { data, error } = await supabase
    .from("card_edition_context_trait")
    .select("id, game_id, is_active")
    .eq("game_id", gameId);

  if (error) {
    console.error(error);
    throw new Error("CARD_EDITION_CONTEXT_TRAIT_QUERY_FAILED");
  }

  return (data ?? []) as EditionContextTraitRow[];
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
