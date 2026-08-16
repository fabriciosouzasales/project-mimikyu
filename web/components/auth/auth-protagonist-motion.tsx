"use client";

import { useEffect, useRef, type CSSProperties, type ReactNode } from "react";

/**
 * Assinatura de motion do produto, extraída (não importada) de
 * `components/catalogo/holo-card.tsx` (`floating`, usado no
 * `CartaZoomDialog` — modal de ampliação de Cartas) — mesmo princípio
 * matemático: duas frequências senoidais independentes combinadas numa
 * trajetória contínua via `requestAnimationFrame` (nunca CSS `@keyframes`,
 * o que evitaria repetição perceptível de ciclo), pausada enquanto o
 * ponteiro está sobre a peça e desligada por completo sob
 * `prefers-reduced-motion: reduce`.
 *
 * O Auth não importa nada de `components/catalogo/` — só o princípio de
 * movimento foi extraído para este componente próprio e isolado. Ajuste de
 * intensidade (2026-08-16, segunda rodada de polish — a primeira tentativa,
 * a ~1/4 da amplitude da referência, ficou "praticamente imperceptível"):
 * amplitude recalibrada para 60% da referência de `holo-card.tsx`
 * (rotateY ±4,2° vs ±7°, rotateX ±2,7° vs ±4,5°, translateY ±4,8px vs
 * ±8px — mesmas fases, só o coeficiente de amplitude mudou), frequências
 * levemente inferiores às originais (~90%, "velocidade pode permanecer
 * ligeiramente inferior à referência"). Critério visual: perceptível em
 * 1–2s de observação normal, sem parecer balanço/tremor/bounce. Não
 * reproduz o brilho/glare (`--holo-x`/
 * `--holo-y`/`--holo-opacity`) do modal de Cartas — o Auth já tem seu
 * próprio tratamento de luz (`.sheen`/`.rim` em `auth-hero.module.css`);
 * só a trajetória (rotateX/rotateY/translateY) foi reaproveitada.
 *
 * Client Component "folha" — só esta peça (a carta protagonista) precisa
 * de JS; o resto do Hero (`auth-hero.tsx`) continua Server Component puro,
 * mesmo padrão já usado por `BrandLogo`/`ThemeToggle`/`LoginForm` dentro da
 * árvore majoritariamente estática do Auth. Escreve em custom properties
 * próprias (`--auth-float-rx`/`--auth-float-ry`/`--auth-float-ty`),
 * consumidas pelo `transform` de `.heroPiece` — nunca sobrescreve
 * `--piece-rotate`/`--piece-lift` (posição/hover existentes), então o
 * hover (`translateY(-6px) scale(1.012)`, puro CSS) continua funcionando
 * normalmente por cima da flutuação: a escrita do RAF pausa enquanto o
 * mouse está sobre a carta (mesmo padrão do `HoloCard`), o valor flutuante
 * congela no último quadro, e só o hover segue reagindo.
 *
 * Sem `<link rel=... hover>`/CLS: nenhuma dimensão muda, só `transform`
 * (composição via GPU, sem custo de layout/paint adicional relevante).
 */
export function AuthProtagonistFloat({
  children,
  className,
  style,
}: {
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const hoveringRef = useRef(false);

  useEffect(() => {
    if (typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      return;
    }

    let frameId: number;
    const start = performance.now();

    function tick(now: number) {
      const node = ref.current;
      if (node && !hoveringRef.current) {
        const t = (now - start) / 1000;
        // Mesmo princípio de holo-card.tsx (floating): duas frequências
        // independentes combinadas, mais uma terceira para o deslocamento
        // vertical. Amplitude a 60% da referência, frequências a ~90%
        // (suspensão claramente perceptível, ainda mais lenta que o modal
        // de Cartas — ver comentário do componente).
        const rotateY = Math.sin(t * 0.4) * 4.2;
        const rotateX = Math.cos(t * 0.3 + 1) * 2.7;
        const translateY = Math.sin(t * 0.47 + 0.6) * 4.8;
        node.style.setProperty("--auth-float-ry", `${rotateY}deg`);
        node.style.setProperty("--auth-float-rx", `${rotateX}deg`);
        node.style.setProperty("--auth-float-ty", `${translateY}px`);
      }
      frameId = requestAnimationFrame(tick);
    }

    frameId = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frameId);
  }, []);

  return (
    <div
      ref={ref}
      onMouseEnter={() => {
        hoveringRef.current = true;
      }}
      onMouseLeave={() => {
        hoveringRef.current = false;
      }}
      className={className}
      style={style}
    >
      {children}
    </div>
  );
}
