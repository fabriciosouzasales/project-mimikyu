/*
===============================================================================
Projeto.....: Project Mimikyu
Script......: run-bootstrap-cards.mjs
Rodada......: CATALOG-HISTORICAL-BOOTSTRAP-03-CARDS-ASSETS-STAGING-01
Status......: STAGING — NUNCA EXECUTADO (nem DRY_RUN real, nem APPLY)
Criado em...: 2026-09-10

Objetivo:
  Orquestrar a FASE CARDS do bootstrap historico para os 151 Card Sets sem
  Cards, reutilizando integralmente os contratos que ja existem. Este script
  NAO reimplementa nenhuma regra de negocio: ele so encadeia, por Set e em
  ordem estritamente sequencial, as mesmas chamadas que a UI faz.

  admin_start_catalog_import
    -> Edge Function import-catalog-cards
    -> job STAGED
    -> inspecao INTEGRAL das linhas de staging
    -> autoaprovacao SOMENTE se o Set inteiro estiver limpo
    -> admin_decide_catalog_import_row
    -> admin_confirm_catalog_import (lotes de 50, igual ao fluxo atual)
    -> resolve_card_primary_species_for_catalog_import_job (nao bloqueante)

  A fase de ASSETS vive em run-bootstrap-assets.mjs. Deliberadamente separada:
  perfis de falha, duracao e retry sao diferentes (a fase Cards e rapida e
  quase sempre passa de primeira; a de Assets e retry-pesada — 203 runs
  historicas para 46 Card Sets, ~4,4 por Set).

O QUE ESTE SCRIPT NAO FAZ (por decisao congelada da rodada):
  - nao importa Server Action do Next (nenhuma dependencia de web/app);
  - nao altera schema, migration, Edge Function ou frontend;
  - nao executa SQL direto de INSERT/UPDATE em card/catalog_import_*;
  - nao decide linha a linha: ou o Set inteiro esta limpo, ou nada e tocado.

Sobre service_role — precisao de terminologia:
  ESTE SCRIPT usa sessao admin real (signInWithPassword). Ele nao recebe,
  nao le e nao persiste service_role em nenhum ponto. Isso NAO significa que
  "o pipeline nunca usa service_role": a Edge Function import-catalog-cards
  pode usar service_role INTERNAMENTE, depois de validar o JWT recebido via
  auth.getUser() e confirmar o papel via rpc('is_admin'). Esse desenho e
  existente, correto e NAO e alterado nesta rodada.

MODO PADRAO = DRY_RUN. APPLY exige --apply explicito.

Uso:
  node run-bootstrap-cards.mjs                          # DRY_RUN dos 151
  node run-bootstrap-cards.mjs --only DET1,SM12,POP1    # DRY_RUN so dos 3
  node run-bootstrap-cards.mjs --only DET1 --apply      # APPLY de 1 Set
  node run-bootstrap-cards.mjs --expansion BW --apply   # APPLY de 1 Expansion
  node run-bootstrap-cards.mjs --limit 5                # corta o universo

Ambiente (obrigatorio, SOMENTE por environment — nunca por argumento):
  NEXT_PUBLIC_SUPABASE_URL
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  MMKYU_ADMIN_EMAIL
  MMKYU_ADMIN_PASSWORD

Seguranca:
  - login por usuario admin real (signInWithPassword), JWT do proprio admin
    repassado a Edge Function no header Authorization, exatamente como a UI faz;
  - is_admin() checado antes de QUALQUER escrita;
  - a senha nunca e impressa, nunca entra em relatorio, nunca vira argumento.
===============================================================================
*/

import { createClient } from "@supabase/supabase-js";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = path.join(__dirname, "manifest-cards.json");
const OUT_DIR = path.join(__dirname, "out");

/** Igual ao CONFIRM_CHUNK_SIZE da Server Action atual — recomendacao do proprio ADR-024. */
export const CONFIRM_CHUNK_SIZE = 50;
/** Lote de decisao. Nao existe teto documentado em admin_decide_catalog_import_row; usamos o mesmo 50 por simetria e previsibilidade. */
export const DECIDE_CHUNK_SIZE = 50;
/** Estados de job que NAO sao terminais — job nesses estados e retomavel. */
export const JOB_NAO_TERMINAIS = ["RECEIVED", "PROCESSING", "STAGED", "CONFIRMING"];
/** Universo esperado do manifest. Fail-fast antes de autenticar. */
export const UNIVERSO_ESPERADO = { total: 151, classe_A: 148, classe_B: 1, classe_C: 2 };

export const STATUS = {
  // --- estados de COBERTURA (derivados de current_card_count vs source_card_count) ---
  NO_CARDS_AT_SOURCE: "NO_CARDS_AT_SOURCE",
  PENDING_IMPORT: "PENDING_IMPORT",
  PARTIAL_SOURCE_IMPORT: "PARTIAL_SOURCE_IMPORT",
  ALREADY_SOURCE_COMPLETE: "ALREADY_SOURCE_COMPLETE",
  SOURCE_COMPLETE_WITH_DECLARED_MISMATCH: "SOURCE_COMPLETE_WITH_DECLARED_MISMATCH",
  REVIEW_REQUIRED_COUNT_EXCEEDS_SOURCE: "REVIEW_REQUIRED_COUNT_EXCEEDS_SOURCE",
  /**
   * RETIRADO em SM-PT-PARTIAL-RECOVERY-01 (2026-09-11). Deixou de ser
   * produzido: fonte pt parcial nao bloqueia mais a importacao, apenas
   * redefine o alvo (ver alvoDeCobertura). A chave e mantida para nao quebrar
   * a leitura de relatorios CSV/JSON gerados antes desta data.
   */
  REVIEW_REQUIRED_SOURCE_PARTIAL: "REVIEW_REQUIRED_SOURCE_PARTIAL",
  // --- estados de EXECUCAO ---
  REVIEW_REQUIRED: "REVIEW_REQUIRED",
  REVIEW_REQUIRED_CONFIRMATION_CONFLICT: "REVIEW_REQUIRED_CONFIRMATION_CONFLICT",
  COMPLETED_WITH_ERRORS: "COMPLETED_WITH_ERRORS",
  STALLED_CONFIRMATION: "STALLED_CONFIRMATION",
  READY: "READY",
  IMPORTED: "IMPORTED",
  NOTHING_TO_CONFIRM: "NOTHING_TO_CONFIRM",
  FAILED_START: "FAILED_START",
  FAILED_EDGE_FUNCTION: "FAILED_EDGE_FUNCTION",
  FAILED_NOT_STAGED: "FAILED_NOT_STAGED",
  FAILED_DECIDE: "FAILED_DECIDE",
  FAILED_CONFIRM: "FAILED_CONFIRM",
  FAILED_TERMINAL_JOB_WITH_FAILED_ROWS: "FAILED_TERMINAL_JOB_WITH_FAILED_ROWS",
  FAILED_UNEXPECTED: "FAILED_UNEXPECTED",
};

// ---------------------------------------------------------------------------
// Politica de autoaprovacao — funcao PURA, testavel sem banco.
// ---------------------------------------------------------------------------

/**
 * Decide se um Set pode seguir automaticamente, olhando TODAS as suas linhas.
 *
 * Estados seguros (e SOMENTE eles):
 *   - VALID   + NEW     + PENDING  -> elegivel para autoaprovacao;
 *   - VALID   + MATCHED + SKIPPED  -> elegivel para continuidade/reexecucao.
 *
 * Qualquer NEEDS_REVIEW, INVALID, CONFLICT, ou qualquer combinacao fora das
 * duas acima (inclusive combinacoes "inesperadas" que ainda nao existem hoje)
 * classifica o SET INTEIRO como REVIEW_REQUIRED: nenhuma linha e aprovada,
 * nenhuma confirmacao parcial acontece, e o script segue para o proximo Set.
 *
 * Linha ja persistida (INSERTED/UPDATED/UNCHANGED) nao invalida o Set — e o
 * caso normal de reexecucao. Linha com persistence_status FAILED invalida:
 * admin_confirm_catalog_import so olha PENDING e nenhuma funcao reseta esse
 * campo, entao insistir no mesmo job nunca resolveria.
 */
export function avaliarPoliticaAutoaprovacao(linhas) {
  const censo = {
    total: linhas.length,
    valid_new: 0,
    valid_matched: 0,
    needs_review: 0,
    invalid: 0,
    conflict: 0,
    outros: 0,
    ja_persistidas: 0,
    persistencia_falha: 0,
  };
  const aprovaveis = [];
  const motivos = new Set();

  for (const l of linhas) {
    const v = l.validation_status;
    const m = l.match_status;
    const d = l.decision_status;
    const p = l.persistence_status;

    if (v === "NEEDS_REVIEW") censo.needs_review += 1;
    if (v === "INVALID") censo.invalid += 1;
    if (m === "CONFLICT") censo.conflict += 1;
    if (p === "INSERTED" || p === "UPDATED" || p === "UNCHANGED") censo.ja_persistidas += 1;
    if (p === "FAILED") censo.persistencia_falha += 1;

    if (v === "VALID" && m === "NEW" && d === "PENDING") {
      censo.valid_new += 1;
      aprovaveis.push(l.id);
      continue;
    }
    if (v === "VALID" && m === "MATCHED" && d === "SKIPPED") {
      censo.valid_matched += 1;
      continue;
    }
    // Reexecucao: linha ja aprovada e ja persistida num APPLY anterior.
    if (v === "VALID" && d === "APPROVED" && (p === "INSERTED" || p === "UPDATED" || p === "UNCHANGED")) {
      censo.valid_new += 1;
      continue;
    }
    censo.outros += 1;
    motivos.add(`combinacao_inesperada:${v}/${m}/${d}/${p}`);
  }

  if (censo.needs_review > 0) motivos.add(`NEEDS_REVIEW=${censo.needs_review}`);
  if (censo.invalid > 0) motivos.add(`INVALID=${censo.invalid}`);
  if (censo.conflict > 0) motivos.add(`CONFLICT=${censo.conflict}`);
  if (censo.persistencia_falha > 0) motivos.add(`PERSISTENCE_FAILED=${censo.persistencia_falha}`);

  const limpo = motivos.size === 0;
  return {
    limpo,
    censo,
    aprovaveis: limpo ? aprovaveis : [],
    motivo: limpo ? null : Array.from(motivos).sort().join("; "),
  };
}

/**
 * Detecta o caso "fonte parcial em pt": o /pt existe e NAO esta vazio, mas
 * expoe MENOS cartas que o /en. O fallback da Edge Function so dispara em 404
 * ou lista vazia — entao esses Sets viriam incompletos e o fallback nao seria
 * acionado. Sao 3 excecoes historicas (SMP 240/248, SM1 163/172, SM4 124/125),
 * deficit total de 18 Cards. NAO justificam alterar a Edge Function.
 *
 * `pt === null`  -> /pt deu 404          -> fallback en, caminho normal.
 * `pt === 0`     -> /pt veio vazio       -> fallback en, caminho normal.
 * `0 < pt < en`  -> fonte parcial        -> alvo passa a ser o total pt.
 *
 * ATUALIZADO em SM-PT-PARTIAL-RECOVERY-01 (2026-09-11): este predicado deixou
 * de bloquear a importacao. Ele agora SELECIONA O ALVO (ver alvoDeCobertura).
 * Prova que motivou a mudanca: os 18 IDs de EN\PT foram sondados um a um em
 * `/pt/cards/{id}` e devolveram 18/18 HTTP 404 — as cartas nao existem em pt
 * na fonte, nao e ausencia apenas da listagem do Set. Logo o deficit e source
 * debt real e o alvo honesto para esses Sets e a populacao pt.
 */
export function fontePtParcial({ source_pt_card_count, source_card_count }) {
  return (
    typeof source_pt_card_count === "number" &&
    source_pt_card_count > 0 &&
    source_pt_card_count < source_card_count
  );
}

/**
 * ALVO de cobertura — quantas Cards este Set deve ter quando estiver completo.
 *
 * O alvo tem que ser coerente com o idioma que a Edge Function REALMENTE vai
 * importar, e nao com o idioma de maior populacao. A Edge usa pt sempre que
 * `/pt/sets/{id}` devolve lista nao vazia; so cai para en em 404 ou lista
 * vazia. Portanto, quando a fonte pt existe porem e menor que a en, o Set vai
 * ser importado em pt e o alvo honesto e o total pt — nunca o total en.
 *
 * Usar o total en como alvo nesses Sets produzia dois defeitos encadeados:
 * (1) nunca convergiam, ficando presos em REVIEW_REQUIRED_SOURCE_PARTIAL a
 * cada reexecucao; (2) sugeria que faltavam Cards importaveis quando o que
 * falta nao existe em pt na fonte.
 *
 * O deficit (en - pt) NAO desaparece: continua medido na coluna
 * `deficit_fonte_pt` do relatorio e explicitado no `motivo`, e o Set termina
 * como SOURCE_COMPLETE_WITH_DECLARED_MISMATCH — mesmo tratamento ja dado a
 * TK-SM-L. Divergencia declarada, dado NAO corrigido.
 *
 * NUNCA seleciona en para um Set cuja fonte pt e valida: o alvo menor e
 * exatamente o mecanismo que impede o fallback para en.
 *
 * CORRECTION-01: `idioma_previsto` e OBRIGATORIO na decisao. So `0 < pt < en`
 * nao basta — essa e uma condicao sobre a FONTE, nao sobre o idioma que sera
 * importado. Um Set de importacao en pode perfeitamente ter uma listagem pt
 * menor e nao vazia; nesse caso o alvo continua sendo o total en, porque e em
 * en que ele sera importado. Reduzir o alvo ali criaria um falso "completo"
 * (90/100) num Set que na verdade tem 100 cartas importaveis.
 *
 * `idioma_previsto` vem do manifest (campo por Set, presente nos 151) e e o
 * mesmo sinal ja usado pelo resto do fluxo — nenhuma fonte de dado nova.
 * Qualquer valor diferente de "pt" e tratado como en (fail-safe: na duvida,
 * alvo maior, que nunca conclui cedo demais).
 */
export function alvoDeCobertura({ idioma_previsto, source_card_count, source_pt_card_count }) {
  const importaEmPt = idioma_previsto === "pt";
  return importaEmPt && fontePtParcial({ source_pt_card_count, source_card_count })
    ? source_pt_card_count
    : source_card_count;
}

/**
 * Estado de COBERTURA de um Set — funcao pura, derivada do que a fonte expoe
 * (via `alvoDeCobertura`) contra o que o banco tem (`currentCardCount`).
 *
 * BLOCKER CORRIGIDO NESTA RODADA: a regra anterior era `cardsNoBanco > 0 =>
 * ALREADY_HAS_CARDS`, o que ESCONDIA um Set parcialmente persistido — 50 de
 * 100 Cards apareceria como "ja feito". O alvo passa a ser sempre
 * `source_card_count`, nunca `declared_total_set_size` e nunca "> 0".
 *
 * Precedencia (a ordem importa e e deliberada):
 *   A. banco ACIMA do alvo            -> REVIEW_REQUIRED_COUNT_EXCEEDS_SOURCE
 *   B. alvo sem cartas                -> NO_CARDS_AT_SOURCE
 *   C. banco IGUAL ao alvo            -> ALREADY_SOURCE_COMPLETE
 *                                        (ou ..._WITH_DECLARED_MISMATCH quando
 *                                         o alvo diverge do declarado, ex.
 *                                         TK-SM-L 18/30 e SM1 163/172)
 *   D. banco zerado                   -> PENDING_IMPORT
 *   E. banco entre 0 e o alvo         -> PARTIAL_SOURCE_IMPORT
 *
 * A vem PRIMEIRO (corrigido em CORRECTION-02): "banco acima da fonte" e o
 * sinal mais alarmante que existe e nunca pode ser mascarado por outro estado.
 * Em particular, `source = 0` com `current > 0` e um Set que tem Cards no banco
 * e nenhuma carta na fonte — isso e REVIEW_REQUIRED_COUNT_EXCEEDS_SOURCE, nao
 * NO_CARDS_AT_SOURCE. Quando B e alcancado, `current` e necessariamente 0.
 *
 * C vem antes de D/E porque e observacao terminal sobre o banco, sem escrita.
 *
 * SM-PT-PARTIAL-RECOVERY-01: o antigo gate "fonte parcial em pt ->
 * REVIEW_REQUIRED_SOURCE_PARTIAL, escrever=false" foi REMOVIDO. Ele impedia a
 * importacao inteira de SM1/SM4/SMP — e, por tabela, impedia tambem a criacao
 * do card_set_external_reference, que so nasce dentro de
 * admin_start_catalog_import. A parcialidade agora e tratada no ALVO, nao como
 * bloqueio: o Set importa a populacao pt disponivel e converge.
 */
export function decidirEstadoDeCobertura({
  currentCardCount,
  source_card_count,
  declared_total_set_size,
  source_pt_card_count,
  idioma_previsto,
}) {
  const alvo = alvoDeCobertura({ idioma_previsto, source_card_count, source_pt_card_count });
  // Derivado do alvo JA decidido, nao de um predicado paralelo: e verdadeiro
  // exatamente quando o alvo foi reduzido para a populacao pt. Impossivel
  // divergir de alvoDeCobertura por esquecimento futuro.
  const alvoReduzidoParaPt = alvo !== source_card_count;
  // Sufixo informativo — a divergencia pt<en nunca some do relatorio, mesmo
  // quando deixa de bloquear.
  const avisoPt = alvoReduzidoParaPt
    ? ` [fonte pt parcial: pt=${source_pt_card_count}, en=${source_card_count}, deficit=${source_card_count - source_pt_card_count} — importar pt, NUNCA en]`
    : "";

  if (currentCardCount > alvo) {
    return {
      estado: STATUS.REVIEW_REQUIRED_COUNT_EXCEEDS_SOURCE,
      escrever: false,
      alvo,
      motivo: `banco tem ${currentCardCount} Card(s) e a fonte expoe ${alvo} — nao escrever automaticamente`,
    };
  }
  if (alvo === 0) {
    // Neste ponto currentCardCount e necessariamente 0 (o caso > 0 saiu acima).
    return {
      estado: STATUS.NO_CARDS_AT_SOURCE,
      escrever: false,
      alvo,
      motivo: "fonte nao expoe nenhuma carta para este Set",
    };
  }
  if (currentCardCount === alvo) {
    const divergeDoDeclarado = alvo !== declared_total_set_size;
    return {
      estado: divergeDoDeclarado
        ? STATUS.SOURCE_COMPLETE_WITH_DECLARED_MISMATCH
        : STATUS.ALREADY_SOURCE_COMPLETE,
      escrever: false,
      alvo,
      motivo: divergeDoDeclarado
        ? `completo em relacao a fonte (${currentCardCount}/${alvo}), mas o declarado e ${declared_total_set_size} — divergencia mantida explicita, dado NAO corrigido${avisoPt}`
        : `completo em relacao a fonte (${currentCardCount}/${alvo})`,
    };
  }
  if (currentCardCount === 0) {
    return { estado: STATUS.PENDING_IMPORT, escrever: true, alvo, motivo: `0/${alvo} — importacao normal${avisoPt}` };
  }
  return {
    estado: STATUS.PARTIAL_SOURCE_IMPORT,
    escrever: true,
    alvo,
    motivo: `${currentCardCount}/${alvo} — parcial, NUNCA considerar concluido; inspecionar job anterior e abrir job novo quando necessario${avisoPt}`,
  };
}

/**
 * Decide o ponto de entrada para um Set. Funcao pura — nao toca no banco, so
 * classifica o que foi lido. Consome o estado de cobertura: se ele nao
 * autoriza escrita, o Set sai aqui, com o estado como status final.
 */
export function decidirPontoDeEntrada({ cobertura, jobAtivo, jobTerminalComFalha }) {
  if (!cobertura.escrever) {
    return { acao: "SKIP", status: cobertura.estado, motivo: cobertura.motivo };
  }
  if (jobAtivo) {
    if (jobAtivo.status === "RECEIVED") {
      return { acao: "INVOCAR_EDGE_FUNCTION", jobId: jobAtivo.id, motivo: "job existente ainda em RECEIVED" };
    }
    // STAGED e CONFIRMING sao fluxos DIFERENTES (corrigido em CORRECTION-02).
    // admin_decide_catalog_import_row() so aceita job STAGED;
    // admin_confirm_catalog_import() aceita STAGED ou CONFIRMING justamente
    // para retomar uma confirmacao interrompida. Agrupar os dois levaria o
    // script a tentar decidir linhas de um job em CONFIRMING.
    if (jobAtivo.status === "STAGED") {
      return { acao: "INSPECIONAR_LINHAS", jobId: jobAtivo.id, motivo: "job existente em STAGED — decisao editorial pendente" };
    }
    if (jobAtivo.status === "CONFIRMING") {
      return { acao: "RETOMAR_CONFIRMACAO", jobId: jobAtivo.id, motivo: "job existente em CONFIRMING — retomar confirmacao, NUNCA decidir linhas" };
    }
    // PROCESSING: outra execucao pode estar em andamento. Nunca concorrer.
    return { acao: "SKIP", status: STATUS.FAILED_UNEXPECTED, motivo: `job ${jobAtivo.id} em PROCESSING — nao concorrer` };
  }
  if (jobTerminalComFalha) {
    // Precedente real (2024sv, 2026-09-10): linha FAILED e terminal; a unica
    // saida e abrir um job NOVO. Isso e permitido e esperado.
    return { acao: "ABRIR_JOB", motivo: "job anterior terminou com linhas FAILED — abrir job novo" };
  }
  return { acao: "ABRIR_JOB", motivo: "nenhum job anterior" };
}

/** Teto de ciclos do laco STAGED/CONFIRMING. Protecao contra loop sem progresso. */
export const MAX_CICLOS_JOB = 6;

/**
 * GUARD DE CONFLITO SURGIDO DURANTE A CONFIRMACAO. Funcao pura.
 *
 * Contrato real de admin_confirm_catalog_import(): uma linha pode entrar na
 * confirmacao como VALID / NEW / APPROVED / PENDING e, ao recalcular contra o
 * catalogo real, descobrir um conflito NOVO. Nesse caso a RPC muda
 * match_status para CONFLICT, MANTEM decision_status = APPROVED, MANTEM
 * persistence_status = PENDING e mantem o job em CONFIRMING.
 *
 * Numa segunda chamada, a combinacao CONFLICT + APPROVED e indistinguivel de
 * "conflito revisado e aprovado por um humano" — e a RPC pode executar UPDATE.
 * Isso NAO e permitido no bootstrap automatico: a linha nunca foi revisada,
 * ela estava APPROVED de ANTES do conflito existir.
 *
 * Por isso: sempre que o job estiver em CONFIRMING, antes de QUALQUER nova
 * chamada a admin_confirm_catalog_import(), as linhas elegiveis sao relidas e
 * passam por este guard. Havendo conflito, o Set inteiro sai como
 * REVIEW_REQUIRED_CONFIRMATION_CONFLICT: nenhuma confirmacao adicional,
 * nenhuma alteracao de decision_status, nenhuma chamada a
 * admin_decide_catalog_import_row(). O estado e PRESERVADO exatamente como
 * esta, para revisao editorial explicita.
 *
 * O ramo STAGED nao precisa deste guard: qualquer CONFLICT encontrado na
 * inspecao integral ja torna o Set REVIEW_REQUIRED em
 * avaliarPoliticaAutoaprovacao(), antes de qualquer decisao.
 */
export function detectarConflitoDeConfirmacao(elegiveis) {
  const conflitos = (elegiveis ?? []).filter(
    (l) =>
      l.decision_status === "APPROVED" &&
      l.persistence_status === "PENDING" &&
      l.match_status === "CONFLICT",
  );
  return {
    temConflito: conflitos.length > 0,
    quantidade: conflitos.length,
    ids: conflitos.map((l) => l.id),
  };
}

/**
 * Decide o que fazer depois de uma rodada de admin_confirm_catalog_import(),
 * relendo o STATUS REAL do job. Funcao pura.
 *
 * COMPLETED             -> concluido.
 * COMPLETED_WITH_ERRORS -> concluido com falhas registradas; recuperacao
 *                          posterior por JOB NOVO, conforme a politica ja
 *                          existente (linha FAILED e terminal).
 * STAGED                -> ainda ha decisoes pendentes; so entao voltar ao
 *                          fluxo de inspecao + politica editorial.
 * CONFIRMING            -> confirmacao ainda pendente; continuar SOMENTE se
 *                          houve progresso seguro (o numero de linhas
 *                          elegiveis DIMINUIU) e o teto de ciclos nao estourou.
 *
 * `pendentesAntes`/`pendentesDepois` = linhas com persistence_status = PENDING
 * e decision_status IN (APPROVED, SKIPPED), medidas antes e depois da rodada.
 */
export function decidirAposConfirmacao({ statusJob, pendentesAntes, pendentesDepois, ciclo }) {
  if (statusJob === "COMPLETED") {
    return { acao: "CONCLUIR", status: STATUS.IMPORTED, motivo: "job COMPLETED" };
  }
  if (statusJob === "COMPLETED_WITH_ERRORS") {
    return {
      acao: "CONCLUIR",
      status: STATUS.COMPLETED_WITH_ERRORS,
      motivo: "job COMPLETED_WITH_ERRORS — falhas registradas; recuperacao posterior exige JOB NOVO",
    };
  }
  if (statusJob === "STAGED") {
    return { acao: "INSPECIONAR_LINHAS", motivo: "job voltou a STAGED — existem decisoes ainda pendentes" };
  }
  if (statusJob === "CONFIRMING") {
    if (ciclo >= MAX_CICLOS_JOB) {
      return {
        acao: "PARAR",
        status: STATUS.STALLED_CONFIRMATION,
        motivo: `job segue CONFIRMING apos ${ciclo} ciclo(s) — teto atingido, parando para evitar loop`,
      };
    }
    if (pendentesDepois === 0) {
      return {
        acao: "PARAR",
        status: STATUS.STALLED_CONFIRMATION,
        motivo: "job segue CONFIRMING mas nao ha mais linha elegivel a confirmar — sem progresso possivel",
      };
    }
    if (pendentesDepois >= pendentesAntes) {
      return {
        acao: "PARAR",
        status: STATUS.STALLED_CONFIRMATION,
        motivo: `sem progresso: elegiveis ${pendentesAntes} -> ${pendentesDepois}. Parando para evitar loop`,
      };
    }
    return { acao: "CONTINUAR_CONFIRMACAO", motivo: `progresso seguro: elegiveis ${pendentesAntes} -> ${pendentesDepois}` };
  }
  return {
    acao: "PARAR",
    status: STATUS.FAILED_UNEXPECTED,
    motivo: `job em estado terminal inesperado apos confirmacao: ${statusJob}`,
  };
}

// ---------------------------------------------------------------------------
// Infra
// ---------------------------------------------------------------------------

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
  if (args.expansion) out = out.filter((s) => args.expansion.includes(s.expansion_code.toUpperCase()));
  if (args.only) out = out.filter((s) => args.only.includes(s.card_set_code.toUpperCase()));
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

function chunk(items, size) {
  const out = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

// ---------------------------------------------------------------------------
// Leituras
// ---------------------------------------------------------------------------

async function contarCards(supabase, cardSetId) {
  const { count, error } = await supabase
    .from("card")
    .select("id", { count: "exact", head: true })
    .eq("card_set_id", cardSetId);
  if (error) throw new Error(`FALHA_CONTAR_CARDS: ${error.message}`);
  return count ?? 0;
}

async function buscarJobAtivo(supabase, cardSetId) {
  const { data, error } = await supabase
    .from("catalog_import_job")
    .select("id, status, external_set_id, total_rows, valid_rows")
    .eq("card_set_id", cardSetId)
    .eq("source", "TCGDEX")
    .in("status", JOB_NAO_TERMINAIS)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw new Error(`FALHA_BUSCAR_JOB_ATIVO: ${error.message}`);
  return data ?? null;
}

async function existeJobTerminalComLinhaFalha(supabase, cardSetId) {
  const { data, error } = await supabase
    .from("catalog_import_job")
    .select("id, failed_rows")
    .eq("card_set_id", cardSetId)
    .eq("source", "TCGDEX")
    .gt("failed_rows", 0)
    .limit(1);
  if (error) throw new Error(`FALHA_BUSCAR_JOB_COM_FALHA: ${error.message}`);
  return (data ?? []).length > 0;
}

/** Le TODAS as linhas do job, paginando — o censo precisa ser integral, nunca amostral. */
async function lerTodasAsLinhas(supabase, jobId) {
  const PAG = 500;
  const linhas = [];
  for (let offset = 0; ; offset += PAG) {
    const { data, error } = await supabase
      .from("catalog_import_row")
      .select("id, validation_status, match_status, decision_status, persistence_status, error_detail")
      .eq("job_id", jobId)
      .order("id", { ascending: true })
      .range(offset, offset + PAG - 1);
    if (error) throw new Error(`FALHA_LER_LINHAS: ${error.message}`);
    linhas.push(...(data ?? []));
    if ((data ?? []).length < PAG) break;
  }
  return linhas;
}

async function lerJob(supabase, jobId) {
  const { data, error } = await supabase
    .from("catalog_import_job")
    .select("id, status, total_rows, valid_rows, rejected_rows, inserted_rows, updated_rows, unchanged_rows, skipped_rows, failed_rows, error_summary")
    .eq("id", jobId)
    .maybeSingle();
  if (error) throw new Error(`FALHA_LER_JOB: ${error.message}`);
  return data ?? null;
}

// ---------------------------------------------------------------------------
// Escritas — todas via RPC/Edge Function existentes
// ---------------------------------------------------------------------------

/**
 * Linhas elegiveis a confirmacao: ja DECIDIDAS (APPROVED/SKIPPED) e ainda nao
 * persistidas. Mesmo criterio da Server Action. Serve tanto para o ramo STAGED
 * (depois de decidir) quanto para o CONFIRMING (onde nada foi decidido agora).
 */
async function contarElegiveis(supabase, jobId) {
  const { data, error } = await supabase
    .from("catalog_import_row")
    .select("id, match_status, decision_status, persistence_status")
    .eq("job_id", jobId)
    .eq("persistence_status", "PENDING")
    .in("decision_status", ["APPROVED", "SKIPPED"]);
  if (error) throw new Error(`FALHA_CONTAR_ELEGIVEIS: ${error.message}`);
  const linhas = data ?? [];
  // `linhas` carrega match_status para alimentar detectarConflitoDeConfirmacao().
  return { ids: linhas.map((r) => r.id), linhas };
}

/** admin_confirm_catalog_import() em lotes sequenciais, igual ao fluxo atual. */
async function confirmarEmLotes(supabase, jobId, ids) {
  const lotes = ids.length > 0 ? chunk(ids, CONFIRM_CHUNK_SIZE) : [null];
  let ultimo = null;
  for (const lote of lotes) {
    const { data, error } = await supabase.rpc("admin_confirm_catalog_import", {
      p_job_id: jobId,
      p_row_ids: lote,
    });
    if (error) return { erro: error.message, ultimo };
    const [row] = (data ?? []);
    if (row) ultimo = row;
  }
  return { erro: null, ultimo };
}

async function invocarImportCatalogCards(supabaseUrl, accessToken, jobId) {
  const url = `${supabaseUrl}/functions/v1/import-catalog-cards`;
  const resposta = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
    body: JSON.stringify({ job_id: jobId }),
  });
  const corpo = await resposta.json().catch(() => null);
  return { ok: resposta.ok, status: resposta.status, corpo };
}

async function esperarStaged(supabase, jobId, { tentativas = 40, intervaloMs = 3000 } = {}) {
  for (let i = 0; i < tentativas; i += 1) {
    const job = await lerJob(supabase, jobId);
    if (!job) throw new Error("JOB_SUMIU");
    if (job.status === "STAGED" || job.status === "CONFIRMING") return job;
    if (!JOB_NAO_TERMINAIS.includes(job.status)) return job; // terminal (FAILED/COMPLETED/...)
    await dormir(intervaloMs);
  }
  return await lerJob(supabase, jobId);
}

// ---------------------------------------------------------------------------
// Processamento de UM Set
// ---------------------------------------------------------------------------

async function processarSet({ supabase, supabaseUrl, accessToken, set, apply }) {
  const linha = {
    expansion_code: set.expansion_code,
    card_set_code: set.card_set_code,
    external_set_id: set.external_set_id,
    classe: set.classe,
    motivo_manifest: set.motivo,
    declared_total_set_size: set.declared_total_set_size,
    source_card_count: set.source_card_count,
    source_pt_card_count: set.source_pt_card_count,
    current_card_count: 0,
    target_card_count: set.source_card_count,
    deficit_fonte_pt: fontePtParcial(set) ? set.source_card_count - set.source_pt_card_count : 0,
    estado_cobertura: null,
    modo: apply ? "APPLY" : "DRY_RUN",
    estado_inicial: null,
    job_id: null,
    linhas_total: 0,
    valid_new: 0,
    matched: 0,
    needs_review: 0,
    invalid: 0,
    conflict: 0,
    approved: 0,
    inserted: 0,
    unchanged: 0,
    updated: 0,
    failed: 0,
    ciclos_job: 0,
    retomadas_confirmacao: 0,
    conflitos_na_confirmacao: 0,
    conflito_row_ids: null,
    status_final: null,
    motivo: null,
  };

  try {
    const cardsNoBanco = await contarCards(supabase, set.card_set_id);
    const jobAtivo = await buscarJobAtivo(supabase, set.card_set_id);
    const jobComFalha = await existeJobTerminalComLinhaFalha(supabase, set.card_set_id);
    linha.current_card_count = cardsNoBanco;

    const cobertura = decidirEstadoDeCobertura({
      currentCardCount: cardsNoBanco,
      source_card_count: set.source_card_count,
      declared_total_set_size: set.declared_total_set_size,
      source_pt_card_count: set.source_pt_card_count,
      // CORRECTION-01: idioma efetivo da importacao, direto do manifest.
      idioma_previsto: set.idioma_previsto,
    });
    linha.estado_cobertura = cobertura.estado;
    // Alvo REAL da rodada (pode ser o total pt quando a fonte pt e parcial).
    // A coluna source_card_count segue registrando o total en, e
    // deficit_fonte_pt segue registrando a diferenca — nada some do relatorio.
    linha.target_card_count = cobertura.alvo;
    linha.estado_inicial = `cards=${cardsNoBanco}/${cobertura.alvo}; cobertura=${cobertura.estado}; job_ativo=${jobAtivo ? jobAtivo.status : "nenhum"}; job_anterior_com_falha=${jobComFalha}`;

    const entrada = decidirPontoDeEntrada({
      cobertura,
      jobAtivo,
      jobTerminalComFalha: jobComFalha,
    });

    if (entrada.acao === "SKIP") {
      linha.status_final = entrada.status;
      linha.motivo = entrada.motivo;
      linha.job_id = jobAtivo?.id ?? null;
      return linha;
    }

    if (!apply) {
      linha.status_final = STATUS.READY;
      linha.motivo = `DRY_RUN: acao prevista = ${entrada.acao} (${entrada.motivo}); alvo ${cobertura.alvo} carta(s) na fonte`;
      linha.job_id = entrada.jobId ?? null;
      return linha;
    }

    // ---------------- APPLY ----------------
    let jobId = entrada.jobId ?? null;

    if (entrada.acao === "ABRIR_JOB") {
      const { data, error } = await supabase.rpc("admin_start_catalog_import", {
        p_card_set_id: set.card_set_id,
        p_source: "TCGDEX",
        p_external_set_id: set.external_set_id,
      });
      if (error) {
        linha.status_final = STATUS.FAILED_START;
        linha.motivo = error.message;
        return linha;
      }
      jobId = String(data);
    }

    linha.job_id = jobId;

    if (entrada.acao === "ABRIR_JOB" || entrada.acao === "INVOCAR_EDGE_FUNCTION") {
      const r = await invocarImportCatalogCards(supabaseUrl, accessToken, jobId);
      if (!r.ok) {
        linha.status_final = STATUS.FAILED_EDGE_FUNCTION;
        linha.motivo = `HTTP ${r.status}: ${r.corpo?.error ?? "sem corpo"}`;
        return linha;
      }
    }

    if (entrada.acao === "ABRIR_JOB" || entrada.acao === "INVOCAR_EDGE_FUNCTION") {
      const job = await esperarStaged(supabase, jobId);
      if (!job || (job.status !== "STAGED" && job.status !== "CONFIRMING")) {
        linha.status_final = STATUS.FAILED_NOT_STAGED;
        linha.motivo = `job terminou em ${job?.status ?? "desconhecido"}: ${job?.error_summary ?? ""}`;
        return linha;
      }
    }

    // ---------------------------------------------------------------------
    // Laco dirigido pelo STATUS REAL do job. STAGED e CONFIRMING sao ramos
    // distintos e NUNCA se misturam: decision so acontece no ramo STAGED.
    // ---------------------------------------------------------------------
    let houveConfirmacao = false;
    let pendentesAnterior = Number.POSITIVE_INFINITY;

    for (let ciclo = 1; ciclo <= MAX_CICLOS_JOB; ciclo += 1) {
      const job = await lerJob(supabase, jobId);
      if (!job) {
        linha.status_final = STATUS.FAILED_UNEXPECTED;
        linha.motivo = "job desapareceu durante o processamento";
        return linha;
      }
      let ramo = null;

      if (job.status === "STAGED") {
        // ---- RAMO STAGED: inspecao integral + politica + decide + confirm ----
        const linhasStaging = await lerTodasAsLinhas(supabase, jobId);
        const politica = avaliarPoliticaAutoaprovacao(linhasStaging);

        linha.linhas_total = politica.censo.total;
        linha.valid_new = politica.censo.valid_new;
        linha.matched = politica.censo.valid_matched;
        linha.needs_review = politica.censo.needs_review;
        linha.invalid = politica.censo.invalid;
        linha.conflict = politica.censo.conflict;

        if (!politica.limpo) {
          linha.status_final = STATUS.REVIEW_REQUIRED;
          linha.motivo = politica.motivo;
          return linha;
        }

        // admin_decide_catalog_import_row() SO e chamada aqui — o contrato da
        // RPC exige job STAGED, e alterar decision_status com o job em
        // CONFIRMING seria mexer numa confirmacao em andamento.
        if (politica.aprovaveis.length > 0) {
          for (const lote of chunk(politica.aprovaveis, DECIDE_CHUNK_SIZE)) {
            const { error } = await supabase.rpc("admin_decide_catalog_import_row", {
              p_row_ids: lote,
              p_decision_status: "APPROVED",
            });
            if (error) {
              linha.status_final = STATUS.FAILED_DECIDE;
              linha.motivo = error.message;
              return linha;
            }
            linha.approved += lote.length;
          }
        }
      } else if (job.status === "CONFIRMING") {
        // ---- RAMO CONFIRMING: NUNCA decide. So retoma a confirmacao. ----
        linha.retomadas_confirmacao += 1;
        ramo = "CONFIRMING";
      } else {
        // Estado terminal alcancado sem passar por confirmacao nesta rodada.
        const fim = decidirAposConfirmacao({
          statusJob: job.status,
          pendentesAntes: pendentesAnterior,
          pendentesDepois: 0,
          ciclo,
        });
        linha.status_final = fim.status ?? STATUS.FAILED_UNEXPECTED;
        linha.motivo = fim.motivo;
        return linha;
      }

      // ---- Confirmacao (comum aos dois ramos) ----
      const elegiveisAntes = await contarElegiveis(supabase, jobId);

      // GUARD: conflito surgido DURANTE a confirmacao. Roda no ramo CONFIRMING
      // SEMPRE, e antes de qualquer nova chamada a admin_confirm_catalog_import().
      // Cobre os dois caminhos: o Set que ja ENTROU com o job em CONFIRMING, e o
      // Set cujo job PERMANECEU em CONFIRMING depois de uma rodada — porque o
      // proximo ciclo do laco relê o job, cai neste mesmo ramo e relê as linhas.
      if (ramo === "CONFIRMING") {
        const conflito = detectarConflitoDeConfirmacao(elegiveisAntes.linhas);
        if (conflito.temConflito) {
          linha.conflitos_na_confirmacao = conflito.quantidade;
          linha.conflito_row_ids = conflito.ids.slice(0, 10).join(" ");
          linha.status_final = STATUS.REVIEW_REQUIRED_CONFIRMATION_CONFLICT;
          linha.motivo =
            `${conflito.quantidade} linha(s) APPROVED + PENDING + CONFLICT no job em CONFIRMING — ` +
            "conflito surgido DURANTE a confirmacao. Nenhuma confirmacao adicional, nenhuma decisao alterada; " +
            "estado preservado para revisao editorial explicita.";
          return linha;
        }
      }

      const r = await confirmarEmLotes(supabase, jobId, elegiveisAntes.ids);
      if (r.erro) {
        linha.status_final = STATUS.FAILED_CONFIRM;
        linha.motivo = r.erro;
        return linha;
      }
      houveConfirmacao = true;
      if (r.ultimo) {
        linha.inserted = r.ultimo.inserted_count ?? 0;
        linha.updated = r.ultimo.updated_count ?? 0;
        linha.unchanged = r.ultimo.unchanged_count ?? 0;
        linha.failed = r.ultimo.failed_count ?? 0;
      }

      // ---- Relemos o job e decidimos o proximo passo ----
      const jobDepois = await lerJob(supabase, jobId);
      const elegiveisDepois = await contarElegiveis(supabase, jobId);
      const proximo = decidirAposConfirmacao({
        statusJob: jobDepois?.status ?? "DESCONHECIDO",
        pendentesAntes: elegiveisAntes.ids.length,
        pendentesDepois: elegiveisDepois.ids.length,
        ciclo,
      });
      linha.ciclos_job = ciclo;

      if (proximo.acao === "CONCLUIR" || proximo.acao === "PARAR") {
        // Fatia C — Primary Species. Mesmo contrato da Server Action: uma
        // unica chamada, fora do laco de lotes, em transacao propria; falha
        // aqui e so registrada e nunca desfaz a confirmacao ja persistida.
        if (houveConfirmacao) {
          const { error: erroSpecies } = await supabase.rpc(
            "resolve_card_primary_species_for_catalog_import_job",
            { p_job_id: jobId },
          );
          if (erroSpecies) {
            linha.motivo = `primary_species falhou (nao bloqueante): ${erroSpecies.message}`;
          }
        }
        const semNada = elegiveisAntes.ids.length === 0 && linha.inserted === 0 && proximo.acao === "CONCLUIR";
        linha.status_final = semNada ? STATUS.NOTHING_TO_CONFIRM : (proximo.status ?? STATUS.IMPORTED);
        linha.motivo = linha.motivo ?? proximo.motivo;
        return linha;
      }
      // CONTINUAR_CONFIRMACAO ou INSPECIONAR_LINHAS: proximo ciclo do laco.
      pendentesAnterior = elegiveisDepois.ids.length;
    }

    linha.status_final = STATUS.STALLED_CONFIRMATION;
    linha.motivo = `teto de ${MAX_CICLOS_JOB} ciclos atingido sem estado terminal`;
    return linha;
  } catch (erro) {
    linha.status_final = STATUS.FAILED_UNEXPECTED;
    linha.motivo = erro instanceof Error ? erro.message : String(erro);
    return linha;
  }
}

// ---------------------------------------------------------------------------
// Relatorios
// ---------------------------------------------------------------------------

const COLUNAS_CSV = [
  "expansion_code", "card_set_code", "external_set_id", "classe", "motivo_manifest",
  "declared_total_set_size", "source_card_count", "source_pt_card_count",
  "current_card_count", "target_card_count", "deficit_fonte_pt", "estado_cobertura",
  "modo", "estado_inicial", "job_id",
  "linhas_total", "valid_new", "matched", "needs_review", "invalid", "conflict",
  "approved", "inserted", "unchanged", "updated", "failed",
  "ciclos_job", "retomadas_confirmacao", "conflitos_na_confirmacao", "conflito_row_ids",
  "status_final", "motivo",
];

export function paraCsv(linhas, colunas = COLUNAS_CSV) {
  const esc = (v) => {
    if (v === null || v === undefined) return "";
    const s = String(v);
    return /[",\n;]/.test(s) ? `"${s.replaceAll('"', '""')}"` : s;
  };
  return [colunas.join(","), ...linhas.map((l) => colunas.map((c) => esc(l[c])).join(","))].join("\n");
}

async function gravarRelatorios(nome, payload, linhas) {
  await mkdir(OUT_DIR, { recursive: true });
  const carimbo = new Date().toISOString().replaceAll(":", "-").replaceAll(".", "-");
  const base = path.join(OUT_DIR, `${nome}-${carimbo}`);
  await writeFile(`${base}.json`, JSON.stringify(payload, null, 2), "utf8");
  await writeFile(`${base}.csv`, paraCsv(linhas), "utf8");
  return { json: `${base}.json`, csv: `${base}.csv` };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

export async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const manifest = JSON.parse(await readFile(MANIFEST_PATH, "utf8"));

  // Fail-fast de universo ANTES de autenticar e ANTES de qualquer escrita.
  const porClasse = manifest.sets.reduce((acc, s) => ({ ...acc, [s.classe]: (acc[s.classe] ?? 0) + 1 }), {});
  if (
    manifest.sets.length !== UNIVERSO_ESPERADO.total ||
    (porClasse.A ?? 0) !== UNIVERSO_ESPERADO.classe_A ||
    (porClasse.B ?? 0) !== UNIVERSO_ESPERADO.classe_B ||
    (porClasse.C ?? 0) !== UNIVERSO_ESPERADO.classe_C
  ) {
    throw new Error(
      `UNIVERSO_DIVERGENTE: manifest tem ${manifest.sets.length} Sets (A=${porClasse.A ?? 0}, B=${porClasse.B ?? 0}, C=${porClasse.C ?? 0}); esperado ${JSON.stringify(UNIVERSO_ESPERADO)}.`,
    );
  }

  const universo = filtrarUniverso(manifest.sets, args);
  if (universo.length === 0) throw new Error("FILTRO_VAZIO: nenhum Set selecionado.");

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

  console.log(`[bootstrap-cards] modo=${args.apply ? "APPLY" : "DRY_RUN"} sets=${universo.length}/${manifest.sets.length}`);

  const linhas = [];
  for (const [i, set] of universo.entries()) {
    console.log(`[${i + 1}/${universo.length}] ${set.card_set_code} (${set.expansion_code}) classe=${set.classe}`);
    const linha = await processarSet({ supabase, supabaseUrl, accessToken, set, apply: args.apply });
    linhas.push(linha);
    console.log(`    -> ${linha.status_final}${linha.motivo ? ` (${linha.motivo})` : ""}`);
  }

  const resumo = linhas.reduce((acc, l) => ({ ...acc, [l.status_final]: (acc[l.status_final] ?? 0) + 1 }), {});
  const resumo_cobertura = linhas.reduce((acc, l) => ({ ...acc, [l.estado_cobertura]: (acc[l.estado_cobertura] ?? 0) + 1 }), {});
  const payload = {
    rodada: "CATALOG-HISTORICAL-BOOTSTRAP-03",
    fase: "CARDS",
    modo: args.apply ? "APPLY" : "DRY_RUN",
    executado_em: new Date().toISOString(),
    filtros: { only: args.only, expansion: args.expansion, limit: args.limit },
    universo: { manifest: manifest.sets.length, selecionados: universo.length },
    resumo,
    resumo_cobertura,
    totais: {
      inserted: linhas.reduce((s, l) => s + (l.inserted ?? 0), 0),
      unchanged: linhas.reduce((s, l) => s + (l.unchanged ?? 0), 0),
      failed: linhas.reduce((s, l) => s + (l.failed ?? 0), 0),
      approved: linhas.reduce((s, l) => s + (l.approved ?? 0), 0),
    },
    resultados: linhas,
  };

  const arquivos = await gravarRelatorios(`cards-${args.apply ? "apply" : "dry_run"}`, payload, linhas);
  console.log(`[bootstrap-cards] resumo: ${JSON.stringify(resumo)}`);
  console.log(`[bootstrap-cards] cobertura: ${JSON.stringify(resumo_cobertura)}`);
  console.log(`[bootstrap-cards] relatorios: ${arquivos.json} / ${arquivos.csv}`);
  await supabase.auth.signOut();
  return payload;
}

const executadoDiretamente = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (executadoDiretamente) {
  main().catch((erro) => {
    console.error(`[bootstrap-cards] ABORTADO: ${erro instanceof Error ? erro.message : String(erro)}`);
    process.exitCode = 1;
  });
}
