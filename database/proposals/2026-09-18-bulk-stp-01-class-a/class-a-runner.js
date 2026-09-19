/* ============================================================================
Project Mimikyu — BULK-STP-01 / CLASSE A — Runner autenticado (DevTools)
Arquivo......: database/proposals/2026-09-18-bulk-stp-01-class-a/class-a-runner.js
Versão.......: 1.0
Status.......: PROPOSTA — NÃO EXECUTADO
Criado em....: 2026-09-18, em `BULK-STP-01-CLASS-A-RUNNER-STAGING-01`
Autoridade...: CLASS-A-OPERATIONAL-DESIGN-01 + CORRECTION-01 (ambos APROVADOS)

OBJETIVO
  Consumir as 17.222 linhas da CLASSE A (VALID / PENDING / PENDING) dos 113
  Card Sets TARGET, aprovando-as e confirmando-as em massa, sem trabalho
  manual Set a Set.

O QUE ELE É
  Snippet descartável, colado UMA vez no console do DevTools, que morre com o
  refresh da página. Não é frontend permanente. Não cria tabela, RPC, Edge,
  policy nem grant. Não roda SQL. Não escreve em tabela.

O QUE ELE USA — E NADA ALÉM DISSO
  - public.admin_decide_catalog_variant_import_row(UUID[], TEXT)
  - public.admin_confirm_catalog_variant_import(UUID, UUID[])
  Ambas SECURITY DEFINER, ambas já LIVE, ambas chamadas com sessão de
  administrador real.

COMO EXECUTAR
  1. Login na aplicação como ADMINISTRADOR REAL.
  2. Abrir uma página autenticada (ex.: /catalogo/importar-variantes).
  3. DevTools (F12) → Console.
  4. Preencher PROJECT_REF e ANON_KEY.
  5. Colar este arquivo inteiro e Enter.
  6. MANTER A ABA VISÍVEL E EM FOCO durante toda a execução (ver §SESSÃO).

NOTA DE SEGURANÇA
  ANON_KEY é a publishable/anon key — PÚBLICA POR DESENHO, já exposta ao
  browser pelo app (`NEXT_PUBLIC_SUPABASE_ANON_KEY`). Não é segredo.
  O access_token da sessão — esse sim segredo — é RELIDO do cookie antes de
  cada request, nunca é congelado, nunca é impresso, nunca é gravado.

  NÃO usa service_role. NÃO fabrica JWT. NÃO usa SET ROLE. NÃO grava em
  localStorage/sessionStorage/cookie. NÃO cria segredo novo.

============================================================================
§ CAMPAIGN FREEZE — PREMISSA DE CONCORRÊNCIA, NÃO SUGESTÃO
============================================================================
  Durante CANARY, FULL e qualquer retomada, enquanto este runner estiver
  rodando:

    - o usuário NÃO utiliza a UI de Importação / Revisão de Variantes;
    - NENHUM mapping é criado ou resolvido (admin_resolve_* em qualquer
      variante, incluindo Printing) — qualquer um reclassifica staging e
      invalida os conjuntos A/B/C já lidos;
    - NENHUM Print Profile é criado
      (admin_create_card_printing_profile_with_backfill faz backfill);
    - NENHUMA nova importação / novo job é disparado para os 113 TARGET;
    - NENHUMA segunda instância deste runner, em nenhuma aba;
    - NENHUM write SQL paralelo, por nenhum caminho.

  Este é um CONTROLE OPERACIONAL ACEITO **somente** para esta campanha
  efêmera. NÃO é precedente para bulk permanente multi-admin: não há lock no
  banco, e a garantia é disciplina humana.

  O runner não confia no freeze — ele o VERIFICA. Os detectores são:
  o gate rows_affected === |A|, o gate RESUME_PARTIAL, o gate F>0 e o
  precheck de baseline por fase. Qualquer um que dispare => STOP.

============================================================================
§ SESSÃO / VISIBILITY
============================================================================
  - access_token RELIDO do cookie antes de CADA request.
  - O SessionRefresher da aplicação só renova o token com a ABA ATIVA. Por
    isso o runner PAUSA enquanto `document.visibilityState !== "visible"` e
    retoma sozinho ao voltar. NÃO implementa refresh próprio.
  - Sessão ausente/ilegível, 401 real ou 403 not-admin => ABORT fail-closed.

============================================================================
§ CONJUNTOS — DEFINIÇÃO FECHADA
============================================================================
  A = validation VALID       / decision PENDING  / persistence PENDING
      => candidatos a APPROVED. É a Classe A.

  B = validation VALID       / decision APPROVED / persistence PENDING
      => recuperação de execução interrompida entre decide e confirm.

  C = validation INVALID     / decision SKIPPED  / persistence PENDING
      E normalized_data->>'skip_reason' = 'SIZE_OUT_OF_SCOPE'
      => automáticas do sistema (incidente JUMBO), a consolidar em UNCHANGED.
      C É FECHADO: qualquer SKIPPED/PENDING fora desse predicado => STOP.

  N = validation NEEDS_REVIEW / decision PENDING
      => NUNCA tocadas. Só observadas.

  F = persistence FAILED
      => estado de PRIMEIRA CLASSE. Baseline 0. Qualquer F => STOP.
         NUNCA retry automático de FAILED.

============================================================================
§ ATOMICIDADE — O QUE A RPC DE CONFIRM GARANTE E O QUE NÃO GARANTE
============================================================================
  admin_confirm_catalog_variant_import é transacional NA CHAMADA, mas captura
  exceção POR ROW (EXCEPTION WHEN OTHERS dentro do loop). Logo ela pode
  legitimamente COMMITAR com algumas linhas INSERTED/UNCHANGED e outras
  FAILED.

  Portanto: NÃO assumir atomicidade semântica por row. "Parte saiu de PENDING"
  NÃO é estado impossível — é o estado normal de um confirm com falhas. O
  protocolo de NETWORK_ERROR_NO_RESPONSE abaixo reflete isso.

============================================================================
§ RESULTADOS DA RPC — O QUE SIGNIFICAM
============================================================================
  admin_decide_...  => INTEGER rows_affected. EXIGIR igualdade exata com |A|.
  admin_confirm_... => contadores ACUMULADOS DO JOB, não delta da chamada.
                       NUNCA usar inserted_count/unchanged_count como delta
                       operacional. Deltas vêm de snapshots PRE/POST.
============================================================================ */

(async function bulkStpClassARunner() {
  "use strict";

  // ==========================================================================
  // § CONFIGURAÇÃO OBRIGATÓRIA
  // ==========================================================================
  const PROJECT_REF = "COLE_AQUI_O_PROJECT_REF";          // ex.: qjfutqujxrbzgrtkpgkg
  const ANON_KEY    = "COLE_AQUI_A_NEXT_PUBLIC_SUPABASE_ANON_KEY";

  // ==========================================================================
  // § MODO — DRY_RUN por padrão. CANARY e FULL exigem EDIÇÃO EXPLÍCITA desta
  //   constante. Não há transição automática, não há prompt, não há auto-FULL.
  // ==========================================================================
  const RUN_MODE = "DRY_RUN";   // "DRY_RUN" | "CANARY" | "FULL"

  // ==========================================================================
  // § MANIFESTO — AUTORIDADE DE PERTENCIMENTO
  //   Status NUNCA é critério de pertencimento. SM12 é DEFERRED, está STAGED,
  //   e fica fora por ASSERÇÃO explícita — não por consequência de filtro.
  // ==========================================================================
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
    "TK-SM-R"  ]);
  const TARGET_SET = new Set(TARGET_SET_CODES);

  /** DEFERRED que está STAGED e precisa ficar fora — verificado, não suposto. */
  const DEFERRED_STAGED_OUT_OF_SCOPE = Object.freeze(["SM12"]);

  /** CANARY congelado — os 4 Sets aprovados em CORRECTION-01. */
  const CANARY_SET_CODES = Object.freeze(["FUT2020", "NEO3", "NEO1", "BASE2"]);

  // ==========================================================================
  // § BASELINES ESPERADOS POR FASE  (deltas mode-aware)
  //   FULL NUNCA usa 7.671 como baseline físico: ele roda sobre o pós-canary.
  // ==========================================================================
  const EXPECTED = Object.freeze({
    DRY_RUN: {
      phase: "INICIAL",
      targetStaged: 113, targetCompleted: 0,
      classA: 17222, jobsWithClassA: 109,
      cardVariant: 7671,
      setC: 76, jobsWithC: 29,
      setB: 0, setF: 0,
      needsReview: 1642,
    },
    CANARY: {
      phase: "INICIAL",
      targetStaged: 113, targetCompleted: 0,
      classA: 17222, jobsWithClassA: 109,
      cardVariant: 7671,
      setC: 76, jobsWithC: 29,
      setB: 0, setF: 0,
      needsReview: 1642,
      execDelta: 488,
      cardVariantAfter: 8159,
    },
    FULL: {
      phase: "POS_CANARY",
      targetStaged: 110, targetCompleted: 3,
      classA: 16734, jobsWithClassA: 105,
      cardVariant: 8159,
      setC: 73, jobsWithC: 28,
      setB: 0, setF: 0,
      needsReview: 1642,
      execDelta: 16734,
      cardVariantAfter: 24893,
    },
  });

  /** Estado FINAL esperado ao término do FULL — usado só no POSTCHECK. */
  const EXPECTED_FINAL = Object.freeze({
    targetStaged: 62, targetCompleted: 51,
    classA: 0, setC: 0, setB: 0, setF: 0,
    cardVariant: 24893, needsReview: 1642,
    unchangedAccumulated: 76, insertedAccumulated: 17222,
  });

  // ==========================================================================
  // § TETOS DO CONTRATO (Queries 2144 v2.0 e 2145 v2.0)
  // ==========================================================================
  const MAX_DECIDE_IDS  = 10000;  // c_max_row_ids
  const MAX_CONFIRM_IDS = 1000;   // c_max_rows

  // ==========================================================================
  // § PACING
  // ==========================================================================
  const PACE_MS            = 1200;
  const TRANSIENT_BACKOFF  = [30000, 120000];
  const RATE_LIMIT_COOLDOWN_MS = 65 * 60 * 1000;

  // ==========================================================================
  // § INFRA — log sem segredos
  // ==========================================================================
  const started = new Date();
  const lines = [];
  function log(...a) { const s = a.join(" "); lines.push(s); console.log(s); }
  function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

  class Stop extends Error {
    constructor(code, detail) { super(`${code}: ${detail}`); this.code = code; this.detail = detail; }
  }
  function stop(code, detail) { throw new Stop(code, detail); }

  async function waitVisible() {
    if (document.visibilityState === "visible") return;
    log("⏸  aba em background — pausado (o token só renova com a aba ativa)");
    await new Promise((resolve) => {
      const h = () => {
        if (document.visibilityState === "visible") {
          document.removeEventListener("visibilitychange", h);
          resolve();
        }
      };
      document.addEventListener("visibilitychange", h);
    });
    log("▶  aba visível — retomando");
  }

  // ==========================================================================
  // § TOKEN — relido do cookie a cada request, nunca congelado, nunca logado
  // ==========================================================================
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
      const tok = parsed && parsed.access_token;
      return typeof tok === "string" && tok.length > 0 ? tok : null;
    } catch { return null; }
  }

  function authHeaders() {
    const token = readAccessToken();
    if (!token) stop("NO_SESSION", "access_token ausente ou ilegível — faça login novamente");
    return { apikey: ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  }

  const BASE = () => `https://${PROJECT_REF}.supabase.co`;

  /** Classificação de erro — allowlists fechadas. NO_RESPONSE fica FORA das três. */
  function classify(status, body) {
    if (status === 429) return "ERR_RATE_LIMIT";
    if (status >= 500) return "ERR_TRANSIENT";
    const msg = String(body || "");
    if (/ADMIN_\w+_(FORBIDDEN|MISSING_IDS|INVALID_STATUS|NOT_FOUND|JOB_NOT_STAGED|NEEDS_REVIEW|TOO_MANY_ROWS|EMPTY_ROW_IDS|INVALID_ARRAY_SHAPE)/.test(msg)) return "ERR_PERMANENT";
    if (/NEEDS_REVIEW_CANNOT_BE_CONFIRMED|PRINTING_NOT_RESOLVED|SIZE_OUT_OF_SCOPE/.test(msg)) return "ERR_PERMANENT";
    if (status === 401 || status === 403) return "ERR_PERMANENT";
    return "ERR_PERMANENT";
  }

  // ==========================================================================
  // § TRANSPORTE — REST (leitura) e RPC (escrita). Nada de SQL direto.
  // ==========================================================================
  async function restGet(path) {
    await waitVisible();
    let res;
    try {
      res = await fetch(`${BASE()}/rest/v1/${path}`, { method: "GET", headers: authHeaders(), credentials: "omit" });
    } catch (e) {
      stop("NETWORK_ERROR_NO_RESPONSE", `GET ${path.split("?")[0]} — sem resposta`);
    }
    const text = await res.text();
    if (!res.ok) stop("READ_FAILED", `GET ${path.split("?")[0]} → HTTP ${res.status} ${text.slice(0, 200)}`);
    return text ? JSON.parse(text) : [];
  }

  /** COUNT exato sem trazer linhas. */
  async function restCount(path) {
    await waitVisible();
    let res;
    try {
      res = await fetch(`${BASE()}/rest/v1/${path}`, {
        method: "GET",
        headers: { ...authHeaders(), Prefer: "count=exact", Range: "0-0" },
        credentials: "omit",
      });
    } catch (e) {
      stop("NETWORK_ERROR_NO_RESPONSE", `COUNT ${path.split("?")[0]} — sem resposta`);
    }
    if (!res.ok && res.status !== 206) {
      const t = await res.text();
      stop("READ_FAILED", `COUNT ${path.split("?")[0]} → HTTP ${res.status} ${t.slice(0, 200)}`);
    }
    const cr = res.headers.get("content-range") || "";
    const n = Number(String(cr).split("/").pop());
    if (!Number.isFinite(n)) stop("READ_FAILED", `content-range ilegível em ${path.split("?")[0]}`);
    return n;
  }

  /** Leitura paginada fail-closed. */
  async function restGetAll(resource, query) {
    const PAGE = 1000;
    const out = [];
    for (let off = 0; ; off += PAGE) {
      const page = await restGet(`${resource}?${query}&limit=${PAGE}&offset=${off}`);
      out.push(...page);
      if (page.length < PAGE) break;
      if (off > 200000) stop("READ_RUNAWAY", `${resource} passou de 200k linhas`);
    }
    return out;
  }

  /**
   * RPC. `noResponseCode` é o código a emitir quando a chamada não obtém
   * resposta — o chamador PRECISA tratá-lo re-derivando estado do banco.
   * NUNCA há retry cego aqui.
   */
  async function rpc(fn, args, noResponseCode) {
    await waitVisible();
    let res;
    try {
      res = await fetch(`${BASE()}/rest/v1/rpc/${fn}`, {
        method: "POST", headers: authHeaders(), credentials: "omit", body: JSON.stringify(args),
      });
    } catch (e) {
      stop(noResponseCode || "NETWORK_ERROR_NO_RESPONSE", `${fn} — sem resposta`);
    }
    const text = await res.text();
    if (!res.ok) {
      const kind = classify(res.status, text);
      const err = new Error(`${fn} → HTTP ${res.status} ${text.slice(0, 300)}`);
      err.kind = kind;
      throw err;
    }
    return text ? JSON.parse(text) : null;
  }

  // ==========================================================================
  // § GATE — MANIFESTO
  // ==========================================================================
  function assertManifest() {
    if (TARGET_SET_CODES.length !== 113)
      stop("MANIFEST_COUNT", `${TARGET_SET_CODES.length} ≠ 113`);
    if (TARGET_SET.size !== TARGET_SET_CODES.length)
      stop("MANIFEST_DUPLICATE", "há códigos duplicados no manifesto");
    for (const code of DEFERRED_STAGED_OUT_OF_SCOPE) {
      if (TARGET_SET.has(code)) stop("MANIFEST_DEFERRED_LEAK", `${code} não pode estar no manifesto`);
    }
    if (CANARY_SET_CODES.length !== 4)
      stop("CANARY_COUNT", `${CANARY_SET_CODES.length} ≠ 4`);
    for (const code of CANARY_SET_CODES) {
      if (!TARGET_SET.has(code)) stop("CANARY_NOT_IN_MANIFEST", code);
    }
    log(`✓ manifesto: 113 TARGET · ${DEFERRED_STAGED_OUT_OF_SCOPE.join(",")} fora · CANARY 4/4 dentro`);
  }

  // ==========================================================================
  // § LEITURA DE ESTADO — sempre do banco, nunca da memória
  // ==========================================================================
  async function loadJobs() {
    const rows = await restGetAll(
      "catalog_variant_import_job",
      "select=id,status,card_set_id,card_set:card_set_id(code)&order=id"
    );
    return rows.map((r) => ({
      id: r.id,
      status: r.status,
      code: r.card_set && r.card_set.code ? r.card_set.code : null,
    }));
  }

  /** Classifica as linhas de UM job em A / B / C / N / F. 1 request por job. */
  async function loadSets(jobId) {
    const rows = await restGetAll(
      "catalog_variant_import_row",
      `select=id,validation_status,decision_status,persistence_status,normalized_data&job_id=eq.${jobId}`
    );
    const A = [], B = [], C = [], N = [], F = [], strayC = [];
    for (const r of rows) {
      const v = r.validation_status, d = r.decision_status, p = r.persistence_status;
      const reason = r.normalized_data && r.normalized_data.skip_reason;
      if (p === "FAILED") { F.push(r.id); continue; }
      if (v === "VALID" && d === "PENDING"  && p === "PENDING") { A.push(r.id); continue; }
      if (v === "VALID" && d === "APPROVED" && p === "PENDING") { B.push(r.id); continue; }
      if (d === "SKIPPED" && p === "PENDING") {
        if (v === "INVALID" && reason === "SIZE_OUT_OF_SCOPE") C.push(r.id);
        else strayC.push(r.id);
        continue;
      }
      if (v === "NEEDS_REVIEW" && d === "PENDING") { N.push(r.id); continue; }
    }
    return { A, B, C, N, F, strayC, total: rows.length };
  }

  async function snapshotGlobal(jobs) {
    const target = jobs.filter((j) => j.code && TARGET_SET.has(j.code));
    const targetStaged    = target.filter((j) => j.status === "STAGED").length;
    const targetCompleted = target.filter((j) => j.status === "COMPLETED").length;
    const stagedOutside   = jobs.filter((j) => j.status === "STAGED" && (!j.code || !TARGET_SET.has(j.code)));
    const cardVariant = await restCount("card_variant?select=id");
    return { target, targetStaged, targetCompleted, stagedOutside, cardVariant };
  }

  // ==========================================================================
  // § PRECHECK — mode-aware. FULL espera o baseline PÓS-CANARY, não o original.
  // ==========================================================================
  async function precheck(scopeCodes) {
    const exp = EXPECTED[RUN_MODE];
    if (!exp) stop("RUN_MODE_INVALID", RUN_MODE);

    const jobs = await loadJobs();
    const snap = await snapshotGlobal(jobs);

    log(`— PRECHECK (${RUN_MODE} · fase esperada ${exp.phase}) —`);
    log(`  TARGET STAGED=${snap.targetStaged} COMPLETED=${snap.targetCompleted} · card_variant=${snap.cardVariant}`);

    // SM12 e qualquer outro STAGED fora do manifesto: existir é esperado,
    // ser tocado é que não.
    const outsideCodes = snap.stagedOutside.map((j) => j.code || "(sem code)").sort();
    log(`  STAGED fora do manifesto: ${outsideCodes.length ? outsideCodes.join(", ") : "nenhum"}`);
    for (const code of DEFERRED_STAGED_OUT_OF_SCOPE) {
      if (!outsideCodes.includes(code)) {
        log(`  ⚠ ${code} não aparece como STAGED fora do manifesto — estado mudou desde o desenho`);
      }
    }

    if (snap.targetStaged !== exp.targetStaged)
      stop("BASELINE_TARGET_STAGED", `${snap.targetStaged} ≠ ${exp.targetStaged} (fase ${exp.phase})`);
    if (snap.targetCompleted !== exp.targetCompleted)
      stop("BASELINE_TARGET_COMPLETED", `${snap.targetCompleted} ≠ ${exp.targetCompleted}`);
    if (snap.cardVariant !== exp.cardVariant)
      stop("BASELINE_CARD_VARIANT", `${snap.cardVariant} ≠ ${exp.cardVariant} (fase ${exp.phase})`);

    // Varredura dos jobs do manifesto — conjuntos A/B/C/N/F agregados.
    let classA = 0, jobsWithClassA = 0, setB = 0, setC = 0, jobsWithC = 0,
        setF = 0, needsReview = 0, stray = 0, maxConfirm = 0, maxDecide = 0;
    const perJob = new Map();

    const inScope = jobs.filter((j) =>
      j.code && TARGET_SET.has(j.code) && (j.status === "STAGED" || j.status === "CONFIRMING"));

    for (const j of inScope) {
      const s = await loadSets(j.id);
      perJob.set(j.code, { job: j, sets: s });
      classA += s.A.length; if (s.A.length > 0) jobsWithClassA += 1;
      setB += s.B.length;
      setC += s.C.length;  if (s.C.length > 0) jobsWithC += 1;
      setF += s.F.length;
      needsReview += s.N.length;
      stray += s.strayC.length;
      maxDecide  = Math.max(maxDecide, s.A.length);
      maxConfirm = Math.max(maxConfirm, s.A.length + s.B.length + s.C.length);
      await sleep(80);
    }

    log(`  Classe A=${classA} em ${jobsWithClassA} jobs · B=${setB} · C=${setC} em ${jobsWithC} jobs`);
    log(`  N=${needsReview} · F=${setF} · SKIPPED fora do predicado C=${stray}`);
    log(`  max |A|=${maxDecide} (teto decide ${MAX_DECIDE_IDS}) · max |A∪B∪C|=${maxConfirm} (teto confirm ${MAX_CONFIRM_IDS})`);

    if (stray !== 0)      stop("UNEXPECTED_SKIPPED_KIND", `${stray} SKIPPED/PENDING fora de INVALID+SIZE_OUT_OF_SCOPE`);
    if (setF !== exp.setF) stop("FAILED_ROWS_PRESENT", `F=${setF} ≠ ${exp.setF} — nunca retry automático de FAILED`);
    if (setB !== exp.setB) stop("UNEXPECTED_APPROVED_PENDING", `B=${setB} ≠ ${exp.setB}`);
    if (classA !== exp.classA)             stop("BASELINE_CLASS_A", `${classA} ≠ ${exp.classA}`);
    if (jobsWithClassA !== exp.jobsWithClassA) stop("BASELINE_JOBS_WITH_CLASS_A", `${jobsWithClassA} ≠ ${exp.jobsWithClassA}`);
    if (setC !== exp.setC)                 stop("BASELINE_SET_C", `${setC} ≠ ${exp.setC}`);
    if (jobsWithC !== exp.jobsWithC)       stop("BASELINE_JOBS_WITH_C", `${jobsWithC} ≠ ${exp.jobsWithC}`);
    if (needsReview !== exp.needsReview)   stop("BASELINE_NEEDS_REVIEW", `${needsReview} ≠ ${exp.needsReview}`);
    if (maxDecide  > MAX_DECIDE_IDS)  stop("DECIDE_CEILING", `${maxDecide} > ${MAX_DECIDE_IDS}`);
    if (maxConfirm > MAX_CONFIRM_IDS) stop("CONFIRM_CEILING", `${maxConfirm} > ${MAX_CONFIRM_IDS}`);

    // Escopo da execução
    const scope = scopeCodes
      ? inScope.filter((j) => scopeCodes.includes(j.code))
      : inScope;
    if (scopeCodes) {
      const missing = scopeCodes.filter((c) => !scope.some((j) => j.code === c));
      if (missing.length) stop("CANARY_JOB_MISSING", missing.join(", "));
    }

    log(`✓ PRECHECK PASS — escopo desta execução: ${scope.length} job(s)`);
    return { jobs, snap, perJob, scope };
  }

  // ==========================================================================
  // § EXECUÇÃO POR JOB — state machine
  // ==========================================================================
  async function processJob(job) {
    const code = job.code;
    const pre = await loadSets(job.id);

    if (pre.strayC.length) stop("UNEXPECTED_SKIPPED_KIND", `${code}: ${pre.strayC.length} SKIPPED fora do predicado C`);
    if (pre.F.length)      stop("FAILED_ROWS_PRESENT", `${code}: F=${pre.F.length}`);
    if (pre.A.length > 0 && pre.B.length > 0)
      stop("RESUME_PARTIAL", `${code}: A=${pre.A.length} e B=${pre.B.length} simultâneos — decide é atômico; isto indica concorrência`);

    if (pre.A.length === 0 && pre.B.length === 0 && pre.C.length === 0) {
      return { code, outcome: pre.N.length > 0 ? "NO_CLASS_A_ROWS" : "ALREADY_DONE",
               deltaInserted: 0, deltaUnchanged: 0, needsReview: pre.N.length };
    }

    // ---- passo 1: decide, somente sobre A -----------------------------------
    if (pre.A.length > 0) {
      const n = await rpc("admin_decide_catalog_variant_import_row",
        { p_row_ids: pre.A, p_decision_status: "APPROVED" }, "NO_RESPONSE_DECIDE");
      if (n !== pre.A.length)
        stop("DECIDE_ROWS_MISMATCH", `${code}: rows_affected=${n} ≠ |A|=${pre.A.length}`);

      // ---- passo 2: RELER e provar que A virou B antes do confirm -----------
      const mid = await loadSets(job.id);
      const midB = new Set(mid.B);
      const naoMigrou = pre.A.filter((id) => !midB.has(id));
      if (naoMigrou.length)
        stop("DECIDE_NOT_REFLECTED", `${code}: ${naoMigrou.length} de ${pre.A.length} linhas não estão em B após decide`);
      if (mid.A.length !== 0)
        stop("DECIDE_LEFTOVER_A", `${code}: A=${mid.A.length} após decide — esperado 0`);
      if (mid.F.length) stop("FAILED_ROWS_PRESENT", `${code}: F apareceu após decide`);
    }

    // ---- passo 3: confirm com array EXPLÍCITO A∪B∪C -------------------------
    const cur = await loadSets(job.id);
    const S = [...cur.B, ...cur.C];
    if (S.length === 0) {
      return { code, outcome: "ALREADY_DONE", deltaInserted: 0, deltaUnchanged: 0, needsReview: cur.N.length };
    }
    if (S.length > MAX_CONFIRM_IDS) stop("CONFIRM_CEILING", `${code}: |S|=${S.length}`);

    const preInserted  = await restCount(`catalog_variant_import_row?select=id&job_id=eq.${job.id}&persistence_status=eq.INSERTED`);
    const preUnchanged = await restCount(`catalog_variant_import_row?select=id&job_id=eq.${job.id}&persistence_status=eq.UNCHANGED`);

    try {
      await rpc("admin_confirm_catalog_variant_import", { p_job_id: job.id, p_row_ids: S }, "NO_RESPONSE_CONFIRM");
    } catch (e) {
      if (e instanceof Stop && e.code === "NO_RESPONSE_CONFIRM") {
        await reconcileConfirmNoResponse(job, S);
      } else {
        throw e;
      }
    }

    // ---- passo 4: POST — delta por snapshot, NUNCA pelos contadores da RPC --
    const post = await loadSets(job.id);
    if (post.F.length) {
      const detail = await restGetAll("catalog_variant_import_row",
        `select=id,error_detail&job_id=eq.${job.id}&persistence_status=eq.FAILED`);
      log(`  ✗ ${code}: FAILED em ${detail.length} linha(s)`);
      for (const d of detail.slice(0, 10)) log(`      ${d.id} :: ${String(d.error_detail).slice(0, 160)}`);
      stop("CONFIRM_COMMITTED_WITH_FAILURES", `${code}: F=${post.F.length} — nenhum retry`);
    }
    const postInserted  = await restCount(`catalog_variant_import_row?select=id&job_id=eq.${job.id}&persistence_status=eq.INSERTED`);
    const postUnchanged = await restCount(`catalog_variant_import_row?select=id&job_id=eq.${job.id}&persistence_status=eq.UNCHANGED`);

    return {
      code,
      outcome: post.N.length > 0 ? "PARTIAL_OK_NEEDS_REVIEW_REMAIN" : "OK",
      deltaInserted:  postInserted  - preInserted,
      deltaUnchanged: postUnchanged - preUnchanged,
      needsReview: post.N.length,
    };
  }

  // ==========================================================================
  // § NETWORK_ERROR_NO_RESPONSE no CONFIRM — re-derivação, nunca retry cego
  //
  //   A RPC captura exceção POR ROW e pode COMMITAR com parte INSERTED/
  //   UNCHANGED e parte FAILED. Portanto "parte saiu de PENDING" NÃO é
  //   impossível — e é justamente por isso que não se retenta.
  // ==========================================================================
  async function reconcileConfirmNoResponse(job, S) {
    log(`  ⚠ ${job.code}: confirm sem resposta — re-derivando estado do banco (sem retry cego)`);
    const rows = await restGetAll(
      "catalog_variant_import_row",
      `select=id,decision_status,persistence_status&job_id=eq.${job.id}`
    );
    const byId = new Map(rows.map((r) => [r.id, r]));
    let stillPending = 0, terminal = 0, failed = 0, missing = 0;
    for (const id of S) {
      const r = byId.get(id);
      if (!r) { missing += 1; continue; }
      if (r.persistence_status === "PENDING") stillPending += 1;
      else if (r.persistence_status === "FAILED") failed += 1;
      else terminal += 1;   // INSERTED | UNCHANGED
    }
    if (missing) stop("INDETERMINATE_CONFIRM_STATE", `${job.code}: ${missing} id(s) de S sumiram da leitura`);

    // C — qualquer FAILED encerra. Precede B por ser o caso mais grave.
    if (failed > 0) {
      const detail = await restGetAll("catalog_variant_import_row",
        `select=id,error_detail&job_id=eq.${job.id}&persistence_status=eq.FAILED`);
      for (const d of detail.slice(0, 20)) log(`      ${d.id} :: ${String(d.error_detail).slice(0, 160)}`);
      stop("CONFIRM_COMMITTED_WITH_FAILURES", `${job.code}: ${failed} FAILED — nenhum retry, ids e error_detail acima`);
    }
    // A — nada saiu de PENDING: a chamada não produziu persistência observável.
    if (stillPending === S.length && terminal === 0) {
      log(`  ↻ ${job.code}: nenhuma linha saiu de PENDING — estado revalidado, nova chamada permitida`);
      const fresh = await loadSets(job.id);
      if (fresh.F.length) stop("FAILED_ROWS_PRESENT", `${job.code}: F apareceu na revalidação`);
      const S2 = [...fresh.B, ...fresh.C];
      if (S2.length === 0) return;
      await rpc("admin_confirm_catalog_variant_import", { p_job_id: job.id, p_row_ids: S2 }, "NO_RESPONSE_CONFIRM_RETRY");
      return;
    }
    // B — todas terminais e zero FAILED: a chamada foi aplicada.
    if (terminal === S.length && stillPending === 0) {
      log(`  ✓ ${job.code}: confirm foi aplicado (todas as ${S.length} linhas terminais, 0 FAILED)`);
      return;
    }
    // D — mistura inesperada.
    stop("INDETERMINATE_CONFIRM_STATE",
      `${job.code}: PENDING=${stillPending} terminal=${terminal} FAILED=${failed} de |S|=${S.length} — concorrência ou divergência, não retry`);
  }

  // ==========================================================================
  // § POSTCHECK
  // ==========================================================================
  async function postcheck(pre, results) {
    const exp = EXPECTED[RUN_MODE];
    const jobs = await loadJobs();
    const snap = await snapshotGlobal(jobs);

    const deltaInserted  = results.reduce((a, r) => a + r.deltaInserted, 0);
    const deltaUnchanged = results.reduce((a, r) => a + r.deltaUnchanged, 0);
    const deltaCardVariant = snap.cardVariant - pre.snap.cardVariant;

    log("");
    log("— POSTCHECK —");
    log(`  Δ card_variant (execução) = ${deltaCardVariant}  (esperado ${exp.execDelta})`);
    log(`  card_variant agora        = ${snap.cardVariant}  (esperado ${exp.cardVariantAfter})`);
    log(`  Δ INSERTED por snapshot   = ${deltaInserted}`);
    log(`  Δ UNCHANGED por snapshot  = ${deltaUnchanged}`);
    log(`  TARGET STAGED=${snap.targetStaged} COMPLETED=${snap.targetCompleted}`);

    if (deltaCardVariant !== exp.execDelta)
      stop("POST_DELTA_CARD_VARIANT", `${deltaCardVariant} ≠ ${exp.execDelta}`);
    if (snap.cardVariant !== exp.cardVariantAfter)
      stop("POST_CARD_VARIANT", `${snap.cardVariant} ≠ ${exp.cardVariantAfter}`);
    if (deltaInserted !== exp.execDelta)
      stop("POST_DELTA_INSERTED", `${deltaInserted} ≠ ${exp.execDelta}`);

    // DEFERRED e SM12 intocados
    const outsideNow = jobs.filter((j) => j.status === "STAGED" && (!j.code || !TARGET_SET.has(j.code))).map((j) => j.code);
    const outsideBefore = pre.snap.stagedOutside.map((j) => j.code);
    if (JSON.stringify(outsideNow.sort()) !== JSON.stringify(outsideBefore.sort()))
      stop("DEFERRED_TOUCHED", `STAGED fora do manifesto mudou: ${outsideBefore} → ${outsideNow}`);

    // F global
    const failedNow = await restCount("catalog_variant_import_row?select=id&persistence_status=eq.FAILED");
    if (failedNow !== 0) stop("FAILED_ROWS_PRESENT", `F global=${failedNow} após a execução`);

    log("✓ POSTCHECK PASS");
    return { snap, deltaCardVariant, deltaInserted, deltaUnchanged };
  }

  // ==========================================================================
  // § MAIN
  // ==========================================================================
  try {
    log("=".repeat(78));
    log(`BULK-STP-01 / CLASSE A — RUN_MODE = ${RUN_MODE}   (${started.toISOString()})`);
    log("=".repeat(78));

    if (PROJECT_REF.startsWith("COLE_") || ANON_KEY.startsWith("COLE_"))
      stop("CONFIG_MISSING", "preencha PROJECT_REF e ANON_KEY");
    if (!["DRY_RUN", "CANARY", "FULL"].includes(RUN_MODE))
      stop("RUN_MODE_INVALID", RUN_MODE);

    assertManifest();

    const scopeCodes = RUN_MODE === "CANARY" ? [...CANARY_SET_CODES] : null;
    const pre = await precheck(scopeCodes);

    if (RUN_MODE === "DRY_RUN") {
      log("");
      log("DRY_RUN concluído — SOMENTE LEITURA. Nada foi decidido, confirmado ou materializado.");
      log("Para CANARY ou FULL: edite a constante RUN_MODE. Não há transição automática.");
      log("=".repeat(78));
      return;
    }

    log("");
    log(`— ${RUN_MODE} LIVE — ${pre.scope.length} job(s) —`);
    const results = [];
    for (const job of pre.scope) {
      const r = await processJob(job);
      results.push(r);
      log(`  ${r.outcome.padEnd(32)} ${String(r.code).padEnd(10)} +${r.deltaInserted} INSERTED · +${r.deltaUnchanged} UNCHANGED · N=${r.needsReview}`);
      await sleep(PACE_MS);
    }

    await postcheck(pre, results);

    log("");
    log("RESUMO POR JOB");
    for (const r of results) log(`  ${String(r.code).padEnd(10)} ${r.outcome}`);
    log("=".repeat(78));
    log(`${RUN_MODE} concluído. NÃO há transição automática para a próxima fase.`);
    log("=".repeat(78));
  } catch (e) {
    console.error("");
    console.error("█".repeat(78));
    if (e instanceof Stop) console.error(`STOP ${e.code}: ${e.detail}`);
    else console.error(`STOP UNEXPECTED: ${e && e.message ? e.message : e}`);
    console.error("Nenhuma fase posterior deve ser iniciada até a causa ser entendida.");
    console.error("█".repeat(78));
  }
})();
