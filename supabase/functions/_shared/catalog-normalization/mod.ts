// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Ponto único de importação para as duas Edge Functions consumidoras:
// import-catalog-cards (resolução inicial) e revalidate-catalog-import-rows
// (revalidação de linhas em staging). Nenhuma das duas deve importar os
// módulos internos (category.ts, rarity.ts, resolve-row.ts,
// normalize-value.ts) diretamente — sempre por aqui, para que uma futura
// reorganização interna deste diretório não exija tocar nos chamadores.

export { normalizeExternalCatalogValue } from "./normalize-value.ts";
export { resolveCategory } from "./category.ts";
export { resolveRarity } from "./rarity.ts";
export type { RarityMappingLookup } from "./rarity.ts";
export { deriveCollectorOrder, resolveCatalogImportRow } from "./resolve-row.ts";
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
