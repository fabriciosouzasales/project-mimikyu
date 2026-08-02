import { Boxes } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { CatalogoGallery } from "@/components/catalogo/catalogo-gallery";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import {
  CATALOGO_SEARCH_CARDS_PAGE_SIZE,
  getCardSetLogoUrls,
  getCardSetsGroupedByExpansion,
  getCardSetsOverview,
  getExpansoes,
  getGameOptions,
  searchCatalogo,
  type CardSetsExpansionGroupWithLogo,
} from "@/lib/catalogo/queries";

/**
 * Tela Catálogo — página de entrada do módulo (spec de UX aprovada em
 * 2026-07-31, com os quatro ajustes da mesma data: ação "Novo" cobrindo o
 * domínio completo, ordenação explícita com filtro de Jogo, busca que só
 * atualiza o conteúdo, "Carregar mais" no lugar de rolagem infinita).
 * Substitui a antiga listagem somente-leitura em `/catalogo/card-sets`
 * (`card-sets-table.tsx`, que fica sem uso — ver relatório de pendências).
 * A rota de detalhe (`/catalogo/card-sets/[code]`) não é alterada.
 *
 * Ajuste 2026-07-31 (pedido de Fabrício, "faça todos os ajustes necessários
 * para manter o mesmo padrão da página Expansões"): `jogos`/`expansoes`
 * (sem filtro) e `cardSets` (via `getCardSetsOverview()`, mesma função da
 * tabela da Visão Geral) passam a alimentar também `CardSetsStats` —
 * totais sempre globais, independente do filtro/busca ativo na galeria
 * abaixo (mesmo raciocínio de `ExpansoesStats`/`getExpansoes()` sem
 * filtro).
 *
 * Ajuste 2026-08-02 (pedido de Fabrício: "da mesma forma como fizemos na
 * página de expansões, separando-as por Jogo, precisamos na página de
 * Coleções, separá-las por Expansão. Hoje aparecem todas juntas") — modo
 * galeria (sem busca) passou a usar `getCardSetsGroupedByExpansion()` em vez
 * de `getCardSetsForCatalogo()` paginado — mesma mudança estrutural já
 * aplicada a `/catalogo/expansoes` quando ganhou agrupamento por Jogo (ver
 * `expansoes/page.tsx`). URLs assinadas resolvidas de uma vez só para todos
 * os itens de todos os grupos (mesmo padrão de `allPaths` em `expansoes/
 * page.tsx`). Busca (`mode === "search"`) continua flat e paginada, sem
 * mudança — `getCardSetsForCatalogo()` segue em uso só por ela (via
 * `searchCatalogo`/`searchCatalogoAction`).
 */
export default async function CatalogoCardSetsPage({
  searchParams,
}: {
  searchParams: Promise<{ game?: string; expansion?: string; q?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Coleções", Boxes);
  if (denied) return denied;

  const { game, expansion, q } = await searchParams;
  const query = q?.trim() ?? "";

  const [jogos, expansoesDoJogo, expansoes, cardSetsOverview] = await Promise.all([
    getGameOptions(supabase),
    game ? getExpansoes(supabase, { gameCode: game }) : Promise.resolve([]),
    getExpansoes(supabase),
    getCardSetsOverview(supabase),
  ]);

  const mode: "gallery" | "search" = query ? "search" : "gallery";

  let initialCards: Awaited<ReturnType<typeof searchCatalogo>>["cards"] = [];
  let searchItems: Awaited<ReturnType<typeof searchCatalogo>>["cardSets"] = [];
  let initialHasMore = false;
  let groups: Awaited<ReturnType<typeof getCardSetsGroupedByExpansion>> = [];

  if (mode === "search") {
    const result = await searchCatalogo(supabase, query, {
      cardsLimit: CATALOGO_SEARCH_CARDS_PAGE_SIZE,
      cardsOffset: 0,
    });
    searchItems = result.cardSets;
    initialCards = result.cards;
    initialHasMore = result.hasMoreCards;
  } else {
    groups = await getCardSetsGroupedByExpansion(supabase, { gameCode: game, expansionCode: expansion });
  }

  // URLs assinadas resolvidas de uma vez só, para todos os caminhos
  // envolvidos (grupos + busca) — mesmo padrão de `expansoes/page.tsx`.
  const allPaths = [
    ...groups.flatMap((group) => group.items.map((item) => item.logoStoragePath)),
    ...searchItems.map((item) => item.logoStoragePath),
  ];
  const logoUrls = await getCardSetLogoUrls(supabase, allPaths);
  const withLogo = <T extends { logoStoragePath: string | null }>(item: T) => ({
    ...item,
    logoUrl: item.logoStoragePath ? (logoUrls.get(item.logoStoragePath) ?? null) : null,
  });
  const groupsWithLogo: CardSetsExpansionGroupWithLogo[] = groups.map((group) => ({
    ...group,
    items: group.items.map(withLogo),
  }));
  const cardSetsWithLogo = searchItems.map(withLogo);

  return (
    <AppShell title="Coleções" icon={Boxes}>
      <PageContainer width="wide">
        <CatalogoGallery
          jogos={jogos}
          expansoesDoJogo={expansoesDoJogo}
          expansoes={expansoes}
          cardSetsOverview={cardSetsOverview}
          gameCode={game}
          expansionCode={expansion}
          query={query}
          initialGroups={groupsWithLogo}
          initialCardSets={cardSetsWithLogo}
          initialHasMore={initialHasMore}
          initialCards={initialCards}
          mode={mode}
        />
      </PageContainer>
    </AppShell>
  );
}
