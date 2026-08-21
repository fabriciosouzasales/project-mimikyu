// Project Mimikyu — supabase/functions/justtcg-price-refresh/pricing-source-lookup.ts
// Resolução do pricing_source_id da fonte JUSTTCG — extraído de index.ts (correção de
// segurança, 2026-08-21, 2ª rodada). Motivo da extração: index.ts tem `Deno.serve(...)` no
// escopo do módulo, então importá-lo (como um teste offline precisaria fazer) dispararia
// um listener real como efeito colateral — inaceitável para a suíte 100% offline já
// estabelecida neste incremento. Este módulo não tem esse problema: é uma função pura,
// sem `Deno.serve`, importável e testável isoladamente (ver
// pricing-source-lookup.test.ts).
//
// Único ponto do repositório autorizado a ler pricing_source com este literal fixo — mesmo
// precedente documentado em scripts/sync-justtcg-pricing.ts ("4. Acesso restrito e
// explícito à fonte JUSTTCG"). Nunca um parâmetro vindo da requisição HTTP.
//
// Correção de segurança (2026-08-21, 2ª rodada — divergência apontada por Fabrício após a
// suíte offline revelar o mesmo anti-padrão já corrigido em handler.ts): esta função
// registrava `error?.message` cru em Function Logs. O objeto `error` aqui é a resposta
// bruta do PostgREST — pode carregar texto de constraint, nome de coluna/tabela, ou
// qualquer fragmento da query malsucedida — e nunca deve chegar ao logger. Mesmo desenho
// de logger sanitizado e injetável de handler.ts (reexportado dali para não duplicar o
// default): só um código fixo e um contexto operacional booleano (havia erro vs.
// simplesmente não encontrado) chegam ao logger — nunca `error`, `error.message`,
// `error.stack`, nem o objeto PostgREST/`data` em si.

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
    logError("JUSTTCG_PRICE_REFRESH_SOURCE_LOOKUP_FAILED", {
      hadError: Boolean(error),
    });
    return null;
  }
  return (data as { id: string }).id;
}
