// Project Mimikyu — supabase/functions/pricing-set-matching-preview/types.ts
// Tipos do resultado de PREVIEW de correspondência de Set (P16.3 — Descoberta de
// Correspondência, 2026-08-25). "Preview": nenhum destes estados é persistido em
// pricing_set_mapping nesta rodada — ver core.ts e o cabeçalho de index.ts para a garantia
// de zero escrita.
//
// Nomenclatura deliberadamente DISTINTA de pricing_set_mapping.match_status
// (CONFIRMED/PENDING/NOT_FOUND/REJECTED, os 4 status reais gravados no banco) para nunca
// sugerir que um destes 4 estados já foi persistido:
//   SAFE_CANDIDATE  — a JustTCG devolveu exatamente 1 Set com a mesma release_date (mesmo
//                     critério de resolveSetMatchV2()==="CONFIRMED" no núcleo P16.2 — aqui
//                     renomeado para deixar claro que é uma SUGESTÃO, não uma confirmação).
//   AMBIGUOUS       — mais de um candidato com a mesma release_date; nunca escolhido
//                     automaticamente.
//   NOT_FOUND       — zero candidatos na JustTCG, ou Set local sem release_date.
//   ALREADY_CONFIRMED — já existe pricing_set_mapping CONFIRMED para este Set+fonte; a
//                     jornada de descoberta não teria efeito nenhum (nada a fazer).
// Mais os estados de entrada inválida (SET_NOT_FOUND/SET_NOT_ELIGIBLE/NO_ACTIVE_SOURCE) e
// de falha técnica da JustTCG (JUSTTCG_AUTH_FAILURE/JUSTTCG_TECHNICAL_FAILURE/
// JUSTTCG_BUDGET_STOPPED) — nunca confundidos com NOT_FOUND (Seção 12 do pedido de
// Fabrício: "distinguir sempre resultado válido de falha técnica").

import type { JustTcgSet } from "../_shared/pricing-justtcg/mod.ts";

export type LocalSetContext = {
  card_set_id: string;
  card_set_code: string;
  card_set_name: string;
  release_date: string | null;
  pricing_source_id: string;
  pricing_source_code: string;
};

export type SafeCandidate = {
  external_set_id: string;
  external_set_name: string;
  release_date_raw: string | null;
  method: string;
  evidence: Record<string, unknown>;
};

export type AmbiguousCandidate = {
  external_set_id: string;
  external_set_name: string;
  release_date_raw: string | null;
};

export type PreviewResult =
  | { kind: "SET_NOT_FOUND" }
  | { kind: "SET_NOT_ELIGIBLE" }
  | { kind: "NO_ACTIVE_SOURCE" }
  | {
    kind: "ALREADY_CONFIRMED";
    local: LocalSetContext;
    external_set_id: string;
    external_set_name: string | null;
    last_checked_at: string | null;
  }
  | { kind: "SAFE_CANDIDATE"; local: LocalSetContext; candidate: SafeCandidate }
  | {
    kind: "AMBIGUOUS";
    local: LocalSetContext;
    candidates: AmbiguousCandidate[];
    evidence: Record<string, unknown>;
  }
  | { kind: "NOT_FOUND"; local: LocalSetContext; evidence: Record<string, unknown> }
  | { kind: "JUSTTCG_AUTH_FAILURE" }
  | { kind: "JUSTTCG_BUDGET_STOPPED" }
  | { kind: "JUSTTCG_TECHNICAL_FAILURE"; detail: string };

export type { JustTcgSet };
