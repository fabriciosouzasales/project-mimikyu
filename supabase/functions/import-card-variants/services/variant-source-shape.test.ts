// Project Mimikyu — supabase/functions/import-card-variants/services/variant-source-shape.test.ts
// Bateria do parser ancorado + do guard de cobertura (SOURCE-VARIANT-SAFETY-01, 2026-09-18).
//
// 100% offline: nenhuma chamada de rede, nenhum acesso ao Supabase, nenhum
// GitHub. As fixtures marcadas "REAL" são transcrições literais de trechos de
// arquivos-fonte da TCGdex lidos durante a AUDIT-01.
//
// Execução canônica:
//   deno test --allow-read supabase/functions/import-card-variants/services/variant-source-shape.test.ts
//
// ORGANIZAÇÃO
//   A — SHAPES: os 5 vereditos do contrato, incluindo ARRAY_EMPTY ≠ ABSENT.
//   B — NÃO-CAPTURA: prova de que OBJECT nunca cai no caminho ARRAY e de que
//       o array de OUTRO campo nunca é capturado. Esta é a regressão do
//       fail-open fechado nesta rodada; cada caso aqui devolvia variante
//       FABRICADA na versão anterior do parser.
//   C — FIXTURES REAIS.
//   D — GUARD DE COBERTURA: prova estrutural (o guard existe em index.ts e
//       precede toda escrita) + prova comportamental do predicado sobre um
//       Card Set MIXED montado com o parser REAL.

import { parseVariantSource, extractVariantsFromSource } from "./github-source.ts";

const INDEX_URL = new URL("../index.ts", import.meta.url);

type Resultado = { caso: string; ok: boolean; detalhe?: string };
function assert(acc: Resultado[], caso: string, ok: boolean, detalhe?: string) {
  acc.push({ caso, ok, detalhe: ok ? undefined : detalhe ?? "assertion falhou" });
}
function assertShape(acc: Resultado[], caso: string, src: string, shape: string, combos: number) {
  const r = parseVariantSource(src);
  const ok = r.shape === shape && r.combos.length === combos;
  assert(acc, caso, ok, `esperado ${shape}/${combos}, obtido ${r.shape}/${r.combos.length}`);
}

// ---------------------------------------------------------------------------
// FIXTURES REAIS (transcrição literal dos arquivos-fonte lidos na AUDIT-01)
// ---------------------------------------------------------------------------

/** REAL — data/EX/Dragon/4.ts (ARRAY, com thirdParty aninhado). */
const REAL_ARRAY = `\tretreat: 2,

\tvariants: [
\t\t{
\t\t\ttype: "holo",
\t\t\tthirdParty: {
\t\t\t\tcardmarket: 1234
\t\t\t}
\t\t},
\t],
}
`;

/** REAL — data/Sword & Shield/Sword & Shield/2.ts (OBJECT legado). */
const REAL_OBJECT_SWSH1 = `\tretreat: 1,
\tregulationMark: "D",

\tvariants: {
\t\tnormal: true,
\t\treverse: true,
\t\tholo: false,
\t\tfirstEdition: false
\t},

\tdescription: {
\t\ten: "Its flowers give off a relaxing fragrance."
\t},

\tthirdParty: {
\t\tcardmarket: 436189,
\t\ttcgplayer: 208268
\t}
}
`;

/** REAL — data/Sword & Shield/Champion's Path/3.ts (OBJECT legado). */
const REAL_OBJECT_CP = `\tretreat: 3,
\tregulationMark: "D",

\tvariants: {
\t\tnormal: true,
\t\treverse: true,
\t\tholo: false,
\t\tfirstEdition: false
\t},

\tstage: "Stage1",

\tthirdParty: {
\t\tcardmarket: 499870
\t}
}
`;

/** REAL — data/Sun & Moon/Cosmic Eclipse/1.ts (ABSENT: sem a chave). */
const REAL_ABSENT_SM12 = `\tweaknesses: [
\t\t{
\t\t\ttype: "Fire",
\t\t\tvalue: "×2"
\t\t},
\t],

\tretreat: 3,

\tthirdParty: {
\t\tcardmarket: 398449
\t}
}
`;

/** REAL — data-asia/PMCG/PMCG2/027.ts (`variants : [` com espaço). */
const REAL_ARRAY_ESPACADO = `\tretreat: 1,

\tvariants : [
\t\t{
\t\t\ttype: "holo",
\t\t},
\t]
}
`;

export function runVariantSourceShapeTests(): Resultado[] {
  const r: Resultado[] = [];

  // ===== A — OS 5 SHAPES DO CONTRATO ======================================

  assertShape(r, "A ARRAY — extrai os 5 campos",
    `\tvariants: [\n\t\t{\n\t\t\ttype: "holo",\n\t\t\tfoil: "cosmos",\n\t\t\tsubtype: "full-art",\n\t\t\tstamp: ["1st-edition"],\n\t\t\tsize: "jumbo",\n\t\t},\n\t],\n}`,
    "ARRAY", 1);

  {
    const c = parseVariantSource(
      `\tvariants: [\n\t\t{ type: "holo", foil: "cosmos", subtype: "full-art", stamp: ["1st-edition"], size: "jumbo" }\n\t]\n}`,
    ).combos[0];
    assert(r, "A ARRAY — os 5 campos chegam com o valor bruto da fonte",
      c?.type === "holo" && c?.foil === "cosmos" && c?.subtype === "full-art" &&
      c?.size === "jumbo" && JSON.stringify(c?.stamp) === '["1st-edition"]',
      JSON.stringify(c));
  }

  assertShape(r, "A ARRAY — múltiplas entradas", `\tvariants: [\n\t\t{ type: "normal" },\n\t\t{ type: "reverse" }\n\t]\n}`, "ARRAY", 2);
  assertShape(r, "A ARRAY — aspas simples aceitas", `\tvariants: [\n\t\t{ type: 'reverse' }\n\t]\n}`, "ARRAY", 1);
  // --- ALL-OR-NOTHING (CORRECTION-01) -------------------------------------
  // Os três casos obrigatórios do mandato. Antes, o primeiro devolvia
  // `ARRAY` com 1 combo — sucesso PARCIAL silencioso dentro de um único
  // arquivo, invisível para qualquer guard a jusante.
  assertShape(r, "A(corr) ARRAY com 1 objeto válido + 1 sem `type` → UNSUPPORTED",
    `\tvariants: [\n\t\t{ type: "normal" },\n\t\t{ foil: "cosmos" }\n\t]\n}`, "UNSUPPORTED", 0);
  assertShape(r, "A(corr) ARRAY com TODAS as entradas sem `type` → UNSUPPORTED",
    `\tvariants: [\n\t\t{ foil: "cosmos" }\n\t]\n}`, "UNSUPPORTED", 0);
  assertShape(r, "A(corr) `type` presente mas vazio → UNSUPPORTED",
    `\tvariants: [\n\t\t{ type: "" }\n\t]\n}`, "UNSUPPORTED", 0);

  // B — `thirdParty` aninhado NÃO quebra o parsing e NÃO integra identidade.
  {
    const p = parseVariantSource(
      `\tvariants: [\n\t\t{\n\t\t\ttype: "holo",\n\t\t\tthirdParty: {\n\t\t\t\tcardmarket: 1234,\n\t\t\t\ttcgplayer: 5678\n\t\t\t}\n\t\t},\n\t\t{\n\t\t\ttype: "normal",\n\t\t\tthirdParty: { cardmarket: 99 }\n\t\t}\n\t]\n}`,
    );
    assert(r, "B(corr) ARRAY com `thirdParty` aninhado continua ARRAY válido",
      p.shape === "ARRAY" && p.combos.length === 2 &&
      p.combos[0].type === "holo" && p.combos[1].type === "normal",
      JSON.stringify(p));
    assert(r, "B(corr) `thirdParty` não vira campo de identidade",
      p.combos.every((c) => c.foil === null && c.subtype === null && c.size === null && c.stamp === null),
      JSON.stringify(p.combos));
  }

  // C — conteúdo não vazio que não resulta em nenhum objeto top-level.
  assertShape(r, "C(corr) array de escalares (sem objetos) → UNSUPPORTED",
    `\tvariants: [\n\t\t"normal",\n\t\t"reverse",\n\t]\n}`, "UNSUPPORTED", 0);
  assertShape(r, "C(corr) conteúdo ilegível sem objetos → UNSUPPORTED",
    `\tvariants: [ ??? ]\n}`, "UNSUPPORTED", 0);
  assertShape(r, "C(corr) array aninhado sem objetos → UNSUPPORTED",
    `\tvariants: [\n\t\t[ "normal" ]\n\t]\n}`, "UNSUPPORTED", 0);

  // INVARIANTE derivada: ARRAY ⇒ combos ≥ 1 (array vazio vira ARRAY_EMPTY,
  // objeto ilegível vira UNSUPPORTED). Não existe mais ARRAY com 0 combos.
  for (const src of [REAL_ARRAY, `\tvariants: [{ type: "a" }, { type: "b" }]\n}`]) {
    const p = parseVariantSource(src);
    assert(r, `A(corr) invariante ARRAY ⇒ combos>=1 (${p.shape}/${p.combos.length})`,
      p.shape !== "ARRAY" || p.combos.length >= 1);
  }

  assertShape(r, "A ARRAY_EMPTY — `variants: []`", `\tvariants: [],\n}`, "ARRAY_EMPTY", 0);
  assertShape(r, "A ARRAY_EMPTY — `[]` com whitespace interno", `\tvariants: [\n\n\t],\n}`, "ARRAY_EMPTY", 0);

  assertShape(r, "A OBJECT — `variants: { ... }`", `\tvariants: {\n\t\tnormal: true\n\t},\n}`, "OBJECT", 0);
  assertShape(r, "A ABSENT — chave inexistente", `\tretreat: 3,\n\tthirdParty: { cardmarket: 1 }\n}`, "ABSENT", 0);

  assertShape(r, "A UNSUPPORTED — valor escalar", `\tvariants: true,\n}`, "UNSUPPORTED", 0);
  assertShape(r, "A UNSUPPORTED — valor string", `\tvariants: "normal",\n}`, "UNSUPPORTED", 0);
  assertShape(r, "A UNSUPPORTED — array não terminado (fonte malformada)",
    `\tvariants: [\n\t\t{ type: "holo" }\n`, "UNSUPPORTED", 0);

  // ARRAY_EMPTY é um veredito DIFERENTE de ABSENT — a exigência explícita do
  // contrato. `[]` = a fonte afirma que não há variante; ausência = ela cala.
  assert(r, "A ARRAY_EMPTY é distinguido de ABSENT",
    parseVariantSource(`\tvariants: [],\n}`).shape === "ARRAY_EMPTY" &&
    parseVariantSource(`\tretreat: 1,\n}`).shape === "ABSENT");

  // Whitespace seguro ao redor dos dois-pontos.
  assertShape(r, "A whitespace — `variants : [`", `\tvariants : [\n\t\t{ type: "holo" }\n\t]\n}`, "ARRAY", 1);
  assertShape(r, "A whitespace — `variants\\n\\t: [`", `\tvariants\n\t: [\n\t\t{ type: "holo" }\n\t]\n}`, "ARRAY", 1);
  assertShape(r, "A whitespace — `variants :  {` ainda é OBJECT", `\tvariants :  {\n\t\tnormal: true\n\t}\n}`, "OBJECT", 0);

  // ===== B — NÃO-CAPTURA (regressão do fail-open) =========================
  //
  // Cada caso abaixo devolvia variante FABRICADA na versão anterior, que
  // fazia `indexOf("[", keyIndex)` e pegava o próximo colchete do arquivo.

  assertShape(r, "B OBJECT + `weaknesses:[{type}]` depois → OBJECT (antes: [{type:'Fire'}])",
    `\tvariants: {\n\t\tnormal: true\n\t},\n\tweaknesses: [\n\t\t{ type: "Fire", value: "×2" }\n\t],\n}`, "OBJECT", 0);
  assertShape(r, "B OBJECT + `abilities:[{type}]` depois → OBJECT (antes: [{type:'Ability'}])",
    `\tvariants: {\n\t\tnormal: true\n\t},\n\tabilities: [\n\t\t{ type: "Ability", name: { en: "X" } }\n\t],\n}`, "OBJECT", 0);
  assertShape(r, "B OBJECT + `resistances:[{type}]` depois → OBJECT",
    `\tvariants: {\n\t\tholo: true\n\t},\n\tresistances: [\n\t\t{ type: "Water", value: "-30" }\n\t],\n}`, "OBJECT", 0);
  assertShape(r, "B OBJECT + `types:[]` depois → OBJECT",
    `\tvariants: {\n\t\tnormal: true\n\t},\n\ttypes: [\n\t\t"Grass",\n\t],\n}`, "OBJECT", 0);
  assertShape(r, "B ABSENT + `weaknesses:[{type}]` → ABSENT (nada a ancorar)",
    `\tweaknesses: [\n\t\t{ type: "Fire", value: "×2" }\n\t],\n}`, "ABSENT", 0);

  // Sufixo/prefixo de identificador nunca casa.
  assertShape(r, "B `variants_detailed:` NÃO casa com a chave `variants`",
    `\tvariants_detailed: [\n\t\t{ type: "normal" }\n\t],\n}`, "ABSENT", 0);
  assertShape(r, "B `card_variants:` NÃO casa (sufixo de outro identificador)",
    `\tcard_variants: [\n\t\t{ type: "normal" }\n\t],\n}`, "ABSENT", 0);

  // A âncora é posicional: o array capturado é o que segue os dois-pontos,
  // e apenas ele — arrays posteriores no arquivo não contaminam.
  {
    const p = parseVariantSource(
      `\tvariants: [\n\t\t{ type: "normal" }\n\t],\n\tweaknesses: [\n\t\t{ type: "Fire" }\n\t],\n}`,
    );
    assert(r, "B ARRAY captura SÓ o próprio bloco, não o array seguinte",
      p.shape === "ARRAY" && p.combos.length === 1 && p.combos[0].type === "normal",
      JSON.stringify(p));
  }
  {
    const p = parseVariantSource(
      `\tweaknesses: [\n\t\t{ type: "Fire" }\n\t],\n\tvariants: [\n\t\t{ type: "reverse" }\n\t],\n}`,
    );
    assert(r, "B ARRAY precedido por outro array não é deslocado",
      p.shape === "ARRAY" && p.combos.length === 1 && p.combos[0].type === "reverse",
      JSON.stringify(p));
  }

  // ===== C — FIXTURES REAIS ===============================================

  assertShape(r, "C REAL data/EX/Dragon/4.ts → ARRAY", REAL_ARRAY, "ARRAY", 1);
  assertShape(r, "C REAL SWSH1/2.ts → OBJECT", REAL_OBJECT_SWSH1, "OBJECT", 0);
  assertShape(r, "C REAL Champion's Path/3.ts → OBJECT", REAL_OBJECT_CP, "OBJECT", 0);
  assertShape(r, "C REAL Cosmic Eclipse/1.ts → ABSENT", REAL_ABSENT_SM12, "ABSENT", 0);
  assertShape(r, "C REAL data-asia PMCG2/027.ts (`variants : [`) → ARRAY", REAL_ARRAY_ESPACADO, "ARRAY", 1);

  assert(r, "C extractVariantsFromSource continua devolvendo só os combos",
    JSON.stringify(extractVariantsFromSource(REAL_ARRAY)) === JSON.stringify(parseVariantSource(REAL_ARRAY).combos) &&
    extractVariantsFromSource(REAL_OBJECT_SWSH1).length === 0 &&
    extractVariantsFromSource(REAL_ABSENT_SM12).length === 0);

  // ===== D — GUARD DE COBERTURA ===========================================
  // D.1 — estrutural: o guard existe, tem o erro canônico, e roda ANTES de
  //       qualquer escrita ou leitura de mapeamento.

  const src = Deno.readTextFileSync(INDEX_URL);
  const iFetch    = src.indexOf('"VARIANT_SOURCE_FETCH_FAILED_FOR_CORRELATED_CARDS: "');
  const iCoverage = src.indexOf('"VARIANT_SOURCE_CARD_COVERAGE_INCOMPLETE: "');
  const iGuard    = src.indexOf('"VARIANT_SOURCE_UNSUPPORTED_FOR_CORRELATED_CARDS: "');
  const iExisting = src.indexOf("listExistingCardVariantsMap(supabase");
  const iInsert   = src.indexOf("insertVariantImportRows(supabase");
  const iStaged   = src.indexOf("finalizeVariantJobStaged(");
  const primeiroGuard = Math.min(iFetch, iCoverage, iGuard);

  assert(r, "D1 os TRÊS guards estão presentes com seus tokens canônicos",
    iFetch > 0 && iCoverage > 0 && iGuard > 0, `fetch@${iFetch} coverage@${iCoverage} shape@${iGuard}`);

  // ORDEM DOS GUARDS = classificação correta do erro. Uma Card com fetch
  // falho também está ausente da cobertura; se o guard de cobertura viesse
  // antes, uma falha de rede TRANSITÓRIA seria reportada como
  // CARD_COVERAGE_INCOMPLETE (PERMANENTE) e perderia o retry.
  assert(r, "D1 guard de FETCH precede o de COBERTURA (senão transitório vira permanente)",
    iFetch < iCoverage, `fetch@${iFetch} coverage@${iCoverage}`);
  assert(r, "D1 guard de COBERTURA precede o de SHAPE", iCoverage < iGuard,
    `coverage@${iCoverage} shape@${iGuard}`);

  // NENHUM staging antes de NENHUM dos três.
  assert(r, "D1 todos os guards PRECEDEM a leitura de variantes existentes",
    iExisting > 0 && iGuard < iExisting, `ultimoGuard@${iGuard} listExisting@${iExisting}`);
  assert(r, "D1 todos os guards PRECEDEM insertVariantImportRows",
    iInsert > 0 && iGuard < iInsert, `ultimoGuard@${iGuard} insert@${iInsert}`);
  assert(r, "D1 todos os guards PRECEDEM finalizeVariantJobStaged",
    iStaged > 0 && iGuard < iStaged, `ultimoGuard@${iGuard} staged@${iStaged}`);
  assert(r, "D1 o PRIMEIRO guard já precede qualquer escrita ou leitura de mapeamento",
    primeiroGuard > 0 && primeiroGuard < iExisting && primeiroGuard < iInsert && primeiroGuard < iStaged);

  assert(r, "D1 os três guards usam `throw new Error` (failVariantJob → FAILED persistido)",
    /throw new Error\(\s*\n?\s*"VARIANT_SOURCE_FETCH_FAILED_FOR_CORRELATED_CARDS: "/.test(src) &&
    /throw new Error\(\s*\n?\s*"VARIANT_SOURCE_CARD_COVERAGE_INCOMPLETE: "/.test(src) &&
    /throw new Error\(\s*\n?\s*"VARIANT_SOURCE_UNSUPPORTED_FOR_CORRELATED_CARDS: "/.test(src));

  // Cobertura canônica: a autoridade é `public.card`, via listCardIdsOfCardSet.
  assert(r, "D1 autoridade de completude é public.card (listCardIdsOfCardSet)",
    src.includes("listCardIdsOfCardSet(supabase, cardSetId)"));
  assert(r, "D1 a MESMA leitura é injetada no lineage (sem consulta duplicada)",
    src.includes("listCardLineageCorrelationMap(supabase, cardSetId, externalSetId, cardIdsOfSetPromise)"));
  // A asserção é sobre CÓDIGO: o comentário de governança cita
  // `total_set_size` de propósito (para dizer que NÃO é a autoridade) e não
  // pode fazer a prova falhar. Comentários removidos antes de procurar.
  const codigo = src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n").filter((l) => !l.trim().startsWith("//")).join("\n");
  assert(r, "D1 completude NÃO usa total_set_size (código, sem comentários)",
    !/total_set_size/.test(codigo));
  assert(r, "D1 completude NÃO usa contagem de arquivos do GitHub como denominador",
    !/cardFiles\.length\s*[!=]==?\s*(expected|cardIds)/.test(codigo));
  assert(r, "D1 a direção testada é expected MINUS representadas",
    src.includes("[...expectedCardIds].filter((id) => !representedCardIds.has(id))"));
  assert(r, "D1 fetchError de Card CORRELACIONADA é o critério (cardId != null && fetchError != null)",
    src.includes("fileResults.filter((r) => r.cardId !== null && r.fetchError !== null)"));
  assert(r, "D1 os três error_summary trazem contagem + amostra limitada",
    src.includes("cards_correlacionadas_com_falha=") && src.includes("causas=") &&
    src.includes("cards_canonicas=") && src.includes("ausentes=") &&
    src.includes("amostra_card_id(") && src.includes("SOURCE_SHAPE_SAMPLE_LIMIT = 10"));
  assert(r, "D1 critério é POR CARD (shape ARRAY E combos > 0), não por total de linhas",
    src.includes('result.sourceShape === "ARRAY" && result.combos.length > 0'));
  assert(r, "D1 error_summary reporta total de correlacionadas", src.includes("correlacionadas=${correlated.length}"));
  assert(r, "D1 error_summary reporta contagem por shape",
    ["ARRAY=", "ARRAY_SEM_VARIANTE=", "ARRAY_EMPTY=", "OBJECT=", "ABSENT=", "UNSUPPORTED="]
      .every((k) => src.includes(k)));
  assert(r, "D1 amostra é LIMITADA (nunca o Set inteiro)",
    src.includes("SOURCE_SHAPE_SAMPLE_LIMIT = 10") &&
    src.includes("unsupportedSample.length < SOURCE_SHAPE_SAMPLE_LIMIT"));
  assert(r, "D1 index.ts usa parseVariantSource (e não mais o extrator cego)",
    src.includes("parseVariantSource(source)") && !src.includes("extractVariantsFromSource(source)"));
  assert(r, "D1 OBJECT NÃO é convertido em lugar nenhum da Edge",
    !/firstEdition|wPromo/.test(src));

  // D.2 — comportamental: o predicado do guard, aplicado a Card Sets montados
  //       com o parser REAL. Reproduz a fórmula do index.ts (shape ARRAY e
  //       ao menos um combo) para provar o veredito em cada composição.

  const cobertura = (fontes: string[]) => {
    const correlated = fontes.map((s) => parseVariantSource(s));
    const ok = correlated.filter((p) => p.shape === "ARRAY" && p.combos.length > 0).length;
    return { total: correlated.length, ok, semCobertura: correlated.length - ok };
  };

  {
    // Set 100% ARRAY (perfil dos 113 TARGET) → passa.
    const c = cobertura([REAL_ARRAY, REAL_ARRAY, REAL_ARRAY]);
    assert(r, "D2 Set 100% ARRAY → semCobertura=0, job segue para STAGED",
      c.semCobertura === 0 && c.ok === 3, JSON.stringify(c));
  }
  {
    // MIXED — o caso que `resolvedRows.length === 0` NÃO detectaria: as Cards
    // ARRAY produzem linhas, então o job terminaria STAGED com staging
    // parcial e error_summary nulo. O guard por Card reprova.
    const c = cobertura([REAL_ARRAY, REAL_ARRAY, REAL_ABSENT_SM12]);
    assert(r, "D2 Set MIXED (2 ARRAY + 1 ABSENT) → semCobertura=1, job FALHA antes de STAGED",
      c.semCobertura === 1 && c.ok === 2, JSON.stringify(c));
    assert(r, "D2 MIXED produziria linhas (>0) — prova de que o guard antigo não pegaria",
      parseVariantSource(REAL_ARRAY).combos.length > 0);
  }
  {
    // ABSENT puro — o "sucesso vazio" de SM12.
    const c = cobertura([REAL_ABSENT_SM12, REAL_ABSENT_SM12]);
    assert(r, "D2 Set 100% ABSENT (SM12) → semCobertura=total, job FALHA",
      c.semCobertura === 2 && c.ok === 0, JSON.stringify(c));
  }
  {
    // OBJECT puro — SWSH1 / Champion's Path.
    const c = cobertura([REAL_OBJECT_SWSH1, REAL_OBJECT_CP]);
    assert(r, "D2 Set 100% OBJECT (SWSH1/SWSH3.5) → semCobertura=total, job FALHA",
      c.semCobertura === 2 && c.ok === 0, JSON.stringify(c));
  }
  {
    // ARRAY_EMPTY e ARRAY parcialmente ilegível (agora UNSUPPORTED) reprovam.
    const c = cobertura([REAL_ARRAY, `\tvariants: [],\n}`, `\tvariants: [\n\t\t{ type: "a" },\n\t\t{ foil: "cosmos" }\n\t]\n}`]);
    assert(r, "D2 ARRAY_EMPTY e ARRAY parcialmente ilegível contam como sem cobertura",
      c.semCobertura === 2 && c.ok === 1, JSON.stringify(c));
  }

  // ===== E — COBERTURA CANÔNICA E FETCH FALHO (CORRECTION-01) =============
  // Reproduz os predicados de GUARD 1 e GUARD 2 do index.ts sobre um
  // `fileResults` simulado, provando o veredito em cada composição.

  type Sim = { externalCardId: string; cardId: string | null; fetchError: string | null };
  const guard1 = (files: Sim[]) => files.filter((f) => f.cardId !== null && f.fetchError !== null);
  const guard2 = (expected: string[], files: Sim[]) => {
    const correlated = files.filter((f) => f.cardId !== null && f.fetchError === null);
    const represented = new Set(correlated.map((f) => f.cardId as string));
    return expected.filter((id) => !represented.has(id));
  };

  {
    // Set íntegro: 3 Cards canônicas, 3 arquivos, tudo lido.
    const files: Sim[] = [
      { externalCardId: "sv02-1", cardId: "C1", fetchError: null },
      { externalCardId: "sv02-2", cardId: "C2", fetchError: null },
      { externalCardId: "sv02-3", cardId: "C3", fetchError: null },
    ];
    assert(r, "E Set íntegro → GUARD 1 e GUARD 2 passam",
      guard1(files).length === 0 && guard2(["C1", "C2", "C3"], files).length === 0);
  }
  {
    // O caso que o guard de shape NÃO pegava: arquivo da Card sumiu da fonte.
    const files: Sim[] = [
      { externalCardId: "sv02-1", cardId: "C1", fetchError: null },
      { externalCardId: "sv02-2", cardId: "C2", fetchError: null },
    ];
    const ausentes = guard2(["C1", "C2", "C3"], files);
    assert(r, "E Card canônica sem arquivo na fonte → COBERTURA INCOMPLETA (1 ausente)",
      ausentes.length === 1 && ausentes[0] === "C3", JSON.stringify(ausentes));
    assert(r, "E …e ela NÃO aparece em fetchError (nenhum fetch ocorreu)", guard1(files).length === 0);
  }
  {
    // Fetch falho de Card correlacionada: GUARD 1 pega, e é TRANSITÓRIO.
    const files: Sim[] = [
      { externalCardId: "sv02-1", cardId: "C1", fetchError: null },
      { externalCardId: "sv02-2", cardId: "C2", fetchError: "GITHUB_SOURCE_FETCH_FAILED: GITHUB_RAW_TIMEOUT" },
    ];
    assert(r, "E fetch falho de Card correlacionada → GUARD 1 pega (1 falha)",
      guard1(files).length === 1 && guard1(files)[0].externalCardId === "sv02-2");
    assert(r, "E …e ela também sumiria da cobertura — por isso GUARD 1 vem ANTES",
      guard2(["C1", "C2"], files).length === 1);
  }
  {
    // Arquivo EXTRA sem Card MMKYU: nem blocker de completude, nem de fetch.
    const files: Sim[] = [
      { externalCardId: "sv02-1", cardId: "C1", fetchError: null },
      { externalCardId: "sv02-999", cardId: null, fetchError: null },
      { externalCardId: "sv02-998", cardId: null, fetchError: "GITHUB_SOURCE_FETCH_FAILED: GITHUB_RAW_HTTP_404" },
    ];
    assert(r, "E arquivo EXTRA sem cardId NÃO dispara GUARD 1 (mesmo com fetch falho)",
      guard1(files).length === 0);
    assert(r, "E arquivo EXTRA sem cardId NÃO dispara GUARD 2 (direção testada é uma só)",
      guard2(["C1"], files).length === 0);
  }

  return r;
}

Deno.test("variant source shape — parser ancorado + guard de cobertura", () => {
  const resultados = runVariantSourceShapeTests();
  const falhas = resultados.filter((x) => !x.ok);

  for (const x of resultados) {
    console.log(`${x.ok ? "PASS" : "FAIL"}  ${x.caso}${x.detalhe ? `  — ${x.detalhe}` : ""}`);
  }
  console.log(`\n${resultados.length} casos · ${resultados.length - falhas.length} PASS · ${falhas.length} FAIL`);

  if (resultados.length === 0) throw new Error("VARIANT_SOURCE_SHAPE_TESTS_VAZIO");
  if (falhas.length > 0) {
    throw new Error(
      `VARIANT_SOURCE_SHAPE_TESTS_FAILED (${falhas.length}/${resultados.length}):\n` +
        falhas.map((x) => `  - ${x.caso}${x.detalhe ? ` — ${x.detalhe}` : ""}`).join("\n"),
    );
  }
});
