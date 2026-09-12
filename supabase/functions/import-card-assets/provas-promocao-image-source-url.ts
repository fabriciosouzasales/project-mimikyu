/*
===============================================================================
HARNESS OFFLINE — PROMOTION-INTEGRITY-GATE-01 / CORRECTION-01
Arquivo....: supabase/functions/import-card-assets/provas-promocao-image-source-url.ts
Alvo.......: ./services/database.ts -> promoverImageSourceUrlDerivada()

Risco coberto:
  Um UPDATE filtrado por (card_id, asset_source_id, language_id) pode terminar
  com `error = null` e ZERO linhas afetadas — sob RLS, um WHERE que nao casa
  nada visivel nao e erro. A versao anterior devolvia sucesso baseada em
  `data.length > 0` sobre um `select("id")`, que nao prova o VALOR persistido.

Contrato provado aqui:
  sucesso SOMENTE se error == null, data existir e
  data.image_source_url === imageSourceUrl.
  Zero linhas / erro / excecao => false, sempre sem lancar.

GARANTIAS DE ISOLAMENTO
  Rede: zero. Banco: zero. Escrita: zero. O cliente `supabase` e um stub que
  registra as chamadas e devolve um resultado programado.

EXECUCAO (a partir da raiz do repositorio):
  deno run supabase/functions/import-card-assets/provas-promocao-image-source-url.ts

Criterio de PASS: "RESULTADO: 12/12 OK" e exit code 0.
  Caso 1 sucesso .............................. 4
  Caso 2 zero linhas / erro ................... 2
  Caso 3 URL divergente ....................... 2
  Caso 4 excecao do client .................... 2
  Guards de entrada ........................... 2
===============================================================================
*/

import { promoverImageSourceUrlDerivada } from "./services/database.ts";

const CHAVE = {
  card_id: "0009114a-845b-46da-aeb0-3a94fa691427",
  asset_source_id: "11111111-1111-1111-1111-111111111111",
  language_id: "22222222-2222-2222-2222-222222222222",
};
const URL_PROMOVIDA = "https://assets.tcgdex.net/en/swsh/swsh4.5/SV001";

type Resultado = { data: unknown; error: unknown };

/** Stub do cliente: registra o que foi chamado e devolve o resultado programado. */
function fakeSupabase(
  resultado: Resultado | (() => never),
): {
  from: (t: string) => unknown;
  chamadas: { tabela?: string; payload?: Record<string, unknown>; filtros: [string, unknown][]; select?: string; single: boolean };
} {
  const chamadas = {
    tabela: undefined as string | undefined,
    payload: undefined as Record<string, unknown> | undefined,
    filtros: [] as [string, unknown][],
    select: undefined as string | undefined,
    single: false,
  };

  const encadeavel = {
    update(payload: Record<string, unknown>) {
      chamadas.payload = payload;
      return encadeavel;
    },
    upsert() {
      throw new Error("PROIBIDO: promocao nunca pode usar UPSERT.");
    },
    eq(coluna: string, valor: unknown) {
      chamadas.filtros.push([coluna, valor]);
      return encadeavel;
    },
    select(cols: string) {
      chamadas.select = cols;
      return encadeavel;
    },
    single() {
      chamadas.single = true;
      if (typeof resultado === "function") return resultado();
      return Promise.resolve(resultado);
    },
  };

  return {
    from(tabela: string) {
      chamadas.tabela = tabela;
      return encadeavel;
    },
    chamadas,
  };
}

let total = 0;
const falhas: string[] = [];
function ok(nome: string, cond: boolean, detalhe = "") {
  total += 1;
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}

// ---------------------------------------------------------------------------
// Caso 1 — 1 linha + URL igual => true
// ---------------------------------------------------------------------------
{
  const sb = fakeSupabase({
    data: { id: "ref-1", image_source_url: URL_PROMOVIDA },
    error: null,
  });
  const r = await promoverImageSourceUrlDerivada(sb as never, CHAVE, URL_PROMOVIDA);

  ok("R01 sucesso => true", r === true, String(r));
  ok("R02 payload SO image_source_url + updated_at",
    sb.chamadas.payload !== undefined &&
      Object.keys(sb.chamadas.payload).sort().join(",") === "image_source_url,updated_at",
    JSON.stringify(sb.chamadas.payload));
  ok("R03 filtros exatos pelos 3 campos da chave",
    JSON.stringify(sb.chamadas.filtros) === JSON.stringify([
      ["card_id", CHAVE.card_id],
      ["asset_source_id", CHAVE.asset_source_id],
      ["language_id", CHAVE.language_id],
    ]),
    JSON.stringify(sb.chamadas.filtros));
  ok("R04 select inclui image_source_url e usa .single()",
    String(sb.chamadas.select).includes("image_source_url") && sb.chamadas.single === true,
    `${sb.chamadas.select} single=${sb.chamadas.single}`);
}

// ---------------------------------------------------------------------------
// Caso 2 — zero linhas / erro => false
// ---------------------------------------------------------------------------
{
  // Com `.single()`, zero linhas chega como ERRO (PGRST116), nao como sucesso.
  const sbZero = fakeSupabase({
    data: null,
    error: { code: "PGRST116", message: "JSON object requested, multiple (or no) rows returned" },
  });
  ok("R05 zero linhas => false",
    (await promoverImageSourceUrlDerivada(sbZero as never, CHAVE, URL_PROMOVIDA)) === false);

  // Defesa em profundidade: se algum dia vier data=null SEM erro, tambem false.
  const sbNulo = fakeSupabase({ data: null, error: null });
  ok("R06 data null sem erro => false",
    (await promoverImageSourceUrlDerivada(sbNulo as never, CHAVE, URL_PROMOVIDA)) === false);
}

// ---------------------------------------------------------------------------
// Caso 3 — URL divergente => false
// ---------------------------------------------------------------------------
{
  const sb = fakeSupabase({
    data: { id: "ref-1", image_source_url: "https://assets.tcgdex.net/en/swsh/swsh4.5sv/SV001" },
    error: null,
  });
  ok("R07 URL persistida divergente => false",
    (await promoverImageSourceUrlDerivada(sb as never, CHAVE, URL_PROMOVIDA)) === false);

  const sbNull = fakeSupabase({ data: { id: "ref-1", image_source_url: null }, error: null });
  ok("R08 URL persistida null => false",
    (await promoverImageSourceUrlDerivada(sbNull as never, CHAVE, URL_PROMOVIDA)) === false);
}

// ---------------------------------------------------------------------------
// Caso 4 — excecao do client => false, NUNCA propaga
// ---------------------------------------------------------------------------
{
  const sb = fakeSupabase(() => {
    throw new Error("NETWORK_DOWN");
  });
  let lancou = false;
  let r: boolean | null = null;
  try {
    r = await promoverImageSourceUrlDerivada(sb as never, CHAVE, URL_PROMOVIDA);
  } catch {
    lancou = true;
  }
  ok("R09 excecao contida (nao propaga)", lancou === false);
  ok("R10 excecao => false", r === false, String(r));
}

// ---------------------------------------------------------------------------
// Guards de entrada — nao chegam a tocar o cliente
// ---------------------------------------------------------------------------
{
  const sbUrlVazia = fakeSupabase({ data: { id: "x", image_source_url: "" }, error: null });
  const r1 = await promoverImageSourceUrlDerivada(sbUrlVazia as never, CHAVE, "");
  ok("R11 imageSourceUrl vazia => false sem tocar o cliente",
    r1 === false && sbUrlVazia.chamadas.tabela === undefined);

  const sbChave = fakeSupabase({ data: { id: "x", image_source_url: URL_PROMOVIDA }, error: null });
  const r2 = await promoverImageSourceUrlDerivada(
    sbChave as never,
    { ...CHAVE, language_id: "" },
    URL_PROMOVIDA,
  );
  ok("R12 chave incompleta => false sem tocar o cliente",
    r2 === false && sbChave.chamadas.tabela === undefined);
}

// ---------------------------------------------------------------------------
console.log(`RESULTADO: ${total - falhas.length}/${total} OK`);
if (falhas.length > 0) {
  console.error(`\nFALHAS (${falhas.length}):`);
  for (const f of falhas) console.error(`  - ${f}`);
  Deno.exit(1);
}
