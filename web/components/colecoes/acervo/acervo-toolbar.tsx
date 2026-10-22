"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowDownUp, Loader2, Search, SlidersHorizontal, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import {
  ACERVO_PATH,
  ACERVO_QUERY_MAX_LENGTH,
  type AcervoCollectionFilter,
  type AcervoState,
  acervoHref,
  formatCount,
} from "@/lib/colecoes/acervo";
import type { AcervoFilterOptions } from "@/lib/colecoes/acervo-queries";
import { storageFilterFromValue, storageFilterOptions, storageFilterValue } from "@/lib/colecoes/acervo-storage-filter";
import type { StorageLocation } from "@/lib/colecoes/storage-locations";
import { cn } from "@/lib/utils";
import styles from "./acervo.module.css";

const DEBOUNCE_MS = 300;

/**
 * Busca, filtros e ordenação de Meu acervo — a única ilha cliente da lista.
 *
 * O estado vive na URL (renderização no servidor, compartilhável, voltar/
 * avançar funcionam). Sem JavaScript, é um `<form method="get">` comum com
 * botão "Aplicar". Com JavaScript: busca com debounce de 300 ms e filtros
 * aplicados na hora, via `router.replace` dentro de `useTransition` — o
 * indicador acompanha a navegação real, sem atraso artificial.
 *
 * Uma única linha no desktop (WHERE-04 FRONTEND UX CORRECTION-01, decisão do
 * proprietário): Busca | Set | Idioma | Coleção | Localização | Ordenação. A
 * busca ganha mais espaço; os quatro filtros têm largura compacta e igual (o
 * valor longo é truncado no campo fechado, completo nas opções); a ordenação
 * fica na ponta direita, com ícone no próprio campo e rótulo só para leitores
 * de tela. A barra nunca quebra em duas linhas: sem largura suficiente
 * (container query da própria barra), os filtros recolhem no botão "Filtros".
 * A contagem de resultados fica junto da galeria (acervo-view), fora da barra.
 *
 * Recolhido (barra estreita ou celular): busca, botão "Filtros" e ordenação;
 * os mesmos `<Select>` abrem logo abaixo (sem segundo conjunto de controles).
 */
export function AcervoToolbar({
  state,
  options,
  locations = null,
}: {
  state: AcervoState;
  /** `null` = opções indisponíveis: os filtros somem, a busca continua. */
  options: AcervoFilterOptions | null;
  /** WHERE-04: locais do usuário (5219); `null` = lista indisponível (o filtro explica). */
  locations?: StorageLocation[] | null;
}) {
  const router = useRouter();
  const [query, setQuery] = useState(state.query ?? "");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [isPending, startTransition] = useTransition();
  const lastQuery = useRef(state.query ?? "");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const next = state.query ?? "";
    if (next !== lastQuery.current) {
      lastQuery.current = next;
      setQuery(next);
    }
  }, [state.query]);

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  function go(next: Partial<AcervoState>) {
    startTransition(() => {
      router.replace(acervoHref({ ...state, detail: null, page: 1, ...next }), { scroll: false });
    });
  }

  function submitQuery(raw: string) {
    const trimmed = raw.trim();
    if (trimmed === lastQuery.current) return;
    lastQuery.current = trimmed;
    go({ query: trimmed || null });
  }

  const collectionValue =
    state.collection.kind === "none" ? "sem" : state.collection.kind === "collection" ? state.collection.id : "";
  const activeFilterCount =
    (state.setCode ? 1 : 0) +
    (state.languageCode ? 1 : 0) +
    (state.collection.kind !== "all" ? 1 : 0) +
    (state.storage.kind !== "all" ? 1 : 0);
  const storageOptions = storageFilterOptions(state.storage, locations);
  const storageValue = storageFilterValue(state.storage);
  // Nome completo do local escolhido ao passar o mouse (o campo fechado trunca).
  const storageTitle = [...storageOptions.base, ...storageOptions.locations].find((o) => o.value === storageValue)?.label;

  return (
    <form
      role="search"
      method="get"
      action={ACERVO_PATH}
      className={styles.toolbar}
      onSubmit={(event) => {
        event.preventDefault();
        if (timer.current) clearTimeout(timer.current);
        submitQuery(query);
      }}
    >
      <div className={styles.controls}>
        <div className={cn("relative", styles.search)}>
          <label htmlFor="acervo-busca" className="sr-only">
            Buscar no seu acervo por nome ou número
          </label>
          <Search
            className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-control-muted-foreground"
            aria-hidden="true"
          />
          <Input
            id="acervo-busca"
            name="q"
            type="search"
            inputMode="search"
            autoComplete="off"
            spellCheck={false}
            maxLength={ACERVO_QUERY_MAX_LENGTH}
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

        {options ? (
          <Button
            type="button"
            variant="outline"
            className={cn("h-9", styles.filtersButton)}
            aria-expanded={filtersOpen}
            aria-controls="acervo-filtros"
            onClick={() => setFiltersOpen((open) => !open)}
          >
            <SlidersHorizontal className="h-4 w-4" aria-hidden="true" />
            Filtros{activeFilterCount > 0 ? ` · ${activeFilterCount}` : ""}
          </Button>
        ) : null}

        {options ? (
          <div id="acervo-filtros" className={styles.filterGroup} data-open={filtersOpen}>
            <FilterSelect
              id="acervo-set"
              name="set"
              label="Set"
              value={state.setCode ?? ""}
              allLabel="Todos os Sets"
              options={options.sets}
              onChange={(value) => go({ setCode: value || null })}
            />
            <FilterSelect
              id="acervo-idioma"
              name="idioma"
              label="Idioma"
              value={state.languageCode ?? ""}
              allLabel="Todos os idiomas"
              options={options.languages}
              onChange={(value) => go({ languageCode: value || null })}
            />
            <div>
              <label htmlFor="acervo-colecao" className="sr-only">
                Coleção
              </label>
              <Select
                id="acervo-colecao"
                name="colecao"
                value={collectionValue}
                className={styles.filterSelect}
                onChange={(event) => {
                  const value = event.target.value;
                  const collection: AcervoCollectionFilter =
                    value === "sem" ? { kind: "none" } : value ? { kind: "collection", id: value } : { kind: "all" };
                  go({ collection });
                }}
              >
                <option value="">Todas as coleções</option>
                <option value="sem">Sem coleção</option>
                {options.collections.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label} ({formatCount(option.count)})
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="acervo-local" className="sr-only">
                Localização física
              </label>
              <Select
                id="acervo-local"
                name="local"
                value={storageValue}
                title={storageTitle}
                className={styles.filterSelect}
                onChange={(event) => go({ storage: storageFilterFromValue(event.target.value) })}
              >
                {storageOptions.base.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
                <optgroup label="Seus locais">
                  {storageOptions.locations.map((option) => (
                    <option key={option.value} value={option.value} disabled={option.disabled}>
                      {option.label}
                    </option>
                  ))}
                </optgroup>
              </Select>
            </div>
            <noscript>
              <Button type="submit" variant="outline" className="h-9">
                Aplicar
              </Button>
            </noscript>
          </div>
        ) : null}

        {/* A contagem visível mora junto da galeria; aqui só o aviso de atualização para leitores de tela. */}
        <span className="sr-only" aria-live="polite">
          {isPending ? "Atualizando resultados…" : ""}
        </span>

        <div className={styles.sortGroup}>
          <label htmlFor="acervo-ordem" className="sr-only">
            Ordenar por
          </label>
          <ArrowDownUp className={styles.sortIcon} aria-hidden="true" />
          <Select
            id="acervo-ordem"
            name="ordem"
            value={state.sort}
            className={styles.sortSelect}
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
  options: { value: string; label: string; count: number }[];
  onChange: (value: string) => void;
}) {
  return (
    <div>
      <label htmlFor={id} className="sr-only">
        {label}
      </label>
      <Select id={id} name={name} value={value} className={styles.filterSelect} onChange={(event) => onChange(event.target.value)}>
        <option value="">{allLabel}</option>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label} ({formatCount(option.count)})
          </option>
        ))}
      </Select>
    </div>
  );
}
