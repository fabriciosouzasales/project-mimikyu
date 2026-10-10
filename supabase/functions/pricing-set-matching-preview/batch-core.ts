// Project Mimikyu — supabase/functions/pricing-set-matching-preview/batch-core.ts
// Modo BATCH do preview de correspondência de Set (PRICING-MODULE-RECOVERY-01, Fase 3,
// 2026-10-10). Mesma regra de matching do modo single (resolveSetMatchV2 — release_date
// exata, nunca nome), aplicada a TODOS os Sets elegíveis sem mapeamento CONFIRMED com UMA
// única requisição GET /v1/sets à JustTCG (o modo single gastaria 1 requisição por Set).
//
// Zero escrita: só leituras via SetMatchingPreviewPort + 1 GET. A confirmação continua na
// RPC admin_confirm_pricing_set_mapping (chamada pela Server Action com a sessão do admin).
//
// Proteções além do modo single (o lote enxerga conflitos que o single não enxerga):
//   - TAKEN: o candidato externo já está CONFIRMED para outro Set local
//     (uq_pricing_set_mapping_source_external_confirmed impediria a confirmação).
//   - CONFLICT: dois ou mais Sets locais do lote apontam para o MESMO candidato seguro
//     (ex.: Set principal e Galeria de Treinador com a mesma data) — nenhum é seguro.
// Nos dois casos o item deixa de ser SAFE_CANDIDATE e vai para revisão manual.
// NOT_FOUND ganha sugestões por data próxima (±45 dias) só como ajuda à escolha manual —
// nunca como confirmação automática.

import { GAME_CODE, type JustTcgClient } from "../_shared/pricing-justtcg/mod.ts";
import { normalizeJustTcgSets, resolveSetMatchV2 } from "../_shared/pricing-justtcg-matching/mod.ts";
import type { SetMatchingPreviewPort } from "./port.ts";
import type { JustTcgSet } from "./types.ts";

const JUSTTCG_SOURCE_CODE = "JUSTTCG";
const NEAR_DATE_WINDOW_DAYS = 45;
const NEAR_DATE_MAX_SUGGESTIONS = 5;

export type BatchExternalSet = {
  external_set_id: string;
  external_set_name: string;
  release_date: string | null;
  /** Código do Set local que já usa este Set externo (CONFIRMED), ou null. */
  taken_by: string | null;
};

export type BatchItemState = "SAFE_CANDIDATE" | "AMBIGUOUS" | "CONFLICT" | "TAKEN" | "NOT_FOUND";

export type BatchItem = {
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  release_date: string | null;
  expansion_code: string;
  expansion_name: string;
  expansion_release_order: number | null;
  active_card_count: number;
  current_match_status: string | null;
  state: BatchItemState;
  /** Preenchido em SAFE_CANDIDATE (e em CONFLICT/TAKEN, para mostrar qual seria). */
  candidate: { external_set_id: string; external_set_name: string; release_date: string | null } | null;
  /** Candidatos de mesma data (AMBIGUOUS) ou de data próxima (NOT_FOUND). */
  suggestions: Array<{ external_set_id: string; external_set_name: string; release_date: string | null; days_apart: number }>;
  /** Para CONFLICT: os outros Sets locais que disputam o mesmo candidato. TAKEN: quem já usa. */
  conflict_with: string[];
};

export type BatchPreviewResult =
  | { kind: "NO_ACTIVE_SOURCE" }
  | { kind: "JUSTTCG_AUTH_FAILURE" }
  | { kind: "JUSTTCG_BUDGET_STOPPED" }
  | { kind: "JUSTTCG_TECHNICAL_FAILURE"; detail: string }
  | {
    kind: "OK";
    pricing_source_id: string;
    generated_at: string;
    items: BatchItem[];
    external_sets: BatchExternalSet[];
  };

function daysBetween(a: string, b: string): number {
  return Math.round(Math.abs(Date.parse(`${a}T00:00:00Z`) - Date.parse(`${b}T00:00:00Z`)) / 86_400_000);
}

export async function previewSetMatchingBatch(
  port: SetMatchingPreviewPort,
  client: JustTcgClient,
  now: () => Date = () => new Date(),
): Promise<BatchPreviewResult> {
  const source = await port.findActivePricingSource(JUSTTCG_SOURCE_CODE);
  if (!source) return { kind: "NO_ACTIVE_SOURCE" };

  const [targets, taken] = await Promise.all([
    port.listDiscoveryTargets(source.id),
    port.listConfirmedExternalSets(source.id),
  ]);

  const setsResult = await client.get<{ data: JustTcgSet[] }>("/sets", { game: GAME_CODE });
  if (setsResult.status === "AUTH_FAILURE") return { kind: "JUSTTCG_AUTH_FAILURE" };
  if (setsResult.status === "BUDGET_STOPPED") return { kind: "JUSTTCG_BUDGET_STOPPED" };
  if (setsResult.status === "TECHNICAL_FAILURE") {
    return { kind: "JUSTTCG_TECHNICAL_FAILURE", detail: setsResult.errorDetail };
  }

  const allSets = normalizeJustTcgSets(setsResult.data.data ?? []);
  const toSuggestion = (s: JustTcgSet, ref: string | null) => ({
    external_set_id: s.id,
    external_set_name: s.name,
    release_date: s.release_date ?? null,
    days_apart: ref && s.release_date ? daysBetween(ref, s.release_date) : 0,
  });

  const items: BatchItem[] = targets.map((t) => {
    const base = {
      card_set_id: t.cardSetId,
      card_set_code: t.cardSetCode,
      card_set_name: t.cardSetName,
      release_date: t.releaseDate,
      expansion_code: t.expansionCode,
      expansion_name: t.expansionName,
      expansion_release_order: t.expansionReleaseOrder,
      active_card_count: t.activeCardCount,
      current_match_status: t.currentMatchStatus,
      candidate: null,
      suggestions: [] as BatchItem["suggestions"],
      conflict_with: [] as string[],
    };

    const nearDate = () =>
      t.releaseDate
        ? allSets
          .filter((s) => s.release_date && daysBetween(t.releaseDate!, s.release_date) <= NEAR_DATE_WINDOW_DAYS)
          .map((s) => toSuggestion(s, t.releaseDate))
          .sort((a, b) => a.days_apart - b.days_apart || a.external_set_name.localeCompare(b.external_set_name))
          .slice(0, NEAR_DATE_MAX_SUGGESTIONS)
        : [];

    if (!t.releaseDate) return { ...base, state: "NOT_FOUND" as const };

    const match = resolveSetMatchV2({ codigoMmkyu: t.cardSetCode, releaseDateIso: t.releaseDate }, allSets);
    if (match.status === "CONFIRMED") {
      const candidate = { external_set_id: match.set.id, external_set_name: match.set.name, release_date: match.set.release_date ?? null };
      const takenBy = taken.get(match.set.id);
      if (takenBy) return { ...base, state: "TAKEN" as const, candidate, conflict_with: [takenBy], suggestions: nearDate() };
      return { ...base, state: "SAFE_CANDIDATE" as const, candidate };
    }
    if (match.status === "AMBIGUOUS") {
      return { ...base, state: "AMBIGUOUS" as const, suggestions: match.candidates.map((c) => toSuggestion(c, t.releaseDate)) };
    }
    return { ...base, state: "NOT_FOUND" as const, suggestions: nearDate() };
  });

  // CONFLICT: mesmo candidato seguro para 2+ Sets locais do lote.
  const byExternal = new Map<string, BatchItem[]>();
  for (const it of items) {
    if (it.state === "SAFE_CANDIDATE" && it.candidate) {
      const list = byExternal.get(it.candidate.external_set_id) ?? [];
      list.push(it);
      byExternal.set(it.candidate.external_set_id, list);
    }
  }
  for (const group of byExternal.values()) {
    if (group.length < 2) continue;
    for (const it of group) {
      it.state = "CONFLICT";
      it.conflict_with = group.filter((o) => o !== it).map((o) => o.card_set_code);
      it.suggestions = allSets
        .filter((s) => s.release_date && it.release_date && daysBetween(it.release_date, s.release_date) <= NEAR_DATE_WINDOW_DAYS)
        .map((s) => toSuggestion(s, it.release_date))
        .sort((a, b) => a.days_apart - b.days_apart || a.external_set_name.localeCompare(b.external_set_name))
        .slice(0, NEAR_DATE_MAX_SUGGESTIONS);
    }
  }

  const external_sets: BatchExternalSet[] = allSets
    .map((s) => ({
      external_set_id: s.id,
      external_set_name: s.name,
      release_date: s.release_date ?? null,
      taken_by: taken.get(s.id) ?? null,
    }))
    .sort((a, b) => (b.release_date ?? "").localeCompare(a.release_date ?? "") || a.external_set_name.localeCompare(b.external_set_name));

  return { kind: "OK", pricing_source_id: source.id, generated_at: now().toISOString(), items, external_sets };
}
