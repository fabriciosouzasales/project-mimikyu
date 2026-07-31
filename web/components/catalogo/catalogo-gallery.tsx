"use client";

import { Plus } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { PageActions, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { CatalogoContent } from "@/components/catalogo/catalogo-content";
import { CatalogoFilterChips } from "@/components/catalogo/catalogo-filter-chips";
import { CatalogoSearchBar } from "@/components/catalogo/catalogo-search-bar";
import { NovoCatalogoDialog } from "@/components/catalogo/novo-catalogo-dialog";
import type { CardSetWithLogo } from "@/app/catalogo/card-sets/catalogo-actions";
import type { CatalogoCardResult, ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

/**
 * Composição raiz da tela Catálogo (spec aprovada 2026-07-31, ajustada em
 * 2026-07-31): cabeçalho, busca e filtros ficam fixos (sticky) e nunca
 * mudam de estrutura; só `CatalogoContent`, remontado via `key` a cada
 * combinação de modo/filtro/busca, troca entre galeria e resultado.
 */
export function CatalogoGallery({
  jogos,
  expansoesDoJogo,
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
  gameCode?: string;
  expansionCode?: string;
  query: string;
  initialCardSets: CardSetWithLogo[];
  initialHasMore: boolean;
  initialCards: CatalogoCardResult[];
  mode: "gallery" | "search";
}) {
  const [novoOpen, setNovoOpen] = useState(false);

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <PageTitle>Catálogo</PageTitle>
          <PageDescription>Explore os Card Sets catalogados, por Jogo ou por busca direta.</PageDescription>
        </PageHeading>
        <PageActions>
          <Button type="button" size="sm" onClick={() => setNovoOpen(true)}>
            <Plus className="h-3.5 w-3.5" />
            Novo
          </Button>
        </PageActions>
      </PageHeader>

      <div className="sticky top-0 z-10 -mx-1 space-y-3 bg-background px-1 pb-3 pt-1">
        <CatalogoSearchBar initialQuery={query} />
        <CatalogoFilterChips
          jogos={jogos}
          expansoesDoJogo={expansoesDoJogo}
          gameCode={gameCode}
          expansionCode={expansionCode}
          query={query}
        />
      </div>

      <CatalogoContent
        key={`${mode}-${gameCode ?? ""}-${expansionCode ?? ""}-${query}`}
        mode={mode}
        gameCode={gameCode}
        expansionCode={expansionCode}
        query={query}
        initialCardSets={initialCardSets}
        initialHasMore={initialHasMore}
        initialCards={initialCards}
      />

      <NovoCatalogoDialog open={novoOpen} onOpenChange={setNovoOpen} jogos={jogos} />
    </div>
  );
}
