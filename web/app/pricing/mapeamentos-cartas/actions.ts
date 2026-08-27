"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Action de Mapeamentos de Cartas (Bloco 4 do Pricing Admin,
 * migration 3942; convergência com Pendências em 2026-08-27) — único write
 * desta tela é `admin_reclassify_pricing_card_mapping` (CONFIRMED↔REJECTED,
 * motivo obrigatório), mas depois da convergência só REJECTED→CONFIRMED é
 * alcançável pela UI (CONFIRMED nunca aparece na fila). Migration 3962
 * adiciona hardening: reclassificar para CONFIRMED exige uma
 * `pricing_source_card_identity` PRIMARY já confirmada, usada para
 * preencher `external_card_id`/`external_card_name` — não existe "editar
 * detalhes" aqui, essas colunas nunca são setadas manualmente pela Server
 * Action.
 */

export type ReclassificarMapeamentoCartaState = { error: string | null; success?: boolean };

export async function reclassificarMapeamentoCarta(
  _prevState: ReclassificarMapeamentoCartaState,
  formData: FormData,
): Promise<ReclassificarMapeamentoCartaState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reclassify_pricing_card_mapping", {
    p_id: String(formData.get("id") ?? ""),
    p_new_status: String(formData.get("new_status") ?? ""),
    p_reason: String(formData.get("reason") ?? ""),
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/mapeamentos-cartas");
  return { error: null, success: true };
}
