"use client";

import { Plus } from "lucide-react";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { loadMoreExpansoes, searchExpansoesAction } from "@/app/catalogo/expansoes/catalogo-actions";
import { CreateExpansionDialog, EditExpansionDialog } from "@/components/catalogo/expansoes-table";
import { CatalogoFilterChips } from "@/components/catalogo/catalogo-filter-chips";
import { CatalogoSearchBar } from "@/components/catalogo/catalogo-search-bar";
import { ExpansaoGalleryCard } from "@/components/catalogo/expansao-gallery-card";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { PageActions, PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

/**
 * Redesenho da tela de Expansões (2026-07-31) usando exatamente a mesma
 * linguagem visual/comportamento da tela Catálogo (Card Sets): cabeçalho +
 * ação fixos, busca e filtro de Jogo em barra fixa, galeria de cards,
 * "Carregar mais", estados vazio/carregamento no mesmo formato. Único chip
 * de Jogo (sem segundo nível de Expansão — filtrar Expansão dentro da
 * própria tela de Expansões seria circular).
 *
 * Cadastro/edição continuam nos mesmos Dialogs já existentes
 * (`CreateExpansionDialog`/`EditExpansionDialog`, agora exportados) — sem
 * página de detalhe própria para Expansion, editar é abrir o Dialog a
 * partir do card, não navegar.
 */
export function ExpansoesGallery({
  jogos,
  gameCode,
  query,
  mode,
  defaultGameId,
  initialItems,
  initialHasMore,
}: {
  jogos: GameOption[];
  gameCode?: string;
  query: string;
  mode: "gallery" | "search";
  defaultGameId?: string;
  initialItems: ExpansaoRow[];
  initialHasMore: boolean;
}) {
  const router = useRouter();
  const state = useAdminListState();
  const [items, setItems] = useState(initialItems);
  const [hasMore, setHasMore] = useState(initialHasMore);
  const [isPending, startTransition] = useTransition();

  // Sincroniza com o lote inicial sempre que o servidor manda um novo
  // (busca, filtro de Jogo ou navegação) — evita misturar itens carregados
  // via "Carregar mais" de um contexto anterior com o novo.
  useEffect(() => {
    setItems(initialItems);
    setHasMore(initialHasMore);
  }, [initialItems, initialHasMore]);

  const editingExpansao = items.find((item) => item.id === state.editingId) ?? null;

  function handleLoadMore() {
    startTransition(async () => {
      const result =
        mode === "search"
          ? await searchExpansoesAction({ query, offset: items.length })
          : await loadMoreExpansoes({ gameCode, offset: items.length });
      setItems((prev) => [...prev, ...result.items]);
      setHasMore(result.hasMore);
    });
  }

  function handleSaved(message: string, id?: string) {
    state.onSuccess(message, id);
    router.refresh();
  }

  return (
    <div className="space-y-4">
      <PageHeader>
        <PageHeading>
          <PageTitle>Expansões</PageTitle>
          <PageDescription>Explore as Expansões catalogadas, por Jogo ou por busca direta.</PageDescription>
        </PageHeading>
        <PageActions>
          <Button type="button" size="sm" onClick={state.startCreate}>
            <Plus className="h-3.5 w-3.5" />
            Nova expansão
          </Button>
        </PageActions>
      </PageHeader>

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <div className="sticky top-0 z-10 -mx-1 space-y-3 bg-background px-1 pb-3 pt-1">
        <CatalogoSearchBar initialQuery={query} placeholder="Buscar por nome ou código da Expansão…" />
        <CatalogoFilterChips
          jogos={jogos}
          expansoesDoJogo={[]}
          gameCode={gameCode}
          query={query}
          basePath="/catalogo/expansoes"
        />
      </div>

      {items.length === 0 ? (
        mode === "search" ? (
          <EmptyState title={`Nenhum resultado para "${query}"`} description="Tente outro nome ou código." />
        ) : (
          <EmptyState
            title="Nenhuma Expansão cadastrada ainda"
            description='Use o botão "Nova expansão" para começar.'
          />
        )
      ) : (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
            {items.map((expansao) => (
              <ExpansaoGalleryCard
                key={expansao.id}
                expansao={expansao}
                highlighted={state.highlightId === expansao.id}
                onEdit={state.startEdit}
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
      />
    </div>
  );
}
