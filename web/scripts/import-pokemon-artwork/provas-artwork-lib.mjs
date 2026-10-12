/*
Provas offline do importador de artes (Pokédex P2 Lote B). Sem rede, sem LIVE:
PokéAPI, Storage e RPC são simulados; Sharp é o real.
Uso (a partir de web/): node scripts/import-pokemon-artwork/provas-artwork-lib.mjs
*/
import sharp from "sharp";
import {
  ArtworkError, PILOT_NUMBERS, buildPaths, inspectOriginal, makeDisplay, makeHttp,
  processSpecies, resolveSource, sanitizeMessage,
} from "./artwork-lib.mjs";
import { parseArgs } from "./run-import-pokemon-artwork.mjs";

let pass = 0;
let fail = 0;
const ok = (cond, label, extra = "") => {
  if (cond) { pass++; console.log(`ok   ${label}`); } else { fail++; console.log(`FAIL ${label} ${extra}`); }
};
const rejects = async (promise, code, label) => {
  try { await promise; ok(false, label, "(não rejeitou)"); }
  catch (e) { ok(e instanceof ArtworkError && e.code === code, label, `(${e?.code ?? e?.message})`); }
};

const ART = (id) => `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/${id}.png`;
function fakePokeApi({ n, speciesId = n, pokemonId = n, artUrl = ART(pokemonId), national = n, defaults = 1, speciesLink = speciesId }) {
  const calls = [];
  const fetchJson = async (url) => {
    calls.push(url);
    if (url.endsWith(`pokemon-species/${n}/`)) {
      return {
        id: speciesId,
        pokedex_numbers: [{ entry_number: national, pokedex: { name: "national" } }],
        varieties: Array.from({ length: defaults }, () => ({ is_default: true, pokemon: { url: `https://pokeapi.co/api/v2/pokemon/${pokemonId}/` } })),
      };
    }
    if (url.endsWith(`pokemon/${pokemonId}/`)) {
      return { id: pokemonId, is_default: true, species: { url: `https://pokeapi.co/api/v2/pokemon-species/${speciesLink}/` }, sprites: { other: { "official-artwork": { front_default: artUrl } } } };
    }
    throw new Error(`URL inesperada ${url}`);
  };
  return { fetchJson, calls };
}
const png = (w, h, alpha = 0.5) => sharp({ create: { width: w, height: h, channels: 4, background: { r: 200, g: 40, b: 40, alpha } } })
  .composite([{ input: { create: { width: Math.floor(w / 2), height: Math.floor(h / 2), channels: 4, background: { r: 20, g: 120, b: 220, alpha: 1 } } }, top: 10, left: 10 }])
  .png().toBuffer();

function fakeSupabase({ uploadError = null, importAction = "INSERTED", importError = null } = {}) {
  const uploads = [];
  const rpcs = [];
  return {
    uploads, rpcs,
    storage: { from: (bucket) => ({ upload: async (path, buffer, options) => { uploads.push({ bucket, path, size: buffer.length, options }); return { error: typeof uploadError === "function" ? uploadError(path) : uploadError }; } }) },
    rpc: async (name, args) => {
      rpcs.push({ name, args });
      if (name === "admin_record_pokemon_species_artwork_import") return importError ? { data: null, error: importError } : { data: { action: importAction }, error: null };
      if (name === "admin_record_pokemon_species_artwork_failure") return { data: { status: "FAILED", image_preserved: false }, error: null };
      return { data: null, error: { message: "rpc inesperada" } };
    },
  };
}

// 1. Resolução por ids oficiais, sem presumir igualdade
{
  const api = fakePokeApi({ n: 25 });
  const s = await resolveSource(25, api.fetchJson);
  ok(s.sourceSpeciesId === "25" && s.sourcePokemonId === "25" && s.sourceUrl === ART(25), "1a resolve #25 pela espécie e pela forma padrão");
  const api2 = fakePokeApi({ n: 900, pokemonId: 10900 });
  const s2 = await resolveSource(900, api2.fetchJson);
  ok(s2.sourcePokemonId === "10900" && s2.sourceSpeciesId === "900", "1b forma padrão com id diferente do número é aceita e registrada como veio");
  await rejects(resolveSource(25, fakePokeApi({ n: 25, national: 26 }).fetchJson), "SOURCE_NATIONAL_MISMATCH", "1c número nacional divergente é recusado");
  await rejects(resolveSource(25, fakePokeApi({ n: 25, defaults: 2 }).fetchJson), "SOURCE_DEFAULT_FORM_AMBIGUOUS", "1d duas formas padrão são recusadas");
  await rejects(resolveSource(25, fakePokeApi({ n: 25, speciesLink: 26 }).fetchJson), "SOURCE_SPECIES_LINK_MISMATCH", "1e forma apontando para outra espécie é recusada");
  await rejects(resolveSource(25, fakePokeApi({ n: 25, artUrl: "https://evil.example/25.png" }).fetchJson), "SOURCE_URL_NOT_ALLOWED", "1f URL de imagem fora da origem permitida é recusada");
  await rejects(resolveSource(25, fakePokeApi({ n: 25, artUrl: null }).fetchJson), "SOURCE_NO_OFFICIAL_ARTWORK", "1g espécie sem Official Artwork é recusada");
}

// 2. Validação do original
{
  await rejects(inspectOriginal(Buffer.from("<html>not png</html>"), sharp), "VALIDATION_NOT_PNG", "2a conteúdo não-PNG é recusado");
  const big = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.alloc(1048576)]);
  await rejects(inspectOriginal(big, sharp), "VALIDATION_TOO_LARGE", "2b original > 1 MB é recusado");
  await rejects(inspectOriginal(await png(32, 32), sharp), "VALIDATION_DIMENSIONS", "2c dimensões abaixo do mínimo são recusadas");
  const o = await inspectOriginal(await png(475, 475), sharp);
  ok(o.width === 475 && o.height === 475 && o.hasAlpha && o.warnings.length === 0 && /^[0-9a-f]{64}$/.test(o.sha256), "2d PNG 475x475 com alfa aceito sem avisos");
}

// 3. WebP: proporção, transparência, tamanho, caminhos no formato do banco
{
  const buf = await png(475, 475);
  const o = await inspectOriginal(buf, sharp);
  const d = await makeDisplay(buf, o, sharp);
  ok(d.width === 320 && d.height === 320 && d.hasAlpha && d.sizeBytes < buf.length, "3a 475x475 → WebP 320x320 com alfa e menor que o original", `${d.width}x${d.height} ${d.sizeBytes}B`);
  const wide = await png(600, 400);
  const ow = await inspectOriginal(wide, sharp);
  const dw = await makeDisplay(wide, ow, sharp);
  ok(dw.width === 320 && dw.height === 213 && ow.warnings.length === 1, "3b 600x400 → 320x213 (proporção preservada) com aviso de tamanho não padrão", `${dw.width}x${dw.height}`);
  const small = await png(200, 200);
  const os = await inspectOriginal(small, sharp);
  const ds = await makeDisplay(small, os, sharp);
  ok(ds.width === 200 && ds.height === 200, "3c original menor que 320 não é ampliado");
  const p = buildPaths(25, o.sha256, d.sha256);
  ok(/^official-artwork\/[0-9]{4}\/original-[0-9a-f]{16}\.png$/.test(p.original) && /^official-artwork\/[0-9]{4}\/w320-[0-9a-f]{16}\.webp$/.test(p.display) && p.original.startsWith("official-artwork/0025/"), "3d caminhos batem com as CHECKs da 6132");
}

// 4. Orquestração
const buf475 = await png(475, 475);
const baseDeps = (api, supabase, extra = {}) => ({ fetchJson: api.fetchJson, fetchBinary: async () => buf475, sharp, supabase, now: () => new Date("2026-10-12T12:00:00Z"), ...extra });
{
  const api = fakePokeApi({ n: 1 });
  const sb = fakeSupabase();
  let fetched = false;
  const r = await processSpecies(1, { ...baseDeps(api, sb), fetchBinary: async () => { fetched = true; return buf475; } }, { apply: true, force: false, currentStatus: "IMPORTED" });
  ok(r.outcome === "SKIPPED_ALREADY_IMPORTED" && api.calls.length === 0 && !fetched && sb.uploads.length === 0 && sb.rpcs.length === 0, "4a espécie já IMPORTED é pulada sem rede, upload ou RPC");
}
{
  const api = fakePokeApi({ n: 150 });
  const sb = fakeSupabase();
  const previews = [];
  const r = await processSpecies(150, baseDeps(api, sb, { writePreview: async (n) => previews.push(n) }), { apply: false, force: false, currentStatus: "PENDING" });
  ok(r.outcome === "DRY_RUN_OK" && sb.uploads.length === 0 && sb.rpcs.length === 0 && previews[0] === 150, "4b DRY_RUN não envia nem registra; só gera prévia local");
}
{
  const api = fakePokeApi({ n: 1025 });
  const sb = fakeSupabase();
  const r = await processSpecies(1025, baseDeps(api, sb), { apply: true, force: false, currentStatus: "PENDING" });
  const rec = sb.rpcs[0];
  ok(r.outcome === "IMPORTED_INSERTED" && sb.uploads.length === 2, "4c APPLY envia 2 arquivos e registra", r.outcome);
  ok(sb.uploads.every((u) => u.bucket === "pokemon-species-artwork" && u.options.upsert === false), "4d uploads só no bucket próprio e sem sobrescrita (upsert:false)");
  ok(sb.uploads[0].options.contentType === "image/png" && sb.uploads[1].options.contentType === "image/webp", "4e content-type correto por arquivo");
  ok(rec.name === "admin_record_pokemon_species_artwork_import" && rec.args.p_national_dex_number === 1025 && rec.args.p_source_species_id === "1025"
     && rec.args.p_original_storage_path === sb.uploads[0].path && rec.args.p_display_storage_path === sb.uploads[1].path
     && rec.args.p_original_width === 475 && rec.args.p_display_width === 320, "4f RPC recebe os mesmos caminhos enviados e as dimensões medidas");
}
{
  const api = fakePokeApi({ n: 25 });
  const sb = fakeSupabase({ uploadError: { statusCode: "409", message: "The resource already exists" }, importAction: "UNCHANGED" });
  const r = await processSpecies(25, baseDeps(api, sb), { apply: true, force: true, currentStatus: "IMPORTED" });
  ok(r.outcome === "IMPORTED_UNCHANGED" && r.original.upload === "ALREADY_PRESENT", "4g retomada: arquivo já presente no mesmo caminho é aceito (mesmo hash) e o registro fica UNCHANGED");
}
{
  const api = fakePokeApi({ n: 201 });
  const sb = fakeSupabase({ uploadError: { statusCode: "403", message: "new row violates row-level security policy" } });
  const r = await processSpecies(201, baseDeps(api, sb), { apply: true, force: false, currentStatus: "PENDING" });
  const failure = sb.rpcs.find((c) => c.name === "admin_record_pokemon_species_artwork_failure");
  ok(r.outcome === "FAILED" && r.error_code === "STORAGE_UPLOAD" && failure && failure.args.p_error_code === "STORAGE_UPLOAD"
     && !sb.rpcs.some((c) => c.name === "admin_record_pokemon_species_artwork_import"), "4h falha de upload registra diagnóstico e não chama o registro de importação");
}
{
  const api = fakePokeApi({ n: 493 });
  const sb = fakeSupabase();
  const r = await processSpecies(493, { ...baseDeps(api, sb), fetchBinary: async () => Buffer.from("not an image") }, { apply: true, force: false, currentStatus: "PENDING" });
  ok(r.outcome === "FAILED" && r.error_code === "VALIDATION_NOT_PNG" && sb.uploads.length === 0 && sb.rpcs[0]?.args.p_source_url === ART(493), "4i conteúdo inválido não é enviado; falha registrada com a URL de origem");
}
{
  const api = fakePokeApi({ n: 649 });
  const sb = fakeSupabase();
  const r = await processSpecies(649, { ...baseDeps(api, sb), fetchBinary: async () => { throw new ArtworkError("DOWNLOAD_TIMEOUT", "timeout"); } }, { apply: false, force: false, currentStatus: "PENDING" });
  ok(r.outcome === "FAILED" && sb.rpcs.length === 0, "4j falha em DRY_RUN não escreve nada no banco");
}

// 5. Rede: retry, 404, timeout
{
  let calls = 0;
  const http = makeHttp({ userAgent: "t", sleep: async () => {}, fetchImpl: async () => { calls++; return calls === 1 ? new Response("x", { status: 503 }) : new Response(JSON.stringify({ ok: 1 }), { status: 200 }); } });
  const j = await http.fetchJson("https://pokeapi.co/api/v2/x");
  ok(j.ok === 1 && calls === 2, "5a 503 → nova tentativa e sucesso");
  const http404 = makeHttp({ userAgent: "t", sleep: async () => {}, fetchImpl: async () => new Response("", { status: 404 }) });
  await rejects(http404.fetchJson("https://pokeapi.co/api/v2/x"), "SOURCE_NOT_FOUND", "5b 404 não é repetido e vira SOURCE_NOT_FOUND");
  let n2 = 0;
  const httpTimeout = makeHttp({ userAgent: "t", sleep: async () => {}, fetchImpl: async () => { n2++; const e = new Error("aborted"); e.name = "TimeoutError"; throw e; } });
  await rejects(httpTimeout.fetchBinary("https://raw.githubusercontent.com/x.png"), "DOWNLOAD_TIMEOUT", "5c timeout em 2 tentativas vira DOWNLOAD_TIMEOUT");
  ok(n2 === 2, "5d timeout tentou exatamente 2 vezes");
}

// 6. Segurança de logs e argumentos
{
  const s = sanitizeMessage("falhou Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.abcdefghij password=segredo");
  ok(!s.includes("eyJ") && !s.includes("segredo"), "6a mensagens nunca carregam JWT ou senha");
  ok(JSON.stringify(parseArgs(["--pilot"]).numbers) === JSON.stringify(PILOT_NUMBERS) && parseArgs(["--pilot"]).apply === false, "6b --pilot = 10 espécies, DRY_RUN por padrão");
  let blocked = false;
  try { parseArgs(["--all"]); } catch (e) { blocked = /CARGA_INTEGRAL_BLOQUEADA/.test(e.message); }
  ok(blocked, "6c --all sem --confirm-all é bloqueado");
  let none = false;
  try { parseArgs(["--apply"]); } catch (e) { none = /SELECAO_AUSENTE/.test(e.message); }
  ok(none, "6d --apply sem seleção é recusado");
}

console.log(`\n${pass} ok, ${fail} falha(s)`);
process.exit(fail ? 1 : 0);
