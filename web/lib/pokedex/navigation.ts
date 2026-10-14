/**
 * Navegação entre fichas por contexto (Pokédex P4a, 2026-10-13).
 *
 * Dois contextos, decididos pela presença de `?geracao=` na URL:
 *
 * - Pokédex Nacional (sem geração): anterior/próximo seguem a ordem nacional e
 *   atravessam fronteiras de geração livremente.
 * - Geração selecionada: anterior/próximo ficam dentro da geração. Na primeira
 *   espécie não há anterior; na última, em vez de um "próximo" de outra geração
 *   (que manteria o filtro antigo e quebraria o "voltar"), a ficha oferece a
 *   transição explícita para a próxima geração, já com o contexto atualizado.
 *
 * Funções puras sobre dados que a ficha já lê (a espécie e os vizinhos ±1 vêm
 * de `get_pokedex_species_detail`, com geração e região) — nenhuma leitura nova.
 */

import type { PokedexContext } from "./format.ts";

/** O mínimo de uma espécie que a navegação precisa (subconjunto da ficha). */
export type NavigationSpecies = {
  national_dex_number: number;
  species_name: string;
  artwork_path: string | null;
  generation_ordinal: number;
  generation_code: string;
  region_name: string | null;
};

/** Primeira espécie da próxima geração e o contexto com que ela deve ser aberta. */
export type GenerationTransition = {
  generationOrdinal: number;
  generationCode: string;
  regionName: string | null;
  first: NavigationSpecies;
  context: PokedexContext;
};

export type SpeciesNavigation = {
  previous: NavigationSpecies | null;
  next: NavigationSpecies | null;
  /** Só no contexto de geração, na última espécie dela, quando existe geração seguinte. */
  nextGeneration: GenerationTransition | null;
};

/**
 * O contexto de geração só vale se a espécie pertence a ela. Um link antigo,
 * editado à mão ou a busca rápida para outra geração produzem `?geracao=` que não
 * corresponde à espécie: nesse caso a ficha deve abrir no contexto nacional
 * (mesma pesquisa), para que o "voltar" nunca procure uma espécie fora da
 * geração filtrada.
 */
export function isGenerationContextMismatch(context: PokedexContext, speciesGenerationOrdinal: number): boolean {
  return context.generation !== null && context.generation !== speciesGenerationOrdinal;
}

export function resolveSpeciesNavigation({
  current,
  previous,
  next,
  context,
}: {
  current: Pick<NavigationSpecies, "generation_ordinal">;
  previous: NavigationSpecies | null;
  next: NavigationSpecies | null;
  /** Contexto já normalizado (sem divergência de geração). */
  context: PokedexContext;
}): SpeciesNavigation {
  if (context.generation === null) {
    return { previous, next, nextGeneration: null };
  }

  const generation = current.generation_ordinal;
  const sameGeneration = (species: NavigationSpecies | null) =>
    species !== null && species.generation_ordinal === generation ? species : null;

  const nextInGeneration = sameGeneration(next);
  const nextGeneration: GenerationTransition | null =
    next !== null && nextInGeneration === null && next.generation_ordinal > generation
      ? {
          generationOrdinal: next.generation_ordinal,
          generationCode: next.generation_code,
          regionName: next.region_name,
          first: next,
          context: { query: context.query, generation: next.generation_ordinal },
        }
      : null;

  return { previous: sameGeneration(previous), next: nextInGeneration, nextGeneration };
}
