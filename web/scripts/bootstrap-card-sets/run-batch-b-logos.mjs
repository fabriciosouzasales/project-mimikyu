#!/usr/bin/env node
/*
================================================================
Projeto.....: Project Mimikyu
Script......: bootstrap-card-sets / run-batch-b-logos.mjs
Rodada......: CATALOG-HISTORICAL-BOOTSTRAP-02-BATCH-B-LOGOS-01
Data........: 2026-09-09
Status......: ONE-SHOT DESCARTÁVEL — não é infraestrutura permanente.

Objetivo....:
Carregar as logos disponíveis na TCGdex para os 82 Card Sets criados
pelo Lote B, reutilizando EXCLUSIVAMENTE o que já existe:

  - bucket privado `card-set-logo` (Query 276, ADR-022);
  - políticas de `storage.objects` já vigentes (admin-only);
  - RPC `admin_set_card_set_logo(uuid, text)` (Query 275, SECURITY DEFINER).

Nenhum schema, RPC, policy, frontend ou pipeline permanente é criado
ou alterado por este script.

Universo....: `manifest-batch-b.json` — as mesmas 82 linhas do Lote B.

Modos.......:
  DRY_RUN (padrão) — não escreve nada. Nenhum upload, nenhuma chamada
                     de RPC. Faz apenas leituras: `card_set`, metadata
                     da TCGdex e um HEAD no asset (só cabeçalhos, sem
                     transferir o corpo da imagem).
  APPLY            — baixa o WEBP, valida, envia ao bucket e só então
                     grava o ponteiro.

Classificação por linha:
  READY              → Set existe, confere com o manifest, tem logo na
                       TCGdex e `logo_storage_path` está vazio
  NO_LOGO_AVAILABLE  → a TCGdex não expõe logo para este Set. Condição
                       NORMAL, nunca erro (38 dos 82, medido em
                       BATCH-B-PREAPPLY-01)
  ALREADY_HAS_LOGO   → `logo_storage_path` já preenchido → SKIP total.
                       Nada é baixado, enviado ou sobrescrito
  SET_NOT_FOUND      → não existe Card Set para (expansion_id, code)
  CONFLICT           → o Card Set existe mas diverge do manifest
  UPLOADED           → (APPLY) arquivo enviado e ponteiro gravado
  FAILED             → (APPLY) falha isolada nesta linha; ver `detalhe`

Contrato do APPLY, por Set, nesta ordem exata:
  1. GET   `<logo>.webp` na TCGdex
  2. valida HTTP 200
  3. valida Content-Type compatível com `image/webp`
  4. valida tamanho <= 5 MB (mesmo teto do CardSetLogoUploader)
  5. upload em `card-set-logo` no caminho `{card_set_id}/{uuid}.webp`
     (`upsert: false`) — mesmo padrão do uploader do frontend
  6. só depois, `admin_set_card_set_logo(card_set_id, caminho)`
  7. se a RPC falhar, tenta remover o arquivo recém-enviado (o Card Set
     permanece sem logo, íntegro, e a linha vira FAILED)

A URL da TCGdex NUNCA é persistida — `admin_set_card_set_logo()` inclusive
rejeita URL absoluta (`ADMIN_SET_CARD_SET_LOGO_INVALID_PATH`). O que vai
para o banco é sempre o caminho relativo dentro do bucket.

Logo já existente nunca é removida nem substituída: o fluxo só age quando
o ponteiro está vazio.

Isolamento de falha:
  Cada Set é processado dentro do seu próprio try/catch. Uma falha de
  rede, de upload ou de RPC afeta SOMENTE aquela linha — não desfaz nem
  toca nos Card Sets já criados, e não interrompe as demais. Basta
  reexecutar: as linhas que deram certo voltam como ALREADY_HAS_LOGO e
  as que falharam voltam como READY.

Autenticação:
  Por usuário admin real, via e-mail/senha lidos do ambiente. Nada é
  hardcoded, nenhum `service_role`, a senha nunca é impressa. O script
  falha cedo se a sessão resultante não for admin (`is_admin()` = false),
  antes de qualquer escrita.

Variáveis de ambiente obrigatórias (as mesmas dos Lotes A e B):
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  MMKYU_ADMIN_EMAIL
  MMKYU_ADMIN_PASSWORD

Uso (a partir de `web/`):
  node scripts/bootstrap-card-sets/run-batch-b-logos.mjs              # DRY_RUN
  node scripts/bootstrap-card-sets/run-batch-b-logos.mjs --apply      # APPLY

Saídas:
  web/scripts/bootstrap-card-sets/out/batch-b-logos-<modo>-<timestamp>.json
  web/scripts/bootstrap-card-sets/out/batch-b-logos-<modo>-<timestamp>.csv

Notas de contrato (medidas em 2026-09-09):
  - Discovery de BATCH-B-PREAPPLY-01: 44/82 com logo, 38/82 sem;
    `.webp` disponível em 44/44; `.png` em 43/44 (`ecard1` é a exceção);
    `.jpg` em 0/44. Por isso o formato é WEBP, sem fallback.
  - `symbol` NÃO é usado como substituto de logo — são coisas distintas.
  - Estado no início desta rodada: os 82 existem, 199 Card Sets POKEMON
    no total, e nenhum dos 82 tem `logo_storage_path` preenchido.
================================================================
*/

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createClient } from "@supabase/supabase-js";

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFEST = join(HERE, "manifest-batch-b.json");
const OUT_DIR = join(HERE, "out");

const APPLY = process.argv.includes("--apply");
const MODE = APPLY ? "APPLY" : "DRY_RUN";

const BUCKET = "card-set-logo";
const MAX_LOGO_BYTES = 5 * 1024 * 1024; // 5 MB — mesmo teto do CardSetLogoUploader.
const CONTENT_TYPE = "image/webp";
const TCGDEX_SET = "https://api.tcgdex.net/v2/en/sets/";

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

/** `image/webp` e `image/webp; charset=...` são aceitos; qualquer outro tipo, não. */
export function contentTypeCompativel(valor) {
  return String(valor ?? "")
    .split(";")[0]
    .trim()
    .toLowerCase() === CONTENT_TYPE;
}

/** Divergência entre o Card Set gravado e a linha do manifest. */
export function compararComManifest(s, row) {
  const dif = [];
  const nome = String(s.name ?? "").trim();
  if (row.name !== nome) dif.push(`name: "${row.name}" != "${nome}"`);
  if (row.set_type !== s.set_type) dif.push(`set_type: ${row.set_type} != ${s.set_type}`);
  if ((row.release_date ?? null) !== s.release_date) dif.push(`release_date: ${row.release_date} != ${s.release_date}`);
  if (row.base_set_size !== s.base_set_size) dif.push(`base_set_size: ${row.base_set_size} != ${s.base_set_size}`);
  if (row.total_set_size !== s.total_set_size) dif.push(`total_set_size: ${row.total_set_size} != ${s.total_set_size}`);
  return dif;
}

/** Metadata da TCGdex. Devolve a base do logo (sem extensão) ou null. */
async function lerLogoTcgdex(tcgdexSetId) {
  const resposta = await fetch(TCGDEX_SET + encodeURIComponent(tcgdexSetId));
  if (!resposta.ok) throw new Error(`TCGdex respondeu ${resposta.status} para ${tcgdexSetId}`);
  const dados = await resposta.json();
  return dados?.logo ?? null;
}

async function main() {
  const faltando = REQUIRED_ENV.filter((k) => !process.env[k]);
  if (faltando.length) fail(`variáveis de ambiente ausentes: ${faltando.join(", ")}`);

  const manifest = JSON.parse(await readFile(MANIFEST, "utf8"));
  const sets = manifest.sets ?? [];
  if (!sets.length) fail("manifest vazio.");

  console.log(`\n=== BOOTSTRAP CARD SET LOGOS — LOTE B ===`);
  console.log(`modo .......... ${MODE}`);
  console.log(`universo ...... ${sets.length} Card Sets (manifest-batch-b.json)`);
  console.log(`bucket ........ ${BUCKET} (privado, políticas existentes)`);
  console.log(`formato ....... ${CONTENT_TYPE}, até ${MAX_LOGO_BYTES} bytes`);

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

  // Estado atual dos Card Sets das Expansions envolvidas.
  const expansionIds = [...new Set(sets.map((s) => s.expansion_id))];
  const { data: existentes, error: qErr } = await supabase
    .from("card_set")
    .select("id, expansion_id, code, name, set_type, release_date, base_set_size, total_set_size, logo_storage_path")
    .in("expansion_id", expansionIds);
  if (qErr) fail(`leitura de card_set falhou: ${qErr.message}`);

  const porChave = new Map(existentes.map((r) => [`${r.expansion_id}|${r.code}`, r]));
  console.log(`estado atual .. ${existentes.length} Card Sets nas ${expansionIds.length} Expansions envolvidas\n`);

  const resultados = [];

  for (const s of sets) {
    const linha = {
      tcgdex_set_id: s.tcgdex_set_id,
      expansion_code: s.expansion_code,
      code: s.code,
      card_set_id: null,
      status: null,
      logo_storage_path: null,
      detalhe: "",
    };

    try {
      // 1) Localizar o Card Set já criado.
      const existente = porChave.get(`${s.expansion_id}|${s.code}`);
      if (!existente) {
        linha.status = "SET_NOT_FOUND";
        linha.detalhe = "nenhum Card Set para (expansion_id, code)";
        resultados.push(linha);
        continue;
      }
      linha.card_set_id = existente.id;

      // 2) Confirmar que corresponde ao manifest.
      const dif = compararComManifest(s, existente);
      if (dif.length) {
        linha.status = "CONFLICT";
        linha.detalhe = dif.join("; ");
        resultados.push(linha);
        continue;
      }

      // 3) Ponteiro já preenchido: SKIP total. Nada é baixado nem tocado.
      if (existente.logo_storage_path) {
        linha.status = "ALREADY_HAS_LOGO";
        linha.logo_storage_path = existente.logo_storage_path;
        linha.detalhe = "skip — logo existente nunca é removida ou substituída";
        resultados.push(linha);
        continue;
      }

      // 4) Metadata da TCGdex.
      const logoBase = await lerLogoTcgdex(s.tcgdex_set_id);
      if (!logoBase) {
        linha.status = "NO_LOGO_AVAILABLE";
        linha.detalhe = "TCGdex não expõe logo para este Set (condição normal)";
        resultados.push(linha);
        continue;
      }
      const urlWebp = `${logoBase}.webp`;

      if (!APPLY) {
        // DRY_RUN: HEAD apenas — cabeçalhos, sem transferir a imagem.
        let head;
        try {
          head = await fetch(urlWebp, { method: "HEAD" });
        } catch (e) {
          linha.status = "FAILED";
          linha.detalhe = `HEAD falhou em ${urlWebp}: ${e.message}`;
          resultados.push(linha);
          continue;
        }
        const tipo = head.headers.get("content-type");
        const tamanho = Number(head.headers.get("content-length") ?? 0);
        if (!head.ok) {
          linha.status = "FAILED";
          linha.detalhe = `HEAD ${head.status} em ${urlWebp}`;
        } else if (!contentTypeCompativel(tipo)) {
          linha.status = "FAILED";
          linha.detalhe = `Content-Type "${tipo}" incompatível com ${CONTENT_TYPE}`;
        } else if (tamanho > MAX_LOGO_BYTES) {
          linha.status = "FAILED";
          linha.detalhe = `tamanho ${tamanho} acima do teto de ${MAX_LOGO_BYTES}`;
        } else {
          linha.status = "READY";
          linha.detalhe = `seria enviado (${tipo}, ${tamanho || "?"} bytes)`;
        }
        resultados.push(linha);
        continue;
      }

      // 5) APPLY — download.
      const resposta = await fetch(urlWebp);
      if (!resposta.ok) {
        linha.status = "FAILED";
        linha.detalhe = `download HTTP ${resposta.status} em ${urlWebp}`;
        resultados.push(linha);
        continue;
      }
      const tipo = resposta.headers.get("content-type");
      if (!contentTypeCompativel(tipo)) {
        linha.status = "FAILED";
        linha.detalhe = `Content-Type "${tipo}" incompatível com ${CONTENT_TYPE}`;
        resultados.push(linha);
        continue;
      }
      const bytes = new Uint8Array(await resposta.arrayBuffer());
      if (bytes.byteLength === 0) {
        linha.status = "FAILED";
        linha.detalhe = "corpo vazio";
        resultados.push(linha);
        continue;
      }
      if (bytes.byteLength > MAX_LOGO_BYTES) {
        linha.status = "FAILED";
        linha.detalhe = `tamanho ${bytes.byteLength} acima do teto de ${MAX_LOGO_BYTES}`;
        resultados.push(linha);
        continue;
      }

      // 6) Upload — mesmo padrão de caminho do CardSetLogoUploader.
      const caminho = `${existente.id}/${crypto.randomUUID()}.webp`;
      const { error: uploadErr } = await supabase.storage
        .from(BUCKET)
        .upload(caminho, bytes, { contentType: CONTENT_TYPE, upsert: false });
      if (uploadErr) {
        linha.status = "FAILED";
        linha.detalhe = `upload falhou: ${uploadErr.message}`;
        resultados.push(linha);
        continue;
      }

      // 7) Só depois do upload confirmado, grava o ponteiro relativo.
      const { error: rpcErr } = await supabase.rpc("admin_set_card_set_logo", {
        p_card_set_id: existente.id,
        p_logo_storage_path: caminho,
      });
      if (rpcErr) {
        // Remove o arquivo órfão. O Card Set continua sem logo, íntegro.
        let limpeza = "arquivo órfão removido";
        const { error: removeErr } = await supabase.storage.from(BUCKET).remove([caminho]);
        if (removeErr) limpeza = `NÃO foi possível remover o arquivo órfão (${caminho}): ${removeErr.message}`;
        linha.status = "FAILED";
        linha.detalhe = `admin_set_card_set_logo falhou: ${rpcErr.message} — ${limpeza}`;
        resultados.push(linha);
        continue;
      }

      linha.status = "UPLOADED";
      linha.logo_storage_path = caminho;
      linha.detalhe = `${bytes.byteLength} bytes`;
      resultados.push(linha);
    } catch (e) {
      // Falha isolada: não interrompe o lote nem afeta Card Sets já criados.
      linha.status = "FAILED";
      linha.detalhe = `exceção: ${e?.message ?? String(e)}`;
      resultados.push(linha);
    }
  }

  const resumo = resultados.reduce((a, r) => ((a[r.status] = (a[r.status] || 0) + 1), a), {});
  console.log("=== RESUMO ===");
  for (const [k, v] of Object.entries(resumo)) console.log(`  ${k.padEnd(20)} ${v}`);

  const problemas = resultados.filter(
    (r) => r.status === "FAILED" || r.status === "CONFLICT" || r.status === "SET_NOT_FOUND",
  );
  if (problemas.length) {
    console.log("\n=== LINHAS QUE EXIGEM ATENÇÃO (reexecutáveis) ===");
    for (const p of problemas) console.log(`  ${p.tcgdex_set_id} (${p.code}): ${p.status} — ${p.detalhe}`);
  }

  await mkdir(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const baseName = join(OUT_DIR, `batch-b-logos-${MODE.toLowerCase()}-${stamp}`);

  await writeFile(
    `${baseName}.json`,
    JSON.stringify({ modo: MODE, executado_em: new Date().toISOString(), resumo, resultados }, null, 2),
    "utf8",
  );

  const csv = [
    "tcgdex_set_id,expansion_code,code,card_set_id,status,logo_storage_path,detalhe",
    ...resultados.map((r) =>
      [
        r.tcgdex_set_id,
        r.expansion_code,
        r.code,
        r.card_set_id ?? "",
        r.status,
        r.logo_storage_path ?? "",
        `"${String(r.detalhe).replace(/"/g, '""')}"`,
      ].join(","),
    ),
  ].join("\n");
  await writeFile(`${baseName}.csv`, csv, "utf8");

  console.log(`\nrelatórios: ${baseName}.json / .csv`);

  await supabase.auth.signOut();

  if (MODE === "APPLY" && problemas.length) process.exit(2);
}

main().catch((e) => fail(e?.stack ?? String(e)));
