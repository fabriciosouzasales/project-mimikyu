/*
===============================================================================
HARNESS OFFLINE — SWSH-SUBSET-ASSET-ALIAS-RECOVERY-01
Arquivo....: supabase/functions/import-card-assets/provas-asset-path-alias.ts
Alvo.......: ./services/tcgdex.ts  (modulo puro — NAO importa index.ts, que
             executa Deno.serve() no topo)

Evidencia LIVE que motivou a correcao:
  Gate 0 — metadata EN dos 6 subsets = 200; IDs candidatos da issue publica
    (swsh9.5tg, swsh10.5tg, swsh11.5tg, swsh12.5tg) = 404. Portanto NAO ha
    correcao de external_set_id: o ID do catalogo esta CERTO.
  Piloto CDN — EN high.webp = 200 nos 6, sob o diretorio do Set-PAI.
  Piloto CDN — PT-BR 404/404 nos 6 => pt-BR FORA desta rodada.
  LIVE — os 6 subsets somam 312 Cards com 0 Assets EN.

GARANTIAS DE ISOLAMENTO
  Rede: zero. Banco: zero. Escrita: zero. Credenciais: zero.
  `resolverBaseImageUrlComAlias` e funcao pura.

EXECUCAO (a partir da raiz do repositorio):
  deno run --allow-read supabase/functions/import-card-assets/provas-asset-path-alias.ts

  `--allow-read` e necessario SO pelo Bloco 9, que le index.ts para provar
  estaticamente que a regra de promocao esta no call site. Zero rede, zero
  banco, zero escrita.

Criterio de PASS: "RESULTADO: 140/140 OK" e exit code 0.
  Bloco 0 mapa ............................... 4
  Bloco 1 os 6 aliases EN (6 x 3) ........... 18
  Bloco 2 PT-BR no-op (6 x 2) ............... 12
  Bloco 3 Set normal byte-equivalente ........ 3
  Bloco 4 localIds SV/GG/TG literais ......... 6
  Bloco 5 idempotencia ....................... 2
  Bloco 6 segmento divergente => no-op ....... 2
  Bloco 7 origem/idioma/serie + degenerados .. 11
  --- CORRECTION-02 -------------------------------
  Bloco 8 derivacao restrita ................. 69
          8.1 os 6 subsets derivam (6 x 3) ... 18
          8.2 Set normal sem image => NONE .... 5
          8.3 PT-BR nunca deriva (6 x 2) ..... 12
          8.4 localId invalido/traversal (14x2) 28
          8.5 image presente => SOURCE ........ 3
          8.6 URL de constantes ............... 3
  Bloco 9 politica de promocao ............... 13
          (P99 virou P99a-P99d — HARNESS-CORRECTION-01)
===============================================================================
*/

import {
  ALIAS_DIRETORIO_ASSET,
  derivarBaseImageUrlAllowlist,
  IDIOMAS_COM_ALIAS_DE_DIRETORIO,
  localIdValidoParaSubset,
  ORIGEM_RESOLUCAO,
  resolverBaseImageUrlComAlias,
  resolverBaseImageUrlDaCarta,
} from "./services/tcgdex.ts";

const ORIGEM = "https://assets.tcgdex.net";

/** Os 6 subsets, com um localId REAL de cada (formato literal da fonte). */
const CASOS = [
  { setId: "swsh4.5sv", dir: "swsh4.5", localId: "SV001" },
  { setId: "swsh12.5gg", dir: "swsh12.5", localId: "GG01" },
  { setId: "swsh9tg", dir: "swsh9", localId: "TG01" },
  { setId: "swsh10tg", dir: "swsh10", localId: "TG01" },
  { setId: "swsh11tg", dir: "swsh11", localId: "TG01" },
  { setId: "swsh12tg", dir: "swsh12", localId: "TG01" },
] as const;

const urlDe = (lang: string, serie: string, dir: string, localId: string) =>
  `${ORIGEM}/${lang}/${serie}/${dir}/${localId}`;

let total = 0;
const falhas: string[] = [];
function ok(nome: string, cond: boolean, detalhe = "") {
  total += 1;
  if (!cond) falhas.push(`${nome}${detalhe ? ` — ${detalhe}` : ""}`);
}

// ---------------------------------------------------------------------------
// Bloco 0 — o mapa em si
// ---------------------------------------------------------------------------
ok("P00 mapa tem exatamente 6 entradas",
  Object.keys(ALIAS_DIRETORIO_ASSET).length === 6,
  String(Object.keys(ALIAS_DIRETORIO_ASSET).length));
ok("P01 mapa congelado (nao mutavel em runtime)", Object.isFrozen(ALIAS_DIRETORIO_ASSET));
ok("P02 idiomas com alias = apenas 'en'",
  IDIOMAS_COM_ALIAS_DE_DIRETORIO.length === 1 && IDIOMAS_COM_ALIAS_DE_DIRETORIO[0] === "en",
  JSON.stringify(IDIOMAS_COM_ALIAS_DE_DIRETORIO));
ok("P03 mapa bate com a evidencia do piloto",
  CASOS.every((c) => ALIAS_DIRETORIO_ASSET[c.setId] === c.dir));

// ---------------------------------------------------------------------------
// Bloco 1 — os 6 aliases em EN (6 x 3 asserts)
// ---------------------------------------------------------------------------
for (const c of CASOS) {
  const entrada = urlDe("en", "swsh", c.setId, c.localId);
  const r = resolverBaseImageUrlComAlias(entrada, c.setId, "en");
  const esperado = urlDe("en", "swsh", c.dir, c.localId);

  ok(`P_${c.setId}_alias aplicado`, r.aliasAplicado === true, JSON.stringify(r));
  ok(`P_${c.setId}_url correta`, r.url === esperado, `${r.url} !== ${esperado}`);

  // Decomposicao segmento a segmento: prova que SO o diretorio mudou.
  const a = new URL(entrada).pathname.split("/");
  const b = new URL(r.url).pathname.split("/");
  ok(`P_${c.setId}_so o diretorio mudou`,
    new URL(r.url).origin === ORIGEM &&
      a[1] === b[1] &&                      // idioma
      a[2] === b[2] &&                      // serie
      b[3] === c.dir &&                     // diretorio TROCADO
      a[4] === b[4],                        // localId INTACTO
    JSON.stringify({ a, b }));
}

// ---------------------------------------------------------------------------
// Bloco 2 — PT-BR e no-op nos 6 (pt e pt-BR)
// ---------------------------------------------------------------------------
for (const c of CASOS) {
  for (const lang of ["pt-BR", "pt"]) {
    const entrada = urlDe("pt", "swsh", c.setId, c.localId);
    const r = resolverBaseImageUrlComAlias(entrada, c.setId, lang);
    ok(`P_${c.setId}_${lang}_no-op`,
      r.aliasAplicado === false && r.url === entrada, `${lang}: ${r.url}`);
  }
}

// ---------------------------------------------------------------------------
// Bloco 3 — Set normal (fora do mapa) e byte-equivalente
// ---------------------------------------------------------------------------
{
  for (const [nome, setId, url] of [
    ["swsh9 (pai)", "swsh9", urlDe("en", "swsh", "swsh9", "001")],
    ["xy1", "xy1", urlDe("en", "xy", "xy1", "1")],
    ["sm10", "sm10", urlDe("en", "sm", "sm10", "226")],
  ] as [string, string, string][]) {
    const r = resolverBaseImageUrlComAlias(url, setId, "en");
    ok(`P_normal_${nome} byte-equivalente`,
      r.aliasAplicado === false && r.url === url, r.url);
  }
}

// ---------------------------------------------------------------------------
// Bloco 4 — localIds preservados LITERALMENTE (sem normalizacao numerica)
// ---------------------------------------------------------------------------
{
  const literais = ["SV001", "SV122", "GG01", "GG70", "TG01", "TG30"];
  for (const localId of literais) {
    const setId = localId.startsWith("SV")
      ? "swsh4.5sv"
      : localId.startsWith("GG")
      ? "swsh12.5gg"
      : "swsh9tg";
    const r = resolverBaseImageUrlComAlias(
      urlDe("en", "swsh", setId, localId), setId, "en");
    const ultimo = new URL(r.url).pathname.split("/").pop();
    ok(`P_literal_${localId}`, ultimo === localId, `${ultimo} !== ${localId}`);
  }
}

// ---------------------------------------------------------------------------
// Bloco 5 — idempotencia
// ---------------------------------------------------------------------------
{
  const c = CASOS[0];
  const r1 = resolverBaseImageUrlComAlias(
    urlDe("en", "swsh", c.setId, c.localId), c.setId, "en");
  const r2 = resolverBaseImageUrlComAlias(r1.url, c.setId, "en");
  ok("P30 2a passada nao muda a URL", r2.url === r1.url, `${r2.url} !== ${r1.url}`);
  ok("P31 2a passada marca aliasAplicado = false", r2.aliasAplicado === false);
}

// ---------------------------------------------------------------------------
// Bloco 6 — segmento divergente => no-op (fonte ja corrigida)
// ---------------------------------------------------------------------------
{
  // A fonte ja publica o diretorio-pai: nada a fazer.
  const jaCorreta = urlDe("en", "swsh", "swsh9", "TG01");
  const r = resolverBaseImageUrlComAlias(jaCorreta, "swsh9tg", "en");
  ok("P32 diretorio ja correto => no-op",
    r.aliasAplicado === false && r.url === jaCorreta, r.url);

  // Diretorio terceiro, sem relacao com a chave: nao mexer.
  const outro = urlDe("en", "swsh", "swsh7", "TG01");
  const r2 = resolverBaseImageUrlComAlias(outro, "swsh9tg", "en");
  ok("P33 diretorio de terceiro => no-op", r2.aliasAplicado === false && r2.url === outro);
}

// ---------------------------------------------------------------------------
// Bloco 7 — origem / idioma / serie preservados; entradas degeneradas
// ---------------------------------------------------------------------------
{
  const c = CASOS[2]; // swsh9tg
  const r = resolverBaseImageUrlComAlias(
    urlDe("en", "swsh", c.setId, c.localId), c.setId, "en");
  ok("P34 origem preservada", new URL(r.url).origin === ORIGEM, new URL(r.url).origin);
  ok("P35 idioma preservado", new URL(r.url).pathname.split("/")[1] === "en");
  ok("P36 serie preservada", new URL(r.url).pathname.split("/")[2] === "swsh");
  ok("P37 sem path traversal", !r.url.includes("..") && !r.url.includes("//swsh"));

  for (
    const [nome, url, setId, lang] of [
      ["url vazia", "", "swsh9tg", "en"],
      ["url nao-URL", "nao-e-url/TG01", "swsh9tg", "en"],
      ["externalSetId null", urlDe("en", "swsh", "swsh9tg", "TG01"), null, "en"],
      ["externalSetId vazio", urlDe("en", "swsh", "swsh9tg", "TG01"), "", "en"],
      ["languageCode null", urlDe("en", "swsh", "swsh9tg", "TG01"), "swsh9tg", null],
      ["image null", null, "swsh9tg", "en"],
    ] as [string, string | null, string | null, string | null][]
  ) {
    const rr = resolverBaseImageUrlComAlias(url, setId, lang);
    ok(`P_degenerado_${nome} => no-op sem lancar`,
      rr.aliasAplicado === false && rr.url === (url ?? ""), JSON.stringify(rr));
  }

  // Chave case-insensitive na comparacao, mas destino literal do mapa.
  const rMaiusc = resolverBaseImageUrlComAlias(
    urlDe("en", "swsh", "SWSH9TG", "TG01"), "SWSH9TG", "en");
  ok("P44 external_set_id em maiuscula ainda casa",
    rMaiusc.aliasAplicado === true && rMaiusc.url === urlDe("en", "swsh", "swsh9", "TG01"),
    rMaiusc.url);
}

// ---------------------------------------------------------------------------
// Bloco 8 — CORRECTION-02: derivacao quando a fonte NAO publica `image`
// ---------------------------------------------------------------------------
// Fato medido: /v2/en/sets/swsh4.5sv devolve a carta SV001 SEM `image`; o
// endpoint da carta individual tambem. A CDN, porem, responde 200 em
// /en/swsh/swsh4.5/SV001/high.webp. O alias sozinho nao resolve — nao ha URL
// para aliasar. Dai a derivacao, restrita a allowlist + en + formato.
{
  const LOCAL_ID_POR_SET: Record<string, string> = {
    "swsh4.5sv": "SV001", "swsh12.5gg": "GG01", "swsh9tg": "TG01",
    "swsh10tg": "TG01", "swsh11tg": "TG01", "swsh12tg": "TG01",
  };

  // 8.1 — os 6 subsets derivam corretamente em EN (6 x 3)
  for (const c of CASOS) {
    const localId = LOCAL_ID_POR_SET[c.setId];
    const r = resolverBaseImageUrlDaCarta(undefined, c.setId, localId, "en");
    const esperado = urlDe("en", "swsh", c.dir, localId);

    ok(`P_deriv_${c.setId}_origem`, r.origem === ORIGEM_RESOLUCAO.DERIVED_ALLOWLIST, r.origem);
    ok(`P_deriv_${c.setId}_url`, r.url === esperado, `${r.url} !== ${esperado}`);
    ok(`P_deriv_${c.setId}_localId literal`,
      new URL(r.url).pathname.split("/").pop() === localId);
  }

  // 8.2 — Set normal com `image` ausente => NONE (nunca deriva fora da allowlist)
  for (const setId of ["swsh9", "xy1", "sm10", "swsh4.5", "swsh12.5"]) {
    const r = resolverBaseImageUrlDaCarta(null, setId, "001", "en");
    ok(`P_none_${setId}`, r.origem === ORIGEM_RESOLUCAO.NONE && r.url === "", `${r.origem}/${r.url}`);
  }

  // 8.3 — PT-BR nunca deriva (piloto: 404/404 nos 6)
  for (const c of CASOS) {
    for (const lang of ["pt-BR", "pt"]) {
      const r = resolverBaseImageUrlDaCarta(undefined, c.setId, LOCAL_ID_POR_SET[c.setId], lang);
      ok(`P_deriv_${c.setId}_${lang}_NONE`, r.origem === ORIGEM_RESOLUCAO.NONE && r.url === "");
    }
  }

  // 8.4 — localId invalido / traversal / encoding => NONE
  for (
    const [nome, setId, localId] of [
      ["traversal simples", "swsh4.5sv", "../../etc/passwd"],
      ["traversal encoded", "swsh4.5sv", "..%2F..%2Fx"],
      ["barra", "swsh4.5sv", "SV001/extra"],
      ["ponto", "swsh4.5sv", "SV001.webp"],
      ["query", "swsh4.5sv", "SV001?x=1"],
      ["hash", "swsh4.5sv", "SV001#a"],
      ["host embutido", "swsh4.5sv", "//evil.com/x"],
      ["formato errado (TG em SV)", "swsh4.5sv", "TG01"],
      ["formato errado (SV em TG)", "swsh9tg", "SV001"],
      ["digitos a menos", "swsh4.5sv", "SV01"],
      ["digitos a mais", "swsh9tg", "TG001"],
      ["minuscula", "swsh4.5sv", "sv001"],
      ["vazio", "swsh4.5sv", ""],
      ["espaco", "swsh4.5sv", " SV001 "],
    ] as [string, string, string][]
  ) {
    const r = resolverBaseImageUrlDaCarta(undefined, setId, localId, "en");
    ok(`P_traversal_${nome} => NONE`,
      r.origem === ORIGEM_RESOLUCAO.NONE && r.url === "", `${r.origem}/${r.url}`);
    ok(`P_traversal_${nome} => localIdValidoParaSubset false`,
      localIdValidoParaSubset(setId, localId) === false);
  }

  // 8.5 — `image` presente continua SOURCE (a derivacao nao sequestra o fluxo)
  {
    const c = CASOS[0];
    const daFonte = urlDe("en", "swsh", c.setId, "SV001");
    const r = resolverBaseImageUrlDaCarta(daFonte, c.setId, "SV001", "en");
    ok("P80 image presente => SOURCE", r.origem === ORIGEM_RESOLUCAO.SOURCE, r.origem);
    ok("P81 SOURCE ainda aplica o alias de diretorio",
      r.url === urlDe("en", "swsh", c.dir, "SV001") && r.aliasAplicado === true, r.url);

    const normal = urlDe("en", "swsh", "swsh9", "001");
    const r2 = resolverBaseImageUrlDaCarta(normal, "swsh9", "001", "en");
    ok("P82 Set normal com image => SOURCE byte-equivalente",
      r2.origem === ORIGEM_RESOLUCAO.SOURCE && r2.url === normal && r2.aliasAplicado === false);
  }

  // 8.6 — a URL derivada e construida de CONSTANTES: host do cliente e ignorado
  {
    const r = derivarBaseImageUrlAllowlist("swsh9tg", "TG01", "en");
    ok("P83 origem constante assets.tcgdex.net",
      r !== null && new URL(r).origin === "https://assets.tcgdex.net", String(r));
    ok("P84 sem credenciais/query/hash",
      r !== null && !r.includes("@") && !r.includes("?") && !r.includes("#"), String(r));
    ok("P85 path com exatamente 4 segmentos",
      r !== null && new URL(r).pathname.split("/").length === 5, String(r));
  }
}

// ---------------------------------------------------------------------------
// Bloco 9 — CORRECTION-02: politica de PROMOCAO (hipotese != identidade)
// ---------------------------------------------------------------------------
// Aqui provamos a REGRA CRITICA, sem banco: a decisao de persistir
// `image_source_url` e funcao PURA da origem e do sucesso do download.
// Espelha exatamente o que `index.ts` faz nos dois pontos.
{
  /** Espelho da regra em index.ts: o que vai para image_source_url na SINCRONIZACAO. */
  const persistirNaSincronizacao = (origem: string, url: string) =>
    origem === ORIGEM_RESOLUCAO.SOURCE ? (url || null) : null;

  /** Espelho da regra em index.ts: promocao SO apos download bem-sucedido. */
  const promoverAposDownload = (origem: string, sucesso: boolean, url: string) =>
    origem === ORIGEM_RESOLUCAO.DERIVED_ALLOWLIST && sucesso ? url : null;

  const c = CASOS[0];
  const derivada = resolverBaseImageUrlDaCarta(undefined, c.setId, "SV001", "en");
  const daFonte = resolverBaseImageUrlDaCarta(
    urlDe("en", "swsh", c.setId, "SV001"), c.setId, "SV001", "en");
  const nenhuma = resolverBaseImageUrlDaCarta(undefined, "swsh9", "001", "en");

  ok("P90 DERIVED nao e persistida na sincronizacao",
    persistirNaSincronizacao(derivada.origem, derivada.url) === null);
  ok("P91 SOURCE e persistida na sincronizacao",
    persistirNaSincronizacao(daFonte.origem, daFonte.url) === urlDe("en", "swsh", c.dir, "SV001"));
  ok("P92 NONE persiste null", persistirNaSincronizacao(nenhuma.origem, nenhuma.url) === null);

  ok("P93 DERIVED + download OK => promove a base derivada",
    promoverAposDownload(derivada.origem, true, derivada.url)
      === urlDe("en", "swsh", c.dir, "SV001"));
  ok("P94 DERIVED + download FALHOU => permanece null",
    promoverAposDownload(derivada.origem, false, derivada.url) === null);
  ok("P95 SOURCE nunca entra no caminho de promocao",
    promoverAposDownload(daFonte.origem, true, daFonte.url) === null);
  ok("P96 NONE nunca promove", promoverAposDownload(nenhuma.origem, true, nenhuma.url) === null);

  // Prova estatica: as duas regras existem no index.ts, escritas como aqui.
  {
    const fonte = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    ok("P97 sincronizacao condiciona a SOURCE",
      fonte.includes("origemDaUrl(tcgCard.localId) === ORIGEM_RESOLUCAO.SOURCE"));
    ok("P98 promocao condiciona a DERIVED_ALLOWLIST",
      fonte.includes("origemDaUrl(tcgCard.localId) === ORIGEM_RESOLUCAO.DERIVED_ALLOWLIST"));
    // HARNESS-CORRECTION-01 — a versao anterior usava indexOf() sobre o arquivo
    // INTEIRO e capturava o IMPORT de promoverImageSourceUrlDerivada (linha
    // ~405), nao a chamada (~1162), comparando-o contra upsertCardAsset
    // (~1128). Media import x chamada, e reprovava com a ordem correta.
    //
    // Agora a busca e restrita ao CORPO de processImageForCard() e as CHAMADAS
    // efetivas (`await <nome>(`), nao a qualquer mencao do identificador.
    const inicioCorpo = fonte.indexOf("async function processImageForCard(");
    ok("P99a corpo de processImageForCard localizado", inicioCorpo >= 0);

    const corpo = inicioCorpo >= 0 ? fonte.slice(inicioCorpo) : "";
    const iUpsert = corpo.indexOf("await upsertCardAsset(");
    const iPromocao = corpo.indexOf("await promoverImageSourceUrlDerivada(");

    ok("P99b ambas as chamadas existem no corpo", iUpsert >= 0 && iPromocao >= 0,
      `upsert=${iUpsert} promocao=${iPromocao}`);
    ok("P99c promocao ocorre APOS upsertCardAsset", iPromocao > iUpsert,
      `upsert=${iUpsert} promocao=${iPromocao}`);
    ok("P99d import nao e confundido com chamada",
      fonte.indexOf("promoverImageSourceUrlDerivada") < inicioCorpo,
      "o import deve vir ANTES do corpo — e por isso indexOf global falhava");
  }
}

// ---------------------------------------------------------------------------
console.log(`RESULTADO: ${total - falhas.length}/${total} OK`);
if (falhas.length > 0) {
  console.error(`\nFALHAS (${falhas.length}):`);
  for (const f of falhas) console.error(`  - ${f}`);
  Deno.exit(1);
}
