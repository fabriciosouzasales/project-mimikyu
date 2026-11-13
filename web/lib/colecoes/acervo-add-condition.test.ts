import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  type DraftLine,
  type RegisterItem,
  addLine,
  canonicalRegisterItems,
  classifyFailure,
  confirmCardsRequest,
  failureMessage,
  issueMessage,
  lineKey,
  confirmSetRequest,
  previewCardsRequest,
  previewSetRequest,
  setRequestCondition,
  toRegisterItems,
  updateLine,
  validRegisterItems,
} from "./acervo-add.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");

const V1 = "11111111-1111-4111-8111-111111111111";
const V2 = "22222222-2222-4222-8222-222222222222";
const PT = "33333333-3333-4333-8333-333333333333";
const EN = "44444444-4444-4444-8444-444444444444";
const KEY = "55555555-5555-4555-8555-555555555555";

function line(overrides: Partial<DraftLine> = {}): DraftLine {
  return {
    cardId: "c1",
    cardName: "Pikachu",
    setCode: "base1",
    setName: "Base",
    collectorNumber: "58",
    collectorTotal: 102,
    imageUrl: null,
    variantId: V1,
    variantLabel: null,
    isDefaultVariant: true,
    languageId: PT,
    quantity: 1,
    conditionCode: "NM",
    ...overrides,
  };
}

// ---- identidade da linha: variante + idioma + condição ----

test("lineKey: variante + idioma + condição", () => {
  assert.equal(lineKey(line()), `${V1}:${PT}:NM`);
  assert.notEqual(lineKey(line()), lineKey(line({ conditionCode: "LP" })));
});

test("addLine: mesma variante+idioma em condições DIFERENTES são linhas distintas", () => {
  const lines = addLine(addLine([], line()), line({ conditionCode: "LP", quantity: 2 }));
  assert.equal(lines.length, 2);
  assert.deepEqual(lines.map((l) => [l.conditionCode, l.quantity]), [["NM", 1], ["LP", 2]]);
});

test("addLine: os TRÊS atributos iguais → funde somando quantidades", () => {
  const lines = addLine(addLine([], line({ conditionCode: "MP" })), line({ conditionCode: "MP", quantity: 3 }));
  assert.equal(lines.length, 1);
  assert.equal(lines[0]?.quantity, 4);
  assert.equal(lines[0]?.conditionCode, "MP");
});

test("updateLine: trocar a condição para a de outra linha igual funde; para uma nova, não", () => {
  const lines = [line({ quantity: 1 }), line({ conditionCode: "LP", quantity: 2 }), line({ languageId: EN, quantity: 5 })];
  const merged = updateLine(lines, 1, { conditionCode: "NM" });
  assert.equal(merged.length, 2);
  assert.deepEqual([merged[0]?.conditionCode, merged[0]?.quantity], ["NM", 3], "funde na posição da primeira");
  const distinct = updateLine(lines, 0, { conditionCode: "HP" });
  assert.equal(distinct.length, 3);
  assert.equal(distinct[0]?.conditionCode, "HP");
  // Mesmo trio de idioma diferente não funde.
  assert.equal(updateLine(lines, 2, { conditionCode: "LP" }).length, 3);
});

// ---- payload: NM omitido (histórico), demais enviados ----

test("toRegisterItems: NM (padrão ou escolhido) é omitido; os demais códigos vão como condition_code", () => {
  const items = toRegisterItems([
    line(),
    line({ variantId: V2, conditionCode: "NM" }),
    line({ conditionCode: "M" }),
    line({ languageId: EN, conditionCode: "LP" }),
    line({ variantId: V2, languageId: EN, conditionCode: "MP" }),
    line({ variantId: V2, conditionCode: "HP" }),
    line({ variantId: V2, conditionCode: "DMG", languageId: EN }),
  ]);
  assert.deepEqual(items[0], { card_variant_id: V1, language_id: PT, quantity: 1 });
  assert.deepEqual(items[1], { card_variant_id: V2, language_id: PT, quantity: 1 });
  assert.ok(!("condition_code" in (items[0] ?? {})), "sem a chave — não é condition_code: undefined");
  assert.deepEqual(
    items.slice(2).map((i) => i.condition_code),
    ["M", "LP", "MP", "HP", "DMG"],
    "código canônico (LP/DMG), nunca o rótulo SP/DM",
  );
});

test("pedido só com NM é byte a byte o histórico (prévia e confirmação)", () => {
  const items = toRegisterItems([line({ quantity: 2 }), line({ variantId: V2, conditionCode: "NM" })]);
  assert.equal(
    JSON.stringify(previewCardsRequest(items)),
    JSON.stringify({
      operation_type: "REGISTER_PHYSICAL_CARDS",
      items: [
        { card_variant_id: V1, language_id: PT, quantity: 2 },
        { card_variant_id: V2, language_id: PT, quantity: 1 },
      ],
      collection_id: null,
      storage_container_id: null,
    }),
  );
  assert.equal(
    JSON.stringify(confirmCardsRequest(KEY, "fp", items)),
    JSON.stringify({
      idempotency_key: KEY,
      preview_fingerprint: "fp",
      items: [
        { card_variant_id: V1, language_id: PT, quantity: 2 },
        { card_variant_id: V2, language_id: PT, quantity: 1 },
      ],
      collection_id: null,
      storage_container_id: null,
    }),
  );
});

test("canonicalRegisterItems (servidor): só NM explícito sai; não-NM canônicos seguem; ordem e demais campos intactos", () => {
  const raw = [
    { card_variant_id: V1, language_id: PT, quantity: 1, condition_code: "NM" as const },
    { card_variant_id: V2, language_id: PT, quantity: 2, condition_code: "LP" as const },
    { card_variant_id: V2, language_id: EN, quantity: 1 },
  ];
  const out = canonicalRegisterItems(raw);
  assert.equal(
    JSON.stringify(out),
    JSON.stringify([
      { card_variant_id: V1, language_id: PT, quantity: 1 },
      { card_variant_id: V2, language_id: PT, quantity: 2, condition_code: "LP" },
      { card_variant_id: V2, language_id: EN, quantity: 1 },
    ]),
    "NM explícito vira o item histórico (sem a chave), byte a byte",
  );
  for (const code of ["M", "LP", "MP", "HP", "DMG"] as const) {
    assert.deepEqual(canonicalRegisterItems([{ card_variant_id: V1, language_id: PT, quantity: 3, condition_code: code }]), [
      { card_variant_id: V1, language_id: PT, quantity: 3, condition_code: code },
    ]);
  }
  assert.notEqual(out[0], raw[0], "não muta a entrada");
  assert.equal(raw[0]?.condition_code, "NM");
});

test("propriedades desconhecidas NÃO são descartadas: seguem para o banco, que as recusa como antes do V1-16", () => {
  const withExtra = [{ card_variant_id: V1, language_id: PT, quantity: 1, extra: "x" } as unknown as RegisterItem];
  // A validação de formato do servidor continua como era (não olha chaves extras)…
  assert.equal(validRegisterItems(withExtra), true);
  // …e a normalização as repassa intactas — inclusive junto de NM explícito.
  assert.deepEqual(canonicalRegisterItems(withExtra), withExtra);
  const extraNm = [{ card_variant_id: V1, language_id: PT, quantity: 1, condition_code: "NM", extra: "x" } as unknown as RegisterItem];
  assert.deepEqual(canonicalRegisterItems(extraNm), [{ card_variant_id: V1, language_id: PT, quantity: 1, extra: "x" }]);
  // Recusa do banco ("cada item de items aceita exatamente as chaves…", 22023) → mesma falha de antes.
  assert.equal(classifyFailure("22023", "cada item de items aceita exatamente as chaves card_variant_id, language_id, quantity e condition_code (opcional)"), "invalid");
});

test("códigos inválidos continuam recusados antes do banco (a normalização só roda depois da validação)", () => {
  for (const bad of ["SP", "DM", "nm", "XX", ""]) {
    assert.equal(validRegisterItems([{ card_variant_id: V1, language_id: PT, quantity: 1, condition_code: bad }]), false, bad);
  }
  const actions = read("app/colecoes/acervo/actions.ts");
  const previewBody = actions.slice(actions.indexOf("export async function previewAddCards"), actions.indexOf("export async function confirmAddCards"));
  assert.ok(previewBody.indexOf("validRegisterItems(items)") < previewBody.indexOf("canonicalRegisterItems(items)"));
  const confirmBody = actions.slice(actions.indexOf("export async function confirmAddCards"), actions.indexOf("export async function previewAddSet"));
  assert.ok(confirmBody.indexOf("validRegisterItems(input.items)") < confirmBody.indexOf("canonicalRegisterItems(input.items)"));
});

test("validRegisterItems: condição opcional só com os seis códigos; duplicidade pelo trio (ausente ≡ NM)", () => {
  assert.equal(validRegisterItems([{ card_variant_id: V1, language_id: PT, quantity: 1, condition_code: "LP" }]), true);
  for (const bad of ["SP", "DM", "nm", "", "XX", 3, null]) {
    assert.equal(validRegisterItems([{ card_variant_id: V1, language_id: PT, quantity: 1, condition_code: bad }]), false, String(bad));
  }
  // Mesma variante+idioma em condições diferentes: válido (linhas legítimas).
  assert.equal(
    validRegisterItems([
      { card_variant_id: V1, language_id: PT, quantity: 1 },
      { card_variant_id: V1, language_id: PT, quantity: 1, condition_code: "LP" },
    ]),
    true,
  );
  // Ausente + NM explícito = o mesmo trio → duplicata (como o banco).
  assert.equal(
    validRegisterItems([
      { card_variant_id: V1, language_id: PT, quantity: 1 },
      { card_variant_id: V1, language_id: PT, quantity: 1, condition_code: "NM" },
    ]),
    false,
  );
});

// ---- CONDITION_NOT_FOUND sem mexer nas mensagens anteriores ----

test("CONDITION_NOT_FOUND: falha e issue próprias; mensagens anteriores intactas", () => {
  assert.equal(classifyFailure("22023", "CONDITION_NOT_FOUND: 1 condition_code inexistente(s) na escala canonica: XX"), "invalid_condition");
  assert.equal(classifyFailure("22023", "condition_code, quando informado, deve ser uma string nao vazia"), "invalid_condition");
  assert.match(failureMessage("invalid_condition"), /condição/i);
  assert.match(issueMessage({ code: "CONDITION_NOT_FOUND", count: 1 }), /condições escolhidas não é válida/);
  // Anteriores: mesma classificação e mesmo texto.
  assert.equal(classifyFailure("22023", "PREVIEW_STALE: o estado mudou"), "stale");
  assert.equal(classifyFailure("22023", "items contem 1 item(ns) (card_variant_id, language_id, condition_code) duplicado(s)"), "invalid");
  assert.equal(classifyFailure("22023", "a operacao criaria 1001 Physical Cards e excede o limite de 1000 por chamada"), "too_many");
  assert.equal(failureMessage("invalid"), "Não conseguimos entender este pedido. Revise a seleção e tente de novo.");
  assert.equal(issueMessage({ code: "DUPLICATE_ITEM", count: 1 }), "A mesma carta aparece repetida na seleção.");
});

// ---- guardas de fonte ----

test("painel: Condição por linha (NM padrão, mapa canônico), chave pelo trio, condição na revisão; Set e +1 intocados", () => {
  const src = read("components/colecoes/acervo/acervo-add.tsx");
  assert.match(src, /conditionCode: DEFAULT_CARD_CONDITION,/, "carta nova entra em NM");
  assert.match(src, /<label htmlFor=\{`\$\{id\}-condition`\} className=\{styles\.fieldLabel\}>\s*Condição/);
  assert.match(src, /cardConditionOptions\(\)\.map/);
  assert.match(src, /if \(isCardConditionCode\(value\)\) onChange\(\{ conditionCode: value \}\);/);
  assert.equal(src.match(/key=\{lineKey\(line\)\}/g)?.length, 2, "seleção e revisão");
  assert.match(src, /cardConditionLabel\(line\.conditionCode\)\?\.short/);
  const actions = read("app/colecoes/acervo/actions.ts");
  assert.match(actions, /preview\(previewCardsRequest\(canonicalRegisterItems\(items\), target, storage\)\)/);
  assert.match(actions, /confirmCardsRequest\(input\.idempotencyKey, input\.fingerprint, canonicalRegisterItems\(input\.items\), target, storage\)/);
  const plusOne = actions.slice(actions.indexOf("export async function addMyCopies"), actions.indexOf("export async function removeMyCopies"));
  assert.doesNotMatch(plusOne, /condition|canonicalRegisterItems/, "+1 intocado (NM por omissão)");
});

// ---- FRONTEND-04: condição do Set inteiro (B2) ----

const SET = "66666666-6666-4666-8666-666666666666";
const COL = "77777777-7777-4777-8777-777777777777";
const STO = "88888888-8888-4888-8888-888888888888";

test("setRequestCondition: ausente/null/NM → sem a chave; cinco códigos não-NM → canônico; resto → recusa", () => {
  assert.equal(setRequestCondition(undefined), null);
  assert.equal(setRequestCondition(null), null);
  assert.equal(setRequestCondition("NM"), null, "NM explícito também é omitido");
  for (const code of ["M", "LP", "MP", "HP", "DMG"]) assert.equal(setRequestCondition(code), code);
  for (const bad of ["SP", "DM", "nm", "", "XX", 3, {}]) assert.equal(setRequestCondition(bad), false, String(bad));
});

test("Set com NM (padrão ou explícito): prévia e confirmação byte a byte iguais às históricas", () => {
  const historicPreview = JSON.stringify({
    operation_type: "REGISTER_CARD_SET",
    card_set_id: SET,
    language_id: PT,
    collection_id: COL,
    storage_container_id: STO,
  });
  const historicConfirm = JSON.stringify({
    idempotency_key: KEY,
    preview_fingerprint: "fp",
    card_set_id: SET,
    language_id: PT,
    collection_id: COL,
    storage_container_id: STO,
  });
  for (const condition of [undefined, null, setRequestCondition("NM") || null]) {
    assert.equal(JSON.stringify(previewSetRequest(SET, PT, COL, STO, condition ?? null)), historicPreview);
    assert.equal(JSON.stringify(confirmSetRequest(KEY, "fp", SET, PT, COL, STO, condition ?? null)), historicConfirm);
  }
  assert.equal(JSON.stringify(previewSetRequest(SET, PT, COL, STO)), historicPreview, "chamada antiga (sem o parâmetro)");
  assert.equal(JSON.stringify(confirmSetRequest(KEY, "fp", SET, PT, COL, STO)), historicConfirm);
});

test("Set com condição não-NM: condition_code canônico no nível do pedido, igual na prévia e na confirmação", () => {
  for (const code of ["M", "LP", "MP", "HP", "DMG"] as const) {
    const preview = previewSetRequest(SET, EN, null, null, code);
    const confirm = confirmSetRequest(KEY, "fp", SET, EN, null, null, code);
    assert.equal(preview.condition_code, code);
    assert.equal(confirm.condition_code, code);
    assert.equal(Object.keys(preview).at(-1), "condition_code", "acrescentada ao fim; demais chaves na ordem histórica");
    // Mesmo contrato nas duas: tirando o que só a confirmação tem, os campos coincidem.
    const { idempotency_key: _k, preview_fingerprint: _f, ...confirmFields } = confirm;
    const { operation_type: _o, ...previewFields } = preview;
    assert.deepEqual(confirmFields, previewFields);
  }
});

test("actions do Set: condição validada antes do banco (inválida → invalid_condition); mesma condição na prévia e na confirmação", () => {
  const actions = read("app/colecoes/acervo/actions.ts");
  const previewBody = actions.slice(actions.indexOf("export async function previewAddSet"), actions.indexOf("export async function confirmAddSet"));
  assert.match(previewBody, /const condition = setRequestCondition\(input\?\.conditionCode\);/);
  assert.match(previewBody, /if \(condition === false\) return \{ ok: false, reason: "invalid_condition" \};\s*return preview\(previewSetRequest\(input\.cardSetId, input\.languageId, target, storage, condition\)\);/);
  const confirmBody = actions.slice(actions.indexOf("export async function confirmAddSet"), actions.indexOf("export async function removeMyCopy("));
  assert.match(confirmBody, /if \(condition === false\) return \{ ok: false, reason: "invalid_condition" \};/);
  assert.match(confirmBody, /confirmSetRequest\(input\.idempotencyKey, input\.fingerprint, input\.cardSetId, input\.languageId, target, storage, condition\)/);
  // Erros e mensagens anteriores do Set preservados.
  assert.equal(classifyFailure("22023", "card set not found"), "set_not_found");
  assert.equal(classifyFailure("22023", "card set has no active cards"), "set_empty");
  assert.equal(classifyFailure("22023", "CARD_DEFAULT_VARIANT_MISSING: 2 card(s) sem variante padrao"), "default_variant_missing");
  assert.equal(classifyFailure("22023", "p_request aceita exatamente as chaves idempotency_key, preview_fingerprint, card_set_id, language_id, collection_id, storage_container_id e condition_code (opcional)"), "invalid", "chave desconhecida recusada pelo banco, como antes");
});

test("painel do Set: um campo Condição (NM padrão, mapa canônico), enviado na prévia e na confirmação, exibido na revisão", () => {
  const src = read("components/colecoes/acervo/acervo-add.tsx");
  const setFlow = src.slice(src.indexOf("function SetFlow"));
  assert.match(setFlow, /useState<CardConditionCode>\(DEFAULT_CARD_CONDITION\)/);
  assert.match(setFlow, /<label htmlFor=\{conditionFieldId\} className=\{styles\.sectionTitle\}>\s*Condição das cartas/);
  assert.match(setFlow, /cardConditionOptions\(\)\.map/);
  assert.match(setFlow, /if \(isCardConditionCode\(value\)\) setConditionCode\(value\);/);
  assert.match(setFlow, /previewAddSet\(\{ cardSetId, languageId, collectionId, storageId, conditionCode \}\)/);
  assert.match(setFlow, /confirmAddSet\(\{ idempotencyKey: key, fingerprint, cardSetId, languageId, collectionId, storageId, conditionCode \}\)/);
  assert.match(setFlow, /na condição\{" "\}\s*<strong>\{cardConditionLabel\(conditionCode\)\?\.label \?\? conditionCode\}<\/strong>/);
});
