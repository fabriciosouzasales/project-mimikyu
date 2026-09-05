// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/cross-check.ts
// Cross-check nacional OBRIGATÓRIO (Seção 4.3 do contrato) — responsabilidade
// EXCLUSIVA do script Deno, ANTES da construção do snapshot. O PLAN (Query 6104)
// não tenta reprovar isso — o contrato é explícito: "nenhuma checagem [no PLAN]
// finge provar algo que não está representado no JSON recebido".

import type { PokeApiPokedexEntry, PokeApiSpeciesDetail } from "./types.ts";
import { extractIdFromUrl } from "./normalize.ts";

export type CrossCheckFailureReason =
  | "NATIONAL_ENTRY_MISSING"
  | "NATIONAL_ENTRY_DUPLICATE"
  | "NATIONAL_ENTRY_NUMBER_MISMATCH"
  | "SPECIES_NOT_IN_NATIONAL_SET"
  | "NATIONAL_ENTRY_NOT_IN_SPECIES_SET"
  // REVISION-03 (Bloco 2, S=P exato) — nunca deixar Map/Set mascarar
  // duplicidade: estas 3 causas eram engolidas silenciosamente antes desta
  // correção (a última sobrescrita "vencia" sem registrar falha alguma).
  | "SPECIES_EXTERNAL_ID_DUPLICATE"
  | "NATIONAL_ENTRY_SPECIES_ID_DUPLICATE"
  | "NATIONAL_ENTRY_SPECIES_ID_UNEXTRACTABLE";

export interface CrossCheckFailure {
  externalSpeciesId: string;
  reason: CrossCheckFailureReason;
  detail: string;
}

export interface CrossCheckResult {
  ok: boolean;
  failures: CrossCheckFailure[];
}

// Para CADA Species descoberta em /pokemon-species/, pokedex_numbers[] deve
// conter EXATAMENTE UMA entrada onde pokedex.name = 'national', com
// entry_number IDÊNTICO ao entry_number correspondente em
// /pokedex/national.pokemon_entries[] (autoridade) — para 100% das Species.
// Também valida S = P (Seção 4.3): o conjunto de Species descobertas deve
// coincidir exatamente com o conjunto de entries do National Pokédex.
export function crossCheckNationalPokedex(
  speciesDetails: PokeApiSpeciesDetail[],
  nationalEntries: PokeApiPokedexEntry[],
): CrossCheckResult {
  const failures: CrossCheckFailure[] = [];

  // ---- Duplicidade de Species no conjunto descoberto (Bloco 2) ----------
  // Um Set silencioso colapsaria IDs repetidos sem nunca reportar o
  // problema — aqui contamos ocorrências explicitamente antes de decidir
  // pertinência ao conjunto, para que a duplicidade em si vire falha.
  const speciesIdCounts = new Map<string, number>();
  for (const species of speciesDetails) {
    const id = String(species.id);
    speciesIdCounts.set(id, (speciesIdCounts.get(id) ?? 0) + 1);
  }
  for (const [id, count] of speciesIdCounts) {
    if (count > 1) {
      failures.push({
        externalSpeciesId: id,
        reason: "SPECIES_EXTERNAL_ID_DUPLICATE",
        detail:
          `Species external ID ${id} aparece ${count}x no conjunto descoberto de /pokemon-species/ (esperado exatamente 1).`,
      });
    }
  }
  const speciesIds = new Set(speciesIdCounts.keys());

  // ---- Construção da autoridade nacional (Bloco 1 + Bloco 2) ------------
  // Nunca sobrescreve silenciosamente: uma entrada sem external_species_id
  // extraível e duas entradas apontando para a mesma Species são ambas
  // reportadas como falha explícita, nunca mascaradas por um `Map.set`
  // subsequente "vencendo" por cima da anterior.
  const nationalByExternalSpeciesId = new Map<string, number>();
  const nationalDuplicateSpeciesIds = new Set<string>();
  for (const entry of nationalEntries) {
    const externalId = extractIdFromUrl(entry.pokemon_species?.url ?? "");
    if (!externalId) {
      failures.push({
        externalSpeciesId: "?",
        reason: "NATIONAL_ENTRY_SPECIES_ID_UNEXTRACTABLE",
        detail:
          `Entrada de /pokedex/national com entry_number=${entry.entry_number} tem ` +
          `pokemon_species.url sem ID numérico extraível: "${entry.pokemon_species?.url ?? ""}".`,
      });
      continue;
    }
    if (nationalByExternalSpeciesId.has(externalId)) {
      nationalDuplicateSpeciesIds.add(externalId);
      continue;
    }
    nationalByExternalSpeciesId.set(externalId, entry.entry_number);
  }
  for (const externalId of nationalDuplicateSpeciesIds) {
    failures.push({
      externalSpeciesId: externalId,
      reason: "NATIONAL_ENTRY_SPECIES_ID_DUPLICATE",
      detail:
        `Species external ID ${externalId} aparece em mais de uma entrada de ` +
        `/pokedex/national.pokemon_entries[] (esperado exatamente 1).`,
    });
  }

  for (const species of speciesDetails) {
    const externalId = String(species.id);
    const nationalEntriesForSpecies = (species.pokedex_numbers ?? []).filter(
      (p) => p.pokedex?.name === "national",
    );

    if (nationalEntriesForSpecies.length === 0) {
      failures.push({
        externalSpeciesId: externalId,
        reason: "NATIONAL_ENTRY_MISSING",
        detail: `Species ${externalId} sem entrada pokedex_numbers[national].`,
      });
      continue;
    }
    if (nationalEntriesForSpecies.length > 1) {
      failures.push({
        externalSpeciesId: externalId,
        reason: "NATIONAL_ENTRY_DUPLICATE",
        detail:
          `Species ${externalId} com ${nationalEntriesForSpecies.length} entradas pokedex_numbers[national] (esperado exatamente 1).`,
      });
      continue;
    }

    const authorityEntryNumber = nationalByExternalSpeciesId.get(externalId);
    const claimedEntryNumber = nationalEntriesForSpecies[0].entry_number;

    if (authorityEntryNumber === undefined) {
      failures.push({
        externalSpeciesId: externalId,
        reason: "SPECIES_NOT_IN_NATIONAL_SET",
        detail:
          `Species ${externalId} não aparece em /pokedex/national.pokemon_entries[] (autoridade).`,
      });
      continue;
    }
    if (authorityEntryNumber !== claimedEntryNumber) {
      failures.push({
        externalSpeciesId: externalId,
        reason: "NATIONAL_ENTRY_NUMBER_MISMATCH",
        detail:
          `Species ${externalId}: pokedex_numbers[national].entry_number=${claimedEntryNumber} <> autoridade /pokedex/national=${authorityEntryNumber}.`,
      });
    }
  }

  // S = P (segunda metade) — toda entry do National Pokédex também deve
  // corresponder a uma Species efetivamente descoberta.
  for (const [externalId] of nationalByExternalSpeciesId) {
    if (!speciesIds.has(externalId)) {
      failures.push({
        externalSpeciesId: externalId,
        reason: "NATIONAL_ENTRY_NOT_IN_SPECIES_SET",
        detail:
          `entry_number de /pokedex/national referencia Species ${externalId}, ausente de /pokemon-species/ (S<>P).`,
      });
    }
  }

  return { ok: failures.length === 0, failures };
}
