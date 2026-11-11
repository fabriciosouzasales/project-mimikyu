import type { ReactNode } from "react";
import styles from "./storage-glyph.module.css";

/**
 * Recipientes desenhados (STORAGE LOCATIONS CONCEPT B, linguagem gráfica da
 * rodada ART DIRECTION & UX-02). Um objeto por tipo do catálogo (5212), de
 * frente, na mesma gramática: traço único em `currentColor`, duas superfícies
 * grafite (`--obj`/`--obj-2`) e UM detalhe dourado — a etiqueta do fichário, o
 * lacre da tampa do ETB, o entalhe da caixa. Tipo novo ou sem tipo → recipiente
 * genérico tracejado. Decorativo (`aria-hidden`): o tipo sempre está escrito ao
 * lado. Opcionalmente escreve o código do colecionador no próprio objeto
 * (painel do local); `open` = tampa erguida / fichário na página de bolsos.
 */

const S = { stroke: "currentColor", strokeWidth: 1.6, strokeLinejoin: "round", strokeLinecap: "round" } as const;

type LabelAt = { x: number; y: number; max: number; onPaper?: boolean };

const LABEL_AT: Record<string, LabelAt> = {
  BINDER: { x: 67, y: 34.5, max: 30, onPaper: true },
  ETB: { x: 60, y: 26.5, max: 70 },
  BOX: { x: 60, y: 70, max: 56 },
  DECK_BOX: { x: 60, y: 62, max: 34 },
  FOLDER: { x: 60, y: 76, max: 60 },
  CASE: { x: 60, y: 72, max: 30 },
  OTHER: { x: 60, y: 78, max: 60 },
};

function Label({ at, text }: { at: LabelAt; text: string }) {
  const size = text.length > 6 ? 8 : text.length > 4 ? 9 : 10;
  const fit = text.length * size * 0.66 > at.max;
  return (
    <text
      x={at.x}
      y={at.y}
      textAnchor="middle"
      className={at.onPaper ? styles.labelOnPaper : styles.label}
      fontSize={size}
      fontWeight={800}
      letterSpacing={0.3}
      {...(fit ? { textLength: at.max, lengthAdjust: "spacingAndGlyphs" as const } : {})}
    >
      {text}
    </text>
  );
}

function shape(kind: string, label: ReactNode, hasLabel: boolean): ReactNode {
  switch (kind) {
    case "BINDER":
      return (
        <g className={styles.binder}>
          <rect x="26" y="8" width="70" height="82" rx="5" className={styles.surface} {...S} />
          <g className={styles.cover}>
            <rect x="26" y="8" width="70" height="82" rx="5" className={styles.surface} {...S} />
            <rect x="26" y="8" width="13" height="82" rx="4" className={styles.surface2} {...S} />
            <circle cx="32.5" cy="26" r="1.8" fill="currentColor" />
            <circle cx="32.5" cy="49" r="1.8" fill="currentColor" />
            <circle cx="32.5" cy="72" r="1.8" fill="currentColor" />
            <rect x="50" y="22" width="34" height="18" rx="2.5" className={styles.paper} stroke="var(--glyph-gold)" strokeWidth="1.6" />
            {hasLabel ? null : <path d="M55 29h24M55 34h15" className={styles.ink} strokeWidth="1.4" strokeLinecap="round" />}
            {label}
          </g>
          <g className={styles.pages}>
            <rect x="44" y="14" width="46" height="70" rx="2" className={styles.paper} {...S} />
            <path d="M52 22h12v16H52zM70 22h12v16H70zM52 44h12v16H52zM70 44h12v16H70zM52 66h12v12H52zM70 66h12v12H70z" fill="none" className={styles.ink} strokeWidth="1.2" />
          </g>
        </g>
      );
    case "ETB":
      return (
        <g>
          <rect x="24" y="30" width="72" height="60" rx="3" className={styles.surface2} {...S} />
          <rect x="40" y="48" width="40" height="30" rx="2" className={styles.paper} {...S} />
          <path d="M47 54v18M53 52v22M59 54v18M65 52v22M71 54v18" className={styles.ink} strokeWidth="1.4" strokeLinecap="round" />
          <g className={styles.lid}>
            <rect x="19" y="14" width="82" height="22" rx="3" className={styles.surface} {...S} />
            <path d="M19 30h82" stroke="var(--glyph-gold)" strokeWidth="2" />
            {label}
          </g>
        </g>
      );
    case "BOX":
      return (
        <g>
          <rect x="8" y="42" width="104" height="44" rx="3" className={styles.surface2} {...S} />
          <path d="M30 42v44M90 42v44" className={styles.line} strokeWidth="1.2" />
          <g className={styles.lid}>
            <rect x="6" y="30" width="108" height="16" rx="3" className={styles.surface} {...S} />
            <path d="M52 46a8 7 0 0 0 16 0" className={styles.paper} stroke="var(--glyph-gold)" strokeWidth="1.8" />
          </g>
          {label}
        </g>
      );
    case "FOLDER":
      return (
        <g>
          <rect x="18" y="12" width="84" height="76" rx="4" className={styles.surface} {...S} />
          <path d="M18 34l42 18 42-18" fill="none" {...S} />
          <rect x="56" y="46" width="8" height="12" rx="2" fill="var(--glyph-gold)" />
          {label}
        </g>
      );
    case "DECK_BOX":
      return (
        <g>
          <rect x="40" y="22" width="40" height="66" rx="3" className={styles.surface2} {...S} />
          <g className={styles.lid}>
            <rect x="38" y="12" width="44" height="24" rx="3" className={styles.surface} {...S} />
          </g>
          <rect x="54" y="32" width="12" height="7" rx="2" fill="var(--glyph-gold)" />
          {label}
        </g>
      );
    case "CASE":
      return (
        <g>
          <path d="M48 28v-8h24v8" fill="none" {...S} />
          <rect x="12" y="28" width="96" height="58" rx="7" className={styles.surface} {...S} />
          <path d="M12 50h96" className={styles.line} strokeWidth="1.2" />
          <rect x="32" y="44" width="10" height="12" rx="2" fill="var(--glyph-gold)" />
          <rect x="78" y="44" width="10" height="12" rx="2" fill="var(--glyph-gold)" />
          {label}
        </g>
      );
    case "SAFE":
      return (
        <g>
          <rect x="22" y="10" width="76" height="76" rx="5" className={styles.surface2} {...S} />
          <rect x="30" y="18" width="60" height="60" rx="3" className={styles.surface} {...S} />
          <circle cx="60" cy="48" r="11" fill="none" stroke="var(--glyph-gold)" strokeWidth="2" />
          <path d="M60 41v4M67 48h-4" stroke="var(--glyph-gold)" strokeWidth="2" strokeLinecap="round" />
          <path d="M30 88v4M90 88v4" {...S} />
        </g>
      );
    default:
      return (
        <g>
          <rect x="16" y="30" width="88" height="56" rx="5" className={styles.surface2} {...S} strokeDasharray="5 4" />
          <path d="M16 44h88" className={styles.line} strokeWidth="1.2" strokeDasharray="5 4" />
          <circle cx="60" cy="64" r="3" fill="var(--glyph-gold)" />
          {label}
        </g>
      );
  }
}

export function StorageGlyph({
  kindCode,
  code = null,
  open = false,
  className,
}: {
  kindCode: string | null;
  /** Código do colecionador escrito no objeto (só onde há espaço para lê-lo). */
  code?: string | null;
  open?: boolean;
  className?: string;
}) {
  const kind = kindCode ?? "OTHER";
  const at = LABEL_AT[kind] ?? (kind === "SAFE" ? null : LABEL_AT.OTHER);
  const label = code && at ? <Label at={at} text={code} /> : null;
  return (
    <svg
      className={`${styles.glyph} ${className ?? ""}`}
      data-open={open || undefined}
      viewBox="0 0 120 96"
      aria-hidden="true"
      focusable="false"
    >
      {shape(kind, label, label !== null)}
    </svg>
  );
}
