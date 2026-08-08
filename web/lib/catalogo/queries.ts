import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Camada de leitura da Visão Geral do Catálogo Editorial (/catalogo).
 *
 * Todas as funções aqui dependem inteiramente da política de RLS
 * catalog_admin_select (ADR-022, Query 274) — não fazem nenhuma checagem de
 * autorização própria. Chamadas por um usuário não-administrador retornam
 * listas vazias (RLS filtra silenciosamente), nunca erro; a página que usa
 * este módulo é responsável por checar is_admin() antes de renderizar
 * qualquer bloco (mesmo padrão de /usuarios).
 *
 * Ajuste 2026-07-31 (pedido de Fabrício): a tabela de Card Sets da Visão
 * Geral passou a trazer Jogo/Expansão (`getCardSetsOverview` embute
 * `expansion(code, name, game(code, name))`) — reverte a decisão anterior
 * de omitir essa informação (só havia 1 Game/1 Expansion na época); mantida
 * mesmo com pouca variação hoje, para não precisar de nova mudança de
 * schema quando um segundo Jogo/Expansão for cadastrado. Sem exposição da
 * discrepância de Card Category ENERGY (decisão editorial interna, não deve
 * aparecer nesta tela).
 *
 * Ajuste 2026-08-08 (Sprint Gerencial 1, Query 2123/2124, ADR-027):
 * `getEstadoDoCatalogo()`/`getCardSetsOverview()` passaram a ler volume e
 * cobertura de imagem de `public.catalog_card_set_metrics` (view canônica,
 * `security_invoker = true`), não mais agregando `fetchCardsComCobertura()`
 * em memória — elimina a classe de bug já vivida em produção com a
 * paginação de 1000 linhas (ver `fetchAllRows` abaixo) para este caminho
 * específico. `fetchCardsComCobertura()` continua em uso só por
 * `getDistribuicaoPorRaridade()`, que não foi migrada nesta rodada.
 */

type CardRow = {
  id: string;
  card_set_id: string;
  rarity_id: string | null;
  // PostgREST retorna a contagem de um embed agregado ora como objeto único
  // ({ count }), ora como array de um item ([{ count }]) dependendo da
  // versão/relação — normalizado por extractCount() abaixo, nunca acessado
  // diretamente.
  card_asset: { count: number } | { count: number }[] | null;
  rarity: { code: string; name: string; display_order: number } | null;
};

/** Normaliza o embed agregado `resource(count)` do PostgREST, que pode vir como objeto único ou array de um item. */
function extractCount(value: { count: number } | { count: number }[] | null | undefined): number {
  if (!value) return 0;
  return Array.isArray(value) ? (value[0]?.count ?? 0) : (value.count ?? 0);
}

/**
 * Tamanho de página do PostgREST — `db-max-rows` do projeto Supabase
 * (padrão 1000, não configurado neste projeto para um valor diferente).
 * Qualquer `.select()` sem `.range()` é truncado silenciosamente nesse
 * limite, sem erro — a resposta só vem mais curta que o total real.
 */
const SUPABASE_MAX_ROWS_PAGE_SIZE = 1000;

/**
 * Pagina uma consulta em lotes de SUPABASE_MAX_ROWS_PAGE_SIZE via
 * `.range()`, até esgotar os resultados. Necessário em qualquer leitura de
 * `card`/`card_asset` sem filtro que já limite o resultado a poucas
 * dezenas de linhas (ex.: um único Card Set) — descoberto na prática em
 * 2026-08-01 (Fabrício: o Card Set MEE, com 8 cartas já cadastradas há
 * muito tempo, apareceu incorretamente como "sem cartas" assim que o total
 * de public.card cruzou 1000 linhas, logo após a importação de ME5 via
 * TCGdex — `getCardCountsForSets`/`fetchCardsComCobertura`, sem `.range()`,
 * vinham perdendo silenciosamente as linhas além da primeira página).
 * `buildQuery` deve montar a query do zero a cada chamada (nunca reaproveitar
 * um builder já usado) porque `.range()` é aplicado de novo por página.
 */
async function fetchAllRows(
  buildQuery: (from: number, to: number) => PromiseLike<{ data: unknown[] | null; error: unknown }>,
): Promise<unknown[]> {
  const all: unknown[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await buildQuery(from, from + SUPABASE_MAX_ROWS_PAGE_SIZE - 1);
    if (error || !data) break;
    all.push(...data);
    if (data.length < SUPABASE_MAX_ROWS_PAGE_SIZE) break;
    from += SUPABASE_MAX_ROWS_PAGE_SIZE;
  }
  return all;
}

type CardSetRow = {
  id: string;
  code: string;
  name: string;
  set_type: string;
  total_set_size: number;
  logo_storage_path: string | null;
  expansion: { code: string; name: string; game: { code: string; name: string } | null } | null;
};

type AssetImportRunRow = {
  id: string;
  run_code: string;
  status: string;
  execution_context: string;
  requested_count: number;
  success_count: number;
  failed_count: number;
  created_at: string;
  card_set: { code: string; name: string } | null;
  language: { code: string } | null;
};

export type EstadoDoCatalogo = {
  cardSetsCatalogados: number;
  cardSetsComImagensCompletas: number;
  cartasCatalogadas: number;
  execucoesComPendencia: number;
};

export type CardSetOverviewRow = {
  code: string;
  name: string;
  setType: string;
  totalSetSize: number;
  cardsCatalogados: number;
  temImagensCompletas: boolean;
  temLogo: boolean;
  expansionName: string | null;
  gameName: string | null;
};

export type DistribuicaoPorRaridade = {
  code: string;
  name: string;
  totalCards: number;
};

export type AtividadeRecenteItem = {
  id: string;
  runCode: string;
  cardSetCode: string | null;
  cardSetName: string | null;
  languageCode: string | null;
  status: string;
  executionContext: string;
  requestedCount: number;
  successCount: number;
  failedCount: number;
  createdAt: string;
};

/**
 * Base para Distribuição por Raridade — uma única leitura (paginada via
 * fetchAllRows, ver acima) de `card` com `card_asset(count)` e `rarity`
 * embutidos. Único consumidor restante desde 2026-08-08: Estado do
 * Catálogo e Card Sets migraram para `catalog_card_set_metrics` (Query
 * 2123/2124, ADR-027) — ver ajuste no cabeçalho do arquivo. Continua
 * agregando em memória, não no banco (decisão original preservada, só a
 * paginação foi corrigida — o volume cruzou os 1000 registros em
 * 2026-08-01, ver fetchAllRows).
 */
async function fetchCardsComCobertura(supabase: SupabaseClient): Promise<CardRow[]> {
  const rows = await fetchAllRows((from, to) =>
    supabase
      .from("card")
      .select("id, card_set_id, rarity_id, card_asset(count), rarity(code, name, display_order)")
      .range(from, to),
  );

  return rows as unknown as CardRow[];
}

async function fetchCardSets(supabase: SupabaseClient): Promise<CardSetRow[]> {
  const { data, error } = await supabase
    .from("card_set")
    .select("id, code, name, set_type, total_set_size, logo_storage_path, expansion(code, name, game(code, name))")
    .order("release_order", { ascending: true });

  if (error || !data) {
    return [];
  }

  // `as unknown as` (não `as` direto): sem tipos gerados do schema, o
  // Supabase infere o embed `expansion(...)` como array (relação a-muitos
  // genérica) mesmo sendo a-um de verdade (FK obrigatória); mesmo padrão já
  // usado em `fetchCardsComCobertura` para `card_asset`/`rarity`.
  return data as unknown as CardSetRow[];
}

type CardSetMetricsRow = {
  card_set_id: string;
  cards_cadastradas: number;
  cards_com_imagem_algum_idioma: number;
};

/**
 * Métricas canônicas de volume/cobertura por Card Set, direto de
 * public.catalog_card_set_metrics (Query 2123/2124, ADR-027) — nunca mais
 * agregadas em memória a partir de fetchCardsComCobertura(). A view já
 * cobre todos os Card Sets (LEFT JOIN interno a card_counts/
 * image_union_counts), sem paginação: grão é por Card Set (dezenas de
 * linhas), não por Card (a cardinalidade que exigiu fetchAllRows()).
 */
async function fetchCardSetMetrics(supabase: SupabaseClient): Promise<CardSetMetricsRow[]> {
  const { data, error } = await supabase
    .from("catalog_card_set_metrics")
    .select("card_set_id, cards_cadastradas, cards_com_imagem_algum_idioma");

  if (error || !data) {
    return [];
  }

  return data as unknown as CardSetMetricsRow[];
}

export async function getEstadoDoCatalogo(supabase: SupabaseClient): Promise<EstadoDoCatalogo> {
  const [metrics, { count: execucoesComPendencia }] = await Promise.all([
    fetchCardSetMetrics(supabase),
    supabase.from("asset_import_run").select("id", { count: "exact", head: true }).neq("status", "COMPLETED"),
  ]);

  const cardSetsComImagensCompletas = metrics.filter(
    (row) => row.cards_cadastradas > 0 && row.cards_cadastradas === row.cards_com_imagem_algum_idioma,
  ).length;

  const cartasCatalogadas = metrics.reduce((total, row) => total + row.cards_cadastradas, 0);

  return {
    cardSetsCatalogados: metrics.length,
    cardSetsComImagensCompletas,
    cartasCatalogadas,
    execucoesComPendencia: execucoesComPendencia ?? 0,
  };
}

export async function getCardSetsOverview(supabase: SupabaseClient): Promise<CardSetOverviewRow[]> {
  const [cardSets, metrics] = await Promise.all([fetchCardSets(supabase), fetchCardSetMetrics(supabase)]);

  const metricsPorCardSetId = new Map(metrics.map((row) => [row.card_set_id, row]));

  return cardSets.map((set) => {
    const metric = metricsPorCardSetId.get(set.id);
    const cardsCatalogados = metric?.cards_cadastradas ?? 0;
    const cardsComImagem = metric?.cards_com_imagem_algum_idioma ?? 0;
    return {
      code: set.code,
      name: set.name,
      setType: set.set_type,
      totalSetSize: set.total_set_size,
      cardsCatalogados,
      temImagensCompletas: cardsCatalogados > 0 && cardsCatalogados === cardsComImagem,
      temLogo: !!set.logo_storage_path,
      expansionName: set.expansion?.name ?? null,
      gameName: set.expansion?.game?.name ?? null,
    };
  });
}

export async function getDistribuicaoPorRaridade(supabase: SupabaseClient): Promise<DistribuicaoPorRaridade[]> {
  const cards = await fetchCardsComCobertura(supabase);

  const porRaridade = new Map<string, DistribuicaoPorRaridade & { displayOrder: number }>();
  for (const card of cards) {
    if (!card.rarity) continue;
    const atual = porRaridade.get(card.rarity.code) ?? {
      code: card.rarity.code,
      name: card.rarity.name,
      totalCards: 0,
      displayOrder: card.rarity.display_order,
    };
    atual.totalCards += 1;
    porRaridade.set(card.rarity.code, atual);
  }

  return Array.from(porRaridade.values())
    .sort((a, b) => a.displayOrder - b.displayOrder)
    .map(({ code, name, totalCards }) => ({ code, name, totalCards }));
}

/**
 * Base do detalhe de um Card Set (rota /catalogo/card-sets/{code}), destino
 * real da navegação da tabela na Visão Geral (refinamento 6 aprovado por
 * Fabrício). O design completo da tela de detalhe é um incremento futuro
 * — esta função só resolve os mesmos dados já usados em getCardSetsOverview,
 * filtrados para um único Card Set.
 */
export async function getCardSetByCode(
  supabase: SupabaseClient,
  code: string,
): Promise<CardSetOverviewRow | null> {
  const overview = await getCardSetsOverview(supabase);
  return overview.find((set) => set.code === code) ?? null;
}

// ---------------------------------------------------------------------------
// Catálogo (galeria de Card Sets, /catalogo/card-sets) — camada de leitura
// para a tela de entrada do módulo (spec aprovada em 2026-07-31). Separada de
// getCardSetsOverview acima porque exige campos que aquela nunca precisou
// (Jogo/Expansão associados, data de lançamento, id) e busca/pagina de forma
// diferente (galeria + busca unificada, não uma listagem simples).
// ---------------------------------------------------------------------------

export const CATALOGO_PAGE_SIZE = 24;
export const CATALOGO_SEARCH_CARDS_PAGE_SIZE = 12;

export type CatalogoCardSetRow = {
  id: string;
  code: string;
  name: string;
  setType: string;
  releaseOrder: number;
  releaseDate: string | null;
  /** Quantidade de cartas do set base (sem secretas) — `card_set.base_set_size`. */
  baseSetSize: number;
  /** Quantidade total, incluindo secretas — `card_set.total_set_size`. A diferença `totalSetSize - baseSetSize` é a contagem de secretas (ver comentário de `120_create_card_set_table.sql`). */
  totalSetSize: number;
  expansionId: string;
  /** Código curto da Expansão (ex.: "SV") — adicionado em 2026-08-01 para o combobox de Coleção de Importar Cartas, ver toCatalogoCardSetRow. */
  expansionCode: string;
  expansionName: string;
  expansionReleaseOrder: number;
  gameId: string;
  gameCode: string;
  gameName: string;
  cardsCatalogados: number;
  logoStoragePath: string | null;
  createdAt: string;
};

export type CatalogoCardResult = {
  id: string;
  name: string;
  collectorNumber: string;
  cardSetCode: string;
  cardSetName: string;
  gameName: string;
};

export type CatalogoSearchResult = {
  cardSets: CatalogoCardSetRow[];
  cards: CatalogoCardResult[];
  hasMoreCards: boolean;
};

/** `CatalogoCardSetRow` com a URL assinada da logo já resolvida — mesmo papel de `ExpansaoWithLogo`. Reexportado como `CardSetWithLogo` em `card-sets/catalogo-actions.ts` para não quebrar os imports já existentes nos componentes de galeria/Dialog. */
export type CatalogoCardSetRowWithLogo = CatalogoCardSetRow & { logoUrl: string | null };

type CatalogoCardSetRawRow = {
  id: string;
  code: string;
  name: string;
  set_type: string;
  release_order: number;
  release_date: string | null;
  base_set_size: number;
  total_set_size: number;
  logo_storage_path: string | null;
  created_at: string;
  // `game.created_at` incluído aqui (mesmo padrão de `game.created_at` em
  // `ExpansionRawRow`, ver nota lá) porque `getCardSetsGroupedByExpansion()`
  // precisa dele para ordenar os grupos (Expansões) sem misturar Jogos
  // diferentes — opcional porque as demais queries que reaproveitam este
  // tipo (busca, galeria de Cartas) não o usam.
  expansion: { id: string; code: string; name: string; release_order: number; game: { id: string; code: string; name: string; created_at?: string } | null } | null;
};

async function fetchCardSetsForCatalogo(
  supabase: SupabaseClient,
  filters: { gameCode?: string; expansionCode?: string },
): Promise<CatalogoCardSetRawRow[]> {
  let query = supabase
    .from("card_set")
    .select(
      "id, code, name, set_type, release_order, release_date, base_set_size, total_set_size, logo_storage_path, created_at, expansion!inner(id, code, name, release_order, game!inner(id, code, name, created_at))",
    );

  if (filters.expansionCode) {
    query = query.eq("expansion.code", filters.expansionCode);
  } else if (filters.gameCode) {
    query = query.eq("expansion.game.code", filters.gameCode);
  }

  const { data, error } = await query;
  if (error || !data) {
    return [];
  }
  return data as unknown as CatalogoCardSetRawRow[];
}

/**
 * Ordenação e paginação em memória, mesmo padrão já usado por
 * getEstadoDoCatalogo/getCardSetsOverview para agregar Cards por Card Set —
 * evita depender de ordenação por coluna de tabela relacionada via
 * PostgREST (suporte varia por versão do cliente). Sem filtro de Jogo/
 * Expansão, cruza Jogos por `release_date` real (único campo comparável
 * entre Jogos diferentes — `release_order` só faz sentido dentro de cada
 * um, causa raiz do problema identificado na auditoria da tela de
 * Expansões). Com filtro ativo, segue a mesma dupla chave (`release_order`
 * de Expansão e depois de Card Set), mas **decrescente** (2026-07-31,
 * pedido de Fabrício: "sempre as mais atuais no topo" — mesmo critério de
 * "mais recente primeiro" já aplicado ao caso sem filtro, agora também no
 * caminho de clique a partir do card de Expansão em `/catalogo/expansoes`).
 *
 * Ajuste 2026-07-31, rodada seguinte (pedido explícito de Fabrício: "os
 * card sets devem ser organizados por data de lançamento e se as datas
 * forem iguais deve ser levado em consideração o número de ordem do
 * lançamento. Sempre em ordem decrescente para os dois parâmetros") — no
 * caminho sem filtro, o desempate deixou de ser `created_at` (metadado
 * técnico, sem significado editorial) e passou a ser `release_order`
 * descendente, tanto quando as duas datas coincidem quanto quando as duas
 * estão ausentes. Quando só uma das duas tem `release_date`, a com data
 * continua vindo primeiro (comportamento já existente, não questionado).
 */
function sortCatalogoCardSets(rows: CatalogoCardSetRawRow[], filtered: boolean): CatalogoCardSetRawRow[] {
  const sorted = [...rows];
  if (filtered) {
    sorted.sort((a, b) => {
      const expansionDiff = (b.expansion?.release_order ?? 0) - (a.expansion?.release_order ?? 0);
      if (expansionDiff !== 0) return expansionDiff;
      return b.release_order - a.release_order;
    });
  } else {
    sorted.sort((a, b) => {
      if (a.release_date && b.release_date && a.release_date !== b.release_date) {
        return b.release_date.localeCompare(a.release_date);
      }
      if (a.release_date && !b.release_date) return -1;
      if (!a.release_date && b.release_date) return 1;
      return b.release_order - a.release_order;
    });
  }
  return sorted;
}

async function getCardCountsForSets(supabase: SupabaseClient, cardSetIds: string[]): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  if (cardSetIds.length === 0) {
    return counts;
  }
  const rows = await fetchAllRows((from, to) =>
    supabase.from("card").select("card_set_id").in("card_set_id", cardSetIds).range(from, to),
  );
  for (const row of rows as { card_set_id: string }[]) {
    counts.set(row.card_set_id, (counts.get(row.card_set_id) ?? 0) + 1);
  }
  return counts;
}

function toCatalogoCardSetRow(row: CatalogoCardSetRawRow, counts: Map<string, number>): CatalogoCardSetRow {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    setType: row.set_type,
    releaseOrder: row.release_order,
    releaseDate: row.release_date,
    baseSetSize: row.base_set_size,
    totalSetSize: row.total_set_size,
    expansionId: row.expansion?.id ?? "",
    expansionCode: row.expansion?.code ?? "",
    expansionName: row.expansion?.name ?? "—",
    expansionReleaseOrder: row.expansion?.release_order ?? 0,
    gameId: row.expansion?.game?.id ?? "",
    gameCode: row.expansion?.game?.code ?? "",
    gameName: row.expansion?.game?.name ?? "—",
    cardsCatalogados: counts.get(row.id) ?? 0,
    logoStoragePath: row.logo_storage_path,
    createdAt: row.created_at,
  };
}

/** Galeria principal da tela Catálogo — sem termo de busca. */
export async function getCardSetsForCatalogo(
  supabase: SupabaseClient,
  options: { gameCode?: string; expansionCode?: string; limit: number; offset: number },
): Promise<{ items: CatalogoCardSetRow[]; hasMore: boolean }> {
  const filtered = Boolean(options.gameCode || options.expansionCode);
  const all = sortCatalogoCardSets(
    await fetchCardSetsForCatalogo(supabase, { gameCode: options.gameCode, expansionCode: options.expansionCode }),
    filtered,
  );

  const page = all.slice(options.offset, options.offset + options.limit);
  const hasMore = all.length > options.offset + options.limit;
  const counts = await getCardCountsForSets(supabase, page.map((row) => row.id));

  return { items: page.map((row) => toCatalogoCardSetRow(row, counts)), hasMore };
}

export type CardSetsExpansionGroup = {
  expansionId: string;
  expansionCode: string;
  expansionName: string;
  /** Usado só para o selo de cor do Jogo no cabeçalho do grupo (`getGameAccentColor`) — cada card já mostra o nome do Jogo individualmente (ver `CardSetGalleryCard`), então o grupo não precisa repetir `gameName`. */
  gameCode: string;
  items: CatalogoCardSetRow[];
};

/** `CardSetsExpansionGroup` com a URL assinada da logo já resolvida em cada item — ver `CatalogoCardSetRowWithLogo`. */
export type CardSetsExpansionGroupWithLogo = Omit<CardSetsExpansionGroup, "items"> & { items: CatalogoCardSetRowWithLogo[] };

type CardSetsExpansionGroupInternal = CardSetsExpansionGroup & { gameCreatedAt: string; expansionReleaseOrder: number };

/**
 * Galeria principal da tela Coleções — sem termo de busca. Agrupada por
 * Expansão (2026-08-02, pedido de Fabrício: "da mesma forma como fizemos na
 * página de expansões, separando-as por Jogo, precisamos na página de
 * Coleções, separá-las por Expansão. Hoje aparecem todas juntas") — mesmo
 * padrão estrutural de `getExpansoesGroupedByGame()`: sem paginação em modo
 * galeria (carrega tudo que casa com o filtro opcional de Jogo/Expansão); o
 * "Carregar mais" (`CATALOGO_PAGE_SIZE` por vez) continua existindo só para
 * a busca (`getCardSetsForCatalogo`, flat, sem agrupamento — inalterada).
 *
 * Ordem dos GRUPOS (cada Expansão): reaproveita a mesma dupla chave já usada
 * para ordenar Expansões dentro de um Jogo em `getExpansoesGroupedByGame` —
 * `game.created_at` ascendente primeiro (Jogo cadastrado há mais tempo
 * primeiro, nunca intercala Jogos diferentes) e, como desempate dentro do
 * mesmo Jogo, `expansion.release_order` ascendente (a mesma "ordem de
 * lançamento" já usada para as próprias Expansões, ver nota em
 * `getExpansoesGroupedByGame`). Não usa nome/código (alfabético) pela mesma
 * razão de lá — Pokémon deve continuar vindo antes de Lorcana, não por
 * coincidência alfabética.
 *
 * Ordem dos ITENS (Coleções) dentro de cada grupo: deliberadamente NÃO
 * ascendente — ao contrário do padrão adotado para Expansões-dentro-de-Jogo,
 * aqui preserva a decisão já confirmada especificamente para Coleções
 * (2026-07-31, pedido de Fabrício: "os card sets devem ser organizados por
 * data de lançamento e se as datas forem iguais deve ser levado em
 * consideração o número de ordem do lançamento. Sempre em ordem decrescente
 * para os dois parâmetros" — mesma lógica de `sortCatalogoCardSets`, ramo
 * "unfiltered": mais recentes no topo de cada grupo, não a mais antiga.
 */
export async function getCardSetsGroupedByExpansion(
  supabase: SupabaseClient,
  filters?: { gameCode?: string; expansionCode?: string },
): Promise<CardSetsExpansionGroup[]> {
  const rows = await fetchCardSetsForCatalogo(supabase, {
    gameCode: filters?.gameCode,
    expansionCode: filters?.expansionCode,
  });
  const counts = await getCardCountsForSets(supabase, rows.map((row) => row.id));

  const groups = new Map<string, CardSetsExpansionGroupInternal>();
  for (const row of rows) {
    const expansionId = row.expansion?.id ?? "";
    let group = groups.get(expansionId);
    if (!group) {
      group = {
        expansionId,
        expansionCode: row.expansion?.code ?? "",
        expansionName: row.expansion?.name ?? "—",
        gameCode: row.expansion?.game?.code ?? "",
        items: [],
        gameCreatedAt: row.expansion?.game?.created_at ?? "",
        expansionReleaseOrder: row.expansion?.release_order ?? 0,
      };
      groups.set(expansionId, group);
    }
    group.items.push(toCatalogoCardSetRow(row, counts));
  }

  const result = Array.from(groups.values());
  for (const group of result) {
    group.items.sort((a, b) => {
      if (a.releaseDate && b.releaseDate && a.releaseDate !== b.releaseDate) {
        return b.releaseDate.localeCompare(a.releaseDate);
      }
      if (a.releaseDate && !b.releaseDate) return -1;
      if (!a.releaseDate && b.releaseDate) return 1;
      return b.releaseOrder - a.releaseOrder;
    });
  }
  result.sort((a, b) => {
    const gameDiff = a.gameCreatedAt.localeCompare(b.gameCreatedAt);
    if (gameDiff !== 0) return gameDiff;
    return a.expansionReleaseOrder - b.expansionReleaseOrder;
  });
  return result;
}

type CatalogoCardSearchRawRow = {
  id: string;
  name: string;
  collector_number: string;
  card_set: { code: string; name: string; expansion: { game: { name: string } | null } | null } | null;
};

/** Busca unificada da tela Catálogo — Card Sets (nome/código) e Cartas (nome/número), em paralelo. */
export async function searchCatalogo(
  supabase: SupabaseClient,
  term: string,
  options: { cardsLimit: number; cardsOffset: number },
): Promise<CatalogoSearchResult> {
  const q = term.trim();
  if (!q) {
    return { cardSets: [], cards: [], hasMoreCards: false };
  }

  const [setsResult, cardsResult] = await Promise.all([
    supabase
      .from("card_set")
      .select(
        "id, code, name, set_type, release_order, release_date, logo_storage_path, created_at, expansion!inner(id, code, name, release_order, game!inner(id, code, name))",
      )
      .or(`name.ilike.%${q}%,code.ilike.%${q}%`)
      .limit(6),
    supabase
      .from("card")
      .select("id, name, collector_number, card_set(code, name, expansion(game(name)))")
      .or(`name.ilike.%${q}%,collector_number.ilike.%${q}%`)
      .order("name", { ascending: true })
      .range(options.cardsOffset, options.cardsOffset + options.cardsLimit),
  ]);

  const setRows = (setsResult.data ?? []) as unknown as CatalogoCardSetRawRow[];
  const counts = await getCardCountsForSets(supabase, setRows.map((row) => row.id));
  const cardSets = setRows.map((row) => toCatalogoCardSetRow(row, counts));

  const cardRows = (cardsResult.data ?? []) as unknown as CatalogoCardSearchRawRow[];
  const hasMoreCards = cardRows.length > options.cardsLimit;
  const cardsPage = hasMoreCards ? cardRows.slice(0, options.cardsLimit) : cardRows;

  const cards: CatalogoCardResult[] = cardsPage.map((row) => ({
    id: row.id,
    name: row.name,
    collectorNumber: row.collector_number,
    cardSetCode: row.card_set?.code ?? "",
    cardSetName: row.card_set?.name ?? "—",
    gameName: row.card_set?.expansion?.game?.name ?? "—",
  }));

  return { cardSets, cards, hasMoreCards };
}

/** URLs assinadas (bucket privado `card-set-logo`, nunca getPublicUrl — ver 05-modelo-de-dados.md) para os logos presentes no lote atual. */
export async function getCardSetLogoUrls(
  supabase: SupabaseClient,
  paths: (string | null)[],
): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  const validPaths = paths.filter((path): path is string => !!path);
  if (validPaths.length === 0) {
    return map;
  }

  const { data, error } = await supabase.storage.from("card-set-logo").createSignedUrls(validPaths, 60 * 60);
  if (error || !data) {
    return map;
  }
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) {
      map.set(item.path, item.signedUrl);
    }
  }
  return map;
}

export type JogoRow = {
  id: string;
  code: string;
  name: string;
  totalExpansoes: number;
  createdAt: string;
  updatedAt: string;
};

type GameRawRow = {
  id: string;
  code: string;
  name: string;
  created_at: string;
  updated_at: string;
  expansion: { count: number } | { count: number }[] | null;
};

/**
 * Lista de Jogos (`game`) — só 1 registro hoje. Deliberadamente sem contagens
 * em cascata (Card Sets/Cartas por Jogo exigiriam 2 saltos de junção via
 * Expansion); se o catálogo crescer para múltiplos Jogos, essa decisão pode
 * ser revisitada.
 */
export async function getJogos(supabase: SupabaseClient): Promise<JogoRow[]> {
  const { data, error } = await supabase
    .from("game")
    .select("id, code, name, created_at, updated_at, expansion(count)")
    .order("name", { ascending: true });

  if (error || !data) {
    return [];
  }

  return (data as unknown as GameRawRow[]).map((game) => ({
    id: game.id,
    code: game.code,
    name: game.name,
    totalExpansoes: extractCount(game.expansion),
    createdAt: game.created_at,
    updatedAt: game.updated_at,
  }));
}

export const JOGOS_PAGE_SIZE = 10;

/**
 * Versão paginada/filtrável de `getJogos`, para a tabela da tela Jogos
 * (redesenho 2026-07-31 — busca e paginação via URL, mesmo padrão
 * server-driven de Expansões/Catálogo). `getJogos` continua existindo sem
 * alteração — os indicadores da tela (`JogosStats`) precisam do total real
 * do domínio, não da página/filtro atual, então seguem usando a lista
 * completa. Usa `.range()`/`count: "exact"` do próprio Supabase em vez do
 * padrão "busca tudo e pagina em memória" de Expansões: `game` não tem a
 * complicação de ordenar por coluna de tabela relacionada que motivou
 * aquela decisão ali.
 */
export async function getJogosPaged(
  supabase: SupabaseClient,
  { search, limit = JOGOS_PAGE_SIZE, offset = 0 }: { search?: string; limit?: number; offset?: number } = {},
): Promise<{ items: JogoRow[]; totalCount: number }> {
  let query = supabase
    .from("game")
    .select("id, code, name, created_at, updated_at, expansion(count)", { count: "exact" })
    .order("name", { ascending: true })
    .range(offset, offset + limit - 1);

  if (search) {
    query = query.or(`name.ilike.%${search}%,code.ilike.%${search}%`);
  }

  const { data, error, count } = await query;

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  return {
    items: (data as unknown as GameRawRow[]).map((game) => ({
      id: game.id,
      code: game.code,
      name: game.name,
      totalExpansoes: extractCount(game.expansion),
      createdAt: game.created_at,
      updatedAt: game.updated_at,
    })),
    totalCount: count ?? 0,
  };
}

export type ExpansaoRow = {
  id: string;
  code: string;
  name: string;
  releaseOrder: number;
  gameId: string;
  gameCode: string;
  gameName: string;
  totalCardSets: number;
  createdAt: string;
  updatedAt: string;
  /** Caminho relativo dentro do bucket privado `expansion-logo` (Query 2045/2047) — NULL = sem logo cadastrada. Nunca uma URL; para exibir, gerar URL assinada via `getExpansionLogoUrls()`. */
  logoStoragePath: string | null;
};

/** `ExpansaoRow` com a URL assinada da logo já resolvida — usado só pelas telas de leitura (galeria, Dialog de edição), nunca pela camada de escrita. */
export type ExpansaoWithLogo = ExpansaoRow & { logoUrl: string | null };

type ExpansionRawRow = {
  id: string;
  code: string;
  name: string;
  release_order: number;
  created_at: string;
  updated_at: string;
  logo_storage_path: string | null;
  // `created_at` do Jogo só é selecionado por `fetchExpansoesRawForCatalogo`
  // (usado para ordenar os grupos de `getExpansoesGroupedByGame` pela ordem
  // de cadastro do Jogo) — por isso opcional aqui, ausente nas demais
  // queries que reaproveitam este tipo (`getExpansoes`, `searchExpansoes`).
  game: { id: string; code: string; name: string; created_at?: string } | null;
  card_set: { count: number } | { count: number }[] | null;
};

/**
 * Lista de Expansões. `filters.gameCode`, quando informado, restringe o
 * resultado ao Jogo daquele código — usado pelo link "Expansões" clicável na
 * tela de Jogos (`?game=CODE`, ver `/catalogo/expansoes`).
 */
export async function getExpansoes(
  supabase: SupabaseClient,
  filters?: { gameCode?: string },
): Promise<ExpansaoRow[]> {
  let query = supabase
    .from("expansion")
    .select(
      "id, code, name, release_order, created_at, updated_at, logo_storage_path, game!inner(id, code, name), card_set(count)",
    )
    .order("release_order", { ascending: true });

  if (filters?.gameCode) {
    query = query.eq("game.code", filters.gameCode);
  }

  const { data, error } = await query;

  if (error || !data) {
    return [];
  }

  return (data as unknown as ExpansionRawRow[]).map((expansion) => ({
    id: expansion.id,
    code: expansion.code,
    name: expansion.name,
    releaseOrder: expansion.release_order,
    gameId: expansion.game?.id ?? "",
    gameCode: expansion.game?.code ?? "",
    gameName: expansion.game?.name ?? "—",
    totalCardSets: extractCount(expansion.card_set),
    createdAt: expansion.created_at,
    updatedAt: expansion.updated_at,
    logoStoragePath: expansion.logo_storage_path,
  }));
}

// ---------------------------------------------------------------------------
// Catálogo — galeria de Expansões (/catalogo/expansoes, redesenho 2026-07-31,
// mesma linguagem visual/comportamento da galeria de Card Sets acima).
// Devolve `ExpansaoRow` (mesmo tipo já usado por getExpansoes/CreateExpansion
// Dialog/EditExpansionDialog) — sem tipo novo, evita qualquer divergência de
// forma entre a galeria e os Dialogs de criação/edição já existentes.
//
// Adaptação à entidade: Expansion não tem `release_date` — só
// `release_order`, um inteiro sequencial relativo ao próprio Jogo (ver
// `database/schema/110_create_expansion_table.sql`). Ganhou
// `logo_storage_path` em 2026-07-31 (Queries 2045-2047, pedido de
// Fabrício), mesmo padrão de `card_set.logo_storage_path` — bucket privado
// `expansion-logo`, escrita só via `admin_set_expansion_logo()`, leitura via
// URL assinada (`getExpansionLogoUrls()`, abaixo).
// ---------------------------------------------------------------------------

export const EXPANSOES_PAGE_SIZE = 24;

async function fetchExpansoesRawForCatalogo(
  supabase: SupabaseClient,
  filters: { gameCode?: string },
): Promise<ExpansionRawRow[]> {
  // `game.created_at` incluído aqui (e só aqui — ver nota em `ExpansionRawRow`)
  // porque `getExpansoesGroupedByGame()` precisa dele para ordenar os grupos
  // pela ordem de cadastro do Jogo, não alfabeticamente.
  let query = supabase
    .from("expansion")
    .select(
      "id, code, name, release_order, created_at, updated_at, logo_storage_path, game!inner(id, code, name, created_at), card_set(count)",
    );

  if (filters.gameCode) {
    query = query.eq("game.code", filters.gameCode);
  }

  const { data, error } = await query;
  if (error || !data) {
    return [];
  }
  return data as unknown as ExpansionRawRow[];
}

function toExpansaoRow(row: ExpansionRawRow): ExpansaoRow {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    releaseOrder: row.release_order,
    gameId: row.game?.id ?? "",
    gameCode: row.game?.code ?? "",
    gameName: row.game?.name ?? "—",
    totalCardSets: extractCount(row.card_set),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    logoStoragePath: row.logo_storage_path,
  };
}

export type ExpansoesGameGroup = {
  gameId: string;
  gameCode: string;
  gameName: string;
  items: ExpansaoRow[];
};

/** `ExpansoesGameGroup` com a URL assinada da logo já resolvida em cada item — ver `ExpansaoWithLogo`. */
export type ExpansoesGameGroupWithLogo = Omit<ExpansoesGameGroup, "items"> & { items: ExpansaoWithLogo[] };

type ExpansoesGameGroupInternal = ExpansoesGameGroup & { gameCreatedAt: string };

/**
 * Galeria principal da tela Expansões — sem termo de busca. Agrupada por
 * Jogo (2026-07-31, pedido de Fabrício: "exibidas separadamente por cada
 * tipo de Jogo e organizadas pela data de lançamento de forma decrescente").
 * Como Expansion não tem `release_date` (ver nota acima), "data de
 * lançamento" é representada por `release_order` (maior valor = Expansão
 * mais recente daquele Jogo, por definição do próprio campo).
 *
 * Nota sobre a direção do sort dentro do grupo: `release_order` ASCENDENTE
 * (1, 2, 3…) — não descendente. Fabrício pediu "decrescente" inicialmente,
 * mas reportou "ordem inversa" ao ver o resultado com descendente aplicado
 * (2026-07-31); ajustado para ascendente a partir desse feedback direto na
 * tela.
 *
 * Ordem dos grupos (2026-07-31, mesmo dia, segundo ajuste): NÃO é
 * alfabética — Fabrício pediu explicitamente "primeiro listar... Pokémon e
 * depois Lorcana... Pokémon foi o primeiro game cadastrado". Grupos
 * ordenados por `game.created_at` ASCENDENTE — Jogo cadastrado há mais
 * tempo aparece primeiro. Deliberadamente diferente do critério de
 * `getGameOptions()` (alfabético, usado só no seletor de Jogo dos
 * formulários) — não há razão para os dois seguirem o mesmo critério.
 *
 * Sem paginação: carrega tudo que casa com o filtro opcional de Jogo — o
 * "Carregar mais" (flat, `EXPANSOES_PAGE_SIZE` por vez) não compõe com
 * agrupamento por Jogo, então continua existindo só para a busca
 * (`searchExpansoes`, abaixo, que permanece flat).
 */
export async function getExpansoesGroupedByGame(
  supabase: SupabaseClient,
  filters?: { gameCode?: string },
): Promise<ExpansoesGameGroup[]> {
  const rows = await fetchExpansoesRawForCatalogo(supabase, { gameCode: filters?.gameCode });

  const groups = new Map<string, ExpansoesGameGroupInternal>();
  for (const row of rows) {
    const gameId = row.game?.id ?? "";
    let group = groups.get(gameId);
    if (!group) {
      group = {
        gameId,
        gameCode: row.game?.code ?? "",
        gameName: row.game?.name ?? "—",
        gameCreatedAt: row.game?.created_at ?? "",
        items: [],
      };
      groups.set(gameId, group);
    }
    group.items.push(toExpansaoRow(row));
  }

  const result = Array.from(groups.values());
  for (const group of result) {
    group.items.sort((a, b) => a.releaseOrder - b.releaseOrder);
  }
  result.sort((a, b) => a.gameCreatedAt.localeCompare(b.gameCreatedAt));
  return result;
}

/**
 * Busca por nome ou código da Expansão — mais simples que a busca dupla de
 * Catálogo (Card Set + Carta): Expansion não tem Cards como filhos diretos,
 * então não há um segundo tipo de resultado fazendo sentido aqui.
 */
export async function searchExpansoes(
  supabase: SupabaseClient,
  term: string,
  options: { limit: number; offset: number },
): Promise<{ items: ExpansaoRow[]; hasMore: boolean }> {
  const q = term.trim();
  if (!q) {
    return { items: [], hasMore: false };
  }

  const { data, error } = await supabase
    .from("expansion")
    .select(
      "id, code, name, release_order, created_at, updated_at, logo_storage_path, game!inner(id, code, name), card_set(count)",
    )
    .or(`name.ilike.%${q}%,code.ilike.%${q}%`)
    .order("name", { ascending: true });

  if (error || !data) {
    return { items: [], hasMore: false };
  }

  const rows = data as unknown as ExpansionRawRow[];
  const page = rows.slice(options.offset, options.offset + options.limit);
  const hasMore = rows.length > options.offset + options.limit;
  return { items: page.map(toExpansaoRow), hasMore };
}

/**
 * URLs assinadas (1h) para as logos de Expansão — mesmo padrão de
 * `getCardSetLogoUrls()` (bucket privado, admin-only), agora para
 * `expansion-logo` (Queries 2045-2047, 2026-07-31). Recebe uma lista de
 * `logoStoragePath` (com nulos, para simplificar a chamada a partir de uma
 * lista de `ExpansaoRow`) e devolve um mapa `path -> URL assinada`, só com
 * os caminhos não-nulos que resolveram com sucesso.
 */
export async function getExpansionLogoUrls(
  supabase: SupabaseClient,
  paths: (string | null)[],
): Promise<Map<string, string>> {
  const map = new Map<string, string>();
  const validPaths = paths.filter((path): path is string => !!path);
  if (validPaths.length === 0) {
    return map;
  }

  const { data, error } = await supabase.storage.from("expansion-logo").createSignedUrls(validPaths, 60 * 60);
  if (error || !data) {
    return map;
  }
  for (const item of data) {
    if (item.path && item.signedUrl && !item.error) {
      map.set(item.path, item.signedUrl);
    }
  }
  return map;
}

export type GameOption = { id: string; code: string; name: string };

/** Opções para o seletor de Jogo do formulário de cadastro de Expansão. */
export async function getGameOptions(supabase: SupabaseClient): Promise<GameOption[]> {
  const { data, error } = await supabase.from("game").select("id, code, name").order("name", { ascending: true });

  if (error || !data) {
    return [];
  }

  return data as GameOption[];
}

/**
 * Todos os Card Sets, na mesma ordenação "mais recente primeiro" da galeria
 * de Coleções sem filtro (`sortCatalogoCardSets`, `filtered = false`) — base
 * única para a tela /catalogo/cartas: os 3 primeiros alimentam os cards de
 * logo em destaque (pedido de Fabrício, 2026-07-31: "ao invés de trazer no
 * topo cards com indicadores, vamos trazer cards com a imagem da logo dos
 * três card set mais recentes"), a lista inteira alimenta o seletor
 * "Coleção". Sem paginação/contagem de cartas (`counts` vazio) — nenhum dos
 * dois consumidores precisa de `cardsCatalogados`.
 *
 * **Atualização 2026-07-31 (mesmo dia, rodada seguinte):** `cardsCatalogados`
 * passou a ser necessário — dois novos consumidores: (1) `CartasStats`,
 * indicadores que substituem a antiga barra "Recentes" (removida por pedido
 * de Fabrício: "perdeu o sentido... com os filtros que incluímos"); (2) a
 * regra de seleção padrão em `page.tsx`, que agora precisa saber quais Card
 * Sets têm cartas para escolher "o último card set com cartas cadastradas"
 * em vez do último Card Set cadastrado (que pode não ter nenhuma carta
 * ainda). `getCardCountsForSets` (já usada por `getCardSetsForCatalogo`/
 * `getEstadoDoCatalogo`) resolve isso numa única query extra, mesmo padrão
 * já estabelecido.
 */
export async function getCardSetsForCartas(supabase: SupabaseClient): Promise<CatalogoCardSetRow[]> {
  const rows = sortCatalogoCardSets(await fetchCardSetsForCatalogo(supabase, {}), false);
  const counts = await getCardCountsForSets(
    supabase,
    rows.map((row) => row.id),
  );
  return rows.map((row) => toCatalogoCardSetRow(row, counts));
}

/**
 * Quais Card Sets têm o job de importação TCGdex mais recente incompleto —
 * novo em 2026-08-01 (sétima rodada, bug real reportado por Fabrício: "não
 * consigo retomar a importação de SV1 e SV2 (também importem parcialmente
 * as cartas)").
 *
 * A primeira tentativa de corrigir isso comparou `cardsCatalogados` contra
 * `card_set.total_set_size` — **rejeitada depois de checar os dados reais**:
 * `total_set_size` é preenchido manualmente por Fabrício ao cadastrar a
 * Coleção e nem sempre inclui as secretas que só a TCGdex revela (SV1 tem
 * `total_set_size = 252`, mas a TCGdex reporta 258 cartas reais — as 6 que
 * falharam na confirmação por causa do gap de `HYPER_RARE` são exatamente a
 * diferença). Comparar contra esse campo escondia SV1 de novo.
 *
 * O sinal correto vem do próprio histórico de `catalog_import_job`: para
 * cada Card Set, olha só o job MAIS RECENTE (`created_at desc` — um retry
 * bem-sucedido não deve ser ofuscado por uma tentativa antiga que falhou) e
 * considera "incompleto" quando `total_rows > inserted_rows + updated_rows +
 * unchanged_rows` — ou seja, sobrou alguma linha que nunca foi persistida,
 * seja por falha na confirmação (caso SV1, `failed_rows > 0`) ou por nunca
 * ter ficado válida o bastante pra ser processada (caso SV2: job com status
 * `COMPLETED`, sem nenhuma falha registrada, mas só 270 das 279 linhas
 * chegaram a ser inseridas — as outras 9 nunca passaram de `NEEDS_REVIEW`/
 * `INVALID`). Cobre os dois casos com a mesma regra, sem depender de status
 * específico.
 */
export async function getLatestImportJobIncompleteFlags(
  supabase: SupabaseClient,
  cardSetIds: string[],
): Promise<Map<string, boolean>> {
  const flags = new Map<string, boolean>();
  if (cardSetIds.length === 0) return flags;

  const rows = await fetchAllRows((from, to) =>
    supabase
      .from("catalog_import_job")
      .select("card_set_id, total_rows, inserted_rows, updated_rows, unchanged_rows, created_at")
      .in("card_set_id", cardSetIds)
      .order("created_at", { ascending: false })
      .range(from, to),
  );

  const seen = new Set<string>();
  for (const row of rows as {
    card_set_id: string;
    total_rows: number;
    inserted_rows: number;
    updated_rows: number;
    unchanged_rows: number;
  }[]) {
    // Primeira ocorrência de cada card_set_id é a mais recente (ordenado
    // desc acima) — ignora quaisquer jobs mais antigos do mesmo Card Set.
    if (seen.has(row.card_set_id)) continue;
    seen.add(row.card_set_id);
    const processed = row.inserted_rows + row.updated_rows + row.unchanged_rows;
    flags.set(row.card_set_id, row.total_rows > processed);
  }
  return flags;
}

export type CartasCatalogoStats = {
  totalVariacoes: number;
  totalImagens: number;
  cardsSemImagem: number;
};

/**
 * Indicadores agregados da tela Cartas que não são deriváveis de
 * `cardSets` — pedido de Fabrício (2026-07-31, mesmo dia, lista fechada de
 * 5 indicadores para substituir o rascunho anterior de `CartasStats`):
 * "Quantidade de variações cadastradas", "Quantidade de imagens em nossa
 * base" e "Quantidade de cartas sem imagens". Os outros dois da lista
 * (Cartas, Coleções sem Cartas) já vêm de `cardSets`/`cardsCatalogados`,
 * sem consulta nova — ver `CartasStats`.
 *
 * Três contagens independentes, todas `count: "exact", head: true` (sem
 * trazer linhas, só o total — mesmo padrão já usado em
 * `getEstadoDoCatalogo` para `execucoesComPendencia`):
 * - `card_variant` (Query 160) — cada linha é uma variante colecionável
 *   cadastrada para uma Card (ex.: STANDARD, REVERSE_HOLO); conta 1:1 com
 *   o pedido.
 * - `card_asset` (Query 180) — todo ativo digital já registrado no
 *   catálogo, não só imagens de frente (CARD_FRONT) — o pedido foi
 *   "imagens em nossa base", sem restringir o tipo.
 * - Cards sem imagem: total de Cards (`totalCartas`, calculado por quem
 *   chama — mesma base de `cardsCatalogados`, sem filtro `is_active`,
 *   para não divergir do indicador "Cartas") menos os Cards com pelo
 *   menos um `card_asset` primário do tipo CARD_FRONT (mesmo critério que
 *   decide o placeholder "Sem imagem" em `CartaGridCard`/`CartaZoomDialog`
 *   — ver `cartaImageUrl`/`pickCardFrontPath`). `card_asset_type!inner(code)`
 *   com `.eq("card_asset_type.code", ...)` é o mesmo padrão de filtro por
 *   coluna de tabela relacionada já usado em `fetchCardSetsForCatalogo`
 *   (`expansion!inner`/`.eq("expansion.code", ...)`); depende da política
 *   de SELECT em `card_asset_type` para `authenticated`+`is_admin()`
 *   corrigida pela Query 2053 nesta mesma rodada de trabalho.
 */
export async function getCartasCatalogoStats(
  supabase: SupabaseClient,
  totalCartas: number,
): Promise<CartasCatalogoStats> {
  const [variantResult, assetResult, frontAssetsRows] = await Promise.all([
    supabase.from("card_variant").select("id", { count: "exact", head: true }),
    supabase.from("card_asset").select("id", { count: "exact", head: true }),
    fetchAllRows((from, to) =>
      supabase
        .from("card_asset")
        .select("card_id, card_asset_type!inner(code)")
        .eq("is_primary", true)
        .eq("card_asset_type.code", "CARD_FRONT")
        .range(from, to),
    ),
  ]);

  const totalVariacoes = variantResult.count ?? 0;
  const totalImagens = assetResult.count ?? 0;
  const cardsComImagem = new Set((frontAssetsRows as { card_id: string }[]).map((row) => row.card_id)).size;
  const cardsSemImagem = Math.max(totalCartas - cardsComImagem, 0);

  return { totalVariacoes, totalImagens, cardsSemImagem };
}

export type CatalogoCardSetImagensRow = CatalogoCardSetRow & {
  /** Cards com pelo menos uma imagem primária (CARD_FRONT, qualquer idioma) já registrada — mesmo critério de "tem imagem" usado pelo indicador global `cardsSemImagem` (getCartasCatalogoStats), agora por Card Set. */
  imagesImportadas: number;
  /** cardsCatalogados - imagesImportadas — nunca negativo. */
  imagesPendentes: number;
};

/**
 * Quantos Cards de cada Card Set já têm pelo menos uma imagem primária
 * (CARD_FRONT) registrada — mesmo critério/consulta de `getCartasCatalogoStats`
 * (`card_asset.is_primary = true` + `card_asset_type.code = 'CARD_FRONT'`,
 * embed-relation-filter via `!inner`/`.eq()`), agrupado por `card_set_id`
 * através de um segundo embed (`card!inner(card_set_id)`) — mesmo padrão já
 * usado por `contarImagensImportadas` em `tcgdex/actions.ts` (2026-08-02),
 * aqui generalizado para vários Card Sets de uma vez em vez de um só.
 * `.in("card.card_set_id", ...)` filtra pela tabela relacionada, mesmo
 * mecanismo de `.eq("card.card_set_id", ...)` já confirmado funcionando em
 * produção.
 *
 * `languageCode` (2026-08-02, suporte EN + PT-BR): antes esta consulta não
 * filtrava por idioma NENHUM — contava qualquer `card_asset` CARD_FRONT
 * primário, de qualquer idioma, então uma Coleção 100% importada em `en`
 * aparecia como "completa" mesmo com `pt-BR` inteiramente pendente. Agora
 * exige `language!inner(code)` + `.eq("language.code", languageCode)`, mesmo
 * padrão já usado por `contarImagensImportadas`.
 */
async function getImagesImportadasPorCardSet(
  supabase: SupabaseClient,
  cardSetIds: string[],
  languageCode: string,
): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  if (cardSetIds.length === 0) return counts;

  const rows = await fetchAllRows((from, to) =>
    supabase
      .from("card_asset")
      .select("card_id, card!inner(card_set_id), card_asset_type!inner(code), language!inner(code)")
      .eq("is_primary", true)
      .eq("card_asset_type.code", "CARD_FRONT")
      .eq("language.code", languageCode)
      .in("card.card_set_id", cardSetIds)
      .range(from, to),
  );

  const cardIdsBySet = new Map<string, Set<string>>();
  for (const row of rows as { card_id: string; card: { card_set_id: string } | { card_set_id: string }[] | null }[]) {
    const cardSetId = Array.isArray(row.card) ? row.card[0]?.card_set_id : row.card?.card_set_id;
    if (!cardSetId) continue;
    if (!cardIdsBySet.has(cardSetId)) cardIdsBySet.set(cardSetId, new Set());
    cardIdsBySet.get(cardSetId)!.add(row.card_id);
  }
  for (const [cardSetId, cardIds] of cardIdsBySet) {
    counts.set(cardSetId, cardIds.size);
  }
  return counts;
}

/**
 * Card Sets elegíveis para a tela dedicada `/catalogo/importar-imagens`
 * (2026-08-02, pedido explícito de Fabrício: página própria, cópia da
 * `Importar Cartas` em layout, para retomar a importação de imagens de uma
 * Coleção que já tem Cards cadastradas — o seletor de `Importar Cartas` para
 * de listar uma Coleção assim que ela ganha a primeira Card, então não havia
 * como reabrir a importação de imagens pela tela depois de uma falha
 * parcial/total, como a de SV4/Fenda Paradoxal, Query 2092 v1.2).
 *
 * Critério: Card Set com pelo menos uma Card cadastrada (`cardsCatalogados >
 * 0` — sem cartas, é `Importar Cartas` que resolve) E com pelo menos uma
 * Card ainda sem imagem (`imagesPendentes > 0`) — cobre os três casos do
 * pedido de Fabrício na mesma condição: nunca importado (`imagesImportadas
 * = 0`), falha parcial (`0 < imagesImportadas < cardsCatalogados`) e falha
 * total (mesma coisa que nunca importado, do ponto de vista desta consulta
 * — a run em si pode ter FAILED, mas o que importa aqui é quantas Cards
 * ainda não têm imagem).
 *
 * `languageCode` (2026-08-02, DEFAULT 'en' — mesmo padrão default de
 * `admin_start_asset_import_run()` v1.3, preserva o comportamento anterior
 * para quem ainda não passa o parâmetro): decide QUAL idioma está pendente —
 * a mesma Coleção pode aparecer para `en` e para `pt-BR` de forma
 * independente, cada consulta vendo só o idioma pedido.
 */
export async function getCardSetsForImportacaoImagens(
  supabase: SupabaseClient,
  languageCode: string = "en",
): Promise<CatalogoCardSetImagensRow[]> {
  const cardSets = (await getCardSetsForCartas(supabase)).filter((cardSet) => cardSet.cardsCatalogados > 0);
  const imagesImportadasCounts = await getImagesImportadasPorCardSet(
    supabase,
    cardSets.map((cardSet) => cardSet.id),
    languageCode,
  );

  return cardSets
    .map((cardSet) => {
      const imagesImportadas = imagesImportadasCounts.get(cardSet.id) ?? 0;
      const imagesPendentes = Math.max(cardSet.cardsCatalogados - imagesImportadas, 0);
      return { ...cardSet, imagesImportadas, imagesPendentes };
    })
    .filter((cardSet) => cardSet.imagesPendentes > 0);
}

/**
 * Um Card Set específico, com as mesmas contagens de imagem de
 * `getCardSetsForImportacaoImagens` (`imagesImportadas`/`imagesPendentes`),
 * mas SEM o filtro `imagesPendentes > 0` — usada como fallback em
 * `page.tsx` (2026-08-02, correção de bug real reportado por Fabrício: a
 * tela `/catalogo/importar-imagens` resetava — combobox voltava para
 * "Selecione uma Coleção..." e o resultado final da importação sumia — assim
 * que uma importação terminava com sucesso. Causa: `page.tsx` resolvia
 * `selectedCardSet` só a partir da lista filtrada por pendentes; quando
 * `imagesPendentes` chegava a 0, o Card Set some dessa lista, `selectedCardSet`
 * virava `null`, e a `key={selectedCardSet?.id}` de `ImportarImagensView`
 * forçava um remount que apagava todo o estado de progresso em React. Esta
 * função permite `page.tsx` continuar resolvendo o Card Set selecionado
 * mesmo depois de sair da lista de pendentes — a lista (`cardSets`, usada só
 * para popular as OPÇÕES do combobox) continua filtrada normalmente, então
 * a Coleção concluída não volta a ser oferecida para nova seleção, só
 * permanece visível enquanto for a que já está selecionada.
 *
 * `languageCode` (2026-08-02, DEFAULT 'en', mesmo motivo de
 * `getCardSetsForImportacaoImagens`): precisa ser o MESMO idioma que a tela
 * está mostrando — senão `imagesPendentes` reflete o idioma errado.
 */
export async function getCardSetImagensById(
  supabase: SupabaseClient,
  cardSetId: string,
  languageCode: string = "en",
): Promise<CatalogoCardSetImagensRow | null> {
  const cardSets = await getCardSetsForCartas(supabase);
  const cardSet = cardSets.find((row) => row.id === cardSetId);
  if (!cardSet) return null;

  const imagesImportadasCounts = await getImagesImportadasPorCardSet(supabase, [cardSetId], languageCode);
  const imagesImportadas = imagesImportadasCounts.get(cardSetId) ?? 0;
  const imagesPendentes = Math.max(cardSet.cardsCatalogados - imagesImportadas, 0);
  return { ...cardSet, imagesImportadas, imagesPendentes };
}

export type CartaManualImportManifestRow = {
  id: string;
  collectorNumber: string;
  name: string;
  /** Já tem CARD_FRONT primário nesse idioma — mesmo critério de `getImagesImportadasPorCardSet`. Usado pela tela `/catalogo/importar-imagens` (modo Manual) para validar a seleção de arquivos ANTES do upload: sinaliza arquivo cujo Card já tem imagem (aviso de sobrescrita, não bloqueante) e Card sem arquivo correspondente (informativo). */
  hasImage: boolean;
};

/**
 * Manifesto de Cards de um Card Set + idioma, para a validação prévia do
 * modo Manual da tela `/catalogo/importar-imagens` (ADR-026, emenda
 * "Segundo ponto de entrada via UI", 2026-08-08) — carregado uma vez ao
 * selecionar Coleção+idioma, permitindo checar nomes/quantidade/duplicidade/
 * Card inexistente/Card já com imagem no cliente, sem uma chamada por
 * arquivo. Mesmo critério de "tem imagem" de `getImagesImportadasPorCardSet`
 * (`is_primary = true` + `card_asset_type.code = 'CARD_FRONT'` +
 * `language.code = languageCode`), aqui por Card individual em vez de
 * agregado por Card Set. Ordenado por `collectorNumber` (ordem numérica,
 * não lexicográfica — `"10"` depois de `"2"`) para a tabela de revisão
 * ficar sempre em ordem crescente.
 */
export async function getCartasParaImportacaoManual(
  supabase: SupabaseClient,
  cardSetId: string,
  languageCode: string,
): Promise<CartaManualImportManifestRow[]> {
  const [cardRows, assetRows] = await Promise.all([
    fetchAllRows((from, to) =>
      supabase
        .from("card")
        .select("id, collector_number, name")
        .eq("card_set_id", cardSetId)
        .eq("is_active", true)
        .range(from, to),
    ),
    fetchAllRows((from, to) =>
      supabase
        .from("card_asset")
        .select("card_id, card!inner(card_set_id), card_asset_type!inner(code), language!inner(code)")
        .eq("is_primary", true)
        .eq("card_asset_type.code", "CARD_FRONT")
        .eq("language.code", languageCode)
        .eq("card.card_set_id", cardSetId)
        .range(from, to),
    ),
  ]);

  const cardIdsWithImage = new Set((assetRows as { card_id: string }[]).map((row) => row.card_id));

  return (cardRows as { id: string; collector_number: string; name: string }[])
    .map((card) => ({
      id: card.id,
      collectorNumber: card.collector_number,
      name: card.name,
      hasImage: cardIdsWithImage.has(card.id),
    }))
    .sort((a, b) => a.collectorNumber.localeCompare(b.collectorNumber, undefined, { numeric: true }));
}

export type CartaCompletaRow = {
  id: string;
  collectorNumber: string;
  collectorTotal: number | null;
  collectorOrder: number;
  name: string;
  /** Adicionado 2026-08-07 (tela de edição de Card, pedido de Fabrício: "duas cartas cadastradas com a raridade errada") — os `id`s brutos de raridade/categoria não eram necessários enquanto a tela só exibia (nunca editava) esses dados; agora alimentam os selects de `EditCardDialog`. */
  rarityId: string;
  rarityCode: string;
  rarityName: string;
  rarityDisplayOrder: number;
  raritySymbolCode: string;
  categoryId: string;
  categoryCode: string;
  categoryName: string;
  categoryDisplayOrder: number;
  /** Imagem CARD_FRONT principal em português (pt-BR), quando importada. */
  imageUrlPt: string | null;
  /** Imagem CARD_FRONT principal em inglês (en), quando importada. */
  imageUrlEn: string | null;
  /**
   * Adicionado 2026-08-07 (subciclo Card: criação e desativação/reativação,
   * ADR-023) — soft delete real (Query 2020). Antes desta rodada,
   * `getCartasCompletas` filtrava sempre `is_active = true` no próprio
   * banco, então esse campo nem existia (toda linha retornada já era
   * ativa por construção). Agora que a tela pode exibir cartas inativas
   * (toggle "Mostrar inativas"), a UI precisa saber, por carta, qual é o
   * estado — daí este campo.
   */
  isActive: boolean;
};

type CartaCompletaAssetRawRow = {
  storage_path: string | null;
  is_primary: boolean;
  card_asset_type: { code: string } | null;
  language: { code: string } | null;
};

type CartaCompletaRawRow = {
  id: string;
  collector_number: string;
  collector_total: number | null;
  collector_order: number;
  name: string;
  is_active: boolean;
  rarity: { id: string; code: string; name: string; symbol_code: string; display_order: number } | null;
  card_category: { id: string; code: string; name: string; display_order: number } | null;
  card_asset: CartaCompletaAssetRawRow[] | null;
};

/**
 * Caminho da imagem CARD_FRONT principal de um idioma específico — usada
 * duas vezes (pt-BR e en) para alimentar o alternador de idioma da imagem
 * na tela Cartas (pedido de Fabrício, 2026-07-31: "incluir um componente
 * para alternar entre imagens das cartas em PT e IN"). Antes só o idioma
 * preferido (`IMAGE_LANGUAGE_PRIORITY`, pt-BR > en) era resolvido — agora
 * ambos ficam disponíveis em `CartaCompletaRow` e a UI decide qual mostrar;
 * nem todo Card Set tem os dois idiomas importados (ver
 * docs/06-pipeline-importacao.md), então um dos dois pode vir `null`.
 */
function pickCardFrontPath(assets: CartaCompletaAssetRawRow[] | null, languageCode: string): string | null {
  if (!assets) return null;
  return (
    assets.find(
      (asset) =>
        asset.is_primary &&
        asset.card_asset_type?.code === "CARD_FRONT" &&
        asset.storage_path &&
        asset.language?.code === languageCode,
    )?.storage_path ?? null
  );
}

/**
 * Todas as cartas ativas de um único Card Set, com imagem (CARD_FRONT,
 * ativo principal, ver `pickCardFrontPath`) e metadados de raridade/
 * categoria — base da galeria visual de Cartas (pedido de Fabrício,
 * 2026-07-31: "a exibição das cartas é a funcionalidade que deve
 * impressionar qualquer usuário visualmente"). Ordenadas por
 * `collector_order` — decisão já registrada em `getCartasPorCardSet`
 * (função que esta substitui): `collector_order` é relativo a cada Card
 * Set, então uma lista sem filtro de Set intercalaria numerações sem
 * sentido; o seletor "Coleção" (`getCardSetsForCartas`) resolve isso.
 *
 * Bucket `card-front` é público (Seed 895 — `is_public = TRUE`, diferente
 * dos buckets de logo que são privados/assinados) — `getPublicUrl()` é
 * síncrono, sem round-trip extra por carta. Nenhuma política de RLS nova
 * foi necessária: `card`, `card_asset`, `rarity`, `card_category` já têm
 * SELECT liberado para authenticated+is_admin() desde a Query 274
 * (ADR-022), a mesma leitura que `getCartasPorCardSet` já fazia para
 * `card`/`rarity`/`card_category`.
 *
 * `options.incluirInativas` (2026-08-07, subciclo Card: criação e
 * desativação/reativação, ADR-023) — por padrão continua filtrando só
 * `is_active = true` (mesmo comportamento de sempre, seguro para qualquer
 * chamador futuro que não conheça o toggle "Mostrar inativas"); `page.tsx`
 * passa `incluirInativas: true` explicitamente, porque a galeria precisa
 * das cartas inativas tanto para o toggle quanto para sugerir o próximo
 * `collector_order` livre (Card criada considerando ativas E inativas,
 * mesma regra de duplicidade da Query 2115) sem uma segunda consulta.
 */
export async function getCartasCompletas(
  supabase: SupabaseClient,
  cardSetId: string,
  options?: { incluirInativas?: boolean },
): Promise<CartaCompletaRow[]> {
  let query = supabase
    .from("card")
    .select(
      "id, collector_number, collector_total, collector_order, name, is_active, rarity(id, code, name, symbol_code, display_order), card_category(id, code, name, display_order), card_asset(storage_path, is_primary, card_asset_type(code), language(code))",
    )
    .eq("card_set_id", cardSetId);

  if (!options?.incluirInativas) {
    query = query.eq("is_active", true);
  }

  const { data, error } = await query.order("collector_order", { ascending: true });

  if (error || !data) {
    return [];
  }

  return (data as unknown as CartaCompletaRawRow[]).map((card) => {
    const pathPt = pickCardFrontPath(card.card_asset, "pt-BR");
    const pathEn = pickCardFrontPath(card.card_asset, "en");
    return {
      id: card.id,
      collectorNumber: card.collector_number,
      collectorTotal: card.collector_total,
      collectorOrder: card.collector_order,
      name: card.name,
      isActive: card.is_active,
      rarityId: card.rarity?.id ?? "",
      rarityCode: card.rarity?.code ?? "",
      rarityName: card.rarity?.name ?? "—",
      rarityDisplayOrder: card.rarity?.display_order ?? 0,
      raritySymbolCode: card.rarity?.symbol_code ?? "",
      categoryId: card.card_category?.id ?? "",
      categoryCode: card.card_category?.code ?? "",
      categoryName: card.card_category?.name ?? "—",
      categoryDisplayOrder: card.card_category?.display_order ?? 0,
      imageUrlPt: pathPt ? (supabase.storage.from("card-front").getPublicUrl(pathPt).data.publicUrl ?? null) : null,
      imageUrlEn: pathEn ? (supabase.storage.from("card-front").getPublicUrl(pathEn).data.publicUrl ?? null) : null,
    };
  });
}

export type CategoriaOption = { id: string; code: string; name: string; displayOrder: number };

/**
 * Todas as Categorias editoriais (Pokémon/Treinador/Energia) cadastradas —
 * novo em 2026-08-07, alimenta o select "Categoria" de `EditCardDialog`
 * (tela de edição de Card, pedido de Fabrício: "editar todas as informações
 * possíveis... incluindo a sua raridade"). Mesmo padrão de `getGameOptions`:
 * cadastro fixo/pequeno, sem paginação.
 */
export async function getCategoriaOptions(supabase: SupabaseClient): Promise<CategoriaOption[]> {
  const { data, error } = await supabase
    .from("card_category")
    .select("id, code, name, display_order")
    .order("display_order", { ascending: true });

  if (error || !data) {
    return [];
  }

  return (data as { id: string; code: string; name: string; display_order: number }[]).map((row) => ({
    id: row.id,
    code: row.code,
    name: row.name,
    displayOrder: row.display_order,
  }));
}

export type ImportacaoRow = {
  id: string;
  runCode: string;
  runType: string;
  status: string;
  executionContext: string;
  assetSourceName: string | null;
  cardSetCode: string | null;
  cardSetName: string | null;
  languageCode: string | null;
  requestedCount: number;
  successCount: number;
  failedCount: number;
  createdAt: string;
};

type AssetImportRunFullRawRow = {
  id: string;
  run_code: string;
  run_type: string;
  status: string;
  execution_context: string;
  requested_count: number;
  success_count: number;
  failed_count: number;
  created_at: string;
  asset_source: { name: string } | null;
  card_set: { code: string; name: string } | null;
  language: { code: string } | null;
};

/** Histórico completo de execuções de importação — versão sem `limit` de getAtividadeRecente, para a tela dedicada. */
export async function getImportacoes(supabase: SupabaseClient): Promise<ImportacaoRow[]> {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select(
      "id, run_code, run_type, status, execution_context, requested_count, success_count, failed_count, created_at, asset_source(name), card_set(code, name), language(code)",
    )
    .order("created_at", { ascending: false });

  if (error || !data) {
    return [];
  }

  return (data as unknown as AssetImportRunFullRawRow[]).map((run) => ({
    id: run.id,
    runCode: run.run_code,
    runType: run.run_type,
    status: run.status,
    executionContext: run.execution_context,
    assetSourceName: run.asset_source?.name ?? null,
    cardSetCode: run.card_set?.code ?? null,
    cardSetName: run.card_set?.name ?? null,
    languageCode: run.language?.code ?? null,
    requestedCount: run.requested_count,
    successCount: run.success_count,
    failedCount: run.failed_count,
    createdAt: run.created_at,
  }));
}

// ---------------------------------------------------------------------------
// Importação via TCGdex (Ciclo 2, ADR-024) — leitura de apoio ao fluxo
// /catalogo/importar-cartas, adicionada em 2026-08-01.
// ---------------------------------------------------------------------------

// `getCardSetsSemCartas`/`CardSetSemCartasRow` removidos em 2026-08-01: o
// filtro "só Coleções com zero cartas" (que essa função existia só para
// aplicar) tinha sido tentativamente removido na mesma rodada, mas
// Fabrício confirmou que o seletor DEVE continuar restrito a Coleções sem
// cartas — o próprio protótipo mostrar "ME5" foi lido errado (ME5 é o
// exemplo do rótulo, não uma Coleção com cartas de fato sendo oferecida).
// O filtro agora é aplicado inline em `/catalogo/importar-cartas/page.tsx`
// a partir do resultado de getCardSetsForCartas() (mesma base de
// `cardsCatalogados` de sempre) — sem reintroduzir uma função só para um
// `.filter()` de uma linha.

export type CatalogImportJobStatus = {
  id: string;
  status: string;
  progressStep: string | null;
  totalRows: number;
  validRows: number;
  rejectedRows: number;
  insertedRows: number;
  updatedRows: number;
  unchangedRows: number;
  skippedRows: number;
  failedRows: number;
  errorSummary: string | null;
  cardSetCode: string;
  cardSetName: string;
};

type CatalogImportJobRawRow = {
  id: string;
  status: string;
  progress_step: string | null;
  total_rows: number;
  valid_rows: number;
  rejected_rows: number;
  inserted_rows: number;
  updated_rows: number;
  unchanged_rows: number;
  skipped_rows: number;
  failed_rows: number;
  error_summary: string | null;
  card_set: { code: string; name: string } | null;
};

/** Status real de um catalog_import_job (Query 2060) — base da tela de acompanhamento do fluxo TCGdex. */
export async function getCatalogImportJobStatus(
  supabase: SupabaseClient,
  jobId: string,
): Promise<CatalogImportJobStatus | null> {
  const { data, error } = await supabase
    .from("catalog_import_job")
    .select(
      "id, status, progress_step, total_rows, valid_rows, rejected_rows, inserted_rows, updated_rows, unchanged_rows, skipped_rows, failed_rows, error_summary, card_set(code, name)",
    )
    .eq("id", jobId)
    .maybeSingle();

  if (error || !data) return null;

  const row = data as unknown as CatalogImportJobRawRow;

  return {
    id: row.id,
    status: row.status,
    progressStep: row.progress_step,
    totalRows: row.total_rows,
    validRows: row.valid_rows,
    rejectedRows: row.rejected_rows,
    insertedRows: row.inserted_rows,
    updatedRows: row.updated_rows,
    unchangedRows: row.unchanged_rows,
    skippedRows: row.skipped_rows,
    failedRows: row.failed_rows,
    errorSummary: row.error_summary,
    cardSetCode: row.card_set?.code ?? "",
    cardSetName: row.card_set?.name ?? "",
  };
}

export type CatalogImportRowView = {
  id: string;
  name: string;
  collectorNumber: string;
  collectorTotal: number | null;
  category: string | null;
  categorySource: string | null;
  categoryConfidence: string | null;
  /** Raridade exatamente como veio da TCGdex (raw_data.rarity) — ver comentário de getCatalogImportRows abaixo. */
  rawRarity: string | null;
  /** URL-base da imagem da TCGdex (raw_data.image, sem sufixo) — ver comentário de getCatalogImportRows abaixo. */
  imageBaseUrl: string | null;
  reviewNotes: string[];
  validationStatus: string;
  matchStatus: string;
  decisionStatus: string;
  persistenceStatus: string;
  errorDetail: string | null;
};

type CatalogImportRowNormalizedData = {
  name?: string;
  collector_number?: string;
  collector_total?: number | null;
  category?: string | null;
  category_source?: string | null;
  category_confidence?: string | null;
  review_notes?: string[] | null;
};

type CatalogImportRowRawRow = {
  id: string;
  raw_data: Record<string, unknown> | null;
  normalized_data: CatalogImportRowNormalizedData | null;
  validation_status: string;
  match_status: string;
  decision_status: string;
  persistence_status: string;
  error_detail: string | null;
};

/**
 * Linhas de staging (catalog_import_row, Query 2070) de um job — base da
 * tela de Revisão (Ciclo 2, Sprint 2b, ADR-024).
 *
 * Buscadas em ordem de created_at (mesma ordem usada por
 * admin_confirm_catalog_import(), Query 2082, `ORDER BY r.created_at`, e
 * pela inserção em lote do processador), mas **exibidas** em ordem
 * crescente de collector_number (2026-08-01, terceira rodada, pedido de
 * Fabrício: "a tabela de revisão deve ser organizada em ordem crescente
 * pelo campo número da carta" — created_at não tem significado nenhum pra
 * quem está revisando visualmente). `collector_number` vem de
 * normalized_data (JSONB), não uma coluna própria, então o sort é feito
 * aqui em memória (nunca no SQL) — `Number(...)` porque é string
 * ("001", "157"...); `Number.parseInt` falharia silenciosamente em casos
 * como "157a" (não deveria existir, mas cai pro fim da lista via `NaN` →
 * `Infinity` em vez de quebrar a ordenação inteira). A ordem usada por
 * admin_confirm_catalog_import() continua sendo a de created_at — só a
 * exibição mudou, o RPC não foi tocado.
 *
 * `rawRarity` lê raw_data.rarity (texto exatamente como veio da TCGdex, ex.:
 * "Rare Holo") em vez de resolver rarity_id contra public.rarity: é o mesmo
 * dado que normalize.ts (Edge Function) usou para decidir
 * RARIDADE_NAO_MAPEADA/RARIDADE_AUSENTE_NA_TCGDEX — mostra ao administrador
 * exatamente o que foi avaliado, sem uma segunda consulta para resolver um
 * nome canônico que a própria linha pode nem ter conseguido mapear (rarity_id
 * fica NULL nesse caso).
 *
 * `imageBaseUrl` lê raw_data.image (2026-08-01, nona rodada — miniatura na
 * revisão, pedido de Fabrício: "a revisão deve parecer uma revisão de
 * cartas"). É uma URL-base da TCGdex sem sufixo/extensão (ex.:
 * "https://assets.tcgdex.net/pt/sv/sv03/014") — quem renderiza acrescenta
 * `/low.webp` (miniatura pequena; mesma convenção de sufixo que
 * `buildTcgdexHighImageUrl` usa com `/high.webp` para a imagem em alta
 * resolução, em supabase/functions/import-card-assets/services/storage.ts,
 * só que aqui optou-se pela variante leve por ser só uma miniatura de
 * tabela). Puramente leitura de um campo já buscado — não é uma nova chamada
 * de rede nem toca banco/Edge Function.
 */
export async function getCatalogImportRows(
  supabase: SupabaseClient,
  jobId: string,
): Promise<CatalogImportRowView[]> {
  const { data, error } = await supabase
    .from("catalog_import_row")
    .select(
      "id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status, error_detail",
    )
    .eq("job_id", jobId)
    .order("created_at", { ascending: true });

  if (error || !data) {
    return [];
  }

  const rows = (data as unknown as CatalogImportRowRawRow[]).map((row) => {
    const normalized = row.normalized_data ?? {};
    const rawRarity = typeof row.raw_data?.rarity === "string" ? (row.raw_data.rarity as string) : null;
    const imageBaseUrl = typeof row.raw_data?.image === "string" ? (row.raw_data.image as string) : null;

    return {
      id: row.id,
      name: normalized.name ?? "—",
      collectorNumber: normalized.collector_number ?? "—",
      collectorTotal: normalized.collector_total ?? null,
      category: normalized.category ?? null,
      categorySource: normalized.category_source ?? null,
      categoryConfidence: normalized.category_confidence ?? null,
      rawRarity,
      imageBaseUrl,
      reviewNotes: normalized.review_notes ?? [],
      validationStatus: row.validation_status,
      matchStatus: row.match_status,
      decisionStatus: row.decision_status,
      persistenceStatus: row.persistence_status,
      errorDetail: row.error_detail,
    };
  });

  return rows.sort((a, b) => {
    const numA = Number(a.collectorNumber);
    const numB = Number(b.collectorNumber);
    return (Number.isNaN(numA) ? Infinity : numA) - (Number.isNaN(numB) ? Infinity : numB);
  });
}

export async function getAtividadeRecente(supabase: SupabaseClient, limit = 8): Promise<AtividadeRecenteItem[]> {
  const { data, error } = await supabase
    .from("asset_import_run")
    .select(
      "id, run_code, status, execution_context, requested_count, success_count, failed_count, created_at, card_set(code, name), language(code)",
    )
    .order("created_at", { ascending: false })
    .limit(limit);

  if (error || !data) {
    return [];
  }

  return (data as unknown as AssetImportRunRow[]).map((run) => ({
    id: run.id,
    runCode: run.run_code,
    cardSetCode: run.card_set?.code ?? null,
    cardSetName: run.card_set?.name ?? null,
    languageCode: run.language?.code ?? null,
    status: run.status,
    executionContext: run.execution_context,
    requestedCount: run.requested_count,
    successCount: run.success_count,
    failedCount: run.failed_count,
    createdAt: run.created_at,
  }));
}

/**
 * Camada de leitura da tela /catalogo/raridades (task #336, ciclo de
 * cadastro self-service de Raridade, 2026-08-06/07 — ver
 * `docs/log.md`). Duas responsabilidades: `getRaridades` lista as
 * raridades canônicas já cadastradas com seus mapeamentos externos
 * (`rarity_external_mapping`); `getRevalidacaoPendenteResumo` calcula, a
 * partir dos jobs hoje revalidáveis (`STAGED`/`CONFIRMING`/
 * `COMPLETED_WITH_ERRORS` — mesmo filtro de `listRevalidatableJobs` na
 * Edge Function `revalidate-catalog-import-rows`), quais valores brutos de
 * raridade (`raw_data.rarity`, texto exatamente como veio da fonte
 * externa) ainda não têm mapeamento — é essa lista que alimenta o fluxo
 * "Resolver raridade".
 *
 * `getRaridades` busca `rarity` e `rarity_external_mapping` em duas
 * consultas simples e junta em memória, em vez de um select com
 * relacionamento embutido do PostgREST (`rarity_external_mapping(...)`) —
 * mesma cautela documentada em `import-catalog-cards`/
 * `revalidate-catalog-import-rows` (2026-08-07): esse embed específico já
 * falhou em produção nesta rodada (ver `docs/log.md`, fix do GYM1/SWSH1).
 */
export type RaridadeMapeamentoRow = {
  id: string;
  assetSourceCode: string;
  externalValue: string;
  normalizedExternalValue: string;
};

export type RaridadeRow = {
  id: string;
  code: string;
  name: string;
  symbolCode: string;
  displayOrder: number;
  createdAt: string;
  updatedAt: string;
  mapeamentos: RaridadeMapeamentoRow[];
};

type RarityRawRow = {
  id: string;
  code: string;
  name: string;
  symbol_code: string;
  display_order: number;
  created_at: string;
  updated_at: string;
};

type RarityExternalMappingRawRow = {
  id: string;
  rarity_id: string;
  asset_source_id: string;
  external_value: string;
  normalized_external_value: string;
};

export async function getRaridades(supabase: SupabaseClient): Promise<RaridadeRow[]> {
  const { data: rarityRows, error: rarityError } = await supabase
    .from("rarity")
    .select("id, code, name, symbol_code, display_order, created_at, updated_at")
    .order("display_order", { ascending: true });

  if (rarityError || !rarityRows) {
    return [];
  }

  const { data: mappingRows } = await supabase
    .from("rarity_external_mapping")
    .select("id, rarity_id, asset_source_id, external_value, normalized_external_value");

  const { data: sourceRows } = await supabase.from("asset_source").select("id, code");
  const sourceCodeById = new Map<string, string>(
    ((sourceRows ?? []) as { id: string; code: string }[]).map((s) => [s.id, s.code]),
  );

  const mappingsByRarityId = new Map<string, RaridadeMapeamentoRow[]>();
  for (const mapping of (mappingRows ?? []) as RarityExternalMappingRawRow[]) {
    const list = mappingsByRarityId.get(mapping.rarity_id) ?? [];
    list.push({
      id: mapping.id,
      assetSourceCode: sourceCodeById.get(mapping.asset_source_id) ?? "—",
      externalValue: mapping.external_value,
      normalizedExternalValue: mapping.normalized_external_value,
    });
    mappingsByRarityId.set(mapping.rarity_id, list);
  }

  return (rarityRows as unknown as RarityRawRow[]).map((rarity) => ({
    id: rarity.id,
    code: rarity.code,
    name: rarity.name,
    symbolCode: rarity.symbol_code,
    displayOrder: rarity.display_order,
    createdAt: rarity.created_at,
    updatedAt: rarity.updated_at,
    mapeamentos: mappingsByRarityId.get(rarity.id) ?? [],
  }));
}

export type RaridadePendenteRow = {
  /** Texto exatamente como veio da fonte externa (raw_data.rarity). */
  rawValue: string;
  totalLinhas: number;
  /** Códigos de Coleção afetados por este valor não mapeado, ordenados. */
  cardSets: string[];
};

export type RevalidacaoPendenteResumo = {
  totalJobsRevalidaveis: number;
  totalLinhasPendentes: number;
  valoresNaoMapeados: RaridadePendenteRow[];
};

const RAIDADE_JOB_STATUSES_REVALIDAVEIS = ["STAGED", "CONFIRMING", "COMPLETED_WITH_ERRORS"] as const;

export async function getRevalidacaoPendenteResumo(supabase: SupabaseClient): Promise<RevalidacaoPendenteResumo> {
  const { data: jobs, error: jobsError } = await supabase
    .from("catalog_import_job")
    .select("id, card_set_id")
    .in("status", RAIDADE_JOB_STATUSES_REVALIDAVEIS);

  if (jobsError || !jobs || jobs.length === 0) {
    return { totalJobsRevalidaveis: 0, totalLinhasPendentes: 0, valoresNaoMapeados: [] };
  }

  const jobRows = jobs as { id: string; card_set_id: string }[];
  const jobIds = jobRows.map((job) => job.id);
  const cardSetIdByJobId = new Map<string, string>(jobRows.map((job) => [job.id, job.card_set_id]));

  const { data: cardSetRows } = await supabase.from("card_set").select("id, code");
  const cardSetCodeById = new Map<string, string>(
    ((cardSetRows ?? []) as { id: string; code: string }[]).map((cs) => [cs.id, cs.code]),
  );

  const { data: rows, error: rowsError } = await supabase
    .from("catalog_import_row")
    .select("job_id, raw_data, normalized_data")
    .in("job_id", jobIds);

  if (rowsError || !rows) {
    return { totalJobsRevalidaveis: jobIds.length, totalLinhasPendentes: 0, valoresNaoMapeados: [] };
  }

  const porValor = new Map<string, { totalLinhas: number; cardSets: Set<string> }>();
  let totalLinhasPendentes = 0;

  for (const row of rows as { job_id: string; raw_data: Record<string, unknown>; normalized_data: Record<string, unknown> }[]) {
    const rarityId = (row.normalized_data as { rarity_id?: string | null } | null)?.rarity_id ?? null;
    if (rarityId) continue;

    totalLinhasPendentes += 1;
    const rawValue = typeof row.raw_data?.rarity === "string" ? (row.raw_data.rarity as string) : "(sem valor)";
    const entry = porValor.get(rawValue) ?? { totalLinhas: 0, cardSets: new Set<string>() };
    entry.totalLinhas += 1;

    const cardSetId = cardSetIdByJobId.get(row.job_id);
    const cardSetCode = cardSetId ? cardSetCodeById.get(cardSetId) : undefined;
    if (cardSetCode) entry.cardSets.add(cardSetCode);

    porValor.set(rawValue, entry);
  }

  const valoresNaoMapeados = Array.from(porValor.entries())
    .map(([rawValue, entry]) => ({
      rawValue,
      totalLinhas: entry.totalLinhas,
      cardSets: Array.from(entry.cardSets).sort(),
    }))
    .sort((a, b) => b.totalLinhas - a.totalLinhas);

  return {
    totalJobsRevalidaveis: jobIds.length,
    totalLinhasPendentes,
    valoresNaoMapeados,
  };
}
