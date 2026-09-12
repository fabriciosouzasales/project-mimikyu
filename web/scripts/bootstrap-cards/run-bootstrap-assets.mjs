/*
===============================================================================
Projeto.....: Project Mimikyu
Script......: run-bootstrap-assets.mjs
Rodada......: CATALOG-HISTORICAL-BOOTSTRAP-03-CARDS-ASSETS-STAGING-01
              + ASSETS-BLOCKERS-IMPLEMENTATION-01 (2026-09-11)
Status......: STAGING — NUNCA EXECUTADO (nem DRY_RUN real, nem APPLY)
Criado em...: 2026-09-10

Correcao 2026-09-11 (ASSETS-BLOCKERS-IMPLEMENTATION-01) — tres falsos
negativos silenciosos, todos corrigidos SOMENTE neste arquivo (nenhuma
migration, nenhuma mudanca na Edge Function, nenhum status novo persistido):

  B1 localId cru x collector_number canonico. A fonte publica "1"; o banco
     guarda "001". A comparacao literal fazia toda carta de numeracao pura
     de Set com collector_total >= 10 parecer ausente na fonte, e cair em
     NOT_AVAILABLE_AT_SOURCE. Corrigido com chaveFonte() nos DOIS lados +
     indexarFontePorChave() com FAIL CLOSED em colisao.

  B2 non-2xx virava ausencia — e, no APPLY, virava sucesso. Com a fonte
     inacessivel, disponiveisNaFonte caia para 0, o alvo virava 0 e
     concluirFasePorCobertura devolvia ALREADY_COMPLETE: o Set era pulado
     sem uma unica tentativa de importacao. Corrigido com estado explicito
     de indisponibilidade, 1 retry honrando Retry-After, a classe
     FONTE_INDISPONIVEL e o status LOCAL FAILED_SOURCE_UNAVAILABLE.

  B3 total_set_size era lido e nunca usado. Cobertura de 100% sobre uma
     populacao incompleta de Cards era reportada como COMPLETED. Agora a
     divergencia e registrada por Set e COMPLETED e rebaixado para o status
     LOCAL COMPLETED_PARTIAL_POPULATION.

Objetivo:
  Orquestrar a FASE ASSETS do bootstrap historico, reutilizando integralmente
  o pipeline de imagens que ja existe. Deliberadamente SEPARADO de
  run-bootstrap-cards.mjs: perfis de falha, duracao e retry sao diferentes —
  a fase Cards passa quase sempre de primeira; a de Assets e retry-pesada
  (medido: 203 runs historicas para 46 Card Sets, ~4,4 por Set, 40 FAILED e
  53 COMPLETED_WITH_ERRORS).

  Semantica reproduzida EXATAMENTE como o frontend faz hoje
  (web/components/catalogo/importar-tcgdex-view.tsx, laco de encadeamento):

    pt-BR  -> sempre tentado primeiro
    en     -> tentado na sequencia, SEMPRE, exceto quando pt-BR devolveu
              supported = false (Card Set sem card_set_external_reference
              TCGDEX ativo — condicao independente de idioma; tentar en nao
              mudaria nada)

  Por fase de idioma, o mesmo fluxo de duas etapas da UI:
    admin_start_asset_import_run  (rapido, so a RPC)
      -> Edge Function import-card-assets (lento, bloqueante)

  Preservados: alreadyActive, retry com limite, progresso incremental ja
  persistido, skip de Asset ja existente (v2.7.0 da Edge Function),
  runExpired -> abrir run NOVA (nunca reusar run terminal), interrupted ->
  parar o retry daquele caso.

DOIS MODOS:

  1) DRY_RUN (padrao) — RECONCILIACAO DE LACUNAS, read-only.
     Varre TODOS os 199 Card Sets Pokemon (nao so os 151) e classifica cada
     Asset AUSENTE em exatamente uma de duas classes:

       A. NOT_AVAILABLE_AT_SOURCE — a TCGdex nao publica imagem para aquela
          carta naquele idioma. Nenhuma acao possivel.
       B. IMPORTABLE_GAP — a TCGdex publica a imagem, e o banco nao tem.
          Elegivel para importacao.

     Sem fonte externa. Sem pesquisa editorial. Somente TCGdex.
     Inclui MFB (34 Cards, hoje sem nenhum Asset), 2024SV (15 Cards, hoje so
     'en') e os Sets novos que a fase Cards vier a importar.

  2) APPLY (--apply) — executa pt-BR -> en por Set, sequencialmente.

FONTE DE VERDADE DE COMPLETUDE = O BANCO, NAO O CORPO DA EDGE FUNCTION.
  Os contadores devolvidos por import-card-assets (`images.imported/failed`,
  `failures[]`, `code`, `interrupted`) sao DIAGNOSTICO DA TENTATIVA e so isso —
  desde a v2.7.0 eles refletem apenas o que AQUELA chamada tentou, nao o
  acumulado da Colecao. Depois de cada tentativa o script MEDE a cobertura
  real em card_asset, por Card Set + idioma, e e essa medida que decide se a
  fase terminou.

O QUE ESTE SCRIPT NAO FAZ:
  - nao reimplementa download/checksum/upload (isso e da Edge Function);
  - nao importa Server Action do Next;
  - nao altera schema, migration, Edge Function ou frontend;
  - nao remove nem sobrescreve Asset existente.

Sobre service_role — precisao de terminologia:
  ESTE SCRIPT usa sessao admin real (signInWithPassword). Ele nao recebe,
  nao le e nao persiste service_role em nenhum ponto. Isso NAO significa que
  "o pipeline nunca usa service_role": a Edge Function import-card-assets pode
  usar service_role INTERNAMENTE, depois de validar o JWT recebido via
  auth.getUser() e confirmar o papel via rpc('is_admin'). Esse desenho e
  existente, correto e NAO e alterado nesta rodada.

Uso:
  node run-bootstrap-assets.mjs                              # DRY_RUN dos 199
  node run-bootstrap-assets.mjs --expansion SM               # DRY_RUN de 1 Expansion
  node run-bootstrap-assets.mjs --only MFB,2024SV            # DRY_RUN pontual
  node run-bootstrap-assets.mjs --only MFB --apply           # APPLY de 1 Set
  node run-bootstrap-assets.mjs --expansion BW --apply       # APPLY por Expansion

Ambiente (obrigatorio, SOMENTE por environment):
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  MMKYU_ADMIN_EMAIL
  MMKYU_ADMIN_PASSWORD
===============================================================================
*/

import { createClient } from "@supabase/supabase-js";
import { mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(__dirname, "out");

/** Ordem congelada das fases de idioma. pt-BR sempre primeiro. */
export const FASES_IDIOMA = [
  { db: "pt-BR", tcgdex: "pt" },
  { db: "en", tcgdex: "en" },
];

/** Mesmo teto de tentativas do retry automatico da UI. */
export const MAX_TENTATIVAS_POR_FASE = 3;
/** Universo esperado de Card Sets Pokemon. Fail-fast antes de autenticar. */
export const UNIVERSO_ESPERADO_CARD_SETS = 199;

/**
 * ATENCAO — todos os valores abaixo sao estado LOCAL do script e do relatorio.
 * NENHUM deles e persistido em asset_import_run nem em qualquer coluna do
 * banco. A maquina de estados de asset_import_run permanece exatamente como
 * esta (ASSETS-BLOCKERS-IMPLEMENTATION-01: "nao adicionar novo status
 * persistido").
 */
export const STATUS_FASE = {
  UNSUPPORTED: "UNSUPPORTED",
  SKIPPED_UNSUPPORTED_PTBR: "SKIPPED_UNSUPPORTED_PTBR",
  ALREADY_COMPLETE: "ALREADY_COMPLETE",
  /** Havia run PENDING/RUNNING. NUNCA e conclusao — o Set volta para a fila. */
  ACTIVE_RUN_DEFERRED: "ACTIVE_RUN_DEFERRED",
  COMPLETED: "COMPLETED",
  /**
   * B3: cobertura de Assets completa para as Cards que EXISTEM, mas a
   * populacao de Cards do Set esta abaixo de total_set_size. Estado LOCAL —
   * "completo" nunca pode significar duas coisas diferentes no relatorio.
   */
  COMPLETED_PARTIAL_POPULATION: "COMPLETED_PARTIAL_POPULATION",
  COMPLETED_WITH_ERRORS: "COMPLETED_WITH_ERRORS",
  PARTIAL_COVERAGE: "PARTIAL_COVERAGE",
  INTERRUPTED: "INTERRUPTED",
  FAILED_OPEN_RUN: "FAILED_OPEN_RUN",
  FAILED_EDGE_FUNCTION: "FAILED_EDGE_FUNCTION",
  /**
   * B2: a leitura da TCGdex falhou (non-2xx apos retry, ou excecao de rede).
   * Estado LOCAL e NAO conclusivo. Existe exatamente para impedir que uma
   * falha de fonte seja lida como ausencia de imagem ou como fase completa.
   */
  FAILED_SOURCE_UNAVAILABLE: "FAILED_SOURCE_UNAVAILABLE",
  /**
   * CORRECTION-01: a fonte respondeu 2xx (ok=true), mas o payload nao produziu
   * um snapshot minimo valido. Estado LOCAL e NAO conclusivo. Existe para
   * impedir o unico fail-open restante: invocar a Edge sem `set_snapshot`
   * faria a Edge cair no caminho Edge -> api.tcgdex.net, que e justamente o
   * host comprovadamente inalcancavel a partir da Edge. Fail closed: nenhuma
   * run e aberta, a Edge nao e invocada.
   */
  FAILED_SNAPSHOT_UNAVAILABLE: "FAILED_SNAPSHOT_UNAVAILABLE",
  FAILED_UNEXPECTED: "FAILED_UNEXPECTED",
};

/** Status de fase que NUNCA podem ser lidos como "Set concluido". */
export const STATUS_NAO_CONCLUSIVOS = [
  STATUS_FASE.ACTIVE_RUN_DEFERRED,
  STATUS_FASE.PARTIAL_COVERAGE,
  STATUS_FASE.INTERRUPTED,
  STATUS_FASE.FAILED_OPEN_RUN,
  STATUS_FASE.FAILED_EDGE_FUNCTION,
  STATUS_FASE.FAILED_SOURCE_UNAVAILABLE,
  STATUS_FASE.FAILED_SNAPSHOT_UNAVAILABLE,
  STATUS_FASE.FAILED_UNEXPECTED,
];

export const CLASSE_LACUNA = {
  NOT_AVAILABLE_AT_SOURCE: "NOT_AVAILABLE_AT_SOURCE",
  IMPORTABLE_GAP: "IMPORTABLE_GAP",
  /** B2: a fonte nao pode ser lida. NAO e ausencia — e desconhecimento. */
  FONTE_INDISPONIVEL: "FONTE_INDISPONIVEL",
};

// ---------------------------------------------------------------------------
// Funcoes puras — testaveis sem banco e sem rede
// ---------------------------------------------------------------------------

/**
 * Encadeamento pt-BR -> en. Recebe o resultado da fase pt-BR e responde se a
 * fase en deve rodar. Espelha literalmente o `if (!ptResult.supported)` do
 * frontend: en so e pulado quando pt-BR veio `supported = false`. Qualquer
 * outro desfecho de pt-BR — sucesso, falha parcial, erro real, interrupcao —
 * ainda dispara en.
 */
export function deveTentarEn(resultadoPtBr) {
  return resultadoPtBr?.supported !== false;
}

/**
 * B1 — chave de comparacao simetrica entre os dois lados.
 *
 * A TCGdex publica `localId` CRU ("1", "25", "TG12"); o banco guarda
 * `collector_number` CANONICO, com zero-padding na largura de collector_total
 * ("001", "025", "TG12"). Comparar os dois literalmente faz toda carta de
 * numeracao pura de um Set com collector_total >= 10 parecer ausente na fonte.
 *
 * Normaliza os DOIS lados para a mesma chave:
 *   numerico puro -> remove apenas o padding semantico ("001" e "1" -> "1")
 *   alfanumerico  -> trim + uppercase ("tg12" e " TG12 " -> "TG12")
 *
 * Deliberadamente NAO importa padCollectorNumber (Deno/TS do
 * _shared/catalog-normalization): este e um script Node one-shot e a regra
 * aqui e de COMPARACAO, nao de gravacao — nenhum valor derivado desta funcao
 * e persistido.
 */
/**
 * BOOTSTRAP-METADATA-PASSTHROUGH-01 — DTO MÍNIMO enviado à Edge como
 * `set_snapshot`, para ela não repetir o GET a `api.tcgdex.net` (hoje
 * inalcançável a partir da plataforma Edge; ver v2.10/v2.11 da Edge).
 *
 * NUNCA repassa o payload bruto da TCGdex. Somente os quatro campos que a
 * Edge de fato consome — `id`, `localId`, `name`, `image` — e `image` só
 * quando é string não vazia. `id` vem do PRÓPRIO payload (`j.id`), não do
 * código do Set: se divergir do `external_set_id` da run, a Edge rejeita, e
 * essa rejeição é desejável (foi exatamente o modo de falha do job SV3.5,
 * que trouxe payload de sv04).
 */
export function montarSetSnapshot(payload) {
  const id = String(payload?.id ?? "").trim();
  if (id === "") return null;

  const cards = [];
  for (const c of payload?.cards ?? []) {
    const cardId = String(c?.id ?? "").trim();
    const localId = String(c?.localId ?? "").trim();
    const name = String(c?.name ?? "").trim();
    if (cardId === "" || localId === "" || name === "") return null;

    const card = { id: cardId, localId, name };
    if (typeof c?.image === "string" && c.image.trim() !== "") {
      card.image = c.image.trim();
    }
    cards.push(card);
  }

  if (cards.length < 1 || cards.length > 500) return null;
  return { id, cards };
}

export function chaveFonte(v) {
  const s = String(v ?? "").trim();
  if (s === "") return "";
  return /^\d+$/.test(s) ? String(Number(s)) : s.toUpperCase();
}

/**
 * Monta o indice da fonte por chave normalizada. FAIL CLOSED em colisao: se
 * dois localId distintos normalizarem para a mesma chave, a comparacao deixou
 * de ser confiavel para o Set inteiro e e melhor abortar do que classificar
 * errado em silencio.
 */
export function indexarFontePorChave(cards) {
  const mapa = new Map();
  const origem = new Map();
  for (const c of cards ?? []) {
    const bruto = String(c.localId);
    const chave = chaveFonte(bruto);
    if (mapa.has(chave)) {
      throw new Error(
        `COLISAO_CHAVE_FONTE: localId "${origem.get(chave)}" e "${bruto}" normalizam para "${chave}". ` +
        `Comparacao fonte x banco nao e confiavel neste Card Set — abortado antes de classificar.`,
      );
    }
    mapa.set(chave, Boolean(c.image));
    origem.set(chave, bruto);
  }
  return mapa;
}

/**
 * Classifica UMA lacuna de Asset. `temNaFonte` vem da listagem da TCGdex
 * (campo `image` da carta, no idioma da fase); `temNoBanco` vem de card_asset.
 * Devolve null quando nao ha lacuna.
 *
 * B2: `fonteOk` e obrigatorio. Quando a leitura da fonte falhou, a resposta e
 * FONTE_INDISPONIVEL — NUNCA NOT_AVAILABLE_AT_SOURCE. "Nao consegui perguntar"
 * e "perguntei e nao tem" sao fatos diferentes.
 */
export function classificarLacuna({ temNoBanco, temNaFonte, fonteOk }) {
  if (temNoBanco) return null;
  if (fonteOk !== true) return CLASSE_LACUNA.FONTE_INDISPONIVEL;
  return temNaFonte ? CLASSE_LACUNA.IMPORTABLE_GAP : CLASSE_LACUNA.NOT_AVAILABLE_AT_SOURCE;
}

/**
 * B3 — divergencia entre a populacao de Cards no banco e o total declarado do
 * Card Set. Pura, sem I/O. Nunca corrige catalogo: so nomeia o fato.
 *
 *   MENOR  -> faltam Cards no banco (ex.: os Cards que o G5b nao importou).
 *             Assets das Cards existentes continuam validos; o que muda e que
 *             o Set NAO pode ser reportado como COMPLETED puro.
 *   MAIOR  -> ha mais Cards do que o Set declara. Sinalizado e mais nada —
 *             correcao de catalogo esta fora do escopo desta rodada.
 */
export function descreverDivergenciaPopulacao({ cardsNoBanco, declaredTotalSetSize }) {
  if (typeof declaredTotalSetSize !== "number" || declaredTotalSetSize <= 0) return null;
  if (cardsNoBanco === declaredTotalSetSize) return null;
  const delta = cardsNoBanco - declaredTotalSetSize;
  return delta < 0
    ? `MENOR: ${cardsNoBanco}/${declaredTotalSetSize} (faltam ${-delta} Cards no banco)`
    : `MAIOR: ${cardsNoBanco}/${declaredTotalSetSize} (excedente de ${delta} Cards — sinalizado, nao corrigido)`;
}

/**
 * Conclusoes POSITIVAS — os unicos status que afirmam completude ao leitor do
 * relatorio. Toda conclusao positiva precisa ser rebaixada quando a populacao
 * de Cards esta abaixo do declarado (B3); do contrario o relatorio comunica
 * completude integral sobre um Set incompleto.
 */
export const STATUS_CONCLUSIVOS_POSITIVOS = [
  STATUS_FASE.COMPLETED,
  STATUS_FASE.ALREADY_COMPLETE,
];

/**
 * B3 — populacao incompleta rebaixa QUALQUER conclusao positiva para
 * COMPLETED_PARTIAL_POPULATION.
 *
 * Correcao ASSETS-BLOCKERS-CORRECTION-02: a versao anterior so tratava
 * COMPLETED. Isso deixava um falso positivo aberto — 95 Cards no banco de 100
 * declaradas, todas as 95 com Asset, statusBase = ALREADY_COMPLETE, e o
 * relatorio dizia completude integral. ALREADY_COMPLETE afirma completude
 * tanto quanto COMPLETED, entao precisa do mesmo rebaixamento.
 *
 * Estados NAO conclusivos (PARTIAL_COVERAGE, FAILED_SOURCE_UNAVAILABLE,
 * ACTIVE_RUN_DEFERRED, INTERRUPTED, FAILED_*) passam intactos: eles ja nao
 * afirmam completude, e rebaixa-los apagaria a causa real da nao conclusao.
 * UNSUPPORTED e SKIPPED_UNSUPPORTED_PTBR tambem passam intactos — descrevem
 * ausencia de referencia externa, nao completude.
 */
export function statusFinalComPopulacao({ statusBase, cardsNoBanco, declaredTotalSetSize }) {
  if (!STATUS_CONCLUSIVOS_POSITIVOS.includes(statusBase)) return statusBase;
  if (typeof declaredTotalSetSize !== "number" || declaredTotalSetSize <= 0) return statusBase;
  if (typeof cardsNoBanco !== "number") return statusBase;
  return cardsNoBanco < declaredTotalSetSize ? STATUS_FASE.COMPLETED_PARTIAL_POPULATION : statusBase;
}

/**
 * Decide se vale abrir uma run nova para esta fase. `runExpired` significa que
 * a run anterior chegou a estado terminal — a maquina de estados nunca permite
 * reabrir, entao reusar o mesmo run_code jamais teria sucesso.
 */
/**
 * Conclusao de uma fase de idioma medida NO BANCO, nao no corpo da resposta.
 * `cobertura` = { total, com_asset } lido de card/card_asset depois da
 * tentativa. `disponiveisNaFonte` (opcional) permite distinguir "faltam
 * imagens que a fonte tem" de "a fonte nao publica o resto".
 */
export function concluirFasePorCobertura({ cobertura, disponiveisNaFonte = null, fonteOk = true }) {
  // B2 — guarda dura: sem leitura confiavel da fonte NAO existe conclusao.
  // Antes desta guarda, um 503 zerava `disponiveisNaFonte`, o alvo virava 0 e
  // a fase era declarada ALREADY_COMPLETE ("nada disponivel na fonte") sem
  // nenhuma tentativa de importacao — falso sucesso, nao degradacao.
  if (fonteOk !== true) {
    return {
      status: STATUS_FASE.FAILED_SOURCE_UNAVAILABLE,
      completa: false,
      motivo: "fonte indisponivel — impossivel concluir; nenhuma ausencia inferida",
    };
  }
  const alvo = typeof disponiveisNaFonte === "number" ? Math.min(disponiveisNaFonte, cobertura.total) : cobertura.total;
  if (alvo === 0) {
    return { status: STATUS_FASE.ALREADY_COMPLETE, completa: true, motivo: "nada disponivel na fonte para este idioma" };
  }
  if (cobertura.com_asset >= alvo) {
    return { status: STATUS_FASE.COMPLETED, completa: true, motivo: `cobertura no banco ${cobertura.com_asset}/${alvo}` };
  }
  return {
    status: STATUS_FASE.PARTIAL_COVERAGE,
    completa: false,
    motivo: `cobertura no banco ${cobertura.com_asset}/${alvo} — NAO concluido; medido no banco, nao no corpo da Edge Function`,
  };
}

/**
 * Identificador canonico devolvido pela Edge Function quando a run ja chegou a
 * status terminal (index.ts, guard de terminalidade).
 */
export const CODIGO_RUN_TERMINAL = "IMPORT_RUN_ALREADY_TERMINAL";

/**
 * ASSETS-RETRY-TERMINAL-FIX-01 — reconhecimento de run terminal.
 *
 * O contrato HTTP real nao e uniforme: algumas respostas trazem o
 * identificador em `code`, outras o trazem apenas como PREFIXO de `error`
 * ("IMPORT_RUN_ALREADY_TERMINAL: esta run ja chegou a um status final...").
 * O executor so olhava `code`, entao tratava a run morta como viva e repetia
 * na MESMA run_code — exatamente o que foi observado em DC1 EN
 * (RUN-20260911-00004241).
 *
 * DELIBERADAMENTE nao olha `r.status`: HTTP 409 e usado por outras condicoes
 * e NUNCA deve, sozinho, classificar a run como terminal. O gatilho e o
 * identificador, nao o codigo HTTP.
 */
export function ehRespostaRunTerminal(corpo) {
  if (!corpo || typeof corpo !== "object") return false;
  if (corpo.code === CODIGO_RUN_TERMINAL) return true;
  return typeof corpo.error === "string" && corpo.error.startsWith(CODIGO_RUN_TERMINAL);
}

export function decidirRetry({ tentativa, runExpired, interrupted }) {
  if (interrupted) return { repetir: false, abrirRunNova: false, motivo: "interrupted: padrao de falha sistematica, insistir nao muda o resultado" };
  if (tentativa >= MAX_TENTATIVAS_POR_FASE) return { repetir: false, abrirRunNova: false, motivo: `teto de ${MAX_TENTATIVAS_POR_FASE} tentativas atingido` };
  if (runExpired) return { repetir: true, abrirRunNova: true, motivo: "run terminal — abrir run NOVA, nunca reusar run_code morto" };
  return { repetir: true, abrirRunNova: false, motivo: "retry na mesma run" };
}

export function parseArgs(argv) {
  const args = { apply: false, only: null, expansion: null, limit: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--apply") args.apply = true;
    else if (a === "--only") args.only = String(argv[++i] ?? "").split(",").map((s) => s.trim().toUpperCase()).filter(Boolean);
    else if (a === "--expansion") args.expansion = String(argv[++i] ?? "").split(",").map((s) => s.trim().toUpperCase()).filter(Boolean);
    else if (a === "--limit") args.limit = Number(argv[++i]);
  }
  return args;
}

export function filtrarUniverso(sets, args) {
  let out = sets;
  if (args.expansion) out = out.filter((s) => args.expansion.includes(String(s.expansion_code).toUpperCase()));
  if (args.only) out = out.filter((s) => args.only.includes(String(s.card_set_code).toUpperCase()));
  if (args.limit && Number.isFinite(args.limit)) out = out.slice(0, args.limit);
  return out;
}

const ENV_OBRIGATORIAS = [
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "MMKYU_ADMIN_EMAIL",
  "MMKYU_ADMIN_PASSWORD",
];

function conferirAmbiente() {
  const faltando = ENV_OBRIGATORIAS.filter((k) => !process.env[k]);
  if (faltando.length > 0) {
    throw new Error(`ENV_AUSENTE: ${faltando.join(", ")}. Defina no ambiente — nunca por argumento de linha de comando.`);
  }
}

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------------------
// Leituras
// ---------------------------------------------------------------------------

// `export` adicionado em ASSETS-FINAL-CDN-AUDIT-01: leitura pura, reusada pelo
// diagnostico read-only audit-assets-cdn.mjs para que o universo auditado seja
// o MESMO por construcao, nunca por reimplementacao. Zero mudanca de logica.
export async function listarCardSetsPokemon(supabase) {
  const { data, error } = await supabase
    .from("card_set")
    .select("id, code, total_set_size, expansion:expansion_id!inner(code, release_order, game:game_id!inner(code))")
    .eq("expansion.game.code", "POKEMON");
  if (error) throw new Error(`FALHA_LISTAR_CARD_SETS: ${error.message}`);
  return (data ?? [])
    .map((r) => ({
      card_set_id: r.id,
      card_set_code: r.code,
      expansion_code: r.expansion.code,
      expansion_release_order: r.expansion.release_order,
      external_set_id: String(r.code).toLowerCase(),
      declared_total_set_size: r.total_set_size,
    }))
    .sort((a, b) => a.expansion_release_order - b.expansion_release_order || a.card_set_code.localeCompare(b.card_set_code));
}

/** Cards do Set + quais idiomas ja tem Asset primario ativo. Pagina — nunca amostra. */
// `export` adicionado em ASSETS-FINAL-CDN-AUDIT-01 — ver nota em
// listarCardSetsPokemon. Leitura pura, zero mudanca de logica.
export async function lerCardsComAssets(supabase, cardSetId) {
  const PAG = 500;
  const cards = [];
  for (let offset = 0; ; offset += PAG) {
    const { data, error } = await supabase
      .from("card")
      .select("id, collector_number")
      .eq("card_set_id", cardSetId)
      .order("id", { ascending: true })
      .range(offset, offset + PAG - 1);
    if (error) throw new Error(`FALHA_LER_CARDS: ${error.message}`);
    cards.push(...(data ?? []));
    if ((data ?? []).length < PAG) break;
  }
  if (cards.length === 0) return [];

  const idiomasPorCard = new Map(cards.map((c) => [c.id, new Set()]));
  const ids = cards.map((c) => c.id);
  for (let i = 0; i < ids.length; i += 200) {
    const fatia = ids.slice(i, i + 200);
    const { data, error } = await supabase
      .from("card_asset")
      .select("card_id, is_primary, is_active, language:language_id!inner(code), tipo:asset_type_id!inner(code)")
      .in("card_id", fatia)
      .eq("is_primary", true)
      .eq("is_active", true);
    if (error) throw new Error(`FALHA_LER_ASSETS: ${error.message}`);
    for (const a of data ?? []) {
      if (a.tipo?.code !== "CARD_FRONT") continue;
      idiomasPorCard.get(a.card_id)?.add(a.language.code);
    }
  }
  return cards.map((c) => ({ ...c, idiomas: idiomasPorCard.get(c.id) ?? new Set() }));
}

/**
 * Disponibilidade na fonte, por idioma, para UM Set. Uma requisicao por idioma:
 * a listagem /{lang}/sets/{id} ja traz o campo `image` por carta (verificado).
 * Devolve Map<collector_number, boolean>.
 *
 * IMPORTANTE — honestidade do dado: presenca de `image` e a DECLARACAO da
 * fonte, nao prova de HTTP 200 no CDN. Isso e suficiente para separar
 * "nao existe na fonte" de "existe e nao importamos", que e o objetivo desta
 * reconciliacao. A verificacao real do arquivo continua sendo da Edge Function,
 * no momento do download.
 */
export function calcularEsperaRetry(retryAfterHeader, padraoMs = 2000) {
  if (!retryAfterHeader) return padraoMs;
  const segundos = Number(String(retryAfterHeader).trim());
  if (Number.isFinite(segundos) && segundos >= 0) return Math.min(segundos * 1000, 30000);
  const data = Date.parse(String(retryAfterHeader));
  if (Number.isFinite(data)) return Math.min(Math.max(data - Date.now(), 0), 30000);
  return padraoMs;
}

export async function disponibilidadeNaFonte(externalSetId, langTcgdex, fetchImpl = fetch, dormirImpl = dormir) {
  const url = `https://api.tcgdex.net/v2/${langTcgdex}/sets/${externalSetId}`;

  for (let tentativa = 1; tentativa <= 2; tentativa += 1) {
    let r;
    try {
      r = await fetchImpl(url);
    } catch (erro) {
      // Excecao de rede (DNS, TLS, timeout). Antes subia sem tratamento; agora
      // vira estado explicito de indisponibilidade, nunca ausencia.
      if (tentativa === 1) { await dormirImpl(2000); continue; }
      return { ok: false, http: null, mapa: new Map(), erro: erro instanceof Error ? erro.message : String(erro) };
    }

    if (r.ok) {
      let j;
      try {
        j = await r.json();
      } catch (erro) {
        return { ok: false, http: r.status, mapa: new Map(), erro: `corpo nao e JSON: ${erro instanceof Error ? erro.message : String(erro)}` };
      }
      // B1: indice por chave normalizada, com FAIL CLOSED em colisao.
      // `snapshot`: DTO minimo para o passthrough. null quando o payload nao
      // satisfaz o contrato minimo — e, a partir da CORRECTION-01, null com
      // ok=true FAZ A FASE ABORTAR (FAILED_SNAPSHOT_UNAVAILABLE). Nao existe
      // mais fallback silencioso para o caminho Edge -> api.tcgdex.net.
      return {
        ok: true,
        http: r.status,
        mapa: indexarFontePorChave(j.cards ?? []),
        snapshot: montarSetSnapshot(j),
        erro: null,
      };
    }

    const retentavel = r.status === 429 || r.status >= 500;
    if (retentavel && tentativa === 1) {
      await dormirImpl(calcularEsperaRetry(r.headers?.get?.("Retry-After")));
      continue;
    }
    return { ok: false, http: r.status, mapa: new Map(), erro: `HTTP ${r.status}` };
  }
  return { ok: false, http: null, mapa: new Map(), erro: "esgotou o retry sem resposta utilizavel" };
}

// ---------------------------------------------------------------------------
// DRY_RUN — reconciliacao de lacunas dos 199
// ---------------------------------------------------------------------------

async function reconciliarLacunasDoSet(supabase, set) {
  const linha = {
    expansion_code: set.expansion_code,
    card_set_code: set.card_set_code,
    external_set_id: set.external_set_id,
    cards_no_banco: 0,
    // B3 — populacao declarada x real, sempre visivel no relatorio.
    declared_total_set_size: set.declared_total_set_size ?? null,
    cards_na_fonte: null,
    divergencia_populacao: null,
    "pt-BR_ja_existentes": 0,
    "pt-BR_importable_gap": 0,
    "pt-BR_not_available_at_source": 0,
    "pt-BR_fonte_indisponivel": 0,
    "pt-BR_fonte_http": null,
    "pt-BR_fonte_erro": null,
    en_ja_existentes: 0,
    en_importable_gap: 0,
    en_not_available_at_source: 0,
    en_fonte_indisponivel: 0,
    en_fonte_http: null,
    en_fonte_erro: null,
    observacao: null,
  };

  const cards = await lerCardsComAssets(supabase, set.card_set_id);
  linha.cards_no_banco = cards.length;
  if (cards.length === 0) {
    linha.observacao = "Set sem Cards — fora da reconciliacao de Assets ate a fase Cards rodar";
    return linha;
  }

  for (const fase of FASES_IDIOMA) {
    let fonte;
    try {
      fonte = await disponibilidadeNaFonte(set.external_set_id, fase.tcgdex);
    } catch (erro) {
      // Inclui COLISAO_CHAVE_FONTE (B1, fail closed). Fonte inutilizavel para
      // este Set+idioma — nada e classificado como ausente.
      fonte = { ok: false, http: null, mapa: new Map(), erro: erro instanceof Error ? erro.message : String(erro) };
    }
    linha[`${fase.db}_fonte_http`] = fonte.http;
    linha[`${fase.db}_fonte_erro`] = fonte.erro ?? null;
    // pt-BR e en devem trazer o mesmo universo de cartas; registra o da 1a fase ok.
    if (fonte.ok && linha.cards_na_fonte === null) linha.cards_na_fonte = fonte.mapa.size;

    for (const card of cards) {
      const temNoBanco = card.idiomas.has(fase.db);
      if (temNoBanco) {
        linha[`${fase.db}_ja_existentes`] += 1;
        continue;
      }
      // B1: consulta pela MESMA chave normalizada usada ao indexar a fonte.
      const temNaFonte = fonte.ok ? (fonte.mapa.get(chaveFonte(card.collector_number)) ?? false) : false;
      const classe = classificarLacuna({ temNoBanco, temNaFonte, fonteOk: fonte.ok });
      if (classe === CLASSE_LACUNA.IMPORTABLE_GAP) linha[`${fase.db}_importable_gap`] += 1;
      else if (classe === CLASSE_LACUNA.NOT_AVAILABLE_AT_SOURCE) linha[`${fase.db}_not_available_at_source`] += 1;
      else linha[`${fase.db}_fonte_indisponivel`] += 1;
    }
  }

  linha.divergencia_populacao = descreverDivergenciaPopulacao({
    cardsNoBanco: linha.cards_no_banco,
    declaredTotalSetSize: linha.declared_total_set_size,
  });
  return linha;
}

// ---------------------------------------------------------------------------
// APPLY — uma fase de idioma
// ---------------------------------------------------------------------------

/**
 * Cobertura REAL no banco para um Card Set + idioma. Esta e a fonte de verdade
 * de completude — o corpo da Edge Function nunca e.
 */
async function medirCoberturaNoBanco(supabase, cardSetId, languageCode) {
  const [totalRes, cobertosRes] = await Promise.all([
    supabase.from("card").select("id", { count: "exact", head: true }).eq("card_set_id", cardSetId),
    supabase
      .from("card_asset")
      .select("id, card!inner(card_set_id), asset_type:asset_type_id!inner(code), language:language_id!inner(code)", {
        count: "exact",
        head: true,
      })
      .eq("card.card_set_id", cardSetId)
      .eq("asset_type.code", "CARD_FRONT")
      .eq("language.code", languageCode)
      .eq("is_primary", true)
      .eq("is_active", true),
  ]);
  if (totalRes.error) throw new Error(`FALHA_MEDIR_TOTAL: ${totalRes.error.message}`);
  if (cobertosRes.error) throw new Error(`FALHA_MEDIR_COBERTURA: ${cobertosRes.error.message}`);
  return { total: totalRes.count ?? 0, com_asset: cobertosRes.count ?? 0 };
}

/** B3 — populacao real de Cards do Set, para confronto com total_set_size. */
async function contarCardsDoSet(supabase, cardSetId) {
  const { count, error } = await supabase
    .from("card")
    .select("id", { count: "exact", head: true })
    .eq("card_set_id", cardSetId);
  if (error) throw new Error(`FALHA_CONTAR_CARDS: ${error.message}`);
  return count ?? 0;
}

async function abrirRun(supabase, cardSetId, languageCode, initiatedBy) {
  const { data, error } = await supabase.rpc("admin_start_asset_import_run", {
    p_card_set_id: cardSetId,
    p_run_type: "FULL_CARD_SET",
    p_initiated_by: initiatedBy,
    p_language_code: languageCode,
  });
  if (error) return { erro: error.message };
  const [row] = (data ?? []);
  return {
    supported: row?.supported ?? false,
    runId: row?.run_id ?? null,
    runCode: row?.run_code ?? null,
    alreadyActive: row?.already_active ?? false,
  };
}

export async function invocarImportCardAssets(supabaseUrl, accessToken, runCode, setSnapshot) {
  // CORRECTION-01 — segunda linha de defesa do fail closed. O guard primario
  // esta em executarFaseIdioma(); este aqui existe para que NENHUM caminho
  // futuro consiga invocar a Edge sem snapshot por omissao de argumento.
  if (!setSnapshot) {
    throw new Error(
      "SNAPSHOT_OBRIGATORIO: invocarImportCardAssets chamada sem set_snapshot. " +
      "Sem snapshot a Edge cairia em api.tcgdex.net (host inalcancavel a partir da Edge).",
    );
  }
  const url = `${supabaseUrl}/functions/v1/import-card-assets`;
  const payload = { run_code: runCode, set_snapshot: setSnapshot };
  const resposta = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify(payload),
  });
  const corpo = await resposta.json().catch(() => null);
  return { ok: resposta.ok, status: resposta.status, corpo };
}

export async function executarFaseIdioma({ supabase, supabaseUrl, accessToken, set, fase }) {
  const resultado = {
    idioma: fase.db,
    supported: true,
    status: null,
    run_code: null,
    tentativas: 0,
    // Diagnostico DA TENTATIVA (corpo da Edge Function) — nunca conclusao.
    diag_importados: 0,
    diag_falhos: 0,
    diag_code: null,
    fonte_http: null,
    // Medida REAL no banco — esta e a conclusao.
    cobertura_antes: null,
    cobertura_depois: null,
    disponiveis_na_fonte: null,
    motivo: null,
  };

  const antes = await medirCoberturaNoBanco(supabase, set.card_set_id, fase.db);
  resultado.cobertura_antes = `${antes.com_asset}/${antes.total}`;

  let fonte;
  try {
    fonte = await disponibilidadeNaFonte(set.external_set_id, fase.tcgdex);
  } catch (erro) {
    fonte = { ok: false, http: null, mapa: new Map(), erro: erro instanceof Error ? erro.message : String(erro) };
  }

  // B2 — sem leitura confiavel da fonte, a fase ABORTA como nao conclusiva.
  // Nenhuma run e aberta, a Edge Function nao e invocada, e o Set volta para a
  // fila. Antes, este caminho produzia ALREADY_COMPLETE e pulava o Set.
  if (!fonte.ok) {
    resultado.status = STATUS_FASE.FAILED_SOURCE_UNAVAILABLE;
    resultado.cobertura_depois = resultado.cobertura_antes;
    resultado.disponiveis_na_fonte = null;
    resultado.fonte_http = fonte.http;
    resultado.motivo = `fonte indisponivel (${fonte.erro ?? `HTTP ${fonte.http}`}) — nenhuma run aberta, nenhuma ausencia inferida`;
    return resultado;
  }

  const disponiveis = Array.from(fonte.mapa.values()).filter(Boolean).length;
  resultado.disponiveis_na_fonte = disponiveis;
  resultado.fonte_http = fonte.http;

  // Ja completo antes de qualquer chamada: nao abre run, nao invoca nada.
  const jaCompleto = concluirFasePorCobertura({ cobertura: antes, disponiveisNaFonte: disponiveis, fonteOk: true });
  if (jaCompleto.completa) {
    resultado.status = STATUS_FASE.ALREADY_COMPLETE;
    resultado.cobertura_depois = resultado.cobertura_antes;
    resultado.motivo = jaCompleto.motivo;
    return resultado;
  }

  // CORRECTION-01 — FAIL CLOSED DO SNAPSHOT.
  // Daqui para baixo a fase VAI executar APPLY (abrir run + invocar a Edge).
  // A fonte respondeu 2xx, logo `montarSetSnapshot()` teve o payload em maos:
  // se ainda assim nao produziu snapshot, o payload nao satisfaz o contrato
  // minimo. Invocar a Edge sem `set_snapshot` NAO e degradacao aceitavel —
  // e cair no caminho Edge -> api.tcgdex.net, o host comprovadamente
  // inalcancavel a partir da Edge. Aborta ANTES de abrir qualquer run.
  if (!fonte.snapshot) {
    resultado.status = STATUS_FASE.FAILED_SNAPSHOT_UNAVAILABLE;
    resultado.cobertura_depois = resultado.cobertura_antes;
    resultado.motivo =
      "fonte respondeu 2xx mas nao produziu set_snapshot minimo valido — " +
      "nenhuma run aberta, Edge Function NAO invocada (fail closed: sem snapshot " +
      "a Edge cairia em api.tcgdex.net)";
    return resultado;
  }

  let abrirNova = true;
  let runCode = null;

  for (let tentativa = 1; tentativa <= MAX_TENTATIVAS_POR_FASE; tentativa += 1) {
    resultado.tentativas = tentativa;

    if (abrirNova) {
      const run = await abrirRun(
        supabase,
        set.card_set_id,
        fase.db,
        `bootstrap-cards:${set.card_set_code}`,
      );
      if (run.erro) {
        resultado.status = STATUS_FASE.FAILED_OPEN_RUN;
        resultado.motivo = run.erro;
        resultado.cobertura_depois = resultado.cobertura_antes;
        return resultado;
      }
      if (run.supported === false) {
        resultado.supported = false;
        resultado.status = STATUS_FASE.UNSUPPORTED;
        resultado.motivo = "Card Set sem card_set_external_reference TCGDEX ativo — caminho normal, nao erro";
        resultado.cobertura_depois = resultado.cobertura_antes;
        return resultado;
      }
      if (run.alreadyActive) {
        // NUNCA invocar uma segunda Edge Function concorrente, e NUNCA
        // registrar o Set como concluido so porque havia uma run ativa.
        const agora = await medirCoberturaNoBanco(supabase, set.card_set_id, fase.db);
        resultado.status = STATUS_FASE.ACTIVE_RUN_DEFERRED;
        resultado.run_code = run.runCode;
        resultado.cobertura_depois = `${agora.com_asset}/${agora.total}`;
        resultado.motivo =
          "run PENDING/RUNNING ja existente para este Set+idioma — nenhuma chamada concorrente feita; " +
          "Set ADIADO, nao concluido. Reexecutar depois que a run em andamento chegar a estado terminal.";
        return resultado;
      }
      runCode = run.runCode;
      resultado.run_code = runCode;
      abrirNova = false;
    }

    const r = await invocarImportCardAssets(
      supabaseUrl,
      accessToken,
      runCode,
      fonte.snapshot,
    );
    const corpo = r.corpo ?? {};
    const runExpired = ehRespostaRunTerminal(corpo);
    const interrupted = Boolean(corpo.interrupted);

    // Corpo = DIAGNOSTICO da tentativa. Registrado, nunca usado como conclusao.
    resultado.diag_importados = corpo.images?.imported ?? 0;
    resultado.diag_falhos = corpo.images?.failed ?? 0;
    resultado.diag_code = corpo.code ?? (r.ok ? null : `HTTP_${r.status}`);
    if (!r.ok) resultado.motivo = `HTTP ${r.status}: ${corpo.error ?? "sem corpo"}`;

    // CONCLUSAO medida no banco, depois da tentativa.
    const depois = await medirCoberturaNoBanco(supabase, set.card_set_id, fase.db);
    resultado.cobertura_depois = `${depois.com_asset}/${depois.total}`;
    // fonteOk explicito: neste ponto a leitura da fonte ja foi bem-sucedida
    // (o caminho !fonte.ok retornou antes de qualquer run ser aberta).
    const conclusao = concluirFasePorCobertura({ cobertura: depois, disponiveisNaFonte: disponiveis, fonteOk: true });
    resultado.status = conclusao.status;
    if (conclusao.completa) {
      resultado.motivo = conclusao.motivo;
      return resultado;
    }

    const decisao = decidirRetry({ tentativa, runExpired, interrupted });
    if (!decisao.repetir) {
      if (interrupted) resultado.status = STATUS_FASE.INTERRUPTED;
      resultado.motivo = [resultado.motivo, conclusao.motivo, decisao.motivo].filter(Boolean).join(" | ");
      return resultado;
    }
    abrirNova = decisao.abrirRunNova;
    await dormir(2000);
  }
  resultado.motivo = [resultado.motivo, "teto de tentativas atingido sem cobertura completa"].filter(Boolean).join(" | ");
  return resultado;
}

async function processarSetAssets({ supabase, supabaseUrl, accessToken, set }) {
  const linha = {
    expansion_code: set.expansion_code,
    card_set_code: set.card_set_code,
    external_set_id: set.external_set_id,
    cards_no_banco: null,
    declared_total_set_size: set.declared_total_set_size ?? null,
    divergencia_populacao: null,
    fases: [],
    status_final: null,
    motivo: null,
  };
  try {
    const ptBr = await executarFaseIdioma({ supabase, supabaseUrl, accessToken, set, fase: FASES_IDIOMA[0] });
    linha.fases.push(ptBr);

    if (!deveTentarEn(ptBr)) {
      linha.fases.push({
        idioma: "en",
        supported: false,
        status: STATUS_FASE.SKIPPED_UNSUPPORTED_PTBR,
        motivo: "pt-BR devolveu supported = false — condicao independente de idioma; tentar en nao mudaria nada",
        tentativas: 0,
        diag_importados: 0,
        diag_falhos: 0,
        diag_code: null,
        cobertura_antes: null,
        cobertura_depois: null,
        disponiveis_na_fonte: null,
        run_code: null,
      });
      linha.status_final = STATUS_FASE.UNSUPPORTED;
      return linha;
    }

    const en = await executarFaseIdioma({ supabase, supabaseUrl, accessToken, set, fase: FASES_IDIOMA[1] });
    linha.fases.push(en);

    // Conclusao do SET = conclusao das fases, e conclusao de fase e medida no
    // banco. Qualquer fase em estado nao conclusivo (adiada por run ativa,
    // cobertura parcial, interrompida ou com falha) impede marcar o Set como
    // concluido — inclusive o caso ACTIVE_RUN_DEFERRED.
    const naoConclusiva = linha.fases.find((f) => STATUS_NAO_CONCLUSIVOS.includes(f.status));
    const statusBase = naoConclusiva ? naoConclusiva.status : STATUS_FASE.COMPLETED;
    if (naoConclusiva) linha.motivo = `fase ${naoConclusiva.idioma}: ${naoConclusiva.motivo ?? naoConclusiva.status}`;

    // B3 — cobertura completa sobre populacao incompleta nao e COMPLETED.
    const totalNoBanco = await contarCardsDoSet(supabase, set.card_set_id);
    linha.cards_no_banco = totalNoBanco;
    linha.declared_total_set_size = set.declared_total_set_size ?? null;
    linha.divergencia_populacao = descreverDivergenciaPopulacao({
      cardsNoBanco: totalNoBanco,
      declaredTotalSetSize: set.declared_total_set_size,
    });
    linha.status_final = statusFinalComPopulacao({
      statusBase,
      cardsNoBanco: totalNoBanco,
      declaredTotalSetSize: set.declared_total_set_size,
    });
    if (linha.status_final === STATUS_FASE.COMPLETED_PARTIAL_POPULATION) {
      linha.motivo = [linha.motivo, `Assets completos, mas ${linha.divergencia_populacao}`].filter(Boolean).join(" | ");
    }
    return linha;
  } catch (erro) {
    linha.status_final = STATUS_FASE.FAILED_UNEXPECTED;
    linha.motivo = erro instanceof Error ? erro.message : String(erro);
    return linha;
  }
}

// ---------------------------------------------------------------------------
// Relatorios
// ---------------------------------------------------------------------------

export function paraCsv(linhas, colunas) {
  const esc = (v) => {
    if (v === null || v === undefined) return "";
    const s = String(v);
    return /[",\n;]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
  };
  return [colunas.join(","), ...linhas.map((l) => colunas.map((c) => esc(l[c])).join(","))].join("\n");
}

const COLUNAS_DRY_RUN = [
  "expansion_code", "card_set_code", "external_set_id",
  "cards_no_banco", "declared_total_set_size", "cards_na_fonte", "divergencia_populacao",
  "pt-BR_ja_existentes", "pt-BR_importable_gap", "pt-BR_not_available_at_source",
  "pt-BR_fonte_indisponivel", "pt-BR_fonte_http", "pt-BR_fonte_erro",
  "en_ja_existentes", "en_importable_gap", "en_not_available_at_source",
  "en_fonte_indisponivel", "en_fonte_http", "en_fonte_erro",
  "observacao",
];

const COLUNAS_APPLY = [
  "expansion_code", "card_set_code", "external_set_id",
  "cards_no_banco", "declared_total_set_size", "divergencia_populacao", "status_final",
  "idioma", "status", "run_code", "tentativas",
  "cobertura_antes", "cobertura_depois", "disponiveis_na_fonte", "fonte_http",
  "diag_importados", "diag_falhos", "diag_code",
  "motivo",
];

function achatarApply(linhas) {
  return linhas.flatMap((l) =>
    l.fases.map((f) => ({
      expansion_code: l.expansion_code,
      card_set_code: l.card_set_code,
      external_set_id: l.external_set_id,
      cards_no_banco: l.cards_no_banco,
      declared_total_set_size: l.declared_total_set_size,
      divergencia_populacao: l.divergencia_populacao,
      status_final: l.status_final,
      idioma: f.idioma,
      status: f.status,
      run_code: f.run_code,
      tentativas: f.tentativas,
      cobertura_antes: f.cobertura_antes,
      cobertura_depois: f.cobertura_depois,
      disponiveis_na_fonte: f.disponiveis_na_fonte,
      fonte_http: f.fonte_http ?? null,
      diag_importados: f.diag_importados,
      diag_falhos: f.diag_falhos,
      diag_code: f.diag_code,
      motivo: f.motivo,
    })),
  );
}

async function gravarRelatorios(nome, payload, linhasCsv, colunas) {
  await mkdir(OUT_DIR, { recursive: true });
  const carimbo = new Date().toISOString().replaceAll(":", "-").replaceAll(".", "-");
  const base = path.join(OUT_DIR, `${nome}-${carimbo}`);
  await writeFile(`${base}.json`, JSON.stringify(payload, null, 2), "utf8");
  await writeFile(`${base}.csv`, paraCsv(linhasCsv, colunas), "utf8");
  return { json: `${base}.json`, csv: `${base}.csv` };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

export async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  conferirAmbiente();

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabase = createClient(supabaseUrl, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: auth, error: erroAuth } = await supabase.auth.signInWithPassword({
    email: process.env.MMKYU_ADMIN_EMAIL,
    password: process.env.MMKYU_ADMIN_PASSWORD,
  });
  if (erroAuth) throw new Error(`FALHA_LOGIN: ${erroAuth.message}`);
  const accessToken = auth.session?.access_token;
  if (!accessToken) throw new Error("FALHA_LOGIN: sessao sem access_token.");

  const { data: ehAdmin, error: erroAdmin } = await supabase.rpc("is_admin");
  if (erroAdmin) throw new Error(`FALHA_IS_ADMIN: ${erroAdmin.message}`);
  if (ehAdmin !== true) throw new Error("NAO_ADMIN: a sessao autenticada nao tem papel administrativo. Abortado antes de qualquer escrita.");

  const todos = await listarCardSetsPokemon(supabase);
  if (todos.length !== UNIVERSO_ESPERADO_CARD_SETS) {
    throw new Error(`UNIVERSO_DIVERGENTE: ${todos.length} Card Sets Pokemon, esperado ${UNIVERSO_ESPERADO_CARD_SETS}.`);
  }

  const universo = filtrarUniverso(todos, args);
  if (universo.length === 0) throw new Error("FILTRO_VAZIO: nenhum Set selecionado.");

  console.log(`[bootstrap-assets] modo=${args.apply ? "APPLY" : "DRY_RUN"} sets=${universo.length}/${todos.length}`);

  if (!args.apply) {
    const linhas = [];
    for (const [i, set] of universo.entries()) {
      console.log(`[${i + 1}/${universo.length}] ${set.card_set_code} (${set.expansion_code})`);
      linhas.push(await reconciliarLacunasDoSet(supabase, set));
    }
    const totais = linhas.reduce(
      (acc, l) => ({
        cards: acc.cards + l.cards_no_banco,
        ptbr_existentes: acc.ptbr_existentes + l["pt-BR_ja_existentes"],
        ptbr_importable: acc.ptbr_importable + l["pt-BR_importable_gap"],
        ptbr_indisponivel: acc.ptbr_indisponivel + l["pt-BR_not_available_at_source"],
        ptbr_fonte_indisponivel: acc.ptbr_fonte_indisponivel + l["pt-BR_fonte_indisponivel"],
        en_existentes: acc.en_existentes + l.en_ja_existentes,
        en_importable: acc.en_importable + l.en_importable_gap,
        en_indisponivel: acc.en_indisponivel + l.en_not_available_at_source,
        en_fonte_indisponivel: acc.en_fonte_indisponivel + l.en_fonte_indisponivel,
        sets_com_divergencia_populacao: acc.sets_com_divergencia_populacao + (l.divergencia_populacao ? 1 : 0),
      }),
      {
        cards: 0,
        ptbr_existentes: 0, ptbr_importable: 0, ptbr_indisponivel: 0, ptbr_fonte_indisponivel: 0,
        en_existentes: 0, en_importable: 0, en_indisponivel: 0, en_fonte_indisponivel: 0,
        sets_com_divergencia_populacao: 0,
      },
    );
    const payload = {
      rodada: "CATALOG-HISTORICAL-BOOTSTRAP-03",
      fase: "ASSETS",
      modo: "DRY_RUN_RECONCILIACAO",
      executado_em: new Date().toISOString(),
      filtros: { only: args.only, expansion: args.expansion, limit: args.limit },
      universo: { card_sets_pokemon: todos.length, selecionados: universo.length },
      criterio:
        "IMPORTABLE_GAP = fonte publica a imagem e o banco nao tem. " +
        "NOT_AVAILABLE_AT_SOURCE = a fonte foi lida com sucesso e nao publica. " +
        "FONTE_INDISPONIVEL = a fonte nao pode ser lida (non-2xx apos retry ou excecao) — NAO e ausencia. " +
        "Comparacao fonte x banco por chave normalizada (chaveFonte). Somente TCGdex.",
      totais,
      resultados: linhas,
    };
    const arquivos = await gravarRelatorios("assets-dry_run", payload, linhas, COLUNAS_DRY_RUN);
    console.log(`[bootstrap-assets] totais: ${JSON.stringify(totais)}`);
    console.log(`[bootstrap-assets] relatorios: ${arquivos.json} / ${arquivos.csv}`);
    await supabase.auth.signOut();
    return payload;
  }

  const linhas = [];
  for (const [i, set] of universo.entries()) {
    console.log(`[${i + 1}/${universo.length}] ${set.card_set_code} (${set.expansion_code})`);
    const linha = await processarSetAssets({ supabase, supabaseUrl, accessToken, set });
    linhas.push(linha);
    for (const f of linha.fases) {
      console.log(
        `    ${f.idioma}: ${f.status} | cobertura ${f.cobertura_antes ?? "-"} -> ${f.cobertura_depois ?? "-"} ` +
        `(fonte=${f.disponiveis_na_fonte ?? "-"}; diag imported=${f.diag_importados ?? 0}/failed=${f.diag_falhos ?? 0})`,
      );
    }
  }

  const resumo = linhas.reduce((acc, l) => ({ ...acc, [l.status_final]: (acc[l.status_final] ?? 0) + 1 }), {});
  const payload = {
    rodada: "CATALOG-HISTORICAL-BOOTSTRAP-03",
    fase: "ASSETS",
    modo: "APPLY",
    executado_em: new Date().toISOString(),
    filtros: { only: args.only, expansion: args.expansion, limit: args.limit },
    universo: { card_sets_pokemon: todos.length, selecionados: universo.length },
    resumo,
    resultados: linhas,
  };
  const achatado = achatarApply(linhas);
  const arquivos = await gravarRelatorios("assets-apply", payload, achatado, COLUNAS_APPLY);
  console.log(`[bootstrap-assets] resumo: ${JSON.stringify(resumo)}`);
  console.log(`[bootstrap-assets] relatorios: ${arquivos.json} / ${arquivos.csv}`);
  await supabase.auth.signOut();
  return payload;
}

const executadoDiretamente = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (executadoDiretamente) {
  main().catch((erro) => {
    console.error(`[bootstrap-assets] ABORTADO: ${erro instanceof Error ? erro.message : String(erro)}`);
    process.exitCode = 1;
  });
}
