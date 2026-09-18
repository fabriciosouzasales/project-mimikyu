/* ============================================================================
Project Mimikyu — BULK-STAGING-01 — Runner autenticado (DevTools)
Arquivo......: database/proposals/2026-09-18-bulk-staging-01/bulk-staging-runner.js
Versão.......: 1.0
Status.......: PROPOSTA — NÃO EXECUTADO
Criado em....: 2026-09-18, em `BULK-STAGING-01 / IMPLEMENTATION-01`
Autoridade...: MODELING-AUDIT-02 (CLOSED/APPROVED) + B13 OPÇÃO D

OBJETIVO
  Stagear em massa os Card Sets históricos elegíveis para Variant Import, sem
  trabalho manual Set por Set. Este runner NÃO aprova linhas, NÃO confirma
  jobs e NÃO materializa Card Variant — ele apenas provoca o staging.

O QUE ELE É
  Snippet descartável, colado UMA vez no console do DevTools, que morre com o
  refresh da página. Não é frontend permanente, não cria tabela de
  orquestração, não cria RPC, não roda SQL.

COMO EXECUTAR
  1. Fazer login na aplicação como ADMINISTRADOR REAL.
  2. Abrir qualquer página autenticada (ex.: /catalogo/importar-variantes).
  3. Abrir o DevTools (F12) → aba Console.
  4. Preencher PROJECT_REF e ANON_KEY abaixo.
  5. Colar este arquivo inteiro e pressionar Enter.
  6. MANTER A ABA VISÍVEL E EM FOCO durante toda a execução (ver §SESSÃO).

NOTA DE SEGURANÇA
  ANON_KEY é a publishable/anon key — PÚBLICA POR DESENHO, já exposta ao
  browser pelo próprio app (`NEXT_PUBLIC_SUPABASE_ANON_KEY`). Não é segredo.
  O que É segredo — o access_token da sessão — nunca é armazenado, nunca é
  impresso e nunca sai do escopo da chamada que o usa.

  NÃO usa service_role. NÃO fabrica JWT. NÃO usa SET ROLE. NÃO grava
  localStorage/sessionStorage/cookie. NÃO cria segredo novo.

============================================================================
§ SESSÃO / VISIBILITY  (contrato fechado em MODELING-AUDIT-02)
============================================================================
  - O access_token é RELIDO do cookie antes de CADA request. Nunca é
    congelado em variável de módulo, nunca é passado entre ciclos.
  - O `SessionRefresher` da aplicação (web/components/auth/session-refresher.tsx)
    só renova o token com a ABA ATIVA, e o middleware de refresh está órfão
    desde 2026-08-14. Numa campanha de ~3 h, aba em background = token
    expirado = 401 no meio. Por isso o runner PAUSA enquanto
    `document.visibilityState !== "visible"` e retoma sozinho ao voltar.
  - Sessão ausente/ilegível, 401 real ou 403 not-admin → ABORT fail-closed.
  - Este runner NÃO implementa refresh próprio — o SessionRefresher existente
    satisfaz o requisito com a aba visível.

============================================================================
§ B13 — OPÇÃO D  (fronteira fechada preservada)
============================================================================
  `card_set_external_reference` NÃO é legível por `authenticated`: zero GRANT
  SELECT, zero policy. Essa fronteira é DELIBERADA e este runner a PRESERVA —
  não lê a tabela, não pede grant, não cria policy, não cria RPC.

  A AUTORIDADE CANÔNICA do `external_set_id` continua sendo
  `card_set_external_reference`, lida INTERNAMENTE pela Edge no momento da
  invocação (`findCardSetExternalReference`, service_role).

  O runner usa `catalog_import_job.external_set_id` apenas como
  SNAPSHOT/PROXY OPERACIONAL — nunca como autoridade. Serve só para o guard
  fail-closed de divergência. Regra, por Set:
     - exatamente 1 external_set_id TCGDEX histórico distinto → segue;
     - 0 ou >1 distintos                                       → BLOCKED;
     - job Variant ativo com external_set_id ≠ proxy            → BLOCKED.

  CAMPAIGN FREEZE (pré-condição operacional, fora do runner): durante a
  campanha, nenhum remapeamento de `card_set_external_reference`, nenhuma
  operação privilegiada DELETE+INSERT nessa tabela, nenhuma campanha
  concorrente de remapeamento. O fechamento terá postcheck READ-ONLY externo.

============================================================================
§ CONTRATOS PRESERVADOS
============================================================================
  - somente REST/PostgREST existente — zero SQL ad hoc, zero RPC nova;
  - leituras BULK paginadas fail-closed — zero N+1 por Set;
  - INITIAL_BASELINE_GATE separado de RESUME_GATE;
  - pacing 65 s entre invocações reais;
  - rate limit (403/429) → cooldown 65 min; 2º rate limit após cooldown → ABORT;
  - retry transitório: 1ª → 30 s, 2ª → 120 s, 3ª → FAILED_PERMANENT;
  - classificação de erro por ALLOWLIST; desconhecido → BLOCKED fail-closed;
  - 409 → re-PLAN do Set, nunca SKIP cego;
  - RECEIVED/PROCESSING → ACTIVE_WAIT; 5 min sem avanço de updated_at → BLOCKED;
  - EX5.5 nunca reinvocado/confirmado/rejeitado/excluído;
  - NENHUMA chamada a admin_decide_catalog_variant_import_row nem a
    admin_confirm_catalog_variant_import — proibição ESTRUTURAL: os nomes não
    existem neste arquivo fora deste comentário.

============================================================================ */

(async () => {
  "use strict";

  // ==========================================================================
  // CONFIG — preencher antes de executar
  // ==========================================================================

  const PROJECT_REF = "COLE_AQUI_O_PROJECT_REF";          // ex.: qjfutqujxrbzgrtkpgkg
  const ANON_KEY    = "COLE_AQUI_A_NEXT_PUBLIC_SUPABASE_ANON_KEY";

  /** SAFE DEFAULT. `true` = nenhuma invocação real; só PLAN + relatório. */
  const DRY_RUN = true;

  /** SAFE DEFAULT. "CANARY" = só os 3 maiores Sets, para e relata. */
  const RUN_MODE = "CANARY";                               // "CANARY" | "FULL"

  // --- Constantes do contrato (não alterar sem novo mandato) ----------------

  // Lote histórico da CANARY de 2026-09-18. SM12 permanece aqui como REGISTRO
  // do que foi executado — mas hoje é DEFERRED (fonte ABSENT) e o filtro de
  // cobertura o remove da fila antes de qualquer invocação.
  const CANARY_SET_CODES   = ["SV2", "SM12", "SV4"];       // 279 · 271 · 266 Cards
  const EXCLUDED_SET_CODES = ["ME5.5"];                    // fora do denominador
  const EXPECTED_ELIGIBLE  = 169;
  const EXPECTED_TARGET    = 113;
  const EXPECTED_DEFERRED  = 56;

  // ==========================================================================
  // MANIFESTO DE COBERTURA DE FONTE (SOURCE-VARIANT-SAFETY-01, 2026-09-18)
  //
  // Congelado a partir de SOURCE-VARIANT-SCHEMA-COVERAGE-AUDIT-01 e da
  // decisão de escopo de Fabrício: o FULL processa SOMENTE os 113 Sets
  // ARRAY_SUPPORTED puros. MIXED entra em DEFERRED junto com ABSENT e
  // OBJECT_BOOLEAN — um Set parcialmente extraível produziria staging
  // incompleto que ninguém conseguiria distinguir de staging completo.
  //
  //   TARGET   113 · ARRAY_SUPPORTED puro · 10.301 Cards · ~18.915 rows
  //   DEFERRED  56 =  8 MIXED (ARRAY + ABSENT no mesmo Set)
  //                + 46 ABSENT (fonte não declara variante)
  //                +  2 OBJECT_BOOLEAN (SWSH1, SWSH3.5 — sem foil/subtype)
  //
  // Evidência auditável: ./source-variant-coverage-169.md (classificação
  // Set a Set, com o discriminador e a validação contra a CANARY LIVE).
  //
  // Estas listas são PARTIÇÃO EXATA dos 169 elegíveis. `assertManifest()`
  // prova isso a cada execução, antes de qualquer invocação.
  // ==========================================================================

  /** 113 Sets ARRAY_SUPPORTED puros — único universo invocável no FULL. */
  const TARGET_SET_CODES = Object.freeze([
    "2011BW", "2012BW", "2014XY", "2015XY", "2016XY", "2017SM", "2018SM", "2019SM",
    "2021SWSH", "2022SWSH", "2023SV", "2024SV", "BASE2", "BASE4", "BASE5", "BOG",
    "CEL25", "COL1", "DP1", "DP2", "DP3", "DP4", "DP5", "DP6",
    "DP7", "DPP", "ECARD1", "ECARD2", "ECARD3", "EX1", "EX10", "EX11",
    "EX12", "EX13", "EX14", "EX15", "EX16", "EX2", "EX3", "EX4",
    "EX5", "EX5.5", "EX6", "EX7", "EX8", "EX9", "FUT2020", "GYM1",
    "GYM2", "HGSS1", "HGSS2", "HGSS3", "HGSS4", "HGSSP", "LC", "MFB",
    "NEO1", "NEO2", "NEO3", "NEO4", "NP", "PL1", "PL2", "PL3",
    "PL4", "POP1", "POP2", "POP3", "POP4", "POP5", "POP6", "POP7",
    "POP8", "POP9", "RU1", "SI1", "SM3", "SMP", "SV1", "SV2",
    "SV3", "SV4", "SV4.5", "SWSH10", "SWSH10.5", "SWSH10TG", "SWSH11", "SWSH11TG",
    "SWSH12", "SWSH12.5", "SWSH12.5GG", "SWSH12TG", "SWSH2", "SWSH3", "SWSH4", "SWSH4.5",
    "SWSH4.5SV", "SWSH5", "SWSH6", "SWSH7", "SWSH9", "SWSH9TG", "TK-BW-E", "TK-BW-Z",
    "TK-DP-L", "TK-DP-M", "TK-EX-LATIA", "TK-EX-LATIO", "TK-EX-M", "TK-EX-P", "TK-HS-R", "TK-SM-L",
    "TK-SM-R",
  ]);

  /** 56 Sets fora do FULL, com o motivo canônico de cada um. */
  const DEFERRED_SET_REASON = Object.freeze({
    // --- 8 MIXED: ARRAY e ABSENT convivendo no mesmo Set --------------------
    "BW10": "MIXED", "BW3": "MIXED", "BW5": "MIXED", "SM10": "MIXED",
    "SM11": "MIXED", "SM6": "MIXED", "SM9": "MIXED", "TK-HS-G": "MIXED",
    // --- 46 ABSENT: a fonte não declara variante ----------------------------
    "BW1": "ABSENT", "BW11": "ABSENT", "BW2": "ABSENT", "BW4": "ABSENT",
    "BW6": "ABSENT", "BW7": "ABSENT", "BW8": "ABSENT", "BW9": "ABSENT",
    "BWP": "ABSENT", "DC1": "ABSENT", "DET1": "ABSENT", "DV1": "ABSENT",
    "G1": "ABSENT", "SM1": "ABSENT", "SM115": "ABSENT", "SM12": "ABSENT",
    "SM2": "ABSENT", "SM3.5": "ABSENT", "SM4": "ABSENT", "SM5": "ABSENT",
    "SM7": "ABSENT", "SM7.5": "ABSENT", "SM8": "ABSENT", "SMA": "ABSENT",
    "TK-XY-B": "ABSENT", "TK-XY-LATIA": "ABSENT", "TK-XY-LATIO": "ABSENT", "TK-XY-N": "ABSENT",
    "TK-XY-P": "ABSENT", "TK-XY-SU": "ABSENT", "TK-XY-SY": "ABSENT", "TK-XY-W": "ABSENT",
    "XY0": "ABSENT", "XY1": "ABSENT", "XY10": "ABSENT", "XY11": "ABSENT",
    "XY12": "ABSENT", "XY2": "ABSENT", "XY3": "ABSENT", "XY4": "ABSENT",
    "XY5": "ABSENT", "XY6": "ABSENT", "XY7": "ABSENT", "XY8": "ABSENT",
    "XY9": "ABSENT", "XYP": "ABSENT",
    // --- 2 OBJECT_BOOLEAN: sem foil/subtype, size fixo em "standard" --------
    "SWSH1": "OBJECT_BOOLEAN", "SWSH3.5": "OBJECT_BOOLEAN",
  });

  const TARGET_SET = new Set(TARGET_SET_CODES);
  const isTarget = (code) => TARGET_SET.has(code);

  const PACE_MS            = 65_000;                       // entre invocações reais
  const COOLDOWN_MS        = 65 * 60_000;                  // rate limit
  const BACKOFF_MS         = [30_000, 120_000];            // 1ª e 2ª transitória
  const MAX_TRANSIENT      = 3;                            // 3ª → FAILED_PERMANENT
  const MAX_RATE_LIMIT     = 2;                            // 2ª após cooldown → ABORT
  const ACTIVE_STALL_MS    = 5 * 60_000;                   // sem avanço de updated_at
  const PAGE_SIZE          = 1000;
  const MAX_PAGES          = 50;                           // fail-closed
  const VISIBILITY_POLL_MS = 1000;

  const REST_BASE = `https://${PROJECT_REF}.supabase.co/rest/v1`;
  const EDGE_URL  = `https://${PROJECT_REF}.supabase.co/functions/v1/import-card-variants`;

  const ACTIVE_STATUSES = ["RECEIVED", "PROCESSING", "STAGED", "CONFIRMING"];

  // ==========================================================================
  // ALLOWLIST DE ERROS — fechada. Desconhecido NUNCA é assumido transitório.
  // ==========================================================================

  const ERR_RATE_LIMIT = new Set([
    "GITHUB_CONTENTS_HTTP_403",
    "GITHUB_CONTENTS_HTTP_429",
  ]);

  /**
   * TRANSITÓRIAS — e SOMENTE as que a Edge persistiu em um job `FAILED`.
   *
   * `NETWORK_ERROR_NO_RESPONSE` foi REMOVIDO desta lista de propósito
   * (CORRECTION-01): um `fetch` do browser pode falhar ANTES de a request
   * chegar à Edge, e nesse caso NÃO existe job `FAILED` no banco para
   * reconstruir a tentativa depois de um refresh. Contá-lo aqui criaria um
   * retry budget que só existe em memória — exatamente o que o contrato de
   * resumabilidade proíbe. Erro de transporte tem caminho próprio: re-PLAN
   * pontual e, sem evidência durável nova, ABORT. Ver `invokeSet` e o
   * tratamento de `NO_RESPONSE` no laço principal.
   */
  const ERR_TRANSIENT = new Set([
    "GITHUB_CONTENTS_TIMEOUT",
    "TCGDEX_SET_METADATA_TIMEOUT",
    "TCGDEX_SET_METADATA_HTTP_500",
    "TCGDEX_SET_METADATA_HTTP_502",
    "TCGDEX_SET_METADATA_HTTP_503",
    "TCGDEX_SET_METADATA_HTTP_504",
    // SOURCE-VARIANT-SAFETY-01/CORRECTION-01 — falha de fetch de arquivo de
    // Card CORRELACIONADA. TRANSITÓRIA e legítima nesta lista porque a Edge
    // a PERSISTE em um job `FAILED`: o token é reconstruível do banco depois
    // de qualquer refresh, e o retry budget (30 s → 120 s → terminal na 3ª)
    // sai de `s.failedJobs`, nunca de memória. É exatamente o contraste com
    // `NETWORK_ERROR_NO_RESPONSE`, que continua FORA de todas as listas
    // justamente por NÃO deixar job algum no banco.
    "VARIANT_SOURCE_FETCH_FAILED_FOR_CORRELATED_CARDS",
  ]);

  const ERR_PERMANENT = new Set([
    "CARD_SET_NOT_FOUND",
    "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND",
    "GITHUB_SOURCE_SET_FOLDER_EMPTY_OR_NOT_FOUND",
    "GITHUB_CONTENTS_HTTP_404",
    "GITHUB_CONTENTS_UNEXPECTED_SHAPE",
    "TCGDEX_SET_METADATA_INCOMPLETE",
    // SOURCE-VARIANT-SAFETY-01: o guard de cobertura da Edge. PERMANENTE por
    // natureza — nenhuma retentativa muda o shape do arquivo-fonte. Entra
    // aqui no MESMO ciclo em que o guard é criado, deliberadamente: sem esta
    // linha o erro seria UNKNOWN → BLOCKED → GATE_BLOCKED, e um único Set
    // sem cobertura travaria a campanha inteira em vez de ser registrado.
    "VARIANT_SOURCE_UNSUPPORTED_FOR_CORRELATED_CARDS",
    // CORRECTION-01 — Card canônica de `public.card` sem representação na
    // fonte (o arquivo sumiu da listagem do GitHub). PERMANENTE: nenhuma
    // retentativa faz o arquivo reaparecer. Decisão editorial/upstream.
    "VARIANT_SOURCE_CARD_COVERAGE_INCOMPLETE",
  ]);

  /**
   * Normaliza a mensagem crua ao TOKEN canônico do erro. A Edge às vezes
   * concatena detalhe após `: ` (ex.: "CARD_SET_EXTERNAL_REFERENCE_NOT_FOUND:
   * rode Importar Cartas..."), então o token é o prefixo antes do primeiro
   * dois-pontos.
   */
  function errorToken(raw) {
    if (typeof raw !== "string" || raw.trim() === "") return "UNKNOWN_EMPTY";
    return raw.split(":")[0].trim().toUpperCase();
  }

  /**
   * CLASSIFICAÇÃO FAIL-CLOSED. Só as três allowlists produzem veredito; tudo
   * o mais é UNKNOWN e vira BLOCKED. Um erro novo introduzido por evolução
   * futura da Edge NUNCA é retentado às cegas.
   */
  function classifyError(raw) {
    const tok = errorToken(raw);
    if (ERR_RATE_LIMIT.has(tok)) return "RATE_LIMIT";
    if (ERR_TRANSIENT.has(tok))  return "TRANSIENT";
    if (ERR_PERMANENT.has(tok))  return "PERMANENT";
    return "UNKNOWN";
  }

  // ==========================================================================
  // LOG — nunca imprime token nem segredo
  // ==========================================================================

  const T0 = Date.now();
  const hhmmss = () => new Date().toISOString().slice(11, 19);
  const el = () => {
    const s = Math.floor((Date.now() - T0) / 1000);
    return `${String(Math.floor(s / 60)).padStart(2, "0")}m${String(s % 60).padStart(2, "0")}s`;
  };
  const log  = (...a) => console.log(`[${hhmmss()} +${el()}]`, ...a);
  const warn = (...a) => console.warn(`[${hhmmss()} +${el()}]`, ...a);
  const err  = (...a) => console.error(`[${hhmmss()} +${el()}]`, ...a);

  class AbortCampaign extends Error {
    constructor(code, detail) {
      super(`${code}${detail ? `: ${detail}` : ""}`);
      this.code = code;
    }
  }
  const abort = (code, detail) => { throw new AbortCampaign(code, detail); };
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // ==========================================================================
  // SESSÃO — token relido antes de CADA request, nunca armazenado
  // ==========================================================================

  /**
   * Lê o access_token do cookie `sb-<ref>-auth-token`. O cookie NÃO é
   * httpOnly (é escrito por @supabase/ssr no browser). Pode vir:
   *   - fragmentado em `...auth-token.0`, `.1`, ... (ordem numérica);
   *   - com prefixo `base64-` cujo payload é Base64-URL.
   * Devolve string ou null. NUNCA loga o valor.
   */
  function readAccessToken() {
    const jar = {};
    for (const part of document.cookie.split("; ")) {
      const i = part.indexOf("=");
      if (i > 0) jar[part.slice(0, i)] = part.slice(i + 1);
    }

    const base = `sb-${PROJECT_REF}-auth-token`;
    let raw = jar[base];

    if (raw === undefined) {
      const chunks = Object.keys(jar)
        .filter((k) => k.startsWith(`${base}.`))
        .sort((a, b) => Number(a.split(".").pop()) - Number(b.split(".").pop()));
      if (chunks.length === 0) return null;
      raw = chunks.map((k) => jar[k]).join("");
    }

    let s;
    try { s = decodeURIComponent(raw); } catch { s = raw; }

    if (s.startsWith("base64-")) {
      try {
        const b64 = s.slice(7).replace(/-/g, "+").replace(/_/g, "/");
        const pad = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
        const bytes = Uint8Array.from(atob(pad), (c) => c.charCodeAt(0));
        s = new TextDecoder("utf-8").decode(bytes);
      } catch { return null; }
    }

    try {
      const parsed = JSON.parse(s);
      const tok = Array.isArray(parsed)
        ? parsed[0]
        : (parsed?.access_token ?? parsed?.currentSession?.access_token);
      return (typeof tok === "string" && tok.length > 0) ? tok : null;
    } catch {
      return null;
    }
  }

  /** Bloqueia enquanto a aba não estiver visível. Nunca invoca em background. */
  async function awaitVisible() {
    if (document.visibilityState === "visible") return;
    warn("⏸  aba não está visível — PAUSADO (o SessionRefresher só renova com a aba ativa)");
    while (document.visibilityState !== "visible") await sleep(VISIBILITY_POLL_MS);
    log("▶  aba visível novamente — retomando");
  }

  /** GATE_TOKEN: relê e valida. Nunca devolve o token para fora do caller. */
  function requireToken() {
    const tok = readAccessToken();
    if (!tok) abort("SESSION_LOST", "access_token ausente ou ilegível no cookie");
    return tok;
  }

  // ==========================================================================
  // REST — leituras BULK paginadas fail-closed, zero N+1
  // ==========================================================================

  async function restGetAll(resource, query) {
    const out = [];
    for (let page = 0; page < MAX_PAGES; page += 1) {
      await awaitVisible();
      const token = requireToken();               // relido a CADA página
      const url = `${REST_BASE}/${resource}?${query}&limit=${PAGE_SIZE}&offset=${page * PAGE_SIZE}`;

      let res;
      try {
        res = await fetch(url, {
          headers: {
            apikey: ANON_KEY,
            Authorization: `Bearer ${token}`,
            Accept: "application/json",
          },
        });
      } catch (e) {
        abort("REST_NETWORK_ERROR", `${resource}: ${e?.message ?? "sem resposta"}`);
      }

      if (res.status === 401) abort("SESSION_LOST", `REST 401 em ${resource}`);
      if (res.status === 403) abort("FORBIDDEN", `REST 403 em ${resource}`);
      if (!res.ok) abort("REST_HTTP_ERROR", `${resource} → HTTP ${res.status}`);

      const batch = await res.json();
      if (!Array.isArray(batch)) abort("REST_UNEXPECTED_SHAPE", resource);
      out.push(...batch);

      if (batch.length < PAGE_SIZE) return out;

      // Página cheia na última iteração permitida: a leitura PODE estar
      // incompleta e um PLAN incompleto é indistinguível de um PLAN correto.
      if (page === MAX_PAGES - 1) {
        abort("REST_PAGINATION_EXHAUSTED",
          `${resource}: mais de ${MAX_PAGES * PAGE_SIZE} linhas`);
      }
    }
    return out; // inalcançável
  }

  /** `in.(a,b,c)` do PostgREST, com aspas para UUIDs (seguro e uniforme). */
  const inList = (values) => `in.(${values.map((v) => `"${v}"`).join(",")})`;

  // ==========================================================================
  // PLAN — 3 leituras bulk, classificação em memória
  // ==========================================================================

  /**
   * L1 — universo elegível, da view canônica `catalog_card_set_variant_coverage`
   *      (ADR-027, security_invoker, SELECT liberado a `authenticated`).
   * L2 — jobs de VARIANT dos elegíveis (estado + histórico de falhas).
   * L3 — PROXY B13: external_set_id histórico, de `catalog_import_job`.
   *
   * Nenhuma leitura por Set. Nenhuma leitura de card_set_external_reference.
   */
  async function buildPlan() {
    // ---- L1 ---------------------------------------------------------------
    const coverage = await restGetAll(
      "catalog_card_set_variant_coverage",
      "select=card_set_id,card_set_code,cards_cadastradas,cards_com_variante",
    );

    const eligible = coverage.filter((r) =>
      Number(r.cards_cadastradas) > 0 &&
      Number(r.cards_com_variante) === 0 &&
      !EXCLUDED_SET_CODES.includes(r.card_set_code),
    );

    const ids = eligible.map((r) => r.card_set_id);
    if (ids.length === 0) abort("PLAN_EMPTY", "nenhum Card Set elegível");

    // ---- L2 ---------------------------------------------------------------
    const vJobs = await restGetAll(
      "catalog_variant_import_job",
      `select=id,card_set_id,external_set_id,status,error_summary,created_at,updated_at` +
      `&card_set_id=${inList(ids)}&order=updated_at.asc`,
    );

    // ---- L3 (PROXY B13, nunca autoridade) ---------------------------------
    const cJobs = await restGetAll(
      "catalog_import_job",
      `select=card_set_id,external_set_id&source=eq.TCGDEX&card_set_id=${inList(ids)}`,
    );

    // ---- agregação em memória ---------------------------------------------
    const bySet = new Map();
    for (const r of eligible) {
      bySet.set(r.card_set_id, {
        cardSetId: r.card_set_id,
        code: r.card_set_code,
        cards: Number(r.cards_cadastradas),
        proxyExt: null, proxyDistinct: 0,
        activeJobs: [], failedJobs: [],
      });
    }

    const proxySeen = new Map();
    for (const j of cJobs) {
      if (!bySet.has(j.card_set_id)) continue;
      const ext = (j.external_set_id ?? "").trim();
      if (ext === "") continue;
      if (!proxySeen.has(j.card_set_id)) proxySeen.set(j.card_set_id, new Set());
      proxySeen.get(j.card_set_id).add(ext);
    }
    for (const [setId, set] of proxySeen) {
      const s = bySet.get(setId);
      s.proxyDistinct = set.size;
      s.proxyExt = set.size === 1 ? [...set][0] : null;
    }

    for (const j of vJobs) {
      const s = bySet.get(j.card_set_id);
      if (!s) continue;
      if (ACTIVE_STATUSES.includes(j.status)) s.activeJobs.push(j);
      else if (j.status === "FAILED") s.failedJobs.push(j);
    }

    return { rows: [...bySet.values()], vJobs };
  }

  /**
   * CLASSIFY — puro, derivado só do banco. Ordem de precedência fixa:
   * BLOCKED → ALREADY_STAGED → ACTIVE_WAIT → FAILED_PERMANENT →
   * COOLDOWN_WAIT → RETRY_WAIT → PENDING.
   */
  function classify(s, now = Date.now()) {
    // --- B13: proxy ambíguo ou ausente ------------------------------------
    if (s.proxyDistinct === 0) return { state: "BLOCKED", reason: "PROXY_EXT_AUSENTE" };
    if (s.proxyDistinct > 1)   return { state: "BLOCKED", reason: "PROXY_EXT_MULTIPLO" };

    // --- concorrência ------------------------------------------------------
    if (s.activeJobs.length > 1) return { state: "BLOCKED", reason: "MULTIPLOS_JOBS_ATIVOS" };

    if (s.activeJobs.length === 1) {
      const j = s.activeJobs[0];
      if ((j.external_set_id ?? "").trim() !== s.proxyExt) {
        return { state: "BLOCKED", reason: "EXTERNAL_SET_ID_DIVERGENTE", job: j };
      }
      if (j.status === "STAGED")     return { state: "ALREADY_STAGED", job: j };
      if (j.status === "CONFIRMING") return { state: "BLOCKED", reason: "FORA_DO_ESCOPO", job: j };
      // RECEIVED | PROCESSING
      const stalledFor = now - Date.parse(j.updated_at);
      if (stalledFor > ACTIVE_STALL_MS) {
        return { state: "BLOCKED", reason: "JOB_ATIVO_ESTAGNADO", job: j };
      }
      return { state: "ACTIVE_WAIT", job: j, stalledFor };
    }

    // --- histórico de falhas (reconstrução pura, §3 do MODELING-AUDIT-02) --
    let nTrans = 0, nRate = 0, lastFail = null, lastClass = null;
    for (const j of s.failedJobs) {
      const c = classifyError(j.error_summary);
      if (c === "TRANSIENT") nTrans += 1;
      if (c === "RATE_LIMIT") nRate += 1;
      const t = Date.parse(j.updated_at);
      if (lastFail === null || t > lastFail.t) lastFail = { t, job: j, cls: c };
    }
    if (lastFail) lastClass = lastFail.cls;

    if (lastClass === "UNKNOWN") {
      return { state: "BLOCKED", reason: `ERRO_DESCONHECIDO(${errorToken(lastFail.job.error_summary)})` };
    }
    if (lastClass === "PERMANENT") {
      return { state: "FAILED_PERMANENT", reason: errorToken(lastFail.job.error_summary) };
    }
    if (nTrans >= MAX_TRANSIENT) {
      return { state: "FAILED_PERMANENT", reason: "RETRY_BUDGET_ESGOTADO" };
    }
    if (nRate >= MAX_RATE_LIMIT) {
      return { state: "ABORT_RATE_LIMIT", reason: "RATE_LIMIT_PERSISTENTE" };
    }
    if (lastClass === "RATE_LIMIT") {
      const until = lastFail.t + COOLDOWN_MS;
      if (now < until) return { state: "COOLDOWN_WAIT", until, nRate };
    }
    if (lastClass === "TRANSIENT") {
      const until = lastFail.t + (BACKOFF_MS[nTrans - 1] ?? BACKOFF_MS[BACKOFF_MS.length - 1]);
      if (now < until) return { state: "RETRY_WAIT", until, nTrans };
    }

    return { state: "PENDING", nTrans, nRate };
  }

  // ==========================================================================
  // GATES
  // ==========================================================================

  /**
   * Discriminante INITIAL × RESUME, sem localStorage e sem tabela nova:
   * a campanha começou se existe QUALQUER job de Variant nos elegíveis que
   * não seja o canário EX5.5 pré-existente (job do FALLBACK-01).
   */
  function campaignStarted(plan) {
    return plan.rows.some((s) =>
      !EXCLUDED_SET_CODES.includes(s.code) &&
      s.code !== "EX5.5" &&
      (s.activeJobs.length > 0 || s.failedJobs.length > 0),
    );
  }

  /**
   * MANIFEST GATE (SOURCE-VARIANT-SAFETY-01) — prova, contra o banco e
   * contra si mesmo, que TARGET e DEFERRED são uma partição exata dos
   * elegíveis. Roda antes de qualquer invocação; qualquer divergência é
   * ABORT, nunca ajuste silencioso.
   */
  function assertManifest(plan) {
    const eligible = plan.rows.map((s) => s.code);
    const eligibleSet = new Set(eligible);
    const deferred = Object.keys(DEFERRED_SET_REASON);

    // 1. cardinalidade declarada
    if (TARGET_SET_CODES.length !== EXPECTED_TARGET) {
      abort("MANIFEST_TARGET_COUNT", `${TARGET_SET_CODES.length} ≠ ${EXPECTED_TARGET}`);
    }
    if (deferred.length !== EXPECTED_DEFERRED) {
      abort("MANIFEST_DEFERRED_COUNT", `${deferred.length} ≠ ${EXPECTED_DEFERRED}`);
    }
    // 2. sem duplicados dentro do TARGET (Set colapsaria em silêncio)
    if (TARGET_SET.size !== TARGET_SET_CODES.length) {
      abort("MANIFEST_TARGET_DUPLICADO", `${TARGET_SET_CODES.length - TARGET_SET.size} repetido(s)`);
    }
    // 3. interseção vazia entre TARGET e DEFERRED
    const overlap = deferred.filter((c) => TARGET_SET.has(c));
    if (overlap.length > 0) abort("MANIFEST_INTERSECAO", overlap.join(", "));
    // 4. partição EXATA dos elegíveis, nos dois sentidos
    const foraDoBanco = [...TARGET_SET_CODES, ...deferred].filter((c) => !eligibleSet.has(c));
    if (foraDoBanco.length > 0) abort("MANIFEST_CODIGO_INEXISTENTE", foraDoBanco.join(", "));
    const naoClassificado = eligible.filter((c) => !TARGET_SET.has(c) && !(c in DEFERRED_SET_REASON));
    if (naoClassificado.length > 0) abort("MANIFEST_SET_NAO_CLASSIFICADO", naoClassificado.join(", "));

    log(`  ✔ MANIFEST_GATE PASS — ${EXPECTED_TARGET} TARGET + ${EXPECTED_DEFERRED} DEFERRED = ${eligible.length} elegíveis` +
        " (sem duplicados, sem interseção, partição exata)");
  }

  function runGate(plan, classified) {
    const started = campaignStarted(plan);
    const n = plan.rows.length;
    const staged  = classified.filter((c) => c.state === "ALREADY_STAGED").length;
    const failed  = plan.rows.reduce((a, s) => a + s.failedJobs.length, 0);
    const blocked = classified.filter((c) => c.state === "BLOCKED");

    log(`GATE: ${started ? "RESUME_GATE" : "INITIAL_BASELINE_GATE"}`);
    log(`  elegíveis=${n} · ALREADY_STAGED=${staged} · jobs FAILED=${failed} · BLOCKED=${blocked.length}`);

    if (n !== EXPECTED_ELIGIBLE) {
      abort("GATE_ELIGIBLE_MISMATCH", `esperado ${EXPECTED_ELIGIBLE}, medido ${n}`);
    }

    // Partição TARGET/DEFERRED validada antes de qualquer seleção de lote.
    assertManifest(plan);

    if (blocked.length > 0) {
      for (const b of blocked) err(`  BLOCKED ${b.code}: ${b.reason}`);
      abort("GATE_BLOCKED", `${blocked.length} Set(s) bloqueado(s) — decisão humana necessária`);
    }

    if (!started) {
      // INITIAL: campo precisa estar limpo, exatamente como medido em 2026-09-18.
      if (failed !== 0) abort("GATE_INITIAL_FAILED_NOT_ZERO", `FAILED=${failed}, esperado 0`);
      if (staged !== 1) abort("GATE_INITIAL_STAGED_MISMATCH", `ALREADY_STAGED=${staged}, esperado 1 (EX5.5)`);
      const ex = classified.find((c) => c.code === "EX5.5");
      if (!ex || ex.state !== "ALREADY_STAGED") abort("GATE_INITIAL_EX55", "EX5.5 não está STAGED");
      log("  ✔ INITIAL_BASELINE_GATE PASS (campo limpo; EX5.5 preservado)");
    } else {
      // RESUME: FAILED > 0 é ESPERADO e necessário para reconstruir retry/cooldown.
      log("  ✔ RESUME_GATE PASS (FAILED>0 é esperado e não aborta)");
    }
    return started;
  }

  // ==========================================================================
  // INVOKE — a única escrita que este runner provoca
  // ==========================================================================

  async function invokeSet(s) {
    await awaitVisible();
    const token = requireToken();                 // relido AGORA, nunca antes

    let res;
    try {
      res = await fetch(EDGE_URL, {
        method: "POST",
        headers: {
          apikey: ANON_KEY,
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ card_set_id: s.cardSetId }),
      });
    } catch (e) {
      // ERRO DE TRANSPORTE — desfecho INDETERMINADO. A request pode não ter
      // chegado à Edge (nenhum job criado) OU ter chegado e a resposta ter se
      // perdido (job criado, talvez já STAGED). Nunca classificar aqui: o
      // caller faz re-PLAN pontual e decide pela evidência DURÁVEL.
      return { kind: "NO_RESPONSE", detail: e?.message ?? "sem resposta" };
    }

    if (res.status === 401) abort("SESSION_LOST", "Edge 401");
    if (res.status === 403) abort("FORBIDDEN", "Edge 403 FORBIDDEN_NOT_ADMIN");

    const body = await res.json().catch(() => null);

    if (res.ok && body?.success === true) return { kind: "OK", body };
    const raw = typeof body?.error === "string" ? body.error : `HTTP_${res.status}`;
    if (errorToken(raw) === "JOB_ALREADY_ACTIVE_FOR_CARD_SET") return { kind: "CONFLICT", raw };
    return { kind: "ERROR", raw };
  }

  /**
   * RE-PLAN PONTUAL de um Set — relê do banco os jobs daquele card_set_id e
   * repovoa `activeJobs`/`failedJobs` da linha em memória. É a única leitura
   * por Set do runner, e é deliberada: serve aos contratos de 409, de erro e
   * de transporte. NÃO é N+1 do PLAN (que segue com 3 leituras bulk) — só
   * dispara DEPOIS de uma invocação real.
   */
  async function replanSet(ref) {
    const fresh = await restGetAll(
      "catalog_variant_import_job",
      "select=id,card_set_id,external_set_id,status,error_summary,created_at,updated_at" +
      `&card_set_id=eq.${ref.cardSetId}`,
    );
    ref.activeJobs = fresh.filter((j) => ACTIVE_STATUSES.includes(j.status));
    ref.failedJobs = fresh.filter((j) => j.status === "FAILED");
    return ref;
  }

  // ==========================================================================
  // MAIN
  // ==========================================================================

  const results = new Map();  // code → { state, reason, rows?, byLineage? }
  const record = (s, state, extra = {}) => results.set(s.code, { code: s.code, cards: s.cards, state, ...extra });

  try {
    console.log("%c BULK-STAGING-01 ", "background:#b8860b;color:#111;font-weight:bold");
    log(`modo=${RUN_MODE} · DRY_RUN=${DRY_RUN}`);

    if (PROJECT_REF.startsWith("COLE_AQUI")) abort("CONFIG", "preencha PROJECT_REF");
    if (ANON_KEY.startsWith("COLE_AQUI"))    abort("CONFIG", "preencha ANON_KEY");
    if (!["CANARY", "FULL"].includes(RUN_MODE)) abort("CONFIG", `RUN_MODE inválido: ${RUN_MODE}`);

    await awaitVisible();
    if (!readAccessToken()) abort("SESSION_LOST", "sem sessão — faça login como administrador");
    log("sessão admin: presente (token não é impresso nem armazenado)");

    // ---- PREFLIGHT --------------------------------------------------------
    log("PREFLIGHT — montando PLAN (3 leituras bulk, zero N+1)…");
    let plan = await buildPlan();
    let classified = plan.rows.map((s) => ({ ...classify(s), code: s.code, cards: s.cards, ref: s }));
    const isResume = runGate(plan, classified);

    // ---- seleção do lote --------------------------------------------------
    let queue;
    if (RUN_MODE === "CANARY") {
      queue = classified.filter((c) => CANARY_SET_CODES.includes(c.code));
      const faltando = CANARY_SET_CODES.filter((c) => !queue.some((q) => q.code === c));
      if (faltando.length > 0) abort("CANARY_SET_AUSENTE", faltando.join(", "));
      queue.sort((a, b) => CANARY_SET_CODES.indexOf(a.code) - CANARY_SET_CODES.indexOf(b.code));
      log(`CANARY — lote fixo: ${queue.map((q) => `${q.code}(${q.cards})`).join(" → ")}`);
    } else {
      queue = classified.slice().sort((a, b) => b.cards - a.cards);
      log(`FULL — ${queue.length} Sets elegíveis, maiores primeiro`);
    }

    // ---- FILTRO DE COBERTURA (SOURCE-VARIANT-SAFETY-01) -------------------
    // ÚNICO ponto onde DEFERRED é descartado, e vale para CANARY *e* FULL —
    // estrutural, não condicional ao modo. Um Set DEFERRED nunca chega à
    // porta de invocação; é registrado e sai. (Por isso SM12, que estava no
    // lote CANARY histórico, hoje sai aqui: sua fonte é ABSENT.)
    const deferredNaFila = queue.filter((c) => !isTarget(c.code));
    for (const c of deferredNaFila) {
      record(c.ref, "DEFERRED_SOURCE_COVERAGE", { reason: DEFERRED_SET_REASON[c.code] });
    }
    queue = queue.filter((c) => isTarget(c.code));
    log(`cobertura de fonte — TARGET na fila: ${queue.length} · DEFERRED_SOURCE_COVERAGE: ${deferredNaFila.length}`);
    if (RUN_MODE === "FULL" && queue.length !== EXPECTED_TARGET) {
      abort("FULL_TARGET_MISMATCH", `fila TARGET=${queue.length}, esperado ${EXPECTED_TARGET}`);
    }

    // Registra de saída tudo que já é terminal e não será invocado.
    for (const c of queue) {
      if (["ALREADY_STAGED", "BLOCKED", "FAILED_PERMANENT"].includes(c.state)) {
        record(c.ref, c.state, { reason: c.reason });
      }
    }

    const total = queue.length;
    let done = 0, invoked = 0;

    for (const item of queue) {
      done += 1;

      // Re-CLASSIFY contra o estado corrente (o PLAN é recalculado a cada
      // invocação real; aqui reavaliamos a linha em memória mais recente).
      let c = classify(item.ref);
      const head = `[${done}/${total}] ${item.code} (${item.cards} Cards)`;

      if (c.state === "ABORT_RATE_LIMIT") abort("RATE_LIMIT_PERSISTENTE", item.code);

      if (c.state === "ALREADY_STAGED")   { log(`${head} · ALREADY_STAGED — não reinvocar`); continue; }
      if (c.state === "BLOCKED")          { err(`${head} · BLOCKED — ${c.reason}`); continue; }
      if (c.state === "FAILED_PERMANENT") { err(`${head} · FAILED_PERMANENT — ${c.reason}`); continue; }
      if (c.state === "COOLDOWN_WAIT") {
        const min = Math.ceil((c.until - Date.now()) / 60000);
        warn(`${head} · COOLDOWN_WAIT — ${min} min restantes (rate limit)`);
        record(item.ref, "COOLDOWN_WAIT", { reason: `${min}min` });
        continue;
      }
      if (c.state === "RETRY_WAIT") {
        const s = Math.ceil((c.until - Date.now()) / 1000);
        warn(`${head} · RETRY_WAIT — ${s}s restantes (tentativa ${c.nTrans})`);
        record(item.ref, "RETRY_WAIT", { reason: `${s}s` });
        continue;
      }
      if (c.state === "ACTIVE_WAIT") {
        warn(`${head} · ACTIVE_WAIT — job ${c.job.status} em curso`);
        record(item.ref, "ACTIVE_WAIT", { reason: c.job.status });
        continue;
      }

      // --- PENDING: única porta de invocação -------------------------------
      if (c.state !== "PENDING") abort("ESTADO_INESPERADO", `${item.code}: ${c.state}`);

      // Guard redundante e deliberado: nunca invocar Set com job ativo.
      if (item.ref.activeJobs.length !== 0) abort("GUARD_INVOKE", `${item.code} tem job ativo`);

      if (DRY_RUN) {
        log(`${head} · DRY_RUN — invocaria agora (pacing ${PACE_MS / 1000}s entre invocações reais)`);
        record(item.ref, "DRY_RUN_WOULD_INVOKE");
        continue;
      }

      // Snapshot ANTES da invocação — base para decidir, depois de um erro de
      // transporte, se surgiu EVIDÊNCIA DURÁVEL NOVA no banco.
      const beforeActive = item.ref.activeJobs.length;   // sempre 0 aqui (PENDING)
      const beforeFailed = item.ref.failedJobs.length;

      log(`${head} · invocando…`);
      const r = await invokeSet(item.ref);
      invoked += 1;

      if (r.kind === "OK") {
        const b = r.body;
        log(`${head} · STAGED — rows ${b.rows.total} (VALID ${b.rows.valid} · NEEDS_REVIEW ${b.rows.needs_review})` +
            ` · cards ${b.cards.correlated} (ref ${b.cards.correlated_by_reference} + lineage ${b.cards.correlated_by_lineage})` +
            ` · uncorrelated ${b.cards.uncorrelated}`);
        record(item.ref, "STAGED", {
          rows: b.rows.total, valid: b.rows.valid, needsReview: b.rows.needs_review,
          byLineage: b.cards.correlated_by_lineage, uncorrelated: b.cards.uncorrelated,
        });

      } else if (r.kind === "NO_RESPONSE") {
        // ====================================================================
        // ERRO DE TRANSPORTE — desfecho indeterminado (CORRECTION-01)
        //
        // Um `fetch` do browser pode falhar ANTES de a request chegar à Edge.
        // Nesse caso não existe job FAILED no banco, e contar a tentativa
        // criaria retry budget SÓ EM MEMÓRIA — que um refresh apagaria. Por
        // isso: re-PLAN pontual imediato e decisão exclusivamente pela
        // evidência DURÁVEL. Sem evidência nova, ABORT — nunca tentar de novo
        // às cegas, porque a invocação PODE ter chegado e estar em curso.
        // ====================================================================
        warn(`${head} · erro de transporte (${r.detail}) — desfecho indeterminado, re-PLAN pontual`);
        await replanSet(item.ref);

        const novaEvidencia =
          item.ref.activeJobs.length > beforeActive ||
          item.ref.failedJobs.length > beforeFailed;

        if (!novaEvidencia) {
          err(`${head} · nenhuma evidência durável nova no banco após o erro de transporte`);
          record(item.ref, "BLOCKED", { reason: "EDGE_OUTCOME_UNKNOWN_NO_DURABLE_EVIDENCE" });
          abort("EDGE_OUTCOME_UNKNOWN_NO_DURABLE_EVIDENCE",
            `${item.code}: a invocação pode ou não ter chegado à Edge. ` +
            `Verifique o estado do Set antes de reexecutar o runner.`);
        }

        const c5 = classify(item.ref);
        if (c5.state === "ABORT_RATE_LIMIT") abort("RATE_LIMIT_PERSISTENTE", item.code);
        log(`${head} · evidência durável encontrada → ${c5.state}${c5.reason ? ` (${c5.reason})` : ""}`);
        record(item.ref, c5.state, { reason: c5.reason ?? "via erro de transporte" });

      } else if (r.kind === "CONFLICT") {
        // 409 NUNCA é SKIP cego: re-PLAN deste Set e classificar pelo real.
        warn(`${head} · 409 JOB_ALREADY_ACTIVE — re-PLAN do Set`);
        await replanSet(item.ref);
        const c2 = classify(item.ref);
        log(`${head} · re-PLAN → ${c2.state}${c2.reason ? ` (${c2.reason})` : ""}`);
        record(item.ref, c2.state, { reason: c2.reason ?? "via 409" });

      } else {
        const cls = classifyError(r.raw);
        const tok = errorToken(r.raw);
        // A Edge respondeu e já gravou o job como FAILED; o estado durável
        // está no banco. Refrescamos a linha para que a reclassificação use o
        // que foi PERSISTIDO, nunca o que está em memória.
        await replanSet(item.ref);

        if (cls === "UNKNOWN") {
          err(`${head} · ERRO DESCONHECIDO (${tok}) — BLOCKED fail-closed`);
          record(item.ref, "BLOCKED", { reason: `ERRO_DESCONHECIDO(${tok})` });
          abort("ERRO_DESCONHECIDO", `${item.code}: ${tok}`);
        }
        if (cls === "RATE_LIMIT") {
          const c3 = classify(item.ref);
          if (c3.state === "ABORT_RATE_LIMIT") {
            err(`${head} · 2º rate limit após cooldown completo — ABORT`);
            abort("RATE_LIMIT_PERSISTENTE", item.code);
          }
          warn(`${head} · RATE LIMIT (${tok}) — cooldown de ${COOLDOWN_MS / 60000} min`);
          record(item.ref, "COOLDOWN_WAIT", { reason: tok });
        } else if (cls === "PERMANENT") {
          err(`${head} · FAILED_PERMANENT — ${tok}`);
          record(item.ref, "FAILED_PERMANENT", { reason: tok });
        } else {
          const c4 = classify(item.ref);
          warn(`${head} · transitório (${tok}) — ${c4.state}`);
          record(item.ref, c4.state, { reason: tok });
        }
      }

      // --- PACING: só entre invocações REAIS -------------------------------
      const isLast = done === total;
      if (!isLast) {
        log(`⏱  pacing ${PACE_MS / 1000}s…`);
        await sleep(PACE_MS);
      }
    }

    // ---- RELATÓRIO --------------------------------------------------------
    console.log("%c RESUMO ", "background:#333;color:#fff;font-weight:bold");
    const tally = {};
    for (const r of results.values()) tally[r.state] = (tally[r.state] ?? 0) + 1;
    console.table([...results.values()]);
    log("contagem:", tally);
    log(`invocações reais: ${invoked} · modo=${RUN_MODE} · DRY_RUN=${DRY_RUN}`);

    if (RUN_MODE === "CANARY") {
      console.log("%c CANARY CONCLUÍDO — PARADA OBRIGATÓRIA ", "background:#8a6d00;color:#fff;font-weight:bold");
      log("NÃO prossegue automaticamente para FULL. Executar FULL exige autorização explícita de Fabrício.");
    } else {
      // COMPLETION GATE — denominador é o TARGET, nunca os 169 elegíveis.
      // Os 56 DEFERRED não são pendência da campanha: são escopo excluído
      // por decisão, e contá-los faria o FULL parecer eternamente incompleto.
      const alvo = classified.filter((c) => isTarget(c.code));
      const concluidos = alvo.filter((c) => {
        const r = results.get(c.code);
        return r ? (r.state === "STAGED" || r.state === "ALREADY_STAGED") : false;
      }).length;
      log(`COMPLETION GATE — TARGET ${concluidos}/${EXPECTED_TARGET} em STAGED · ` +
          `${EXPECTED_DEFERRED} DEFERRED_SOURCE_COVERAGE fora do denominador.`);
      log("Conclusão FULL deve ser comprovada por postcheck READ-ONLY externo ao runner.");
    }

  } catch (e) {
    if (e instanceof AbortCampaign) {
      console.log("%c ABORT ", "background:#8b0000;color:#fff;font-weight:bold");
      err(e.message);
      if (results.size > 0) console.table([...results.values()]);
      err("A campanha parou de propósito (fail-closed). Nada foi confirmado nem materializado.");
    } else {
      throw e;
    }
  }
})();
