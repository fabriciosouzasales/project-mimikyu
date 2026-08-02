"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { CardSetGalleryCard } from "@/components/catalogo/card-set-gallery-card";
import { searchCatalogoAction, type CardSetWithLogo } from "@/app/catalogo/card-sets/catalogo-actions";
import type { CatalogoCardResult } from "@/lib/catalogo/queries";

/**
 * SEM USO desde 2026-07-31 (pedido de Fabrício: "faça todos os ajustes
 * necessários para manter o mesmo padrão da página Expansões") — a lógica
 * deste componente foi absorvida diretamente por `catalogo-gallery.tsx`,
 * espelhando `expansoes-gallery.tsx` (que nunca teve essa divisão em dois
 * arquivos). Não removido: o mount do projeto não suporta `unlink()` (ver
 * memória do projeto) — arquivos sem uso ficam marcados, não apagados.
 *
 * Ajuste 2026-08-02: `loadMoreCardSets` (Server Action) foi removida de
 * `catalogo-actions.ts` — o modo galeria da tela real passou a carregar
 * tudo de uma vez, agrupado por Expansão (`getCardSetsGroupedByExpansion()`,
 * ver `catalogo-gallery.tsx`), sem paginação incremental. Este arquivo (sem
 * uso) só precisava continuar compilando; o ramo `else` de `handleLoadMore`
 * (modo galeria) virou um no-op — nunca executado, já que nada monta este
 * componente.
 *
 * Área de conteúdo da tela Catálogo — spec aprovada 2026-07-31, com o ajuste
 * de "Carregar mais" no lugar de rolagem infinita. Cabeçalho/busca/filtros
 * (fora deste componente) nunca mudam; só isto aqui troca entre galeria e
 * resultado de busca. Remontado (via `key` no componente pai) sempre que
 * modo/filtro/busca mudam, para nunca acumular itens de um contexto anterior.
 */
export function CatalogoContent({
  mode,
  gameCode,
  expansionCode,
  query,
  initialCardSets,
  initialHasMore,
  initialCards,
}: {
  mode: "gallery" | "search";
  gameCode?: string;
  expansionCode?: string;
  query: string;
  initialCardSets: CardSetWithLogo[];
  initialHasMore: boolean;
  initialCards: CatalogoCardResult[];
}) {
  const [cardSets, setCardSets] = useState(initialCardSets);
  const [cards, setCards] = useState(initialCards);
  const [hasMore, setHasMore] = useState(initialHasMore);
  const [isPending, startTransition] = useTransition();

  function handleLoadMore() {
    startTransition(async () => {
      if (mode === "search") {
        const result = await searchCatalogoAction({ query, cardsOffset: cards.length });
        setCards((prev) => [...prev, ...result.cards]);
        setHasMore(result.hasMoreCards);
      }
      // Modo galeria: no-op — ver nota no topo do arquivo (componente sem
      // uso, `loadMoreCardSets` removida junto com a paginação flat real).
    });
  }

  if (mode === "search") {
    if (cardSets.length === 0 && cards.length === 0) {
      return (
        <EmptyState
          title={`Nenhum resultado para "${query}"`}
          description="Tente outro nome, código ou número de coleção."
        />
      );
    }

    return (
      <div className="space-y-6">
        {cardSets.length > 0 && (
          <section className="space-y-2">
            <h2 className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Card Sets</h2>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
              {cardSets.map((set) => (
                // Placeholder de props só para o compilador — componente
                // sem uso (ver nota no topo do arquivo).
                <CardSetGalleryCard
                  key={set.id}
                  cardSet={set}
                  highlighted={false}
                  onEdit={() => {}}
                  onQuickDelete={() => {}}
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
    );
  }

  if (cardSets.length === 0) {
    return (
      <EmptyState
        title="Nenhum Card Set cadastrado ainda"
        description='Use o botão "Novo" para começar a catalogar.'
      />
    );
  }

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
        {cardSets.map((set) => (
          <CardSetGalleryCard
            key={set.id}
            cardSet={set}
            highlighted={false}
            onEdit={() => {}}
            onQuickDelete={() => {}}
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
  );
}
