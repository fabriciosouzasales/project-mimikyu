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
 * Pagina uma consulta em lotes de até SUPABASE_MAX_ROWS_PAGE_SIZE via
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
 *
 * Correção real (2026-08-11, bug reportado por Fabrício em
 * `/catalogo/importar-imagens`: várias Coleções já 100% importadas — ME5,
 * SV8, SV8.5, SV9, SV10, SV10.5B, SV10.5W, confirmadas completas em EN e
 * PT-BR direto no banco — apareciam com contagem parcial/errada mesmo logo
 * após um `router.refresh()`, sem relação com cache de aba). Causa: o laço
 * comparava `data.length` contra a CONSTANTE assumida
 * `SUPABASE_MAX_ROWS_PAGE_SIZE` (1000) para decidir se a página era a
 * última. Isso presume que o `db-max-rows` real do projeto Supabase é
 * exatamente 1000 — mas essa configuração vive no dashboard (Settings →
 * API), fora do controle deste código, e pode divergir sem qualquer aviso
 * em tempo de execução. Quando o cap real do servidor é MENOR que 1000
 * (ex.: 500), cada página já vem truncada pelo próprio PostgREST antes de
 * chegar aqui — `data.length` (500) é sempre menor que o `SUPABASE_MAX_ROWS_
 * PAGE_SIZE` assumido (1000), então o laço concluía "acabou" depois da
 * PRIMEIRA página, descartando silenciosamente todo o resto (mesma classe
 * de bug do incidente de 2026-08-01, causa raiz diferente: não faltava
 * paginação, a paginação existente parava cedo demais). Agora o laço avança
 * `from` pelo tanto que REALMENTE veio (`data.length`, não a constante) e só
 * para quando uma página vem vazia — correto para qualquer cap real do
 * servidor, conhecido ou não.
 */
async function fetchAllRows(
  buildQuery: (from: number, to: number) => PromiseLike<{ data: unknown[] | null; error: unknown }>,
): Promise<unknown[]> {
  const all: unknown[] = [];
  let from = 0;
  for (;;) {
    const { data, error } = await buildQuery(from, from + SUPABASE_MAX_ROWS_PAGE_SIZE - 1);
    if (error || !data || data.length === 0) break;
    all.push(...data);
    from += data.length;
  }
  return all;
}

type CardSetRow = {
  id: string;
  code: string;
  name: string;
  set_type: string;
  /** Cartas do set base, sem secretas — `card_set.base_set_size`. Adicionado 2026-08-08 para compor "Cards totais (base + secretas)" no hub de Card Set, mesma fórmula já usada em `formatCardSetTotals()` (`cartas-gallery.tsx`). */
  base_set_size: number;
  total_set_size: number;
  logo_storage_path: string | null;
  release_order: number;
  release_date: string | null;
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

export type CoberturaPorIdiomaItem = {
  languageCode: string;
  cardsComImagem: number;
};

export type EstadoDoCatalogo = {
  cardSetsCatalogados: number;
  cardSetsComImagensCompletas: number;
  cartasCatalogadas: number;
  execucoesComPendencia: number;
  /** Card Sets com cards_pendentes_cadastro > 0 (catalog_card_set_metrics, Query 2123). */
  cardSetsComPendencia: number;
  /** SUM(cards_pendentes_cadastro) — estimativa agregada, nunca a identificação de quais collector_number faltam (mesma ressalva da Query 2123). */
  cartasPendentes: number;
  /** SUM(cards_cadastradas - cards_com_imagem_algum_idioma) — Cards cadastradas sem imagem canônica em nenhum idioma ativo. */
  imagensPendentes: number;
  /** getImportacoesAguardandoRevisaoOuErro() — catalog_import_job em STAGED/CONFIRMING/COMPLETED_WITH_ERRORS/FAILED. */
  importacoesAguardandoRevisaoOuErro: number;
  /** Cobertura de imagem canônica agregada por idioma ativo (catalog_card_set_image_coverage, Query 2123), somada entre todos os Card Sets. */
  coberturaPorIdioma: CoberturaPorIdiomaItem[];
};

export type CardSetOverviewRow = {
  /** Adicionado 2026-08-08 para o hub de Card Set (`/catalogo/card-sets/{code}`) — necessário para montar links de ações contextuais que dependem do UUID (`?cardSetId=` em importar-cartas/importar-imagens), não do `code`. */
  id: string;
  code: string;
  name: string;
  setType: string;
  /** Cartas do set base, sem secretas — `card_set.base_set_size`. Adicionado 2026-08-08 junto com `id`, mesmo motivo. */
  baseSetSize: number;
  totalSetSize: number;
  cardsCatalogados: number;
  /** Cards cadastradas com imagem canônica em algum idioma ativo (catalog_card_set_metrics, Query 2123/2124) — o "atual" da cobertura de imagem, "esperado" é `cardsCatalogados` (só cards já cadastradas podem ter imagem). */
  cardsComImagem: number;
  /** GREATEST(total_set_size - cards_cadastradas, 0) — catalog_card_set_metrics, Query 2123. Antes desta rodada (2026-08-08) era lido de `fetchCardSetMetrics()` só para agregação global em `getEstadoDoCatalogo()`; agora também exposto por Card Set individual (hub). */
  cardsPendentes: number;
  temImagensCompletas: boolean;
  /** URL assinada (bucket privado `card-set-logo`, 1h) — `null` quando a Coleção não tem logo cadastrada. */
  logoUrl: string | null;
  expansionCode: string | null;
  expansionName: string | null;
  gameName: string | null;
  releaseDate: string | null;
  releaseOrder: number;
};

/**
 * Detalhe de um único Card Set (hub operacional, `/catalogo/card-sets/{code}`,
 * escopo V1 aprovado por Fabrício em 2026-08-08) — estende `CardSetOverviewRow`
 * com a única métrica que não faz sentido calcular para toda a listagem da
 * Visão Geral/Coleções (custaria uma query extra por Card Set ali): cobertura
 * de imagem canônica por idioma ativo, recortada para este Card Set
 * específico. Mesma fonte de `EstadoDoCatalogo.coberturaPorIdioma`
 * (`catalog_card_set_image_coverage`, Query 2123), só filtrada por
 * `card_set_id` em vez de somada entre todos os Card Sets.
 */
export type CardSetDetail = CardSetOverviewRow & {
  coberturaPorIdioma: CoberturaPorIdiomaItem[];
};

export type DistribuicaoPorRaridade = {
  code: string;
  name: string;
  totalCards: number;
};

export type AtividadeRecenteItem = {
  id: string;
  runCode: string;
  /** CARTAS (catalog_import_job, ADR-024) ou IMAGENS (asset_import_run) — mesmo domínio de `ImportacaoPipeline`, ver abaixo. */
  pipeline: ImportacaoPipeline;
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
    .select(
      "id, code, name, set_type, base_set_size, total_set_size, logo_storage_path, release_order, release_date, expansion(code, name, game(code, name))",
    );

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
  cards_pendentes_cadastro: number;
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
    .select("card_set_id, cards_cadastradas, cards_com_imagem_algum_idioma, cards_pendentes_cadastro");

  if (error || !data) {
    return [];
  }

  return data as unknown as CardSetMetricsRow[];
}

export type CardSetCardCountRow = {
  card_set_id: string;
  cards_cadastradas: number;
};

/**
 * Leitura enxuta de `catalog_card_set_metrics` — só `card_set_id` e
 * `cards_cadastradas` (2026-08-14, Incremento 4, Opção A da auditoria de
 * performance de `/catalogo/card-sets`; promovida a exportada no Incremento
 * 5, ver abaixo). `fetchCardSetMetrics()` (acima) permanece intocada —
 * `getEstadoDoCatalogo()` e `getCardSetsOverview()` (únicos outros
 * consumidores, confirmados via busca no arquivo) seguem precisando das
 * quatro colunas; reduzi-la globalmente quebraria esses dois.
 *
 * Efeito no plano de execução: sem as colunas de imagem, o planner do
 * Postgres elimina do plano o LEFT JOIN com `image_union_counts` (subquery
 * sobre `card_asset`, ~13.342 linhas) embutido na view — confirmado via
 * `EXPLAIN (ANALYZE, BUFFERS)` no Incremento 4. Isso evita a reavaliação de
 * `is_admin()` (RLS, `catalog_admin_select`) por linha varrida de
 * `card_asset` (achado de RLS registrado à parte em `docs/log.md`, sem
 * alteração de política nesta rodada).
 *
 * Incremento 5 (2026-08-14, Opção 1 — threading explícito via `page.tsx`):
 * antes desta mudança, `getCardSetsGroupedByExpansion()` chamava esta função
 * internamente E `getCardSetsStatsSummary()` (removida, ver nota abaixo)
 * fazia sua própria leitura equivalente de `catalog_card_set_metrics` — duas
 * leituras sem filtro na mesma requisição (modo galeria), cada uma pagando
 * de novo a agregação `card_counts` (GROUP BY sobre `card`, ~7.104 linhas,
 * sob RLS) por trás da view. `getCardSetCardCounts()` promovida a exportada
 * e virou a ÚNICA leitura desta view por requisição: `page.tsx` (composition
 * root) a chama uma vez e distribui o mesmo resultado para os Stats
 * (`summarizeCardSetCardCounts()`, abaixo) e para `getCardSetsGroupedByExpansion()`
 * (que passou a RECEBER os counts em vez de buscá-los). Deliberadamente sem
 * `cache()` do React — threading explícito, sem depender de igualdade
 * referencial de argumento entre chamadas.
 */
export async function getCardSetCardCounts(supabase: SupabaseClient): Promise<CardSetCardCountRow[]> {
  const { data, error } = await supabase.from("catalog_card_set_metrics").select("card_set_id, cards_cadastradas");

  if (error || !data) {
    return [];
  }

  return data as unknown as CardSetCardCountRow[];
}

/**
 * Cobertura de imagem canônica por idioma ativo, agregada entre todos os
 * Card Sets — soma direta de public.catalog_card_set_image_coverage (Query
 * 2123), sem reagregar nada que a view já não tenha calculado. Grão da
 * view já é (card_set, idioma ativo); aqui só somamos cards_com_imagem por
 * idioma, dispensando qualquer view/RPC nova (mesma decisão de "sem objeto
 * novo quando o dado já existe" já aplicada à contagem de
 * catalog_import_job por status).
 */
async function fetchCoberturaImagensPorIdioma(supabase: SupabaseClient): Promise<CoberturaPorIdiomaItem[]> {
  const { data, error } = await supabase.from("catalog_card_set_image_coverage").select("language_code, cards_com_imagem");

  if (error || !data) {
    return [];
  }

  const porIdioma = new Map<string, number>();
  for (const row of data as { language_code: string; cards_com_imagem: number }[]) {
    porIdioma.set(row.language_code, (porIdioma.get(row.language_code) ?? 0) + row.cards_com_imagem);
  }

  return Array.from(porIdioma.entries()).map(([languageCode, cardsComImagem]) => ({ languageCode, cardsComImagem }));
}

/**
 * Mesma view de `fetchCoberturaImagensPorIdioma()`, agora filtrada por um
 * único Card Set — a view já tem esse grão (card_set, idioma ativo), então o
 * filtro é só um `.eq()` a mais, sem view/RPC nova (2026-08-08, hub de Card
 * Set). Usada exclusivamente por `getCardSetByCode()`.
 *
 * Filtro por `card_set_code` (2026-08-14, otimização de `getCardSetByCode()`
 * — Incremento 4, terceiro alvo): antes recebia `cardSetId`, obtido só depois
 * de `getCardSetsOverview()` já ter resolvido o Card Set inteiro — dependência
 * sequencial desnecessária, já que a view expõe `card_set_code` diretamente
 * (mesma coluna já usada por `catalog_card_set_metrics`). Com o filtro por
 * `code`, esta leitura roda em paralelo com as outras duas que compõem
 * `getCardSetByCode()`, sem esperar nenhum `id` ser resolvido antes.
 */
async function fetchCoberturaImagensPorIdiomaDoCardSet(
  supabase: SupabaseClient,
  code: string,
): Promise<CoberturaPorIdiomaItem[]> {
  const { data, error } = await supabase
    .from("catalog_card_set_image_coverage")
    .select("language_code, cards_com_imagem")
    .eq("card_set_code", code);

  if (error || !data) {
    return [];
  }

  return (data as { language_code: string; cards_com_imagem: number }[]).map((row) => ({
    languageCode: row.language_code,
    cardsComImagem: row.cards_com_imagem,
  }));
}

export async function getEstadoDoCatalogo(supabase: SupabaseClient): Promise<EstadoDoCatalogo> {
  const [metrics, { count: execucoesComPendencia }, coberturaPorIdioma, importacoesAguardandoRevisaoOuErro] =
    await Promise.all([
      fetchCardSetMetrics(supabase),
      supabase.from("asset_import_run").select("id", { count: "exact", head: true }).neq("status", "COMPLETED"),
      fetchCoberturaImagensPorIdioma(supabase),
      getImportacoesAguardandoRevisaoOuErro(supabase),
    ]);

  const cardSetsComImagensCompletas = metrics.filter(
    (row) => row.cards_cadastradas > 0 && row.cards_cadastradas === row.cards_com_imagem_algum_idioma,
  ).length;

  const cartasCatalogadas = metrics.reduce((total, row) => total + row.cards_cadastradas, 0);
  const cardSetsComPendencia = metrics.filter((row) => row.cards_pendentes_cadastro > 0).length;
  const cartasPendentes = metrics.reduce((total, row) => total + row.cards_pendentes_cadastro, 0);
  const imagensPendentes = metrics.reduce(
    (total, row) => total + Math.max(row.cards_cadastradas - row.cards_com_imagem_algum_idioma, 0),
    0,
  );

  return {
    cardSetsCatalogados: metrics.length,
    cardSetsComImagensCompletas,
    cartasCatalogadas,
    execucoesComPendencia: execucoesComPendencia ?? 0,
    cardSetsComPendencia,
    cartasPendentes,
    imagensPendentes,
    importacoesAguardandoRevisaoOuErro,
    coberturaPorIdioma,
  };
}

/**
 * Ordena por data de lançamento decrescente, com o número de ordem
 * (`release_order`) também decrescente como desempate — mesma dupla chave já
 * usada por `sortCatalogoCardSets()` (caminho sem filtro de Jogo/Expansão),
 * agora replicada aqui a pedido de Fabrício (2026-08-08) para a tabela de
 * Coleções da Visão Geral. Coleções com `release_date` vêm sempre antes das
 * que não têm (mesmo critério já aplicado em `sortCatalogoCardSets()`).
 */
function sortCardSetsOverview(rows: CardSetOverviewRow[]): CardSetOverviewRow[] {
  return [...rows].sort((a, b) => {
    if (a.releaseDate && b.releaseDate && a.releaseDate !== b.releaseDate) {
      return b.releaseDate.localeCompare(a.releaseDate);
    }
    if (a.releaseDate && !b.releaseDate) return -1;
    if (!a.releaseDate && b.releaseDate) return 1;
    return b.releaseOrder - a.releaseOrder;
  });
}

export async function getCardSetsOverview(supabase: SupabaseClient): Promise<CardSetOverviewRow[]> {
  const [cardSets, metrics] = await Promise.all([fetchCardSets(supabase), fetchCardSetMetrics(supabase)]);

  const logoUrls = await getCardSetLogoUrls(
    supabase,
    cardSets.map((set) => set.logo_storage_path),
  );

  const metricsPorCardSetId = new Map(metrics.map((row) => [row.card_set_id, row]));

  const rows = cardSets.map((set) => {
    const metric = metricsPorCardSetId.get(set.id);
    const cardsCatalogados = metric?.cards_cadastradas ?? 0;
    const cardsComImagem = metric?.cards_com_imagem_algum_idioma ?? 0;
    return {
      id: set.id,
      code: set.code,
      name: set.name,
      setType: set.set_type,
      baseSetSize: set.base_set_size,
      totalSetSize: set.total_set_size,
      cardsCatalogados,
      cardsComImagem,
      cardsPendentes: metric?.cards_pendentes_cadastro ?? 0,
      temImagensCompletas: cardsCatalogados > 0 && cardsCatalogados === cardsComImagem,
      logoUrl: set.logo_storage_path ? (logoUrls.get(set.logo_storage_path) ?? null) : null,
      expansionCode: set.expansion?.code ?? null,
      expansionName: set.expansion?.name ?? null,
      gameName: set.expansion?.game?.name ?? null,
      releaseDate: set.release_date,
      releaseOrder: set.release_order,
    };
  });

  return sortCardSetsOverview(rows);
}

export type CardSetsStatsSummary = {
  totalCardSets: number;
  cardSetsSemCartas: number;
};

/**
 * Resumo mínimo para os indicadores de `/catalogo/card-sets` (`CardSetsStats`)
 * — função PURA, sem I/O (2026-08-14, Incremento 5, substitui
 * `getCardSetsStatsSummary()`, removida). Recebe os mesmos `CardSetCardCountRow[]`
 * já lidos por `getCardSetCardCounts()` para a galeria — `page.tsx`
 * (composition root) chama `getCardSetCardCounts()` uma única vez por
 * requisição e distribui o resultado para esta função E para
 * `getCardSetsGroupedByExpansion()`, eliminando a segunda leitura sem filtro
 * de `catalog_card_set_metrics` que existia antes (cada uma pagando de novo
 * a agregação `card_counts`/RLS por trás da view). `getCardSetsOverview()`
 * não foi alterada — continua servindo `/catalogo` (Visão Geral), que
 * precisa dos campos ricos (nome, logo, expansão) que este resumo
 * deliberadamente não busca.
 *
 * `totalCardSets` = total de linhas (a view cobre 1:1 todos os Card Sets);
 * `cardSetsSemCartas` = linhas com `cards_cadastradas === 0`. Mesma lógica
 * de antes, só a origem do dado mudou de "buscar do banco" para "receber já
 * buscado".
 */
export function summarizeCardSetCardCounts(rows: CardSetCardCountRow[]): CardSetsStatsSummary {
  return {
    totalCardSets: rows.length,
    cardSetsSemCartas: rows.filter((row) => row.cards_cadastradas === 0).length,
  };
}

/**
 * Distribuição de Cards por Raridade. Consumida pela Visão Geral
 * (`/catalogo`) até 2026-08-08 — removida de lá por pedido de Fabrício
 * ("análise de distribuição sem contexto operacional nessa página") e
 * reservada como candidata a relatório da futura Central de Relatórios
 * (Módulo Gerencial, `ROADMAP.md`, Trilha 4). Função e componente
 * `Distribuicoes` (`web/components/catalogo/distribuicoes.tsx`)
 * deliberadamente mantidos, sem nenhum consumidor no momento — não é código
 * morto por engano, é capacidade preservada para reuso.
 */
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
 * Detalhe de um Card Set (rota /catalogo/card-sets/{code}) — destino real da
 * navegação da tabela na Visão Geral (refinamento 6 aprovado por Fabrício,
 * 2026-08-08) e, na mesma data, base do hub operacional da Coleção (escopo V1
 * aprovado: cabeçalho enriquecido, galeria de Cartas, cobertura/pendências,
 * ações contextuais).
 *
 * Otimização (2026-08-14, Incremento 4, terceiro alvo): antes reaproveitava
 * `getCardSetsOverview()` inteiro (43 Card Sets, 43 linhas de métricas, URLs
 * assinadas para os 43 logos) só para descartar 42 resultados via `.find()`.
 * `catalog_card_set_metrics` e `catalog_card_set_image_coverage` já expõem
 * `card_set_code` diretamente — as três leituras (`card_set`, métricas,
 * cobertura) agora filtram por `code` desde o início e rodam em paralelo, sem
 * depender de um `id` resolvido antes. A URL assinada é gerada só para o
 * único `logo_storage_path` deste Card Set. Mapeamento de campos idêntico ao
 * que `getCardSetsOverview()` já fazia — nenhuma listagem (`getCardSetsOverview`,
 * `fetchCardSets`, `fetchCardSetMetrics`) foi alterada, elas continuam
 * servindo a Visão Geral/Coleções normalmente.
 */
export async function getCardSetByCode(supabase: SupabaseClient, code: string): Promise<CardSetDetail | null> {
  const [cardSetResult, metricsResult, coberturaPorIdioma] = await Promise.all([
    supabase
      .from("card_set")
      .select(
        "id, code, name, set_type, base_set_size, total_set_size, logo_storage_path, release_order, release_date, expansion(code, name, game(code, name))",
      )
      .eq("code", code)
      .maybeSingle(),
    supabase
      .from("catalog_card_set_metrics")
      .select("cards_cadastradas, cards_com_imagem_algum_idioma, cards_pendentes_cadastro")
      .eq("card_set_code", code)
      .maybeSingle(),
    fetchCoberturaImagensPorIdiomaDoCardSet(supabase, code),
  ]);

  const cardSetRow = cardSetResult.data as unknown as CardSetRow | null;
  if (cardSetResult.error || !cardSetRow) {
    return null;
  }

  const metrics = metricsResult.data as {
    cards_cadastradas: number;
    cards_com_imagem_algum_idioma: number;
    cards_pendentes_cadastro: number;
  } | null;
  const cardsCatalogados = metrics?.cards_cadastradas ?? 0;
  const cardsComImagem = metrics?.cards_com_imagem_algum_idioma ?? 0;

  const logoUrls = await getCardSetLogoUrls(supabase, [cardSetRow.logo_storage_path]);

  return {
    id: cardSetRow.id,
    code: cardSetRow.code,
    name: cardSetRow.name,
    setType: cardSetRow.set_type,
    baseSetSize: cardSetRow.base_set_size,
    totalSetSize: cardSetRow.total_set_size,
    cardsCatalogados,
    cardsComImagem,
    cardsPendentes: metrics?.cards_pendentes_cadastro ?? 0,
    temImagensCompletas: cardsCatalogados > 0 && cardsCatalogados === cardsComImagem,
    logoUrl: cardSetRow.logo_storage_path ? (logoUrls.get(cardSetRow.logo_storage_path) ?? null) : null,
    expansionCode: cardSetRow.expansion?.code ?? null,
    expansionName: cardSetRow.expansion?.name ?? null,
    gameName: cardSetRow.expansion?.game?.name ?? null,
    releaseDate: cardSetRow.release_date,
    releaseOrder: cardSetRow.release_order,
    coberturaPorIdioma,
  };
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

// Otimização (2026-08-14, Finding 6 da auditoria de segurança/performance do
// Catálogo Editorial): antes, carregava TODAS as linhas de `card` (só
// `card_set_id`) via fetchAllRows() para contar em memória — para a galeria
// inteira (sem filtro), isso é a base inteira de Cards só para produzir uma
// contagem por Coleção. `catalog_card_set_metrics.cards_cadastradas` (Query
// 2123) já é exatamente essa contagem pré-agregada — "COUNT(card) por Card
// Set, sem filtro de is_active", mesmo critério usado aqui antes (comentário
// da coluna, database/schema/2123_create_catalog_card_set_metrics_views.sql)
// — trocar para ler a view é comportamento idêntico, uma leitura por Coleção
// pedida em vez de uma leitura por Card.
async function getCardCountsForSets(supabase: SupabaseClient, cardSetIds: string[]): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  if (cardSetIds.length === 0) {
    return counts;
  }
  const { data, error } = await supabase
    .from("catalog_card_set_metrics")
    .select("card_set_id, cards_cadastradas")
    .in("card_set_id", cardSetIds);
  if (error || !data) {
    return counts;
  }
  for (const row of data as { card_set_id: string; cards_cadastradas: number }[]) {
    counts.set(row.card_set_id, row.cards_cadastradas);
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
  filters: { gameCode?: string; expansionCode?: string } | undefined,
  cardSetCounts: Promise<CardSetCardCountRow[]> | CardSetCardCountRow[],
): Promise<CardSetsExpansionGroup[]> {
  // Paralelização (2026-08-14, gargalo #3 da auditoria de performance de
  // /catalogo/card-sets — mesmo padrão já validado em getCardSetsForCartas(),
  // gargalo #3 de /catalogo/cartas): catalog_card_set_metrics não depende dos
  // ids retornados por fetchCardSetsForCatalogo() para estar correta — a
  // view já cobre, sem filtro, o universo inteiro de Card Sets (43 linhas em
  // produção), e a associação por linha é feita depois via Map (`counts.get
  // (row.id)`), não pela ordem/tamanho da resposta. Linhas do Map fora do
  // filtro de Jogo/Expansão ativo (quando houver) simplesmente nunca são
  // consultadas — sem efeito em nenhuma linha real.
  //
  // Incremento 5 (2026-08-14, Opção 1 — threading explícito via `page.tsx`):
  // esta função DEIXOU de buscar `catalog_card_set_metrics` por conta
  // própria (Incremento 4 chamava `fetchCardSetCardCounts(supabase)` aqui
  // dentro) — agora recebe `cardSetCounts` já iniciado pelo composition
  // root (`page.tsx`), que dispara `getCardSetCardCounts()` UMA única vez
  // por requisição e distribui o mesmo resultado para os Stats e para esta
  // função. Antes, `getCardSetsStatsSummary()` (removida) fazia uma segunda
  // leitura equivalente e sem filtro da mesma view na mesma requisição —
  // cada uma pagando de novo a agregação `card_counts` (GROUP BY sobre
  // `card`, ~7.104 linhas, sob RLS) por trás dela. `cardSetCounts` pode ser
  // a Promise ainda pendente (caso normal — mesma Promise que `page.tsx` já
  // colocou para rodar em paralelo com `fetchCardSetsForCatalogo` abaixo,
  // sem nenhuma serialização nova) ou um array já resolvido.
  const [rows, metrics] = await Promise.all([
    fetchCardSetsForCatalogo(supabase, {
      gameCode: filters?.gameCode,
      expansionCode: filters?.expansionCode,
    }),
    cardSetCounts,
  ]);
  const counts = new Map(metrics.map((row) => [row.card_set_id, row.cards_cadastradas]));

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
  // Paralelização (2026-08-14, auditoria focada de `/catalogo/cartas`,
  // gargalo #3): esta função sempre busca TODOS os Card Sets, sem filtro —
  // diferente de `getCardSetsForCatalogo()` (que pagina e por isso precisa
  // dos IDs da página antes de contar). Sem filtro, o `.in(cardSetIds)` de
  // `getCardCountsForSets()` com a lista completa de IDs sempre retorna as
  // mesmas linhas que uma leitura irrestrita de `catalog_card_set_metrics`
  // (mesmo grão — uma linha por Card Set) — então a segunda leitura pode ser
  // disparada junto com a primeira em vez de esperar os IDs. Duplicado aqui
  // em vez de generalizar `getCardCountsForSets()`, que continua servindo
  // `getCardSetsForCatalogo()` sem alteração.
  const [rawRows, metricsResult] = await Promise.all([
    fetchCardSetsForCatalogo(supabase, {}),
    supabase.from("catalog_card_set_metrics").select("card_set_id, cards_cadastradas"),
  ]);
  const rows = sortCatalogoCardSets(rawRows, false);
  const counts = new Map<string, number>();
  for (const row of (metricsResult.data ?? []) as { card_set_id: string; cards_cadastradas: number }[]) {
    counts.set(row.card_set_id, row.cards_cadastradas);
  }
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
 *   — ver `cartaImageUrl`/`pickCardFrontPath`).
 *
 * Otimização (2026-08-14, Incremento 4 da frente de performance, primeiro
 * alvo recomendado pela análise de over-fetch): a contagem de Cards com
 * imagem não lê mais `card_asset` linha a linha via `fetchAllRows()` (13.342
 * linhas em produção — praticamente a tabela inteira, ~14+ round-trips
 * paginados a cada visita à tela Cartas) para reconstruir `new Set(card_id)`
 * em memória. `catalog_card_set_metrics.cards_com_imagem_algum_idioma`
 * (view já existente, Query 2123/2124) já é `COUNT(DISTINCT card.id)` com o
 * MESMO critério (`is_primary = true`, `card_asset_type.code = 'CARD_FRONT'`,
 * união de todos os idiomas ativos), só que pré-agregado por Card Set —
 * somar essa coluna nas 43 linhas da view (1 round-trip) produz o mesmo
 * total. Equivalência confirmada diretamente em produção antes de aplicar
 * (SUM da view = 7.104 = COUNT(DISTINCT card_id) da query antiga, ambos
 * batendo com `card_total`); também confirmado que os dois idiomas
 * atualmente cadastrados (`en`, `pt-BR`) estão `is_active = true` e que
 * nenhuma linha de `card_asset` referencia um idioma inativo — a única
 * diferença teórica entre a view (que exige `language.is_active = true`) e
 * a query antiga (sem filtro de idioma) não se manifesta nos dados reais.
 */
export async function getCartasCatalogoStats(
  supabase: SupabaseClient,
  totalCartas: number,
): Promise<CartasCatalogoStats> {
  const [variantResult, assetResult, metricsResult] = await Promise.all([
    supabase.from("card_variant").select("id", { count: "exact", head: true }),
    supabase.from("card_asset").select("id", { count: "exact", head: true }),
    supabase.from("catalog_card_set_metrics").select("cards_com_imagem_algum_idioma"),
  ]);

  const totalVariacoes = variantResult.count ?? 0;
  const totalImagens = assetResult.count ?? 0;
  const cardsComImagem = ((metricsResult.data ?? []) as { cards_com_imagem_algum_idioma: number }[]).reduce(
    (sum, row) => sum + row.cards_com_imagem_algum_idioma,
    0,
  );
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
// Otimização (2026-08-14, próximo alvo da análise de over-fetch — Incremento
// 4): antes, carregava TODO `card_asset` do(s) Card Set(s) pedido(s) via
// fetchAllRows() (7.055 linhas/8 round-trips em produção, idioma `en`; 6.287
// linhas/7 round-trips em `pt-BR`) só para reconstruir
// `new Set(card_id).size` por Card Set em memória. `catalog_card_set_image_
// coverage` (Query 2123) já é exatamente essa contagem pré-agregada — mesmo
// critério (`is_primary = true` + `CARD_FRONT`), grão `(card_set_id,
// language_code)`, zero explícito via LEFT JOIN+COALESCE quando não há
// imagem (nunca uma chave ausente). Equivalência confirmada em produção
// antes de aplicar: 0 divergências entre a contagem manual e
// `cards_com_imagem` da view para os 43 Card Sets, idioma `en`; os dois
// idiomas realmente usados pelos consumidores (`en`, `pt-BR`) estão
// `is_active = true` (view só cobre idiomas ativos via CROSS JOIN — mesma
// ressalva teórica, sem efeito prático, já registrada no alvo 1).
async function getImagesImportadasPorCardSet(
  supabase: SupabaseClient,
  cardSetIds: string[],
  languageCode: string,
): Promise<Map<string, number>> {
  const counts = new Map<string, number>();
  if (cardSetIds.length === 0) return counts;

  const { data, error } = await supabase
    .from("catalog_card_set_image_coverage")
    .select("card_set_id, cards_com_imagem")
    .eq("language_code", languageCode)
    .in("card_set_id", cardSetIds);

  if (error || !data) return counts;

  for (const row of data as { card_set_id: string; cards_com_imagem: number }[]) {
    counts.set(row.card_set_id, row.cards_com_imagem);
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
  /**
   * Nomes das Card Variants já cadastradas para esta Card (CV-02,
   * 2026-08-15, pedido de Fabrício: tag de contagem + tooltip com nomes na
   * galeria de `/catalogo/cartas`, somente leitura — nenhum CRUD de Card
   * Variant nesta tela). Vazio = nenhuma variante cadastrada = sem tag.
   *
   * Ordenado por `card_variant_type.display_order` (ordem canônica do tipo
   * dentro do Game — "Padrão, Holográfica, Holográfica Reversa..."), NÃO por
   * `card_variant.variant_order`. Ajuste explícito de Fabrício na aprovação
   * desta rodada: `variant_order` é só ordem técnica de persistência (a
   * ordem em que cada variante foi confirmada pelo pipeline de Importar
   * Variantes, ver `internal.write_card_variant()`/Query 2143), não deve
   * virar semântica visual/canônica — `display_order` é o campo desenhado
   * para isso (`150_create_card_variant_type_table.sql`, `UNIQUE (game_id,
   * display_order)`).
   */
  variantNames: string[];
};

type CartaCompletaAssetRawRow = {
  storage_path: string | null;
  is_primary: boolean;
  card_asset_type: { code: string } | null;
  language: { code: string } | null;
};

/** Card Variant embutida na consulta de `getCartasCompletas` (CV-02) — só os dois campos usados pela tag/tooltip da galeria (nome + ordem canônica de exibição). Nenhum outro campo de `card_variant`/`card_variant_type` é necessário aqui (tela somente leitura). */
type CartaCompletaVariantRawRow = {
  card_variant_type: { name: string; display_order: number } | null;
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
  card_variant: CartaCompletaVariantRawRow[] | null;
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
      // `card_variant(card_variant_type(name, display_order))` — CV-02
      // (2026-08-15): mesma técnica de embedding já usada por `card_asset`
      // acima, zero round-trips novos. `card_variant` já tem GRANT SELECT
      // para `authenticated` (confirmado: `getCartasCatalogoStats()` já lê
      // esta tabela em produção) e RLS admin-only (`catalog_admin_select`,
      // ADR-028) — nenhuma migration necessária.
      "id, collector_number, collector_total, collector_order, name, is_active, rarity(id, code, name, symbol_code, display_order), card_category(id, code, name, display_order), card_asset(storage_path, is_primary, card_asset_type(code), language(code)), card_variant(card_variant_type(name, display_order))",
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
    // Ordenado por `card_variant_type.display_order` (ordem canônica do
    // tipo dentro do Game), não por `variant_order` da linha `card_variant`
    // — ver comentário de `variantNames` em `CartaCompletaRow`.
    const variantNames = (card.card_variant ?? [])
      .filter((variant): variant is { card_variant_type: { name: string; display_order: number } } => variant.card_variant_type !== null)
      .sort((a, b) => a.card_variant_type.display_order - b.card_variant_type.display_order)
      .map((variant) => variant.card_variant_type.name);
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
      variantNames,
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

/**
 * `pipeline` (2026-08-08, Sprint Gerencial 1) distingue as duas frentes de
 * escrita administrativa unificadas nesta tela: `IMAGENS` (asset_import_run,
 * como sempre foi) e `CARTAS` (catalog_import_job, ADR-024 — antes ausente
 * daqui, só aparecia no log limitado de Atividade Recente da Visão Geral).
 * Pré-requisito explícito de Fabrício antes do drill-down do StatCard
 * "Pendências" (Visão Geral): sem uma tela que liste os catalog_import_job
 * aguardando revisão/erro, aquele card não teria destino real.
 */
export type ImportacaoPipeline = "CARTAS" | "IMAGENS";

export type ImportacaoRow = {
  id: string;
  pipeline: ImportacaoPipeline;
  runCode: string;
  /** null para pipeline CARTAS — catalog_import_job não tem conceito de estratégia (run_type), só canal (source). */
  runType: string | null;
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

/**
 * Histórico completo de execuções de importação — une asset_import_run
 * (IMAGENS) e catalog_import_job (CARTAS, ADR-024), sem `limit` (versão
 * completa; a Visão Geral usa getAtividadeRecente, com `limit`, para o log
 * resumido). catalog_import_job não tem `run_code`/`run_type`/
 * `asset_source`/`language_id` — mesma síntese e aproximação de contadores
 * já usadas em getAtividadeRecente (sintetizarRunCodeCatalogImportJob(),
 * calcularContadoresCatalogImportJob(), acima), reaproveitadas aqui em vez
 * de duplicadas. `assetSourceName` recebe o nome de exibição de `source`
 * ('TCGDEX' → 'TCGdex') — mesmo papel semântico de asset_source.name para
 * asset_import_run (de onde veio o dado).
 *
 * Sem `.range()` nas duas consultas, o PostgREST trunca silenciosamente em
 * `SUPABASE_MAX_ROWS_PAGE_SIZE` linhas (ver `fetchAllRows` acima) — ao
 * contrário de `getAtividadeRecente` (que usa `limit` de propósito), esta é
 * a versão "histórico completo" da tela, então precisa de `fetchAllRows`
 * nas duas fontes para não cortar o passado silenciosamente conforme o
 * volume crescer (mesmo bug de classe já visto em `card`/`card_asset`,
 * 2026-08-01).
 */
export async function getImportacoes(supabase: SupabaseClient): Promise<ImportacaoRow[]> {
  const [assetImportRunRows, catalogImportJobRows] = await Promise.all([
    fetchAllRows((from, to) =>
      supabase
        .from("asset_import_run")
        .select(
          "id, run_code, run_type, status, execution_context, requested_count, success_count, failed_count, created_at, asset_source(name), card_set(code, name), language(code)",
        )
        .order("created_at", { ascending: false })
        .range(from, to),
    ),
    fetchAllRows((from, to) =>
      supabase
        .from("catalog_import_job")
        .select(
          "id, status, source, total_rows, inserted_rows, updated_rows, unchanged_rows, failed_rows, rejected_rows, created_at, card_set(code, name)",
        )
        .order("created_at", { ascending: false })
        .range(from, to),
    ),
  ]);

  const assetImportRunItems: ImportacaoRow[] = (assetImportRunRows as unknown as AssetImportRunFullRawRow[]).map(
    (run) => ({
      id: run.id,
      pipeline: "IMAGENS" as const,
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
    }),
  );

  const catalogImportJobItems: ImportacaoRow[] = (catalogImportJobRows as unknown as CatalogImportJobActivityRow[]).map((job) => ({
    id: job.id,
    pipeline: "CARTAS",
    runCode: sintetizarRunCodeCatalogImportJob(job.id),
    runType: null,
    status: job.status,
    executionContext: mapCatalogImportJobSourceParaExecutionContext(job.source),
    assetSourceName: nomeFonteCatalogImportJob(job.source),
    cardSetCode: job.card_set?.code ?? null,
    cardSetName: job.card_set?.name ?? null,
    languageCode: null,
    ...calcularContadoresCatalogImportJob(job),
    createdAt: job.created_at,
  }));

  return [...assetImportRunItems, ...catalogImportJobItems].sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
  );
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

// ---------------------------------------------------------------------------
// Importar Variantes (Incremento 4, ADR-028) — /catalogo/importar-variantes,
// adicionada em 2026-08-15. Mesmo contrato de leitura de Importar Cartas
// (getCardSetsForCartas/getCatalogImportJobStatus/getCatalogImportRows
// acima), uma instância nova dele para o staging de Card Variant
// (catalog_variant_import_job/catalog_variant_import_row, Queries
// 2136-2139) — não uma exceção ao padrão.
// ---------------------------------------------------------------------------

export type CatalogoVariantCardSetRow = CatalogoCardSetRow & {
  /** `catalog_card_set_variant_coverage.cards_com_variante` — Cards do Card Set com pelo menos uma Card Variant cadastrada. */
  cardsComVariante: number;
  /** `catalog_card_set_variant_coverage.cards_sem_variante` — Cards do Card Set ainda sem nenhuma Card Variant. */
  cardsSemVariante: number;
};

/**
 * Card Sets elegíveis para Importar Variantes: reaproveita getCardSetsForCartas
 * (mesma base de Coleção/Expansão/Jogo/cardsCatalogados já usada por Importar
 * Cartas) e cruza com catalog_card_set_variant_coverage (view da Query 2135)
 * para cardsComVariante/cardsSemVariante — as duas buscas são independentes,
 * disparadas juntas via Promise.all (mesmo raciocínio de getCardSetsForCartas
 * para catalog_card_set_metrics, ver comentário lá).
 *
 * Filtro: só Coleções com pelo menos uma carta cadastrada (Importar Variantes
 * pressupõe Importar Cartas já concluído — a própria Edge Function
 * import-card-variants recusa sem card_set_external_reference) E com
 * cardsSemVariante > 0 (nada pendente, nada para importar).
 */
export async function getCardSetsForVariantes(supabase: SupabaseClient): Promise<CatalogoVariantCardSetRow[]> {
  const [cardSets, coverageResult] = await Promise.all([
    getCardSetsForCartas(supabase),
    supabase.from("catalog_card_set_variant_coverage").select("card_set_id, cards_com_variante, cards_sem_variante"),
  ]);

  const coverage = new Map<string, { comVariante: number; semVariante: number }>();
  for (const row of (coverageResult.data ?? []) as {
    card_set_id: string;
    cards_com_variante: number;
    cards_sem_variante: number;
  }[]) {
    coverage.set(row.card_set_id, { comVariante: row.cards_com_variante, semVariante: row.cards_sem_variante });
  }

  return cardSets
    .map((cardSet) => {
      const cov = coverage.get(cardSet.id);
      return {
        ...cardSet,
        cardsComVariante: cov?.comVariante ?? 0,
        cardsSemVariante: cov?.semVariante ?? cardSet.cardsCatalogados,
      };
    })
    .filter((cardSet) => cardSet.cardsCatalogados > 0 && cardSet.cardsSemVariante > 0);
}

export type CatalogVariantImportJobStatus = {
  id: string;
  status: string;
  progressStep: string | null;
  totalRows: number;
  validRows: number;
  rejectedRows: number;
  insertedRows: number;
  unchangedRows: number;
  skippedRows: number;
  failedRows: number;
  errorSummary: string | null;
  cardSetCode: string;
  cardSetName: string;
};

type CatalogVariantImportJobRawRow = {
  id: string;
  status: string;
  progress_step: string | null;
  total_rows: number;
  valid_rows: number;
  rejected_rows: number;
  inserted_rows: number;
  unchanged_rows: number;
  skipped_rows: number;
  failed_rows: number;
  error_summary: string | null;
  card_set: { code: string; name: string } | null;
};

/** Status real de um catalog_variant_import_job (Query 2136) — base do acompanhamento do fluxo Importar Variantes. Sem updatedRows (diferença real frente a CatalogImportJobStatus — ver comentário da Query 2136: uma Card Variant não tem conteúdo para divergir/atualizar). */
export async function getCatalogVariantImportJobStatus(
  supabase: SupabaseClient,
  jobId: string,
): Promise<CatalogVariantImportJobStatus | null> {
  const { data, error } = await supabase
    .from("catalog_variant_import_job")
    .select(
      "id, status, progress_step, total_rows, valid_rows, rejected_rows, inserted_rows, unchanged_rows, skipped_rows, failed_rows, error_summary, card_set(code, name)",
    )
    .eq("id", jobId)
    .maybeSingle();

  if (error || !data) return null;

  const row = data as unknown as CatalogVariantImportJobRawRow;

  return {
    id: row.id,
    status: row.status,
    progressStep: row.progress_step,
    totalRows: row.total_rows,
    validRows: row.valid_rows,
    rejectedRows: row.rejected_rows,
    insertedRows: row.inserted_rows,
    unchangedRows: row.unchanged_rows,
    skippedRows: row.skipped_rows,
    failedRows: row.failed_rows,
    errorSummary: row.error_summary,
    cardSetCode: row.card_set?.code ?? "",
    cardSetName: row.card_set?.name ?? "",
  };
}

export type CatalogVariantImportRowView = {
  id: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  /** raw_data — type/foil/subtype/stamp exatamente como vieram do dataset-fonte, sem interpretação (ver Query 2138). */
  rawType: string | null;
  rawFoil: string | null;
  rawSubtype: string | null;
  rawStamp: string[] | null;
  /** Nome do card_variant_type já resolvido (normalized_data.variant_type_id) — null quando NEEDS_REVIEW (sem mapeamento). */
  variantTypeName: string | null;
  validationStatus: string;
  matchStatus: string;
  decisionStatus: string;
  persistenceStatus: string;
  errorDetail: string | null;
};

type CatalogVariantImportRowRawRow = {
  id: string;
  raw_data: { type?: string; foil?: string | null; subtype?: string | null; stamp?: string[] | null } | null;
  normalized_data: { variant_type_id?: string } | null;
  validation_status: string;
  match_status: string;
  decision_status: string;
  persistence_status: string;
  error_detail: string | null;
  card: { name: string; collector_number: string; collector_total: number | null } | null;
};

/**
 * Linhas de staging (catalog_variant_import_row, Query 2138) de um job —
 * base da tela de Revisão de Importar Variantes. Mesmo padrão de
 * getCatalogImportRows (Carta via join direto — aqui card_id é sempre
 * NOT NULL, nunca precisa de fallback), com uma segunda leitura em lote
 * (card_variant_type) para resolver o nome do tipo de variante proposto a
 * partir de normalized_data.variant_type_id — não dá para embutir isso num
 * único select do PostgREST porque o id fica dentro de um JSONB, não numa
 * coluna FK própria.
 *
 * Ordenado por collector_number (mesmo critério de exibição de
 * getCatalogImportRows) e, dentro da mesma Carta, pelo nome do tipo de
 * variante — mais de uma variante proposta por Carta é o caso comum aqui
 * (diferente de Importar Cartas, uma linha por Carta).
 */
export async function getCatalogVariantImportRows(
  supabase: SupabaseClient,
  jobId: string,
): Promise<CatalogVariantImportRowView[]> {
  const { data, error } = await supabase
    .from("catalog_variant_import_row")
    .select(
      "id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status, error_detail, card:card_id(name, collector_number, collector_total)",
    )
    .eq("job_id", jobId)
    .order("created_at", { ascending: true });

  if (error || !data) {
    return [];
  }

  const rawRows = data as unknown as CatalogVariantImportRowRawRow[];

  const variantTypeIds = Array.from(
    new Set(rawRows.map((row) => row.normalized_data?.variant_type_id).filter((id): id is string => Boolean(id))),
  );
  const variantTypeNames = new Map<string, string>();
  if (variantTypeIds.length > 0) {
    const { data: variantTypes } = await supabase.from("card_variant_type").select("id, name").in("id", variantTypeIds);
    for (const type of (variantTypes ?? []) as { id: string; name: string }[]) {
      variantTypeNames.set(type.id, type.name);
    }
  }

  const rows = rawRows.map((row) => {
    const variantTypeId = row.normalized_data?.variant_type_id ?? null;
    return {
      id: row.id,
      cardName: row.card?.name ?? "—",
      collectorNumber: row.card?.collector_number ?? "—",
      collectorTotal: row.card?.collector_total ?? null,
      rawType: row.raw_data?.type ?? null,
      rawFoil: row.raw_data?.foil ?? null,
      rawSubtype: row.raw_data?.subtype ?? null,
      rawStamp: row.raw_data?.stamp ?? null,
      variantTypeName: variantTypeId ? (variantTypeNames.get(variantTypeId) ?? null) : null,
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
    const byNumber = (Number.isNaN(numA) ? Infinity : numA) - (Number.isNaN(numB) ? Infinity : numB);
    if (byNumber !== 0) return byNumber;
    return (a.variantTypeName ?? "").localeCompare(b.variantTypeName ?? "", "pt-BR");
  });
}

type CatalogImportJobActivityRow = {
  id: string;
  status: string;
  source: string;
  total_rows: number;
  inserted_rows: number;
  updated_rows: number;
  unchanged_rows: number;
  failed_rows: number;
  rejected_rows: number;
  created_at: string;
  card_set: { code: string; name: string } | null;
};

/**
 * Traduz `catalog_import_job.source` ('TCGDEX'/'PDF') para o vocabulário de
 * `execution_context` já usado por asset_import_run ('MANUAL'/'API'/
 * 'SCHEDULED'/'SYSTEM'), em vez de introduzir um vocabulário novo — mesmo
 * campo `executionContext` de `AtividadeRecenteItem`/`ImportacaoRow`,
 * carregado para consumidores futuros mesmo que a Visão Geral (2026-08-08)
 * tenha parado de exibi-lo diretamente (ver coluna "Operação",
 * `atividade-recente.tsx` — passou a distinguir pipeline/idioma, não mais
 * `execution_context`). 'PDF' fica sem tradução (canal encerrado, ADR-024
 * Ciclos 3/4) — aparece com o texto bruto onde ainda for exibido.
 */
function mapCatalogImportJobSourceParaExecutionContext(source: string): string {
  return source === "TCGDEX" ? "API" : source;
}

/** Nome de exibição de `catalog_import_job.source` para a coluna "Fonte" (/catalogo/importacoes) — mesmo papel de `asset_source.name` para asset_import_run. */
function nomeFonteCatalogImportJob(source: string): string {
  return source === "TCGDEX" ? "TCGdex" : source;
}

/**
 * `runCode` sintetizado para catalog_import_job, que não tem coluna
 * equivalente (nunca persistido) — prefixo `CARDS-` distingue visualmente
 * de `RUN-...` (asset_import_run, Query 220) em qualquer log unificado.
 */
function sintetizarRunCodeCatalogImportJob(id: string): string {
  return `CARDS-${id.slice(0, 8).toUpperCase()}`;
}

/**
 * Aproxima os contadores de 3 buckets (requested/success/failed) já usados
 * por asset_import_run a partir dos contadores mais granulares de
 * catalog_import_job. `skipped_rows` fica fora dos dois buckets — soma
 * sucesso+falha pode ficar abaixo do total quando houver linhas puladas;
 * suficiente para logs, não uma reconciliação exata (essa granularidade
 * completa já existe na tela de Revisão do próprio job). Compartilhado por
 * `getAtividadeRecente` e `getImportacoes` para não duplicar a fórmula.
 */
function calcularContadoresCatalogImportJob(job: {
  total_rows: number;
  inserted_rows: number;
  updated_rows: number;
  unchanged_rows: number;
  failed_rows: number;
  rejected_rows: number;
}): { requestedCount: number; successCount: number; failedCount: number } {
  return {
    requestedCount: job.total_rows,
    successCount: job.inserted_rows + job.updated_rows + job.unchanged_rows,
    failedCount: job.failed_rows + job.rejected_rows,
  };
}

/**
 * Une os dois pipelines de escrita administrativa do Catálogo Editorial no
 * mesmo log de Atividade Recente (Sprint Gerencial 1): asset_import_run
 * (importação de IMAGENS) e catalog_import_job (importação de CARDS,
 * ADR-024) — hoje só o primeiro aparecia, apesar dos dois gerarem eventos
 * reais de escrita. Cada fonte busca até `limit` linhas mais recentes
 * (suficiente para reconstruir o top-`limit` real da união — qualquer linha
 * fora do top-`limit` de uma fonte é necessariamente mais antiga que o
 * corte global, já que a outra fonte sozinha já fornece `limit` candidatos
 * mais recentes), depois mescladas, ordenadas por `created_at` e cortadas
 * no mesmo `limit` de sempre — nunca dobra o tamanho da lista final.
 *
 * catalog_import_job não tem `run_code` nem `language_id` (Card Set não
 * carrega idioma, ver Query 2060) — `runCode` é sintetizado a partir do
 * `id` (prefixo `CARDS-`, nunca persistido), `languageCode` fica sempre
 * `null` para esses itens. `requestedCount`/`successCount`/`failedCount`
 * são uma aproximação dos contadores mais granulares de catalog_import_job
 * (`total_rows`/`inserted_rows`+`updated_rows`+`unchanged_rows`/
 * `failed_rows`+`rejected_rows`) — `skipped_rows` não entra em nenhum dos
 * dois buckets, então a soma sucesso+falha pode ficar abaixo do total
 * quando houver linhas puladas; suficiente para o log, não uma
 * reconciliação exata (essa granularidade completa já existe na tela de
 * Revisão do próprio job).
 *
 * `pipeline` (2026-08-08, ajuste de coluna "Operação" pedido por Fabrício)
 * — mesmo campo/domínio de `ImportacaoPipeline` já usado por `getImportacoes()`,
 * marcando explicitamente cada item como `"IMAGENS"` (asset_import_run) ou
 * `"CARTAS"` (catalog_import_job). Antes, a única distinção visível na
 * Visão Geral era `executionContext` (Manual/API Externa/Agendado/Sistema),
 * que não diz qual pipeline gerou o evento — dois eventos de pipelines
 * diferentes por `execution_context = 'API'` ficavam indistinguíveis.
 *
 * Este log é deliberadamente cronológico e sem deduplicação: ao contrário
 * de `getCatalogImportJobIdsExigindoAtencao()` (StatCard "Pendências"), que
 * só considera o job mais recente por Coleção, a Atividade Recente mantém
 * toda execução — inclusive tentativas antigas já superadas por uma
 * posterior bem-sucedida (falhas históricas) — por ser um log de auditoria,
 * não um indicador de pendência atual.
 */
export async function getAtividadeRecente(supabase: SupabaseClient, limit = 8): Promise<AtividadeRecenteItem[]> {
  const [assetImportRunResult, catalogImportJobResult] = await Promise.all([
    supabase
      .from("asset_import_run")
      .select(
        "id, run_code, status, execution_context, requested_count, success_count, failed_count, created_at, card_set(code, name), language(code)",
      )
      .order("created_at", { ascending: false })
      .limit(limit),
    supabase
      .from("catalog_import_job")
      .select(
        "id, status, source, total_rows, inserted_rows, updated_rows, unchanged_rows, failed_rows, rejected_rows, created_at, card_set(code, name)",
      )
      .order("created_at", { ascending: false })
      .limit(limit),
  ]);

  const assetImportRunItems: AtividadeRecenteItem[] = (
    (assetImportRunResult.data ?? []) as unknown as AssetImportRunRow[]
  ).map((run) => ({
    id: run.id,
    runCode: run.run_code,
    pipeline: "IMAGENS" as const,
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

  const catalogImportJobItems: AtividadeRecenteItem[] = (
    (catalogImportJobResult.data ?? []) as unknown as CatalogImportJobActivityRow[]
  ).map((job) => ({
    id: job.id,
    runCode: sintetizarRunCodeCatalogImportJob(job.id),
    pipeline: "CARTAS" as const,
    cardSetCode: job.card_set?.code ?? null,
    cardSetName: job.card_set?.name ?? null,
    languageCode: null,
    status: job.status,
    executionContext: mapCatalogImportJobSourceParaExecutionContext(job.source),
    ...calcularContadoresCatalogImportJob(job),
    createdAt: job.created_at,
  }));

  return [...assetImportRunItems, ...catalogImportJobItems]
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
    .slice(0, limit);
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

/**
 * Otimização (2026-08-14, auditoria focada de `/catalogo/cartas`, gargalo
 * #1): as três leituras abaixo (`rarity`, `rarity_external_mapping`,
 * `asset_source`) não têm nenhuma dependência de dado entre si — só são
 * combinadas depois, em memória (`sourceCodeById`/`mappingsByRarityId`).
 * Antes rodavam em 3 round-trips sequenciais; agora disparam juntas via
 * `Promise.all`, mesmas queries/filtros/campos, mesmo processamento
 * posterior. `rarityError`/`!rarityRows` continuam decidindo o retorno
 * antecipado `[]` exatamente como antes — só a ORDEM das chamadas mudou.
 */
export async function getRaridades(supabase: SupabaseClient): Promise<RaridadeRow[]> {
  const [
    { data: rarityRows, error: rarityError },
    { data: mappingRows },
    { data: sourceRows },
  ] = await Promise.all([
    supabase
      .from("rarity")
      .select("id, code, name, symbol_code, display_order, created_at, updated_at")
      .order("display_order", { ascending: true }),
    supabase
      .from("rarity_external_mapping")
      .select("id, rarity_id, asset_source_id, external_value, normalized_external_value"),
    supabase.from("asset_source").select("id, code"),
  ]);

  if (rarityError || !rarityRows) {
    return [];
  }

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

/**
 * Estados de catalog_import_job que, por si só (independente de contagem de
 * linhas), já representam pendência de atenção administrativa: STAGED/
 * CONFIRMING aguardam decisão explícita
 * (admin_decide_catalog_import_row()/admin_confirm_catalog_import());
 * FAILED e COMPLETED_WITH_ERRORS indicam falha total ou parcial.
 * RECEIVED/PROCESSING são trânsito normal do pipeline, não pendência;
 * CANCELLED é estado final já resolvido (nunca produzido hoje por nenhuma
 * função — ver ck_catalog_import_job_status — mas listado fora por
 * completude do domínio). Mesmo raciocínio de status já usado em
 * RAIDADE_JOB_STATUSES_REVALIDAVEIS logo abaixo, com FAILED incluído a
 * mais (revalidação de Raridade não cobre jobs que falharam por completo).
 *
 * Corrigido em 2026-08-08 (mesma Sprint, revisão de semântica pedida por
 * Fabrício): estes quatro status sozinhos NÃO bastam — um job antigo pode
 * estar em qualquer um deles só porque foi superado por uma tentativa
 * posterior já resolvida para a mesma Coleção (achado real: os 9 jobs que
 * a métrica antiga contava em produção eram todos, sem exceção, tentativas
 * anteriores a um job `COMPLETED` mais recente da mesma Coleção — auditados
 * linha a linha via Query 2822 antes desta implementação). Ver
 * `catalogImportJobExigeAtencao()` abaixo para a regra completa, que
 * combina esta lista com "é o job mais recente da Coleção" e com o caso
 * `COMPLETED` incompleto (ex.: SV2 em 2026-08-01, job `COMPLETED` com
 * `total_rows > inserted+updated+unchanged`, documentado em
 * `getLatestImportJobIncompleteFlags()`).
 */
export const JOB_STATUSES_AGUARDANDO_REVISAO_OU_ERRO = [
  "STAGED",
  "CONFIRMING",
  "COMPLETED_WITH_ERRORS",
  "FAILED",
] as const;

/**
 * Regra única de "exige atenção" para um catalog_import_job — fonte lógica
 * compartilhada por `getImportacoesAguardandoRevisaoOuErro()` (contagem do
 * StatCard "Pendências") e pelo filtro `?atencao=1` de
 * `/catalogo/importacoes` (drill-down), para os dois nunca divergirem.
 * Não decide sozinha se o job é o mais recente da Coleção — isso é
 * responsabilidade de quem chama (`getCatalogImportJobIdsExigindoAtencao()`
 * abaixo), que já filtra para só o job mais recente por `card_set_id` antes
 * de aplicar esta regra.
 */
function catalogImportJobExigeAtencao(status: string, totalRows: number, processado: number): boolean {
  if ((JOB_STATUSES_AGUARDANDO_REVISAO_OU_ERRO as readonly string[]).includes(status)) return true;
  return status === "COMPLETED" && processado < totalRows;
}

/**
 * IDs dos catalog_import_job que exigem atenção HOJE — único ponto de
 * cálculo desta métrica (2026-08-08, correção de semântica pedida por
 * Fabrício depois da Query 2822 revelar que a métrica anterior, baseada só
 * em status, contava jobs antigos já superados por uma tentativa posterior
 * resolvida). Considera só o job MAIS RECENTE por `card_set_id`
 * (`created_at DESC`, primeira ocorrência — mesmo padrão já usado por
 * `getLatestImportJobIncompleteFlags()`) e aplica `catalogImportJobExigeAtencao()`
 * só a ele; jobs mais antigos da mesma Coleção nunca contam, não importa o
 * status. Sem view nova (mesma decisão de escopo já tomada para esta
 * métrica): `catalog_import_job` tem cardinalidade baixa (um job por
 * execução, não por Card), leitura completa + redução em memória basta.
 *
 * Retorna o `Set` de `job.id` (não só a contagem) para o filtro `?atencao=1`
 * de `/catalogo/importacoes` poder reutilizar exatamente o mesmo cálculo —
 * `getImportacoesAguardandoRevisaoOuErro()` abaixo só conta `ids.size`.
 */
export async function getCatalogImportJobIdsExigindoAtencao(supabase: SupabaseClient): Promise<Set<string>> {
  const rows = await fetchAllRows((from, to) =>
    supabase
      .from("catalog_import_job")
      .select("id, card_set_id, status, total_rows, inserted_rows, updated_rows, unchanged_rows, created_at")
      .order("created_at", { ascending: false })
      .range(from, to),
  );

  const idsExigindoAtencao = new Set<string>();
  const cardSetsVistos = new Set<string>();
  for (const job of rows as {
    id: string;
    card_set_id: string;
    status: string;
    total_rows: number;
    inserted_rows: number;
    updated_rows: number;
    unchanged_rows: number;
  }[]) {
    // Primeira ocorrência de cada card_set_id é a mais recente (ordenado
    // desc acima) — jobs mais antigos da mesma Coleção são ignorados,
    // mesmo que estejam em um status que, isolado, pareceria pendente.
    if (cardSetsVistos.has(job.card_set_id)) continue;
    cardSetsVistos.add(job.card_set_id);

    const processado = job.inserted_rows + job.updated_rows + job.unchanged_rows;
    if (catalogImportJobExigeAtencao(job.status, job.total_rows, processado)) {
      idsExigindoAtencao.add(job.id);
    }
  }
  return idsExigindoAtencao;
}

export async function getImportacoesAguardandoRevisaoOuErro(supabase: SupabaseClient): Promise<number> {
  const ids = await getCatalogImportJobIdsExigindoAtencao(supabase);
  return ids.size;
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

// ---------------------------------------------------------------------------
// Log de Atualizações (/catalogo/log-atualizacoes) — trilha de auditoria de
// escrita administrativa do Catálogo Editorial (catalog_admin_action_log,
// ADR-023), lida via admin_list_catalog_action_log()/admin_get_catalog_
// action_log_weekly_summary() (SECURITY DEFINER, paginação e agregação
// server-side — primeira tela do módulo com filtros/paginação via RPC, não
// fetch-tudo-e-filtra-em-memória como Importações/Atividade Recente/Cartas).
// Escopo V1 aprovado por Fabrício em 2026-08-09: 3 gráficos semanais no topo
// (Cadastro/Alteração/Exclusão, janela fixa de 12 semanas), tabela paginada
// (Data | Quem | Entidade | Registro | Ação | Detalhes) com filtros por
// busca/Entidade/Ação/Usuário, Dialog de Detalhes a partir de metadata/
// enriquecimentos já resolvidos no backend — sem diff antes/depois.
// ---------------------------------------------------------------------------

export const LOG_ATUALIZACOES_PAGE_SIZE = 20;

/** Classificação de negócio dos 21 `action` reais, aprovada por Fabrício (2026-08-09) — calculada no banco (`internal.catalog_admin_action_category()`), nunca por sufixo de string no frontend. */
export type LogAtualizacoesCategoria = "CADASTRO" | "ALTERACAO" | "EXCLUSAO" | "OUTRAS";

export type LogAtualizacoesItem = {
  id: string;
  createdAt: string;
  actorId: string | null;
  /** Já resolvido no backend (display_name com fallback username) — null quando actor_id é nulo (ex. chamada service_role sem ator humano, como svc_apply_catalog_import_revalidation sem p_actor_id). */
  actorLabel: string | null;
  entityType: string;
  entityId: string;
  /** Nome amigável do registro específico — resolvido no backend a partir de metadata (via principal) ou de um JOIN de segurança para linhas antigas sem o enriquecimento (ver decisão 2026-08-09 de gravar card_set_name/card_set_code no momento do evento). */
  entityLabel: string;
  action: string;
  category: LogAtualizacoesCategoria;
  metadata: Record<string, unknown> | null;
};

type LogAtualizacoesRawRow = {
  id: string;
  created_at: string;
  actor_id: string | null;
  actor_label: string | null;
  entity_type: string;
  entity_id: string;
  entity_label: string;
  action: string;
  category: LogAtualizacoesCategoria;
  metadata: Record<string, unknown> | null;
  total_count: number;
};

/**
 * Camada de leitura de /catalogo/log-atualizacoes — chama
 * admin_list_catalog_action_log() (paginação/filtros inteiramente
 * server-side, SECURITY DEFINER). Não-administrador recebe RAISE EXCEPTION
 * da própria function (não uma lista vazia silenciosa); a página em si já
 * bloqueia não-administradores via requireCatalogoAdmin() antes de chegar
 * aqui, então o catch abaixo é só defensivo.
 */
export async function getLogAtualizacoes(
  supabase: SupabaseClient,
  options: {
    search?: string;
    entityType?: string;
    action?: string;
    actorId?: string;
    limit?: number;
    offset?: number;
  },
): Promise<{ items: LogAtualizacoesItem[]; totalCount: number }> {
  const { data, error } = await supabase.rpc("admin_list_catalog_action_log", {
    p_search: options.search?.trim() || null,
    p_entity_type: options.entityType || null,
    p_action: options.action || null,
    p_actor_id: options.actorId || null,
    p_limit: options.limit ?? LOG_ATUALIZACOES_PAGE_SIZE,
    p_offset: options.offset ?? 0,
  });

  if (error || !data) {
    return { items: [], totalCount: 0 };
  }

  const rows = data as LogAtualizacoesRawRow[];
  return {
    items: rows.map((row) => ({
      id: row.id,
      createdAt: row.created_at,
      actorId: row.actor_id,
      actorLabel: row.actor_label,
      entityType: row.entity_type,
      entityId: row.entity_id,
      entityLabel: row.entity_label,
      action: row.action,
      category: row.category,
      metadata: row.metadata,
    })),
    totalCount: rows[0]?.total_count ?? 0,
  };
}

export type LogAtualizacoesResumoSemanalItem = {
  /** Segunda-feira da semana ISO (formato YYYY-MM-DD) — mesma convenção de inicioDaSemana() em importacoes-tendencia.tsx. */
  weekStart: string;
  category: "CADASTRO" | "ALTERACAO" | "EXCLUSAO";
  totalCount: number;
};

/**
 * Agregação semanal (janela fixa de 12 semanas, admin_get_catalog_action_
 * log_weekly_summary()) para os 3 gráficos do topo — sempre server-side,
 * nunca client-side sobre uma única página de resultados (a lista tem
 * paginação própria; agregar só a página atual sub-contaria qualquer semana
 * com mais de LOG_ATUALIZACOES_PAGE_SIZE eventos).
 */
export async function getLogAtualizacoesResumoSemanal(
  supabase: SupabaseClient,
): Promise<LogAtualizacoesResumoSemanalItem[]> {
  const { data, error } = await supabase.rpc("admin_get_catalog_action_log_weekly_summary");

  if (error || !data) {
    return [];
  }

  return (data as { week_start: string; category: "CADASTRO" | "ALTERACAO" | "EXCLUSAO"; total_count: number }[]).map(
    (row) => ({
      weekStart: row.week_start,
      category: row.category,
      totalCount: row.total_count,
    }),
  );
}

export type AdminUserOption = {
  id: string;
  label: string;
};

/**
 * Lista de administradores para o filtro "Usuário" de Log de Atualizações —
 * reaproveita admin_list_users() (Query 1061, ADR-021), já SECURITY
 * DEFINER/paginada. Filtra client-side a is_admin = true (a function em si
 * lista todo user_profile, não só administradores — catalog_admin_
 * action_log.actor_id só grava administradores ou NULL, então usuários
 * comuns nunca aparecem no log e não fazem sentido no dropdown).
 * p_limit: 100 cobre qualquer quantidade real de administradores hoje.
 */
export async function getAdminUserOptions(supabase: SupabaseClient): Promise<AdminUserOption[]> {
  const { data, error } = await supabase.rpc("admin_list_users", { p_limit: 100, p_offset: 0 });

  if (error || !data) {
    return [];
  }

  return (data as { id: string; username: string; display_name: string | null; is_admin: boolean }[])
    .filter((row) => row.is_admin)
    .map((row) => ({ id: row.id, label: row.display_name || row.username }))
    .sort((a, b) => a.label.localeCompare(b.label, "pt-BR"));
}

// ---------------------------------------------------------------------------
// Central de Relatórios (/catalogo/relatorios) — última frente da Trilha 4
// (Módulo Gerencial), V1 aprovada por Fabrício (2026-08-09): 6 relatórios
// imprimíveis (@media print, sem motor de PDF, ver web/app/globals.css).
// "Checklist por Coleção" e "Resumo da Coleção" não têm função própria aqui
// — reaproveitam integralmente getCartasCompletas()/getCardSetByCode(), já
// existentes (mesmo dado do hub de Card Set, só apresentado em layout
// imprimível). Os outros 4 reaproveitam catalog_card_set_metrics/
// catalog_card_set_image_coverage (Query 2123/2124, ADR-027) — o comentário
// da própria view já previa esse reuso ("reutilizável por Visão Geral e
// Central de Relatórios").
// ---------------------------------------------------------------------------

type RelatorioCardSetMetricsRawRow = {
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  expansion_code: string;
  game_code: string;
  total_set_size: number;
  cards_cadastradas: number;
  cards_ativas: number;
  cards_inativas: number;
  cards_pendentes_cadastro: number;
  cards_com_imagem_algum_idioma: number;
};

/** Base compartilhada pelos 3 relatórios de métricas estruturais abaixo — uma única leitura de catalog_card_set_metrics, cada relatório filtra/mapeia o que precisa. */
async function fetchRelatorioCardSetMetrics(supabase: SupabaseClient): Promise<RelatorioCardSetMetricsRawRow[]> {
  const { data, error } = await supabase
    .from("catalog_card_set_metrics")
    .select(
      "card_set_id, card_set_code, card_set_name, expansion_code, game_code, total_set_size, cards_cadastradas, cards_ativas, cards_inativas, cards_pendentes_cadastro, cards_com_imagem_algum_idioma",
    );

  if (error || !data) {
    return [];
  }

  return (data as RelatorioCardSetMetricsRawRow[]).sort((a, b) => a.card_set_name.localeCompare(b.card_set_name, "pt-BR"));
}

export type RelatorioCartasPendentesItem = {
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  totalSetSize: number;
  cardsCadastradas: number;
  cardsPendentes: number;
};

/** Relatório "Cartas pendentes por Coleção" — só as Coleções com cards_pendentes_cadastro > 0 (mesma definição de "Saúde do catálogo" na Visão Geral), detalhado linha a linha em vez da contagem agregada. */
export async function getRelatorioCartasPendentes(supabase: SupabaseClient): Promise<RelatorioCartasPendentesItem[]> {
  const rows = await fetchRelatorioCardSetMetrics(supabase);
  return rows
    .filter((row) => row.cards_pendentes_cadastro > 0)
    .map((row) => ({
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      totalSetSize: row.total_set_size,
      cardsCadastradas: row.cards_cadastradas,
      cardsPendentes: row.cards_pendentes_cadastro,
    }));
}

export type RelatorioImagensPendentesItem = {
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  cardsCadastradas: number;
  cardsComImagem: number;
  cardsSemImagem: number;
};

/** Relatório "Imagens pendentes por Coleção" — Coleções com pelo menos uma Carta cadastrada sem imagem canônica em nenhum idioma ativo (cards_cadastradas - cards_com_imagem_algum_idioma > 0). */
export async function getRelatorioImagensPendentes(supabase: SupabaseClient): Promise<RelatorioImagensPendentesItem[]> {
  const rows = await fetchRelatorioCardSetMetrics(supabase);
  return rows
    .map((row) => ({
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      cardsCadastradas: row.cards_cadastradas,
      cardsComImagem: row.cards_com_imagem_algum_idioma,
      cardsSemImagem: row.cards_cadastradas - row.cards_com_imagem_algum_idioma,
    }))
    .filter((row) => row.cardsSemImagem > 0);
}

export type RelatorioQualidadeCatalogoItem = {
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  totalSetSize: number;
  cardsCadastradas: number;
  cardsAtivas: number;
  cardsInativas: number;
  cardsPendentes: number;
  cardsComImagem: number;
  cardsSemImagem: number;
};

/**
 * Relatório "Qualidade do Catálogo" — uma linha por Coleção (TODAS, não só
 * as com pendência, ao contrário dos dois relatórios acima), cruzando as
 * mesmas três lacunas estruturais já mostradas de forma agregada em "Saúde
 * do catálogo" (Visão Geral): pendência de cadastro, pendência de imagem e
 * cartas inativas. Definição confirmada por Fabrício antes da implementação
 * (2026-08-09, via pergunta direta — única das 6 sem especificação prévia
 * registrada em nenhum documento).
 */
export async function getRelatorioQualidadeCatalogo(supabase: SupabaseClient): Promise<RelatorioQualidadeCatalogoItem[]> {
  const rows = await fetchRelatorioCardSetMetrics(supabase);
  return rows.map((row) => ({
    cardSetId: row.card_set_id,
    cardSetCode: row.card_set_code,
    cardSetName: row.card_set_name,
    totalSetSize: row.total_set_size,
    cardsCadastradas: row.cards_cadastradas,
    cardsAtivas: row.cards_ativas,
    cardsInativas: row.cards_inativas,
    cardsPendentes: row.cards_pendentes_cadastro,
    cardsComImagem: row.cards_com_imagem_algum_idioma,
    cardsSemImagem: row.cards_cadastradas - row.cards_com_imagem_algum_idioma,
  }));
}

export type RelatorioCoberturaGeralItem = {
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  languageCode: string;
  cardsCadastradas: number;
  cardsComImagem: number;
};

/**
 * Relatório "Cobertura Geral" — uma linha por (Coleção, idioma ativo), de
 * catalog_card_set_image_coverage, com cards_cadastradas
 * (catalog_card_set_metrics) como denominador — mesma definição de
 * percentual já usada na Visão Geral e no hub de Card Set (cardsComImagem /
 * cardsCatalogados), nunca uma segunda fórmula divergente.
 */
export async function getRelatorioCoberturaGeral(supabase: SupabaseClient): Promise<RelatorioCoberturaGeralItem[]> {
  const [metricsRows, coverageResult] = await Promise.all([
    fetchRelatorioCardSetMetrics(supabase),
    supabase.from("catalog_card_set_image_coverage").select("card_set_id, card_set_code, language_code, cards_com_imagem"),
  ]);

  if (coverageResult.error || !coverageResult.data) {
    return [];
  }

  const metricsPorCardSetId = new Map(metricsRows.map((row) => [row.card_set_id, row]));

  return (
    coverageResult.data as { card_set_id: string; card_set_code: string; language_code: string; cards_com_imagem: number }[]
  )
    .map((row) => {
      const metrics = metricsPorCardSetId.get(row.card_set_id);
      return {
        cardSetId: row.card_set_id,
        cardSetCode: row.card_set_code,
        cardSetName: metrics?.card_set_name ?? row.card_set_code,
        languageCode: row.language_code,
        cardsCadastradas: metrics?.cards_cadastradas ?? 0,
        cardsComImagem: row.cards_com_imagem,
      };
    })
    .sort(
      (a, b) => a.cardSetName.localeCompare(b.cardSetName, "pt-BR") || a.languageCode.localeCompare(b.languageCode),
    );
}

export type RelatorioCoberturaVariantesItem = {
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  cardsCadastradas: number;
  cardsComVariante: number;
  cardsSemVariante: number;
};

/**
 * Relatório "Cobertura de Card Variant" — primeiro incremento técnico do
 * bloco Card Variant (ADR-028, Query 2135, 2026-08-14), motivado pelo
 * checkpoint que confirmou cobertura parcial (7 dos 43 Card Sets têm Card
 * Variant cadastrada). Uma linha por Card Set, direto de
 * catalog_card_set_variant_coverage (view nova, grão = 1 linha por Card Set,
 * já traz cards_cadastradas/cards_com_variante/cards_sem_variante prontos —
 * nenhum join em memória necessário aqui, diferente de
 * getRelatorioCoberturaGeral, porque a view já reaproveita
 * catalog_card_set_metrics internamente). Percentual calculado na página,
 * não em SQL — mesmo padrão de RelatorioCoberturaGeralPage. Leitura única
 * (1 round-trip), 43 linhas sempre, independente do volume de Cards no
 * catálogo.
 */
export async function getRelatorioCoberturaVariantes(
  supabase: SupabaseClient,
): Promise<RelatorioCoberturaVariantesItem[]> {
  const { data, error } = await supabase
    .from("catalog_card_set_variant_coverage")
    .select("card_set_id, card_set_code, card_set_name, cards_cadastradas, cards_com_variante, cards_sem_variante");

  if (error || !data) {
    return [];
  }

  return (
    data as {
      card_set_id: string;
      card_set_code: string;
      card_set_name: string;
      cards_cadastradas: number;
      cards_com_variante: number;
      cards_sem_variante: number;
    }[]
  )
    .map((row) => ({
      cardSetId: row.card_set_id,
      cardSetCode: row.card_set_code,
      cardSetName: row.card_set_name,
      cardsCadastradas: row.cards_cadastradas,
      cardsComVariante: row.cards_com_variante,
      cardsSemVariante: row.cards_sem_variante,
    }))
    .sort((a, b) => a.cardSetName.localeCompare(b.cardSetName, "pt-BR"));
}
