// Project Mimikyu — supabase/functions/justtcg-price-refresh-set/index.ts
// Edge Function do dispatcher durável por Set (P15) — Incremento "Orquestração Programada
// JustTCG", fase "implementar somente o dispatcher/Edge Function que consome as RPCs já
// criadas" (2026-08-22).
//
// Mesmo padrão de "adapter fino" já usado por justtcg-price-refresh/index.ts: nenhuma
// lógica de negócio mora aqui — só a amarração das dependências reais (Deno.env,
// SupabaseClient real, JustTcgClient real) entregues já resolvidas ao handler puro
// (handler.ts) e ao núcleo compartilhado (../_shared/pricing-justtcg-refresh/
// set-refresh-core.ts).
//
// Identidade: verify_jwt=false (mesma razão de ptax-fx-refresh/justtcg-price-refresh —
// chaves sb_secret_.../sb_publishable_... não são JWT) — autorização real via segredo
// dedicado, validado no header "apikey" (ver auth.ts). REAPROVEITA
// JUSTTCG_PRICE_REFRESH_SECRET (mesmo segredo já usado por justtcg-price-refresh — ver
// racional em auth.ts).
//
// Segredos consumidos (Function Secrets — nunca hardcoded, nunca logados):
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — acesso ao banco.
//   JUSTTCG_PRICE_REFRESH_SECRET — segredo dedicado, comparado via apikey.
//   JUSTTCG_API_KEY — credencial real da JustTCG v1.
//
// Nota de arquitetura — NENHUM cron aponta para esta função nesta rodada (requisito
// explícito do pedido: "novo cron dispatcher ainda NÃO deve ser criado nesta rodada"). A
// função existe, pode ser deployada e chamada manualmente para validação, mas só passa a
// rodar de forma agendada em uma migration futura e separada, com autorização explícita.
//
// Granularidade: 1 Set por invocação, decidido inteiramente por
// open_pricing_set_refresh_attempt (migration 3933) — ao contrário de
// justtcg-price-refresh (wave-based, parâmetro waveNumber no corpo), esta função não
// aceita nenhum parâmetro de negócio no corpo da requisição.

import { createClient } from "@supabase/supabase-js";
import { buildSetRefreshSupabaseAdapter } from "../_shared/pricing-justtcg-refresh/set-refresh-supabase-adapter.ts";
import { SET_REQUEST_BUDGET } from "../_shared/pricing-justtcg-refresh/set-refresh-core.ts";
import { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { handleJusttcgPriceRefreshSetRequest } from "./handler.ts";
import { resolveJusttcgPricingSourceId } from "./pricing-source-lookup.ts";

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseServiceRoleKey) {
    console.error(
      "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes no ambiente da Edge Function justtcg-price-refresh-set.",
    );
    return Response.json(
      { success: false, error: "SERVER_MISCONFIGURED" },
      { status: 500 },
    );
  }
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const port = buildSetRefreshSupabaseAdapter(supabase);

  const pricingSourceId = await resolveJusttcgPricingSourceId(supabase);

  const expectedSecret = Deno.env.get("JUSTTCG_PRICE_REFRESH_SECRET") ?? null;
  const justtcgApiKey = Deno.env.get("JUSTTCG_API_KEY") ?? null;

  try {
    return await handleJusttcgPriceRefreshSetRequest(req, {
      expectedSecret,
      port,
      pricingSourceId,
      buildClient: () => {
        if (!justtcgApiKey) {
          console.error(
            "JUSTTCG_PRICE_REFRESH_SET: JUSTTCG_API_KEY ausente no ambiente — a chamada à JustTCG falhará com AUTH_FAILURE.",
          );
        }
        return new JustTcgClient(
          justtcgApiKey ?? "",
          fetch,
          SET_REQUEST_BUDGET,
        );
      },
    });
  } catch {
    console.error("JUSTTCG_PRICE_REFRESH_SET_INTERNAL_ERROR_OUTER");
    return Response.json({ success: false, error: "INTERNAL_ERROR" }, {
      status: 500,
    });
  }
});
