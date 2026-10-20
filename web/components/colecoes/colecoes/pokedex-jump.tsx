"use client";

import { useRouter } from "next/navigation";
import { useCallback, useId, useMemo, useRef, useState } from "react";
import { Loader2, Search, X } from "lucide-react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Input } from "@/components/ui/input";
import { type GenerationOption, formatDex, planPokedexJump, pokedexHref } from "@/lib/colecoes/pokedex";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import {
  QUICK_SEARCH_MAX_QUERY,
  type SpeciesIndexEntry,
  type SpeciesSuggestion,
  parseNumberQuery,
  parseSpeciesIndex,
  searchSpecies,
} from "@/lib/pokedex/species-search";
import styles from "./pokedex.module.css";

type Range = Pick<GenerationOption, "code" | "firstNumber" | "lastNumber" | "selected">;
type IndexStatus = "idle" | "loading" | "ready" | "error";

/**
 * Índice da Pokédex Nacional ([número, nome, arte]) — o mesmo endpoint da busca
 * rápida da ficha (`/api/pokedex/species-index`, sem SQL novo). Carregado uma vez
 * por aba, só na primeira intenção de busca; falha não fica em cache.
 */
let indexRequest: Promise<SpeciesIndexEntry[] | null> | null = null;
let indexCache: SpeciesIndexEntry[] | null = null;

function loadSpeciesIndex(): Promise<SpeciesIndexEntry[] | null> {
  if (indexCache) return Promise.resolve(indexCache);
  if (!indexRequest) {
    indexRequest = fetch("/api/pokedex/species-index", { credentials: "same-origin" })
      .then((response) => (response.ok ? response.json() : null))
      .then((body) => parseSpeciesIndex(body))
      .catch(() => null)
      .then((entries) => {
        if (entries && entries.length > 0) indexCache = entries;
        else indexRequest = null;
        return indexCache;
      });
  }
  return indexRequest;
}

/**
 * Buscar um Pokémon na coleção Pokédex (UX-04): nome ou número nacional.
 *
 * - Escolher um resultado leva à geração dele em "Todas" (`?geracao=…&n=…`):
 *   a grade da geração vem inteira numa página e o card do Pokémon é trazido à
 *   vista, recebe o foco e fica destacado por um instante.
 * - Pokémon de geração fora desta Pokédex aparece na lista, esmaecido, com o
 *   aviso — não navega.
 * - Sem SQL novo: índice nacional já existente + grade da 5204.
 * - Padrão ARIA combobox/listbox com `aria-activedescendant`; ↑ ↓ percorrem,
 *   Enter escolhe, Esc limpa/fecha. Se o índice falhar, o número continua
 *   funcionando (busca só por número).
 */
export function PokedexJump({ collectionId, ranges }: { collectionId: string; ranges: readonly Range[] }) {
  const router = useRouter();
  const inputId = useId();
  const listboxId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState<IndexStatus>("idle");
  const [index, setIndex] = useState<SpeciesIndexEntry[] | null>(indexCache);
  const [active, setActive] = useState(0);
  const [message, setMessage] = useState("");

  const ensureIndex = useCallback(() => {
    if (index || status === "loading") return;
    setStatus("loading");
    void loadSpeciesIndex().then((entries) => {
      setIndex(entries);
      setStatus(entries ? "ready" : "error");
    });
  }, [index, status]);

  const suggestions = useMemo<SpeciesSuggestion[]>(() => {
    const trimmed = query.trim();
    if (!trimmed) return [];
    if (index) return searchSpecies(index, trimmed);
    const asNumber = parseNumberQuery(trimmed);
    return asNumber !== null ? [{ nationalDexNumber: asNumber, name: "", artworkPath: null }] : [];
  }, [index, query]);

  const options = useMemo(
    () => suggestions.map((item) => ({ ...item, plan: planPokedexJump(ranges, item.nationalDexNumber) })),
    [ranges, suggestions],
  );

  const choose = (position: number) => {
    const option = options[position];
    if (!option) return;
    if (option.plan.kind === "outside") {
      setMessage(
        `${option.name || `#${formatDex(option.nationalDexNumber)}`} não faz parte das gerações desta Pokédex. Você pode incluí-la em Ajustes.`,
      );
      return;
    }
    setMessage("");
    setOpen(false);
    setQuery("");
    inputRef.current?.blur();
    router.push(pokedexHref(collectionId, "todas", option.plan.generation, option.nationalDexNumber), { scroll: false });
  };

  const showList = open && query.trim().length > 0;
  const activeId = showList && options[active] ? `${listboxId}-${active}` : undefined;

  return (
    <div className={styles.jump}>
      <label htmlFor={inputId} className="sr-only">
        Buscar Pokémon nesta Pokédex por nome ou número
      </label>
      <Search className={styles.jumpIcon} aria-hidden="true" />
      <Input
        ref={inputRef}
        id={inputId}
        className={styles.jumpInput}
        placeholder="Buscar Pokémon ou nº"
        value={query}
        maxLength={QUICK_SEARCH_MAX_QUERY}
        autoComplete="off"
        role="combobox"
        aria-expanded={showList}
        aria-controls={listboxId}
        aria-activedescendant={activeId}
        aria-autocomplete="list"
        onFocus={() => {
          ensureIndex();
          setOpen(true);
        }}
        onPointerEnter={ensureIndex}
        onBlur={() => window.setTimeout(() => setOpen(false), 120)}
        onChange={(event) => {
          setQuery(event.target.value);
          setActive(0);
          setMessage("");
          setOpen(true);
        }}
        onKeyDown={(event) => {
          if (event.key === "ArrowDown") {
            event.preventDefault();
            setOpen(true);
            setActive((current) => Math.min(current + 1, Math.max(options.length - 1, 0)));
          } else if (event.key === "ArrowUp") {
            event.preventDefault();
            setActive((current) => Math.max(current - 1, 0));
          } else if (event.key === "Enter") {
            if (showList && options.length > 0) {
              event.preventDefault();
              choose(active);
            }
          } else if (event.key === "Escape") {
            if (query) {
              event.preventDefault();
              setQuery("");
              setMessage("");
            } else {
              setOpen(false);
            }
          }
        }}
      />
      {status === "loading" && query ? (
        <Loader2 className={`${styles.jumpAction} animate-spin motion-reduce:animate-none`} aria-hidden="true" />
      ) : query ? (
        <button
          type="button"
          className={styles.jumpClear}
          aria-label="Limpar busca"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => {
            setQuery("");
            setMessage("");
            inputRef.current?.focus();
          }}
        >
          <X className="h-4 w-4" aria-hidden="true" />
        </button>
      ) : null}

      <ul id={listboxId} role="listbox" aria-label="Pokémon encontrados" className={styles.jumpList} hidden={!showList}>
        {showList && options.length === 0 ? (
          <li className={styles.jumpEmpty} role="presentation">
            {status === "loading" ? "Carregando a Pokédex…" : "Nenhum Pokémon com esse nome ou número."}
          </li>
        ) : null}
        {showList
          ? options.map((option, position) => {
              const art = speciesArtworkUrl(option.artworkPath);
              const outside = option.plan.kind === "outside";
              return (
                <li
                  key={option.nationalDexNumber}
                  id={`${listboxId}-${position}`}
                  role="option"
                  aria-selected={position === active}
                  aria-disabled={outside || undefined}
                  className={styles.jumpOption}
                  data-outside={outside || undefined}
                  onMouseDown={(event) => event.preventDefault()}
                  onMouseEnter={() => setActive(position)}
                  onClick={() => choose(position)}
                >
                  <span className={styles.jumpThumb} aria-hidden="true">
                    {art ? (
                      // eslint-disable-next-line @next/next/no-img-element -- miniatura 32 px do mesmo WebP da Pokédex
                      <img src={art} alt="" width={32} height={32} loading="lazy" decoding="async" />
                    ) : (
                      <Pokeball className="h-4 w-4 text-foreground/20" strokeWidth={1.5} />
                    )}
                  </span>
                  <span className={styles.jumpNumber}>#{formatDex(option.nationalDexNumber)}</span>
                  <span className={styles.jumpName}>{option.name || "Ir para este número"}</span>
                  {outside ? <span className={styles.jumpNote}>fora desta Pokédex</span> : null}
                </li>
              );
            })
          : null}
      </ul>

      <p className="sr-only" role="status" aria-live="polite">
        {message || (showList ? `${options.length} ${options.length === 1 ? "resultado" : "resultados"}` : "")}
      </p>
      {message ? (
        <p className={styles.jumpMessage} role="presentation">
          {message}
        </p>
      ) : null}
    </div>
  );
}
