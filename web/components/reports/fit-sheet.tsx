"use client";

import { type ReactNode, useLayoutEffect, useRef, useState } from "react";
import { A4_SCREEN_PX, sheetFitScale } from "@/lib/reports/sheet-fit";
import styles from "./fit-sheet.module.css";

/**
 * Prévia da folha A4 que cabe na tela (STORAGE LOCATIONS MOBILE RESPONSIVENESS
 * CORRECTION-01). Em áreas mais estreitas que a folha (celular), a folha é
 * composta na largura A4 — as mesmas colunas, fontes e quebras da impressão — e
 * reduzida proporcionalmente para mostrar a largura inteira, com rolagem só
 * vertical; o gesto de pinça do navegador amplia para inspeção. Com espaço
 * suficiente (desktop), nada muda. Na impressão o ajuste é anulado
 * (`fit-sheet.module.css`): a folha impressa é idêntica.
 */
export function FitSheet({ children }: { children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState<{ scale: number; height: number } | null>(null);

  useLayoutEffect(() => {
    const box = outer.current;
    const sheet = inner.current;
    if (!box || !sheet) return;
    const measure = () => {
      const scale = sheetFitScale(box.clientWidth);
      setFit((current) => {
        if (scale === null) return current === null ? current : null;
        const height = Math.ceil(sheet.offsetHeight * scale);
        return current && current.scale === scale && current.height === height ? current : { scale, height };
      });
    };
    const observer = new ResizeObserver(measure);
    observer.observe(box);
    observer.observe(sheet);
    measure();
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={outer} className={styles.outer} data-fit={fit ? "" : undefined} style={fit ? { height: fit.height } : undefined}>
      <div
        ref={inner}
        className={styles.inner}
        style={fit ? { width: A4_SCREEN_PX, transform: `scale(${fit.scale})`, transformOrigin: "top left" } : undefined}
      >
        {children}
      </div>
    </div>
  );
}
