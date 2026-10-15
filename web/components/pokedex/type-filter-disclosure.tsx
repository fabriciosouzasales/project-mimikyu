"use client";

import { useLinkStatus } from "next/link";
import { ChevronDown, Loader2, SlidersHorizontal } from "lucide-react";
import { type KeyboardEvent, type ReactNode, useId, useRef, useState } from "react";
import styles from "./type-filter.module.css";

/**
 * Ilha cliente do filtro por tipo (Pokédex P5a, 2026-10-14): só o abrir/fechar do
 * seletor. As opções, os chips ativos e o "Limpar" são links renderizados no servidor
 * (chegam como `children`/`chips`) — a filtragem acontece no servidor, pela URL.
 *
 * - Recolhido por padrão; o painel abre no fluxo da página, logo abaixo da linha do
 *   botão (nunca sobre as cartas) e continua aberto enquanto o usuário escolhe o
 *   segundo tipo — o componente não remonta na navegação suave.
 * - Esc dentro do painel fecha e devolve o foco ao botão.
 */
export function TypeFilterDisclosure({
  activeLabel,
  activeCount,
  chips,
  children,
}: {
  /** "Fogo e Voador" quando há filtro (rótulo acessível do botão). */
  activeLabel: string | null;
  activeCount: number;
  chips: ReactNode;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const buttonRef = useRef<HTMLButtonElement>(null);

  function onPanelKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key !== "Escape") return;
    event.preventDefault();
    setOpen(false);
    buttonRef.current?.focus();
  }

  return (
    <div className={styles.root}>
      <div className={styles.bar}>
        <button
          ref={buttonRef}
          type="button"
          className={styles.trigger}
          data-active={activeCount > 0 ? "" : undefined}
          aria-expanded={open}
          aria-controls={panelId}
          aria-label={activeLabel ? `Tipo: ${activeLabel}. Alterar filtro por tipo` : "Tipo: filtrar por tipo"}
          onClick={() => setOpen((value) => !value)}
        >
          <SlidersHorizontal className={styles.triggerIcon} aria-hidden="true" />
          Tipo
          {activeCount > 0 ? (
            <span className={styles.triggerCount} aria-hidden="true">
              {activeCount}
            </span>
          ) : null}
          <ChevronDown className={styles.chevron} aria-hidden="true" />
        </button>
        {chips}
      </div>
      <div id={panelId} className={styles.panel} hidden={!open} onKeyDown={onPanelKeyDown}>
        {children}
      </div>
    </div>
  );
}

/**
 * Indicador de carregamento do link clicado (opção ou chip) enquanto a galeria
 * filtrada chega do servidor — resposta imediata ao toque, sem tempo artificial.
 * Precisa estar dentro do `<Link>`.
 */
export function TypeLinkPending() {
  const { pending } = useLinkStatus();
  return pending ? <Loader2 className={styles.pending} aria-hidden="true" /> : null;
}
