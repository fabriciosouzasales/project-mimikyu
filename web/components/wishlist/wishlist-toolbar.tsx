"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { ArrowDownUp, Loader2, Search, SlidersHorizontal, X } from "lucide-react";
import acervoStyles from "@/components/colecoes/acervo/acervo.module.css";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import { formatCount } from "@/lib/colecoes/acervo";
import { cn } from "@/lib/utils";
import {
  type WishlistFilterOption,
  type WishlistFilterOptions,
  type WishlistFilters,
  type WishlistOwnershipFilter,
  WISHLIST_PATH,
  WISHLIST_SEARCH_MAX,
  activeWishlistFilterCount,
  clearedWishlistFilters,
  wishlistFilterChips,
  wishlistHref,
} from "@/lib/wishlist/wishlist";

const DEBOUNCE_MS = 300;

/**
 * Busca e filtros da Lista de desejos (V1-11 W6) — a mesma barra do Meu acervo (mesmas
 * classes, mesmo comportamento): estado na URL, renderização no servidor, busca com
 * debounce de 300 ms e filtros aplicados na hora via `router.replace` em `useTransition`
 * (o indicador acompanha a navegação real). Sem JavaScript é um `<form method="get">`.
 *
 * Busca | Set | Raridade | Idioma | Acervo | Ordenação — uma linha no desktop; sem largura, os
 * filtros recolhem no botão "Filtros". Cada filtro lista só o que existe na lista do usuário, com
 * a contagem de desejos. A ordenação é a mesma do Meu acervo ("Mais recentes" | "Set e número")
 * e não conta como filtro. Mudar filtro ou ordem volta para a página 1.
 */
export function WishlistToolbar({ filters, options }: { filters: WishlistFilters; options: WishlistFilterOptions }) {
  const router = useRouter();
  const [query, setQuery] = useState(filters.query ?? "");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [isPending, startTransition] = useTransition();
  const lastQuery = useRef(filters.query ?? "");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const next = filters.query ?? "";
    if (next !== lastQuery.current) {
      lastQuery.current = next;
      setQuery(next);
    }
  }, [filters.query]);

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    [],
  );

  function go(next: Partial<WishlistFilters>) {
    startTransition(() => {
      router.replace(wishlistHref({ ...filters, ...next }), { scroll: false });
    });
  }

  function submitQuery(raw: string) {
    const trimmed = raw.trim().slice(0, WISHLIST_SEARCH_MAX);
    if (trimmed === lastQuery.current) return;
    lastQuery.current = trimmed;
    go({ query: trimmed || null });
  }

  const selectCount = activeWishlistFilterCount({ ...filters, query: null });

  return (
    <form
      role="search"
      method="get"
      action={WISHLIST_PATH}
      className={acervoStyles.toolbar}
      onSubmit={(event) => {
        event.preventDefault();
        if (timer.current) clearTimeout(timer.current);
        submitQuery(query);
      }}
    >
      <div className={acervoStyles.controls}>
        <div className={cn("relative", acervoStyles.search)}>
          <label htmlFor="desejos-busca" className="sr-only">
            Buscar na lista de desejos por nome ou número
          </label>
          <Search
            className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-control-muted-foreground"
            aria-hidden="true"
          />
          <Input
            id="desejos-busca"
            name="q"
            type="search"
            inputMode="search"
            autoComplete="off"
            spellCheck={false}
            maxLength={WISHLIST_SEARCH_MAX}
            placeholder="Buscar por nome ou número"
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              if (timer.current) clearTimeout(timer.current);
              const value = event.target.value;
              timer.current = setTimeout(() => submitQuery(value), DEBOUNCE_MS);
            }}
            className="h-9 pl-9 pr-9 [&::-webkit-search-cancel-button]:hidden"
          />
          <div className="absolute right-1.5 top-1/2 flex -translate-y-1/2 items-center">
            {isPending ? (
              <Loader2 className="mr-1 h-4 w-4 animate-spin text-muted-foreground motion-reduce:animate-none" aria-hidden="true" />
            ) : query ? (
              <button
                type="button"
                onClick={() => {
                  setQuery("");
                  if (timer.current) clearTimeout(timer.current);
                  submitQuery("");
                }}
                className="flex h-7 w-7 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-primary/15"
                aria-label="Limpar busca"
              >
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            ) : null}
          </div>
        </div>

        <Button
          type="button"
          variant="outline"
          className={cn("h-9", acervoStyles.filtersButton)}
          aria-expanded={filtersOpen}
          aria-controls="desejos-filtros"
          onClick={() => setFiltersOpen((open) => !open)}
        >
          <SlidersHorizontal className="h-4 w-4" aria-hidden="true" />
          Filtros{selectCount > 0 ? ` · ${selectCount}` : ""}
        </Button>

        <div id="desejos-filtros" className={acervoStyles.filterGroup} data-open={filtersOpen}>
          <FilterSelect
            id="desejos-set"
            name="set"
            label="Set"
            value={filters.cardSetId ?? ""}
            allLabel="Todos os Sets"
            options={options.cardSets}
            onChange={(value) => go({ cardSetId: value || null })}
          />
          <FilterSelect
            id="desejos-raridade"
            name="raridade"
            label="Raridade"
            value={filters.rarityId ?? ""}
            allLabel="Todas as raridades"
            options={options.rarities}
            onChange={(value) => go({ rarityId: value || null })}
          />
          <FilterSelect
            id="desejos-idioma"
            name="idioma"
            label="Idioma desejado"
            value={filters.language === "*" ? "qualquer" : (filters.language ?? "")}
            allLabel="Todos os idiomas"
            options={options.languages.map((option) => (option.value === "*" ? { ...option, value: "qualquer" } : option))}
            onChange={(value) => go({ language: value === "qualquer" ? "*" : value || null })}
          />
          <FilterSelect
            id="desejos-acervo"
            name="acervo"
            label="Situação no acervo"
            value={filters.ownership === "OWNED" ? "tenho" : filters.ownership === "NOT_OWNED" ? "falta" : ""}
            allLabel="Com e sem exemplar"
            options={options.ownership.map((option) => ({ ...option, value: option.value === "OWNED" ? "tenho" : "falta" }))}
            onChange={(value) => go({ ownership: (value === "tenho" ? "OWNED" : value === "falta" ? "NOT_OWNED" : null) as WishlistOwnershipFilter | null })}
          />
          <noscript>
            <Button type="submit" variant="outline" className="h-9">
              Aplicar
            </Button>
          </noscript>
        </div>

        <span className="sr-only" aria-live="polite">
          {isPending ? "Atualizando resultados…" : ""}
        </span>

        <div className={acervoStyles.sortGroup}>
          <label htmlFor="desejos-ordem" className="sr-only">
            Ordenar por
          </label>
          <ArrowDownUp className={acervoStyles.sortIcon} aria-hidden="true" />
          <Select
            id="desejos-ordem"
            name="ordem"
            value={filters.sort}
            className={acervoStyles.sortSelect}
            onChange={(event) => go({ sort: event.target.value === "set" ? "set" : "recentes" })}
          >
            <option value="recentes">Mais recentes</option>
            <option value="set">Set e número</option>
          </Select>
        </div>
      </div>
    </form>
  );
}

function FilterSelect({
  id,
  name,
  label,
  value,
  allLabel,
  options,
  onChange,
}: {
  id: string;
  name: string;
  label: string;
  value: string;
  allLabel: string;
  options: WishlistFilterOption[];
  onChange: (value: string) => void;
}) {
  const current = options.find((option) => option.value === value);
  return (
    <div>
      <label htmlFor={id} className="sr-only">
        {label}
      </label>
      <Select
        id={id}
        name={name}
        value={value}
        title={current ? current.label : undefined}
        className={acervoStyles.filterSelect}
        onChange={(event) => onChange(event.target.value)}
      >
        <option value="">{allLabel}</option>
        {/* Valor da URL que não está mais entre as opções (lista mudou): continua visível. */}
        {value && !current ? <option value={value}>Filtro atual</option> : null}
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
            {option.detail ? ` · ${option.detail.toUpperCase()}` : ""} ({formatCount(option.count)})
          </option>
        ))}
      </Select>
    </div>
  );
}

/** Filtros ativos como chips removíveis + "Limpar filtros" (volta à lista completa). */
export function WishlistFilterChips({ filters, options }: { filters: WishlistFilters; options: WishlistFilterOptions | null }) {
  const chips = wishlistFilterChips(filters, options);
  if (chips.length === 0) return null;
  return (
    <div className={acervoStyles.chips}>
      {chips.map((chip) => (
        <span key={chip.key} className={acervoStyles.chip}>
          {chip.label}
          <Link href={chip.href} scroll={false} className={acervoStyles.chipRemove} aria-label={`Remover filtro ${chip.label}`}>
            <X className="h-3 w-3" aria-hidden="true" />
          </Link>
        </span>
      ))}
      <Link href={wishlistHref(clearedWishlistFilters(filters))} scroll={false} className={acervoStyles.chipClear}>
        Limpar filtros
      </Link>
    </div>
  );
}
