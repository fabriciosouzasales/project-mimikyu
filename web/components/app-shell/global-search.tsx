"use client";

import { useEffect, useId, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Search, SlidersHorizontal, Loader2, X } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { cardImageUrl, cartaFullNumber, type PesquisaCard } from "@/lib/pesquisa/format";

const DEBOUNCE_MS = 280;
const MAX_SUGGESTIONS = 8;

type SearchResponse = { cards: PesquisaCard[]; totalCount: number; hasMore: boolean };
type SearchStatus = "idle" | "loading" | "success" | "error";

/**
 * Combobox global de pesquisa de cartas — Incremento "Pesquisa Global de
 * Cartas" (2026-08-17, ver ADR-030). Disponível a qualquer usuário
 * autenticado, integrado ao `Header` (renderizado para toda página via
 * `AppShell`). Desktop: `SearchCombobox` inline entre título e ações do
 * header, com dropdown flutuante. Mobile: `MobileSearchOverlay` — modo
 * imersivo dedicado que **substitui** o conteúdo do header (não um dropdown
 * nem um drawer), inspirado funcionalmente no pkmn.gg (pedido explícito de
 * Fabrício, 2026-08-17: "a referência funcional é o pkmn.gg... Não copiar
 * logotipo, cores ou proporções do pkmn.gg" — só o COMPORTAMENTO de
 * transformação do header foi usado como referência, identidade visual
 * MMKYU integralmente preservada).
 *
 * `useCardSearchSuggestions` (abaixo) concentra toda a lógica de busca
 * (debounce, `AbortController`, descarte de resposta obsoleta, navegação) —
 * consumida por ambas as apresentações, que só decidem COMO renderizar o
 * resultado (dropdown flutuante vs. painel de tela cheia).
 */
export function GlobalSearch() {
  return (
    <>
      <div className="hidden md:flex flex-1 justify-center px-4">
        <div className="w-full max-w-sm">
          <SearchCombobox />
        </div>
      </div>
      <MobileSearchOverlay />
    </>
  );
}

/**
 * Estado e lógica de busca de sugestões — extraído em 2026-08-17 do antigo
 * `SearchCombobox` (que atendia desktop E mobile via prop `variant`) para
 * ser reutilizado sem duplicação pelo novo modo imersivo mobile
 * (`MobileSearchOverlay`), que precisa de uma apresentação estruturalmente
 * diferente (painel de tela cheia sempre visível, não um dropdown que abre/
 * fecha). `open`/`setOpen` seguem aqui porque o dropdown do desktop precisa
 * dessa noção (abre ao digitar, fecha ao limpar/Escape/clique fora); o
 * painel mobile simplesmente ignora esses dois campos, derivando o que
 * mostrar diretamente de `status`/`query`/`cards` (ver `mobileSearchPhase`
 * em `MobileSearchOverlay`).
 */
function useCardSearchSuggestions({ onNavigate }: { onNavigate?: () => void } = {}) {
  const router = useRouter();
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  const [query, setQuery] = useState("");
  const [cards, setCards] = useState<PesquisaCard[]>([]);
  const [status, setStatus] = useState<SearchStatus>("idle");
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
      abortRef.current?.abort();
    };
  }, []);

  function fetchSuggestions(term: string) {
    abortRef.current?.abort();
    if (!term.trim()) {
      setCards([]);
      setStatus("idle");
      setOpen(false);
      return;
    }
    const controller = new AbortController();
    abortRef.current = controller;
    setStatus("loading");
    setOpen(true);

    fetch(`/api/cards/search?q=${encodeURIComponent(term.trim())}&limit=${MAX_SUGGESTIONS}`, {
      signal: controller.signal,
    })
      .then((res) => {
        if (!res.ok) throw new Error("search_failed");
        return res.json() as Promise<SearchResponse>;
      })
      .then((data) => {
        setCards(data.cards.slice(0, MAX_SUGGESTIONS));
        setStatus("success");
        setActiveIndex(-1);
      })
      .catch((err) => {
        if (err instanceof DOMException && err.name === "AbortError") return;
        setStatus("error");
        setCards([]);
      });
  }

  function handleChange(next: string) {
    setQuery(next);
    setActiveIndex(-1);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => fetchSuggestions(next), DEBOUNCE_MS);
  }

  function moveActive(direction: 1 | -1) {
    setActiveIndex((prev) => (cards.length === 0 ? -1 : (prev + direction + cards.length) % cards.length));
  }

  function goToAdvancedSearch(term: string = query) {
    const params = new URLSearchParams();
    if (term.trim()) params.set("q", term.trim());
    setOpen(false);
    onNavigate?.();
    router.push(`/pesquisa${params.toString() ? `?${params.toString()}` : ""}`);
  }

  function selectCard(card: PesquisaCard) {
    const params = new URLSearchParams();
    params.set("card", card.id);
    if (query.trim()) params.set("q", query.trim());
    setOpen(false);
    onNavigate?.();
    router.push(`/pesquisa?${params.toString()}`);
  }

  /** Cancela requisição/debounce pendentes e zera tudo — usado ao fechar o modo imersivo mobile. */
  function reset() {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    abortRef.current?.abort();
    setQuery("");
    setCards([]);
    setStatus("idle");
    setOpen(false);
    setActiveIndex(-1);
  }

  return {
    query,
    cards,
    status,
    open,
    setOpen,
    activeIndex,
    setActiveIndex,
    handleChange,
    moveActive,
    goToAdvancedSearch,
    selectCard,
    reset,
  };
}

/**
 * Combobox inline do desktop — dropdown flutuante clássico. Padrão ARIA
 * combobox/listbox (`aria-activedescendant`, sem mover o foco real do DOM
 * para as opções). Comportamento idêntico ao existente antes da extração de
 * `useCardSearchSuggestions` (2026-08-17) — só a lógica de busca mudou de
 * lugar, não o resultado visual/funcional.
 */
function SearchCombobox() {
  const listboxId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const {
    query,
    cards,
    status,
    open,
    setOpen,
    activeIndex,
    setActiveIndex,
    handleChange,
    moveActive,
    goToAdvancedSearch,
    selectCard,
  } = useCardSearchSuggestions();

  // Fecha ao clicar fora do combobox.
  useEffect(() => {
    if (!open) return;
    function handlePointerDown(event: PointerEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, [open, setOpen]);

  function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      if (!open && cards.length > 0) setOpen(true);
      moveActive(1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (!open && cards.length > 0) setOpen(true);
      moveActive(-1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (open && activeIndex >= 0 && cards[activeIndex]) {
        selectCard(cards[activeIndex]);
      } else if (query.trim()) {
        goToAdvancedSearch(query);
      }
    } else if (event.key === "Escape") {
      if (open) {
        event.preventDefault();
        event.stopPropagation();
        setOpen(false);
        setActiveIndex(-1);
      }
    }
  }

  const activeOptionId = activeIndex >= 0 ? `${listboxId}-option-${activeIndex}` : undefined;
  const showDropdown = Boolean(
    open && (status === "loading" || status === "error" || cards.length > 0 || (status === "success" && query.trim())),
  );

  return (
    <div ref={containerRef} className="relative">
      <div className="relative flex items-center">
        <Search className="pointer-events-none absolute left-3 h-4 w-4 text-muted-foreground" aria-hidden="true" />
        <Input
          ref={inputRef}
          value={query}
          onChange={(event) => handleChange(event.target.value)}
          onKeyDown={handleKeyDown}
          onFocus={() => {
            if (cards.length > 0) setOpen(true);
          }}
          placeholder="Pesquisar cartas…"
          role="combobox"
          aria-expanded={showDropdown}
          aria-controls={listboxId}
          aria-activedescendant={activeOptionId}
          aria-autocomplete="list"
          aria-label="Pesquisar cartas por nome, número ou código do Card Set"
          autoComplete="off"
          enterKeyHint="search"
          className="h-9 pl-9 pr-9 text-sm"
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="absolute right-0.5 h-8 w-8"
          title="Abrir pesquisa avançada"
          aria-label="Abrir pesquisa avançada"
          onClick={() => goToAdvancedSearch(query)}
        >
          <SlidersHorizontal className="h-4 w-4" />
        </Button>
      </div>

      {showDropdown && (
        <ul
          id={listboxId}
          role="listbox"
          aria-label="Sugestões de cartas"
          className="absolute z-50 mt-1 max-h-96 w-full overflow-y-auto rounded-lg border border-border bg-surface py-1 shadow-panel"
        >
          {status === "loading" && (
            <li className="flex items-center gap-2 px-3 py-2 text-sm text-muted-foreground">
              <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />
              Buscando…
            </li>
          )}
          {status === "error" && (
            <li className="px-3 py-2 text-sm text-destructive">Não foi possível buscar agora. Tente novamente.</li>
          )}
          {status === "success" && cards.length === 0 && (
            <li className="px-3 py-2 text-sm text-muted-foreground">Nenhuma carta encontrada.</li>
          )}
          {cards.map((card, index) => {
            const imageUrl = cardImageUrl(card);
            const isActive = index === activeIndex;
            return (
              <li
                key={card.id}
                id={`${listboxId}-option-${index}`}
                role="option"
                aria-selected={isActive}
                onMouseDown={(event) => {
                  event.preventDefault();
                  selectCard(card);
                }}
                onMouseEnter={() => setActiveIndex(index)}
                className={cn(
                  "flex cursor-pointer items-center gap-2.5 px-3 py-1.5 text-sm",
                  isActive ? "bg-accent" : "hover:bg-surface-muted",
                )}
              >
                <div className="flex h-9 w-7 shrink-0 items-center justify-center overflow-hidden rounded bg-surface-muted">
                  {imageUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={imageUrl} alt="" className="h-full w-full object-cover" />
                  ) : (
                    <Search className="h-3 w-3 text-muted-foreground/40" aria-hidden="true" />
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium text-foreground">{card.name}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {card.cardSet.code} · {cartaFullNumber(card.collectorNumber, card.collectorTotal)}
                  </p>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

/**
 * Modo imersivo de pesquisa mobile — reescrito por completo em 2026-08-17
 * (pedido de Fabrício, referência funcional pkmn.gg): ao tocar na lupa, o
 * PRÓPRIO header se transforma numa experiência dedicada de pesquisa — não
 * um modal centralizado, não um drawer lateral, não uma simples expansão de
 * campo dentro do header normal (as três alternativas explicitamente
 * rejeitadas). `DialogPrimitive.Content` é posicionado `fixed inset-x-0
 * top-0` com a MESMA altura de linha do header real (`h-14`), então
 * visualmente ele ocupa e substitui a barra do header (menu, identidade,
 * avatar, tema — todos cobertos/inacessíveis enquanto o modo está aberto,
 * satisfazendo "ocultar" sem precisar coordenar estado com o `Header`
 * Server Component). O restante da tela escurece via `DialogPrimitive.Overlay`
 * (bloqueia interação e scroll do conteúdo de fundo — mecanismo padrão do
 * Radix Dialog modal, sem código adicional). `Portal` garante que o painel
 * fique acima de header/sidebar/drawer/conteúdo mesmo se algum desses tiver
 * seu próprio stacking context.
 *
 * Estrutura de duas linhas dentro do `Content`: (1) barra de altura fixa
 * (`h-14`, mesma do header) com campo de busca + botão "Filtros" (pesquisa
 * avançada) + botão "Fechar" (`X`), ambos como toque de ≥44px
 * (`h-11 w-11`), fora do campo — não sobrepostos como no dropdown desktop;
 * (2) painel de sugestões que ocupa o espaço restante (`flex-1 min-h-0
 * overflow-y-auto`), com rolagem própria independente da página. Altura
 * total do `Content` limitada a `max-h-[100dvh]` (unidade de viewport
 * dinâmica — mesma convenção já usada em `AppShell`/`AuthHeroShell`, sem
 * fallback `vh` explícito por não haver precedente disso no projeto) para
 * que o teclado virtual encolha o painel em vez de empurrá-lo para fora da
 * tela. `env(safe-area-inset-top/bottom)` aplicado via padding, para iPhones
 * com notch/Dynamic Island e a barra de gestos inferior.
 *
 * Antes de haver termo digitado (`phase === "hint"`), mostra uma orientação
 * curta em vez de um painel vazio desproporcional. Estados de carregamento/
 * erro/vazio compartilhados com o desktop via `useCardSearchSuggestions`,
 * apresentados aqui como blocos de texto no próprio painel (não um dropdown
 * separado) — itens de sugestão com altura mínima de 44px (toque) e imagem/
 * nome/Card Set/número legíveis. Região `aria-live="polite"` oculta anuncia
 * quantidade de resultados para leitor de tela a cada mudança de status.
 *
 * Fechamento: botão `X`, `Escape` (comportamento nativo do `Dialog` Radix,
 * não interceptado aqui — ao contrário do combobox desktop, não existe uma
 * "lista local" para fechar antes do modo inteiro), navegação concluída
 * (seleção de sugestão ou "Filtros"), e botão Voltar do navegador — um
 * `history.pushState` marcador é empilhado ao abrir (mesma URL, só um
 * `state` extra) especificamente para isso; o listener de `popstate` fecha
 * o painel sem navegação real. Ao fechar sem navegar (X/Escape/clique fora),
 * a marca de histórico é desfeita via `history.back()` (deixa a pilha como
 * estava antes de abrir); ao fechar navegando para `/pesquisa`, a marca é
 * neutralizada via `replaceState` em vez de `back()` (que desfaria a
 * navegação que está prestes a acontecer). `Radix Dialog` cuida, sem código
 * adicional, de: foco automático no campo ao abrir, restauração de foco no
 * botão que abriu ao fechar, bloqueio de scroll do `body`, e remoção
 * completa do overlay/listeners ao desmontar — nenhuma camada invisível
 * permanece interceptando cliques depois de fechado.
 */
function MobileSearchOverlay() {
  const listboxId = useId();
  const [open, setOpen] = useState(false);
  const pushedHistoryRef = useRef(false);

  function closeOverlay(options?: { viaNavigation?: boolean }) {
    suggestions.reset();
    if (pushedHistoryRef.current && typeof window !== "undefined") {
      pushedHistoryRef.current = false;
      if (options?.viaNavigation) {
        // Já vamos empilhar uma rota nova (`/pesquisa`) — só neutraliza a
        // marca de histórico em vez de voltar (voltar desfaria a navegação).
        window.history.replaceState(null, "");
      } else {
        // Consome a entrada marcadora — o listener de popstate abaixo
        // termina o fechamento (setOpen(false)).
        window.history.back();
        return;
      }
    }
    setOpen(false);
  }

  const suggestions = useCardSearchSuggestions({ onNavigate: () => closeOverlay({ viaNavigation: true }) });
  const { query, cards, status, activeIndex, setActiveIndex, handleChange, moveActive, goToAdvancedSearch, selectCard } =
    suggestions;

  // Botão Voltar do navegador fecha o modo imersivo em vez de sair da
  // página — mesma URL (só um `state` extra), sem navegação visível real.
  useEffect(() => {
    if (!open || typeof window === "undefined") return;
    // Guarda contra o duplo-mount do React Strict Mode (dev): sem o `if`,
    // abrir uma vez empilharia dois marcadores de histórico em vez de um só
    // (o `ref` sobrevive ao ciclo montar→desmontar→remontar sintético).
    if (!pushedHistoryRef.current) {
      window.history.pushState({ mmkyuMobileSearch: true }, "");
      pushedHistoryRef.current = true;
    }

    function handlePopState() {
      pushedHistoryRef.current = false;
      setOpen(false);
    }
    window.addEventListener("popstate", handlePopState);
    return () => window.removeEventListener("popstate", handlePopState);
  }, [open]);

  function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      moveActive(1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      moveActive(-1);
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (activeIndex >= 0 && cards[activeIndex]) {
        selectCard(cards[activeIndex]);
      } else if (query.trim()) {
        goToAdvancedSearch();
      }
    }
    // Escape: propositalmente não tratado aqui — deixa o Dialog fechar o
    // modo imersivo inteiro (não existe "lista local" separada para fechar
    // primeiro, diferente do combobox desktop).
  }

  const phase: "hint" | "loading" | "error" | "empty" | "results" =
    status === "loading"
      ? "loading"
      : status === "error"
        ? "error"
        : status === "success"
          ? cards.length === 0
            ? "empty"
            : "results"
          : "hint";

  const liveMessage =
    phase === "loading"
      ? "Buscando cartas…"
      : phase === "error"
        ? "Não foi possível buscar agora."
        : phase === "empty"
          ? "Nenhuma carta encontrada."
          : phase === "results"
            ? `${cards.length} ${cards.length === 1 ? "carta encontrada" : "cartas encontradas"}.`
            : "";

  const activeOptionId = phase === "results" && activeIndex >= 0 ? `${listboxId}-option-${activeIndex}` : undefined;

  return (
    <DialogPrimitive.Root open={open} onOpenChange={(next) => (next ? setOpen(true) : closeOverlay())}>
      <DialogPrimitive.Trigger asChild>
        <Button variant="ghost" size="icon" className="md:hidden" aria-label="Pesquisar cartas">
          <Search className="h-4 w-4" />
        </Button>
      </DialogPrimitive.Trigger>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-foreground/40 data-[state=open]:animate-overlay-in data-[state=closed]:animate-overlay-out" />
        <DialogPrimitive.Content className="fixed inset-x-0 top-0 z-50 flex max-h-[100dvh] flex-col bg-surface pt-[env(safe-area-inset-top)] shadow-panel data-[state=open]:animate-search-panel-in data-[state=closed]:animate-search-panel-out">
          <DialogPrimitive.Title className="sr-only">Pesquisar cartas</DialogPrimitive.Title>
          <div className="flex h-14 shrink-0 items-center gap-1.5 border-b border-border px-3">
            <div className="relative flex-1">
              <Search
                className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground"
                aria-hidden="true"
              />
              <Input
                autoFocus
                value={query}
                onChange={(event) => handleChange(event.target.value)}
                onKeyDown={handleKeyDown}
                placeholder="Pesquisar cartas…"
                role="combobox"
                aria-expanded={phase === "results"}
                aria-controls={listboxId}
                aria-activedescendant={activeOptionId}
                aria-autocomplete="list"
                aria-label="Pesquisar cartas por nome, número ou código do Card Set"
                autoComplete="off"
                enterKeyHint="search"
                inputMode="search"
                className="h-10 pl-9 text-sm"
              />
            </div>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-11 w-11 shrink-0"
              aria-label="Abrir pesquisa avançada"
              onClick={() => goToAdvancedSearch()}
            >
              <SlidersHorizontal className="h-4 w-4" />
            </Button>
            <Button
              type="button"
              variant="ghost"
              size="icon"
              className="h-11 w-11 shrink-0"
              aria-label="Fechar pesquisa"
              onClick={() => closeOverlay()}
            >
              <X className="h-4 w-4" />
            </Button>
          </div>

          <div
            id={listboxId}
            className="min-h-0 flex-1 overflow-y-auto overscroll-contain pb-[env(safe-area-inset-bottom)]"
          >
            {phase === "hint" && (
              <div className="flex h-full flex-col items-center justify-center gap-2 px-6 py-10 text-center">
                <Search className="h-5 w-5 text-muted-foreground/40" aria-hidden="true" />
                <p className="text-sm text-muted-foreground">Pesquise pelo nome, número ou código do Card Set.</p>
              </div>
            )}
            {phase === "loading" && (
              <div className="flex items-center gap-2 px-4 py-4 text-sm text-muted-foreground">
                <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
                Buscando…
              </div>
            )}
            {phase === "error" && (
              <div className="px-4 py-4 text-sm text-destructive">Não foi possível buscar agora. Tente novamente.</div>
            )}
            {phase === "empty" && (
              <div className="flex h-full flex-col items-center justify-center gap-1 px-6 py-10 text-center">
                <p className="text-sm text-muted-foreground">Nenhuma carta encontrada.</p>
              </div>
            )}
            {phase === "results" && (
              <ul role="listbox" aria-label="Sugestões de cartas" className="divide-y divide-border">
                {cards.map((card, index) => {
                  const imageUrl = cardImageUrl(card);
                  const isActive = index === activeIndex;
                  return (
                    <li
                      key={card.id}
                      id={`${listboxId}-option-${index}`}
                      role="option"
                      aria-selected={isActive}
                      onClick={() => selectCard(card)}
                      className={cn(
                        "flex min-h-11 w-full cursor-pointer items-center gap-3 px-3 py-2 text-left text-sm",
                        isActive ? "bg-accent" : "active:bg-surface-muted",
                      )}
                    >
                      <div className="flex h-11 w-8 shrink-0 items-center justify-center overflow-hidden rounded bg-surface-muted">
                        {imageUrl ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img src={imageUrl} alt="" className="h-full w-full object-cover" />
                        ) : (
                          <Search className="h-3.5 w-3.5 text-muted-foreground/40" aria-hidden="true" />
                        )}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-medium text-foreground">{card.name}</p>
                        <p className="truncate text-xs text-muted-foreground">
                          {card.cardSet.code} · {cartaFullNumber(card.collectorNumber, card.collectorTotal)}
                        </p>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>

          <p aria-live="polite" className="sr-only">
            {liveMessage}
          </p>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
