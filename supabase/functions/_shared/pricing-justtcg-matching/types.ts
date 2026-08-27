// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-matching/types.ts
// Tipos puros do domínio de matching JustTCG — extraídos de scripts/sync-justtcg-pricing.ts
// (Incrementos P14.2/P14.4.1/P14.4.3/P14.4.4) para o Incremento P16.2 (Núcleo Compartilhado
// de Matching, 2026-08-25), reutilizável por este CLI e pela futura Edge Function de
// onboarding interativo de Sets (P16.3).
//
// Ponto único de verdade: scripts/sync-justtcg-pricing.ts (CLI de descoberta/matching) e a
// futura Edge Function de onboarding devem importar exclusivamente daqui — nenhum dos dois
// redeclara estes tipos. Mesma disciplina já aplicada a
// supabase/functions/_shared/pricing-justtcg/types.ts.
//
// Nenhum tipo aqui depende de Deno.env, SupabaseClient, fetch, filesystem ou qualquer
// runtime específico — só a forma dos dados de entrada/saída do matching em si.

import type { JustTcgCard, JustTcgSet } from "../pricing-justtcg/mod.ts";

// ----------------------------------------------------------------------------
// Resolução de Set (P14.2/P14.4.1)
// ----------------------------------------------------------------------------

export type SetTarget = {
  codigoMmkyu: string;
  releaseDateIso: string; // YYYY-MM-DD, comparado 1:1 contra card_set.release_date local
  overrideExternalSetId?: string; // compat P8 — suportado, não usado no piloto real de P14.2
};

export type SetMatchResult =
  | { status: "CONFIRMED"; set: JustTcgSet; method: string; evidence: Record<string, unknown> }
  | { status: "NOT_FOUND"; method: string; evidence: Record<string, unknown> }
  | { status: "AMBIGUOUS"; candidates: JustTcgSet[]; method: string; evidence: Record<string, unknown> };

// ----------------------------------------------------------------------------
// Classificação de Set para plano de expansão (P14.4.1/P14.4.3)
// ----------------------------------------------------------------------------

export type ExistingSetMappingLite = {
  cardSetId: string;
  matchStatus: string;
  externalSetId: string | null;
  externalSetName: string | null;
};

export type SetPlanClassification =
  | { status: "ALREADY_CONFIRMED_COMPLETE"; externalSetId: string; externalSetName: string | null; externalVariantsCount: number | null; reason: string }
  | { status: "ALREADY_CONFIRMED_INCOMPLETE"; externalSetId: string; externalSetName: string | null; externalVariantsCount: number | null; reason: string }
  | { status: "SAFE_CANDIDATE"; externalSetId: string; externalSetName: string; externalVariantsCount: number | null; reason: string }
  | { status: "AMBIGUOUS"; candidateCount: number; reason: string }
  | { status: "NOT_FOUND"; reason: string };

// ----------------------------------------------------------------------------
// Correlação de cartas (P14.2/P14.4.4)
// ----------------------------------------------------------------------------

// collector_total é OPCIONAL de propósito (nunca required) — ver isValidCollectorTotal() em
// normalize.ts. Ausência de campo e ausência de valor (undefined/null) são exatamente a
// mesma coisa para a regra "sem collector_total válido, não aplica o desempate".
export type LocalCard = { card_id: string; name: string; collector_number: string; collector_total?: number | null };

// P14.4.4 fix (filtro por denominador) — decomposição puramente sintática do número de
// coleção externo em (1) numerador normalizado, (2) denominador opcional e (3) o valor
// bruto preservado sem nenhuma transformação, só para evidência/auditoria. Ver
// parseCollectorNumberParts() em normalize.ts para a regra completa.
export type ParsedCollectorNumber = { numerator: string; denominator: number | null; raw: string };

export type CardMatchClassification = "SAFE" | "AMBIGUOUS" | "ABSENT";

export type CardMatchResult = {
  classification: CardMatchClassification;
  matched: JustTcgCard | null;
  method: string;
  evidence: Record<string, unknown>;
};

// ----------------------------------------------------------------------------
// Decisão de upsert de mapeamento (P14.2)
// ----------------------------------------------------------------------------

export type MappingRowLike = { id: string; match_status: string };
export type UpsertAction = "INSERTED" | "UPGRADED_TO_CONFIRMED" | "NOOP_ALREADY_CONFIRMED" | "NOOP_KEEP_CONFIRMED_DIVERGENT_INPUT" | "NOOP_SAME_STATUS";
