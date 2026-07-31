import { Layers } from "lucide-react";
import { AppShell } from "@/components/app-shell/app-shell";
import { ExpansoesGallery } from "@/components/catalogo/expansoes-gallery";
import { requireCatalogoAdmin } from "@/components/catalogo/catalogo-guard";
import { PageContainer } from "@/components/ui/page";
import {
  EXPANSOES_PAGE_SIZE,
  getExpansionLogoUrls,
  getExpansoes,
  getExpansoesGroupedByGame,
  getGameOptions,
  searchExpansoes,
  type ExpansaoWithLogo,
  type ExpansoesGameGroupWithLogo,
} from "@/lib/catalogo/queries";

/**
 * Tela de Expansões — redesenhada em 2026-07-31 com a mesma linguagem
 * visual/comportamento da tela Catálogo (Card Sets): galeria de cards,
 * busca, filtro de Jogo, "Carregar mais", em vez da tabela agrupada por
 * Jogo da versão anterior (`ExpansoesTable`, que fica sem uso — ver
 * relatório de pendências). Filtro `?game=CODE` preservado (mesmo destino
 * do contador clicável de Expansões na tela de Jogos). Cadastro/edição
 * continuam via `admin_create_expansion()`/`admin_update_expansion()`
 * (ADR-023) — nenhuma mudança de regra de negócio.
 *
 * Ajuste 2026-07-31 (pedido de Fabrício, "refinar a experiência visual"):
 * ícone `Layers` (mesmo do item de menu) antes do título, cards de
 * indicador (`ExpansoesStats`, padrão introduzido em Jogos) e botão/busca/
 * filtro realinhados ao mesmo padrão de Jogos/Visão Geral — ver
 * `expansoes-gallery.tsx`. A galeria de cards abaixo continua igual de
 * propósito ("mantenha o layout da lista... vamos trabalhar nesse item na
 * sequência").
 *
 * Ajuste 2026-07-31, rodada seguinte (pedido de Fabrício: "as expansões
 * devem ser exibidas separadamente por cada tipo de Jogo e organizadas pela
 * data de lançamento de forma decrescente"): o modo galeria (sem busca)
 * passou a usar `getExpansoesGroupedByGame()` em vez de `getExpansoesForCatalogo()`
 * — ver a função para a nota sobre `release_order` fazer as vezes de "data
 * de lançamento". Busca (`mode === "search"`) continua flat e paginada, sem
 * mudança.
 *
 * Ajuste 2026-07-31, mesmo dia ("vamos incluir uma imagem para cada
 * expansão"): logo por Expansão (Queries 2045-2047, ADR-022, mesmo padrão
 * de `card_set.logo_storage_path`) — bucket privado, leitura só via URL
 * assinada. Resolvidas aqui, no Server Component, para os grupos e para a
 * busca inicial (mesmo padrão de `card-sets/page.tsx`); `searchExpansoesAction`
 * (`catalogo-actions.ts`) resolve de novo para o "Carregar mais" da busca.
 */
export default async function ExpansoesPage({
  searchParams,
}: {
  searchParams: Promise<{ game?: string; q?: string }>;
}) {
  const { denied, supabase } = await requireCatalogoAdmin("Expansões", Layers);
  if (denied) return denied;

  const { game, q } = await searchParams;
  const query = q?.trim() ?? "";
  const mode: "gallery" | "search" = query ? "search" : "gallery";

  // `expansoes` (sem filtro) alimenta só os cards de indicador — sempre
  // totais globais, independente do filtro/busca ativo na galeria abaixo
  // (mesmo raciocínio de `JogosStats`, que usa `getJogos()` completo em vez
  // da página filtrada da tabela).
  const [jogos, expansoes] = await Promise.all([getGameOptions(supabase), getExpansoes(supabase)]);
  const defaultGameId = game ? jogos.find((jogo) => jogo.code === game)?.id : undefined;

  const searchResult =
    mode === "search" ? await searchExpansoes(supabase, query, { limit: EXPANSOES_PAGE_SIZE, offset: 0 }) : null;
  const groups = mode === "gallery" ? await getExpansoesGroupedByGame(supabase, { gameCode: game }) : [];

  // URLs assinadas resolvidas de uma vez só, para todos os caminhos
  // envolvidos (grupos + busca) — uma única chamada de Storage em vez de
  // uma por Expansão.
  const allPaths = [...groups.flatMap((group) => group.items.map((item) => item.logoStoragePath)), ...(searchResult?.items.map((item) => item.logoStoragePath) ?? [])];
  const logoUrls = await getExpansionLogoUrls(supabase, allPaths);
  const withLogo = (item: (typeof groups)[number]["items"][number]): ExpansaoWithLogo => ({
    ...item,
    logoUrl: item.logoStoragePath ? (logoUrls.get(item.logoStoragePath) ?? null) : null,
  });
  const groupsWithLogo: ExpansoesGameGroupWithLogo[] = groups.map((group) => ({
    ...group,
    items: group.items.map(withLogo),
  }));
  const itemsWithLogo: ExpansaoWithLogo[] = (searchResult?.items ?? []).map(withLogo);

  return (
    <AppShell title="Expansões" icon={Layers}>
      <PageContainer width="wide">
        <ExpansoesGallery
          jogos={jogos}
          expansoes={expansoes}
          gameCode={game}
          query={query}
          mode={mode}
          defaultGameId={defaultGameId}
          initialGroups={groupsWithLogo}
          initialItems={itemsWithLogo}
          initialHasMore={searchResult?.hasMore ?? false}
        />
      </PageContainer>
    </AppShell>
  );
}
