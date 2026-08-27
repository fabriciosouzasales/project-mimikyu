// Project Mimikyu — supabase/functions/justtcg-set-bootstrap/pricing-source-lookup.ts
// Resolução do pricing_source_id da fonte JUSTTCG — cópia literal de
// supabase/functions/justtcg-price-refresh-set/pricing-source-lookup.ts (mesmo motivo de
// extração: index.ts tem Deno.serve no escopo do módulo, importar dispararia um listener
// real como efeito colateral — inaceitável para a suíte 100% offline). Único ponto deste
// dispatcher autorizado a ler pricing_source com este literal fixo, nunca um parâmetro
// vindo da requisição HTTP. Logger sanitizado — nunca error/error.message/error.stack cru
// chega ao logger, só um código fixo e um contexto operacional booleano.

import { defaultSanitizedLogger, type SanitizedLogger } from "./handler.ts";

export async function resolveJusttcgPricingSourceId(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  logError: SanitizedLogger = defaultSanitizedLogger,
): Promise<string | null> {
  const { data, error } = await supabase
    .from("pricing_source")
    .select("id, code, is_active")
    .eq("code", "JUSTTCG")
    .maybeSingle();
  if (error || !data) {
    logError("JUSTTCG_SET_BOOTSTRAP_SOURCE_LOOKUP_FAILED", {
      hadError: Boolean(error),
    });
    return null;
  }
  return (data as { id: string }).id;
}
