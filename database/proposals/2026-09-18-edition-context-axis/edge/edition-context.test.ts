/*
===============================================================================
Project Mimikyu — Teste offline de PARIDADE Edge × SQL
Eixo de Contexto de Edição (terceiro eixo de identidade)

Mandato...: EDITION-CONTEXT-AXIS-EDGE-D3-FINAL-CORRECTION-01
Versão....: 3.0
Status....: PROPOSTA — NÃO EXECUTADO. Destino futuro:
            supabase/functions/import-card-variants/edition-context.test.ts

Rodar:
    deno test --allow-read \
      database/proposals/2026-09-18-edition-context-axis/edge/edition-context.test.ts

-------------------------------------------------------------------------------
FONTE ÚNICA DOS EXPECTED
-------------------------------------------------------------------------------
Todos os valores esperados vêm de
`../test-vectors/edition-context-axis-vectors.json` — o MESMO arquivo que o
runner SQL `2834` consome, com o MESMO bloco `bindings`. **Nenhum expected é
declarado neste arquivo.**

Isto é o que a rev 2.0 não tinha. Lá, os 8 testes carregavam os seus próprios
expected, e o harness SQL carregava os dele. Duas suítes verdes provavam duas
opiniões independentes — não equivalência. O mandato nomeia exatamente esse
defeito.

Precedente do projeto: `2026-09-14-card-variant-mapping-source-set-scope`
(harness `2826` Seção 4 + `edge/variant-scope-vectors.test.ts`).

-------------------------------------------------------------------------------
O QUE ESTE ARQUIVO REPRODUZ, E POR QUÊ
-------------------------------------------------------------------------------
`routeEditionContext` e `buildEditionContextIndex` ainda NÃO existem no
arquivo de produção — o patch não foi aplicado. Enquanto isso for verdade,
este teste carrega a réplica declarada abaixo, e o caso `PARIDADE_FONTE`
FALHA de propósito, dizendo que a réplica ainda não pôde ser conferida contra
o original.

Depois do deploy, a réplica sai e o teste importa as funções reais de
`./index.ts`, como faz `variant-scope-vectors.test.ts` com
`listVariantTypeExternalMappings`. Um teste que copiasse a lógica para sempre
provaria a cópia, não a Edge.

-------------------------------------------------------------------------------
CASOS QUE FALHAM CONTRA O CÓDIGO DE HOJE — por desenho
-------------------------------------------------------------------------------
  · TODOS os 18 vetores, porque o eixo 3 não existe na Edge atual;
  · E6, E7, E13, E14 falhariam também contra a **rev 2.0 do próprio patch**,
    que era fail-OPEN para mapping conhecido sem routing ativo;
  · E12 falharia contra a rev 2.0 (não havia INVALID_EC_MAPPING);
  · E16 falharia contra a rev 2.0 (não havia NOT_EVALUATED).
===============================================================================
*/

import { assert, assertEquals } from "jsr:@std/assert";

// ---------------------------------------------------------------------------
// FIXTURE COMPARTILHADA
// ---------------------------------------------------------------------------

const VECTORS_PATH = new URL(
  "../test-vectors/edition-context-axis-vectors.json",
  import.meta.url,
);

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
  bindings: {
    tokens: Record<string, string>;
    scope: Record<string, string>;
  };
  vectors: VectorSpec[];
};

const fixture: Fixture = JSON.parse(await Deno.readTextFile(VECTORS_PATH));

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

const TOKEN = (symbol: string): string => {
  const literal = fixture.bindings.tokens[symbol];
  assert(literal !== undefined, `token simbolico desconhecido: ${symbol}`);
  // O binding declara "TOK_PRINTING": "VEC2834PRINTTOK — token que ...".
  // Só a primeira palavra é o literal.
  return literal.split(" ")[0];
};

const SCOPE = (symbol: string | null): string | null =>
  symbol === null ? null : "VEC2834A";

// ---------------------------------------------------------------------------
// RÉPLICA DECLARADA do patch (DIFF 2). Remover quando o patch estiver aplicado
// e substituir por `import { ... } from "./index.ts"`.
// ---------------------------------------------------------------------------

type EditionContextState =
  | "NOT_EVALUATED"
  | "RESOLVED_NO_EDITION_CONTEXT"
  | "RESOLVED_WITH_EC_PROFILE"
  | "NEEDS_REVIEW_INVALID_EC_MAPPING"
  | "NEEDS_REVIEW_INACTIVE_EC_MAPPING"
  | "NEEDS_REVIEW_INACTIVE_EC_TRAIT"
  | "NEEDS_REVIEW_NO_EC_PROFILE"
  | "NEEDS_REVIEW_INACTIVE_EC_PROFILE";

const EDITION_CONTEXT_TERMINAL_STATES: ReadonlySet<EditionContextState> = new Set([
  "RESOLVED_NO_EDITION_CONTEXT",
  "RESOLVED_WITH_EC_PROFILE",
]);

function isEditionContextResolved(state: EditionContextState): boolean {
  return EDITION_CONTEXT_TERMINAL_STATES.has(state);
}

/** Cópia literal de services/database.ts:487-490 (código de produção). */
function buildTraitsSignatureKey(traitIds: readonly string[] | null | undefined): string {
  if (!traitIds || traitIds.length === 0) return "";
  return [...new Set(traitIds.map((id) => String(id).toLowerCase()))].sort().join(",");
}

const NO_PRINTING_PROFILE_KEY = "~";
const NO_EDITION_CONTEXT_KEY = "~";
const buildPrintingProfileKeyPart = (id: string | null | undefined) =>
  id ?? NO_PRINTING_PROFILE_KEY;
const buildEditionContextKeyPart = (id: string | null | undefined) =>
  id ?? NO_EDITION_CONTEXT_KEY;

type EditionContextIndex = {
  activeTraitsByScopedToken: Map<string, string[]>;
  activeTraitsByGlobalToken: Map<string, string[]>;
  knownScopedTokens: Set<string>;
  knownGlobalTokens: Set<string>;
  profileBySignature: Map<string, string>;
  inactiveProfileIds: Set<string>;
  inactiveTraitIds: Set<string>;
};

type EditionContextRouting = {
  state: EditionContextState;
  editionContextProfileId: string | null;
  editionContextTraitIds: string[];
  residualSubtype: string | null;
  residualStamp: string[] | null;
};

function ecTokenKey(rawField: string, normalizedToken: string): string {
  return `${rawField}|${normalizedToken}`;
}

function buildEditionContextIndex(
  mappings: Array<{
    external_set_id: string | null;
    raw_field: string;
    normalized_token: string;
    traits_signature: string[] | null;
    is_active: boolean;
  }>,
  profiles: Array<{ id: string; traits_signature: string[] | null; is_active: boolean }>,
  traits: Array<{ id: string; is_active: boolean }>,
  externalSetId: string | null,
): EditionContextIndex {
  const activeTraitsByScopedToken = new Map<string, string[]>();
  const activeTraitsByGlobalToken = new Map<string, string[]>();
  const knownScopedTokens = new Set<string>();
  const knownGlobalTokens = new Set<string>();

  for (const m of mappings) {
    const isGlobal = m.external_set_id === null;
    const isThisScope = externalSetId !== null && m.external_set_id === externalSetId;
    if (!isGlobal && !isThisScope) continue;

    const key = ecTokenKey(m.raw_field, m.normalized_token);
    if (isGlobal) knownGlobalTokens.add(key);
    else knownScopedTokens.add(key);

    if (!m.is_active) continue;

    const sig = (m.traits_signature ?? []).map((id) => String(id));
    if (isGlobal) activeTraitsByGlobalToken.set(key, sig);
    else activeTraitsByScopedToken.set(key, sig);
  }

  const profileBySignature = new Map<string, string>();
  const inactiveProfileIds = new Set<string>();
  for (const p of profiles) {
    profileBySignature.set(buildTraitsSignatureKey(p.traits_signature), p.id);
    if (!p.is_active) inactiveProfileIds.add(String(p.id));
  }

  const inactiveTraitIds = new Set<string>();
  for (const t of traits) {
    if (!t.is_active) inactiveTraitIds.add(String(t.id).toLowerCase());
  }

  return {
    activeTraitsByScopedToken,
    activeTraitsByGlobalToken,
    knownScopedTokens,
    knownGlobalTokens,
    profileBySignature,
    inactiveProfileIds,
    inactiveTraitIds,
  };
}

function routeEditionContext(
  index: EditionContextIndex,
  residualSubtype: string | null,
  residualStampSorted: string[] | null,
): EditionContextRouting {
  const untouched = (state: EditionContextState): EditionContextRouting => ({
    state,
    editionContextProfileId: null,
    editionContextTraitIds: [],
    residualSubtype,
    residualStamp: residualStampSorted,
  });

  const traitIds: string[] = [];
  const lookupActive = (key: string): string[] | undefined =>
    index.activeTraitsByScopedToken.get(key) ?? index.activeTraitsByGlobalToken.get(key);
  const isKnown = (key: string): boolean =>
    index.knownScopedTokens.has(key) || index.knownGlobalTokens.has(key);

  let outSubtype = residualSubtype;
  if (residualSubtype !== null && residualSubtype.trim() !== "") {
    const key = ecTokenKey("subtype", residualSubtype);
    const sig = lookupActive(key);
    if (sig !== undefined) {
      if (sig.length === 0) return untouched("NEEDS_REVIEW_INVALID_EC_MAPPING");
      traitIds.push(...sig);
      outSubtype = null;
    } else if (isKnown(key)) {
      return untouched("NEEDS_REVIEW_INACTIVE_EC_MAPPING");
    }
  }

  const outStampTokens: string[] = [];
  for (const token of residualStampSorted ?? []) {
    const key = ecTokenKey("stamp", token);
    const sig = lookupActive(key);
    if (sig !== undefined) {
      if (sig.length === 0) return untouched("NEEDS_REVIEW_INVALID_EC_MAPPING");
      traitIds.push(...sig);
    } else if (isKnown(key)) {
      return untouched("NEEDS_REVIEW_INACTIVE_EC_MAPPING");
    } else {
      outStampTokens.push(token);
    }
  }
  const outStamp = outStampTokens.length > 0 ? [...outStampTokens].sort() : null;

  if (traitIds.length === 0) {
    return {
      state: "RESOLVED_NO_EDITION_CONTEXT",
      editionContextProfileId: null,
      editionContextTraitIds: [],
      residualSubtype: outSubtype,
      residualStamp: outStamp,
    };
  }

  const signatureKey = buildTraitsSignatureKey(traitIds);
  const signature = signatureKey.length > 0 ? signatureKey.split(",") : [];

  const final = (
    state: EditionContextState,
    profileId: string | null,
  ): EditionContextRouting => ({
    state,
    editionContextProfileId: profileId,
    editionContextTraitIds: signature,
    residualSubtype: outSubtype,
    residualStamp: outStamp,
  });

  if (signature.some((id) => index.inactiveTraitIds.has(id))) {
    return final("NEEDS_REVIEW_INACTIVE_EC_TRAIT", null);
  }
  const profileId = index.profileBySignature.get(signatureKey);
  if (profileId === undefined) return final("NEEDS_REVIEW_NO_EC_PROFILE", null);
  if (index.inactiveProfileIds.has(profileId)) {
    return final("NEEDS_REVIEW_INACTIVE_EC_PROFILE", null);
  }
  return final("RESOLVED_WITH_EC_PROFILE", profileId);
}

/** Réplica do bloco de normalized_data de index.ts (DIFF 4 do patch). */
function buildNormalizedData(
  variantTypeId: string | null,
  printingResolved: boolean,
  printingProfileId: string | null,
  ec: EditionContextRouting,
): Record<string, unknown> {
  const normalizedData: Record<string, unknown> = {};
  if (printingResolved && isEditionContextResolved(ec.state)) {
    if (variantTypeId !== null) normalizedData.variant_type_id = variantTypeId;
    normalizedData.printing_profile_id = printingProfileId;
    normalizedData.edition_context_profile_id = ec.editionContextProfileId;
  }
  return normalizedData;
}

// ---------------------------------------------------------------------------
// RUNNER — um caso Deno por vetor, guiado pela fixture.
// ---------------------------------------------------------------------------

type RunOutcome = {
  state: string;
  profileSymbol: string | null;
  traitSymbols: string[];
  residualSubtype: string | null;
  residualStamp: string[];
  emitsAxisKeys: boolean;
};

function runVector(
  v: VectorSpec,
  residual: { subtype: string | null; stamp: string[] },
): RunOutcome {
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
    return {
      id: uuid,
      traits_signature: p.traits.map(ensureTrait),
      is_active: p.is_active,
    };
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

  const index = buildEditionContextIndex(
    mappings,
    profiles,
    traits,
    SCOPE(v.job_scope),
  );

  const printingTerminal = v.printing.state === "RESOLVED_NO_PRINTING" ||
    v.printing.state === "RESOLVED_WITH_PROFILE";

  const subtype = residual.subtype === null ? null : TOKEN(residual.subtype);
  const stamp = residual.stamp.map(TOKEN).sort();

  // 2211:86-91 — o eixo 3 nem roda quando Printing não é terminal.
  const ec: EditionContextRouting = printingTerminal
    ? routeEditionContext(index, subtype, stamp.length > 0 ? stamp : null)
    : {
      state: "NOT_EVALUATED",
      editionContextProfileId: null,
      editionContextTraitIds: [],
      residualSubtype: subtype,
      residualStamp: stamp.length > 0 ? stamp : null,
    };

  const printingProfileId = v.printing.profile === null
    ? null
    : symbolToUuid(v.printing.profile);

  const nd = buildNormalizedData(
    symbolToUuid("VT_FIXTURE"),
    printingTerminal,
    printingProfileId,
    ec,
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
  };
}

function assertAgainstFixture(
  label: string,
  v: VectorSpec,
  residual: { subtype: string | null; stamp: string[] },
  expected: ExpectedSpec,
) {
  const got = runVector(v, residual);

  assertEquals(got.state, expected.edition_context_state, `${label}: estado`);
  assertEquals(
    got.profileSymbol,
    expected.edition_context_profile,
    `${label}: profile`,
  );
  assertEquals(
    got.traitSymbols,
    [...expected.edition_context_trait_ids].sort(),
    `${label}: trait_ids`,
  );
  assertEquals(
    got.residualSubtype,
    expected.residual_subtype === null ? null : TOKEN(expected.residual_subtype),
    `${label}: residual_subtype`,
  );
  assertEquals(
    got.residualStamp,
    expected.residual_stamp.map(TOKEN).sort(),
    `${label}: residual_stamp`,
  );
  assertEquals(
    got.emitsAxisKeys,
    expected.edge_emits_axis_keys,
    `${label}: edge_emits_axis_keys`,
  );
}

for (const v of fixture.vectors) {
  Deno.test(`${v.id} — ${v.title} [${v.covers}]`, () => {
    if (v.expected) {
      assertAgainstFixture(v.id, v, v.residual_after_printing, v.expected);
    }
    for (const sc of v.sub_cases ?? []) {
      assertAgainstFixture(sc.label, v, sc.residual_after_printing, sc.expected);
    }
  });
}

// ---------------------------------------------------------------------------
// IDENTIDADE — a asserção que o vetor E15 carrega e que nenhum outro cobre.
// ---------------------------------------------------------------------------

Deno.test("E15-IDENTIDADE — a chave de 4 partes separa duas Editions; a de 3 as colapsa", () => {
  const v = fixture.vectors.find((x) => x.id === "E15");
  assert(v !== undefined, "vetor E15 ausente da fixture");
  assert(v.identity_assertion !== undefined, "E15 sem identity_assertion");
  assert(v.sub_cases !== undefined && v.sub_cases.length === 2, "E15 precisa de 2 sub-casos");

  const CARD = symbolToUuid("CARD_FIXTURE");
  const VT = symbolToUuid("VT_FIXTURE");

  const keysOf = (label: string) => {
    const sc = v.sub_cases!.find((s) => s.label === label)!;
    const got = runVector(v, sc.residual_after_printing);
    assertEquals(got.state, sc.expected.edition_context_state, `${label}: estado`);
    const ecUuid = sc.expected.edition_context_profile === null
      ? null
      : symbolToUuid(sc.expected.edition_context_profile);
    return {
      quatro: `${CARD}|${VT}|${buildPrintingProfileKeyPart(null)}|${
        buildEditionContextKeyPart(ecUuid)
      }`,
      tres: `${CARD}|${VT}|${buildPrintingProfileKeyPart(null)}`,
    };
  };

  const a = keysOf("E15a");
  const b = keysOf("E15b");

  if (v.identity_assertion.expect_keys_distinct) {
    assert(a.quatro !== b.quatro, "chave de 4 partes NAO separou as duas Editions");
  }
  if (v.identity_assertion.expect_legacy_3part_keys_equal) {
    assertEquals(
      a.tres,
      b.tres,
      "contraprova falhou: a chave antiga de 3 partes deveria colapsar as duas",
    );
  }
});

// ---------------------------------------------------------------------------
// META — o que impede esta suíte de virar teatro.
// ---------------------------------------------------------------------------

Deno.test("COBERTURA — os 8 estados do vocabulário aparecem em algum expected", () => {
  const vistos = new Set<string>();
  for (const v of fixture.vectors) {
    if (v.expected) vistos.add(v.expected.edition_context_state);
    for (const sc of v.sub_cases ?? []) vistos.add(sc.expected.edition_context_state);
  }
  const faltando = fixture.vocabulary.filter((s) => !vistos.has(s));
  assertEquals(faltando, [], `estados sem nenhum vetor: ${faltando.join(", ")}`);
});

Deno.test("ROSTER — nenhum vetor some nem aparece sem estar declarado", () => {
  assertEquals(fixture.vectors.map((v) => v.id), fixture.roster);
});

Deno.test("EXPECTED_NAO_LOCAL — nenhum valor esperado e declarado neste arquivo", async () => {
  // Um expected local reabriria exatamente o defeito que o mandato nomeia:
  // dois runners provando cada um a sua propria opiniao.
  const src = await Deno.readTextFile(new URL(import.meta.url));
  const corpo = src.slice(src.indexOf("// RUNNER"));
  for (const estado of fixture.vocabulary) {
    // O vocabulario aparece legitimamente no tipo EditionContextState e no
    // Set de terminais, ambos ANTES do runner. Depois dele, nao pode.
    assert(
      !corpo.includes(`"${estado}"`),
      `estado ${estado} literal apos o runner — expected local proibido`,
    );
  }
});

Deno.test("PARIDADE_FONTE — a replica precisa ser conferida contra o index.ts real", async () => {
  // Enquanto o patch nao estiver aplicado, este caso FALHA de proposito.
  // Depois do deploy: apagar a replica, importar de ./index.ts, e este caso
  // passa a comparar o texto das duas funcoes, como PARIDADE_INLINE faz em
  // variant-scope-vectors.test.ts.
  let src: string;
  try {
    src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  } catch {
    throw new Error(
      "PARIDADE_FONTE PENDENTE: index.ts nao esta ao lado deste arquivo. " +
        "Enquanto o patch da Edge nao for aplicado, a replica declarada neste " +
        "teste NAO pode ser conferida contra o original — os vetores provam a " +
        "replica, nao a Edge. NAO registrar como PASS.",
    );
  }
  assert(
    src.includes("function routeEditionContext("),
    "index.ts nao contem routeEditionContext — patch nao aplicado.",
  );
  assert(
    src.includes("NEEDS_REVIEW_INACTIVE_EC_MAPPING"),
    "index.ts nao trata mapping conhecido sem routing ativo — fail-OPEN.",
  );
});
