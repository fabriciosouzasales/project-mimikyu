// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Extraído de import-catalog-cards/services/normalize.ts
// (normalizeRarityLookupKey) em 2026-08-06.
//
// Deve produzir EXATAMENTE o mesmo resultado, para o mesmo texto de
// entrada, que public.normalize_external_catalog_value() (Query 2095):
// remove espaços nas pontas, remove acentos, maiúsculas, colapsa espaços
// internos em um único espaço. As duas implementações existem porque as
// Edge Functions rodam em Deno/TS e não têm como chamar unaccent() do
// Postgres por carta sem um round-trip de rede por linha — o núcleo do
// algoritmo (mesma sequência conceitual) é o que se mantém sincronizado
// entre as duas linguagens, não o código.
//
// Já era, na prática, a mesma técnica usada por normalizeRarityLookupKey
// desde 2026-08-01 (remediação do ME5): NFD + remoção de marcas diacríticas
// combinantes (intervalo Unicode U+0300–U+036F) é equivalente, para texto
// latino acentuado, ao dicionário padrão do unaccent do Postgres.
export function normalizeExternalCatalogValue(raw: string): string {
  return raw
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .toUpperCase()
    .replace(/\s+/g, " ");
}
