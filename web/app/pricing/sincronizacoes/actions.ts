"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Actions de Sincronizações (Bloco 3, Operações) — mesmo padrão de
 * `resolucao-mapeamentos/actions.ts`: `{ error: string | null, success? }`,
 * nunca lança, erro traduzido via `traduzirErroPricing`. A única escrita
 * real desta tela é a frequência de refresh por fonte — reusa
 * `admin_set_pricing_refresh_frequency` (migration 3938, já validada, não é
 * nova deste Bloco 3). Estado dos Sets e Dispatcher continuam só-leitura:
 * nenhuma action aqui mexe em `pricing_set_refresh_state`/cron/`next_due_at`
 * (constraint explícita de Fabrício para esta V1).
 */

export type AlterarFrequenciaState = { error: string | null; success?: boolean };

export async function alterarFrequenciaSincronizacao(
  _prevState: AlterarFrequenciaState,
  formData: FormData,
): Promise<AlterarFrequenciaState> {
  const pricingSourceId = String(formData.get("pricingSourceId") ?? "");
  const frequencyDays = Number.parseInt(String(formData.get("frequencyDays") ?? ""), 10);

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_set_pricing_refresh_frequency", {
    p_pricing_source_id: pricingSourceId,
    p_frequency_days: frequencyDays,
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/sincronizacoes");
  revalidatePath("/pricing");
  return { error: null, success: true };
}
