/*
===============================================================================
Projeto.....: Project Mimikyu — Pokédex P2 Lote B
Script......: run-import-pokemon-artwork.mjs
Objetivo....: importar a Official Artwork (forma padrão, PokéAPI) das espécies da
              Pokédex Nacional para o bucket próprio pokemon-species-artwork,
              com original PNG + WebP <= 320 px, e registrar via as funções
              admin da Query 6132. Núcleo em artwork-lib.mjs.

Autenticação: sessão de ADMINISTRADOR real (signInWithPassword), mesmo padrão de
  web/scripts/bootstrap-cards/*.mjs. Nada de service_role: o Storage aceita o
  upload pela policy pokemon_species_artwork_admin_insert (is_admin()) e as
  funções exigem is_admin(). Credenciais SÓ por variável de ambiente; nunca são
  impressas nem gravadas no relatório.

Modos:
  DRY_RUN (padrão) — só leitura no LIVE (login + status). Baixa, valida, converte
    e grava prévias locais em out/preview/ para conferência visual. Nenhum
    upload, nenhuma RPC de escrita.
  APPLY (--apply)  — envia os arquivos e registra no banco.

Seleção (obrigatória, uma delas):
  --pilot                 as 10 espécies do piloto
  --only=1,25,150         números nacionais específicos
  --all --confirm-all     as 1.025 (bloqueado sem --confirm-all)
Outras:
  --force                 reprocessa espécies já IMPORTED (troca só se o conteúdo mudar)

Uso (PowerShell, a partir de web/):
  $env:NEXT_PUBLIC_SUPABASE_URL = "https://qjfutqujxrbzgrtkpgkg.supabase.co"
  $env:NEXT_PUBLIC_SUPABASE_ANON_KEY = "<anon key>"
  $env:MMKYU_ADMIN_EMAIL = "<email admin>"
  $env:MMKYU_ADMIN_PASSWORD = "<senha>"     # digite no terminal; nunca em chat/log
  node scripts/import-pokemon-artwork/run-import-pokemon-artwork.mjs --pilot
  node scripts/import-pokemon-artwork/run-import-pokemon-artwork.mjs --pilot --apply
===============================================================================
*/

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { argv, exit } from "node:process";
import { createClient } from "@supabase/supabase-js";
import sharp from "sharp";
import { PILOT_NUMBERS, dexPad, makeHttp, processSpecies, sanitizeMessage } from "./artwork-lib.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = join(HERE, "out");
const USER_AGENT = "MMKYU-Collector-artwork-import/1.0 (+uso administrativo, baixo volume)";
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
    const { data, error } = await supabase.rpc("admin_list_pokemon_species_artwork_status", { p_status: null, p_limit: 1000, p_offset: offset });
    if (error) throw new Error(`FALHA_STATUS: ${sanitizeMessage(error.message)}`);
    for (const row of data ?? []) status.set(row.national_dex_number, row.artwork_status);
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
  const previewDir = join(OUT_DIR, "preview", stamp);
  if (!opts.apply) await mkdir(previewDir, { recursive: true });

  const http = makeHttp({ userAgent: USER_AGENT });
  const deps = {
    ...http,
    sharp,
    supabase,
    now: () => new Date(),
    writePreview: async (n, png, webp) => {
      await writeFile(join(previewDir, `${dexPad(n)}-original.png`), png);
      await writeFile(join(previewDir, `${dexPad(n)}-w320.webp`), webp);
    },
  };

  console.log(`[artwork] modo ${mode.toUpperCase()} — ${opts.numbers.length} espécie(s)${opts.force ? " — --force" : ""}`);
  const records = [];
  for (const n of opts.numbers) {
    const record = await processSpecies(n, deps, { apply: opts.apply, force: opts.force, currentStatus: status.get(n) ?? "PENDING" });
    records.push(record);
    const detail = record.display
      ? `orig ${record.original.width}x${record.original.height} ${record.original.size_bytes} B · webp ${record.display.width}x${record.display.height} ${record.display.size_bytes} B`
      : record.error_code ?? "";
    console.log(`[artwork] #${dexPad(n)} ${record.outcome} ${detail}${record.warnings.length ? ` · avisos: ${record.warnings.join("; ")}` : ""}`);
    await new Promise((r) => setTimeout(r, PAUSE_MS));
  }

  const summary = records.reduce((acc, r) => ((acc[r.outcome] = (acc[r.outcome] ?? 0) + 1), acc), {});
  const totals = records.reduce((acc, r) => {
    if (r.original) { acc.original_bytes += r.original.size_bytes; acc.display_bytes += r.display.size_bytes; }
    return acc;
  }, { original_bytes: 0, display_bytes: 0 });
  await mkdir(OUT_DIR, { recursive: true });
  const reportPath = join(OUT_DIR, `artwork-${mode}-${stamp}.json`);
  await writeFile(reportPath, JSON.stringify({ mode, generated_at: new Date().toISOString(), summary, totals, records }, null, 2));
  await supabase.auth.signOut();

  console.log(`[artwork] resumo ${JSON.stringify(summary)} · original ${totals.original_bytes} B · webp ${totals.display_bytes} B`);
  console.log(`[artwork] relatório: ${reportPath}${opts.apply ? "" : ` · prévias: ${previewDir}`}`);
  if (records.some((r) => r.outcome === "FAILED")) exit(2);
}

if (import.meta.url === `file://${argv[1]}` || fileURLToPath(import.meta.url) === argv[1]) {
  main().catch((error) => {
    console.error(`[artwork] ABORTADO: ${sanitizeMessage(error?.message)}`);
    exit(1);
  });
}
