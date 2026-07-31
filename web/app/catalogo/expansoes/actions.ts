"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { DeleteEntitiesActionState, EntityActionState } from "@/lib/catalogo/admin-action-types";

// Aliases sobre os tipos compartilhados (`lib/catalogo/admin-action-types.ts`)
// — mesmo padrão de `jogos/actions.ts`.
export type ExpansionActionState = EntityActionState;
export type DeleteExpansionsActionState = DeleteEntitiesActionState;

/**
 * Cadastra uma nova Expansão via admin_create_expansion() (Query 2033,
 * ADR-023). code e release_order são validados dentro da própria função —
 * esta Server Action só garante que os campos não cheguem vazios/inválidos
 * ao RPC.
 */
export async function createExpansion(
  _prevState: ExpansionActionState,
  formData: FormData,
): Promise<ExpansionActionState> {
  const gameId = String(formData.get("game_id") ?? "").trim();
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const releaseOrderRaw = String(formData.get("release_order") ?? "").trim();
  const releaseOrder = Number(releaseOrderRaw);

  if (!gameId) {
    return { error: "Selecione o Jogo." };
  }
  if (!code) {
    return { error: "Informe o código da Expansão." };
  }
  if (!name) {
    return { error: "Informe o nome da Expansão." };
  }
  if (!releaseOrderRaw || !Number.isInteger(releaseOrder) || releaseOrder <= 0) {
    return { error: "Informe uma ordem de lançamento válida (número inteiro positivo)." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_create_expansion", {
    p_game_id: gameId,
    p_code: code,
    p_name: name,
    p_release_order: releaseOrder,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/expansoes");
  revalidatePath("/catalogo/jogos");
  return { error: null, success: true, id: data as string };
}

/**
 * Atualiza nome e ordem de lançamento de uma Expansão via
 * admin_update_expansion() (Query 2034, ADR-023). game_id e code nunca são
 * aceitos aqui — imutáveis por construção (a função nem tem parâmetro para
 * isso), mesmo princípio já aplicado a Game.
 */
export async function updateExpansion(
  _prevState: ExpansionActionState,
  formData: FormData,
): Promise<ExpansionActionState> {
  const id = String(formData.get("id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const releaseOrderRaw = String(formData.get("release_order") ?? "").trim();
  const releaseOrder = Number(releaseOrderRaw);

  if (!id) {
    return { error: "Expansão inválida." };
  }
  if (!name) {
    return { error: "Informe o nome da Expansão." };
  }
  if (!releaseOrderRaw || !Number.isInteger(releaseOrder) || releaseOrder <= 0) {
    return { error: "Informe uma ordem de lançamento válida (número inteiro positivo)." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_expansion", {
    p_id: id,
    p_name: name,
    p_release_order: releaseOrder,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/expansoes");
  return { error: null, success: true, id };
}

/**
 * Exclui uma ou mais Expansões via admin_delete_expansion() (Query 2044,
 * ADR-023 — emenda 2026-07-31 "Expansion: exclusão real via UI", mesmo
 * padrão de deleteGames). Chama a função uma vez por id — cada exclusão é
 * bloqueada individualmente pela FK fk_card_set_expansion se a Expansão
 * tiver Card Sets associados, e o resultado por item é reportado de volta.
 *
 * Pendência: admin_delete_expansion() (Query 2044) ainda não foi executada
 * no Supabase — esta action existe e está correta, mas retorna erro de
 * função inexistente até a Query ser confirmada (ver docs/05-modelo-de-
 * dados.md, "Emenda — Expansion: exclusão real via UI").
 */
export async function deleteExpansions(
  _prevState: DeleteExpansionsActionState,
  formData: FormData,
): Promise<DeleteExpansionsActionState> {
  const ids = formData.getAll("ids").map(String).filter(Boolean);

  if (ids.length === 0) {
    return { error: "Nenhuma Expansão selecionada." };
  }

  const supabase = await createClient();
  const deletedIds: string[] = [];
  const failures: { id: string; error: string }[] = [];

  for (const id of ids) {
    const { error } = await supabase.rpc("admin_delete_expansion", { p_id: id });
    if (error) {
      failures.push({ id, error: traduzirErroCatalogo(error.message) });
    } else {
      deletedIds.push(id);
    }
  }

  revalidatePath("/catalogo/expansoes");

  return {
    error: null,
    success: true,
    deletedIds,
    failures: failures.length > 0 ? failures : undefined,
  };
}
