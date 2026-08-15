"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroCatalogo } from "@/lib/supabase/catalogo-errors";
import type { EntityActionState } from "@/lib/catalogo/admin-action-types";

/**
 * Server Actions da tela /catalogo/tipos-variacao (Incremento 2, ADR-028 —
 * Governança da Taxonomia de Card Variant Type). Mesmo padrão estrutural de
 * `catalogo/raridades/actions.ts`: nenhuma escrita direta na tabela, sempre
 * via RPC `SECURITY DEFINER` (admin_create_card_variant_type()/
 * admin_update_card_variant_type()/admin_deactivate_card_variant_type()/
 * admin_reactivate_card_variant_type(), Queries 2154-2157).
 *
 * Sem exclusão física nesta versão (decisão explícita de Fabrício, mesma
 * ADR) — não existe `deleteCardVariantType` aqui, de propósito.
 */

async function resolveGameId(supabase: Awaited<ReturnType<typeof createClient>>): Promise<string | null> {
  const { data } = await supabase.from("game").select("id").limit(1).maybeSingle();
  return data?.id ?? null;
}

export type CardVariantTypeActionState = EntityActionState;

/**
 * Cadastra um Card Variant Type canônico novo via
 * admin_create_card_variant_type() (Query 2154). Jogo não é campo do
 * formulário — mesmo critério de `createRarityWithMapping`
 * (raridades/actions.ts): um único Game real (POKEMON) hoje, resolvido
 * aqui em vez de pedido ao administrador.
 */
export async function createCardVariantType(
  _prevState: CardVariantTypeActionState,
  formData: FormData,
): Promise<CardVariantTypeActionState> {
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const displayOrder = Number.parseInt(String(formData.get("displayOrder") ?? ""), 10);

  if (!code) return { error: "Informe o código do tipo de variação." };
  if (!name) return { error: "Informe o nome do tipo de variação." };
  if (!Number.isFinite(displayOrder)) return { error: "Ordem de exibição inválida." };

  const supabase = await createClient();
  const gameId = await resolveGameId(supabase);

  if (!gameId) {
    return { error: "Não foi possível resolver o Jogo. Verifique o cadastro base." };
  }

  const { data, error } = await supabase.rpc("admin_create_card_variant_type", {
    p_game_id: gameId,
    p_code: code,
    p_name: name,
    p_description: description || null,
    p_display_order: displayOrder,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/tipos-variacao");
  return { error: null, success: true, id: data as string | undefined };
}

/**
 * Atualiza name/description/displayOrder de um Card Variant Type já
 * cadastrado via admin_update_card_variant_type() (Query 2155). Código e
 * Game são imutáveis — a função nem recebe esses parâmetros, mesmo critério
 * de `updateRarity`.
 */
export async function updateCardVariantType(
  _prevState: CardVariantTypeActionState,
  formData: FormData,
): Promise<CardVariantTypeActionState> {
  const id = String(formData.get("id") ?? "");
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const displayOrder = Number.parseInt(String(formData.get("displayOrder") ?? ""), 10);

  if (!id) return { error: "Tipo de variação inválido." };
  if (!name) return { error: "Informe o nome do tipo de variação." };
  if (!Number.isFinite(displayOrder)) return { error: "Ordem de exibição inválida." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_card_variant_type", {
    p_id: id,
    p_name: name,
    p_description: description || null,
    p_display_order: displayOrder,
  });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/tipos-variacao");
  return { error: null, success: true, id };
}

/**
 * Inativa um Card Variant Type via admin_deactivate_card_variant_type()
 * (Query 2156) — mesmo formato simples (`{error}`) de `deactivateCard`
 * (catalogo/cartas/actions.ts), chamado direto por um Dialog de confirmação
 * (não `useActionState`, mesmo padrão do botão de desativar Card). Nenhuma
 * card_variant/card_variant_type_external_mapping já existente é tocada —
 * garantia da própria RPC, não desta action.
 */
export async function deactivateCardVariantType(id: string): Promise<{ error: string | null }> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_deactivate_card_variant_type", { p_id: id });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/tipos-variacao");
  return { error: null };
}

/**
 * Reativa um Card Variant Type via admin_reactivate_card_variant_type()
 * (Query 2157) — espelho exato de `deactivateCardVariantType` acima, mesmo
 * padrão de `reactivateCard`.
 */
export async function reactivateCardVariantType(id: string): Promise<{ error: string | null }> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reactivate_card_variant_type", { p_id: id });

  if (error) {
    return { error: traduzirErroCatalogo(error.message) };
  }

  revalidatePath("/catalogo/tipos-variacao");
  return { error: null };
}
