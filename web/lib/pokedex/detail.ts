import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Leituras da página de detalhes da espécie (Pokédex P3b, 2026-10-12).
 *
 * - `get_pokedex_species_detail` (Query 6133): identidade, tipos, medidas,
 *   textos com idioma efetivo e indicadores. Exige sessão; 0 linhas = espécie
 *   inexistente.
 * - `get_pokedex_species_hero_artwork` (Query 6134, PROPOSTA): caminho do PNG
 *   original (475 px) para o palco. Opcional — se a função ainda não existir
 *   no banco, a página usa o WebP de 320 px da 6133 sem erro para o usuário.
 *
 * Nenhuma chamada à PokéAPI: tudo vem do banco do MMKYU. Falha de leitura
 * devolve `status: "error"` e a causa vai para o log do servidor.
 */

export type PokedexSpeciesDetail = {
  national_dex_number: number;
  species_name: string;
  generation_code: string;
  generation_ordinal: number;
  region_code: string | null;
  region_name: string | null;
  artwork_path: string | null;
  profile_available: boolean;
  primary_type_code: string | null;
  primary_type_label: string | null;
  secondary_type_code: string | null;
  secondary_type_label: string | null;
  height_m: number | null;
  weight_kg: number | null;
  genus: string | null;
  genus_language: string | null;
  genus_is_official: boolean | null;
  description: string | null;
  description_language: string | null;
  description_is_official: boolean | null;
  description_source_version: string | null;
  is_legendary: boolean | null;
  is_mythical: boolean | null;
  is_baby: boolean | null;
};

export type SpeciesDetailResult =
  | { status: "ok"; species: PokedexSpeciesDetail }
  | { status: "not_found" }
  | { status: "error" };

export type SpeciesHeroArtwork = {
  originalPath: string;
  originalWidth: number | null;
};

/** Idioma pedido à função; a própria função cai para `en` quando não há texto em pt-BR. */
const DETAIL_LANGUAGE = "pt-BR";

export async function getPokedexSpeciesDetail(supabase: SupabaseClient, nationalDexNumber: number): Promise<SpeciesDetailResult> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_pokedex_species_detail", {
    p_national_dex_number: nationalDexNumber,
    p_language: DETAIL_LANGUAGE,
  });
  if (error) {
    logDetailReadFailure("get_pokedex_species_detail", startedAt, error);
    return { status: "error" };
  }
  const row = (data as PokedexSpeciesDetail[] | null)?.[0];
  if (!row) return { status: "not_found" };
  return {
    status: "ok",
    species: {
      ...row,
      // numeric do Postgres chega como string em alguns caminhos do PostgREST.
      height_m: row.height_m === null ? null : Number(row.height_m),
      weight_kg: row.weight_kg === null ? null : Number(row.weight_kg),
    },
  };
}

/** Código PostgREST para "função não encontrada no cache de schema" — 6134 ainda não aplicada. */
const FUNCTION_NOT_FOUND = "PGRST202";

export async function getPokedexSpeciesHeroArtwork(
  supabase: SupabaseClient,
  nationalDexNumber: number,
): Promise<SpeciesHeroArtwork | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_pokedex_species_hero_artwork", {
    p_national_dex_number: nationalDexNumber,
  });
  if (error) {
    if (error.code === FUNCTION_NOT_FOUND) {
      // Dependência opcional (Query 6134 ainda não aplicada): palco usa o WebP 320 px.
      console.warn("[pokedex] get_pokedex_species_hero_artwork indisponível (Query 6134 não aplicada) — usando WebP 320 px");
    } else {
      logDetailReadFailure("get_pokedex_species_hero_artwork", startedAt, error);
    }
    return null;
  }
  const row = (data as { original_path: string | null; original_width: number | null }[] | null)?.[0];
  if (!row?.original_path) return null;
  return { originalPath: row.original_path, originalWidth: row.original_width };
}

function logDetailReadFailure(rpc: string, startedAt: number, error: { code?: string; message?: string } | null): void {
  const elapsedMs = Date.now() - startedAt;
  console.error(`[pokedex] ${rpc} falhou (código ${error?.code ?? "NO_DATA"}, ${elapsedMs} ms): ${error?.message ?? "sem dados"}`);
}
