/**
 * V1-14 R1-C — relatório 03 do Meu acervo, "Valor estimado total": visão patrimonial executiva do
 * acervo físico inteiro (independente de coleção), por Card Set. Sem banco, sem rede.
 *
 * NÃO tem leitura nem regra monetária própria: é uma projeção do Inventário detalhado por Card Set
 * (`buildSetInventoryReport`, leituras 5160/5159/3989), que já calcula quantidade × unitário NM em
 * centavos inteiros e deixa preço ausente fora das somas. Aqui só se agregam os grupos, sem linhas
 * por carta:
 *  - valor por Card Set = subtotal dos cotados (centavos exatos); Set sem cotado → `null` (nunca 0);
 *  - participação = centavos do Set ÷ centavos do total, exibida com uma casa decimal TRUNCADA
 *    (nunca "100,0%" sem ser o total; "<0,1%" para participação positiva menor que 0,1%); a soma
 *    exibida pode não fechar 100% — não há ajuste artificial;
 *  - ordem: valor decrescente, depois nome e código (pt-BR); Sets sem cotação por último;
 *  - exemplares sem cotação: total e por Card Set (a lista carta a carta pertence ao relatório
 *    "Cobertura de preços");
 *  - completude: herdada do inventário (incompleto → impressão bloqueada).
 */
import { formatCount, plural, shareText } from "./acervo-reports.ts";
import type { SetInventoryReport } from "./acervo-set-inventory.ts";

export type AcervoValueSetRow = {
  code: string;
  name: string;
  copies: number;
  pricedCopies: number;
  unpricedCopies: number;
  /** Subtotal dos cotados; `null` quando o Set não tem exemplar cotado. */
  valueBrl: number | null;
  /** Participação no valor total (0..1); `null` sem valor no Set ou sem total. */
  share: number | null;
};

export type AcervoValueReport = {
  totalBrl: number | null;
  totalCopies: number;
  pricedCopies: number;
  unpricedCopies: number;
  /** Card Sets no acervo. */
  setCount: number;
  /** Card Sets com ao menos um exemplar cotado. */
  pricedSetCount: number;
  /** Exemplares cotados pela referência geral da carta (variante sem cotação própria). */
  fallbackCopies: number;
  priceObservedMin: string | null;
  priceObservedMax: string | null;
  sets: AcervoValueSetRow[];
  complete: boolean;
  incompleteReason: SetInventoryReport["incompleteReason"];
};

const cents = (brl: number) => Math.round(brl * 100);
const NAME_ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });

export function buildAcervoValueReport(inventory: SetInventoryReport): AcervoValueReport {
  const totalCents = inventory.totalBrl === null ? null : cents(inventory.totalBrl);
  let fallbackCopies = 0;
  const rows = inventory.sets.map((set) => {
    for (const line of set.lines) if (line.unitBrl !== null && line.priceBasis === "CARD_FALLBACK") fallbackCopies += line.copies;
    const setCents = set.subtotalBrl === null ? null : cents(set.subtotalBrl);
    return {
      row: {
        code: set.code,
        name: set.name,
        copies: set.copies,
        pricedCopies: set.pricedCopies,
        unpricedCopies: set.unpricedCopies,
        valueBrl: setCents === null ? null : setCents / 100,
        share: setCents === null || !totalCents ? null : setCents / totalCents,
      } satisfies AcervoValueSetRow,
      setCents,
    };
  });
  rows.sort((a, b) => {
    if (a.setCents !== b.setCents) {
      if (a.setCents === null) return 1;
      if (b.setCents === null) return -1;
      return b.setCents - a.setCents;
    }
    return NAME_ORDER.compare(a.row.name, b.row.name) || NAME_ORDER.compare(a.row.code, b.row.code);
  });
  const sets = rows.map((r) => r.row);
  return {
    totalBrl: inventory.totalBrl,
    totalCopies: inventory.totalCopies,
    pricedCopies: inventory.pricedCopies,
    unpricedCopies: inventory.unpricedCopies,
    setCount: sets.length,
    pricedSetCount: sets.filter((s) => s.valueBrl !== null).length,
    fallbackCopies,
    priceObservedMin: inventory.priceObservedMin,
    priceObservedMax: inventory.priceObservedMax,
    sets,
    complete: inventory.complete,
    incompleteReason: inventory.incompleteReason,
  };
}

const ONE_DECIMAL = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

/** Participação com uma casa decimal truncada: "—" sem valor, "<0,1%" mínima, "100,0%" só se for o total. */
export function valueShareText(share: number | null): string {
  if (share === null || share <= 0) return "—";
  if (share >= 1) return "100,0%";
  const tenths = Math.floor(share * 1000 + 1e-9);
  if (tenths === 0) return "<0,1%";
  return `${ONE_DECIMAL.format(tenths / 10)}%`;
}

/** Largura da barra de participação (0–100), proporcional ao valor total; mínima visível para "<0,1%". */
export function valueShareBarPercent(share: number | null): number {
  if (share === null || share <= 0) return 0;
  return Math.min(100, Math.max(0.6, share * 100));
}

/** "X de Y exemplares com preço" — proporção de exemplares com referência, não precisão do valor. */
export function valueCoverageText(report: Pick<AcervoValueReport, "pricedCopies" | "totalCopies">): string {
  return `${formatCount(report.pricedCopies)} de ${plural(report.totalCopies, "exemplar", "exemplares")} com preço`;
}

export function valueCoveragePercent(report: Pick<AcervoValueReport, "pricedCopies" | "totalCopies">): string {
  return shareText(report.pricedCopies, report.totalCopies);
}

const DATE = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });

/** Período das observações de preço usadas: "05/11/2026" ou "03/11/2026 a 06/11/2026"; `null` sem cotação. */
export function priceObservationPeriod(report: Pick<AcervoValueReport, "priceObservedMin" | "priceObservedMax">): string | null {
  if (!report.priceObservedMin || !report.priceObservedMax) return null;
  const min = new Date(report.priceObservedMin);
  const max = new Date(report.priceObservedMax);
  if (Number.isNaN(min.getTime()) || Number.isNaN(max.getTime())) return null;
  const a = DATE.format(min);
  const b = DATE.format(max);
  return a === b ? a : `${a} a ${b}`;
}

export function acervoValueSummaryLine(report: AcervoValueReport): string {
  return [plural(report.totalCopies, "exemplar", "exemplares"), plural(report.setCount, "Card Set", "Card Sets")].join(" · ");
}
