// Project Mimikyu — Modelo de apresentação do indicador de variantes da galeria
// (VARIANT-DISPLAY-SEMANTICS-01 / F2.2, Nível 2).
//
// Função pura sobre a projeção de cliente `CartaVariantViewState` (F2.1). Não
// reimplementa nenhuma regra da F1: ordem, partes e colisões chegam prontas.
// Só decide o que o indicador e o popover mostram:
//   - D1: separador textual " / " (aria-label e texto de cada linha);
//   - D2: estado ERROR mostra a contagem bruta + "Detalhes indisponíveis",
//         nunca os nomes legados (I8, sem fallback);
//   - G-COMP PASS (2026-10-09): `rawCount` é a contagem cadastrada.
// Sem dependência de React, Supabase ou rede — testável com node:test.
// Usado também no servidor pelo relatório "Card Variants por Carta" (F2.3).

import type { CartaVariantViewState } from "./carta-variants.ts";
import type { CardVariantLabelAxis } from "./card-variant-display.ts";

/** D1 (CLOSED). Duplicado de `CARD_VARIANT_LABEL_SEPARATOR` para não puxar a F1 para o bundle do cliente. */
export const VARIANT_LABEL_SEPARATOR = " / ";

export type VariantSummaryLinePart = {
  axis: CardVariantLabelAxis;
  text: string;
  /** Finish é o termo principal; Printing e Edition Context são qualificadores. */
  emphasis: "primary" | "qualifier";
};

export type VariantSummaryLine = {
  /** `card_variant.id` — chave React. */
  id: string;
  parts: VariantSummaryLinePart[];
  /** Texto único da linha com D1, para leitores de tela. */
  label: string;
  /** Outra variante da mesma carta tem o mesmo texto (M3: sinalizar, nunca deduplicar). */
  repeatedLabel: boolean;
};

export type VariantSummaryModel =
  | { kind: "HIDDEN" }
  | { kind: "LIST"; count: number; lines: VariantSummaryLine[]; triggerLabel: string }
  | { kind: "UNAVAILABLE"; count: number | null; triggerLabel: string };

function plural(count: number): string {
  return count === 1 ? "1 variação cadastrada" : `${count} variações cadastradas`;
}

/**
 * F2.3 — presença de variante para filtros "Com/Sem variantes".
 * Ausência de projeção ou NONE = sem variante. OK e ERROR = com variante:
 * um ERROR significa que há linhas, só que com dados incompletos (D2), então
 * nunca é tratado como "sem variante".
 */
export function hasCartaVariants(view: CartaVariantViewState | null | undefined): boolean {
  return !!view && view.status !== "NONE";
}

/**
 * F2.3 — quantidade cadastrada para relatórios e totais (G-COMP PASS:
 * `rawCount` = `count(card_variant)`). `null` só quando a contagem é
 * desconhecida (ERROR sem lista); quem soma deve tratar esse caso à parte.
 */
export function cartaVariantCount(view: CartaVariantViewState | null | undefined): number | null {
  if (!view || view.status === "NONE") return 0;
  return typeof view.rawCount === "number" ? view.rawCount : null;
}

export function buildVariantSummaryModel(view: CartaVariantViewState | null | undefined, cartaName: string): VariantSummaryModel {
  if (!view || view.status === "NONE") return { kind: "HIDDEN" };

  if (view.status === "ERROR") {
    const count = typeof view.rawCount === "number" ? view.rawCount : null;
    const countText = count === null ? "variações cadastradas" : plural(count);
    return {
      kind: "UNAVAILABLE",
      count,
      triggerLabel: `${cartaName}: ${countText}, detalhes indisponíveis`,
    };
  }

  const lines: VariantSummaryLine[] = view.variants.map((variant) => {
    const parts: VariantSummaryLinePart[] = variant.parts.map((part) => ({
      axis: part.axis,
      text: part.text,
      emphasis: part.axis === "FINISH" ? "primary" : "qualifier",
    }));
    return {
      id: variant.id,
      parts,
      label: parts.map((part) => part.text).join(VARIANT_LABEL_SEPARATOR),
      repeatedLabel: variant.collidesWith.length > 0 || variant.renderedCollidesWith.length > 0,
    };
  });

  return {
    kind: "LIST",
    count: view.rawCount,
    lines,
    triggerLabel: `Ver variações de ${cartaName}: ${plural(view.rawCount)}`,
  };
}
