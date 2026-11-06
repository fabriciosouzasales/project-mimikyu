/**
 * V1-14 R1-F — "Top 10 cartas mais valiosas" (6º relatório do Meu acervo). Regras puras, sem banco,
 * sem rede.
 *
 * Base = o MESMO inventário com preços do Inventário detalhado (02) e do Valor estimado total (03)
 * (`buildSetInventoryReport`, centavos): todo o acervo físico do titular, independente de coleção,
 * um grupo por variante + idioma. Uma posição por grupo; a mesma variante em dois idiomas pode
 * ocupar duas posições (A).
 *
 * Elegível: grupo com exemplar e referência NM unitária válida (> 0). Sem cotação nunca vale zero
 * e fica fora do ranking (conta na cobertura). Referência geral da carta (`CARD_FALLBACK`) entra,
 * sinalizada (B); referência com observação > 14 dias entra como desatualizada, com a data (G).
 *
 * Ordem: referência unitária em centavos, decrescente — a quantidade nunca interfere; desempates:
 * nome do Card Set (pt-BR), número de colecionador crescente (numérico), variante, idioma e o id da
 * variante (estável). Exatamente 10 posições; grupos empatados com a 10ª são informados (C).
 *
 * Valor das cópias = unitário × exemplares, rotulado à parte; participação do Top 10 sobre o valor
 * estimado dos exemplares cotados — o `totalBrl` do mesmo inventário (D, mesma base do 03).
 * Preço indisponível (bloco que falhou) → ranking provisório, impressão bloqueada (F).
 */
import { formatCount, plural } from "./acervo-reports.ts";
import type { SetInventoryLine, SetInventoryPriceInput, SetInventoryReport } from "./acervo-set-inventory.ts";
import { PRICE_STALE_AFTER_DAYS, daysSince, formatObservedDate, isInternationalReference } from "../pricing/variant-pricing.ts";

export const TOP_CARDS_LIMIT = 10;

export type TopCardLine = {
  rank: number;
  cardVariantId: string;
  languageCode: string;
  languageName: string | null;
  cardName: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  variantLabel: string | null;
  isDefaultVariant: boolean;
  copies: number;
  unitBrl: number;
  /** Unitário × exemplares (centavos exatos). */
  copiesBrl: number;
  /** Referência geral da carta — não é cotação específica da variante. */
  generalCardPrice: boolean;
  observedAt: string | null;
  stale: boolean;
  international: boolean;
  imageUrl: string | null;
};

export type TopCardsIncompleteReason = "too_large" | "mismatch" | "prices_unavailable" | null;

export type TopCardsReport = {
  lines: TopCardLine[];
  /** Grupos variante + idioma do acervo (linhas lidas). */
  totalGroups: number;
  /** Grupos com referência válida (elegíveis). */
  pricedGroups: number;
  /** Grupos cujo preço não pôde ser lido agora. */
  unavailableGroups: number;
  totalCopies: number;
  pricedCopies: number;
  /** Σ valor das cópias das posições; `null` sem posições. */
  topCopiesBrl: number | null;
  topCopies: number;
  /** Valor estimado dos exemplares cotados — mesma base do Valor estimado total. */
  estimatedTotalBrl: number | null;
  /** topCopies ÷ estimado (0–1); `null` sem base. */
  topShare: number | null;
  /** Grupos fora do Top 10 com a mesma referência unitária da 10ª posição. */
  tiedBeyond: number;
  complete: boolean;
  incompleteReason: TopCardsIncompleteReason;
};

const ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });
const cents = (brl: number) => Math.round(brl * 100);
const LAST = "￿";

/** Desempate determinístico entre grupos de mesma referência unitária. */
function tieBreak(a: SetInventoryLine, b: SetInventoryLine): number {
  return (
    ORDER.compare(a.cardSetName, b.cardSetName) ||
    ORDER.compare(a.cardSetCode, b.cardSetCode) ||
    ORDER.compare(a.collectorNumber ?? LAST, b.collectorNumber ?? LAST) ||
    ORDER.compare(a.variantLabel ?? "", b.variantLabel ?? "") ||
    ORDER.compare(a.languageCode, b.languageCode) ||
    (a.cardVariantId < b.cardVariantId ? -1 : a.cardVariantId > b.cardVariantId ? 1 : 0)
  );
}

export function buildTopCardsReport(input: {
  inventory: SetInventoryReport;
  /** Referências usadas no inventário (data da observação por variante). */
  prices: ReadonlyMap<string, SetInventoryPriceInput>;
  /** Variantes cujo bloco de preço falhou (Pricing Resilience). */
  unavailable: ReadonlySet<string>;
  now: number;
  imageUrl?: (path: string) => string | null;
}): TopCardsReport {
  const { inventory } = input;
  const all = inventory.sets.flatMap((set) => set.lines);
  const priced = all.filter((line): line is SetInventoryLine & { unitBrl: number } => line.unitBrl !== null && line.unitBrl > 0);
  const unavailableGroups = all.filter((line) => line.unitBrl === null && input.unavailable.has(line.cardVariantId.toLowerCase())).length;
  const sorted = [...priced].sort((a, b) => cents(b.unitBrl) - cents(a.unitBrl) || tieBreak(a, b));
  const top = sorted.slice(0, TOP_CARDS_LIMIT);
  const last = top[TOP_CARDS_LIMIT - 1];
  const tiedBeyond = last ? sorted.slice(TOP_CARDS_LIMIT).filter((line) => cents(line.unitBrl) === cents(last.unitBrl)).length : 0;

  let topCents = 0;
  let topCopies = 0;
  const lines: TopCardLine[] = top.map((line, index) => {
    const unitCents = cents(line.unitBrl);
    const copiesCents = unitCents * line.copies;
    topCents += copiesCents;
    topCopies += line.copies;
    const observedAt = input.prices.get(line.cardVariantId.toLowerCase())?.observedAt ?? null;
    const age = daysSince(observedAt, input.now);
    const imagePath = line.imagePath ?? null;
    return {
      rank: index + 1,
      cardVariantId: line.cardVariantId,
      languageCode: line.languageCode,
      languageName: line.languageName ?? null,
      cardName: line.cardName,
      collectorNumber: line.collectorNumber,
      collectorTotal: line.collectorTotal,
      cardSetCode: line.cardSetCode,
      cardSetName: line.cardSetName,
      variantLabel: line.variantLabel,
      isDefaultVariant: line.isDefaultVariant,
      copies: line.copies,
      unitBrl: unitCents / 100,
      copiesBrl: copiesCents / 100,
      generalCardPrice: line.priceBasis !== "VARIANT",
      observedAt,
      stale: age !== null && age > PRICE_STALE_AFTER_DAYS,
      international: isInternationalReference(line.languageCode),
      imageUrl: imagePath && input.imageUrl ? input.imageUrl(imagePath) : null,
    };
  });

  const estimatedCents = inventory.totalBrl === null ? null : cents(inventory.totalBrl);
  const incompleteReason: TopCardsIncompleteReason = inventory.incompleteReason ?? (unavailableGroups > 0 ? "prices_unavailable" : null);
  return {
    lines,
    totalGroups: all.length,
    pricedGroups: priced.length,
    unavailableGroups,
    totalCopies: inventory.totalCopies,
    pricedCopies: inventory.pricedCopies,
    topCopiesBrl: lines.length > 0 ? topCents / 100 : null,
    topCopies,
    estimatedTotalBrl: inventory.totalBrl,
    topShare: estimatedCents && estimatedCents > 0 && lines.length > 0 ? topCents / estimatedCents : null,
    tiedBeyond,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

export function topCollectorText(line: Pick<TopCardLine, "collectorNumber" | "collectorTotal">): string {
  if (!line.collectorNumber) return "—";
  return line.collectorTotal ? `${line.collectorNumber}/${line.collectorTotal}` : line.collectorNumber;
}

/** Segunda linha: Card Set · número · variante · idioma. */
export function topIdentityText(line: TopCardLine): string {
  const variant = line.variantLabel ?? (line.isDefaultVariant ? "Padrão" : "Variante");
  return [`${line.cardSetName} (${line.cardSetCode})`, topCollectorText(line), variant, line.languageName ?? line.languageCode].join(" · ");
}

/** Sinais da referência, na ordem do contrato. */
export function topPriceFlags(line: Pick<TopCardLine, "generalCardPrice" | "stale" | "international">): string[] {
  const flags: string[] = [];
  if (line.generalCardPrice) flags.push("Preço geral da carta");
  if (line.stale) flags.push("Desatualizada");
  if (line.international) flags.push("Referência internacional");
  return flags;
}

export function topObservedText(line: Pick<TopCardLine, "observedAt">): string {
  const date = formatObservedDate(line.observedAt);
  return date ? `obs. ${date}` : "data não disponível";
}

export function topCardsSummaryLine(report: Pick<TopCardsReport, "lines" | "pricedGroups">): string {
  return `${plural(report.lines.length, "posição", "posições")} · ${plural(report.pricedGroups, "item cotado", "itens cotados")} no acervo`;
}

/** "X de Y itens (variante + idioma) com cotação" — grupos, não exemplares. */
export function topCoverageText(report: Pick<TopCardsReport, "pricedGroups" | "totalGroups" | "unavailableGroups">): string {
  const base = `${formatCount(report.pricedGroups)} de ${plural(report.totalGroups, "item", "itens")} com cotação`;
  return report.unavailableGroups > 0 ? `${base} · ${plural(report.unavailableGroups, "indisponível agora", "indisponíveis agora")}` : base;
}

export function topTiedText(report: Pick<TopCardsReport, "tiedBeyond">): string | null {
  if (report.tiedBeyond <= 0) return null;
  return `e mais ${plural(report.tiedBeyond, "item", "itens")} com a mesma referência da 10ª posição, fora do ranking pelo desempate`;
}

export function topCardsIncompleteText(reason: TopCardsIncompleteReason): string | null {
  if (reason === "too_large") return "O acervo tem mais itens do que esta versão consegue ler; o ranking pode não estar completo e a impressão fica indisponível.";
  if (reason === "mismatch") return "As linhas não fecharam com o total do acervo no momento da leitura (o acervo mudou durante a leitura?). Tente novamente; a impressão fica indisponível.";
  if (reason === "prices_unavailable")
    return "Alguns preços de referência não puderam ser carregados agora: o ranking é provisório (um item sem preço lido poderia estar entre os dez) e a impressão fica indisponível. Tente novamente em instantes.";
  return null;
}
