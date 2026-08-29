"use client";

import { forwardRef, useImperativeHandle, useRef, type CSSProperties, type ReactNode } from "react";

export interface HingedLeafHandle {
  /** Escreve o ângulo direto no DOM via ref — sem passar por setState/re-render do React. */
  setAngle: (angleDeg: number) => void;
}

interface HingedLeafProps {
  front: ReactNode;
  back: ReactNode;
  className?: string;
  style?: CSSProperties;
  initialAngle?: number;
}

/**
 * Folha genérica com dobradiça na borda ESQUERDA — reaproveitada tanto para
 * a capa (gira em torno da lombada) quanto para cada virada de página
 * (BINDER-MOTION-02, pedido de Fabrício 2026-08-28, em resposta à reprovação
 * conceitual do BINDER-MOTION-01: "abertura deve girar em torno da lombada,
 * não usar crossfade"; "a folha deve rotacionar em torno da lombada/gutter").
 *
 * Técnica: flip-card clássico em CSS 3D (`backface-visibility: hidden` +
 * `rotateY(180deg)` na face de trás) — Baseline amplamente suportado, zero
 * dependência nova. `angleDeg` negativo gira a folha para longe do
 * observador em torno da dobradiça esquerda (abrir/virar da direita para a
 * esquerda). Uma leve translação em Z proporcional a `sin(ângulo)` sugere a
 * folha "levantando" da superfície durante o giro (a "leve
 * deformação/perspectiva" pedida) sem multiplicar a complexidade com
 * múltiplas tiras da folha. Uma sombra dinâmica (também função de
 * `sin(ângulo)`, pico aos 90°) é aplicada em cada face.
 *
 * Performance (aprendizado preservado do BINDER-MOTION-01): o ângulo NUNCA
 * passa por `useState`/re-render do React — `setAngle` grava
 * `transform`/`background` direto nos nós via `ref`, a cada frame de
 * `requestAnimationFrame` no orquestrador. React só re-renderiza quando o
 * CONTEÚDO (front/back) muda, o que acontece uma vez por spread, não a cada
 * frame de scroll/drag.
 */
export const HingedLeaf = forwardRef<HingedLeafHandle, HingedLeafProps>(function HingedLeaf(
  { front, back, className, style, initialAngle = 0 },
  ref,
) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const frontShadowRef = useRef<HTMLDivElement>(null);
  const backShadowRef = useRef<HTMLDivElement>(null);

  useImperativeHandle(
    ref,
    () => ({
      setAngle(angleDeg: number) {
        const angleRad = (angleDeg * Math.PI) / 180;
        const bulge = Math.sin(angleRad) * -10;
        const shadowAlpha = Math.min(0.5, Math.abs(Math.sin(angleRad)) * 0.55);
        if (wrapperRef.current) {
          wrapperRef.current.style.transform = `rotateY(${angleDeg}deg) translateZ(${bulge}px)`;
        }
        if (frontShadowRef.current) {
          frontShadowRef.current.style.background = `linear-gradient(90deg, rgba(0,0,0,${shadowAlpha}), transparent 55%)`;
        }
        if (backShadowRef.current) {
          backShadowRef.current.style.background = `linear-gradient(270deg, rgba(0,0,0,${shadowAlpha}), transparent 55%)`;
        }
      },
    }),
    [],
  );

  return (
    <div
      ref={wrapperRef}
      className={className}
      style={{
        ...style,
        transformOrigin: "left center",
        transformStyle: "preserve-3d",
        transform: `rotateY(${initialAngle}deg)`,
      }}
    >
      <div className="absolute inset-0" style={{ backfaceVisibility: "hidden" }}>
        {front}
        <div ref={frontShadowRef} className="pointer-events-none absolute inset-0" aria-hidden />
      </div>
      <div className="absolute inset-0" style={{ backfaceVisibility: "hidden", transform: "rotateY(180deg)" }}>
        {back}
        <div ref={backShadowRef} className="pointer-events-none absolute inset-0" aria-hidden />
      </div>
    </div>
  );
});
