"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Actions de Condições (Bloco 4 do Pricing Admin, migration 3942) —
 * mesmo padrão de `{ error, success? }` do resto do módulo. Dois writes:
 * `admin_upsert_card_condition` (create/edit em uma função só — `p_id=null`
 * cria, `p_id` preenchido edita; `is_active` sempre editável mesmo com
 * histórico, decisão de Fabrício: desativar preserva `pricing_observation`
 * existente) e `admin_upsert_pricing_condition_mapping` (vínculo
 * Condição↔Fonte externa; a RPC recusa apontar para condição inativa —
 * `CONDITION_INACTIVE_CANNOT_RECEIVE_MAPPING`). Zero DELETE físico em
 * qualquer caminho.
 */

export type SalvarCondicaoState = { error: string | null; success?: boolean; id?: string };

export async function salvarCondicao(_prevState: SalvarCondicaoState, formData: FormData): Promise<SalvarCondicaoState> {
  const supabase = await createClient();
  const idRaw = String(formData.get("id") ?? "").trim();

  const { data, error } = await supabase.rpc("admin_upsert_card_condition", {
    p_id: idRaw || null,
    p_code: String(formData.get("code") ?? ""),
    p_name: String(formData.get("name") ?? ""),
    p_condition_order: Number.parseInt(String(formData.get("condition_order") ?? ""), 10),
    p_is_active: formData.get("is_active") === "on",
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/condicoes");
  return { error: null, success: true, id: data as string };
}

export type SalvarMapeamentoCondicaoState = { error: string | null; success?: boolean };

export async function salvarMapeamentoCondicao(
  _prevState: SalvarMapeamentoCondicaoState,
  formData: FormData,
): Promise<SalvarMapeamentoCondicaoState> {
  const supabase = await createClient();
  const idRaw = String(formData.get("id") ?? "").trim();

  const { error } = await supabase.rpc("admin_upsert_pricing_condition_mapping", {
    p_id: idRaw || null,
    p_pricing_source_id: String(formData.get("pricing_source_id") ?? ""),
    p_external_condition_code: String(formData.get("external_condition_code") ?? ""),
    p_condition_id: String(formData.get("condition_id") ?? ""),
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/condicoes");
  return { error: null, success: true };
}
