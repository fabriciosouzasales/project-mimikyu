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
 * Busca de uma vez a base para Estado do Catálogo, Card Sets e Distribuição
 * por Raridade — uma única leitura de `card` (927 linhas hoje, volume
 * pequeno o suficiente para agregar no servidor) com `card_asset(count)` e
 * `rarity` embutidos, evitando N+1 consultas por Card Set/Raridade.
 */
async function fetchCardsComCobertura(supabase: SupabaseClient): Promise<CardRow[]> {
  const { data, error } = await supabase
    .from("card")
    .select("id, card_set_id, rarity_id, card_asset(count), rarity(code, name, display_order)");

  if (error || !data) {
    return [];
  }

  return data as unknown as CardRow[];
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

export async function getEstadoDoCatalogo(supabase: SupabaseClient): Promise<EstadoDoCatalogo> {
  const [cards, cardSets] = await Promise.all([fetchCardsComCobertura(supabase), fetchCardSets(supabase)]);

  const cardsPorSet = new Map<string, { total: number; comImagem: number }>();
  for (const card of cards) {
    const atual = cardsPorSet.get(card.card_set_id) ?? { total: 0, comImagem: 0 };
    atual.total += 1;
    if (extractCount(card.card_asset) > 0) {
      atual.comImagem += 1;
    }
    cardsPorSet.set(card.card_set_id, atual);
  }

  const cardSetsComImagensCompletas = cardSets.filter((set) => {
    const cobertura = cardsPorSet.get(set.id);
    return !!cobertura && cobertura.total > 0 && cobertura.total === cobertura.comImagem;
  }).length;

  const { count: execucoesComPendencia } = await supabase
    .from("asset_import_run")
    .select("id", { count: "exact", head: true })
    .neq("status", "COMPLETED");

  return {
    cardSetsCatalogados: cardSets.length,
    cardSetsComImagensCompletas,
    cartasCatalogadas: cards.length,
    execucoesComPendencia: execucoesComPendencia ?? 0,
  };
}

export async function getCardSetsOverview(supabase: SupabaseClient): Promise<CardSetOverviewRow[]> {
  const [cards, cardSets] = await Promise.all([fetchCardsComCobertura(supabase), fetchCardSets(supabase)]);

  const cardsPorSet = new Map<string, { total: number; comImagem: number }>();
  for (const card of cards) {
    const atual = cardsPorSet.get(card.card_set_id) ?? { total: 0, comImagem: 0 };
    atual.total += 1;
    if (extractCount(card.card_asset) > 0) {
      atual.comImagem += 1;
    }
    cardsPorSet.set(card.card_set_id, atual);
  }

  return cardSets.map((set) => {
    const cobertura = cardsPorSet.get(set.id) ?? { total: 0, comImagem: 0 };
    return {
      code: set.code,
      name: set.name,
      setType: set.set_type,
      totalSetSize: set.total_set_size,
      cardsCatalogados: cobertura.total,
      temImagensCompletas: cobertura.total > 0 && cobertura.total === cobertura.comImagem,
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
  releaseOrder: number;
  releaseDate: string | null;
  expansionId: string;
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

type CatalogoCardSetRawRow = {
  id: string;
  code: string;
  name: string;
  release_order: number;
  release_date: string | null;
  logo_storage_path: string | null;
  created_at: string;
  expansion: { id: string; name: string; release_order: number; game: { id: string; code: string; name: string } | null } | null;
};

async function fetchCardSetsForCatalogo(
  supabase: SupabaseClient,
  filters: { gameCode?: string; expansionCode?: string },
): Promise<CatalogoCardSetRawRow[]> {
  let query = supabase
    .from("card_set")
    .select(
      "id, code, name, release_order, release_date, logo_storage_path, created_at, expansion!inner(id, name, release_order, game!inner(id, code, name))",
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
 * Expansões); quando `release_date` está nulo (ainda não confirmada),
 * cai para `created_at` como desempate. Com filtro ativo, segue a mesma
 * sequência (`release_order` de Expansão e depois de Card Set) já usada em
 * getExpansoes/fetchCardSets no resto do sistema.
 */
function sortCatalogoCardSets(rows: CatalogoCardSetRawRow[], filtered: boolean): CatalogoCardSetRawRow[] {
  const sorted = [...rows];
  if (filtered) {
    sorted.sort((a, b) => {
      const expansionDiff = (a.expansion?.release_order ?? 0) - (b.expansion?.release_order ?? 0);
      if (expansionDiff !== 0) return expansionDiff;
      return a.release_order - b.release_order;
    });
  } else {
    sorted.sort((a, b) => {
      if (a.release_date && b.release_date) {
        return b.release_date.localeCompare(a.release_date);
      }
      if (a.release_date) return -1;
      if (b.release_date) return 1;
      return b.created_at.localeCompare(a.created_at);
    });
  }
  return sorted;
}

async function getCardCountsForSets(supabase: SupabaseClient, cardSetIds: string[]): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  if (cardSetIds.length === 0) {
    return counts;
  }
  const { data, error } = await supabase.from("card").select("card_set_id").in("card_set_id", cardSetIds);
  if (error || !data) {
    return counts;
  }
  for (const row of data as { card_set_id: string }[]) {
    counts.set(row.card_set_id, (counts.get(row.card_set_id) ?? 0) + 1);
  }
  return counts;
}

function toCatalogoCardSetRow(row: CatalogoCardSetRawRow, counts: Map<string, number>): CatalogoCardSetRow {
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    releaseOrder: row.release_order,
    releaseDate: row.release_date,
    expansionId: row.expansion?.id ?? "",
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
        "id, code, name, release_order, release_date, logo_storage_path, created_at, expansion!inner(id, name, release_order, game!inner(id, code, name))",
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
};

type ExpansionRawRow = {
  id: string;
  code: string;
  name: string;
  release_order: number;
  created_at: string;
  updated_at: string;
  game: { id: string; code: string; name: string } | null;
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
    .select("id, code, name, release_order, created_at, updated_at, game!inner(id, code, name), card_set(count)")
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
  }));
}

// ---------------------------------------------------------------------------
// Catálogo — galeria de Expansões (/catalogo/expansoes, redesenho 2026-07-31,
// mesma linguagem visual/comportamento da galeria de Card Sets acima).
// Devolve `ExpansaoRow` (mesmo tipo já usado por getExpansoes/CreateExpansion
// Dialog/EditExpansionDialog) — sem tipo novo, evita qualquer divergência de
// forma entre a galeria e os Dialogs de criação/edição já existentes.
//
// Adaptação à entidade: Expansion não tem `logo_storage_path` (só card_set
// tem) e não tem `release_date` (só `release_order`, relativo ao próprio
// Jogo) — sem filtro de Jogo, o único campo comparável entre Jogos é
// `created_at`, mesmo fallback já usado em Card Set quando a data real
// está ausente.
// ---------------------------------------------------------------------------

export const EXPANSOES_PAGE_SIZE = 24;

async function fetchExpansoesRawForCatalogo(
  supabase: SupabaseClient,
  filters: { gameCode?: string },
): Promise<ExpansionRawRow[]> {
  let query = supabase
    .from("expansion")
    .select("id, code, name, release_order, created_at, updated_at, game!inner(id, code, name), card_set(count)");

  if (filters.gameCode) {
    query = query.eq("game.code", filters.gameCode);
  }

  const { data, error } = await query;
  if (error || !data) {
    return [];
  }
  return data as unknown as ExpansionRawRow[];
}

function sortExpansoesForCatalogo(rows: ExpansionRawRow[], filtered: boolean): ExpansionRawRow[] {
  const sorted = [...rows];
  if (filtered) {
    sorted.sort((a, b) => a.release_order - b.release_order);
  } else {
    sorted.sort((a, b) => b.created_at.localeCompare(a.created_at));
  }
  return sorted;
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
  };
}

/** Galeria principal da tela Expansões — sem termo de busca. */
export async function getExpansoesForCatalogo(
  supabase: SupabaseClient,
  options: { gameCode?: string; limit: number; offset: number },
): Promise<{ items: ExpansaoRow[]; hasMore: boolean }> {
  const filtered = Boolean(options.gameCode);
  const all = sortExpansoesForCatalogo(
    await fetchExpansoesRawForCatalogo(supabase, { gameCode: options.gameCode }),
    filtered,
  );
  const page = all.slice(options.offset, options.offset + options.limit);
  const hasMore = all.length > options.offset + options.limit;
  return { items: page.map(toExpansaoRow), hasMore };
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
    .select("id, code, name, release_order, created_at, updated_at, game!inner(id, code, name), card_set(count)")
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

export type GameOption = { id: string; code: string; name: string };

/** Opções para o seletor de Jogo do formulário de cadastro de Expansão. */
export async function getGameOptions(supabase: SupabaseClient): Promise<GameOption[]> {
  const { data, error } = await supabase.from("game").select("id, code, name").order("name", { ascending: true });

  if (error || !data) {
    return [];
  }

  return data as GameOption[];
}

export type CardSetOption = { code: string; name: string };

/** Opções para o seletor de Card Set da tela /catalogo/cartas — mesma ordem de exibição do resto do módulo. */
export async function getCardSetOptions(supabase: SupabaseClient): Promise<CardSetOption[]> {
  const cardSets = await fetchCardSets(supabase);
  return cardSets.map((set) => ({ code: set.code, name: set.name }));
}

export type CartaRow = {
  id: string;
  collectorNumber: string;
  collectorTotal: number | null;
  name: string;
  raridadeNome: string | null;
  categoriaNome: string | null;
};

type CardRawRow = {
  id: string;
  collector_number: string;
  collector_total: number | null;
  name: string;
  rarity: { name: string } | null;
  card_category: { name: string } | null;
};

/**
 * Cartas de um único Card Set, ordenadas por `collector_order` — decisão
 * deliberada de não paginar/listar as 927 cartas juntas: `collector_order` é
 * relativo a cada Card Set, então misturar Sets na mesma lista intercalaria
 * numerações sem sentido. Um seletor de Card Set (ver getCardSetOptions)
 * resolve isso e ainda reflete como o catálogo é navegado na prática.
 */
export async function getCartasPorCardSet(supabase: SupabaseClient, cardSetCode: string): Promise<CartaRow[]> {
  const { data: cardSet } = await supabase.from("card_set").select("id").eq("code", cardSetCode).maybeSingle();

  if (!cardSet) {
    return [];
  }

  const { data, error } = await supabase
    .from("card")
    .select("id, collector_number, collector_total, name, rarity(name), card_category(name)")
    .eq("card_set_id", cardSet.id)
    .order("collector_order", { ascending: true });

  if (error || !data) {
    return [];
  }

  return (data as unknown as CardRawRow[]).map((card) => ({
    id: card.id,
    collectorNumber: card.collector_number,
    collectorTotal: card.collector_total,
    name: card.name,
    raridadeNome: card.rarity?.name ?? null,
    categoriaNome: card.card_category?.name ?? null,
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
