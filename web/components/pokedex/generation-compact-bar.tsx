"use client";

import Link from "next/link";
import { ChevronDown } from "lucide-react";
import { useCallback, useEffect, useId, useRef, useState } from "react";
import { type PokedexOrigin, pokedexHref } from "@/lib/pokedex/format";
import { resolveVisibleGeneration, type SectionBox } from "@/lib/pokedex/visible-generation";
import styles from "./generation-compact-bar.module.css";

/** Mesmo corte da barra (generation-compact-bar.module.css): só no desktop. */
const DESKTOP_QUERY = "(min-width: 1024px)";
/** Distância da barra ao topo do contêiner de rolagem (top: 0.5rem no CSS). */
const BAR_TOP = 8;

export type CompactBarGeneration = {
  code: string;
  ordinal: number;
  label: string;
  roman: string;
  regionName: string | null;
  speciesCount: string;
};

/**
 * Barra compacta de orientação da Pokédex Nacional (Pokédex P4c, revisão de UX
 * 2026-10-14 — substitui a régua completa fixa, reprovada na homologação visual).
 *
 * - No topo da página nada muda: a régua de gerações (servidor) continua estática e é a
 *   navegação principal. A barra só aparece quando a régua sai de vista.
 * - Uma linha: "Geração II · Johto", a geração visível na galeria. O botão abre, sob
 *   demanda, a lista das gerações; escolher uma aplica o filtro (mesmo link da régua).
 * - Ocupa só a pílula (sem faixa de largura total) e não tem altura no fluxo: não
 *   desloca o layout ao aparecer/sumir (só opacity/transform).
 * - A lista fecha com Esc, clique fora, rolagem ou ao sumir a barra — nunca fica aberta
 *   sobre as cartas enquanto o usuário rola.
 *
 * Geração visível: regra pura `resolveVisibleGeneration` (linha logo abaixo da barra,
 * histerese na fronteira). Disparo por IntersectionObserver (faixa de 1 px, ≤ 9 seções)
 * e `scrollend`; nenhum listener de rolagem contínua, nenhuma consulta. No mobile e com
 * geração filtrada o componente nem é renderizado / não cria observadores.
 */
export function GenerationCompactBar({
  generations,
  query,
  types,
  origin = null,
}: {
  generations: CompactBarGeneration[];
  query: string | null;
  /** Tipos ativos (P5a) — preservados ao escolher uma geração. */
  types: readonly string[];
  /** P6: origem da galeria (Pokémons Favoritos mantém os links dentro dela). */
  origin?: PokedexOrigin | null;
}) {
  const dockRef = useRef<HTMLDivElement>(null);
  const barRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const panelId = useId();
  const [visible, setVisible] = useState<string | null>(null);
  const [rulerOut, setRulerOut] = useState(false);
  const [focusWithin, setFocusWithin] = useState(false);
  const [open, setOpen] = useState(false);

  const shown = rulerOut || focusWithin;

  useEffect(() => {
    const dock = dockRef.current;
    const bar = barRef.current;
    const ruler = document.querySelector<HTMLElement>("[data-pk-generation-nav]");
    if (!dock || !bar || !ruler) return;
    const media = window.matchMedia(DESKTOP_QUERY);
    const root = scrollParent(dock);
    const scrollTarget: HTMLElement | Window = root ?? window;

    let sectionObserver: IntersectionObserver | null = null;
    let rulerObserver: IntersectionObserver | null = null;
    let resizeObserver: ResizeObserver | null = null;
    let frame = 0;
    let current: string | null = null;

    const sections = () => Array.from(document.querySelectorAll<HTMLElement>("section[data-generation]"));
    const band = () => BAR_TOP + Math.round(bar.offsetHeight);
    const rootTop = () => (root ? root.getBoundingClientRect().top : 0);

    function update() {
      frame = 0;
      const line = rootTop() + band() + 1;
      const boxes: SectionBox[] = sections().map((section) => {
        const rect = section.getBoundingClientRect();
        return { code: section.dataset.generation ?? "", top: rect.top, bottom: rect.bottom };
      });
      const next = resolveVisibleGeneration(boxes, line, current);
      if (next !== current) {
        current = next;
        setVisible(next);
      }
      setRulerOut(ruler!.getBoundingClientRect().bottom <= line);
    }

    function schedule() {
      if (!frame) frame = requestAnimationFrame(update);
    }

    function observe() {
      sectionObserver?.disconnect();
      rulerObserver?.disconnect();
      const height = root ? root.clientHeight : window.innerHeight;
      const top = band();
      sectionObserver = new IntersectionObserver(schedule, {
        root,
        rootMargin: `-${top}px 0px -${Math.max(0, height - top - 1)}px 0px`,
      });
      for (const section of sections()) sectionObserver.observe(section);
      // A régua sai de vista quando passa inteira acima da linha da barra.
      rulerObserver = new IntersectionObserver(schedule, { root, rootMargin: `-${top}px 0px 0px 0px` });
      rulerObserver.observe(ruler!);
      schedule();
    }

    function start() {
      observe();
      resizeObserver = new ResizeObserver(() => observe());
      resizeObserver.observe(root ?? document.documentElement);
      scrollTarget.addEventListener("scrollend", schedule, { passive: true });
    }

    function stop() {
      scrollTarget.removeEventListener("scrollend", schedule);
      sectionObserver?.disconnect();
      rulerObserver?.disconnect();
      resizeObserver?.disconnect();
      sectionObserver = rulerObserver = null;
      resizeObserver = null;
      if (frame) cancelAnimationFrame(frame);
      frame = 0;
      setRulerOut(false);
    }

    const onMediaChange = () => (media.matches ? start() : stop());
    if (media.matches) start();
    media.addEventListener("change", onMediaChange);
    return () => {
      media.removeEventListener("change", onMediaChange);
      stop();
    };
  }, []);

  const close = useCallback((restoreFocus: boolean) => {
    setOpen(false);
    if (restoreFocus) buttonRef.current?.focus();
  }, []);

  // Lista aberta: fecha com Esc, clique fora ou qualquer rolagem (listeners só enquanto aberta).
  useEffect(() => {
    if (!open) return;
    const root = dockRef.current ? scrollParent(dockRef.current) : null;
    const scrollTarget: HTMLElement | Window = root ?? window;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        close(true);
      }
    };
    const onPointer = (event: PointerEvent) => {
      if (!barRef.current?.contains(event.target as Node)) close(false);
    };
    const onScroll = () => close(false);
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    scrollTarget.addEventListener("scroll", onScroll, { passive: true, once: true });
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
      scrollTarget.removeEventListener("scroll", onScroll);
    };
  }, [open, close]);

  // Barra sumiu (voltou ao topo): a lista não pode ficar aberta.
  useEffect(() => {
    if (!shown) setOpen(false);
  }, [shown]);

  const active = generations.find((item) => item.code === visible) ?? generations[0] ?? null;
  if (!active) return null;

  return (
    <div ref={dockRef} className={styles.dock} style={{ marginTop: 0 }}>
      <div
        ref={barRef}
        className={styles.bar}
        data-shown={shown ? "" : undefined}
        aria-hidden={shown ? undefined : true}
        inert={!shown}
        onFocus={() => setFocusWithin(true)}
        onBlur={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setFocusWithin(false);
        }}
      >
        <button
          ref={buttonRef}
          type="button"
          className={styles.trigger}
          aria-expanded={open}
          aria-controls={panelId}
          aria-label={`Geração visível: ${active.label}${active.regionName ? `, ${active.regionName}` : ""}. Escolher outra geração`}
          onClick={() => setOpen((value) => !value)}
        >
          <span className={styles.label}>{active.label}</span>
          {active.regionName ? (
            <>
              <span className={styles.dot} aria-hidden="true">
                ·
              </span>
              <span className={styles.region}>{active.regionName}</span>
            </>
          ) : null}
          <ChevronDown className={styles.chevron} aria-hidden="true" />
        </button>

        <nav id={panelId} aria-label="Gerações" className={styles.panel} hidden={!open}>
          <ul>
            {generations.map((item) => (
              <li key={item.code}>
                <Link
                  href={pokedexHref({ query, generation: item.ordinal, types, origin })}
                  className={styles.option}
                  aria-current={item.code === active.code ? "location" : undefined}
                  onClick={() => setOpen(false)}
                >
                  <span className={styles.optionRoman} aria-hidden="true">
                    {item.roman}
                  </span>
                  <span className={styles.optionName}>{item.regionName ?? item.label}</span>
                  <span className={styles.optionCount}>
                    {item.speciesCount}
                    <span className="sr-only"> espécies</span>
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </div>
  );
}

/** Contêiner de rolagem da página (no AppShell, o `<main>` com overflow-y: auto). */
function scrollParent(element: HTMLElement): HTMLElement | null {
  for (let node = element.parentElement; node; node = node.parentElement) {
    const overflowY = getComputedStyle(node).overflowY;
    if (overflowY === "auto" || overflowY === "scroll") return node;
  }
  return null;
}
