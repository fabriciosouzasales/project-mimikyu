import { AppShell } from "@/components/app-shell/app-shell";
import { ExpansoesGallery } from "@/components/catalogo/expansoes-gallery";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import { EXPANSOES_PAGE_SIZE, getExpansoesForCatalogo, getGameOptions, searchExpansoes } from "@/lib/catalogo/queries";

/**
 * Tela de Expansões — redesenhada em 2026-07-31 com a mesma linguagem
 * visual/comportamento da tela Catálogo (Card Sets): galeria de cards,
 * busca, filtro de Jogo, "Carregar mais", em vez da tabela agrupada por
 * Jogo da versão anterior (`ExpansoesTable`, que fica sem uso — ver
 * relatório de pendências). Filtro `?game=CODE` preservado (mesmo destino
 * do contador clicável de Expansões na tela de Jogos). Cadastro/edição
 * continuam via `admin_create_expansion()`/`admin_update_expansion()`
 * (ADR-023) — nenhuma mudança de regra de negócio.
 */
export default async function ExpansoesPage({
  searchParams,
}: {
  searchParams: Promise<{ game?: string; q?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Expansões");
  if (denied) return denied;

  const { game, q } = await searchParams;
  const query = q?.trim() ?? "";
  const mode: "gallery" | "search" = query ? "search" : "gallery";

  const jogos = await getGameOptions(supabase);
  const defaultGameId = game ? jogos.find((jogo) => jogo.code === game)?.id : undefined;

  const result =
    mode === "search"
      ? await searchExpansoes(supabase, query, { limit: EXPANSOES_PAGE_SIZE, offset: 0 })
      : await getExpansoesForCatalogo(supabase, { gameCode: game, limit: EXPANSOES_PAGE_SIZE, offset: 0 });

  return (
    <AppShell title="Expansões">
      <PageContainer width="wide">
        <ExpansoesGallery
          jogos={jogos}
          gameCode={game}
          query={query}
          mode={mode}
          defaultGameId={defaultGameId}
          initialItems={result.items}
          initialHasMore={result.hasMore}
        />
      </PageContainer>
    </AppShell>
  );
}
