#!/usr/bin/env node
/*
================================================================
Projeto.....: Project Mimikyu
Script......: bootstrap-card-sets / run-batch-a.mjs
Rodada......: CATALOG-HISTORICAL-BOOTSTRAP-02-BATCH-A-PREPARE-01
Data........: 2026-09-09
Status......: ONE-SHOT DESCARTÁVEL — não é infraestrutura permanente.

Objetivo....:
Cadastrar os 71 Card Sets AUTO_READY do Lote A, reutilizando
EXCLUSIVAMENTE a função canônica `admin_create_card_set()`
(ADR-023). Nenhuma tabela, RPC, migration ou external reference é
criada por este script.

Modos.......:
  DRY_RUN (padrão) — não grava nada. Lê o estado atual, valida o
                     manifest e classifica cada linha.
  APPLY            — chama admin_create_card_set() uma vez por Set.

Classificação por linha:
  READY               → não existe; pode ser criado
  ALREADY_EXISTS_MATCH→ já existe e todos os campos batem → SKIP
  CONFLICT            → já existe com pelo menos um campo divergente → STOP
  INVALID             → manifest não passa nas invariantes locais

Autenticação:
  Por usuário admin real, via e-mail/senha lidos do ambiente. Nada é
  hardcoded. A senha nunca é impressa. O script falha cedo se a
  sessão resultante não for admin (is_admin() = false), antes de
  qualquer escrita.

Localização:
  Vive em `web/scripts/` porque depende de `@supabase/supabase-js`, que
  pertence ao projeto `web/`. Nenhum `package.json` ou `node_modules` é
  criado na raiz do repositório.

Variáveis de ambiente obrigatórias (as mesmas já usadas pelo `web/`):
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  MMKYU_ADMIN_EMAIL
  MMKYU_ADMIN_PASSWORD

Uso (a partir de `web/`):
  node scripts/bootstrap-card-sets/run-batch-a.mjs                 # DRY_RUN
  node scripts/bootstrap-card-sets/run-batch-a.mjs --apply         # APPLY

Saídas:
  web/scripts/bootstrap-card-sets/out/batch-a-<modo>-<timestamp>.json
  web/scripts/bootstrap-card-sets/out/batch-a-<modo>-<timestamp>.csv

Notas de contrato (medidas em 2026-09-09):
  - `release_order` gravado é TEMPORÁRIO (>= 1000). Confirmado que
    nenhum Card Set POKEMON usa >= 1000 (max atual = 18). A
    normalização definitiva é uma rodada própria, fora daqui.
  - O external reference NÃO é criado aqui. O processador
    `import-catalog-cards` já faz upsert de
    `card_set_external_reference` quando a importação é iniciada com
    `card_set_id` + `external_set_id`.
  - Nomes são `trim()`ados: a TCGdex devolve alguns com espaço final.
================================================================
*/

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFEST = join(HERE, "manifest-batch-a.json");
const OUT_DIR = join(HERE, "out");

const APPLY = process.argv.includes("--apply");
const MODE = APPLY ? "APPLY" : "DRY_RUN";

const REQUIRED_ENV = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "MMKYU_ADMIN_EMAIL",
  "MMKYU_ADMIN_PASSWORD",
];

function fail(msg) {
  console.error(`\n[ABORT] ${msg}\n`);
  process.exit(1);
}

/* ---------------------------------------------------------------
   Invariantes locais do manifest — não dependem do banco.
   Espelham os CHECKs reais de public.card_set.
--------------------------------------------------------------- */
const CODE_RE = /^[A-Z0-9][A-Z0-9._-]*$/;
const SET_TYPES = new Set(["REGULAR", "SPECIAL", "PROMO", "ENERGY"]);
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function validarLinha(s) {
  const e = [];
  if (!s.tcgdex_set_id) e.push("SEM_TCGDEX_SET_ID");
  if (!UUID_RE.test(s.expansion_id || "")) e.push("EXPANSION_ID_INVALIDO");
  if (String(s.series_id || "").toUpperCase() !== s.expansion_code) {
    e.push("EXPANSION_NAO_DERIVADA_DE_SERIES_ID");
  }
  if (!CODE_RE.test(s.code || "") || s.code.length > 50) e.push("CODE_INVALIDO");
  const nome = String(s.name ?? "").trim();
  if (!nome) e.push("NAME_VAZIO");
  if (nome.length > 150) e.push("NAME_LONGO");
  if (!SET_TYPES.has(s.set_type)) e.push("SET_TYPE_INVALIDO");
  if (!DATE_RE.test(s.release_date || "")) e.push("RELEASE_DATE_INVALIDA");
  if (!(Number.isInteger(s.base_set_size) && s.base_set_size > 0)) e.push("BASE_SIZE_INVALIDO");
  if (!(Number.isInteger(s.total_set_size) && s.total_set_size >= s.base_set_size)) {
    e.push("TOTAL_MENOR_QUE_BASE");
  }
  if (s.set_type === "PROMO" && s.base_set_size !== s.total_set_size) {
    e.push("PROMO_EXIGE_BASE_IGUAL_TOTAL"); // ck_card_set_promo_size
  }
  if (!(Number.isInteger(s.release_order_temporario) && s.release_order_temporario >= 1000)) {
    e.push("RELEASE_ORDER_TEMPORARIO_FORA_DA_FAIXA");
  }
  return e;
}

function compararComExistente(s, row) {
  const dif = [];
  const nome = String(s.name ?? "").trim();
  if (row.name !== nome) dif.push(`name: "${row.name}" != "${nome}"`);
  if (row.set_type !== s.set_type) dif.push(`set_type: ${row.set_type} != ${s.set_type}`);
  if ((row.release_date ?? null) !== s.release_date) {
    dif.push(`release_date: ${row.release_date} != ${s.release_date}`);
  }
  if (row.base_set_size !== s.base_set_size) {
    dif.push(`base_set_size: ${row.base_set_size} != ${s.base_set_size}`);
  }
  if (row.total_set_size !== s.total_set_size) {
    dif.push(`total_set_size: ${row.total_set_size} != ${s.total_set_size}`);
  }
  return dif;
}

async function main() {
  const faltando = REQUIRED_ENV.filter((k) => !process.env[k]);
  if (faltando.length) fail(`variáveis de ambiente ausentes: ${faltando.join(", ")}`);

  const manifest = JSON.parse(await readFile(MANIFEST, "utf8"));
  const sets = manifest.sets ?? [];
  if (!sets.length) fail("manifest vazio.");

  console.log(`\n=== BOOTSTRAP CARD SETS — LOTE A ===`);
  console.log(`modo .......... ${MODE}`);
  console.log(`manifest ...... ${sets.length} Card Sets`);

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: auth, error: authErr } = await supabase.auth.signInWithPassword({
    email: process.env.MMKYU_ADMIN_EMAIL,
    password: process.env.MMKYU_ADMIN_PASSWORD,
  });
  if (authErr || !auth?.user) fail(`autenticação falhou: ${authErr?.message ?? "sem usuário"}`);

  // Guard obrigatório: a sessão precisa ser admin ANTES de qualquer escrita.
  const { data: ehAdmin, error: adminErr } = await supabase.rpc("is_admin");
  if (adminErr) fail(`is_admin() falhou: ${adminErr.message}`);
  if (ehAdmin !== true) fail("a sessão autenticada não é admin — abortando.");
  console.log(`auth .......... OK (admin confirmado, uid=${auth.user.id})`);

  // Estado atual: apenas as Expansions envolvidas.
  const expansionIds = [...new Set(sets.map((s) => s.expansion_id))];
  const { data: existentes, error: qErr } = await supabase
    .from("card_set")
    .select("id, expansion_id, code, name, set_type, release_order, release_date, base_set_size, total_set_size")
    .in("expansion_id", expansionIds);
  if (qErr) fail(`leitura de card_set falhou: ${qErr.message}`);

  const porChave = new Map(existentes.map((r) => [`${r.expansion_id}|${r.code}`, r]));
  const ordensUsadas = new Set(existentes.map((r) => `${r.expansion_id}|${r.release_order}`));
  console.log(`estado atual .. ${existentes.length} Card Sets nas ${expansionIds.length} Expansions envolvidas\n`);

  const resultados = [];

  for (const s of sets) {
    const linha = {
      tcgdex_set_id: s.tcgdex_set_id,
      expansion_code: s.expansion_code,
      code: s.code,
      status: null,
      detalhe: "",
      card_set_id: null,
    };

    const errosLocais = validarLinha(s);
    if (errosLocais.length) {
      linha.status = "INVALID";
      linha.detalhe = errosLocais.join("+");
      resultados.push(linha);
      continue;
    }

    const existente = porChave.get(`${s.expansion_id}|${s.code}`);
    if (existente) {
      const dif = compararComExistente(s, existente);
      linha.card_set_id = existente.id;
      if (dif.length === 0) {
        linha.status = "ALREADY_EXISTS_MATCH";
        linha.detalhe = "skip";
      } else {
        linha.status = "CONFLICT";
        linha.detalhe = dif.join("; ");
      }
      resultados.push(linha);
      continue;
    }

    if (ordensUsadas.has(`${s.expansion_id}|${s.release_order_temporario}`)) {
      linha.status = "INVALID";
      linha.detalhe = `release_order ${s.release_order_temporario} já usado nesta Expansion`;
      resultados.push(linha);
      continue;
    }

    if (!APPLY) {
      linha.status = "READY";
      linha.detalhe = "seria criado";
      resultados.push(linha);
      continue;
    }

    const { data: novoId, error: rpcErr } = await supabase.rpc("admin_create_card_set", {
      p_expansion_id: s.expansion_id,
      p_code: s.code,
      p_name: String(s.name).trim(),
      p_set_type: s.set_type,
      p_release_order: s.release_order_temporario,
      p_base_set_size: s.base_set_size,
      p_total_set_size: s.total_set_size,
      p_release_date: s.release_date,
    });

    if (rpcErr) {
      linha.status = "CONFLICT";
      linha.detalhe = `admin_create_card_set falhou: ${rpcErr.message}`;
    } else {
      linha.status = "CREATED";
      linha.card_set_id = novoId;
      linha.detalhe = "criado";
      ordensUsadas.add(`${s.expansion_id}|${s.release_order_temporario}`);
    }
    resultados.push(linha);
  }

  const resumo = resultados.reduce((a, r) => ((a[r.status] = (a[r.status] || 0) + 1), a), {});
  console.log("=== RESUMO ===");
  for (const [k, v] of Object.entries(resumo)) console.log(`  ${k.padEnd(22)} ${v}`);

  const problemas = resultados.filter((r) => r.status === "CONFLICT" || r.status === "INVALID");
  if (problemas.length) {
    console.log("\n=== LINHAS QUE EXIGEM ATENÇÃO ===");
    for (const p of problemas) console.log(`  ${p.tcgdex_set_id} (${p.code}): ${p.status} — ${p.detalhe}`);
  }

  await mkdir(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const baseName = join(OUT_DIR, `batch-a-${MODE.toLowerCase()}-${stamp}`);

  await writeFile(
    `${baseName}.json`,
    JSON.stringify({ modo: MODE, executado_em: new Date().toISOString(), resumo, resultados }, null, 2),
    "utf8",
  );

  const csv = [
    "tcgdex_set_id,expansion_code,code,status,card_set_id,detalhe",
    ...resultados.map((r) =>
      [r.tcgdex_set_id, r.expansion_code, r.code, r.status, r.card_set_id ?? "", `"${String(r.detalhe).replace(/"/g, '""')}"`].join(","),
    ),
  ].join("\n");
  await writeFile(`${baseName}.csv`, csv, "utf8");

  console.log(`\nrelatórios: ${baseName}.json / .csv`);

  await supabase.auth.signOut();

  if (MODE === "APPLY" && problemas.length) process.exit(2);
}

main().catch((e) => fail(e?.stack ?? String(e)));
