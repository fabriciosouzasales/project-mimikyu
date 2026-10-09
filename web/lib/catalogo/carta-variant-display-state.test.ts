// F2.1 — integração da F1 aos dados da galeria (VARIANT-DISPLAY-SEMANTICS-01,
// F2.1-DATA-INTEGRATION-IMPLEMENTATION-01). Testes S1–S29.
//
// Fixtures: nomes, codes, display_order e combinações de eixos derivados da
// evidência F0 (F0-A.full.json, 2026-10-09) para Dark Alakazam 01/82 (BASE5)
// e Energias 001/015/016 de SVE. Os ids são SINTÉTICOS (UUID v4 fixos) e não
// representam linhas do LIVE.
//
// Executar: node --experimental-strip-types --test lib/catalogo/carta-variant-display-state.test.ts

import assert from "node:assert/strict";
import { test } from "node:test";
import { buildCardVariantDisplays } from "./card-variant-display.ts";
import {
  CARD_VARIANT_LABEL_SEPARATOR,
  buildCartaVariantDisplayState,
  buildCartaVariantView,
  mapCartaVariants,
  projectCartaVariantView,
  readCardSetCode,
  type CartaVariantRawRow,
  type CartaVariantSemanticRawRow,
} from "./carta-variants.ts";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

let seq = 0;
const uid = (): string => `00000000-0000-4000-8000-${(++seq).toString(16).padStart(12, "0")}`;

type AxisRaw = { id: string; name: string; display_order: number };
type FinishRaw = AxisRaw & { code: string | null };

// [LIVE F0] Finish: code, display_order, name.
const FINISH: Record<string, FinishRaw> = {
  STANDARD: { id: uid(), code: "STANDARD", name: "Padrão", display_order: 1 },
  HOLO: { id: uid(), code: "HOLO", name: "Holográfica", display_order: 2 },
  REVERSE_HOLO: { id: uid(), code: "REVERSE_HOLO", name: "Holográfica Reversa", display_order: 4 },
  POKE_BALL_REVERSE: { id: uid(), code: "POKE_BALL_REVERSE", name: "Poké Bola Reversa", display_order: 6 },
  COSMOS_REVERSE: { id: uid(), code: "COSMOS_REVERSE", name: "Cosmos Reversa", display_order: 33 },
  CRACKED_ICE_HOLO: { id: uid(), code: "CRACKED_ICE_HOLO", name: "Holografica Cracked Ice", display_order: 43 },
};
// [LIVE F0] Printing / Edition Context.
const FIRST_EDITION: AxisRaw = { id: uid(), name: "1ª Edição", display_order: 7 };
const PLAYER_REWARDS: AxisRaw = { id: uid(), name: "Programa Player Rewards", display_order: 1420 };
const PROFESSOR: AxisRaw = { id: uid(), name: "Programa Professor", display_order: 1430 };

type Spec = [keyof typeof FINISH, AxisRaw | null, AxisRaw | null];

function row(cardId: string, finish: FinishRaw, printing: AxisRaw | null, ec: AxisRaw | null): CartaVariantSemanticRawRow {
  return {
    id: uid(),
    card_id: cardId,
    variant_type_id: finish.id,
    printing_profile_id: printing?.id ?? null,
    edition_context_profile_id: ec?.id ?? null,
    card_variant_type: { ...finish },
    card_printing_profile: printing ? { ...printing } : null,
    card_edition_context_profile: ec ? { ...ec } : null,
  };
}

function card(specs: Spec[]): CartaVariantSemanticRawRow[] {
  const cardId = uid();
  return specs.map(([finish, printing, ec]) => row(cardId, FINISH[finish]!, printing, ec));
}

const ALAKAZAM = card([
  ["HOLO", null, null],
  ["HOLO", FIRST_EDITION, null],
]);
const GRAMA = card([
  ["STANDARD", null, null],
  ["STANDARD", null, PLAYER_REWARDS],
  ["POKE_BALL_REVERSE", null, null],
  ["COSMOS_REVERSE", null, null],
  ["COSMOS_REVERSE", null, PLAYER_REWARDS],
  ["COSMOS_REVERSE", null, PROFESSOR],
]);
const ESCURIDAO_SPEC: Spec[] = [
  ["STANDARD", null, null],
  ["STANDARD", null, PLAYER_REWARDS],
  ["REVERSE_HOLO", null, null],
  ["COSMOS_REVERSE", null, PLAYER_REWARDS],
  ["COSMOS_REVERSE", null, PROFESSOR],
  ["CRACKED_ICE_HOLO", null, null],
];
const ESCURIDAO = card(ESCURIDAO_SPEC);
const METAL = card(ESCURIDAO_SPEC);

const F0_CASES: { name: string; set: string; rows: CartaVariantSemanticRawRow[]; labels: string[] }[] = [
  { name: "Dark Alakazam", set: "BASE5", rows: ALAKAZAM, labels: ["Holográfica", "Holográfica / 1ª Edição"] },
  {
    name: "Energia de Grama",
    set: "SVE",
    rows: GRAMA,
    labels: [
      "Padrão",
      "Padrão / Programa Player Rewards",
      "Poké Bola Reversa",
      "Cosmos Reversa",
      "Cosmos Reversa / Programa Player Rewards",
      "Cosmos Reversa / Programa Professor",
    ],
  },
  {
    name: "Energia de Escuridão",
    set: "SVE",
    rows: ESCURIDAO,
    labels: [
      "Padrão",
      "Padrão / Programa Player Rewards",
      "Holográfica Reversa",
      "Cosmos Reversa / Programa Player Rewards",
      "Cosmos Reversa / Programa Professor",
      "Holografica Cracked Ice",
    ],
  },
  {
    name: "Energia de Metal",
    set: "SVE",
    rows: METAL,
    labels: [
      "Padrão",
      "Padrão / Programa Player Rewards",
      "Holográfica Reversa",
      "Cosmos Reversa / Programa Player Rewards",
      "Cosmos Reversa / Programa Professor",
      "Holografica Cracked Ice",
    ],
  },
];

/** Shuffle determinístico (LCG) — só para permutar entradas. */
function permute<T>(items: readonly T[], seed: number): T[] {
  const out = [...items];
  let s = seed;
  for (let i = out.length - 1; i > 0; i--) {
    s = (s * 1103515245 + 12345) % 2147483648;
    const j = s % (i + 1);
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

function okState(rows: unknown, set: unknown) {
  const state = buildCartaVariantDisplayState(rows, set);
  assert.equal(state.status, "OK", JSON.stringify(state));
  if (state.status !== "OK") throw new Error("unreachable");
  return state;
}

function okView(rows: unknown, set: unknown) {
  const view = buildCartaVariantView(rows, set);
  assert.equal(view.status, "OK", JSON.stringify(view));
  if (view.status !== "OK") throw new Error("unreachable");
  return view;
}

function errorCodes(rows: unknown, set: unknown = "SVE"): string[] {
  const state = buildCartaVariantDisplayState(rows, set);
  assert.equal(state.status, "ERROR", JSON.stringify(state));
  if (state.status !== "ERROR") throw new Error("unreachable");
  return [...new Set(state.errors.map((error) => error.code))];
}

const labelsOf = (view: ReturnType<typeof okView>): string[] =>
  view.variants.map((variant) => variant.parts.map((part) => part.text).join(CARD_VARIANT_LABEL_SEPARATOR));

// Regra legada (baseline 94b64ba, `mapCartaVariants`), copiada literalmente para S16.
function legacyBaseline(rows: readonly CartaVariantRawRow[] | null | undefined) {
  return (rows ?? [])
    .filter(
      (variant): variant is CartaVariantRawRow & { card_variant_type: { name: string; display_order: number } } =>
        variant.card_variant_type !== null,
    )
    .sort((a, b) => a.card_variant_type.display_order - b.card_variant_type.display_order)
    .map((variant) => ({ id: variant.id, name: variant.card_variant_type.name }));
}

// ---------------------------------------------------------------------------
// S1–S4 — casos F0
// ---------------------------------------------------------------------------

F0_CASES.forEach((fixture, index) => {
  test(`S${index + 1} — ${fixture.name}: ${fixture.rows.length} variantes na ordem F1 com identidade preservada`, () => {
    const state = okState(fixture.rows, fixture.set);
    assert.equal(state.rawCount, fixture.rows.length);
    assert.equal(state.variants.length, fixture.rows.length);
    const view = okView(fixture.rows, fixture.set);
    assert.deepEqual(labelsOf(view), fixture.labels);
    // Identidade: cada id de entrada aparece exatamente uma vez, com seus 5 componentes.
    const byId = new Map(fixture.rows.map((r) => [r.id, r]));
    assert.equal(new Set(view.variants.map((v) => v.id)).size, fixture.rows.length);
    for (const variant of state.variants) {
      const source = byId.get(variant.identity.variantId);
      assert.ok(source, "id de saída sem linha de entrada");
      assert.equal(variant.identity.cardId, source.card_id);
      assert.equal(variant.identity.variantTypeId, source.variant_type_id);
      assert.equal(variant.identity.printingProfileId, source.printing_profile_id);
      assert.equal(variant.identity.editionContextProfileId, source.edition_context_profile_id);
    }
  });
});

test("S1b — Dark Alakazam: a 1ª Edição é a parte PRINTING que diferencia as duas Holográficas", () => {
  const view = okView(ALAKAZAM, "BASE5");
  assert.deepEqual(view.variants[0]!.parts, [{ axis: "FINISH", text: "Holográfica" }]);
  assert.deepEqual(view.variants[1]!.parts, [
    { axis: "FINISH", text: "Holográfica" },
    { axis: "PRINTING", text: "1ª Edição" },
  ]);
  assert.equal(view.variants[0]!.collidesWith.length, 0);
});

// ---------------------------------------------------------------------------
// S5–S20 — contrato
// ---------------------------------------------------------------------------

test("S5 — perfis distintos com o mesmo nome: 2 itens, colisão semântica e renderizada sinalizadas", () => {
  const cardId = uid();
  const ecA: AxisRaw = { id: uid(), name: "Programa Professor", display_order: 2001 };
  const ecB: AxisRaw = { id: uid(), name: "Programa Professor", display_order: 2002 };
  const rows = [row(cardId, FINISH.STANDARD!, null, ecA), row(cardId, FINISH.STANDARD!, null, ecB)];
  const state = okState(rows, "SVE");
  assert.equal(state.variants.length, 2);
  assert.ok(state.variants.every((v) => v.admin.labelCollision.collides));
  const view = okView(rows, "SVE");
  assert.deepEqual(view.variants[0]!.collidesWith, [view.variants[1]!.id]);
  assert.deepEqual(view.variants[1]!.collidesWith, [view.variants[0]!.id]);
  assert.deepEqual(view.variants[0]!.renderedCollidesWith, [view.variants[1]!.id]);
});

test("S6 — Printing e Edition Context simultâneos: três partes e texto sem segmento vazio", () => {
  const rows = [row(uid(), FINISH.HOLO!, FIRST_EDITION, PLAYER_REWARDS)];
  const view = okView(rows, "BASE5");
  assert.deepEqual(
    view.variants[0]!.parts.map((p) => p.axis),
    ["FINISH", "PRINTING", "EDITION_CONTEXT"],
  );
  assert.deepEqual(labelsOf(view), ["Holográfica / 1ª Edição / Programa Player Rewards"]);
});

test("S7 — carta sem variantes: [] → NONE com rawCount 0", () => {
  assert.deepEqual(buildCartaVariantDisplayState([], "SVE"), { status: "NONE", rawCount: 0 });
  assert.deepEqual(buildCartaVariantView([], "SVE"), { status: "NONE", rawCount: 0 });
});

test("S8 — FK preenchida com relacionamento ausente (RLS/embed nulo) → ERROR, nunca eixo ausente", () => {
  const printingMissing = { ...row(uid(), FINISH.HOLO!, FIRST_EDITION, null), card_printing_profile: null };
  assert.deepEqual(errorCodes([printingMissing], "BASE5"), ["PRINTING_EMBED_MISSING"]);
  const ecMissing = { ...row(uid(), FINISH.STANDARD!, null, PLAYER_REWARDS), card_edition_context_profile: null };
  const state = buildCartaVariantDisplayState([ecMissing], "SVE");
  assert.equal(state.status, "ERROR");
  if (state.status === "ERROR") assert.equal(state.rawCount, 1);
  assert.deepEqual(errorCodes([ecMissing]), ["EDITION_CONTEXT_EMBED_MISSING"]);
});

test("S9 — Finish ausente → ERROR FINISH_MISSING (variante nunca omitida)", () => {
  const noFinish = { ...row(uid(), FINISH.HOLO!, null, null), card_variant_type: null };
  assert.deepEqual(errorCodes([noFinish]), ["FINISH_MISSING"]);
});

test("S10 — ids duplicados e identidade de 4 componentes repetida", () => {
  const base = row(uid(), FINISH.HOLO!, null, null);
  assert.deepEqual(errorCodes([base, { ...base }]), ["DUPLICATE_VARIANT_ID"]);
  assert.deepEqual(errorCodes([base, { ...base, id: uid() }]), ["DUPLICATE_IDENTITY"]);
});

test("S11 — entrada inválida: contêiner não-array e elemento não-objeto, sem exceção", () => {
  assert.deepEqual(errorCodes(null), ["INPUT_NOT_ARRAY"]);
  assert.deepEqual(errorCodes([42]), ["INVALID_RECORD"]);
});

test("S12 — estabilidade: 20 permutações da entrada produzem o mesmo resultado", () => {
  const reference = okState(GRAMA, "SVE");
  for (let seed = 1; seed <= 20; seed++) {
    assert.deepEqual(okState(permute(GRAMA, seed), "SVE"), reference);
    assert.deepEqual(okView(permute(GRAMA, seed), "SVE"), okView(GRAMA, "SVE"));
  }
});

test("S13 — isolamento: carta inválida não afeta a carta vizinha", () => {
  const broken = [{ ...row(uid(), FINISH.HOLO!, null, null), card_variant_type: null }];
  const results = [broken, ALAKAZAM].map((rows) => buildCartaVariantView(rows, "BASE5"));
  assert.equal(results[0]!.status, "ERROR");
  assert.equal(results[1]!.status, "OK");
  assert.deepEqual(results[1], okView(ALAKAZAM, "BASE5"));
});

test("S14 — separador \" / \": nome contendo o separador gera colisão renderizada; '·' e '—' não quebram partes", () => {
  const cardId = uid();
  const ec1: AxisRaw = { id: uid(), name: "A / B", display_order: 3001 };
  const ec2: AxisRaw = { id: uid(), name: "B", display_order: 3002 };
  const p1: AxisRaw = { id: uid(), name: "A", display_order: 3003 };
  // "Padrão / A / B" (EC "A / B") × "Padrão / A / B" (Printing "A" + EC "B")
  const rows = [row(cardId, FINISH.STANDARD!, null, ec1), row(cardId, FINISH.STANDARD!, p1, ec2)];
  const view = okView(rows, "SVE");
  assert.deepEqual(labelsOf(view)[0], labelsOf(view)[1]);
  assert.equal(view.variants[0]!.collidesWith.length, 0, "tuplas diferentes: sem colisão semântica");
  assert.equal(view.variants[0]!.renderedCollidesWith.length, 1);
  assert.equal(view.variants[1]!.renderedCollidesWith.length, 1);

  const dotted: AxisRaw = { id: uid(), name: "Liga · Temporada — Final", display_order: 3004 };
  const v2 = okView([row(uid(), FINISH.STANDARD!, null, dotted)], "SVE");
  assert.deepEqual(v2.variants[0]!.parts, [
    { axis: "FINISH", text: "Padrão" },
    { axis: "EDITION_CONTEXT", text: "Liga · Temporada — Final" },
  ]);
});

test("S15 — legado interno (D3): presente no estado do servidor, ausente da projeção", () => {
  for (const fixture of F0_CASES) {
    const state = okState(fixture.rows, fixture.set);
    for (const variant of state.variants) {
      assert.equal(variant.admin.legacy.status, "NOT_IDENTIFIED_AS_LEGACY");
      assert.equal(variant.admin.legacy.reason, "ADJUDICATED_FINISH_CODE");
    }
    const serialized = JSON.stringify(projectCartaVariantView(state));
    for (const forbidden of ["legacy", "LEGACY", "evidenceRef", "ADJUDICATED", "admin"]) {
      assert.ok(!serialized.includes(forbidden), `projeção contém ${forbidden}`);
    }
  }
});

test("S16 — compatibilidade: mapCartaVariants idêntico à regra do baseline nos casos F0", () => {
  for (const fixture of F0_CASES) {
    assert.deepEqual(mapCartaVariants(fixture.rows), legacyBaseline(fixture.rows));
    assert.deepEqual(
      mapCartaVariants(fixture.rows).map((v) => v.name),
      legacyBaseline(fixture.rows).map((v) => v.name),
    );
  }
});

test("S17 — contagem: OK ⇒ rawCount = variantes; ERROR ⇒ rawCount = linhas recebidas", () => {
  for (const fixture of F0_CASES) {
    const view = okView(fixture.rows, fixture.set);
    assert.equal(view.rawCount, view.variants.length);
  }
  const rows = [row(uid(), FINISH.HOLO!, null, null), 7, null];
  const state = buildCartaVariantDisplayState(rows, "SVE");
  assert.equal(state.status, "ERROR");
  if (state.status === "ERROR") assert.equal(state.rawCount, 3);
});

test("S18 — não-mutação da entrada", () => {
  for (const fixture of F0_CASES) {
    const snapshot = JSON.stringify(fixture.rows);
    buildCartaVariantView(fixture.rows, fixture.set);
    buildCartaVariantDisplayState(fixture.rows, fixture.set);
    assert.equal(JSON.stringify(fixture.rows), snapshot);
  }
});

test("S19 — tamanho determinístico da projeção (bytes) nos casos F0", () => {
  const expected = [363, 1058, 1069, 1069];
  F0_CASES.forEach((fixture, index) => {
    const bytes = Buffer.byteLength(JSON.stringify(buildCartaVariantView(fixture.rows, fixture.set)));
    assert.equal(bytes, expected[index], `${fixture.name}: ${bytes} B`);
  });
});

test("S20 — paridade com a F1: o estado é exatamente buildCardVariantDisplays sobre a entrada adaptada", () => {
  for (const fixture of F0_CASES) {
    const direct = buildCardVariantDisplays(fixture.rows.map((r) => toCardVariantDisplayInput(r, fixture.set)));
    assert.ok(direct.ok);
    assert.deepEqual(okState(fixture.rows, fixture.set).variants, direct.ok ? direct.variants : null);
  }
});

// ---------------------------------------------------------------------------
// S21–S29 — entradas malformadas (A1)
// ---------------------------------------------------------------------------

test("S21 — code do Finish ausente: OK com legado FINISH_CODE_UNAVAILABLE (lacuna A1-L1 fixada)", () => {
  const r = row(uid(), FINISH.HOLO!, null, null);
  const { code: _omit, ...finishWithoutCode } = r.card_variant_type!;
  const state = okState([{ ...r, card_variant_type: finishWithoutCode }], "BASE5");
  assert.equal(state.variants[0]!.admin.legacy.status, "INDETERMINATE");
  assert.equal(state.variants[0]!.admin.legacy.reason, "FINISH_CODE_UNAVAILABLE");
});

test("S22 — contêiner não-array → ERROR INPUT_NOT_ARRAY com rawCount null (nunca NONE)", () => {
  for (const container of [null, undefined, "x", 0, {}, { length: 1 }]) {
    const state = buildCartaVariantDisplayState(container, "SVE");
    assert.equal(state.status, "ERROR", String(container));
    if (state.status !== "ERROR") continue;
    assert.equal(state.rawCount, null);
    assert.equal(state.fault, null);
    assert.deepEqual([...new Set(state.errors.map((e) => e.code))], ["INPUT_NOT_ARRAY"]);
    const view = buildCartaVariantView(container, "SVE");
    assert.equal(view.status, "ERROR");
  }
});

test("S23 — linhas null/número/array/array aninhado → INVALID_RECORD sem exceção", () => {
  for (const bad of [null, 7, "linha", [row(uid(), FINISH.HOLO!, null, null)], []]) {
    assert.deepEqual(errorCodes([bad]), ["INVALID_RECORD"], JSON.stringify(bad));
  }
});

test("S24 — chave de FK ausente ≠ null: ausente → INVALID_RECORD; null → válido", () => {
  const r = row(uid(), FINISH.HOLO!, null, null);
  const { printing_profile_id: _p, ...withoutPrintingKey } = r;
  assert.deepEqual(errorCodes([withoutPrintingKey]), ["INVALID_RECORD"]);
  const { edition_context_profile_id: _e, ...withoutEcKey } = r;
  assert.deepEqual(errorCodes([withoutEcKey]), ["INVALID_RECORD"]);
  okState([r], "BASE5");
  // O adaptador não cria a chave ausente.
  const adapted = toCardVariantDisplayInput(withoutPrintingKey, "BASE5") as Record<string, unknown>;
  assert.ok(!Object.prototype.hasOwnProperty.call(adapted, "printingProfileId"));
});

test("S25 — embed array ou primitivo em cada eixo → erro da F1, sem exceção", () => {
  const holo = row(uid(), FINISH.HOLO!, null, null);
  assert.deepEqual(errorCodes([{ ...holo, card_variant_type: [holo.card_variant_type] }]), ["INVALID_RECORD"]);
  assert.deepEqual(errorCodes([{ ...holo, card_variant_type: "HOLO" }]), ["INVALID_RECORD"]);
  const withPrinting = row(uid(), FINISH.HOLO!, FIRST_EDITION, null);
  assert.deepEqual(errorCodes([{ ...withPrinting, card_printing_profile: [FIRST_EDITION] }]), ["INVALID_RECORD"]);
  assert.deepEqual(errorCodes([{ ...withPrinting, card_printing_profile: 7 }]), ["INVALID_RECORD"]);
  assert.deepEqual(errorCodes([{ ...holo, card_edition_context_profile: [PROFESSOR] }]), ["EDITION_CONTEXT_EMBED_WITHOUT_FK"]);
  const withEc = row(uid(), FINISH.STANDARD!, null, PROFESSOR);
  assert.deepEqual(errorCodes([{ ...withEc, card_edition_context_profile: "x" }]), ["INVALID_RECORD"]);
});

test("S26 — Finish parcialmente formado: sem name, sem display_order, display_order textual", () => {
  const r = row(uid(), FINISH.HOLO!, null, null);
  const t = r.card_variant_type!;
  assert.deepEqual(errorCodes([{ ...r, card_variant_type: { id: t.id, code: t.code, display_order: 2 } }]), ["INVALID_AXIS_NAME"]);
  assert.deepEqual(errorCodes([{ ...r, card_variant_type: { id: t.id, code: t.code, name: t.name } }]), ["INVALID_DISPLAY_ORDER"]);
  assert.deepEqual(errorCodes([{ ...r, card_variant_type: { ...t, display_order: "2" } }]), ["INVALID_DISPLAY_ORDER"]);
  assert.deepEqual(errorCodes([{ ...r, card_variant_type: { name: t.name, code: t.code, display_order: 2 } }]), ["INVALID_RECORD"]);
});

test("S27 — exceção inesperada (getter que lança) → ERROR com fault, isolada da carta vizinha", () => {
  const hostile = Object.defineProperty({ ...row(uid(), FINISH.HOLO!, null, null) }, "id", {
    enumerable: true,
    get() {
      throw new Error("boom");
    },
  });
  const state = buildCartaVariantDisplayState([hostile], "BASE5");
  assert.deepEqual(state, { status: "ERROR", rawCount: 1, errors: [], fault: "UNEXPECTED_EXCEPTION" });
  const views = [[hostile], ALAKAZAM].map((rows) => buildCartaVariantView(rows, "BASE5"));
  assert.deepEqual(views[0], { status: "ERROR", rawCount: 1, errors: [], fault: "UNEXPECTED_EXCEPTION" });
  assert.deepEqual(views[1], okView(ALAKAZAM, "BASE5"));
});

test("S28 — card_set ausente, null, primitivo ou code inválido", () => {
  assert.equal(readCardSetCode(undefined), undefined);
  assert.equal(readCardSetCode(null), undefined);
  assert.equal(readCardSetCode("BASE5"), undefined);
  assert.equal(readCardSetCode({}), undefined);
  assert.equal(readCardSetCode({ code: "BASE5" }), "BASE5");
  assert.equal(readCardSetCode({ code: null }), null);
  // Não fornecido → OK (só a classificação interna de legado depende do Set).
  okState(ALAKAZAM, readCardSetCode(null));
  // code de tipo inválido → a F1 rejeita.
  assert.deepEqual(errorCodes(ALAKAZAM, readCardSetCode({ code: 5 })), ["INVALID_CARD_SET_CODE"]);
});

test("S29 — sem fallback legado: tipo nulo é omitido pelo legado, mas é ERROR no estado novo", () => {
  const rows = [row(uid(), FINISH.HOLO!, null, null), { ...row(uid(), FINISH.STANDARD!, null, null), card_variant_type: null }];
  assert.equal(mapCartaVariants(rows).length, 1, "regra legada preservada (omite o tipo nulo)");
  const view = buildCartaVariantView(rows, "BASE5");
  assert.equal(view.status, "ERROR");
  if (view.status === "ERROR") {
    assert.equal(view.rawCount, 2);
    assert.deepEqual(view.errors.map((e) => e.code), ["FINISH_MISSING"]);
  }
  assert.ok(!JSON.stringify(view).includes("Holográfica"), "nenhum nome legado no estado de erro");
});
