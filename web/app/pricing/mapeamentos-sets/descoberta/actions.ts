"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

/**
 * Descoberta de correspondências em lote (PRICING-MODULE-RECOVERY-01, Fase 3, 2026-10-10).
 *
 * - `descobrirCorrespondenciasEmLote`: 1 chamada à Edge `pricing-set-matching-preview` em modo
 *   `batch` (1 única requisição GET /sets à JustTCG para todos os Sets sem correspondência).
 *   Somente leitura.
 * - `confirmarCorrespondenciasEmLote`: REPETE a descoberta no servidor (mais 1 requisição) e só
 *   confirma, via `admin_confirm_pricing_set_mapping` com a sessão do admin, as decisões que
 *   continuam válidas na resposta fresca. O browser nunca é autoridade do que é gravado: o nome
 *   externo, método e evidência vêm da resposta do servidor; o cliente só indica Set + id externo
 *   escolhido. Falha de um item não interrompe os demais (resultado por item).
 */

export type LoteEstado = "SAFE_CANDIDATE" | "AMBIGUOUS" | "CONFLICT" | "TAKEN" | "NOT_FOUND";

export type LoteSugestao = {
  externalSetId: string;
  externalSetName: string;
  releaseDate: string | null;
  daysApart: number;
};

export type LoteItem = {
  cardSetId: string;
  cardSetCode: string;
  cardSetName: string;
  releaseDate: string | null;
  expansionCode: string;
  expansionName: string;
  expansionReleaseOrder: number | null;
  activeCardCount: number;
  state: LoteEstado;
  candidate: { externalSetId: string; externalSetName: string; releaseDate: string | null } | null;
  suggestions: LoteSugestao[];
  conflictWith: string[];
};

export type LoteSetExterno = {
  externalSetId: string;
  externalSetName: string;
  releaseDate: string | null;
  takenBy: string | null;
};

export type DescobertaLoteResult =
  | { ok: true; generatedAt: string; items: LoteItem[]; externalSets: LoteSetExterno[] }
  | { ok: false; error: string };

const ERROR_MESSAGES: Record<string, string> = {
  MISSING_AUTHORIZATION: "Sessão inválida. Faça login novamente.",
  INVALID_USER_SESSION: "Sessão inválida. Faça login novamente.",
  FORBIDDEN_NOT_ADMIN: "Acesso restrito a administradores.",
  JUSTTCG_AUTH_FAILURE: "A JustTCG recusou a credencial de acesso. Avise um administrador do sistema.",
  JUSTTCG_BUDGET_STOPPED: "Limite de requisições à JustTCG atingido nesta janela. Tente novamente em instantes.",
  JUSTTCG_TECHNICAL_FAILURE: "A JustTCG não respondeu corretamente. Tente novamente em instantes.",
};
const FALLBACK = "Não foi possível consultar a JustTCG agora. Tente novamente em instantes.";

// Formato solto validado campo a campo abaixo (contrato em handler.ts da Edge). Sem eslint-disable:
// a regra no-explicit-any não está carregada nesta config (ver nota em ../actions.ts).
type RawBody = any;

async function fetchBatchBody(): Promise<{ ok: true; body: RawBody } | { ok: false; error: string }> {
  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: "Sessão inválida. Faça login novamente." };

  let response: Response;
  try {
    response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/pricing-set-matching-preview`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${session.access_token}` },
      body: JSON.stringify({ mode: "batch" }),
      cache: "no-store",
    });
  } catch {
    return { ok: false, error: FALLBACK };
  }
  const body = await response.json().catch(() => null);
  if (!body || typeof body !== "object") return { ok: false, error: FALLBACK };
  if (body.success === false) return { ok: false, error: ERROR_MESSAGES[String(body.error)] ?? FALLBACK };
  if (body.state === "NO_ACTIVE_SOURCE") return { ok: false, error: "A fonte JustTCG não está ativa." };
  if (body.state !== "BATCH" || !Array.isArray(body.items)) return { ok: false, error: FALLBACK };
  return { ok: true, body };
}

function mapBody(body: RawBody): Extract<DescobertaLoteResult, { ok: true }> {
  const items: LoteItem[] = (body.items as any[]).map((i) => ({
    cardSetId: String(i.card_set_id),
    cardSetCode: String(i.card_set_code),
    cardSetName: String(i.card_set_name),
    releaseDate: i.release_date ?? null,
    expansionCode: String(i.expansion_code ?? ""),
    expansionName: String(i.expansion_name ?? ""),
    expansionReleaseOrder: typeof i.expansion_release_order === "number" ? i.expansion_release_order : null,
    activeCardCount: Number(i.active_card_count ?? 0),
    state: i.state as LoteEstado,
    candidate: i.candidate
      ? {
          externalSetId: String(i.candidate.external_set_id),
          externalSetName: String(i.candidate.external_set_name),
          releaseDate: i.candidate.release_date ?? null,
        }
      : null,
    suggestions: ((i.suggestions ?? []) as any[]).map((s) => ({
      externalSetId: String(s.external_set_id),
      externalSetName: String(s.external_set_name),
      releaseDate: s.release_date ?? null,
      daysApart: Number(s.days_apart ?? 0),
    })),
    conflictWith: Array.isArray(i.conflict_with) ? i.conflict_with.map(String) : [],
  }));
  const externalSets: LoteSetExterno[] = ((body.external_sets ?? []) as any[]).map((e) => ({
    externalSetId: String(e.external_set_id),
    externalSetName: String(e.external_set_name),
    releaseDate: e.release_date ?? null,
    takenBy: e.taken_by ?? null,
  }));
  return { ok: true, generatedAt: String(body.generated_at ?? new Date().toISOString()), items, externalSets };
}

export async function descobrirCorrespondenciasEmLote(): Promise<DescobertaLoteResult> {
  const res = await fetchBatchBody();
  if (!res.ok) return res;
  return mapBody(res.body);
}

export type DecisaoLote = { cardSetId: string; externalSetId: string };

export type ResultadoItemLote = {
  cardSetId: string;
  cardSetCode: string;
  ok: boolean;
  /** Mensagem humana quando `ok=false`. */
  error?: string;
};

export type ConfirmacaoLoteResult =
  | { ok: true; results: ResultadoItemLote[]; confirmed: number; failed: number }
  | { ok: false; error: string };

const MAX_DECISOES = 200;

const RPC_ERRORS: Record<string, string> = {
  ADMIN_CONFIRM_PRICING_SET_MAPPING_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_SET_NOT_ELIGIBLE: "Set não elegível para preços.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_SOURCE_NOT_ACTIVE: "A fonte JustTCG não está mais ativa.",
  ADMIN_CONFIRM_PRICING_SET_MAPPING_ALREADY_CONFIRMED_DIFFERENT_CANDIDATE: "Já confirmado com outro Set externo.",
};

export async function confirmarCorrespondenciasEmLote(decisoes: DecisaoLote[]): Promise<ConfirmacaoLoteResult> {
  if (!Array.isArray(decisoes) || decisoes.length === 0) return { ok: false, error: "Nenhum Set selecionado." };
  if (decisoes.length > MAX_DECISOES) return { ok: false, error: `Confirme no máximo ${MAX_DECISOES} Sets por vez.` };

  const fresh = await fetchBatchBody();
  if (!fresh.ok) return fresh;
  const snapshot = mapBody(fresh.body);
  const itemById = new Map(snapshot.items.map((i) => [i.cardSetId, i]));
  const externalById = new Map(snapshot.externalSets.map((e) => [e.externalSetId, e]));
  const pricingSourceId = String(fresh.body.pricing_source_id ?? "");
  if (!pricingSourceId) return { ok: false, error: FALLBACK };

  // Um Set externo só pode ir para um Set local por lote (o banco também garante via índice único).
  const externalCount = new Map<string, number>();
  for (const d of decisoes) externalCount.set(d.externalSetId, (externalCount.get(d.externalSetId) ?? 0) + 1);

  const supabase = await createClient();
  const results: ResultadoItemLote[] = [];

  for (const d of decisoes) {
    const item = itemById.get(d.cardSetId);
    const code = item?.cardSetCode ?? "?";
    if (!item) {
      results.push({ cardSetId: d.cardSetId, cardSetCode: code, ok: false, error: "Já tem correspondência ou não está mais disponível." });
      continue;
    }
    const external = externalById.get(d.externalSetId);
    if (!external) {
      results.push({ cardSetId: d.cardSetId, cardSetCode: code, ok: false, error: "Set externo não existe mais na JustTCG." });
      continue;
    }
    if (external.takenBy) {
      results.push({ cardSetId: d.cardSetId, cardSetCode: code, ok: false, error: `Set externo já usado por ${external.takenBy}.` });
      continue;
    }
    if ((externalCount.get(d.externalSetId) ?? 0) > 1) {
      results.push({ cardSetId: d.cardSetId, cardSetCode: code, ok: false, error: "O mesmo Set externo foi escolhido para mais de um Set." });
      continue;
    }

    const isSafe = item.state === "SAFE_CANDIDATE" && item.candidate?.externalSetId === d.externalSetId;
    const method = isSafe ? "RELEASE_DATE_EXACT_MATCH" : "ADMIN_MANUAL_SELECTION";
    const evidence = {
      flow: "BATCH_DISCOVERY",
      preview_state: item.state,
      preview_generated_at: snapshot.generatedAt,
      release_date_local: item.releaseDate,
      external_set_id: external.externalSetId,
      external_set_name: external.externalSetName,
      external_release_date: external.releaseDate,
    };

    const { error } = await supabase.rpc("admin_confirm_pricing_set_mapping", {
      p_card_set_id: item.cardSetId,
      p_pricing_source_id: pricingSourceId,
      p_external_set_id: external.externalSetId,
      p_external_set_name: external.externalSetName,
      p_match_method: method,
      p_match_evidence: evidence,
    });
    if (error) {
      const codeMatch = error.message.match(/^([A-Z][A-Z0-9_]*):/);
      const msg =
        (codeMatch?.[1] ? RPC_ERRORS[codeMatch[1]] : undefined) ||
        (error.code === "23505" ? "Set externo já confirmado para outro Set." : "Não foi possível confirmar.");
      results.push({ cardSetId: d.cardSetId, cardSetCode: code, ok: false, error: msg });
      continue;
    }
    results.push({ cardSetId: d.cardSetId, cardSetCode: code, ok: true });
  }

  const confirmed = results.filter((r) => r.ok).length;
  if (confirmed > 0) {
    revalidatePath("/pricing/mapeamentos-sets");
    revalidatePath("/pricing");
  }
  return { ok: true, results, confirmed, failed: results.length - confirmed };
}
