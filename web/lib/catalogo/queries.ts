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
 * Deliberadamente sem indicadores de Game/Expansion (só 1 Game/1 Expansion
 * hoje — não agregam valor visual, ajuste pedido por Fabrício) e sem
 * exposição da discrepância de Card Category ENERGY (decisão editorial
 * interna, não deve aparecer nesta tela).
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
};

export type DistribuicaoPorRaridade = {
  code: string;
  name: string;
  totalCards: number;
};

export type AtividadeRecenteItem = {
  id: string;
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
    .select("id, code, name, set_type, total_set_size, logo_storage_path")
    .order("release_order", { ascending: true });

  if (error || !data) {
    return [];
  }

  return data as CardSetRow[];
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
