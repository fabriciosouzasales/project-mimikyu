// Project Mimikyu — supabase/functions/pricing-set-matching-preview/core.ts
// Núcleo de orquestração do preview de correspondência de Set (P16.3 — Descoberta de
// Correspondência, 2026-08-25). Reaproveita INTEGRALMENTE o núcleo de matching do P16.2
// (_shared/pricing-justtcg-matching/mod.ts) — resolveSetMatchV2() e
// normalizeJustTcgSets() são importados e usados byte a byte, exatamente como o CLI
// (scripts/sync-justtcg-pricing.ts) os usa em executeExpansionPlan(). Nenhuma regra de
// matching é reimplementada aqui (Seção 2 do pedido de Fabrício) — este módulo só decide
// QUANDO chamar o núcleo e como TRADUZIR o resultado para os estados de preview (types.ts).
//
// Zero escrita: nenhuma chamada a .insert/.update/.upsert/.delete/.rpc em lugar nenhum
// deste arquivo — só 3 leituras via SetMatchingPreviewPort e, no máximo, 1 requisição HTTP
// GET à JustTCG (client.get("/sets", ...)) através do JustTcgClient já existente
// (_shared/pricing-justtcg/mod.ts, mesmo cliente do CLI e do refresh diário).
//
// Ordem de decisão (curto-circuito, cada passo pode devolver sem gastar a requisição
// HTTP — Seção 14 do pedido, "evitar refetches/chamadas redundantes"):
//   1. Set existe? -> senão SET_NOT_FOUND (sem nenhuma leitura a mais).
//   2. Set elegível (game POKEMON, mesmo critério da migration 3950)? -> senão SET_NOT_ELIGIBLE.
//   3. Fonte ativa existe? -> senão NO_ACTIVE_SOURCE.
//   4. Já existe mapping CONFIRMED para este Set+fonte? -> ALREADY_CONFIRMED, sem tocar a
//      JustTCG (mapping PENDING/NOT_FOUND/REJECTED ou ausente NÃO encerra aqui — o preview
//      segue para uma descoberta fresca, mesmo comportamento de "Set sem correspondência
//      confirmada ainda").
//   5. Set sem release_date local -> NOT_FOUND (nunca chega a chamar a JustTCG — não há
//      base de comparação).
//   6. 1 única chamada GET /v1/sets?game=pokemon -> resolveSetMatchV2() decide
//      SAFE_CANDIDATE/AMBIGUOUS/NOT_FOUND.

import {
  GAME_CODE,
  type JustTcgClient,
} from "../_shared/pricing-justtcg/mod.ts";
import { normalizeJustTcgSets, resolveSetMatchV2 } from "../_shared/pricing-justtcg-matching/mod.ts";
import type { SetMatchingPreviewPort } from "./port.ts";
import type { JustTcgSet, LocalSetContext, PreviewResult } from "./types.ts";

const JUSTTCG_SOURCE_CODE = "JUSTTCG";

export async function previewSetMatching(
  port: SetMatchingPreviewPort,
  client: JustTcgClient,
  cardSetId: string,
): Promise<PreviewResult> {
  const cardSet = await port.findCardSet(cardSetId);
  if (!cardSet) {
    return { kind: "SET_NOT_FOUND" };
  }

  if (cardSet.gameCode !== "POKEMON") {
    return { kind: "SET_NOT_ELIGIBLE" };
  }

  const source = await port.findActivePricingSource(JUSTTCG_SOURCE_CODE);
  if (!source) {
    return { kind: "NO_ACTIVE_SOURCE" };
  }

  const local: LocalSetContext = {
    card_set_id: cardSet.id,
    card_set_code: cardSet.code,
    card_set_name: cardSet.name,
    release_date: cardSet.releaseDate,
    pricing_source_id: source.id,
    pricing_source_code: source.code,
  };

  const existing = await port.findExistingSetMapping(cardSet.id, source.id);
  if (existing && existing.matchStatus === "CONFIRMED") {
    return {
      kind: "ALREADY_CONFIRMED",
      local,
      external_set_id: existing.externalSetId ?? "",
      external_set_name: existing.externalSetName,
      last_checked_at: existing.lastCheckedAt,
    };
  }

  if (!cardSet.releaseDate) {
    return {
      kind: "NOT_FOUND",
      local,
      evidence: { reason: "SET_LOCAL_SEM_RELEASE_DATE" },
    };
  }

  const setsResult = await client.get<{ data: JustTcgSet[] }>("/sets", { game: GAME_CODE });

  if (setsResult.status === "AUTH_FAILURE") {
    return { kind: "JUSTTCG_AUTH_FAILURE" };
  }
  if (setsResult.status === "BUDGET_STOPPED") {
    return { kind: "JUSTTCG_BUDGET_STOPPED" };
  }
  if (setsResult.status === "TECHNICAL_FAILURE") {
    return { kind: "JUSTTCG_TECHNICAL_FAILURE", detail: setsResult.errorDetail };
  }

  const allSets = normalizeJustTcgSets(setsResult.data.data ?? []);
  const match = resolveSetMatchV2(
    { codigoMmkyu: cardSet.code, releaseDateIso: cardSet.releaseDate },
    allSets,
  );

  if (match.status === "CONFIRMED") {
    return {
      kind: "SAFE_CANDIDATE",
      local,
      candidate: {
        external_set_id: match.set.id,
        external_set_name: match.set.name,
        release_date_raw: match.set.release_date_raw ?? null,
        method: match.method,
        evidence: match.evidence,
      },
    };
  }

  if (match.status === "AMBIGUOUS") {
    return {
      kind: "AMBIGUOUS",
      local,
      candidates: match.candidates.map((c) => ({
        external_set_id: c.id,
        external_set_name: c.name,
        release_date_raw: c.release_date_raw ?? null,
      })),
      evidence: match.evidence,
    };
  }

  return { kind: "NOT_FOUND", local, evidence: match.evidence };
}
