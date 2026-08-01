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
  setType: string;
  releaseOrder: number;
  releaseDate: string | null;
  /** Quantidade de cartas do set base (sem secretas) — `card_set.base_set_size`. */
  baseSetSize: number;
  /** Quantidade total, incluindo secretas — `card_set.total_set_size`. A diferença `totalSetSize - baseSetSize` é a contagem de secretas (ver comentário de `120_create_card_set_table.sql`). */
  totalSetSize: number;
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
  set_type: string;
  release_order: number;
  release_date: string | null;
  base_set_size: number;
  total_set_size: number;
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
      "id, code, name, set_type, release_order, release_date, base_set_size, total_set_size, logo_storage_path, created_at, expansion!inner(id, name, release_order, game!inner(id, code, name))",
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
    setType: row.set_type,
    releaseOrder: row.release_order,
    releaseDate: row.release_date,
    baseSetSize: row.base_set_size,
    totalSetSize: row.total_set_size,
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
        "id, code, name, set_type, release_order, release_date, logo_storage_path, created_at, expansion!inner(id, name, release_order, game!inner(id, code, name))",
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
  const [variantResult, assetResult, frontAssetsResult] = await Promise.all([
    supabase.from("card_variant").select("id", { count: "exact", head: true }),
    supabase.from("card_asset").select("id", { count: "exact", head: true }),
    supabase
      .from("card_asset")
      .select("card_id, card_asset_type!inner(code)")
      .eq("is_primary", true)
      .eq("card_asset_type.code", "CARD_FRONT"),
  ]);

  const totalVariacoes = variantResult.count ?? 0;
  const totalImagens = assetResult.count ?? 0;
  const cardsComImagem = new Set(
    ((frontAssetsResult.data as { card_id: string }[] | null) ?? []).map((row) => row.card_id),
  ).size;
  const cardsSemImagem = Math.max(totalCartas - cardsComImagem, 0);

  return { totalVariacoes, totalImagens, cardsSemImagem };
}

export type CartaCompletaRow = {
  id: string;
  collectorNumber: string;
  collectorTotal: number | null;
  collectorOrder: number;
  name: string;
  rarityCode: string;
  rarityName: string;
  rarityDisplayOrder: number;
  raritySymbolCode: string;
  categoryCode: string;
  categoryName: string;
  categoryDisplayOrder: number;
  /** Imagem CARD_FRONT principal em português (pt-BR), quando importada. */
  imageUrlPt: string | null;
  /** Imagem CARD_FRONT principal em inglês (en), quando importada. */
  imageUrlEn: string | null;
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
  rarity: { code: string; name: string; symbol_code: string; display_order: number } | null;
  card_category: { code: string; name: string; display_order: number } | null;
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
 */
export async function getCartasCompletas(supabase: SupabaseClient, cardSetId: string): Promise<CartaCompletaRow[]> {
  const { data, error } = await supabase
    .from("card")
    .select(
      "id, collector_number, collector_total, collector_order, name, rarity(code, name, symbol_code, display_order), card_category(code, name, display_order), card_asset(storage_path, is_primary, card_asset_type(code), language(code))",
    )
    .eq("card_set_id", cardSetId)
    .eq("is_active", true)
    .order("collector_order", { ascending: true });

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
      rarityCode: card.rarity?.code ?? "",
      rarityName: card.rarity?.name ?? "—",
      rarityDisplayOrder: card.rarity?.display_order ?? 0,
      raritySymbolCode: card.rarity?.symbol_code ?? "",
      categoryCode: card.card_category?.code ?? "",
      categoryName: card.card_category?.name ?? "—",
      categoryDisplayOrder: card.card_category?.display_order ?? 0,
      imageUrlPt: pathPt ? (supabase.storage.from("card-front").getPublicUrl(pathPt).data.publicUrl ?? null) : null,
      imageUrlEn: pathEn ? (supabase.storage.from("card-front").getPublicUrl(pathEn).data.publicUrl ?? null) : null,
    };
  });
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
// /catalogo/importar-cartas/tcgdex, adicionada em 2026-08-01.
// ---------------------------------------------------------------------------

export type CardSetSemCartasRow = {
  id: string;
  code: string;
  name: string;
};

/**
 * Coleções sem nenhuma carta cadastrada — universo elegível para o fluxo de
 * importação via TCGdex. Reaproveita getCardSetsForCartas (mesma base de
 * cardsCatalogados já usada pela página Importar Cartas).
 */
export async function getCardSetsSemCartas(supabase: SupabaseClient): Promise<CardSetSemCartasRow[]> {
  const cardSets = await getCardSetsForCartas(supabase);
  return cardSets
    .filter((cardSet) => cardSet.cardsCatalogados === 0)
    .map((cardSet) => ({ id: cardSet.id, code: cardSet.code, name: cardSet.name }));
}

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
