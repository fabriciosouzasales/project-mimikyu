/*
===============================================================================
HARNESS OFFLINE — IMAGE-QUALITY-FALLBACK-01
Arquivo....: supabase/functions/import-card-assets/provas-image-quality-fallback.ts
Alvo.......: ./services/storage.ts  (modulo puro — NAO importa index.ts, que
             executa Deno.serve() no topo)

Evidencia LIVE que motivou a correcao (SM10 #226, Whimsicott GX, pt-BR):
  https://assets.tcgdex.net/pt/sm/sm10/226/high.webp -> HTTP 404
  https://assets.tcgdex.net/pt/sm/sm10/226/low.webp  -> HTTP 200

GARANTIAS DE ISOLAMENTO
  Rede: zero — `baixar` e injetado e nunca faz fetch.
  Banco: zero. Escrita: zero. Credenciais: zero.

EXECUCAO (a partir da raiz do repositorio):
  deno test --allow-none supabase/functions/import-card-assets/provas-image-quality-fallback.ts
  (ou: deno run supabase/functions/import-card-assets/provas-image-quality-fallback.ts)

Criterio de PASS: "RESULTADO: 35/35 OK" e exit code 0.
  (Q00-Q14 = 15; Bloco 4 = 7 codigos x 2 = 14; Q29-Q34 = 6)
===============================================================================
*/

import {
  baixarImagemComFallbackDeQualidade,
  buildCardStoragePath,
  buildTcgdexHighImageUrl,
  buildTcgdexLowImageUrl,
  ImageDownloadError,
  type BaixarComRetry,
  type ImageDownloadErrorCode,
} from "./services/storage.ts";

const BASE = "https://assets.tcgdex.net/pt/sm/sm10/226";
const HIGH = `${BASE}/high.webp`;
const LOW = `${BASE}/low.webp`;
const CTX = { externalCardId: "sm10-226", collectorNumber: "226" };

const IMAGEM_FALSA = {
  buffer: new Uint8Array([1, 2, 3]),
  mimeType: "image/webp",
  fileExtension: "webp",
  fileSizeBytes: 3,
  checksumSha256: "deadbeef",
} as never;

function erro(code: ImageDownloadErrorCode, url: string, status: number | null, retriable: boolean) {
  return new ImageDownloadError(code, `IMAGE_DOWNLOAD_FAILED: ${code}`, url, status, retriable);
}

/** Fabrica um `baixar` que responde por URL e registra a ordem das chamadas. */
function fakeBaixar(
  plano: Record<string, "ok" | ImageDownloadError | Error>,
): BaixarComRetry & { chamadas: string[] } {
  const chamadas: string[] = [];
  const fn = (async (url: string) => {
    chamadas.push(url);
    const r = plano[url];
    if (r === "ok") return IMAGEM_FALSA;
    if (r === undefined) throw new Error(`URL NAO PREVISTA NO PLANO: ${url}`);
    throw r;
  }) as BaixarComRetry & { chamadas: string[] };
  fn.chamadas = chamadas;
  return fn;
}

let total = 0;
const falhas: string[] = [];
function ok(nome: string, cond: boolean, detalhe = "") {
  total += 1;
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}
async function rejeita(
  nome: string,
  fn: () => Promise<unknown>,
  esperado: ImageDownloadErrorCode | "NAO_DOWNLOAD_ERROR",
) {
  total += 1;
  try {
    await fn();
    falhas.push(`${nome} — deveria LANCAR, mas resolveu`);
  } catch (e) {
    if (esperado === "NAO_DOWNLOAD_ERROR") {
      if (e instanceof ImageDownloadError) falhas.push(`${nome} — erro foi convertido indevidamente`);
      return;
    }
    const c = e instanceof ImageDownloadError ? e.code : "(nao e ImageDownloadError)";
    if (c !== esperado) falhas.push(`${nome} — code esperado ${esperado}, veio ${c}`);
  }
}

// ---------------------------------------------------------------------------
// Bloco 0 — composicao de URL (regressao)
// ---------------------------------------------------------------------------
ok("Q00 high monta /high.webp", buildTcgdexHighImageUrl(BASE) === HIGH, buildTcgdexHighImageUrl(BASE));
ok("Q01 low monta /low.webp", buildTcgdexLowImageUrl(BASE) === LOW, buildTcgdexLowImageUrl(BASE));
ok("Q02 mesma origem/host nas duas variantes",
  new URL(HIGH).origin === new URL(LOW).origin && new URL(LOW).origin === "https://assets.tcgdex.net");
ok("Q03 low nao introduz path traversal", new URL(LOW).pathname === "/pt/sm/sm10/226/low.webp");
ok("Q04 storage path inalterado (webp)",
  buildCardStoragePath("SM10", "226", "pt-BR", "webp") === "sm10/pt-BR/226.webp",
  buildCardStoragePath("SM10", "226", "pt-BR", "webp"));

// ---------------------------------------------------------------------------
// Bloco 1 — high 200 => low NUNCA chamada
// ---------------------------------------------------------------------------
{
  const b = fakeBaixar({ [HIGH]: "ok" });
  const r = await baixarImagemComFallbackDeQualidade(BASE, CTX, b);
  ok("Q05 high 200 => sucesso", r.image === IMAGEM_FALSA);
  ok("Q06 high 200 => qualidade 'high'", r.qualidade === "high", r.qualidade);
  ok("Q07 high 200 => exatamente 1 chamada", b.chamadas.length === 1, JSON.stringify(b.chamadas));
  ok("Q08 high 200 => low NUNCA chamada", !b.chamadas.includes(LOW), JSON.stringify(b.chamadas));
}

// ---------------------------------------------------------------------------
// Bloco 2 — high 404 + low 200 => sucesso via low (caso SM10 #226)
// ---------------------------------------------------------------------------
{
  const b = fakeBaixar({ [HIGH]: erro("HTTP_404", HIGH, 404, false), [LOW]: "ok" });
  const r = await baixarImagemComFallbackDeQualidade(BASE, CTX, b);
  ok("Q09 high 404 + low 200 => sucesso", r.image === IMAGEM_FALSA);
  ok("Q10 qualidade efetiva = 'low'", r.qualidade === "low", r.qualidade);
  ok("Q11 ordem high -> low", JSON.stringify(b.chamadas) === JSON.stringify([HIGH, LOW]), JSON.stringify(b.chamadas));
  ok("Q12 exatamente 2 chamadas", b.chamadas.length === 2);
}

// ---------------------------------------------------------------------------
// Bloco 3 — high 404 + low 404 => falha (indisponivel de verdade)
// ---------------------------------------------------------------------------
{
  const b = fakeBaixar({ [HIGH]: erro("HTTP_404", HIGH, 404, false), [LOW]: erro("HTTP_404", LOW, 404, false) });
  await rejeita("Q13 high 404 + low 404 => HTTP_404",
    () => baixarImagemComFallbackDeQualidade(BASE, CTX, b), "HTTP_404");
  ok("Q14 as duas variantes foram testadas",
    JSON.stringify(b.chamadas) === JSON.stringify([HIGH, LOW]), JSON.stringify(b.chamadas));
}

// ---------------------------------------------------------------------------
// Bloco 4 — erros que NUNCA autorizam fallback
// ---------------------------------------------------------------------------
for (
  const [code, status, retriable] of [
    ["HTTP_5XX", 500, true],
    ["HTTP_429", 429, true],
    ["TIMEOUT", null, true],
    ["NETWORK", null, true],
    ["HTTP_OTHER", 418, false],
    ["EMPTY_RESPONSE", 200, false],
    ["UNSUPPORTED_MIME_TYPE", 200, false],
  ] as [ImageDownloadErrorCode, number | null, boolean][]
) {
  const b = fakeBaixar({ [HIGH]: erro(code, HIGH, status, retriable) });
  await rejeita(`Q_${code} relanca sem fallback`,
    () => baixarImagemComFallbackDeQualidade(BASE, CTX, b), code);
  ok(`Q_${code} low NUNCA chamada`, !b.chamadas.includes(LOW), JSON.stringify(b.chamadas));
}

// ---------------------------------------------------------------------------
// Bloco 5 — erro generico (nao-ImageDownloadError) passa intacto
// ---------------------------------------------------------------------------
{
  const b = fakeBaixar({ [HIGH]: new Error("CARD_NOT_FOUND: 226") });
  await rejeita("Q29 erro generico relanca intacto",
    () => baixarImagemComFallbackDeQualidade(BASE, CTX, b), "NAO_DOWNLOAD_ERROR");
  ok("Q30 erro generico nao aciona low", !b.chamadas.includes(LOW));
}

// ---------------------------------------------------------------------------
// Bloco 6 — low, apos fallback legitimo, mantem a politica de retry
// ---------------------------------------------------------------------------
{
  // O `baixar` injetado É o dono do retry. Aqui ele falha 2x e sucede na 3a,
  // exatamente como downloadImageWithRetry faria com um erro transitorio.
  const chamadas: string[] = [];
  let tentativasLow = 0;
  const comRetry = (async (url: string) => {
    chamadas.push(url);
    if (url === HIGH) throw erro("HTTP_404", HIGH, 404, false);
    tentativasLow += 1;
    if (tentativasLow < 3) throw erro("HTTP_5XX", LOW, 503, true);
    return IMAGEM_FALSA;
  }) as BaixarComRetry;

  // Simula o wrapper de retry externo: reinvoca enquanto for retriable.
  const baixarComRetryReal: BaixarComRetry = async (url, ctx) => {
    for (let t = 1; t <= 3; t += 1) {
      try {
        return await comRetry(url, ctx);
      } catch (e) {
        const de = e instanceof ImageDownloadError ? e : null;
        if (!de?.retriable || t === 3) throw e;
      }
    }
    throw new Error("inalcancavel");
  };

  const r = await baixarImagemComFallbackDeQualidade(BASE, CTX, baixarComRetryReal);
  ok("Q31 low com 5xx transitorio ainda converge", r.qualidade === "low", r.qualidade);
  ok("Q32 low foi retentado 3x dentro do mesmo baixar", tentativasLow === 3, String(tentativasLow));
  ok("Q33 high tentado uma unica vez (404 nao e retriable)",
    chamadas.filter((u) => u === HIGH).length === 1, JSON.stringify(chamadas));
}

// ---------------------------------------------------------------------------
// Bloco 7 — idempotencia da decisao
// ---------------------------------------------------------------------------
{
  const plano = { [HIGH]: erro("HTTP_404", HIGH, 404, false), [LOW]: "ok" } as const;
  const r1 = await baixarImagemComFallbackDeQualidade(BASE, CTX, fakeBaixar({ ...plano }));
  const r2 = await baixarImagemComFallbackDeQualidade(BASE, CTX, fakeBaixar({ ...plano }));
  ok("Q34 mesma entrada => mesma qualidade", r1.qualidade === r2.qualidade && r1.qualidade === "low");
}

// ---------------------------------------------------------------------------
console.log(`RESULTADO: ${total - falhas.length}/${total} OK`);
if (falhas.length > 0) {
  console.error(`\nFALHAS (${falhas.length}):`);
  for (const f of falhas) console.error(`  - ${f}`);
  Deno.exit(1);
}
