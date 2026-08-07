// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Reescrito em 2026-08-06 (cadastro self-service de Raridade) — substitui
// a antiga resolveRarityLookupKey/RARITY_NAME_ALIASES (hardcoded em
// import-catalog-cards/services/normalize.ts, aposentada nesta rodada) por
// resolução via rarity_external_mapping (Query 2096): dado real, editável
// sem deploy pela tela /catalogo/raridades, em vez de uma constante fixa no
// código-fonte.
//
// Cada raridade nova encontrada numa coleção antiga deixa de exigir uma
// alteração de código + deploy — só um cadastro em tela ("Resolver
// raridade"), que já revalida automaticamente as linhas afetadas (ver
// revalidate-catalog-import-rows).

import { normalizeExternalCatalogValue } from "./normalize-value.ts";
import type { Rarity } from "./types.ts";

// Chaveado por normalized_external_value (já calculado por
// public.normalize_external_catalog_value() no momento em que o
// mapeamento foi cadastrado — Query 2095/2101/2104) — nunca por
// rarity.name diretamente. Quem constrói este Map é a camada de acesso a
// dados de cada Edge Function (services/database.ts de import-catalog-
// cards, equivalente em revalidate-catalog-import-rows), lendo
// rarity_external_mapping filtrado por game_id + asset_source_id.
export type RarityMappingLookup = Map<string, Rarity>;

export function resolveRarity(
  rawValue: string | null | undefined,
  mappingByNormalizedValue: RarityMappingLookup,
): { rarity: Rarity | null; note: string | null } {
  if (!rawValue) {
    return { rarity: null, note: "RARIDADE_AUSENTE_NA_TCGDEX" };
  }

  const key = normalizeExternalCatalogValue(rawValue);
  const rarity = mappingByNormalizedValue.get(key) ?? null;

  if (!rarity) {
    return { rarity: null, note: `RARIDADE_NAO_MAPEADA: ${rawValue}` };
  }

  return { rarity, note: null };
}
