"use client";

import { Search, X } from "lucide-react";
import type { KeyboardEvent, PointerEvent } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { MockCardData } from "@/components/experimental/binder-spike/mock-card-face";
import { MockCardFace } from "@/components/experimental/binder-spike/mock-card-face";
import type { RealCardData } from "@/app/experimental/binder-nav-01/mock-data";
import { CARD_PICKER_ENTRIES, searchCardPickerEntries, type CardPickerEntry } from "@/app/experimental/binder-nav-01/card-picker-mock";
import { cn } from "@/lib/utils";
import { RealCardFace } from "./real-card-face";

/**
 * BINDER-ADD-REPLACE-CARD-01 (2026-08-29) — Card Picker: experiência
 * client-facing de seleção de carta para os fluxos ADICIONAR (slot vazio) e
 * SUBSTITUIR (slot ocupado), pedido de Fabrício após o encerramento da
 * frente visual da Collection Library ("retomar implementação funcional do
 * Binder").
 *
 * Reaproveita, em vez de recriar, a infraestrutura já aprovada:
 *  - MESMO shell de modal isolado de `card-detail-modal.tsx` (overlay
 *    translúcido + blur, `role="dialog"`, foco preso manualmente — focus
 *    trap por `Tab`/`Shift+Tab` sobre `FOCUSABLE_SELECTOR` —, `Escape`
 *    fecha, `stopPropagation()` bloqueando TODAS as teclas e gestos de
 *    ponteiro para não vazar para a navegação de spread/swipe do Binder por
 *    baixo). Cópia local deliberada (não import), mesmo padrão de
 *    isolamento experimental já usado em todo o resto do BINDER-NAV-01 —
 *    ver nota completa em `card-detail-modal.tsx`.
 *  - MESMOS tokens de tema `--binder-modal-*` (`globals.css`, escopados via
 *    `.binder-nav-01-scope`) — o Picker abre sobre o Binder (sempre escuro)
 *    com uma superfície clara/premium nos dois temas do app, igual ao Card
 *    Detail.
 *  - MESMO padrão ARIA combobox+listbox já usado em produção pela busca
 *    global (`components/app-shell/global-search.tsx`, `SearchCombobox`):
 *    `role="combobox"` no input, `role="listbox"`/`role="option"` nos
 *    resultados, `aria-activedescendant`, índice roving por teclado. Aqui a
 *    busca é 100% local/síncrona (18 cartas do pool `ME2_CARDS`) — sem
 *    debounce/fetch/AbortController, que só fazem sentido para a busca
 *    global real (API `/api/cards/search`).
 *  - `RealCardFace`/`MockCardFace` para a miniatura de cada resultado —
 *    mesmos componentes que já renderizam a carta dentro do bolso do Binder.
 *
 * ESCOPO V1 do Picker (pedido explícito): busca por nome/número/Set/
 * variant (`searchCardPickerEntries`, `card-picker-mock.ts`), resultados
 * visuais (grid com artwork), navegação por teclado e clique — SEM filtros
 * avançados, sem multi-select, sem DnD, sem Wishlist.
 *
 * Navegação por teclado no grid (simplificação V1, documentada): como o
 * pool tem só 18 itens e o pedido explícito é "não criar filtros avançados
 * ainda", a navegação trata os resultados como uma sequência 1D — não uma
 * grade 2D real. `ArrowRight`/`ArrowDown` avançam, `ArrowLeft`/`ArrowUp`
 * voltam, `Home`/`End` vão para o primeiro/último, `Enter` seleciona o item
 * ativo. Suficiente para um pool pequeno; uma grade 2D de verdade (mapear
 * `ArrowUp`/`ArrowDown` por coluna) só se justifica se o Picker crescer para
 * centenas de resultados — não é o caso aqui.
 *
 * MODO ADD vs. REPLACE: mesmo componente, prop `mode`. Em `replace`, o
 * cabeçalho mostra a carta ATUAL do slot antes da busca (pedido explícito:
 * "mostrar claramente a carta atual") — miniatura + nome, sem ação própria
 * (não é clicável, é só contexto). Selecionar uma nova carta em QUALQUER
 * modo chama o MESMO `onSelect(card)` — quem decide se é "adicionar" ou
 * "substituir" na prática é o chamador (`binder-pages-nav.tsx`,
 * `handleSelectPickerCard`), que já sabe em qual slot está operando; o
 * Picker em si não sabe nem precisa saber a mecânica de armazenamento.
 *
 * Disponibilidade de cópia (pedido explícito: "o picker deve deixar claro
 * quando existe cópia disponível... Collection apenas aloca Inventory
 * Items"): cada resultado mostra um selo "N disponíveis" ou "Sem cópia
 * disponível" (mock, ver `card-picker-mock.ts`); com 0 disponíveis, o botão
 * do resultado fica desabilitado — não é possível selecionar uma carta sem
 * cópia mockada disponível, mesmo neste spike sem Inventory real.
 */

const FOCUSABLE_SELECTOR = 'button:not([disabled]), [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';

export function CardPickerModal({
  mode,
  currentCard,
  onSelect,
  onClose,
}: {
  mode: "add" | "replace";
  currentCard?: MockCardData | RealCardData;
  onSelect: (card: RealCardData) => void;
  onClose: () => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listboxId = "card-picker-listbox";

  const [query, setQuery] = useState("");
  const [activeIndex, setActiveIndex] = useState(0);

  const results = useMemo(() => searchCardPickerEntries(CARD_PICKER_ENTRIES, query), [query]);

  // Índice ativo sempre válido dentro dos resultados atuais — reseta ao
  // digitar (resultado antigo pode ter saído da lista filtrada).
  useEffect(() => {
    setActiveIndex(0);
  }, [query]);

  // Foco inicial no campo de busca — mesmo padrão do `autoFocus` já usado no
  // modo imersivo mobile de `global-search.tsx`, mas via `ref` (o container
  // do Card Detail usa o mesmo racional de foco inicial gerenciado por
  // efeito, não pelo atributo HTML puro).
  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  const moveActive = useCallback(
    (delta: number) => {
      setActiveIndex((current) => {
        if (results.length === 0) return 0;
        return (current + delta + results.length) % results.length;
      });
    },
    [results.length],
  );

  const selectEntry = useCallback(
    (entry: CardPickerEntry) => {
      if (entry.copiesAvailable <= 0) return;
      onSelect(entry.card);
    },
    [onSelect],
  );

  const handleKeyDown = useCallback(
    (event: KeyboardEvent<HTMLDivElement>) => {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        onClose();
        return;
      }
      if (event.key === "ArrowRight" || event.key === "ArrowDown") {
        event.preventDefault();
        moveActive(1);
        event.stopPropagation();
        return;
      }
      if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
        event.preventDefault();
        moveActive(-1);
        event.stopPropagation();
        return;
      }
      if (event.key === "Home") {
        event.preventDefault();
        setActiveIndex(0);
        event.stopPropagation();
        return;
      }
      if (event.key === "End") {
        event.preventDefault();
        setActiveIndex(Math.max(0, results.length - 1));
        event.stopPropagation();
        return;
      }
      if (event.key === "Enter") {
        const entry = results[activeIndex];
        if (entry) {
          event.preventDefault();
          selectEntry(entry);
        }
        event.stopPropagation();
        return;
      }
      if (event.key === "Tab") {
        const root = containerRef.current;
        if (root) {
          const focusable = Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR)).filter(
            (el) => el.getClientRects().length > 0,
          );
          if (focusable.length > 0) {
            const first = focusable[0]!;
            const last = focusable[focusable.length - 1]!;
            if (event.shiftKey && document.activeElement === first) {
              event.preventDefault();
              last.focus();
            } else if (!event.shiftKey && document.activeElement === last) {
              event.preventDefault();
              first.focus();
            }
          }
        }
        event.stopPropagation();
        return;
      }
      // Blanket stop — mesmo racional de `card-detail-modal.tsx`: nenhuma
      // tecla deve vazar para a navegação de spread do Binder por baixo.
      event.stopPropagation();
    },
    [onClose, moveActive, results, activeIndex, selectEntry],
  );

  // Mesmo racional de `card-detail-modal.tsx` para gestos de ponteiro — o
  // wrapper de swipe horizontal do Binder está mais acima na árvore do DOM.
  const stopPointerPropagation = useCallback((event: PointerEvent) => event.stopPropagation(), []);

  const activeOptionId = results[activeIndex] ? `${listboxId}-option-${activeIndex}` : undefined;
  const title = mode === "add" ? "Adicionar carta" : "Substituir carta";

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-6"
      onPointerDown={stopPointerPropagation}
      onPointerUp={stopPointerPropagation}
      onClick={onClose}
    >
      <div aria-hidden className="absolute inset-0 bg-black/72 backdrop-blur-sm" />

      <div
        ref={containerRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        onKeyDown={handleKeyDown}
        onClick={(event) => event.stopPropagation()}
        className="relative z-10 flex w-full max-w-2xl flex-col overflow-hidden rounded-2xl outline-none"
        style={{
          background: "hsl(var(--binder-modal-bg))",
          boxShadow: "var(--binder-modal-shadow)",
          border: "1px solid var(--binder-modal-border)",
          maxHeight: "min(88dvh, 640px)",
        }}
      >
        <div className="flex items-start justify-between gap-3 px-5 pt-5 sm:px-6">
          <div className="min-w-0">
            <h2 className="text-lg font-semibold leading-tight text-black/90 dark:text-white">{title}</h2>
            {mode === "replace" && currentCard ? (
              <div className="mt-2 flex items-center gap-2 rounded-lg border border-black/10 bg-black/[0.04] px-2 py-1.5 dark:border-white/10 dark:bg-white/5">
                {/* BINDER-CARD-ASPECT-RATIO-01 — era `h-9 w-7` (36×28px,
                    ratio 0.778), um valor fixo em pixels que não correspondia
                    nem à convenção antiga do design (5:7 = 0.714) nem à
                    proporção real do asset (8:11 = 0.727) — o pior caso
                    encontrado na varredura, cortando mais que qualquer outro
                    ponto do app. Trocado por `aspect-[8/11]` com `h-9` fixo:
                    a largura passa a ser derivada da proporção real (a caixa
                    vira um item flex com altura definida e largura `auto`,
                    que o `aspect-ratio` resolve nativamente), sem mudar o
                    espaço ocupado ao lado do texto (~26px em vez de 28px). */}
                <div className="aspect-[8/11] h-9 shrink-0 overflow-hidden rounded">
                  {"imageUrl" in currentCard ? <RealCardFace card={currentCard} /> : <MockCardFace card={currentCard} />}
                </div>
                <p className="min-w-0 truncate text-xs text-black/60 dark:text-white/50">
                  Carta atual: <span className="text-black/85 dark:text-white/80">{currentCard.name}</span>
                </p>
              </div>
            ) : (
              <p className="mt-1 text-sm text-black/60 dark:text-white/50">Escolha uma carta para este slot vazio.</p>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Cancelar seleção"
            className="flex h-9 w-9 flex-shrink-0 items-center justify-center rounded-full border border-black/18 bg-black/[0.06] text-black/65 transition-colors hover:bg-black/[0.14] hover:text-black/95 focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-2 focus-visible:ring-offset-[hsl(var(--binder-modal-bg))] dark:border-white/12 dark:bg-white/5 dark:text-white/60 dark:hover:bg-white/10 dark:hover:text-white"
          >
            <X className="h-4 w-4" aria-hidden />
          </button>
        </div>

        <div className="relative mt-3 px-5 sm:px-6">
          <Search className="pointer-events-none absolute left-8 top-1/2 h-4 w-4 -translate-y-1/2 text-black/35 dark:text-white/30 sm:left-9" aria-hidden />
          <input
            ref={inputRef}
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Nome, número, Set ou variant…"
            role="combobox"
            aria-expanded
            aria-controls={listboxId}
            aria-activedescendant={activeOptionId}
            aria-autocomplete="list"
            aria-label="Pesquisar carta por nome, número, Set ou variant"
            autoComplete="off"
            className="h-10 w-full rounded-lg border border-black/15 bg-white/70 pl-9 pr-3 text-sm text-black/90 outline-none placeholder:text-black/35 focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] dark:border-white/12 dark:bg-white/[0.06] dark:text-white/90 dark:placeholder:text-white/30"
          />
        </div>

        <div id={listboxId} role="listbox" aria-label="Resultados da busca" className="mt-3 min-h-0 flex-1 overflow-y-auto px-5 pb-5 sm:px-6">
          {results.length === 0 ? (
            <p className="px-1 py-6 text-center text-sm text-black/45 dark:text-white/35">Nenhuma carta encontrada.</p>
          ) : (
            <div className="grid grid-cols-3 gap-2.5 sm:grid-cols-4">
              {results.map((entry, index) => {
                const isActive = index === activeIndex;
                const unavailable = entry.copiesAvailable <= 0;
                return (
                  <button
                    key={entry.card.id}
                    id={`${listboxId}-option-${index}`}
                    type="button"
                    role="option"
                    aria-selected={isActive}
                    aria-disabled={unavailable || undefined}
                    disabled={unavailable}
                    onMouseEnter={() => setActiveIndex(index)}
                    onClick={() => selectEntry(entry)}
                    className={cn(
                      "flex flex-col overflow-hidden rounded-lg border text-left outline-none transition-colors",
                      unavailable
                        ? "cursor-not-allowed border-black/8 bg-black/[0.02] opacity-50 dark:border-white/6 dark:bg-white/[0.02]"
                        : isActive
                          ? "border-[hsl(40_70%_62%)] bg-[hsl(40_70%_62%_/_0.08)]"
                          : "border-black/10 bg-black/[0.02] hover:border-black/25 dark:border-white/10 dark:bg-white/[0.03] dark:hover:border-white/25",
                    )}
                  >
                    {/* BINDER-CARD-ASPECT-RATIO-01 — `aspect-[5/7]` →
                        `aspect-[8/11]`, proporção real do asset. */}
                    <div className="aspect-[8/11] w-full overflow-hidden">
                      <RealCardFace card={entry.card} />
                    </div>
                    <div className="space-y-0.5 px-2 py-1.5">
                      <p className="truncate text-[11px] font-medium text-black/85 dark:text-white/85">{entry.card.name}</p>
                      <p className="truncate text-[10px] text-black/50 dark:text-white/40">
                        {entry.setCode} · Nº {entry.number}
                        {entry.variantLabel ? ` · ${entry.variantLabel}` : ""}
                      </p>
                      <p
                        className={cn(
                          "text-[10px] font-medium",
                          unavailable ? "text-black/35 dark:text-white/30" : "text-[hsl(32_70%_40%)] dark:text-[hsl(40_75%_68%)]",
                        )}
                      >
                        {unavailable ? "Sem cópia disponível" : `${entry.copiesAvailable} ${entry.copiesAvailable === 1 ? "disponível" : "disponíveis"}`}
                      </p>
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>

        <p aria-live="polite" className="sr-only">
          {results.length} {results.length === 1 ? "carta encontrada" : "cartas encontradas"}.
        </p>
      </div>
    </div>
  );
}
