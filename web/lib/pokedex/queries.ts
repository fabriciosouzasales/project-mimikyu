import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Leituras da Pokédex Nacional (Pokédex P1, 2026-10-12) — contrato das duas
 * funções da Query 6131 (`get_pokedex_generations`,
 * `get_pokedex_national_species`). Ambas exigem sessão (`auth.uid()`) e
 * expõem só o necessário ao colecionador: nenhum UUID, nenhuma coluna
 * administrativa. As tabelas do catálogo Pokémon continuam fechadas para
 * leitura direta — a fronteira de autorização é o banco, não esta camada.
 *
 * Mesmo padrão de `lib/pricing/queries.ts`: falha de leitura devolve `null`
 * (a página mostra o estado de erro) e a causa real vai para o log do
 * servidor, sem dados sensíveis.
 */

export type PokedexGeneration = {
  generation_code: string;
  generation_ordinal: number;
  region_code: string | null;
  region_name: string | null;
  species_count: number;
  first_number: number | null;
  last_number: number | null;
};

export type PokedexSpecies = {
  national_dex_number: number;
  species_name: string;
  generation_code: string;
  generation_ordinal: number;
  /**
   * Caminho da versão WebP da arte no bucket `pokemon-species-artwork` (Query 6132),
   * só quando a imagem foi importada; `null`/ausente = moldura com a Pokébola.
   * Convertido em URL por `speciesArtworkUrl` (lib/pokedex/artwork.ts).
   */
  artwork_path?: string | null;
};

/** Limite espelhado da função SQL (64 caracteres) — evita enviar texto que o banco descartaria. */
export const POKEDEX_QUERY_MAX_LENGTH = 64;

export async function getPokedexGenerations(supabase: SupabaseClient): Promise<PokedexGeneration[] | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_pokedex_generations");
  if (error || !data) {
    logPokedexReadFailure("get_pokedex_generations", startedAt, error);
    return null;
  }
  return (data as PokedexGeneration[]).map((row) => ({ ...row, species_count: Number(row.species_count) }));
}

/**
 * Tamanho de página = teto de linhas por resposta do PostgREST (`max-rows`,
 * 1.000 no projeto). Uma chamada RPC sem paginação é truncada em silêncio
 * nesse teto — foi a causa de a listagem completa mostrar 1.000 de 1.025
 * espécies na homologação da P1. O teto do projeto não é aumentado; a
 * leitura é paginada aqui.
 */
const SPECIES_PAGE_SIZE = 1000;

export async function getPokedexNationalSpecies(
  supabase: SupabaseClient,
  filters: { query: string | null; generation: number | null },
): Promise<PokedexSpecies[] | null> {
  const startedAt = Date.now();
  const byNumber = new Map<number, PokedexSpecies>();

  // Páginas sequenciais por faixa ordenada pelo número nacional. Pesquisas e
  // filtros por geração cabem em uma página (uma chamada, como antes); só a
  // listagem completa precisa de uma segunda. Uma página incompleta encerra.
  for (let from = 0; ; from += SPECIES_PAGE_SIZE) {
    const { data, error } = await supabase
      .rpc("get_pokedex_national_species", {
        p_query: filters.query,
        p_generation: filters.generation,
      })
      .order("national_dex_number", { ascending: true })
      .range(from, from + SPECIES_PAGE_SIZE - 1);

    if (error || !data) {
      logPokedexReadFailure("get_pokedex_national_species", startedAt, error);
      return null;
    }

    const page = data as PokedexSpecies[];
    for (const row of page) byNumber.set(row.national_dex_number, row);
    if (page.length < SPECIES_PAGE_SIZE) break;
  }

  // Map por número nacional: nenhuma espécie duplicada mesmo se uma página
  // se sobrepuser à seguinte; ordenação final garantida aqui.
  return [...byNumber.values()].sort((a, b) => a.national_dex_number - b.national_dex_number);
}

// ---------------------------------------------------------------------------
// Índice de tipos da galeria (Pokédex P3c, Query 6135)
// ---------------------------------------------------------------------------

export type PokedexSpeciesTypes = {
  primaryCode: string;
  primaryLabel: string;
  secondaryCode: string | null;
  secondaryLabel: string | null;
};

type TypeIndexRow = {
  national_dex_number: number;
  primary_type_code: string;
  primary_type_label: string;
  secondary_type_code: string | null;
  secondary_type_label: string | null;
};

/** PostgREST: função ausente no cache de schema — 6135 ainda não aplicada. */
const FUNCTION_NOT_FOUND = "PGRST202";

/**
 * Tipos de todas as espécies com perfil importado, numa leitura em lote (sem N+1),
 * paginada pelo mesmo teto da galeria. Mesma regra de tipos da ficha (6133).
 *
 * Dependência opcional: sem a 6135 (PGRST202) ou em qualquer falha, devolve `null` e a
 * galeria segue funcionando com os cards no tom neutro — os tipos nunca bloqueiam a
 * lista de espécies.
 */
export async function getPokedexSpeciesTypeIndex(supabase: SupabaseClient): Promise<Map<number, PokedexSpeciesTypes> | null> {
  const startedAt = Date.now();
  const index = new Map<number, PokedexSpeciesTypes>();

  for (let from = 0; ; from += SPECIES_PAGE_SIZE) {
    const { data, error } = await supabase
      .rpc("get_pokedex_species_type_index", { p_language: "pt-BR" })
      .order("national_dex_number", { ascending: true })
      .range(from, from + SPECIES_PAGE_SIZE - 1);

    if (error || !data) {
      if (error?.code === FUNCTION_NOT_FOUND) {
        console.warn("[pokedex] get_pokedex_species_type_index indisponível (Query 6135 não aplicada); cards no tom neutro.");
      } else {
        logPokedexReadFailure("get_pokedex_species_type_index", startedAt, error);
      }
      return null;
    }

    const page = data as TypeIndexRow[];
    for (const row of page) {
      if (!row.primary_type_code || !row.primary_type_label) continue;
      index.set(row.national_dex_number, {
        primaryCode: row.primary_type_code,
        primaryLabel: row.primary_type_label,
        secondaryCode: row.secondary_type_code ?? null,
        secondaryLabel: row.secondary_type_code ? row.secondary_type_label ?? row.secondary_type_code : null,
      });
    }
    if (page.length < SPECIES_PAGE_SIZE) break;
  }

  return index;
}

function logPokedexReadFailure(
  rpc: string,
  startedAt: number,
  error: { code?: string; message?: string } | null,
): void {
  const elapsedMs = Date.now() - startedAt;
  const code = error?.code ?? "NO_DATA";
  console.error(`[pokedex] ${rpc} falhou (código ${code}, ${elapsedMs} ms): ${error?.message ?? "sem dados"}`);
}
