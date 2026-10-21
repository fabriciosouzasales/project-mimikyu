"use client";

import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ChevronDown, Loader2, Search, X } from "lucide-react";
import { Pokeball } from "@/components/icons/pokeball-icon";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { speciesArtworkUrl } from "@/lib/pokedex/artwork";
import { type PokedexContext, formatCount, formatDexNumber, speciesDetailHref } from "@/lib/pokedex/format";
import {
  QUICK_SEARCH_MAX_QUERY,
  type SpeciesIndexEntry,
  parseNumberQuery,
  searchSpecies,
} from "@/lib/pokedex/species-search";
import { speciesIndex } from "@/lib/pokedex/species-index-client";
import styles from "./species-quick-search.module.css";

type IndexStatus = "idle" | "loading" | "ready" | "error";
type Option = { nationalDexNumber: number; name: string | null; artworkPath: string | null };

/**
 * Busca rápida da ficha da espécie (Pokédex P3b, 2026-10-12).
 *
 * O indicador "Nº 0006 de 1.025" do canto superior direito vira o gatilho:
 * abre um painel com campo e sugestões (número, nome, miniatura) e troca de
 * espécie sem voltar à Pokédex Nacional, preservando o contexto da galeria
 * (`?q`, `?geracao`).
 *
 * - Padrão ARIA: botão com `aria-haspopup="dialog"` → painel não modal com
 *   combobox/listbox (`aria-activedescendant`; o foco fica no campo).
 * - Teclado: ↑ ↓ percorrem, Enter abre, Esc fecha e devolve o foco ao botão;
 *   Tab para fora fecha. As setas não disparam os atalhos ← → da ficha
 *   (SpeciesKeyboardNav ignora campos de texto e diálogos).
 * - Dados: índice compacto (~1.025 linhas) buscado só na primeira intenção
 *   (hover, foco ou abertura), filtrado localmente — sem ida ao servidor por
 *   tecla e nenhum custo no carregamento da ficha. Sem o índice (falha), a
 *   busca por número continua funcionando.
 * - Miniaturas: o mesmo WebP 320 da galeria (URL imutável, já em cache na
 *   maior parte das vezes), lazy, no máximo 8 por vez.
 */
export function SpeciesQuickSearch({
  current,
  total,
  context,
}: {
  current: number;
  total: number | null;
  context: PokedexContext;
}) {
  const router = useRouter();
  const panelId = useId();
  const listboxId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLUListElement>(null);

  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [activeIndex, setActiveIndex] = useState(0);
  const [index, setIndex] = useState<SpeciesIndexEntry[] | null>(speciesIndex.cached());
  const [status, setStatus] = useState<IndexStatus>(speciesIndex.cached() ? "ready" : "idle");

  const number = formatDexNumber(current);
  const totalLabel = total ? formatCount(total) : null;

  const requestIndex = useCallback(() => {
    if (speciesIndex.cached()) {
      setIndex(speciesIndex.cached());
      setStatus("ready");
      return;
    }
    setStatus((previous) => (previous === "ready" ? previous : "loading"));
    void speciesIndex.load().then((entries) => {
      setIndex(entries);
      setStatus(entries ? "ready" : "error");
    });
  }, []);

  const options = useMemo<Option[]>(() => {
    const trimmed = query.trim();
    if (!trimmed) return [];
    if (index) return searchSpecies(index, trimmed);
    // Sem índice (carregando ou falhou): o número ainda leva direto à ficha.
    const asNumber = parseNumberQuery(trimmed);
    if (asNumber !== null && (total === null || asNumber <= total)) {
      return [{ nationalDexNumber: asNumber, name: null, artworkPath: null }];
    }
    return [];
  }, [index, query, total]);

  // Toda mudança de resultados volta o destaque para a primeira sugestão:
  // Enter sempre abre o melhor resultado.
  useEffect(() => {
    setActiveIndex(0);
  }, [options]);

  useEffect(() => {
    if (!open) return;
    const option = listRef.current?.querySelector<HTMLElement>(`[data-index="${activeIndex}"]`);
    option?.scrollIntoView({ block: "nearest" });
  }, [activeIndex, open]);

  const close = useCallback((returnFocus: boolean) => {
    setOpen(false);
    setQuery("");
    if (returnFocus) triggerRef.current?.focus();
  }, []);

  // Chegou outra espécie (seleção, vizinhos, atalhos ← →): painel fechado e limpo.
  useEffect(() => {
    setOpen(false);
    setQuery("");
  }, [current]);

  // Foco no campo ao abrir.
  useEffect(() => {
    if (!open) return;
    const frame = requestAnimationFrame(() => inputRef.current?.focus());
    return () => cancelAnimationFrame(frame);
  }, [open]);

  // Clique/toque fora fecha (sem roubar o foco do que foi tocado).
  useEffect(() => {
    if (!open) return;
    function onPointerDown(event: PointerEvent) {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) close(false);
    }
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [open, close]);

  function openPanel() {
    requestIndex();
    setOpen(true);
  }

  function select(option: Option | undefined) {
    if (!option) return;
    if (option.nationalDexNumber === current) {
      close(true);
      return;
    }
    setOpen(false);
    setQuery("");
    router.push(speciesDetailHref(option.nationalDexNumber, context));
  }

  function onInputKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.nativeEvent.isComposing) return;
    if (event.key === "ArrowDown") {
      event.preventDefault();
      if (options.length > 0) setActiveIndex((value) => (value + 1) % options.length);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      if (options.length > 0) setActiveIndex((value) => (value - 1 + options.length) % options.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      select(options[activeIndex]);
    }
  }

  const trimmed = query.trim();
  const activeOptionId = options.length > 0 ? `${listboxId}-${activeIndex}` : undefined;
  const waitingForNames = trimmed !== "" && options.length === 0 && (status === "loading" || status === "idle");
  const nameSearchUnavailable = trimmed !== "" && options.length === 0 && status === "error";
  const noResults = trimmed !== "" && options.length === 0 && status === "ready";

  const announcement = !open
    ? ""
    : options.length > 0
      ? `${options.length} ${options.length === 1 ? "espécie encontrada" : "espécies encontradas"}`
      : noResults
        ? "Nenhuma espécie encontrada"
        : nameSearchUnavailable
          ? "Busca por nome indisponível; use o número nacional"
          : "";

  return (
    <div
      ref={rootRef}
      className={styles.root}
      onKeyDown={(event) => {
        if (event.key === "Escape" && open) {
          event.preventDefault();
          event.stopPropagation();
          close(true);
        }
      }}
      onBlur={(event) => {
        // Tab para fora do painel fecha; foco que continua dentro não.
        if (open && !event.currentTarget.contains(event.relatedTarget as Node | null) && event.relatedTarget !== null) {
          close(false);
        }
      }}
    >
      <button
        ref={triggerRef}
        type="button"
        className={styles.trigger}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? panelId : undefined}
        aria-label={`Nº ${number}${totalLabel ? ` de ${totalLabel}` : ""}. Buscar outra espécie`}
        onPointerEnter={requestIndex}
        onFocus={requestIndex}
        onClick={() => (open ? close(true) : openPanel())}
        onKeyDown={(event) => {
          if ((event.key === "ArrowDown" || event.key === "ArrowUp") && !open) {
            event.preventDefault();
            openPanel();
          }
        }}
      >
        <Search className={styles.triggerIcon} aria-hidden="true" />
        <span className={styles.triggerText}>
          Nº {number}
          {totalLabel ? <span className={styles.triggerTotal}> de {totalLabel}</span> : null}
        </span>
        <ChevronDown className={cn(styles.triggerIcon, styles.chevron)} aria-hidden="true" />
      </button>

      {open ? (
        <div id={panelId} role="dialog" aria-label="Buscar espécie" className={styles.panel}>
          <div className={styles.field}>
            <Search className={styles.fieldIcon} aria-hidden="true" />
            <Input
              ref={inputRef}
              type="text"
              role="combobox"
              aria-expanded={options.length > 0}
              aria-controls={listboxId}
              aria-activedescendant={activeOptionId}
              aria-autocomplete="list"
              aria-label="Nome ou número nacional"
              placeholder="Nome ou número — ex.: Pikachu, 25"
              autoComplete="off"
              autoCorrect="off"
              autoCapitalize="none"
              spellCheck={false}
              enterKeyHint="go"
              maxLength={QUICK_SEARCH_MAX_QUERY}
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              onKeyDown={onInputKeyDown}
              className="h-11 pl-10 pr-10 text-base sm:text-sm"
            />
            {status === "loading" && trimmed !== "" ? (
              <Loader2 className={cn(styles.fieldAction, styles.spinner)} aria-hidden="true" />
            ) : query ? (
              <button
                type="button"
                className={styles.clear}
                aria-label="Limpar busca"
                onClick={() => {
                  setQuery("");
                  inputRef.current?.focus();
                }}
              >
                <X className="h-4 w-4" aria-hidden="true" />
              </button>
            ) : null}
          </div>

          <ul ref={listRef} id={listboxId} role="listbox" aria-label="Espécies encontradas" className={styles.list}>
            {options.map((option, position) => {
              const thumb = speciesArtworkUrl(option.artworkPath);
              const isCurrent = option.nationalDexNumber === current;
              return (
                <li
                  key={option.nationalDexNumber}
                  id={`${listboxId}-${position}`}
                  data-index={position}
                  role="option"
                  aria-selected={position === activeIndex}
                  className={styles.option}
                  onMouseDown={(event) => event.preventDefault()}
                  onMouseMove={() => {
                    if (position !== activeIndex) setActiveIndex(position);
                  }}
                  onClick={() => select(option)}
                >
                  <span className={styles.thumb} aria-hidden="true">
                    {thumb ? (
                      // eslint-disable-next-line @next/next/no-img-element -- WebP 320 já otimizado, URL imutável (mesmo arquivo da galeria)
                      <img src={thumb} alt="" width={40} height={40} loading="lazy" decoding="async" draggable={false} />
                    ) : (
                      <Pokeball className={styles.thumbFallback} strokeWidth={1.3} />
                    )}
                  </span>
                  <span className={styles.optionNumber}>
                    <span className="sr-only">Nº </span>
                    {formatDexNumber(option.nationalDexNumber)}
                  </span>
                  <span className={styles.optionName}>{option.name ?? `Ir para o Nº ${formatDexNumber(option.nationalDexNumber)}`}</span>
                  {isCurrent ? <span className={styles.currentTag}>Atual</span> : null}
                </li>
              );
            })}
          </ul>

          {trimmed === "" ? (
            <p className={styles.status}>Digite o nome ou o número nacional da espécie.</p>
          ) : waitingForNames ? (
            <p className={styles.status}>Carregando a Pokédex…</p>
          ) : noResults ? (
            <p className={styles.status}>
              Nenhuma espécie encontrada para <strong className={styles.statusQuery}>“{trimmed}”</strong>.
            </p>
          ) : nameSearchUnavailable ? (
            <p className={styles.status}>
              Não foi possível carregar os nomes agora. Busque pelo número ou{" "}
              <button type="button" className={styles.retry} onClick={requestIndex}>
                tente de novo
              </button>
              .
            </p>
          ) : null}

          <div className={styles.footer} aria-hidden="true">
            <span>
              <kbd className={styles.kbd}>↑</kbd>
              <kbd className={styles.kbd}>↓</kbd> navegar
            </span>
            <span>
              <kbd className={styles.kbd}>Enter</kbd> abrir
            </span>
            <span>
              <kbd className={styles.kbd}>Esc</kbd> fechar
            </span>
          </div>
        </div>
      ) : null}

      <span className="sr-only" role="status" aria-live="polite">
        {announcement}
      </span>
    </div>
  );
}
