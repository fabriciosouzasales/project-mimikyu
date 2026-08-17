"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
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

/**
 * Combobox global de pesquisa de cartas — Incremento "Pesquisa Global de
 * Cartas" (2026-08-17, ver ADR-030). Disponível a qualquer usuário
 * autenticado, integrado ao `Header` (renderizado para toda página via
 * `AppShell`). Desktop: campo inline entre título e ações do header. Mobile:
 * botão compacto que abre um overlay dedicado — nunca comprime o campo
 * completo no espaço insuficiente do header mobile.
 *
 * Padrão ARIA combobox/listbox (`aria-activedescendant`, sem mover o foco
 * real do DOM para as opções) — navegação por teclado sem conflito entre o
 * campo e o botão interno de pesquisa avançada.
 */
export function GlobalSearch() {
  return (
    <>
      <div className="hidden md:flex flex-1 justify-center px-4">
        <div className="w-full max-w-sm">
          <SearchCombobox variant="inline" />
        </div>
      </div>
      <MobileSearchTrigger />
    </>
  );
}

function MobileSearchTrigger() {
  const [open, setOpen] = useState(false);

  return (
    <DialogPrimitive.Root open={open} onOpenChange={setOpen}>
      <DialogPrimitive.Trigger asChild>
        <Button variant="ghost" size="icon" className="md:hidden" aria-label="Pesquisar cartas">
          <Search className="h-4 w-4" />
        </Button>
      </DialogPrimitive.Trigger>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-foreground/20 data-[state=open]:animate-overlay-in data-[state=closed]:animate-overlay-out" />
        <DialogPrimitive.Content className="fixed inset-x-0 top-0 z-50 flex flex-col gap-3 border-b border-border bg-surface p-3 shadow-panel data-[state=open]:animate-drawer-in data-[state=closed]:animate-drawer-out">
          <DialogPrimitive.Title className="sr-only">Pesquisar cartas</DialogPrimitive.Title>
          <div className="flex items-center gap-2">
            <div className="flex-1">
              <SearchCombobox variant="overlay" onNavigate={() => setOpen(false)} autoFocus />
            </div>
            <DialogPrimitive.Close asChild>
              <Button variant="ghost" size="icon" aria-label="Fechar pesquisa">
                <X className="h-4 w-4" />
              </Button>
            </DialogPrimitive.Close>
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

function SearchCombobox({
  variant,
  onNavigate,
  autoFocus,
}: {
  variant: "inline" | "overlay";
  onNavigate?: () => void;
  autoFocus?: boolean;
}) {
  const router = useRouter();
  const listboxId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const [query, setQuery] = useState("");
  const [cards, setCards] = useState<PesquisaCard[]>([]);
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(-1);

  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
      abortRef.current?.abort();
    };
  }, []);

  // Fecha ao clicar fora (variante inline — a overlay já fecha via Dialog).
  useEffect(() => {
    if (variant !== "inline" || !open) return;
    function handlePointerDown(event: PointerEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("pointerdown", handlePointerDown);
    return () => document.removeEventListener("pointerdown", handlePointerDown);
  }, [variant, open]);

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

  function goToAdvancedSearch(term: string) {
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

  function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown") {
      event.preventDefault();
      if (!open && cards.length > 0) setOpen(true);
      setActiveIndex((prev) => (cards.length === 0 ? -1 : (prev + 1) % cards.length));
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (!open && cards.length > 0) setOpen(true);
      setActiveIndex((prev) => (cards.length === 0 ? -1 : (prev - 1 + cards.length) % cards.length));
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
          autoFocus={autoFocus}
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
          className={cn(
            "absolute z-50 mt-1 max-h-96 w-full overflow-y-auto rounded-lg border border-border bg-surface py-1 shadow-panel",
            variant === "overlay" && "max-h-[70vh]",
          )}
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
