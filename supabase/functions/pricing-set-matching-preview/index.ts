// Project Mimikyu — supabase/functions/pricing-set-matching-preview/index.ts
// Edge Function de PREVIEW de correspondência de Set — P16.3 (Descoberta de Correspondência,
// 2026-08-25), item autorizado do Incremento P16 (Onboarding de Sets no Pricing). Recebe
// { card_set_id }, resolve o Set/fonte/mapping localmente, consulta a JustTCG (GET /v1/sets,
// no máximo 1 requisição) e classifica via o núcleo compartilhado de matching do P16.2
// (_shared/pricing-justtcg-matching) — NUNCA escreve em pricing_set_mapping,
// pricing_set_refresh_state, pricing_card_mapping, nem inicia nenhum refresh. Persistência
// fica para P16.4 (fora de escopo desta rodada — ver cabeçalho do pedido de Fabrício).
//
// Fronteira de identidade — mesmo padrão já em produção em
// import-catalog-cards/import-card-assets/import-card-variants (Finding 1 da auditoria de
// segurança do Catálogo Editorial, 2026-08-13, e Seção 3/13 do pedido de Fabrício: "seguir os
// padrões de segurança vigentes das Edge Functions Pricing"): verify_jwt=true
// (supabase/config.toml) garante um JWT assinado válido, mas não basta sozinho (pode ser só a
// anon key, sem usuário nenhum por trás). Um client escopado pelo JWT recebido no cabeçalho
// Authorization chama auth.getUser() para confirmar uma sessão real e rpc('is_admin') para
// confirmar o papel administrativo — só então o código segue para o client de service role
// (usado só para as 3 leituras de SetMatchingPreviewPort), que nunca recebe o JWT do
// chamador. service_role aqui é o mesmo modelo de confiança já usado pelas 3 Edge Functions
// citadas acima (identidade estabelecida ANTES, service_role só para o corpo já autorizado
// da operação) — não é uso indiscriminado (Seção 3 do pedido), é o padrão vigente do repo.
//
// Segredos consumidos (Function Secrets — nunca hardcoded, nunca logados):
//   SUPABASE_URL / SUPABASE_ANON_KEY — client de identidade (auth.getUser/is_admin).
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY — client de leitura (SetMatchingPreviewPort).
//   JUSTTCG_API_KEY — credencial real da JustTCG v1 (mesma variável já usada por
//   justtcg-price-refresh/justtcg-price-refresh-set).

import "@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "@supabase/supabase-js";
import { JustTcgClient, MAX_REQUESTS_PER_RUN } from "../_shared/pricing-justtcg/mod.ts";
import { buildSetMatchingPreviewSupabaseAdapter } from "./supabase-adapter.ts";
import { type AdminVerification, handlePricingSetMatchingPreviewRequest } from "./handler.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Client de serviço — único usado para as 3 leituras de SetMatchingPreviewPort. Nunca
// recebe o JWT do chamador (ver Fronteira de identidade acima).
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

async function verifyAdmin(req: Request): Promise<AdminVerification> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return { ok: false, status: 401, error: "MISSING_AUTHORIZATION" };
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    console.error("PRICING_SET_MATCHING_PREVIEW_INVALID_USER_SESSION:", userError);
    return { ok: false, status: 401, error: "INVALID_USER_SESSION" };
  }

  const { data: isAdminResult, error: isAdminError } = await userClient.rpc("is_admin");
  if (isAdminError || isAdminResult !== true) {
    console.error("PRICING_SET_MATCHING_PREVIEW_FORBIDDEN_NOT_ADMIN:", isAdminError);
    return { ok: false, status: 403, error: "FORBIDDEN_NOT_ADMIN" };
  }

  return { ok: true, userId: userData.user.id };
}

// P16.3 é matching de SET, não de carta (Seção 14 do pedido) — 1 única requisição HTTP por
// invocação (GET /v1/sets), nunca paginação de /cards. requestBudget=1 é um teto de
// segurança redundante (o núcleo já para depois de 1 chamada por desenho), nunca deixa esta
// function martelar a JustTCG mesmo num bug futuro de core.ts.
const PREVIEW_REQUEST_BUDGET = Math.min(1, MAX_REQUESTS_PER_RUN);

Deno.serve(async (req) => {
  const port = buildSetMatchingPreviewSupabaseAdapter(supabase);
  const justtcgApiKey = Deno.env.get("JUSTTCG_API_KEY") ?? null;

  try {
    return await handlePricingSetMatchingPreviewRequest(req, {
      verifyAdmin,
      port,
      buildClient: () => {
        if (!justtcgApiKey) {
          console.error(
            "PRICING_SET_MATCHING_PREVIEW: JUSTTCG_API_KEY ausente no ambiente — a chamada à JustTCG falhará com AUTH_FAILURE.",
          );
        }
        return new JustTcgClient(justtcgApiKey ?? "", fetch, PREVIEW_REQUEST_BUDGET);
      },
    });
  } catch {
    console.error("PRICING_SET_MATCHING_PREVIEW_INTERNAL_ERROR_OUTER");
    return Response.json({ success: false, error: "INTERNAL_ERROR" }, { status: 500 });
  }
});
