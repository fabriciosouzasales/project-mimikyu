"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Action de Mapeamentos de Cartas (Bloco 4 do Pricing Admin,
 * migration 3942) — único write desta tela é `admin_reclassify_pricing_card_mapping`
 * (CONFIRMED↔REJECTED, motivo obrigatório). Não existe "editar detalhes"
 * aqui — `external_card_id`/`external_card_name` só mudam via
 * `admin_resolve_pricing_mapping` (Bloco 2, fluxo de Resolução) ou pelo
 * conector automático; esta tela é cadastro/consulta de todos os status +
 * reclassificação pontual, não um editor de identidade externa.
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
  revalidatePath("/pricing/pendencias");
  return { error: null, success: true };
}
