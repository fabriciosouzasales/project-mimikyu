// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-matching/mapping-upsert.ts
// Upsert idempotente de mapeamentos — corrige a lacuna de P8 (insert-e-tolera nunca
// promovia PENDING/NOT_FOUND para CONFIRMED numa reexecução). Portado de
// scripts/sync-justtcg-pricing.ts (Incremento P14.2) para o Incremento P16.2 (Núcleo
// Compartilhado de Matching, 2026-08-25). Nenhuma mudança de comportamento nesta
// extração — mesma lógica, byte a byte.

import type { MappingRowLike, UpsertAction } from "./types.ts";

// Pura por design (recebe a linha existente, se houver, e a nova classificação; devolve
// só a decisão) — testável 100% offline, sem tocar o Supabase. Uma linha CONFIRMED
// nunca é rebaixada por uma nova classificação pior (ABSENT/AMBIGUOUS): fica preservada,
// só sinalizada como divergência para revisão humana, nunca reescrita silenciosamente.
export function decideMappingUpsert(existing: MappingRowLike | null, newStatus: "CONFIRMED" | "PENDING" | "NOT_FOUND"): UpsertAction {
  if (!existing) return "INSERTED";
  if (existing.match_status === "CONFIRMED") {
    return newStatus === "CONFIRMED" ? "NOOP_SAME_STATUS" : "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT";
  }
  if (newStatus === "CONFIRMED") return "UPGRADED_TO_CONFIRMED";
  return existing.match_status === newStatus ? "NOOP_SAME_STATUS" : "UPGRADED_TO_CONFIRMED"; // PENDING<->NOT_FOUND também é atualizado, sem novo status no schema
}
