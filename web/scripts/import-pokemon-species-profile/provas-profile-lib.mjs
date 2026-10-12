/*
Provas offline do núcleo do importador de perfil (Pokédex P3a). Sem rede, sem banco.
Fixtures reduzidos a partir de respostas reais da PokéAPI consultadas em 2026-10-12
(pokemon-species/25 e /1025, só os campos usados) + Pokémon padrão sintéticos com os
valores oficiais (Pikachu 4 dm / 60 hg / electric; Bulbasaur grass+poison).
Uso: node scripts/import-pokemon-species-profile/provas-profile-lib.mjs
*/

import {
  LANGUAGES, POKEAPI_BASE, ProfileError, buildPayload, normalizeText, processSpecies,
  resolveSpecies, selectFlavor, selectGenus, summarizeCoverage, urlId,
} from "./profile-lib.mjs";
import { parseArgs } from "./run-import-pokemon-species-profile.mjs";

let pass = 0;
let fail = 0;
function ok(cond, label) {
  if (cond) pass += 1;
  else { fail += 1; console.log(`FAIL ${label}`); }
}
async function rejects(promise, code, label) {
  try { await promise; ok(false, `${label} (não rejeitou)`); }
  catch (e) { ok(e instanceof ProfileError && e.code === code, `${label} (veio ${e?.code ?? e?.message})`); }
}

const v = (name, id) => ({ name, url: `${POKEAPI_BASE}version/${id}/` });
const lang = (name) => ({ name, url: `${POKEAPI_BASE}language/x/` });

const species25 = {
  id: 25, is_legendary: false, is_mythical: false, is_baby: false,
  pokedex_numbers: [{ entry_number: 25, pokedex: { name: "national" } }, { entry_number: 22, pokedex: { name: "original-johto" } }],
  genera: [{ genus: "Pokémon Souris", language: lang("fr") }, { genus: "Mouse Pokémon", language: lang("en") }],
  flavor_text_entries: [
    { flavor_text: "When several of\nthese POKéMON\ngather, their\felectricity could\nbuild and cause\nlightning storms.", language: lang("en"), version: v("red", 1) },
    { flavor_text: "It raises its tail\nto check its sur­\nroundings.", language: lang("en"), version: v("silver", 5) },
    { flavor_text: "When Pikachu meet, they’ll touch their tails\ntogether and exchange electricity through them\nas a form of greeting.", language: lang("en"), version: v("shield", 34) },
    { flavor_text: "Possesses cheek sacs in which it stores electricity. This clever\nforest-dweller roasts tough berries with an electric shock before\nconsuming them.", language: lang("en"), version: v("legends-arceus", 39) },
    { flavor_text: "Les Pikachu se disent bonjour en se frottant\nla queue.", language: lang("fr"), version: v("shield", 34) },
    { flavor_text: "Possesses cheek sacs (sword).", language: lang("en"), version: v("sword", 33) },
  ],
  varieties: [
    { is_default: true, pokemon: { name: "pikachu", url: `${POKEAPI_BASE}pokemon/25/` } },
    { is_default: false, pokemon: { name: "pikachu-gmax", url: `${POKEAPI_BASE}pokemon/10199/` } },
  ],
};
const pokemon25 = {
  id: 25, name: "pikachu", is_default: true, height: 4, weight: 60,
  species: { name: "pikachu", url: `${POKEAPI_BASE}pokemon-species/25/` },
  types: [{ slot: 1, type: { name: "electric" } }],
  abilities: [{ ability: { name: "static" } }], stats: [{ base_stat: 35 }], moves: [{ move: { name: "thunder" } }],
};
const species1025 = {
  id: 1025, is_legendary: false, is_mythical: true, is_baby: false,
  pokedex_numbers: [{ entry_number: 1025, pokedex: { name: "national" } }],
  genera: [{ genus: "Subjugation Pokémon", language: lang("en") }, { genus: "Emprise", language: lang("fr") }],
  flavor_text_entries: [
    { flavor_text: "It feeds others toxic mochi that draw out desires and capabilities.", language: lang("en"), version: v("scarlet", 40) },
    { flavor_text: "Its peach-shaped shell serves as storage for a potent poison.", language: lang("en"), version: v("violet", 41) },
  ],
  varieties: [{ is_default: true, pokemon: { name: "pecharunt", url: `${POKEAPI_BASE}pokemon/1025/` } }],
};
const pokemon1025 = {
  id: 1025, name: "pecharunt", is_default: true, height: 3, weight: 3,
  species: { url: `${POKEAPI_BASE}pokemon-species/1025/` },
  types: [{ slot: 2, type: { name: "ghost" } }, { slot: 1, type: { name: "poison" } }],
};
const speciesPtBr = {
  ...species25,
  genera: [...species25.genera, { genus: "Pokémon Rato", language: lang("pt-br") }],
  flavor_text_entries: [...species25.flavor_text_entries, { flavor_text: "Texto pt-BR\nde teste.", language: lang("pt-br"), version: v("scarlet", 40) }],
};

function fetcher(map) {
  const calls = [];
  const fetchJson = async (url) => {
    calls.push(url);
    if (!(url in map)) throw new ProfileError("SOURCE_NOT_FOUND", `404 em ${url}`);
    return structuredClone(map[url]);
  };
  return { fetchJson, calls };
}
const map25 = { [`${POKEAPI_BASE}pokemon-species/25/`]: species25, [`${POKEAPI_BASE}pokemon/25/`]: pokemon25 };
const now = () => new Date("2026-10-12T18:00:00Z");

// --- normalização e seleção --------------------------------------------------------
ok(normalizeText("a\nb\fc\r\nd") === "a b c d", "normalize: quebras -> espaço");
ok(normalizeText("sur­\nroundings") === "surroundings", "normalize: hífen suave + quebra junta a palavra");
ok(normalizeText("POKéMON  x ") === "POKéMON x", "normalize: preserva grafia, colapsa espaços");
ok(normalizeText(null) === "", "normalize: nulo");
ok(urlId(`${POKEAPI_BASE}version/41/`) === 41 && urlId("x") === null, "urlId");
ok(selectFlavor(species25.flavor_text_entries, "en")?.version === "legends-arceus", "descrição en = versão mais recente (legends-arceus, id 39)");
ok(selectFlavor(species25.flavor_text_entries, "fr")?.version === "shield", "descrição fr = shield");
ok(selectFlavor(species25.flavor_text_entries, "pt-br") === null, "sem pt-br na fonte -> nada");
ok(selectFlavor(species1025.flavor_text_entries, "en")?.version === "violet", "#1025: violet (41) vence scarlet (40)");
ok(selectFlavor([{ flavor_text: "  ", language: lang("en"), version: v("x", 50) }, ...species1025.flavor_text_entries], "en")?.version === "violet", "texto vazio não concorre");
ok(selectGenus(species25.genera, "en")?.content === "Mouse Pokémon" && selectGenus(species25.genera, "pt-br") === null, "classificação por idioma");
ok(LANGUAGES[0].code === "pt-BR" && LANGUAGES[1].code === "en" && LANGUAGES.length === 2, "idiomas: pt-BR e en");

// --- resolução ------------------------------------------------------------------------
{
  const { fetchJson, calls } = fetcher(map25);
  const r = await resolveSpecies(25, fetchJson);
  ok(r.pokemon.name === "pikachu" && calls.length === 2, "resolve #25 via variedade padrão (2 requisições)");
}
await rejects(resolveSpecies(25, fetcher({ ...map25, [`${POKEAPI_BASE}pokemon-species/25/`]: { ...species25, pokedex_numbers: [{ entry_number: 26, pokedex: { name: "national" } }] } }).fetchJson), "SOURCE_NATIONAL_MISMATCH", "número nacional divergente");
await rejects(resolveSpecies(25, fetcher({ ...map25, [`${POKEAPI_BASE}pokemon-species/25/`]: { ...species25, varieties: species25.varieties.map((x) => ({ ...x, is_default: true })) } }).fetchJson), "SOURCE_DEFAULT_FORM_AMBIGUOUS", "duas formas padrão");
await rejects(resolveSpecies(25, fetcher({ ...map25, [`${POKEAPI_BASE}pokemon/25/`]: { ...pokemon25, species: { url: `${POKEAPI_BASE}pokemon-species/26/` } } }).fetchJson), "SOURCE_SPECIES_LINK_MISMATCH", "forma aponta para outra espécie");
await rejects(resolveSpecies(25, fetcher({ ...map25, [`${POKEAPI_BASE}pokemon/25/`]: { ...pokemon25, is_default: false } }).fetchJson), "SOURCE_INVALID_PAYLOAD", "Pokémon não padrão");
await rejects(resolveSpecies(25, fetcher({ ...map25, [`${POKEAPI_BASE}pokemon-species/25/`]: { ...species25, is_baby: undefined } }).fetchJson), "SOURCE_INVALID_PAYLOAD", "indicador ausente");

// --- payload --------------------------------------------------------------------------
{
  const { payload, coverage, sourceLanguages } = buildPayload(await resolveSpecies(25, fetcher(map25).fetchJson), now());
  ok(JSON.stringify(Object.keys(payload).sort()) === JSON.stringify(["height_dm", "is_baby", "is_legendary", "is_mythical", "retrieved_at", "source_pokemon_id", "source_pokemon_name", "source_species_id", "source_url", "texts", "types", "weight_hg"]), "payload só com campos autorizados (sem habilidades/estatísticas/golpes)");
  ok(payload.types.join() === "ELECTRIC" && payload.height_dm === 4 && payload.weight_hg === 60, "#25 tipos/medidas");
  ok(payload.source_species_id === "25" && payload.source_pokemon_id === "25" && payload.source_pokemon_name === "pikachu", "#25 referências como vieram");
  ok(payload.texts.length === 2 && payload.texts.every((t) => t.language === "en"), "#25 só textos en (fonte sem pt-br)");
  const genus = payload.texts.find((t) => t.kind === "GENUS");
  ok(genus && !("source_version" in genus), "classificação sem versão");
  ok(payload.texts.find((t) => t.kind === "FLAVOR")?.source_version === "legends-arceus", "descrição com versão de origem");
  ok(coverage["pt-BR"].genus === false && coverage["pt-BR"].flavor === null && coverage.en.flavor === "legends-arceus", "cobertura registrada por idioma");
  ok(sourceLanguages.genus.join() === "en,fr", "idiomas disponíveis na fonte registrados");
  ok(payload.retrieved_at === "2026-10-12T18:00:00.000Z", "data de coleta");
}
{
  const map = { [`${POKEAPI_BASE}pokemon-species/1025/`]: species1025, [`${POKEAPI_BASE}pokemon/1025/`]: pokemon1025 };
  const { payload } = buildPayload(await resolveSpecies(1025, fetcher(map).fetchJson), now());
  ok(payload.types.join() === "POISON,GHOST", "#1025 tipos reordenados pelo slot");
  ok(payload.is_mythical === true, "#1025 mítico");
}
{
  const map = { [`${POKEAPI_BASE}pokemon-species/25/`]: speciesPtBr, [`${POKEAPI_BASE}pokemon/25/`]: pokemon25 };
  const { payload, coverage } = buildPayload(await resolveSpecies(25, fetcher(map).fetchJson), now());
  const pt = payload.texts.filter((t) => t.language === "pt-BR");
  ok(pt.length === 2 && pt.find((t) => t.kind === "FLAVOR")?.content === "Texto pt-BR de teste." && coverage["pt-BR"].flavor === "scarlet", "pt-br presente na fonte -> importado como pt-BR");
}
{
  const bad = (types, extra = {}) => buildPayload({ species: species25, pokemon: { ...pokemon25, types, ...extra }, speciesUrl: "x" }, now());
  try { bad([{ slot: 1, type: { name: "shadow" } }]); ok(false, "tipo desconhecido"); } catch (e) { ok(e.code === "TYPE_UNKNOWN", "tipo desconhecido"); }
  try { bad([{ slot: 2, type: { name: "fire" } }]); ok(false, "slot sem primário"); } catch (e) { ok(e.code === "SOURCE_INVALID_TYPES", "slot sem primário"); }
  try { bad([]); ok(false, "sem tipos"); } catch (e) { ok(e.code === "SOURCE_INVALID_TYPES", "sem tipos"); }
  try { bad(pokemon25.types, { weight: 0 }); ok(false, "peso zero"); } catch (e) { ok(e.code === "SOURCE_INVALID_MEASURE", "peso zero"); }
}

// --- orquestração -----------------------------------------------------------------------
function mockSupabase(responses = {}) {
  const calls = [];
  return {
    calls,
    rpc: async (name, args) => {
      calls.push({ name, args });
      return responses[name] ?? { data: null, error: null };
    },
  };
}
{
  const supabase = mockSupabase();
  const { fetchJson, calls } = fetcher(map25);
  const r = await processSpecies(25, { fetchJson, supabase, now }, { apply: false, force: false, currentStatus: "IMPORTED" });
  ok(r.outcome === "SKIPPED_ALREADY_IMPORTED" && calls.length === 0 && supabase.calls.length === 0, "IMPORTED é pulada sem requisição");
}
{
  const supabase = mockSupabase();
  const r = await processSpecies(25, { fetchJson: fetcher(map25).fetchJson, supabase, now }, { apply: false, force: false, currentStatus: "PENDING" });
  ok(r.outcome === "DRY_RUN_OK" && supabase.calls.length === 0 && r.texts.length === 2, "DRY_RUN não chama o banco");
}
{
  const supabase = mockSupabase({ admin_record_pokemon_species_profile: { data: { action: "INSERTED" }, error: null } });
  const r = await processSpecies(25, { fetchJson: fetcher(map25).fetchJson, supabase, now }, { apply: true, force: false, currentStatus: "FAILED" });
  ok(r.outcome === "IMPORTED_INSERTED" && supabase.calls[0].name === "admin_record_pokemon_species_profile" && supabase.calls[0].args.p_national_dex_number === 25, "APPLY grava via RPC admin (FAILED é reprocessada)");
  ok(supabase.calls[0].args.p_payload.types[0] === "ELECTRIC", "APPLY envia o payload montado");
}
{
  const supabase = mockSupabase({ admin_record_pokemon_species_profile: { data: { action: "UNCHANGED" }, error: null } });
  const r = await processSpecies(25, { fetchJson: fetcher(map25).fetchJson, supabase, now }, { apply: true, force: true, currentStatus: "IMPORTED" });
  ok(r.outcome === "IMPORTED_UNCHANGED", "--force em IMPORTED: banco decide UNCHANGED");
}
{
  const supabase = mockSupabase({
    admin_record_pokemon_species_profile: { data: null, error: { message: "TYPE_UNKNOWN: token=abc Bearer eyJabc.def.ghijklmnopqrstuvwxyz0123" } },
    admin_record_pokemon_species_profile_failure: { data: { profile_preserved: true }, error: null },
  });
  const r = await processSpecies(25, { fetchJson: fetcher(map25).fetchJson, supabase, now }, { apply: true, force: true, currentStatus: "IMPORTED" });
  ok(r.outcome === "FAILED" && r.error_code === "RECORD_PROFILE" && r.failure_recorded && r.profile_preserved === true, "erro do banco -> falha registrada, perfil preservado");
  ok(!/eyJ|token=abc/.test(r.error_message), "mensagem sanitizada (sem credenciais)");
}
{
  const supabase = mockSupabase({ admin_record_pokemon_species_profile_failure: { data: { profile_preserved: false }, error: null } });
  const r = await processSpecies(26, { fetchJson: fetcher(map25).fetchJson, supabase, now }, { apply: true, force: false, currentStatus: "PENDING" });
  ok(r.outcome === "FAILED" && r.error_code === "SOURCE_NOT_FOUND" && supabase.calls.length === 1 && supabase.calls[0].name === "admin_record_pokemon_species_profile_failure", "404 na fonte -> só registro de falha");
}
{
  const records = [
    { coverage: { "pt-BR": { genus: false, flavor: null }, en: { genus: true, flavor: "violet" } } },
    { coverage: { "pt-BR": { genus: true, flavor: "scarlet" }, en: { genus: true, flavor: "violet" } } },
    { outcome: "FAILED" },
  ];
  const s = summarizeCoverage(records);
  ok(s.species_resolved === 2 && s.languages.en.flavor === 2 && s.languages.en.versions.violet === 2 && s.languages["pt-BR"].genus === 1, "resumo de cobertura");
}

// --- argumentos ---------------------------------------------------------------------------
ok(parseArgs(["--pilot"]).numbers.join() === "1,25,150,201,493,649,721,905,906,1025" && parseArgs(["--pilot"]).apply === false, "piloto = 10 espécies da P2, DRY_RUN padrão");
try { parseArgs(["--all"]); ok(false, "--all sem confirmação"); } catch (e) { ok(/CARGA_INTEGRAL_BLOQUEADA/.test(e.message), "--all sem confirmação bloqueado"); }
try { parseArgs([]); ok(false, "sem seleção"); } catch (e) { ok(/SELECAO_AUSENTE/.test(e.message), "sem seleção bloqueado"); }
ok(parseArgs(["--only=25,1,25"]).numbers.join() === "1,25", "--only ordena e deduplica");

console.log(`${pass}/${pass + fail} provas OK`);
if (fail) process.exit(1);
