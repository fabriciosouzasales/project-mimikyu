// Contrato de semântica de exibição de Card Variant (VARIANT-DISPLAY-SEMANTICS-01 / F1).
//
// Fixtures SINTÉTICAS: ids, nomes e ordens são inventados para reproduzir a
// FORMA dos casos observados na interface (Dark Alakazam, Energias SVE). Não
// representam nem afirmam o conteúdo do LIVE.
//
// Executar: node --experimental-strip-types --test lib/catalogo/card-variant-display.test.ts
// (a partir de web/, sem instalar nada — mesmo padrão de variant-size-scope.test.ts.)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  ADJUDICATED_FINISH_CODES,
  ADJUDICATED_LEGACY_CODES,
  ADJUDICATED_SET_LOGO_CODES,
  buildCardVariantDisplays,
  classifyCardVariantLegacy,
  compareCardVariantDisplay,
  findRenderedLabelCollisions,
  formatCardVariantLabel,
  getCardVariantLabelParts,
  sortCardVariantDisplays,
  type CardVariantAxisInput,
  type CardVariantDisplay,
  type CardVariantDisplayInput,
  type CardVariantFinishInput,
} from "./card-variant-display.ts";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/** UUID sintético determinístico a partir de um número. */
function uuid(n: number): string {
  return `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
}

const CARD_A = uuid(0xa001);
const CARD_B = uuid(0xb001);

const FINISH_STANDARD: CardVariantFinishInput = { id: uuid(101), name: "Padrão", displayOrder: 10, code: "STANDARD" };
const FINISH_HOLO: CardVariantFinishInput = { id: uuid(102), name: "Holográfica", displayOrder: 20, code: "HOLO" };
const FINISH_COSMOS_REV: CardVariantFinishInput = {
  id: uuid(103),
  name: "Cosmos Reversa",
  displayOrder: 30,
  code: "COSMOS_REVERSE",
};
const FINISH_CRACKED: CardVariantFinishInput = {
  id: uuid(104),
  name: "Cracked Ice Holo",
  displayOrder: 40,
  code: "CRACKED_ICE_HOLO",
};

const PRINT_FIRST: CardVariantAxisInput = { id: uuid(201), name: "1ª Edição", displayOrder: 1 };
const PRINT_UNLIMITED: CardVariantAxisInput = { id: uuid(202), name: "Tiragem Ilimitada", displayOrder: 3 };
const PRINT_COMPOSITE: CardVariantAxisInput = {
  id: uuid(203),
  name: "Sem Sombra · Bochecha Vermelha · 1ª Edição",
  displayOrder: 6,
};

const EC_REWARDS: CardVariantAxisInput = { id: uuid(301), name: "Player Rewards", displayOrder: 100 };
const EC_PROFESSOR: CardVariantAxisInput = { id: uuid(302), name: "Professor Program", displayOrder: 110 };
const EC_DASH: CardVariantAxisInput = { id: uuid(303), name: "My First Battle — Borda Azul", displayOrder: 120 };

function variant(
  id: number,
  cardId: string,
  finish: CardVariantFinishInput,
  printing: CardVariantAxisInput | null = null,
  editionContext: CardVariantAxisInput | null = null,
): CardVariantDisplayInput {
  return {
    id: uuid(id),
    cardId,
    variantTypeId: finish.id,
    printingProfileId: printing?.id ?? null,
    editionContextProfileId: editionContext?.id ?? null,
    finish,
    printing,
    editionContext,
  };
}

function build(input: unknown): CardVariantDisplay[] {
  const result = buildCardVariantDisplays(input);
  if (!result.ok) {
    assert.fail(`esperado ok, recebido erros: ${JSON.stringify(result.errors)}`);
  }
  return result.variants;
}

function errorCodes(input: unknown): string[] {
  const result = buildCardVariantDisplays(input);
  assert.equal(result.ok, false, "esperado lote rejeitado");
  return result.ok ? [] : result.errors.map((error) => error.code);
}

/** Embaralhamento determinístico (Fisher–Yates com LCG fixo). */
function shuffled<T>(items: readonly T[], seed: number): T[] {
  const copy = [...items];
  let state = seed;
  for (let i = copy.length - 1; i > 0; i -= 1) {
    state = (state * 1103515245 + 12345) % 2147483648;
    const j = state % (i + 1);
    const tmp = copy[i] as T;
    copy[i] = copy[j] as T;
    copy[j] = tmp;
  }
  return copy;
}

const ids = (variants: readonly CardVariantDisplay[]): string[] => variants.map((v) => v.identity.variantId);
const SEP = " · ";

// ---------------------------------------------------------------------------
// T1 — Identidade integral
// ---------------------------------------------------------------------------

test("T1 — preserva card_variant.id, card_id e os ids dos três eixos", () => {
  const input = variant(1, CARD_A, FINISH_HOLO, PRINT_FIRST, EC_REWARDS);
  const [out] = build([input]);
  assert.ok(out);
  assert.deepEqual(out.identity, {
    variantId: input.id,
    cardId: CARD_A,
    variantTypeId: FINISH_HOLO.id,
    printingProfileId: PRINT_FIRST.id,
    editionContextProfileId: EC_REWARDS.id,
  });
  assert.deepEqual(out.presentation, {
    finish: { name: "Holográfica", displayOrder: 20 },
    printing: { name: "1ª Edição", displayOrder: 1 },
    editionContext: { name: "Player Rewards", displayOrder: 100 },
  });
  // Separação de responsabilidades: apresentação não carrega ids nem code.
  assert.equal(JSON.stringify(out.presentation).includes(FINISH_HOLO.id), false);
  assert.equal(JSON.stringify(out.presentation).includes("HOLO\""), false);
});

// ---------------------------------------------------------------------------
// T2 — Eixos opcionais
// ---------------------------------------------------------------------------

test("T2 — combinações de eixos opcionais: null legítimo não gera texto", () => {
  const cases: Array<[CardVariantDisplayInput, string, string[]]> = [
    [variant(1, CARD_A, FINISH_HOLO), "Holográfica", ["FINISH"]],
    [variant(2, CARD_A, FINISH_HOLO, PRINT_FIRST), "Holográfica · 1ª Edição", ["FINISH", "PRINTING"]],
    [variant(3, CARD_A, FINISH_HOLO, null, EC_REWARDS), "Holográfica · Player Rewards", ["FINISH", "EDITION_CONTEXT"]],
    [
      variant(4, CARD_A, FINISH_HOLO, PRINT_FIRST, EC_REWARDS),
      "Holográfica · 1ª Edição · Player Rewards",
      ["FINISH", "PRINTING", "EDITION_CONTEXT"],
    ],
  ];
  for (const [input, expectedLabel, expectedAxes] of cases) {
    const [out] = build([input]);
    assert.ok(out);
    const label = formatCardVariantLabel(out, { separator: SEP });
    assert.equal(label, expectedLabel);
    assert.deepEqual(getCardVariantLabelParts(out).map((p) => p.axis), expectedAxes);
    assert.equal(/null|undefined/.test(label), false);
    assert.equal(label.startsWith(SEP) || label.endsWith(SEP) || label.includes(SEP + SEP), false);
  }
  const [onlyFinish] = build([variant(9, CARD_A, FINISH_STANDARD)]);
  assert.ok(onlyFinish);
  assert.equal(onlyFinish.presentation.printing, null);
  assert.equal(onlyFinish.presentation.editionContext, null);
  assert.equal(onlyFinish.identity.printingProfileId, null);
  assert.equal(onlyFinish.identity.editionContextProfileId, null);
});

// ---------------------------------------------------------------------------
// T3 — Forma "Dark Alakazam": duas HOLO distinguidas por tiragem
// ---------------------------------------------------------------------------

test("T3 — duas Holográfica com tiragens distintas permanecem identificáveis", () => {
  const out = build([variant(2, CARD_A, FINISH_HOLO, PRINT_UNLIMITED), variant(1, CARD_A, FINISH_HOLO, PRINT_FIRST)]);
  assert.equal(out.length, 2);
  assert.notEqual(out[0]?.identity.variantId, out[1]?.identity.variantId);
  assert.deepEqual(
    out.map((v) => formatCardVariantLabel(v, { separator: SEP })),
    ["Holográfica · 1ª Edição", "Holográfica · Tiragem Ilimitada"],
  );
  assert.ok(out.every((v) => v.admin.labelCollision.collides === false));
});

// ---------------------------------------------------------------------------
// T4 — Forma "Energia de Grama": 2 Padrão + 2 Cosmos Reversa
// ---------------------------------------------------------------------------

test("T4 — acabamentos repetidos com contextos distintos: nenhuma variante desaparece", () => {
  const input = [
    variant(11, CARD_A, FINISH_STANDARD),
    variant(12, CARD_A, FINISH_STANDARD, null, EC_REWARDS),
    variant(13, CARD_A, FINISH_COSMOS_REV, null, EC_REWARDS),
    variant(14, CARD_A, FINISH_COSMOS_REV, null, EC_PROFESSOR),
  ];
  const out = build(input);
  assert.equal(out.length, 4);
  assert.deepEqual(new Set(ids(out)), new Set(input.map((v) => v.id)));
  assert.deepEqual(
    out.map((v) => formatCardVariantLabel(v, { separator: SEP })),
    ["Padrão", "Padrão · Player Rewards", "Cosmos Reversa · Player Rewards", "Cosmos Reversa · Professor Program"],
  );
  assert.ok(out.every((v) => !v.admin.labelCollision.collides));
});

// ---------------------------------------------------------------------------
// T5 — Forma "Energia de Escuridão/Metal": 6 variantes, ordem estável
// ---------------------------------------------------------------------------

test("T5 — seis variantes com acabamentos repetidos: ordem estável sob qualquer ordem de entrada", () => {
  const input = [
    variant(21, CARD_B, FINISH_STANDARD),
    variant(22, CARD_B, FINISH_STANDARD, null, EC_REWARDS),
    variant(23, CARD_B, FINISH_COSMOS_REV),
    variant(24, CARD_B, FINISH_COSMOS_REV, null, EC_REWARDS),
    variant(25, CARD_B, FINISH_COSMOS_REV, null, EC_PROFESSOR),
    variant(26, CARD_B, FINISH_CRACKED),
  ];
  const expected = ids(build(input));
  assert.deepEqual(expected, [uuid(21), uuid(22), uuid(23), uuid(24), uuid(25), uuid(26)]);
  for (const seed of [1, 7, 42, 1999, 2026]) {
    assert.deepEqual(ids(build(shuffled(input, seed))), expected, `seed ${seed}`);
  }
});

// ---------------------------------------------------------------------------
// T6 — Colisão textual
// ---------------------------------------------------------------------------

test("T6 — perfis distintos com o mesmo nome: ambas preservadas e colisão sinalizada", () => {
  const twinA: CardVariantAxisInput = { id: uuid(401), name: "Campeonato", displayOrder: 200 };
  const twinB: CardVariantAxisInput = { id: uuid(402), name: "Campeonato", displayOrder: 210 };
  const out = build([
    variant(31, CARD_A, FINISH_HOLO, null, twinA),
    variant(32, CARD_A, FINISH_HOLO, null, twinB),
    variant(33, CARD_A, FINISH_STANDARD),
    // Mesmo rótulo, mas OUTRA carta: não é colisão (colisão é por carta).
    variant(34, CARD_B, FINISH_HOLO, null, twinA),
  ]);
  assert.equal(out.length, 4);
  const byId = new Map(out.map((v) => [v.identity.variantId, v]));
  assert.deepEqual(byId.get(uuid(31))?.admin.labelCollision, { collides: true, collidingVariantIds: [uuid(32)] });
  assert.deepEqual(byId.get(uuid(32))?.admin.labelCollision, { collides: true, collidingVariantIds: [uuid(31)] });
  assert.equal(byId.get(uuid(33))?.admin.labelCollision.collides, false);
  assert.equal(byId.get(uuid(34))?.admin.labelCollision.collides, false);
  // Rótulo do colecionador NÃO recebe UUID.
  for (const v of out) {
    assert.equal(/[0-9a-f]{8}-[0-9a-f]{4}/i.test(formatCardVariantLabel(v, { separator: SEP })), false);
  }
  // Os eixos estruturados continuam distintos para desambiguação futura.
  assert.notEqual(byId.get(uuid(31))?.identity.editionContextProfileId, byId.get(uuid(32))?.identity.editionContextProfileId);
});

// ---------------------------------------------------------------------------
// T7 — Separadores
// ---------------------------------------------------------------------------

test("T7 — nomes com '·' e '—' mantêm a fronteira estrutural dos eixos", () => {
  const [out] = build([variant(41, CARD_A, FINISH_HOLO, PRINT_COMPOSITE, EC_DASH)]);
  assert.ok(out);
  assert.deepEqual(getCardVariantLabelParts(out), [
    { axis: "FINISH", text: "Holográfica" },
    { axis: "PRINTING", text: "Sem Sombra · Bochecha Vermelha · 1ª Edição" },
    { axis: "EDITION_CONTEXT", text: "My First Battle — Borda Azul" },
  ]);
  // O separador é parâmetro: a estrutura não muda com ele.
  assert.equal(
    formatCardVariantLabel(out, { separator: " / " }),
    "Holográfica / Sem Sombra · Bochecha Vermelha · 1ª Edição / My First Battle — Borda Azul",
  );
  assert.throws(() => formatCardVariantLabel(out, { separator: "" }), TypeError);

  // Ambiguidade de renderização: tuplas de nomes diferentes, mesmo texto com " · ".
  const pAB: CardVariantAxisInput = { id: uuid(501), name: "A · B", displayOrder: 50 };
  const ecC: CardVariantAxisInput = { id: uuid(502), name: "C", displayOrder: 300 };
  const pA: CardVariantAxisInput = { id: uuid(503), name: "A", displayOrder: 51 };
  const ecBC: CardVariantAxisInput = { id: uuid(504), name: "B · C", displayOrder: 310 };
  const amb = build([variant(42, CARD_A, FINISH_HOLO, pAB, ecC), variant(43, CARD_A, FINISH_HOLO, pA, ecBC)]);
  assert.ok(amb.every((v) => !v.admin.labelCollision.collides), "nomes por eixo diferem: não é colisão semântica");
  const rendered = findRenderedLabelCollisions(amb, { separator: SEP });
  assert.deepEqual(rendered.get(uuid(42)), [uuid(43)]);
  assert.deepEqual(rendered.get(uuid(43)), [uuid(42)]);
  assert.equal(findRenderedLabelCollisions(amb, { separator: " | " }).size, 0);
});

// ---------------------------------------------------------------------------
// T8 — Ordenação
// ---------------------------------------------------------------------------

test("T8 — ordem: finish → printing (ausente=0) → EC (ausente=0) → id; variant_order ignorado", () => {
  const out = build([
    variant(58, CARD_A, FINISH_HOLO, null, EC_REWARDS),
    variant(57, CARD_A, FINISH_HOLO, PRINT_FIRST),
    variant(56, CARD_A, FINISH_HOLO),
    variant(55, CARD_A, FINISH_STANDARD, PRINT_UNLIMITED),
  ]);
  assert.deepEqual(ids(out), [uuid(55), uuid(56), uuid(58), uuid(57)]);

  // Empate total nos três eixos (cartas diferentes) → desempate por id.
  const tie = build([variant(62, CARD_B, FINISH_HOLO), variant(61, CARD_A, FINISH_HOLO)]);
  assert.deepEqual(ids(tie), [uuid(61), uuid(62)]);

  // Desempate por id independe de caixa (Postgres devolve minúsculas).
  const [x, y] = tie;
  assert.ok(x && y);
  assert.ok(compareCardVariantDisplay(x, y) < 0);
  assert.equal(compareCardVariantDisplay(x, x), 0);

  // variant_order na entrada não influencia (campo é ignorado).
  const withOrder = [variant(71, CARD_A, FINISH_HOLO), variant(72, CARD_A, FINISH_STANDARD)].map((v, i) => ({
    ...v,
    variantOrder: 100 - i,
  }));
  assert.deepEqual(ids(build(withOrder)), [uuid(72), uuid(71)]);

  // sort não muta a entrada.
  const before = ids(out);
  sortCardVariantDisplays([...out].reverse());
  assert.deepEqual(ids(out), before);
});

// ---------------------------------------------------------------------------
// T9 — Legado (M2: evidência positiva)
// ---------------------------------------------------------------------------

test("T9 — legado: evidência de tipo nunca vira prova individual; finish conhecido; desconhecido; indeterminado", () => {
  // Tipo contaminado com população histórica RETIDA (H6 / H1): pertença individual não provável.
  assert.deepEqual(classifyCardVariantLegacy({ finishCode: "STAFF_HOLO", editionContextProfileId: null }), {
    status: "INDETERMINATE",
    reason: "HISTORICAL_LEGACY_TYPE_MEMBERSHIP_UNPROVEN",
    evidenceRef: "database/proposals/2026-09-18-edition-context-axis/HOLD-MANIFEST.md#H6",
  });
  assert.equal(
    classifyCardVariantLegacy({ finishCode: "PROMO_STAMPED", editionContextProfileId: null }).reason,
    "HISTORICAL_LEGACY_TYPE_MEMBERSHIP_UNPROVEN",
  );
  assert.deepEqual(classifyCardVariantLegacy({ finishCode: "HOLO", editionContextProfileId: null }), {
    status: "NOT_IDENTIFIED_AS_LEGACY",
    reason: "ADJUDICATED_FINISH_CODE",
    evidenceRef: "database/proposals/2026-09-18-edition-context-axis/2213_decompose_legacy_card_variants.sql#PASSO-0C",
  });
  // Código desconhecido NUNCA vira legado.
  assert.deepEqual(classifyCardVariantLegacy({ finishCode: "BRAND_NEW_FINISH", editionContextProfileId: null }), {
    status: "INDETERMINATE",
    reason: "UNKNOWN_CODE",
    evidenceRef: null,
  });
  // Família por prefixo sem nome exato: indeterminado.
  assert.equal(
    classifyCardVariantLegacy({ finishCode: "STANDARDS_WORLDS_2010", editionContextProfileId: null }).reason,
    "UNKNOWN_CODE",
  );
  // Caixa diferente não é o mesmo código.
  assert.equal(classifyCardVariantLegacy({ finishCode: "staff_holo", editionContextProfileId: null }).reason, "UNKNOWN_CODE");
  // Sem code.
  assert.equal(classifyCardVariantLegacy({ finishCode: null, editionContextProfileId: null }).reason, "FINISH_CODE_UNAVAILABLE");
  // SET_LOGO_*: depende do Set; fora de EX7–EX16, ainda assim só evidência de tipo.
  assert.equal(
    classifyCardVariantLegacy({ finishCode: "SET_LOGO_REVERSE", editionContextProfileId: null }).reason,
    "SET_CONTEXT_REQUIRED",
  );
  assert.equal(
    classifyCardVariantLegacy({ finishCode: "SET_LOGO_REVERSE", editionContextProfileId: null, cardSetCode: "EX9" }).reason,
    "EX_ERA_SET_LOGO_UNRESOLVED",
  );
  assert.equal(
    classifyCardVariantLegacy({ finishCode: "SET_LOGO_REVERSE", editionContextProfileId: null, cardSetCode: "SVP" }).reason,
    "HISTORICAL_LEGACY_TYPE_MEMBERSHIP_UNPROVEN",
  );
  // EX1 não é EX1x: o predicado é âncora exata (EX1 fica fora da exceção H2).
  assert.equal(
    classifyCardVariantLegacy({ finishCode: "SET_LOGO_STANDARDS", editionContextProfileId: null, cardSetCode: "EX1" }).reason,
    "HISTORICAL_LEGACY_TYPE_MEMBERSHIP_UNPROVEN",
  );
  // Código legado COM Edition Context: inconsistente → indeterminado.
  assert.equal(
    classifyCardVariantLegacy({ finishCode: "STAFF_HOLO", editionContextProfileId: uuid(301) }).reason,
    "LEGACY_CODE_WITH_EDITION_CONTEXT",
  );

  // Integrado: a classificação vem do code, nunca do rótulo exibido.
  const disguised: CardVariantFinishInput = { id: uuid(601), name: "Holográfica", displayOrder: 70, code: "STAFF_HOLO" };
  const [legacy] = build([variant(81, CARD_A, disguised)]);
  assert.equal(legacy?.admin.legacy.status, "INDETERMINATE");
  assert.equal(legacy?.admin.legacy.reason, "HISTORICAL_LEGACY_TYPE_MEMBERSHIP_UNPROVEN");
  assert.equal(formatCardVariantLabel(legacy as CardVariantDisplay, { separator: SEP }), "Holográfica");
});

test("T9c — adversarial: código histórico reutilizado / população fora do escopo provado nunca é LEGACY_PROVEN", () => {
  // Tipos cuja população foi decomposta INTEIRA pela 2213: uma ocorrência atual
  // (ex.: importação nova reutilizando COSMOS_REWARDS_REVERSE) está fora da prova.
  for (const code of ["COSMOS_REWARDS_REVERSE", "SATANDARD_REWARDS", "PLAYER_REWARD_REVERSE", "W_PROMO_STAMPED"]) {
    assert.deepEqual(
      classifyCardVariantLegacy({ finishCode: code, editionContextProfileId: null }),
      {
        status: "INDETERMINATE",
        reason: "HISTORICAL_LEGACY_TYPE_OUTSIDE_PROVEN_POPULATION",
        evidenceRef: ADJUDICATED_LEGACY_CODES[code] ?? null,
      },
      code,
    );
  }
  // Varredura exaustiva: nenhum código conhecido, em nenhum Set (inclusive
  // vazio/EX/fora de EX) e com ou sem EC, produz LEGACY_PROVEN em F1.
  const codes = [
    ...Object.keys(ADJUDICATED_LEGACY_CODES),
    ...ADJUDICATED_SET_LOGO_CODES,
    ...ADJUDICATED_FINISH_CODES,
    "BRAND_NEW_FINISH",
    "",
  ];
  const sets: Array<string | null | undefined> = [undefined, null, "", "EX7", "EX16", "EX17", "EX1", "SVP", "DP1", "SWSH9", "BASE1"];
  for (const code of codes) {
    for (const cardSetCode of sets) {
      for (const editionContextProfileId of [null, uuid(301)]) {
        const result = classifyCardVariantLegacy({ finishCode: code, editionContextProfileId, cardSetCode });
        assert.notEqual(result.status, "LEGACY_PROVEN", `${code} / ${String(cardSetCode)} / ${String(editionContextProfileId)}`);
        if (ADJUDICATED_FINISH_CODES.includes(code)) assert.equal(result.status, "NOT_IDENTIFIED_AS_LEGACY");
        else assert.equal(result.status, "INDETERMINATE");
      }
    }
  }
  // Código histórico disfarçado com nome de acabamento legítimo, via build.
  const reused: CardVariantFinishInput = { id: uuid(602), name: "Cosmos Reversa", displayOrder: 81, code: "COSMOS_REWARDS_REVERSE" };
  const [out] = build([variant(82, CARD_B, reused)]);
  assert.equal(out?.admin.legacy.reason, "HISTORICAL_LEGACY_TYPE_OUTSIDE_PROVEN_POPULATION");
});

test("T9b — paridade das listas adjudicadas com os artefatos do repositório", () => {
  const here = dirname(fileURLToPath(import.meta.url));
  const axisDir = resolve(here, "../../../database/proposals/2026-09-18-edition-context-axis");
  const sql = readFileSync(resolve(axisDir, "2213_decompose_legacy_card_variants.sql"), "utf8");
  const block = sql.match(/CREATE TEMP TABLE finish_codes[\s\S]*?\) f\(code\);/);
  assert.ok(block, "bloco finish_codes não encontrado na 2213");
  const sqlCodes = [...block[0].matchAll(/\('([A-Z0-9_]+)'\)/g)].map((m) => m[1]);
  assert.deepEqual([...ADJUDICATED_FINISH_CODES].sort(), [...sqlCodes].sort());
  assert.equal(new Set(sqlCodes).size, 28);

  const manifests =
    readFileSync(resolve(axisDir, "HOLD-MANIFEST.md"), "utf8") +
    readFileSync(resolve(axisDir, "MIGRATION-MAP-365.md"), "utf8") +
    sql;
  for (const code of [...Object.keys(ADJUDICATED_LEGACY_CODES), ...ADJUDICATED_SET_LOGO_CODES]) {
    assert.ok(manifests.includes(code), `${code} não consta dos manifestos adjudicados`);
    assert.equal(ADJUDICATED_FINISH_CODES.includes(code), false, `${code} não pode ser FINISH e legado ao mesmo tempo`);
  }
});

// ---------------------------------------------------------------------------
// T10 — Cardinalidade
// ---------------------------------------------------------------------------

test("T10 — N entradas válidas produzem exatamente N saídas, sem deduplicar por nome", () => {
  const sameName: CardVariantAxisInput[] = [1, 2, 3, 4, 5].map((n) => ({
    id: uuid(700 + n),
    name: "Mesmo Nome",
    displayOrder: 400 + n,
  }));
  const input = sameName.map((ec, i) => variant(90 + i, CARD_A, FINISH_HOLO, null, ec));
  const out = build(input);
  assert.equal(out.length, input.length);
  assert.equal(new Set(ids(out)).size, input.length);
  assert.ok(out.every((v) => v.admin.labelCollision.collidingVariantIds.length === 4));
  assert.deepEqual(build([]), []);
});

// ---------------------------------------------------------------------------
// T11 — Determinismo
// ---------------------------------------------------------------------------

test("T11 — mesma entrada semântica, qualquer ordem: resultado idêntico", () => {
  const input = [
    variant(101, CARD_A, FINISH_HOLO, PRINT_FIRST),
    variant(102, CARD_A, FINISH_HOLO),
    variant(103, CARD_A, FINISH_COSMOS_REV, null, EC_PROFESSOR),
    variant(104, CARD_B, FINISH_STANDARD, null, EC_REWARDS),
    variant(105, CARD_B, FINISH_STANDARD, null, { id: uuid(801), name: "Player Rewards", displayOrder: 101 }),
  ];
  const reference = JSON.stringify(build(input));
  for (const seed of [3, 11, 97, 4242]) {
    assert.equal(JSON.stringify(build(shuffled(input, seed))), reference, `seed ${seed}`);
  }
  // A entrada não é mutada.
  const snapshot = JSON.stringify(input);
  build(input);
  assert.equal(JSON.stringify(input), snapshot);
});

// ---------------------------------------------------------------------------
// T12 — Robustez (fail-closed, sem identidade inventada, sem truncamento)
// ---------------------------------------------------------------------------

test("T12 — entradas inválidas rejeitam o lote inteiro com erros tipados, sem exceção", () => {
  const good = variant(201, CARD_A, FINISH_HOLO);

  assert.deepEqual(errorCodes("não é array"), ["INPUT_NOT_ARRAY"]);
  assert.deepEqual(errorCodes([null]), ["INVALID_RECORD"]);
  assert.ok(errorCodes([{ ...good, id: "não-uuid" }]).includes("INVALID_VARIANT_ID"));
  assert.ok(errorCodes([{ ...good, cardId: undefined }]).includes("INVALID_CARD_ID"));
  assert.ok(errorCodes([{ ...good, finish: null }]).includes("FINISH_MISSING"));
  assert.ok(errorCodes([{ ...good, variantTypeId: uuid(999) }]).includes("FINISH_ID_MISMATCH"));
  assert.ok(errorCodes([{ ...good, finish: { ...FINISH_HOLO, name: "   " } }]).includes("INVALID_AXIS_NAME"));
  assert.ok(errorCodes([{ ...good, finish: { ...FINISH_HOLO, displayOrder: 1.5 } }]).includes("INVALID_DISPLAY_ORDER"));
  assert.ok(errorCodes([{ ...good, finish: { ...FINISH_HOLO, code: "" } }]).includes("INVALID_FINISH_CODE"));

  // FK preenchida sem eixo (ex.: RLS) — nunca vira "sem tiragem".
  assert.ok(errorCodes([{ ...good, printingProfileId: PRINT_FIRST.id, printing: null }]).includes("PRINTING_EMBED_MISSING"));
  assert.ok(
    errorCodes([{ ...good, editionContextProfileId: EC_REWARDS.id, editionContext: null }]).includes(
      "EDITION_CONTEXT_EMBED_MISSING",
    ),
  );
  // Eixo sem FK, e eixo com id diferente da FK.
  assert.ok(errorCodes([{ ...good, printing: PRINT_FIRST }]).includes("PRINTING_EMBED_WITHOUT_FK"));
  assert.ok(
    errorCodes([{ ...good, editionContextProfileId: EC_REWARDS.id, editionContext: EC_PROFESSOR }]).includes(
      "EDITION_CONTEXT_ID_MISMATCH",
    ),
  );
  // display_order 0 em perfil real colidiria com a sentinela de ausência.
  assert.ok(
    errorCodes([variant(202, CARD_A, FINISH_HOLO, { ...PRINT_FIRST, displayOrder: 0 })]).includes("INVALID_DISPLAY_ORDER"),
  );
  // FKs obrigatórias como chaves explícitas.
  const { printingProfileId: _omit, ...withoutFk } = good;
  assert.ok(errorCodes([withoutFk]).includes("INVALID_RECORD"));

  // Duplicidades.
  assert.deepEqual(errorCodes([good, { ...good }]), ["DUPLICATE_VARIANT_ID"]);
  assert.deepEqual(errorCodes([good, { ...good, id: good.id.toUpperCase() }]), ["DUPLICATE_VARIANT_ID"]);
  assert.deepEqual(errorCodes([good, { ...good, id: uuid(203) }]), ["DUPLICATE_IDENTITY"]);

  // Um registro ruim invalida o lote: nada parcial é devolvido.
  const mixed = buildCardVariantDisplays([good, variant(204, CARD_A, FINISH_STANDARD), { ...good, id: "x", cardId: "y" }]);
  assert.equal(mixed.ok, false);
  assert.equal("variants" in mixed, false);
  if (!mixed.ok) {
    assert.ok(mixed.errors.every((e) => e.index === 2));
    assert.ok(mixed.errors.every((e) => e.variantId === null), "id inválido nunca é inventado");
  }
});
