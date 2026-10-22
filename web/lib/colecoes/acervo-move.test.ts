// WHERE-05B — mover exemplares em lote a partir da galeria (regras puras).
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-move.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { parseAcervoState } from "./acervo.ts";
import {
  type CandidateCopy,
  MOVE_KEYS_MAX,
  type MoveScope,
  buildMovePlan,
  chunk,
  moveFailureFromWrite,
  moveFailureMessage,
  moveSuccessMessage,
  normalizeMoveKeys,
  pairOrFilter,
  planTokenSource,
  scopeFromSignature,
  scopeOf,
  scopeSignature,
} from "./acervo-move.ts";

const V1 = "11111111-1111-4111-8111-111111111111";
const V2 = "22222222-2222-4222-8222-222222222222";
const L_PT = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const L_EN = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const LOC_A = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const LOC_B = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const COL_1 = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const COL_2 = "ffffffff-ffff-4fff-8fff-ffffffffffff";
const LANGS = new Map([
  ["pt", L_PT],
  ["en", L_EN],
]);

function id(n: number): string {
  return `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
}
function copy(n: number, variant: string, language: string, storage: string | null): CandidateCopy {
  return { id: id(n), cardVariantId: variant, languageId: language, storageContainerId: storage };
}
function scope(params: Record<string, string> = {}): MoveScope {
  return scopeOf(parseAcervoState(params));
}

const K1 = { cardVariantId: V1, languageCode: "pt" };
const K2 = { cardVariantId: V2, languageCode: "en" };

// ---------------------------------------------------------------- escopo
test("assinatura do escopo ignora ordem, página e detalhe", () => {
  const a = scopeSignature(scope({ q: "pikachu", local: LOC_A, ordem: "set", pagina: "3" }));
  const b = scopeSignature(scope({ q: "pikachu", local: LOC_A, carta: `${V1}.pt` }));
  assert.equal(a, b);
  assert.notEqual(a, scopeSignature(scope({ q: "pikachu" })));
  assert.notEqual(a, scopeSignature(scope({ q: "raichu", local: LOC_A })));
});

test("assinatura muda com coleção, idioma e Set", () => {
  const base = scopeSignature(scope());
  const extras: Record<string, string>[] = [{ colecao: COL_1 }, { colecao: "sem" }, { idioma: "pt" }, { set: "sv1" }, { local: "sem" }];
  for (const extra of extras) {
    assert.notEqual(scopeSignature(scope(extra)), base);
  }
});

test("servidor só aceita escopo canônico", () => {
  const sig = scopeSignature(scope({ local: LOC_A, colecao: COL_1 }));
  assert.deepEqual(scopeFromSignature(sig), scope({ local: LOC_A, colecao: COL_1 }));
  assert.deepEqual(scopeFromSignature(""), scope());
  assert.equal(scopeFromSignature("local=nao-e-uuid"), null);
  assert.equal(scopeFromSignature(`${sig}&pagina=2`), null);
  assert.equal(scopeFromSignature(`${sig}&local=${LOC_B}`), null);
  assert.equal(scopeFromSignature(42), null);
});

// ---------------------------------------------------------------- chaves
test("chaves: válidas, distintas, até 500", () => {
  assert.deepEqual(normalizeMoveKeys([`${V1}.pt`, `${V1}.pt`, `${V2}.en`]), [K1, K2]);
  assert.equal(normalizeMoveKeys([]), null);
  assert.equal(normalizeMoveKeys([`${V1}.pt`, "lixo"]), null);
  assert.equal(normalizeMoveKeys([V1]), null);
  assert.equal(normalizeMoveKeys("x"), null);
  const many = Array.from({ length: MOVE_KEYS_MAX + 1 }, (_, i) => `${id(i)}.pt`);
  assert.equal(normalizeMoveKeys(many), null);
  assert.equal(normalizeMoveKeys(many.slice(0, MOVE_KEYS_MAX))?.length, MOVE_KEYS_MAX);
});

test("filtro de pares exatos, nunca produto cartesiano", () => {
  assert.equal(
    pairOrFilter([
      { cardVariantId: V1, languageId: L_PT },
      { cardVariantId: V2, languageId: L_EN },
    ]),
    `and(card_variant_id.eq.${V1},language_id.eq.${L_PT}),and(card_variant_id.eq.${V2},language_id.eq.${L_EN})`,
  );
  assert.deepEqual(chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
});

// ---------------------------------------------------------------- plano
test("sem filtros: todos os exemplares dos pares exatos; idioma errado fica de fora", () => {
  const plan = buildMovePlan({
    keys: [K1],
    languageIdByCode: LANGS,
    candidates: [copy(1, V1, L_PT, null), copy(2, V1, L_PT, LOC_A), copy(3, V1, L_EN, null)],
    allocationByCopy: null,
    scope: scope(),
    target: LOC_B,
  });
  assert.deepEqual(plan.toMove, [id(1), id(2)]);
  assert.equal(plan.fromNone, 1);
  assert.equal(plan.fromOther, 1);
  assert.equal(plan.atTarget, 0);
  assert.deepEqual(plan.unresolvedKeys, []);
});

test("filtro por local: só os exemplares daquele local", () => {
  const plan = buildMovePlan({
    keys: [K1],
    languageIdByCode: LANGS,
    candidates: [copy(1, V1, L_PT, LOC_A), copy(2, V1, L_PT, LOC_B), copy(3, V1, L_PT, null)],
    allocationByCopy: null,
    scope: scope({ local: LOC_A }),
    target: null,
  });
  assert.deepEqual(plan.toMove, [id(1)]);
});

test("filtro sem local: só os sem local", () => {
  const plan = buildMovePlan({
    keys: [K1],
    languageIdByCode: LANGS,
    candidates: [copy(1, V1, L_PT, LOC_A), copy(2, V1, L_PT, null)],
    allocationByCopy: null,
    scope: scope({ local: "sem" }),
    target: LOC_B,
  });
  assert.deepEqual(plan.toMove, [id(2)]);
});

test("filtro por coleção e sem coleção", () => {
  const candidates = [copy(1, V1, L_PT, null), copy(2, V1, L_PT, null), copy(3, V1, L_PT, null)];
  const allocations = new Map([
    [id(1), COL_1],
    [id(2), COL_2],
  ]);
  const inCol = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates, allocationByCopy: allocations, scope: scope({ colecao: COL_1 }), target: LOC_A });
  assert.deepEqual(inCol.toMove, [id(1)]);
  const none = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates, allocationByCopy: allocations, scope: scope({ colecao: "sem" }), target: LOC_A });
  assert.deepEqual(none.toMove, [id(3)]);
});

test("filtro de coleção sem leitura de alocações → nada entra (fail-closed)", () => {
  const plan = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates: [copy(1, V1, L_PT, null)], allocationByCopy: null, scope: scope({ colecao: COL_1 }), target: LOC_A });
  assert.equal(plan.copies.length, 0);
  assert.deepEqual(plan.unresolvedKeys, [`${V1}.pt`]);
});

test("filtros combinados (AND): coleção + local + idioma", () => {
  const candidates = [copy(1, V1, L_PT, LOC_A), copy(2, V1, L_PT, LOC_B), copy(3, V1, L_PT, LOC_A)];
  const allocations = new Map([
    [id(1), COL_1],
    [id(2), COL_1],
  ]);
  const plan = buildMovePlan({
    keys: [K1, K2],
    languageIdByCode: LANGS,
    candidates,
    allocationByCopy: allocations,
    scope: scope({ colecao: COL_1, local: LOC_A, idioma: "pt" }),
    target: LOC_B,
  });
  assert.deepEqual(plan.toMove, [id(1)]);
  // K2 (en) não pertence ao recorte de idioma pt: não resolvida, nunca excluída em silêncio.
  assert.deepEqual(plan.unresolvedKeys, [`${V2}.en`]);
});

test("chaves não resolvidas: idioma desconhecido e item sem exemplares", () => {
  const plan = buildMovePlan({
    keys: [K1, { cardVariantId: V2, languageCode: "ja" }],
    languageIdByCode: LANGS,
    candidates: [],
    allocationByCopy: null,
    scope: scope(),
    target: LOC_A,
  });
  assert.deepEqual(plan.unresolvedKeys.sort(), [`${V1}.pt`, `${V2}.ja`].sort());
});

test("já no destino e destino nulo", () => {
  const candidates = [copy(1, V1, L_PT, LOC_A), copy(2, V1, L_PT, null)];
  const toA = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates, allocationByCopy: null, scope: scope(), target: LOC_A });
  assert.equal(toA.atTarget, 1);
  assert.deepEqual(toA.toMove, [id(2)]);
  const clear = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates, allocationByCopy: null, scope: scope(), target: null });
  assert.equal(clear.atTarget, 1);
  assert.deepEqual(clear.toMove, [id(1)]);
  assert.equal(clear.fromOther, 1);
  const nothing = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates: [copy(1, V1, L_PT, LOC_A)], allocationByCopy: null, scope: scope(), target: LOC_A });
  assert.equal(nothing.toMove.length, 0);
  assert.equal(nothing.atTarget, 1);
});

test("duplicatas entre blocos de leitura não contam duas vezes", () => {
  const plan = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates: [copy(1, V1, L_PT, null), copy(1, V1, L_PT, null)], allocationByCopy: null, scope: scope(), target: LOC_A });
  assert.equal(plan.copies.length, 1);
  assert.equal(plan.perKey[`${V1}.pt`], 1);
});

test("500 cabem; 501 é responsabilidade do servidor (plano expõe o tamanho real)", () => {
  const make = (n: number) => Array.from({ length: n }, (_, i) => copy(i + 1, V1, L_PT, null));
  const p500 = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates: make(500), allocationByCopy: null, scope: scope(), target: LOC_A });
  assert.equal(p500.copies.length, 500);
  const p501 = buildMovePlan({ keys: [K1], languageIdByCode: LANGS, candidates: make(501), allocationByCopy: null, scope: scope(), target: LOC_A });
  assert.equal(p501.copies.length, 501);
});

// ---------------------------------------------------------------- token
test("token muda com exemplar a mais, a menos, movido, destino ou escopo", () => {
  const base = { target: LOC_A, scopeSignature: "", keys: [K1], copies: [copy(1, V1, L_PT, null), copy(2, V1, L_PT, LOC_B)] };
  const t = planTokenSource(base);
  assert.equal(planTokenSource({ ...base, copies: [...base.copies].reverse(), keys: [K1, K1] }) === t, false); // chaves repetidas mudam a linha
  assert.equal(planTokenSource({ ...base, copies: [...base.copies].reverse() }), t); // ordem não importa
  assert.notEqual(planTokenSource({ ...base, copies: [...base.copies, copy(3, V1, L_PT, null)] }), t);
  assert.notEqual(planTokenSource({ ...base, copies: [base.copies[0] as CandidateCopy] }), t);
  assert.notEqual(planTokenSource({ ...base, copies: [copy(1, V1, L_PT, LOC_A), copy(2, V1, L_PT, LOC_B)] }), t);
  assert.notEqual(planTokenSource({ ...base, target: null }), t);
  assert.notEqual(planTokenSource({ ...base, scopeSignature: "idioma=pt" }), t);
});

// ---------------------------------------------------------------- falhas
test("erros da 5024: banco → definitivo; sem código → desconhecido", () => {
  assert.equal(moveFailureFromWrite({ code: "P0001", message: "um ou mais physical_card_ids não pertencem ao inventory do chamador" }), "plan_changed");
  assert.equal(moveFailureFromWrite({ code: "P0001", message: "storage container not found" }), "storage_gone");
  assert.equal(moveFailureFromWrite({ code: "23503", message: "fk" }), "storage_gone");
  assert.equal(moveFailureFromWrite({ code: "P0001", message: "authentication required" }), "not_authenticated");
  assert.equal(moveFailureFromWrite({ code: "P0001", message: "lote excede 500" }), "too_large");
  assert.equal(moveFailureFromWrite({ code: "57014", message: "canceling statement due to statement timeout" }), "unavailable");
  assert.equal(moveFailureFromWrite({ code: "", message: "TypeError: fetch failed" }), "unknown");
  assert.equal(moveFailureFromWrite(null), "unknown");
  for (const reason of ["unknown", "plan_changed", "too_large", "empty", "unresolved"] as const) {
    assert.ok(moveFailureMessage(reason).length > 10);
  }
});

test("mensagem de sucesso", () => {
  assert.equal(moveSuccessMessage(3, "Fichário", 0), "3 exemplares movidos para “Fichário”. Nenhuma carta mudou de coleção.");
  assert.equal(moveSuccessMessage(1, null, 2), "1 exemplar ficou sem localização definida. 2 já estavam lá. Nenhuma carta mudou de coleção.");
});
