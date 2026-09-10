#!/usr/bin/env node
/*
================================================================
Projeto.....: Project Mimikyu
Script......: bootstrap-card-sets / run-bootstrap-logos.mjs
Rodada......: CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SET-LOGOS-IMPLEMENTATION-01
Data........: 2026-09-09
Status......: ONE-SHOT DESCARTÁVEL — não é infraestrutura permanente.

Objetivo....:
Carregar as logos disponíveis na TCGdex para os 153 Card Sets criados
pelo bootstrap histórico (71 do Lote A + 82 do Lote B), reutilizando
EXCLUSIVAMENTE o que já existe:

  - bucket privado `card-set-logo` (Query 276, ADR-022);
  - políticas de `storage.objects` já vigentes (admin-only);
  - RPC `admin_set_card_set_logo(uuid, text)` (Query 275, SECURITY DEFINER).

Nenhum schema, RPC, policy, tabela, frontend ou pipeline permanente é
criado ou alterado por este script.

Universo....: `manifest-batch-a.json` (71) + `manifest-batch-b.json` (82).
              Os 46 Card Sets originais ficam FORA por construção — não
              estão em nenhum dos dois manifestos e já têm logo.

Sucede......: `run-batch-b-logos.mjs`, que cobria só o Lote B e era
              WEBP-only. Este generaliza o universo e acrescenta o
              fallback de formato. Mesmo contrato operacional.

Modos.......:
  DRY_RUN (padrão) — não escreve nada. Nenhum download de corpo, nenhum
                     upload, nenhuma chamada de RPC. Só leituras:
                     `card_set`, metadata da TCGdex e HEAD nos assets
                     (cabeçalhos apenas).
  APPLY            — baixa o asset, valida, envia ao bucket e só então
                     grava o ponteiro.

Formato — WEBP primário, PNG fallback:
  Medido em 2026-09-09 sobre os 153. Dos 105 Sets com logo, 103 têm
  `.webp` e 2 NÃO têm: `hgss3` (Undaunted) e `xy3` (Furious Fists), que
  existem apenas em `.png`. Um script WEBP-only os pularia em silêncio.
  A ordem é sempre WEBP → PNG; PNG só entra quando o WEBP não existe.
  `.jpg` não é oferecido pela fonte e não é tentado.

Classificação por linha:
  ALREADY_HAS_LOGO         → `logo_storage_path` já preenchido → SKIP
                             total. Nada é consultado, baixado, enviado
                             ou sobrescrito
  NO_LOGO_AVAILABLE        → a TCGdex não expõe logo. Condição NORMAL,
                             nunca erro (48 dos 153)
  READY                    → (DRY_RUN) tem asset válido e ponteiro vazio
  UPLOADED                 → (APPLY) arquivo enviado e ponteiro gravado
  SET_NOT_FOUND            → não existe Card Set para (expansion_id, code)
  CONFLICT                 → o Card Set existe mas diverge do manifest
  FAILED_METADATA          → a consulta de metadata da TCGdex falhou
  FAILED_ASSET_UNAVAILABLE → há `logo` na metadata, mas nem WEBP nem PNG
                             respondem
  FAILED_DOWNLOAD          → (APPLY) o GET do asset não devolveu 200
  FAILED_VALIDATION        → Content-Type incompatível, corpo vazio ou
                             tamanho acima de 5 MB
  FAILED_UPLOAD            → o upload no bucket falhou
  FAILED_POINTER           → o upload deu certo, a RPC falhou e a
                             releitura CONFIRMOU que o ponteiro não foi
                             gravado; o objeto recém-enviado é removido
  FAILED_POINTER_AMBIGUOUS → o upload deu certo, a RPC falhou e não foi
                             possível confirmar o estado do ponteiro; o
                             objeto é PRESERVADO e o caminho vai para o
                             relatório, para reconciliação manual
  FAILED_UNEXPECTED        → exceção fora das etapas conhecidas

Contrato do APPLY, por Set, nesta ordem exata:
  1. resolve o formato (HEAD em `.webp`, depois `.png`)
  2. GET do formato escolhido
  3. exige HTTP 200
  4. valida Content-Type — `image/webp` ou `image/png`, conforme o
     formato escolhido
  5. valida tamanho <= 5 MB (mesmo teto do CardSetLogoUploader)
  6. upload em `card-set-logo` no caminho `{card_set_id}/{uuid}.{ext}`
     (`upsert: false`) — mesmo padrão do uploader do frontend
  7. só depois, `admin_set_card_set_logo(card_set_id, caminho)`
  8. se a RPC falhar, NÃO remove às cegas — ver abaixo

Resposta ambígua da RPC (corrigido em CORRECTION-01):
  Um erro devolvido por `admin_set_card_set_logo()` não prova que a
  escrita não aconteceu: a transação pode ter sido efetivada no banco e
  a resposta ter se perdido por rede ou timeout. Remover o objeto nesse
  caso deixaria `logo_storage_path` preenchido apontando para um arquivo
  que não existe mais — corrupção silenciosa, visível só no frontend.

  Por isso, quando a RPC erra, o ponteiro é RELIDO antes de qualquer
  remoção:
    - ponteiro == caminho recém-enviado → a escrita ocorreu. NÃO remove.
      A linha vira UPLOADED, com o detalhe registrando que houve resposta
      ambígua confirmada por releitura.
    - ponteiro NULL ou diferente → a escrita não ocorreu. Remove o objeto
      e a linha vira FAILED_POINTER.
    - a releitura também falha → estado desconhecido. NÃO remove, a linha
      vira FAILED_POINTER_AMBIGUOUS e o caminho do objeto vai para o
      relatório (campo `objeto_pendente`).

  Princípio: órfão rastreável é preferível a ponteiro persistido
  apontando para arquivo removido. Um órfão custa bytes no bucket e está
  listado no relatório; o inverso quebra a leitura do Card Set.

A URL da TCGdex NUNCA é persistida — `admin_set_card_set_logo()` inclusive
rejeita URL absoluta (`ADMIN_SET_CARD_SET_LOGO_INVALID_PATH`). O que vai
para o banco é sempre o caminho relativo dentro do bucket. `symbol` NUNCA
é usado como substituto de logo. Logo já existente NUNCA é removida nem
substituída.

Isolamento de falha:
  Logo é enriquecimento editorial, não parte da integridade do Card Set.
  Cada Set é processado no seu próprio try/catch: falha de metadata,
  download, validação, upload ou RPC afeta SOMENTE aquela linha — não
  desfaz nem toca nos Card Sets já criados e não interrompe as demais.
  Nenhuma falha de logo vira rollback de Card Set. Reexecutar é seguro:
  as linhas concluídas voltam como ALREADY_HAS_LOGO e as que falharam
  voltam como READY.

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
  node scripts/bootstrap-card-sets/run-bootstrap-logos.mjs             # DRY_RUN
  node scripts/bootstrap-card-sets/run-bootstrap-logos.mjs --apply     # APPLY

Saídas:
  web/scripts/bootstrap-card-sets/out/bootstrap-logos-<modo>-<timestamp>.json
  web/scripts/bootstrap-card-sets/out/bootstrap-logos-<modo>-<timestamp>.csv

Estado medido em 2026-09-09, antes do APPLY:
  153 Sets localizados, 0 SET_NOT_FOUND, 0 CONFLICT, 0 ALREADY_HAS_LOGO,
  105 com logo (61 do Lote A + 44 do Lote B), 48 sem logo.
  Volume total dos 105: ~1,8 MB; maior arquivo `ru1` com 87 KB.
  Cobertura final possível no catálogo: 46 + 105 = 151 de 199 (75,9 %).
================================================================
*/

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createClient } from "@supabase/supabase-js";

const HERE = dirname(fileURLToPath(import.meta.url));
const MANIFEST_A = join(HERE, "manifest-batch-a.json");
const MANIFEST_B = join(HERE, "manifest-batch-b.json");
const OUT_DIR = join(HERE, "out");

const APPLY = process.argv.includes("--apply");
const MODE = APPLY ? "APPLY" : "DRY_RUN";

const BUCKET = "card-set-logo";
const MAX_LOGO_BYTES = 5 * 1024 * 1024; // 5 MB — mesmo teto do CardSetLogoUploader.
const TCGDEX_SET = "https://api.tcgdex.net/v2/en/sets/";

/** Ordem de preferência de formato. WEBP primeiro; PNG só como fallback. */
export const FORMATOS = [
  { ext: "webp", contentType: "image/webp" },
  { ext: "png", contentType: "image/png" },
];

/**
 * Tamanho exato esperado do universo. Divergência é ABORT antes de
 * autenticar ou escrever: se o número mudou, alguém mexeu num manifesto
 * e o contrato desta rodada não vale mais.
 */
export const UNIVERSO_ESPERADO = { total: 153, A: 71, B: 82 };

/** Exceção capturada → status coerente com a etapa em que ocorreu. */
export const STATUS_POR_ETAPA = {
  metadata: "FAILED_METADATA",
  formato: "FAILED_ASSET_UNAVAILABLE",
  download: "FAILED_DOWNLOAD",
  validacao: "FAILED_VALIDATION",
  upload: "FAILED_UPLOAD",
  // Exceção na etapa do ponteiro: pode haver objeto enviado e estado do
  // banco desconhecido — nunca remove às cegas.
  ponteiro: "FAILED_POINTER_AMBIGUOUS",
};

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

/** `image/webp` e `image/webp; charset=...` são aceitos; qualquer outro, não. */
export function contentTypeCompativel(valor, esperado) {
  return String(valor ?? "").split(";")[0].trim().toLowerCase() === esperado;
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

/* ---------------------------------------------------------------
   Universo — os dois manifestos, com as invariantes do lote.
   Função pura, exportada para poder ser exercitada isoladamente.
--------------------------------------------------------------- */
export function montarUniverso(manifestA, manifestB) {
  const entradas = [
    ...(manifestA.sets ?? []).map((s) => ({ ...s, batch: "A" })),
    ...(manifestB.sets ?? []).map((s) => ({ ...s, batch: "B" })),
  ];

  const erros = [];
  const porChave = new Set();
  const porTcgdex = new Set();
  for (const e of entradas) {
    const chave = `${e.expansion_id}|${e.code}`;
    if (porChave.has(chave)) erros.push(`chave duplicada: ${e.expansion_code}/${e.code}`);
    porChave.add(chave);
    if (porTcgdex.has(e.tcgdex_set_id)) erros.push(`tcgdex_set_id duplicado: ${e.tcgdex_set_id}`);
    porTcgdex.add(e.tcgdex_set_id);
  }

  const porBatch = entradas.reduce((a, e) => ((a[e.batch] = (a[e.batch] || 0) + 1), a), {});

  // Fail-fast do universo — cobrado antes de autenticar ou escrever.
  if (entradas.length !== UNIVERSO_ESPERADO.total) {
    erros.push(`total do universo é ${entradas.length}, esperado ${UNIVERSO_ESPERADO.total}`);
  }
  if ((porBatch.A ?? 0) !== UNIVERSO_ESPERADO.A) {
    erros.push(`Lote A tem ${porBatch.A ?? 0} entradas, esperado ${UNIVERSO_ESPERADO.A}`);
  }
  if ((porBatch.B ?? 0) !== UNIVERSO_ESPERADO.B) {
    erros.push(`Lote B tem ${porBatch.B ?? 0} entradas, esperado ${UNIVERSO_ESPERADO.B}`);
  }

  return { entradas, erros, total: entradas.length, porBatch };
}

/* ---------------------------------------------------------------
   Resposta ambígua da RPC do ponteiro.

   `relerPonteiro()` deve devolver `{ valor }` com o `logo_storage_path`
   atual (podendo ser null) ou `{ erro }` quando a releitura falhar.
   `removerObjeto()` deve devolver `null` em sucesso ou uma mensagem de
   erro. Ambos injetáveis para poder ser exercitados sem rede.

   Nunca remove sem antes CONFIRMAR que o ponteiro não foi gravado.
--------------------------------------------------------------- */
export async function resolverPonteiroAmbiguo({ caminho, mensagemRpc, relerPonteiro, removerObjeto }) {
  const releitura = await relerPonteiro();

  if (releitura?.erro) {
    return {
      status: "FAILED_POINTER_AMBIGUOUS",
      detalhe:
        `admin_set_card_set_logo falhou: ${mensagemRpc} — releitura do ponteiro também falhou: ${releitura.erro}. ` +
        `Objeto PRESERVADO para reconciliação manual (órfão rastreável é preferível a ponteiro apontando para arquivo removido).`,
      logo_storage_path: null,
      objeto_pendente: caminho,
    };
  }

  if (releitura?.valor === caminho) {
    // A escrita ocorreu; só a resposta se perdeu. Preservar o objeto.
    return {
      status: "UPLOADED",
      detalhe: `resposta ambígua da RPC (${mensagemRpc}), mas a releitura confirmou o ponteiro gravado — objeto preservado`,
      logo_storage_path: caminho,
      objeto_pendente: null,
    };
  }

  // Ponteiro NULL ou apontando para outro arquivo: a escrita não ocorreu.
  const erroRemocao = await removerObjeto();
  if (erroRemocao) {
    return {
      status: "FAILED_POINTER_AMBIGUOUS",
      detalhe:
        `admin_set_card_set_logo falhou: ${mensagemRpc}. Ponteiro confirmado como não gravado ` +
        `(${releitura?.valor ?? "NULL"}), mas a remoção do objeto falhou: ${erroRemocao}.`,
      logo_storage_path: null,
      objeto_pendente: caminho,
    };
  }
  return {
    status: "FAILED_POINTER",
    detalhe:
      `admin_set_card_set_logo falhou: ${mensagemRpc}. Ponteiro confirmado como não gravado ` +
      `(${releitura?.valor ?? "NULL"}); objeto recém-enviado removido. Card Set permanece sem logo, íntegro.`,
    logo_storage_path: null,
    objeto_pendente: null,
  };
}

/* ---------------------------------------------------------------
   Primeiro passo — depende só do banco, não da TCGdex.
   Função pura, exportada para a prova de reexecução.
--------------------------------------------------------------- */
export function avaliarCardSet(entrada, existente) {
  if (!existente) {
    return { status: "SET_NOT_FOUND", detalhe: "nenhum Card Set para (expansion_id, code)" };
  }
  const dif = compararComManifest(entrada, existente);
  if (dif.length) return { status: "CONFLICT", detalhe: dif.join("; ") };
  if (existente.logo_storage_path) {
    return {
      status: "ALREADY_HAS_LOGO",
      detalhe: "skip — logo existente nunca é removida ou substituída",
      logo_storage_path: existente.logo_storage_path,
    };
  }
  return { status: "PROSSEGUIR", detalhe: "" };
}

/* ---------------------------------------------------------------
   Resolução de formato — WEBP primeiro, PNG fallback.

   `sondar(url)` deve devolver `{ ok, contentType, bytes }` ou `null`
   quando o asset não existe. Injetável para poder ser exercitado sem
   rede. Nota de campo: a CDN da TCGdex responde a ausência SEM
   cabeçalhos CORS, então no navegador o fetch lança em vez de devolver
   404 — por isso "não existe" é representado por `null`, cobrindo os
   dois comportamentos.
--------------------------------------------------------------- */
export async function escolherFormato(logoBase, sondar) {
  const tentativas = [];
  for (const f of FORMATOS) {
    const url = `${logoBase}.${f.ext}`;
    const r = await sondar(url);
    if (!r || !r.ok) {
      tentativas.push(`${f.ext}: indisponível`);
      continue;
    }
    if (!contentTypeCompativel(r.contentType, f.contentType)) {
      tentativas.push(`${f.ext}: Content-Type "${r.contentType}" != ${f.contentType}`);
      continue;
    }
    if (Number(r.bytes) > MAX_LOGO_BYTES) {
      tentativas.push(`${f.ext}: ${r.bytes} bytes acima do teto de ${MAX_LOGO_BYTES}`);
      continue;
    }
    return { ext: f.ext, contentType: f.contentType, url, bytes: Number(r.bytes) || 0, tentativas };
  }
  return { ext: null, tentativas };
}

/** Sondagem real por HEAD — só cabeçalhos, nenhum corpo transferido. */
async function sondarHead(url) {
  try {
    const h = await fetch(url, { method: "HEAD" });
    if (!h.ok) return null;
    return { ok: true, contentType: h.headers.get("content-type"), bytes: Number(h.headers.get("content-length") ?? 0) };
  } catch {
    return null;
  }
}

/** Metadata da TCGdex. Devolve a base do logo (sem extensão) ou null. */
async function lerLogoTcgdex(tcgdexSetId) {
  const resposta = await fetch(TCGDEX_SET + encodeURIComponent(tcgdexSetId));
  if (!resposta.ok) throw new Error(`TCGdex respondeu ${resposta.status}`);
  const dados = await resposta.json();
  return dados?.logo ?? null;
}

/* ---------------------------------------------------------------
   Exceção inesperada → status + rastreabilidade do objeto.

   Função pura, exportada, usada pelo catch externo do laço. Se a
   exceção ocorreu na etapa do ponteiro e já havia objeto enviado, o
   caminho é devolvido em `objeto_pendente`: o objeto é preservado E
   rastreável. Órfão preservado que não aparece no relatório é
   equivalente a órfão perdido.
--------------------------------------------------------------- */
export function classificarExcecao({ etapa, erro, caminhoEnviado, bucket = BUCKET }) {
  const status = STATUS_POR_ETAPA[etapa] ?? "FAILED_UNEXPECTED";
  let detalhe = `exceção na etapa "${etapa}": ${erro?.message ?? String(erro)}`;
  let objeto_pendente = null;

  if (etapa === "ponteiro" && caminhoEnviado != null) {
    objeto_pendente = caminhoEnviado;
    detalhe +=
      ` — objeto NÃO removido (${caminhoEnviado}); reconciliação manual necessária:` +
      ` conferir logo_storage_path do Card Set e o bucket ${bucket}`;
  }

  return { status, detalhe, objeto_pendente };
}

async function main() {
  const faltando = REQUIRED_ENV.filter((k) => !process.env[k]);
  if (faltando.length) fail(`variáveis de ambiente ausentes: ${faltando.join(", ")}`);

  const [manifestA, manifestB] = await Promise.all([
    readFile(MANIFEST_A, "utf8").then(JSON.parse),
    readFile(MANIFEST_B, "utf8").then(JSON.parse),
  ]);

  const universo = montarUniverso(manifestA, manifestB);
  if (universo.erros.length) fail(`universo inconsistente:\n  ${universo.erros.join("\n  ")}`);
  if (!universo.total) fail("universo vazio.");

  console.log(`\n=== BOOTSTRAP CARD SET LOGOS — LOTES A + B ===`);
  console.log(`modo .......... ${MODE}`);
  console.log(`universo ...... ${universo.total} Card Sets (A: ${universo.porBatch.A ?? 0}, B: ${universo.porBatch.B ?? 0})`);
  console.log(`bucket ........ ${BUCKET} (privado, políticas existentes)`);
  console.log(`formatos ...... ${FORMATOS.map((f) => f.ext).join(" → ")}, até ${MAX_LOGO_BYTES} bytes`);

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

  const expansionIds = [...new Set(universo.entradas.map((s) => s.expansion_id))];
  const { data: existentes, error: qErr } = await supabase
    .from("card_set")
    .select("id, expansion_id, code, name, set_type, release_date, base_set_size, total_set_size, logo_storage_path")
    .in("expansion_id", expansionIds);
  if (qErr) fail(`leitura de card_set falhou: ${qErr.message}`);

  const porChave = new Map(existentes.map((r) => [`${r.expansion_id}|${r.code}`, r]));
  console.log(`estado atual .. ${existentes.length} Card Sets nas ${expansionIds.length} Expansions envolvidas\n`);

  const resultados = [];

  for (const s of universo.entradas) {
    const linha = {
      batch: s.batch,
      tcgdex_set_id: s.tcgdex_set_id,
      expansion_code: s.expansion_code,
      code: s.code,
      card_set_id: null,
      formato: null,
      status: null,
      detalhe: "",
      logo_storage_path: null,
      objeto_pendente: null,
    };

    // Etapa corrente — usada para classificar exceções de forma coerente.
    let etapa = "localizacao";

    // Caminho do objeto efetivamente enviado ao bucket. Declarado FORA do
    // try porque o catch externo precisa dele: se uma exceção inesperada
    // ocorrer depois do upload, o objeto existe e tem de aparecer em
    // "objetos pendentes" — órfão preservado só serve se for rastreável.
    let caminhoEnviado = null;

    try {
      const existente = porChave.get(`${s.expansion_id}|${s.code}`);
      const avaliacao = avaliarCardSet(s, existente);
      if (existente) linha.card_set_id = existente.id;

      if (avaliacao.status !== "PROSSEGUIR") {
        linha.status = avaliacao.status;
        linha.detalhe = avaliacao.detalhe;
        linha.logo_storage_path = avaliacao.logo_storage_path ?? null;
        resultados.push(linha);
        continue;
      }

      // Metadata da TCGdex.
      etapa = "metadata";
      let logoBase;
      try {
        logoBase = await lerLogoTcgdex(s.tcgdex_set_id);
      } catch (e) {
        linha.status = "FAILED_METADATA";
        linha.detalhe = `metadata falhou: ${e.message}`;
        resultados.push(linha);
        continue;
      }
      if (!logoBase) {
        linha.status = "NO_LOGO_AVAILABLE";
        linha.detalhe = "TCGdex não expõe logo para este Set (condição normal)";
        resultados.push(linha);
        continue;
      }

      // Resolução de formato: WEBP → PNG.
      etapa = "formato";
      const escolha = await escolherFormato(logoBase, sondarHead);
      if (!escolha.ext) {
        linha.status = "FAILED_ASSET_UNAVAILABLE";
        linha.detalhe = `há logo na metadata mas nenhum formato serve — ${escolha.tentativas.join("; ")}`;
        resultados.push(linha);
        continue;
      }
      linha.formato = escolha.ext;

      if (!APPLY) {
        linha.status = "READY";
        linha.detalhe =
          `seria enviado (${escolha.contentType}, ${escolha.bytes || "?"} bytes)` +
          (escolha.ext === "png" ? " — fallback PNG, WEBP indisponível" : "");
        resultados.push(linha);
        continue;
      }

      // APPLY — download.
      etapa = "download";
      const resposta = await fetch(escolha.url);
      if (!resposta.ok) {
        linha.status = "FAILED_DOWNLOAD";
        linha.detalhe = `HTTP ${resposta.status} em ${escolha.url}`;
        resultados.push(linha);
        continue;
      }
      etapa = "validacao";
      const tipo = resposta.headers.get("content-type");
      if (!contentTypeCompativel(tipo, escolha.contentType)) {
        linha.status = "FAILED_VALIDATION";
        linha.detalhe = `Content-Type "${tipo}" incompatível com ${escolha.contentType}`;
        resultados.push(linha);
        continue;
      }
      const bytes = new Uint8Array(await resposta.arrayBuffer());
      if (bytes.byteLength === 0) {
        linha.status = "FAILED_VALIDATION";
        linha.detalhe = "corpo vazio";
        resultados.push(linha);
        continue;
      }
      if (bytes.byteLength > MAX_LOGO_BYTES) {
        linha.status = "FAILED_VALIDATION";
        linha.detalhe = `${bytes.byteLength} bytes acima do teto de ${MAX_LOGO_BYTES}`;
        resultados.push(linha);
        continue;
      }

      // Upload — mesmo padrão de caminho do CardSetLogoUploader.
      etapa = "upload";
      caminhoEnviado = `${existente.id}/${crypto.randomUUID()}.${escolha.ext}`;
      const { error: uploadErr } = await supabase.storage
        .from(BUCKET)
        .upload(caminhoEnviado, bytes, { contentType: escolha.contentType, upsert: false });
      if (uploadErr) {
        linha.status = "FAILED_UPLOAD";
        linha.detalhe = uploadErr.message;
        resultados.push(linha);
        continue;
      }

      // Só depois do upload confirmado, grava o ponteiro relativo. A partir
      // daqui o objeto JÁ existe no bucket: nada é removido sem confirmar
      // antes o estado real do ponteiro.
      etapa = "ponteiro";
      const { error: rpcErr } = await supabase.rpc("admin_set_card_set_logo", {
        p_card_set_id: existente.id,
        p_logo_storage_path: caminhoEnviado,
      });
      if (rpcErr) {
        const desfecho = await resolverPonteiroAmbiguo({
          caminho: caminhoEnviado,
          mensagemRpc: rpcErr.message,
          relerPonteiro: async () => {
            const { data, error } = await supabase
              .from("card_set")
              .select("logo_storage_path")
              .eq("id", existente.id)
              .maybeSingle();
            if (error) return { erro: error.message };
            if (!data) return { erro: "Card Set não encontrado na releitura" };
            return { valor: data.logo_storage_path ?? null };
          },
          removerObjeto: async () => {
            const { error } = await supabase.storage.from(BUCKET).remove([caminhoEnviado]);
            return error ? error.message : null;
          },
        });
        linha.status = desfecho.status;
        linha.detalhe = desfecho.detalhe;
        linha.logo_storage_path = desfecho.logo_storage_path;
        linha.objeto_pendente = desfecho.objeto_pendente;
        resultados.push(linha);
        continue;
      }

      linha.status = "UPLOADED";
      linha.logo_storage_path = caminhoEnviado;
      linha.detalhe = `${bytes.byteLength} bytes`;
      resultados.push(linha);
    } catch (e) {
      // Logo é enriquecimento editorial: falha isolada nunca vira rollback
      // de Card Set nem interrompe o lote. A classificação segue a etapa em
      // que a exceção ocorreu — nunca um rótulo genérico.
      const desfecho = classificarExcecao({ etapa, erro: e, caminhoEnviado });
      linha.status = desfecho.status;
      linha.detalhe = desfecho.detalhe;
      linha.objeto_pendente = desfecho.objeto_pendente;
      resultados.push(linha);
    }
  }

  const resumo = resultados.reduce((a, r) => ((a[r.status] = (a[r.status] || 0) + 1), a), {});
  console.log("=== RESUMO ===");
  for (const [k, v] of Object.entries(resumo)) console.log(`  ${k.padEnd(26)} ${v}`);

  const porBatch = {};
  for (const r of resultados) {
    porBatch[r.batch] ??= {};
    porBatch[r.batch][r.status] = (porBatch[r.batch][r.status] || 0) + 1;
  }
  console.log("\n=== POR LOTE ===");
  for (const [b, contagens] of Object.entries(porBatch)) {
    console.log(`  Lote ${b}: ${Object.entries(contagens).map(([k, v]) => `${k}=${v}`).join(", ")}`);
  }

  const porFormato = resultados.reduce((a, r) => (r.formato ? ((a[r.formato] = (a[r.formato] || 0) + 1), a) : a), {});
  if (Object.keys(porFormato).length) {
    console.log("\n=== POR FORMATO ===");
    for (const [k, v] of Object.entries(porFormato)) console.log(`  ${k.padEnd(26)} ${v}`);
    const fallback = resultados.filter((r) => r.formato === "png");
    if (fallback.length) {
      console.log(`  fallback PNG: ${fallback.map((r) => r.tcgdex_set_id).join(", ")}`);
    }
  }

  const problemas = resultados.filter((r) => r.status.startsWith("FAILED_") || r.status === "CONFLICT" || r.status === "SET_NOT_FOUND");
  if (problemas.length) {
    console.log("\n=== LINHAS QUE EXIGEM ATENÇÃO (reexecutáveis) ===");
    for (const p of problemas) console.log(`  [${p.batch}] ${p.tcgdex_set_id} (${p.code}): ${p.status} — ${p.detalhe}`);
  }

  // Objetos enviados que ficaram em estado indeterminado. Nunca são
  // removidos automaticamente — órfão rastreável é preferível a ponteiro
  // apontando para arquivo removido.
  const pendentes = resultados.filter((r) => r.objeto_pendente);
  if (pendentes.length) {
    console.log("\n=== OBJETOS PENDENTES DE RECONCILIAÇÃO MANUAL ===");
    console.log(`  bucket: ${BUCKET}`);
    for (const p of pendentes) {
      console.log(`  [${p.batch}] ${p.tcgdex_set_id} (${p.code}) card_set_id=${p.card_set_id} → ${p.objeto_pendente}`);
    }
  }

  await mkdir(OUT_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const baseName = join(OUT_DIR, `bootstrap-logos-${MODE.toLowerCase()}-${stamp}`);

  await writeFile(
    `${baseName}.json`,
    JSON.stringify(
      {
        modo: MODE,
        executado_em: new Date().toISOString(),
        universo: universo.porBatch,
        resumo,
        por_lote: porBatch,
        por_formato: porFormato,
        objetos_pendentes: pendentes.map((p) => ({
          batch: p.batch,
          tcgdex_set_id: p.tcgdex_set_id,
          code: p.code,
          card_set_id: p.card_set_id,
          bucket: BUCKET,
          objeto: p.objeto_pendente,
        })),
        resultados,
      },
      null,
      2,
    ),
    "utf8",
  );

  const csv = [
    "batch,tcgdex_set_id,expansion_code,code,card_set_id,formato,status,logo_storage_path,objeto_pendente,detalhe",
    ...resultados.map((r) =>
      [
        r.batch,
        r.tcgdex_set_id,
        r.expansion_code,
        r.code,
        r.card_set_id ?? "",
        r.formato ?? "",
        r.status,
        r.logo_storage_path ?? "",
        r.objeto_pendente ?? "",
        `"${String(r.detalhe).replace(/"/g, '""')}"`,
      ].join(","),
    ),
  ].join("\n");
  await writeFile(`${baseName}.csv`, csv, "utf8");

  console.log(`\nrelatórios: ${baseName}.json / .csv`);

  await supabase.auth.signOut();

  if (MODE === "APPLY" && problemas.length) process.exit(2);
}

// Só executa quando invocado diretamente. Importar este módulo (para
// exercitar as funções puras isoladamente) não dispara o processo.
const invocadoDiretamente = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invocadoDiretamente) {
  main().catch((e) => fail(e?.stack ?? String(e)));
}
