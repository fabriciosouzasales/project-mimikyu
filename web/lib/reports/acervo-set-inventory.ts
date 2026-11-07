/**
 * V1-14 R1-B — regras puras do relatório "Inventário detalhado por Card Set" (relatório 02 do
 * Acervo; o 01, "Inventário geral e por coleção", vive em `acervo-reports.ts`). Sem banco, sem rede.
 *
 * Leituras existentes, nenhuma SQL nova:
 *  - 5160 `get_my_inventory_summary`: exemplares, diferentes (Card Variant + idioma), Sets, repetidas;
 *  - 5159 `get_my_inventory_items` com `p_sort = 'SET_NUMBER'`: TODOS os grupos Card Variant + idioma
 *    do acervo (sem filtro de coleção — a alocação não importa), na ordem canônica do Acervo
 *    (Set: lançamento mais recente primeiro; dentro do Set: `collector_order`, variante, idioma);
 *  - 3983 `get_card_variants_pricing_summary`: referência NM unitária por variante.
 * Conferência: Σ exemplares das linhas = total do acervo e nº de linhas = diferentes; senão,
 * incompleto (impressão bloqueada, D7.8). Preço ausente/≤ 0 = sem cotação — fora das somas, nunca zero.
 */
import { type InventorySummaryInput, plural, shareText } from "./acervo-reports.ts";

export type SetInventoryItemInput = {
  cardVariantId: string;
  languageCode: string;
  cardName: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  variantLabel: string | null;
  isDefaultVariant: boolean;
  copies: number;
  /** Nome do idioma (5159) — usado pelo Top 10 (R1-F); opcional para os demais relatórios. */
  languageName?: string | null;
  /** Frente da carta no bucket público `card-front` (5159) — miniatura do Top 10 (R1-F). */
  imagePath?: string | null;
  /** `rarity.code` da CARTA (5159/5261) — Distribuição por raridade (R1-H); `null` = carta sem raridade. */
  rarityCode?: string | null;
};

/** Referência NM unitária válida (> 0) por variante; ausente = sem cotação. */
export type SetInventoryPriceInput = { brl: number; basis: "VARIANT" | "CARD_FALLBACK" | null; observedAt: string | null };

export type SetInventoryLine = SetInventoryItemInput & {
  unitBrl: number | null;
  totalBrl: number | null;
  priceBasis: SetInventoryPriceInput["basis"];
};

export type InventorySetGroup = {
  code: string;
  name: string;
  lines: SetInventoryLine[];
  copies: number;
  pricedCopies: number;
  unpricedCopies: number;
  /** Σ dos cotados; `null` se nenhum exemplar do Set tem cotação. */
  subtotalBrl: number | null;
};

export type SetInventoryReport = {
  totalCopies: number;
  distinctItems: number;
  distinctSets: number;
  duplicateCopies: number;
  pricedCopies: number;
  unpricedCopies: number;
  /** Σ dos exemplares cotados; `null` sem nenhum cotado (nunca R$ 0 por ausência). */
  totalBrl: number | null;
  priceObservedMin: string | null;
  priceObservedMax: string | null;
  sets: InventorySetGroup[];
  complete: boolean;
  incompleteReason: "mismatch" | "too_large" | null;
};

/** Centavos inteiros: somas exatas (sem acúmulo de erro de ponto flutuante). */
const cents = (brl: number) => Math.round(brl * 100);

export function buildSetInventoryReport(input: {
  summary: InventorySummaryInput;
  items: readonly SetInventoryItemInput[];
  prices: ReadonlyMap<string, SetInventoryPriceInput>;
  /** Todas as páginas foram lidas (sem teto). */
  itemsComplete: boolean;
}): SetInventoryReport {
  const groups = new Map<string, InventorySetGroup & { subtotalCents: number }>();
  let pricedCopies = 0;
  let totalCents = 0;
  let copiesSum = 0;
  let obsMin: string | null = null;
  let obsMax: string | null = null;
  for (const item of input.items) {
    const price = input.prices.get(item.cardVariantId.toLowerCase());
    const unit = price && price.brl > 0 ? price.brl : null;
    const lineCents = unit === null ? null : cents(unit) * item.copies;
    const line: SetInventoryLine = {
      ...item,
      unitBrl: unit,
      totalBrl: lineCents === null ? null : lineCents / 100,
      priceBasis: unit === null ? null : (price?.basis ?? null),
    };
    let group = groups.get(item.cardSetCode);
    if (!group) {
      group = { code: item.cardSetCode, name: item.cardSetName, lines: [], copies: 0, pricedCopies: 0, unpricedCopies: 0, subtotalBrl: null, subtotalCents: 0 };
      groups.set(item.cardSetCode, group);
    }
    group.lines.push(line);
    group.copies += item.copies;
    copiesSum += item.copies;
    if (lineCents === null) {
      group.unpricedCopies += item.copies;
    } else {
      group.pricedCopies += item.copies;
      group.subtotalCents += lineCents;
      pricedCopies += item.copies;
      totalCents += lineCents;
      const at = price?.observedAt ?? null;
      if (at) {
        if (!obsMin || at < obsMin) obsMin = at;
        if (!obsMax || at > obsMax) obsMax = at;
      }
    }
  }
  const sets = [...groups.values()].map(({ subtotalCents, ...g }) => ({ ...g, subtotalBrl: g.pricedCopies > 0 ? subtotalCents / 100 : null }));
  const { summary } = input;
  const balanced = copiesSum === summary.totalCopies && input.items.length === summary.distinctItems;
  const incompleteReason = !input.itemsComplete ? "too_large" : !balanced ? "mismatch" : null;
  return {
    totalCopies: summary.totalCopies,
    distinctItems: summary.distinctItems,
    distinctSets: summary.distinctSets,
    duplicateCopies: summary.duplicateCopies,
    pricedCopies,
    unpricedCopies: copiesSum - pricedCopies,
    totalBrl: pricedCopies > 0 ? totalCents / 100 : null,
    priceObservedMin: obsMin,
    priceObservedMax: obsMax,
    sets,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

const BRL = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });

export function formatBrl(value: number): string {
  return BRL.format(value);
}

/** "N% dos exemplares com preço" — percentual calculado e truncado (nunca 100% com exemplar sem preço). */
export function coverageText(report: Pick<SetInventoryReport, "pricedCopies" | "totalCopies">): string {
  return `${shareText(report.pricedCopies, report.totalCopies)} dos exemplares com preço`;
}

export function collectorLabel(line: Pick<SetInventoryLine, "collectorNumber" | "collectorTotal">): string {
  if (!line.collectorNumber) return "—";
  return line.collectorTotal ? `${line.collectorNumber}/${line.collectorTotal}` : line.collectorNumber;
}

export function variantLabelText(line: Pick<SetInventoryLine, "variantLabel" | "isDefaultVariant">): string {
  return line.variantLabel ?? (line.isDefaultVariant ? "Padrão" : "Variante");
}

export function setInventorySummaryLine(report: SetInventoryReport): string {
  return [
    plural(report.totalCopies, "exemplar", "exemplares"),
    plural(report.distinctItems, "diferente", "diferentes"),
    plural(report.sets.length, "Card Set", "Card Sets"),
  ].join(" · ");
}

export function setInventoryIncompleteText(reason: SetInventoryReport["incompleteReason"]): string | null {
  if (reason === "too_large") return "O acervo tem mais itens do que esta versão consegue listar; a impressão fica indisponível para não sair incompleta.";
  if (reason === "mismatch") return "As linhas não fecharam com o total do acervo no momento da leitura (o acervo mudou durante a leitura?). Tente novamente; a impressão fica indisponível.";
  return null;
}
