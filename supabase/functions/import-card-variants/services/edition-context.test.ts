// Project Mimikyu — supabase/functions/import-card-variants/services/edition-context.test.ts
//
// Teste de PARIDADE Edge × SQL do Eixo de Contexto de Edição (terceiro eixo
// de identidade).
//
// Rodar, a partir de supabase/functions/import-card-variants/:
//   deno test --allow-read services/edition-context.test.ts
//
// -----------------------------------------------------------------------------
// ZERO RÉPLICA DE LÓGICA DE PRODUÇÃO
// -----------------------------------------------------------------------------
// Tudo que decide alguma coisa sob teste é IMPORTADO do código que a Edge
// executa em produção:
//
//   ./edition-context.ts  routeEditionContext, buildEditionContextIndex,
//                         isEditionContextResolved
//   ./database.ts         buildVariantNormalizedData, buildVariantIdentityKey,
//                         buildPrintingProfileKeyPart
//
// A revisão anterior deste arquivo (em database/proposals/.../edge/) carregava
// uma RÉPLICA declarada do roteador e do bloco de normalized_data. Duas suítes
// verdes provavam duas opiniões independentes — não equivalência. Uma cópia
// que pode divergir em silêncio prova a cópia, não a Edge.
//
// O que permanece local é andaime de fixture — carga do JSON, ligação
// símbolo→uuid, resolução dos bindings, acumulador de assertions. Nada disso
// decide estado, resíduo, chave ou identidade.
//
// -----------------------------------------------------------------------------
// FONTE ÚNICA DOS EXPECTED
// -----------------------------------------------------------------------------
// Todos os valores esperados vêm de
// `database/proposals/2026-09-18-edition-context-axis/test-vectors/
//  edition-context-axis-vectors.json` — o MESMO arquivo que o runner SQL 2834
// consome, com o MESMO bloco `bindings`. NENHUM expected é declarado aqui, e o
// caso EXPECTED_NAO_LOCAL existe para provar isso mecanicamente.
//
// Precedente do projeto: `2026-09-14-card-variant-mapping-source-set-scope`
// (harness 2826 Seção 4 + edge/variant-scope-vectors.test.ts).
//
// -----------------------------------------------------------------------------
// GUARDS TEXTUAIS — só onde não cabe teste comportamental
// -----------------------------------------------------------------------------
// Duas decisões do eixo vivem inline no laço de linhas do `Deno.serve` do
// index.ts e não são funções: o `isValid` de três eixos e a ordem em que o
// resíduo chega ao Variant Type. Extraí-las só para testá-las seria inventar
// estrutura; então elas são conferidas por leitura do texto do index.ts, no
// molde do PARIDADE_INLINE de variant-scope-vectors.test.ts. Os guards também
// confirmam que os helpers importados aqui são os que a produção CHAMA — sem
// isso, um helper poderia virar código morto e esta suíte voltaria a provar
// uma cópia.
//
// Sem dependências externas, como as suítes vizinhas (cors, size-scope,
// lineage-correlation, variant-source-shape): assertions locais, um Deno.test
// que falha de verdade.

import {
  buildEditionContextIndex,
  isEditionContextResolved,
  routeEditionContext,
} from "./edition-context.ts";
import type { EditionContextRouting } from "./edition-context.ts";
import {
  buildPrintingProfileKeyPart,
  buildVariantIdentityKey,
  buildVariantNormalizedData,
} from "./database.ts";

// ---------------------------------------------------------------------------
// INFRA DE ASSERTIONS (idêntica em espírito à de size-scope.test.ts)
// ---------------------------------------------------------------------------

export type Resultado = { caso: string; ok: boolean; detalhe: string };

function check(r: Resultado[], caso: string, ok: boolean, detalhe = "") {
  r.push({ caso, ok, detalhe: ok ? "" : detalhe });
}

function checkEq(r: Resultado[], caso: string, obtido: unknown, esperado: unknown) {
  const a = JSON.stringify(obtido);
  const b = JSON.stringify(esperado);
  r.push({ caso, ok: a === b, detalhe: a === b ? "" : `obtido=${a} esperado=${b}` });
}

// ---------------------------------------------------------------------------
// FIXTURE COMPARTILHADA
// ---------------------------------------------------------------------------

const VECTORS_URL = new URL(
  "../../../../database/proposals/2026-09-18-edition-context-axis/test-vectors/edition-context-axis-vectors.json",
  import.meta.url,
);
const INDEX_URL = new URL("../index.ts", import.meta.url);

type MappingSpec = {
  scope: string | null;
  raw_field: "subtype" | "stamp";
  token: string;
  traits: string[];
  is_active: boolean;
};

type ExpectedSpec = {
  edition_context_state: string;
  edition_context_profile: string | null;
  edition_context_trait_ids: string[];
  residual_subtype: string | null;
  residual_stamp: string[];
  edge_emits_axis_keys: boolean;
};

type VectorSpec = {
  id: string;
  title: string;
  covers: string;
  job_scope: string | null;
  printing: { state: string; profile: string | null };
  residual_after_printing: { subtype: string | null; stamp: string[] };
  ec_traits: Array<{ id: string; is_active: boolean }>;
  ec_profiles: Array<{ id: string; traits: string[]; is_active: boolean }>;
  ec_mappings: MappingSpec[];
  expected?: ExpectedSpec;
  sub_cases?: Array<{
    label: string;
    residual_after_printing: { subtype: string | null; stamp: string[] };
    expected: ExpectedSpec;
  }>;
  identity_assertion?: {
    expect_keys_distinct: boolean;
    expect_legacy_3part_keys_equal: boolean;
  };
};

type Fixture = {
  version: string;
  vocabulary: string[];
  roster: string[];
  bindings: { tokens: Record<string, string>; scope: Record<string, string> };
  vectors: VectorSpec[];
};

// ---------------------------------------------------------------------------
// BINDINGS — símbolo abstrato -> objeto físico.
// As MESMAS regras que o runner SQL 2834 aplica. Sem este bloco, cada runner
// inventaria a sua própria ligação e a paridade seria afirmada, não verificada.
// ---------------------------------------------------------------------------

/** UUID determinístico a partir do símbolo. Estável entre execuções. */
function symbolToUuid(symbol: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < symbol.length; i++) {
    h ^= symbol.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  const hex = h.toString(16).padStart(8, "0");
  return `${hex}-0000-4000-8000-${hex}00000000`.slice(0, 36);
}

// ===========================================================================
// RUNNER — daqui para baixo, nenhum literal do vocabulário pode aparecer.
// ===========================================================================

type RunOutcome = {
  state: string;
  profileSymbol: string | null;
  traitSymbols: string[];
  residualSubtype: string | null;
  residualStamp: string[];
  emitsAxisKeys: boolean;
  editionContextProfileId: string | null;
};

function makeBinders(fixture: Fixture) {
  const TOKEN = (symbol: string): string => {
    const literal = fixture.bindings.tokens[symbol];
    if (literal === undefined) throw new Error(`token simbolico desconhecido: ${symbol}`);
    // O binding declara "TOK_PRINTING": "VEC2834PRINTTOK — token que ...".
    // Só a primeira palavra é o literal.
    return literal.split(" ")[0];
  };
  const SCOPE = (symbol: string | null): string | null => (symbol === null ? null : "VEC2834A");
  return { TOKEN, SCOPE };
}

function runVector(
  fixture: Fixture,
  v: VectorSpec,
  residual: { subtype: string | null; stamp: string[] },
): RunOutcome {
  const { TOKEN, SCOPE } = makeBinders(fixture);

  // Símbolo <-> uuid, nos dois sentidos, para que o expected simbólico da
  // fixture possa ser comparado sem o teste conhecer nenhum uuid.
  const traitUuidOf = new Map<string, string>();
  const traitSymbolOf = new Map<string, string>();
  for (const t of v.ec_traits) {
    const uuid = symbolToUuid(t.id);
    traitUuidOf.set(t.id, uuid);
    traitSymbolOf.set(uuid, t.id);
  }
  // Traits citados só em mappings/profiles também precisam de uuid.
  const ensureTrait = (sym: string): string => {
    if (!traitUuidOf.has(sym)) {
      const uuid = symbolToUuid(sym);
      traitUuidOf.set(sym, uuid);
      traitSymbolOf.set(uuid, sym);
    }
    return traitUuidOf.get(sym)!;
  };

  const profileSymbolOf = new Map<string, string>();
  const profiles = v.ec_profiles.map((p) => {
    const uuid = symbolToUuid(p.id);
    profileSymbolOf.set(uuid, p.id);
    return { id: uuid, traits_signature: p.traits.map(ensureTrait), is_active: p.is_active };
  });

  const mappings = v.ec_mappings.map((m) => ({
    external_set_id: SCOPE(m.scope),
    raw_field: m.raw_field,
    normalized_token: TOKEN(m.token),
    traits_signature: m.traits.map(ensureTrait),
    is_active: m.is_active,
  }));

  const traits = [...traitUuidOf.entries()].map(([sym, uuid]) => ({
    id: uuid,
    is_active: v.ec_traits.find((t) => t.id === sym)?.is_active ?? true,
  }));

  // PRODUÇÃO — índice real.
  const index = buildEditionContextIndex(mappings, profiles, traits, SCOPE(v.job_scope));

  const printingTerminal = v.printing.state === "RESOLVED_NO_PRINTING" ||
    v.printing.state === "RESOLVED_WITH_PROFILE";

  const subtype = residual.subtype === null ? null : TOKEN(residual.subtype);
  const stamp = residual.stamp.map(TOKEN).sort();

  // PRODUÇÃO — roteador real. O gate de "Impressão não terminal" está DENTRO
  // dele (2211:86-91), então o estado correspondente também é produzido pelo
  // código real e não por um literal deste arquivo.
  const ec: EditionContextRouting = routeEditionContext(
    index,
    printingTerminal,
    subtype,
    stamp.length > 0 ? stamp : null,
  );

  const printingProfileId = v.printing.profile === null ? null : symbolToUuid(v.printing.profile);

  // PRODUÇÃO — normalized_data real. `edge_emits_axis_keys` é a presença da
  // chave do eixo 3 no objeto que a Edge grava em catalog_variant_import_row.
  const nd = buildVariantNormalizedData(
    symbolToUuid("VT_FIXTURE"),
    printingTerminal,
    printingProfileId,
    isEditionContextResolved(ec.state),
    ec.editionContextProfileId,
  );

  return {
    state: ec.state,
    profileSymbol: ec.editionContextProfileId === null
      ? null
      : profileSymbolOf.get(ec.editionContextProfileId) ?? "<<UUID DESCONHECIDO>>",
    traitSymbols: ec.editionContextTraitIds
      .map((u) => traitSymbolOf.get(u) ?? "<<UUID DESCONHECIDO>>")
      .sort(),
    residualSubtype: ec.residualSubtype,
    residualStamp: (ec.residualStamp ?? []).slice().sort(),
    emitsAxisKeys: Object.hasOwn(nd, "edition_context_profile_id"),
    editionContextProfileId: ec.editionContextProfileId,
  };
}

function assertAgainstFixture(
  r: Resultado[],
  fixture: Fixture,
  label: string,
  v: VectorSpec,
  residual: { subtype: string | null; stamp: string[] },
  expected: ExpectedSpec,
) {
  const { TOKEN } = makeBinders(fixture);
  const got = runVector(fixture, v, residual);

  checkEq(r, `${label} estado`, got.state, expected.edition_context_state);
  checkEq(r, `${label} profile`, got.profileSymbol, expected.edition_context_profile);
  checkEq(
    r,
    `${label} trait_ids`,
    got.traitSymbols,
    [...expected.edition_context_trait_ids].sort(),
  );
  checkEq(
    r,
    `${label} residual_subtype`,
    got.residualSubtype,
    expected.residual_subtype === null ? null : TOKEN(expected.residual_subtype),
  );
  checkEq(
    r,
    `${label} residual_stamp`,
    got.residualStamp,
    expected.residual_stamp.map(TOKEN).sort(),
  );
  checkEq(r, `${label} edge_emits_axis_keys`, got.emitsAxisKeys, expected.edge_emits_axis_keys);
}

export async function runEditionContextTests(): Promise<Resultado[]> {
  const r: Resultado[] = [];
  const fixture: Fixture = JSON.parse(await Deno.readTextFile(VECTORS_URL));

  // -------------------------------------------------------------------------
  // OS 18 CASOS — um por expected declarado na fixture.
  // -------------------------------------------------------------------------
  let casos = 0;
  for (const v of fixture.vectors) {
    if (v.expected) {
      assertAgainstFixture(r, fixture, v.id, v, v.residual_after_printing, v.expected);
      casos++;
    }
    for (const sc of v.sub_cases ?? []) {
      assertAgainstFixture(r, fixture, sc.label, v, sc.residual_after_printing, sc.expected);
      casos++;
    }
  }

  // -------------------------------------------------------------------------
  // E15 — IDENTIDADE DE 4 COMPONENTES, comportamental.
  //
  // Os dois sub-casos têm o MESMO card, o MESMO variant_type e o MESMO
  // printing_profile (null). SÓ o eixo 3 difere. A chave de 4 partes tem de
  // separá-los; a antiga, de 3, os colapsava — e a segunda Variant, REAL e
  // distinta, seria classificada MATCHED contra a primeira e nunca criada.
  //
  // A chave de 4 partes vem do helper de PRODUÇÃO. A de 3 é montada aqui de
  // propósito: ela não existe mais no código, é a contraprova.
  // -------------------------------------------------------------------------
  const e15 = fixture.vectors.find((x) => x.id === "E15");
  check(r, "E15 presente na fixture", e15 !== undefined);
  if (e15) {
    check(
      r,
      "E15 tem 2 sub-casos",
      (e15.sub_cases?.length ?? 0) === 2,
      `sub_cases=${e15.sub_cases?.length ?? 0}`,
    );
    check(r, "E15 tem identity_assertion", e15.identity_assertion !== undefined);

    const CARD = symbolToUuid("CARD_FIXTURE");
    const VT = symbolToUuid("VT_FIXTURE");

    const keysOf = (label: string) => {
      const sc = e15.sub_cases!.find((s) => s.label === label)!;
      const got = runVector(fixture, e15, sc.residual_after_printing);
      checkEq(r, `E15 ${label} estado`, got.state, sc.expected.edition_context_state);
      return {
        quatro: buildVariantIdentityKey(CARD, VT, null, got.editionContextProfileId),
        tres: `${CARD}|${VT}|${buildPrintingProfileKeyPart(null)}`,
      };
    };

    const a = keysOf("E15a");
    const b = keysOf("E15b");

    if (e15.identity_assertion?.expect_keys_distinct) {
      check(
        r,
        "E15 chave de 4 partes SEPARA as duas Editions",
        a.quatro !== b.quatro,
        `a=${a.quatro} b=${b.quatro}`,
      );
    }
    if (e15.identity_assertion?.expect_legacy_3part_keys_equal) {
      check(
        r,
        "E15 contraprova: a chave antiga de 3 partes as colapsaria",
        a.tres === b.tres,
        `a=${a.tres} b=${b.tres}`,
      );
    }
  }

  // -------------------------------------------------------------------------
  // COBERTURA / ROSTER — a fixture não pode encolher em silêncio.
  // -------------------------------------------------------------------------
  checkEq(r, "COBERTURA 17 vetores", fixture.vectors.length, 17);
  checkEq(r, "COBERTURA 18 casos", casos, 18);
  checkEq(r, "COBERTURA 8 estados no vocabulario", fixture.vocabulary.length, 8);
  checkEq(
    r,
    "ROSTER nenhum vetor some nem aparece sem estar declarado",
    fixture.vectors.map((v) => v.id),
    fixture.roster,
  );

  const estadosUsados = new Set<string>();
  for (const v of fixture.vectors) {
    if (v.expected) estadosUsados.add(v.expected.edition_context_state);
    for (const sc of v.sub_cases ?? []) estadosUsados.add(sc.expected.edition_context_state);
  }
  checkEq(
    r,
    "COBERTURA os 8 estados aparecem em algum expected",
    fixture.vocabulary.filter((s) => !estadosUsados.has(s)),
    [],
  );

  // -------------------------------------------------------------------------
  // EXPECTED_NAO_LOCAL — um expected local reabriria exatamente o defeito que
  // este arquivo existe para fechar: dois runners provando cada um a sua
  // própria opinião.
  // -------------------------------------------------------------------------
  {
    const src = await Deno.readTextFile(new URL(import.meta.url));
    const corpo = src.slice(src.indexOf("// RUNNER"));
    for (const estado of fixture.vocabulary) {
      check(
        r,
        `EXPECTED_NAO_LOCAL sem literal ${estado} apos o runner`,
        !corpo.includes(`"${estado}"`),
        "expected local proibido",
      );
    }
  }

  // -------------------------------------------------------------------------
  // INTEGRAÇÃO — guards textuais sobre o index.ts, só para o que é inline.
  // -------------------------------------------------------------------------
  {
    const src = await Deno.readTextFile(INDEX_URL);
    // Comentários SAEM antes de normalizar. Sem isso, a prosa que explica o
    // código entraria nas buscas e um guard passaria (ou reprovaria) por causa
    // de um comentário — exatamente o tipo de prova que não prova nada.
    const semComentarios = src
      .replace(/\/\*[\s\S]*?\*\//g, " ")
      .replace(/(^|[^:])\/\/[^\n]*/g, "$1");
    const n = semComentarios.replace(/\s+/g, " ");

    check(
      r,
      "INTEGRACAO isValid exige os TRES eixos",
      n.includes(
        "const isValid = printingResolved && editionContextResolved && variantTypeId !== null;",
      ),
      "a expressao de isValid do index.ts mudou; rebasear teste e codigo juntos",
    );

    check(
      r,
      "INTEGRACAO Variant Type recebe o residuo POS-eixo-3",
      n.includes(
        "buildVariantComboKey( normalizedType, normalizedFoil, editionContext.residualSubtype, editionContext.residualStamp, )",
      ),
      "buildVariantComboKey nao esta recebendo o residuo pos-Edition Context",
    );

    // Guard negativo, ancorado em buildVariantComboKey: a ordem dos eixos não
    // pode regredir para pós-um-eixo. `routeEditionContext` recebe
    // `printing.residual*` LEGITIMAMENTE — é ele que consome esse resíduo —,
    // então o guard precisa nomear a função, não o argumento.
    check(
      r,
      "INTEGRACAO guard negativo: nenhum buildVariantComboKey com printing.residual*",
      !n.includes("buildVariantComboKey( normalizedType, normalizedFoil, printing."),
      "o residuo pos-Impressao voltou a alimentar o Variant Type — contaminacao",
    );

    // Sem estes, os helpers importados aqui poderiam ser codigo morto e a
    // suite voltaria a provar uma copia.
    check(
      r,
      "INTEGRACAO index.ts chama buildVariantNormalizedData",
      n.includes("buildVariantNormalizedData("),
      "normalized_data voltou a ser bloco inline",
    );
    check(
      r,
      "INTEGRACAO index.ts chama buildVariantIdentityKey",
      n.includes("buildVariantIdentityKey("),
      "a identidade de 4 componentes voltou a ser template literal",
    );
    check(
      r,
      "INTEGRACAO index.ts chama routeEditionContext",
      n.includes("routeEditionContext("),
      "o eixo 3 nao esta integrado ao laco de linhas",
    );
    check(
      r,
      "INTEGRACAO os 2 contadores do eixo 3 sao incrementados",
      n.includes("editionContextUnresolvedRows++") &&
        n.includes("editionContextWithProfileRows++"),
      "contadores do eixo 3 ausentes",
    );
    check(
      r,
      "INTEGRACAO os 2 contadores do eixo 3 sao publicados",
      n.includes("rows_unresolved: editionContextUnresolvedRows,") &&
        n.includes("rows_with_profile: editionContextWithProfileRows,"),
      "contadores do eixo 3 incrementados porem nao publicados",
    );
  }

  return r;
}

// ---------------------------------------------------------------------------
// Deno.test real — falha de verdade quando qualquer assertion falha.
// ---------------------------------------------------------------------------

Deno.test("edition-context — paridade Edge x SQL do terceiro eixo (17 vetores / 18 casos)", async () => {
  const resultados = await runEditionContextTests();
  const falhas = resultados.filter((x) => !x.ok);

  for (const x of resultados) {
    console.log(`${x.ok ? "PASS" : "FAIL"}  ${x.caso}${x.detalhe ? `  — ${x.detalhe}` : ""}`);
  }
  console.log(
    `\n${resultados.length} casos · ${resultados.length - falhas.length} PASS · ${falhas.length} FAIL`,
  );

  if (resultados.length === 0) {
    throw new Error("EDITION_CONTEXT_TESTS_VAZIO: a suite nao produziu nenhum caso.");
  }
  if (falhas.length > 0) {
    throw new Error(
      `EDITION_CONTEXT_TESTS_FALHOU: ${falhas.length} de ${resultados.length} — ` +
        falhas.map((x) => x.caso).join(" | "),
    );
  }
});
