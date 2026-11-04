/**
 * V1-11 W7 — faltantes em lote: regras puras + verificação estática da 5352.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  BULK_WISH_LIMIT,
  type BulkItem,
  type BulkPosition,
  buildBulkItems,
  bulkAddHeadline,
  bulkCounts,
  bulkPlan,
  candidateVariants,
  chooseBulkVariant,
  classifyBulkItem,
  parseBulkSelectionRequests,
  parseCatalogVariantsByCard,
  resolveBulkConfirmation,
  selectAllDirect,
  summarizeBulkConfirmation,
  summarizeBulkAdd,
  toggleBulkItem,
} from "./wishlist-bulk.ts";
import { ANY_FINISH, wishPositionKey } from "./wishlist.ts";

const C1 = "11111111-1111-4111-8111-111111111111";
const C2 = "22222222-2222-4222-8222-222222222222";
const C3 = "33333333-3333-4333-8333-333333333333";
const C4 = "44444444-4444-4444-8444-444444444444";
const V1 = "aaaaaaaa-0000-4000-8000-000000000001";
const V2A = "aaaaaaaa-0000-4000-8000-000000000002";
const V2B = "aaaaaaaa-0000-4000-8000-000000000003";
const V3 = "aaaaaaaa-0000-4000-8000-000000000004";
const NORMAL = "bbbbbbbb-0000-4000-8000-000000000001";
const HOLO = "bbbbbbbb-0000-4000-8000-000000000002";

const rows = [
  { card_id: C1, card_variant_id: V1, variant_type_id: NORMAL, is_default_variant: true, variant_label: "Normal" },
  { card_id: C2, card_variant_id: V2A, variant_type_id: NORMAL, is_default_variant: true, variant_label: "Normal" },
  { card_id: C2, card_variant_id: V2B, variant_type_id: HOLO, is_default_variant: false, variant_label: "Holo Reversa" },
  { card_id: C3, card_variant_id: V3, variant_type_id: HOLO, is_default_variant: true, variant_label: "Holo" },
  { card_id: C3, card_variant_id: "não-uuid", variant_type_id: HOLO, is_default_variant: false, variant_label: "x" },
];

function setPosition(cardId: string): BulkPosition {
  return { key: cardId, cardId, cardName: `Carta ${cardId.slice(0, 1)}`, collectorNumber: "001", collectorTotal: 100, imagePath: null, finishKey: null, finishLabel: null, isSecret: false };
}
function masterPosition(cardId: string, finishKey: string): BulkPosition {
  return { ...setPosition(cardId), key: `${cardId}:${finishKey}`, finishKey, finishLabel: finishKey === ANY_FINISH ? "Qualquer acabamento" : "Acab." };
}

const byCard = parseCatalogVariantsByCard(rows);

test("W7: linhas da 5352 → carta → variantes; linha fora do contrato é descartada", () => {
  assert.ok(byCard);
  assert.deepEqual(byCard.get(C2)?.map((v) => [v.variantId, v.variantTypeId, v.isDefault]), [
    [V2A, NORMAL, true],
    [V2B, HOLO, false],
  ]);
  assert.equal(byCard.get(C3)?.length, 1);
  assert.equal(parseCatalogVariantsByCard(null), null);
});

test("W7 Set: carta com uma variante = direta; com várias = escolha; sem variante = nenhuma", () => {
  assert.ok(byCard);
  const items = buildBulkItems([setPosition(C1), setPosition(C2), setPosition(C4)], byCard, { cards: new Set(), positions: null });
  assert.deepEqual(items.map((i) => i.state), ["direct", "choose", "none"]);
  assert.equal(classifyBulkItem([], false), "none");
});

test("W7 Set: carta que já tem desejo vai para 'já na lista' e nunca entra no lote", () => {
  assert.ok(byCard);
  const items = buildBulkItems([setPosition(C1), setPosition(C2)], byCard, { cards: new Set([C1]), positions: null });
  assert.deepEqual(items.map((i) => i.state), ["wished", "choose"]);
  const selection = toggleBulkItem(new Map(), items[0] as BulkItem);
  assert.equal(selection.size, 0);
  assert.deepEqual(bulkPlan(items, new Map([[C1, V1]])).variantIds, []);
});

test("W7 Master Set: candidatas só do acabamento da posição; secreta aceita qualquer acabamento", () => {
  assert.ok(byCard);
  assert.deepEqual(candidateVariants(masterPosition(C2, NORMAL), byCard).map((o) => o.variantId), [V2A]);
  assert.deepEqual(candidateVariants(masterPosition(C2, HOLO), byCard).map((o) => o.variantId), [V2B]);
  assert.deepEqual(candidateVariants(masterPosition(C2, ANY_FINISH), byCard).map((o) => o.variantId), [V2A, V2B]);
  // Acabamento sem variante ativa: nada a desejar (nunca outro acabamento no lugar).
  assert.deepEqual(candidateVariants(masterPosition(C1, HOLO), byCard), []);
  const items = buildBulkItems(
    [masterPosition(C2, NORMAL), masterPosition(C2, ANY_FINISH), masterPosition(C1, HOLO), masterPosition(C3, HOLO)],
    byCard,
    { cards: null, positions: new Set([wishPositionKey(C3, HOLO)]) },
  );
  assert.deepEqual(items.map((i) => i.state), ["direct", "choose", "none", "wished"]);
});

test("W7: nada vem marcado; nenhum item selecionado = nada a gravar", () => {
  assert.ok(byCard);
  const items = buildBulkItems([setPosition(C1), setPosition(C2)], byCard, { cards: new Set(), positions: null });
  assert.deepEqual(bulkPlan(items, new Map()), { variantIds: [], ready: 0, pendingChoice: 0 });
});

test("W7: um e vários itens; desmarcar (cancelar a escolha) tira do lote", () => {
  assert.ok(byCard);
  const items = buildBulkItems([setPosition(C1), setPosition(C3)], byCard, { cards: new Set(), positions: null });
  let selection = toggleBulkItem(new Map(), items[0] as BulkItem);
  assert.deepEqual(bulkPlan(items, selection).variantIds, [V1]);
  selection = toggleBulkItem(selection, items[1] as BulkItem);
  assert.deepEqual(bulkPlan(items, selection).variantIds.sort(), [V1, V3].sort());
  selection = toggleBulkItem(selection, items[0] as BulkItem);
  assert.deepEqual(bulkPlan(items, selection).variantIds, [V3]);
});

test("W7: 'Marcar todas' só marca as prontas, nunca as ambíguas (variante não é presumida)", () => {
  assert.ok(byCard);
  const items = buildBulkItems([setPosition(C1), setPosition(C2), setPosition(C3)], byCard, { cards: new Set(), positions: null });
  const selection = selectAllDirect(new Map(), items);
  assert.deepEqual([...selection.keys()].sort(), [C1, C3].sort());
  assert.equal(bulkPlan(items, selection).pendingChoice, 0);
});

test("W7: ambígua marcada sem variante fica pendente e bloqueia; escolher a variante a libera", () => {
  assert.ok(byCard);
  const items = buildBulkItems([setPosition(C2)], byCard, { cards: new Set(), positions: null });
  const item = items[0] as BulkItem;
  let selection = toggleBulkItem(new Map(), item);
  assert.deepEqual(bulkPlan(items, selection), { variantIds: [], ready: 0, pendingChoice: 1 });
  selection = chooseBulkVariant(selection, item, V2B);
  assert.deepEqual(bulkPlan(items, selection), { variantIds: [V2B], ready: 1, pendingChoice: 0 });
  // Variante fora das opções da posição é ignorada; "nenhuma" desmarca.
  assert.equal(chooseBulkVariant(selection, item, V1).get(C2), V2B);
  assert.equal(chooseBulkVariant(selection, item, null).has(C2), false);
});

test("W7: contagens por grupo para a prévia", () => {
  assert.ok(byCard);
  const items = buildBulkItems([setPosition(C1), setPosition(C2), setPosition(C3), setPosition(C4)], byCard, { cards: new Set([C3]), positions: null });
  assert.deepEqual(bulkCounts(items), { direct: 1, choose: 1, wished: 1, none: 1 });
});

test("W7: resultado — criados, já existentes, indisponíveis e sem resposta (nunca sucesso silencioso)", () => {
  const ok = summarizeBulkAdd([V1, V3], [
    { card_variant_id: V1, entry_id: C1, outcome: "CREATED" },
    { card_variant_id: V3, entry_id: C3, outcome: "EXISTING" },
  ]);
  assert.deepEqual(ok, { created: 1, existing: 1, unavailable: 0, missing: 0, complete: true });
  assert.equal(bulkAddHeadline(ok!), "1 desejo incluído na sua Lista");

  const partial = summarizeBulkAdd([V1, V2A, V3], [
    { card_variant_id: V1, entry_id: C1, outcome: "CREATED" },
    { card_variant_id: V2A, entry_id: null, outcome: "UNAVAILABLE" },
    // V3 sem resposta; linha de variante não pedida é ignorada; CREATED sem id não conta.
    { card_variant_id: V2B, entry_id: C2, outcome: "CREATED" },
  ]);
  assert.deepEqual(partial, { created: 1, existing: 0, unavailable: 1, missing: 1, complete: false });

  const repeat = summarizeBulkAdd([V1], [{ card_variant_id: V1, entry_id: C1, outcome: "EXISTING" }]);
  assert.equal(bulkAddHeadline(repeat!), "Tudo já estava na sua Lista de desejos");
  assert.equal(summarizeBulkAdd([V1], { error: true }), null);
  assert.equal(summarizeBulkAdd([V1], [{ card_variant_id: V1, entry_id: null, outcome: "CREATED" }])?.missing, 1);
});

test("W7: teto do lote alinhado com a 5352 e as leituras de posição", () => {
  assert.equal(BULK_WISH_LIMIT, 500);
});

// ---------------------------------------------------------------------------
// Estático: 5352 (proposta)
// ---------------------------------------------------------------------------

const SQL = readFileSync(
  new URL("../../../database/schema/5352_create_wishlist_bulk_functions.sql", import.meta.url),
  "utf8",
);
const CODE = SQL.replace(/\/\*[\s\S]*?\*\//g, "").replace(/--.*$/gm, "");

test("W7 (estático): 5352 identifica o usuário só pela sessão e não aceita user_id", () => {
  assert.match(CODE, /v_user\s+uuid := auth\.uid\(\)/);
  assert.doesNotMatch(CODE, /p_user/i);
  assert.match(CODE, /where w\.user_id = v_user/);
  assert.match(CODE, /errcode = '28000'/);
});

test("W7 (estático): 5352 só grava na Lista de desejos — nada em coleção, exemplar, alocação ou fichário", () => {
  const writes = [...CODE.matchAll(/\b(insert\s+into|update|delete\s+from)\s+public\.([a-z_]+)/gi)].map((m) => m[2]);
  assert.deepEqual([...new Set(writes)], ["card_wishlist_entry"]);
  assert.doesNotMatch(CODE, /collection|physical_card|binder|allocation|inventory/i);
});

test("W7 (estático): 5352 é idempotente, sempre 'qualquer idioma', com teto e grants mínimos", () => {
  assert.match(CODE, /on conflict on constraint uq_card_wishlist_entry_user_variant_language do nothing/);
  assert.match(CODE, /select v_user, x, null/);
  assert.match(CODE, /cardinality\(v_ids\) > 500/);
  assert.match(CODE, /'CREATED'/);
  assert.match(CODE, /'EXISTING'/);
  assert.match(CODE, /'UNAVAILABLE'/);
  for (const fn of ["get_catalog_card_variants_for_cards(uuid[])", "add_my_wishlist_entries(uuid[])"]) {
    const name = fn.replace(/[()[\]]/g, "\\$&");
    assert.match(CODE, new RegExp(`revoke all on function public\\.${name} from public`));
    assert.match(CODE, new RegExp(`revoke all on function public\\.${name} from anon`));
    assert.match(CODE, new RegExp(`grant execute on function public\\.${name} to authenticated`));
  }
  assert.equal((CODE.match(/security definer/g) ?? []).length, 2);
  assert.equal((CODE.match(/set search_path = ''/g) ?? []).length, 2);
});

// ---------------------------------------------------------------------------
// Estático: fluxo (prévia → revisão → confirmação única) e independência da coleção
// ---------------------------------------------------------------------------

test("W7 (estático): painel começa sem nada marcado, revisa antes e grava uma vez", () => {
  const ui = readFileSync(new URL("../../components/wishlist/missing-wishes-launcher.tsx", import.meta.url), "utf8");
  assert.match(ui, /useState<BulkSelection>\(new Map\(\)\)/, "seleção inicial vazia");
  assert.match(ui, /setStep\("review"\)/, "revisão antes da confirmação");
  assert.equal((ui.match(/addMissingWishes\(/g) ?? []).length, 1, "uma gravação por confirmação");
  assert.match(ui, /disabled=\{plan\.variantIds\.length === 0 \|\| plan\.pendingChoice > 0\}/, "não avança sem seleção ou com ambígua pendente");
  assert.doesNotMatch(ui, /colecoes\/colecoes\/actions|linkMasterSetPositions|add_physical/, "nada muda na coleção ou no acervo");
});

test("W7 (estático): ações leem em lote e só gravam na Lista", () => {
  const actions = readFileSync(new URL("../../app/colecoes/lista-de-desejos/actions.ts", import.meta.url), "utf8");
  const preview = actions.slice(actions.indexOf("export async function previewMissingWishes"), actions.indexOf("export type AddMissingWishesResult"));
  assert.match(preview, /p_filter: "MISSING"/);
  assert.equal((preview.match(/get_catalog_card_variants_for_cards/g) ?? []).length, 2, "uma chamada (+ log) para todas as cartas");
  assert.doesNotMatch(preview, /\.rpc\("add_|for \(const .* of positions\)[\s\S]*\.rpc\(/, "prévia nunca grava nem lê por carta");
  const add = actions.slice(actions.indexOf("export async function addMissingWishes"), actions.indexOf("export type SpeciesWishCards"));
  assert.deepEqual([...add.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]), ["add_my_wishlist_entries"]);

  const view = readFileSync(new URL("../../components/colecoes/colecoes/collection-view.tsx", import.meta.url), "utf8");
  assert.match(view, /<MissingWishesLauncher collectionId=\{collection\.id\} missing=\{missing\} \/>/);
  assert.match(view, /isMaster \? \(master\.wishedPositions \?\? null\) !== null : wishedCards !== null/, "só para o titular, com o estado da Lista lido");
});

// ---------------------------------------------------------------------------
// FIX-03 — confirmação revalidada no servidor
// ---------------------------------------------------------------------------

function freshSet(wished: string[] = [], missing = [C1, C2, C3]) {
  assert.ok(byCard);
  return buildBulkItems(missing.map(setPosition), byCard, { cards: new Set(wished), positions: null });
}

test("FIX-03: variante fora das candidatas da posição é recusada (nada gravado)", () => {
  const plan = resolveBulkConfirmation(freshSet(), [
    { positionKey: C1, variantId: V1 },
    { positionKey: C3, variantId: V2A }, // variante de outra carta
  ]);
  assert.deepEqual(plan.variantIds, [V1]);
  assert.deepEqual(plan.outcomes.map((o) => o.outcome), ["accepted", "invalid_variant"]);
  assert.equal(summarizeBulkConfirmation(plan, null).rejected, 1);
});

test("FIX-03 Master Set: acabamento incompatível é recusado; secreta aceita qualquer acabamento", () => {
  assert.ok(byCard);
  const fresh = buildBulkItems([masterPosition(C2, NORMAL), masterPosition(C2, ANY_FINISH)], byCard, { cards: null, positions: new Set() });
  const plan = resolveBulkConfirmation(fresh, [
    { positionKey: `${C2}:${NORMAL}`, variantId: V2B }, // Holo numa posição Normal
    { positionKey: `${C2}:${ANY_FINISH}`, variantId: V2B },
  ]);
  assert.deepEqual(plan.outcomes.map((o) => o.outcome), ["invalid_variant", "accepted"]);
  assert.deepEqual(plan.variantIds, [V2B]);
});

test("FIX-03: posição preenchida entre prévia e confirmação é ignorada com resultado explícito", () => {
  const plan = resolveBulkConfirmation(freshSet([], [C3]), [
    { positionKey: C1, variantId: V1 }, // C1 deixou de faltar
    { positionKey: C3, variantId: V3 },
  ]);
  assert.deepEqual(plan.outcomes.map((o) => o.outcome), ["not_missing", "accepted"]);
  const summary = summarizeBulkConfirmation(plan, { created: 1, existing: 0, unavailable: 0, missing: 0, complete: true });
  assert.equal(summary.notMissing, 1);
  assert.equal(summary.created, 1);
});

test("FIX-03: desejo incluído em outra aba entre prévia e confirmação → 'já existia', sem gravar", () => {
  const plan = resolveBulkConfirmation(freshSet([C1]), [{ positionKey: C1, variantId: V1 }]);
  assert.deepEqual(plan.variantIds, []);
  const summary = summarizeBulkConfirmation(plan, null);
  assert.deepEqual([summary.created, summary.alreadyWished, summary.complete], [0, 1, true]);
});

test("FIX-03: seleção duplicada ou manipulada — repetida conta uma vez, malformada derruba o pedido", () => {
  const plan = resolveBulkConfirmation(freshSet(), [
    { positionKey: C1, variantId: V1 },
    { positionKey: C1.toUpperCase(), variantId: V1 },
  ]);
  assert.deepEqual(plan.outcomes.map((o) => o.outcome), ["accepted", "duplicate"]);
  assert.deepEqual(plan.variantIds, [V1]);
  assert.equal(summarizeBulkConfirmation(plan, { created: 1, existing: 0, unavailable: 0, missing: 0, complete: true }).complete, false);

  assert.deepEqual(parseBulkSelectionRequests([{ positionKey: ` ${C1.toUpperCase()} `, variantId: V1 }]), [{ positionKey: C1, variantId: V1 }]);
  assert.equal(parseBulkSelectionRequests([]), null);
  assert.equal(parseBulkSelectionRequests({ positionKey: C1, variantId: V1 }), null);
  assert.equal(parseBulkSelectionRequests([{ positionKey: C1, variantId: "não-uuid" }]), null);
  assert.equal(parseBulkSelectionRequests([{ positionKey: "x".repeat(81), variantId: V1 }]), null);
  assert.equal(parseBulkSelectionRequests(Array.from({ length: BULK_WISH_LIMIT + 1 }, () => ({ positionKey: C1, variantId: V1 }))), null);
  // Campos extras de "elegibilidade" enviados pelo navegador são ignorados.
  assert.deepEqual(parseBulkSelectionRequests([{ positionKey: C2, variantId: V2B, state: "direct", eligible: true }]), [{ positionKey: C2, variantId: V2B }]);
});

test("FIX-03: posição de outra coleção (ou inexistente) nunca é aceita", () => {
  const plan = resolveBulkConfirmation(freshSet(), [{ positionKey: C4, variantId: V1 }]);
  assert.deepEqual(plan.outcomes.map((o) => o.outcome), ["not_missing"]);
  assert.deepEqual(plan.variantIds, []);
});

test("FIX-03 (estático): a confirmação recebe coleção + posições e refaz a prévia no servidor", () => {
  const actions = readFileSync(new URL("../../app/colecoes/lista-de-desejos/actions.ts", import.meta.url), "utf8");
  const add = actions.slice(actions.indexOf("export async function addMissingWishes"), actions.indexOf("export type SpeciesWishCards"));
  assert.match(add, /input: \{ collectionId: string; selections: BulkSelectionRequest\[\] \}/);
  assert.match(add, /parseBulkSelectionRequests\(input\?\.selections\)/);
  assert.match(add, /await loadMissingWishItems\(supabase, id\)/, "recalcula faltantes, candidatas e Lista");
  assert.match(add, /resolveBulkConfirmation\(fresh\.items, requests\)/);
  assert.match(add, /p_card_variant_ids: plan\.variantIds/, "grava só o que o servidor aceitou");
  assert.doesNotMatch(add, /variantIds: string\[\]\)/, "não aceita mais lista solta de variantes");
  const loader = actions.slice(actions.indexOf("async function loadMissingWishItems"), actions.indexOf("export type AddMissingWishesResult"));
  assert.match(loader, /getMyCollection\(supabase, id\)/, "coleção precisa ser do usuário da sessão");
  assert.match(loader, /collection === undefined\) return \{ ok: false, reason: "invalid" \}/, "coleção de outro usuário = inválida");
  const ui = readFileSync(new URL("../../components/wishlist/missing-wishes-launcher.tsx", import.meta.url), "utf8");
  assert.match(ui, /addMissingWishes\(\{ collectionId, selections \}\)/);
});
