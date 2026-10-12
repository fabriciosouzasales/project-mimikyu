/*
===============================================================================
Projeto.....: Project Mimikyu — Pokédex P2 Lote B
Arquivo.....: artwork-lib.mjs
Papel.......: núcleo do importador de Official Artwork das espécies (Node + Sharp).
              Funções puras/injetáveis — rede, Storage, RPC e disco chegam por
              parâmetro, para que provas-artwork-lib.mjs teste tudo offline.

Fluxo por espécie (contrato da Query 6132, ver
database/proposals/2026-10-12-pokedex-p2-artwork-foundation/README.md):
  1. Resolver origem SEM presumir igualdade de ids:
       /pokemon-species/{n}  -> confere pokedex_numbers[national] == n
                             -> varieties[is_default] (exatamente 1)
       /pokemon/{id}         -> confere species.url == a espécie resolvida
                             -> sprites.other["official-artwork"].front_default
     source_species_id = id devolvido pela PokéAPI (o banco ainda confere com a
     referência cadastrada); source_pokemon_id = id da forma padrão, como veio.
  2. Baixar (timeout + 1 retry), validar PNG (assinatura, formato, dimensões,
     tamanho), SHA-256.
  3. Gerar WebP <= 320x320 com Sharp (fit inside, sem ampliar, alfa preservado).
  4. APPLY: enviar original + WebP para pokemon-species-artwork com caminhos
     endereçados por conteúdo e upsert:false (nunca sobrescreve); objeto já
     existente no mesmo caminho = mesmo conteúdo (o caminho contém o hash).
  5. APPLY: admin_record_pokemon_species_artwork_import(...). Qualquer falha ->
     admin_record_pokemon_species_artwork_failure(...) (não derruba imagem
     válida — garantido pelo banco).
Espécie já IMPORTED é pulada antes de qualquer download (salvo --force).
===============================================================================
*/

import { createHash } from "node:crypto";

export const BUCKET = "pokemon-species-artwork";
export const PILOT_NUMBERS = [1, 25, 150, 201, 493, 649, 721, 905, 906, 1025];
export const POKEAPI_BASE = "https://pokeapi.co/api/v2/";
export const ALLOWED_ART_PREFIX = "https://raw.githubusercontent.com/PokeAPI/sprites/";
export const MAX_BYTES = 1048576;
export const DISPLAY_MAX = 320;
export const EXPECTED_ORIGINAL = 475;
export const WEBP_OPTIONS = { quality: 82, alphaQuality: 90, effort: 6, smartSubsample: true };

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** Erro com código estável (vira last_error_code no banco: ^[A-Z][A-Z0-9_]*$). */
export class ArtworkError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

export function sha256Hex(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

export function dexPad(n) {
  return String(n).padStart(4, "0");
}

export function buildPaths(n, originalSha, displaySha) {
  const dex = dexPad(n);
  return {
    original: `official-artwork/${dex}/original-${originalSha.slice(0, 16)}.png`,
    display: `official-artwork/${dex}/w320-${displaySha.slice(0, 16)}.webp`,
  };
}

/** Remove qualquer coisa com cara de credencial antes de registrar/relatar. */
export function sanitizeMessage(message) {
  return String(message ?? "erro sem mensagem")
    .replace(/Bearer\s+[A-Za-z0-9._-]+/gi, "Bearer [redacted]")
    .replace(/eyJ[A-Za-z0-9._-]{20,}/g, "[redacted-jwt]")
    .replace(/(password|apikey|api_key|token)=\S+/gi, "$1=[redacted]")
    .slice(0, 1000);
}

// ---------------------------------------------------------------------------
// 1. Resolução da origem
// ---------------------------------------------------------------------------
export async function resolveSource(n, fetchJson) {
  const species = await fetchJson(`${POKEAPI_BASE}pokemon-species/${n}/`);
  const national = (species.pokedex_numbers ?? []).find((p) => p?.pokedex?.name === "national");
  if (!national || national.entry_number !== n) {
    throw new ArtworkError("SOURCE_NATIONAL_MISMATCH", `pokemon-species/${n} não declara o número nacional ${n}`);
  }
  if (!Number.isInteger(species.id) || species.id < 1) {
    throw new ArtworkError("SOURCE_INVALID_PAYLOAD", `pokemon-species/${n} sem id válido`);
  }
  const defaults = (species.varieties ?? []).filter((v) => v?.is_default === true);
  if (defaults.length !== 1) {
    throw new ArtworkError("SOURCE_DEFAULT_FORM_AMBIGUOUS", `pokemon-species/${n} tem ${defaults.length} formas padrão`);
  }
  const pokemonUrl = defaults[0]?.pokemon?.url;
  if (typeof pokemonUrl !== "string" || !pokemonUrl.startsWith(`${POKEAPI_BASE}pokemon/`)) {
    throw new ArtworkError("SOURCE_INVALID_PAYLOAD", `forma padrão de ${n} com URL inesperada`);
  }

  const pokemon = await fetchJson(pokemonUrl);
  const speciesUrl = pokemon?.species?.url ?? "";
  if (!speciesUrl.replace(/\/$/, "").endsWith(`/pokemon-species/${species.id}`)) {
    throw new ArtworkError("SOURCE_SPECIES_LINK_MISMATCH", `forma padrão não aponta para a espécie ${species.id}`);
  }
  if (pokemon.is_default !== true || !Number.isInteger(pokemon.id) || pokemon.id < 1) {
    throw new ArtworkError("SOURCE_INVALID_PAYLOAD", `forma padrão de ${n} inválida`);
  }
  const artUrl = pokemon?.sprites?.other?.["official-artwork"]?.front_default;
  if (typeof artUrl !== "string" || artUrl === "") {
    throw new ArtworkError("SOURCE_NO_OFFICIAL_ARTWORK", `forma padrão de ${n} sem Official Artwork`);
  }
  if (!artUrl.startsWith(ALLOWED_ART_PREFIX)) {
    throw new ArtworkError("SOURCE_URL_NOT_ALLOWED", `URL de imagem fora da origem permitida`);
  }
  return {
    sourceSpeciesId: String(species.id),
    sourcePokemonId: String(pokemon.id),
    sourceUrl: artUrl,
  };
}

// ---------------------------------------------------------------------------
// 2–3. Validação do original e geração do WebP
// ---------------------------------------------------------------------------
export async function inspectOriginal(buffer, sharp) {
  if (!buffer || buffer.length === 0) throw new ArtworkError("VALIDATION_EMPTY", "arquivo vazio");
  if (buffer.length > MAX_BYTES) throw new ArtworkError("VALIDATION_TOO_LARGE", `original com ${buffer.length} bytes (> 1 MB)`);
  if (!buffer.subarray(0, 8).equals(PNG_SIGNATURE)) throw new ArtworkError("VALIDATION_NOT_PNG", "assinatura PNG ausente");
  let meta;
  try {
    meta = await sharp(buffer).metadata();
  } catch (error) {
    throw new ArtworkError("VALIDATION_UNREADABLE", `PNG ilegível: ${sanitizeMessage(error?.message)}`);
  }
  if (meta.format !== "png") throw new ArtworkError("VALIDATION_NOT_PNG", `formato ${meta.format}`);
  const { width, height } = meta;
  if (!(width >= 64 && width <= 4096 && height >= 64 && height <= 4096)) {
    throw new ArtworkError("VALIDATION_DIMENSIONS", `dimensões ${width}x${height} fora de 64..4096`);
  }
  const warnings = [];
  if (width !== EXPECTED_ORIGINAL || height !== EXPECTED_ORIGINAL) warnings.push(`original ${width}x${height} (esperado ${EXPECTED_ORIGINAL}x${EXPECTED_ORIGINAL})`);
  if (!meta.hasAlpha) warnings.push("original sem canal alfa");
  return { width, height, hasAlpha: Boolean(meta.hasAlpha), sizeBytes: buffer.length, sha256: sha256Hex(buffer), warnings };
}

export async function makeDisplay(buffer, original, sharp) {
  const webp = await sharp(buffer)
    .resize({ width: DISPLAY_MAX, height: DISPLAY_MAX, fit: "inside", withoutEnlargement: true })
    .webp(WEBP_OPTIONS)
    .toBuffer();
  const meta = await sharp(webp).metadata();
  if (meta.format !== "webp") throw new ArtworkError("TRANSFORMATION_FORMAT", `saída ${meta.format}`);
  if (!(meta.width >= 1 && meta.width <= DISPLAY_MAX && meta.width <= original.width
        && meta.height >= 1 && meta.height <= DISPLAY_MAX && meta.height <= original.height)) {
    throw new ArtworkError("TRANSFORMATION_DIMENSIONS", `WebP ${meta.width}x${meta.height}`);
  }
  if (Math.abs(meta.width / meta.height - original.width / original.height) > 0.02) {
    throw new ArtworkError("TRANSFORMATION_ASPECT", "proporção alterada na conversão");
  }
  if (original.hasAlpha && !meta.hasAlpha) throw new ArtworkError("TRANSFORMATION_ALPHA_LOST", "transparência perdida");
  if (webp.length > MAX_BYTES) throw new ArtworkError("TRANSFORMATION_TOO_LARGE", `WebP com ${webp.length} bytes`);
  return { buffer: webp, width: meta.width, height: meta.height, hasAlpha: Boolean(meta.hasAlpha), sizeBytes: webp.length, sha256: sha256Hex(webp) };
}

// ---------------------------------------------------------------------------
// 4. Upload sem sobrescrita
// ---------------------------------------------------------------------------
function isAlreadyExists(error) {
  const status = String(error?.statusCode ?? error?.status ?? "");
  return status === "409" || /already exists|duplicate/i.test(String(error?.message ?? ""));
}

export async function uploadImmutable(storage, path, buffer, contentType) {
  const { error } = await storage.from(BUCKET).upload(path, buffer, {
    contentType,
    upsert: false,
    cacheControl: "31536000",
  });
  if (!error) return "UPLOADED";
  // Caminho contém o hash do conteúdo: objeto existente = mesmo arquivo (retomada segura).
  if (isAlreadyExists(error)) return "ALREADY_PRESENT";
  throw new ArtworkError("STORAGE_UPLOAD", `upload ${path}: ${sanitizeMessage(error.message)}`);
}

// ---------------------------------------------------------------------------
// 5. Orquestração por espécie
// ---------------------------------------------------------------------------
/**
 * deps: { fetchJson, fetchBinary, sharp, supabase (storage + rpc), writePreview, now }
 * opts: { apply: boolean, force: boolean, currentStatus: 'PENDING'|'IMPORTED'|'FAILED' }
 */
export async function processSpecies(n, deps, opts) {
  const record = { national_dex_number: n, mode: opts.apply ? "APPLY" : "DRY_RUN", outcome: null, warnings: [] };

  if (opts.currentStatus === "IMPORTED" && !opts.force) {
    record.outcome = "SKIPPED_ALREADY_IMPORTED";
    return record;
  }

  let source = null;
  try {
    source = await resolveSource(n, deps.fetchJson);
    Object.assign(record, { source_species_id: source.sourceSpeciesId, source_pokemon_id: source.sourcePokemonId, source_url: source.sourceUrl });

    const retrievedAt = deps.now();
    const originalBuffer = await deps.fetchBinary(source.sourceUrl);
    const original = await inspectOriginal(originalBuffer, deps.sharp);
    const display = await makeDisplay(originalBuffer, original, deps.sharp);
    const paths = buildPaths(n, original.sha256, display.sha256);
    record.warnings.push(...original.warnings);
    Object.assign(record, {
      original: { path: paths.original, width: original.width, height: original.height, size_bytes: original.sizeBytes, sha256: original.sha256 },
      display: { path: paths.display, width: display.width, height: display.height, size_bytes: display.sizeBytes, sha256: display.sha256 },
    });

    if (!opts.apply) {
      if (deps.writePreview) await deps.writePreview(n, originalBuffer, display.buffer);
      record.outcome = "DRY_RUN_OK";
      return record;
    }

    record.original.upload = await uploadImmutable(deps.supabase.storage, paths.original, originalBuffer, "image/png");
    record.display.upload = await uploadImmutable(deps.supabase.storage, paths.display, display.buffer, "image/webp");

    const { data, error } = await deps.supabase.rpc("admin_record_pokemon_species_artwork_import", {
      p_national_dex_number: n,
      p_source_species_id: source.sourceSpeciesId,
      p_source_pokemon_id: source.sourcePokemonId,
      p_source_url: source.sourceUrl,
      p_retrieved_at: retrievedAt.toISOString(),
      p_original_storage_path: paths.original,
      p_original_width: original.width,
      p_original_height: original.height,
      p_original_size_bytes: original.sizeBytes,
      p_original_checksum_sha256: original.sha256,
      p_display_storage_path: paths.display,
      p_display_width: display.width,
      p_display_height: display.height,
      p_display_size_bytes: display.sizeBytes,
      p_display_checksum_sha256: display.sha256,
    });
    if (error) throw new ArtworkError("RECORD_IMPORT", sanitizeMessage(error.message));
    record.outcome = `IMPORTED_${data?.action ?? "UNKNOWN"}`;
    return record;
  } catch (error) {
    const code = error instanceof ArtworkError ? error.code : "UNEXPECTED_ERROR";
    record.outcome = "FAILED";
    record.error_code = code;
    record.error_message = sanitizeMessage(error?.message);
    if (opts.apply) {
      const { data, error: failError } = await deps.supabase.rpc("admin_record_pokemon_species_artwork_failure", {
        p_national_dex_number: n,
        p_error_code: code,
        p_error_message: record.error_message,
        p_source_url: source?.sourceUrl ?? null,
      });
      record.failure_recorded = !failError;
      record.image_preserved = data?.image_preserved ?? null;
      if (failError) record.failure_record_error = sanitizeMessage(failError.message);
    }
    return record;
  }
}

// ---------------------------------------------------------------------------
// Rede (produção): timeout de 20 s e 1 nova tentativa em 429/5xx/falha de rede
// ---------------------------------------------------------------------------
export function makeHttp({ fetchImpl = fetch, userAgent, timeoutMs = 20000, retryDelayMs = 1500, sleep } = {}) {
  const wait = sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
  async function request(url, kind) {
    let lastError;
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const response = await fetchImpl(url, { headers: { "User-Agent": userAgent, Accept: kind === "json" ? "application/json" : "image/png" }, signal: AbortSignal.timeout(timeoutMs) });
        if (response.status === 404) throw new ArtworkError("SOURCE_NOT_FOUND", `404 em ${url}`);
        if (response.status === 429 || response.status >= 500) {
          lastError = new ArtworkError("SOURCE_UNAVAILABLE", `HTTP ${response.status} em ${url}`);
          const retryAfter = Number(response.headers.get("retry-after"));
          if (attempt === 1) { await wait(Number.isFinite(retryAfter) && retryAfter > 0 ? Math.min(retryAfter, 30) * 1000 : retryDelayMs); continue; }
          throw lastError;
        }
        if (!response.ok) throw new ArtworkError("SOURCE_REQUEST", `HTTP ${response.status} em ${url}`);
        if (kind === "json") return await response.json();
        const length = Number(response.headers.get("content-length"));
        if (Number.isFinite(length) && length > MAX_BYTES) throw new ArtworkError("VALIDATION_TOO_LARGE", `content-length ${length}`);
        return Buffer.from(await response.arrayBuffer());
      } catch (error) {
        if (error instanceof ArtworkError) throw error;
        lastError = new ArtworkError(error?.name === "TimeoutError" ? "DOWNLOAD_TIMEOUT" : "SOURCE_NETWORK", sanitizeMessage(error?.message));
        if (attempt === 1) { await wait(retryDelayMs); continue; }
      }
    }
    throw lastError;
  }
  return {
    fetchJson: (url) => request(url, "json"),
    fetchBinary: (url) => request(url, "binary"),
  };
}
