/**
 * Indicadores do capítulo de uma geração (Pokédex P4b, 2026-10-13).
 *
 * Função pura sobre dados que a galeria já carrega — nenhuma leitura nova:
 * - a geração (Query 6131: contagem e intervalo de números nacionais);
 * - o índice de tipos de todas as espécies (Query 6135), que NÃO é filtrado pela
 *   pesquisa. Por isso a composição descreve a geração inteira, mesmo quando a grade
 *   abaixo mostra só os resultados de uma pesquisa.
 *
 * Definições (exibidas assim na interface):
 * - Espécies: `species_count` da geração.
 * - Tipos presentes: quantos dos 18 tipos aparecem em pelo menos uma espécie da
 *   geração, como tipo primário ou secundário.
 * - Composição: para cada tipo, quantas espécies da geração o têm (primário ou
 *   secundário). Uma espécie de dois tipos conta nos dois, então a soma pode passar do
 *   total de espécies — a interface diz "espécies com o tipo", nunca "porcentagem".
 */

import type { PokedexGeneration, PokedexSpeciesTypes } from "./queries.ts";
import { POKEMON_TYPE_PALETTE } from "./type-palette.ts";

export type ChapterTypeCount = { code: string; label: string; count: number };

export type GenerationChapter = {
  generationCode: string;
  generationOrdinal: number;
  regionName: string | null;
  speciesCount: number;
  firstNumber: number | null;
  lastNumber: number | null;
  /** `null` quando o índice de tipos está indisponível (a composição some, o resto fica). */
  composition: {
    /** Tipos em ordem decrescente de espécies; empate pela ordem canônica dos 18 tipos. */
    types: ChapterTypeCount[];
    /** Espécies da geração que têm tipo no índice (normalmente = speciesCount). */
    typedSpecies: number;
  } | null;
};

const CANONICAL_ORDER = new Map(Object.keys(POKEMON_TYPE_PALETTE).map((code, index) => [code, index]));

function canonicalIndex(code: string): number {
  return CANONICAL_ORDER.get(code) ?? Number.MAX_SAFE_INTEGER;
}

export function buildGenerationChapter(
  generation: PokedexGeneration,
  speciesTypes: Map<number, PokedexSpeciesTypes> | null,
): GenerationChapter {
  const base = {
    generationCode: generation.generation_code,
    generationOrdinal: generation.generation_ordinal,
    regionName: generation.region_name,
    speciesCount: generation.species_count,
    firstNumber: generation.first_number,
    lastNumber: generation.last_number,
  };

  if (!speciesTypes || generation.first_number === null || generation.last_number === null) {
    return { ...base, composition: null };
  }

  const counts = new Map<string, ChapterTypeCount>();
  let typedSpecies = 0;

  function add(code: string, label: string) {
    const current = counts.get(code);
    if (current) current.count += 1;
    else counts.set(code, { code, label, count: 1 });
  }

  for (let n = generation.first_number; n <= generation.last_number; n += 1) {
    const types = speciesTypes.get(n);
    if (!types) continue;
    typedSpecies += 1;
    add(types.primaryCode, types.primaryLabel);
    if (types.secondaryCode && types.secondaryLabel && types.secondaryCode !== types.primaryCode) {
      add(types.secondaryCode, types.secondaryLabel);
    }
  }

  if (typedSpecies === 0) {
    return { ...base, composition: null };
  }

  const types = [...counts.values()].sort(
    (a, b) => b.count - a.count || canonicalIndex(a.code) - canonicalIndex(b.code) || a.code.localeCompare(b.code),
  );

  return { ...base, composition: { types, typedSpecies } };
}

/** Quantos tipos ficam visíveis antes de "ver os outros" (o restante abre num disclosure nativo). */
export const CHAPTER_VISIBLE_TYPES = 6;

/**
 * Separa os tipos visíveis dos recolhidos. O corte nunca separa um empate: se o último
 * visível empata com os seguintes, todos os empatados ficam visíveis — a interface não
 * escolhe arbitrariamente entre tipos com a mesma contagem.
 */
export function splitChapterTypes(
  types: ChapterTypeCount[],
  limit: number = CHAPTER_VISIBLE_TYPES,
): { visible: ChapterTypeCount[]; hidden: ChapterTypeCount[] } {
  if (types.length <= limit) return { visible: types, hidden: [] };
  const threshold = types[limit - 1]?.count ?? 0;
  let end = limit;
  while (end < types.length && types[end]?.count === threshold) end += 1;
  return { visible: types.slice(0, end), hidden: types.slice(end) };
}
