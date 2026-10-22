"use client";

import Link from "next/link";
import { Check, CheckSquare, MapPin, X } from "lucide-react";
import { type ReactNode, createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { formatCount } from "@/lib/colecoes/acervo";
import { MOVE_KEYS_MAX, moveSelectionSummary } from "@/lib/colecoes/acervo-move";
import {
  type SelectedItem,
  type Selection,
  emptySelection,
  isSelected,
  pageFullySelected,
  reconcileScope,
  removeKeys,
  selectPage,
  selectionTotals,
  toggleItem,
  unselectPage,
} from "@/lib/colecoes/acervo-selection";
import type { StorageLocation } from "@/lib/colecoes/storage-locations";
import { AcervoMovePanel } from "./acervo-move-panel";
import styles from "./acervo.module.css";
import local from "./acervo-selection.module.css";

/**
 * WHERE-05B — modo seleção da galeria de Meu acervo.
 *
 * Fora do modo seleção NADA muda: cada carta continua sendo o mesmo link para
 * o detalhe (`AcervoTileShell` devolve exatamente o `<Link>` homologado).
 * Dentro do modo, a carta vira um botão de alternância (`aria-pressed`) —
 * Tab/Enter/Espaço marcam e desmarcam; a barra no rodapé da galeria mostra
 * "N cartas · M exemplares" (M indicativo) e as ações.
 *
 * O provedor fica na raiz da página: a navegação entre páginas (`?pagina=`)
 * troca só a busca da URL, e o App Router preserva o estado de componentes
 * cliente nesse caso — a seleção sobrevive à paginação (D3). Quando o escopo
 * (busca, Set, idioma, coleção, local) muda, a seleção é limpa com aviso.
 */

type Ctx = {
  active: boolean;
  selection: Selection;
  toggle(item: SelectedItem): void;
};

const SelectionContext = createContext<Ctx | null>(null);

export function AcervoSelectionProvider({
  scope,
  pageItems,
  locations,
  children,
}: {
  /** Assinatura canônica do escopo da galeria (`scopeSignature`). */
  scope: string;
  /** Cartas da página atual (para "selecionar esta página"). */
  pageItems: SelectedItem[];
  /** Locais do usuário (5219); `null` = indisponível. */
  locations: StorageLocation[] | null;
  children: ReactNode;
}) {
  const [active, setActive] = useState(false);
  const [selection, setSelection] = useState<Selection>(() => emptySelection(scope));
  const [notice, setNotice] = useState<{ tone: "success" | "warning"; text: string } | null>(null);

  // D3 — escopo diferente → seleção descartada, com aviso (nunca em silêncio).
  // Ajuste durante a renderização (padrão do React para estado derivado de prop).
  if (selection.scope !== scope) {
    const next = reconcileScope(selection, scope);
    setSelection(next.selection);
    setNotice(next.cleared ? { tone: "warning", text: "Os filtros ou a busca mudaram — a seleção foi limpa." } : null);
  }

  const toggle = useCallback(
    (item: SelectedItem) => {
      const next = toggleItem(selection, item);
      setSelection(next.selection);
      setNotice(next.capped ? { tone: "warning", text: `Você pode selecionar até ${formatCount(MOVE_KEYS_MAX)} cartas por vez.` } : null);
    },
    [selection],
  );

  const value = useMemo<Ctx>(() => ({ active, selection, toggle }), [active, selection, toggle]);

  const controls: Controls = {
    active,
    selection,
    notice,
    pageItems,
    locations,
    scope,
    start: () => {
      setNotice(null);
      setActive(true);
    },
    stop: () => {
      setActive(false);
      setNotice(null);
      setSelection(emptySelection(scope));
    },
    selectPage: () => {
      const next = selectPage(selection, pageItems);
      setSelection(next.selection);
      setNotice(
        next.skipped > 0
          ? { tone: "warning", text: `Limite de ${formatCount(MOVE_KEYS_MAX)} cartas atingido — ${formatCount(next.skipped)} desta página ficaram de fora.` }
          : null,
      );
    },
    unselectPage: () => setSelection((current) => unselectPage(current, pageItems.map((item) => item.key))),
    clear: () => {
      setNotice(null);
      setSelection(emptySelection(scope));
    },
    remove: (keys: string[]) => setSelection((current) => removeKeys(current, keys)),
    done: (text: string) => {
      setSelection(emptySelection(scope));
      setNotice({ tone: "success", text });
    },
  };

  return (
    <SelectionContext.Provider value={value}>
      <ControlsContext.Provider value={controls}>{children}</ControlsContext.Provider>
    </SelectionContext.Provider>
  );
}

type Controls = {
  active: boolean;
  selection: Selection;
  notice: { tone: "success" | "warning"; text: string } | null;
  pageItems: SelectedItem[];
  locations: StorageLocation[] | null;
  scope: string;
  start(): void;
  stop(): void;
  selectPage(): void;
  unselectPage(): void;
  clear(): void;
  remove(keys: string[]): void;
  done(text: string): void;
};

const ControlsContext = createContext<Controls | null>(null);

function useControls(): Controls {
  const ctx = useContext(ControlsContext);
  if (!ctx) throw new Error("AcervoSelectionProvider ausente");
  return ctx;
}

/**
 * A carta da galeria. Fora do modo seleção: o `<Link>` homologado, idêntico.
 * No modo seleção: botão de alternância com o mesmo conteúdo visual e uma
 * marca no canto (sem cor como único sinal: a marca muda de forma).
 */
export function AcervoTileShell({
  href,
  ariaLabel,
  itemKey,
  name,
  copies,
  children,
}: {
  href: string;
  ariaLabel: string;
  itemKey: string;
  name: string;
  /** Exemplares no recorte atual (indicativo). */
  copies: number;
  children: ReactNode;
}) {
  const ctx = useContext(SelectionContext);
  if (!ctx || !ctx.active) {
    return (
      <Link href={href} scroll={false} className={styles.tile} aria-label={ariaLabel}>
        {children}
      </Link>
    );
  }
  const selected = isSelected(ctx.selection, itemKey);
  return (
    <button
      type="button"
      className={`${styles.tile} ${local.selectable}`}
      aria-pressed={selected}
      aria-label={`${ariaLabel}. ${selected ? "Selecionada" : "Selecionar"}`}
      data-selected={selected || undefined}
      onClick={() => ctx.toggle({ key: itemKey, name, copies })}
    >
      {children}
      <span className={local.mark} aria-hidden="true">
        {selected ? <Check className="h-3.5 w-3.5" strokeWidth={3} /> : null}
      </span>
    </button>
  );
}

/** Botão "Selecionar" junto da contagem de resultados. */
export function AcervoSelectionToggle() {
  const controls = useControls();
  if (controls.active) return null;
  return (
    <Button variant="outline" size="sm" className={local.toggle} onClick={controls.start}>
      <CheckSquare className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
      Selecionar
    </Button>
  );
}

/**
 * Barra do modo seleção, no rodapé da galeria (fixa enquanto a galeria rola).
 * Contagem indicativa, selecionar/desmarcar esta página, limpar, mover, sair.
 */
export function AcervoSelectionBar() {
  const controls = useControls();
  const [panelOpen, setPanelOpen] = useState(false);
  const barRef = useRef<HTMLDivElement>(null);
  const { cards, copies } = selectionTotals(controls.selection);
  const pageKeys = controls.pageItems.map((item) => item.key);
  const allPage = pageFullySelected(controls.selection, pageKeys);

  // Ao entrar no modo, o foco vai para a barra (anúncio do modo e atalho para as ações).
  useEffect(() => {
    if (controls.active) barRef.current?.focus();
  }, [controls.active]);

  if (!controls.active) return null;

  return (
    <div
      ref={barRef}
      tabIndex={-1}
      role="region"
      aria-label="Seleção de cartas"
      className={local.bar}
    >
      <div className={local.barMain}>
        <p className={local.count} aria-live="polite" aria-atomic="true">
          {cards === 0 ? "Toque nas cartas para selecionar" : moveSelectionSummary(cards, copies)}
        </p>
        <div className={local.actions}>
          {pageKeys.length > 0 ? (
            <Button variant="ghost" size="sm" onClick={allPage ? controls.unselectPage : controls.selectPage}>
              {allPage ? "Desmarcar esta página" : "Selecionar esta página"}
            </Button>
          ) : null}
          {cards > 0 ? (
            <Button variant="ghost" size="sm" onClick={controls.clear}>
              Limpar
            </Button>
          ) : null}
          <Button
            size="sm"
            className="aria-disabled:pointer-events-none aria-disabled:opacity-50"
            aria-disabled={cards === 0 || undefined}
            onClick={() => cards > 0 && setPanelOpen(true)}
          >
            <MapPin className="mr-1.5 h-3.5 w-3.5" aria-hidden="true" />
            Mover…
          </Button>
          <Button variant="outline" size="sm" onClick={controls.stop} aria-label="Sair da seleção">
            <X className="h-3.5 w-3.5 sm:mr-1.5" aria-hidden="true" />
            <span className="max-sm:sr-only">Sair</span>
          </Button>
        </div>
      </div>
      <div aria-live="polite">
        {controls.notice ? <InlineFeedback tone={controls.notice.tone}>{controls.notice.text}</InlineFeedback> : null}
      </div>
      {panelOpen ? (
        <AcervoMovePanel
          selection={controls.selection}
          scope={controls.scope}
          locations={controls.locations}
          onClose={() => {
            setPanelOpen(false);
            barRef.current?.focus();
          }}
          onRemoveKeys={controls.remove}
          onDone={(text) => {
            controls.done(text);
          }}
        />
      ) : null}
    </div>
  );
}
