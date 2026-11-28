#!/usr/bin/env node
/*
  V1-13 · E4 — sonda de chamadas diretas à API com JWT real (P4-B, S2–S9, E1–E3, F1–F4).

  O que faz: entra com as contas de teste (senha digitada, oculta, nunca gravada), executa os
  passos de um arquivo de casos (RPC do PostgREST ou envio ao Storage) e compara o resultado com
  o esperado. Para no PRIMEIRO desvio: um desvio de segurança significa STOP da E4 e
  encerramento do TEST.

  O que NÃO faz: não executa SQL, não muda a barreira, não cria contas, não grava credenciais nem
  tokens, não imprime corpos de resposta. A saída tem só: passo, papel, RPC, HTTP, código,
  linhas, chaves proibidas encontradas (nomes) e duração.

  Uso (a partir da raiz do repositório):
    node scripts/v1-13/e4-probe.mjs --cases <casos.json> --out <saida.json> [--env web/.env.local]
  O arquivo de casos e a saída ficam FORA do repositório (ex.: Downloads\mmkyu-runs\e4\).
*/
import { readFileSync, writeFileSync } from "node:fs";
import { randomBytes, randomUUID } from "node:crypto";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

/** Mesma regra do front (`web/lib/colecoes/copy-token.ts`) + e-mail. */
export const FORBIDDEN_KEY = /physical|allocation|owner_user|user_id|membership|storage|location|condition|price|email/i;
export const COPY_TOKEN = /^pc1\.[0-9a-f]{64}$/;
const EXPECTS = /^(ok|refused|empty|code:[0-9A-Z]{5}|msg:[A-Z_]{3,64})$/;

/** Valida o arquivo de casos; devolve a lista de problemas (vazia = válido). */
export function validateCases(c) {
  const errs = [];
  if (!c || typeof c !== "object") return ["arquivo de casos inválido"];
  const sessions = c.sessions ?? {};
  for (const [k, v] of Object.entries(sessions)) {
    if (!/^[A-Z][A-Z0-9]{0,5}$/.test(k)) errs.push(`sessão com rótulo inválido: ${k}`);
    if (typeof v !== "string" || !v.includes("@")) errs.push(`sessão ${k}: informe o e-mail da conta de teste`);
  }
  const ids = new Set();
  for (const [i, s] of (c.steps ?? []).entries()) {
    if (s.pause) continue;
    if (!s.id || ids.has(s.id)) errs.push(`passo ${i}: id ausente ou repetido`);
    ids.add(s.id);
    if (s.as !== "anon" && !(s.as in sessions)) errs.push(`${s.id}: sessão desconhecida ${s.as}`);
    if (!s.rpc && !s.storage_upload) errs.push(`${s.id}: informe rpc ou storage_upload`);
    if (s.rpc && !/^[a-z][a-z0-9_]{2,62}$/.test(s.rpc)) errs.push(`${s.id}: nome de RPC inválido`);
    if (!EXPECTS.test(String(s.expect))) errs.push(`${s.id}: expect inválido (${s.expect})`);
    if (s.storage_upload && s.expect !== "refused") errs.push(`${s.id}: envio ao Storage só como recusa esperada`);
  }
  if (!(c.steps ?? []).length) errs.push("nenhum passo");
  return errs;
}

/** Substitui {VAR}, {uid:S}, {FORGED_TOKEN}, {RANDOM_UUID} e tokens capturados. Variável ausente → erro. */
export function expand(value, ctx) {
  if (typeof value === "string") {
    // Variável sozinha com valor numérico (página, linha, coluna) mantém o tipo número no JSON da RPC.
    const only = value.match(/^\{([A-Za-z0-9_]+)\}$/);
    if (only && typeof ctx.vars[only[1]] === "number" && !(only[1] in ctx.captured)) return ctx.vars[only[1]];
    return value.replace(/\{([A-Za-z0-9_:]+)\}/g, (_, name) => {
      if (name === "FORGED_TOKEN") return `pc1.${randomBytes(32).toString("hex")}`;
      if (name === "RANDOM_UUID") return randomUUID();
      if (name.startsWith("uid:")) {
        const u = ctx.uids[name.slice(4)];
        if (!u) throw new Error(`uid desconhecido: ${name}`);
        return u;
      }
      const v = ctx.captured[name] ?? ctx.vars[name];
      if (v === undefined || v === null || v === "") throw new Error(`variável ausente: ${name}`);
      return String(v);
    });
  }
  if (Array.isArray(value)) return value.map((v) => expand(v, ctx));
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, expand(v, ctx)]));
  return value;
}

/** Nomes de chaves proibidas em qualquer nível da resposta (só os nomes). */
export function forbiddenKeys(body, found = new Set()) {
  if (Array.isArray(body)) for (const v of body) forbiddenKeys(v, found);
  else if (body && typeof body === "object") {
    for (const [k, v] of Object.entries(body)) {
      if (FORBIDDEN_KEY.test(k)) found.add(k);
      forbiddenKeys(v, found);
    }
  }
  return [...found].sort();
}

function rowsOf(body) {
  if (Array.isArray(body)) return body.length;
  if (body === null || body === undefined) return 0;
  return 1;
}

/** Compara um resultado com o esperado. `res` = { http, code, msg, body }. */
export function evaluate(step, res) {
  const ok = res.http >= 200 && res.http < 300;
  const e = String(step.expect);
  let pass;
  if (e === "ok") pass = ok;
  else if (e === "refused") pass = !ok;
  else if (e === "empty") pass = ok && rowsOf(res.body) === 0;
  else if (e.startsWith("code:")) pass = !ok && res.code === e.slice(5);
  else pass = !ok && res.msg === e.slice(4);
  const keys = ok && step.scan !== false ? forbiddenKeys(res.body) : [];
  if (keys.length) pass = false; // dado patrimonial ou pessoal na resposta → sempre FAIL
  return { pass, keys, rows: ok ? rowsOf(res.body) : 0 };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Captura um campo da primeira linha para passos seguintes (fica só na memória do processo).
 * Campo `copy_token` só aceita token opaco; os demais (ex.: `pokedex_position_id`) só UUID de catálogo.
 */
export function capture(step, body, captured) {
  for (const [name, field] of Object.entries(step.capture ?? {})) {
    const row = Array.isArray(body) ? body[0] : body;
    const v = row && typeof row === "object" ? row[field] : undefined;
    const ok = typeof v === "string" && (field === "copy_token" ? COPY_TOKEN.test(v) : UUID.test(v));
    if (!ok) return `${step.id}: captura ${name} sem ${field === "copy_token" ? "token opaco" : "identificador"} válido`;
    captured[name] = v;
  }
  return null;
}

function readEnv(path) {
  const env = {};
  for (const line of readFileSync(path, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*(NEXT_PUBLIC_SUPABASE_URL|NEXT_PUBLIC_SUPABASE_ANON_KEY)\s*=\s*(.*?)\s*$/);
    if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  if (!/^https:\/\/[a-z0-9]{20}\.supabase\.co$/.test(env.NEXT_PUBLIC_SUPABASE_URL ?? "") || !env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    throw new Error("URL/chave pública do Supabase ausentes no arquivo de ambiente");
  }
  return { url: env.NEXT_PUBLIC_SUPABASE_URL, anon: env.NEXT_PUBLIC_SUPABASE_ANON_KEY };
}

function askHidden(question) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    rl._writeToOutput = (s) => { if (s.includes(question)) rl.output.write(s); };
    rl.question(question, (a) => { rl.close(); process.stdout.write("\n"); resolve(a); });
  });
}

function askEnter(text) {
  return new Promise((resolve) => {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    rl.question(`\n>>> ${text}\n    Enter para continuar... `, () => { rl.close(); resolve(); });
  });
}

async function signIn(api, email) {
  const password = await askHidden(`Senha da conta de teste ${email}: `);
  const r = await fetch(`${api.url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: api.anon, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token || !j.user?.id) throw new Error(`entrada recusada para ${email} (HTTP ${r.status})`);
  return { token: j.access_token, uid: j.user.id };
}

async function call(api, session, step, ctx) {
  const headers = { apikey: api.anon, "Content-Type": "application/json" };
  if (session) headers.Authorization = `Bearer ${session.token}`;
  const t0 = performance.now();
  let r;
  if (step.storage_upload) {
    const path = expand(step.storage_upload.path, ctx);
    const png = Buffer.from("89504e470d0a1a0a0000000d4948445200000001000000010806000000" + "1f15c4890000000d49444154789c6360000002000154a24f5d0000000049454e44ae426082", "hex");
    r = await fetch(`${api.url}/storage/v1/object/${step.storage_upload.bucket}/${path}`, {
      method: "POST", headers: { ...headers, "Content-Type": "image/png", "x-upsert": "false" }, body: png,
    });
    if (r.ok) {
      // Compensação imediata: o envio não deveria ter sido aceito.
      await fetch(`${api.url}/storage/v1/object/${step.storage_upload.bucket}/${path}`, { method: "DELETE", headers }).catch(() => {});
    }
  } else {
    r = await fetch(`${api.url}/rest/v1/rpc/${step.rpc}`, { method: "POST", headers, body: JSON.stringify(expand(step.args ?? {}, ctx)) });
  }
  const ms = Math.round(performance.now() - t0);
  const text = await r.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = null; }
  const err = !r.ok && body && typeof body === "object" ? body : {};
  const msg = typeof err.message === "string" && /^[A-Z_]{3,64}$/.test(err.message) ? err.message : "";
  const code = typeof err.code === "string" ? err.code : typeof err.statusCode === "string" ? err.statusCode : "";
  return { http: r.status, code, msg, body: r.ok ? body : null, ms };
}

async function main() {
  const arg = (n, d) => { const i = process.argv.indexOf(n); return i > 0 ? process.argv[i + 1] : d; };
  const casesPath = arg("--cases"), outPath = arg("--out"), envPath = arg("--env", "web/.env.local");
  if (!casesPath || !outPath) throw new Error("uso: --cases <casos.json> --out <saida.json> [--env web/.env.local]");
  const cases = JSON.parse(readFileSync(casesPath, "utf8"));
  const errs = validateCases(cases);
  if (errs.length) throw new Error(`casos inválidos:\n  ${errs.join("\n  ")}`);
  const api = readEnv(envPath);
  const sessions = {}, uids = {};
  for (const [label, email] of Object.entries(cases.sessions)) {
    sessions[label] = await signIn(api, email);
    uids[label] = sessions[label].uid;
  }
  const ctx = { vars: cases.vars ?? {}, captured: {}, uids };
  const log = { fase: cases.fase ?? "", inicio_utc: new Date().toISOString(), passos: [], resultado: "" };
  console.log(`\nE4 · fase ${log.fase} · ${cases.steps.length} passos`);
  for (const step of cases.steps) {
    if (step.pause) { await askEnter(step.pause); continue; }
    const res = await call(api, step.as === "anon" ? null : sessions[step.as], step, ctx);
    const ev = evaluate(step, res);
    const capErr = ev.pass && res.http < 300 ? capture(step, res.body, ctx.captured) : null;
    const pass = ev.pass && !capErr;
    const rec = { id: step.id, caso: step.case ?? "", papel: step.as, alvo: step.rpc ?? `storage:${step.storage_upload.bucket}`,
                  esperado: step.expect, http: res.http, codigo: res.code || res.msg, linhas: ev.rows, chaves_proibidas: ev.keys, ms: res.ms,
                  resultado: pass ? "PASS" : "FAIL", motivo: capErr ?? "" };
    log.passos.push(rec);
    console.log(`${pass ? "PASS" : "FAIL"}  ${rec.id.padEnd(10)} ${rec.papel.padEnd(5)} ${rec.alvo.padEnd(48)} HTTP ${rec.http} ${rec.codigo} linhas=${rec.linhas} ${rec.ms} ms${ev.keys.length ? ` CHAVES: ${ev.keys.join(",")}` : ""}${capErr ? ` ${capErr}` : ""}`);
    if (!pass) {
      log.resultado = `STOP no passo ${rec.id}`;
      break;
    }
  }
  if (!log.resultado) log.resultado = "PASS (todos os passos conforme o esperado)";
  log.fim_utc = new Date().toISOString();
  writeFileSync(outPath, JSON.stringify(log, null, 2));
  console.log(`\n${log.resultado}\nRegistro: ${outPath}`);
  process.exitCode = log.resultado.startsWith("PASS") ? 0 : 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((e) => { console.error(`ERRO: ${e.message}`); process.exitCode = 2; });
}
