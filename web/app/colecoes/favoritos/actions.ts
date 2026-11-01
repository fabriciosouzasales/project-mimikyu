"use server";

import { type SetFavoriteResult, favoriteFailureReason, normalizeId } from "@/lib/favorites/card-favorites";
import { getMyCardFavoriteIds } from "@/lib/favorites/card-favorites-queries";
import { createClient } from "@/lib/supabase/server";

/**
 * Define se uma carta é favorita do usuário da sessão (V1-10, Query 5336) — mesmo
 * contrato da Espécie favorita (`app/pokedex/actions.ts`):
 * - identidade só pela sessão; o cliente envia a carta e o estado desejado, nunca
 *   um `user_id`. Sem `service_role`;
 * - DEFINE o estado (não alterna): repetir dá o mesmo resultado; a ordem entre
 *   gravações da mesma carta é garantida no cliente (uma por vez, última intenção vence);
 * - entradas validadas aqui só para responder cedo; a autoridade é o banco;
 * - sem `revalidatePath`: a tela já mostra o novo estado e as páginas relêem os
 *   favoritos na próxima navegação.
 */
export async function setCardFavorite(cardId: string, favorite: boolean): Promise<SetFavoriteResult> {
  const id = normalizeId(cardId);
  if (!id || typeof favorite !== "boolean") return { ok: false, reason: "invalid" };

  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_card_favorite", { p_card_id: id, p_favorite: favorite });

  if (error || typeof data !== "boolean") {
    console.error(
      JSON.stringify({ scope: "favorites.cards.write", fn: "set_card_favorite", ms: Date.now() - startedAt, code: error?.code ?? "NO_DATA" }),
    );
    return { ok: false, reason: favoriteFailureReason(error?.code) };
  }
  return { ok: true, favorite: data };
}

/**
 * Favoritos entre as cartas de uma grade montada no cliente (Pesquisa) — uma leitura
 * em lote por página carregada (blocos de até 500). `null` = indisponível: a grade
 * segue com os corações vazios e o clique continua funcionando.
 */
export async function readCardFavoriteIds(cardIds: string[]): Promise<string[] | null> {
  if (!Array.isArray(cardIds) || cardIds.length === 0) return [];
  if (cardIds.length > 2000) return null;
  const supabase = await createClient();
  const set = await getMyCardFavoriteIds(supabase, cardIds);
  return set ? [...set] : null;
}
