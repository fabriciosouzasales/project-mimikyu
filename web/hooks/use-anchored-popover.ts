"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";

type Position = { top: number; left: number };

/**
 * Popover ancorado a um gatilho, posicionado via `getBoundingClientRect()` +
 * portal (não via CSS `position: absolute` dentro do grid) — criado para
 * `CardPriceBadge` (P12, redesenho 2026-08-18) sem depender de nenhuma
 * biblioteca nova: o sandbox de execução deste agente não tem acesso ao
 * registry do npm (`npm install` real falha com `403`), então um Popover
 * Radix (que resolveria isso "de graça") não pôde ser adicionado como
 * dependência — implementado à mão, mesma garantia de "nunca cortado pelo
 * grid" que um `overflow-hidden`/`transform` de qualquer ancestral do
 * gatilho poderia causar com posicionamento puramente relativo.
 *
 * Abre em hover (com pequeno atraso, evita abrir ao só passar o mouse de
 * relance pelo grid) ou foco (imediato, navegação por teclado); fecha em
 * `mouseleave`/`blur` (com atraso, dá tempo do ponteiro entrar no conteúdo
 * sem fechar no meio do caminho), `Escape` (fecha e devolve o foco ao
 * gatilho) e clique fora (gatilho e conteúdo, cobre toque em mobile).
 *
 * Posicionamento (refinado a partir de QA visual, 2026-08-18): prioriza
 * lateral ao gatilho (direita primeiro, depois esquerda) — só cai para
 * abaixo/acima do gatilho quando nenhum dos dois lados tem espaço. Em
 * qualquer caso, nunca sai da viewport: `COLLISION_PADDING` (12px) é
 * respeitado como distância mínima de qualquer borda da tela.
 */
const COLLISION_PADDING = 12;
const ANCHOR_GAP = 8;
export function useAnchoredPopover<
  TAnchor extends HTMLElement = HTMLButtonElement,
  TContent extends HTMLElement = HTMLDivElement,
>() {
  const anchorRef = useRef<TAnchor>(null);
  const contentRef = useRef<TContent>(null);
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState<Position | null>(null);
  const openTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearTimers = useCallback(() => {
    if (openTimer.current) {
      clearTimeout(openTimer.current);
      openTimer.current = null;
    }
    if (closeTimer.current) {
      clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
  }, []);

  const openNow = useCallback(() => {
    clearTimers();
    setOpen(true);
  }, [clearTimers]);

  const closeNow = useCallback(() => {
    clearTimers();
    setOpen(false);
    setPosition(null);
  }, [clearTimers]);

  const scheduleOpen = useCallback(
    (delayMs = 120) => {
      clearTimers();
      openTimer.current = setTimeout(() => setOpen(true), delayMs);
    },
    [clearTimers],
  );

  const scheduleClose = useCallback(
    (delayMs = 160) => {
      clearTimers();
      closeTimer.current = setTimeout(() => {
        setOpen(false);
        setPosition(null);
      }, delayMs);
    },
    [clearTimers],
  );

  const toggle = useCallback(() => {
    clearTimers();
    setOpen((current) => !current);
  }, [clearTimers]);

  const recomputePosition = useCallback(() => {
    const anchor = anchorRef.current;
    if (!anchor) return;

    const rect = anchor.getBoundingClientRect();
    const contentWidth = contentRef.current?.offsetWidth ?? 272;
    const contentHeight = contentRef.current?.offsetHeight ?? 220;
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    const spaceRight = viewportWidth - rect.right - COLLISION_PADDING;
    const spaceLeft = rect.left - COLLISION_PADDING;
    const spaceBelow = viewportHeight - rect.bottom - COLLISION_PADDING;
    const spaceAbove = rect.top - COLLISION_PADDING;

    let top: number;
    let left: number;

    if (spaceRight >= contentWidth) {
      // Lateral direita — posição preferida.
      left = rect.right + ANCHOR_GAP;
      top = rect.top + rect.height / 2 - contentHeight / 2;
    } else if (spaceLeft >= contentWidth) {
      // Lateral esquerda — segunda preferência, quando a direita não cabe.
      left = rect.left - contentWidth - ANCHOR_GAP;
      top = rect.top + rect.height / 2 - contentHeight / 2;
    } else if (spaceBelow >= contentHeight || spaceBelow >= spaceAbove) {
      // Nenhum lado cabe: cai para abaixo/acima do gatilho (fallback).
      top = rect.bottom + ANCHOR_GAP;
      left = rect.left;
    } else {
      top = rect.top - contentHeight - ANCHOR_GAP;
      left = rect.left;
    }

    // Nunca sai da viewport — 12px de collision padding em qualquer borda.
    left = Math.min(Math.max(left, COLLISION_PADDING), viewportWidth - contentWidth - COLLISION_PADDING);
    top = Math.min(Math.max(top, COLLISION_PADDING), viewportHeight - contentHeight - COLLISION_PADDING);

    setPosition({ top, left });
  }, []);

  // Mede depois do conteúdo já estar montado (mas ainda invisível) —
  // `useLayoutEffect` roda antes da pintura do navegador, então a primeira
  // aparição do popover já nasce na posição certa, sem flash num canto
  // errado da tela.
  useLayoutEffect(() => {
    if (!open) return;
    recomputePosition();
  }, [open, recomputePosition]);

  useEffect(() => {
    if (!open) return;
    const handle = () => recomputePosition();
    window.addEventListener("resize", handle);
    window.addEventListener("scroll", handle, true);
    return () => {
      window.removeEventListener("resize", handle);
      window.removeEventListener("scroll", handle, true);
    };
  }, [open, recomputePosition]);

  useEffect(() => {
    if (!open) return;

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        closeNow();
        anchorRef.current?.focus();
      }
    }

    function handlePointerDown(event: PointerEvent) {
      const target = event.target as Node | null;
      if (!target) return;
      if (anchorRef.current?.contains(target)) return;
      if (contentRef.current?.contains(target)) return;
      closeNow();
    }

    document.addEventListener("keydown", handleKeyDown);
    document.addEventListener("pointerdown", handlePointerDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.removeEventListener("pointerdown", handlePointerDown);
    };
  }, [open, closeNow]);

  useEffect(() => () => clearTimers(), [clearTimers]);

  return { anchorRef, contentRef, open, position, openNow, closeNow, scheduleOpen, scheduleClose, toggle };
}
