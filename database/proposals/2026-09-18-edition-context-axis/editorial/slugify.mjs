// ============================================================================
// slugify.mjs — slug determinístico para DECK_PLAYER_<SLUG>  (E2, item 4)
// Status: PROPOSTA. Ferramenta de apoio editorial; não toca banco nem Edge.
//
// Rodar:
//   node database/proposals/2026-09-18-edition-context-axis/editorial/slugify.mjs
//   node ... slugify.mjs --from-csv edition-context-vocabulary.csv
//
// ----------------------------------------------------------------------------
// O QUE ESTE ARQUIVO DECIDE, E O QUE ELE NÃO DECIDE
// ----------------------------------------------------------------------------
// DECIDE: a transformação `source_value -> SLUG`. É mecânica, determinística
// e auditável — exatamente o tipo de coisa que NÃO deve ser feita à mão 38
// vezes, porque a mão erra e não é reproduzível.
//
// NÃO DECIDE: quais dos tokens residuais SÃO jogadores, nem o display name.
// "Nome próprio" é juízo editorial; desambiguar homônimos, idem. Este script
// recebe a lista já classificada por uma pessoa.
//
// Regras do mandato, implementadas uma a uma:
//   · determinístico        -> função pura, sem estado, sem locale
//   · ASCII                 -> NFD + remoção de marcas combinantes
//   · UPPER_SNAKE_CASE      -> separadores viram `_`, tudo maiúsculo
//   · só pontuação/diacrítico é removido -> letras e dígitos preservados
//   · não traduzir nome próprio -> nenhuma tabela de tradução aqui
//   · sem trait genérico PERSON/PLAYER -> o prefixo é sempre DECK_PLAYER_
// ============================================================================

/**
 * Converte um `source_value` em SLUG ASCII UPPER_SNAKE_CASE.
 * Pura e determinística: mesma entrada, mesma saída, sempre.
 */
export function slugify(sourceValue) {
  if (typeof sourceValue !== "string" || sourceValue.trim() === "") {
    throw new Error(`SLUG_EMPTY_SOURCE: valor de origem vazio ou nao-string`);
  }

  const slug = sourceValue
    // 1. Decompõe e remove marcas combinantes: "Pokémon" -> "Pokemon",
    //    "Muñoz" -> "Munoz", "Łukasz" fica "Lukasz" só com o passo 2.
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    // 2. Letras latinas que NFD não decompõe (têm o traço no próprio glifo).
    //    Lista fechada e explícita — nada de tabela de transliteração geral,
    //    que abriria porta para "traduzir" nome próprio.
    .replace(/[Łł]/g, "L")
    .replace(/[Øø]/g, "O")
    .replace(/[Ðð]/g, "D")
    .replace(/[Þþ]/g, "TH")
    .replace(/[ßẞ]/g, "SS")
    .replace(/[Æ]/g, "AE").replace(/[æ]/g, "AE")
    .replace(/[Œ]/g, "OE").replace(/[œ]/g, "OE")
    // 3. Qualquer separador (espaço, hífen, ponto, apóstrofo) vira `_`.
    .replace(/[\s\-._'’`]+/g, "_")
    // 4. Sobrou pontuação? Sai. Letras e dígitos ASCII permanecem.
    .replace(/[^A-Za-z0-9_]/g, "")
    // 5. Normaliza `_` repetidos e das pontas.
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "")
    .toUpperCase();

  if (slug === "") {
    throw new Error(
      `SLUG_EMPTY_RESULT: "${sourceValue}" reduziu a vazio. ` +
        `Caractere fora do alfabeto latino — decisao editorial necessaria.`,
    );
  }
  if (!/^[A-Z][A-Z0-9_]*$/.test(slug)) {
    // `ck_cect_code_format` exige `^[A-Z][A-Z0-9_]*$` no code COMPLETO.
    // Como o code é `DECK_PLAYER_` + slug, um slug iniciado por dígito é
    // legal no code final — mas o sinalizamos, porque quase sempre indica
    // que o token não era um nome próprio.
    return { slug, warning: "SLUG_NAO_INICIA_COM_LETRA" };
  }
  return { slug, warning: null };
}

export const toCode = (slug) => `DECK_PLAYER_${slug}`;

/**
 * Detecta colisões: dois `source_value` distintos que produzem o mesmo SLUG.
 * Colisão NÃO é resolvida aqui — vira BLOCKER editorial pontual, porque
 * desambiguar homônimos é decisão de pessoa (ex.: sufixo de ano ou país).
 */
export function detectCollisions(sourceValues) {
  const bySlug = new Map();
  const errors = [];
  for (const sv of sourceValues) {
    try {
      const { slug, warning } = slugify(sv);
      if (!bySlug.has(slug)) bySlug.set(slug, []);
      bySlug.get(slug).push({ source: sv, warning });
    } catch (e) {
      errors.push({ source: sv, error: e.message });
    }
  }
  const collisions = [...bySlug.entries()]
    .filter(([, list]) => new Set(list.map((x) => x.source)).size > 1)
    .map(([slug, list]) => ({ slug, code: toCode(slug), sources: list.map((x) => x.source) }));
  return { bySlug, collisions, errors };
}

// ----------------------------------------------------------------------------
// AUTOTESTE — roda sempre que o arquivo é executado direto.
// Prova as regras do mandato com casos que as violariam.
// ----------------------------------------------------------------------------
const CASES = [
  // [entrada, slug esperado, o que o caso prova]
  ["jason-klaczynski", "JASON_KLACZYNSKI", "hifen -> underscore"],
  ["Jason Klaczynski", "JASON_KLACZYNSKI", "espaco -> underscore; caixa"],
  ["tord-reklev", "TORD_REKLEV", "forma canonica TCGdex"],
  ["José Muñoz", "JOSE_MUNOZ", "diacriticos removidos (NFD)"],
  ["Łukasz Kowalski", "LUKASZ_KOWALSKI", "latino sem decomposicao NFD"],
  ["O'Brien", "O_BRIEN", "apostrofo ASCII -> separador"],
  ["O’Brien", "O_BRIEN", "apostrofo tipografico -> mesmo slug"],
  ["Jr. Smith", "JR_SMITH", "ponto -> separador"],
  ["ANDRE--CHIASSON", "ANDRE_CHIASSON", "separadores repetidos colapsam"],
  ["-leading-and-trailing-", "LEADING_AND_TRAILING", "bordas aparadas"],
  ["Søren Nielsen", "SOREN_NIELSEN", "o-cortado"],
  ["worlds-2023", "WORLDS_2023", "digitos preservados"],
];

function runSelfTest() {
  let pass = 0, fail = 0;
  console.log("--- slugify: autoteste ---");
  for (const [input, expected, why] of CASES) {
    let got;
    try { got = slugify(input).slug; } catch (e) { got = `<<${e.message}>>`; }
    if (got === expected) { pass++; console.log(`PASS  ${JSON.stringify(input).padEnd(24)} -> ${got}`); }
    else { fail++; console.log(`FAIL  ${JSON.stringify(input).padEnd(24)} -> ${got}  (esperado ${expected}) [${why}]`); }
  }

  // Determinismo: duas passadas sobre a mesma entrada dão o mesmo resultado.
  const det = CASES.every(([i]) => slugify(i).slug === slugify(i).slug);
  if (det) { pass++; console.log("PASS  determinismo (2 passadas identicas)"); }
  else { fail++; console.log("FAIL  determinismo"); }

  // ASCII estrito na saída.
  const ascii = CASES.every(([i]) => /^[A-Z0-9_]+$/.test(slugify(i).slug));
  if (ascii) { pass++; console.log("PASS  saida ASCII [A-Z0-9_] estrita"); }
  else { fail++; console.log("FAIL  saida nao-ASCII"); }

  // Colisão é DETECTADA, não resolvida em silêncio.
  const { collisions } = detectCollisions(["O'Brien", "O’Brien", "O-Brien", "tord-reklev"]);
  if (collisions.length === 1 && collisions[0].slug === "O_BRIEN" && collisions[0].sources.length === 3) {
    pass++; console.log("PASS  colisao detectada: 3 origens -> DECK_PLAYER_O_BRIEN");
  } else {
    fail++; console.log(`FAIL  deteccao de colisao: ${JSON.stringify(collisions)}`);
  }

  // Entrada que reduz a vazio FALHA ALTO em vez de virar code invalido.
  let threw = false;
  try { slugify("---"); } catch { threw = true; }
  if (threw) { pass++; console.log("PASS  entrada vazia apos limpeza levanta SLUG_EMPTY_RESULT"); }
  else { fail++; console.log("FAIL  entrada vazia nao levantou"); }

  console.log(`\n=== ${pass} PASS / ${fail} FAIL ===`);
  return fail;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const idx = process.argv.indexOf("--from-csv");
  if (idx === -1) {
    process.exit(runSelfTest() ? 1 : 0);
  } else {
    // Modo operacional: lê a coluna source_value do CSV editorial.
    const fs = await import("node:fs");
    const path = process.argv[idx + 1];
    const lines = fs.readFileSync(path, "utf8").split(/\r?\n/).filter(Boolean);
    const header = lines[0].split(",").map((h) => h.trim());
    const col = header.indexOf("source_token");
    const fam = header.indexOf("family");
    if (col === -1 || fam === -1) {
      console.error("CSV sem coluna source_token/family.");
      process.exit(1);
    }
    const sources = lines.slice(1)
      .map((l) => l.split(","))
      .filter((c) => (c[fam] ?? "").trim() === "DECK_PLAYER")
      .map((c) => c[col].trim())
      .filter(Boolean);

    const { bySlug, collisions, errors } = detectCollisions(sources);
    console.log(`source_value,slug,code`);
    for (const [slug, list] of [...bySlug.entries()].sort()) {
      for (const it of list) console.log(`${it.source},${slug},${toCode(slug)}`);
    }
    if (errors.length) {
      console.error(`\n${errors.length} ERRO(S):`);
      for (const e of errors) console.error(`  ${e.source}: ${e.error}`);
    }
    if (collisions.length) {
      console.error(`\n${collisions.length} COLISAO(OES) — BLOCKER EDITORIAL:`);
      for (const c of collisions) console.error(`  ${c.code} <- ${c.sources.join(" | ")}`);
      process.exit(1);
    }
    console.error(`\nOK: ${sources.length} origens -> ${bySlug.size} slugs, zero colisao.`);
  }
}
