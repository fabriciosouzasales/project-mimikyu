"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { traduzirErroPricing } from "@/lib/pricing/pricing-errors";

/**
 * Server Actions de Mapeamentos de Sets (Bloco 4 do Pricing Admin, migration
 * 3942) — mesmo padrão de `{ error, success? }` do resto do módulo. Dois
 * writes: `admin_update_pricing_set_mapping_details` (nome sempre editável;
 * `external_set_id` bloqueado por dependência, guardado no próprio SQL —
 * fonte única de verdade, `pricing_set_mapping_dependency_exists`) e
 * `admin_reclassify_pricing_set_mapping` (CONFIRMED↔REJECTED, motivo
 * obrigatório, mesma guarda de dependência na direção CONFIRMED→REJECTED).
 */

export type AtualizarDetalhesMapeamentoSetState = { error: string | null; success?: boolean };

export async function atualizarDetalhesMapeamentoSet(
  _prevState: AtualizarDetalhesMapeamentoSetState,
  formData: FormData,
): Promise<AtualizarDetalhesMapeamentoSetState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_update_pricing_set_mapping_details", {
    p_id: String(formData.get("id") ?? ""),
    p_external_set_id: String(formData.get("external_set_id") ?? ""),
    p_external_set_name: String(formData.get("external_set_name") ?? ""),
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/mapeamentos-sets");
  return { error: null, success: true };
}

export type ReclassificarMapeamentoSetState = { error: string | null; success?: boolean };

export async function reclassificarMapeamentoSet(
  _prevState: ReclassificarMapeamentoSetState,
  formData: FormData,
): Promise<ReclassificarMapeamentoSetState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reclassify_pricing_set_mapping", {
    p_id: String(formData.get("id") ?? ""),
    p_new_status: String(formData.get("new_status") ?? ""),
    p_reason: String(formData.get("reason") ?? ""),
  });

  if (error) {
    return { error: traduzirErroPricing(error.message) };
  }

  revalidatePath("/pricing/mapeamentos-sets");
  revalidatePath("/pricing/mapeamentos-cartas");
  return { error: null, success: true };
}

/**
 * Erros retornados pela Edge Function `pricing-set-matching-preview` (P16.3,
 * ver supabase/functions/pricing-set-matching-preview/handler.ts) — não são
 * exceções de RPC `CODIGO: texto` (formato de `traduzirErroPricing` acima),
 * são o campo `error` de um corpo JSON `{ success: false, error: "CODIGO" }`.
 * Mapa próprio, deliberadamente pequeno: só os códigos que este handler pode
 * de fato devolver.
 */
const PREVIEW_ERROR_MESSAGES: Record<string, string> = {
  SET_NOT_FOUND: "Este Set não foi encontrado — atualize a página e tente novamente.",
  MISSING_AUTHORIZATION: "Sessão inválida. Faça login novamente.",
  INVALID_USER_SESSION: "Sessão inválida. Faça login novamente.",
  FORBIDDEN_NOT_ADMIN: "Acesso restrito a administradores.",
  JUSTTCG_AUTH_FAILURE: "A fonte externa (JustTCG) recusou a credencial de acesso. Avise um administrador do sistema.",
  JUSTTCG_BUDGET_STOPPED: "Limite de requisições à fonte externa atingido nesta janela. Tente novamente em instantes.",
  JUSTTCG_TECHNICAL_FAILURE: "A fonte externa (JustTCG) não respondeu corretamente. Tente novamente em instantes.",
};

const PREVIEW_ERROR_FALLBACK = "Não foi possível concluir a consulta. Tente novamente em instantes.";

export type PreverCorrespondenciaSetLocal = {
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  releaseDate: string | null;
  pricingSourceId: string;
  pricingSourceCode: string;
};

export type PreverCorrespondenciaSetCandidate = {
  externalSetId: string;
  externalSetName: string;
  releaseDateRaw: string | null;
};

// P16.4 (Confirmação do Mapping) — `evidence` já existe na resposta real da Edge Function
// (SafeCandidate.evidence, ver pricing-set-matching-preview/types.ts) mas era descartado aqui
// no P16.3 (preview não persistia nada, então não precisava do rastro). Agora threaded até
// confirmarCorrespondenciaSet() para virar `match_evidence` no pricing_set_mapping — mesmo
// candidato que o admin viu no Dialog, sem reconstrução nem nova chamada à JustTCG.
type PreverCorrespondenciaSetCandidateEvidence = Record<string, unknown>;

export type PreverCorrespondenciaSetResult = {
  error: string | null;
  state:
    | "SET_NOT_ELIGIBLE"
    | "NO_ACTIVE_SOURCE"
    | "ALREADY_CONFIRMED"
    | "SAFE_CANDIDATE"
    | "AMBIGUOUS"
    | "NOT_FOUND"
    | null;
  local: PreverCorrespondenciaSetLocal | null;
  alreadyConfirmed: { externalSetId: string; externalSetName: string | null; lastCheckedAt: string | null } | null;
  candidate: (PreverCorrespondenciaSetCandidate & { method: string; evidence: PreverCorrespondenciaSetCandidateEvidence }) | null;
  candidates: PreverCorrespondenciaSetCandidate[] | null;
};

const EMPTY_PREVIEW_FIELDS = {
  local: null,
  alreadyConfirmed: null,
  candidate: null,
  candidates: null,
} satisfies Pick<PreverCorrespondenciaSetResult, "local" | "alreadyConfirmed" | "candidate" | "candidates">;

type RawSetMatchingPreviewCandidate = {
  external_set_id: string;
  external_set_name: string;
  release_date_raw: string | null;
};

/**
 * Fronteira única de chamada à Edge Function `pricing-set-matching-preview` (deployada,
 * verify_jwt=true + auth.getUser() + rpc('is_admin') no próprio index.ts da function) —
 * mesma fronteira de identidade de `iniciarImportacaoVariantes`
 * (catalogo/importar-variantes/actions.ts), access_token da sessão do próprio administrador
 * repassado no header Authorization, nunca lido/manipulado no browser. Extraída em P16.4
 * (hardening 2026-08-26) para ser reusada tanto pelo preview (`preverCorrespondenciaSet`,
 * mostra ao admin) quanto pela CONFIRMAÇÃO (`confirmarCorrespondenciaSet`, repreview
 * server-side imediatamente antes de persistir) — mesmo núcleo P16.2 por trás dos dois
 * caminhos, nunca uma segunda heurística. Somente leitura: zero `.insert/.update/.rpc` aqui.
 */
// `body` deliberadamente `any`: espelha o retorno solto de `response.json()` já usado neste
// módulo desde o P16.3 — o formato real é validado por `body.success`/`body.state` em cada
// chamador, não por um tipo estático (o contrato vem de `handler.ts` da Edge Function).
// Nota (2026-08-26): comentário `eslint-disable-next-line @typescript-eslint/no-explicit-any`
// removido daqui — `web/.eslintrc.json` só estende `next/core-web-vitals` (sem
// `next/typescript`), então essa regra nunca chega a ser carregada nesta config; o
// disable-comment apontava para uma regra inexistente e isso é erro de build no ESLint 9,
// não aviso ignorável (causa real da falha de deploy do Vercel neste commit).
async function fetchSetMatchingPreviewBody(cardSetId: string): Promise<{ ok: true; body: any } | { ok: false; error: string }> {
  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return { ok: false, error: "Sessão inválida. Faça login novamente." };
  }

  const functionUrl = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/pricing-set-matching-preview`;

  let response: Response;
  try {
    response = await fetch(functionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ card_set_id: cardSetId }),
      cache: "no-store",
    });
  } catch (fetchError) {
    const message = fetchError instanceof Error ? fetchError.message : "Falha de rede.";
    return { ok: false, error: `Falha ao consultar a fonte externa: ${message}` };
  }

  const body = await response.json().catch(() => null);

  if (!body || typeof body !== "object") {
    return { ok: false, error: PREVIEW_ERROR_FALLBACK };
  }

  if (body.success === false) {
    const code = typeof body.error === "string" ? body.error : "";
    return { ok: false, error: PREVIEW_ERROR_MESSAGES[code] ?? PREVIEW_ERROR_FALLBACK };
  }

  return { ok: true, body: body as Record<string, unknown> };
}

/**
 * P16.3 (Descoberta de Correspondência) — DESCOBRIR → CLASSIFICAR → APRESENTAR para um Set
 * UNMAPPED. Esta Server Action NUNCA escreve em nenhuma tabela — a function chamada é
 * somente leitura + 1 requisição HTTP à JustTCG (ver core.ts da function); persistência de
 * mapping é `confirmarCorrespondenciaSet`, abaixo.
 */
export async function preverCorrespondenciaSet(cardSetId: string): Promise<PreverCorrespondenciaSetResult> {
  if (!cardSetId) {
    return { error: "Set inválido.", state: null, ...EMPTY_PREVIEW_FIELDS };
  }

  const preview = await fetchSetMatchingPreviewBody(cardSetId);
  if (!preview.ok) {
    return { error: preview.error, state: null, ...EMPTY_PREVIEW_FIELDS };
  }
  const body = preview.body;

  const local: PreverCorrespondenciaSetLocal | null = body.local
    ? {
        cardSetId: body.local.card_set_id,
        cardSetCode: body.local.card_set_code,
        cardSetName: body.local.card_set_name,
        releaseDate: body.local.release_date,
        pricingSourceId: body.local.pricing_source_id,
        pricingSourceCode: body.local.pricing_source_code,
      }
    : null;

  switch (body.state) {
    case "SET_NOT_ELIGIBLE":
    case "NO_ACTIVE_SOURCE":
      return { error: null, state: body.state, ...EMPTY_PREVIEW_FIELDS };

    case "ALREADY_CONFIRMED":
      return {
        error: null,
        state: "ALREADY_CONFIRMED",
        local,
        alreadyConfirmed: {
          externalSetId: body.external_set_id,
          externalSetName: body.external_set_name ?? null,
          lastCheckedAt: body.last_checked_at ?? null,
        },
        candidate: null,
        candidates: null,
      };

    case "SAFE_CANDIDATE":
      return {
        error: null,
        state: "SAFE_CANDIDATE",
        local,
        candidate: {
          externalSetId: body.candidate?.external_set_id ?? "",
          externalSetName: body.candidate?.external_set_name ?? "",
          releaseDateRaw: body.candidate?.release_date_raw ?? null,
          method: body.candidate?.method ?? "",
          evidence:
            body.candidate?.evidence && typeof body.candidate.evidence === "object" ? body.candidate.evidence : {},
        },
        alreadyConfirmed: null,
        candidates: null,
      };

    case "AMBIGUOUS": {
      const rawCandidates = (body.candidates ?? []) as RawSetMatchingPreviewCandidate[];
      return {
        error: null,
        state: "AMBIGUOUS",
        local,
        candidates: rawCandidates.map((c) => ({
          externalSetId: c.external_set_id,
          externalSetName: c.external_set_name,
          releaseDateRaw: c.release_date_raw ?? null,
        })),
        alreadyConfirmed: null,
        candidate: null,
      };
    }

    case "NOT_FOUND":
      return { error: null, state: "NOT_FOUND", local, ...{ alreadyConfirmed: null, candidate: null, candidates: null } };

    default:
      return { error: PREVIEW_ERROR_FALLBACK, state: null, ...EMPTY_PREVIEW_FIELDS };
  }
}

/**
 * Erros de `admin_confirm_pricing_set_mapping` (P16.4, migration 3951) — mesmo formato
 * `CODIGO: texto` das demais RPCs administrativas (ver `pricing-errors.ts`), mas com um mapa
 * próprio: os códigos desta RPC ainda não existiam em `traduzirErroPricing`.
 */
const CONFIRM_ERROR_MESSAGES: Record<string, string> = {
  ADMIN_CONFIRM_PRICING_SET_MAPPING_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_CARD_SET: "Set inválido.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_SOURCE: "Fonte de preço inválida.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_MISSING_EXTERNAL_ID: "Identificador externo ausente — descubra a correspondência novamente.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_SET_NOT_FOUND: "Este Set não foi encontrado — atualize a página e tente novamente.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_SET_NOT_ELIGIBLE: "Este Set não é elegível para sincronização de preços.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_SOURCE_NOT_FOUND: "Fonte de preço não encontrada.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_SOURCE_NOT_ACTIVE: "Esta fonte de preço não está mais ativa.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_ALREADY_CONFIRMED_DIFFERENT_CANDIDATE:
    "Este Set+fonte já está confirmado com outra correspondência — use a edição de detalhes ou a reclassificação para trocar o vínculo.",
};

const CONFIRM_ERROR_FALLBACK = "Não foi possível confirmar a correspondência. Tente novamente em instantes.";

// Mensagens humanas para os estados de repreview que NUNCA levam a persistência (Seção 3 do
// hardening P16.4, 2026-08-26) — todos zero escrita, nenhum toca a RPC 3951.
const CONFIRM_REPREVIEW_BLOCKED_MESSAGES: Record<string, string> = {
  ALREADY_CONFIRMED: "Este Set já foi confirmado (por você ou outro administrador) — atualize a página.",
  AMBIGUOUS: "Mais de uma correspondência foi encontrada agora na fonte externa — reabra Sincronizar para revisar.",
  NOT_FOUND: "Nenhuma correspondência foi encontrada na fonte externa neste momento. Tente novamente mais tarde.",
  SET_NOT_ELIGIBLE: "Este Set não é elegível para sincronização de preços.",
  NO_ACTIVE_SOURCE: "Nenhuma fonte de preço está ativa no momento.",
};

export type ConfirmarCorrespondenciaSetState = { error: string | null; success?: boolean };

export type ConfirmarCorrespondenciaSetInput = {
  cardSetId: string;
  /**
   * Controle otimista apenas — o candidato que o admin viu no Dialog. NUNCA é a fonte de
   * verdade do que é persistido (ver hardening abaixo); serve só para detectar "a
   * correspondência sugerida mudou entre o preview e o clique em Confirmar" e recusar a
   * confirmação nesse caso, em vez de gravar silenciosamente um candidato diferente do que
   * o admin realmente aprovou visualmente.
   */
  expectedExternalSetId?: string;
};

/**
 * P16.4 (Confirmação do Mapping) — persiste, via `admin_confirm_pricing_set_mapping`
 * (migration 3951), a correspondência descoberta no preview P16.3 (SAFE_CANDIDATE).
 *
 * HARDENING (2026-08-26, revisão pré-aplicação da 3951): o browser deixou de ser autoridade
 * para `external_set_id`/`external_set_name`/`match_method`/`match_evidence`. Esta Server
 * Action agora REPETE o preview real (mesma `pricing-set-matching-preview`, mesmo núcleo
 * compartilhado P16.2 via `fetchSetMatchingPreviewBody` acima) imediatamente antes de
 * chamar a RPC — todo valor gravado vem exclusivamente desta resposta fresca do servidor,
 * nunca do `input` recebido do cliente. `input.expectedExternalSetId` é usado apenas como
 * checagem de "o candidato mudou desde que o admin olhou" — não como valor persistido.
 *
 * Qualquer resultado do repreview que não seja SAFE_CANDIDATE (ou que seja SAFE_CANDIDATE
 * com um `external_set_id` diferente do que o admin viu) é zero escrita: a RPC 3951 nem
 * chega a ser chamada. Quando o repreview É SAFE_CANDIDATE e bate com o esperado, a RPC 3951
 * continua sendo a autoridade transacional final (idempotência, bloqueio de overwrite,
 * proteção contra TOCTOU se outro admin confirmou entre o repreview e o INSERT/UPDATE).
 */
export async function confirmarCorrespondenciaSet(
  input: ConfirmarCorrespondenciaSetInput,
): Promise<ConfirmarCorrespondenciaSetState> {
  if (!input.cardSetId) {
    return { error: "Set inválido." };
  }

  const preview = await fetchSetMatchingPreviewBody(input.cardSetId);
  if (!preview.ok) {
    return { error: preview.error };
  }
  const body = preview.body;

  if (body.state !== "SAFE_CANDIDATE") {
    const message = CONFIRM_REPREVIEW_BLOCKED_MESSAGES[body.state as string];
    return { error: message ?? CONFIRM_ERROR_FALLBACK };
  }

  const freshExternalSetId = typeof body.candidate?.external_set_id === "string" ? body.candidate.external_set_id : "";
  const freshExternalSetName = typeof body.candidate?.external_set_name === "string" ? body.candidate.external_set_name : "";
  const freshMethod = typeof body.candidate?.method === "string" ? body.candidate.method : null;
  const freshEvidence =
    body.candidate?.evidence && typeof body.candidate.evidence === "object" ? body.candidate.evidence : {};

  if (!freshExternalSetId || !body.local?.card_set_id || !body.local?.pricing_source_id) {
    return { error: CONFIRM_ERROR_FALLBACK };
  }

  // "Candidato mudou entre preview e confirmação" (Seção 3) — só checado quando o cliente
  // enviou um valor esperado; sem ele, a confirmação segue com o candidato fresco do servidor
  // (mesmo assim NUNCA com dado vindo do cliente — só sem a checagem extra de "mudou").
  if (input.expectedExternalSetId && input.expectedExternalSetId !== freshExternalSetId) {
    return { error: "A correspondência sugerida mudou. Revise novamente antes de confirmar." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_confirm_pricing_set_mapping", {
    p_card_set_id: body.local.card_set_id,
    p_pricing_source_id: body.local.pricing_source_id,
    p_external_set_id: freshExternalSetId,
    p_external_set_name: freshExternalSetName,
    p_match_method: freshMethod,
    p_match_evidence: freshEvidence,
  });

  if (error) {
    const match = error.message.match(/^([A-Z][A-Z0-9_]*):\s*(.*)$/);
    const code = match?.[1];
    return { error: (code && CONFIRM_ERROR_MESSAGES[code]) ?? CONFIRM_ERROR_FALLBACK };
  }

  revalidatePath("/pricing/mapeamentos-sets");
  revalidatePath("/pricing");
  return { error: null, success: true };
}
