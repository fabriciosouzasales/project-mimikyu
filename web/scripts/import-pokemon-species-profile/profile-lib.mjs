/*
===============================================================================
Projeto.....: Project Mimikyu — Pokédex P3a
Arquivo.....: profile-lib.mjs
Papel.......: núcleo do importador do perfil de referência das espécies (PokéAPI).
              Funções puras/injetáveis — rede e Supabase chegam por parâmetro, para
              que provas-profile-lib.mjs teste tudo offline.

Dados autorizados (AP-017 v1.10 / ADR-011 v1.4):
  espécie ......... classificação (genus), descrição selecionada (flavor text),
                    is_legendary, is_mythical, is_baby
  forma padrão .... tipos (ordem por slot), altura (dm), peso (hg)
Nada mais é extraído da resposta da PokéAPI (habilidades, estatísticas, golpes etc.
são ignorados) e a resposta bruta não é guardada.

Fluxo por espécie (contrato da Query 6133):
  1. /pokemon-species/{n}: confere pokedex_numbers[national] == n e exatamente uma
     variedade padrão; /pokemon/{id}: confere species.url == espécie e is_default.
     Nenhuma igualdade de ids é presumida.
  2. Monta o payload: tipos mapeados para o vocabulário canônico, textos só dos idiomas
     da lista LANGUAGES, com normalização técnica documentada (normalizeText) e
     seleção determinística da descrição (selectFlavor).
  3. APPLY: admin_record_pokemon_species_profile(n, payload) — INSERTED/UPDATED/
     RECOVERED/UNCHANGED. Falha -> admin_record_pokemon_species_profile_failure
     (perfil válido preservado pelo banco).
Espécie já IMPORTED é pulada antes de qualquer requisição (salvo --force).
===============================================================================
*/

import { ArtworkError as ProfileError, PILOT_NUMBERS, dexPad, makeHttp, sanitizeMessage } from "../import-pokemon-artwork/artwork-lib.mjs";

export { ProfileError, PILOT_NUMBERS, dexPad, makeHttp, sanitizeMessage };

export const POKEAPI_BASE = "https://pokeapi.co/api/v2/";

/**
 * Idiomas importados: código da PokéAPI -> código BCP 47 do MMKYU. pt-BR primeiro
 * (prioritário na interface); en é o original de referência. Um idioma novo = nova
 * entrada aqui (o banco aceita qualquer código BCP 47 válido).
 */
export const LANGUAGES = [
  { api: "pt-br", code: "pt-BR" },
  { api: "en", code: "en" },
];

/** Nome do tipo na PokéAPI -> código canônico (pokemon_type.code, Query 6133). */
export const TYPE_CODES = {
  normal: "NORMAL", fighting: "FIGHTING", flying: "FLYING", poison: "POISON",
  ground: "GROUND", rock: "ROCK", bug: "BUG", ghost: "GHOST", steel: "STEEL",
  fire: "FIRE", water: "WATER", grass: "GRASS", electric: "ELECTRIC", psychic: "PSYCHIC",
  ice: "ICE", dragon: "DRAGON", dark: "DARK", fairy: "FAIRY",
};

/**
 * Normalização técnica (só formatação, nunca conteúdo):
 *  - hífen suave (U+00AD) seguido de quebra = palavra hifenizada pela tela do jogo -> junta;
 *  - hífen suave isolado -> removido;
 *  - quebras de linha/página/tabulação (\n \f \r \t) -> espaço;
 *  - espaços repetidos -> um; bordas aparadas.
 * Grafia, maiúsculas ("POKéMON") e pontuação permanecem como na fonte.
 */
export function normalizeText(value) {
  return String(value ?? "")
    .replace(/­[\n\f\r]+/g, "")
    .replace(/­/g, "")
    .replace(/[\n\f\r\t]+/g, " ")
    .replace(/ {2,}/g, " ")
    .trim();
}

/** Id numérico ao final de uma URL da PokéAPI (".../version/41/" -> 41). */
export function urlId(url) {
  const match = /\/(\d+)\/?$/.exec(String(url ?? ""));
  return match ? Number(match[1]) : null;
}

/**
 * Critério editorial da descrição (determinístico, documentado no README da 6133):
 * para cada idioma, a entrada da versão de jogo MAIS RECENTE — maior id de versão na
 * PokéAPI, que cresce com a ordem de lançamento. Uma entrada por idioma; versões sem
 * texto naquele idioma simplesmente não concorrem.
 */
export function selectFlavor(entries, apiLanguage) {
  let best = null;
  for (const entry of entries ?? []) {
    if (entry?.language?.name !== apiLanguage) continue;
    const id = urlId(entry?.version?.url);
    const content = normalizeText(entry?.flavor_text);
    if (!id || !content || !entry?.version?.name) continue;
    if (!best || id > best.versionId) best = { versionId: id, version: entry.version.name, content };
  }
  return best;
}

export function selectGenus(genera, apiLanguage) {
  const entry = (genera ?? []).find((g) => g?.language?.name === apiLanguage);
  const content = normalizeText(entry?.genus);
  return content ? { content } : null;
}

/** Idiomas presentes na fonte (para o relatório de cobertura), em ordem estável. */
export function languagesIn(list) {
  return [...new Set((list ?? []).map((item) => item?.language?.name).filter(Boolean))].sort();
}

// ---------------------------------------------------------------------------
// 1. Resolução: espécie -> variedade padrão -> Pokémon (forma padrão)
// ---------------------------------------------------------------------------
export async function resolveSpecies(n, fetchJson) {
  const speciesUrl = `${POKEAPI_BASE}pokemon-species/${n}/`;
  const species = await fetchJson(speciesUrl);
  const national = (species?.pokedex_numbers ?? []).find((p) => p?.pokedex?.name === "national");
  if (!national || national.entry_number !== n) {
    throw new ProfileError("SOURCE_NATIONAL_MISMATCH", `pokemon-species/${n} não declara o número nacional ${n}`);
  }
  if (!Number.isInteger(species.id) || species.id < 1) {
    throw new ProfileError("SOURCE_INVALID_PAYLOAD", `pokemon-species/${n} sem id válido`);
  }
  for (const flag of ["is_legendary", "is_mythical", "is_baby"]) {
    if (typeof species[flag] !== "boolean") {
      throw new ProfileError("SOURCE_INVALID_PAYLOAD", `pokemon-species/${n} sem ${flag}`);
    }
  }
  const defaults = (species.varieties ?? []).filter((v) => v?.is_default === true);
  if (defaults.length !== 1) {
    throw new ProfileError("SOURCE_DEFAULT_FORM_AMBIGUOUS", `pokemon-species/${n} tem ${defaults.length} formas padrão`);
  }
  const pokemonUrl = defaults[0]?.pokemon?.url;
  if (typeof pokemonUrl !== "string" || !pokemonUrl.startsWith(`${POKEAPI_BASE}pokemon/`)) {
    throw new ProfileError("SOURCE_INVALID_PAYLOAD", `forma padrão de ${n} com URL inesperada`);
  }

  const pokemon = await fetchJson(pokemonUrl);
  if (!String(pokemon?.species?.url ?? "").replace(/\/$/, "").endsWith(`/pokemon-species/${species.id}`)) {
    throw new ProfileError("SOURCE_SPECIES_LINK_MISMATCH", `forma padrão não aponta para a espécie ${species.id}`);
  }
  if (pokemon.is_default !== true || !Number.isInteger(pokemon.id) || pokemon.id < 1
      || typeof pokemon.name !== "string" || !/^[a-z0-9][a-z0-9-]*$/.test(pokemon.name)) {
    throw new ProfileError("SOURCE_INVALID_PAYLOAD", `forma padrão de ${n} inválida`);
  }
  return { species, pokemon, speciesUrl };
}

// ---------------------------------------------------------------------------
// 2. Payload (só os campos autorizados)
// ---------------------------------------------------------------------------
export function buildPayload({ species, pokemon, speciesUrl }, retrievedAt) {
  const slots = [...(pokemon.types ?? [])].sort((a, b) => a?.slot - b?.slot);
  if (slots.length < 1 || slots.length > 2 || slots.some((t, i) => t?.slot !== i + 1)) {
    throw new ProfileError("SOURCE_INVALID_TYPES", `tipos com slots inesperados (${slots.map((t) => t?.slot).join(",")})`);
  }
  const types = slots.map((t) => {
    const code = TYPE_CODES[t?.type?.name];
    if (!code) throw new ProfileError("TYPE_UNKNOWN", `tipo desconhecido: ${t?.type?.name}`);
    return code;
  });
  for (const [field, max] of [["height", 10000], ["weight", 100000]]) {
    if (!Number.isInteger(pokemon[field]) || pokemon[field] < 1 || pokemon[field] > max) {
      throw new ProfileError("SOURCE_INVALID_MEASURE", `${field} inválido: ${pokemon[field]}`);
    }
  }

  const texts = [];
  const coverage = {};
  for (const { api, code } of LANGUAGES) {
    const genus = selectGenus(species.genera, api);
    const flavor = selectFlavor(species.flavor_text_entries, api);
    if (genus) texts.push({ kind: "GENUS", language: code, content: genus.content });
    if (flavor) texts.push({ kind: "FLAVOR", language: code, content: flavor.content, source_version: flavor.version });
    coverage[code] = { genus: Boolean(genus), flavor: flavor ? flavor.version : null };
  }
  for (const text of texts) {
    if (text.content.length > 2000) throw new ProfileError("SOURCE_TEXT_TOO_LONG", `${text.kind} ${text.language}`);
  }

  const payload = {
    source_species_id: String(species.id),
    source_pokemon_id: String(pokemon.id),
    source_pokemon_name: pokemon.name,
    source_url: speciesUrl,
    retrieved_at: retrievedAt.toISOString(),
    is_legendary: species.is_legendary,
    is_mythical: species.is_mythical,
    is_baby: species.is_baby,
    height_dm: pokemon.height,
    weight_hg: pokemon.weight,
    types,
    texts,
  };
  const sourceLanguages = {
    genus: languagesIn(species.genera),
    flavor: languagesIn(species.flavor_text_entries),
  };
  return { payload, coverage, sourceLanguages };
}

// ---------------------------------------------------------------------------
// 3. Orquestração por espécie
// ---------------------------------------------------------------------------
/**
 * deps: { fetchJson, supabase (rpc), now }
 * opts: { apply: boolean, force: boolean, currentStatus: 'PENDING'|'IMPORTED'|'FAILED' }
 */
export async function processSpecies(n, deps, opts) {
  const record = { national_dex_number: n, mode: opts.apply ? "APPLY" : "DRY_RUN", outcome: null };

  if (opts.currentStatus === "IMPORTED" && !opts.force) {
    record.outcome = "SKIPPED_ALREADY_IMPORTED";
    return record;
  }

  try {
    const resolved = await resolveSpecies(n, deps.fetchJson);
    const { payload, coverage, sourceLanguages } = buildPayload(resolved, deps.now());
    Object.assign(record, {
      source_species_id: payload.source_species_id,
      source_pokemon_id: payload.source_pokemon_id,
      source_pokemon_name: payload.source_pokemon_name,
      types: payload.types,
      height_dm: payload.height_dm,
      weight_hg: payload.weight_hg,
      flags: { is_legendary: payload.is_legendary, is_mythical: payload.is_mythical, is_baby: payload.is_baby },
      coverage,
      source_languages: sourceLanguages,
      texts: payload.texts,
    });

    if (!opts.apply) {
      record.outcome = "DRY_RUN_OK";
      return record;
    }

    const { data, error } = await deps.supabase.rpc("admin_record_pokemon_species_profile", {
      p_national_dex_number: n,
      p_payload: payload,
    });
    if (error) throw new ProfileError("RECORD_PROFILE", sanitizeMessage(error.message));
    record.outcome = `IMPORTED_${data?.action ?? "UNKNOWN"}`;
    return record;
  } catch (error) {
    const code = error instanceof ProfileError ? error.code : "UNEXPECTED_ERROR";
    record.outcome = "FAILED";
    record.error_code = code;
    record.error_message = sanitizeMessage(error?.message);
    if (opts.apply) {
      const { data, error: failError } = await deps.supabase.rpc("admin_record_pokemon_species_profile_failure", {
        p_national_dex_number: n,
        p_error_code: code,
        p_error_message: record.error_message,
      });
      record.failure_recorded = !failError;
      record.profile_preserved = data?.profile_preserved ?? null;
      if (failError) record.failure_record_error = sanitizeMessage(failError.message);
    }
    return record;
  }
}

/** Resumo de cobertura de idiomas para o relatório (só registros com payload). */
export function summarizeCoverage(records) {
  const summary = {};
  for (const { code } of LANGUAGES) summary[code] = { genus: 0, flavor: 0, versions: {} };
  let resolved = 0;
  for (const record of records) {
    if (!record.coverage) continue;
    resolved += 1;
    for (const [code, item] of Object.entries(record.coverage)) {
      if (item.genus) summary[code].genus += 1;
      if (item.flavor) {
        summary[code].flavor += 1;
        summary[code].versions[item.flavor] = (summary[code].versions[item.flavor] ?? 0) + 1;
      }
    }
  }
  return { species_resolved: resolved, languages: summary };
}
