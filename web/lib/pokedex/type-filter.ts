/**
 * Filtro por tipo da Pokédex Nacional (Pokédex P5a, 2026-10-14).
 *
 * Regras puras, sem React e sem rede, sobre dados que a página já lê: a lista de
 * espécies (6131, já filtrada por pesquisa e geração) e o índice de tipos (6135).
 * Nenhuma consulta nova.
 *
 * - Até dois tipos (`?tipo=FIRE,FLYING`), sempre combinados com "E": um tipo = espécies
 *   que o têm como primário ou secundário (mesma regra da composição do capítulo, P4b);
 *   dois tipos = espécies que têm os dois, em qualquer ordem. Não há "OU".
 * - URL canônica: códigos estáveis em maiúsculas, sem repetição, na ordem em que o
 *   usuário os escolheu (`fire,flying` vira `FIRE,FLYING`; `FLYING,FIRE` é igualmente
 *   válida e dá o mesmo resultado). Código desconhecido é descartado (nunca um erro para
 *   o usuário), e o excesso além de dois também.
 * - Espécie sem tipos no índice nunca entra num resultado filtrado por tipo: sem o dado,
 *   o filtro não afirma nada sobre ela.
 */

import type { PokedexSpeciesTypes } from "./queries.ts";

export const MAX_TYPE_FILTERS = 2;

/** Ordem oficial dos 18 tipos (`pokemon_type.display_order`): a ordem do seletor e o conjunto de códigos válidos. */
export const POKEMON_TYPE_ORDER = [
  "NORMAL",
  "FIGHTING",
  "FLYING",
  "POISON",
  "GROUND",
  "ROCK",
  "BUG",
  "GHOST",
  "STEEL",
  "FIRE",
  "WATER",
  "GRASS",
  "ELECTRIC",
  "PSYCHIC",
  "ICE",
  "DRAGON",
  "DARK",
  "FAIRY",
] as const;

const KNOWN_TYPES = new Set<string>(POKEMON_TYPE_ORDER);

export type TypeParam = {
  /** Tipos válidos, sem repetição, na ordem escolhida; no máximo dois. */
  types: string[];
  /** `false` quando a URL trouxe `?tipo=` diferente da forma canônica (deve redirecionar). */
  isCanonical: boolean;
};

/** Só códigos válidos, sem repetição, no máximo dois, na ordem dada — a forma que vai para a URL. */
export function canonicalTypes(codes: readonly string[]): string[] {
  const unique: string[] = [];
  for (const code of codes) {
    if (KNOWN_TYPES.has(code) && !unique.includes(code)) unique.push(code);
    if (unique.length === MAX_TYPE_FILTERS) break;
  }
  return unique;
}

/**
 * Normaliza `?tipo=` da URL. Aceita vírgula ou espaço como separador, maiúsculas ou
 * minúsculas e o parâmetro repetido (`?tipo=FIRE&tipo=FLYING`). Os dois primeiros
 * códigos válidos valem; o resto é descartado.
 */
export function parseTypeParam(value: string | string[] | undefined): TypeParam {
  if (value === undefined) return { types: [], isCanonical: true };
  const raw = Array.isArray(value) ? value.join(",") : value;
  const codes = raw
    .slice(0, 200)
    .split(/[\s,]+/)
    .map((part) => part.trim().toUpperCase())
    .filter(Boolean);
  const types = canonicalTypes(codes);
  return { types, isCanonical: !Array.isArray(value) && raw === types.join(",") && types.length > 0 };
}

/** Valor do parâmetro `tipo` (ou `null` sem filtro). */
export function typeParamValue(types: readonly string[] | undefined): string | null {
  return types && types.length > 0 ? types.join(",") : null;
}

/** A espécie tem todos os tipos selecionados (primário ou secundário)? Seleção vazia = sim. */
export function speciesMatchesTypes(speciesTypes: readonly (string | null | undefined)[], selected: readonly string[] | undefined): boolean {
  if (!selected || selected.length === 0) return true;
  return selected.every((code) => speciesTypes.includes(code));
}

/** Liga/desliga um tipo (o novo entra por último). No limite de dois, um tipo novo não entra. */
export function toggleType(selected: readonly string[], code: string): string[] {
  if (selected.includes(code)) return selected.filter((item) => item !== code);
  if (selected.length >= MAX_TYPE_FILTERS) return [...selected];
  return canonicalTypes([...selected, code]);
}

export type TypeFilterResult<T> = {
  /** Espécies do resultado (mesma ordem da lista de entrada). */
  species: T[];
  /**
   * Para cada tipo: quantas espécies do resultado atual também o têm. Para um tipo ainda
   * não selecionado, é exatamente o tamanho do resultado se ele for acrescentado ("E").
   */
  counts: Map<string, number>;
};

/**
 * Aplica a seleção à lista já filtrada por pesquisa/geração, numa única passagem
 * (1.025 espécies no pior caso), e devolve também as contagens do seletor.
 */
export function applyTypeFilter<T extends { national_dex_number: number }>(
  species: readonly T[],
  index: ReadonlyMap<number, PokedexSpeciesTypes>,
  selected: readonly string[],
): TypeFilterResult<T> {
  const result: T[] = [];
  const counts = new Map<string, number>();
  for (const item of species) {
    const types = index.get(item.national_dex_number);
    if (!types) {
      if (selected.length === 0) result.push(item);
      continue;
    }
    if (!speciesMatchesTypes([types.primaryCode, types.secondaryCode], selected)) continue;
    result.push(item);
    counts.set(types.primaryCode, (counts.get(types.primaryCode) ?? 0) + 1);
    if (types.secondaryCode && types.secondaryCode !== types.primaryCode) {
      counts.set(types.secondaryCode, (counts.get(types.secondaryCode) ?? 0) + 1);
    }
  }
  return { species: result, counts };
}

/**
 * Rótulos (pt-BR, vindos do banco) dos tipos presentes no índice, na ordem oficial.
 * Para assim que encontra os 18 — na prática, poucas dezenas de entradas.
 */
export function typeLabels(index: ReadonlyMap<number, PokedexSpeciesTypes>): Map<string, string> {
  const found = new Map<string, string>();
  for (const types of index.values()) {
    if (!found.has(types.primaryCode)) found.set(types.primaryCode, types.primaryLabel);
    if (types.secondaryCode && types.secondaryLabel && !found.has(types.secondaryCode)) {
      found.set(types.secondaryCode, types.secondaryLabel);
    }
    if (found.size >= POKEMON_TYPE_ORDER.length) break;
  }
  const ordered = new Map<string, string>();
  for (const code of POKEMON_TYPE_ORDER) {
    const label = found.get(code);
    if (label) ordered.set(code, label);
  }
  return ordered;
}

/** "Fogo" / "Fogo e Voador". */
export function joinTypeLabels(labels: readonly string[]): string {
  return labels.length <= 1 ? labels.join("") : `${labels.slice(0, -1).join(", ")} e ${labels[labels.length - 1]}`;
}
