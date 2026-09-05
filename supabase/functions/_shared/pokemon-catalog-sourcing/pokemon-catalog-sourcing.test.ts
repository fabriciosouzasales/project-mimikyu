// Project Mimikyu — supabase/functions/_shared/pokemon-catalog-sourcing/pokemon-catalog-sourcing.test.ts
// Bateria offline (100% sem rede, sem Supabase) — mesma convenção de
// _shared/pricing-ptax/pricing-ptax.test.ts: runXTests() (síncrono) +
// runXAsyncTests() (assíncrono, para retry/timeout/concorrência/orquestração).
// Executada via `deno run --allow-env scripts/run-pokemon-catalog-sourcing.ts
// --fixture-check` (ou `--fixture-check` automático quando SUPABASE_URL/
// SUPABASE_SERVICE_ROLE_KEY estão ausentes).
//
// Cobre exatamente as 11 categorias exigidas pela rodada
// POKEMON-CATALOG-SOURCING-INITIAL-LOAD-EXECUTOR-STAGING-01: normalização;
// IDs; geração/região; nomes EN; S=P; cross-check nacional; determinismo do
// snapshot; payload guard; DRY_RUN/APPLY sem HTTP indevido; retry/timeout;
// nenhuma exposição de segredo.

import {
  codeFromSlug,
  extractCanonicalNameEn,
  extractGenerationOrdinal,
  extractIdFromUrl,
  romanNumeralToInt,
} from "./normalize.ts";
import { sanitize } from "./sanitize.ts";
import { crossCheckNationalPokedex } from "./cross-check.ts";
import {
  buildDeterministicSnapshot,
  computePayloadCount,
  isPayloadGuardExceeded,
  serializeSnapshotDeterministically,
} from "./snapshot.ts";
import {
  clampConcurrency,
  createHeartbeatGate,
  fetchJsonWithRetry,
  isAllowedPokeApiUrl,
  isRetryableStatus,
  mapWithConcurrency,
  parseRetryAfterMs,
} from "./http.ts";
import { discoverAllPaged } from "./discovery.ts";
import { acquirePokemonCatalogSnapshot } from "./acquisition.ts";
import { createHeartbeatAwareWait, runApply, runDryRun } from "./orchestrator.ts";
import { isSafeRunCode } from "./fs-snapshot-store.ts";
import { validateExactlyOneMode } from "./cli-validation.ts";
import type {
  PlannedSnapshotRecord,
  PokeApiPokedexEntry,
  PokeApiSpeciesDetail,
  PokemonCatalogSnapshot,
} from "./types.ts";
import type { PokemonCatalogSourcingPort } from "./run-port.ts";

export interface TestReport {
  assertions: Array<[string, boolean]>;
}

// ============================================================================
// Testes síncronos: normalização, IDs, nomes EN, sanitização, cross-check,
// snapshot/determinismo/payload guard.
// ============================================================================

export function runPokemonCatalogSourcingTests(): TestReport {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // ---- normalize.ts: IDs ----
  assert(
    "extractIdFromUrl: extrai id numérico da URL (com trailing slash)",
    extractIdFromUrl("https://pokeapi.co/api/v2/region/1/") === "1",
  );
  assert(
    "extractIdFromUrl: extrai id numérico da URL (sem trailing slash)",
    extractIdFromUrl("https://pokeapi.co/api/v2/region/12") === "12",
  );
  assert(
    "extractIdFromUrl: URL sem id numérico -> null (nunca inferência silenciosa)",
    extractIdFromUrl("https://pokeapi.co/api/v2/region/kanto/") === null,
  );

  // ---- normalize.ts: nomes EN (Seção 4.0) ----
  assert(
    "extractCanonicalNameEn: encontra a entrada 'en' entre várias linguagens",
    extractCanonicalNameEn([
      { name: "Kantō", language: { name: "ja-Hrkt", url: "" } },
      { name: "Kanto", language: { name: "en", url: "" } },
    ]) === "Kanto",
  );
  assert(
    "extractCanonicalNameEn: ausência de 'en' -> null (nunca fallback para outro idioma)",
    extractCanonicalNameEn([{ name: "x", language: { name: "fr", url: "" } }]) === null,
  );
  assert("extractCanonicalNameEn: array vazio -> null", extractCanonicalNameEn([]) === null);
  assert("extractCanonicalNameEn: undefined -> null", extractCanonicalNameEn(undefined) === null);
  assert(
    "extractCanonicalNameEn: nome 'en' vazio/whitespace -> null (CANONICAL_NAME_BLANK)",
    extractCanonicalNameEn([{ name: "   ", language: { name: "en", url: "" } }]) === null,
  );

  // ---- normalize.ts: code de structured slug (Região/Nacional) ----
  assert("codeFromSlug: 'kanto' -> 'KANTO'", codeFromSlug("kanto") === "KANTO");
  assert(
    "codeFromSlug: 'generation-i' -> 'GENERATION_I' (hífen -> underscore)",
    codeFromSlug("generation-i") === "GENERATION_I",
  );

  // ---- normalize.ts: geração (algarismo romano -> ordinal_number, Seção 4.2) ----
  assert("romanNumeralToInt: I -> 1", romanNumeralToInt("I") === 1);
  assert("romanNumeralToInt: IV -> 4 (notação subtrativa)", romanNumeralToInt("IV") === 4);
  assert("romanNumeralToInt: VIII -> 8", romanNumeralToInt("VIII") === 8);
  assert("romanNumeralToInt: IX -> 9", romanNumeralToInt("IX") === 9);
  assert(
    "romanNumeralToInt: X -> 10 (sem limite artificial de gerações — cobre futuras)",
    romanNumeralToInt("X") === 10,
  );
  assert("romanNumeralToInt: dígito inválido -> null", romanNumeralToInt("IIQ") === null);
  assert("romanNumeralToInt: string vazia -> null", romanNumeralToInt("") === null);
  assert(
    "extractGenerationOrdinal: 'generation-i' -> 1 (nunca do id da PokéAPI)",
    extractGenerationOrdinal("generation-i") === 1,
  );
  assert("extractGenerationOrdinal: 'generation-viii' -> 8", extractGenerationOrdinal("generation-viii") === 8);
  assert(
    "extractGenerationOrdinal: slug fora do formato 'generation-<roman>' -> null",
    extractGenerationOrdinal("kanto") === null,
  );

  // ---- sanitize.ts: nenhuma exposição de segredo (Seção 15) ----
  const fakeJwt =
    "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.abcdefghijklmnopqrstuvwxyz123456";
  assert(
    "sanitize: redige JWT completo (service_role/anon key)",
    sanitize(`erro ao conectar: ${fakeJwt}`) === "erro ao conectar: [REDACTED_JWT]",
  );
  assert(
    "sanitize: redige header 'Authorization: Bearer <token>' por INTEIRO (não só a 1ª palavra)",
    !sanitize("Authorization: Bearer abc123secreto")!.includes("abc123secreto"),
  );
  assert(
    "sanitize: redige 'Bearer <token>' solto (sem prefixo Authorization:)",
    !sanitize("usando Bearer xyz999")!.includes("xyz999"),
  );
  assert("sanitize: null/undefined -> null (nunca lança)", sanitize(null) === null && sanitize(undefined) === null);
  assert(
    "sanitize: texto sem segredo passa intacto (não redige em excesso)",
    sanitize("HTTP 500: erro interno") === "HTTP 500: erro interno",
  );

  // ---- cross-check.ts: cross-check nacional OBRIGATÓRIO + S=P (Seção 4.3) ----
  const species = (
    id: number,
    entryNumber: number | null,
    dupNational = false,
  ): PokeApiSpeciesDetail => {
    const pokedex_numbers: PokeApiSpeciesDetail["pokedex_numbers"] = [];
    if (entryNumber !== null) {
      pokedex_numbers.push({ entry_number: entryNumber, pokedex: { name: "national", url: "" } });
      if (dupNational) {
        pokedex_numbers.push({ entry_number: entryNumber, pokedex: { name: "national", url: "" } });
      }
    }
    return {
      id,
      name: `sp-${id}`,
      names: [],
      generation: { name: "generation-i", url: "https://pokeapi.co/api/v2/generation/1/" },
      pokedex_numbers,
    };
  };
  const nationalEntry = (entryNumber: number, speciesId: number): PokeApiPokedexEntry => ({
    entry_number: entryNumber,
    pokemon_species: {
      name: `sp-${speciesId}`,
      url: `https://pokeapi.co/api/v2/pokemon-species/${speciesId}/`,
    },
  });

  {
    const ok = crossCheckNationalPokedex(
      [species(1, 1), species(2, 2), species(3, 152)],
      [nationalEntry(1, 1), nationalEntry(2, 2), nationalEntry(152, 3)],
    );
    assert(
      "crossCheck: S=P e entry_number 100% coincidente -> ok, zero falhas",
      ok.ok && ok.failures.length === 0,
    );
  }
  {
    const missing = crossCheckNationalPokedex([species(1, null)], [nationalEntry(1, 1)]);
    assert(
      "crossCheck: entrada national ausente -> NATIONAL_ENTRY_MISSING",
      !missing.ok && missing.failures.some((f) => f.reason === "NATIONAL_ENTRY_MISSING"),
    );
  }
  {
    const dup = crossCheckNationalPokedex([species(1, 1, true)], [nationalEntry(1, 1)]);
    assert(
      "crossCheck: entrada national duplicada -> NATIONAL_ENTRY_DUPLICATE",
      !dup.ok && dup.failures.some((f) => f.reason === "NATIONAL_ENTRY_DUPLICATE"),
    );
  }
  {
    const mismatch = crossCheckNationalPokedex([species(1, 1)], [nationalEntry(2, 1)]);
    assert(
      "crossCheck: entry_number divergente da autoridade -> NATIONAL_ENTRY_NUMBER_MISMATCH",
      !mismatch.ok && mismatch.failures.some((f) => f.reason === "NATIONAL_ENTRY_NUMBER_MISMATCH"),
    );
  }
  {
    const spNotInNational = crossCheckNationalPokedex([species(1, 1)], []);
    assert(
      "crossCheck (S=P): Species fora do conjunto nacional -> SPECIES_NOT_IN_NATIONAL_SET",
      !spNotInNational.ok &&
        spNotInNational.failures.some((f) => f.reason === "SPECIES_NOT_IN_NATIONAL_SET"),
    );
  }
  {
    const entryNotInSpecies = crossCheckNationalPokedex([], [nationalEntry(1, 1)]);
    assert(
      "crossCheck (S=P): entry nacional sem Species correspondente -> NATIONAL_ENTRY_NOT_IN_SPECIES_SET",
      !entryNotInSpecies.ok &&
        entryNotInSpecies.failures.some((f) => f.reason === "NATIONAL_ENTRY_NOT_IN_SPECIES_SET"),
    );
  }

  // ---- cross-check.ts [REVISION-03, Bloco 2 — S=P exato]: Map/Set nunca
  // mascara duplicidade. Os 3 casos abaixo eram engolidos silenciosamente
  // antes desta correção (a última sobrescrita "vencia" sem registrar falha
  // alguma). ----
  {
    // Species external ID duplicado no conjunto descoberto: duas entradas de
    // /pokemon-species/ com o MESMO id (nunca deveria acontecer, mas um Set
    // silencioso colapsaria sem avisar).
    const dupSpecies = crossCheckNationalPokedex(
      [species(1, 1), species(1, 1)],
      [nationalEntry(1, 1)],
    );
    assert(
      "crossCheck [Bloco 2]: Species external ID duplicado no conjunto descoberto -> SPECIES_EXTERNAL_ID_DUPLICATE (nunca mascarado por Set)",
      !dupSpecies.ok &&
        dupSpecies.failures.some((f) => f.reason === "SPECIES_EXTERNAL_ID_DUPLICATE"),
    );
  }
  {
    // Species external ID duplicado em National entries: duas entradas de
    // /pokedex/1/.pokemon_entries[] apontando para a MESMA Species (via URL).
    const dupNationalTarget = crossCheckNationalPokedex(
      [species(1, 1)],
      [nationalEntry(1, 1), nationalEntry(2, 1)],
    );
    assert(
      "crossCheck [Bloco 2]: Species external ID duplicado em National entries -> NATIONAL_ENTRY_SPECIES_ID_DUPLICATE (nunca a última sobrescrita 'vence' silenciosamente)",
      !dupNationalTarget.ok &&
        dupNationalTarget.failures.some((f) => f.reason === "NATIONAL_ENTRY_SPECIES_ID_DUPLICATE"),
    );
  }
  {
    // National entry sem external_species_id extraível: pokemon_species.url
    // sem ID numérico (slug puro, url vazia, etc.).
    const unextractable = crossCheckNationalPokedex(
      [species(1, 1)],
      [{ entry_number: 1, pokemon_species: { name: "sp-1", url: "https://pokeapi.co/api/v2/pokemon-species/kanto/" } }],
    );
    assert(
      "crossCheck [Bloco 2]: National entry sem external_species_id extraível -> NATIONAL_ENTRY_SPECIES_ID_UNEXTRACTABLE",
      !unextractable.ok &&
        unextractable.failures.some((f) => f.reason === "NATIONAL_ENTRY_SPECIES_ID_UNEXTRACTABLE"),
    );
  }

  // ---- http.ts [REVISION-03, Bloco 3]: allowlist de origem PokéAPI ----
  assert(
    "isAllowedPokeApiUrl: URL dentro de https://pokeapi.co/api/v2/ -> permitida",
    isAllowedPokeApiUrl("https://pokeapi.co/api/v2/pokemon-species/1/"),
  );
  assert(
    "isAllowedPokeApiUrl: origem completamente diferente -> rejeitada",
    !isAllowedPokeApiUrl("https://evil.example.com/api/v2/pokemon-species/1/"),
  );
  assert(
    "isAllowedPokeApiUrl: subdomínio/prefixo parecido mas fora do allowlist exato -> rejeitada",
    !isAllowedPokeApiUrl("https://pokeapi.co.evil.com/api/v2/pokemon-species/1/"),
  );
  assert(
    "isAllowedPokeApiUrl: http (não https) para o mesmo host -> rejeitada (protocolo faz parte do allowlist)",
    !isAllowedPokeApiUrl("http://pokeapi.co/api/v2/pokemon-species/1/"),
  );

  // ---- fs-snapshot-store.ts [REVISION-03, Bloco 4]: regex canônico de
  // run_code + defesa contra path traversal — validado ANTES de qualquer
  // acesso a filesystem (aqui, testado como função pura, sem tocar em Deno.*). ----
  assert(
    "isSafeRunCode: forma canônica válida (RUN-YYYYMMDD-NNNNNNNN) -> true",
    isSafeRunCode("RUN-20260904-00000001"),
  );
  assert(
    "isSafeRunCode: sequência com mais de 8 dígitos (regex usa {8,}) -> true",
    isSafeRunCode("RUN-20260904-000000012345"),
  );
  assert(
    "isSafeRunCode: sem prefixo RUN- -> false",
    !isSafeRunCode("20260904-00000001"),
  );
  assert(
    "isSafeRunCode: data com menos de 8 dígitos -> false",
    !isSafeRunCode("RUN-2026904-00000001"),
  );
  assert(
    "isSafeRunCode: sequência com menos de 8 dígitos -> false",
    !isSafeRunCode("RUN-20260904-1"),
  );
  assert(
    "isSafeRunCode: path traversal via '../' embutido -> false (path traversal, mesmo que colidisse com o regex)",
    !isSafeRunCode("RUN-20260904-00000001/../../etc/passwd"),
  );
  assert(
    "isSafeRunCode: separador '/' embutido -> false",
    !isSafeRunCode("RUN-20260904-0000/0001"),
  );
  assert(
    "isSafeRunCode: separador '\\\\' embutido -> false",
    !isSafeRunCode("RUN-20260904-0000\\0001"),
  );
  assert(
    "isSafeRunCode: string vazia -> false",
    !isSafeRunCode(""),
  );

  // ---- cli-validation.ts [REVISION-03, Bloco 5]: exatamente um modo entre
  // fixture-check/dry-run/apply ----
  assert(
    "validateExactlyOneMode: --fixture-check sozinho -> ok",
    validateExactlyOneMode({ fixtureCheck: true, dryRun: false, apply: false }).ok,
  );
  assert(
    "validateExactlyOneMode: --dry-run sozinho -> ok",
    validateExactlyOneMode({ fixtureCheck: false, dryRun: true, apply: false }).ok,
  );
  assert(
    "validateExactlyOneMode: --apply sozinho -> ok",
    validateExactlyOneMode({ fixtureCheck: false, dryRun: false, apply: true }).ok,
  );
  assert(
    "validateExactlyOneMode: NENHUM modo especificado -> não ok (nunca fallback implícito)",
    !validateExactlyOneMode({ fixtureCheck: false, dryRun: false, apply: false }).ok,
  );
  assert(
    "validateExactlyOneMode: MAIS DE UM modo simultâneo (--dry-run e --apply) -> não ok",
    !validateExactlyOneMode({ fixtureCheck: false, dryRun: true, apply: true }).ok,
  );
  assert(
    "validateExactlyOneMode: os 3 modos simultâneos -> não ok",
    !validateExactlyOneMode({ fixtureCheck: true, dryRun: true, apply: true }).ok,
  );

  // ---- snapshot.ts: determinismo + payload guard (Seção 5) ----
  {
    const regions = [
      { external_region_id: "2", code: "JOHTO", canonical_name: "Johto", source_url: "u2", metadata: {} },
      { external_region_id: "1", code: "KANTO", canonical_name: "Kanto", source_url: "u1", metadata: {} },
    ];
    const generations = [
      {
        external_generation_id: "2",
        code: "GENERATION_II",
        canonical_name: "Generation II",
        ordinal_number: 2,
        main_region_external_id: "2",
        source_url: "g2",
        metadata: {},
      },
      {
        external_generation_id: "1",
        code: "GENERATION_I",
        canonical_name: "Generation I",
        ordinal_number: 1,
        main_region_external_id: "1",
        source_url: "g1",
        metadata: {},
      },
    ];
    const speciesRows = [
      {
        external_species_id: "3",
        national_dex_number: 3,
        canonical_name: "Venusaur",
        generation_external_id: "1",
        source_url: "s3",
        metadata: {},
      },
      {
        external_species_id: "1",
        national_dex_number: 1,
        canonical_name: "Bulbasaur",
        generation_external_id: "1",
        source_url: "s1",
        metadata: {},
      },
    ];
    const entries = [
      { external_species_id: "3", position_number: 3 },
      { external_species_id: "1", position_number: 1 },
    ];
    const nationalPokedex = {
      external_pokedex_id: "1",
      code: "NATIONAL",
      canonical_name: "National",
      source_url: "n",
      metadata: {},
    };

    const snap = buildDeterministicSnapshot({
      regions,
      generations,
      species: speciesRows,
      nationalPokedex,
      nationalPokedexEntries: entries,
    });
    assert(
      "snapshot: regions ordenadas por external_region_id numérico ASC",
      snap.regions.map((r) => r.external_region_id).join(",") === "1,2",
    );
    assert(
      "snapshot: generations ordenadas por external_generation_id numérico ASC",
      snap.generations.map((g) => g.external_generation_id).join(",") === "1,2",
    );
    assert(
      "snapshot: species ordenadas por external_species_id numérico ASC",
      snap.species.map((s) => s.external_species_id).join(",") === "1,3",
    );
    assert(
      "snapshot: national_pokedex_entries ordenadas por position_number ASC",
      snap.national_pokedex_entries.map((e) => e.position_number).join(",") === "1,3",
    );

    const snapAgain = buildDeterministicSnapshot({
      regions: [...regions].reverse(),
      generations: [...generations].reverse(),
      species: [...speciesRows].reverse(),
      nationalPokedex,
      nationalPokedexEntries: [...entries].reverse(),
    });
    assert(
      "snapshot: determinismo — mesma entrada em ordem diferente produz a MESMA serialização",
      serializeSnapshotDeterministically(snap) === serializeSnapshotDeterministically(snapAgain),
    );

    assert(
      "snapshot: computePayloadCount soma as 4 famílias + 1 (national_pokedex)",
      computePayloadCount(snap) === 2 + 2 + 2 + 2 + 1,
    );
    assert("snapshot: payload guard não excedido para snapshot pequeno", !isPayloadGuardExceeded(snap));

    const bigEntries = Array.from({ length: 25_000 }, (_, i) => ({
      external_species_id: String(i + 1),
      position_number: i + 1,
    }));
    const bigSnap: PokemonCatalogSnapshot = buildDeterministicSnapshot({
      regions: [],
      generations: [],
      species: [],
      nationalPokedex,
      nationalPokedexEntries: bigEntries,
    });
    assert(
      "snapshot: payload guard EXCEDIDO acima de 25000 (25000 entries + 1 national > 25000)",
      isPayloadGuardExceeded(bigSnap),
    );
  }

  return { assertions };
}

// ============================================================================
// Testes assíncronos: retry/timeout/Retry-After, concorrência, paginação,
// aquisição (integração) e orquestração DRY_RUN/APPLY sem HTTP indevido.
// ============================================================================

export async function runPokemonCatalogSourcingAsyncTests(): Promise<TestReport> {
  const assertions: Array<[string, boolean]> = [];
  const assert = (label: string, cond: boolean) => assertions.push([label, cond]);

  // ---- http.ts: retry/timeout/Retry-After (Seção 12) ----
  {
    let calls = 0;
    const fakeFetch = (async () => {
      calls++;
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }) as unknown as typeof fetch;
    const waits: number[] = [];
    const result = await fetchJsonWithRetry("https://pokeapi.co/api/v2/pokemon/1/", {
      fetchImpl: fakeFetch,
      waitImpl: (ms: number) => {
        waits.push(ms);
        return Promise.resolve();
      },
    });
    assert(
      "fetchJsonWithRetry: sucesso na 1ª tentativa, sem esperar nem repetir",
      result.status === "SUCCESS" && calls === 1 && waits.length === 0,
    );
  }
  {
    let calls = 0;
    const fakeFetch = (async () => {
      calls++;
      if (calls < 3) return new Response("erro interno", { status: 500 });
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }) as unknown as typeof fetch;
    const waits: number[] = [];
    const result = await fetchJsonWithRetry("https://pokeapi.co/api/v2/pokemon/1/", {
      fetchImpl: fakeFetch,
      waitImpl: (ms: number) => {
        waits.push(ms);
        return Promise.resolve();
      },
    });
    assert(
      "fetchJsonWithRetry: 500,500,200 -> SUCCESS após 2 retries (3 tentativas totais)",
      result.status === "SUCCESS" && calls === 3,
    );
    assert(
      "fetchJsonWithRetry: espera 1s antes da 2ª tentativa, 3s antes da 3ª (default)",
      waits[0] === 1000 && waits[1] === 3000,
    );
  }
  {
    let calls = 0;
    const fakeFetch = (async () => {
      calls++;
      return new Response("not found", { status: 404 });
    }) as unknown as typeof fetch;
    const result = await fetchJsonWithRetry("https://pokeapi.co/api/v2/pokemon/1/", {
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "fetchJsonWithRetry: 404 não é retryable — falha na 1ª tentativa, nunca repete",
      result.status === "TECHNICAL_FAILURE" && calls === 1,
    );
  }
  {
    let calls = 0;
    const fakeFetch = (async () => {
      calls++;
      if (calls === 1) {
        return new Response("rate limited", { status: 429, headers: { "Retry-After": "7" } });
      }
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }) as unknown as typeof fetch;
    const waits: number[] = [];
    const result = await fetchJsonWithRetry("https://pokeapi.co/api/v2/pokemon/1/", {
      fetchImpl: fakeFetch,
      waitImpl: (ms: number) => {
        waits.push(ms);
        return Promise.resolve();
      },
    });
    assert(
      "fetchJsonWithRetry: 429 com Retry-After: 7 -> respeita 7000ms (nunca o default de 1000ms)",
      result.status === "SUCCESS" && waits[0] === 7000,
    );
  }
  {
    let calls = 0;
    // deno-lint-ignore no-explicit-any
    const fakeFetch = (async (_url: unknown, init: any) => {
      calls++;
      return new Promise((_resolve, reject) => {
        init.signal.addEventListener("abort", () =>
          reject(new Error("The operation was aborted"))
        );
      });
    }) as unknown as typeof fetch;
    const result = await fetchJsonWithRetry("https://pokeapi.co/api/v2/pokemon/1/", {
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
      timeoutMs: 5,
      maxAttempts: 2,
    });
    assert(
      "fetchJsonWithRetry: timeout é retryable; após esgotar tentativas reporta TECHNICAL_FAILURE",
      result.status === "TECHNICAL_FAILURE" && calls === 2 &&
        result.detail.includes("TIMEOUT"),
    );
  }

  assert("clampConcurrency: valor dentro da faixa 1..10 preservado", clampConcurrency(7) === 7);
  assert("clampConcurrency: valor abaixo de 1 -> clampado para 1", clampConcurrency(0) === 1);
  assert("clampConcurrency: valor acima de 10 -> clampado para 10", clampConcurrency(50) === 10);
  assert("clampConcurrency: NaN -> default 5", clampConcurrency(NaN) === 5);
  assert(
    "isRetryableStatus: 408/429/5xx são retryable",
    isRetryableStatus(429) && isRetryableStatus(500) && isRetryableStatus(503) &&
      isRetryableStatus(408),
  );
  assert("isRetryableStatus: 404/400 não são retryable", !isRetryableStatus(404) && !isRetryableStatus(400));
  assert("parseRetryAfterMs: valor em segundos convertido para ms", parseRetryAfterMs("5") === 5000);
  assert("parseRetryAfterMs: header ausente -> null", parseRetryAfterMs(null) === null);

  // ---- http.ts: concorrência configurável (Seção 12) ----
  {
    let active = 0;
    let maxActive = 0;
    const items = Array.from({ length: 20 }, (_, i) => i);
    await mapWithConcurrency(items, 3, async (item) => {
      active++;
      maxActive = Math.max(maxActive, active);
      await new Promise((r) => setTimeout(r, 1));
      active--;
      return item * 2;
    });
    assert("mapWithConcurrency: nunca excede o limite configurado (3)", maxActive <= 3);
  }
  {
    const items = [1, 2, 3, 4, 5];
    const results = await mapWithConcurrency(items, 2, (item) => Promise.resolve(item * 10));
    assert(
      "mapWithConcurrency: preserva correspondência de índice entre entrada e saída",
      results.join(",") === "10,20,30,40,50",
    );
  }
  {
    // onItemSettled (auditoria item 1 — heartbeat durante aquisição longa,
    // não só no início): confirma que o callback é chamado exatamente uma
    // vez por item concluído, com a contagem acumulada e o total corretos —
    // independência de mapWithConcurrency, antes de testar via acquisition.
    const items = Array.from({ length: 10 }, (_, i) => i);
    const settledCalls: Array<[number, number]> = [];
    await mapWithConcurrency(
      items,
      3,
      (item) => Promise.resolve(item),
      (completedCount, total) => {
        settledCalls.push([completedCount, total]);
      },
    );
    assert(
      "mapWithConcurrency: onItemSettled é chamado uma vez por item, com total correto e contagem estritamente crescente",
      settledCalls.length === 10 &&
        settledCalls.every(([, total]) => total === 10) &&
        settledCalls.map(([count]) => count).join(",") === "1,2,3,4,5,6,7,8,9,10",
    );
  }
  {
    // mapWithConcurrency sem onItemSettled: garante que o parâmetro é
    // opcional e não quebra o uso pré-existente (chamadas de discovery/detail
    // fetch que não precisam de progresso).
    const results = await mapWithConcurrency([1, 2, 3], 2, (item) => Promise.resolve(item));
    assert(
      "mapWithConcurrency: onItemSettled ausente não altera o comportamento (retrocompatível)",
      results.join(",") === "1,2,3",
    );
  }

  // ---- discovery.ts: paginação (Seção 3, nunca cardinalidade fixa) ----
  {
    let calls = 0;
    const fakeFetch = (async (url: string) => {
      calls++;
      if (url === "https://pokeapi.co/api/v2/list/") {
        return new Response(
          JSON.stringify({
            count: 3,
            next: "https://pokeapi.co/api/v2/list/?page=2",
            previous: null,
            results: [{ name: "a", url: "a" }],
          }),
          { status: 200 },
        );
      }
      return new Response(
        JSON.stringify({
          count: 3,
          next: null,
          previous: "https://pokeapi.co/api/v2/list/",
          results: [{ name: "b", url: "b" }, { name: "c", url: "c" }],
        }),
        { status: 200 },
      );
    }) as unknown as typeof fetch;
    const result = await discoverAllPaged("https://pokeapi.co/api/v2/list/", {
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "discoverAllPaged: percorre TODAS as páginas seguindo `next` até null",
      result.status === "SUCCESS" && result.items.length === 3 && calls === 2,
    );
  }

  // ---- acquisition.ts: integração completa (Region -> Generation -> Species -> National) ----
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "kanto", url: `${BASE}/region/1/` }],
      },
      [`${BASE}/generation/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "generation-i", url: `${BASE}/generation/1/` }],
      },
      [`${BASE}/pokemon-species/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "bulbasaur", url: `${BASE}/pokemon-species/1/` }],
      },
      [`${BASE}/region/1/`]: { id: 1, name: "kanto", names: namesEn("Kanto") },
      [`${BASE}/generation/1/`]: {
        id: 1,
        name: "generation-i",
        names: namesEn("Generation I"),
        main_region: { name: "kanto", url: `${BASE}/region/1/` },
      },
      [`${BASE}/pokemon-species/1/`]: {
        id: 1,
        name: "bulbasaur",
        names: namesEn("Bulbasaur"),
        generation: { name: "generation-i", url: `${BASE}/generation/1/` },
        pokedex_numbers: [{ entry_number: 1, pokedex: { name: "national", url: "" } }],
      },
      // REVISION-04 — o GET real de aquisição/autoridade é `/pokedex/national/`
      // (contrato canônico); `/pokedex/1/` é exclusivamente o `source_url`
      // gravado no snapshot final (ver teste dedicado mais abaixo).
      [`${BASE}/pokedex/national/`]: {
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [
          { entry_number: 1, pokemon_species: { name: "bulbasaur", url: `${BASE}/pokemon-species/1/` } },
        ],
      },
    };
    const fakeFetch = (async (url: string) => {
      const body = routes[url];
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;

    const acquisition = await acquirePokemonCatalogSnapshot({
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
      concurrency: 5,
    });
    assert("acquisition (integração): status SUCCESS", acquisition.status === "SUCCESS");
    assert(
      "acquisition (integração): Region normalizada (code=KANTO, canonical_name=Kanto)",
      acquisition.regions.length === 1 && acquisition.regions[0].code === "KANTO" &&
        acquisition.regions[0].canonical_name === "Kanto",
    );
    assert(
      "acquisition (integração): Generation com ordinal_number=1 (do slug) e main_region_external_id=1 (da URL, não de canonical_name)",
      acquisition.generations.length === 1 &&
        acquisition.generations[0].ordinal_number === 1 &&
        acquisition.generations[0].main_region_external_id === "1",
    );
    assert(
      "acquisition (integração): Species com national_dex_number=1 (de pokedex_numbers[national]) e external_species_id=id (não da URL)",
      acquisition.species.length === 1 &&
        acquisition.species[0].national_dex_number === 1 &&
        acquisition.species[0].external_species_id === "1",
    );

    // ---- orchestrator.ts: DRY_RUN feliz de ponta a ponta ----
    let heartbeatCalls = 0;
    let planCalledWithSnapshot: PokemonCatalogSnapshot | null = null;
    const savedRecords = new Map<string, PlannedSnapshotRecord>();
    // Instrumenta a ORDEM real das chamadas — prova objetiva de que o store
    // nunca é acionado antes do PLAN resolver (correção REVISION-01), e não
    // apenas de que ele acaba sendo chamado em algum momento.
    const callOrder: string[] = [];
    const fakeStore = {
      save: (record: PlannedSnapshotRecord) => {
        callOrder.push("store-save-called");
        savedRecords.set(record.runCode, record);
        return Promise.resolve(record.runCode);
      },
      load: (code: string) => Promise.resolve(savedRecords.get(code) ?? null),
    };
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-1",
          runCode: "RUN-20260904-00000099",
          preflightRunId: null,
          preflightSnapshotHash: null,
        }),
      heartbeat: () => {
        heartbeatCalls++;
        return Promise.resolve({
          outcome: "OK",
          runId: "run-1",
          status: "ACQUIRING",
          heartbeatAt: "2026-09-04T00:00:00Z",
        });
      },
      plan: (_runId, snapshot) => {
        callOrder.push("plan-called");
        planCalledWithSnapshot = snapshot;
        return Promise.resolve({
          outcome: "COMPLETED",
          runId: "run-1",
          status: "COMPLETED",
          snapshotHash: "a".repeat(64),
          planSummary: { ok: true },
        });
      },
      apply: () => Promise.reject(new Error("DRY_RUN não deveria chamar apply")),
      closeFailed: () => Promise.resolve({ outcome: "FAILED", runId: "run-1", status: "FAILED" }),
    };
    const dryRunResult = await runDryRun({
      port: fakePort,
      snapshotStore: fakeStore,
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert("runDryRun (integração): COMPLETED de ponta a ponta", dryRunResult.kind === "COMPLETED");
    assert(
      "runDryRun (integração): heartbeat chamado ANTES da aquisição (precondição ACQUIRING do PLAN)",
      heartbeatCalls >= 1,
    );
    assert(
      "runDryRun (integração): PLAN recebeu o snapshot com Region/Species normalizados",
      (planCalledWithSnapshot as PokemonCatalogSnapshot | null)?.regions?.[0]?.code === "KANTO" &&
        (planCalledWithSnapshot as PokemonCatalogSnapshot | null)?.species?.[0]?.national_dex_number === 1,
    );
    assert(
      "runDryRun (integração) [REVISION-01]: store.save só é chamado APÓS plan() resolver — nunca antes (ordem real de chamadas)",
      callOrder.join(",") === "plan-called,store-save-called",
    );
    assert(
      "runDryRun (integração) [REVISION-01/02]: snapshot salvo localmente é o ENVELOPE run_id/run_code/hash/planOutcome + snapshot (vínculo inequívoco ao preflight)",
      savedRecords.get("RUN-20260904-00000099")?.runId === "run-1" &&
        savedRecords.get("RUN-20260904-00000099")?.runCode === "RUN-20260904-00000099" &&
        savedRecords.get("RUN-20260904-00000099")?.snapshotHash === "a".repeat(64) &&
        savedRecords.get("RUN-20260904-00000099")?.planOutcome === "COMPLETED",
    );
  }

  // ---- acquisition.ts [auditoria item 1]: heartbeat é renovado DURANTE uma
  // fase Species longa (não apenas uma vez no início da aquisição) — usa uma
  // lista de 120 Species (> 2x HEARTBEAT_INTERVAL_ITEMS=50) para provar que
  // o callback onHeartbeat é acionado periodicamente ao longo do loop, além
  // das renovações incondicionais entre fases (Regions->Generations->
  // Species). ----
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const SPECIES_COUNT = 120;
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/generation/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokemon-species/`]: {
        count: SPECIES_COUNT,
        next: null,
        previous: null,
        results: Array.from({ length: SPECIES_COUNT }, (_, i) => ({
          name: `species-${i + 1}`,
          url: `${BASE}/pokemon-species/${i + 1}/`,
        })),
      },
      // REVISION-04 — o GET real de aquisição/autoridade é `/pokedex/national/`
      // (contrato canônico); `/pokedex/1/` é exclusivamente o `source_url`
      // gravado no snapshot final (ver teste dedicado mais abaixo).
      [`${BASE}/pokedex/national/`]: {
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: Array.from({ length: SPECIES_COUNT }, (_, i) => ({
          entry_number: i + 1,
          pokemon_species: { name: `species-${i + 1}`, url: `${BASE}/pokemon-species/${i + 1}/` },
        })),
      },
    };
    for (let i = 1; i <= SPECIES_COUNT; i++) {
      routes[`${BASE}/pokemon-species/${i}/`] = {
        id: i,
        name: `species-${i}`,
        names: namesEn(`Species ${i}`),
        generation: { name: "generation-i", url: `${BASE}/generation/1/` },
        pokedex_numbers: [{ entry_number: i, pokedex: { name: "national", url: "" } }],
      };
    }
    const fakeFetch = (async (url: string) => {
      const body = routes[url];
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;

    let heartbeatCallsDuringAcquisition = 0;
    const acquisition = await acquirePokemonCatalogSnapshot({
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
      concurrency: 5,
      onHeartbeat: () => {
        heartbeatCallsDuringAcquisition++;
        return Promise.resolve();
      },
    });
    assert(
      "acquisition (heartbeat periódico) [auditoria item 1]: 120 Species processadas com sucesso",
      acquisition.status === "SUCCESS" && acquisition.species.length === SPECIES_COUNT,
    );
    // Renovações incondicionais entre fases (Regions->Generations,
    // Generations->Species) = 2, MAIS ao menos floor(120/50) = 2 renovações
    // periódicas dentro do próprio loop de Species (a cada
    // HEARTBEAT_INTERVAL_ITEMS itens concluídos) => mínimo de 4 chamadas,
    // estritamente mais que "uma vez no início".
    assert(
      "acquisition (heartbeat periódico) [auditoria item 1]: heartbeat é renovado MÚLTIPLAS vezes durante uma fase Species longa, não apenas uma vez no início",
      heartbeatCallsDuringAcquisition >= 4,
    );
  }

  // ---- acquisition.ts [REVISION-05, Bloco 3 residual físico]: heartbeat é
  // renovado DURANTE uma fase Region longa — mesmo checkpoint por item já
  // comprovado acima para Species, agora também cobrindo Region (auditoria
  // física encontrou que só Species e discovery tinham o checkpoint;
  // Region/Generation renovavam só nas transições de fase). 120 Regions,
  // Generation/Species vazios, para isolar a fase sob teste. ----
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const REGION_COUNT = 120;
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: {
        count: REGION_COUNT,
        next: null,
        previous: null,
        results: Array.from({ length: REGION_COUNT }, (_, i) => ({
          name: `region-${i + 1}`,
          url: `${BASE}/region/${i + 1}/`,
        })),
      },
      [`${BASE}/generation/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokemon-species/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokedex/national/`]: {
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [],
      },
    };
    for (let i = 1; i <= REGION_COUNT; i++) {
      routes[`${BASE}/region/${i}/`] = {
        id: i,
        name: `region-${i}`,
        names: namesEn(`Region ${i}`),
      };
    }
    const fakeFetch = (async (url: string) => {
      const body = routes[url];
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;

    let heartbeatCallsDuringAcquisition = 0;
    const acquisition = await acquirePokemonCatalogSnapshot({
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
      concurrency: 5,
      onHeartbeat: () => {
        heartbeatCallsDuringAcquisition++;
        return Promise.resolve();
      },
    });
    assert(
      "acquisition (heartbeat periódico) [REVISION-05]: 120 Regions processadas com sucesso",
      acquisition.status === "SUCCESS" && acquisition.regions.length === REGION_COUNT,
    );
    // Antes da correção, Region só renovava heartbeat nas 3 transições
    // incondicionais de fase (discovery concluído, antes de Generations,
    // antes de Species) — nunca durante o próprio loop de itens. Exigir >=
    // REGION_COUNT prova que o checkpoint por item está ativo (só ele já
    // produz 120 chamadas, muito além das 3 incondicionais).
    assert(
      "acquisition (heartbeat periódico) [REVISION-05]: heartbeat é renovado DURANTE a fase Region longa (checkpoint por item), não apenas nas transições de fase",
      heartbeatCallsDuringAcquisition >= REGION_COUNT,
    );
  }

  // ---- acquisition.ts [REVISION-05, Bloco 3 residual físico]: mesmo
  // checkpoint por item, agora para Generation. Region/Species vazios para
  // isolar a fase. Todas as 120 Generations reaproveitam o mesmo slug
  // "generation-i" (ordinal 1) — válido para este teste porque acquisition.ts
  // não impõe unicidade de ordinal/slug entre itens; só a extração precisa
  // ser bem-sucedida por item. ----
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const GENERATION_COUNT = 120;
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/generation/`]: {
        count: GENERATION_COUNT,
        next: null,
        previous: null,
        results: Array.from({ length: GENERATION_COUNT }, (_, i) => ({
          name: `generation-${i + 1}`,
          url: `${BASE}/generation/${i + 1}/`,
        })),
      },
      [`${BASE}/pokemon-species/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokedex/national/`]: {
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [],
      },
    };
    for (let i = 1; i <= GENERATION_COUNT; i++) {
      routes[`${BASE}/generation/${i}/`] = {
        id: i,
        name: "generation-i",
        names: namesEn(`Generation ${i}`),
        main_region: { name: "kanto", url: `${BASE}/region/1/` },
      };
    }
    const fakeFetch = (async (url: string) => {
      const body = routes[url];
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;

    let heartbeatCallsDuringAcquisition = 0;
    const acquisition = await acquirePokemonCatalogSnapshot({
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
      concurrency: 5,
      onHeartbeat: () => {
        heartbeatCallsDuringAcquisition++;
        return Promise.resolve();
      },
    });
    assert(
      "acquisition (heartbeat periódico) [REVISION-05]: 120 Generations processadas com sucesso",
      acquisition.status === "SUCCESS" && acquisition.generations.length === GENERATION_COUNT,
    );
    assert(
      "acquisition (heartbeat periódico) [REVISION-05]: heartbeat é renovado DURANTE a fase Generation longa (checkpoint por item), não apenas nas transições de fase",
      heartbeatCallsDuringAcquisition >= GENERATION_COUNT,
    );
  }

  // ---- orchestrator.ts [REVISION-05, Bloco 3 residual físico]:
  // createHeartbeatAwareWait — espera curta (<= chunkMs) não precisa de
  // heartbeat intermediário; o tempo total aguardado continua exatamente o
  // solicitado. ----
  {
    let heartbeatCalls = 0;
    const waitCalls: number[] = [];
    const wait = createHeartbeatAwareWait(
      (ms: number) => {
        waitCalls.push(ms);
        return Promise.resolve();
      },
      () => {
        heartbeatCalls++;
        return Promise.resolve();
      },
      1_000,
    );
    await wait(800);
    assert(
      "createHeartbeatAwareWait [REVISION-05]: espera <= chunkMs -> nenhum heartbeat intermediário, tempo total preservado EXATAMENTE",
      heartbeatCalls === 0 && waitCalls.length === 1 && waitCalls[0] === 800,
    );
  }

  // ---- orchestrator.ts + http.ts [REVISION-05, Bloco 3 residual físico]:
  // Retry-After longo NUNCA pode deixar o run sem heartbeat pelo tempo total
  // da espera. Prova, através de fetchJsonWithRetry REAL (não um mock do
  // próprio retry), que (1) o tempo total efetivamente aguardado bate
  // EXATAMENTE com o Retry-After declarado pelo servidor (1800s = stale
  // threshold de 30min) — a política de retry/Retry-After nunca é alterada
  // pelo chunking; e (2) o heartbeat é invocado MÚLTIPLAS vezes DURANTE essa
  // espera, não apenas uma vez no fim. chunkMs=10_000 aqui é só para o teste
  // rodar sem qualquer delay real (waitImpl injetado resolve
  // instantaneamente) — produção usa HEARTBEAT_AWARE_WAIT_CHUNK_MS (1min). ----
  {
    const RETRY_AFTER_SECONDS = 1800; // 30min — exatamente o stale threshold (Query 6103)
    const RETRY_AFTER_MS = RETRY_AFTER_SECONDS * 1000;
    let attempt = 0;
    const fakeFetch = (async () => {
      attempt++;
      if (attempt === 1) {
        return new Response("rate limited", {
          status: 429,
          headers: { "Retry-After": String(RETRY_AFTER_SECONDS) },
        });
      }
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }) as unknown as typeof fetch;

    const waitCalls: number[] = [];
    const rawWait = (ms: number) => {
      waitCalls.push(ms);
      return Promise.resolve();
    };
    let heartbeatDuringWaitCalls = 0;
    const heartbeatAwareWait = createHeartbeatAwareWait(
      rawWait,
      () => {
        heartbeatDuringWaitCalls++;
        return Promise.resolve();
      },
      10_000,
    );

    const result = await fetchJsonWithRetry("https://pokeapi.co/api/v2/pokedex/national/", {
      fetchImpl: fakeFetch,
      waitImpl: heartbeatAwareWait,
    });

    assert(
      "createHeartbeatAwareWait [REVISION-05]: Retry-After de 1800s -> tempo total efetivamente aguardado (soma de todas as chamadas internas a waitImpl) bate EXATAMENTE com o valor declarado pelo servidor, política de retry preservada (2ª tentativa SUCCESS)",
      result.status === "SUCCESS" &&
        attempt === 2 &&
        waitCalls.reduce((a, b) => a + b, 0) === RETRY_AFTER_MS,
    );
    assert(
      "createHeartbeatAwareWait [REVISION-05]: heartbeat é invocado MÚLTIPLAS vezes DURANTE a espera de Retry-After longa (1800s), não apenas uma vez no fim",
      heartbeatDuringWaitCalls >= 10,
    );
  }

  // ---- orchestrator.ts: DRY_RUN/APPLY sem HTTP indevido (Seção 8/10) ----
  {
    let fetchCalls = 0;
    const fakeFetch = (() => {
      fetchCalls++;
      return Promise.reject(new Error("não deveria ter chamado fetch"));
    }) as unknown as typeof fetch;
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "SOURCE_BUSY",
          runId: null,
          runCode: null,
          preflightRunId: null,
          preflightSnapshotHash: null,
        }),
      heartbeat: () => Promise.reject(new Error("não deveria chamar heartbeat")),
      plan: () => Promise.reject(new Error("não deveria chamar plan")),
      apply: () => Promise.reject(new Error("não deveria chamar apply")),
      closeFailed: () => Promise.reject(new Error("não deveria chamar closeFailed")),
    };
    const fakeStore = { save: () => Promise.resolve("x"), load: () => Promise.resolve(null) };
    const result = await runDryRun({
      port: fakePort,
      snapshotStore: fakeStore,
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "runDryRun: SOURCE_BUSY encerra IMEDIATAMENTE, sem qualquer chamada HTTP",
      result.kind === "SOURCE_BUSY" && fetchCalls === 0,
    );
  }
  {
    // Garantia estrutural: ApplyDeps não tem fetchImpl — runApply() é
    // fisicamente incapaz de fazer HTTP (não há import de fetch/http.ts em
    // orchestrator.ts para o caminho de APPLY). Este teste confirma o
    // comportamento observável: reutiliza EXATAMENTE o snapshot salvo.
    const savedRecords = new Map<string, PlannedSnapshotRecord>();
    const approvedSnapshot: PokemonCatalogSnapshot = {
      regions: [],
      generations: [],
      species: [],
      national_pokedex: {
        external_pokedex_id: "1",
        code: "NATIONAL",
        canonical_name: "National",
        source_url: "n",
        metadata: {},
      },
      national_pokedex_entries: [],
    };
    const approvedRecord: PlannedSnapshotRecord = {
      runId: "preflight-uuid",
      runCode: "RUN-20260904-00000001",
      snapshotHash: "c".repeat(64),
      planOutcome: "COMPLETED",
      snapshot: approvedSnapshot,
    };
    savedRecords.set(approvedRecord.runCode, approvedRecord);
    const fakeStore = {
      save: (record: PlannedSnapshotRecord) => {
        savedRecords.set(record.runCode, record);
        return Promise.resolve(record.runCode);
      },
      load: (code: string) => Promise.resolve(savedRecords.get(code) ?? null),
    };
    let applyCalledWithSnapshot: PokemonCatalogSnapshot | null = null;
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: (_type, preflightId) =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-apply-1",
          runCode: "RUN-20260904-00000002",
          preflightRunId: preflightId,
          // REVISION-03 (Bloco 4): precisa bater com approvedRecord.snapshotHash
          // — runApply() agora valida isto pós-openRun(APPLY) antes de chamar apply().
          preflightSnapshotHash: approvedRecord.snapshotHash,
        }),
      heartbeat: () => Promise.reject(new Error("APPLY não deveria chamar heartbeat")),
      plan: () => Promise.reject(new Error("APPLY não deveria chamar plan")),
      apply: (_runId, snapshot) => {
        applyCalledWithSnapshot = snapshot;
        return Promise.resolve({
          outcome: "COMPLETED",
          runId: "run-apply-1",
          status: "COMPLETED",
          applySummary: { ok: true },
        });
      },
      closeFailed: () =>
        Promise.resolve({ outcome: "FAILED", runId: "run-apply-1", status: "FAILED" }),
    };
    const result = await runApply({
      port: fakePort,
      snapshotStore: fakeStore,
      preflightRunId: "preflight-uuid",
      preflightRunCode: "RUN-20260904-00000001",
    });
    assert(
      "runApply: COMPLETED reutilizando EXATAMENTE o snapshot salvo pelo DRY_RUN (zero regeneração)",
      result.kind === "COMPLETED" && applyCalledWithSnapshot === approvedSnapshot,
    );
  }
  {
    // Auditoria item 4 — vínculo inequívoco run_id/run_code/hash: se o
    // envelope gravado em disco pertence a um run_id diferente do
    // preflightRunId solicitado, runApply() barra ANTES de abrir run ou
    // chamar apply — nunca confia apenas no nome do arquivo/run_code.
    const mismatchedRecord: PlannedSnapshotRecord = {
      runId: "run-id-diferente-do-solicitado",
      runCode: "RUN-20260904-00000003",
      snapshotHash: "d".repeat(64),
      // planOutcome=COMPLETED de propósito: isola este teste à checagem de
      // runId, sem se confundir com a checagem de elegibilidade (REVISION-02).
      planOutcome: "COMPLETED",
      snapshot: {
        regions: [],
        generations: [],
        species: [],
        national_pokedex: {
          external_pokedex_id: "1",
          code: "NATIONAL",
          canonical_name: "National",
          source_url: "n",
          metadata: {},
        },
        national_pokedex_entries: [],
      },
    };
    const fakeStore = {
      save: () => Promise.reject(new Error("n/a")),
      load: () => Promise.resolve(mismatchedRecord),
    };
    let openCalled = false;
    let applyCalled = false;
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () => {
        openCalled = true;
        return Promise.resolve({
          outcome: "CLAIMED",
          runId: "x",
          runCode: "x",
          preflightRunId: null,
          preflightSnapshotHash: null,
        });
      },
      heartbeat: () => Promise.reject(new Error("n/a")),
      plan: () => Promise.reject(new Error("n/a")),
      apply: () => {
        applyCalled = true;
        return Promise.reject(new Error("n/a"));
      },
      closeFailed: () => Promise.resolve({ outcome: "FAILED", runId: "x", status: "FAILED" }),
    };
    const result = await runApply({
      port: fakePort,
      snapshotStore: fakeStore,
      preflightRunId: "preflight-uuid-esperado",
      preflightRunCode: "RUN-20260904-00000003",
    });
    assert(
      "runApply [REVISION-01]: run_id do envelope divergente do preflightRunId solicitado -> SNAPSHOT_MISMATCH, sem abrir run nem chamar apply",
      result.kind === "SNAPSHOT_MISMATCH" && !openCalled && !applyCalled,
    );
  }
  {
    // REVISION-02, isolado: runId BATE (nenhum SNAPSHOT_MISMATCH), mas
    // planOutcome=COMPLETED_WITH_DIVERGENCES -> PREFLIGHT_NOT_ELIGIBLE,
    // barrado ANTES de abrir run ou chamar apply. Prova que a checagem de
    // elegibilidade é independente da checagem de identidade (runId).
    const divergentRecord: PlannedSnapshotRecord = {
      runId: "preflight-uuid-elegibilidade",
      runCode: "RUN-20260904-00000004",
      snapshotHash: "e".repeat(64),
      planOutcome: "COMPLETED_WITH_DIVERGENCES",
      snapshot: {
        regions: [],
        generations: [],
        species: [],
        national_pokedex: {
          external_pokedex_id: "1",
          code: "NATIONAL",
          canonical_name: "National",
          source_url: "n",
          metadata: {},
        },
        national_pokedex_entries: [],
      },
    };
    const fakeStore = {
      save: () => Promise.reject(new Error("n/a")),
      load: () => Promise.resolve(divergentRecord),
    };
    let openCalled = false;
    let applyCalled = false;
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () => {
        openCalled = true;
        return Promise.resolve({
          outcome: "CLAIMED",
          runId: "x",
          runCode: "x",
          preflightRunId: null,
          preflightSnapshotHash: null,
        });
      },
      heartbeat: () => Promise.reject(new Error("n/a")),
      plan: () => Promise.reject(new Error("n/a")),
      apply: () => {
        applyCalled = true;
        return Promise.reject(new Error("n/a"));
      },
      closeFailed: () => Promise.resolve({ outcome: "FAILED", runId: "x", status: "FAILED" }),
    };
    const result = await runApply({
      port: fakePort,
      snapshotStore: fakeStore,
      preflightRunId: "preflight-uuid-elegibilidade",
      preflightRunCode: "RUN-20260904-00000004",
    });
    assert(
      "runApply [REVISION-02]: runId correto mas planOutcome=COMPLETED_WITH_DIVERGENCES -> PREFLIGHT_NOT_ELIGIBLE, sem abrir run nem chamar apply",
      result.kind === "PREFLIGHT_NOT_ELIGIBLE" && !openCalled && !applyCalled,
    );
  }
  {
    let openCalled = false;
    const fakeStore = { save: () => Promise.resolve("x"), load: () => Promise.resolve(null) };
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () => {
        openCalled = true;
        return Promise.resolve({
          outcome: "CLAIMED",
          runId: "x",
          runCode: "x",
          preflightRunId: null,
          preflightSnapshotHash: null,
        });
      },
      heartbeat: () => Promise.reject(new Error("n/a")),
      plan: () => Promise.reject(new Error("n/a")),
      apply: () => Promise.reject(new Error("n/a")),
      closeFailed: () => Promise.resolve({ outcome: "FAILED", runId: "x", status: "FAILED" }),
    };
    const result = await runApply({
      port: fakePort,
      snapshotStore: fakeStore,
      preflightRunId: "p",
      preflightRunCode: "RUN-INEXISTENTE",
    });
    assert(
      "runApply: snapshot local ausente -> SNAPSHOT_NOT_FOUND, NUNCA abre run (evita consumir o guard de concorrência à toa)",
      result.kind === "SNAPSHOT_NOT_FOUND" && !openCalled,
    );
  }

  // ---- orchestrator.ts [REVISION-02]: comportamento ponta a ponta por
  // outcome de PLAN:
  //  - COMPLETED_WITH_DIVERGENCES: snapshot É salvo (valor de auditoria/
  //    diagnóstico — REVISION-02 corrige a rodada anterior, que descartava
  //    esse snapshot), mas um runApply() subsequente é barrado ANTES de
  //    abrir run, com PREFLIGHT_NOT_ELIGIBLE (planOutcome != COMPLETED).
  //  - VALIDATION_FAILURE / PAYLOAD_GUARD_EXCEEDED: nenhum registro é
  //    criado; um runApply() subsequente resulta em SNAPSHOT_NOT_FOUND. ----
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "kanto", url: `${BASE}/region/1/` }],
      },
      [`${BASE}/generation/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "generation-i", url: `${BASE}/generation/1/` }],
      },
      [`${BASE}/pokemon-species/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "bulbasaur", url: `${BASE}/pokemon-species/1/` }],
      },
      [`${BASE}/region/1/`]: { id: 1, name: "kanto", names: namesEn("Kanto") },
      [`${BASE}/generation/1/`]: {
        id: 1,
        name: "generation-i",
        names: namesEn("Generation I"),
        main_region: { name: "kanto", url: `${BASE}/region/1/` },
      },
      [`${BASE}/pokemon-species/1/`]: {
        id: 1,
        name: "bulbasaur",
        names: namesEn("Bulbasaur"),
        generation: { name: "generation-i", url: `${BASE}/generation/1/` },
        pokedex_numbers: [{ entry_number: 1, pokedex: { name: "national", url: "" } }],
      },
      // REVISION-04 — o GET real de aquisição/autoridade é `/pokedex/national/`
      // (contrato canônico); `/pokedex/1/` é exclusivamente o `source_url`
      // gravado no snapshot final (ver teste dedicado mais abaixo).
      [`${BASE}/pokedex/national/`]: {
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [
          { entry_number: 1, pokemon_species: { name: "bulbasaur", url: `${BASE}/pokemon-species/1/` } },
        ],
      },
    };
    const fakeFetch = (async (url: string) => {
      const body = routes[url];
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;

    const cenarios: Array<
      {
        planOutcome: "COMPLETED_WITH_DIVERGENCES" | "VALIDATION_FAILURE" | "PAYLOAD_GUARD_EXCEEDED";
        expectedDryRunKind: string;
        expectSaved: boolean;
        expectedApplyKind: string;
      }
    > = [
      {
        planOutcome: "COMPLETED_WITH_DIVERGENCES",
        expectedDryRunKind: "COMPLETED_WITH_DIVERGENCES",
        expectSaved: true,
        expectedApplyKind: "PREFLIGHT_NOT_ELIGIBLE",
      },
      {
        planOutcome: "VALIDATION_FAILURE",
        expectedDryRunKind: "PLAN_VALIDATION_FAILURE",
        expectSaved: false,
        expectedApplyKind: "SNAPSHOT_NOT_FOUND",
      },
      {
        planOutcome: "PAYLOAD_GUARD_EXCEEDED",
        expectedDryRunKind: "PAYLOAD_GUARD_EXCEEDED",
        expectSaved: false,
        expectedApplyKind: "SNAPSHOT_NOT_FOUND",
      },
    ];

    for (const cenario of cenarios) {
      const savedRecords = new Map<string, PlannedSnapshotRecord>();
      const fakeStore = {
        save: (record: PlannedSnapshotRecord) => {
          savedRecords.set(record.runCode, record);
          return Promise.resolve(record.runCode);
        },
        load: (code: string) => Promise.resolve(savedRecords.get(code) ?? null),
      };
      const runCode = `RUN-20260904-DIVERGENT-${cenario.planOutcome}`;
      let openCalledDuringApply = false;
      const fakePort: PokemonCatalogSourcingPort = {
        openRun: () => {
          openCalledDuringApply = true;
          return Promise.resolve({
            outcome: "CLAIMED",
            runId: "run-div-1",
            runCode,
            preflightRunId: null,
            preflightSnapshotHash: null,
          });
        },
        heartbeat: () =>
          Promise.resolve({
            outcome: "OK",
            runId: "run-div-1",
            status: "ACQUIRING",
            heartbeatAt: "2026-09-04T00:00:00Z",
          }),
        plan: () =>
          Promise.resolve({
            outcome: cenario.planOutcome,
            runId: "run-div-1",
            status: cenario.planOutcome,
            snapshotHash: cenario.planOutcome === "COMPLETED_WITH_DIVERGENCES" ? "b".repeat(64) : null,
            planSummary: cenario.planOutcome === "COMPLETED_WITH_DIVERGENCES" ? { divergences: 1 } : null,
          }),
        apply: () => Promise.reject(new Error("não deveria chamar apply")),
        closeFailed: () =>
          Promise.resolve({ outcome: "FAILED", runId: "run-div-1", status: "FAILED" }),
      };
      // openRun() é usado tanto pelo DRY_RUN inicial quanto por um eventual
      // APPLY subsequente — zera o flag antes de medir especificamente a
      // chamada de runApply() abaixo.
      const dryRunResult = await runDryRun({
        port: fakePort,
        snapshotStore: fakeStore,
        fetchImpl: fakeFetch,
        waitImpl: () => Promise.resolve(),
      });
      assert(
        `runDryRun [REVISION-02]: PLAN ${cenario.planOutcome} -> outcome ${cenario.expectedDryRunKind}`,
        dryRunResult.kind === cenario.expectedDryRunKind,
      );
      assert(
        cenario.expectSaved
          ? `runDryRun [REVISION-02]: PLAN ${cenario.planOutcome} PERSISTE snapshot local (planOutcome=${cenario.planOutcome} no envelope, não descartado)`
          : `runDryRun [REVISION-02]: PLAN ${cenario.planOutcome} NUNCA persiste snapshot local (nenhum registro salvo para este run_code)`,
        cenario.expectSaved
          ? savedRecords.get(runCode)?.planOutcome === cenario.planOutcome
          : !savedRecords.has(runCode),
      );

      openCalledDuringApply = false;
      const applyResult = await runApply({
        port: fakePort,
        snapshotStore: fakeStore,
        preflightRunId: "run-div-1",
        preflightRunCode: runCode,
      });
      assert(
        `runApply [REVISION-02]: preflight originado de PLAN ${cenario.planOutcome} -> ${cenario.expectedApplyKind}, SEM abrir run`,
        applyResult.kind === cenario.expectedApplyKind && !openCalledDuringApply,
      );
    }
  }

  // ==========================================================================
  // REVISION-03 — TESTES ADVERSARIAIS (5 blocos da auditoria física)
  // ==========================================================================

  // ---- Bloco 3 (HTTP/Heartbeat): allowlist de origem ANTES de qualquer
  // chamada de rede — fetchJsonWithRetry é o funil único. ----
  {
    let calls = 0;
    const fakeFetch = (async () => {
      calls++;
      return new Response("{}", { status: 200 });
    }) as unknown as typeof fetch;
    const result = await fetchJsonWithRetry("https://evil.example.com/api/v2/pokemon/1/", {
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "fetchJsonWithRetry [Bloco 3]: URL fora do allowlist -> TECHNICAL_FAILURE ANTES de qualquer chamada de rede (fetchImpl nunca invocado)",
      result.status === "TECHNICAL_FAILURE" && calls === 0,
    );
  }
  {
    // deno-lint-ignore no-explicit-any
    let capturedInit: any = null;
    // deno-lint-ignore no-explicit-any
    const fakeFetch = (async (_url: unknown, init: any) => {
      capturedInit = init;
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }) as unknown as typeof fetch;
    await fetchJsonWithRetry("https://pokeapi.co/api/v2/pokemon/1/", {
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      'fetchJsonWithRetry [Bloco 3]: toda chamada real usa redirect:"error" (nunca segue redirect para origem não permitida)',
      capturedInit?.redirect === "error",
    );
  }
  {
    // `next` malicioso apontando para fora do allowlist — discoverAllPaged
    // nunca segue o link, mesmo vindo de dentro de uma resposta 200 válida.
    let calls = 0;
    const fakeFetch = (async (url: string) => {
      calls++;
      if (url === "https://pokeapi.co/api/v2/pokemon-species/") {
        return new Response(
          JSON.stringify({
            count: 2,
            next: "https://evil.example.com/steal?page=2",
            previous: null,
            results: [{ name: "a", url: "https://pokeapi.co/api/v2/pokemon-species/1/" }],
          }),
          { status: 200 },
        );
      }
      return new Response("not found", { status: 404 });
    }) as unknown as typeof fetch;
    const result = await discoverAllPaged("https://pokeapi.co/api/v2/pokemon-species/", {
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "discoverAllPaged [Bloco 3]: `next` fora do allowlist -> TECHNICAL_FAILURE, NUNCA segue o link malicioso (só 1 chamada real)",
      result.status === "TECHNICAL_FAILURE" && calls === 1,
    );
  }
  {
    // concurrency também limita discovery (antes: Promise.all incondicional
    // disparava as 3 listagens simultaneamente mesmo com concurrency=1).
    const BASE = "https://pokeapi.co/api/v2";
    const listingUrls = [`${BASE}/region/`, `${BASE}/generation/`, `${BASE}/pokemon-species/`];
    let activeListing = 0;
    let maxActiveListing = 0;
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "kanto", url: `${BASE}/region/1/` }],
      },
      [`${BASE}/generation/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "generation-i", url: `${BASE}/generation/1/` }],
      },
      [`${BASE}/pokemon-species/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "bulbasaur", url: `${BASE}/pokemon-species/1/` }],
      },
      [`${BASE}/region/1/`]: { id: 1, name: "kanto", names: namesEn("Kanto") },
      [`${BASE}/generation/1/`]: {
        id: 1,
        name: "generation-i",
        names: namesEn("Generation I"),
        main_region: { name: "kanto", url: `${BASE}/region/1/` },
      },
      [`${BASE}/pokemon-species/1/`]: {
        id: 1,
        name: "bulbasaur",
        names: namesEn("Bulbasaur"),
        generation: { name: "generation-i", url: `${BASE}/generation/1/` },
        pokedex_numbers: [{ entry_number: 1, pokedex: { name: "national", url: "" } }],
      },
      [`${BASE}/pokedex/national/`]: {
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [
          { entry_number: 1, pokemon_species: { name: "bulbasaur", url: `${BASE}/pokemon-species/1/` } },
        ],
      },
    };
    const fakeFetch = (async (url: string) => {
      const isListing = listingUrls.includes(url);
      if (isListing) {
        activeListing++;
        maxActiveListing = Math.max(maxActiveListing, activeListing);
        // Ponto de interleaving real: se o código disparasse as 3 listagens
        // via Promise.all incondicional, esta pausa deixaria as 3 ativas ao
        // mesmo tempo antes de qualquer uma resolver.
        await new Promise((r) => setTimeout(r, 5));
      }
      const body = routes[url];
      if (isListing) activeListing--;
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;

    const acquisition = await acquirePokemonCatalogSnapshot({
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
      concurrency: 1,
    });
    assert(
      "acquisition [Bloco 3]: concurrency=1 nunca permite mais de 1 listagem de discovery ativa simultaneamente (region/generation/species)",
      acquisition.status === "SUCCESS" && maxActiveListing <= 1,
    );
  }
  {
    // createHeartbeatGate: gating estritamente temporal, nunca por contagem.
    let now = 1_000;
    let calls = 0;
    const gate = createHeartbeatGate(() => {
      calls++;
      return Promise.resolve();
    }, () => now, 100);
    await gate(); // delta=0 desde a construção -> não dispara
    assert(
      "createHeartbeatGate: chamada imediatamente após construção (delta=0) não dispara heartbeat",
      calls === 0,
    );
    now = 1_050; // delta 50 < 100
    await gate();
    assert(
      "createHeartbeatGate: chamada antes do intervalo mínimo não dispara heartbeat",
      calls === 0,
    );
    now = 1_101; // delta 101 >= 100
    await gate();
    assert(
      "createHeartbeatGate: chamada após o intervalo mínimo dispara heartbeat exatamente uma vez",
      calls === 1,
    );
    now = 1_150; // delta desde o último beat (1101) = 49 < 100
    await gate();
    assert(
      "createHeartbeatGate: reseta o relógio após disparar — chamada logo em seguida não dispara de novo",
      calls === 1,
    );
  }
  {
    const gate = createHeartbeatGate(undefined, () => 9_999_999, 1);
    await gate();
    assert("createHeartbeatGate: onHeartbeat ausente -> no-op seguro (nunca lança)", true);
  }

  // ---- Bloco 1 (National Authority): validação de identidade do recurso
  // /pokedex/national/ (id===1, name==="national") ANTES de aceitar como
  // autoridade — REVISION-04: o GET real de aquisição é /pokedex/national/
  // (contrato canônico), nunca /pokedex/1/ (que é só o source_url gravado no
  // snapshot). ----
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const baseRoutes = (): Record<string, unknown> => ({
      [`${BASE}/region/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/generation/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokemon-species/`]: { count: 0, next: null, previous: null, results: [] },
    });
    {
      const routes = baseRoutes();
      routes[`${BASE}/pokedex/national/`] = {
        id: 999,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [],
      };
      const fakeFetch = (async (url: string) => {
        const body = routes[url];
        if (!body) return new Response("not found", { status: 404 });
        return new Response(JSON.stringify(body), { status: 200 });
      }) as unknown as typeof fetch;
      const acquisition = await acquirePokemonCatalogSnapshot({
        fetchImpl: fakeFetch,
        waitImpl: () => Promise.resolve(),
        concurrency: 5,
      });
      assert(
        "acquisition [Bloco 1]: /pokedex/national/ retornando id != 1 -> VALIDATION_ISSUES com NATIONAL_POKEDEX_ID_MISMATCH",
        acquisition.status === "VALIDATION_ISSUES" &&
          acquisition.issues.some((i) =>
            i.stage === "NATIONAL_POKEDEX" && i.reason.startsWith("NATIONAL_POKEDEX_ID_MISMATCH")
          ),
      );
    }
    {
      const routes = baseRoutes();
      routes[`${BASE}/pokedex/national/`] = {
        id: 1,
        name: "nacional-errado",
        names: namesEn("National"),
        pokemon_entries: [],
      };
      const fakeFetch = (async (url: string) => {
        const body = routes[url];
        if (!body) return new Response("not found", { status: 404 });
        return new Response(JSON.stringify(body), { status: 200 });
      }) as unknown as typeof fetch;
      const acquisition = await acquirePokemonCatalogSnapshot({
        fetchImpl: fakeFetch,
        waitImpl: () => Promise.resolve(),
        concurrency: 5,
      });
      assert(
        'acquisition [Bloco 1]: /pokedex/national/ retornando name != "national" -> VALIDATION_ISSUES com NATIONAL_POKEDEX_NAME_MISMATCH',
        acquisition.status === "VALIDATION_ISSUES" &&
          acquisition.issues.some((i) =>
            i.stage === "NATIONAL_POKEDEX" && i.reason.startsWith("NATIONAL_POKEDEX_NAME_MISMATCH")
          ),
      );
    }
  }
  {
    // REVISION-04: o fetch real de aquisição/autoridade usa `/pokedex/national/`
    // (contrato canônico); o snapshot final enviado a PLAN, por sua vez, grava
    // `national_pokedex.source_url` como `/pokedex/1/` — os dois valores são
    // deliberadamente diferentes (endpoint de aquisição vs. source_url do
    // snapshot), nunca o mesmo.
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/generation/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokemon-species/`]: {
        count: 1,
        next: null,
        previous: null,
        results: [{ name: "bulbasaur", url: `${BASE}/pokemon-species/1/` }],
      },
      [`${BASE}/pokemon-species/1/`]: {
        id: 1,
        name: "bulbasaur",
        names: namesEn("Bulbasaur"),
        generation: { name: "generation-i", url: `${BASE}/generation/1/` },
        pokedex_numbers: [{ entry_number: 1, pokedex: { name: "national", url: "" } }],
      },
      [`${BASE}/pokedex/national/`]: {
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [
          { entry_number: 1, pokemon_species: { name: "bulbasaur", url: `${BASE}/pokemon-species/1/` } },
        ],
      },
    };
    const fakeFetch = (async (url: string) => {
      const body = routes[url];
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;
    let planCalledWithSnapshot: PokemonCatalogSnapshot | null = null;
    const fakeStore = { save: () => Promise.resolve("x"), load: () => Promise.resolve(null) };
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-src-1",
          runCode: "RUN-20260904-00000030",
          preflightRunId: null,
          preflightSnapshotHash: null,
        }),
      heartbeat: () =>
        Promise.resolve({ outcome: "OK", runId: "run-src-1", status: "ACQUIRING", heartbeatAt: "2026-09-04T00:00:00Z" }),
      plan: (_runId, snapshot) => {
        planCalledWithSnapshot = snapshot;
        return Promise.resolve({
          outcome: "COMPLETED",
          runId: "run-src-1",
          status: "COMPLETED",
          snapshotHash: "i".repeat(64),
          planSummary: {},
        });
      },
      apply: () => Promise.reject(new Error("n/a")),
      closeFailed: () => Promise.resolve({ outcome: "FAILED", runId: "run-src-1", status: "FAILED" }),
    };
    await runDryRun({
      port: fakePort,
      snapshotStore: fakeStore,
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "runDryRun [Bloco 1]: snapshot enviado a PLAN tem national_pokedex.source_url == https://pokeapi.co/api/v2/pokedex/1/ (endpoint de aquisição foi /pokedex/national/, source_url do snapshot é sempre /pokedex/1/ — nunca o mesmo valor)",
      (planCalledWithSnapshot as PokemonCatalogSnapshot | null)?.national_pokedex?.source_url ===
        "https://pokeapi.co/api/v2/pokedex/1/",
    );
  }

  // ---- REVISION-04 (teste combinado, pedido explicitamente pela auditoria
  // externa): prova SIMULTANEAMENTE, no mesmo fetch instrumentado, que (1) o
  // fetch real de aquisição/autoridade usa `/pokedex/national/` (nunca
  // `/pokedex/1/`); (2) uma resposta desse endpoint com id/name incompatíveis
  // falha a validação de identidade (Bloco 1); e (3) quando a resposta É
  // compatível, o snapshot final enviado a PLAN grava
  // `national_pokedex.source_url` como `https://pokeapi.co/api/v2/pokedex/1/`
  // — nunca o slug `/pokedex/national/` usado na aquisição. Os dois ramos
  // (falha e sucesso) compartilham o mesmo builder de fetch instrumentado,
  // contando explicitamente as chamadas a cada URL. ----
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    let nationalEndpointCallCount = 0;
    let pokedexOneEndpointCallCount = 0;

    function buildInstrumentedFetch(nationalBody: unknown): typeof fetch {
      const routes: Record<string, unknown> = {
        [`${BASE}/region/`]: { count: 0, next: null, previous: null, results: [] },
        [`${BASE}/generation/`]: { count: 0, next: null, previous: null, results: [] },
        [`${BASE}/pokemon-species/`]: {
          count: 1,
          next: null,
          previous: null,
          results: [{ name: "bulbasaur", url: `${BASE}/pokemon-species/1/` }],
        },
        [`${BASE}/pokemon-species/1/`]: {
          id: 1,
          name: "bulbasaur",
          names: namesEn("Bulbasaur"),
          generation: { name: "generation-i", url: `${BASE}/generation/1/` },
          pokedex_numbers: [{ entry_number: 1, pokedex: { name: "national", url: "" } }],
        },
        [`${BASE}/pokedex/national/`]: nationalBody,
      };
      return (async (url: string) => {
        if (url === `${BASE}/pokedex/national/`) nationalEndpointCallCount++;
        if (url === `${BASE}/pokedex/1/`) pokedexOneEndpointCallCount++;
        const body = routes[url];
        if (!body) return new Response("not found", { status: 404 });
        return new Response(JSON.stringify(body), { status: 200 });
      }) as unknown as typeof fetch;
    }

    // Ramo A: resposta com id incompatível -> falha ANTES de aceitar como
    // autoridade; o fetch instrumentado prova que /pokedex/national/ foi
    // usado e /pokedex/1/ nunca foi chamado.
    {
      const fakeFetch = buildInstrumentedFetch({
        id: 999,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [],
      });
      const acquisition = await acquirePokemonCatalogSnapshot({
        fetchImpl: fakeFetch,
        waitImpl: () => Promise.resolve(),
        concurrency: 5,
      });
      assert(
        "REVISION-04 [combinado] ramo A (id incompatível): fetch de autoridade usou /pokedex/national/ (nunca /pokedex/1/) e a resposta com id != 1 falhou a validação (VALIDATION_ISSUES/NATIONAL_POKEDEX_ID_MISMATCH)",
        nationalEndpointCallCount >= 1 &&
          pokedexOneEndpointCallCount === 0 &&
          acquisition.status === "VALIDATION_ISSUES" &&
          acquisition.issues.some((i) =>
            i.stage === "NATIONAL_POKEDEX" && i.reason.startsWith("NATIONAL_POKEDEX_ID_MISMATCH")
          ),
      );
    }

    // Ramo B: resposta compatível -> aceita como autoridade; o snapshot final
    // enviado a PLAN grava source_url como /pokedex/1/, mesmo o fetch real
    // tendo usado /pokedex/national/ (nunca o contrário).
    {
      nationalEndpointCallCount = 0;
      pokedexOneEndpointCallCount = 0;
      const fakeFetch = buildInstrumentedFetch({
        id: 1,
        name: "national",
        names: namesEn("National"),
        pokemon_entries: [
          { entry_number: 1, pokemon_species: { name: "bulbasaur", url: `${BASE}/pokemon-species/1/` } },
        ],
      });
      let planCalledWithSnapshot: PokemonCatalogSnapshot | null = null;
      const fakeStore = { save: () => Promise.resolve("x"), load: () => Promise.resolve(null) };
      const fakePort: PokemonCatalogSourcingPort = {
        openRun: () =>
          Promise.resolve({
            outcome: "CLAIMED",
            runId: "run-src-2",
            runCode: "RUN-20260904-00000031",
            preflightRunId: null,
            preflightSnapshotHash: null,
          }),
        heartbeat: () =>
          Promise.resolve({
            outcome: "OK",
            runId: "run-src-2",
            status: "ACQUIRING",
            heartbeatAt: "2026-09-04T00:00:00Z",
          }),
        plan: (_runId, snapshot) => {
          planCalledWithSnapshot = snapshot;
          return Promise.resolve({
            outcome: "COMPLETED",
            runId: "run-src-2",
            status: "COMPLETED",
            snapshotHash: "j".repeat(64),
            planSummary: {},
          });
        },
        apply: () => Promise.reject(new Error("n/a")),
        closeFailed: () => Promise.resolve({ outcome: "FAILED", runId: "run-src-2", status: "FAILED" }),
      };
      await runDryRun({
        port: fakePort,
        snapshotStore: fakeStore,
        fetchImpl: fakeFetch,
        waitImpl: () => Promise.resolve(),
      });
      assert(
        "REVISION-04 [combinado] ramo B (resposta compatível): fetch de autoridade usou /pokedex/national/ e o snapshot final enviado a PLAN grava national_pokedex.source_url == https://pokeapi.co/api/v2/pokedex/1/ (nunca o slug /pokedex/national/, que foi só o endpoint de aquisição)",
        nationalEndpointCallCount >= 1 &&
          pokedexOneEndpointCallCount === 0 &&
          (planCalledWithSnapshot as PokemonCatalogSnapshot | null)?.national_pokedex?.source_url ===
            "https://pokeapi.co/api/v2/pokedex/1/",
      );
    }
  }

  // ---- Bloco 5 (Operational Safety): heartbeat/plan lançam exceção após
  // CLAIMED -> closeFailed tentado; falha do PRÓPRIO closeFailed nunca
  // mascara o erro original. ----
  {
    let closeFailedCalls = 0;
    let fetchCalls = 0;
    const fakeStore = { save: () => Promise.reject(new Error("n/a")), load: () => Promise.resolve(null) };
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-hb-1",
          runCode: "RUN-20260904-00000010",
          preflightRunId: null,
          preflightSnapshotHash: null,
        }),
      heartbeat: () => Promise.reject(new Error("RPC_INDISPONIVEL")),
      plan: () => Promise.reject(new Error("não deveria chamar plan")),
      apply: () => Promise.reject(new Error("não deveria chamar apply")),
      closeFailed: (runId, errorSummary) => {
        closeFailedCalls++;
        void runId;
        void errorSummary;
        return Promise.resolve({ outcome: "FAILED", runId, status: "FAILED" });
      },
    };
    const fakeFetch = (() => {
      fetchCalls++;
      return Promise.reject(new Error("não deveria chamar fetch"));
    }) as unknown as typeof fetch;
    const result = await runDryRun({
      port: fakePort,
      snapshotStore: fakeStore,
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "runDryRun [Bloco 5]: heartbeat() lança exceção -> HEARTBEAT_FAILED, closeFailed tentado, ZERO chamadas HTTP",
      result.kind === "HEARTBEAT_FAILED" && closeFailedCalls === 1 && fetchCalls === 0 &&
        result.detail === "RPC_INDISPONIVEL",
    );
  }
  {
    const fakeStore = { save: () => Promise.reject(new Error("n/a")), load: () => Promise.resolve(null) };
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-hb-2",
          runCode: "RUN-20260904-00000011",
          preflightRunId: null,
          preflightSnapshotHash: null,
        }),
      heartbeat: () => Promise.reject(new Error("HEARTBEAT_ORIGINAL")),
      plan: () => Promise.reject(new Error("n/a")),
      apply: () => Promise.reject(new Error("n/a")),
      closeFailed: () => Promise.reject(new Error("CLOSE_FAILED_TAMBEM_FALHOU")),
    };
    const result = await runDryRun({
      port: fakePort,
      snapshotStore: fakeStore,
      fetchImpl: (() => Promise.reject(new Error("n/a"))) as unknown as typeof fetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "runDryRun [Bloco 5]: falha do PRÓPRIO closeFailed NÃO mascara o erro original de heartbeat (retorna HEARTBEAT_FAILED com a mensagem original)",
      result.kind === "HEARTBEAT_FAILED" && result.detail === "HEARTBEAT_ORIGINAL",
    );
  }
  {
    const BASE = "https://pokeapi.co/api/v2";
    const namesEn = (name: string) => [{ name, language: { name: "en", url: "" } }];
    const routes: Record<string, unknown> = {
      [`${BASE}/region/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/generation/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokemon-species/`]: { count: 0, next: null, previous: null, results: [] },
      [`${BASE}/pokedex/national/`]: { id: 1, name: "national", names: namesEn("National"), pokemon_entries: [] },
    };
    const fakeFetch = (async (url: string) => {
      const body = routes[url];
      if (!body) return new Response("not found", { status: 404 });
      return new Response(JSON.stringify(body), { status: 200 });
    }) as unknown as typeof fetch;
    let closeFailedCalls = 0;
    const fakeStore = { save: () => Promise.reject(new Error("não deveria salvar")), load: () => Promise.resolve(null) };
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-plan-1",
          runCode: "RUN-20260904-00000012",
          preflightRunId: null,
          preflightSnapshotHash: null,
        }),
      heartbeat: () =>
        Promise.resolve({ outcome: "OK", runId: "run-plan-1", status: "ACQUIRING", heartbeatAt: "2026-09-04T00:00:00Z" }),
      plan: () => Promise.reject(new Error("PLAN_RPC_INDISPONIVEL")),
      apply: () => Promise.reject(new Error("não deveria chamar apply")),
      closeFailed: () => {
        closeFailedCalls++;
        return Promise.resolve({ outcome: "FAILED", runId: "run-plan-1", status: "FAILED" });
      },
    };
    const result = await runDryRun({
      port: fakePort,
      snapshotStore: fakeStore,
      fetchImpl: fakeFetch,
      waitImpl: () => Promise.resolve(),
    });
    assert(
      "runDryRun [Bloco 5]: plan() lança exceção -> PLAN_EXCEPTION, closeFailed tentado, nenhum snapshot salvo",
      result.kind === "PLAN_EXCEPTION" && closeFailedCalls === 1 && result.detail === "PLAN_RPC_INDISPONIVEL",
    );
  }

  // ---- Bloco 4 (Snapshot Integrity): APPLY valida record.runCode ==
  // preflightRunCode, e após openRun(APPLY) valida preflightRunId/
  // preflightSnapshotHash retornados pelo banco contra o envelope local —
  // mismatch em qualquer um dos dois -> closeFailed + SNAPSHOT_MISMATCH,
  // `apply` NUNCA chamado. ----
  {
    const record: PlannedSnapshotRecord = {
      runId: "preflight-uuid-x",
      runCode: "RUN-20260904-00000020",
      snapshotHash: "f".repeat(64),
      planOutcome: "COMPLETED",
      snapshot: {
        regions: [],
        generations: [],
        species: [],
        national_pokedex: {
          external_pokedex_id: "1",
          code: "NATIONAL",
          canonical_name: "National",
          source_url: "n",
          metadata: {},
        },
        national_pokedex_entries: [],
      },
    };
    const fakeStore = { save: () => Promise.reject(new Error("n/a")), load: () => Promise.resolve(record) };
    let openCalled = false;
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () => {
        openCalled = true;
        return Promise.resolve({
          outcome: "CLAIMED",
          runId: "x",
          runCode: "x",
          preflightRunId: null,
          preflightSnapshotHash: null,
        });
      },
      heartbeat: () => Promise.reject(new Error("n/a")),
      plan: () => Promise.reject(new Error("n/a")),
      apply: () => Promise.reject(new Error("n/a")),
      closeFailed: () => Promise.resolve({ outcome: "FAILED", runId: "x", status: "FAILED" }),
    };
    const result = await runApply({
      port: fakePort,
      snapshotStore: fakeStore,
      preflightRunId: "preflight-uuid-x",
      // Chave de load DIFERENTE do runCode gravado dentro do próprio
      // envelope — a checagem é uma segunda camada independente da forma de
      // armazenamento/indexação usada pelo SnapshotStore concreto.
      preflightRunCode: "RUN-20260904-00000099",
    });
    assert(
      "runApply [Bloco 4]: record.runCode interno != preflightRunCode solicitado -> SNAPSHOT_MISMATCH, sem abrir run",
      result.kind === "SNAPSHOT_MISMATCH" && !openCalled,
    );
  }
  {
    const record: PlannedSnapshotRecord = {
      runId: "preflight-uuid-y",
      runCode: "RUN-20260904-00000021",
      snapshotHash: "g".repeat(64),
      planOutcome: "COMPLETED",
      snapshot: {
        regions: [],
        generations: [],
        species: [],
        national_pokedex: {
          external_pokedex_id: "1",
          code: "NATIONAL",
          canonical_name: "National",
          source_url: "n",
          metadata: {},
        },
        national_pokedex_entries: [],
      },
    };
    const fakeStore = { save: () => Promise.reject(new Error("n/a")), load: () => Promise.resolve(record) };
    let applyCalled = false;
    let closeFailedCalls = 0;
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-apply-mismatch",
          runCode: "RUN-20260904-00000022",
          // Banco resolveu um preflight DIFERENTE do envelope local -> divergência grave.
          preflightRunId: "preflight-uuid-DIFERENTE",
          preflightSnapshotHash: record.snapshotHash,
        }),
      heartbeat: () => Promise.reject(new Error("n/a")),
      plan: () => Promise.reject(new Error("n/a")),
      apply: () => {
        applyCalled = true;
        return Promise.reject(new Error("n/a"));
      },
      closeFailed: () => {
        closeFailedCalls++;
        return Promise.resolve({ outcome: "FAILED", runId: "run-apply-mismatch", status: "FAILED" });
      },
    };
    const result = await runApply({
      port: fakePort,
      snapshotStore: fakeStore,
      preflightRunId: record.runId,
      preflightRunCode: record.runCode,
    });
    assert(
      "runApply [Bloco 4]: banco retorna preflightRunId divergente do envelope local pós-openRun(APPLY) -> closeFailed chamado, SNAPSHOT_MISMATCH, apply NUNCA chamado",
      result.kind === "SNAPSHOT_MISMATCH" && !applyCalled && closeFailedCalls === 1,
    );
  }
  {
    // Mesmo cenário de divergência pós-openRun, mas closeFailed TAMBÉM
    // lança — não pode mascarar a divergência detectada.
    const record: PlannedSnapshotRecord = {
      runId: "preflight-uuid-z",
      runCode: "RUN-20260904-00000023",
      snapshotHash: "h".repeat(64),
      planOutcome: "COMPLETED",
      snapshot: {
        regions: [],
        generations: [],
        species: [],
        national_pokedex: {
          external_pokedex_id: "1",
          code: "NATIONAL",
          canonical_name: "National",
          source_url: "n",
          metadata: {},
        },
        national_pokedex_entries: [],
      },
    };
    const fakeStore = { save: () => Promise.reject(new Error("n/a")), load: () => Promise.resolve(record) };
    let applyCalled = false;
    const fakePort: PokemonCatalogSourcingPort = {
      openRun: () =>
        Promise.resolve({
          outcome: "CLAIMED",
          runId: "run-apply-mismatch-2",
          runCode: "RUN-20260904-00000024",
          preflightRunId: record.runId,
          preflightSnapshotHash: "hash-totalmente-diferente",
        }),
      heartbeat: () => Promise.reject(new Error("n/a")),
      plan: () => Promise.reject(new Error("n/a")),
      apply: () => {
        applyCalled = true;
        return Promise.reject(new Error("n/a"));
      },
      closeFailed: () => Promise.reject(new Error("CLOSE_FAILED_TAMBEM_FALHOU")),
    };
    const result = await runApply({
      port: fakePort,
      snapshotStore: fakeStore,
      preflightRunId: record.runId,
      preflightRunCode: record.runCode,
    });
    assert(
      "runApply [Bloco 4]: falha do PRÓPRIO closeFailed não impede a detecção de divergência de preflight -> ainda retorna SNAPSHOT_MISMATCH, apply nunca chamado",
      result.kind === "SNAPSHOT_MISMATCH" && !applyCalled,
    );
  }

  return { assertions };
}
