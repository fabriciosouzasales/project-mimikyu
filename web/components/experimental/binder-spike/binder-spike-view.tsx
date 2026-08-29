"use client";

import { X } from "lucide-react";
import { useCallback, useState } from "react";
import { BINDER_NAME, BINDER_SUBTITLE, MOCK_BINDER_SPIKE_PAGES } from "@/app/experimental/binder-spike/mock-data";
import { runWithViewTransition } from "@/lib/view-transitions";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import { BinderCover } from "./binder-cover";
import { BinderPages } from "./binder-pages";

/**
 * "Binder-First" — spike client-facing isolado (pedido verbatim de
 * Fabrício, 2026-08-28): abandona a evolução do "Visual Collection Space"
 * com múltiplos Storage Containers (`app/experimental/collection-space/`,
 * preservado intacto como prova técnica encerrada, não baseline visual) e
 * isola só o Binder — o principal objeto client-facing do MMKYU — como
 * objeto físico premium (capa PU/leather-like, zíper, costura, lombada) com
 * transição de abertura e miolo com bolsos vazios/ocupados.
 *
 * Reaproveita, sem alteração de contrato, os dois mecanismos já validados
 * na Rodada UX-01/UX-01.1: `runWithViewTransition`/`canUseViewTransitions`
 * (`lib/view-transitions.ts`) para o "morph" de abertura, com fallback
 * automático sem navegador compatível ou `prefers-reduced-motion: reduce`;
 * e `usePrefersReducedMotion` (`lib/use-prefers-reduced-motion.ts`) para
 * desligar rotação/perspectiva decorativa nesse mesmo caso.
 *
 * Escopo desta rodada: capa fechada, transição, miolo com 2 páginas e
 * slots só visuais (sem lógica funcional, sem persistência, sem drag,
 * sem regra de domínio) — ver `mock-data.ts`.
 *
 * Rodada BINDER-VIS-02 (2026-08-28, mesma data): protagonismo de escala do
 * fechado (`binder-cover.tsx`), continuidade física fechado→aberto e
 * páginas/bolsos/cartas mais realistas (`binder-pages.tsx`,
 * `binder-slot.tsx`, `mock-card-face.tsx`) — cabeçalho/rodapé desta view
 * ficaram mais discretos (menos padding vertical) para o binder dominar a
 * viewport, sem mudar nenhum mecanismo de interação.
 */

const TRANSITION_NAME = "binder-spike-object";

export function BinderSpikeView() {
  const [open, setOpen] = useState(false);
  const prefersReducedMotion = usePrefersReducedMotion();

  const handleOpen = useCallback(() => {
    runWithViewTransition(() => setOpen(true));
  }, []);

  const handleClose = useCallback(() => {
    runWithViewTransition(() => setOpen(false));
  }, []);

  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      if (open) {
        if (event.key === "Escape") {
          event.preventDefault();
          handleClose();
        }
        return;
      }
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        handleOpen();
      }
    },
    [open, handleOpen, handleClose],
  );

  return (
    <div
      className="relative flex h-dvh w-full flex-col overflow-hidden bg-[hsl(30_20%_7%)]"
      onKeyDown={handleKeyDown}
    >
      {/* Glow ambiente — mesmo matiz dourado da marca usado na Rodada UX-01.1. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 60% 50% at 50% 36%, hsl(37 55% 26% / 0.3), transparent 68%), radial-gradient(ellipse 55% 42% at 50% 80%, hsl(37 60% 20% / 0.38), transparent 70%)",
        }}
      />

      <header className="relative z-10 px-6 pt-4 sm:px-10">
        <p className="text-[11px] font-medium uppercase tracking-[0.18em] text-white/35">
          Spike experimental · Binder-first · não é a IA oficial
        </p>
        <h1 className="mt-0.5 text-base font-semibold text-white/90 sm:text-lg">Visual Spike — Binder</h1>
      </header>

      {!open ? (
        <button
          type="button"
          onClick={handleOpen}
          className="group relative z-10 flex flex-1 items-center justify-center rounded-2xl focus:outline-none focus-visible:ring-2 focus-visible:ring-[hsl(40_70%_62%)] focus-visible:ring-offset-4 focus-visible:ring-offset-[hsl(30_20%_7%)]"
          aria-label={`Abrir ${BINDER_NAME}`}
        >
          {/* Sombra de contato no "chão". */}
          <span
            aria-hidden
            className="absolute h-6 w-48 rounded-[50%] blur-md"
            style={{ background: "rgba(0,0,0,0.55)", top: "77%" }}
          />
          <span
            className={
              prefersReducedMotion
                ? "inline-block"
                : "inline-block transition-transform duration-300 ease-out group-hover:-translate-y-1 group-focus-visible:-translate-y-1"
            }
          >
            <BinderCover viewTransitionName={TRANSITION_NAME} />
          </span>
        </button>
      ) : (
        <div
          className="relative z-10 flex flex-1 flex-col items-center justify-center gap-6 px-4 pb-6 sm:px-10"
          role="dialog"
          aria-modal="true"
          aria-label={`Interior de ${BINDER_NAME}`}
        >
          <button
            type="button"
            onClick={handleClose}
            className="absolute right-4 top-0 z-20 rounded-full border border-white/15 bg-black/20 p-2 text-white/70 transition-colors hover:bg-white/10 hover:text-white sm:right-10"
            aria-label="Fechar binder"
          >
            <X className="h-4 w-4" aria-hidden />
          </button>
          <BinderPages pages={MOCK_BINDER_SPIKE_PAGES} viewTransitionName={TRANSITION_NAME} />
        </div>
      )}

      <div className="relative z-10 flex flex-col items-center gap-0.5 pb-5 pt-1 text-center">
        <h2 className="text-sm font-semibold text-white/90 sm:text-base">{BINDER_NAME}</h2>
        <p className="text-[11px] text-white/45">{BINDER_SUBTITLE}</p>
        <p className="mt-0.5 text-[10px] text-white/30">
          {open ? "Esc ou botão fechar para voltar" : "Enter/Espaço ou clique para abrir"}
        </p>
      </div>
    </div>
  );
}
