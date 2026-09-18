// Project Mimikyu — supabase/functions/import-card-variants/services/cors.test.ts
// Bateria do suporte CORS mínimo (CORS-BROWSER-INVOKE-01, 2026-09-18).
//
// 100% offline: nenhuma chamada de rede, nenhum acesso ao Supabase.
//
// Execução canônica:
//   deno test --allow-read supabase/functions/import-card-variants/services/cors.test.ts
//
// POR QUE ESTE TESTE É ESTRUTURAL + TABELA-VERDADE, E NÃO E2E
// ------------------------------------------------------------------
// `index.ts` chama `Deno.serve(...)` no topo do módulo: importá-lo num teste
// subiria um servidor. Por isso não há `import` daqui para lá. Em vez disso:
//
//   (A) PROVAS ESTRUTURAIS — lêem o texto real de `index.ts` e provam o
//       contrato (allowlist sem wildcard, curto-circuito do preflight antes
//       da lógica, handler intacto, CORS aplicado a toda resposta).
//   (B) TABELA-VERDADE — extrai o corpo REAL de `corsHeadersFor` do arquivo
//       e o avalia. Não é uma reimplementação paralela que poderia divergir:
//       é o mesmo código, exercitado.
//
// O que NENHUM teste offline pode provar é o comportamento do navegador. A
// prova definitiva do CORS é o preflight real contra a function publicada —
// e ela pertence ao gate pós-deploy, não a este arquivo.

const INDEX_URL = new URL("../index.ts", import.meta.url);

type Resultado = { caso: string; ok: boolean; detalhe?: string };
function assert(acc: Resultado[], caso: string, ok: boolean, detalhe?: string) {
  acc.push({ caso, ok, detalhe: ok ? undefined : detalhe ?? "assertion falhou" });
}

/**
 * Extrai o corpo de `corsHeadersFor` do texto de `index.ts` e o transforma
 * numa função executável. Falha alto se a assinatura mudar — o que é
 * desejável: um teste que silenciosamente para de testar é pior que nenhum.
 */
function loadCorsHeadersFor(src: string): (req: Request) => Record<string, string> {
  const marker = "function corsHeadersFor(req: Request): Record<string, string> {";
  const start = src.indexOf(marker);
  if (start < 0) throw new Error("CORS_TEST_MARKER_NAO_ENCONTRADO: corsHeadersFor mudou de assinatura");

  const bodyStart = start + marker.length;
  let depth = 1, i = bodyStart;
  while (i < src.length && depth > 0) {
    if (src[i] === "{") depth += 1;
    else if (src[i] === "}") depth -= 1;
    i += 1;
  }
  const body = src.slice(bodyStart, i - 1)
    // tipos TS que o `new Function` não entende, removidos sem alterar lógica
    .replace(/:\s*Record<string,\s*string>/g, "");

  const allowlist = src.match(/const CORS_ALLOWED_ORIGINS = new Set<string>\(\[([\s\S]*?)\]\);/);
  if (!allowlist) throw new Error("CORS_TEST_ALLOWLIST_NAO_ENCONTRADA");

  const prelude = `const CORS_ALLOWED_ORIGINS = new Set([${allowlist[1]}]);`;
  return new Function("req", `${prelude}\n${body}`) as (req: Request) => Record<string, string>;
}

const reqWith = (origin: string | null, method = "POST") =>
  new Request("https://example.test/functions/v1/import-card-variants", {
    method,
    headers: origin === null ? {} : { Origin: origin },
  });

export function runCorsTests(): Resultado[] {
  const r: Resultado[] = [];
  const src = Deno.readTextFileSync(INDEX_URL);
  assert(r, "index.ts foi lido", src.length > 0);

  // ===== A — PROVAS ESTRUTURAIS ==========================================

  assert(r, "A allowlist explícita contém o origin de produção",
    /const CORS_ALLOWED_ORIGINS = new Set<string>\(\[\s*"https:\/\/mmkyu\.vercel\.app",\s*\]\);/.test(src));
  assert(r, "A NUNCA usa wildcard em Access-Control-Allow-Origin",
    !/Access-Control-Allow-Origin["'\s:]+\*/.test(src) && !src.includes('"*"'));
  assert(r, "A métodos e headers do preflight conforme contrato",
    src.includes('const CORS_ALLOW_METHODS = "POST, OPTIONS";') &&
    src.includes('const CORS_ALLOW_HEADERS = "authorization, apikey, content-type, x-client-info";'));

  // Curto-circuito do preflight ANTES da lógica de negócio: o `return` do
  // OPTIONS precisa vir ANTES da única chamada a handleImportRequest.
  const iOptions = src.indexOf('if (req.method === "OPTIONS"');
  const iHandler = src.indexOf("await handleImportRequest(req)");
  assert(r, "A preflight é tratado antes de delegar ao handler",
    iOptions > 0 && iHandler > 0 && iOptions < iHandler,
    `OPTIONS@${iOptions} handler@${iHandler}`);
  assert(r, "A preflight responde 204 sem corpo",
    /return new Response\(null, \{\s*status: 204,/.test(src));

  // O handler é uma função nomeada, chamada UMA única vez, de dentro do
  // Deno.serve — isto é o que garante CORS uniforme em toda resposta.
  assert(r, "A handler extraído para função nomeada",
    src.includes("async function handleImportRequest(req: Request): Promise<Response> {"));
  assert(r, "A handleImportRequest é invocado exatamente uma vez",
    (src.match(/await handleImportRequest\(req\)/g) ?? []).length === 1);
  assert(r, "A há exatamente um Deno.serve",
    (src.match(/Deno\.serve\(/g) ?? []).length === 1);
  assert(r, "A CORS é aplicado a TODA resposta do handler",
    /for \(const \[key, value\] of Object\.entries\(cors\)\) response\.headers\.set\(key, value\);/.test(src));

  // Os 11 retornos do handler seguem intactos — nenhum header CORS à mão.
  // Conta `return Response.json(` (a forma executável); a forma solta
  // `Response.json(...)` aparece também no comentário de governança e não
  // pode contaminar a contagem.
  const responses = src.match(/return Response\.json\(/g) ?? [];
  assert(r, "A os 11 retornos Response.json do handler continuam existindo", responses.length === 11,
    `encontrados: ${responses.length}`);
  assert(r, "A nenhum Response.json recebeu header CORS manualmente",
    !/return Response\.json\([\s\S]{0,400}?Access-Control-Allow-Origin/.test(src));

  // Fronteira de identidade preservada.
  assert(r, "A auth.getUser() preservado", src.includes("userClient.auth.getUser()"));
  assert(r, "A rpc(\"is_admin\") preservado", src.includes('userClient.rpc("is_admin")'));
  assert(r, "A 405 para método != POST preservado",
    src.includes('{ success: false, error: "METHOD_NOT_ALLOWED" }, { status: 405, headers: { Allow: "POST" } }'));

  // ===== B — TABELA-VERDADE (código real, extraído e executado) ==========

  const corsHeadersFor = loadCorsHeadersFor(src);

  const semOrigin = corsHeadersFor(reqWith(null));
  assert(r, "B sem Origin → nenhum header (Server Action inalterado)",
    Object.keys(semOrigin).length === 0, JSON.stringify(semOrigin));

  const permitido = corsHeadersFor(reqWith("https://mmkyu.vercel.app"));
  assert(r, "B origin permitido → ACAO com o origin exato",
    permitido["Access-Control-Allow-Origin"] === "https://mmkyu.vercel.app");
  assert(r, "B origin permitido → Vary: Origin", permitido["Vary"] === "Origin");
  assert(r, "B origin permitido → ACAO nunca é '*'",
    permitido["Access-Control-Allow-Origin"] !== "*");

  for (const mau of [
    "https://evil.example",
    "http://mmkyu.vercel.app",             // esquema diferente
    "https://mmkyu.vercel.app.evil.com",   // sufixo malicioso
    "https://MMKYU.vercel.app",            // caixa diferente
    "null",
  ]) {
    const h = corsHeadersFor(reqWith(mau));
    assert(r, `B origin não permitido (${mau}) → SEM Access-Control-Allow-Origin`,
      h["Access-Control-Allow-Origin"] === undefined, JSON.stringify(h));
    assert(r, `B origin não permitido (${mau}) → ainda declara Vary: Origin`,
      h["Vary"] === "Origin");
  }

  return r;
}

Deno.test("cors — suporte mínimo à invocação pelo browser", () => {
  const resultados = runCorsTests();
  const falhas = resultados.filter((x) => !x.ok);

  for (const x of resultados) {
    console.log(`${x.ok ? "PASS" : "FAIL"}  ${x.caso}${x.detalhe ? `  — ${x.detalhe}` : ""}`);
  }
  console.log(`\n${resultados.length} casos · ${resultados.length - falhas.length} PASS · ${falhas.length} FAIL`);

  if (resultados.length === 0) throw new Error("CORS_TESTS_VAZIO");
  if (falhas.length > 0) {
    throw new Error(
      `CORS_TESTS_FAILED (${falhas.length}/${resultados.length}):\n` +
        falhas.map((x) => `  - ${x.caso}${x.detalhe ? ` — ${x.detalhe}` : ""}`).join("\n"),
    );
  }
});
