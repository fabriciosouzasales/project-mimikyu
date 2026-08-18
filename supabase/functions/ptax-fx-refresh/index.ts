// Project Mimikyu — supabase/functions/ptax-fx-refresh/index.ts
// Edge Function agendada: refresh da cotação PTAX (BCB_PTAX, USD->BRL) — Incremento
// P13.3 (2026-08-18).
//
// Esta função é o segundo chamador de _shared/pricing-ptax (o primeiro é o adapter
// manual scripts/sync-ptax-fx-rate.ts, Incremento P13.2) — nenhuma lógica de negócio é
// duplicada aqui: toda a decisão de requisição/resposta/orquestração mora em
// handler.ts (função pura, testável offline sem Deno) e no núcleo compartilhado
// (../_shared/pricing-ptax). Este arquivo só existe para AMARRAR as dependências reais
// (Deno.env, fetch global, cliente Supabase real) e entregá-las já resolvidas ao
// handler puro — mesmo padrão de "adapter fino" já usado pelo script manual.
//
// Identidade (ADR-031, preservada sem alteração): verify_jwt=false — necessário porque
// chaves sb_secret_.../sb_publishable_... não são JWT. A autorização real é um segredo
// dedicado desta função (PTAX_FX_REFRESH_SECRET, Function Secret do Supabase — nunca a
// publishable key), validado no header "apikey" por comparação manual em tempo
// constante (ver auth.ts). Não usa @supabase/server.
//
// Nota de arquitetura registrada nesta rodada (P13.3): o modelo completo do ADR-031
// prevê o segredo residindo em Supabase Vault (vault.create_secret) do lado Postgres,
// para uso futuro por pg_cron/pg_net ao montar a chamada HTTP agendada. Este round
// explicitamente NÃO mexe em Cron/Vault nem usa segredo real ("Limites" do escopo) — o
// que esta Edge Function consome é a METADE do lado da função: Deno.env.get(...) é o
// mecanismo padrão do Supabase para Function Secrets (definidos via `supabase secrets
// set`, também apoiados em Vault internamente), e é exatamente o que o handler
// precisará ler em produção independentemente de qual lado dispara a chamada (Cron via
// pg_net, ou qualquer outro agendador externo). Nenhuma peça da validação (header
// apikey + comparação constant-time) muda quando o lado Cron/Vault for implementado em
// uma rodada futura — só a origem do valor gravado em PTAX_FX_REFRESH_SECRET.
//
// Execução via Edge: triggered_by=SCHEDULED, confirmed_by=NULL sempre (nunca um admin
// humano por trás desta chamada) — ver run-lifecycle.ts (SyncRunTrigger).

import { createClient } from "@supabase/supabase-js";
import { buildPricingPtaxSupabaseAdapter } from "../_shared/pricing-ptax/mod.ts";
import { handlePtaxFxRefreshRequest } from "./handler.ts";

const REQUEST_TIMEOUT_MS = 15_000;

Deno.serve(async (req) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseServiceRoleKey) {
    console.error(
      "SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY ausentes no ambiente da Edge Function ptax-fx-refresh.",
    );
    return Response.json(
      { success: false, error: "SERVER_MISCONFIGURED" },
      { status: 500 },
    );
  }
  const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);
  // Adapter de infraestrutura construído UMA ÚNICA VEZ por invocação — implementa
  // PtaxSyncRunPort (run-lifecycle.ts) sobre o SupabaseClient real, reaproveitado para
  // tudo (repositório de taxas + ciclo de vida do run). Mesma função usada pelo
  // adapter manual (scripts/sync-ptax-fx-rate.ts) — nenhuma query duplicada.
  const port = buildPricingPtaxSupabaseAdapter(supabase);

  // PTAX_FX_REFRESH_SECRET: Function Secret dedicado desta Edge Function (nunca a
  // publishable/anon key). Ausente no ambiente => isAuthorized() sempre nega (ver
  // auth.ts) — nunca um "aberto por omissão".
  const expectedSecret = Deno.env.get("PTAX_FX_REFRESH_SECRET") ?? null;

  try {
    return await handlePtaxFxRefreshRequest(req, {
      expectedSecret,
      port,
      fetchImpl: fetch,
      waitImpl: (ms: number) =>
        new Promise((resolve) => setTimeout(resolve, ms)),
      now: new Date(),
      timeoutMs: REQUEST_TIMEOUT_MS,
    });
  } catch (error) {
    // Rede de segurança final — handlePtaxFxRefreshRequest já tem seu próprio
    // try/catch interno; isto só cobre uma falha totalmente inesperada fora dele.
    console.error(error);
    return Response.json({ success: false, error: "INTERNAL_ERROR" }, {
      status: 500,
    });
  }
});
