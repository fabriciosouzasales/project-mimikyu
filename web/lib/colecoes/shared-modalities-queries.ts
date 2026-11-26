import type { SupabaseClient } from "@supabase/supabase-js";
import type { MasterSetPositionsPage } from "./master-set";
import type { PokedexPositionsPage } from "./pokedex";
import {
  SHARED_MASTER_SET_PAGE_SIZE,
  SHARED_POKEDEX_PAGE_SIZE,
  type SharedModalityFilter,
  parseSharedMasterSetPositions,
  parseSharedPokedexPositions,
  sharedModalitySqlFilter,
} from "./shared-modalities";

/**
 * V1-13 · E3-6 — leituras de participante do Master Set (5323) e da Pokédex
 * (5324), com a sessão do usuário. `null` = falha de leitura (erro ou formato
 * inesperado); lista vazia NÃO é prova de vazio (ver `sharedModalityRead`).
 * Log: função, duração e código — nenhum dado da coleção.
 */

function logFailure(fn: string, startedAt: number, code: string | undefined) {
  console.error(JSON.stringify({ scope: "colecoes.sharing.modality", fn, ms: Date.now() - startedAt, code: code ?? "BAD_SHAPE" }));
}

export async function getSharedMasterSetPositions(
  supabase: SupabaseClient,
  collectionId: string,
  filter: SharedModalityFilter,
  page: number,
): Promise<MasterSetPositionsPage | null> {
  const startedAt = Date.now();
  const offset = Math.min(100_000, Math.max(0, page - 1) * SHARED_MASTER_SET_PAGE_SIZE);
  const { data, error } = await supabase.rpc("get_shared_master_set_positions", {
    p_collection_id: collectionId,
    p_filter: sharedModalitySqlFilter(filter),
    p_limit: SHARED_MASTER_SET_PAGE_SIZE,
    p_offset: offset,
  });
  if (error) {
    logFailure("get_shared_master_set_positions", startedAt, error.code);
    return null;
  }
  const parsed = parseSharedMasterSetPositions(data);
  if (!parsed) logFailure("get_shared_master_set_positions", startedAt, undefined);
  return parsed;
}

export async function getSharedPokedexPositions(
  supabase: SupabaseClient,
  collectionId: string,
  filter: SharedModalityFilter,
  offset: number,
): Promise<PokedexPositionsPage | null> {
  const startedAt = Date.now();
  const { data, error } = await supabase.rpc("get_shared_pokedex_positions", {
    p_collection_id: collectionId,
    p_filter: sharedModalitySqlFilter(filter),
    p_generation_code: null,
    p_limit: SHARED_POKEDEX_PAGE_SIZE,
    p_offset: offset,
  });
  if (error) {
    logFailure("get_shared_pokedex_positions", startedAt, error.code);
    return null;
  }
  const parsed = parseSharedPokedexPositions(data);
  if (!parsed) logFailure("get_shared_pokedex_positions", startedAt, undefined);
  return parsed;
}
