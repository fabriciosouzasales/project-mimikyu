"use client";

import { type ReactNode, useCallback, useEffect, useRef } from "react";
import styles from "./action-capsule.module.css";

/**
 * Cápsula de ações do cabeçalho (V1-14 R1-A UX REDIRECTION-02) — UM componente visual para as
 * ações do módulo (na Coleção: Relatórios, Compartilhar, Ajustes), no lugar de botões soltos.
 *
 * Linguagem inspirada nas referências aprovadas (Glassy Sidebar V5 / Navigation Tabs V5),
 * reescrita sobre os tokens do MMKYU — nenhum código copiado, nenhuma dependência:
 *  - superfície contínua de vidro (transparência controlada, borda fina, brilho superior,
 *    profundidade em camadas), nos dois temas;
 *  - UM indicador que desliza entre as ações (hover e foco por teclado) sem mover nenhum alvo:
 *    ele é uma camada absoluta atrás dos botões (só `transform`/largura dele mesmo);
 *  - ação "aberta" (`aria-expanded="true"`, ex.: o menu de Relatórios) segura o indicador com o
 *    tom dourado — é dali que o menu nasce.
 *
 * Os gatilhos continuam sendo os componentes de origem (mesmos painéis, mesmas permissões);
 * a cápsula só os apresenta: cada gatilho recebe `styles.item` (e `styles.label` no texto, que
 * vira acessível-só no celular) importando `action-capsule.module.css` — também de componentes
 * de servidor, que não podem importar valores de um módulo "use client". Teclado: Tab percorre as ações; foco visível próprio.
 * `prefers-reduced-motion` = indicador sem viagem; `prefers-reduced-transparency` e navegador
 * sem `backdrop-filter` = superfície opaca.
 */
export function ActionCapsule({ label, children }: { label: string; children: ReactNode }) {
  const rootRef = useRef<HTMLDivElement>(null);
  const indicatorRef = useRef<HTMLSpanElement>(null);

  const items = useCallback(
    () => Array.from(rootRef.current?.querySelectorAll<HTMLElement>(`.${styles.item}`) ?? []),
    [],
  );

  /** Leva o indicador até `node` (ou o recolhe). Nunca mexe no layout das ações. */
  const moveTo = useCallback((node: HTMLElement | null, instant = false) => {
    const indicator = indicatorRef.current;
    if (!indicator) return;
    if (!node) {
      indicator.dataset.visible = "false";
      return;
    }
    if (instant || indicator.dataset.visible !== "true") indicator.dataset.snap = "true";
    indicator.style.transform = `translateX(${node.offsetLeft}px)`;
    indicator.style.width = `${node.offsetWidth}px`;
    indicator.dataset.tone = node.getAttribute("aria-expanded") === "true" ? "active" : "hover";
    indicator.dataset.visible = "true";
    if (indicator.dataset.snap) {
      // Primeira aparição: surge no lugar (sem viajar da esquerda); depois desliza.
      requestAnimationFrame(() =>
        requestAnimationFrame(() => {
          if (indicatorRef.current) delete indicatorRef.current.dataset.snap;
        }),
      );
    }
  }, []);

  /** Repouso: fica na ação aberta (dourado) ou some. */
  const rest = useCallback(() => {
    const expanded = items().find((node) => node.getAttribute("aria-expanded") === "true") ?? null;
    moveTo(expanded);
  }, [items, moveTo]);

  // Menu aberto/fechado dentro da cápsula muda `aria-expanded`: o indicador acompanha.
  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const observer = new MutationObserver(() => {
      const hovered = root.matches(":hover");
      const focused = root.contains(document.activeElement) ? (document.activeElement as HTMLElement).closest<HTMLElement>(`.${styles.item}`) : null;
      if (focused && !hovered) moveTo(focused);
      else if (!hovered) rest();
      else {
        const indicator = indicatorRef.current;
        const current = items().find((node) => node.matches(":hover")) ?? null;
        if (indicator && current) indicator.dataset.tone = current.getAttribute("aria-expanded") === "true" ? "active" : "hover";
      }
    });
    observer.observe(root, { subtree: true, attributes: true, attributeFilter: ["aria-expanded"] });
    const onResize = () => rest();
    window.addEventListener("resize", onResize);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", onResize);
    };
  }, [items, moveTo, rest]);

  return (
    <div
      ref={rootRef}
      role="group"
      aria-label={label}
      className={styles.capsule}
      onPointerOver={(event) => {
        const node = (event.target as HTMLElement).closest<HTMLElement>(`.${styles.item}`);
        if (node && rootRef.current?.contains(node)) moveTo(node);
      }}
      onPointerLeave={() => {
        const focused = (document.activeElement as HTMLElement | null)?.closest<HTMLElement>(`.${styles.item}`) ?? null;
        if (focused && rootRef.current?.contains(focused) && focused.matches(":focus-visible")) moveTo(focused);
        else rest();
      }}
      onFocus={(event) => {
        const node = (event.target as HTMLElement).closest<HTMLElement>(`.${styles.item}`);
        if (node && node.matches(":focus-visible")) moveTo(node);
      }}
      onBlur={(event) => {
        if (!rootRef.current?.contains(event.relatedTarget as Node | null)) rest();
      }}
    >
      <span ref={indicatorRef} className={styles.indicator} data-visible="false" aria-hidden="true" />
      {children}
    </div>
  );
}
