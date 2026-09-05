// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/acquisition.ts
// Orquestra Discovery + Detail fetch + Normalização (Seções 3/4 do contrato)
// para as quatro famílias (Region, Generation, Species, National Pokédex).
// Núcleo puro quanto a I/O de rede: fetch/wait são sempre injetados
// (FetchJsonDeps) — nenhuma referência a `fetch`/`setTimeout` globais aqui.

import { fetchJsonWithRetry, type FetchJsonDeps, mapWithConcurrency } from "./http.ts";
import { discoverAllPaged } from "./discovery.ts";
import {
  codeFromSlug,
  extractCanonicalNameEn,
  extractGenerationOrdinal,
  extractIdFromUrl,
} from "./normalize.ts";
import type {
  GenerationSnapshotRow,
  PokeApiGenerationDetail,
  PokeApiPokedexDetail,
  PokeApiRegionDetail,
  PokeApiSpeciesDetail,
  RegionSnapshotRow,
  SourcingCallLogEntry,
  SpeciesSnapshotRow,
} from "./types.ts";

export const POKEAPI_BASE_URL = "https://pokeapi.co/api/v2";
// REVISION-04 (correção de divergência residual da REVISION-03) — o contrato
// canônico (docs/06a-pokemon-catalog-sourcing.md) determina que a AQUISIÇÃO/
// AUTORIDADE é feita via `/pokedex/national/` (o GET real de fato usado); o
// `/pokedex/1/` é exclusivamente o `source_url` gravado no SNAPSHOT (ver
// orchestrator.ts, NATIONAL_POKEDEX_SOURCE_URL) — os dois valores nunca foram
// a mesma coisa e a REVISION-03 os havia colapsado incorretamente em um só.
// As validações de identidade (id===1 / name==="national") abaixo continuam
// obrigatórias sobre a resposta deste GET, e `national_dex_number` continua
// derivado de `pokemon_entries[].entry_number` (autoridade) após o
// cross-check — nenhum dos dois muda nesta correção.
export const NATIONAL_POKEDEX_URL = `${POKEAPI_BASE_URL}/pokedex/national/`;

// REVISION-03 (Bloco 3): `deps.onHeartbeat`, quando fornecido, já chega até
// aqui PRÉ-LIMITADO POR TEMPO (createHeartbeatGate, construído pelo
// chamador em orchestrator.ts) — este módulo nunca decide "a cada quantos
// itens" renovar; ele apenas invoca a função em TODO checkpoint natural
// (cada página de discovery, cada item de detail fetch, cada transição de
// fase) e deixa o gate decidir se tempo suficiente já passou para valer a
// pena um heartbeat real. Isso cobre discovery (potencialmente lento por
// paginação) e detail fetch (potencialmente longo por volume) igualmente,
// sem depender de contagem de itens.

export interface AcquisitionIssue {
  stage: "REGION" | "GENERATION" | "SPECIES" | "NATIONAL_POKEDEX";
  externalId: string | null;
  reason: string;
}

export interface AcquisitionResult {
  // SUCCESS: nenhum problema, snapshot pode ser montado.
  // VALIDATION_ISSUES: aquisição HTTP OK, mas dados retornados são
  //   estruturalmente inválidos (nome EN ausente, slug de geração
  //   inesperado, etc.) — nunca deve prosseguir para PLAN.
  // TECHNICAL_FAILURE: falha de rede/HTTP não recuperada pelo retry.
  status: "SUCCESS" | "VALIDATION_ISSUES" | "TECHNICAL_FAILURE";
  regions: RegionSnapshotRow[];
  generations: GenerationSnapshotRow[];
  species: SpeciesSnapshotRow[];
  speciesRaw: PokeApiSpeciesDetail[];
  nationalPokedexRaw: PokeApiPokedexDetail | null;
  issues: AcquisitionIssue[];
  callLog: SourcingCallLogEntry[];
  detail?: string;
}

export interface AcquisitionDeps extends FetchJsonDeps {
  concurrency: number;
  onHeartbeat?: () => Promise<void>;
}

export async function acquirePokemonCatalogSnapshot(
  deps: AcquisitionDeps,
): Promise<AcquisitionResult> {
  const callLog: SourcingCallLogEntry[] = [];
  const issues: AcquisitionIssue[] = [];

  // 1. Discovery — Regions, Generations, Species (paginado, Seção 3: nunca
  //    assumir cardinalidade fixa). REVISION-03 (Bloco 3): antes disparava as
  //    3 listagens via Promise.all incondicional — mesmo com concurrency=1
  //    configurado, isso resultava em 3 GETs simultâneos, violando o limite.
  //    mapWithConcurrency aqui garante que o número de listagens ativas ao
  //    mesmo tempo nunca excede `deps.concurrency`, exatamente como já
  //    ocorre nas fases de detail fetch abaixo. Cada `discoverAllPaged`
  //    recebe o heartbeat gate para renovar durante sua própria paginação
  //    (não apenas depois que as 3 listagens terminam).
  const discoveryTasks = [
    () => discoverAllPaged(`${POKEAPI_BASE_URL}/region/`, deps, deps.onHeartbeat),
    () => discoverAllPaged(`${POKEAPI_BASE_URL}/generation/`, deps, deps.onHeartbeat),
    () => discoverAllPaged(`${POKEAPI_BASE_URL}/pokemon-species/`, deps, deps.onHeartbeat),
  ];
  const [regionsList, generationsList, speciesList] = await mapWithConcurrency(
    discoveryTasks,
    deps.concurrency,
    (task) => task(),
  );
  for (const r of [regionsList, generationsList, speciesList]) {
    callLog.push(...r.callLog);
  }
  const failedDiscovery = [regionsList, generationsList, speciesList].find(
    (r) => r.status !== "SUCCESS",
  );
  if (failedDiscovery) {
    return {
      status: "TECHNICAL_FAILURE",
      regions: [],
      generations: [],
      species: [],
      speciesRaw: [],
      nationalPokedexRaw: null,
      issues,
      callLog,
      detail: failedDiscovery.detail,
    };
  }

  if (deps.onHeartbeat) await deps.onHeartbeat();

  // 2. Detail fetch — Regions. REVISION-05 (Bloco 3, residual físico) — o
  //    mesmo checkpoint por item já usado na fase Species (abaixo) agora
  //    também cobre Regions: `deps.onHeartbeat` é invocado a CADA item
  //    concluído (via `onItemSettled` de mapWithConcurrency), sem condição de
  //    contagem — o próprio `onHeartbeat` já é o gate temporal
  //    (createHeartbeatGate) que decide se tempo suficiente passou para
  //    valer um heartbeat real. Antes desta correção, uma fase de Regions
  //    excepcionalmente lenta (muitos itens ou retries longos) só renovava o
  //    heartbeat nas transições de fase, nunca durante o próprio loop.
  const regionDetailResults = await mapWithConcurrency(
    regionsList.items,
    deps.concurrency,
    (item) => fetchJsonWithRetry(item.url, deps),
    deps.onHeartbeat
      ? async () => {
        await deps.onHeartbeat!();
      }
      : undefined,
  );
  const regions: RegionSnapshotRow[] = [];
  regionDetailResults.forEach((result, idx) => {
    callLog.push(...result.callLog);
    const sourceUrl = regionsList.items[idx].url;
    if (result.status !== "SUCCESS") {
      issues.push({
        stage: "REGION",
        externalId: null,
        reason: `${sourceUrl}: ${result.detail}`,
      });
      return;
    }
    const detail = result.json as PokeApiRegionDetail;
    const canonicalName = extractCanonicalNameEn(detail.names);
    const externalId = String(detail.id);
    if (!canonicalName) {
      issues.push({
        stage: "REGION",
        externalId,
        reason: "CANONICAL_NAME_BLANK",
      });
      return;
    }
    regions.push({
      external_region_id: externalId,
      code: codeFromSlug(detail.name),
      canonical_name: canonicalName,
      source_url: sourceUrl,
      metadata: {},
    });
  });

  // Renova o heartbeat entre fases (Seção 7.2) — Regions concluídas, antes de
  // iniciar Generations. Cobre catálogos pequenos onde o loop de progresso
  // por item (usado abaixo, na fase Species) nunca dispara.
  if (deps.onHeartbeat) await deps.onHeartbeat();

  // 3. Detail fetch — Generations. main_region_external_id é extraído aqui,
  //    resolvido pelo banco/PLAN via referência externa — NUNCA por
  //    canonical_name (Seção 4.2). REVISION-05 (Bloco 3, residual físico) —
  //    mesmo checkpoint por item de Regions/Species, agora também em
  //    Generations.
  const generationDetailResults = await mapWithConcurrency(
    generationsList.items,
    deps.concurrency,
    (item) => fetchJsonWithRetry(item.url, deps),
    deps.onHeartbeat
      ? async () => {
        await deps.onHeartbeat!();
      }
      : undefined,
  );
  const generations: GenerationSnapshotRow[] = [];
  generationDetailResults.forEach((result, idx) => {
    callLog.push(...result.callLog);
    const sourceUrl = generationsList.items[idx].url;
    if (result.status !== "SUCCESS") {
      issues.push({
        stage: "GENERATION",
        externalId: null,
        reason: `${sourceUrl}: ${result.detail}`,
      });
      return;
    }
    const detail = result.json as PokeApiGenerationDetail;
    const canonicalName = extractCanonicalNameEn(detail.names);
    const externalId = String(detail.id);
    const ordinal = extractGenerationOrdinal(detail.name);
    const mainRegionExternalId = extractIdFromUrl(detail.main_region?.url ?? "");
    if (!canonicalName) {
      issues.push({
        stage: "GENERATION",
        externalId,
        reason: "CANONICAL_NAME_BLANK",
      });
      return;
    }
    if (ordinal === null) {
      issues.push({
        stage: "GENERATION",
        externalId,
        reason: `INVALID_ROMAN_SLUG: ${detail.name}`,
      });
      return;
    }
    if (!mainRegionExternalId) {
      issues.push({
        stage: "GENERATION",
        externalId,
        reason: "MAIN_REGION_URL_UNPARSEABLE",
      });
      return;
    }
    generations.push({
      external_generation_id: externalId,
      code: codeFromSlug(detail.name),
      canonical_name: canonicalName,
      ordinal_number: ordinal,
      main_region_external_id: mainRegionExternalId,
      source_url: sourceUrl,
      metadata: {},
    });
  });

  // Renova o heartbeat entre fases — Generations concluídas, antes da fase
  // mais longa (Species, tipicamente 1000+ itens).
  if (deps.onHeartbeat) await deps.onHeartbeat();

  // 4. Detail fetch — Species. Busca o detail de TODAS as Species descobertas
  //    (Seção 3). external_species_id = pokemon-species.id (Seção 4.3) — do
  //    corpo da resposta, nunca da URL. Fase potencialmente longa
  //    (1000+ Species): REVISION-03 (Bloco 3) invoca `deps.onHeartbeat` a
  //    CADA item concluído, sem condição de contagem — o próprio
  //    `onHeartbeat` já é o gate temporal (createHeartbeatGate, construído em
  //    orchestrator.ts) que decide se tempo suficiente passou para valer um
  //    heartbeat real. Isso evita que o stale recovery de open_run (30 min,
  //    Query 6103) reconcilie prematuramente um DRY_RUN legítimo ainda em
  //    ACQUIRING, sem depender de "a cada 50 itens".
  const speciesDetailResults = await mapWithConcurrency(
    speciesList.items,
    deps.concurrency,
    (item) => fetchJsonWithRetry(item.url, deps),
    deps.onHeartbeat
      ? async () => {
        await deps.onHeartbeat!();
      }
      : undefined,
  );
  const species: SpeciesSnapshotRow[] = [];
  const speciesRaw: PokeApiSpeciesDetail[] = [];
  speciesDetailResults.forEach((result, idx) => {
    callLog.push(...result.callLog);
    const sourceUrl = speciesList.items[idx].url;
    if (result.status !== "SUCCESS") {
      issues.push({
        stage: "SPECIES",
        externalId: null,
        reason: `${sourceUrl}: ${result.detail}`,
      });
      return;
    }
    const detail = result.json as PokeApiSpeciesDetail;
    speciesRaw.push(detail);
    const canonicalName = extractCanonicalNameEn(detail.names);
    const externalId = String(detail.id);
    const generationExternalId = extractIdFromUrl(detail.generation?.url ?? "");
    if (!canonicalName) {
      issues.push({
        stage: "SPECIES",
        externalId,
        reason: "CANONICAL_NAME_BLANK",
      });
      return;
    }
    if (!generationExternalId) {
      issues.push({
        stage: "SPECIES",
        externalId,
        reason: "GENERATION_URL_UNPARSEABLE",
      });
      return;
    }
    const nationalEntry = (detail.pokedex_numbers ?? []).find(
      (p) => p.pokedex?.name === "national",
    );
    if (!nationalEntry) {
      // Reportado aqui para visibilidade; o cross-check obrigatório
      // (cross-check.ts) é a autoridade formal desta regra (Seção 4.3).
      issues.push({
        stage: "SPECIES",
        externalId,
        reason: "NATIONAL_ENTRY_MISSING",
      });
      return;
    }
    species.push({
      external_species_id: externalId,
      // REVISION-03 (Bloco 1, National Authority) — este valor é o
      // AUTO-DECLARADO da própria Species (pokedex_numbers[national]), usado
      // apenas como valor provisório aqui. A ordem de aquisição mandatória
      // (Seção 3: Species antes de National Pokédex) impede que a autoridade
      // já esteja disponível neste ponto. orchestrator.ts SOBRESCREVE este
      // campo com `national.pokemon_entries[].entry_number` (a autoridade
      // real) após o cross-check S=P passar e antes de montar o snapshot
      // determinístico — nunca deve chegar ao PLAN com o valor auto-declarado.
      national_dex_number: nationalEntry.entry_number,
      canonical_name: canonicalName,
      generation_external_id: generationExternalId,
      source_url: sourceUrl,
      metadata: {},
    });
  });

  // 5. National Pokédex — external_pokedex_id fixo "1" (Seção 4.4), nunca o
  //    slug "national" usado como identidade externa.
  const nationalResult = await fetchJsonWithRetry(NATIONAL_POKEDEX_URL, deps);
  callLog.push(...nationalResult.callLog);
  if (nationalResult.status !== "SUCCESS") {
    issues.push({
      stage: "NATIONAL_POKEDEX",
      externalId: null,
      reason: nationalResult.detail,
    });
    return {
      status: "TECHNICAL_FAILURE",
      regions,
      generations,
      species,
      speciesRaw,
      nationalPokedexRaw: null,
      issues,
      callLog,
      detail: nationalResult.detail,
    };
  }
  const nationalPokedexRaw = nationalResult.json as PokeApiPokedexDetail;
  // REVISION-03 (Bloco 1, National Authority) — a autoridade nacional só é
  // válida se o próprio recurso confirmar sua identidade: id numérico fixo
  // 1 E slug "national". Sem esta checagem, uma resposta malformada/trocada
  // (ex.: PokéAPI servindo o pokédex errado sob a mesma URL por engano de
  // configuração externa) seria aceita silenciosamente como autoridade.
  if (nationalPokedexRaw.id !== 1) {
    issues.push({
      stage: "NATIONAL_POKEDEX",
      externalId: String(nationalPokedexRaw.id),
      reason: `NATIONAL_POKEDEX_ID_MISMATCH: esperado 1, recebido ${nationalPokedexRaw.id}`,
    });
  }
  if (nationalPokedexRaw.name !== "national") {
    issues.push({
      stage: "NATIONAL_POKEDEX",
      externalId: String(nationalPokedexRaw.id),
      reason: `NATIONAL_POKEDEX_NAME_MISMATCH: esperado "national", recebido "${nationalPokedexRaw.name}"`,
    });
  }
  if (!extractCanonicalNameEn(nationalPokedexRaw.names)) {
    issues.push({
      stage: "NATIONAL_POKEDEX",
      externalId: String(nationalPokedexRaw.id),
      reason: "CANONICAL_NAME_BLANK",
    });
  }

  return {
    status: issues.length > 0 ? "VALIDATION_ISSUES" : "SUCCESS",
    regions,
    generations,
    species,
    speciesRaw,
    nationalPokedexRaw,
    issues,
    callLog,
  };
}
