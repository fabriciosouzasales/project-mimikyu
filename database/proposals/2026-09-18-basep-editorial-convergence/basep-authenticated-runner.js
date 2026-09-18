/* =============================================================================
 * BASEP — RUNNER AUTENTICADO EFÊMERO
 * =============================================================================
 * Mandato...: BASEP — IMPLEMENTATION STAGING-01 / RUNNER CORRECTION-02
 * Versão....: 1.2
 * Status....: EXECUTADO — LIVE 2026-09-18 (18 RPCs, 02:5x UTC). Evidência histórica;
 *             NÃO reexecutar: os checkpoints passam a bater e o script vira no-op.
 * Data......: 2026-09-18
 *
 * -----------------------------------------------------------------------------
 * O QUE ISTO É — E O QUE NÃO É
 * -----------------------------------------------------------------------------
 * NÃO é produto. NÃO é importado por nada. NÃO está em `web/`. Não há build,
 * bundle, rota ou deploy que o alcance. É um artefato de EVIDÊNCIA desta rodada,
 * feito para ser colado uma vez no console do DevTools e morrer com o refresh
 * da aba.
 *
 * COMO EXECUTAR (quando autorizado)
 *   1. Abrir a aplicação JÁ AUTENTICADO como administrador.
 *   2. Manter a aba EM FOCO — `SessionRefresher` só renova o token com a aba
 *      ativa, e o middleware de refresh está órfão desde 2026-08-14.
 *   3. Preencher ANON_KEY abaixo (pública por desenho — ver nota de segurança).
 *   4. Colar tudo no console e pressionar Enter.
 *
 * -----------------------------------------------------------------------------
 * v1.2 — CORREÇÃO DE RUNNER CORRECTION-02: RESUMABILIDADE VERDADEIRA
 * -----------------------------------------------------------------------------
 * BLOCKER CORRIGIDO. Na v1.1 o preflight identificava as rows da convergência
 * por `validation_status = NEEDS_REVIEW` e exigia `valid_rows = 47` + 27
 * resíduos. Mas cada mapping das Fases C/E faz COMMIT sozinho e TRANSFORMA
 * parte dessas 27 em VALID. Logo, depois da primeira escrita o próprio
 * preflight passava a reprovar — o rerun morria em A2/A3 antes de chegar aos
 * checkpoints. A resumabilidade era nominal, não real.
 *
 * Correção:
 *   1. IDENTIDADE POR ASSINATURA, NÃO POR ESTADO. A Fase A lê as 74 rows e
 *      separa as 27 da convergência pelas 12 assinaturas de `raw_data`. A
 *      assinatura é imutável — não muda quando a row é revalidada.
 *   2. JOB PREFLIGHT RESUMÍVEL. Não se exige mais `valid_rows = 47`; exige-se
 *      que `valid_rows` seja IGUAL à contagem real de VALID nas 74 rows e que
 *      esteja na janela legítima [47, 72].
 *   3. INVARIANTE DE WORKFLOW em qualquer estado retomável: as 47 fora do
 *      conjunto sempre VALID/APPROVED/INSERTED; as 27 sempre PENDING/PENDING;
 *      as 2 deferidas sempre NEEDS_REVIEW; as outras 25 apenas NEEDS_REVIEW ou
 *      VALID. Qualquer outro estado => STOP.
 *   4. `anchor(sig)` passa a vir do grupo das 27, independente do
 *      `validation_status` corrente.
 *   5. CHECKPOINT FAIL-EARLY nas Fases C e E: o grupo da assinatura é RELIDO
 *      no momento da checagem — mapping presente exige o grupo inteiro VALID;
 *      mapping ausente exige o grupo inteiro NEEDS_REVIEW. Um mapping que
 *      existe não pode mascarar propagação incompleta ou drift de staging.
 *
 * -----------------------------------------------------------------------------
 * v1.1 — CORREÇÕES DE RUNNER CORRECTION-01 (mantidas)
 * -----------------------------------------------------------------------------
 *   1. COOKIE. Base64-URL (codec do @supabase/ssr 0.5.2), chunks CONTÍGUOS,
 *      `TextDecoder({ fatal: true })`, base não-fragmentado com precedência.
 *   2. TOKEN NÃO CONGELADO — relido a cada `rpc()` / `sel()`.
 *   3. IDENTIDADE CANÔNICA COMPLETA nos checkpoints.
 *   4. GATES DE RETORNO explícitos e por objeto.
 *   5. GATE FINAL com leitura do job e PROVA DE WORKFLOW.
 *
 * -----------------------------------------------------------------------------
 * SEGURANÇA — O QUE ESTE SCRIPT FAZ E NÃO FAZ
 * -----------------------------------------------------------------------------
 *   - USA a sessão administrativa REAL já existente no navegador.
 *   - NÃO imprime o access token. Em lugar nenhum. Nenhum `log` o recebe.
 *   - NÃO copia o token para arquivo, disco, chat ou rede de terceiros. Ele é
 *     lido de `document.cookie` e usado no header da mesma request.
 *   - NÃO grava localStorage, sessionStorage nem cookie.
 *   - NÃO usa `service_role`.
 *   - NÃO fabrica JWT.
 *   - NÃO usa SET ROLE nem request.jwt.claims.
 *   - NÃO cria usuário temporário.
 *   - NÃO chama worker `internal.*` com actor_id simulado — só wrappers
 *     `public.admin_*`, que executam `is_admin()` e derivam o ator de
 *     `auth.uid()`.
 *   - NÃO decide e NÃO persiste nenhuma row — isso é da UI.
 *   - NÃO tem dependência externa. Só `fetch`, `atob`, `TextDecoder`, `JSON`.
 *
 *   ANON_KEY: é a publishable/anon key. O próprio repositório a documenta como
 *   "segura para o navegador" (`web/lib/supabase/client.ts`), ela é
 *   `NEXT_PUBLIC_*`, está inlinada no bundle de toda página e já viaja em toda
 *   requisição que a aplicação faz. Não é credencial de sessão.
 *
 * -----------------------------------------------------------------------------
 * ATOMICIDADE — LEIA ANTES DE EXECUTAR
 * -----------------------------------------------------------------------------
 * NÃO EXISTE TRANSAÇÃO ENTRE AS 18 RPCs. Cada chamada é a sua própria
 * transação e faz COMMIT sozinha. Um erro na chamada N NÃO desfaz as N-1
 * anteriores. É FALSO dizer "falha = zero escrita" depois que a primeira
 * escrita ocorreu.
 *
 * Por isso o runner é FAIL-CLOSED e RESUMABLE:
 *   - FAIL-CLOSED: para na PRIMEIRA divergência e não tenta compensar.
 *   - RESUMABLE:   antes de cada objeto, consulta o estado corrente.
 *                    ausente                   -> executa
 *                    presente e IDÊNTICO       -> checkpoint concluído, segue
 *                    presente e DIVERGENTE     -> STOP
 *                  Nunca repete uma criação às cegas. Reexecutar o script
 *                  inteiro após uma parada é seguro e retoma de onde parou —
 *                  em QUALQUER ponto da sequência (ver v1.2 acima).
 * ========================================================================== */

(async () => {
  "use strict";

  // ---------------------------------------------------------------------------
  // CONFIGURAÇÃO
  // ---------------------------------------------------------------------------
  const PROJECT_REF  = "qjfutqujxrbzgrtkpgkg";
  const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
  const ANON_KEY     = "COLE_AQUI_A_NEXT_PUBLIC_SUPABASE_ANON_KEY";

  const JOB_ID       = "cf829d56-921c-4e97-983d-0aec56690464"; // BASEP, STAGED
  const SET_CODE     = "basep";
  const SOURCE_CODE  = "TCGDEX";
  const GAME_CODE    = "POKEMON";

  const DRY_RUN = false; // true = só preflight + diagnóstico, nenhuma escrita

  // ---------------------------------------------------------------------------
  // INFRA
  // ---------------------------------------------------------------------------
  const log  = (...a) => console.log("[BASEP]", ...a);
  const fail = (code, detail) => {
    console.error("[BASEP] STOP:", code, detail ?? "");
    throw new Error(`STOP ${code}`);
  };

  /**
   * Base64-URL -> bytes. Codec do @supabase/ssr 0.5.2.
   * `atob` sozinho NÃO serve: o alfabeto usa `-` e `_`, e o padding é omitido.
   */
  function base64UrlToBytes(input) {
    let t = String(input).replace(/-/g, "+").replace(/_/g, "/");
    const rest = t.length % 4;
    if (rest === 2) t += "==";
    else if (rest === 3) t += "=";
    else if (rest === 1) return null; // comprimento impossível em base64
    let bin;
    try { bin = atob(t); } catch { return null; }
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i += 1) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }

  /**
   * Lê o access token do cookie do @supabase/ssr (0.5.2).
   *
   * O cookie NÃO é httpOnly — é escrito por `document.cookie` pelo
   * SessionRefresher (ver comentário em web/components/auth/session-refresher.tsx).
   *
   * Regras:
   *   - o cookie base NÃO fragmentado tem PRECEDÊNCIA;
   *   - se ausente, reconstrói SOMENTE chunks CONTÍGUOS (.0, .1, .2 …) e para
   *     no primeiro índice ausente — nunca coleta por `startsWith`;
   *   - prefixo `base64-` => payload Base64-URL => bytes => UTF-8 => JSON.
   *
   * O valor NUNCA é retornado ao console, logado ou serializado.
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
      const chunks = [];
      for (let i = 0; ; i += 1) {
        const piece = jar[`${base}.${i}`];
        if (piece === undefined) break; // contiguidade: para no primeiro buraco
        chunks.push(piece);
      }
      if (chunks.length === 0) return null;
      raw = chunks.join("");
    }

    let s;
    try { s = decodeURIComponent(raw); } catch { s = raw; }

    if (s.startsWith("base64-")) {
      const bytes = base64UrlToBytes(s.slice(7));
      if (bytes === null) return null;
      try {
        s = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      } catch {
        return null;
      }
    }

    let parsed;
    try { parsed = JSON.parse(s); } catch { return null; }

    const tok = Array.isArray(parsed)
      ? parsed[0]
      : (parsed.access_token ?? parsed?.currentSession?.access_token);

    return typeof tok === "string" && tok.length > 0 ? tok : null;
  }

  /**
   * Monta os headers RELENDO o token agora. Não há token congelado: se a
   * sessão sumiu entre uma chamada e outra, paramos ANTES de emitir a request.
   */
  function authHeaders(where) {
    const tok = readAccessToken();
    if (!tok) {
      fail("SESSION_LOST",
        `Sessão ausente/ilegível no cookie antes de: ${where}. Faça login novamente, mantenha a aba em foco e reexecute o script (ele é resumable).`);
    }
    return {
      apikey: ANON_KEY,
      Authorization: `Bearer ${tok}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    };
  }

  async function rpc(fn, body) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
      method: "POST", headers: authHeaders(`rpc ${fn}`), body: JSON.stringify(body ?? {}),
    });
    const txt = await r.text();
    let data = null;
    try { data = txt ? JSON.parse(txt) : null; } catch { data = txt; }
    if (!r.ok) fail(`RPC_${fn}_HTTP_${r.status}`, data);
    return data;
  }

  async function sel(path) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
      headers: authHeaders(`select ${path.split("?")[0]}`),
    });
    const txt = await r.text();
    if (!r.ok) fail(`SELECT_HTTP_${r.status}`, txt);
    return txt ? JSON.parse(txt) : [];
  }

  const one = (out) => (Array.isArray(out) ? out[0] : out);

  const sameSet = (a, b) => {
    const x = [...(a || [])].sort(), y = [...(b || [])].sort();
    return x.length === y.length && x.every((v, i) => v === y[i]);
  };

  /** Compara campos escalares esperados; devolve lista de divergências. */
  const diffFields = (got, want) =>
    Object.keys(want)
      .filter((k) => got[k] !== want[k])
      .map((k) => `${k}: esperado ${JSON.stringify(want[k])}, obtido ${JSON.stringify(got[k])}`);

  const q = encodeURIComponent;

  /**
   * Assinatura textual estável de uma row, derivada SOMENTE de raw_data.
   * É IMUTÁVEL: não muda quando a row é revalidada. É o que torna a
   * resumabilidade real — identificamos as 27 pelo que elas SÃO, não pelo
   * estado em que estão.
   */
  const sigOf = (row) => {
    const d = row.raw_data || {};
    const stamp = Array.isArray(d.stamp) ? d.stamp.join("+") : null;
    return `${d.type || "?"}|${stamp ? "stamp:" + stamp : "subtype:" + (d.subtype || "")}`;
  };

  // As 12 assinaturas da convergência e a cardinalidade exata de cada uma.
  const EXPECTED_SIGS = {
    "normal|stamp:1st-movie": 4,
    "normal|stamp:1st-movie-inverted": 4,
    "normal|stamp:pikachu-tail": 6,
    "normal|stamp:pokemon-4-ever": 2,
    "normal|stamp:pokemon-center-ny": 2,
    "normal|stamp:jr-stamp-rally": 1,
    "normal|stamp:grey-star": 1,
    "normal|stamp:1st-edition-error": 1,
    "normal|subtype:glossy": 1,
    "normal|subtype:aoki-error": 3,
    "holo|stamp:pikachu-tail": 1,
    "holo|subtype:missing-hp": 1,
  };

  // As duas deferidas: NUNCA podem sair de NEEDS_REVIEW.
  const DEFERRED_SIGS = ["holo|stamp:pikachu-tail", "holo|subtype:missing-hp"];

  // ===========================================================================
  // FASE A — AUTH PROBE + PREFLIGHT RESUMÍVEL (100% READ-ONLY)
  // ===========================================================================
  log("— FASE A: auth probe + preflight resumível —");

  // Somente booleano. O token em si nunca é impresso.
  log("sessão resolvida:", readAccessToken() !== null);
  if (ANON_KEY.startsWith("COLE_AQUI")) {
    fail("A0_NO_ANON_KEY", "Preencha ANON_KEY antes de executar.");
  }

  const isAdmin = await rpc("is_admin", {});
  log("is_admin():", isAdmin);
  if (isAdmin !== true) fail("A1_NOT_ADMIN", "is_admin() não retornou TRUE. Nenhuma escrita foi feita.");

  // --- A2. As 74 rows, com estado completo ----------------------------------
  const all = await sel(
    `catalog_variant_import_row?job_id=eq.${JOB_ID}` +
    `&select=id,raw_data,validation_status,decision_status,persistence_status`);
  if (all.length !== 74) fail("A2_TOTAL_ROWS", `esperado 74 rows no job, obtido ${all.length}`);

  // --- A3. Separação por ASSINATURA (imutável), não por estado ---------------
  const bySig = {};
  const convergence = [];
  const historicas = [];
  for (const row of all) {
    const sig = sigOf(row);
    if (sig in EXPECTED_SIGS) {
      (bySig[sig] ||= []).push(row);
      convergence.push(row);
    } else {
      historicas.push(row);
    }
  }

  for (const [sig, n] of Object.entries(EXPECTED_SIGS)) {
    const got = (bySig[sig] || []).length;
    if (got !== n) fail("A3_SIGNATURE_DRIFT", `${sig}: esperado ${n} rows, obtido ${got}`);
  }
  if (convergence.length !== 27) fail("A3_CONVERGENCE_COUNT", `esperado 27 rows nas 12 assinaturas, obtido ${convergence.length}`);
  if (historicas.length !== 47) fail("A3_HISTORIC_COUNT", `esperado 47 rows fora das 12 assinaturas, obtido ${historicas.length}`);

  const CONVERGENCE_IDS = convergence.map((r) => r.id);
  const convergenceSet = new Set(CONVERGENCE_IDS);
  log(`separação por assinatura: ${convergence.length} convergência · ${historicas.length} históricas`);

  // --- A4. INVARIANTE DE WORKFLOW (vale em QUALQUER estado retomável) --------
  {
    const bad = historicas.filter(
      (r) => r.validation_status !== "VALID" || r.decision_status !== "APPROVED" || r.persistence_status !== "INSERTED");
    if (bad.length) {
      fail("A4_HISTORIC_DRIFT",
        `${bad.length} das 47 rows históricas não estão em VALID/APPROVED/INSERTED. Estado do job foi alterado fora deste fluxo — STOP.`);
    }
  }
  {
    const bad = convergence.filter(
      (r) => r.decision_status !== "PENDING" || r.persistence_status !== "PENDING");
    if (bad.length) {
      fail("A4_CONVERGENCE_DECIDED",
        `${bad.length} das 27 rows da convergência já têm decisão/persistência. A decisão é da UI, não do runner — STOP.`);
    }
  }
  for (const sig of DEFERRED_SIGS) {
    const bad = (bySig[sig] || []).filter((r) => r.validation_status !== "NEEDS_REVIEW");
    if (bad.length) {
      fail("A4_DEFERRED_RESOLVED",
        `${sig}: deve permanecer NEEDS_REVIEW sempre, mas ${bad.length} row(s) saíram desse estado — STOP.`);
    }
  }
  {
    const resolviveis = convergence.filter((r) => !DEFERRED_SIGS.includes(sigOf(r)));
    const bad = resolviveis.filter(
      (r) => r.validation_status !== "NEEDS_REVIEW" && r.validation_status !== "VALID");
    if (bad.length) {
      fail("A4_UNEXPECTED_VALIDATION",
        `${bad.length} das 25 rows resolvíveis estão em estado diferente de NEEDS_REVIEW/VALID — STOP.`);
    }
    log(`25 resolvíveis: ${resolviveis.filter((r) => r.validation_status === "VALID").length} VALID · ${resolviveis.filter((r) => r.validation_status === "NEEDS_REVIEW").length} NEEDS_REVIEW`);
  }

  // --- A5. Cabeçalho do job, coerente com a contagem REAL --------------------
  const validNow = all.filter((r) => r.validation_status === "VALID").length;
  const [job0] = await sel(`catalog_variant_import_job?id=eq.${JOB_ID}&select=id,status,total_rows,valid_rows,external_set_id`);
  if (!job0) fail("A5_JOB_NOT_FOUND", JOB_ID);
  log("job:", job0.external_set_id, job0.status, `${job0.total_rows}/${job0.valid_rows}`, `(VALID real = ${validNow})`);
  {
    const d = diffFields(job0, { status: "STAGED", total_rows: 74, external_set_id: SET_CODE });
    if (d.length) fail("A5_JOB_BASELINE", d.join(" · "));
  }
  if (job0.valid_rows !== validNow) {
    fail("A5_JOB_VALID_MISMATCH", `job.valid_rows=${job0.valid_rows} difere da contagem real de VALID=${validNow}`);
  }
  if (validNow < 47 || validNow > 72) {
    fail("A5_JOB_VALID_WINDOW", `VALID=${validNow} fora da janela legítima [47, 72] desta convergência`);
  }

  /** Âncora: qualquer row do grupo, independente do validation_status atual. */
  const anchor = (sig) => (bySig[sig] || [])[0]?.id;

  /** IDs do grupo de uma assinatura. */
  const groupIds = (sig) => (bySig[sig] || []).map((r) => r.id);

  /**
   * RELÊ o grupo agora e exige que TODO ele esteja no `expected`.
   * Também reafirma o invariante PENDING/PENDING. Um mapping já existente não
   * pode mascarar propagação incompleta nem drift de staging.
   */
  async function assertGroup(ctx, sig, expected) {
    const ids = groupIds(sig);
    if (ids.length === 0) fail(`${ctx}_GROUP_EMPTY`, sig);
    const rows = await sel(
      `catalog_variant_import_row?id=in.(${ids.join(",")})` +
      `&select=id,validation_status,decision_status,persistence_status`);
    if (rows.length !== ids.length) {
      fail(`${ctx}_GROUP_READ`, `${sig}: esperado ${ids.length} rows, lidas ${rows.length}`);
    }
    const badState = rows.filter((r) => r.validation_status !== expected);
    if (badState.length) {
      fail(`${ctx}_GROUP_STATE`,
        `${sig}: esperado TODAS as ${ids.length} rows em ${expected}, ${badState.length} divergente(s). Propagação incompleta ou drift — STOP.`);
    }
    const badFlow = rows.filter((r) => r.decision_status !== "PENDING" || r.persistence_status !== "PENDING");
    if (badFlow.length) {
      fail(`${ctx}_GROUP_WORKFLOW`, `${sig}: ${badFlow.length} row(s) já decididas/persistidas — STOP.`);
    }
  }

  // --- A6. Identidade canônica: Game e Asset Source resolvidos por code ------
  const [game] = await sel(`game?code=eq.${GAME_CODE}&select=id,code`);
  if (!game) fail("A6_GAME_NOT_FOUND", GAME_CODE);

  const [source] = await sel(`asset_source?code=eq.${SOURCE_CODE}&select=id,code,is_active`);
  if (!source) fail("A6_SOURCE_NOT_FOUND", SOURCE_CODE);
  if (source.is_active !== true) fail("A6_SOURCE_INACTIVE", SOURCE_CODE);
  log("game/source resolvidos por code.");

  // --- A7. Traits: 8 no total; os 4 relevantes validados campo a campo -------
  const traits = await sel(`card_printing_trait?game_id=eq.${game.id}&select=id,code,name,display_order,is_active`);
  const traitBy = Object.fromEntries(traits.map((t) => [t.code, t]));
  log("traits POKEMON:", traits.length);
  if (traits.length !== 8) {
    fail("A7_TRAIT_COUNT", `esperado 8 (5 da Query 2169 + 3 da Query 2201), obtido ${traits.length}. Aplique a 2201 antes do runner.`);
  }
  const TRAIT_EXPECT = {
    GREY_STAR_SYMBOL: { display_order: 6, is_active: true },
    GLOSSY_STOCK:     { display_order: 7, is_active: true },
    AOKI_CREDIT:      { display_order: 8, is_active: true },
    FIRST_EDITION:    { display_order: 1, is_active: true },
  };
  for (const [code, want] of Object.entries(TRAIT_EXPECT)) {
    const t = traitBy[code];
    if (!t) fail("A7_TRAIT_MISSING", `${code} — aplique a migration 2201 antes de rodar o runner.`);
    const d = diffFields(t, { code, ...want });
    if (d.length) fail("A7_TRAIT_DIVERGENT", `${code}: ${d.join(" · ")}`);
  }

  // --- A8. VT STANDARD: por game_id + code, validado campo a campo -----------
  const [vtStandard] = await sel(`card_variant_type?game_id=eq.${game.id}&code=eq.STANDARD&select=id,code,name,description,display_order,is_active`);
  if (!vtStandard) fail("A8_VT_STANDARD_NOT_FOUND");
  {
    const d = diffFields(vtStandard, {
      code: "STANDARD",
      name: "Padrão",
      description: "Versão principal da Card, conforme sua impressão editorial padrão.",
      display_order: 1,
      is_active: true,
    });
    if (d.length) fail("A8_VT_STANDARD_DIVERGENT", d.join(" · "));
  }

  log("PREFLIGHT OK. Nenhuma escrita até aqui.");
  if (DRY_RUN) { log("DRY_RUN=true — encerrando antes da primeira escrita."); return; }

  // ===========================================================================
  // FASE B — 3 PROFILES  (RPC: admin_create_card_printing_profile_with_backfill)
  // ===========================================================================
  log("— FASE B: profiles —");

  const PROFILES = [
    { code: "GREY_STAR_GLOSSY", name: "Estrela Cinza · Stock Brilhante", order: 8,
      traits: ["GREY_STAR_SYMBOL", "GLOSSY_STOCK"],
      desc: "Tiragem com símbolo de coleção estrela cinza e card stock brilhante (Hyper CoroCoro, Japão, 1999)." },
    { code: "GLOSSY", name: "Stock Brilhante", order: 9,
      traits: ["GLOSSY_STOCK"],
      desc: "Tiragem em card stock japonês brilhante da mesma impressão inglesa (Gotta Comic, Japão, 2000)." },
    { code: "AOKI_CREDIT", name: "Crédito Toshinao Aoki", order: 10,
      traits: ["AOKI_CREDIT"],
      desc: "Tiragem que credita Toshinao Aoki no lugar de Naoyo Kimura; corrigida em tiragem posterior." },
  ];

  for (const p of PROFILES) {
    const want = p.traits.map((c) => traitBy[c].id);

    // Checkpoint por identidade canônica: game_id + code.
    const [cur] = await sel(
      `card_printing_profile?game_id=eq.${game.id}&code=eq.${q(p.code)}` +
      `&select=id,game_id,code,name,description,display_order,is_active,traits_signature`);

    if (cur) {
      const d = diffFields(cur, {
        game_id: game.id, code: p.code, name: p.name,
        description: p.desc, display_order: p.order, is_active: true,
      });
      if (!sameSet(cur.traits_signature, want)) d.push("traits_signature difere do esperado");
      if (d.length) fail("B_PROFILE_DIVERGENT", `${p.code}: ${d.join(" · ")}`);
      log(`  ✓ checkpoint já concluído: ${p.code}`);
      continue;
    }

    const row = one(await rpc("admin_create_card_printing_profile_with_backfill", {
      p_code: p.code, p_name: p.name, p_description: p.desc,
      p_display_order: p.order, p_trait_ids: want,
    }));
    log(`  + ${p.code}`, row);
    if (!row?.profile_id) fail("B_PROFILE_NO_ID", p.code);
    if (!sameSet(row.traits_signature, want)) fail("B_PROFILE_SIGNATURE", p.code);
    // Criar Profile não cria routing: nenhum token externo passa a resolver por
    // causa dele. Nada pode ser revalidado, nada pode ficar pendente, nenhum
    // job pode ser afetado — em fresh run OU em retomada.
    {
      const d = diffFields(row, {
        rows_touched: 0, rows_revalidated: 0, rows_still_pending: 0, jobs_affected: 0,
      });
      if (d.length) fail("B_PROFILE_GATE", `${p.code}: ${d.join(" · ")}`);
    }
  }

  // ===========================================================================
  // FASE C — 4 PRINTING MAPPINGS
  //          (RPC: admin_resolve_catalog_variant_import_printing_mapping)
  // ===========================================================================
  log("— FASE C: printing mappings —");

  const PRINTING = [
    { sig: "normal|stamp:grey-star",         field: "stamp",   token: "grey-star",         norm: "GREY-STAR",
      traits: ["GREY_STAR_SYMBOL", "GLOSSY_STOCK"], rows_updated: 1 },
    { sig: "normal|subtype:glossy",          field: "subtype", token: "glossy",            norm: "GLOSSY",
      traits: ["GLOSSY_STOCK"],                     rows_updated: 1 },
    { sig: "normal|subtype:aoki-error",      field: "subtype", token: "aoki-error",        norm: "AOKI-ERROR",
      traits: ["AOKI_CREDIT"],                      rows_updated: 3 },
    { sig: "normal|stamp:1st-edition-error", field: "stamp",   token: "1st-edition-error", norm: "1ST-EDITION-ERROR",
      traits: ["FIRST_EDITION"],                    rows_updated: 1 },
  ];

  for (const m of PRINTING) {
    const want = m.traits.map((c) => traitBy[c].id);

    // Checkpoint por identidade canônica completa do routing de Printing.
    const [cur] = await sel(
      `card_printing_external_mapping?game_id=eq.${game.id}&asset_source_id=eq.${source.id}` +
      `&raw_field=eq.${q(m.field)}&normalized_token=eq.${q(m.norm)}&is_active=is.true` +
      `&select=id,game_id,asset_source_id,raw_field,normalized_token,is_active,traits_signature`);

    if (cur) {
      if (!sameSet(cur.traits_signature, want)) {
        fail("C_PRINTING_DIVERGENT",
          `${m.field}:${m.token} já existe ATIVO com traits_signature diferente da esperada.`);
      }
      // FAIL-EARLY: mapping presente exige o grupo INTEIRO já propagado.
      await assertGroup("C", m.sig, "VALID");
      log(`  ✓ checkpoint já concluído: ${m.field}:${m.token} (grupo inteiro VALID)`);
      continue;
    }

    // FAIL-EARLY: mapping ausente exige o grupo INTEIRO ainda não resolvido.
    await assertGroup("C", m.sig, "NEEDS_REVIEW");

    const rowId = anchor(m.sig);
    if (!rowId) fail("C_ANCHOR_MISSING", m.sig);

    const row = one(await rpc("admin_resolve_catalog_variant_import_printing_mapping", {
      p_row_id: rowId, p_raw_field: m.field, p_token: m.token, p_trait_ids: want,
    }));
    log(`  + ${m.field}:${m.token}`, row);
    if (!row?.mapping_id) fail("C_PRINTING_NO_ID", m.token);
    // GATE: cardinalidade exata + zero pendência + cross-job restrito a BASEP.
    {
      const d = diffFields(row, {
        rows_updated: m.rows_updated, rows_still_pending: 0, jobs_affected: 1,
      });
      if (d.length) fail("C_PRINTING_GATE", `${m.token}: ${d.join(" · ")}`);
    }
  }

  // ===========================================================================
  // FASE D — 5 VARIANT TYPES  (RPC: admin_create_card_variant_type)
  //          NÃO usar *_with_import_mapping: ele cria mapping GLOBAL.
  // ===========================================================================
  log("— FASE D: variant types —");

  const VTS = [
    { code: "STANDARD_FIRST_MOVIE",          name: "Padrão Pokémon The First Movie",                   order: 90,
      desc: "Versão principal da carta com o selo promocional em gold foil \"Kids WB Presents Pokémon The First Movie\", aplicado no canto superior direito após a impressão." },
    { code: "STANDARD_FIRST_MOVIE_INVERTED", name: "Padrão Pokémon The First Movie — Selo Invertido",  order: 91,
      desc: "Mesmo selo da variedade anterior, aplicado 180° invertido e no canto inferior esquerdo — erro de orientação de fábrica catalogado no guia de erros da PSA. Variedade editorial distinta, não defeito de exemplar." },
    { code: "STANDARD_PIKACHU_WORLD_2000",   name: "Padrão Pikachu World Collection 2000",             order: 92,
      desc: "Versão principal da carta com o selo em gold foil no formato de cauda de Pikachu, fora do canto inferior esquerdo da moldura de arte; reimpressão exclusiva da Pikachu World Collection (Pokémon Park 2000, Sydney)." },
    { code: "STANDARD_POKEMON_4EVER",        name: "Padrão Pokémon 4Ever",                             order: 93,
      desc: "Versão principal da carta com o logotipo \"Pokémon 4Ever\" impresso na moldura da arte; promo de cinema e de lançamento em DVD/VHS do filme (2002)." },
    { code: "STANDARD_POKEMON_CENTER_NY",    name: "Padrão Pokémon Center NY",                         order: 94,
      desc: "Versão principal da carta com o selo \"Pokémon Center NY\" sob a ilustração, exclusiva da loja Pokémon Center New York (novembro de 2002)." },
  ];

  const vtIdByCode = {};
  for (const vt of VTS) {
    // Checkpoint por identidade canônica: game_id + code.
    const [cur] = await sel(
      `card_variant_type?game_id=eq.${game.id}&code=eq.${q(vt.code)}` +
      `&select=id,code,name,description,display_order,is_active`);

    if (cur) {
      const d = diffFields(cur, {
        code: vt.code, name: vt.name, description: vt.desc,
        display_order: vt.order, is_active: true,
      });
      if (d.length) fail("D_VT_DIVERGENT", `${vt.code}: ${d.join(" · ")}`);
      vtIdByCode[vt.code] = cur.id;
      log(`  ✓ checkpoint já concluído: ${vt.code}`);
      continue;
    }

    const id = await rpc("admin_create_card_variant_type", {
      p_game_id: game.id, p_code: vt.code, p_name: vt.name,
      p_description: vt.desc, p_display_order: vt.order,
    });
    if (typeof id !== "string" || id.length !== 36) fail("D_VT_NO_ID", vt.code);
    log(`  + ${vt.code}`);
    vtIdByCode[vt.code] = id;
  }

  // ===========================================================================
  // FASE E — 6 VT MAPPINGS SCOPED basep
  //          (RPC: admin_resolve_catalog_variant_import_mapping_for_set)
  // ===========================================================================
  log("— FASE E: variant type mappings SCOPED —");

  const VT_MAPPINGS = [
    { sig: "normal|stamp:1st-movie",          stamp: "1ST-MOVIE",          rows: 4, vt: () => vtIdByCode["STANDARD_FIRST_MOVIE"] },
    { sig: "normal|stamp:1st-movie-inverted", stamp: "1ST-MOVIE-INVERTED", rows: 4, vt: () => vtIdByCode["STANDARD_FIRST_MOVIE_INVERTED"] },
    { sig: "normal|stamp:pikachu-tail",       stamp: "PIKACHU-TAIL",       rows: 6, vt: () => vtIdByCode["STANDARD_PIKACHU_WORLD_2000"] },
    { sig: "normal|stamp:pokemon-4-ever",     stamp: "POKEMON-4-EVER",     rows: 2, vt: () => vtIdByCode["STANDARD_POKEMON_4EVER"] },
    { sig: "normal|stamp:pokemon-center-ny",  stamp: "POKEMON-CENTER-NY",  rows: 2, vt: () => vtIdByCode["STANDARD_POKEMON_CENTER_NY"] },
    { sig: "normal|stamp:jr-stamp-rally",     stamp: "JR-STAMP-RALLY",     rows: 1, vt: () => vtStandard.id },
  ];

  for (const m of VT_MAPPINGS) {
    const wantVt = m.vt();
    if (typeof wantVt !== "string") fail("E_VT_ID_MISSING", m.stamp);

    // Checkpoint pela identidade completa do índice de combinação:
    // game + source + set + type + foil NULL + subtype NULL + stamp exato.
    // O array é comparado em JS para não depender da serialização de array
    // do PostgREST no filtro.
    const candidates = await sel(
      `card_variant_type_external_mapping?game_id=eq.${game.id}&asset_source_id=eq.${source.id}` +
      `&external_set_id=eq.${q(SET_CODE)}&normalized_type=eq.NORMAL` +
      `&normalized_foil=is.null&normalized_subtype=is.null` +
      `&select=id,game_id,asset_source_id,external_set_id,normalized_type,normalized_foil,normalized_subtype,normalized_stamp,variant_type_id`);

    const cur = candidates.find((x) => sameSet(x.normalized_stamp, [m.stamp]));

    if (cur) {
      if (cur.variant_type_id !== wantVt) {
        fail("E_VT_MAPPING_DIVERGENT",
          `${m.stamp}: mapping SCOPED existente aponta para variant_type_id diferente do esperado.`);
      }
      // FAIL-EARLY: mapping presente exige o grupo INTEIRO já propagado.
      await assertGroup("E", m.sig, "VALID");
      log(`  ✓ checkpoint já concluído: ${m.stamp} (grupo inteiro VALID)`);
      continue;
    }

    // FAIL-EARLY: mapping ausente exige o grupo INTEIRO ainda não resolvido.
    await assertGroup("E", m.sig, "NEEDS_REVIEW");

    const rowId = anchor(m.sig);
    if (!rowId) fail("E_ANCHOR_MISSING", m.sig);

    const row = one(await rpc("admin_resolve_catalog_variant_import_mapping_for_set", {
      p_row_id: rowId, p_variant_type_id: wantVt,
    }));
    log(`  + ${m.stamp}`, row);
    if (!row?.mapping_id) fail("E_VT_MAPPING_NO_ID", m.stamp);
    {
      const d = diffFields(row, {
        scope_kind: "SOURCE_SET",
        external_set_id: SET_CODE,
        rows_total: m.rows,
        rows_reclassified: m.rows,
        rows_still_pending: 0,
        jobs_affected: 1,
      });
      if (d.length) fail("E_VT_MAPPING_GATE", `${m.stamp}: ${d.join(" · ")}`);
    }
  }

  // ===========================================================================
  // FASE F — GATE CONSOLIDADO (READ-ONLY)
  // ===========================================================================
  log("— FASE F: gate consolidado —");

  // F.1 — cabeçalho do job
  const [job1] = await sel(`catalog_variant_import_job?id=eq.${JOB_ID}&select=id,status,total_rows,valid_rows,external_set_id`);
  if (!job1) fail("F_JOB_NOT_FOUND", JOB_ID);
  log("job final:", job1.status, `${job1.total_rows}/${job1.valid_rows}`);
  {
    const d = diffFields(job1, { status: "STAGED", total_rows: 74, valid_rows: 72, external_set_id: SET_CODE });
    if (d.length) fail("F_JOB_GATE", d.join(" · "));
  }

  // F.2 — matriz de validação das 74 rows
  const after = await sel(`catalog_variant_import_row?job_id=eq.${JOB_ID}&select=id,validation_status,decision_status,persistence_status,raw_data`);
  const valid  = after.filter((r) => r.validation_status === "VALID").length;
  const review = after.filter((r) => r.validation_status === "NEEDS_REVIEW");

  log(`VALID=${valid}  NEEDS_REVIEW=${review.length}  total=${after.length}`);

  if (after.length !== 74) fail("F_TOTAL_DRIFT", `total do job mudou: ${after.length}`);
  if (review.length !== 2) fail("F_REVIEW_COUNT", `esperado 2 NEEDS_REVIEW, obtido ${review.length}`);
  if (valid !== 72) fail("F_VALID_COUNT", `esperado 72 VALID (47 históricas + 25 desta convergência), obtido ${valid}`);

  const remaining = review.map(sigOf).sort();
  if (!sameSet(remaining, [...DEFERRED_SIGS].sort())) {
    fail("F_WRONG_RESIDUAL", `resíduo final inesperado: ${JSON.stringify(remaining)}`);
  }

  // F.3 — PROVA DE WORKFLOW
  // Nada pode ter sido decidido ou persistido sem ação humana. As 47 rows
  // históricas seguem APPROVED/INSERTED; as 27 desta convergência seguem
  // PENDING/PENDING até a UI decidir 25 + 2.
  const historicasF = after.filter((r) => !convergenceSet.has(r.id));
  const convergenciaF = after.filter((r) => convergenceSet.has(r.id));

  if (historicasF.length !== 47) fail("F_WORKFLOW_HISTORIC_COUNT", `esperado 47 históricas, obtido ${historicasF.length}`);
  if (convergenciaF.length !== 27) fail("F_WORKFLOW_CONVERGENCE_COUNT", `esperado 27 desta convergência, obtido ${convergenciaF.length}`);

  const historicasOk = historicasF.filter(
    (r) => r.validation_status === "VALID" && r.decision_status === "APPROVED" && r.persistence_status === "INSERTED").length;
  if (historicasOk !== 47) {
    fail("F_WORKFLOW_HISTORIC_DRIFT",
      `esperado 47 rows históricas em VALID/APPROVED/INSERTED, obtido ${historicasOk}. Houve decisão/persistência inesperada.`);
  }

  const convergenciaOk = convergenciaF.filter(
    (r) => r.decision_status === "PENDING" && r.persistence_status === "PENDING").length;
  if (convergenciaOk !== 27) {
    fail("F_WORKFLOW_CONVERGENCE_DRIFT",
      `esperado 27 rows desta convergência ainda em decision=PENDING/persistence=PENDING, obtido ${convergenciaOk}. O runner NÃO decide nem persiste — isso é da UI.`);
  }

  log("PROVA DE WORKFLOW OK: 47 históricas APPROVED/INSERTED · 27 desta convergência PENDING/PENDING.");
  log("GATE OK — 25 resolvidas, 2 deferidas (exatamente as esperadas).");
  log("Próximo passo, na UI: aprovar 25, pular 2, confirmar importação.");
})();
