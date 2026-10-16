"use server";

import { type SetFavoriteResult, favoriteFailureReason, isValidNationalDexNumber } from "@/lib/pokedex/favorites";
import { createClient } from "@/lib/supabase/server";

/**
 * Define se uma espécie é favorita do usuário da sessão (Pokédex P6, Query 6137).
 *
 * - Identidade: só a sessão (cookie) — o cliente envia o número e o estado desejado,
 *   nunca um `user_id`; a função SQL resolve o dono por `auth.uid()`. Sem
 *   `service_role`.
 * - DEFINE o estado (não alterna): repetir a chamada dá o mesmo resultado. Cliques
 *   duplos e reenvios são seguros; a ordem entre gravações da mesma espécie é garantida
 *   no cliente (uma por vez, última intenção vence — lib/pokedex/favorites.ts).
 * - Entradas validadas aqui só para responder cedo; a autoridade é o banco (22023/
 *   P0002/28000).
 * - Sem `revalidatePath`: a interface já mostra o novo estado; cada página da Pokédex é
 *   dinâmica e relê os favoritos na próxima navegação.
 */
export async function setPokedexSpeciesFavorite(nationalDexNumber: number, favorite: boolean): Promise<SetFavoriteResult> {
  if (!isValidNationalDexNumber(nationalDexNumber) || typeof favorite !== "boolean") {
    return { ok: false, reason: "invalid" };
  }

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_pokedex_species_favorite", {
    p_national_dex_number: nationalDexNumber,
    p_favorite: favorite,
  });

  if (error || typeof data !== "boolean") {
    const reason = favoriteFailureReason(error?.code);
    console.error(
      `[pokedex] set_pokedex_species_favorite falhou (código ${error?.code ?? "NO_DATA"}, ${Date.now() - startedAt} ms): ${error?.message ?? "sem dados"}`,
    );
    return { ok: false, reason };
  }

  return { ok: true, favorite: data };
}
