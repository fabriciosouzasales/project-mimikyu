"use client";

import { Layers, Plus } from "lucide-react";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { loadMoreExpansoes, searchExpansoesAction } from "@/app/catalogo/expansoes/catalogo-actions";
import { CreateExpansionDialog, EditExpansionDialog } from "@/components/catalogo/expansoes-table";
import { CatalogoFilterSelect } from "@/components/catalogo/catalogo-filter-select";
import { CatalogoSearchBar } from "@/components/catalogo/catalogo-search-bar";
import { ExpansaoGalleryCard } from "@/components/catalogo/expansao-gallery-card";
import { ExpansoesStats } from "@/components/catalogo/expansoes-stats";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { InlineFeedback } from "@/components/ui/feedback";
import { PageDescription, PageHeader, PageHeading, PageTitle } from "@/components/ui/page";
import { useAdminListState } from "@/hooks/use-admin-list-state";
import type { ExpansaoRow, GameOption } from "@/lib/catalogo/queries";

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
 * tela Jogos. A galeria de cards abaixo **não muda** nesta rodada — pedido
 * explícito de Fabrício para tratar isso numa próxima etapa.
 *
 * Cadastro/edição continuam nos mesmos Dialogs já existentes
 * (`CreateExpansionDialog`/`EditExpansionDialog`, agora exportados) — sem
 * página de detalhe própria para Expansion, editar é abrir o Dialog a
 * partir do card, não navegar.
 */
export function ExpansoesGallery({
  jogos,
  expansoes,
  gameCode,
  query,
  mode,
  defaultGameId,
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
          <div className="flex items-center gap-2">
            <Layers className="h-5 w-5 text-muted-foreground" aria-hidden="true" />
            <PageTitle>Expansões</PageTitle>
          </div>
          <PageDescription>Explore as Expansões catalogadas, por Jogo ou por busca direta.</PageDescription>
        </PageHeading>
      </PageHeader>

      <ExpansoesStats expansoes={expansoes} />

      {state.successMessage && <InlineFeedback tone="success">{state.successMessage}</InlineFeedback>}

      <div className="space-y-2">
        <div className="flex justify-end">
          <Button type="button" size="sm" onClick={state.startCreate}>
            <Plus className="h-3.5 w-3.5" />
            Nova expansão
          </Button>
        </div>

        <div className="sticky top-0 z-10 -mx-1 flex items-center gap-2 bg-background px-1 pb-3 pt-1">
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
