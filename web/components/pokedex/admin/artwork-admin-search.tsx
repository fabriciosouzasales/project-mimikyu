"use client";

import { Loader2, Search, X } from "lucide-react";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState, useTransition } from "react";
import { Input } from "@/components/ui/input";

const DEBOUNCE_MS = 300;
const PATH = "/pokedex/imagens";

/**
 * Pesquisa da administração de Imagens (Lote E) — mesmo comportamento da
 * pesquisa da Pokédex Nacional (form GET sem JavaScript; com JavaScript,
 * debounce + `router.replace` + indicador real da transição), preservando o
 * filtro de situação e voltando à primeira página.
 */
export function ArtworkAdminSearch({
  initialQuery,
  statusParam,
  maxLength,
}: {
  initialQuery: string | null;
  statusParam: string | null;
  maxLength: number;
}) {
  const router = useRouter();
  const [value, setValue] = useState(initialQuery ?? "");
  const [isPending, startTransition] = useTransition();
  const lastPushed = useRef(initialQuery ?? "");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const next = initialQuery ?? "";
    if (next !== lastPushed.current) {
      lastPushed.current = next;
      setValue(next);
    }
  }, [initialQuery]);

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  function navigate(raw: string) {
    const query = raw.trim();
    if (query === lastPushed.current) return;
    lastPushed.current = query;
    const params = new URLSearchParams();
    if (query) params.set("q", query);
    if (statusParam) params.set("status", statusParam);
    const search = params.toString();
    startTransition(() => {
      router.replace(search ? `${PATH}?${search}` : PATH, { scroll: false });
    });
  }

  return (
    <form
      role="search"
      action={PATH}
      method="get"
      className="relative w-full"
      onSubmit={(event) => {
        event.preventDefault();
        if (timer.current) clearTimeout(timer.current);
        navigate(value);
      }}
    >
      <label htmlFor="pokedex-imagens-search" className="sr-only">
        Pesquisar espécie por nome ou número
      </label>
      <Search
        className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-control-muted-foreground"
        aria-hidden="true"
      />
      <Input
        id="pokedex-imagens-search"
        name="q"
        type="search"
        autoComplete="off"
        spellCheck={false}
        maxLength={maxLength}
        placeholder="Nome ou número — ex.: Pikachu, 25"
        value={value}
        onChange={(event) => {
          setValue(event.target.value);
          if (timer.current) clearTimeout(timer.current);
          const next = event.target.value;
          timer.current = setTimeout(() => navigate(next), DEBOUNCE_MS);
        }}
        className="h-9 pl-9 pr-10 [&::-webkit-search-cancel-button]:hidden"
      />
      {statusParam ? <input type="hidden" name="status" value={statusParam} /> : null}
      <div className="absolute right-2 top-1/2 flex -translate-y-1/2 items-center">
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
