/* =============================================================================
 * BASE3 — RUNNER AUTENTICADO EFÊMERO
 * =============================================================================
 * Mandato...: BASE3 — IMPLEMENTATION STAGING-01
 * Versão....: 1.0
 * Status....: EXECUTADO — DRY_RUN PASS e execução LIVE PASS em 2026-09-18
 *             (9 RPCs, 02:55:16–02:55:27 UTC). Evidência histórica; NÃO
 *             reexecutar: os checkpoints passam a bater e o script vira no-op.
 * Data......: 2026-09-18
 * Base......: `basep-authenticated-runner.js` v1.2 (aprovado em
 *             BASEP — RUNNER CORRECTION-02). Mesma disciplina, escopo novo.
 *
 * -----------------------------------------------------------------------------
 * O QUE ISTO É — E O QUE NÃO É
 * -----------------------------------------------------------------------------
 * NÃO é produto. NÃO é importado por nada. NÃO está em `web/`. Não há build,
 * bundle, rota ou deploy que o alcance. É um artefato de EVIDÊNCIA desta rodada,
 * feito para ser colado uma vez no console do DevTools e morrer com o refresh
 * da aba.
 *
 * ORDEM CANÔNICA DA RODADA — não inverter
 *
 *      2829 PRE  ->  2202  ->  runner  ->  2829 POST  ->  UI
 *
 * O `2829 PRE` roda ANTES DA PRIMEIRA ESCRITA LIVE DA RODADA — portanto antes
 * da migration 2202, não entre ela e o runner. O collision gate precisa medir o
 * estado intocado; medi-lo depois de qualquer escrita já é medir outro estado.
 *
 * COMO EXECUTAR (quando autorizado)
 *   1. Rodar `2829_base3_collision_gate.sql` — **2829 PRE**, antes de tudo.
 *      Esperado: 11/11 PASS, `GATE` PASS. Qualquer FAIL => STOP, nada é aplicado.
 *   2. Aplicar a migration `2202_add_base3_evolution_box_error_trait.sql`.
 *   3. Abrir a aplicação JÁ AUTENTICADO como administrador.
 *   4. Manter a aba EM FOCO — `SessionRefresher` só renova o token com a aba
 *      ativa, e o middleware de refresh está órfão desde 2026-08-14.
 *   5. Preencher ANON_KEY abaixo (pública por desenho — ver nota de segurança).
 *   6. Colar tudo no console e pressionar Enter com `DRY_RUN = true` (valor
 *      padrão deste arquivo). Nenhuma escrita ocorre: o script para no fim do
 *      preflight.
 *   7. Auditar o retorno do DRY_RUN. Só então Fabrício altera explicitamente
 *      `DRY_RUN` para `false` e cola o script de novo para escrever.
 *   8. Rodar `2829_base3_collision_gate.sql` — **2829 POST** — ANTES de
 *      decidir/confirmar na UI.
 *
 * -----------------------------------------------------------------------------
 * O QUE MUDA EM RELAÇÃO AO RUNNER DE BASEP — E POR QUÊ
 * -----------------------------------------------------------------------------
 *  1. ASSINATURA INCLUI `foil`. Em BASEP o `foil` era irrelevante e `sigOf()`
 *     usava só `type` + stamp/subtype. Em BASE3 isso seria FATAL: as duas rows
 *     de Prerelease do Aerodactyl diferem SOMENTE no `foil` (`starlight` vs
 *     `cosmos`) e colapsariam na mesma assinatura. `sigOf()` passa a ser
 *     `type|foil|stamp|subtype`.
 *
 *  2. INVARIANTE DE WORKFLOW DIFERENTE. Em BASEP 47 rows já estavam
 *     APPROVED/INSERTED. Em BASE3 **as 177 estão PENDING/PENDING** — nenhuma foi
 *     decidida ainda. O invariante correto aqui é: TODAS as 177 em
 *     PENDING/PENDING, as 172 históricas sempre VALID, as 5 da convergência em
 *     NEEDS_REVIEW ou VALID (conforme o ponto da retomada).
 *
 *  3. ZERO DEFERIDAS. Em BASEP duas assinaturas nunca podiam sair de
 *     NEEDS_REVIEW. Em BASE3 as 5 resolvem; o gate final exige 177 VALID / 0
 *     NEEDS_REVIEW.
 *
 *  4. PREVIEW CANÔNICO ANTES DE CADA MAPPING DE VARIANT TYPE. Usa a RPC
 *     read-only `admin_preview_catalog_variant_import_mapping(row, vt, scope)`
 *     — que já existe e é o caminho canônico — para provar ANTES da escrita:
 *     `would_apply = true`, `block_reason = null`, `rows_total = 1`,
 *     `rows_class_a = 1`, `rows_class_b = 0`, `canonical_class_c = 0`,
 *     `jobs_affected = 1`. É a resposta direta ao item do mandato "provar
 *     exatamente 1 row BASE3 reclassificada e zero impacto inesperado em outros
 *     jobs". Contrato conferido contra o LIVE nesta rodada.
 *
 *  5. FASE F GLOBAL SEPARADA. O único mapping GLOBAL (`NORMAL|{WOTC}` →
 *     `W_PROMO_STAMPED`) usa `admin_resolve_catalog_variant_import_mapping`,
 *     cujo contrato de retorno é OUTRO: `(mapping_id, rows_updated,
 *     jobs_affected)` — sem `rows_still_pending`, sem `scope_kind`.
 *
 *  6. COLLISION GATE. A prova completa das 177 identidades exige
 *     `internal.compute_variant_residual_signature` e
 *     `internal.lookup_variant_type_for_row`, que NÃO são expostas ao PostgREST.
 *     Reimplementá-las aqui seria duplicar lógica interna (proibido) e criar uma
 *     RPC nova também (proibido). Logo a prova completa mora em
 *     `2829_base3_collision_gate.sql`, rodado por Fabrício no SQL Editor como
 *     **2829 PRE** (antes da 2202, portanto antes da primeira escrita LIVE) e
 *     como **2829 POST** (depois deste runner, antes da UI).
 *     Este runner prova aqui o que consegue observar SEM duplicar nada:
 *     zero `card_variant` nas 62 Cards e unicidade de tupla `raw_data` por Card.
 *     Ver FASE G.
 *
 * -----------------------------------------------------------------------------
 * DISCIPLINA HERDADA DE BASEP v1.2 (mantida integralmente)
 * -----------------------------------------------------------------------------
 *   1. COOKIE. Base64-URL (codec do @supabase/ssr 0.5.2), chunks CONTÍGUOS,
 *      `TextDecoder({ fatal: true })`, base não-fragmentado com precedência.
 *   2. TOKEN NÃO CONGELADO — relido a cada `rpc()` / `sel()`.
 *   3. `is_admin()` probe antes de qualquer coisa.
 *   4. IDENTIDADE CANÔNICA COMPLETA nos checkpoints (Game e Asset Source por
 *      `code`, nunca UUID hard-coded).
 *   5. GATES DE RETORNO explícitos e por objeto.
 *   6. FAIL-CLOSED + RESUMABILIDADE REAL por assinatura imutável.
 *   7. CHECKPOINT FAIL-EARLY: o grupo da assinatura é RELIDO no momento da
 *      checagem — mapping presente exige o grupo VALID; ausente exige
 *      NEEDS_REVIEW.
 *   8. DRY_RUN.
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
 *   - NÃO cria RPC permanente nova.
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
 * NÃO EXISTE TRANSAÇÃO ENTRE AS 9 RPCs DE ESCRITA. Cada chamada é a sua própria
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
 *                  inteiro após uma parada é seguro e retoma de onde parou.
 *
 * ESCRITAS DESTE RUNNER (9):
 *   1 Profile · 1 Printing mapping · 3 Variant Types · 3 VT mappings SCOPED ·
 *   1 VT mapping GLOBAL.
 * O 10º objeto do pacote — o trait `EVOLUTION_BOX_ERROR` — vem da migration
 * `2202`, porque `card_printing_trait` não tem writer canônico.
 * ========================================================================== */

(async () => {
  "use strict";

  // ---------------------------------------------------------------------------
  // CONFIGURAÇÃO
  // ---------------------------------------------------------------------------
  const PROJECT_REF  = "qjfutqujxrbzgrtkpgkg";
  const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
  const ANON_KEY     = "COLE_AQUI_A_NEXT_PUBLIC_SUPABASE_ANON_KEY";

  const JOB_ID       = "d5b7a148-0459-40fd-a32f-13fdcb845026"; // BASE3, STAGED
  const SET_CODE     = "base3";
  const SOURCE_CODE  = "TCGDEX";
  const GAME_CODE    = "POKEMON";

  const TOTAL_ROWS   = 177;
  const CONV_ROWS    = 5;    // rows da convergência editorial
  const HIST_ROWS    = 172;  // rows já resolvidas

  // SAFE DEFAULT: o artefato staged é fail-safe. `true` = só preflight +
  // diagnóstico, ZERO escrita. Fabrício altera para `false` EXPLICITAMENTE, e
  // só depois de auditar o retorno do DRY_RUN. Não há outra lógica de guarda.
  const DRY_RUN = true;

  // ---------------------------------------------------------------------------
  // INFRA
  // ---------------------------------------------------------------------------
  const log  = (...a) => console.log("[BASE3]", ...a);
  const fail = (code, detail) => {
    console.error("[BASE3] STOP:", code, detail ?? "");
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
   * Assinatura textual estável de uma row, derivada SOMENTE de `raw_data`.
   * É IMUTÁVEL: não muda quando a row é revalidada. É o que torna a
   * resumabilidade real — identificamos as 5 pelo que elas SÃO, não pelo
   * estado em que estão.
   *
   * INCLUI `foil` — sem ele, `holo|stamp:pre-release` colapsaria as duas rows
   * de Prerelease do Aerodactyl numa assinatura só. É a diferença central em
   * relação ao runner de BASEP.
   *
   * Mesmo formato do overlay de `2829_base3_collision_gate.sql`.
   */
  const sigOf = (row) => {
    const d = row.raw_data || {};
    const type = String(d.type ?? "?").toLowerCase();
    const foil = String(d.foil ?? "-").toLowerCase();
    const stampArr = Array.isArray(d.stamp) ? d.stamp : null;
    const tail = (stampArr && stampArr.length > 0)
      ? `stamp:${stampArr.map((s) => String(s).toLowerCase()).join("+")}`
      : `subtype:${String(d.subtype ?? "").toLowerCase()}`;
    return `${type}|${foil}|${tail}`;
  };

  // As 5 assinaturas da convergência e a cardinalidade exata de cada uma.
  const EXPECTED_SIGS = {
    "holo|starlight|stamp:pre-release": 1,
    "holo|cosmos|stamp:pre-release": 1,
    "holo|galaxy|subtype:evolution-box-error": 1,
    "holo|cosmos|subtype:1999-copyright": 1,
    "normal|-|stamp:wotc": 1,
  };

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

  // --- A2. As 177 rows, com estado completo ---------------------------------
  const all = await sel(
    `catalog_variant_import_row?job_id=eq.${JOB_ID}` +
    `&select=id,card_id,raw_data,validation_status,decision_status,persistence_status&limit=1000`);
  if (all.length !== TOTAL_ROWS) fail("A2_TOTAL_ROWS", `esperado ${TOTAL_ROWS} rows no job, obtido ${all.length}`);

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
    if (got !== n) fail("A3_SIGNATURE_DRIFT", `${sig}: esperado ${n} row(s), obtido ${got}`);
  }
  if (convergence.length !== CONV_ROWS) fail("A3_CONVERGENCE_COUNT", `esperado ${CONV_ROWS} rows nas 5 assinaturas, obtido ${convergence.length}`);
  if (historicas.length !== HIST_ROWS) fail("A3_HISTORIC_COUNT", `esperado ${HIST_ROWS} rows fora das 5 assinaturas, obtido ${historicas.length}`);

  const convergenceSet = new Set(convergence.map((r) => r.id));
  log(`separação por assinatura: ${convergence.length} convergência · ${historicas.length} históricas`);

  // --- A4. INVARIANTE DE WORKFLOW (vale em QUALQUER estado retomável) --------
  // Em BASE3, ao contrário de BASEP, NENHUMA row foi decidida ainda: as 177
  // estão PENDING/PENDING e assim devem continuar até a UI agir.
  {
    const bad = all.filter(
      (r) => r.decision_status !== "PENDING" || r.persistence_status !== "PENDING");
    if (bad.length) {
      fail("A4_ALREADY_DECIDED",
        `${bad.length} das ${TOTAL_ROWS} rows já têm decisão/persistência. A decisão é da UI, não do runner — STOP.`);
    }
  }
  {
    const bad = historicas.filter((r) => r.validation_status !== "VALID");
    if (bad.length) {
      fail("A4_HISTORIC_DRIFT",
        `${bad.length} das ${HIST_ROWS} rows históricas não estão VALID. Estado do job foi alterado fora deste fluxo — STOP.`);
    }
  }
  {
    const bad = convergence.filter(
      (r) => r.validation_status !== "NEEDS_REVIEW" && r.validation_status !== "VALID");
    if (bad.length) {
      fail("A4_UNEXPECTED_VALIDATION",
        `${bad.length} das ${CONV_ROWS} rows da convergência estão em estado diferente de NEEDS_REVIEW/VALID — STOP.`);
    }
    log(`${CONV_ROWS} da convergência: ${convergence.filter((r) => r.validation_status === "VALID").length} VALID · ${convergence.filter((r) => r.validation_status === "NEEDS_REVIEW").length} NEEDS_REVIEW`);
  }

  // --- A5. Cabeçalho do job, coerente com a contagem REAL --------------------
  const validNow = all.filter((r) => r.validation_status === "VALID").length;
  const [job0] = await sel(`catalog_variant_import_job?id=eq.${JOB_ID}&select=id,status,total_rows,valid_rows,external_set_id,source`);
  if (!job0) fail("A5_JOB_NOT_FOUND", JOB_ID);
  log("job:", job0.external_set_id, job0.status, `${job0.total_rows}/${job0.valid_rows}`, `(VALID real = ${validNow})`);
  {
    const d = diffFields(job0, {
      status: "STAGED", total_rows: TOTAL_ROWS, external_set_id: SET_CODE, source: SOURCE_CODE,
    });
    if (d.length) fail("A5_JOB_BASELINE", d.join(" · "));
  }
  if (job0.valid_rows !== validNow) {
    fail("A5_JOB_VALID_MISMATCH", `job.valid_rows=${job0.valid_rows} difere da contagem real de VALID=${validNow}`);
  }
  if (validNow < HIST_ROWS || validNow > TOTAL_ROWS) {
    fail("A5_JOB_VALID_WINDOW", `VALID=${validNow} fora da janela legítima [${HIST_ROWS}, ${TOTAL_ROWS}] desta convergência`);
  }

  /** Âncora: a row do grupo, independente do validation_status atual. */
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
      fail(`${ctx}_GROUP_READ`, `${sig}: esperado ${ids.length} row(s), lidas ${rows.length}`);
    }
    const badState = rows.filter((r) => r.validation_status !== expected);
    if (badState.length) {
      fail(`${ctx}_GROUP_STATE`,
        `${sig}: esperado TODAS as ${ids.length} row(s) em ${expected}, ${badState.length} divergente(s). Propagação incompleta ou drift — STOP.`);
    }
    const badFlow = rows.filter((r) => r.decision_status !== "PENDING" || r.persistence_status !== "PENDING");
    if (badFlow.length) {
      fail(`${ctx}_GROUP_WORKFLOW`, `${sig}: ${badFlow.length} row(s) já decididas/persistidas — STOP.`);
    }
  }

  /**
   * PREVIEW CANÔNICO (read-only) antes de cada mapping de Variant Type.
   * Contrato conferido contra o LIVE em 2026-09-18 para um caso SOURCE_SET de
   * uma row: ok/would_apply=true, block_reason=null, rows_total=1,
   * rows_class_a=1, rows_class_b=0, canonical_class_c=0, jobs_affected=1.
   */
  async function previewGate(ctx, rowId, vtId, scopeKind, label) {
    const p = one(await rpc("admin_preview_catalog_variant_import_mapping", {
      p_row_id: rowId, p_variant_type_id: vtId, p_scope_kind: scopeKind,
    }));
    log(`    preview ${label}:`, p);
    if (!p) fail(`${ctx}_PREVIEW_EMPTY`, label);
    const d = diffFields(p, {
      scope_kind: scopeKind,
      would_apply: true,
      block_reason: null,
      rows_total: 1,
      rows_class_a: 1,
      rows_class_b: 0,
      canonical_class_c: 0,
      jobs_affected: 1,
      target_variant_type_id: vtId,
    });
    if (d.length) fail(`${ctx}_PREVIEW_GATE`, `${label}: ${d.join(" · ")}`);
  }

  // --- A6. Identidade canônica: Game e Asset Source resolvidos por code ------
  const [game] = await sel(`game?code=eq.${GAME_CODE}&select=id,code`);
  if (!game) fail("A6_GAME_NOT_FOUND", GAME_CODE);

  const [source] = await sel(`asset_source?code=eq.${SOURCE_CODE}&select=id,code,is_active`);
  if (!source) fail("A6_SOURCE_NOT_FOUND", SOURCE_CODE);
  if (source.is_active !== true) fail("A6_SOURCE_INACTIVE", SOURCE_CODE);
  log("game/source resolvidos por code.");

  // --- A7. Traits: 9 no total; o novo validado campo a campo ----------------
  const traits = await sel(`card_printing_trait?game_id=eq.${game.id}&select=id,code,name,display_order,is_active`);
  const traitBy = Object.fromEntries(traits.map((t) => [t.code, t]));
  log("traits POKEMON:", traits.length);
  if (traits.length !== 9) {
    fail("A7_TRAIT_COUNT",
      `esperado 9 (5 da Query 2169 + 3 da Query 2201 + 1 da Query 2202), obtido ${traits.length}. Aplique a 2202 ANTES do runner.`);
  }
  {
    const t = traitBy["EVOLUTION_BOX_ERROR"];
    if (!t) fail("A7_TRAIT_MISSING", "EVOLUTION_BOX_ERROR — aplique a migration 2202 antes de rodar o runner.");
    const d = diffFields(t, { code: "EVOLUTION_BOX_ERROR", display_order: 9, is_active: true });
    if (d.length) fail("A7_TRAIT_DIVERGENT", `EVOLUTION_BOX_ERROR: ${d.join(" · ")}`);
  }

  // --- A8. VTs reutilizados: HOLO e COSMOS_HOLO, por game_id + code ----------
  const [vtHolo] = await sel(`card_variant_type?game_id=eq.${game.id}&code=eq.HOLO&select=id,code,display_order,is_active`);
  if (!vtHolo) fail("A8_VT_HOLO_NOT_FOUND");
  if (vtHolo.is_active !== true) fail("A8_VT_HOLO_INACTIVE");

  const [vtCosmos] = await sel(`card_variant_type?game_id=eq.${game.id}&code=eq.COSMOS_HOLO&select=id,code,display_order,is_active`);
  if (!vtCosmos) fail("A8_VT_COSMOS_NOT_FOUND");
  if (vtCosmos.is_active !== true) fail("A8_VT_COSMOS_INACTIVE");
  log("VTs reutilizados resolvidos: HOLO, COSMOS_HOLO.");

  // --- A9. Mapping SCOPED base3 já existente (HOLO/GALAXY) deve estar lá ------
  // É ele que devolve `HOLO` para o resíduo de `evolution-box-error` depois que
  // o eixo Printing consumir o token. Se sumiu, a Fase C não resolve nada.
  {
    const base = await sel(
      `card_variant_type_external_mapping?game_id=eq.${game.id}&asset_source_id=eq.${source.id}` +
      `&external_set_id=eq.${q(SET_CODE)}&normalized_type=eq.HOLO&normalized_foil=eq.GALAXY` +
      `&normalized_subtype=is.null&select=id,variant_type_id,normalized_stamp`);
    const hit = base.find((x) => x.variant_type_id === vtHolo.id);
    if (!hit) {
      fail("A9_BASE_SCOPED_MAPPING_MISSING",
        "o mapping SCOPED base3 (HOLO/GALAXY -> HOLO) não foi encontrado. Sem ele, o resíduo de evolution-box-error não resolve — STOP.");
    }
  }

  // --- A10. COLLISION GATE (parte observável pelo runner) --------------------
  await collisionGate("A10");

  log("PREFLIGHT OK. Nenhuma escrita até aqui.");
  if (DRY_RUN) {
    log("DRY_RUN=true (padrão do arquivo) — encerrando ANTES da primeira escrita.");
    log("Audite o retorno acima. Para escrever, altere DRY_RUN para false e cole de novo.");
    return;
  }

  // ===========================================================================
  // FASE B — 1 PROFILE  (RPC: admin_create_card_printing_profile_with_backfill)
  // ===========================================================================
  log("— FASE B: profile —");

  const PROFILE = {
    code: "EVOLUTION_BOX_ERROR",
    name: "Erro da Caixa de Evolução",
    order: 11,
    traits: ["EVOLUTION_BOX_ERROR"],
    desc: "Tiragem cuja chapa holográfica reserva o recorte da caixa de evolução em carta que não evolui; corrigida em tiragem posterior.",
  };

  {
    const want = PROFILE.traits.map((c) => traitBy[c].id);

    // Checkpoint por identidade canônica: game_id + code.
    const [cur] = await sel(
      `card_printing_profile?game_id=eq.${game.id}&code=eq.${q(PROFILE.code)}` +
      `&select=id,game_id,code,name,description,display_order,is_active,traits_signature`);

    if (cur) {
      const d = diffFields(cur, {
        game_id: game.id, code: PROFILE.code, name: PROFILE.name,
        description: PROFILE.desc, display_order: PROFILE.order, is_active: true,
      });
      if (!sameSet(cur.traits_signature, want)) d.push("traits_signature difere do esperado");
      if (d.length) fail("B_PROFILE_DIVERGENT", `${PROFILE.code}: ${d.join(" · ")}`);
      log(`  ✓ checkpoint já concluído: ${PROFILE.code}`);
    } else {
      const row = one(await rpc("admin_create_card_printing_profile_with_backfill", {
        p_code: PROFILE.code, p_name: PROFILE.name, p_description: PROFILE.desc,
        p_display_order: PROFILE.order, p_trait_ids: want,
      }));
      log(`  + ${PROFILE.code}`, row);
      if (!row?.profile_id) fail("B_PROFILE_NO_ID", PROFILE.code);
      if (!sameSet(row.traits_signature, want)) fail("B_PROFILE_SIGNATURE", PROFILE.code);
      // Criar Profile não cria routing: nenhum token externo passa a resolver por
      // causa dele. Nada pode ser revalidado, nada pode ficar pendente, nenhum
      // job pode ser afetado — em fresh run OU em retomada.
      {
        const d = diffFields(row, {
          rows_touched: 0, rows_revalidated: 0, rows_still_pending: 0, jobs_affected: 0,
        });
        if (d.length) fail("B_PROFILE_GATE", `${PROFILE.code}: ${d.join(" · ")}`);
      }
    }
  }

  // ===========================================================================
  // FASE C — 1 PRINTING MAPPING
  //          (RPC: admin_resolve_catalog_variant_import_printing_mapping)
  // ===========================================================================
  log("— FASE C: printing mapping —");

  const PRINTING = {
    sig: "holo|galaxy|subtype:evolution-box-error",
    field: "subtype",
    token: "evolution-box-error",
    norm: "EVOLUTION-BOX-ERROR",
    traits: ["EVOLUTION_BOX_ERROR"],
    rows_updated: 1,
  };

  {
    const m = PRINTING;
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
      log(`  ✓ checkpoint já concluído: ${m.field}:${m.token} (grupo VALID)`);
    } else {
      // FAIL-EARLY: mapping ausente exige o grupo INTEIRO ainda não resolvido.
      await assertGroup("C", m.sig, "NEEDS_REVIEW");

      const rowId = anchor(m.sig);
      if (!rowId) fail("C_ANCHOR_MISSING", m.sig);

      const row = one(await rpc("admin_resolve_catalog_variant_import_printing_mapping", {
        p_row_id: rowId, p_raw_field: m.field, p_token: m.token, p_trait_ids: want,
      }));
      log(`  + ${m.field}:${m.token}`, row);
      if (!row?.mapping_id) fail("C_PRINTING_NO_ID", m.token);
      // GATE: cardinalidade exata + zero pendência + cross-job restrito a BASE3.
      {
        const d = diffFields(row, {
          rows_updated: m.rows_updated, rows_still_pending: 0, jobs_affected: 1,
        });
        if (d.length) fail("C_PRINTING_GATE", `${m.token}: ${d.join(" · ")}`);
      }
    }
  }

  // ===========================================================================
  // FASE D — 3 VARIANT TYPES  (RPC: admin_create_card_variant_type)
  //          NÃO usar *_with_import_mapping: ele cria mapping GLOBAL para todos,
  //          e três dos quatro mappings desta rodada são SOURCE_SET.
  // ===========================================================================
  log("— FASE D: variant types —");

  const VTS = [
    { code: "PRERELEASE_HOLO", name: "Prerelease Holo", order: 95,
      desc: "Tiragem promocional de pré-lançamento com o selo \"PRERELEASE\" aplicado no canto inferior direito da arte, no padrão holográfico padrão do Set (Starlight). Impressão promocional norte-americana de Fossil, distribuída como promo de Pokémon League em julho de 1999." },
    { code: "PRERELEASE_COSMOS_HOLO", name: "Prerelease Holo Cosmos", order: 96,
      desc: "Mesma tiragem promocional de pré-lançamento, com o selo \"PRERELEASE\" aplicado, porém no padrão holográfico Cosmos em vez do padrão do Set. Impressão promocional europeia de Fossil; reconhecida pela PSA como variedade própria." },
    { code: "W_PROMO_STAMPED", name: "Promo Estampada W", order: 97,
      desc: "Reimpressão promocional com o selo em gold foil no formato do \"W\" do logotipo original da Wizards of the Coast, aplicado sobre a carta. Programa W Promotional: 7 cartas em 6 expansões, entre setembro de 1999 e março de 2001, a maioria distribuída por revistas de Pokémon." },
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
  // FASE E — 3 VT MAPPINGS SCOPED base3
  //          (RPC: admin_resolve_catalog_variant_import_mapping_for_set)
  // ===========================================================================
  log("— FASE E: variant type mappings SCOPED —");

  const VT_SCOPED = [
    { sig: "holo|starlight|stamp:pre-release",
      label: "HOLO/STARLIGHT/{PRE-RELEASE}",
      type: "HOLO", foil: "STARLIGHT", subtype: null, stamp: ["PRE-RELEASE"],
      vt: () => vtIdByCode["PRERELEASE_HOLO"] },
    { sig: "holo|cosmos|stamp:pre-release",
      label: "HOLO/COSMOS/{PRE-RELEASE}",
      type: "HOLO", foil: "COSMOS", subtype: null, stamp: ["PRE-RELEASE"],
      vt: () => vtIdByCode["PRERELEASE_COSMOS_HOLO"] },
    { sig: "holo|cosmos|subtype:1999-copyright",
      label: "HOLO/COSMOS/1999-COPYRIGHT",
      type: "HOLO", foil: "COSMOS", subtype: "1999-COPYRIGHT", stamp: null,
      vt: () => vtCosmos.id },
  ];

  for (const m of VT_SCOPED) {
    const wantVt = m.vt();
    if (typeof wantVt !== "string") fail("E_VT_ID_MISSING", m.label);

    // Checkpoint pela identidade completa do índice de combinação:
    // game + source + set + type + foil + subtype + stamp exato.
    // O array de stamp é comparado em JS para não depender da serialização de
    // array do PostgREST no filtro.
    const subtypeFilter = m.subtype === null
      ? "&normalized_subtype=is.null"
      : `&normalized_subtype=eq.${q(m.subtype)}`;

    const candidates = await sel(
      `card_variant_type_external_mapping?game_id=eq.${game.id}&asset_source_id=eq.${source.id}` +
      `&external_set_id=eq.${q(SET_CODE)}&normalized_type=eq.${q(m.type)}` +
      `&normalized_foil=eq.${q(m.foil)}` + subtypeFilter +
      `&select=id,external_set_id,normalized_type,normalized_foil,normalized_subtype,normalized_stamp,variant_type_id`);

    const cur = candidates.find((x) => sameSet(x.normalized_stamp, m.stamp ?? []));

    if (cur) {
      if (cur.variant_type_id !== wantVt) {
        fail("E_VT_MAPPING_DIVERGENT",
          `${m.label}: mapping SCOPED existente aponta para variant_type_id diferente do esperado.`);
      }
      // FAIL-EARLY: mapping presente exige o grupo INTEIRO já propagado.
      await assertGroup("E", m.sig, "VALID");
      log(`  ✓ checkpoint já concluído: ${m.label} (grupo VALID)`);
      continue;
    }

    // FAIL-EARLY: mapping ausente exige o grupo INTEIRO ainda não resolvido.
    await assertGroup("E", m.sig, "NEEDS_REVIEW");

    const rowId = anchor(m.sig);
    if (!rowId) fail("E_ANCHOR_MISSING", m.sig);

    // PREVIEW canônico ANTES da escrita.
    await previewGate("E", rowId, wantVt, "SOURCE_SET", m.label);

    const row = one(await rpc("admin_resolve_catalog_variant_import_mapping_for_set", {
      p_row_id: rowId, p_variant_type_id: wantVt,
    }));
    log(`  + ${m.label}`, row);
    if (!row?.mapping_id) fail("E_VT_MAPPING_NO_ID", m.label);
    {
      const d = diffFields(row, {
        scope_kind: "SOURCE_SET",
        external_set_id: SET_CODE,
        rows_total: 1,
        rows_reclassified: 1,
        rows_still_pending: 0,
        jobs_affected: 1,
      });
      if (d.length) fail("E_VT_MAPPING_GATE", `${m.label}: ${d.join(" · ")}`);
    }
  }

  // ===========================================================================
  // FASE F — 1 VT MAPPING GLOBAL
  //          (RPC: admin_resolve_catalog_variant_import_mapping)
  //
  // GLOBAL é a decisão SEMÂNTICA, não um atalho: o programa W Promotional é
  // transversal por definição (7 cartas, 6 expansões, 1999-2001). Restringir a
  // `base3` afirmaria que o selo "W" é um fenômeno de Fossil — o que a fonte
  // nega nominalmente.
  //
  // Contrato de retorno DIFERENTE do de Fase E: (mapping_id, rows_updated,
  // jobs_affected). Não há `rows_still_pending` nem `scope_kind`.
  // ===========================================================================
  log("— FASE F: variant type mapping GLOBAL —");

  {
    const sig = "normal|-|stamp:wotc";
    const label = "NORMAL/—/—/{WOTC}";
    const wantVt = vtIdByCode["W_PROMO_STAMPED"];
    if (typeof wantVt !== "string") fail("F_VT_ID_MISSING", label);

    const candidates = await sel(
      `card_variant_type_external_mapping?game_id=eq.${game.id}&asset_source_id=eq.${source.id}` +
      `&external_set_id=is.null&normalized_type=eq.NORMAL` +
      `&normalized_foil=is.null&normalized_subtype=is.null` +
      `&select=id,external_set_id,normalized_type,normalized_foil,normalized_subtype,normalized_stamp,variant_type_id`);

    const cur = candidates.find((x) => sameSet(x.normalized_stamp, ["WOTC"]));

    if (cur) {
      if (cur.variant_type_id !== wantVt) {
        fail("F_VT_MAPPING_DIVERGENT",
          `${label}: mapping GLOBAL existente aponta para variant_type_id diferente do esperado.`);
      }
      await assertGroup("F", sig, "VALID");
      log(`  ✓ checkpoint já concluído: ${label} (grupo VALID)`);
    } else {
      await assertGroup("F", sig, "NEEDS_REVIEW");

      const rowId = anchor(sig);
      if (!rowId) fail("F_ANCHOR_MISSING", sig);

      // PREVIEW canônico ANTES da escrita — é aqui que se prova "exatamente 1
      // row BASE3 reclassificada e zero impacto inesperado em outros jobs".
      await previewGate("F", rowId, wantVt, "GLOBAL", label);

      const row = one(await rpc("admin_resolve_catalog_variant_import_mapping", {
        p_row_id: rowId, p_variant_type_id: wantVt,
      }));
      log(`  + ${label}`, row);
      if (!row?.mapping_id) fail("F_VT_MAPPING_NO_ID", label);
      {
        const d = diffFields(row, { rows_updated: 1, jobs_affected: 1 });
        if (d.length) fail("F_VT_MAPPING_GATE", `${label}: ${d.join(" · ")}`);
      }
      // Confirmação independente do gate: o mapping nasceu GLOBAL mesmo.
      const [chk] = await sel(
        `card_variant_type_external_mapping?id=eq.${row.mapping_id}` +
        `&select=id,external_set_id,variant_type_id`);
      if (!chk) fail("F_VT_MAPPING_READBACK", label);
      if (chk.external_set_id !== null) {
        fail("F_VT_MAPPING_NOT_GLOBAL",
          `${label}: external_set_id=${JSON.stringify(chk.external_set_id)}, esperado null (GLOBAL).`);
      }
      if (chk.variant_type_id !== wantVt) fail("F_VT_MAPPING_READBACK_VT", label);
    }
  }

  // ===========================================================================
  // FASE G — GATE CONSOLIDADO (READ-ONLY)
  // ===========================================================================
  log("— FASE G: gate consolidado —");

  // G.1 — cabeçalho do job
  const [job1] = await sel(`catalog_variant_import_job?id=eq.${JOB_ID}&select=id,status,total_rows,valid_rows,external_set_id`);
  if (!job1) fail("G_JOB_NOT_FOUND", JOB_ID);
  log("job final:", job1.status, `${job1.total_rows}/${job1.valid_rows}`);
  {
    const d = diffFields(job1, {
      status: "STAGED", total_rows: TOTAL_ROWS, valid_rows: TOTAL_ROWS, external_set_id: SET_CODE,
    });
    if (d.length) fail("G_JOB_GATE", d.join(" · "));
  }

  // G.2 — matriz de validação das 177 rows
  const after = await sel(
    `catalog_variant_import_row?job_id=eq.${JOB_ID}` +
    `&select=id,card_id,validation_status,decision_status,persistence_status,raw_data&limit=1000`);
  const valid  = after.filter((r) => r.validation_status === "VALID").length;
  const review = after.filter((r) => r.validation_status === "NEEDS_REVIEW");

  log(`VALID=${valid}  NEEDS_REVIEW=${review.length}  total=${after.length}`);

  if (after.length !== TOTAL_ROWS) fail("G_TOTAL_DRIFT", `total do job mudou: ${after.length}`);
  if (review.length !== 0) {
    fail("G_REVIEW_COUNT",
      `esperado 0 NEEDS_REVIEW, obtido ${review.length}: ${JSON.stringify(review.map(sigOf))}`);
  }
  if (valid !== TOTAL_ROWS) fail("G_VALID_COUNT", `esperado ${TOTAL_ROWS} VALID, obtido ${valid}`);

  // G.3 — PROVA DE WORKFLOW
  // Nada pode ter sido decidido ou persistido sem ação humana. As 177 seguem
  // PENDING/PENDING até a UI aprovar e confirmar.
  {
    const ok = after.filter(
      (r) => r.decision_status === "PENDING" && r.persistence_status === "PENDING").length;
    if (ok !== TOTAL_ROWS) {
      fail("G_WORKFLOW_DRIFT",
        `esperado ${TOTAL_ROWS} rows em decision=PENDING/persistence=PENDING, obtido ${ok}. O runner NÃO decide nem persiste — isso é da UI.`);
    }
  }

  // G.4 — COLLISION GATE de novo, agora no estado final
  await collisionGate("G4", after);

  log("PROVA DE WORKFLOW OK: 177 rows PENDING/PENDING.");
  log("GATE OK — 5 resolvidas, 0 deferidas, 0 NEEDS_REVIEW.");
  log("Próximo passo: rodar 2829_base3_collision_gate.sql — 2829 POST — e, se PASS,");
  log("na UI: aprovar as 177 e confirmar a importação.");

  // ===========================================================================
  // COLLISION GATE — parte observável pelo runner
  // ===========================================================================
  /**
   * O que o runner PODE provar sem duplicar o resolver nem criar RPC:
   *
   *   G-a. ZERO card_variant materializado nas Cards do job. Se é zero, nenhuma
   *        identidade projetada pode colidir com algo pré-existente — toda
   *        colisão possível é intra-job.
   *   G-b. As tuplas `raw_data` (type|foil|subtype|stamp) são DISTINTAS dentro
   *        de cada Card. É condição NECESSÁRIA da distinção de identidade: duas
   *        rows com a MESMA tupla na MESMA Card resolveriam para a mesma
   *        identidade, sempre.
   *
   * O que ele NÃO pode provar aqui, e por quê: a condição SUFICIENTE (duas
   * tuplas diferentes podem, em tese, resolver para a mesma identidade) exige o
   * resolver `internal.*`. Essa prova é `2829_base3_collision_gate.sql`, rodado
   * como 2829 PRE (antes da 2202) e como 2829 POST (depois deste runner).
   * NÃO tratar G-a/G-b como prova completa.
   */
  async function collisionGate(ctx, preloaded) {
    const rows = preloaded ?? await sel(
      `catalog_variant_import_row?job_id=eq.${JOB_ID}&select=id,card_id,raw_data&limit=1000`);
    if (rows.length !== TOTAL_ROWS) fail(`${ctx}_COLLISION_ROWS`, `esperado ${TOTAL_ROWS}, obtido ${rows.length}`);

    const cardIds = [...new Set(rows.map((r) => r.card_id))];
    if (cardIds.length !== 62) fail(`${ctx}_COLLISION_CARDS`, `esperado 62 Cards distintas, obtido ${cardIds.length}`);

    // G-a: zero variantes já materializadas nessas Cards.
    const existing = await sel(
      `card_variant?card_id=in.(${cardIds.join(",")})&select=id&limit=1000`);
    if (existing.length !== 0) {
      fail(`${ctx}_COLLISION_MATERIALIZED`,
        `esperado 0 card_variant nas 62 Cards de BASE3, obtido ${existing.length}. A premissa "Set parte do zero" caiu — STOP.`);
    }

    // G-b: tuplas raw_data distintas por Card.
    const seen = new Set();
    for (const r of rows) {
      const key = `${r.card_id}|${sigOf(r)}`;
      if (seen.has(key)) {
        fail(`${ctx}_COLLISION_DUPLICATE_TUPLE`,
          `duas rows da mesma Card com a mesma tupla raw_data: ${key} — identidade projetada colidiria — STOP.`);
      }
      seen.add(key);
    }

    log(`  collision gate (${ctx}): 0 materializadas · ${seen.size} tuplas distintas em ${cardIds.length} Cards.`);
    log(`  prova COMPLETA das 177 identidades: rodar 2829_base3_collision_gate.sql.`);
  }
})();
