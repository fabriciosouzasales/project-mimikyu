// Project Mimikyu — supabase/functions/_shared/pricing-justtcg-matching/mod.ts
// Ponto único de importação do núcleo compartilhado de matching JustTCG — Incremento P16.2
// (Núcleo Compartilhado de Matching, 2026-08-25), item do pedido de Fabrício: extrair a
// lógica pura de matching hoje existente em scripts/sync-justtcg-pricing.ts para um módulo
// reutilizável por este CLI e pela futura Edge Function de onboarding interativo de Sets
// (P16.3). Consumidores devem importar só por aqui — nunca os módulos internos
// diretamente. Mesmo padrão já usado em supabase/functions/_shared/pricing-justtcg/mod.ts
// e supabase/functions/_shared/pricing-ptax/mod.ts.
//
// Escopo deliberado deste núcleo (refatoração pura — nenhuma mudança de pesos, thresholds,
// heurísticas, critérios de igualdade, fallback, regras de ambiguidade, prioridade de
// candidatos, estados ou comportamento de upsert): resolução de identidade de Set
// (resolveSetMatchV2/classifySetForExpansionPlan), resolução de identidade de carta
// (buildExternalNumberIndex/isNameCompatible/classifyCardMatch) e a decisão de upsert de
// mapeamento (decideMappingUpsert) — as três frentes nomeadas no pedido de Fabrício. Ficaram
// FORA de propósito (não são "matching", são camadas adjacentes que continuam vivendo só no
// CLI): classifyInsertResult/classifyObservationWrite/computeFinalStatus (classificação de
// RESULTADO DE ESCRITA no Supabase, não de identidade), diagnoseExternalCoverage/
// logDryRunCardEvidence/planVariantProjection (diagnóstico e impressão de dry-run —
// logDryRunCardEvidence usa console.log, incompatível com um núcleo sem side effects), e
// buildExpansionWaves/buildBackfillWaves/estimateCardsPagesFromLocalCount (agrupamento em
// ondas para o modo --expansion-plan em lote, não a decisão de matching em si — a futura
// jornada interativa de onboarding de P16.3 trata um Set por vez). Ver relatório do
// Incremento P16.2 para o racional completo desta fronteira.

export type {
  CardMatchClassification,
  CardMatchResult,
  ExistingSetMappingLite,
  LocalCard,
  MappingRowLike,
  ParsedCollectorNumber,
  SetMatchResult,
  SetPlanClassification,
  SetTarget,
  UpsertAction,
} from "./types.ts";

export {
  isUsableExternalNumber,
  isValidCollectorTotal,
  normalizeExternalSetReleaseDate,
  normalizeJustTcgSets,
  normalizeName,
  normalizeNumber,
  parseCollectorNumberParts,
} from "./normalize.ts";

export { classifySetForExpansionPlan, resolveSetMatchV2 } from "./set-matching.ts";

export { buildExternalNumberIndex, classifyCardMatch, isNameCompatible } from "./card-matching.ts";

export { decideMappingUpsert } from "./mapping-upsert.ts";
