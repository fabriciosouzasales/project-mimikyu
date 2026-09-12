/*
===============================================================================
HARNESS OFFLINE — ASSETS-FINAL-CDN-AUDIT-01
Arquivo..: web/scripts/bootstrap-cards/provas-audit-assets-cdn.mjs
Alvo.....: ./audit-assets-cdn.mjs

Prova que a semantica de sondagem do auditor e a MESMA da Edge
(IMAGE-QUALITY-FALLBACK-01): high primeiro, low SOMENTE apos 404 comprovado,
e nada transitorio vira "ausente".

Rede: zero (o sondador e injetado). Banco: zero. Escrita: zero.

EXECUCAO (raiz do repositorio):
  node web/scripts/bootstrap-cards/provas-audit-assets-cdn.mjs

Criterio de PASS: "RESULTADO: 146/146 OK" e exit code 0.
  Blocos 0-8 (CDN, redirect, import-safety) ................. 52
  Bloco 9  FONTE_INDISPONIVEL decide por HTTP (CORR-03B) .... 23
  Bloco 10 SNAPSHOT_INVALIDO decide por universo (CORR-03B) . 19
  Bloco 0  import-safety do auditor ................. 2
  Bloco 0b import-safety do CLI importado (CORR-01) .. 3
  Bloco 1  classificacao de status (+3xx, CORR-01) ... 15
  Bloco 2  guard de origem ......................... 6
  Bloco 3  high 200 => low nunca .................... 3
  Bloco 4  high 404 + low 200 ....................... 2
  Bloco 5  high 404 + low 404 ....................... 1
  Bloco 6  transitorios nunca viram ausente ......... 7
  Bloco 6b redirect fail-closed (CORR-01) ........... 7
  Bloco 7  origem invalida .......................... 2
  Bloco 8  args / fase de idioma .................... 4
  Bloco 9  FONTE_INDISPONIVEL decide por HTTP (03B) . 23
  Bloco 10 SNAPSHOT_INVALIDO decide por universo .... 19
  Bloco 11 metadata 404 != veredito da CDN (PROOF-04) 20
  Bloco 12 leitura via RPC governada (RPC-05) ....... 11
  Bloco 13 rotulo da causa do bloqueio (CORR-06) .... 21
===============================================================================
*/

import { execFileSync } from "node:child_process";

const URL_MODULO = new URL("./audit-assets-cdn.mjs", import.meta.url).href;
const URL_BOOTSTRAP = new URL("./run-bootstrap-assets.mjs", import.meta.url).href;
const mod = await import(URL_MODULO);
const {
  RESULTADO,
  classificarStatusCdn,
  ehRetentavel,
  ehRedirect,
  urlDeOrigemAutorizada,
  sondarCandidato,
  decidirVeredito,
  faseDoIdioma,
  parseArgs,
  main,
} = mod;

const BASE = "https://assets.tcgdex.net/pt/xy/xy1/1";
const HIGH = `${BASE}/high.webp`;
const LOW = `${BASE}/low.webp`;

let total = 0;
const falhas = [];
function ok(nome, cond, detalhe = "") {
  total += 1;
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}

/** Sondador injetado: responde por URL e registra a ordem das chamadas. */
function fakeSondar(plano) {
  const chamadas = [];
  const fn = async (url) => {
    chamadas.push(url);
    const r = plano[url];
    if (r === undefined) throw new Error(`URL NAO PREVISTA: ${url}`);
    return r;
  };
  fn.chamadas = chamadas;
  return fn;
}
const st = (status) => ({ status, erro: null });
const net = (erro) => ({ status: null, erro });

// --------------------------------------------------------------------------
// Bloco 0 — import-safety
// --------------------------------------------------------------------------
total += 1;
try {
  const saida = execFileSync(
    process.execPath,
    ["--input-type=module", "-e", `await import(${JSON.stringify(URL_MODULO)}); console.log("IMPORT_OK");`],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot }, timeout: 30_000 },
  );
  if (!saida.includes("IMPORT_OK")) falhas.push(`A00 import-safety — stdout: ${saida.trim()}`);
  if (saida.includes("ABORTADO") || saida.includes("READ-ONLY |")) falhas.push("A00 import-safety — main() rodou no import");
} catch (e) {
  falhas.push(`A00 import-safety — processo falhou: ${e.stderr ?? e.message}`);
}
ok("A01 main exportado mas nao invocado", typeof main === "function");

// --------------------------------------------------------------------------
// Bloco 0b — CORRECTION-01 item 1: IMPORT SAFETY do CLI importado
// --------------------------------------------------------------------------
// O auditor importa run-bootstrap-assets.mjs, que TAMBEM e um CLI. Aqui o
// subprocesso importa o bootstrap com argv ADVERSARIAL (as flags do auditor)
// e com env MINIMO (sem as 4 variaveis do bootstrap). Se o guard de entrada
// falhasse, main() rodaria e: (a) imprimiria "modo=" ou "ABORTADO: ENV_AUSENTE";
// (b) tentaria login/rede. Silencio + exit 0 e a prova.
//
// HARNESS-CORRECTION-02: o separador `--` e OBRIGATORIO. Sem ele o proprio
// Node consome `--idioma` como opcao sua e aborta com "bad option: --idioma",
// antes mesmo de importar o bootstrap — o teste falhava por erro de invocacao,
// nao por defeito do guard. Com `--`, tudo que vem depois vai para
// process.argv do script.
//
// Efeito colateral desejavel: sob `-e`, process.argv[1] passa a ser
// "--idioma" (truthy). Isso significa que o guard NAO e satisfeito por
// curto-circuito no `process.argv[1] &&` — a comparacao de caminho
// (`fileURLToPath(import.meta.url) === path.resolve(process.argv[1])`) e
// realmente exercitada, e path.resolve("--idioma") jamais coincide com o
// caminho do bootstrap. Prova mais forte que a da rodada anterior.
total += 1;
try {
  const saida = execFileSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      `await import(${JSON.stringify(URL_BOOTSTRAP)}); console.log("BOOTSTRAP_IMPORT_OK");`,
      "--",
      "--idioma", "en", "--concorrencia", "8", "--apply",
    ],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot }, timeout: 30_000 },
  );
  if (!saida.includes("BOOTSTRAP_IMPORT_OK")) falhas.push(`A01b bootstrap import — stdout: ${saida.trim()}`);
  if (/modo=|ABORTADO|ENV_AUSENTE|\[bootstrap-assets\]/.test(saida)) {
    falhas.push(`A01b bootstrap import — main() rodou por efeito colateral: ${saida.trim()}`);
  }
} catch (e) {
  falhas.push(`A01b bootstrap import com argv adversarial falhou: ${e.stderr ?? e.message}`);
}

// O auditor NAO importa parseArgs do bootstrap: usa o proprio. Prova de que
// argv do auditor e lido pelo parser do auditor, sem interferencia.
ok("A01c argv do auditor nao e consumido pelo bootstrap",
  (() => { const a = parseArgs(["--idioma", "en", "--concorrencia", "2"]); return a.idioma === "en" && a.concorrencia === 2; })());
ok("A01d import do bootstrap nao exporta parseArgs conflitante para o auditor",
  typeof parseArgs === "function" && parseArgs([]).idioma === "pt-BR");

// --------------------------------------------------------------------------
// Bloco 1 — classificacao de status (pura)
// --------------------------------------------------------------------------
ok("A02 200 = DISPONIVEL", classificarStatusCdn(200) === "DISPONIVEL");
ok("A03 204 = DISPONIVEL", classificarStatusCdn(204) === "DISPONIVEL");
ok("A04 404 = AUSENTE", classificarStatusCdn(404) === "AUSENTE");
ok("A05 403 NAO e ausente", classificarStatusCdn(403) === "NAO_CONCLUSIVO");
ok("A06 429 NAO e ausente", classificarStatusCdn(429) === "NAO_CONCLUSIVO");
ok("A07 503 NAO e ausente", classificarStatusCdn(503) === "NAO_CONCLUSIVO");
ok("A08 405 NAO e ausente", classificarStatusCdn(405) === "NAO_CONCLUSIVO");
// CORRECTION-01 item 2 — nenhum 3xx pode virar DISPONIVEL nem AUSENTE.
ok("A08a 301 NAO conclusivo", classificarStatusCdn(301) === "NAO_CONCLUSIVO");
ok("A08b 302 NAO conclusivo", classificarStatusCdn(302) === "NAO_CONCLUSIVO");
ok("A08c 307 NAO conclusivo", classificarStatusCdn(307) === "NAO_CONCLUSIVO");
ok("A08d 308 NAO conclusivo", classificarStatusCdn(308) === "NAO_CONCLUSIVO");
ok("A08e ehRedirect cobre 300..399",
  ehRedirect(301) && ehRedirect(302) && ehRedirect(307) && ehRedirect(308) &&
  !ehRedirect(200) && !ehRedirect(404) && !ehRedirect(503) && !ehRedirect(null));
ok("A08f redirect NAO e retentavel", !ehRetentavel(301) && !ehRetentavel(302) && !ehRetentavel(308));
ok("A09 retentavel: 429 e 5xx", ehRetentavel(429) && ehRetentavel(500) && ehRetentavel(503));
ok("A10 nao retentavel: 404/403", !ehRetentavel(404) && !ehRetentavel(403));

// --------------------------------------------------------------------------
// Bloco 2 — guard de origem
// --------------------------------------------------------------------------
ok("A11 origem valida", urlDeOrigemAutorizada(BASE) === true);
ok("A12 http rejeitado", urlDeOrigemAutorizada("http://assets.tcgdex.net/x") === false);
ok("A13 host-suffix hostil rejeitado", urlDeOrigemAutorizada("https://assets.tcgdex.net.evil.com/x") === false);
ok("A14 host de metadata rejeitado", urlDeOrigemAutorizada("https://api.tcgdex.net/v2/pt/sets/xy1") === false);
ok("A15 credenciais embutidas rejeitadas", urlDeOrigemAutorizada("https://u:p@assets.tcgdex.net/x") === false);
ok("A16 lixo rejeitado", urlDeOrigemAutorizada("nao-e-url") === false && urlDeOrigemAutorizada(null) === false);

// --------------------------------------------------------------------------
// Bloco 3 — high 200 => low NUNCA consultada
// --------------------------------------------------------------------------
{
  const s = fakeSondar({ [HIGH]: st(200) });
  const r = await sondarCandidato(BASE, s);
  ok("A17 high 200 => high_available", r.resultado === RESULTADO.HIGH_AVAILABLE, r.resultado);
  ok("A18 high 200 => 1 sondagem", s.chamadas.length === 1, JSON.stringify(s.chamadas));
  ok("A19 high 200 => low nunca consultada", !s.chamadas.includes(LOW));
}

// --------------------------------------------------------------------------
// Bloco 4 — high 404 + low 200 => low_only_available
// --------------------------------------------------------------------------
{
  const s = fakeSondar({ [HIGH]: st(404), [LOW]: st(200) });
  const r = await sondarCandidato(BASE, s);
  ok("A20 high404+low200 => low_only_available", r.resultado === RESULTADO.LOW_ONLY_AVAILABLE, r.resultado);
  ok("A21 ordem high -> low", JSON.stringify(s.chamadas) === JSON.stringify([HIGH, LOW]), JSON.stringify(s.chamadas));
}

// --------------------------------------------------------------------------
// Bloco 5 — high 404 + low 404 => source debt
// --------------------------------------------------------------------------
{
  const s = fakeSondar({ [HIGH]: st(404), [LOW]: st(404) });
  const r = await sondarCandidato(BASE, s);
  ok("A22 high404+low404 => unavailable_404_404", r.resultado === RESULTADO.UNAVAILABLE_404_404, r.resultado);
}

// --------------------------------------------------------------------------
// Bloco 6 — nada transitorio pode virar "ausente"
// --------------------------------------------------------------------------
{
  const casos = [
    ["high 503", { [HIGH]: st(503) }],
    ["high 429", { [HIGH]: st(429) }],
    ["high timeout", { [HIGH]: net("TIMEOUT") }],
    ["high network", { [HIGH]: net("NETWORK: ECONNRESET") }],
    ["high 403", { [HIGH]: st(403) }],
    ["high404 + low 503", { [HIGH]: st(404), [LOW]: st(503) }],
  ];
  for (const [nome, plano] of casos) {
    const s = fakeSondar(plano);
    const r = await sondarCandidato(BASE, s);
    ok(`A_${nome} => transient_error`, r.resultado === RESULTADO.TRANSIENT_ERROR, r.resultado);
  }
}
{
  // Erro transitorio em high NUNCA autoriza consultar low.
  const s = fakeSondar({ [HIGH]: st(503) });
  await sondarCandidato(BASE, s);
  ok("A29 high 503 => low nunca consultada", !s.chamadas.includes(LOW), JSON.stringify(s.chamadas));
}

// --------------------------------------------------------------------------
// Bloco 6b — CORRECTION-01 item 2: REDIRECT FAIL-CLOSED
// --------------------------------------------------------------------------
{
  // Um 302 para outro host NUNCA pode ser lido como imagem disponivel.
  const s = fakeSondar({ [HIGH]: { status: 302, erro: "REDIRECT_NAO_SEGUIDO -> https://cdn.evil.example/x.webp" } });
  const r = await sondarCandidato(BASE, s);
  ok("A29a high 302 cross-origin => transient_error", r.resultado === RESULTADO.TRANSIENT_ERROR, r.resultado);
  ok("A29b high 302 => low NUNCA consultada", !s.chamadas.includes(LOW), JSON.stringify(s.chamadas));
  ok("A29c destino do redirect aparece no detalhe",
    String(r.detalhe).includes("REDIRECT_NAO_SEGUIDO") && String(r.detalhe).includes("cdn.evil.example"), String(r.detalhe));
}
{
  // Redirect no low, apos 404 legitimo em high, tambem e inconclusivo.
  const s = fakeSondar({
    [HIGH]: { status: 404, erro: null },
    [LOW]: { status: 308, erro: "REDIRECT_NAO_SEGUIDO -> https://outro.host/x" },
  });
  const r = await sondarCandidato(BASE, s);
  ok("A29d low 308 => transient_error, nao unavailable", r.resultado === RESULTADO.TRANSIENT_ERROR, r.resultado);
  ok("A29e detalhe preserva high 404 + destino",
    String(r.detalhe).includes("high 404") && String(r.detalhe).includes("REDIRECT_NAO_SEGUIDO"), String(r.detalhe));
}
{
  // Prova estatica: o fetch real e emitido com redirect: "manual".
  const fonte = await (await import("node:fs/promises")).readFile(
    new URL("./audit-assets-cdn.mjs", import.meta.url), "utf8",
  );
  ok("A29f sondarUrl usa redirect: \"manual\"", fonte.includes('redirect: "manual"'));
  ok("A29g nenhum redirect: \"follow\" remanescente", !fonte.includes('redirect: "follow"'));
}

// --------------------------------------------------------------------------
// Bloco 7 — origem invalida e transitorio, nao ausente
// --------------------------------------------------------------------------
{
  const s = fakeSondar({});
  const r = await sondarCandidato("https://api.tcgdex.net/v2/pt/sets/xy1", s);
  ok("A30 origem invalida => transient_error", r.resultado === RESULTADO.TRANSIENT_ERROR, r.resultado);
  ok("A31 origem invalida => zero sondagem", s.chamadas.length === 0);
}

// --------------------------------------------------------------------------
// Bloco 8 — args e fase de idioma
// --------------------------------------------------------------------------
ok("A32 default = XY / pt-BR", (() => { const a = parseArgs([]); return a.expansion[0] === "XY" && a.idioma === "pt-BR"; })());
ok("A33 --only desliga --expansion", (() => { const a = parseArgs(["--only", "XY1"]); return a.expansion === null && a.only[0] === "XY1"; })());
ok("A34 concorrencia limitada a 8", parseArgs(["--concorrencia", "99"]).concorrencia === 8);
ok("A35 fase pt-BR -> tcgdex 'pt'", faseDoIdioma("pt-BR").tcgdex === "pt");

// --------------------------------------------------------------------------
// Bloco 9 — VERDICT-CORRECTION-03B: FONTE_INDISPONIVEL decide por HTTP
// --------------------------------------------------------------------------
// Base: o cenario real de XY pt-BR (1520/1520 unavailable_404_404).
const XY_REAL = {
  total_candidates: 1520,
  high_available: 0,
  low_only_available: 0,
  unavailable_404_404: 1520,
  transient_error: 0,
  accessible_not_imported: 0,
};
// HTTP 404 na listagem = veredito DETERMINISTICO da fonte (o Set nao existe
// naquele idioma) => KNOWN SOURCE DEBT. `cards_sem_asset` e IRRELEVANTE aqui:
// XYP tem 216 Cards sem asset pt-BR justamente porque o /pt e 404.
// SOURCE-404-CDN-PROOF-04 — metadata 404 deixou de ser suficiente por si: o Set
// so e NAO bloqueante quando nada restou por provar, isto e, quando TODOS os
// Cards faltantes tiveram identidade autoritativa e foram sondados na CDN
// (`cards_sem_identidade === 0`). O default 0 abaixo representa esse caso.
const fonte404 = (set, cardsSemAsset, semIdentidade = 0) => ({
  set, http: 404, erro: "HTTP 404",
  cards_sem_asset: cardsSemAsset,
  cards_enviados_a_cdn: cardsSemAsset - semIdentidade,
  cards_sem_identidade: semIdentidade,
});
// Qualquer desfecho NAO deterministico => INCONCLUSIVO.
const fonteIndeterminada = (set, cardsSemAsset, http = null, erro = "TIMEOUT") =>
  ({ set, http, erro, cards_sem_asset: cardsSemAsset });

// 9.1 — CENARIO REAL XY: 12 Sets com /pt 404 e MUITOS Cards sem asset.
{
  const doze = Array.from({ length: 12 }, (_, i) => fonte404(`XY${i + 1}`, 100 + i));
  const v = decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: doze });
  ok("A36 12 Sets /pt 404 com cards_sem_asset>0 => PASS WITH KNOWN SOURCE DEBT",
    v.veredito.startsWith("PASS WITH KNOWN SOURCE DEBT"), v.veredito);
  ok("A37 os 12 entram como NAO bloqueantes", v.naoBloqueantes.length === 12 && v.bloqueantes.length === 0);
  ok("A38 particao e identidade OK", v.particaoOk && v.identidadeOk);
  ok("A39 veredito sinaliza o debt fora do universo",
    v.veredito.includes("12 Set(s) de source debt deterministico FORA do universo auditado"), v.veredito);
}

// 9.2 — XYP real: 404 com 216 Cards sem asset NAO pode bloquear.
{
  const v = decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: [fonte404("XYP", 216)] });
  ok("A40 XYP 404 / 216 sem asset => nao bloqueia",
    v.bloqueantes.length === 0 && v.veredito.startsWith("PASS WITH KNOWN SOURCE DEBT"), v.veredito);
}

// 9.3 — desfecho NAO deterministico bloqueia, mesmo com cobertura completa.
{
  const casos = [
    ["timeout", fonteIndeterminada("XY13", 0, null, "TIMEOUT")],
    ["rede", fonteIndeterminada("XY13", 0, null, "NETWORK: ECONNRESET")],
    ["429", fonteIndeterminada("XY13", 0, 429, "HTTP 429")],
    ["503", fonteIndeterminada("XY13", 0, 503, "HTTP 503")],
    ["corpo nao-JSON em 200", fonteIndeterminada("XY13", 0, 200, "corpo nao e JSON")],
    ["colisao de chave", fonteIndeterminada("XY13", 0, null, "COLISAO_CHAVE_FONTE")],
  ];
  for (const [nome, s] of casos) {
    const v = decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: [s] });
    ok(`A_fonte_${nome} => INCONCLUSIVO`, v.veredito.startsWith("INCONCLUSIVO") && v.bloqueantes.length === 1, v.veredito);
  }
}

// 9.4 — mistura: 404 nao bloqueia, 503 bloqueia, no MESMO relatorio.
{
  const v = decidirVeredito({
    ...XY_REAL,
    setsFonteIndisponivel: [fonte404("XYP", 216), fonteIndeterminada("XY13", 7, 503, "HTTP 503")],
  });
  ok("A47 mistura => INCONCLUSIVO", v.veredito.startsWith("INCONCLUSIVO"), v.veredito);
  ok("A48 so o 503 bloqueia",
    v.bloqueantes.length === 1 && v.bloqueantes[0].set === "XY13" && v.naoBloqueantes.length === 1);
  ok("A49 motivo mostra origem e http", v.veredito.includes("XY13[FONTE_ILEGIVEL,http=503](7)"), v.veredito);
}

// 9.5 — FAIL CLOSED na origem FONTE: http ausente/NaN/string nao e 404.
{
  ok("A50 http ausente => bloqueia",
    decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: [{ set: "XY9", cards_sem_asset: 0 }] })
      .bloqueantes.length === 1);
  ok("A51 http NaN => bloqueia",
    decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: [{ set: "XY9", http: NaN, cards_sem_asset: 0 }] })
      .bloqueantes.length === 1);
  ok("A52 http string '404' => bloqueia (sem coercao)",
    decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: [{ set: "XY9", http: "404", cards_sem_asset: 0 }] })
      .bloqueantes.length === 1);
}

// 9.6 — regressoes de precedencia (inalteradas pela 03B)
{
  ok("A53 transient_error=1 => INCONCLUSIVO",
    decidirVeredito({ ...XY_REAL, unavailable_404_404: 1519, transient_error: 1 })
      .veredito.includes("transient_error=1"));
  ok("A54 accessible_not_imported=2 => FAIL",
    decidirVeredito({
      ...XY_REAL, unavailable_404_404: 1518, high_available: 1, low_only_available: 1,
      accessible_not_imported: 2, setsFonteIndisponivel: [fonte404("XY1", 5)],
    }).veredito.startsWith("FAIL"));
  ok("A55 particao quebrada => INVALIDO",
    decidirVeredito({ ...XY_REAL, unavailable_404_404: 999 }).veredito.startsWith("INVALIDO"));
  ok("A56 INVALIDO vence bloqueante de fonte",
    decidirVeredito({ ...XY_REAL, unavailable_404_404: 999, setsFonteIndisponivel: [fonteIndeterminada("XY1", 5)] })
      .veredito.startsWith("INVALIDO"));
  ok("A57 identidade quebrada => INVALIDO",
    decidirVeredito({ ...XY_REAL, accessible_not_imported: 3 }).veredito.startsWith("INVALIDO"));
  ok("A58 lista vazia => PASS",
    decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: [] }).veredito.startsWith("PASS WITH KNOWN SOURCE DEBT"));
}

// --------------------------------------------------------------------------
// Bloco 10 — VERDICT-CORRECTION-03B: SNAPSHOT_INVALIDO decide por universo
// --------------------------------------------------------------------------
// Aqui a fonte RESPONDEU 2xx — nao ha veredito dela para herdar. O criterio e
// `cards_sem_asset`, com fail closed. Criterio DIFERENTE do de FONTE.
const semSnap = (set, cardsSemAsset) =>
  (cardsSemAsset === undefined ? { set } : { set, cards_sem_asset: cardsSemAsset });

// 10.1 — snapshot invalido + cards_sem_asset=0 => NAO bloqueia
{
  const v = decidirVeredito({ ...XY_REAL, setsSemSnapshot: [semSnap("XY5", 0), semSnap("XY6", 0)] });
  ok("A59 snapshot invalido com cobertura completa => PASS",
    v.veredito.startsWith("PASS WITH KNOWN SOURCE DEBT"), v.veredito);
  ok("A60 os 2 entram como nao bloqueantes", v.naoBloqueantes.length === 2 && v.bloqueantes.length === 0);
  ok("A61 origem marcada como SNAPSHOT_INVALIDO",
    v.naoBloqueantes.every((s) => s.origem === "SNAPSHOT_INVALIDO"));
  ok("A62 lista de snapshot fica separada da de fonte",
    v.semSnapshot.naoBloqueantes.length === 2 && v.fonteIlegivel.naoBloqueantes.length === 0);
}

// 10.2 — snapshot invalido + cards_sem_asset>0 => INCONCLUSIVO
{
  const v = decidirVeredito({ ...XY_REAL, setsSemSnapshot: [semSnap("XY7", 4)] });
  ok("A63 snapshot invalido com universo auditavel => INCONCLUSIVO",
    v.veredito.startsWith("INCONCLUSIVO"), v.veredito);
  ok("A64 motivo nomeia Set, origem e tamanho",
    v.veredito.includes("XY7[SNAPSHOT_INVALIDO](4)"), v.veredito);
  ok("A65 contabilizado no balde de snapshot, nao no de fonte",
    v.semSnapshot.bloqueantes.length === 1 && v.fonteIlegivel.bloqueantes.length === 0);
}

// 10.3 — snapshot invalido com campo ausente/NaN/"0" => FAIL CLOSED
{
  ok("A66 cards_sem_asset ausente => bloqueia",
    decidirVeredito({ ...XY_REAL, setsSemSnapshot: [semSnap("XY8")] }).veredito.startsWith("INCONCLUSIVO"));
  ok("A67 cards_sem_asset NaN => bloqueia",
    decidirVeredito({ ...XY_REAL, setsSemSnapshot: [semSnap("XY8", NaN)] }).bloqueantes.length === 1);
  ok("A68 cards_sem_asset \"0\" => bloqueia (sem coercao)",
    decidirVeredito({ ...XY_REAL, setsSemSnapshot: [semSnap("XY8", "0")] }).bloqueantes.length === 1);
  ok("A69 campo ausente aparece como '?' no motivo",
    decidirVeredito({ ...XY_REAL, setsSemSnapshot: [semSnap("XY8")] }).veredito.includes("XY8[SNAPSHOT_INVALIDO](?)"));
}

// 10.4 — CRITERIOS DIFERENTES convivendo: http=404 nao bloqueia mesmo com
// universo grande; snapshot invalido com o MESMO universo bloqueia.
{
  const v = decidirVeredito({
    ...XY_REAL,
    setsFonteIndisponivel: [fonte404("XYP", 216)],
    setsSemSnapshot: [semSnap("XY4", 216)],
  });
  ok("A70 mesmo cards_sem_asset, vereditos diferentes por origem",
    v.fonteIlegivel.naoBloqueantes.length === 1 && v.semSnapshot.bloqueantes.length === 1, v.veredito);
  ok("A71 resultado final => INCONCLUSIVO (so o snapshot bloqueia)",
    v.veredito.startsWith("INCONCLUSIVO") && v.bloqueantes.length === 1, v.veredito);
  ok("A72 motivo distingue as origens",
    v.veredito.includes("XY4[SNAPSHOT_INVALIDO](216)") && !v.veredito.includes("XYP"), v.veredito);
}

// 10.5 — as duas origens somam quando ambas sao bloqueantes
{
  const v = decidirVeredito({
    ...XY_REAL,
    setsFonteIndisponivel: [fonte404("XY1", 5), fonteIndeterminada("XY2", 3, 503, "HTTP 503")],
    setsSemSnapshot: [semSnap("XY3", 0), semSnap("XY4", 9)],
  });
  ok("A73 2 bloqueantes (1 de cada origem)",
    v.bloqueantes.length === 2 &&
    v.fonteIlegivel.bloqueantes.length === 1 && v.semSnapshot.bloqueantes.length === 1);
  ok("A74 2 nao bloqueantes (1 de cada origem)",
    v.naoBloqueantes.length === 2 &&
    v.fonteIlegivel.naoBloqueantes.length === 1 && v.semSnapshot.naoBloqueantes.length === 1);
  ok("A75 motivo cita as duas origens",
    v.veredito.includes("XY2[FONTE_ILEGIVEL,http=503](3)") && v.veredito.includes("XY4[SNAPSHOT_INVALIDO](9)"), v.veredito);
}

// 10.6 — regressao: PASS so com as DUAS listas limpas
{
  ok("A76 ambas vazias => PASS",
    decidirVeredito({ ...XY_REAL, setsFonteIndisponivel: [], setsSemSnapshot: [] })
      .veredito.startsWith("PASS WITH KNOWN SOURCE DEBT"));
  ok("A77 default das duas listas e [] (omissao nao quebra)",
    decidirVeredito({ ...XY_REAL }).veredito.startsWith("PASS WITH KNOWN SOURCE DEBT"));
}

// --------------------------------------------------------------------------
// Bloco 11 — SOURCE-404-CDN-PROOF-04: metadata 404 NAO e veredito da CDN
// --------------------------------------------------------------------------
// Premissa provada nesta fase: `api.tcgdex.net` (metadata) e
// `assets.tcgdex.net` (arquivos) sao hosts distintos e JA divergiram. Logo
// `HTTP 404` na listagem `/{lang}/sets/{id}` significa METADATA_SOURCE_404, e
// nao KNOWN SOURCE DEBT. O debt so pode ser afirmado depois que cada Card
// faltante for provado 404/404 direto na CDN.
//
// Cenario base: XYP, Set com metadata /pt 404 e 216 Cards sem asset pt-BR.
// Os candidatos entram pelos contadores normais; o que muda no veredito e que
// o Set so deixa de bloquear quando `cards_sem_identidade === 0`.
const XYP_META404 = {
  total_candidates: 216,
  high_available: 0,
  low_only_available: 0,
  unavailable_404_404: 216,
  transient_error: 0,
  accessible_not_imported: 0,
};

// 11.1 — metadata 404 + CDN 404/404 => KNOWN SOURCE DEBT PROVADO, nao bloqueia
{
  const s = fakeSondar({ [HIGH]: st(404), [LOW]: st(404) });
  const r = await sondarCandidato(BASE, s);
  ok("A78 metadata404 + CDN 404/404 => unavailable_404_404",
    r.resultado === RESULTADO.UNAVAILABLE_404_404, r.resultado);
  const v = decidirVeredito({ ...XYP_META404, setsFonteIndisponivel: [fonte404("XYP", 216, 0)] });
  ok("A79 todos os 216 provados 404/404 => PASS WITH KNOWN SOURCE DEBT",
    v.veredito.startsWith("PASS WITH KNOWN SOURCE DEBT"), v.veredito);
  ok("A80 XYP nao bloqueia quando nada restou por provar",
    v.bloqueantes.length === 0 && v.fonteIlegivel.naoBloqueantes.length === 1);
}

// 11.2 — metadata 404 + CDN high 200 => FAIL (acionavel, ha o que importar)
{
  const s = fakeSondar({ [HIGH]: st(200) });
  const r = await sondarCandidato(BASE, s);
  ok("A81 metadata404 + high 200 => high_available", r.resultado === RESULTADO.HIGH_AVAILABLE, r.resultado);
  ok("A82 high 200 nao consulta low", !s.chamadas.includes(LOW), JSON.stringify(s.chamadas));
  const v = decidirVeredito({
    ...XYP_META404, high_available: 1, unavailable_404_404: 215, accessible_not_imported: 1,
    setsFonteIndisponivel: [fonte404("XYP", 216, 0)],
  });
  ok("A83 1 Card baixavel num Set metadata-404 => FAIL, nunca PASS",
    v.veredito.startsWith("FAIL") && v.veredito.includes("1 Card(s) baixaveis"), v.veredito);
}

// 11.3 — metadata 404 + high 404 / low 200 => FAIL (acionavel via fallback)
{
  const s = fakeSondar({ [HIGH]: st(404), [LOW]: st(200) });
  const r = await sondarCandidato(BASE, s);
  ok("A84 metadata404 + high404/low200 => low_only_available",
    r.resultado === RESULTADO.LOW_ONLY_AVAILABLE, r.resultado);
  const v = decidirVeredito({
    ...XYP_META404, low_only_available: 1, unavailable_404_404: 215, accessible_not_imported: 1,
    setsFonteIndisponivel: [fonte404("XYP", 216, 0)],
  });
  ok("A85 low-only num Set metadata-404 => FAIL (a regra high->low resolve)",
    v.veredito.startsWith("FAIL"), v.veredito);
}

// 11.4 — metadata 404 + desfecho transitorio na CDN => INCONCLUSIVO
{
  for (const [nome, plano] of [
    ["high 503", { [HIGH]: st(503) }],
    ["high 429", { [HIGH]: st(429) }],
    ["high timeout", { [HIGH]: net("TIMEOUT") }],
    ["high404 + low 500", { [HIGH]: st(404), [LOW]: st(500) }],
  ]) {
    const r = await sondarCandidato(BASE, fakeSondar(plano));
    ok(`A_meta404_cdn_${nome} => transient_error`, r.resultado === RESULTADO.TRANSIENT_ERROR, r.resultado);
  }
  const v = decidirVeredito({
    ...XYP_META404, unavailable_404_404: 215, transient_error: 1,
    setsFonteIndisponivel: [fonte404("XYP", 216, 0)],
  });
  ok("A90 transitorio na CDN => INCONCLUSIVO, nunca debt",
    v.veredito.startsWith("INCONCLUSIVO") && v.veredito.includes("transient_error=1"), v.veredito);
}

// 11.5 — metadata 404 + identidade insuficiente => INCONCLUSIVO
// Sem `card_external_reference.image_source_url` no idioma alvo nao existe URL
// confiavel: a rota da CDN carrega o slug da serie e, como a evidencia dos
// subsets SWSH mostra, o diretorio de Assets pode ate divergir do external_set_id.
// Adivinhar e proibido — entao o Set volta a bloquear.
{
  const v = decidirVeredito({
    total_candidates: 0, high_available: 0, low_only_available: 0,
    unavailable_404_404: 0, transient_error: 0, accessible_not_imported: 0,
    setsFonteIndisponivel: [fonte404("XYP", 216, 216)],
  });
  ok("A91 216 faltantes sem identidade => INCONCLUSIVO", v.veredito.startsWith("INCONCLUSIVO"), v.veredito);
  ok("A92 motivo nomeia o Set e quantos ficaram sem identidade",
    v.veredito.includes("XYP[METADATA_404,sem_identidade=216](216)"), v.veredito);
  ok("A93 identidade parcial tambem bloqueia (1 de 216 basta)",
    decidirVeredito({ ...XYP_META404, unavailable_404_404: 215, total_candidates: 215,
      setsFonteIndisponivel: [fonte404("XYP", 216, 1)] }).bloqueantes.length === 1);
}

// 11.6 — FAIL CLOSED no campo de identidade: ausente/NaN/string nao vale 0
{
  const semCampo = { set: "XYP", http: 404, erro: "HTTP 404", cards_sem_asset: 216 };
  ok("A94 cards_sem_identidade ausente => bloqueia",
    decidirVeredito({ ...XYP_META404, setsFonteIndisponivel: [semCampo] }).bloqueantes.length === 1);
  ok("A95 cards_sem_identidade NaN => bloqueia",
    decidirVeredito({ ...XYP_META404, setsFonteIndisponivel: [{ ...semCampo, cards_sem_identidade: NaN }] })
      .bloqueantes.length === 1);
  ok("A96 cards_sem_identidade \"0\" => bloqueia (sem coercao)",
    decidirVeredito({ ...XYP_META404, setsFonteIndisponivel: [{ ...semCampo, cards_sem_identidade: "0" }] })
      .bloqueantes.length === 1);
  ok("A97 ausencia do campo aparece como '?' no motivo",
    decidirVeredito({ ...XYP_META404, setsFonteIndisponivel: [semCampo] })
      .veredito.includes("XYP[METADATA_404,sem_identidade=?](216)"));
}

// --------------------------------------------------------------------------
// Bloco 12 — EXTERNAL-REFERENCE-READ-RPC-05: leitura via RPC governada
// --------------------------------------------------------------------------
// `card_external_reference` tem RLS=true, zero policy e SELECT apenas para
// postgres/service_role — o SELECT direto abortou o smoke de XYP com
// "permission denied". A fronteira esta correta; a leitura passa pela RPC
// READ-ONLY/ADMIN-ONLY. Aqui provamos o CONTRATO do cliente, sem rede e sem
// banco: qual chamada e feita, com quais argumentos, em que lotes.
{
  const { lerUrlsAutoritativas, RPC_URLS_AUTORITATIVAS, TAMANHO_LOTE_IDENTIDADE } = mod;

  /** Stub de supabase-js: registra rpc() e denuncia qualquer from(). */
  function fakeSupabase(responder) {
    const chamadas = [];
    return {
      chamadas,
      from() { throw new Error("PROIBIDO: acesso direto a tabela via .from()"); },
      async rpc(nome, args) {
        chamadas.push({ nome, args });
        return responder(nome, args);
      },
    };
  }
  const linha = (id, url, ext) => ({ card_id: id, image_source_url: url, external_card_id: ext });

  // 12.1 — chama a RPC pelo nome exato, com os argumentos nomeados corretos.
  {
    const sb = fakeSupabase(() => ({ data: [linha("c1", "https://x/1", "zz-1")], error: null }));
    const mapa = await lerUrlsAutoritativas(sb, ["c1"], "pt-BR");
    ok("A98 usa rpc(), nao .from()", sb.chamadas.length === 1);
    ok("A99 nome da RPC exato",
      sb.chamadas[0].nome === "admin_list_card_external_image_sources" &&
      sb.chamadas[0].nome === RPC_URLS_AUTORITATIVAS, sb.chamadas[0].nome);
    ok("A100 repassa p_card_ids e p_language_code",
      JSON.stringify(sb.chamadas[0].args) === JSON.stringify({ p_card_ids: ["c1"], p_language_code: "pt-BR" }),
      JSON.stringify(sb.chamadas[0].args));
    ok("A101 devolve { url, external_card_id } por card_id",
      mapa.get("c1")?.url === "https://x/1" && mapa.get("c1")?.external_card_id === "zz-1");
  }

  // 12.2 — lotes de 200: 401 ids => 3 chamadas (200/200/1).
  {
    const ids = Array.from({ length: 401 }, (_, i) => `c${i}`);
    const sb = fakeSupabase(() => ({ data: [], error: null }));
    await lerUrlsAutoritativas(sb, ids, "pt-BR");
    ok("A102 tamanho de lote = 200", TAMANHO_LOTE_IDENTIDADE === 200, String(TAMANHO_LOTE_IDENTIDADE));
    ok("A103 401 ids => 3 lotes de 200/200/1",
      JSON.stringify(sb.chamadas.map((c) => c.args.p_card_ids.length)) === JSON.stringify([200, 200, 1]),
      JSON.stringify(sb.chamadas.map((c) => c.args.p_card_ids.length)));
    ok("A104 nenhum lote excede o teto de 500 da RPC",
      sb.chamadas.every((c) => c.args.p_card_ids.length <= 500));
  }

  // 12.3 — erro da RPC vira FALHA_LER_EXTERNAL_REFERENCE (nunca silencio).
  //   Importa: se isto virasse mapa vazio, o auditor leria "sem identidade" e
  //   devolveria INCONCLUSIVO por um motivo FALSO — permissao, nao ausencia.
  {
    const sb = fakeSupabase(() => ({ data: null, error: { message: "permission denied" } }));
    let msg = null;
    try { await lerUrlsAutoritativas(sb, ["c1"], "pt-BR"); } catch (e) { msg = e.message; }
    ok("A105 erro da RPC propaga como FALHA_LER_EXTERNAL_REFERENCE",
      typeof msg === "string" && msg.startsWith("FALHA_LER_EXTERNAL_REFERENCE:"), String(msg));
  }

  // 12.4 — linha sem image_source_url e ignorada (defesa no cliente, alem do
  //   filtro que a propria RPC ja aplica).
  {
    const sb = fakeSupabase(() => ({
      data: [linha("c1", null, "zz-1"), linha("c2", "https://x/2", "zz-2")], error: null,
    }));
    const mapa = await lerUrlsAutoritativas(sb, ["c1", "c2"], "pt-BR");
    ok("A106 URL nula nao entra no mapa", !mapa.has("c1") && mapa.has("c2"), JSON.stringify([...mapa.keys()]));
  }

  // 12.5 — prova estatica: o auditor nao le a tabela diretamente em lugar algum.
  {
    const fonte = await (await import("node:fs/promises")).readFile(
      new URL("./audit-assets-cdn.mjs", import.meta.url), "utf8",
    );
    ok("A107 nenhum .from(\"card_external_reference\") no auditor",
      !fonte.includes('from("card_external_reference")'));
    ok("A108 nenhuma referencia a external_set_id vinda da RPC",
      !fonte.includes("p_external_set_id") && !fonte.includes("ident.external_set_id"));
  }
}

// --------------------------------------------------------------------------
// Bloco 13 — REPORTING-CORRECTION-06: rotulo da CAUSA do bloqueio
// --------------------------------------------------------------------------
// Regressao do smoke real: XYP/pt-BR (metadata HTTP 404, identity_insufficient
// = 216) era impresso como "fonte nao deterministica (timeout/rede/429/5xx/
// parse)". O veredito estava CORRETO (INCONCLUSIVO); o rotulo e que induzia a
// acao errada — "e so rodar de novo" — quando a acao real e reconciliar
// identidade. Aqui travamos a classificacao, sem tocar no gate.
{
  const { CLASSE_BLOQUEIO, classificarBloqueante, particionarBloqueantesParaRelatorio } = mod;

  const meta404Bloqueante = (set, universo, semId) =>
    ({ set, http: 404, erro: "HTTP 404", cards_sem_asset: universo,
       cards_sem_identidade: semId, origem: "FONTE_ILEGIVEL" });
  const naoDetBloqueante = (set, universo, http, erro) =>
    ({ set, http, erro, cards_sem_asset: universo, origem: "FONTE_ILEGIVEL" });
  const snapBloqueante = (set, universo) =>
    ({ set, cards_sem_asset: universo, origem: "SNAPSHOT_INVALIDO" });

  // 13.1 — o caso real: XYP metadata 404 + 216 sem identidade.
  {
    const xyp = meta404Bloqueante("XYP", 216, 216);
    ok("A109 XYP e METADATA_404_IDENTIDADE_INSUFICIENTE",
      classificarBloqueante(xyp) === CLASSE_BLOQUEIO.METADATA_404_IDENTIDADE_INSUFICIENTE,
      classificarBloqueante(xyp));
    ok("A110 XYP NAO e FONTE_NAO_DETERMINISTICA (o defeito do relatorio)",
      classificarBloqueante(xyp) !== CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA);
  }

  // 13.2 — fonte realmente nao deterministica continua na classe 2.
  {
    for (const [nome, s] of [
      ["timeout", naoDetBloqueante("XY13", 5, null, "TIMEOUT")],
      ["rede", naoDetBloqueante("XY13", 5, null, "NETWORK: ECONNRESET")],
      ["429", naoDetBloqueante("XY13", 5, 429, "HTTP 429")],
      ["503", naoDetBloqueante("XY13", 5, 503, "HTTP 503")],
      ["parse 200", naoDetBloqueante("XY13", 5, 200, "corpo nao e JSON")],
    ]) {
      ok(`A_classe_${nome} => FONTE_NAO_DETERMINISTICA`,
        classificarBloqueante(s) === CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA, classificarBloqueante(s));
    }
  }

  // 13.3 — snapshot invalido tem classe propria, mesmo sem http.
  {
    ok("A116 SNAPSHOT_INVALIDO tem classe propria",
      classificarBloqueante(snapBloqueante("XY4", 9)) === CLASSE_BLOQUEIO.SNAPSHOT_INVALIDO);
    ok("A117 origem vence: snapshot com http=404 NAO vira metadata-404",
      classificarBloqueante({ ...snapBloqueante("XY4", 9), http: 404 }) === CLASSE_BLOQUEIO.SNAPSHOT_INVALIDO);
  }

  // 13.4 — PARTICAO: as 3 classes somam exatamente a lista de bloqueantes,
  //   sem perder nem duplicar nenhum Set.
  {
    const lista = [
      meta404Bloqueante("XYP", 216, 216),
      meta404Bloqueante("DC1", 34, 34),
      naoDetBloqueante("XY13", 5, 503, "HTTP 503"),
      snapBloqueante("XY4", 9),
    ];
    const p = particionarBloqueantesParaRelatorio(lista);
    const m = p[CLASSE_BLOQUEIO.METADATA_404_IDENTIDADE_INSUFICIENTE];
    const d = p[CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA];
    const s = p[CLASSE_BLOQUEIO.SNAPSHOT_INVALIDO];
    ok("A118 particao soma o total", m.length + d.length + s.length === lista.length,
      `${m.length}+${d.length}+${s.length} vs ${lista.length}`);
    ok("A119 contagens por classe corretas", m.length === 2 && d.length === 1 && s.length === 1);
    ok("A120 nenhum Set duplicado entre classes",
      new Set([...m, ...d, ...s].map((x) => x.set)).size === lista.length);
    ok("A121 XYP e DC1 na classe de identidade",
      m.map((x) => x.set).join(",") === "XYP,DC1", m.map((x) => x.set).join(","));
    ok("A122 lista vazia => 3 classes vazias", (() => {
      const z = particionarBloqueantesParaRelatorio([]);
      return Object.values(z).every((a) => a.length === 0) && Object.keys(z).length === 3;
    })());
  }

  // 13.5 — FAIL CLOSED de rotulo: sem http conclusivo, cai na classe que pede
  //   REEXECUCAO (a acao mais barata e sem risco), nunca em "debt de identidade".
  {
    ok("A123 http ausente => FONTE_NAO_DETERMINISTICA",
      classificarBloqueante({ set: "X", cards_sem_asset: 1, origem: "FONTE_ILEGIVEL" })
        === CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA);
    ok("A124 http string '404' => FONTE_NAO_DETERMINISTICA (sem coercao)",
      classificarBloqueante({ set: "X", http: "404", cards_sem_asset: 1, origem: "FONTE_ILEGIVEL" })
        === CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA);
    ok("A125 entrada invalida nao explode",
      classificarBloqueante(null) === CLASSE_BLOQUEIO.FONTE_NAO_DETERMINISTICA);
  }

  // 13.6 — o gate NAO mudou: mesmos vereditos de antes desta correcao.
  {
    const base = { total_candidates: 0, high_available: 0, low_only_available: 0,
      unavailable_404_404: 0, transient_error: 0, accessible_not_imported: 0 };
    const v = decidirVeredito({ ...base,
      setsFonteIndisponivel: [{ set: "XYP", http: 404, erro: "HTTP 404",
        cards_sem_asset: 216, cards_enviados_a_cdn: 0, cards_sem_identidade: 216 }] });
    ok("A126 XYP segue INCONCLUSIVO (gate intacto)", v.veredito.startsWith("INCONCLUSIVO"), v.veredito);
    ok("A127 motivo segue nomeando sem_identidade=216",
      v.veredito.includes("XYP[METADATA_404,sem_identidade=216](216)"), v.veredito);
  }

  // 13.7 — prova estatica: o rotulo enganoso nao voltou ao console.
  {
    const fonte = await (await import("node:fs/promises")).readFile(
      new URL("./audit-assets-cdn.mjs", import.meta.url), "utf8",
    );
    ok("A128 sem a linha antiga que rotulava tudo como nao deterministico",
      !fonte.includes("fonte nao deterministica (timeout/rede/429/5xx/parse): ${fonteIlegivel.bloqueantes.length}"));
    ok("A129 console imprime as 3 classes",
      fonte.includes("[1] METADATA_404 + IDENTIDADE INSUFICIENTE") &&
      fonte.includes("[2] FONTE NAO DETERMINISTICA") &&
      fonte.includes("[3] SNAPSHOT INVALIDO"));
  }
}

// --------------------------------------------------------------------------
console.log(`RESULTADO: ${total - falhas.length}/${total} OK`);
if (falhas.length > 0) {
  console.error(`\nFALHAS (${falhas.length}):`);
  for (const f of falhas) console.error(`  - ${f}`);
  process.exitCode = 1;
}
