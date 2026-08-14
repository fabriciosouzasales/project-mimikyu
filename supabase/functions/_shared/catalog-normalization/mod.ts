// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Ponto único de importação para as Edge Functions consumidoras:
// import-catalog-cards (resolução inicial), revalidate-catalog-import-rows
// (revalidação de linhas em staging) e import-card-assets (padronização do
// collector_number usado no lookup de Cards para associação de imagem —
// 2026-08-13). Nenhuma delas deve importar os módulos internos (category.ts,
// rarity.ts, resolve-row.ts, normalize-value.ts) diretamente — sempre por
// aqui, para que uma futura reorganização interna deste diretório não exija
// tocar nos chamadores.

export { normalizeExternalCatalogValue } from "./normalize-value.ts";
export { resolveCategory } from "./category.ts";
export { resolveRarity } from "./rarity.ts";
export type { RarityMappingLookup } from "./rarity.ts";
export { deriveCollectorOrder, padCollectorNumber, resolveCatalogImportRow } from "./resolve-row.ts";
export type { ResolveCatalogRowInput } from "./resolve-row.ts";
export type {
  CardCategoryRow,
  CategoryConfidence,
  CategorySource,
  ExistingCard,
  NormalizedData,
  Rarity,
  RawCatalogCard,
  ResolvedCatalogRow,
} from "./types.ts";
