/**
 * V1-14 R2-G — "Distribuição por raridade" (D7 v1.67 §4o, D1–D6). Núcleo PURO: junta as posições
 * canônicas da coleção (mesma leitura do Checklist — 5169 ou 5189/5198, `is_satisfied` do banco) à
 * raridade da CARTA (`search_cards`) e ao catálogo oficial (5355), e confere tudo com o resumo
 * canônico (5332). Nenhuma regra de completude aqui.
 *
 *  - Raridade é da carta: cada posição pertence a exatamente uma raridade; no Master Set os
 *    acabamentos somam na raridade da carta (nunca viram categoria).
 *  - Agrupamento por `rarity_code` (nunca pelo nome), ordem do catálogo (`display_order`, `code`);
 *    só raridades presentes no objetivo. Mesmo nome com códigos diferentes: a identificação ganha o
 *    código (regra da R1-H), nunca se mesclam.
 *  - Unidade: posições (nunca exemplares).
 *  - Conferência: Σ esperadas = total canônico, Σ satisfeitas = satisfeitas canônicas, cada posição
 *    classificada uma vez, leituras completas. Qualquer divergência → incompleto com motivo
 *    (impressão bloqueada); nada é estimado nem redistribuído.
 */
import { progressBarPercent, progressPercentText } from "../colecoes/colecoes.ts";
import type { ChecklistKind, ChecklistRow } from "./collection-checklist.ts";
import type { RarityCatalogEntry, RarityCatalogInput } from "./distribution.ts";

export const RARITY_DISTRIBUTION_TITLE = "Distribuição por raridade";
export const RARITY_UNRESOLVED_KEY = "__sem_raridade__";

const N = new Intl.NumberFormat("pt-BR");

// ---------------------------------------------------------------------------------------------
// Raridade por carta (`search_cards`, paginada) — validação de cada página
// ---------------------------------------------------------------------------------------------

export type CardRarityRead =
  | { status: "ok"; rarities: Map<string, string>; total: number }
  | { status: "incomplete"; rarities: Map<string, string>; total: number; reason: "pages" | "too_large" }
  | { status: "error" };

/** Teto de páginas da leitura de raridade (60 cartas por página → 1.200 cartas; o maior Set atual tem 300). */
export const RARITY_PAGE_SIZE = 60;
export const RARITY_MAX_PAGES = 20;

export type RarityPage = { rows: Array<{ cardId: string; rarityCode: string; cardSetCode: string }>; total: number };

/** Uma página da `search_cards` → linhas validadas; `null` = fora da forma esperada. */
export function parseRarityPage(data: unknown): RarityPage | null {
  if (!Array.isArray(data)) return null;
  const rows: RarityPage["rows"] = [];
  let total: number | null = data.length === 0 ? 0 : null;
  for (const raw of data) {
    if (!raw || typeof raw !== "object") return null;
    const r = raw as Record<string, unknown>;
    const t = typeof r.total_count === "string" ? Number(r.total_count) : r.total_count;
    if (typeof r.card_id !== "string" || typeof r.rarity_code !== "string" || r.rarity_code === "" || typeof r.card_set_code !== "string") return null;
    if (typeof t !== "number" || !Number.isInteger(t) || t < 0) return null;
    if (total !== null && t !== total) return null;
    total = t;
    rows.push({ cardId: r.card_id.toLowerCase(), rarityCode: r.rarity_code, cardSetCode: r.card_set_code });
  }
  return { rows, total: total ?? 0 };
}

/**
 * Junta as páginas (já validadas) numa tabela carta → raridade, conferindo: todas do Set da coleção,
 * nenhuma carta repetida, total estável entre páginas, conjunto lido = total informado.
 */
export function mergeRarityPages(setCode: string, pages: ReadonlyArray<RarityPage | null>, expectedPages: number): CardRarityRead {
  const first = pages[0];
  if (!first) return { status: "error" };
  const rarities = new Map<string, string>();
  let consistent = pages.length === expectedPages;
  const wanted = setCode.toLocaleLowerCase("en");
  for (const page of pages) {
    if (!page || page.total !== first.total) {
      consistent = false;
      continue;
    }
    for (const row of page.rows) {
      if (row.cardSetCode.toLocaleLowerCase("en") !== wanted || rarities.has(row.cardId)) {
        consistent = false;
        continue;
      }
      rarities.set(row.cardId, row.rarityCode);
    }
  }
  if (rarities.size !== first.total) consistent = false;
  return consistent ? { status: "ok", rarities, total: first.total } : { status: "incomplete", rarities, total: first.total, reason: "pages" };
}

// ---------------------------------------------------------------------------------------------
// Relatório
// ---------------------------------------------------------------------------------------------

export type RarityBand = {
  /** `rarity_code`, ou `RARITY_UNRESOLVED_KEY` para posições sem raridade identificada. */
  key: string;
  kind: "rarity" | "unresolved";
  label: string;
  /** Código, só quando o nome é ambíguo entre as raridades presentes. */
  detail: string | null;
  symbolCode: string | null;
  expected: number;
  satisfied: number;
  missing: number;
};

export type RarityDistributionIncomplete =
  | "positions"
  | "rarity_read"
  | "catalog_unavailable"
  | "rarity_unknown"
  | "rarity_unresolved"
  | "duplicate_position"
  | "total_mismatch";

export type RarityDistributionReport = {
  kind: ChecklistKind;
  bands: RarityBand[];
  /** Totais canônicos (5332) — os indicadores. */
  expected: number;
  satisfied: number;
  missing: number;
  /** Somas das categorias (iguais aos canônicos quando completo). */
  sumExpected: number;
  sumSatisfied: number;
  complete: boolean;
  incompleteReason: RarityDistributionIncomplete | null;
  /** Nº de raridades distintas do objetivo (sem o grupo "sem raridade"). */
  rarityCount: number;
};

export type RarityDistributionInput = {
  kind: ChecklistKind;
  positions: readonly ChecklistRow[];
  /** Leitura de posições completa (Checklist: `rows.length === total`). */
  positionsComplete: boolean;
  rarities: CardRarityRead;
  catalog: RarityCatalogInput;
  canonical: { total: number; satisfied: number };
};

export function buildRarityDistribution(input: RarityDistributionInput): RarityDistributionReport {
  const { positions, rarities, catalog, canonical, kind } = input;
  const byCode = new Map<string, RarityCatalogEntry>(catalog.status === "ok" ? catalog.entries.map((e) => [e.code, e]) : []);
  const map = rarities.status === "error" ? new Map<string, string>() : rarities.rarities;

  type Acc = RarityBand & { order: number };
  const accs = new Map<string, Acc>();
  const seen = new Set<string>();
  let duplicate = false;
  let unresolved = false;
  let unknown = false;
  for (const row of positions) {
    if (seen.has(row.key)) {
      duplicate = true;
      continue;
    }
    seen.add(row.key);
    const code = row.cardId ? map.get(row.cardId) : undefined;
    const entry = code ? byCode.get(code) : undefined;
    if (!code) unresolved = true;
    else if (!entry && catalog.status === "ok") unknown = true;
    const key = code ?? RARITY_UNRESOLVED_KEY;
    let acc = accs.get(key);
    if (!acc) {
      acc =
        key === RARITY_UNRESOLVED_KEY
          ? { key, kind: "unresolved", label: "Sem raridade identificada", detail: null, symbolCode: null, expected: 0, satisfied: 0, missing: 0, order: Number.MAX_SAFE_INTEGER }
          : entry
            ? { key, kind: "rarity", label: entry.name, detail: null, symbolCode: entry.symbolCode, expected: 0, satisfied: 0, missing: 0, order: entry.displayOrder }
            : // Código fora do catálogo (ou catálogo indisponível): visível, nunca mesclado; relatório incompleto.
              { key, kind: "rarity", label: "Raridade não reconhecida", detail: key, symbolCode: null, expected: 0, satisfied: 0, missing: 0, order: Number.MAX_SAFE_INTEGER - 1 };
      accs.set(key, acc);
    }
    acc.expected += 1;
    if (row.owned) acc.satisfied += 1;
  }

  const list = [...accs.values()].sort((a, b) => a.order - b.order || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
  // Mesmo nome com códigos diferentes: a identificação ganha o código (R1-H).
  const names = new Map<string, number>();
  for (const a of list) if (a.kind === "rarity") names.set(a.label.toLocaleLowerCase("pt-BR"), (names.get(a.label.toLocaleLowerCase("pt-BR")) ?? 0) + 1);
  for (const a of list) if (a.kind === "rarity" && (names.get(a.label.toLocaleLowerCase("pt-BR")) ?? 0) > 1) a.detail = a.key;
  const bands: RarityBand[] = list.map(({ order: _order, ...band }) => ({ ...band, missing: band.expected - band.satisfied }));

  const sumExpected = bands.reduce((s, b) => s + b.expected, 0);
  const sumSatisfied = bands.reduce((s, b) => s + b.satisfied, 0);
  const incompleteReason: RarityDistributionIncomplete | null = !input.positionsComplete
    ? "positions"
    : rarities.status !== "ok"
      ? "rarity_read"
      : catalog.status !== "ok"
        ? "catalog_unavailable"
        : duplicate
          ? "duplicate_position"
          : unknown
            ? "rarity_unknown"
            : unresolved
              ? "rarity_unresolved"
              : sumExpected !== canonical.total || sumSatisfied !== canonical.satisfied
                ? "total_mismatch"
                : null;

  return {
    kind,
    bands,
    expected: canonical.total,
    satisfied: canonical.satisfied,
    missing: Math.max(0, canonical.total - canonical.satisfied),
    sumExpected,
    sumSatisfied,
    complete: incompleteReason === null,
    incompleteReason,
    rarityCount: bands.filter((b) => b.kind === "rarity").length,
  };
}

// ---------------------------------------------------------------------------------------------
// Textos (pt-BR) — mesmos na tela e na impressão
// ---------------------------------------------------------------------------------------------

export function positionsWord(n: number): string {
  return n === 1 ? "posição" : "posições";
}

/** "12 de 40". */
export function bandOfText(band: Pick<RarityBand, "satisfied" | "expected">): string {
  return `${N.format(band.satisfied)} de ${N.format(band.expected)}`;
}

export function bandPercentText(band: Pick<RarityBand, "satisfied" | "expected">): string {
  return progressPercentText(band.satisfied, band.expected);
}

/** Largura da barra (0–100), com o mínimo visível da regra do produto. */
export function bandBarPercent(band: Pick<RarityBand, "satisfied" | "expected">): number {
  return progressBarPercent(band.satisfied, band.expected);
}

export function bandMissingText(band: Pick<RarityBand, "missing" | "expected">): string {
  if (band.expected > 0 && band.missing === 0) return "Completa";
  return `faltam ${N.format(band.missing)}`;
}

export function bandComplete(band: Pick<RarityBand, "missing" | "expected">): boolean {
  return band.expected > 0 && band.missing === 0;
}

export function bandLabel(band: Pick<RarityBand, "label" | "detail">): string {
  return band.detail ? `${band.label} · ${band.detail}` : band.label;
}

/** Leitura acessível da barra: "Rara Dupla: 12 de 40 posições satisfeitas, 30%, faltam 28". */
export function bandAriaText(band: RarityBand): string {
  return `${bandLabel(band)}: ${bandOfText(band)} ${positionsWord(band.expected)} satisfeitas, ${bandPercentText(band)}, ${bandMissingText(band).toLowerCase()}`;
}

export function overallPercentText(report: Pick<RarityDistributionReport, "satisfied" | "expected">): string {
  return progressPercentText(report.satisfied, report.expected);
}


export function rarityDistributionIncompleteText(reason: RarityDistributionIncomplete | null): string | null {
  switch (reason) {
    case null:
      return null;
    case "positions":
      return "Relatório incompleto: nem todas as posições da coleção puderam ser lidas agora. Tente novamente; nada foi alterado.";
    case "rarity_read":
      return "Relatório incompleto: a raridade de parte das cartas do Set não pôde ser lida agora. Tente novamente; nada foi alterado.";
    case "catalog_unavailable":
      return "Relatório incompleto: o catálogo de raridades não pôde ser lido agora. Tente novamente; nada foi alterado.";
    case "rarity_unknown":
      return "Relatório incompleto: há carta com raridade que não consta do catálogo vigente. A distribuição não é definitiva.";
    case "rarity_unresolved":
      return "Relatório incompleto: há posições cuja raridade não foi identificada. Elas aparecem em “Sem raridade identificada”.";
    case "duplicate_position":
      return "Relatório incompleto: a leitura das posições devolveu uma posição repetida. A distribuição não é definitiva.";
    case "total_mismatch":
      return "Relatório incompleto: a soma das raridades não confere com o resumo da coleção. A distribuição não é definitiva.";
  }
}

export const RARITY_DISTRIBUTION_NOTES: readonly string[] = [
  "Raridade oficial da carta no catálogo MMKYU. No Master Set, cada acabamento é uma posição e conta na raridade da carta; acabamento não é raridade.",
  "Completude pela regra oficial da coleção: posição satisfeita = ao menos um exemplar alocado que a atende. Posições não são exemplares físicos.",
  "Percentuais arredondados para baixo, como no restante do produto; 100% só quando a categoria está completa.",
];
