/**
 * V1-14 R1-G — "Cartas repetidas" (7º relatório do Meu acervo). Regras puras, sem banco, sem rede.
 *
 * Base = o MESMO inventário com preços do Inventário detalhado (02), do Valor estimado total (03) e
 * do Top 10 (06): todo o acervo físico do titular, independente de coleção, um grupo por
 * **variante + idioma** (A). Repetido = grupo com 2+ exemplares; cópias adicionais = exemplares − 1.
 * Σ adicionais do acervo inteiro tem de coincidir com as repetidas canônicas da 5160
 * (`duplicate_copies`); divergência → incompleto (impressão bloqueada).
 *
 * Valor (D) = referência NM unitária × cópias ADICIONAIS (a unidade de referência nunca entra),
 * em centavos; participação sobre a mesma base do Valor estimado total (`inventory.totalBrl`).
 * Grupo sem cotação continua listado ("Sem cotação", valor "—", nunca zero); preço que não pôde
 * ser lido agora → "Indisponível", totais parciais e relatório provisório (F). Cópia adicional é
 * contagem — não indica disponibilidade para venda, troca nem reserva.
 *
 * Ordem: Card Sets na ordem do Inventário detalhado (lançamento mais recente primeiro, B); dentro
 * do Set, número de colecionador crescente (numérico), variante, idioma e id da variante (C).
 *
 * Localização física (5354, `get_my_inventory_group_locations`): a leitura traz TODOS os locais do
 * grupo; a distribuição tem de fechar com os exemplares (Σ locais = exemplares = exemplares da
 * 5159); falha de leitura, grupo ausente ou divergência → incompleto (impressão bloqueada).
 *
 * Exibição = só as CÓPIAS ADICIONAIS (`DUPLICATE-ONLY PHYSICAL LOCATIONS-01`), por convenção
 * gerencial do relatório — nada muda nos dados físicos, posições ou alocações:
 *  1. adicionais = exemplares − 1; uma unidade do grupo é a "unidade de referência";
 *  2. referência = um exemplar POSICIONADO no fichário digital: local com página (a 5354 só devolve
 *     página para exemplar num bolso do fichário vinculado ao próprio recipiente — o tipo do
 *     recipiente sozinho não conta); com mais de um, o primeiro por nome do recipiente e id;
 *  3. sem exemplar posicionado: o primeiro recipiente definido por nome e id; só sem local → "Sem
 *     local definido";
 *  4. os demais exemplares são as adicionais por local; locais com zero adicionais não aparecem;
 *     Σ adicionais por local = adicionais do grupo.
 * Páginas: a 5354 devolve as páginas DISTINTAS de cada local, não quantos exemplares estão
 * posicionados. No local da referência, as páginas das adicionais só são conhecidas quando cada
 * exemplar ocupa uma página própria (páginas = exemplares; a referência fica com a menor); senão a
 * página não é inventada ("página não identificada"). Nos outros locais, as páginas são as reais.
 */
import { PRICE_STALE_AFTER_DAYS, daysSince } from "../pricing/variant-pricing.ts";
import { formatCount, plural, shareText } from "./acervo-reports.ts";
import type { SetInventoryLine, SetInventoryPriceInput, SetInventoryReport } from "./acervo-set-inventory.ts";

export type DuplicateReference =
  | { kind: "priced"; unitBrl: number; generalCardPrice: boolean; stale: boolean; observedAt: string | null }
  | { kind: "none" }
  | { kind: "unavailable" };

/** Um local de armazenamento de um grupo (5354). `containerId` nulo = "Sem local definido". */
export type DuplicateLocation = {
  containerId: string | null;
  name: string | null;
  kindLabel: string | null;
  copies: number;
  /** Páginas do fichário digital vinculado ao recipiente (crescentes; vazio quando não há). */
  pages: number[];
};

/** Distribuição de um grupo devolvida pela 5354. */
export type DuplicateLocationGroup = { copies: number; locations: DuplicateLocation[] };

/** Cópias adicionais num local (exibição). `pagesUnknown` = há adicionais posicionáveis aqui, mas a página não é determinável. */
export type DuplicateAdditionalLocation = DuplicateLocation & { pagesUnknown: boolean };

/** Leitura das localizações: grupos por `duplicateGroupKey`, ou leitura indisponível. */
export type DuplicateLocationsInput = { status: "ok"; groups: ReadonlyMap<string, DuplicateLocationGroup> } | { status: "unavailable" };

/** Chave do grupo variante + idioma (mesma nas duas leituras). */
export const duplicateGroupKey = (cardVariantId: string, languageCode: string) => `${cardVariantId.toLowerCase()}|${languageCode}`;

export type DuplicateLine = {
  cardVariantId: string;
  languageCode: string;
  languageName: string | null;
  cardName: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  variantLabel: string | null;
  isDefaultVariant: boolean;
  copies: number;
  additional: number;
  reference: DuplicateReference;
  /** Referência unitária × adicionais; `null` sem cotação/indisponível. */
  additionalBrl: number | null;
  imageUrl: string | null;
  /** Onde estão TODOS os exemplares do grupo (conciliação); `null` = localização não lida/conciliada. */
  locations: DuplicateLocation[] | null;
  /** Onde estão as cópias ADICIONAIS (exibição; Σ copies = additional); `null` junto com `locations`. */
  additionalLocations: DuplicateAdditionalLocation[] | null;
};

export type DuplicateSet = {
  code: string;
  name: string;
  lines: DuplicateLine[];
  additional: number;
  /** Σ das adicionais cotadas; `null` sem nenhuma cotada. */
  subtotalBrl: number | null;
  /** Há linha com preço indisponível agora (subtotal não definitivo). */
  partial: boolean;
};

export type DuplicatesIncompleteReason =
  | "too_large"
  | "mismatch"
  | "locations_unavailable"
  | "locations_mismatch"
  | "prices_unavailable"
  | null;

export type DuplicatesReport = {
  sets: DuplicateSet[];
  /** Grupos (variante + idioma) com 2+ exemplares. */
  repeatedGroups: number;
  /** Grupos do acervo lidos. */
  totalGroups: number;
  /** Σ (exemplares − 1). */
  additionalCopies: number;
  /** Exemplares dos grupos repetidos. */
  copiesInRepeated: number;
  pricedAdditional: number;
  unavailableAdditional: number;
  /** Σ valor das adicionais cotadas; `null` sem nenhuma cotada (nunca R$ 0). */
  additionalBrl: number | null;
  /** Valor estimado dos exemplares cotados — mesma base do Valor estimado total. */
  estimatedTotalBrl: number | null;
  share: number | null;
  /** `duplicate_copies` da 5160 (conferência). */
  canonicalDuplicates: number;
  /** Grupos repetidos sem distribuição conciliada (ausente ou Σ locais ≠ exemplares). */
  locationMismatches: number;
  complete: boolean;
  incompleteReason: DuplicatesIncompleteReason;
};

const ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });
const byId = (a: string | null, b: string | null) => (a === b ? 0 : a === null ? 1 : b === null ? -1 : a < b ? -1 : 1);
/** Ordem estável de recipientes: nome, id; "Sem local definido" por último. */
const byContainer = (a: DuplicateLocation, b: DuplicateLocation) =>
  (a.containerId === null ? 1 : 0) - (b.containerId === null ? 1 : 0) || ORDER.compare(a.name ?? a.kindLabel ?? "", b.name ?? b.kindLabel ?? "") || byId(a.containerId, b.containerId);

/** Unidade de referência do grupo (convenção do relatório; ver cabeçalho). */
export function duplicateReferenceLocation(locations: readonly DuplicateLocation[]): DuplicateLocation | null {
  const positioned = locations.filter((l) => l.containerId !== null && l.pages.length > 0);
  const defined = locations.filter((l) => l.containerId !== null);
  const pool = positioned.length > 0 ? positioned : defined.length > 0 ? defined : [...locations];
  return [...pool].sort(byContainer)[0] ?? null;
}

/** Distribuição das cópias adicionais: todos os locais menos a unidade de referência; zeros fora. */
export function duplicateAdditionalLocations(locations: readonly DuplicateLocation[]): DuplicateAdditionalLocation[] {
  const reference = duplicateReferenceLocation(locations);
  const out: DuplicateAdditionalLocation[] = [];
  for (const location of locations) {
    if (location !== reference) {
      out.push({ ...location, pages: [...location.pages], pagesUnknown: false });
      continue;
    }
    const copies = location.copies - 1;
    if (copies <= 0) continue;
    // Referência posicionada: páginas das adicionais só são certas se cada exemplar ocupa uma página.
    const exact = location.pages.length === location.copies;
    out.push({ ...location, copies, pages: exact ? location.pages.slice(1) : [], pagesUnknown: location.pages.length > 0 && !exact });
  }
  return out.sort((a, b) => b.copies - a.copies || byContainer(a, b));
}
const cents = (brl: number) => Math.round(brl * 100);
const LAST = "￿";

function lineOrder(a: SetInventoryLine, b: SetInventoryLine): number {
  return (
    ORDER.compare(a.collectorNumber ?? LAST, b.collectorNumber ?? LAST) ||
    ORDER.compare(a.variantLabel ?? "", b.variantLabel ?? "") ||
    ORDER.compare(a.languageCode, b.languageCode) ||
    (a.cardVariantId < b.cardVariantId ? -1 : a.cardVariantId > b.cardVariantId ? 1 : 0)
  );
}

export function buildDuplicatesReport(input: {
  inventory: SetInventoryReport;
  prices: ReadonlyMap<string, SetInventoryPriceInput>;
  unavailable: ReadonlySet<string>;
  locations: DuplicateLocationsInput;
  now: number;
  imageUrl?: (path: string) => string | null;
}): DuplicatesReport {
  const { inventory } = input;
  const locationGroups = input.locations.status === "ok" ? input.locations.groups : null;
  let locationMismatches = 0;
  let totalGroups = 0;
  let allAdditional = 0;
  let repeatedGroups = 0;
  let additionalCopies = 0;
  let copiesInRepeated = 0;
  let pricedAdditional = 0;
  let unavailableAdditional = 0;
  let totalCents = 0;
  let anyPriced = false;
  const sets: DuplicateSet[] = [];

  for (const set of inventory.sets) {
    totalGroups += set.lines.length;
    let setAdditional = 0;
    let setCents = 0;
    let setPriced = false;
    let setPartial = false;
    const lines: DuplicateLine[] = [];
    for (const line of [...set.lines].sort(lineOrder)) {
      allAdditional += Math.max(0, line.copies - 1);
      if (line.copies < 2) continue;
      const additional = line.copies - 1;
      const key = line.cardVariantId.toLowerCase();
      let reference: DuplicateReference;
      let additionalBrl: number | null = null;
      if (line.unitBrl !== null && line.unitBrl > 0) {
        const unitCents = cents(line.unitBrl);
        const observedAt = input.prices.get(key)?.observedAt ?? null;
        const age = daysSince(observedAt, input.now);
        reference = {
          kind: "priced",
          unitBrl: unitCents / 100,
          generalCardPrice: line.priceBasis !== "VARIANT",
          stale: age !== null && age > PRICE_STALE_AFTER_DAYS,
          observedAt,
        };
        const lineCents = unitCents * additional;
        additionalBrl = lineCents / 100;
        setCents += lineCents;
        setPriced = true;
        pricedAdditional += additional;
      } else if (input.unavailable.has(key)) {
        reference = { kind: "unavailable" };
        setPartial = true;
        unavailableAdditional += additional;
      } else {
        reference = { kind: "none" };
      }
      repeatedGroups += 1;
      additionalCopies += additional;
      copiesInRepeated += line.copies;
      setAdditional += additional;
      const imagePath = line.imagePath ?? null;
      let locations: DuplicateLocation[] | null = null;
      if (locationGroups) {
        const group = locationGroups.get(duplicateGroupKey(key, line.languageCode));
        const sum = group ? group.locations.reduce((n, l) => n + l.copies, 0) : -1;
        if (group && group.copies === line.copies && sum === line.copies) locations = group.locations;
        else locationMismatches += 1;
      }
      const additionalLocations = locations ? duplicateAdditionalLocations(locations) : null;
      if (additionalLocations && additionalLocations.reduce((n, l) => n + l.copies, 0) !== additional) {
        // Invariante: Σ adicionais por local = adicionais do grupo (nunca exibir distribuição que não fecha).
        locationMismatches += 1;
        locations = null;
      }
      lines.push({
        cardVariantId: key,
        languageCode: line.languageCode,
        languageName: line.languageName ?? null,
        cardName: line.cardName,
        collectorNumber: line.collectorNumber,
        collectorTotal: line.collectorTotal,
        variantLabel: line.variantLabel,
        isDefaultVariant: line.isDefaultVariant,
        copies: line.copies,
        additional,
        reference,
        additionalBrl,
        imageUrl: imagePath && input.imageUrl ? input.imageUrl(imagePath) : null,
        locations,
        additionalLocations: locations ? additionalLocations : null,
      });
    }
    if (lines.length === 0) continue;
    totalCents += setCents;
    anyPriced = anyPriced || setPriced;
    sets.push({ code: set.code, name: set.name, lines, additional: setAdditional, subtotalBrl: setPriced ? setCents / 100 : null, partial: setPartial });
  }

  const estimatedCents = inventory.totalBrl === null ? null : cents(inventory.totalBrl);
  const canonicalDuplicates = inventory.duplicateCopies;
  const incompleteReason: DuplicatesIncompleteReason =
    inventory.incompleteReason ??
    (allAdditional !== canonicalDuplicates
      ? "mismatch"
      : repeatedGroups > 0 && !locationGroups
        ? "locations_unavailable"
        : locationMismatches > 0
          ? "locations_mismatch"
          : unavailableAdditional > 0
            ? "prices_unavailable"
            : null);
  return {
    sets,
    repeatedGroups,
    totalGroups,
    additionalCopies,
    copiesInRepeated,
    pricedAdditional,
    unavailableAdditional,
    additionalBrl: anyPriced ? totalCents / 100 : null,
    estimatedTotalBrl: inventory.totalBrl,
    share: anyPriced && estimatedCents && estimatedCents > 0 ? totalCents / estimatedCents : null,
    canonicalDuplicates,
    locationMismatches,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

// ---------------------------------------------------------------------------
// Texto
// ---------------------------------------------------------------------------

export function duplicateCollectorText(line: Pick<DuplicateLine, "collectorNumber" | "collectorTotal">): string {
  if (!line.collectorNumber) return "—";
  return line.collectorTotal ? `${line.collectorNumber}/${line.collectorTotal}` : line.collectorNumber;
}

/** Segunda linha da carta: variante · idioma. */
export function duplicateVariantText(line: Pick<DuplicateLine, "variantLabel" | "isDefaultVariant" | "languageName" | "languageCode">): string {
  return [line.variantLabel ?? (line.isDefaultVariant ? "Padrão" : "Variante"), line.languageName ?? line.languageCode].join(" · ");
}

/** "ETB006 — Celebração de 30 Anos: 7 adicionais" · "Fichário: 1 adicional (p. 5)" — um local das adicionais. */
export function duplicateAdditionalLocationText(location: DuplicateAdditionalLocation): string {
  const label = location.containerId === null ? "Sem local definido" : (location.name ?? location.kindLabel ?? "Local sem nome");
  const pages = location.pages.length > 0 ? ` (p. ${location.pages.join(", ")})` : location.pagesUnknown ? " (página não identificada)" : "";
  return `${label}: ${plural(location.copies, "adicional", "adicionais")}${pages}`;
}

/** Terceira linha da carta: onde estão as cópias adicionais; `null` → "Localização indisponível". */
export function duplicateAdditionalLocationsText(locations: readonly DuplicateAdditionalLocation[] | null): string {
  if (!locations || locations.length === 0) return "Localização indisponível";
  return locations.map(duplicateAdditionalLocationText).join("; ");
}

/** Sinais da referência: preço geral e desatualizada (sem "Referência internacional" neste relatório). */
export function duplicateFlags(line: Pick<DuplicateLine, "reference">): string[] {
  const flags: string[] = [];
  if (line.reference.kind === "priced") {
    if (line.reference.generalCardPrice) flags.push("Preço geral da carta");
    if (line.reference.stale) flags.push("Desatualizada");
  }
  return flags;
}

/** Valor de um agregado: "Sem cotação" sem cotadas; com indisponível, marcado "(parcial)". */
export function duplicatesValueText(value: number | null, partial: boolean, formatMoney: (brl: number) => string): string {
  if (value === null) return partial ? "Indisponível" : "Sem cotação";
  return partial ? `${formatMoney(value)} (parcial)` : formatMoney(value);
}

export function duplicatesSummaryLine(report: Pick<DuplicatesReport, "repeatedGroups" | "additionalCopies" | "sets">): string {
  return [
    plural(report.repeatedGroups, "item repetido", "itens repetidos"),
    plural(report.additionalCopies, "cópia adicional", "cópias adicionais"),
    plural(report.sets.length, "Card Set", "Card Sets"),
  ].join(" · ");
}

/** "Z% das adicionais" — cobertura das cópias adicionais (truncada). */
export function duplicatesCoverageNote(report: Pick<DuplicatesReport, "pricedAdditional" | "additionalCopies">): string {
  return `${shareText(report.pricedAdditional, report.additionalCopies)} das adicionais`;
}

export function duplicatesSetLine(set: Pick<DuplicateSet, "lines" | "additional">): string {
  return `${plural(set.lines.length, "item", "itens")} · ${plural(set.additional, "adicional", "adicionais")}`;
}

export function duplicatesCountNote(report: Pick<DuplicatesReport, "totalGroups">): string {
  return `de ${formatCount(report.totalGroups)} itens`;
}

export function duplicatesIncompleteText(reason: DuplicatesIncompleteReason): string | null {
  if (reason === "too_large") return "O acervo tem mais itens do que esta versão consegue ler; a lista pode não estar completa e a impressão fica indisponível.";
  if (reason === "mismatch")
    return "As cópias adicionais não fecharam com o total de repetidas do acervo no momento da leitura (o acervo mudou durante a leitura?). Tente novamente; a impressão fica indisponível.";
  if (reason === "locations_unavailable")
    return "A localização física dos exemplares não pôde ser carregada agora; a lista não está completa e a impressão fica indisponível. Feche e abra o relatório de novo em instantes.";
  if (reason === "locations_mismatch")
    return "A localização física de alguns itens não fechou com a quantidade de exemplares (o acervo mudou durante a leitura?). Feche e abra o relatório de novo; a impressão fica indisponível.";
  if (reason === "prices_unavailable")
    return "Alguns preços de referência não puderam ser carregados agora (marcados “Indisponível”); os valores são provisórios e a impressão fica indisponível. Tente novamente em instantes.";
  return null;
}
