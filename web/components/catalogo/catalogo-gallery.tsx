"use client";

import { Boxes, Plus } from "lucide-react";
import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { deleteCardSets } from "@/app/catalogo/card-sets/actions";
import { loadMoreCardSets, searchCatalogoAction, type CardSetWithLogo } from "@/app/catalogo/card-sets/catalogo-actions";
import { CardSetGalleryCard } from "@/components/catalogo/card-set-gallery-card";
import { CardSetsStats } from "@/components/catalogo/card-sets-stats";
import { EditCardSetDialog } from "@/components/catalogo/card-set-dialogs";
import { CatalogoFilterSelect } from "@/components/catalogo/catalogo-filter-select";
import { CatalogoSearchBar } from "@/components/catalogo/catalogo-search-bar";
import { ConfirmDeleteBar } from "@/components/catalogo/confirm-delete-bar";
import { NovoCatalogoDialog } from "@/components/catalogo/novo-catalogo-dialog";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import type { CatalogoCardResult, CardSetOverviewRow, ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

/**
 * Composição raiz da tela Coleções (spec aprovada 2026-07-31; cabeçalho,
 * busca e filtros fixos, `CatalogoContent` trocava entre galeria e
 * resultado). Reescrita em 2026-07-31 (pedido de Fabrício: "faça todos os
 * ajustes necessários para manter o mesmo padrão da página Expansões") para
 * a mesma estrutura de `expansoes-gallery.tsx` — a antiga divisão em dois
 * componentes (`CatalogoGallery` para cabeçalho/busca fixos +
 * `CatalogoContent` para o conteúdo trocável) foi absorvida aqui num único
 * componente, espelhando Expansões (que nunca teve essa divisão). O arquivo
 * `catalogo-content.tsx` fica sem uso — não removido (mount não suporta
 * `unlink()`, ver memória do projeto), mas não é mais importado por
 * nenhuma tela.
 *
 * Ajustes trazidos do padrão de Expansões:
 * - `CardSetsStats` (indicadores) entre o cabeçalho e a busca.
 * - Botão "Novo" sai do `PageHeader` e passa a ficar numa linha própria,
 *   logo acima do `Card` que envolve busca+filtro+conteúdo (mesmo lugar de
 *   "Nova expansão"/"Novo Jogo").
 * - Busca e filtro migram para dentro do `Card` (cabeçalho do card, só
 *   separado por `border-b`), no tamanho/cor padrão (`h-9`,
 *   `bg-surface-muted`, `text-xs`) — deixam de flutuar soltos/`sticky`.
 * - Ação rápida de editar/excluir em cada card (`CardSetGalleryCard`),
 *   mesmo mecanismo de `useAdminListState` + `ConfirmDeleteBar` já usado em
 *   Jogos/Expansões. `EditCardSetDialog`/`deleteCardSets` chamam
 *   `admin_update_card_set()`/`admin_delete_card_set()` (Queries 2048/2050,
 *   ADR-023) — novas neste ciclo, ver `card-sets/actions.ts`.
 *
 * Cadastro de Card Set continua fora do escopo (`NovoCatalogoDialog`
 * mantido como estava — `admin_create_card_set()` ainda não existe).
 */
export function CatalogoGallery({
  jogos,
  expansoesDoJogo,
  expansoes,
  cardSetsOverview,
  gameCode,
  expansionCode,
  query,
  initialCardSets,
  initialHasMore,
  initialCards,
  mode,
}: {
  jogos: GameOption[];
  expansoesDoJogo: ExpansaoRow[];
  /** Lista completa, sem filtro/paginação — só para `CardSetsStats` (mesmo papel de `expansoes` em `ExpansoesStats`). */
  expansoes: ExpansaoRow[];
  /** Todos os Card Sets, sem filtro/paginação (via `getCardSetsOverview()`) — só para `CardSetsStats`. */
  cardSetsOverview: CardSetOverviewRow[];
  gameCode?: string;
  expansionCode?: string;
  query: string;
  initialCardSets: CardSetWithLogo[];
  initialHasMore: boolean;
  initialCards: CatalogoCardResult[];
  mode: "gallery" | "search";
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [novoOpen, setNovoOpen] = useState(false);
  const [cardSets, setCardSets] = useState(initialCardSets);
  const [cards, setCards] = useState(initialCards);
  const [hasMore, setHasMore] = useState(initialHasMore);
  const [isPending, startTransition] = useTransition();

  // Sincroniza com o lote inicial sempre que o servidor manda um novo
  // (busca, filtro ou navegação) — mesmo cuidado de `expansoes-gallery.tsx`
  // para nunca misturar itens de "Carregar mais" de um contexto anterior.
  useEffect(() => {
    setCardSets(initialCardSets);
    setCards(initialCards);
    setHasMore(initialHasMore);
  }, [initialCardSets, initialCards, initialHasMore]);

  const editingCardSet = cardSets.find((set) => set.id === state.editingId) ?? null;
  const cardSetToDelete = cardSets.find((set) => state.selectedIds.has(set.id)) ?? null;

  function handleLoadMore() {
    startTransition(async () => {
      if (mode === "search") {
        const result = await searchCatalogoAction({ query, cardsOffset: cards.length });
        setCards((prev) => [...prev, ...result.cards]);
        setHasMore(result.hasMoreCards);
      } else {
        const result = await loadMoreCardSets({ gameCode, expansionCode, offset: cardSets.length });
        setCardSets((prev) => [...prev, ...result.items]);
        setHasMore(result.hasMore);
      }
    });
  }

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  function handleDeleted() {
    state.onSuccess("Card Set excluído com sucesso.");
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <div className="flex items-center gap-2">
            <Boxes className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Coleções</PageTitle>
          </div>
          <PageDescription>Explore os Card Sets catalogados, por Jogo ou por busca direta.</PageDescription>
        </PageHeading>
      </PageHeader>

      <CardSetsStats jogos={jogos} expansoes={expansoes} cardSets={cardSetsOverview} />

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      {state.confirmingDelete && cardSetToDelete && (
        <ConfirmDeleteBar
          items={[{ id: cardSetToDelete.id, label: `${cardSetToDelete.name} (${cardSetToDelete.code})` }]}
          action={deleteCardSets}
          nounSingular="card set"
          nounPlural="card sets"
          onDone={handleDeleted}
          onPartialSuccess={() => router.refresh()}
          onCancel={state.cancelConfirmDelete}
        />
      )}

      <div className="space-y-2">
        <div className="flex justify-end">
          <Button type="button" size="sm" onClick={() => setNovoOpen(true)}>
            <Plus className="h-3.5 w-3.5" />
            Novo
          </Button>
        </div>

        <Card density="compact" className="overflow-hidden">
          <div className="flex items-center gap-2 border-b border-border p-4">
            <div className="min-w-0 flex-1">
              <CatalogoSearchBar initialQuery={query} className="h-9 bg-surface-muted text-xs" />
            </div>
            <CatalogoFilterSelect
              jogos={jogos}
              expansoesDoJogo={expansoesDoJogo}
              gameCode={gameCode}
              expansionCode={expansionCode}
              query={query}
              className="h-9 bg-surface-muted text-xs"
            />
          </div>

          {/* `pt-4` explícito, mesmo motivo de `expansoes-gallery.tsx`:
              `CardContent density="compact"` não tem padding-top por
              padrão — sem ele, a primeira linha de cards ficava colada na
              borda inferior da busca. */}
          <CardContent density="compact" className="pt-4">
            {mode === "search" ? (
              cardSets.length === 0 && cards.length === 0 ? (
                <EmptyState
                  title={`Nenhum resultado para "${query}"`}
                  description="Tente outro nome, código ou número de coleção."
                />
              ) : (
                <div className="space-y-6">
                  {cardSets.length > 0 && (
                    <section className="space-y-2">
                      <h2 className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Card Sets</h2>
                      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
                        {cardSets.map((set) => (
                          <CardSetGalleryCard
                            key={set.id}
                            cardSet={set}
                            highlighted={state.highlightId === set.id}
                            onEdit={state.startEdit}
                            onQuickDelete={state.startQuickDelete}
                          />
                        ))}
                      </div>
                    </section>
                  )}

                  {cards.length > 0 && (
                    <section className="space-y-2">
                      <h2 className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Cartas</h2>
                      <div className="divide-y divide-border/60 rounded-lg border border-border">
                        {cards.map((card) => (
                          <Link
                            key={card.id}
                            href={`/catalogo/card-sets/${card.cardSetCode}`}
                            className="flex items-center justify-between px-4 py-2.5 text-sm transition-colors hover:bg-surface-muted"
                          >
                            <span className="text-foreground">{card.name}</span>
                            <span className="text-xs text-muted-foreground">
                              {card.cardSetName} · {card.collectorNumber} · {card.gameName}
                            </span>
                          </Link>
                        ))}
                      </div>
                    </section>
                  )}

                  {hasMore && (
                    <div className="flex justify-center">
                      <Button type="button" variant="outline" size="sm" onClick={handleLoadMore} disabled={isPending}>
                        {isPending ? "Carregando…" : "Carregar mais"}
                      </Button>
                    </div>
                  )}
                </div>
              )
            ) : cardSets.length === 0 ? (
              <EmptyState
                title="Nenhum Card Set cadastrado ainda"
                description='Use o botão "Novo" para começar a catalogar.'
              />
            ) : (
              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
                  {cardSets.map((set) => (
                    <CardSetGalleryCard
                      key={set.id}
                      cardSet={set}
                      highlighted={state.highlightId === set.id}
                      onEdit={state.startEdit}
                      onQuickDelete={state.startQuickDelete}
                    />
                  ))}
                </div>

                {hasMore && (
                  <div className="flex justify-center">
                    <Button type="button" variant="outline" size="sm" onClick={handleLoadMore} disabled={isPending}>
                      {isPending ? "Carregando…" : "Carregar mais"}
                    </Button>
                  </div>
                )}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <NovoCatalogoDialog open={novoOpen} onOpenChange={setNovoOpen} />

      <EditCardSetDialog
        open={editingCardSet !== null}
        cardSet={editingCardSet}
        onSaved={handleSaved}
        onCancel={state.cancelEdit}
      />
    </div>
  );
}
