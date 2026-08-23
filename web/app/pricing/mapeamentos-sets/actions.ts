"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Actions de Mapeamentos de Sets (Bloco 4 do Pricing Admin, migration
 * 3942) — mesmo padrão de `{ error, success? }` do resto do módulo. Dois
 * writes: `admin_update_pricing_set_mapping_details` (nome sempre editável;
 * `external_set_id` bloqueado por dependência, guardado no próprio SQL —
 * fonte única de verdade, `pricing_set_mapping_dependency_exists`) e
 * `admin_reclassify_pricing_set_mapping` (CONFIRMED↔REJECTED, motivo
 * obrigatório, mesma guarda de dependência na direção CONFIRMED→REJECTED).
 */

export type AtualizarDetalhesMapeamentoSetState = { error: string | null; success?: boolean };

export async function atualizarDetalhesMapeamentoSet(
  _prevState: AtualizarDetalhesMapeamentoSetState,
  formData: FormData,
): Promise<AtualizarDetalhesMapeamentoSetState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_pricing_set_mapping_details", {
    p_id: String(formData.get("id") ?? ""),
    p_external_set_id: String(formData.get("external_set_id") ?? ""),
    p_external_set_name: String(formData.get("external_set_name") ?? ""),
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/mapeamentos-sets");
  return { error: null, success: true };
}

export type ReclassificarMapeamentoSetState = { error: string | null; success?: boolean };

export async function reclassificarMapeamentoSet(
  _prevState: ReclassificarMapeamentoSetState,
  formData: FormData,
): Promise<ReclassificarMapeamentoSetState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reclassify_pricing_set_mapping", {
    p_id: String(formData.get("id") ?? ""),
    p_new_status: String(formData.get("new_status") ?? ""),
    p_reason: String(formData.get("reason") ?? ""),
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/mapeamentos-sets");
  revalidatePath("/pricing/mapeamentos-cartas");
  return { error: null, success: true };
}
