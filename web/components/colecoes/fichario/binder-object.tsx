"use client";

import { type ReactNode, useEffect, useState } from "react";
import { BINDER_UNITS, type BinderFit, type ViewSide } from "@/lib/colecoes/binder";
import type { BinderFinish } from "@/lib/colecoes/binder-finish";
import { cn } from "@/lib/utils";
import { INTERIOR_HUE, InsideCoverFace, darkZipperTeeth, insideCoverSurface, leatherSurface } from "./binder-chrome";

/** Corte de spread (duas páginas) do fichário — o mesmo para titular e participante. */
export const BINDER_SPREAD_MEDIA = "(min-width: 900px)";

/**
 * O objeto fichário aberto — couro no acabamento da coleção com trama, zíper
 * nas quatro bordas, puxador, duas folhas com leve inclinação 3D, lombada
 * escura e contracapa com a identidade (nome próprio + logomarca).
 *
 * Extraído de `BinderWorkspace` em V1-12 VIEWER EXPERIENCE PARITY
 * CORRECTION-02, SEM mudança visual: é a MESMA peça para o titular (área de
 * trabalho, bolsos editáveis) e para o participante VIEWER (leitor só
 * leitura). O que muda entre os dois é só o conteúdo de cada folha
 * (`renderPage`) e o atalho opcional na contracapa (`innerExtra`).
 *
 * A geometria vem de `fit` (`computeBinderFit`): bolso, margens, spread ou
 * página única. Troca de vista: deslocamento curto + opacidade (~200 ms),
 * desligada sem `animate` (prefers-reduced-motion).
 */
export function BinderObjectFrame({
  finish,
  fit,
  sides,
  view,
  direction,
  animate,
  coverName,
  coverBrandMark,
  renderPage,
  innerExtra = null,
}: {
  finish: BinderFinish;
  fit: BinderFit;
  sides: ViewSide[];
  view: number;
  direction: 1 | -1;
  animate: boolean;
  coverName: string;
  coverBrandMark: boolean;
  /** Conteúdo de uma folha (grade de bolsos) — recebe o encaixe já calculado. */
  renderPage: (page: number, metrics: { pocket: number; gap: number }) => ReactNode;
  /** Sobre a contracapa traseira (vista > 1): atalho do titular, se houver. */
  innerExtra?: ReactNode;
}) {
  const p = fit.pocket;
  const pad = p * BINDER_UNITS.pad;
  const pagePad = p * BINDER_UNITS.pagePad;
  const gap = p * BINDER_UNITS.gap;
  const spine = p * BINDER_UNITS.spine;
  const two = sides.length === 2;
  return (
    <div
      className="relative overflow-hidden rounded-[22px]"
      style={{
        width: fit.width,
        height: fit.height,
        // A borda de 1px entra na conta (border-box): o miolo fica com a medida exata do encaixe.
        padding: Math.max(0, pad - 1),
        backgroundImage: leatherSurface(finish),
        boxShadow: ["inset 0 1px 0 hsl(0 0% 100% / 0.08)", "inset 0 -2px 10px hsl(0 0% 0% / 0.5)", "0 40px 60px -20px rgba(0,0,0,0.65)"].join(", "),
        border: "1px solid hsl(0 0% 0% / 0.5)",
      }}
    >
      <div className="pointer-events-none absolute left-[8%] right-[8%] top-[6px] h-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(false) }} aria-hidden />
      <div className="pointer-events-none absolute bottom-[6px] left-[8%] right-[8%] h-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(false) }} aria-hidden />
      <div className="pointer-events-none absolute bottom-[12%] left-[5px] top-[12%] w-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(true) }} aria-hidden />
      <div className="pointer-events-none absolute bottom-[12%] right-[5px] top-[12%] w-[2.5px] rounded-full opacity-70" style={{ backgroundImage: darkZipperTeeth(true) }} aria-hidden />
      <div
        className="pointer-events-none absolute left-[3px] top-[7%] h-3.5 w-2 rounded-[2px] opacity-80"
        style={{ background: "linear-gradient(160deg, hsl(0 0% 46%), hsl(0 0% 16%))", boxShadow: "0 1px 2px rgba(0,0,0,0.5)" }}
        aria-hidden
      />

      <div className="relative flex h-full" style={{ perspective: "2000px" }}>
        {sides.map((side, index) => {
          const position: "left" | "right" | "single" = !two ? "single" : index === 0 ? "left" : "right";
          const panel = (
            <div
              key={`${view}-${index}`}
              className="relative h-full flex-1"
              style={two ? { transform: position === "left" ? "rotateY(2deg)" : "rotateY(-2deg)", transformOrigin: position === "left" ? "right center" : "left center" } : undefined}
            >
              {/* Sombra projetada (folha solta sobre o couro). A contracapa é rebaixada na moldura: não projeta sombra (P3-A correção de volume). */}
              {side === "inner" ? null : (
                <div
                  className={cn("absolute inset-0", position === "left" ? "rounded-l-lg" : position === "right" ? "rounded-r-lg" : "rounded-lg")}
                  style={{ transform: "translate(2px, 3px)", background: `hsl(${INTERIOR_HUE} 10% 4%)` }}
                  aria-hidden
                />
              )}
              <div
                className={cn("relative h-full overflow-hidden", position === "left" ? "rounded-l-lg" : position === "right" ? "rounded-r-lg" : "rounded-lg")}
                style={{
                  // Respiro extra (BINDER_MARGIN) só no alto, embaixo e na lateral externa; o lado da lombada fica como estava.
                  paddingTop: pagePad + fit.marginY,
                  paddingBottom: pagePad + fit.marginY,
                  paddingLeft: pagePad + (position === "right" ? 0 : fit.marginX),
                  paddingRight: pagePad + (position === "left" ? 0 : fit.marginX),
                  ...(side === "inner" ? insideCoverSurface(position) : pageSurface(position)),
                }}
              >
                <PanelTransition direction={direction} animate={animate}>
                  {side === "inner" ? (
                    <>
                      <InsideCoverFace name={coverName} showBrandMark={coverBrandMark} />
                      {/* Vista > 1: é a contracapa traseira — o fim do fichário. */}
                      {view > 1 ? innerExtra : null}
                    </>
                  ) : (
                    renderPage(side, { pocket: p, gap })
                  )}
                </PanelTransition>
              </div>
            </div>
          );
          if (index === 0 && two) {
            return [
              panel,
              <div key="spine" className="pointer-events-none relative flex-shrink-0" style={{ width: spine }} aria-hidden>
                <div
                  className="absolute inset-0"
                  style={{
                    background: `linear-gradient(90deg, transparent, hsl(${INTERIOR_HUE} 22% 5%) 30%, hsl(${INTERIOR_HUE} 16% 3%) 50%, hsl(${INTERIOR_HUE} 22% 5%) 70%, transparent)`,
                  }}
                />
                <div
                  className="absolute inset-0"
                  style={{ background: "radial-gradient(ellipse 60% 100% at 50% 50%, hsl(0 0% 0% / 0.55) 0%, transparent 70%)", boxShadow: "0 0 20px 6px rgba(0,0,0,0.55)" }}
                />
                <div className="absolute inset-y-2 left-[22%] w-px" style={{ background: "hsl(0 0% 100% / 0.07)" }} />
                <div className="absolute inset-y-2 right-[22%] w-px" style={{ background: "hsl(0 0% 100% / 0.07)" }} />
              </div>,
            ];
          }
          return panel;
        })}
      </div>
    </div>
  );
}

/** Troca de vista do spike: deslocamento curto + opacidade (~200 ms), nunca virada 3D. */
function PanelTransition({ direction, animate, children }: { direction: 1 | -1; animate: boolean; children: ReactNode }) {
  const [entered, setEntered] = useState(!animate);
  useEffect(() => {
    if (!animate) return;
    const raf = requestAnimationFrame(() => setEntered(true));
    return () => cancelAnimationFrame(raf);
  }, [animate]);
  return (
    <div
      className={cn("h-full", animate && "transition-all duration-200 ease-out")}
      style={animate ? { transform: entered ? "translateX(0)" : `translateX(${direction * 8}px)`, opacity: entered ? 1 : 0 } : undefined}
    >
      {children}
    </div>
  );
}

/** Folha com bolsos: acabamento original (inalterado). */
function pageSurface(position: "left" | "right" | "single"): React.CSSProperties {
  return {
    background: `linear-gradient(${position === "right" ? "260deg" : "100deg"}, hsl(${INTERIOR_HUE} 14% 11%) 0%, hsl(${INTERIOR_HUE} 18% 6%) 100%)`,
    boxShadow: [
      position === "left" ? "inset -26px 0 30px -22px rgba(0,0,0,0.85)" : "inset 26px 0 30px -22px rgba(0,0,0,0.85)",
      "inset 0 2px 6px rgba(0,0,0,0.4)",
    ].join(", "),
  };
}
