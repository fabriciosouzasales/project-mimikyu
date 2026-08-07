// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Extraído de import-catalog-cards/services/normalize.ts em 2026-08-06.
// Resolução de categoria (POKEMON/TRAINER/ENERGY) — não depende de
// nenhuma tabela de mapeamento (diferente de raridade, ver rarity.ts):
// a TCGdex já manda um valor de categoria estruturado, só a tradução
// EN/PT dos rótulos e o fallback heurístico vivem aqui.
//
// Compartilhado porque a revalidação também precisa resolver categoria a
// partir de raw_data já armazenado — mesma lógica, nunca duplicada entre
// import-catalog-cards e revalidate-catalog-import-rows.

import type { CategoryConfidence, CategorySource, RawCatalogCard } from "./types.ts";

// Inclui as duas formas (inglês e português) porque o valor bruto vem da
// própria TCGdex no idioma pedido (TCGDEX_LANGUAGE) — com "pt" ela devolve
// "Pokémon"/"Treinador"/"Energia", não "Pokemon"/"Trainer"/"Energy". Bug
// real, descoberto na remediação do ME5 (2026-08-01): só as chaves em
// inglês existiam, então toda carta Treinador caía no fallback heurístico
// (resolveCategoryByHeuristic) com confidence "LOW" — bloqueava a linha em
// NEEDS_REVIEW à toa (ver blockingIssues em resolve-row.ts).
const CATEGORY_BY_TCGDEX_VALUE: Record<string, string> = {
  Pokemon: "POKEMON",
  "Pokémon": "POKEMON",
  Trainer: "TRAINER",
  Treinador: "TRAINER",
  Energy: "ENERGY",
  Energia: "ENERGY",
};

export function resolveCategory(
  rawCard: RawCatalogCard,
): { category: string; source: CategorySource; confidence: CategoryConfidence } {
  const apiCategory = CATEGORY_BY_TCGDEX_VALUE[rawCard.category];
  if (apiCategory) {
    return { category: apiCategory, source: "API", confidence: "HIGH" };
  }
  return resolveCategoryByHeuristic(rawCard);
}

function resolveCategoryByHeuristic(
  rawCard: RawCatalogCard,
): { category: string; source: CategorySource; confidence: CategoryConfidence } {
  const name = rawCard.name ?? "";

  if (/^energia\b/i.test(name) || /^energy\b/i.test(name)) {
    return { category: "ENERGY", source: "ENERGY_PREFIX", confidence: "MEDIUM" };
  }
  if (Array.isArray(rawCard.dexId) && rawCard.dexId.length > 0) {
    return { category: "POKEMON", source: "POKEMON_MATCH", confidence: "MEDIUM" };
  }
  return { category: "TRAINER", source: "TRAINER_FALLBACK", confidence: "LOW" };
}
