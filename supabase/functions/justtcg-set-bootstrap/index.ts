// Project Mimikyu — supabase/functions/justtcg-set-bootstrap/index.ts
// Edge Function do dispatcher de bootstrap de Set (CARD_SYNC) — P16.5.4 ("wiring da Edge
// Function de bootstrap", 2026-08-26). Único objetivo desta rodada: expor
// executeBootstrapAttempt() (P16.5.2/P16.5.3, já testado offline) via HTTP, reaproveitando
// integralmente bootstrap-core.ts/bootstrap-supabase-adapter.ts — nenhuma lógica de negócio
// nova mora aqui.
//
// Mesmo padrão de "adapter fino" já usado por justtcg-price-refresh-set/index.ts: nenhuma
// lógica de negócio mora aqui — só a amarração das dependências reais (Deno.env,
// SupabaseClient real, JustTcgClient real) entregues já resolvidas ao handler puro
// (handler.ts) e ao núcleo compartilhado (../_shared/pricing-justtcg-bootstrap/
// bootstrap-core.ts).
//
// Identidade: verify_jwt=false (mesma razão de ptax-fx-refresh/justtcg-price-refresh/
// justtcg-price-refresh-set — chaves sb_secret_.../sb_publishable_... não são JWT) —
// autorização real via segredo dedicado, validado no header "apikey" (ver auth.ts).
// REAPROVEITA JUSTTCG_PRICE_REFRESH_SECRET (mesmo segredo já usado pelas duas Edge
// Functions de price-refresh — ver racional em auth.ts).
//
// Segredos consumidos (Function Secrets — nunca hardcoded, nunca logados):
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — acesso ao banco.
//   JUSTTCG_PRICE_REFRESH_SECRET — segredo dedicado, comparado via apikey.
//   JUSTTCG_API_KEY — credencial real da JustTCG v1.
//
// Nota de arquitetura — NENHUM cron aponta para esta função nesta rodada (requisito
// explícito do pedido: "nenhum cron ainda"). A função existe, pode ser deployada e chamada
// manualmente para validação, mas só passa a rodar de forma agendada em uma migration
// futura e separada, com autorização explícita. NENHUMA execução real do SWSH8 (ou
// qualquer outro Set) foi disparada nesta rodada.
//
// Granularidade: 1 Set por invocação, decidido inteiramente por
// open_pricing_set_bootstrap_attempt (migration 3955) — esta função não aceita nenhum
// parâmetro de negócio no corpo da requisição, mesma disciplina de
// justtcg-price-refresh-set.
//
// NENHUMA alteração no price dispatcher (justtcg-price-refresh/justtcg-price-refresh-set)
// nesta rodada — arquivos daquelas duas Edge Functions permanecem intocados.

import { createClient } from "@supabase/supabase-js";
import {
  BOOTSTRAP_REQUEST_BUDGET,
  buildBootstrapSupabaseAdapter,
} from "../_shared/pricing-justtcg-bootstrap/mod.ts";
import { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { handleJusttcgSetBootstrapRequest } from "./handler.ts";
import { resolveJusttcgPricingSourceId } from "./pricing-source-lookup.ts";

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseServiceRoleKey) {
    console.error(
      "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes no ambiente da Edge Function justtcg-set-bootstrap.",
    );
    return Response.json(
      { success: false, error: "SERVER_MISCONFIGURED" },
      { status: 500 },
    );
  }
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  const port = buildBootstrapSupabaseAdapter(supabase);

  const pricingSourceId = await resolveJusttcgPricingSourceId(supabase);

  const expectedSecret = Deno.env.get("JUSTTCG_PRICE_REFRESH_SECRET") ?? null;
  const justtcgApiKey = Deno.env.get("JUSTTCG_API_KEY") ?? null;

  try {
    return await handleJusttcgSetBootstrapRequest(req, {
      expectedSecret,
      port,
      pricingSourceId,
      buildClient: () => {
        if (!justtcgApiKey) {
          console.error(
            "JUSTTCG_SET_BOOTSTRAP: JUSTTCG_API_KEY ausente no ambiente — a chamada à JustTCG falhará com AUTH_FAILURE.",
          );
        }
        return new JustTcgClient(
          justtcgApiKey ?? "",
          fetch,
          BOOTSTRAP_REQUEST_BUDGET,
        );
      },
    });
  } catch {
    console.error("JUSTTCG_SET_BOOTSTRAP_INTERNAL_ERROR_OUTER");
    return Response.json({ success: false, error: "INTERNAL_ERROR" }, {
      status: 500,
    });
  }
});
