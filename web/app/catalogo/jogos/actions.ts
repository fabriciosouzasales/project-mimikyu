"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { DeleteEntitiesActionState, EntityActionState } from "@/lib/catalogo/admin-action-types";

// Aliases sobre os tipos compartilhados (`lib/catalogo/admin-action-types.ts`)
// — mantém os nomes já usados por `jogos-table.tsx` sem duplicar a forma.
export type GameActionState = EntityActionState;
export type DeleteGamesActionState = DeleteEntitiesActionState;

/**
 * Cadastra um novo Jogo via admin_create_game() (Query 2031, ADR-023).
 * code é normalizado (maiúsculas) e validado dentro da própria função —
 * esta Server Action só garante que os campos não cheguem vazios ao RPC.
 */
export async function createGame(_prevState: GameActionState, formData: FormData): Promise<GameActionState> {
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();

  if (!code) {
    return { error: "Informe o código do Jogo." };
  }
  if (!name) {
    return { error: "Informe o nome do Jogo." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_create_game", { p_code: code, p_name: name });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/jogos");
  return { error: null, success: true, id: data as string };
}

/**
 * Atualiza o nome de um Jogo via admin_update_game() (Query 2032, ADR-023).
 * code nunca é aceito aqui — é imutável por construção (a função nem tem
 * parâmetro para isso), não apenas por convenção de formulário.
 */
export async function updateGame(_prevState: GameActionState, formData: FormData): Promise<GameActionState> {
  const id = String(formData.get("id") ?? "");
  const name = String(formData.get("name") ?? "").trim();

  if (!id) {
    return { error: "Jogo inválido." };
  }
  if (!name) {
    return { error: "Informe o nome do Jogo." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_game", { p_id: id, p_name: name });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/jogos");
  return { error: null, success: true, id };
}

/**
 * Exclui um ou mais Jogos via admin_delete_game() (Query 2042, ADR-023 —
 * emenda "Game: exclusão real via UI"). Chama a função uma vez por id — não
 * existe (nem faz sentido criar, dado o volume) uma função de exclusão em
 * lote; cada exclusão é bloqueada individualmente pela FK se o Jogo tiver
 * Expansions associadas, e o resultado por item é reportado de volta.
 */
export async function deleteGames(
  _prevState: DeleteGamesActionState,
  formData: FormData,
): Promise<DeleteGamesActionState> {
  const ids = formData.getAll("ids").map(String).filter(Boolean);

  if (ids.length === 0) {
    return { error: "Nenhum Jogo selecionado." };
  }

  const supabase = await createClient();
  const deletedIds: string[] = [];
  const failures: { id: string; error: string }[] = [];

  for (const id of ids) {
    const { error } = await supabase.rpc("admin_delete_game", { p_id: id });
    if (error) {
      failures.push({ id, error: traduzirErroCatalogo(error.message) });
    } else {
      deletedIds.push(id);
    }
  }

  revalidatePath("/catalogo/jogos");

  return {
    error: null,
    success: true,
    deletedIds,
    failures: failures.length > 0 ? failures : undefined,
  };
}
