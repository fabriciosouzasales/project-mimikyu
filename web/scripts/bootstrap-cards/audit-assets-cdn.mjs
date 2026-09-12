/*
===============================================================================
ASSETS-FINAL-CDN-AUDIT-01 — diagnostico READ-ONLY
Arquivo....: web/scripts/bootstrap-cards/audit-assets-cdn.mjs
Objetivo...: provar, carta a carta, se os candidatos `<idioma>_importable_gap`
             sao de fato baixaveis da CDN da TCGdex — ou se sao source debt.

ESCOPO PADRAO: --expansion XY --idioma pt-BR  (os 1.520 candidatos)

O QUE ESTE SCRIPT NAO FAZ (garantias, nao intencoes)
  - NAO escreve no banco: so usa SELECT via listarCardSetsPokemon() e
    lerCardsComAssets(), ambas leituras puras importadas do bootstrap;
  - NAO cria asset_import_run: nao chama admin_start_asset_import_run;
  - NAO invoca Edge Function: nao ha fetch para /functions/v1/*;
  - NAO escreve no Storage: nao ha upload;
  - NAO altera logica produtiva: importa funcoes, nao as modifica;
  - NAO baixa binario: usa HEAD (cai para GET+cancel so se a CDN recusar HEAD).

POR QUE IMPORTA DO BOOTSTRAP EM VEZ DE REIMPLEMENTAR
  O universo auditado precisa ser IDENTICO ao que o bootstrap classifica como
  importable_gap. Reimplementar a leitura de Cards/assets ou a chave de
  comparacao abriria espaco para divergencia silenciosa — exatamente a classe
  de bug que esta rodada quer fechar. Aqui, `chaveFonte`,
  `indexarFontePorChave`, `classificarLacuna` e `disponibilidadeNaFonte` sao
  as MESMAS funcoes usadas no DRY_RUN.

CARGA NA FONTE
  - 1 GET por Card Set por idioma (reusa `disponibilidadeNaFonte`, que ja traz
    o snapshot com a URL-base de cada carta — zero GET extra);
  - 1 HEAD por candidato em high.webp; + 1 HEAD em low.webp SOMENTE se high
    devolver 404 (mesma regra do IMAGE-QUALITY-FALLBACK-01 da Edge);
  - concorrencia default 4, pausa default 120ms, ate 2 tentativas e SOMENTE
    para erro transitorio (429/5xx/rede/timeout).

Ambiente (obrigatorio, somente por environment):
  NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_ANON_KEY,
  MMKYU_ADMIN_EMAIL, MMKYU_ADMIN_PASSWORD

Uso:
  node web/scripts/bootstrap-cards/audit-assets-cdn.mjs
  node web/scripts/bootstrap-cards/audit-assets-cdn.mjs --expansion XY --idioma pt-BR
  node web/scripts/bootstrap-cards/audit-assets-cdn.mjs --only XY1,XY2 --concorrencia 2
===============================================================================
*/

import { createClient } from "@supabase/supabase-js";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

import {
  listarCardSetsPokemon,
  lerCardsComAssets,
  disponibilidadeNaFonte,
  classificarLacuna,
  chaveFonte,
  filtrarUniverso,
  CLASSE_LACUNA,
  FASES_IDIOMA,
} from "./run-bootstrap-assets.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(__dirname, "out");

const ORIGEM_CDN = "https://assets.tcgdex.net";
const TIMEOUT_MS = 15_000;
const MAX_TENTATIVAS = 2;

// ---------------------------------------------------------------------------
// Resultado por candidato — vocabulario fechado
// ---------------------------------------------------------------------------
export const RESULTADO = {
  HIGH_AVAILABLE: "high_available",
  LOW_ONLY_AVAILABLE: "low_only_available",
  UNAVAILABLE_404_404: "unavailable_404_404",
  TRANSIENT_ERROR: "transient_error",
};

/**
 * SOURCE-404-CDN-PROOF-04 — de onde veio a URL-base do candidato.
 *   SNAPSHOT              -> listagem /{lang}/sets/{id} respondeu 2xx;
 *   CARD_EXTERNAL_REFERENCE -> metadata deu 404, mas a identidade TCGdex ja
 *                            estava persistida em card_external_reference
 *                            (image_source_url), por Card e por idioma.
 */
export const ORIGEM_IDENTIDADE = {
  SNAPSHOT: "SNAPSHOT",
  CARD_EXTERNAL_REFERENCE: "CARD_EXTERNAL_REFERENCE",
};

export function parseArgs(argv) {
  const a = {
    expansion: ["XY"],
    only: null,
    idioma: "pt-BR",
    concorrencia: 4,
    pausaMs: 120,
    limit: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const k = argv[i];
    if (k === "--expansion") a.expansion = String(argv[++i] ?? "").split(",").map((s) => s.trim().toUpperCase()).filter(Boolean);
    else if (k === "--only") a.only = String(argv[++i] ?? "").split(",").map((s) => s.trim().toUpperCase()).filter(Boolean);
    else if (k === "--idioma") a.idioma = String(argv[++i] ?? "").trim();
    else if (k === "--concorrencia") a.concorrencia = Math.max(1, Math.min(8, Number(argv[++i]) || 4));
    else if (k === "--pausa-ms") a.pausaMs = Math.max(0, Number(argv[++i]) || 0);
    else if (k === "--limit") a.limit = Number(argv[++i]);
  }
  if (a.only) a.expansion = null;
  return a;
}

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

/** Fase de idioma correspondente ao codigo do banco (pt-BR / en). */
export function faseDoIdioma(idiomaDb) {
  const f = FASES_IDIOMA.find((x) => x.db === idiomaDb);
  if (!f) throw new Error(`IDIOMA_INVALIDO: "${idiomaDb}". Aceitos: ${FASES_IDIOMA.map((x) => x.db).join(", ")}`);
  return f;
}

/**
 * Guard de origem — a URL-base vem da fonte, mas nunca e seguida sem checagem.
 * Mesma regra do validarSetSnapshot da Edge: origin exata, https, sem
 * credenciais embutidas.
 */
export function urlDeOrigemAutorizada(valor) {
  let u;
  try { u = new URL(String(valor)); } catch { return false; }
  return u.protocol === "https:" &&
    u.hostname === "assets.tcgdex.net" &&
    u.origin === ORIGEM_CDN &&
    u.username === "" &&
    u.password === "";
}

/**
 * Classifica UMA resposta HTTP em: disponivel / ausente / nao conclusivo.
 * Funcao pura — testavel sem rede.
 *
 * CORRECTION-01 — 3xx e NAO_CONCLUSIVO, explicitamente. Com
 * `redirect: "manual"` (ver sondarUrl) um redirect chega ate aqui como status
 * real. Ele NUNCA pode virar "AUSENTE" nem "DISPONIVEL": nao sabemos o que ha
 * no destino, e seguir um Location cross-origin sairia do unico host
 * autorizado. Fail closed.
 */
export function classificarStatusCdn(status) {
  if (status >= 200 && status < 300) return "DISPONIVEL";
  if (status >= 300 && status < 400) return "NAO_CONCLUSIVO";
  if (status === 404) return "AUSENTE";
  return "NAO_CONCLUSIVO";
}

export function ehRetentavel(status) {
  return status === 429 || (status >= 500 && status <= 599);
}

/** CORRECTION-01 — um redirect nao e erro transitorio; nunca retentar. */
export function ehRedirect(status) {
  return typeof status === "number" && status >= 300 && status < 400;
}

/**
 * HEAD com timeout. Cai para GET+cancel apenas se a CDN recusar o metodo
 * (405/501) — assim nunca interpretamos "metodo nao suportado" como 404.
 *
 * CORRECTION-01 — REDIRECT FAIL-CLOSED: `redirect: "manual"`.
 * Validar a URL inicial com urlDeOrigemAutorizada() nao basta se o `fetch`
 * seguir redirects sozinho: um 302 para outro host faria a sonda medir um
 * recurso fora de assets.tcgdex.net e reportar 200 como se fosse a carta.
 * Com "manual", o 3xx chega cru, e classificado como NAO_CONCLUSIVO
 * (-> transient_error) e o `Location` entra no relatorio como evidencia.
 * Seguir redirect same-origin NAO foi implementado de proposito — seria
 * ampliacao de escopo; hoje qualquer redirect e inconclusivo.
 */
async function sondarUrl(url, fetchImpl = fetch) {
  const tentar = async (metodo) => {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
    try {
      const r = await fetchImpl(url, { method: metodo, signal: ctrl.signal, redirect: "manual" });
      if (metodo === "GET") { try { await r.body?.cancel(); } catch { /* noop */ } }
      if (ehRedirect(r.status)) {
        const destino = r.headers?.get?.("location") ?? "(sem Location)";
        return { status: r.status, erro: `REDIRECT_NAO_SEGUIDO -> ${destino}` };
      }
      return { status: r.status, erro: null };
    } catch (e) {
      const timeout = e?.name === "AbortError" || e?.name === "TimeoutError";
      return { status: null, erro: timeout ? "TIMEOUT" : `NETWORK: ${e?.message ?? String(e)}` };
    } finally {
      clearTimeout(t);
    }
  };

  for (let tentativa = 1; tentativa <= MAX_TENTATIVAS; tentativa += 1) {
    let r = await tentar("HEAD");
    if (r.status === 405 || r.status === 501) r = await tentar("GET");

    if (r.status === null) {
      if (tentativa < MAX_TENTATIVAS) { await dormir(1000 * tentativa); continue; }
      return r;
    }
    if (ehRetentavel(r.status) && tentativa < MAX_TENTATIVAS) {
      await dormir(1000 * tentativa);
      continue;
    }
    return r;
  }
  return { status: null, erro: "RETRY_ESGOTADO" };
}

/**
 * high primeiro; low SOMENTE apos 404 comprovado em high — espelha
 * IMAGE-QUALITY-FALLBACK-01. Devolve o vocabulario de RESULTADO.
 */
export async function sondarCandidato(baseImageUrl, sondar = sondarUrl) {
  // CORRECTION-01: status E erro juntos no detalhe — sem isso um
  // REDIRECT_NAO_SEGUIDO apareceria no relatorio so como "high 302",
  // escondendo o destino que motivou a recusa.
  const descreve = (r) => (r.erro ? `${r.status ?? ""} ${r.erro}`.trim() : String(r.status));

  if (!urlDeOrigemAutorizada(baseImageUrl)) {
    return { resultado: RESULTADO.TRANSIENT_ERROR, detalhe: `ORIGEM_NAO_AUTORIZADA: ${baseImageUrl}`, high: null, low: null };
  }

  const high = await sondar(`${baseImageUrl}/high.webp`);
  const cHigh = high.status === null ? "NAO_CONCLUSIVO" : classificarStatusCdn(high.status);

  if (cHigh === "DISPONIVEL") {
    return { resultado: RESULTADO.HIGH_AVAILABLE, detalhe: null, high: high.status, low: null };
  }
  if (cHigh === "NAO_CONCLUSIVO") {
    return {
      resultado: RESULTADO.TRANSIENT_ERROR,
      detalhe: `high ${descreve(high)}`,
      high: high.status, low: null,
    };
  }

  // high = 404 comprovado -> unica porta para consultar low.
  const low = await sondar(`${baseImageUrl}/low.webp`);
  const cLow = low.status === null ? "NAO_CONCLUSIVO" : classificarStatusCdn(low.status);

  if (cLow === "DISPONIVEL") return { resultado: RESULTADO.LOW_ONLY_AVAILABLE, detalhe: null, high: 404, low: low.status };
  if (cLow === "AUSENTE") return { resultado: RESULTADO.UNAVAILABLE_404_404, detalhe: null, high: 404, low: 404 };
  return {
    resultado: RESULTADO.TRANSIENT_ERROR,
    detalhe: `high 404 / low ${descreve(low)}`,
    high: 404, low: low.status,
  };
}

/**
 * VERDICT-CORRECTION-03 — veredito como funcao PURA, para ser testavel sem
 * rede/banco.
 *
 * A regra que mudou: fonte ilegivel deixou de bloquear POR SI. O que bloqueia
 * e fonte ilegivel que esconde UNIVERSO AUDITAVEL — isto e, Set em que existe
 * ao menos um Card sem asset no idioma (`cards_sem_asset > 0`). Um Set com
 * cobertura completa nao pode gerar candidato sob nenhum resultado de fonte,
 * entao sua falha e ruido, nao risco: vira warning.
 *
 * Precedencia deliberada:
 *   1. particao/identidade quebrada -> INVALIDO (relatorio nao utilizavel);
 *   2. transient_error > 0 OU fonte ilegivel bloqueante -> INCONCLUSIVO;
 *   3. accessible_not_imported === 0 -> PASS WITH KNOWN SOURCE DEBT;
 *   4. resto -> FAIL.
 */
export function decidirVeredito({
  total_candidates,
  high_available,
  low_only_available,
  unavailable_404_404,
  transient_error,
  accessible_not_imported,
  setsFonteIndisponivel = [],
  setsSemSnapshot = [],
}) {
  const particaoOk =
    high_available + low_only_available + unavailable_404_404 + transient_error === total_candidates;
  const identidadeOk = accessible_not_imported === high_available + low_only_available;

  // VERDICT-CORRECTION-03B — as duas origens compartilham a MAQUINA de
  // particao, mas NAO o criterio. Sao fenomenos diferentes:
  //
  // FONTE_INDISPONIVEL — o discriminador e o STATUS HTTP, nao cards_sem_asset.
  //   HTTP 404 na listagem `/{lang}/sets/{id}` e resposta DETERMINISTICA: a
  //   fonte afirma que o Set nao existe naquele idioma. Isso e KNOWN SOURCE
  //   DEBT, e os Cards desse Set ficam FORA do universo de candidatos por
  //   construcao (classificarLacuna devolve FONTE_INDISPONIVEL, nunca
  //   IMPORTABLE_GAP). Exigir `cards_sem_asset === 0` aqui seria incoerente:
  //   XYP tem 216 Cards sem asset pt-BR PRECISAMENTE porque o /pt e 404 —
  //   exigir zero faria todo Set 404 bloquear, tornando a regra inocua.
  //   Qualquer outro desfecho (timeout, rede, 429, 5xx, corpo nao-JSON,
  //   colisao de chave, retry esgotado) e INCONCLUSIVO: nao sabemos o que a
  //   fonte diria.
  //
  // SNAPSHOT_INVALIDO — aqui a fonte RESPONDEU 2xx; o que falhou foi o parse
  //   do payload. Nao ha veredito da fonte para herdar, entao o criterio e o
  //   universo: so nao bloqueia quem PROVOU cobertura completa
  //   (cards_sem_asset numerico igual a zero). Ausencia/NaN/tipo invalido
  //   bloqueia — fail closed.
  // SOURCE-404-CDN-PROOF-04 — metadata 404 so e NAO bloqueante quando nao
  // restou nada por provar: ou o Set nao tem Card faltante, ou TODOS os
  // faltantes foram enviados a sondagem da CDN (e o veredito deles vive nos
  // contadores de candidato). Qualquer Card sem identidade autoritativa
  // bloqueia — nao ha URL confiavel para construir, e adivinhar e proibido.
  const fonte404Deterministico = (s) =>
    typeof s.http === "number" && s.http === 404 &&
    typeof s.cards_sem_identidade === "number" && s.cards_sem_identidade === 0;
  const provouSemUniverso = (s) => typeof s.cards_sem_asset === "number" && s.cards_sem_asset === 0;

  const particionar = (lista, origem, ehNaoBloqueante) => ({
    bloqueantes: lista.filter((s) => !ehNaoBloqueante(s)).map((s) => ({ ...s, origem })),
    naoBloqueantes: lista.filter(ehNaoBloqueante).map((s) => ({ ...s, origem })),
  });

  // Listas distintas preservadas para diagnostico; unificadas so no gate.
  const fonteIlegivel = particionar(setsFonteIndisponivel, "FONTE_ILEGIVEL", fonte404Deterministico);
  const semSnapshot = particionar(setsSemSnapshot, "SNAPSHOT_INVALIDO", provouSemUniverso);
  const bloqueantes = [...fonteIlegivel.bloqueantes, ...semSnapshot.bloqueantes];
  const naoBloqueantes = [...fonteIlegivel.naoBloqueantes, ...semSnapshot.naoBloqueantes];

  const descreverSet = (s) => {
    const universo = Number.isFinite(s.cards_sem_asset) ? s.cards_sem_asset : "?";
    if (s.origem !== "FONTE_ILEGIVEL") return `${s.set}[SNAPSHOT_INVALIDO](${universo})`;
    const semId = Number.isFinite(s.cards_sem_identidade) ? s.cards_sem_identidade : "?";
    return s.http === 404
      ? `${s.set}[METADATA_404,sem_identidade=${semId}](${universo})`
      : `${s.set}[FONTE_ILEGIVEL,http=${s.http ?? "-"}](${universo})`;
  };

  let veredito;
  if (!particaoOk || !identidadeOk) {
    veredito = "INVALIDO — particao das classes nao fecha; relatorio NAO utilizavel";
  } else if (transient_error > 0 || bloqueantes.length > 0) {
    const motivos = [];
    if (transient_error > 0) motivos.push(`transient_error=${transient_error}`);
    if (bloqueantes.length > 0) {
      motivos.push(`universo nao classificavel em ${bloqueantes.length} Set(s): ${bloqueantes.map(descreverSet).join(", ")}`);
    }
    veredito = `INCONCLUSIVO — ${motivos.join("; ")}; reexecutar antes de concluir`;
  } else if (accessible_not_imported === 0) {
    const debtFora = naoBloqueantes.length > 0
      ? ` + ${naoBloqueantes.length} Set(s) de source debt deterministico FORA do universo auditado`
      : "";
    veredito = `PASS WITH KNOWN SOURCE DEBT — todo gap remanescente e 404 em high E low${debtFora}`;
  } else {
    veredito = `FAIL — ${accessible_not_imported} Card(s) baixaveis da CDN seguem sem Asset`;
  }

  return { veredito, particaoOk, identidadeOk, bloqueantes, naoBloqueantes, fonteIlegivel, semSnapshot };
}

/**
 * REPORTING-CORRECTION-06 — classificacao de RELATORIO, nao de decisao.
 *
 * Defeito observado no smoke real de XYP/pt-BR: o console imprimia
 *
 *   "fonte nao deterministica (timeout/rede/429/5xx/parse): 1"
 *
 * para um Set cuja metadata respondeu HTTP 404 — um desfecho perfeitamente
 * DETERMINISTICO. O bloqueio de XYP nao veio de incerteza sobre a fonte; veio
 * de `identity_insufficient = 216`: 216 Cards faltantes em pt-BR sem nenhum
 * `image_source_url` pt-BR persistido, logo sem URL confiavel para sondar na
 * CDN. Sao fenomenos diferentes, com acoes diferentes:
 *
 *   METADATA_404_IDENTIDADE_INSUFICIENTE -> acao: reconciliar identidade
 *        (SET-ID / ASSET-PATH). Reexecutar a auditoria NAO muda nada.
 *   FONTE_NAO_DETERMINISTICA             -> acao: reexecutar. A fonte pode
 *        responder outra coisa da proxima vez.
 *   SNAPSHOT_INVALIDO                    -> acao: investigar o payload 2xx.
 *
 * Rotular o primeiro como o segundo induziria exatamente a decisao errada:
 * "e so rodar de novo".
 *
 * Esta funcao NAO participa do gate. `decidirVeredito` permanece byte-
 * identico; a particao aqui e derivada da lista que ele ja devolve.
 *
 * Um bloqueante de origem FONTE_ILEGIVEL com http === 404 so pode estar
 * bloqueando porque `fonte404Deterministico` rejeitou o Set, e a UNICA razao
 * possivel para isso, com http === 404, e `cards_sem_identidade` diferente de
 * zero (ausente, NaN, string ou > 0). Ou seja: o rotulo e verdadeiro por
 * construcao, nao por coincidencia.
 */
export const CLASSE_BLOQUEIO = {
  METADATA_404_IDENTIDADE_INSUFICIENTE: "METADATA_404_IDENTIDADE_INSUFICIENTE",
  FONTE_NAO_DETERMINISTICA: "FONTE_NAO_DETERMINISTICA",
  SNAPSHOT_INVALIDO: "SNAPSHOT_INVALIDO",
};

export function classificarBloqueante(s) {
  if (!s || typeof s !== "object") return CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA;
  if (s.origem === "SNAPSHOT_INVALIDO") return CLASSE_BLOQUEIO.SNAPSHOT_INVALIDO;
  return s.http === 404
    ? CLASSE_BLOQUEIO.METADATA_404_IDENTIDADE_INSUFICIENTE
    : CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA;
}

/** Particiona a lista de bloqueantes nas 3 classes, preservando a ordem. */
export function particionarBloqueantesParaRelatorio(bloqueantes = []) {
  const saida = {
    [CLASSE_BLOQUEIO.METADATA_404_IDENTIDADE_INSUFICIENTE]: [],
    [CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA]: [],
    [CLASSE_BLOQUEIO.SNAPSHOT_INVALIDO]: [],
  };
  for (const s of bloqueantes) saida[classificarBloqueante(s)].push(s);
  return saida;
}

/**
 * SOURCE-404-CDN-PROOF-04 — identidade TCGdex AUTORITATIVA ja persistida.
 *
 * `card_external_reference.image_source_url` guarda a URL-base da carta na CDN,
 * por Card e por idioma, gravada quando a fonte ainda era legivel. E a unica
 * identidade confiavel para um Set cuja metadata hoje da 404.
 *
 * NAO derivamos URL a partir de collector_number, nem trocamos o segmento de
 * idioma de uma URL de outro idioma: a rota da CDN inclui o slug da serie
 * (`/pt/xy/xyp/...`), que nao e dedutivel do codigo do Set. Sem
 * image_source_url no idioma alvo, o veredito e IDENTITY_INSUFFICIENT.
 *
 * EXTERNAL-REFERENCE-READ-RPC-05 — o SELECT direto NAO e possivel e nao deve
 * ser tornado possivel. `card_external_reference` tem RLS=true, zero policy e
 * SELECT apenas para postgres/service_role; o smoke de XYP abortou com
 * "permission denied for table card_external_reference". Essa fronteira esta
 * correta. A leitura passa pela RPC READ-ONLY/ADMIN-ONLY
 * `admin_list_card_external_image_sources` (migration 6127), que devolve
 * apenas card_id / image_source_url / external_card_id.
 *
 * A RPC NAO devolve external_set_id de proposito: sem ele, este auditor fica
 * fisicamente incapaz de reconstruir o path da CDN a partir do codigo do Set —
 * o que a evidencia dos subsets SWSH (swsh4.5sv -> pasta swsh4.5) prova ser
 * uma deducao falsa.
 *
 * Leitura pura, em lotes de 200 (a RPC tem teto proprio de 500 e falha alto
 * acima disso, em vez de truncar em silencio).
 */
export const RPC_URLS_AUTORITATIVAS = "admin_list_card_external_image_sources";
export const TAMANHO_LOTE_IDENTIDADE = 200;

export async function lerUrlsAutoritativas(supabase, cardIds, languageCode) {
  const porCard = new Map();
  for (let i = 0; i < cardIds.length; i += TAMANHO_LOTE_IDENTIDADE) {
    const fatia = cardIds.slice(i, i + TAMANHO_LOTE_IDENTIDADE);
    const { data, error } = await supabase.rpc(RPC_URLS_AUTORITATIVAS, {
      p_card_ids: fatia,
      p_language_code: languageCode,
    });
    if (error) throw new Error(`FALHA_LER_EXTERNAL_REFERENCE: ${error.message}`);
    for (const r of data ?? []) {
      if (!r.image_source_url) continue;
      porCard.set(r.card_id, { url: r.image_source_url, external_card_id: r.external_card_id });
    }
  }
  return porCard;
}

/** Pool de concorrencia fixa, sem dependencia externa. */
async function emLotes(itens, concorrencia, pausaMs, tarefa) {
  const saida = new Array(itens.length);
  let proximo = 0;
  const trabalhador = async () => {
    for (;;) {
      const i = proximo++;
      if (i >= itens.length) return;
      saida[i] = await tarefa(itens[i], i);
      if (pausaMs > 0) await dormir(pausaMs);
    }
  };
  await Promise.all(Array.from({ length: concorrencia }, trabalhador));
  return saida;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

export async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const fase = faseDoIdioma(args.idioma);

  for (const k of ["NEXT_PUBLIC_SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_ANON_KEY", "MMKYU_ADMIN_EMAIL", "MMKYU_ADMIN_PASSWORD"]) {
    if (!process.env[k]) throw new Error(`ENV_AUSENTE: ${k}`);
  }

  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { error: erroLogin } = await supabase.auth.signInWithPassword({
    email: process.env.MMKYU_ADMIN_EMAIL,
    password: process.env.MMKYU_ADMIN_PASSWORD,
  });
  if (erroLogin) throw new Error(`FALHA_LOGIN: ${erroLogin.message}`);

  const todos = await listarCardSetsPokemon(supabase);
  const universo = filtrarUniverso(todos, args);

  console.log(`[audit-cdn] READ-ONLY | idioma=${args.idioma} sets=${universo.length} concorrencia=${args.concorrencia}`);

  const candidatos = [];
  const setsSemSnapshot = [];
  const setsFonteIndisponivel = [];

  // ---- Fase 1: derivar os candidatos EXATAMENTE como o bootstrap faz -------
  for (const set of universo) {
    const cards = await lerCardsComAssets(supabase, set.card_set_id);
    if (cards.length === 0) continue;

    let fonte;
    try {
      fonte = await disponibilidadeNaFonte(set.external_set_id, fase.tcgdex);
    } catch (e) {
      fonte = { ok: false, http: null, mapa: new Map(), snapshot: null, erro: e instanceof Error ? e.message : String(e) };
    }

    if (!fonte.ok) {
      const faltantes = cards.filter((c) => !c.idiomas.has(fase.db));

      // SOURCE-404-CDN-PROOF-04 — metadata 404 NAO prova ausencia na CDN.
      // `api.tcgdex.net` e `assets.tcgdex.net` sao hosts distintos e ja
      // divergiram nesta fase (metadata inalcancavel da Edge; SM10 #226 com
      // high 404 e low 200). Entao um Set com metadata 404 e METADATA_SOURCE_404,
      // nao KNOWN SOURCE DEBT: cada Card faltante e auditado direto na CDN,
      // usando a identidade autoritativa ja persistida.
      if (fonte.http === 404 && faltantes.length > 0) {
        const urls = await lerUrlsAutoritativas(supabase, faltantes.map((c) => c.id), fase.db);
        let semIdentidade = 0;
        for (const card of faltantes) {
          const ident = urls.get(card.id);
          if (!ident) { semIdentidade += 1; continue; }
          candidatos.push({
            expansion_code: set.expansion_code,
            card_set_code: set.card_set_code,
            external_set_id: set.external_set_id,
            card_id: card.id,
            collector_number: card.collector_number,
            chave: chaveFonte(card.collector_number),
            base_image_url: ident.url,
            external_card_id: ident.external_card_id,
            origem_identidade: ORIGEM_IDENTIDADE.CARD_EXTERNAL_REFERENCE,
          });
        }
        setsFonteIndisponivel.push({
          set: set.card_set_code,
          http: 404,
          erro: fonte.erro,
          cards_sem_asset: faltantes.length,
          cards_enviados_a_cdn: faltantes.length - semIdentidade,
          cards_sem_identidade: semIdentidade,
        });
        continue;
      }

      // Fonte ilegivel por desfecho NAO deterministico (timeout/rede/429/5xx/
      // parse/colisao) => nada a sondar, NADA inferido como ausente.
      //
      // VERDICT-CORRECTION-03 — o que decide se isso BLOQUEIA o veredito nao e
      // a falha da fonte em si, e sim se ela esconde universo auditavel.
      // `cards_sem_asset` e fato do BANCO, legivel mesmo com a fonte fora do ar:
      //   0  -> o Set nao pode conter candidato sob NENHUM resultado de fonte,
      //         logo a falha e irrelevante para accessible_not_imported;
      //   >0 -> a fonte poderia revelar IMPORTABLE_GAP que nao conseguimos
      //         medir -> bloqueia (INCONCLUSIVO).
      // Deliberadamente NAO usamos o `pt-BR_importable_gap` do DRY_RUN global
      // como criterio: seria confiar num artefato externo, de outro momento, e
      // gap=0 la tambem pode significar "fonte ilegivel la tambem". A contagem
      // no banco e autossuficiente e mais forte.
      setsFonteIndisponivel.push({
        set: set.card_set_code,
        http: fonte.http,
        erro: fonte.erro,
        cards_sem_asset: faltantes.length,
        cards_enviados_a_cdn: 0,
        cards_sem_identidade: null,
      });
      continue;
    }

    // URL-base por chave normalizada, a partir do snapshot ja obtido no GET.
    const urlPorChave = new Map();
    for (const c of fonte.snapshot?.cards ?? []) {
      if (c.image) urlPorChave.set(chaveFonte(c.localId), c.image);
    }
    // VERDICT-CORRECTION-03 — snapshot invalido tambem ganha a contagem de
    // universo afetado. Nao entra no gate: candidatos de um Set sem snapshot
    // ja caem em transient_error (SEM_URL_BASE_NO_SNAPSHOT), que bloqueia.
    // Registrado so para o leitor do relatorio nao precisar deduzir.
    if (!fonte.snapshot) {
      setsSemSnapshot.push({
        set: set.card_set_code,
        cards_sem_asset: cards.filter((c) => !c.idiomas.has(fase.db)).length,
      });
    }

    for (const card of cards) {
      const temNoBanco = card.idiomas.has(fase.db);
      const chave = chaveFonte(card.collector_number);
      const temNaFonte = fonte.mapa.get(chave) ?? false;
      const classe = classificarLacuna({ temNoBanco, temNaFonte, fonteOk: fonte.ok });
      if (classe !== CLASSE_LACUNA.IMPORTABLE_GAP) continue;

      candidatos.push({
        expansion_code: set.expansion_code,
        card_set_code: set.card_set_code,
        external_set_id: set.external_set_id,
        card_id: card.id,
        collector_number: card.collector_number,
        chave,
        base_image_url: urlPorChave.get(chave) ?? null,
        origem_identidade: ORIGEM_IDENTIDADE.SNAPSHOT,
      });
    }
  }

  console.log(`[audit-cdn] candidatos derivados = ${candidatos.length}`);

  // ---- Fase 2: sondar a CDN -----------------------------------------------
  const sondados = await emLotes(candidatos, args.concorrencia, args.pausaMs, async (c, i) => {
    if ((i + 1) % 100 === 0) console.log(`[audit-cdn] ${i + 1}/${candidatos.length}`);
    if (!c.base_image_url) {
      // fonte disse que a carta existe (mapa=true) mas o snapshot nao trouxe
      // URL utilizavel — inconclusivo, NUNCA "ausente".
      return { ...c, resultado: RESULTADO.TRANSIENT_ERROR, detalhe: "SEM_URL_BASE_NO_SNAPSHOT", high: null, low: null };
    }
    const r = await sondarCandidato(c.base_image_url);
    return { ...c, ...r };
  });

  // ---- Fase 3: contadores --------------------------------------------------
  const conta = (v) => sondados.filter((s) => s.resultado === v).length;
  const total_candidates = sondados.length;
  const high_available = conta(RESULTADO.HIGH_AVAILABLE);
  const low_only_available = conta(RESULTADO.LOW_ONLY_AVAILABLE);
  const unavailable_404_404 = conta(RESULTADO.UNAVAILABLE_404_404);
  const transient_error = conta(RESULTADO.TRANSIENT_ERROR);

  // Acessivel na CDN E ausente no banco = o que a correcao de Assets ainda deve.
  const acessiveis = sondados.filter(
    (s) => s.resultado === RESULTADO.HIGH_AVAILABLE || s.resultado === RESULTADO.LOW_ONLY_AVAILABLE,
  );
  const accessible_not_imported = acessiveis.length;

  // VERDICT-CORRECTION-03 — veredito centralizado na funcao pura.
  const { veredito, particaoOk, identidadeOk, bloqueantes, naoBloqueantes, fonteIlegivel, semSnapshot } =
    decidirVeredito({
      total_candidates,
      high_available,
      low_only_available,
      unavailable_404_404,
      transient_error,
      accessible_not_imported,
      setsFonteIndisponivel,
      setsSemSnapshot,
    });

  console.log("\n=== ASSETS-FINAL-CDN-AUDIT-01 ===");
  console.log(`idioma ....................... ${args.idioma}`);
  console.log(`total_candidates ............. ${total_candidates}`);
  console.log(`high_available ............... ${high_available}`);
  console.log(`low_only_available ........... ${low_only_available}`);
  console.log(`unavailable_404_404 .......... ${unavailable_404_404}`);
  console.log(`transient_error .............. ${transient_error}`);
  console.log(`accessible_not_imported ...... ${accessible_not_imported}`);

  // SOURCE-404-CDN-PROOF-04 — contadores da fatia metadata-404.
  const meta404 = setsFonteIndisponivel.filter((s) => s.http === 404);
  const identity_insufficient = meta404.reduce(
    (acc, s) => acc + (Number.isFinite(s.cards_sem_identidade) ? s.cards_sem_identidade : 0), 0);
  const meta404EnviadosCdn = meta404.reduce((acc, s) => acc + (s.cards_enviados_a_cdn ?? 0), 0);
  const porOrigem = (o) => sondados.filter((s) => s.origem_identidade === o).length;
  console.log(`  dos quais via metadata-404 ... ${meta404EnviadosCdn} sondados na CDN`);
  console.log(`identity_insufficient ........ ${identity_insufficient}`);
  console.log(`  candidatos por identidade .... snapshot=${porOrigem(ORIGEM_IDENTIDADE.SNAPSHOT)} external_ref=${porOrigem(ORIGEM_IDENTIDADE.CARD_EXTERNAL_REFERENCE)}`);

  if (acessiveis.length > 0) {
    console.log(`\n--- accessible_not_imported (${acessiveis.length}) ---`);
    for (const a of acessiveis) {
      console.log(`${a.card_set_code.padEnd(10)} #${String(a.collector_number).padEnd(6)} ${a.resultado.padEnd(20)} ${a.base_image_url}`);
    }
  }

  // VERDICT-CORRECTION-03A — gate unificado, listas separadas por origem.
  // REPORTING-CORRECTION-06 — a linha passa a expor `sem_identidade`, que e o
  // numero que explica o bloqueio de um Set metadata-404. Antes ele so existia
  // no JSON, e o leitor do console nao tinha como saber a causa real.
  const linhaSet = (s) => {
    const universo = Number.isFinite(s.cards_sem_asset) ? s.cards_sem_asset : "AUSENTE/INVALIDO";
    const semId = s.cards_sem_identidade === null || s.cards_sem_identidade === undefined
      ? null
      : (Number.isFinite(s.cards_sem_identidade) ? s.cards_sem_identidade : "AUSENTE/INVALIDO");
    const sufixo = semId === null ? "" : ` | sem identidade ${fase.db}: ${semId}`;
    // Rotulo permanece `s.origem`: linhaSet tambem serve o bloco WARNING, onde
    // um metadata-404 e NAO bloqueante (identidade completa) — chama-lo de
    // "IDENTIDADE INSUFICIENTE" ali seria falso. A classe de bloqueio e dada
    // pelo cabecalho da secao, nao pela linha.
    return `      ${s.set} [${s.origem}]: HTTP ${s.http ?? "-"} ${s.erro ?? ""}` +
      ` | cards sem asset ${fase.db}: ${universo}${sufixo}`;
  };

  // REPORTING-CORRECTION-06 — 3 classes visualmente separadas, cada uma com a
  // acao correspondente. Nao altera o gate; so lê a lista que ele devolveu.
  if (bloqueantes.length > 0) {
    const porClasse = particionarBloqueantesParaRelatorio(bloqueantes);
    const meta404 = porClasse[CLASSE_BLOQUEIO.METADATA_404_IDENTIDADE_INSUFICIENTE];
    const naoDet = porClasse[CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA];
    const semSnap = porClasse[CLASSE_BLOQUEIO.SNAPSHOT_INVALIDO];

    console.log(`\nBLOQUEANTE — desfecho NAO conclusivo: ${bloqueantes.length}`);

    console.log(`\n  [1] METADATA_404 + IDENTIDADE INSUFICIENTE: ${meta404.length}`);
    if (meta404.length > 0) {
      console.log(`      A fonte respondeu 404 de forma DETERMINISTICA, mas restaram Cards`);
      console.log(`      faltantes sem image_source_url em ${fase.db} — sem URL confiavel nao ha`);
      console.log(`      o que sondar na CDN, e adivinhar identidade e proibido.`);
      console.log(`      ACAO: reconciliar identidade (SET-ID / ASSET-PATH). Reexecutar NAO resolve.`);
      for (const s of meta404) console.log(linhaSet(s));
    }

    console.log(`\n  [2] FONTE NAO DETERMINISTICA (timeout/rede/429/5xx/parse): ${naoDet.length}`);
    if (naoDet.length > 0) {
      console.log(`      Nao sabemos o que a fonte diria. ACAO: reexecutar.`);
      for (const s of naoDet) console.log(linhaSet(s));
    }

    console.log(`\n  [3] SNAPSHOT INVALIDO com universo auditavel: ${semSnap.length}`);
    if (semSnap.length > 0) {
      console.log(`      A fonte respondeu 2xx; o parse do payload falhou. ACAO: investigar o corpo.`);
      for (const s of semSnap) console.log(linhaSet(s));
    }
  }
  if (naoBloqueantes.length > 0) {
    console.log(`\nWARNING (nao bloqueante): ${naoBloqueantes.length}`);
    console.log(`  fonte HTTP 404 deterministico — KNOWN SOURCE DEBT: ${fonteIlegivel.naoBloqueantes.length}`);
    console.log(`    O Set nao existe em ${fase.db} na fonte; seus Cards ficam FORA do universo`);
    console.log(`    de candidatos por construcao (FONTE_INDISPONIVEL, nunca IMPORTABLE_GAP).`);
    console.log(`  snapshot invalido com cobertura ${fase.db} completa: ${semSnapshot.naoBloqueantes.length}`);
    for (const s of naoBloqueantes) console.log(linhaSet(s));
  }

  console.log(`\nVEREDITO: ${veredito}`);

  // ---- Evidencia em disco (fora do banco) ----------------------------------
  await mkdir(OUT_DIR, { recursive: true });
  const carimbo = new Date().toISOString().replace(/[:.]/g, "-");
  const arquivo = path.join(OUT_DIR, `assets-cdn-audit-${carimbo}.json`);
  await writeFile(arquivo, JSON.stringify({
    rodada: "ASSETS-FINAL-CDN-AUDIT-01",
    gerado_em: new Date().toISOString(),
    modo: "READ_ONLY",
    filtros: { expansion: args.expansion, only: args.only, idioma: args.idioma },
    totais: {
      total_candidates, high_available, low_only_available,
      unavailable_404_404, transient_error, accessible_not_imported,
      identity_insufficient,
      metadata_404_sondados_na_cdn: meta404EnviadosCdn,
      candidatos_via_snapshot: porOrigem(ORIGEM_IDENTIDADE.SNAPSHOT),
      candidatos_via_external_reference: porOrigem(ORIGEM_IDENTIDADE.CARD_EXTERNAL_REFERENCE),
    },
    particao_ok: particaoOk,
    identidade_ok: identidadeOk,
    veredito,
    accessible_not_imported: acessiveis,
    // VERDICT-CORRECTION-03A — gate unificado + listas distintas por origem.
    universo_nao_classificavel_bloqueantes: bloqueantes,
    universo_nao_classificavel_nao_bloqueantes: naoBloqueantes,
    // REPORTING-CORRECTION-06 — mesma lista, particionada por CAUSA do
    // bloqueio. Derivada, nao paralela: soma sempre igual a `bloqueantes`.
    bloqueantes_por_classe: particionarBloqueantesParaRelatorio(bloqueantes),
    sets_fonte_indisponivel_bloqueantes: fonteIlegivel.bloqueantes,
    sets_fonte_indisponivel_nao_bloqueantes: fonteIlegivel.naoBloqueantes,
    sets_sem_snapshot_bloqueantes: semSnapshot.bloqueantes,
    sets_sem_snapshot_nao_bloqueantes: semSnapshot.naoBloqueantes,
    sets_fonte_indisponivel: setsFonteIndisponivel,
    sets_sem_snapshot: setsSemSnapshot,
    candidatos: sondados,
  }, null, 2), "utf8");
  console.log(`\nEvidencia: ${arquivo}`);

  if (!particaoOk || !identidadeOk) process.exitCode = 1;
  return { total_candidates, high_available, low_only_available, unavailable_404_404, transient_error, accessible_not_imported, veredito };
}

const executadoDiretamente = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (executadoDiretamente) {
  main().catch((erro) => {
    console.error(`[audit-cdn] ABORTADO: ${erro instanceof Error ? erro.message : String(erro)}`);
    process.exitCode = 1;
  });
}
