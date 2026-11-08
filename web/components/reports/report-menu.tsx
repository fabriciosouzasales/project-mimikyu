"use client";

import { createPortal } from "react-dom";
import {
  type FocusEvent as ReactFocusEvent,
  type KeyboardEvent,
  type PointerEvent as ReactPointerEvent,
  type RefObject,
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { BarChart3, Bookmark, ClipboardCheck, Clock3, Copy, Heart, Layers, Library, LibraryBig, ListX, PieChart, TrendingUp, Trophy, type LucideIcon } from "lucide-react";
import type { ReportMenuIcon, ReportMenuItem } from "@/lib/reports/collection-checklist";
import { MENU_PANEL_WIDTH, placeReportMenu } from "@/lib/reports/menu-placement";
import styles from "./report-menu.module.css";

const ICONS: Record<ReportMenuIcon, LucideIcon> = {
  checklist: ClipboardCheck,
  missing: ListX,
  value: BarChart3,
  wish: Bookmark,
  favorite: Heart,
  top: Trophy,
  duplicates: Copy,
  distribution: PieChart,
  inventory: Library,
  "inventory-sets": Layers,
  collections: LibraryBig,
  upcoming: Clock3,
  evolution: TrendingUp,
};


/**
 * Menu de Relatórios (V1-14 R1-A UX REDIRECTION-02) — menu contextual compacto que nasce da
 * ação "Relatórios" da cápsula do cabeçalho. Reutilizável (Acervo e Locais depois): recebe só
 * dados (`ReportMenuItem[]`) e devolve a escolha por `onSelect` — quem chama decide abrir o
 * relatório em sobreposição, sem sair da página.
 *
 * Densidade baixa: um grupo rotulado pelo contexto, uma linha por relatório (ícone, nome e uma
 * prévia curta), motivo só quando indisponível; nenhum texto decorativo. Cabe mais relatórios
 * sem mudar a forma (a lista cresce; grupos novos entram com o mesmo rótulo).
 *
 * Continuidade com a cápsula: o painel aparece logo abaixo dela, com um traço dourado alinhado
 * ao centro do gatilho — o mesmo dourado do indicador que fica na ação aberta.
 *
 * Teclado: botão com `aria-haspopup="menu"`/`aria-expanded`; seta para baixo abre; lista
 * `role="menu"` com `menuitem`; setas/Home/End movem o foco, Esc fecha e devolve o foco, Tab
 * fecha. Item indisponível continua focável (`aria-disabled`) e diz o porquê.
 * `prefers-reduced-motion` = sem deslizamento; `prefers-reduced-transparency` = opaco.
 * Celular (≤ 640 px): folha inferior com véu, alvos ≥ 44 px.
 */
export function ReportMenu({
  contextLabel,
  items,
  onSelect,
  triggerRef,
  open,
  onOpenChange,
}: {
  /** Rótulo do grupo — ex.: "Desta coleção". */
  contextLabel: string;
  items: ReportMenuItem[];
  onSelect: (id: string) => void;
  /** Gatilho (vive na cápsula); o menu se ancora nele e devolve o foco a ele. */
  triggerRef: RefObject<HTMLButtonElement | null>;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [anchor, setAnchor] = useState<{ top: number; left: number; notch: number } | null>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const glideRef = useRef<HTMLSpanElement>(null);
  const titleId = useId();

  const itemNodes = useCallback(
    () => Array.from(listRef.current?.querySelectorAll<HTMLElement>("[data-menu-item]") ?? []),
    [],
  );

  /** A pílula desliza até o item (só transform/altura dela; sem layout dos vizinhos). */
  const glideTo = useCallback((node: HTMLElement | null) => {
    const glide = glideRef.current;
    if (!glide) return;
    if (!node) {
      glide.style.opacity = "0";
      return;
    }
    glide.style.transform = `translateY(${node.offsetTop}px)`;
    glide.style.height = `${node.offsetHeight}px`;
    glide.style.opacity = "1";
  }, []);

  const close = useCallback(
    (restoreFocus: boolean) => {
      onOpenChange(false);
      setAnchor(null);
      if (restoreFocus) triggerRef.current?.focus();
    },
    [onOpenChange, triggerRef],
  );

  const placed = anchor !== null;
  const place = useCallback(() => {
    const trigger = triggerRef.current;
    if (!trigger) return;
    const rect = trigger.getBoundingClientRect();
    // Logo abaixo da cápsula (o gatilho mora dentro dela). Largura útil sem a barra de rolagem
    // (`clientWidth`): o painel nunca fica sob ela; gatilho no canto direito → painel alinhado à
    // borda direita da cápsula (regra em lib/reports/menu-placement.ts).
    const capsule = trigger.parentElement?.getBoundingClientRect() ?? rect;
    const { top, left, notch } = placeReportMenu({
      triggerLeft: rect.left,
      triggerWidth: rect.width,
      capsuleRight: capsule.right,
      capsuleBottom: capsule.bottom,
      viewportWidth: document.documentElement.clientWidth,
      panelWidth: Math.min(MENU_PANEL_WIDTH, window.innerWidth - 16), // = min(18rem, 100vw − 1rem) do CSS
    });
    setAnchor({ top, left, notch });
  }, [triggerRef]);

  useLayoutEffect(() => {
    if (!open) return;
    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, { capture: true, passive: true });
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, { capture: true });
    };
  }, [open, place]);

  // Ao abrir: foco no primeiro item disponível (ou no primeiro) e a pílula já assentada nele.
  useLayoutEffect(() => {
    if (!open || !placed) return;
    const nodes = itemNodes();
    const start = nodes.find((node) => node.getAttribute("aria-disabled") !== "true") ?? nodes[0] ?? null;
    const glide = glideRef.current;
    if (glide) glide.dataset.snap = "true";
    glideTo(start);
    start?.focus({ preventScroll: true });
    const frame = requestAnimationFrame(() => {
      if (glide) delete glide.dataset.snap;
    });
    return () => cancelAnimationFrame(frame);
  }, [open, placed, glideTo, itemNodes]);

  // Clique/toque fora fecha (sem roubar o foco de onde a pessoa clicou).
  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as Node;
      if (!triggerRef.current?.contains(target) && !panelRef.current?.contains(target)) close(false);
    };
    document.addEventListener("pointerdown", onPointerDown);
    return () => document.removeEventListener("pointerdown", onPointerDown);
  }, [open, close, triggerRef]);

  function onMenuKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const nodes = itemNodes();
    const index = nodes.indexOf(document.activeElement as HTMLElement);
    let next = -1;
    if (event.key === "ArrowDown") next = index < 0 ? 0 : (index + 1) % nodes.length;
    else if (event.key === "ArrowUp") next = index < 0 ? nodes.length - 1 : (index - 1 + nodes.length) % nodes.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = nodes.length - 1;
    else if (event.key === "Escape") {
      event.preventDefault();
      close(true);
      return;
    } else if (event.key === "Tab") {
      close(false);
      return;
    }
    const target = next >= 0 ? nodes[next] : undefined;
    if (target) {
      event.preventDefault();
      target.focus();
    }
  }

  if (!open || !anchor) return null;

  return createPortal(
    <div className={styles.layer}>
      <div className={styles.scrim} aria-hidden="true" onClick={() => close(true)} />
      <div
        ref={panelRef}
        className={styles.panel}
        role="menu"
        aria-labelledby={titleId}
        onKeyDown={onMenuKeyDown}
        style={{ top: anchor.top, left: anchor.left, ["--notch-x" as string]: `${anchor.notch}px` }}
      >
        <span className={styles.notch} aria-hidden="true" />
        <span className={styles.grabber} aria-hidden="true" />
        <p className={styles.group} id={titleId}>
          {contextLabel}
        </p>
        <div
          ref={listRef}
          className={styles.list}
          onPointerLeave={() => {
            const current = itemNodes().find((node) => node === document.activeElement) ?? null;
            glideTo(current);
          }}
        >
          <span ref={glideRef} className={styles.glide} aria-hidden="true" />
          {items.map((item) => {
            const Icon = ICONS[item.icon];
            const disabled = Boolean(item.disabledReason);
            return (
              <button
                key={item.id}
                type="button"
                role="menuitem"
                data-menu-item="true"
                className={styles.item}
                aria-disabled={disabled || undefined}
                tabIndex={-1}
                onPointerEnter={(event: ReactPointerEvent<HTMLElement>) => glideTo(event.currentTarget)}
                onFocus={(event: ReactFocusEvent<HTMLElement>) => glideTo(event.currentTarget)}
                onClick={() => {
                  if (disabled) return;
                  close(true);
                  onSelect(item.id);
                }}
              >
                <Icon className={styles.itemIcon} aria-hidden="true" />
                <span className={styles.itemText}>
                  <span className={styles.itemLabel}>{item.label}</span>
                  {item.disabledReason ? <span className={styles.itemReason}>{item.disabledReason}</span> : null}
                </span>
                {item.metric && !disabled ? <span className={styles.itemMetric}>{item.metric}</span> : null}
              </button>
            );
          })}
        </div>
      </div>
    </div>,
    document.body,
  );
}
