"use client";

import { useCallback, useEffect, useRef, useState, type CSSProperties } from "react";
import { flushSync } from "react-dom";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Search, SlidersHorizontal, ChevronDown, X } from "lucide-react";
import { CardImagePreview } from "@/components/card/card-image-preview";
import { CardPreviewOverlay } from "@/components/card/card-preview-overlay";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/alert";
import { EmptyState } from "@/components/ui/empty-state";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { cardImageUrl, cartaFullNumber, type PesquisaCard } from "@/lib/pesquisa/format";
import { canUseViewTransitions, cardImagePreviewTransitionName, runWithViewTransition } from "@/lib/view-transitions";

const PAGE_SIZE = 36;

type FilterOption = { code: string; name: string; symbolCode?: string };
type FilterOptions = {
  cardSets: FilterOption[];
  categories: FilterOption[];
  rarities: FilterOption[];
};

type SearchResponse = { cards: PesquisaCard[]; totalCount: number; hasMore: boolean };

/**
 * Corpo client-side de `/pesquisa` — estado (busca, filtros, paginação) 100%
 * derivado da URL (`q`/`card`/`set`/`category`/`rarity`), conforme ADR-030.
 * Sem filtro de Jogo nesta versão — decisão de escopo explícita, não integra
 * a interface, a URL nem o contrato público (`search_cards`/
 * `search_card_filter_options`, ver migrations 4030/4031). Reaproveita
 * `Input`/`Select`/`EmptyState`/`Skeleton` (STD-004) — não reescreve
 * `CartasGallery` (galeria administrativa): formatação e URL de imagem vêm
 * de `lib/pesquisa/format.ts`.
 *
 * Preview ampliado (2026-08-17, pedido de Fabrício: "o preview de cartas em
 * Pesquisa deve ser estruturalmente compartilhado com Cartas, não apenas
 * visualmente parecido") — usa exatamente o mesmo `CardPreviewOverlay`/
 * `CardImagePreview` (`components/card/`) que `CartaZoomDialog` na galeria
 * administrativa: mesmo `HoloCard` com motion senoidal (`floating`), mesma
 * sombra/backdrop, mesmo morph via View Transitions API quando disponível
 * (`lib/view-transitions.ts`, mesmo mecanismo de `CartasGallery`), sem
 * rodapé de texto (nome/Card Set/raridade removido — `Cartas` nunca teve
 * um). Substitui o `Dialog` estático anterior, que reimplementava a
 * apresentação da carta ampliada do zero (ver `docs/adr/ADR-030-card-search-projection.md`,
 * seção "Preview compartilhado de carta").
 */
export function PesquisaView() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const q = searchParams.get("q") ?? "";
  const cardId = searchParams.get("card");
  const setCode = searchParams.get("set") ?? "";
  const categoryCode = searchParams.get("category") ?? "";
  const rarityCode = searchParams.get("rarity") ?? "";

  const hasAdvancedFilters = Boolean(setCode || categoryCode || rarityCode);

  const [queryInput, setQueryInput] = useState(q);
  const [advancedOpen, setAdvancedOpen] = useState(hasAdvancedFilters);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [filterOptions, setFilterOptions] = useState<FilterOptions | null>(null);
  const [filterOptionsLoading, setFilterOptionsLoading] = useState(true);

  const [cards, setCards] = useState<PesquisaCard[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState(false);
  const [zoomCard, setZoomCard] = useState<PesquisaCard | null>(null);
  // Qual carta, entre as do grid, empresta seu `viewTransitionName` para o
  // morph em andamento — mesmo princípio de `transitionTargetId` em
  // `CartasGallery` (ver `openZoom`/`closeZoom` abaixo e `lib/view-transitions.ts`).
  const [transitionTargetId, setTransitionTargetId] = useState<string | null>(null);

  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => setQueryInput(q), [q]);

  // Opções de filtro — carregadas uma única vez (sem Jogo, abrangem todos os
  // Card Sets/Categorias/Raridades ativos, sem escopo por Jogo nesta versão).
  useEffect(() => {
    setFilterOptionsLoading(true);
    fetch("/api/cards/filter-options")
      .then((res) => (res.ok ? (res.json() as Promise<FilterOptions>) : Promise.reject()))
      .then(setFilterOptions)
      .catch(() => setFilterOptions(null))
      .finally(() => setFilterOptionsLoading(false));
  }, []);

  const buildSearchParams = useCallback(
    (offset: number) => {
      const params = new URLSearchParams();
      if (q) params.set("q", q);
      if (cardId) params.set("card", cardId);
      if (setCode) params.set("set", setCode);
      if (categoryCode) params.set("category", categoryCode);
      if (rarityCode) params.set("rarity", rarityCode);
      params.set("limit", String(PAGE_SIZE));
      params.set("offset", String(offset));
      return params;
    },
    [q, cardId, setCode, categoryCode, rarityCode],
  );

  // Busca principal — refeita a cada mudança de parâmetro na URL, sempre do zero (offset 0).
  useEffect(() => {
    abortRef.current?.abort();

    if (!q && !cardId && !setCode && !categoryCode && !rarityCode) {
      setCards([]);
      setTotalCount(0);
      setHasMore(false);
      setLoading(false);
      setError(false);
      return;
    }

    const controller = new AbortController();
    abortRef.current = controller;
    setLoading(true);
    setError(false);

    fetch(`/api/cards/search?${buildSearchParams(0).toString()}`, { signal: controller.signal })
      .then((res) => {
        if (!res.ok) throw new Error("search_failed");
        return res.json() as Promise<SearchResponse>;
      })
      .then((data) => {
        setCards(data.cards);
        setTotalCount(data.totalCount);
        setHasMore(data.hasMore);
      })
      .catch((err) => {
        if (err instanceof DOMException && err.name === "AbortError") return;
        setError(true);
        setCards([]);
        setTotalCount(0);
        setHasMore(false);
      })
      .finally(() => setLoading(false));

    return () => controller.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, cardId, setCode, categoryCode, rarityCode]);

  function loadMore() {
    setLoadingMore(true);
    fetch(`/api/cards/search?${buildSearchParams(cards.length).toString()}`)
      .then((res) => {
        if (!res.ok) throw new Error("search_failed");
        return res.json() as Promise<SearchResponse>;
      })
      .then((data) => {
        setCards((prev) => [...prev, ...data.cards]);
        setHasMore(data.hasMore);
      })
      .catch(() => setError(true))
      .finally(() => setLoadingMore(false));
  }

  function updateParams(mutate: (params: URLSearchParams) => void) {
    const params = new URLSearchParams(searchParams.toString());
    // A carta fixada (`card`) só faz sentido junto do termo que a originou —
    // qualquer alteração manual de filtro/busca a partir daqui descarta o pin.
    params.delete("card");
    mutate(params);
    router.replace(`${pathname}${params.toString() ? `?${params.toString()}` : ""}`);
  }

  function handleQueryChange(next: string) {
    setQueryInput(next);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      updateParams((params) => {
        if (next.trim()) params.set("q", next.trim());
        else params.delete("q");
      });
    }, 300);
  }

  function handleFilterChange(key: "set" | "category" | "rarity", next: string) {
    updateParams((params) => {
      if (next) params.set(key, next);
      else params.delete(key);
    });
  }

  function handleClear() {
    setQueryInput("");
    router.replace(pathname);
  }

  // Abertura/fechamento do preview ampliado — mesmo mecanismo de
  // `openZoom`/`closeZoom` em `CartasGallery`: `flushSync` marca a carta-alvo
  // ANTES do `startViewTransition` capturar o snapshot "antigo" (sem isso,
  // a miniatura ainda estaria sem o `viewTransitionName` no instante em que
  // o navegador olha o DOM), depois `runWithViewTransition` troca o estado
  // dentro do callback que o navegador usa para morfar entre os dois
  // snapshots.
  function openZoom(card: PesquisaCard) {
    flushSync(() => setTransitionTargetId(card.id));
    runWithViewTransition(() => setZoomCard(card));
  }

  function closeZoom() {
    runWithViewTransition(() => setZoomCard(null));
    setTransitionTargetId(null);
  }

  const hasAnyParam = Boolean(q || cardId || setCode || categoryCode || rarityCode);

  return (
    <div className="mx-auto max-w-6xl">
      <div className="mb-6">
        <div className="flex items-center gap-2">
          <Search className="h-5 w-5 shrink-0 text-muted-foreground" aria-hidden="true" />
          <h1 className="font-heading text-xl font-medium text-foreground">Pesquisa avançada</h1>
        </div>
        <p className="mt-1 text-sm text-muted-foreground">
          Pesquise cartas por nome, número de colecionador ou código do Card Set, e refine por Card Set, Categoria e
          Raridade.
        </p>
      </div>

      <div className="space-y-3 rounded-lg border border-border bg-surface p-4">
        <div className="relative">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={queryInput}
            onChange={(event) => handleQueryChange(event.target.value)}
            placeholder="Pesquisar cartas…"
            aria-label="Pesquisar cartas por nome, número ou código do Card Set"
            className="pl-9"
          />
        </div>

        <div>
          <button
            type="button"
            onClick={() => setAdvancedOpen((prev) => !prev)}
            className="flex items-center gap-1.5 text-sm font-medium text-muted-foreground hover:text-foreground"
            aria-expanded={advancedOpen}
            aria-controls="pesquisa-filtros-avancados"
          >
            <SlidersHorizontal className="h-3.5 w-3.5" aria-hidden="true" />
            Filtros avançados
            <ChevronDown className={cn("h-3.5 w-3.5 transition-transform", advancedOpen && "rotate-180")} />
          </button>
        </div>

        {advancedOpen && (
          <div id="pesquisa-filtros-avancados" className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div>
              <label className="mb-1 block text-xs font-medium text-muted-foreground">Card Set</label>
              <Select
                value={setCode}
                onChange={(event) => handleFilterChange("set", event.target.value)}
                disabled={filterOptionsLoading || !filterOptions}
              >
                <option value="">Todos os Card Sets</option>
                {filterOptions?.cardSets.map((set) => (
                  <option key={set.code} value={set.code}>
                    {set.name} ({set.code})
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-muted-foreground">Categoria</label>
              <Select
                value={categoryCode}
                onChange={(event) => handleFilterChange("category", event.target.value)}
                disabled={filterOptionsLoading || !filterOptions}
              >
                <option value="">Todas as categorias</option>
                {filterOptions?.categories.map((category) => (
                  <option key={category.code} value={category.code}>
                    {category.name}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label className="mb-1 block text-xs font-medium text-muted-foreground">Raridade</label>
              <Select
                value={rarityCode}
                onChange={(event) => handleFilterChange("rarity", event.target.value)}
                disabled={filterOptionsLoading || !filterOptions}
              >
                <option value="">Todas as raridades</option>
                {filterOptions?.rarities.map((rarity) => (
                  <option key={rarity.code} value={rarity.code}>
                    {rarity.name}
                  </option>
                ))}
              </Select>
            </div>
          </div>
        )}

        {hasAnyParam && (
          <div>
            <Button type="button" variant="ghost" size="sm" onClick={handleClear}>
              <X className="h-3.5 w-3.5" />
              Limpar
            </Button>
          </div>
        )}
      </div>

      <div className="mt-4">
        {!loading && !error && hasAnyParam && (
          <p className="mb-3 text-sm text-muted-foreground">
            {totalCount === 0 ? "Nenhum resultado" : `${totalCount} ${totalCount === 1 ? "resultado" : "resultados"}`}
          </p>
        )}

        {error ? (
          <Alert variant="destructive">Não foi possível buscar agora. Tente novamente.</Alert>
        ) : !hasAnyParam ? (
          <EmptyState
            icon={Search}
            title="Comece pesquisando"
            description="Digite um nome, número de colecionador ou código de Card Set, ou use os filtros acima."
          />
        ) : loading ? (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
            {Array.from({ length: 12 }).map((_, index) => (
              <Skeleton key={index} className="aspect-[5/7] w-full rounded-lg" />
            ))}
          </div>
        ) : cards.length === 0 ? (
          <EmptyState title="Nenhuma carta encontrada" description="Tente outro termo ou ajuste os filtros." />
        ) : (
          <>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6">
              {cards.map((card) => (
                <PesquisaCardTile
                  key={card.id}
                  card={card}
                  onZoom={() => openZoom(card)}
                  isTransitionSource={transitionTargetId === card.id && zoomCard?.id !== card.id}
                />
              ))}
            </div>
            {hasMore && (
              <div className="mt-6 flex justify-center">
                <Button type="button" variant="outline" onClick={loadMore} disabled={loadingMore}>
                  {loadingMore ? "Carregando…" : "Carregar mais"}
                </Button>
              </div>
            )}
          </>
        )}
      </div>

      <CardPreviewOverlay
        open={Boolean(zoomCard)}
        onClose={closeZoom}
        title={zoomCard?.name ?? "Carta"}
        useViewTransition={canUseViewTransitions()}
      >
        {zoomCard && (
          <CardImagePreview
            imageUrl={cardImageUrl(zoomCard)}
            alt={zoomCard.name}
            viewTransitionName={cardImagePreviewTransitionName(zoomCard.id)}
          />
        )}
      </CardPreviewOverlay>
    </div>
  );
}

function PesquisaCardTile({
  card,
  onZoom,
  isTransitionSource,
}: {
  card: PesquisaCard;
  onZoom: () => void;
  isTransitionSource: boolean;
}) {
  const imageUrl = cardImageUrl(card);
  return (
    <button
      type="button"
      onClick={onZoom}
      className="group flex flex-col gap-1.5 rounded-lg text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      aria-label={`Ampliar ${card.name}`}
    >
      <div
        className="aspect-[5/7] w-full overflow-hidden rounded-lg border border-border bg-surface-muted"
        style={
          { viewTransitionName: isTransitionSource ? cardImagePreviewTransitionName(card.id) : "none" } as CSSProperties
        }
      >
        {imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={imageUrl}
            alt={card.name}
            className="h-full w-full object-cover transition-transform group-hover:scale-[1.02]"
            loading="lazy"
          />
        ) : (
          <div className="flex h-full w-full items-center justify-center">
            <Search className="h-6 w-6 text-muted-foreground/30" aria-hidden="true" />
          </div>
        )}
      </div>
      <div className="min-w-0">
        <p className="truncate text-xs font-medium text-foreground">{card.name}</p>
        <p className="truncate text-[11px] text-muted-foreground">
          {card.cardSet.code} · {cartaFullNumber(card.collectorNumber, card.collectorTotal)}
        </p>
      </div>
    </button>
  );
}
