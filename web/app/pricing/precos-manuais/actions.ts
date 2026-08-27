"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Action de Preços Manuais (migrations 3967-3969) — único write desta
 * tela é `admin_set_manual_price`, sempre um novo INSERT em
 * `pricing_manual_price` (append-only): "Atualizar preço" na UI nunca é um
 * UPDATE, é a mesma chamada com um novo valor, preservando o registro
 * anterior para histórico/auditoria (`pricing_admin_action_log`).
 */

export type DefinirPrecoManualState = { error: string | null; success?: boolean; cardId?: string };

export async function definirPrecoManual(
  _prevState: DefinirPrecoManualState,
  formData: FormData,
): Promise<DefinirPrecoManualState> {
  const supabase = await createClient();
  const cardId = String(formData.get("card_id") ?? "");
  const conditionId = String(formData.get("condition_id") ?? "");
  const priceRaw = String(formData.get("price") ?? "").replace(",", ".");
  const price = Number(priceRaw);
  const currencyCode = String(formData.get("currency_code") ?? "BRL");
  const observedAtRaw = String(formData.get("observed_at") ?? "");
  const reason = String(formData.get("reason") ?? "");

  if (!Number.isFinite(price)) {
    return { error: "Informe um valor numérico válido." };
  }

  // `<input type="datetime-local">` devolve "AAAA-MM-DDTHH:mm" sem timezone
  // — interpretado como horário local do navegador antes de virar ISO/UTC
  // para a RPC (mesma resolução que `new Date(...)` já faz por padrão).
  const observedAtDate = observedAtRaw ? new Date(observedAtRaw) : null;
  if (!observedAtDate || Number.isNaN(observedAtDate.getTime())) {
    return { error: "Informe uma data de referência válida." };
  }

  const { error } = await supabase.rpc("admin_set_manual_price", {
    p_card_id: cardId,
    p_condition_id: conditionId,
    p_price: price,
    p_currency_code: currencyCode,
    p_observed_at: observedAtDate.toISOString(),
    p_reason: reason,
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/precos-manuais");
  return { error: null, success: true, cardId };
}
