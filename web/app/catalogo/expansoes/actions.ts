"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { EntityActionState } from "@/lib/catalogo/admin-action-types";

// Alias sobre o tipo compartilhado (`lib/catalogo/admin-action-types.ts`) —
// mesmo padrão de `jogos/actions.ts`. Sem exclusão: ADR-023 não prevê
// (nem foi pedida) exclusão de Expansion — só Game recebeu essa emenda.
export type ExpansionActionState = EntityActionState;

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
