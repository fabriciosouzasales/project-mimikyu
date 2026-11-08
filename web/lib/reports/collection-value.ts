/**
 * V1-14 R2-E — "Valor estimado dos exemplares alocados" (relatório da Coleção; D7 v1.59 §4m,
 * decisões D1–D12). Regras puras, sem banco.
 *
 * - Unidade (D1): exemplar físico ALOCADO à coleção, apresentado por variante + idioma (grupo da
 *   5159 filtrada pela coleção). Valor do grupo = quantidade alocada × referência NM unitária, em
 *   centavos — a mesma conta de `buildSetInventoryReport` (R1-B/R1-C): `Math.round(brl × 100)` por
 *   unidade, depois × quantidade.
 * - Referência (D3): só o que `inventoryPriceInput` aceita (`has_pricing` e valor > 0), via 3989.
 * - Três estados por grupo, nunca confundidos (D7):
 *     A `priced`      — referência válida e positiva;
 *     B `unpriced`    — leitura bem-sucedida, sem referência válida ("Sem cotação");
 *     C `unavailable` — o bloco de preço falhou (falha técnica). Qualquer C → relatório provisório.
 *   C nunca entra em B nem vira zero; sem nenhum A, o total é `null` (nunca R$ 0).
 * - Sinais (D4, regra da R1-F): "Preço geral da carta" (referência que não é da própria variante) e
 *   "Desatualizada" (observação com mais de 14 dias), com a data. Sem "Referência internacional".
 * - Ordem (D9): grupos A por valor do grupo decrescente; empate pela ordem canônica do Set
 *   (`order` = posição na 5159 em `SET_NUMBER`: número de colecionador, variante, idioma, ids) e
 *   pelo id da variante. Grupos B e C num bloco final intercalado, na ordem do Set.
 * - Integridade (D11): Σ quantidades = `total_copies` (5159) = `copies_count` (5332); linhas =
 *   `total_count`; sem grupo repetido; teto de 5.000 grupos. Divergência → incompleto. As leituras
 *   sequenciais NÃO formam um snapshot transacional único: totais coincidentes não provam ausência
 *   de omissão — só tornam observáveis as mudanças que alteram contagens ou repetem/omitem grupos.
 */
import { PRICE_STALE_AFTER_DAYS, daysSince, formatObservedDate } from "../pricing/variant-pricing.ts";
import type { SetInventoryItemInput, SetInventoryPriceInput } from "./acervo-set-inventory.ts";

/** Teto contratual (D11): grupos variante + idioma. */
export const COLLECTION_VALUE_MAX_GROUPS = 5000;

export type CollectionValuePriceState = "priced" | "unpriced" | "unavailable";

/** Grupo da 5159 com a posição canônica na ordem `SET_NUMBER` (0, 1, 2…). */
export type CollectionValueItemInput = SetInventoryItemInput & { order: number };

export type CollectionValueLine = {
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
  /** Exemplares deste grupo alocados à coleção. */
  copies: number;
  /** Posição canônica do grupo na ordem do Set (5159 `SET_NUMBER`). */
  order: number;
  state: CollectionValuePriceState;
  /** Só em `priced`. */
  unitCents: number | null;
  /** Só em `priced`: unitCents × copies. */
  lineCents: number | null;
  generalCardPrice: boolean;
  stale: boolean;
  observedAt: string | null;
  imageUrl: string | null;
};

export type CollectionValueIncompleteReason = "too_large" | "duplicate" | "inconsistent_pages" | "total_mismatch" | "collection_mismatch" | null;

/** O que a leitura paginada da 5159 observou (preparação; ver `collection-value-queries.ts`). */
export type CollectionValueReadCheck = {
  /** `total_count` da 1ª página (grupos do recorte). */
  totalCount: number;
  /** `total_copies` da 1ª página (exemplares do recorte). */
  totalCopies: number;
  /** Algum grupo (variante + idioma) apareceu mais de uma vez entre as páginas. */
  duplicate: boolean;
  /** Totais diferentes entre páginas ou página intermediária menor que o esperado (omissão observável). */
  inconsistentPages: boolean;
};

export type CollectionValueReport = {
  state: "empty" | "ready";
  lines: CollectionValueLine[];
  /** Exemplares alocados (Σ das quantidades lidas). */
  copies: number;
  /** Grupos variante + idioma lidos. */
  groups: number;
  pricedCopies: number;
  pricedGroups: number;
  /** Só B (sem cotação legítima). */
  unpricedCopies: number;
  unpricedGroups: number;
  /** Só C (falha técnica). */
  unavailableCopies: number;
  unavailableGroups: number;
  /** Soma dos grupos A, em centavos; `null` sem nenhum A (nunca zero). */
  totalCents: number | null;
  /** Há grupo C: valor parcial, impressão não autorizada. */
  provisional: boolean;
  complete: boolean;
  incompleteReason: CollectionValueIncompleteReason;
  /** Impressão autorizada só com o conjunto completo e sem C (D7/D11). */
  printable: boolean;
  /** Datas extremas das observações usadas nos grupos A (nota metodológica); `null` sem datas. */
  observedFrom: string | null;
  observedTo: string | null;
};

const unitCentsOf = (brl: number) => Math.round(brl * 100);
const keyOf = (item: Pick<SetInventoryItemInput, "cardVariantId" | "languageCode">) => `${item.cardVariantId.toLowerCase()}|${item.languageCode}`;

/**
 * Constrói o relatório. `prices` = referências válidas (já filtradas por `inventoryPriceInput`);
 * `unavailable` = variantes cujo bloco de preço falhou; ausente nos dois = B (sem cotação).
 */
export function buildCollectionValueReport(input: {
  items: readonly CollectionValueItemInput[];
  prices: ReadonlyMap<string, SetInventoryPriceInput>;
  unavailable: ReadonlySet<string>;
  read: CollectionValueReadCheck;
  /** `copies_count` da 5332 (alocações da coleção autorizada). */
  collectionCopies: number;
  now: number;
  imageUrl?: (path: string) => string | null;
}): CollectionValueReport {
  const seen = new Set<string>();
  let duplicate = input.read.duplicate;
  const lines: CollectionValueLine[] = [];
  let copies = 0;
  let pricedCopies = 0;
  let pricedGroups = 0;
  let unpricedCopies = 0;
  let unpricedGroups = 0;
  let unavailableCopies = 0;
  let unavailableGroups = 0;
  let totalCents = 0;
  let observedFrom: string | null = null;
  let observedTo: string | null = null;

  for (const item of input.items) {
    const key = keyOf(item);
    if (seen.has(key)) duplicate = true;
    seen.add(key);
    const id = item.cardVariantId.toLowerCase();
    const price = input.prices.get(id);
    const state: CollectionValuePriceState = input.unavailable.has(id) ? "unavailable" : price ? "priced" : "unpriced";
    copies += item.copies;
    let unitCents: number | null = null;
    let lineCents: number | null = null;
    let observedAt: string | null = null;
    let generalCardPrice = false;
    let stale = false;
    if (state === "priced" && price) {
      unitCents = unitCentsOf(price.brl);
      lineCents = unitCents * item.copies;
      totalCents += lineCents;
      pricedCopies += item.copies;
      pricedGroups += 1;
      observedAt = price.observedAt;
      generalCardPrice = price.basis !== "VARIANT";
      const age = daysSince(observedAt, input.now);
      stale = age !== null && age > PRICE_STALE_AFTER_DAYS;
      if (observedAt && Number.isFinite(Date.parse(observedAt))) {
        if (observedFrom === null || Date.parse(observedAt) < Date.parse(observedFrom)) observedFrom = observedAt;
        if (observedTo === null || Date.parse(observedAt) > Date.parse(observedTo)) observedTo = observedAt;
      }
    } else if (state === "unpriced") {
      unpricedCopies += item.copies;
      unpricedGroups += 1;
    } else {
      unavailableCopies += item.copies;
      unavailableGroups += 1;
    }
    const imagePath = item.imagePath ?? null;
    lines.push({
      cardVariantId: id,
      languageCode: item.languageCode,
      languageName: item.languageName ?? null,
      cardName: item.cardName,
      collectorNumber: item.collectorNumber,
      collectorTotal: item.collectorTotal,
      cardSetCode: item.cardSetCode,
      cardSetName: item.cardSetName,
      variantLabel: item.variantLabel,
      isDefaultVariant: item.isDefaultVariant,
      copies: item.copies,
      order: item.order,
      state,
      unitCents,
      lineCents,
      generalCardPrice,
      stale,
      observedAt,
      imageUrl: imagePath && input.imageUrl ? input.imageUrl(imagePath) : null,
    });
  }

  lines.sort(compareLines);

  const groups = lines.length;
  const incompleteReason: CollectionValueIncompleteReason =
    input.read.totalCount > COLLECTION_VALUE_MAX_GROUPS
      ? "too_large"
      : duplicate
        ? "duplicate"
        : input.read.inconsistentPages
          ? "inconsistent_pages"
          : groups !== input.read.totalCount || copies !== input.read.totalCopies
            ? "total_mismatch"
            : copies !== input.collectionCopies
              ? "collection_mismatch"
              : null;
  const complete = incompleteReason === null;
  const provisional = unavailableGroups > 0;
  return {
    state: groups === 0 && complete ? "empty" : "ready",
    lines,
    copies,
    groups,
    pricedCopies,
    pricedGroups,
    unpricedCopies,
    unpricedGroups,
    unavailableCopies,
    unavailableGroups,
    totalCents: pricedGroups > 0 ? totalCents : null,
    provisional,
    complete,
    incompleteReason,
    printable: complete && !provisional,
    observedFrom,
    observedTo,
  };
}

/** D9: A por valor decrescente (empate: ordem do Set, id); depois B e C intercalados pela ordem do Set. */
export function compareLines(a: CollectionValueLine, b: CollectionValueLine): number {
  const aPriced = a.state === "priced";
  const bPriced = b.state === "priced";
  if (aPriced !== bPriced) return aPriced ? -1 : 1;
  if (aPriced && bPriced && a.lineCents !== b.lineCents) return (b.lineCents ?? 0) - (a.lineCents ?? 0);
  if (a.order !== b.order) return a.order - b.order;
  if (a.cardVariantId !== b.cardVariantId) return a.cardVariantId < b.cardVariantId ? -1 : 1;
  return a.languageCode < b.languageCode ? -1 : a.languageCode > b.languageCode ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Textos (apresentação; a interface da E3 consome sem recalcular).

const brl = new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" });
const count = new Intl.NumberFormat("pt-BR");

export function formatCents(value: number): string {
  return brl.format(value / 100);
}

/** Rótulo de cada estado de preço (texto inequívoco, nunca só cor). */
export const COLLECTION_VALUE_STATE_LABEL: Record<CollectionValuePriceState, string> = {
  priced: "Cotada",
  unpriced: "Sem cotação",
  unavailable: "Preço indisponível",
};

/** KPI "Valor estimado" (D8/D12): nunca R$ 0 sem cotação válida; parcial explícito com C. */
export function collectionValueTotalText(report: Pick<CollectionValueReport, "totalCents" | "provisional">): string {
  if (report.totalCents === null) return report.provisional ? "Indisponível" : "Sem cotação";
  return report.provisional ? `${formatCents(report.totalCents)} (parcial)` : formatCents(report.totalCents);
}

/** Cobertura (D8): "X de Y exemplares cotados". */
export function collectionValueCoverageText(report: Pick<CollectionValueReport, "pricedCopies" | "copies">): string {
  return `${count.format(report.pricedCopies)} de ${count.format(report.copies)} ${report.copies === 1 ? "exemplar cotado" : "exemplares cotados"}`;
}

/** KPI "Exemplares alocados" (D8): exemplares e grupos distintos variante + idioma. */
export function collectionValueAllocatedText(report: Pick<CollectionValueReport, "copies" | "groups">): { value: string; note: string } {
  return { value: count.format(report.copies), note: `${count.format(report.groups)} ${report.groups === 1 ? "item (variante e idioma)" : "itens (variante e idioma)"}` };
}

/** KPI "Sem cotação" (D8): só B — exemplares e grupos legitimamente sem referência válida. */
export function collectionValueUnpricedText(report: Pick<CollectionValueReport, "unpricedCopies" | "unpricedGroups">): { value: string; note: string } {
  return {
    value: count.format(report.unpricedCopies),
    note: `${report.unpricedCopies === 1 ? "exemplar" : "exemplares"} · ${count.format(report.unpricedGroups)} ${report.unpricedGroups === 1 ? "item" : "itens"}`,
  };
}

/** Sinais da referência (D4), na ordem: preço geral, desatualizada. */
export function collectionValuePriceFlags(line: Pick<CollectionValueLine, "generalCardPrice" | "stale">): string[] {
  const flags: string[] = [];
  if (line.generalCardPrice) flags.push("Preço geral da carta");
  if (line.stale) flags.push("Desatualizada");
  return flags;
}

export function collectionValueIncompleteText(reason: CollectionValueIncompleteReason): string | null {
  switch (reason) {
    case "too_large":
      return `A coleção tem mais de ${count.format(COLLECTION_VALUE_MAX_GROUPS)} itens (variante e idioma) — grande demais para este relatório. A impressão fica indisponível.`;
    case "duplicate":
      return "Um item apareceu repetido na leitura (a coleção pode ter mudado durante a leitura). Reabra o relatório; a impressão fica indisponível.";
    case "inconsistent_pages":
    case "total_mismatch":
    case "collection_mismatch":
      return "Os totais lidos não fecham (a coleção pode ter mudado durante a leitura). Reabra o relatório; a impressão fica indisponível.";
    default:
      return null;
  }
}

export const COLLECTION_VALUE_PROVISIONAL_TEXT =
  "Algumas referências de preço não puderam ser lidas agora. O valor é parcial e a impressão fica indisponível — tente novamente em instantes.";

/** Nota metodológica obrigatória (D12; D5 só no Master Set). */
export function collectionValueNotes(input: { masterSet: boolean; observedFrom: string | null; observedTo: string | null }): string[] {
  const notes = [
    "Valor estimado = quantidade alocada × referência NM unitária de cada variante. Só entram exemplares alocados a esta coleção; um exemplar nunca é contado em duas coleções.",
    "A referência é de mercado na condição NM (Near Mint). A condição física dos seus exemplares não é registrada — o valor não reflete desgaste.",
    "Não é garantia de revenda nem valor de liquidação, nem custo de aquisição. Não tem relação com o percentual de completude da coleção.",
    "Itens sem cotação ficam fora da soma (nunca valem zero). \"Preço geral da carta\" indica referência da carta, não da variante; \"Desatualizada\", observação com mais de 14 dias.",
  ];
  if (input.masterSet) notes.push("No Master Set, todos os exemplares alocados entram no valor, inclusive os que não atendem às posições atuais do objetivo.");
  const from = formatObservedDate(input.observedFrom);
  const to = formatObservedDate(input.observedTo);
  if (from && to) notes.push(from === to ? `Referências observadas em ${from}, convertidas para reais pela PTAX.` : `Referências observadas entre ${from} e ${to}, convertidas para reais pela PTAX.`);
  return notes;
}

// ---------------------------------------------------------------------------
// Texto das linhas (E3): formatação dos valores já calculados — nenhum cálculo financeiro novo.

/** "Nº/total" (ou só o número; "—" sem número). */
export function collectionValueCollectorText(line: Pick<CollectionValueLine, "collectorNumber" | "collectorTotal">): string {
  if (!line.collectorNumber) return "—";
  return line.collectorTotal ? `${line.collectorNumber}/${line.collectorTotal}` : line.collectorNumber;
}

/** Variante (rótulo do catálogo; "Padrão" para a variante padrão sem rótulo). */
export function collectionValueVariantText(line: Pick<CollectionValueLine, "variantLabel" | "isDefaultVariant">): string {
  return line.variantLabel ?? (line.isDefaultVariant ? "Padrão" : "Variante");
}

/** Idioma por extenso (código como último recurso). */
export function collectionValueLanguageText(line: Pick<CollectionValueLine, "languageName" | "languageCode">): string {
  return line.languageName ?? line.languageCode;
}

/** Referência unitária da linha: valor em `priced`; rótulo inequívoco em B e C. */
export function collectionValueUnitText(line: Pick<CollectionValueLine, "state" | "unitCents">): string {
  return line.state === "priced" && line.unitCents !== null ? formatCents(line.unitCents) : COLLECTION_VALUE_STATE_LABEL[line.state];
}

/** Valor da linha: valor em `priced`; "—" fora da soma (B) e "Indisponível" (C) — nunca zero. */
export function collectionValueLineText(line: Pick<CollectionValueLine, "state" | "lineCents">): string {
  if (line.state === "priced" && line.lineCents !== null) return formatCents(line.lineCents);
  return line.state === "unavailable" ? "Indisponível" : "—";
}

/** Data da observação da referência (só cotadas). */
export function collectionValueObservedText(line: Pick<CollectionValueLine, "state" | "observedAt">): string | null {
  if (line.state !== "priced") return null;
  const date = formatObservedDate(line.observedAt);
  return date ? `obs. ${date}` : "data não disponível";
}
