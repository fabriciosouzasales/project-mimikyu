/*
===============================================================================
HARNESS OFFLINE — run-bootstrap-assets.mjs
Arquivo......: web/scripts/bootstrap-cards/provas-assets-bootstrap.mjs
Alvo.........: ./run-bootstrap-assets.mjs (mesmo diretorio)
Status.......: NUNCA EXECUTADO pelo agente (sandbox sem node nesta sessao)

Cobre, acumulado:
  - B1/B2/B3 (ASSETS-BLOCKERS-IMPLEMENTATION-01)
  - statusFinalComPopulacao (CORRECTION-02)
  - set_snapshot / DTO minimo (BOOTSTRAP-METADATA-PASSTHROUGH-01)
  - import-safety + fail closed do snapshot (PASSTHROUGH CORRECTION-01)
  - reconhecimento de run terminal (ASSETS-RETRY-TERMINAL-FIX-01, A61-A86)

GARANTIAS DE ISOLAMENTO
  - Rede REAL: zero. Todo `fetch` e injetado por parametro ou stubbado em
    globalThis e restaurado no `finally`.
  - Banco REAL: zero. O client Supabase e um stub local (`fakeQuery`).
  - Escrita: zero. Nenhum arquivo e criado, alterado ou removido.
  - Credenciais: zero. O subprocesso de import-safety roda com env MINIMO,
    deliberadamente sem as 4 variaveis exigidas pelo script.

EXECUCAO (a partir da raiz do repositorio):
  node web/scripts/bootstrap-cards/provas-assets-bootstrap.mjs

Criterio de PASS: "RESULTADO: 87/87 OK" e exit code 0.
Qualquer FAIL lista o caso e encerra com exit code 1.
Duracao aproximada: ~20s (os cenarios ponta a ponta do Bloco 9 percorrem o
`dormir(2000)` real entre tentativas).
===============================================================================
*/

import { execFileSync } from "node:child_process";

const URL_MODULO = new URL("./run-bootstrap-assets.mjs", import.meta.url).href;

const mod = await import(URL_MODULO);
const {
  chaveFonte,
  indexarFontePorChave,
  classificarLacuna,
  concluirFasePorCobertura,
  statusFinalComPopulacao,
  montarSetSnapshot,
  disponibilidadeNaFonte,
  invocarImportCardAssets,
  executarFaseIdioma,
  calcularEsperaRetry,
  decidirRetry,
  ehRespostaRunTerminal,
  CODIGO_RUN_TERMINAL,
  MAX_TENTATIVAS_POR_FASE,
  STATUS_FASE,
  STATUS_NAO_CONCLUSIVOS,
  STATUS_CONCLUSIVOS_POSITIVOS,
  CLASSE_LACUNA,
  FASES_IDIOMA,
  main,
} = mod;

let total = 0;
const falhas = [];
function ok(nome, cond, detalhe = "") {
  total += 1;
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}
async function lanca(nome, fn, trecho) {
  total += 1;
  try {
    await fn();
    falhas.push(`${nome} — deveria LANCAR, mas retornou normalmente`);
  } catch (e) {
    if (trecho && !String(e.message).includes(trecho)) {
      falhas.push(`${nome} — lancou com mensagem inesperada: ${e.message}`);
    }
  }
}
const dormirNoop = async () => {};

// ---------------------------------------------------------------------------
// Bloco 0 — IMPORT-SAFETY
// ---------------------------------------------------------------------------
// Prova forte: um processo Node limpo importa o modulo e termina com exit 0.
// Se main() rodasse no import, faltariam as 4 env vars obrigatorias e o
// processo imprimiria "[bootstrap-assets] ABORTADO" com exitCode 1.
total += 1;
try {
  const saida = execFileSync(
    process.execPath,
    ["--input-type=module", "-e", `await import(${JSON.stringify(URL_MODULO)}); console.log("IMPORT_OK");`],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot },
      timeout: 30_000,
    },
  );
  if (!saida.includes("IMPORT_OK")) falhas.push(`A00 import-safety — stdout inesperado: ${saida.trim()}`);
  if (saida.includes("ABORTADO") || saida.includes("bootstrap-assets] modo=")) {
    falhas.push("A00 import-safety — main() executou no import");
  }
} catch (e) {
  falhas.push(`A00 import-safety — processo falhou (main() provavelmente rodou): ${e.stderr ?? e.message}`);
}
ok("A01 main exportado mas nao invocado", typeof main === "function");
ok("A02 import nao setou exitCode", process.exitCode === undefined || process.exitCode === 0, String(process.exitCode));

// ---------------------------------------------------------------------------
// Bloco 1 — chave de comparacao (B1)
// ---------------------------------------------------------------------------
ok("A03 padding numerico removido", chaveFonte("001") === "1" && chaveFonte("1") === "1");
ok("A04 alfanumerico uppercase+trim", chaveFonte(" tg12 ") === "TG12");
ok("A05 vazio", chaveFonte(null) === "" && chaveFonte("   ") === "");
ok("A06 nao numerico com zeros nao vira numero", chaveFonte("0A1") === "0A1");
ok("A07 indice por chave",
  indexarFontePorChave([{ localId: "001", image: "x" }, { localId: "TG1", image: null }]).get("1") === true);
await lanca("A08 colisao de chave FAIL CLOSED",
  async () => indexarFontePorChave([{ localId: "1" }, { localId: "001" }]), "COLISAO_CHAVE_FONTE");

// ---------------------------------------------------------------------------
// Bloco 2 — classificacao de lacuna (B2)
// ---------------------------------------------------------------------------
ok("A09 ja no banco", classificarLacuna({ temNoBanco: true, temNaFonte: false, fonteOk: true }) === null);
ok("A10 fonte indisponivel nunca vira ausencia",
  classificarLacuna({ temNoBanco: false, temNaFonte: false, fonteOk: false }) === CLASSE_LACUNA.FONTE_INDISPONIVEL);
ok("A11 lacuna importavel",
  classificarLacuna({ temNoBanco: false, temNaFonte: true, fonteOk: true }) === CLASSE_LACUNA.IMPORTABLE_GAP);
ok("A12 ausente na fonte",
  classificarLacuna({ temNoBanco: false, temNaFonte: false, fonteOk: true }) === CLASSE_LACUNA.NOT_AVAILABLE_AT_SOURCE);

// ---------------------------------------------------------------------------
// Bloco 3 — conclusao por cobertura (B2/B3)
// ---------------------------------------------------------------------------
ok("A13 fonte ruim nunca conclui",
  concluirFasePorCobertura({ cobertura: { com_asset: 10, total: 10 }, fonteOk: false }).status
    === STATUS_FASE.FAILED_SOURCE_UNAVAILABLE);
ok("A14 fonte ruim completa=false",
  concluirFasePorCobertura({ cobertura: { com_asset: 10, total: 10 }, fonteOk: false }).completa === false);
ok("A15 nada na fonte = ALREADY_COMPLETE",
  concluirFasePorCobertura({ cobertura: { com_asset: 0, total: 10 }, disponiveisNaFonte: 0 }).status
    === STATUS_FASE.ALREADY_COMPLETE);
ok("A16 alvo limitado pela fonte",
  concluirFasePorCobertura({ cobertura: { com_asset: 3, total: 10 }, disponiveisNaFonte: 3 }).status
    === STATUS_FASE.COMPLETED);
ok("A17 cobertura parcial",
  concluirFasePorCobertura({ cobertura: { com_asset: 2, total: 10 }, disponiveisNaFonte: 10 }).status
    === STATUS_FASE.PARTIAL_COVERAGE);

// ---------------------------------------------------------------------------
// Bloco 4 — status final x populacao (CORRECTION-02)
// ---------------------------------------------------------------------------
ok("A18 COMPLETED rebaixa",
  statusFinalComPopulacao({ statusBase: STATUS_FASE.COMPLETED, cardsNoBanco: 99, declaredTotalSetSize: 103 })
    === STATUS_FASE.COMPLETED_PARTIAL_POPULATION);
ok("A19 ALREADY_COMPLETE tambem rebaixa",
  statusFinalComPopulacao({ statusBase: STATUS_FASE.ALREADY_COMPLETE, cardsNoBanco: 99, declaredTotalSetSize: 103 })
    === STATUS_FASE.COMPLETED_PARTIAL_POPULATION);
ok("A20 populacao completa nao rebaixa",
  statusFinalComPopulacao({ statusBase: STATUS_FASE.COMPLETED, cardsNoBanco: 103, declaredTotalSetSize: 103 })
    === STATUS_FASE.COMPLETED);
ok("A21 status nao conclusivo nao e tocado",
  statusFinalComPopulacao({ statusBase: STATUS_FASE.PARTIAL_COVERAGE, cardsNoBanco: 1, declaredTotalSetSize: 103 })
    === STATUS_FASE.PARTIAL_COVERAGE);
ok("A22 declared ausente nao rebaixa",
  statusFinalComPopulacao({ statusBase: STATUS_FASE.COMPLETED, cardsNoBanco: 99, declaredTotalSetSize: null })
    === STATUS_FASE.COMPLETED);
ok("A23 cardsNoBanco nao numerico nao rebaixa",
  statusFinalComPopulacao({ statusBase: STATUS_FASE.COMPLETED, cardsNoBanco: null, declaredTotalSetSize: 103 })
    === STATUS_FASE.COMPLETED);
ok("A24 STATUS_CONCLUSIVOS_POSITIVOS exportado",
  Array.isArray(STATUS_CONCLUSIVOS_POSITIVOS) && STATUS_CONCLUSIVOS_POSITIVOS.length === 2);

// ---------------------------------------------------------------------------
// Bloco 5 — STATUS_NAO_CONCLUSIVOS
// ---------------------------------------------------------------------------
ok("A25 STATUS_NAO_CONCLUSIVOS exportado", Array.isArray(STATUS_NAO_CONCLUSIVOS));
ok("A26 inclui FAILED_SOURCE_UNAVAILABLE",
  STATUS_NAO_CONCLUSIVOS.includes(STATUS_FASE.FAILED_SOURCE_UNAVAILABLE));
ok("A27 inclui FAILED_SNAPSHOT_UNAVAILABLE",
  STATUS_NAO_CONCLUSIVOS.includes(STATUS_FASE.FAILED_SNAPSHOT_UNAVAILABLE));
ok("A28 FAILED_SNAPSHOT_UNAVAILABLE nao e conclusivo positivo",
  !STATUS_CONCLUSIVOS_POSITIVOS.includes(STATUS_FASE.FAILED_SNAPSHOT_UNAVAILABLE));
ok("A29 ordem de fases congelada",
  FASES_IDIOMA[0].db === "pt-BR" && FASES_IDIOMA[1].db === "en");

// ---------------------------------------------------------------------------
// Bloco 6 — montarSetSnapshot (DTO minimo)
// ---------------------------------------------------------------------------
const payloadOk = {
  id: "base1",
  name: "Base Set",
  logo: "https://assets.tcgdex.net/en/base/base1/logo",
  cards: [{ id: "base1-1", localId: "1", name: "Alakazam", image: "https://assets.tcgdex.net/en/base/base1/1", rarity: "Rare" }],
};
const s1 = montarSetSnapshot(payloadOk);
ok("A30 snapshot gerado", s1 !== null);
ok("A31 so id e cards no topo", s1 && JSON.stringify(Object.keys(s1)) === JSON.stringify(["id", "cards"]));
ok("A32 so 4 campos por card",
  s1 && JSON.stringify(Object.keys(s1.cards[0])) === JSON.stringify(["id", "localId", "name", "image"]));
ok("A33 rarity/logo descartados", s1 && s1.cards[0].rarity === undefined && s1.logo === undefined);
ok("A34 id vem do payload, nao do codigo do Set",
  montarSetSnapshot({ ...payloadOk, id: "sv04" })?.id === "sv04");
ok("A35 sem id -> null", montarSetSnapshot({ cards: payloadOk.cards }) === null);
ok("A36 card sem name -> null",
  montarSetSnapshot({ id: "base1", cards: [{ id: "a", localId: "1", name: "" }] }) === null);
ok("A37 card sem localId -> null",
  montarSetSnapshot({ id: "base1", cards: [{ id: "a", name: "X" }] }) === null);
ok("A38 cards vazio -> null", montarSetSnapshot({ id: "base1", cards: [] }) === null);
ok("A39 cards > 500 -> null",
  montarSetSnapshot({
    id: "base1",
    cards: Array.from({ length: 501 }, (_, i) => ({ id: `c${i}`, localId: String(i + 1), name: "X" })),
  }) === null);
ok("A40 image vazia e omitida",
  montarSetSnapshot({ id: "base1", cards: [{ id: "a", localId: "1", name: "X", image: "   " }] })
    ?.cards[0].image === undefined);

// ---------------------------------------------------------------------------
// Bloco 7 — disponibilidadeNaFonte (fetch injetado, offline)
// ---------------------------------------------------------------------------
const resp = (status, body, headers = {}) => ({
  ok: status >= 200 && status < 300,
  status,
  headers: { get: (k) => headers[k] ?? null },
  json: async () => body,
});

const f1 = await disponibilidadeNaFonte("base1", "en", async () => resp(200, payloadOk), dormirNoop);
ok("A41 2xx -> ok", f1.ok === true && f1.http === 200);
ok("A42 mapa indexado", f1.mapa.get("1") === true);
ok("A43 snapshot presente no retorno", f1.snapshot !== null && f1.snapshot.id === "base1");

const payloadRuim = { id: "base1", cards: [{ id: "base1-1", localId: "1", name: "", image: "x" }] };
const f2 = await disponibilidadeNaFonte("base1", "en", async () => resp(200, payloadRuim), dormirNoop);
ok("A44 2xx com payload fora do contrato -> ok=true, snapshot=null", f2.ok === true && f2.snapshot === null);

let n429 = 0;
const f3 = await disponibilidadeNaFonte("base1", "en", async () => {
  n429 += 1;
  return n429 === 1 ? resp(429, null, { "Retry-After": "1" }) : resp(200, payloadOk);
}, dormirNoop);
ok("A45 429 -> retry uma vez e sucesso", f3.ok === true && n429 === 2);

let n404 = 0;
const f4 = await disponibilidadeNaFonte("base1", "en", async () => { n404 += 1; return resp(404, null); }, dormirNoop);
ok("A46 404 nao faz retry", f4.ok === false && f4.http === 404 && n404 === 1);

let nNet = 0;
const f5 = await disponibilidadeNaFonte("base1", "en", async () => { nNet += 1; throw new Error("ECONNRESET"); }, dormirNoop);
ok("A47 excecao de rede vira indisponibilidade", f5.ok === false && f5.http === null && nNet === 2);

const f6 = await disponibilidadeNaFonte("base1", "en",
  async () => ({ ok: true, status: 200, headers: { get: () => null }, json: async () => { throw new Error("Unexpected token"); } }),
  dormirNoop);
ok("A48 corpo nao-JSON vira indisponibilidade", f6.ok === false && String(f6.erro).includes("nao e JSON"));

ok("A49 Retry-After segundos", calcularEsperaRetry("2", 500) === 2000);
ok("A50 Retry-After teto 30s", calcularEsperaRetry("999", 500) === 30000);

// ---------------------------------------------------------------------------
// Bloco 8 — FAIL CLOSED do snapshot (PASSTHROUGH CORRECTION-01)
// ---------------------------------------------------------------------------

// 8.1 — segunda linha de defesa: invocacao direta sem snapshot lanca.
await lanca("A51 invocar sem snapshot lanca",
  async () => invocarImportCardAssets("https://x.supabase.co", "jwt", "RUN-1", null),
  "SNAPSHOT_OBRIGATORIO");
await lanca("A52 invocar com snapshot ausente (argumento omitido) lanca",
  async () => invocarImportCardAssets("https://x.supabase.co", "jwt", "RUN-1"),
  "SNAPSHOT_OBRIGATORIO");

// 8.2 — guard primario: a fase aborta ANTES de abrir run e ANTES da Edge.
function fakeQuery(resultado) {
  const q = {
    select: () => q,
    eq: () => q,
    then: (res, rej) => Promise.resolve(resultado).then(res, rej),
  };
  return q;
}
const supabaseStub = {
  rpcCalls: 0,
  from(tabela) {
    // total de cards = 2, cobertos = 0 -> fase NAO esta completa
    return fakeQuery({ count: tabela === "card" ? 2 : 0, error: null });
  },
  rpc() {
    supabaseStub.rpcCalls += 1;
    return fakeQuery({ data: [{ supported: true, run_id: "r", run_code: "RUN-X", already_active: false }], error: null });
  },
};

const fetchOriginal = globalThis.fetch;
const chamadas = [];
globalThis.fetch = async (url) => {
  chamadas.push(String(url));
  // Payload 2xx, com images (para disponiveis > 0), mas com um card sem name
  // -> montarSetSnapshot() devolve null. Cenario exato do blocker.
  return resp(200, {
    id: "base1",
    cards: [
      { id: "base1-1", localId: "1", name: "Alakazam", image: "https://assets.tcgdex.net/en/base/base1/1" },
      { id: "base1-2", localId: "2", name: "", image: "https://assets.tcgdex.net/en/base/base1/2" },
    ],
  });
};

let r8;
try {
  r8 = await executarFaseIdioma({
    supabase: supabaseStub,
    supabaseUrl: "https://x.supabase.co",
    accessToken: "jwt",
    set: { card_set_id: "cs-1", card_set_code: "BASE1", external_set_id: "base1" },
    fase: FASES_IDIOMA[1],
  });
} finally {
  globalThis.fetch = fetchOriginal;
}

ok("A53 status = FAILED_SNAPSHOT_UNAVAILABLE",
  r8?.status === STATUS_FASE.FAILED_SNAPSHOT_UNAVAILABLE, String(r8?.status));
ok("A54 nenhuma run aberta (zero rpc)", supabaseStub.rpcCalls === 0, String(supabaseStub.rpcCalls));
ok("A55 Edge NAO invocada",
  chamadas.filter((u) => u.includes("/functions/v1/import-card-assets")).length === 0,
  JSON.stringify(chamadas));
ok("A56 exatamente 1 fetch (so a fonte)", chamadas.length === 1, JSON.stringify(chamadas));
ok("A57 nao caiu em api.tcgdex.net pela Edge", chamadas[0]?.startsWith("https://api.tcgdex.net/v2/en/sets/base1"));
ok("A58 cobertura nao foi alterada", r8?.cobertura_depois === r8?.cobertura_antes);
ok("A59 run_code permanece nulo", r8?.run_code === null);
ok("A60 motivo explicito de fail closed",
  String(r8?.motivo).includes("fail closed") && String(r8?.motivo).includes("NAO invocada"));

// ---------------------------------------------------------------------------
// Bloco 9 — ASSETS-RETRY-TERMINAL-FIX-01
// Reconhecimento de IMPORT_RUN_ALREADY_TERMINAL em `code` E em `error`.
// ---------------------------------------------------------------------------

// Mensagem LIVE observada em DC1 EN (RUN-20260911-00004241).
const ERRO_REAL_409 =
  "IMPORT_RUN_ALREADY_TERMINAL: esta run já chegou a um status final e não pode ser reaberta.";

// 9.1 — reconhecimento puro
ok("A61 terminal via code", ehRespostaRunTerminal({ code: CODIGO_RUN_TERMINAL }) === true);
ok("A62 terminal via error real (prefixo)", ehRespostaRunTerminal({ error: ERRO_REAL_409 }) === true);
ok("A63 terminal via error exato sem sufixo", ehRespostaRunTerminal({ error: CODIGO_RUN_TERMINAL }) === true);
ok("A64 code tem precedencia (error ausente)",
  ehRespostaRunTerminal({ code: CODIGO_RUN_TERMINAL, error: "outra coisa" }) === true);

// 9.2 — NAO terminal (requisito 4: 409 generico nunca vira terminal)
ok("A65 409 generico por error diferente",
  ehRespostaRunTerminal({ error: "IMPORT_RUN_ALREADY_ACTIVE: ja existe run ativa." }) === false);
ok("A66 409 generico por code diferente",
  ehRespostaRunTerminal({ code: "IMPORT_RUN_ALREADY_ACTIVE" }) === false);
ok("A67 token no MEIO da mensagem nao conta",
  ehRespostaRunTerminal({ error: "falhou porque IMPORT_RUN_ALREADY_TERMINAL foi detectado" }) === false);
ok("A68 corpo vazio", ehRespostaRunTerminal({}) === false);
ok("A69 corpo null", ehRespostaRunTerminal(null) === false);
ok("A70 corpo string", ehRespostaRunTerminal(ERRO_REAL_409) === false);
ok("A71 error nao-string", ehRespostaRunTerminal({ error: { code: CODIGO_RUN_TERMINAL } }) === false);
ok("A72 COMPLETED_WITH_ERRORS nao e terminal para o retry",
  ehRespostaRunTerminal({ code: null, images: { imported: 10, failed: 3 } }) === false);

// 9.3 — regra congelada de decidirRetry (regressao, NAO alterada nesta rodada)
ok("A73 terminal -> abre run NOVA",
  decidirRetry({ tentativa: 1, runExpired: true, interrupted: false }).abrirRunNova === true);
ok("A74 nao terminal -> retry na MESMA run",
  decidirRetry({ tentativa: 1, runExpired: false, interrupted: false }).abrirRunNova === false);
ok("A75 interrupted tem precedencia sobre terminal",
  decidirRetry({ tentativa: 1, runExpired: true, interrupted: true }).repetir === false);
ok("A76 teto de tentativas tem precedencia sobre terminal",
  decidirRetry({ tentativa: MAX_TENTATIVAS_POR_FASE, runExpired: true, interrupted: false }).repetir === false);

// 9.4 — integracao ponta a ponta: o `error` real chega ate abrirRun().
// Com o defeito antigo (`corpo.code === ...`) este bloco abriria UMA run e
// repetiria na mesma; com a correcao abre uma run NOVA por tentativa.
function cenarioTerminal(corpoDoEdge) {
  const rpcArgs = [];
  const posts = [];
  let seq = 0;
  const sb = {
    from: (t) => fakeQuery({ count: t === "card" ? 2 : 0, error: null }),
    rpc: (nome, args) => {
      rpcArgs.push({ nome, args });
      seq += 1;
      return fakeQuery({
        data: [{ supported: true, run_id: `id-${seq}`, run_code: `RUN-${seq}`, already_active: false }],
        error: null,
      });
    },
  };
  const stub = async (url, init) => {
    const u = String(url);
    if (u.startsWith("https://api.tcgdex.net/")) {
      return resp(200, {
        id: "base1",
        cards: [
          { id: "base1-1", localId: "1", name: "Alakazam", image: "https://assets.tcgdex.net/en/base/base1/1" },
          { id: "base1-2", localId: "2", name: "Abra", image: "https://assets.tcgdex.net/en/base/base1/2" },
        ],
      });
    }
    posts.push(JSON.parse(init.body));
    return resp(409, corpoDoEdge);
  };
  return { sb, rpcArgs, posts, stub };
}

async function rodarCenario(corpoDoEdge) {
  const c = cenarioTerminal(corpoDoEdge);
  const original = globalThis.fetch;
  globalThis.fetch = c.stub;
  try {
    const r = await executarFaseIdioma({
      supabase: c.sb,
      supabaseUrl: "https://x.supabase.co",
      accessToken: "jwt",
      set: { card_set_id: "cs-1", card_set_code: "DC1", external_set_id: "base1" },
      fase: FASES_IDIOMA[1],
    });
    return { ...c, r };
  } finally {
    globalThis.fetch = original;
  }
}

// Caso canonico (code)
const e2eCode = await rodarCenario({ code: CODIGO_RUN_TERMINAL, error: "run terminal" });
ok("A77 [code] uma run NOVA por tentativa",
  e2eCode.rpcArgs.length === MAX_TENTATIVAS_POR_FASE, `rpc=${e2eCode.rpcArgs.length}`);
ok("A78 [code] run_code nunca reutilizado",
  new Set(e2eCode.posts.map((p) => p.run_code)).size === e2eCode.posts.length,
  JSON.stringify(e2eCode.posts.map((p) => p.run_code)));
ok("A79 [code] status nao conclusivo",
  STATUS_NAO_CONCLUSIVOS.includes(e2eCode.r.status), String(e2eCode.r.status));

// Caso real observado (error com prefixo) — o que o defeito deixava passar
const e2eErro = await rodarCenario({ error: ERRO_REAL_409 });
ok("A80 [error real] uma run NOVA por tentativa",
  e2eErro.rpcArgs.length === MAX_TENTATIVAS_POR_FASE, `rpc=${e2eErro.rpcArgs.length}`);
ok("A81 [error real] run_code nunca reutilizado",
  new Set(e2eErro.posts.map((p) => p.run_code)).size === e2eErro.posts.length,
  JSON.stringify(e2eErro.posts.map((p) => p.run_code)));
ok("A82 [error real] diag_code registra o HTTP",
  e2eErro.r.diag_code === "HTTP_409", String(e2eErro.r.diag_code));
ok("A83 [error real] snapshot passthrough preservado",
  e2eErro.posts.every((p) => p.set_snapshot?.id === "base1" && p.set_snapshot.cards.length === 2));

// 409 DIFERENTE — nao terminal: precisa repetir na MESMA run (1 rpc so)
const e2eOutro = await rodarCenario({ error: "IMPORT_RUN_ALREADY_ACTIVE: ja existe run ativa." });
ok("A84 [409 diferente] NAO abre run nova",
  e2eOutro.rpcArgs.length === 1, `rpc=${e2eOutro.rpcArgs.length}`);
ok("A85 [409 diferente] reutiliza o mesmo run_code",
  new Set(e2eOutro.posts.map((p) => p.run_code)).size === 1,
  JSON.stringify(e2eOutro.posts.map((p) => p.run_code)));

// interrupted continua encerrando na primeira tentativa
const e2eInterrupted = await rodarCenario({ error: ERRO_REAL_409, interrupted: true });
ok("A86 interrupted encerra sem nova run",
  e2eInterrupted.rpcArgs.length === 1 && e2eInterrupted.r.status === STATUS_FASE.INTERRUPTED,
  `rpc=${e2eInterrupted.rpcArgs.length} status=${e2eInterrupted.r.status}`);

// ---------------------------------------------------------------------------
console.log(`RESULTADO: ${total - falhas.length}/${total} OK`);
if (falhas.length > 0) {
  console.error(`\nFALHAS (${falhas.length}):`);
  for (const f of falhas) console.error(`  - ${f}`);
  process.exitCode = 1;
}
