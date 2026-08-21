// Project Mimikyu — supabase/functions/justtcg-price-refresh/index.ts
// Edge Function agendada: refresh diário de preços JustTCG (JUSTTCG, cartas já
// confirmadas PRIMARY/ALTERNATE) — Incremento de Atualização Diária JustTCG
// (2026-08-21), item C.
//
// Mesmo padrão de "adapter fino" já usado por supabase/functions/ptax-fx-refresh/
// index.ts: nenhuma lógica de negócio mora aqui — só a amarração das dependências reais
// (Deno.env, SupabaseClient real, JustTcgClient real) entregues já resolvidas ao handler
// puro (handler.ts) e ao núcleo compartilhado (../_shared/pricing-justtcg-refresh e
// ../_shared/pricing-justtcg).
//
// Identidade: verify_jwt=false (chaves sb_secret_.../sb_publishable_... não são JWT) — a
// autorização real é um segredo dedicado desta função (JUSTTCG_PRICE_REFRESH_SECRET,
// Function Secret do Supabase — nunca a publishable key), validado no header "apikey" por
// comparação manual em tempo constante (ver auth.ts). Não usa @supabase/server.
//
// Segredos consumidos (Function Secrets — nunca hardcoded, nunca logados):
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — acesso ao banco (mesmo padrão de
//     ptax-fx-refresh e do CLI sync-justtcg-pricing.ts).
//   JUSTTCG_PRICE_REFRESH_SECRET — segredo dedicado desta função, comparado via apikey.
//   JUSTTCG_API_KEY — credencial real da JustTCG v1 (mesma variável já usada pelo CLI),
//     repassada ao JustTcgClient só no momento em que uma onda de fato precisa chamar a
//     JustTCG (handler.ts já valida método/auth/waveNumber antes de construir o cliente).
//
// Nota de arquitetura (mesmo precedente de ptax-fx-refresh, P13.3->P13.4): o desenho
// completo (Fabrício, item E) prevê 30 jobs pg_cron + pg_net + Vault chamando esta função
// via HTTP, um por onda (waveNumber 1-30 — elevado de 1-10 nesta rodada de correção pós-
// incidente, 2026-08-21: WAVE_PAGE_CAP caiu de 30 para 10 e MAX_WAVES subiu de 10 para 30,
// mesmo teto diário de 300 páginas, para manter cada execução bem abaixo do deadline
// interno de 110s — ver core.ts). Cron/Vault ficam para a migration do item E (3927),
// PROPOSTA e nunca aplicada nesta rodada.
//
// Execução via Edge: triggered_by=SCHEDULED, confirmed_by=NULL sempre (regra 8 de
// Fabrício) — garantido em nível de tipo por run-lifecycle.ts (PriceRefreshRunPort nunca
// aceita um parâmetro de trigger).

import { createClient } from "@supabase/supabase-js";
import { buildPricingJustTcgRefreshSupabaseAdapter } from "../_shared/pricing-justtcg-refresh/supabase-adapter.ts";
import { WAVE_PAGE_CAP } from "../_shared/pricing-justtcg-refresh/wave-plan.ts";
import { JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { handleJusttcgPriceRefreshRequest } from "./handler.ts";
import { resolveJusttcgPricingSourceId } from "./pricing-source-lookup.ts";

// Teto por onda (regra 5 de Fabrício: "Cada onda tem teto autoritativo de
// WAVE_PAGE_CAP requisições") — importado diretamente de wave-plan.ts (nunca uma
// constante local duplicada — correção desta rodada, 2026-08-21: uma constante local
// fixa em 30 teria ficado dessincronizada do WAVE_PAGE_CAP=10 pós-incidente, reabrindo a
// mesma janela de estouro de wall-clock). JustTcgClient aplica Math.min(requestBudget,
// MAX_REQUESTS_PER_RUN) internamente — nenhum orçamento de onda jamais afrouxa o teto de
// segurança global do cliente.
const WAVE_REQUEST_BUDGET = WAVE_PAGE_CAP;

// resolveJusttcgPricingSourceId foi extraída para pricing-source-lookup.ts (correção de
// segurança, 2026-08-21, 2ª rodada) — o `Deno.serve(...)` abaixo torna este módulo
// impróprio para import direto em teste offline; a função em si vive num módulo puro e sem
// esse efeito colateral, testado em pricing-source-lookup.test.ts.

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseServiceRoleKey) {
    console.error(
      "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes no ambiente da Edge Function justtcg-price-refresh.",
    );
    return Response.json(
      { success: false, error: "SERVER_MISCONFIGURED" },
      { status: 500 },
    );
  }
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  // Adapter de infraestrutura construído UMA ÚNICA VEZ por invocação — implementa
  // PriceRefreshRunPort sobre o SupabaseClient real, reaproveitado por todo o núcleo
  // (core.ts) para leitura de candidatos/identidades e escrita de produtos/observações/
  // telemetria/ciclo de vida do run.
  const port = buildPricingJustTcgRefreshSupabaseAdapter(supabase);

  const pricingSourceId = await resolveJusttcgPricingSourceId(supabase);

  // JUSTTCG_PRICE_REFRESH_SECRET: Function Secret dedicado desta Edge Function (nunca a
  // publishable/anon key). Ausente no ambiente => isAuthorized() sempre nega (ver
  // auth.ts) — nunca um "aberto por omissão".
  const expectedSecret = Deno.env.get("JUSTTCG_PRICE_REFRESH_SECRET") ?? null;
  // JUSTTCG_API_KEY: mesma credencial já usada pelo CLI (scripts/sync-justtcg-pricing.ts)
  // — lida aqui só para ser repassada à fábrica do cliente; handler.ts só invoca a
  // fábrica depois de método/auth/waveNumber já validados.
  const justtcgApiKey = Deno.env.get("JUSTTCG_API_KEY") ?? null;

  try {
    return await handleJusttcgPriceRefreshRequest(req, {
      expectedSecret,
      port,
      pricingSourceId,
      buildClient: () => {
        if (!justtcgApiKey) {
          // Defensivo — handler.ts só chama buildClient() depois de validar
          // método/auth/waveNumber; se chegou aqui sem a credencial, é erro de
          // configuração do ambiente, nunca do chamador HTTP. JustTcgClient exige uma
          // apiKey não-vazia por assinatura; um valor ausente vira uma string vazia
          // deliberada, que a própria JustTCG rejeitará como 401 (AUTH_FAILURE) —
          // nunca um crash não tratado, e nunca um log da chave (que aqui nem existe).
          console.error(
            "JUSTTCG_PRICE_REFRESH: JUSTTCG_API_KEY ausente no ambiente — a chamada à JustTCG falhará com AUTH_FAILURE.",
          );
        }
        return new JustTcgClient(
          justtcgApiKey ?? "",
          fetch,
          WAVE_REQUEST_BUDGET,
        );
      },
    });
  } catch {
    // Rede de segurança final — handleJusttcgPriceRefreshRequest já tem seu próprio
    // try/catch interno (com logger sanitizado próprio, ver handler.ts); isto só cobre uma
    // falha totalmente inesperada fora dele (ex.: a própria fábrica de dependências acima
    // lançando antes de entrar no handler). Mesma correção de segurança do handler.ts:
    // `catch` sem binding — nenhum `Error`/`error.message`/`error.stack` cru chega ao
    // logger a partir daqui, só um código fixo.
    console.error("JUSTTCG_PRICE_REFRESH_INTERNAL_ERROR_OUTER");
    return Response.json({ success: false, error: "INTERNAL_ERROR" }, {
      status: 500,
    });
  }
});
