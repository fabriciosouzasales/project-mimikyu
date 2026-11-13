import { formatCount } from "./acervo.ts";
import { CARD_CONDITION_CODES, type CardConditionCode, cardConditionLabel, isCardConditionCode } from "./card-condition.ts";

/**
 * V1-16 UX-B — distribuição das condições declaradas de um conjunto de
 * exemplares (Encontrar carta: total da identidade e cada local).
 *
 * - Ordem e rótulos vêm só do mapa canônico (`card-condition.ts`): M, NM, SP
 *   (LP), MP, HP, DM (DMG).
 * - Código ausente ou fora da escala NÃO vira condição: conta em
 *   `unrecognized` e aparece como "não reconhecida" — nada é inventado nem
 *   promovido a NM.
 * - Invariante: Σ `counts` + `unrecognized` = `total` (um exemplar, uma
 *   contagem).
 */
export type ConditionTally = {
  counts: Record<CardConditionCode, number>;
  unrecognized: number;
  total: number;
};

export function emptyConditionTally(): ConditionTally {
  return { counts: { M: 0, NM: 0, LP: 0, MP: 0, HP: 0, DMG: 0 }, unrecognized: 0, total: 0 };
}

/** Soma um exemplar (muta o acumulador; uso interno das agregações). */
export function addToConditionTally(tally: ConditionTally, code: unknown): void {
  tally.total += 1;
  if (isCardConditionCode(code)) tally.counts[code] += 1;
  else tally.unrecognized += 1;
}

export function tallyConditions(codes: Iterable<unknown>): ConditionTally {
  const tally = emptyConditionTally();
  for (const code of codes) addToConditionTally(tally, code);
  return tally;
}

export type ConditionPart = { code: CardConditionCode; short: string; name: string; count: number };

/** Só as condições presentes, na ordem canônica. */
export function conditionParts(tally: ConditionTally): ConditionPart[] {
  return CARD_CONDITION_CODES.filter((code) => tally.counts[code] > 0).map((code) => {
    const label = cardConditionLabel(code)!;
    return { code, short: label.short, name: label.name, count: tally.counts[code] };
  });
}

/** "NM ×2 · SP ×1" (+ "· Condição não reconhecida ×1"). Vazio quando não há exemplares. */
export function conditionDistributionText(tally: ConditionTally): string {
  const parts = conditionParts(tally).map((p) => `${p.short} ×${formatCount(p.count)}`);
  if (tally.unrecognized > 0) parts.push(`Condição não reconhecida ×${formatCount(tally.unrecognized)}`);
  return parts.join(" · ");
}

/** Leitura por extenso: "Condições declaradas: 2 Near Mint, 1 Slightly Played". */
export function conditionDistributionAccessible(tally: ConditionTally): string {
  const parts = conditionParts(tally).map((p) => `${formatCount(p.count)} ${p.name}`);
  if (tally.unrecognized > 0) {
    parts.push(`${formatCount(tally.unrecognized)} sem condição reconhecida`);
  }
  if (parts.length === 0) return "";
  return `Condições declaradas: ${parts.join(", ")}`;
}

// ---------------------------------------------------------------------------
// V1-16 UX-C — resumo de condições na grade do Meu acervo (G1, D2; D1 substituída pela UX-C CORRECTION-01)
// ---------------------------------------------------------------------------

/** Teto da leitura de exemplares não-NM por página (abaixo do `max_rows` padrão do PostgREST). */
export const PAGE_CONDITION_READ_MAX = 1000;

/** Chips visíveis por carta; o resto vira "+n". */
export const GRID_CONDITION_CHIPS_MAX = 3;

/** Identidade exata do grupo da galeria: variante + idioma. */
export function conditionGroupKey(cardVariantId: string, languageCode: string): string {
  return `${cardVariantId.toLowerCase()}:${languageCode}`;
}

export type PageConditionGroup = { cardVariantId: string; languageCode: string; copiesOwned: number };

export type PageConditionIssue =
  | "count_missing"
  | "count_mismatch"
  | "over_limit"
  | "bad_row"
  | "foreign_variant"
  | "unmapped_language"
  | "unexpected_code"
  | "nm_in_read"
  | "exceeds_total";

/**
 * Agrega a leitura dos exemplares NÃO-NM das variantes da página (`physical_card`,
 * RLS select-own) nos grupos exibidos.
 *
 * - D2: o total do grupo é `copiesOwned` (5220, todos os exemplares da
 *   identidade, sem filtro) — a leitura não-NM também não tem filtro algum.
 * - NM = `copiesOwned` − Σ não-NM, só quando a leitura está COMPLETA
 *   (`count` exato = linhas recebidas, dentro do teto) e coerente
 *   (Σ não-NM ≤ total). Qualquer dúvida → o grupo (ou a página toda) fica sem
 *   resumo, nunca com um número possivelmente errado.
 * - UX-C CORRECTION-01 (substitui a D1): todo grupo com exemplar físico
 *   entra, inclusive o todo NM (`NM ×N`) — mas só com a leitura completa;
 *   leitura falha/incompleta → nenhum grupo, nunca NM presumido.
 * - Idioma: `physical_card` traz `language_id`; o código vem dos idiomas do
 *   cadastro (5164, já lidos pela página). Id sem código conhecido → a
 *   variante inteira fica sem resumo (não dá para saber de qual grupo é).
 * `issues` = códigos para o log (sem dados do usuário).
 */
export function pageConditionMix(input: {
  groups: readonly PageConditionGroup[];
  languages: readonly { id: string; code: string }[];
  rows: readonly unknown[];
  count: number | null | undefined;
}): { mix: Map<string, ConditionTally>; issues: PageConditionIssue[] } {
  const issues = new Set<PageConditionIssue>();
  const mix = new Map<string, ConditionTally>();
  const { groups, rows, count } = input;
  if (count === null || count === undefined || !Number.isInteger(count)) issues.add("count_missing");
  else if (count > PAGE_CONDITION_READ_MAX) issues.add("over_limit");
  else if (count !== rows.length) issues.add("count_mismatch");
  if (rows.length > PAGE_CONDITION_READ_MAX) issues.add("over_limit");
  if (issues.size > 0) return { mix, issues: [...issues] };

  const variants = new Set(groups.map((g) => g.cardVariantId.toLowerCase()));
  const codeOf = new Map(input.languages.map((l) => [l.id.toLowerCase(), l.code]));
  const nonNm = new Map<string, Record<CardConditionCode, number>>();
  const taintedVariants = new Set<string>();
  const taintedGroups = new Set<string>();

  for (const raw of rows) {
    const row = raw as Record<string, unknown> | null;
    const variant = typeof row?.card_variant_id === "string" ? row.card_variant_id.toLowerCase() : null;
    const languageId = typeof row?.language_id === "string" ? row.language_id.toLowerCase() : null;
    if (!variant || !languageId) {
      issues.add("bad_row");
      return { mix: new Map(), issues: [...issues] };
    }
    if (!variants.has(variant)) {
      // A leitura foi pedida só para as variantes da página: outra variante = resposta incoerente.
      issues.add("foreign_variant");
      return { mix: new Map(), issues: [...issues] };
    }
    const languageCode = codeOf.get(languageId);
    if (languageCode === undefined) {
      issues.add("unmapped_language");
      taintedVariants.add(variant);
      continue;
    }
    const key = conditionGroupKey(variant, languageCode);
    const code = row?.condition_code;
    if (code === "NM") {
      issues.add("nm_in_read");
      taintedGroups.add(key);
      continue;
    }
    if (!isCardConditionCode(code)) {
      issues.add("unexpected_code");
      taintedGroups.add(key);
      continue;
    }
    const counts = nonNm.get(key) ?? { M: 0, NM: 0, LP: 0, MP: 0, HP: 0, DMG: 0 };
    counts[code] += 1;
    nonNm.set(key, counts);
  }

  for (const group of groups) {
    const variant = group.cardVariantId.toLowerCase();
    const key = conditionGroupKey(variant, group.languageCode);
    if (taintedVariants.has(variant) || taintedGroups.has(key)) continue;
    const total = group.copiesOwned;
    // Grupo sem exemplar físico (não deveria vir da 5220) → sem chips.
    if (!Number.isInteger(total) || total <= 0) continue;
    // UX-C CORRECTION-01 (substitui a D1): leitura completa e coerente sem nenhum
    // não-NM deste grupo → todos NM. Só chega aqui com a leitura provada inteira;
    // em falha a função já saiu sem nenhum grupo (nunca NM presumido).
    const counts = nonNm.get(key) ?? { M: 0, NM: 0, LP: 0, MP: 0, HP: 0, DMG: 0 };
    const others = Object.values(counts).reduce((s, n) => s + n, 0);
    if (total < others) {
      issues.add("exceeds_total");
      continue;
    }
    mix.set(key, { counts: { ...counts, NM: total - others }, unrecognized: 0, total });
  }
  return { mix, issues: [...issues] };
}

/** Chips da grade: até `GRID_CONDITION_CHIPS_MAX` condições na ordem canônica + quantas ficaram de fora. */
export function gridConditionChips(tally: ConditionTally): { chips: ConditionPart[]; more: number } {
  const parts = conditionParts(tally);
  return { chips: parts.slice(0, GRID_CONDITION_CHIPS_MAX), more: Math.max(0, parts.length - GRID_CONDITION_CHIPS_MAX) };
}

/** Chips visíveis por carta nos cartões estreitos (GRID VISUAL REFINEMENT). */
export const GRID_CONDITION_CHIPS_NARROW = 2;

export type GridConditionDisplay =
  /** Todos os exemplares numa condição só: só a sigla (a quantidade já está no ×N do nome). */
  | { kind: "uniform"; part: ConditionPart }
  /**
   * Condições mistas, na ordem canônica: até `GRID_CONDITION_CHIPS_MAX` chips
   * (o último só aparece em cartão largo). `moreNarrow`/`moreWide` = quantas
   * CONDIÇÕES ficam ocultas em cada largura (nunca exemplares).
   */
  | { kind: "mixed"; chips: ConditionPart[]; moreNarrow: number; moreWide: number };

/**
 * GRID VISUAL REFINEMENT — transformação SÓ de apresentação sobre um tally já
 * validado por `pageConditionMix` (não recalcula nem relaxa nada). Tally vazio
 * ou com código não reconhecido → `null` (a grade não mostra condição).
 */
export function gridConditionDisplay(tally: ConditionTally | null | undefined): GridConditionDisplay | null {
  if (!tally || tally.total <= 0 || tally.unrecognized > 0) return null;
  const parts = conditionParts(tally);
  if (parts.length === 0) return null;
  if (parts.length === 1) return { kind: "uniform", part: parts[0]! };
  return {
    kind: "mixed",
    chips: parts.slice(0, GRID_CONDITION_CHIPS_MAX),
    moreNarrow: Math.max(0, parts.length - GRID_CONDITION_CHIPS_NARROW),
    moreWide: Math.max(0, parts.length - GRID_CONDITION_CHIPS_MAX),
  };
}

/**
 * Onde estão os exemplares de uma identidade, com a condição de cada grupo —
 * uma única passada sobre os exemplares já lidos (5363 + local físico), sem
 * leitura nova. `null` = algum exemplar sem local resolvido (leitura
 * incoerente: a interface mostra erro em vez de números parciais).
 */
export type CopyPlacement = {
  total: number;
  byStorage: Record<string, number>;
  unlocated: number;
  conditions: ConditionTally;
  conditionsByStorage: Record<string, ConditionTally>;
  unlocatedConditions: ConditionTally;
};

export function summarizeCopyPlacement(
  copies: readonly { physicalCardId: string; conditionCode: unknown }[],
  storageOf: ReadonlyMap<string, string | null>,
): CopyPlacement | null {
  const byStorage: Record<string, number> = {};
  const conditionsByStorage: Record<string, ConditionTally> = {};
  const conditions = emptyConditionTally();
  const unlocatedConditions = emptyConditionTally();
  let unlocated = 0;
  for (const copy of copies) {
    if (!storageOf.has(copy.physicalCardId)) return null;
    const where = storageOf.get(copy.physicalCardId) ?? null;
    addToConditionTally(conditions, copy.conditionCode);
    if (where === null) {
      unlocated += 1;
      addToConditionTally(unlocatedConditions, copy.conditionCode);
    } else {
      byStorage[where] = (byStorage[where] ?? 0) + 1;
      addToConditionTally((conditionsByStorage[where] ??= emptyConditionTally()), copy.conditionCode);
    }
  }
  return { total: copies.length, byStorage, unlocated, conditions, conditionsByStorage, unlocatedConditions };
}
