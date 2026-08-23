"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Action de Fontes de Preço (Bloco 4 do Pricing Admin, migration
 * 3942) — mesmo padrão de `resolucao-mapeamentos/actions.ts`:
 * `{ error: string | null, success? }`, nunca lança, erro traduzido via
 * `traduzirErroPricing`. Único write desta tela é `admin_update_pricing_source`
 * — nunca mexe em `frequency_days` (isso continua sendo
 * `admin_set_pricing_refresh_frequency`, migrations 3937/3938, editado em
 * /pricing/sincronizacoes).
 */

export type AtualizarFontePrecoState = { error: string | null; success?: boolean };

export async function atualizarFontePreco(
  _prevState: AtualizarFontePrecoState,
  formData: FormData,
): Promise<AtualizarFontePrecoState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_pricing_source", {
    p_pricing_source_id: String(formData.get("pricingSourceId") ?? ""),
    p_name: String(formData.get("name") ?? ""),
    p_base_url: String(formData.get("base_url") ?? ""),
    p_api_base_url: String(formData.get("api_base_url") ?? ""),
    p_documentation_url: String(formData.get("documentation_url") ?? ""),
    p_terms_url: String(formData.get("terms_url") ?? ""),
    p_attribution_text: String(formData.get("attribution_text") ?? ""),
    p_requires_commercial_agreement: formData.get("requires_commercial_agreement") === "on",
    p_supports_api: formData.get("supports_api") === "on",
    p_is_active: formData.get("is_active") === "on",
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/fontes");
  revalidatePath("/pricing/sincronizacoes");
  revalidatePath("/pricing");
  return { error: null, success: true };
}
