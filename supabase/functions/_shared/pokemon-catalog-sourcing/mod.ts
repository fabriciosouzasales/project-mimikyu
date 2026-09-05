// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/mod.ts
// Barrel do núcleo compartilhado de Pokémon Catalog Sourcing. Reaproveitado
// pelo adapter manual (scripts/run-pokemon-catalog-sourcing.ts) hoje; mesma
// base ficaria disponível para uma futura Edge Function agendada, sem
// duplicar nenhuma lógica (mesmo padrão de _shared/pricing-ptax).

export * from "./types.ts";
export * from "./sanitize.ts";
export * from "./http.ts";
export * from "./normalize.ts";
export * from "./discovery.ts";
export * from "./acquisition.ts";
export * from "./cross-check.ts";
export * from "./snapshot.ts";
export * from "./run-port.ts";
export * from "./supabase-adapter.ts";
export * from "./orchestrator.ts";
export * from "./fs-snapshot-store.ts";
export * from "./cli-validation.ts";
export {
  runPokemonCatalogSourcingAsyncTests,
  runPokemonCatalogSourcingTests,
} from "./pokemon-catalog-sourcing.test.ts";
