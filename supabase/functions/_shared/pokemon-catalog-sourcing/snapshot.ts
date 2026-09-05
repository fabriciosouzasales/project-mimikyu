// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/snapshot.ts
// Montagem do snapshot determinístico (Seção 5) + payload guard (Seção 5.1).

import type {
  GenerationSnapshotRow,
  NationalPokedexEntrySnapshot,
  NationalPokedexSnapshot,
  PokemonCatalogSnapshot,
  RegionSnapshotRow,
  SpeciesSnapshotRow,
} from "./types.ts";

export const PAYLOAD_GUARD_MAX = 25_000;

// Ordenação determinística EXATA da Seção 5 — aplicada sempre antes de
// qualquer serialização/hash/persistência do snapshot:
//   regions: numeric(external_region_id) ASC
//   generations: numeric(external_generation_id) ASC
//   species: numeric(external_species_id) ASC
//   national_pokedex_entries: position_number ASC, numeric(external_species_id) ASC tie-breaker
export function buildDeterministicSnapshot(input: {
  regions: RegionSnapshotRow[];
  generations: GenerationSnapshotRow[];
  species: SpeciesSnapshotRow[];
  nationalPokedex: NationalPokedexSnapshot;
  nationalPokedexEntries: NationalPokedexEntrySnapshot[];
}): PokemonCatalogSnapshot {
  const regions = [...input.regions].sort(
    (a, b) => Number(a.external_region_id) - Number(b.external_region_id),
  );
  const generations = [...input.generations].sort(
    (a, b) =>
      Number(a.external_generation_id) - Number(b.external_generation_id),
  );
  const species = [...input.species].sort(
    (a, b) => Number(a.external_species_id) - Number(b.external_species_id),
  );
  const national_pokedex_entries = [...input.nationalPokedexEntries].sort(
    (a, b) => {
      if (a.position_number !== b.position_number) {
        return a.position_number - b.position_number;
      }
      return Number(a.external_species_id) - Number(b.external_species_id);
    },
  );

  return {
    regions,
    generations,
    species,
    national_pokedex: input.nationalPokedex,
    national_pokedex_entries,
  };
}

// Payload guard (Seção 5.1) — proteção técnica, NÃO cardinalidade de negócio.
export function computePayloadCount(snapshot: PokemonCatalogSnapshot): number {
  return (
    snapshot.regions.length +
    snapshot.generations.length +
    snapshot.species.length +
    snapshot.national_pokedex_entries.length +
    1 // representa national_pokedex
  );
}

export function isPayloadGuardExceeded(
  snapshot: PokemonCatalogSnapshot,
): boolean {
  return computePayloadCount(snapshot) > PAYLOAD_GUARD_MAX;
}

// Serialização determinística (Seção 5): "mesmas chaves, mesma ordem de
// chaves, mesmos valores para o mesmo estado externo". JSON.stringify
// preserva a ordem de inserção das chaves de um objeto literal — como todo
// objeto de linha deste módulo é sempre construído com a MESMA ordem de
// campos (ver acquisition.ts), a serialização é estável entre execuções para
// o mesmo estado de entrada, incluindo a ordenação de arrays acima.
export function serializeSnapshotDeterministically(
  snapshot: PokemonCatalogSnapshot,
): string {
  return JSON.stringify(snapshot);
}
