/*
===============================================================================
Projeto.....: Project Mimikyu — Pokédex P3a
Script......: run-import-pokemon-species-profile.mjs
Objetivo....: importar da PokéAPI o perfil de referência das espécies (classificação,
              descrição, lendário/mítico/bebê; tipos, altura e peso da forma padrão)
              e registrar via as funções admin da Query 6133. Núcleo em profile-lib.mjs.

Autenticação: mesma do importador de imagens (P2) — sessão de ADMINISTRADOR real
  (signInWithPassword), sem service_role. Credenciais só por variável de ambiente;
  nunca impressas nem gravadas no relatório.

Modos:
  DRY_RUN (padrão) — login + leitura do status; consulta a PokéAPI e monta os payloads,
    sem nenhuma RPC de escrita. O relatório mostra tipos, medidas, indicadores, textos
    selecionados (idioma + versão) e a cobertura de idiomas.
  APPLY (--apply)  — registra no banco.

Seleção (obrigatória, uma delas):
  --pilot                 as 10 espécies do piloto da P2 (1, 25, 150, 201, 493, 649, 721, 905, 906, 1025)
  --only=1,25,150         números nacionais específicos
  --all --confirm-all     as 1.025 (bloqueado sem --confirm-all)
Outras:
  --force                 reprocessa espécies já IMPORTED (o banco devolve UNCHANGED se nada mudou)

Uso (PowerShell, a partir de web/; variáveis como no piloto da P2):
  node scripts/import-pokemon-species-profile/run-import-pokemon-species-profile.mjs --pilot
  node scripts/import-pokemon-species-profile/run-import-pokemon-species-profile.mjs --pilot --apply
===============================================================================
*/

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { argv, exit } from "node:process";
import { createClient } from "@supabase/supabase-js";
import { LANGUAGES, PILOT_NUMBERS, dexPad, makeHttp, processSpecies, sanitizeMessage, summarizeCoverage } from "./profile-lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, "out");
const USER_AGENT = "MMKYU-Collector-species-profile-import/1.0 (+uso administrativo, baixo volume)";
const PAUSE_MS = 400;
const ENV_REQUIRED = ["NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY", "MMKYU_ADMIN_EMAIL", "MMKYU_ADMIN_PASSWORD"];

export function parseArgs(args) {
  const opts = { apply: false, force: false, numbers: null };
  let all = false;
  let confirmAll = false;
  for (const arg of args) {
    if (arg === "--apply") opts.apply = true;
    else if (arg === "--force") opts.force = true;
    else if (arg === "--pilot") opts.numbers = [...PILOT_NUMBERS];
    else if (arg === "--all") all = true;
    else if (arg === "--confirm-all") confirmAll = true;
    else if (arg.startsWith("--only=")) {
      const list = arg.slice(7).split(",").map((s) => s.trim()).filter(Boolean);
      if (list.length === 0 || list.some((s) => !/^\d{1,4}$/.test(s))) throw new Error("ARG_INVALIDO: --only aceita números nacionais separados por vírgula.");
      opts.numbers = [...new Set(list.map(Number))].sort((a, b) => a - b);
    } else throw new Error(`ARG_DESCONHECIDO: ${arg}`);
  }
  if (all) {
    if (!confirmAll) throw new Error("CARGA_INTEGRAL_BLOQUEADA: --all exige --confirm-all.");
    opts.numbers = Array.from({ length: 1025 }, (_, i) => i + 1);
  }
  if (!opts.numbers) throw new Error("SELECAO_AUSENTE: use --pilot, --only=... ou --all --confirm-all.");
  if (opts.numbers.some((n) => n < 1 || n > 1025)) throw new Error("ARG_INVALIDO: números fora de 1..1025.");
  return opts;
}

async function loadStatus(supabase) {
  const status = new Map();
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase.rpc("admin_list_pokemon_species_profile_status", { p_status: null, p_limit: 1000, p_offset: offset });
    if (error) throw new Error(`FALHA_STATUS: ${sanitizeMessage(error.message)}`);
    for (const row of data ?? []) status.set(row.national_dex_number, row.profile_status);
    if (!data || data.length < 1000) break;
  }
  return status;
}

async function main() {
  const opts = parseArgs(argv.slice(2));
  const missing = ENV_REQUIRED.filter((k) => !process.env[k]);
  if (missing.length) throw new Error(`ENV_AUSENTE: ${missing.join(", ")}. Defina no ambiente — nunca por argumento.`);

  const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: auth, error: authError } = await supabase.auth.signInWithPassword({
    email: process.env.MMKYU_ADMIN_EMAIL,
    password: process.env.MMKYU_ADMIN_PASSWORD,
  });
  if (authError || !auth?.session) throw new Error(`FALHA_LOGIN: ${sanitizeMessage(authError?.message ?? "sessão ausente")}`);
  const { data: isAdmin, error: adminError } = await supabase.rpc("is_admin");
  if (adminError) throw new Error(`FALHA_IS_ADMIN: ${sanitizeMessage(adminError.message)}`);
  if (isAdmin !== true) throw new Error("NAO_ADMIN: sessão sem papel administrativo. Abortado antes de qualquer leitura/escrita.");

  const status = await loadStatus(supabase);
  if (status.size !== 1025) throw new Error(`UNIVERSO_DIVERGENTE: ${status.size} espécies no status (esperado 1025).`);

  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const mode = opts.apply ? "apply" : "dry-run";
  const http = makeHttp({ userAgent: USER_AGENT });
  const deps = { fetchJson: http.fetchJson, supabase, now: () => new Date() };

  console.log(`[profile] modo ${mode.toUpperCase()} — ${opts.numbers.length} espécie(s)${opts.force ? " — --force" : ""}`);
  const records = [];
  for (const n of opts.numbers) {
    const record = await processSpecies(n, deps, { apply: opts.apply, force: opts.force, currentStatus: status.get(n) ?? "PENDING" });
    records.push(record);
    const langs = record.coverage
      ? LANGUAGES.map(({ code }) => `${code}: genus ${record.coverage[code].genus ? "sim" : "não"}, descrição ${record.coverage[code].flavor ?? "não"}`).join(" | ")
      : record.error_code ?? "";
    const detail = record.types ? `${record.types.join("/")} · ${record.height_dm} dm · ${record.weight_hg} hg · ${langs}` : langs;
    console.log(`[profile] #${dexPad(n)} ${record.outcome} ${detail}`);
    if (record.outcome !== "SKIPPED_ALREADY_IMPORTED") await new Promise((r) => setTimeout(r, PAUSE_MS));
  }

  const summary = records.reduce((acc, r) => ((acc[r.outcome] = (acc[r.outcome] ?? 0) + 1), acc), {});
  const coverage = summarizeCoverage(records);
  const selection = "Descrição: por idioma, a entrada da versão de jogo mais recente (maior id de versão na PokéAPI). Classificação: entrada única por idioma. Normalização: só quebras/hífen suave/espaços.";
  await mkdir(OUT_DIR, { recursive: true });
  const reportPath = join(OUT_DIR, `species-profile-${mode}-${stamp}.json`);
  await writeFile(reportPath, JSON.stringify({ mode, generated_at: new Date().toISOString(), selection, summary, coverage, records }, null, 2));
  await supabase.auth.signOut();

  console.log(`[profile] resumo ${JSON.stringify(summary)}`);
  for (const [code, item] of Object.entries(coverage.languages)) {
    console.log(`[profile] cobertura ${code}: classificação ${item.genus}/${coverage.species_resolved} · descrição ${item.flavor}/${coverage.species_resolved} · versões ${JSON.stringify(item.versions)}`);
  }
  console.log(`[profile] relatório: ${reportPath}`);
  if (records.some((r) => r.outcome === "FAILED")) exit(2);
}

if (import.meta.url === `file://${argv[1]}` || fileURLToPath(import.meta.url) === argv[1]) {
  main().catch((error) => {
    console.error(`[profile] ABORTADO: ${sanitizeMessage(error?.message)}`);
    exit(1);
  });
}
