"use client";

import { Layers, Plus } from "lucide-react";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { deleteExpansions } from "@/app/catalogo/expansoes/actions";
import { searchExpansoesAction } from "@/app/catalogo/expansoes/catalogo-actions";
import { CreateExpansionDialog, EditExpansionDialog } from "@/components/catalogo/expansoes-table";
import { CatalogoFilterSelect } from "@/components/catalogo/catalogo-filter-select";
import { CatalogoSearchBar } from "@/components/catalogo/catalogo-search-bar";
import { ConfirmDeleteBar } from "@/components/catalogo/confirm-delete-bar";
import { ExpansaoGalleryCard } from "@/components/catalogo/expansao-gallery-card";
import { ExpansoesStats } from "@/components/catalogo/expansoes-stats";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import { getGameAccentColor } from "@/lib/catalogo/game-accent";
import type { ExpansaoRow, ExpansaoWithLogo, ExpansoesGameGroupWithLogo, GameOption } from "@/lib/catalogo/queries";

/**
 * Redesenho da tela de Expansões (2026-07-31) usando exatamente a mesma
 * linguagem visual/comportamento da tela Catálogo (Card Sets): busca e
 * filtro de Jogo em barra fixa, galeria de cards, "Carregar mais", estados
 * vazio/carregamento no mesmo formato. Único chip de Jogo (sem segundo
 * nível de Expansão — filtrar Expansão dentro da própria tela de Expansões
 * seria circular).
 *
 * Ajuste 2026-07-31 (pedido de Fabrício, "refinar a experiência visual"):
 * ícone `Layers` antes do título (mesmo do item de menu — ver `AppShell`/
 * `Header`), cards de indicador (`ExpansoesStats`, padrão de Jogos) entre o
 * cabeçalho e a busca, botão "Nova expansão" fora do `PageHeader` — agora
 * fica logo acima da busca (mesmo lugar de "Novo Jogo" em Jogos) — e busca/
 * filtro no mesmo tamanho/cor (`h-9`, `text-xs`, `bg-surface-muted`) da
 * tela Jogos.
 *
 * Ajuste 2026-07-31, rodada seguinte (pedido de Fabrício: busca "quase
 * invisível" flutuando sobre o fundo da página): busca/filtro deixam de
 * flutuar soltos (`sticky`/`bg-background`) e passam a viver dentro do
 * mesmo `Card` branco que envolve a galeria — mesmo padrão de Jogos
 * (`jogos-table.tsx`: busca no cabeçalho do card, separada só por
 * `border-b`, conteúdo logo abaixo).
 *
 * Cadastro continua no mesmo Dialog já existente (`CreateExpansionDialog`,
 * exportado). Edição também (`EditExpansionDialog`), mas deixou de ser o
 * clique no card inteiro (2026-07-31, pedido de Fabrício) — agora é uma
 * ação rápida (ícone de lápis) dentro do card; o clique no card em si
 * navega para Coleções filtradas por aquela Expansão — ver
 * `expansao-gallery-card.tsx`.
 *
 * Ajuste 2026-07-31, mesma rodada ("vamos implementar logo a função de
 * deletar item"): ação rápida de excluir (ícone de lixeira, ao lado do de
 * editar) — mesmo mecanismo de `useAdminListState.startQuickDelete()` +
 * `ConfirmDeleteBar` já usado em Jogos. Server Action `deleteExpansions`
 * chama `admin_delete_expansion()` (Query 2044, ADR-023) — CONFIRMADA
 * EXECUTADA e validada por Fabrício via UI (2026-07-31).
 *
 * Ajuste 2026-07-31, rodada seguinte (pedido de Fabrício: "as expansões
 * devem ser exibidas separadamente por cada tipo de Jogo e organizadas pela
 * data de lançamento de forma decrescente"): o modo galeria (sem busca)
 * deixou de ser uma grade flat paginada e passou a ser uma seção por Jogo
 * (`ExpansoesGameGroup`, `getExpansoesGroupedByGame()`), cada uma com seu
 * próprio grid de cards ordenado por `release_order` — ver a função de
 * query para a nota sobre `release_order` fazer as vezes de "data de
 * lançamento" (Expansion não tem coluna de data real) e sobre a direção do
 * sort (ascendente, ajustada a partir do feedback de Fabrício vendo o
 * resultado ao vivo). Como consequência necessária do agrupamento, o
 * "Carregar mais" flat deixou de existir no modo galeria — a tela carrega
 * todas as Expansões de uma vez. A busca (`mode === "search"`) continua
 * exatamente como antes: lista flat, sem agrupamento, paginada.
 *
 * Ajuste 2026-07-31, mesmo dia (segundo ajuste de ordenação): a ordem dos
 * próprios grupos (Jogos) NÃO é alfabética — Fabrício pediu explicitamente
 * "primeiro... Pokémon e depois Lorcana... Pokémon foi o primeiro game
 * cadastrado". `getExpansoesGroupedByGame()` ordena os grupos por
 * `game.created_at` ascendente (Jogo mais antigo primeiro), não pelo nome.
 *
 * Ajuste 2026-07-31, mesmo dia ("vamos incluir uma imagem para cada
 * expansão"): logo por Expansão (Queries 2045-2047, ADR-022). `initialGroups`/
 * `initialItems` chegam com `logoUrl` já resolvida (URL assinada, gerada no
 * Server Component — ver `expansoes/page.tsx`); `ExpansaoGalleryCard` exibe
 * a imagem quando existe, iniciais como reserva. Upload/remoção acontecem
 * dentro do `EditExpansionDialog` (não no de criação — a Expansão precisa
 * já existir para ter um id de caminho no bucket); `onLogoUpdated` só chama
 * `router.refresh()`, sem fechar o Dialog nem mostrar o banner de sucesso
 * do formulário nome/ordem (são ações independentes).
 */
export function ExpansoesGallery({
  jogos,
  expansoes,
  gameCode,
  query,
  mode,
  defaultGameId,
  initialGroups,
  initialItems,
  initialHasMore,
}: {
  jogos: GameOption[];
  /** Lista completa, sem filtro/paginação — só para `ExpansoesStats` (mesmo papel de `jogos` em `JogosStats`). */
  expansoes: ExpansaoRow[];
  gameCode?: string;
  query: string;
  mode: "gallery" | "search";
  defaultGameId?: string;
  /** Modo galeria: Expansões agrupadas por Jogo, cada grupo já ordenado por `release_order` e com `logoUrl` resolvida. */
  initialGroups: ExpansoesGameGroupWithLogo[];
  /** Modo busca: lista flat, paginada — sem agrupamento por Jogo. */
  initialItems: ExpansaoWithLogo[];
  initialHasMore: boolean;
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [groups, setGroups] = useState(initialGroups);
  const [items, setItems] = useState(initialItems);
  const [hasMore, setHasMore] = useState(initialHasMore);
  const [isPending, startTransition] = useTransition();

  // Sincroniza com o lote inicial sempre que o servidor manda um novo
  // (busca, filtro de Jogo ou navegação) — evita misturar itens carregados
  // via "Carregar mais" de um contexto anterior com o novo.
  useEffect(() => {
    setGroups(initialGroups);
    setItems(initialItems);
    setHasMore(initialHasMore);
  }, [initialGroups, initialItems, initialHasMore]);

  // Lista flat de todos os itens visíveis, independente do modo — usada só
  // para localizar a Expansão em edição/exclusão e o destaque de sucesso;
  // nunca para renderizar (a renderização respeita o modo, grupos ou flat).
  const allItems = mode === "search" ? items : groups.flatMap((group) => group.items);
  const editingExpansao = allItems.find((item) => item.id === state.editingId) ?? null;
  const expansaoToDelete = allItems.find((item) => state.selectedIds.has(item.id)) ?? null;

  function handleLoadMore() {
    startTransition(async () => {
      const result = await searchExpansoesAction({ query, offset: items.length });
      setItems((prev) => [...prev, ...result.items]);
      setHasMore(result.hasMore);
    });
  }

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  function handleDeleted() {
    state.onSuccess("Expansão excluída com sucesso.");
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <Layers className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Expansões</PageTitle>
          </div>
          <PageDescription>Explore as Expansões catalogadas, por Jogo ou por busca direta.</PageDescription>
        </PageHeading>
      </PageHeader>

      <ExpansoesStats expansoes={expansoes} jogos={jogos} />

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      {state.confirmingDelete && expansaoToDelete && (
        <ConfirmDeleteBar
          items={[{ id: expansaoToDelete.id, label: `${expansaoToDelete.name} (${expansaoToDelete.code})` }]}
          action={deleteExpansions}
          nounSingular="expansão"
          nounPlural="expansões"
          onDone={handleDeleted}
          onPartialSuccess={() => router.refresh()}
          onCancel={state.cancelConfirmDelete}
        />
      )}

      <div className="space-y-2">
        <div className="flex justify-end">
          <Button type="button" size="sm" onClick={state.startCreate}>
            <Plus className="h-3.5 w-3.5" />
            Nova expansão
          </Button>
        </div>

        <Card density="compact" className="overflow-hidden">
          <div className="flex items-center gap-2 border-b border-border p-4">
            <div className="min-w-0 flex-1">
              <CatalogoSearchBar
                initialQuery={query}
                placeholder="Buscar por nome ou código da Expansão…"
                className="h-9 bg-surface-muted text-xs"
              />
            </div>
            <CatalogoFilterSelect
              jogos={jogos}
              expansoesDoJogo={[]}
              gameCode={gameCode}
              className="h-9 bg-surface-muted text-xs"
              query={query}
              basePath="/catalogo/expansoes"
            />
          </div>

          {/* `pt-4` explícito: `CardContent density="compact"` por padrão não
              tem padding-top (pensado para conteúdo que encosta na borda,
              como a tabela de Jogos) — sem ele, a primeira linha de cards
              da galeria ficava colada na borda inferior da busca. */}
          <CardContent density="compact" className="pt-4">
            {mode === "search" ? (
              items.length === 0 ? (
                <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro nome ou código." />
              ) : (
                <div className="space-y-4">
                  <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
                    {items.map((expansao) => (
                      <ExpansaoGalleryCard
                        key={expansao.id}
                        expansao={expansao}
                        highlighted={state.highlightId === expansao.id}
                        onEdit={state.startEdit}
                        onQuickDelete={state.startQuickDelete}
                      />
                    ))}
                  </div>

                  {hasMore && (
                    <div className="flex justify-center">
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={handleLoadMore}
                        disabled={isPending}
                      >
                        {isPending ? "Carregando…" : "Carregar mais"}
                      </Button>
                    </div>
                  )}
                </div>
              )
            ) : groups.length === 0 ? (
              <EmptyState
                title="Nenhuma Expansão cadastrada ainda"
                description='Use o botão "Nova expansão" para começar.'
              />
            ) : (
              <div className="space-y-6">
                {groups.map((group) => (
                  <div key={group.gameId} className="space-y-3">
                    <div className="flex items-center gap-2">
                      <span
                        className="h-2 w-2 shrink-0 rounded-full"
                        style={{ backgroundColor: getGameAccentColor(group.gameCode || group.gameName) }}
                        aria-hidden="true"
                      />
                      <h3 className="text-sm font-medium text-foreground">{group.gameName}</h3>
                      <span className="text-xs text-muted-foreground">
                        ({group.items.length} {group.items.length === 1 ? "expansão" : "expansões"})
                      </span>
                    </div>
                    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
                      {group.items.map((expansao) => (
                        <ExpansaoGalleryCard
                          key={expansao.id}
                          expansao={expansao}
                          highlighted={state.highlightId === expansao.id}
                          onEdit={state.startEdit}
                          onQuickDelete={state.startQuickDelete}
                        />
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <CreateExpansionDialog
        open={state.creating}
        jogos={jogos}
        defaultGameId={defaultGameId}
        onSaved={handleSaved}
        onCancel={state.cancelCreate}
      />

      <EditExpansionDialog
        open={editingExpansao !== null}
        expansao={editingExpansao}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
        onLogoUpdated={() => router.refresh()}
      />
    </div>
  );
}
