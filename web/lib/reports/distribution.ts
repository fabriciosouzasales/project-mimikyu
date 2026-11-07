/**
 * V1-14 R1-H — "Distribuição por Set, raridade e idioma" (8º relatório do Meu acervo). Regras
 * puras, sem banco, sem rede. Contrato: D7 §4h.
 *
 * Base = o MESMO inventário com preços do Valor estimado total (03): todo o acervo físico do
 * titular, independente de coleção, um grupo por variante + idioma (`buildSetInventoryReport`,
 * centavos). Três dimensões — Card Set, Raridade (da CARTA, nomes e ordem da 5355) e Idioma — com
 * as mesmas medidas, sempre separadas:
 *  - exemplares físicos (principal: barras, % e ordem);
 *  - itens = grupos variante + idioma (complementar; nunca somados aos exemplares);
 *  - valor estimado NM (complementar) = referência unitária × exemplares, só dos cotados.
 * Conferência: em cada dimensão Σ exemplares = 5160 `total_copies`, Σ itens = `distinct_items` e
 * Σ valor = Valor estimado total; senão incompleto (impressão bloqueada). Sem cotação nunca é zero;
 * preço que não pôde ser lido agora → "Indisponível"/"(parcial)", provisório. Participações
 * financeiras sempre sobre o valor estimado COTADO.
 *
 * Raridade: agrupada por `rarity_code`, nunca pelo nome; nomes e ordem (`display_order`, code)
 * exclusivamente da 5355. Códigos diferentes com o mesmo nome nunca se mesclam: quando presentes
 * juntos, a identificação ganha o código ("Comum · COMMON"); sem ambiguidade, só o nome. Carta sem
 * raridade → "Sem raridade definida" (por último). Código ausente da 5355 → inconsistência
 * (incompleto); catálogo indisponível → provisório; nos dois casos, impressão bloqueada.
 */
import { formatCount, plural, shareText } from "./acervo-reports.ts";
import type { SetInventoryLine, SetInventoryReport } from "./acervo-set-inventory.ts";

export type RarityCatalogEntry = { code: string; name: string; symbolCode: string; displayOrder: number };
export type RarityCatalogInput = { status: "ok"; entries: readonly RarityCatalogEntry[] } | { status: "unavailable" };

export type DistributionBandKind = "set" | "rarity" | "rarity-none" | "rarity-unknown" | "language";

export type DistributionBand = {
  /** Chave estável (código do Set, `rarity_code`, código do idioma). */
  key: string;
  kind: DistributionBandKind;
  label: string;
  /** Identificação secundária (código do Set; código da raridade só quando o nome é ambíguo). */
  detail: string | null;
  copies: number;
  items: number;
  pricedCopies: number;
  /** Exemplares cujo preço não pôde ser lido agora (≠ sem cotação). */
  unavailableCopies: number;
  /** Σ dos cotados; `null` sem nenhum cotado (nunca R$ 0). */
  valueBrl: number | null;
  /** Participação física (0–1). */
  copiesShare: number;
  /** Participação no valor estimado cotado (0–1); `null` sem valor. */
  valueShare: number | null;
  /** Menos de 50% dos exemplares da faixa cotados. */
  lowCoverage: boolean;
  /** Faixa de maior concentração física da dimensão (destaque discreto). */
  top: boolean;
};

export type DistributionDimension = { bands: DistributionBand[]; copies: number; items: number; valueBrl: number | null; balanced: boolean };

export type DistributionIncompleteReason =
  | "too_large"
  | "mismatch"
  | "rarity_unknown"
  | "rarity_unavailable"
  | "prices_unavailable"
  | null;

export type DistributionReport = {
  totalCopies: number;
  distinctItems: number;
  pricedCopies: number;
  unavailableCopies: number;
  /** Mesmo número do Valor estimado total; `null` sem nenhum cotado. */
  totalBrl: number | null;
  sets: DistributionDimension;
  /** Top 10 Sets + "Demais" (resumo visual da composição). */
  setSummary: { top: DistributionBand[]; othersCount: number; othersCopies: number };
  /** `null` = catálogo de raridades indisponível (seção substituída por aviso). */
  rarities: DistributionDimension | null;
  languages: DistributionDimension;
  rarityCount: number;
  complete: boolean;
  incompleteReason: DistributionIncompleteReason;
};

export const LOW_COVERAGE_THRESHOLD = 0.5;
export const SET_SUMMARY_TOP = 10;
export const NO_RARITY_KEY = "∅";

const ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });
const cents = (brl: number) => Math.round(brl * 100);
const byKey = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

type Acc = { key: string; kind: DistributionBandKind; label: string; detail: string | null; copies: number; items: number; pricedCopies: number; unavailableCopies: number; cents: number };

function add(map: Map<string, Acc>, key: string, seed: () => Omit<Acc, "copies" | "items" | "pricedCopies" | "unavailableCopies" | "cents">, line: SetInventoryLine, unavailable: boolean) {
  let acc = map.get(key);
  if (!acc) {
    acc = { ...seed(), copies: 0, items: 0, pricedCopies: 0, unavailableCopies: 0, cents: 0 };
    map.set(key, acc);
  }
  acc.copies += line.copies;
  acc.items += 1;
  if (line.totalBrl !== null) {
    acc.pricedCopies += line.copies;
    acc.cents += cents(line.totalBrl);
  } else if (unavailable) acc.unavailableCopies += line.copies;
}

function finish(accs: Acc[], totalCopies: number, totalCents: number, expected: { copies: number; items: number; cents: number }): DistributionDimension {
  let copies = 0;
  let items = 0;
  let sum = 0;
  let topIndex = -1;
  accs.forEach((a, i) => {
    copies += a.copies;
    items += a.items;
    sum += a.cents;
    if (topIndex < 0 || a.copies > (accs[topIndex] as Acc).copies) topIndex = i;
  });
  const bands = accs.map((a, i) => ({
    key: a.key,
    kind: a.kind,
    label: a.label,
    detail: a.detail,
    copies: a.copies,
    items: a.items,
    pricedCopies: a.pricedCopies,
    unavailableCopies: a.unavailableCopies,
    valueBrl: a.pricedCopies > 0 ? a.cents / 100 : null,
    copiesShare: totalCopies > 0 ? a.copies / totalCopies : 0,
    valueShare: a.pricedCopies > 0 && totalCents > 0 ? a.cents / totalCents : null,
    lowCoverage: a.copies > 0 && a.pricedCopies / a.copies < LOW_COVERAGE_THRESHOLD,
    top: i === topIndex && a.copies > 0,
  }));
  return { bands, copies, items, valueBrl: accs.some((a) => a.pricedCopies > 0) ? sum / 100 : null, balanced: copies === expected.copies && items === expected.items && sum === expected.cents };
}

export function buildDistributionReport(input: {
  inventory: SetInventoryReport;
  /** Variantes cujo preço não pôde ser lido agora (Pricing Resilience). */
  unavailable: ReadonlySet<string>;
  rarities: RarityCatalogInput;
}): DistributionReport {
  const { inventory } = input;
  const totalCents = inventory.totalBrl === null ? 0 : cents(inventory.totalBrl);
  const expected = { copies: inventory.totalCopies, items: inventory.distinctItems, cents: totalCents };
  const catalog = input.rarities.status === "ok" ? new Map(input.rarities.entries.map((e) => [e.code, e])) : null;

  const setAccs = new Map<string, Acc>();
  const setOrder = new Map<string, number>();
  const rarityAccs = new Map<string, Acc>();
  const languageAccs = new Map<string, Acc>();
  let unavailableCopies = 0;
  let unknownRarity = false;

  inventory.sets.forEach((set, index) => {
    setOrder.set(set.code, index);
    for (const line of set.lines) {
      const unavailable = line.totalBrl === null && input.unavailable.has(line.cardVariantId.toLowerCase());
      if (unavailable) unavailableCopies += line.copies;
      add(setAccs, set.code, () => ({ key: set.code, kind: "set", label: set.name, detail: set.code }), line, unavailable);
      const code = line.rarityCode ?? null;
      if (code === null) {
        add(rarityAccs, NO_RARITY_KEY, () => ({ key: NO_RARITY_KEY, kind: "rarity-none", label: "Sem raridade definida", detail: null }), line, unavailable);
      } else {
        const entry = catalog?.get(code);
        if (catalog && !entry) unknownRarity = true;
        add(
          rarityAccs,
          code,
          () => (entry ? { key: code, kind: "rarity", label: entry.name, detail: null } : { key: code, kind: "rarity-unknown", label: "Raridade não reconhecida no catálogo", detail: null }),
          line,
          unavailable,
        );
      }
      const lang = line.languageCode;
      add(languageAccs, lang, () => ({ key: lang, kind: "language", label: line.languageName ?? lang, detail: null }), line, unavailable);
    }
  });

  // Card Set: exemplares ↓, lançamento mais recente (ordem canônica do Inventário detalhado), código.
  const setList = [...setAccs.values()].sort((a, b) => b.copies - a.copies || (setOrder.get(a.key) ?? 0) - (setOrder.get(b.key) ?? 0) || byKey(a.key, b.key));
  const sets = finish(setList, inventory.totalCopies, totalCents, expected);

  // Raridade: ordem do catálogo (display_order, code); sem raridade e não reconhecida por último.
  let rarities: DistributionDimension | null = null;
  if (catalog) {
    const rank = (a: Acc) => (a.kind === "rarity" ? 0 : a.kind === "rarity-unknown" ? 1 : 2);
    const rarityList = [...rarityAccs.values()].sort((a, b) => {
      const ea = catalog.get(a.key);
      const eb = catalog.get(b.key);
      return rank(a) - rank(b) || (ea && eb ? ea.displayOrder - eb.displayOrder : 0) || byKey(a.key, b.key);
    });
    // Nome igual em códigos diferentes presentes juntos → o código entra na identificação de todos.
    const names = new Map<string, number>();
    for (const a of rarityList) if (a.kind === "rarity") names.set(a.label.toLocaleLowerCase("pt-BR"), (names.get(a.label.toLocaleLowerCase("pt-BR")) ?? 0) + 1);
    for (const a of rarityList) if (a.kind === "rarity" && (names.get(a.label.toLocaleLowerCase("pt-BR")) ?? 0) > 1) a.detail = a.key;
    rarities = finish(rarityList, inventory.totalCopies, totalCents, expected);
  }

  // Idioma: exemplares ↓, nome, código.
  const languageList = [...languageAccs.values()].sort((a, b) => b.copies - a.copies || ORDER.compare(a.label, b.label) || byKey(a.key, b.key));
  const languages = finish(languageList, inventory.totalCopies, totalCents, expected);

  const balanced = sets.balanced && languages.balanced && (rarities === null || rarities.balanced);
  const incompleteReason: DistributionIncompleteReason =
    inventory.incompleteReason ??
    (!balanced ? "mismatch" : unknownRarity ? "rarity_unknown" : !catalog ? "rarity_unavailable" : unavailableCopies > 0 ? "prices_unavailable" : null);

  const top = sets.bands.slice(0, SET_SUMMARY_TOP);
  const rest = sets.bands.slice(SET_SUMMARY_TOP);
  return {
    totalCopies: inventory.totalCopies,
    distinctItems: inventory.distinctItems,
    pricedCopies: inventory.pricedCopies,
    unavailableCopies,
    totalBrl: inventory.totalBrl,
    sets,
    setSummary: { top, othersCount: rest.length, othersCopies: rest.reduce((n, b) => n + b.copies, 0) },
    rarities,
    languages,
    rarityCount: [...rarityAccs.values()].filter((a) => a.kind !== "rarity-none").length,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

const ONE_DECIMAL = new Intl.NumberFormat("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 });

/** Participação com uma casa, truncada (mesma convenção do Valor estimado total): "—", "<0,1%", "100,0%". */
export function distributionShareText(share: number | null): string {
  if (share === null || share <= 0) return "—";
  if (share >= 1) return "100,0%";
  const tenths = Math.floor(share * 1000 + 1e-9);
  if (tenths === 0) return "<0,1%";
  return `${ONE_DECIMAL.format(tenths / 10)}%`;
}

/** Largura da barra (0–100), proporcional aos exemplares; mínima visível. */
export function distributionBarPercent(share: number): number {
  if (share <= 0) return 0;
  return Math.min(100, Math.max(0.8, share * 100));
}

/** Valor de uma faixa: "Sem cotação" / "Indisponível" / "R$ x (parcial)". */
export function distributionValueText(band: Pick<DistributionBand, "valueBrl" | "unavailableCopies">, formatMoney: (brl: number) => string): string {
  if (band.valueBrl === null) return band.unavailableCopies > 0 ? "Indisponível" : "Sem cotação";
  return band.unavailableCopies > 0 ? `${formatMoney(band.valueBrl)} (parcial)` : formatMoney(band.valueBrl);
}

/** Cobertura de uma faixa: exemplares cotados / exemplares (truncada). */
export function distributionCoverageText(band: Pick<DistributionBand, "pricedCopies" | "copies">): string {
  return shareText(band.pricedCopies, band.copies);
}

export function distributionSummaryLine(report: Pick<DistributionReport, "totalCopies" | "distinctItems" | "sets">): string {
  return [plural(report.totalCopies, "exemplar", "exemplares"), plural(report.distinctItems, "item", "itens"), plural(report.sets.bands.length, "Card Set", "Card Sets")].join(" · ");
}

/**
 * Resumo visual Top 10 + Demais só quando o acervo tem MAIS de 10 Card Sets (`FINAL VISUAL
 * REFINEMENT-01`); até 10, a tabela completa já mostra tudo e a frase seria sempre "100,0%".
 */
export function distributionShowsSetComposition(report: Pick<DistributionReport, "sets">): boolean {
  return report.sets.bands.length > SET_SUMMARY_TOP;
}

/** "Os 10 maiores Sets reúnem X% dos exemplares; demais N Sets, Y%." */
export function distributionSetSummaryText(report: Pick<DistributionReport, "setSummary" | "totalCopies">): string {
  const { top, othersCount, othersCopies } = report.setSummary;
  const topCopies = top.reduce((n, b) => n + b.copies, 0);
  const head = `${top.length === 1 ? "O Set" : `Os ${formatCount(top.length)} maiores Sets`} ${top.length === 1 ? "reúne" : "reúnem"} ${distributionShareText(report.totalCopies > 0 ? topCopies / report.totalCopies : 0)} dos exemplares`;
  if (othersCount === 0) return `${head}.`;
  return `${head}; ${othersCount === 1 ? "o outro Set" : `demais ${formatCount(othersCount)} Sets`}, ${distributionShareText(othersCopies / report.totalCopies)}.`;
}

export function distributionIncompleteText(reason: DistributionIncompleteReason): string | null {
  if (reason === "too_large") return "O acervo tem mais itens do que esta versão consegue ler; a distribuição pode não estar completa e a impressão fica indisponível.";
  if (reason === "mismatch")
    return "As faixas não fecharam com o total do acervo no momento da leitura (o acervo mudou durante a leitura?). Tente novamente; a impressão fica indisponível.";
  if (reason === "rarity_unknown")
    return "Há exemplares com uma raridade que não está no catálogo de raridades; a distribuição por raridade não está completa e a impressão fica indisponível.";
  if (reason === "rarity_unavailable")
    return "O catálogo de raridades não pôde ser carregado agora; a distribuição por raridade não está disponível e a impressão fica indisponível. Feche e abra o relatório de novo em instantes.";
  if (reason === "prices_unavailable")
    return "Alguns preços de referência não puderam ser carregados agora (marcados “Indisponível”); os valores são provisórios e a impressão fica indisponível. Tente novamente em instantes.";
  return null;
}
