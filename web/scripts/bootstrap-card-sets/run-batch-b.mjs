#!/usr/bin/env node
/*
================================================================
Projeto.....: Project Mimikyu
Script......: bootstrap-card-sets / run-batch-b.mjs
Rodada......: CATALOG-HISTORICAL-BOOTSTRAP-02-BATCH-B-CORRECTION-01
Data........: 2026-09-09
Status......: ONE-SHOT DESCARTÁVEL — não é infraestrutura permanente.

Objetivo....:
Cadastrar os 82 Card Sets do Lote B, reutilizando EXCLUSIVAMENTE a
função canônica `admin_create_card_set()` (ADR-023). Nenhuma tabela,
RPC, migration ou external reference é criada por este script.

Mesmo padrão operacional seguro do `run-batch-a.mjs`, com três
invariantes adicionais próprias do Lote B:

  1. Roteamento de Expansion explícito por linha.
     No Lote A toda linha satisfazia `upper(series_id) = expansion_code`.
     No Lote B as Series `tk` (Trainer Kits) e `mc` (McDonald's) não
     possuem Expansion própria (ROUTE_AT_CARD_SET_LEVEL) — o destino é
     decidido por evidência editorial de era. Cada linha declara
     `roteamento_expansion` e `roteamento_evidencia`, e o validador
     cobra a bijeção apenas quando o roteamento é SERIES_BIJECTION.

  2. Guard de PROMO por Expansion (ADR-015).
     ADR-015 define no máximo uma série promocional por Expansion, mas
     o índice único parcial recomendado NÃO existe no banco físico
     (confirmado em 2026-09-09). O guard aqui é local e preventivo:
     roda antes de qualquer escrita e aborta se algum destino passaria
     de um PROMO.
     Só entra na conta o PROMO **realmente novo** — isto é, aquele cuja
     chave (expansion_id, code) ainda não existe. Um PROMO do manifest
     que já exista é o MESMO registro (reexecução após APPLY, ou
     retomada de APPLY parcial) e segue pelo fluxo normal —
     ALREADY_EXISTS_MATCH ou CONFLICT —, nunca pelo guard. Sem isso, um
     segundo DRY_RUN após o APPLY abortaria lendo o próprio PROMO
     recém-criado como se fosse um segundo.

  3. `name_origem` obrigatório.
     Os 82 Sets retornam 404 no endpoint `/pt/` da TCGdex (medido set a
     set; o endpoint está vivo — `bw2`, `sm3.5`, `col1`, `g1` e `svp`
     respondem 200). Estado do manifest: **81 EN_PROVISIONAL + 1
     PT_BR_CONFIRMADO** — `mfb` ("My First Battle") é PT_BR_CONFIRMADO
     porque o Pokémon Press pt-BR já confirmou oficialmente esse mesmo
     nome para o mercado brasileiro; a string estar em inglês não torna
     a origem provisional. EN_PROVISIONAL NÃO afirma que nunca existiu
     edição PT-BR; a revisão de nome é rodada própria.

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
  node scripts/bootstrap-card-sets/run-batch-b.mjs                 # DRY_RUN
  node scripts/bootstrap-card-sets/run-batch-b.mjs --apply         # APPLY

Saídas:
  web/scripts/bootstrap-card-sets/out/batch-b-<modo>-<timestamp>.json
  web/scripts/bootstrap-card-sets/out/batch-b-<modo>-<timestamp>.csv

Notas de contrato (medidas em 2026-09-09):
  - `release_order` gravado é TEMPORÁRIO (>= 1000), contíguo por
    Expansion a partir do próximo livre >= 1000, já considerando os 71
    Card Sets criados pelo Lote A. A normalização definitiva é uma
    rodada própria, fora daqui.
  - O external reference NÃO é criado aqui. O processador
    `import-catalog-cards` já faz upsert de
    `card_set_external_reference` quando a importação é iniciada com
    `card_set_id` + `external_set_id`.
  - Nomes são `trim()`ados: a TCGdex devolve alguns com espaço final.
  - `xyp` entra como PROMO com base = total = 216, por decisão de
    produto (ADR-015 + precedente `SVP`), embora a TCGdex informe
    official = 211.
================================================================
*/

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createClient } from "@supabase/supabase-js";

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFEST = join(HERE, "manifest-batch-b.json");
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
const ROTEAMENTOS = new Set(["SERIES_BIJECTION", "CARD_SET_LEVEL"]);
const SERIES_SEM_EXPANSION = new Set(["tk", "mc"]);
const NAME_ORIGENS = new Set(["PT_BR_CONFIRMADO", "EN_PROVISIONAL"]);

// Sets do TCGdex explicitamente fora deste lote — nenhum pode aparecer.
const PROIBIDOS = new Set(["miscp", "jumbo", "xya", "wp"]);

function validarLinha(s) {
  const e = [];
  if (!s.tcgdex_set_id) e.push("SEM_TCGDEX_SET_ID");
  if (PROIBIDOS.has(String(s.tcgdex_set_id))) e.push("SET_FORA_DO_ESCOPO_DO_LOTE_B");
  if (!UUID_RE.test(s.expansion_id || "")) e.push("EXPANSION_ID_INVALIDO");

  if (!ROTEAMENTOS.has(s.roteamento_expansion)) {
    e.push("ROTEAMENTO_EXPANSION_INVALIDO");
  } else if (s.roteamento_expansion === "SERIES_BIJECTION") {
    if (String(s.series_id || "").toUpperCase() !== s.expansion_code) {
      e.push("EXPANSION_NAO_DERIVADA_DE_SERIES_ID");
    }
  } else {
    // CARD_SET_LEVEL só é legítimo para Series que comprovadamente não
    // têm Expansion própria, e exige evidência escrita.
    if (!SERIES_SEM_EXPANSION.has(String(s.series_id || ""))) {
      e.push("ROTEAMENTO_CARD_SET_LEVEL_INDEVIDO");
    }
    if (!String(s.roteamento_evidencia ?? "").trim()) {
      e.push("ROTEAMENTO_SEM_EVIDENCIA");
    }
  }

  if (!CODE_RE.test(s.code || "") || s.code.length > 50) e.push("CODE_INVALIDO");
  const nome = String(s.name ?? "").trim();
  if (!nome) e.push("NAME_VAZIO");
  if (nome.length > 150) e.push("NAME_LONGO");
  if (!NAME_ORIGENS.has(s.name_origem)) e.push("NAME_ORIGEM_INVALIDA");
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

/* ---------------------------------------------------------------
   Guard ADR-015 — no máximo um PROMO por Expansion.

   Função pura, exportada para poder ser exercitada isoladamente
   contra estados sintéticos (pré-APPLY, pós-APPLY, APPLY parcial).

   Regra de idempotência: um PROMO do manifest cuja chave
   (expansion_id, code) JÁ EXISTE não é uma adição — é o mesmo
   registro. Ele sai da conta do guard e é resolvido adiante pelo
   fluxo normal (ALREADY_EXISTS_MATCH se tudo bate, CONFLICT se
   algum campo divergir). Só PROMO realmente novo entra na soma.
--------------------------------------------------------------- */
export function avaliarGuardPromo(sets, existentes) {
  const chavesExistentes = new Set(existentes.map((r) => `${r.expansion_id}|${r.code}`));

  const promoJaNaExpansion = new Map();
  for (const r of existentes) {
    if (r.set_type === "PROMO") {
      promoJaNaExpansion.set(r.expansion_id, (promoJaNaExpansion.get(r.expansion_id) ?? 0) + 1);
    }
  }

  const novosPorExpansion = [];
  const jaCriadosPorExpansion = [];
  const adicoes = new Map();
  for (const s of sets) {
    if (s.set_type !== "PROMO") continue;
    const registro = { expansion_id: s.expansion_id, expansion_code: s.expansion_code, code: s.code };
    if (chavesExistentes.has(`${s.expansion_id}|${s.code}`)) {
      jaCriadosPorExpansion.push(registro);
      continue;
    }
    novosPorExpansion.push(registro);
    adicoes.set(s.expansion_id, (adicoes.get(s.expansion_id) ?? 0) + 1);
  }

  const violacoes = [];
  for (const [expansionId, novos] of adicoes) {
    const jaExiste = promoJaNaExpansion.get(expansionId) ?? 0;
    if (jaExiste + novos > 1) {
      const code = novosPorExpansion.find((d) => d.expansion_id === expansionId).expansion_code;
      violacoes.push(`${code}: ${jaExiste} existente(s) + ${novos} novo(s) no lote`);
    }
  }

  return { violacoes, novosPorExpansion, jaCriadosPorExpansion };
}

async function main() {
  const faltando = REQUIRED_ENV.filter((k) => !process.env[k]);
  if (faltando.length) fail(`variáveis de ambiente ausentes: ${faltando.join(", ")}`);

  const manifest = JSON.parse(await readFile(MANIFEST, "utf8"));
  const sets = manifest.sets ?? [];
  if (!sets.length) fail("manifest vazio.");

  console.log(`\n=== BOOTSTRAP CARD SETS — LOTE B ===`);
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
  console.log(`estado atual .. ${existentes.length} Card Sets nas ${expansionIds.length} Expansions envolvidas`);

  const guard = avaliarGuardPromo(sets, existentes);
  if (guard.violacoes.length) {
    fail(`ADR-015 — mais de um PROMO por Expansion:\n  ${guard.violacoes.join("\n  ")}`);
  }
  console.log(
    `guard PROMO ... OK (<= 1 por Expansion; PROMO novos no lote: ` +
      `${guard.novosPorExpansion.length ? guard.novosPorExpansion.map((d) => `${d.expansion_code}/${d.code}`).join(", ") : "nenhum"}` +
      `${guard.jaCriadosPorExpansion.length ? ` | já criados, fora da conta: ${guard.jaCriadosPorExpansion.map((d) => `${d.expansion_code}/${d.code}`).join(", ")}` : ""})\n`,
  );

  const resultados = [];

  for (const s of sets) {
    const linha = {
      tcgdex_set_id: s.tcgdex_set_id,
      expansion_code: s.expansion_code,
      code: s.code,
      set_type: s.set_type,
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
      ordensUsadas.add(`${s.expansion_id}|${s.release_order_temporario}`);
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

  const porTipo = resultados.reduce((a, r) => ((a[r.set_type] = (a[r.set_type] || 0) + 1), a), {});
  console.log("\n=== DISTRIBUIÇÃO POR set_type ===");
  for (const [k, v] of Object.entries(porTipo)) console.log(`  ${k.padEnd(22)} ${v}`);

  const problemas = resultados.filter((r) => r.status === "CONFLICT" || r.status === "INVALID");
  if (problemas.length) {
    console.log("\n=== LINHAS QUE EXIGEM ATENÇÃO ===");
    for (const p of problemas) console.log(`  ${p.tcgdex_set_id} (${p.code}): ${p.status} — ${p.detalhe}`);
  }

  await mkdir(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const baseName = join(OUT_DIR, `batch-b-${MODE.toLowerCase()}-${stamp}`);

  await writeFile(
    `${baseName}.json`,
    JSON.stringify({ modo: MODE, executado_em: new Date().toISOString(), resumo, por_set_type: porTipo, resultados }, null, 2),
    "utf8",
  );

  const csv = [
    "tcgdex_set_id,expansion_code,code,set_type,status,card_set_id,detalhe",
    ...resultados.map((r) =>
      [r.tcgdex_set_id, r.expansion_code, r.code, r.set_type, r.status, r.card_set_id ?? "", `"${String(r.detalhe).replace(/"/g, '""')}"`].join(","),
    ),
  ].join("\n");
  await writeFile(`${baseName}.csv`, csv, "utf8");

  console.log(`\nrelatórios: ${baseName}.json / .csv`);

  await supabase.auth.signOut();

  if (MODE === "APPLY" && problemas.length) process.exit(2);
}

// Só executa quando invocado diretamente. Importar este módulo (para
// exercitar `avaliarGuardPromo` isoladamente) não dispara o processo.
const invocadoDiretamente =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invocadoDiretamente) {
  main().catch((e) => fail(e?.stack ?? String(e)));
}
