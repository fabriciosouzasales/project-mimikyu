// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-matching/set-matching.ts
// Resolução de correspondência de Set — release_date exato, nunca nome. Portado de
// scripts/sync-justtcg-pricing.ts (Incrementos P14.2/P14.4.1/P14.4.3) para o Incremento
// P16.2 (Núcleo Compartilhado de Matching, 2026-08-25). Nenhuma mudança de comportamento
// nesta extração — mesma lógica, byte a byte (pesos/thresholds/regras de ambiguidade
// preservados exatamente).

import type { JustTcgSet } from "../pricing-justtcg/mod.ts";
import type { ExistingSetMappingLite, SetMatchResult, SetPlanClassification, SetTarget } from "./types.ts";

// Sinal automatizado: release_date exata. Nome nunca é usado para casar Sets — nenhuma
// tabela local tem um nome em inglês confiável (nenhuma tabela local — card_set/expansion/
// game — guarda um nome em inglês; os nomes são todos pt-BR). Zero candidatos -> NOT_FOUND;
// mais de um -> AMBIGUOUS (nunca confirmado automaticamente); exatamente um -> CONFIRMED.
export function resolveSetMatchV2(target: SetTarget, allSets: JustTcgSet[]): SetMatchResult {
  if (target.overrideExternalSetId) {
    const override = allSets.find((s) => s.id === target.overrideExternalSetId);
    if (override) {
      return { status: "CONFIRMED", set: override, method: "OVERRIDE_MANUAL", evidence: { external_set_id: override.id, external_set_name: override.name } };
    }
    return { status: "NOT_FOUND", method: "OVERRIDE_NAO_CONFIRMADO_NA_RESPOSTA_ATUAL", evidence: { esperado: target.overrideExternalSetId } };
  }

  const candidates = allSets.filter((s) => s.release_date === target.releaseDateIso);
  if (candidates.length === 0) {
    return { status: "NOT_FOUND", method: "RELEASE_DATE_EXACT_MATCH", evidence: { release_date_esperada: target.releaseDateIso, candidatos_encontrados: 0 } };
  }
  if (candidates.length > 1) {
    return {
      status: "AMBIGUOUS",
      candidates,
      method: "RELEASE_DATE_EXACT_MATCH",
      evidence: {
        release_date_esperada: target.releaseDateIso,
        candidatos: candidates.map((c) => ({ id: c.id, name: c.name, release_date_raw: c.release_date_raw ?? null })),
      },
    };
  }
  return {
    status: "CONFIRMED",
    set: candidates[0],
    method: "RELEASE_DATE_EXACT_MATCH",
    evidence: {
      release_date_esperada: target.releaseDateIso,
      external_set_id: candidates[0].id,
      external_set_name: candidates[0].name,
      external_set_release_date_raw: candidates[0].release_date_raw ?? null,
    },
  };
}

// Pura — mesmo sinal primário automatizado já validado em resolveSetMatchV2() (P14.2):
// release_date normalizada é a ÚNICA evidência usada para confirmar automaticamente. Nome
// nunca é fundamento isolado. Um mapping já CONFIRMED é sempre preservado, nunca reavaliado
// contra allExternalSets — ALREADY_CONFIRMED_COMPLETE/INCOMPLETE é decidido só pelo estado
// local (mapping do Set + cobertura agregada de cartas), antes de qualquer comparação de data.
//
// P14.4.3: "Set confirmado" deixou de implicar "cobertura completa" — coverage.mappedCards
// conta QUALQUER pricing_card_mapping existente (CONFIRMED, PENDING ou NOT_FOUND contam como
// "mapeada" — o gap real é ausência TOTAL de mapping); >= (não ===) é deliberado, tolerante a
// mappedCards nunca poder superar localCardCount em condições normais, mas sem quebrar se
// algum dia divergir por um instante entre leituras.
export function classifySetForExpansionPlan(
  local: { releaseDateIso: string | null; localCardCount: number },
  existingMapping: ExistingSetMappingLite | null,
  allExternalSets: JustTcgSet[],
  coverage: { mappedCards: number } | null,
): SetPlanClassification {
  if (existingMapping && existingMapping.matchStatus === "CONFIRMED") {
    const knownExternal = existingMapping.externalSetId ? allExternalSets.find((s) => s.id === existingMapping.externalSetId) : undefined;
    const mappedCards = coverage?.mappedCards ?? 0;
    const isComplete = mappedCards >= local.localCardCount;
    return {
      status: isComplete ? "ALREADY_CONFIRMED_COMPLETE" : "ALREADY_CONFIRMED_INCOMPLETE",
      externalSetId: existingMapping.externalSetId ?? "",
      externalSetName: existingMapping.externalSetName,
      externalVariantsCount: knownExternal?.variants_count ?? null,
      reason: isComplete ? "MAPPING_JA_CONFIRMED_COBERTURA_COMPLETA" : "MAPPING_JA_CONFIRMED_COBERTURA_INCOMPLETA",
    };
  }

  if (!local.releaseDateIso) {
    return { status: "NOT_FOUND", reason: "SET_LOCAL_SEM_RELEASE_DATE" };
  }

  const candidates = allExternalSets.filter((s) => s.release_date === local.releaseDateIso);
  if (candidates.length === 0) {
    return { status: "NOT_FOUND", reason: "RELEASE_DATE_SEM_CORRESPONDENCIA_EXTERNA" };
  }
  if (candidates.length > 1) {
    return { status: "AMBIGUOUS", candidateCount: candidates.length, reason: "RELEASE_DATE_COM_MULTIPLOS_CANDIDATOS" };
  }
  return {
    status: "SAFE_CANDIDATE",
    externalSetId: candidates[0].id,
    externalSetName: candidates[0].name,
    externalVariantsCount: candidates[0].variants_count ?? null,
    reason: "RELEASE_DATE_EXACT_MATCH_UNICO",
  };
}
