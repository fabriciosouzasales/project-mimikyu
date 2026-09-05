// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/types.ts
// Núcleo compartilhado do executor de Pokémon Catalog Sourcing (PokéAPI).
// POKEMON-CATALOG-SOURCING-INITIAL-LOAD-EXECUTOR-STAGING-01 (2026-09-04).
// Ver docs/06a-pokemon-catalog-sourcing.md — contrato canônico completo.
//
// Núcleo puro: nada aqui lê variável de ambiente, cria cliente Supabase real, ou
// chama fetch()/setTimeout() do ambiente global diretamente — toda dependência
// externa é injetada pelo chamador (scripts/run-pokemon-catalog-sourcing.ts hoje,
// mesmo precedente estrutural de _shared/pricing-ptax e _shared/pricing-justtcg-*).

export type FetchLike = typeof fetch;
export type WaitLike = (ms: number) => Promise<void>;

// ---------------------------------------------------------------------------
// Snapshot (Seção 5 do contrato) — forma EXATA persistida/enviada a PLAN/APPLY.
// Todo campo de identidade externa é TEXT (Seção 4: "IDs externos PokéAPI
// numéricos serializados como TEXT, nunca slug") — nunca number.
// ---------------------------------------------------------------------------

export interface RegionSnapshotRow {
  external_region_id: string;
  code: string;
  canonical_name: string;
  source_url: string;
  metadata: Record<string, never>;
}

export interface GenerationSnapshotRow {
  external_generation_id: string;
  code: string;
  canonical_name: string;
  ordinal_number: number;
  main_region_external_id: string;
  source_url: string;
  metadata: Record<string, never>;
}

export interface SpeciesSnapshotRow {
  external_species_id: string;
  national_dex_number: number;
  canonical_name: string;
  generation_external_id: string;
  source_url: string;
  metadata: Record<string, never>;
}

export interface NationalPokedexSnapshot {
  external_pokedex_id: string;
  code: string;
  canonical_name: string;
  source_url: string;
  metadata: Record<string, never>;
}

export interface NationalPokedexEntrySnapshot {
  external_species_id: string;
  position_number: number;
}

export interface PokemonCatalogSnapshot {
  regions: RegionSnapshotRow[];
  generations: GenerationSnapshotRow[];
  species: SpeciesSnapshotRow[];
  national_pokedex: NationalPokedexSnapshot;
  national_pokedex_entries: NationalPokedexEntrySnapshot[];
}

// ---------------------------------------------------------------------------
// Formas cruas mínimas da PokéAPI — só os campos que este módulo consome.
// ---------------------------------------------------------------------------

export interface PokeApiNamedApiResource {
  name: string;
  url: string;
}

export interface PokeApiNameEntry {
  name: string;
  language: PokeApiNamedApiResource;
}

export interface PokeApiPagedList {
  count: number;
  next: string | null;
  previous: string | null;
  results: PokeApiNamedApiResource[];
}

export interface PokeApiRegionDetail {
  id: number;
  name: string;
  names: PokeApiNameEntry[];
}

export interface PokeApiGenerationDetail {
  id: number;
  name: string;
  names: PokeApiNameEntry[];
  main_region: PokeApiNamedApiResource;
}

export interface PokeApiPokedexNumberEntry {
  entry_number: number;
  pokedex: PokeApiNamedApiResource;
}

export interface PokeApiSpeciesDetail {
  id: number;
  name: string;
  names: PokeApiNameEntry[];
  generation: PokeApiNamedApiResource;
  pokedex_numbers: PokeApiPokedexNumberEntry[];
}

export interface PokeApiPokedexEntry {
  entry_number: number;
  pokemon_species: PokeApiNamedApiResource;
}

export interface PokeApiPokedexDetail {
  id: number;
  name: string;
  names: PokeApiNameEntry[];
  pokemon_entries: PokeApiPokedexEntry[];
}

// ---------------------------------------------------------------------------
// Resultado de uma chamada HTTP individual (telemetria/diagnóstico).
// ---------------------------------------------------------------------------

export type SourcingFetchOutcome = "SUCCESS" | "TECHNICAL_FAILURE";

export interface SourcingCallLogEntry {
  sequenceNumber: number;
  endpoint: string;
  httpStatusCode: number | null;
  outcome: SourcingFetchOutcome;
  errorDetail: string | null;
}

// ---------------------------------------------------------------------------
// Contrato mínimo de persistência local do snapshot PLANEJADO (Seção 8: fluxo
// canônico "... → PLAN → salvar snapshot local sanitizado" — o snapshot só é
// gravado DEPOIS do retorno do PLAN, nunca antes; um snapshot pré-PLAN nunca é
// tratado como aprovado). "APPLY usa EXATAMENTE o snapshot aprovado e faz ZERO
// GETs à PokéAPI". Implementação real sobre filesystem em fs-snapshot-store.ts;
// testes usam um fake em memória.
//
// Semântica NEUTRA (REVISION-02): "planejado" != "aprovado para APPLY". O
// registro é persistido para QUALQUER outcome terminal de sucesso do PLAN —
// COMPLETED ou COMPLETED_WITH_DIVERGENCES — porque um snapshot divergente
// ainda tem valor de auditoria/diagnóstico e NÃO deve ser descartado. A
// elegibilidade para APPLY é decidida separadamente, em runApply(), a partir
// do campo `planOutcome`: só `COMPLETED` é aceito como preflight; qualquer
// outro valor é recusado localmente, ANTES de abrir run ou chamar apply.
// VALIDATION_FAILURE, PAYLOAD_GUARD_EXCEEDED e exceções nunca chegam a este
// contrato — nenhum registro é criado para esses casos.
//
// O registro persistido é um ENVELOPE (não o snapshot cru): amarra
// inequivocamente run_id/run_code/snapshot_hash/plan_outcome ao snapshot, para
// que um futuro APPLY (ou uma auditoria) nunca precise confiar apenas no nome
// do arquivo/chave para saber a que preflight — e a que resultado de PLAN —
// aquele snapshot pertence.
// ---------------------------------------------------------------------------

export type PlannedSnapshotOutcome = "COMPLETED" | "COMPLETED_WITH_DIVERGENCES";

export interface PlannedSnapshotRecord {
  runId: string;
  runCode: string;
  snapshotHash: string;
  planOutcome: PlannedSnapshotOutcome;
  snapshot: PokemonCatalogSnapshot;
}

export interface SnapshotStore {
  save(record: PlannedSnapshotRecord): Promise<string>;
  load(runCode: string): Promise<PlannedSnapshotRecord | null>;
}
