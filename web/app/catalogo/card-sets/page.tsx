import { Boxes } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { CatalogoGallery } from "@/components/catalogo/catalogo-gallery";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import {
  CATALOGO_PAGE_SIZE,
  CATALOGO_SEARCH_CARDS_PAGE_SIZE,
  getCardSetLogoUrls,
  getCardSetsForCatalogo,
  getCardSetsOverview,
  getExpansoes,
  getGameOptions,
  searchCatalogo,
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

  let initialCardSets: Awaited<ReturnType<typeof getCardSetsForCatalogo>>["items"] = [];
  let initialHasMore = false;
  let initialCards: Awaited<ReturnType<typeof searchCatalogo>>["cards"] = [];

  if (mode === "search") {
    const result = await searchCatalogo(supabase, query, {
      cardsLimit: CATALOGO_SEARCH_CARDS_PAGE_SIZE,
      cardsOffset: 0,
    });
    initialCardSets = result.cardSets;
    initialCards = result.cards;
    initialHasMore = result.hasMoreCards;
  } else {
    const result = await getCardSetsForCatalogo(supabase, {
      gameCode: game,
      expansionCode: expansion,
      limit: CATALOGO_PAGE_SIZE,
      offset: 0,
    });
    initialCardSets = result.items;
    initialHasMore = result.hasMore;
  }

  const logoUrls = await getCardSetLogoUrls(
    supabase,
    initialCardSets.map((set) => set.logoStoragePath),
  );
  const cardSetsWithLogo = initialCardSets.map((set) => ({
    ...set,
    logoUrl: set.logoStoragePath ? (logoUrls.get(set.logoStoragePath) ?? null) : null,
  }));

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
          initialCardSets={cardSetsWithLogo}
          initialHasMore={initialHasMore}
          initialCards={initialCards}
          mode={mode}
        />
      </PageContainer>
    </AppShell>
  );
}
