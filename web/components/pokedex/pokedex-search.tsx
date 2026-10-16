"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Loader2, Search, X } from "lucide-react";
import { Input } from "@/components/ui/input";
import { type PokedexOrigin, galleryBasePath, pokedexHref } from "@/lib/pokedex/format";
import { cn } from "@/lib/utils";

const DEBOUNCE_MS = 300;

/**
 * Pesquisa da Pokédex Nacional (Pokédex P1). Única ilha cliente da página:
 * a lista é renderizada no servidor a partir da URL (`?q=` e `?geracao=`).
 *
 * - Funciona sem JavaScript: é um `<form method="get">` comum.
 * - Com JavaScript: pesquisa enquanto digita (debounce de 300 ms) via
 *   `router.replace`, sem empilhar histórico a cada tecla e sem rolar a
 *   página; o indicador de carregamento acompanha a transição real do
 *   servidor (`useTransition`), não um tempo artificial.
 * - A geração e os tipos selecionados (P5a) são preservados.
 */
export function PokedexSearch({
  initialQuery,
  generation,
  types = [],
  maxLength,
  size = "md",
  origin = null,
}: {
  initialQuery: string | null;
  generation: number | null;
  /** Tipos ativos (`?tipo=`, P5a), já canônicos. */
  types?: readonly string[];
  /** P6: pesquisa dentro da página Pokémons Favoritos. */
  origin?: PokedexOrigin | null;
  maxLength: number;
  /** "lg": campo de destaque do cabeçalho da Pokédex Nacional (P3c). */
  size?: "md" | "lg";
}) {
  const large = size === "lg";
  const router = useRouter();
  const [value, setValue] = useState(initialQuery ?? "");
  const [isPending, startTransition] = useTransition();
  const lastPushed = useRef<string>(initialQuery ?? "");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // A URL pode mudar por fora deste campo (ex.: "Limpar pesquisa" no estado
  // vazio). Só sincroniza quando o valor não veio daqui, para nunca
  // sobrescrever o que o usuário está digitando.
  useEffect(() => {
    const next = initialQuery ?? "";
    if (next !== lastPushed.current) {
      lastPushed.current = next;
      setValue(next);
    }
  }, [initialQuery]);

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  function navigate(rawQuery: string) {
    const query = rawQuery.trim();
    if (query === lastPushed.current) return;
    lastPushed.current = query;

    startTransition(() => {
      router.replace(pokedexHref({ query: query || null, generation, types, origin }), { scroll: false });
    });
  }

  function schedule(nextValue: string) {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => navigate(nextValue), DEBOUNCE_MS);
  }

  return (
    <form
      role="search"
      action={galleryBasePath({ origin })}
      method="get"
      className="relative w-full"
      onSubmit={(event) => {
        event.preventDefault();
        if (timer.current) clearTimeout(timer.current);
        navigate(value);
      }}
    >
      <label htmlFor="pokedex-search" className="sr-only">
        Pesquisar Pokémon por nome ou número
      </label>
      <Search
        className={cn(
          "pointer-events-none absolute top-1/2 -translate-y-1/2 text-control-muted-foreground",
          large ? "left-4 h-[18px] w-[18px]" : "left-3 h-4 w-4",
        )}
        aria-hidden="true"
      />
      <Input
        id="pokedex-search"
        name="q"
        type="search"
        inputMode="search"
        autoComplete="off"
        spellCheck={false}
        maxLength={maxLength}
        placeholder="Nome ou número"
        value={value}
        onChange={(event) => {
          setValue(event.target.value);
          schedule(event.target.value);
        }}
        className={cn(
          "[&::-webkit-search-cancel-button]:hidden",
          large ? "h-[3.25rem] rounded-xl pl-12 pr-12 text-base" : "h-10 pl-9 pr-10",
        )}
      />
      {generation ? <input type="hidden" name="geracao" value={generation} /> : null}
      {types.length > 0 ? <input type="hidden" name="tipo" value={types.join(",")} /> : null}

      <div className={cn("absolute top-1/2 flex -translate-y-1/2 items-center", large ? "right-3" : "right-2")}>
        {isPending ? (
          <Loader2 className="h-4 w-4 animate-spin text-muted-foreground motion-reduce:animate-none" aria-hidden="true" />
        ) : value ? (
          <button
            type="button"
            onClick={() => {
              setValue("");
              if (timer.current) clearTimeout(timer.current);
              navigate("");
            }}
            className="flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-primary/15"
            aria-label="Limpar pesquisa"
          >
            <X className="h-4 w-4" aria-hidden="true" />
          </button>
        ) : null}
      </div>
      <span className="sr-only" aria-live="polite">
        {isPending ? "Pesquisando…" : ""}
      </span>
    </form>
  );
}
