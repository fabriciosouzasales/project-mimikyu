"use client";

import { Loader2, Search } from "lucide-react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Input } from "@/components/ui/input";

type CardSuggestion = {
  id: string;
  name: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSet: { code: string; name: string };
};

/**
 * Combobox de busca/seleção de Carta — Preço por Carta (Bloco 5, migration
 * 3943). Deliberadamente um componente próprio, não uma extração do
 * `useCardSearchSuggestions` de `global-search.tsx`: mesmo espírito do
 * comentário em `lib/pesquisa/format.ts` ("pequena duplicação de funções
 * puras, preferível a acoplar") — aqui o resultado da escolha não é navegar
 * para `/pesquisa`, é escrever `?card=<id>` na própria URL da página atual e
 * deixar o RPC 3943 (`admin_get_pricing_report_card`) devolver a identidade
 * completa da carta escolhida, então nenhum estado de "carta selecionada"
 * precisa ser mantido aqui além do necessário para fechar o dropdown.
 *
 * Reaproveita a mesma rota `/api/cards/search` (Route Handler autenticado,
 * não exclusivo do Pricing) — histórico completo do contrato em
 * `web/app/api/cards/search/route.ts`.
 */
export function CardPicker({ paramName = "card" }: { paramName?: string }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const containerRef = useRef<HTMLDivElement>(null);

  const [query, setQuery] = useState("");
  const [results, setResults] = useState<CardSuggestion[]>([]);
  const [status, setStatus] = useState<"idle" | "loading" | "loaded">("idle");
  const [open, setOpen] = useState(false);

  useEffect(() => {
    function handleOutside(event: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(event.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleOutside);
    return () => document.removeEventListener("mousedown", handleOutside);
  }, []);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length === 0) {
      setResults([]);
      setStatus("idle");
      return;
    }

    const controller = new AbortController();
    setStatus("loading");
    const handle = setTimeout(() => {
      fetch(`/api/cards/search?q=${encodeURIComponent(trimmed)}&limit=8`, { signal: controller.signal })
        .then((res) => res.json())
        .then((data: { cards?: CardSuggestion[] }) => {
          setResults(data.cards ?? []);
          setStatus("loaded");
        })
        .catch((err: unknown) => {
          if (err instanceof DOMException && err.name === "AbortError") return;
          setResults([]);
          setStatus("loaded");
        });
    }, 280);

    return () => {
      clearTimeout(handle);
      controller.abort();
    };
  }, [query]);

  function selectCard(cardId: string) {
    const params = new URLSearchParams(searchParams.toString());
    params.set(paramName, cardId);
    router.push(`${pathname}?${params.toString()}`);
    setOpen(false);
    setQuery("");
  }

  return (
    <div ref={containerRef} className="relative w-full max-w-md">
      <div className="relative">
        <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden="true" />
        <Input
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          placeholder="Buscar carta por nome ou número..."
          className="pl-8"
          role="combobox"
          aria-expanded={open}
          aria-controls="card-picker-listbox"
          aria-autocomplete="list"
        />
        {status === "loading" && (
          <Loader2 className="absolute right-2.5 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-muted-foreground" aria-hidden="true" />
        )}
      </div>

      {open && results.length > 0 && (
        <ul
          id="card-picker-listbox"
          role="listbox"
          className="absolute z-20 mt-1 max-h-72 w-full overflow-auto rounded-lg border border-border bg-surface p-1 shadow-panel"
        >
          {results.map((card) => (
            <li key={card.id}>
              <button
                type="button"
                role="option"
                aria-selected={false}
                onClick={() => selectCard(card.id)}
                className="flex w-full flex-col items-start gap-0.5 rounded-md px-2.5 py-1.5 text-left text-sm hover:bg-surface-muted"
              >
                <span className="font-medium text-foreground">{card.name}</span>
                <span className="text-xs text-muted-foreground">
                  {card.cardSet.code} · {card.collectorNumber.padStart(3, "0")}/
                  {card.collectorTotal != null ? String(card.collectorTotal).padStart(3, "0") : "???"}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      {open && status === "loaded" && results.length === 0 && query.trim().length > 0 && (
        <div className="absolute z-20 mt-1 w-full rounded-lg border border-border bg-surface p-3 text-xs text-muted-foreground shadow-panel">
          Nenhuma carta encontrada.
        </div>
      )}
    </div>
  );
}
