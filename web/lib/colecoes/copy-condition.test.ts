import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { activeProvisional } from "./acervo-refresh.ts";
import {
  CONDITION_BATCH_MAX,
  type ConditionClient,
  conditionApplySuccess,
  conditionSignature,
  copyConditionFailureFromError,
  copyConditionFailureMessage,
  idsToChange,
  normalizeConditionBatch,
  parseConditionResult,
  setCopiesCondition,
} from "./copy-condition.ts";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const C = "33333333-3333-4333-8333-333333333333";

function fakeClient(response: { data: unknown; error: { code?: string; message?: string } | null }) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client: ConditionClient = {
    rpc: (fn, args) => {
      calls.push({ fn, args });
      return Promise.resolve(response);
    },
  };
  return { client, calls };
}

// ---- lote ----

test("normalizeConditionBatch: deduplica; recusa vazio, não-array, inválido e acima de 500 (teto sobre o array recebido)", () => {
  assert.deepEqual(normalizeConditionBatch([A, A, B]), [A, B]);
  assert.equal(normalizeConditionBatch([]), null);
  assert.equal(normalizeConditionBatch(null), null);
  assert.equal(normalizeConditionBatch("x"), null);
  assert.equal(normalizeConditionBatch([A, "não-uuid"]), null);
  assert.equal(normalizeConditionBatch([A, 7]), null);
  assert.equal(normalizeConditionBatch(Array(CONDITION_BATCH_MAX).fill(A))?.length, 1, "500 entradas (mesmo repetidas) passam");
  assert.equal(normalizeConditionBatch(Array(CONDITION_BATCH_MAX + 1).fill(A)), null, "501 entradas brutas → recusa");
});

// ---- action (só a 5364, sem sucesso parcial) ----

test("setCopiesCondition: chama SÓ set_my_physical_cards_condition, com ids deduplicados e o código canônico", async () => {
  const { client, calls } = fakeClient({ data: [{ requested_count: 2, changed_count: 1 }], error: null });
  const out = await setCopiesCondition(client, { physicalCardIds: [A, B, A], conditionCode: "LP" });
  assert.deepEqual(calls, [{ fn: "set_my_physical_cards_condition", args: { p_physical_card_ids: [A, B], p_condition_code: "LP" } }]);
  assert.deepEqual(out, { ok: true, requested: 2, changed: 1, conditionCode: "LP" }, "changed pode ser menor que requested");
});

test("setCopiesCondition: lote ou código inválido param ANTES do banco", async () => {
  for (const input of [
    { physicalCardIds: [], conditionCode: "NM" },
    { physicalCardIds: ["x"], conditionCode: "NM" },
    { physicalCardIds: Array(501).fill(A), conditionCode: "NM" },
    { physicalCardIds: [A], conditionCode: "SP" },
    { physicalCardIds: [A], conditionCode: "nm" },
    { physicalCardIds: [A], conditionCode: null },
  ]) {
    const { client, calls } = fakeClient({ data: [{ requested_count: 1, changed_count: 1 }], error: null });
    const out = await setCopiesCondition(client, input);
    assert.equal(out.ok, false);
    assert.equal(calls.length, 0, JSON.stringify(input.conditionCode));
  }
  const tooMany = await setCopiesCondition(fakeClient({ data: null, error: null }).client, { physicalCardIds: Array(501).fill(A), conditionCode: "NM" });
  assert.deepEqual(tooMany, { ok: false, reason: "too_many" });
  const badCode = await setCopiesCondition(fakeClient({ data: null, error: null }).client, { physicalCardIds: [A], conditionCode: "DM" });
  assert.deepEqual(badCode, { ok: false, reason: "invalid_condition" }, "rótulo exibido não é código");
});

test("setCopiesCondition: erro do banco vira falha classificada; forma inesperada nunca vira sucesso", async () => {
  const gone = await setCopiesCondition(
    fakeClient({ data: null, error: { code: "22023", message: "um ou mais physical_card_ids não pertencem ao inventory do chamador" } }).client,
    { physicalCardIds: [A], conditionCode: "MP" },
  );
  assert.equal(gone.ok, false);
  assert.equal(gone.ok === false && gone.reason, "copies_gone");
  for (const data of [null, [], [{}], [{ requested_count: 2, changed_count: 3 }], [{ requested_count: 0, changed_count: 0 }], "x"]) {
    const out = await setCopiesCondition(fakeClient({ data, error: null }).client, { physicalCardIds: [A], conditionCode: "HP" });
    assert.deepEqual(out, { ok: false, reason: "unavailable", code: "BAD_SHAPE" }, JSON.stringify(data));
  }
});

test("copyConditionFailureFromError: sessão, exemplar indisponível, concorrência, lote, código e genérico", () => {
  const cases: [Record<string, string>, string][] = [
    [{ code: "28000", message: "authentication required" }, "not_authenticated"],
    [{ code: "42501", message: "permission denied for function set_my_physical_cards_condition" }, "not_authenticated"],
    [{ code: "22023", message: "um ou mais physical_card_ids não pertencem ao inventory do chamador" }, "copies_gone"],
    [{ code: "55P03", message: "canceling statement due to lock timeout" }, "busy"],
    [{ code: "40P01", message: "deadlock detected" }, "busy"],
    [{ code: "22023", message: "lote excede o limite de 500 itens por chamada" }, "too_many"],
    [{ code: "22023", message: "CONDITION_NOT_FOUND: condition_code inexistente na escala canônica: XX" }, "invalid_condition"],
    [{ code: "22023", message: "condition_code é obrigatório" }, "invalid_condition"],
    [{ code: "22023", message: "p_physical_card_ids não pode ser vazio" }, "invalid"],
    [{ code: "22023", message: "inventory not found for current user" }, "unavailable"],
    [{ code: "XX000", message: "boom" }, "unavailable"],
  ];
  for (const [error, reason] of cases) assert.equal(copyConditionFailureFromError(error), reason, error.message);
  assert.equal(copyConditionFailureFromError(null), "unavailable");
});

test("mensagens: linguagem do colecionador, sempre dizendo que nada mudou em falha", () => {
  for (const reason of ["not_authenticated", "invalid_condition", "copies_gone", "busy", "unavailable"] as const) {
    const text = copyConditionFailureMessage(reason);
    assert.match(text, /[Nn]enhuma condição foi alterada|Nada foi alterado/, reason);
    assert.doesNotMatch(text, /physical_card|inventory|SQL|22023/, reason);
  }
  assert.match(copyConditionFailureMessage("too_many"), /500/);
});

test("parseConditionResult: uma linha (requested_count, changed_count) com 0 ≤ changed ≤ requested", () => {
  assert.deepEqual(parseConditionResult([{ requested_count: 3, changed_count: 0 }]), { requested: 3, changed: 0 });
  assert.deepEqual(parseConditionResult({ requested_count: "2", changed_count: "2" }), { requested: 2, changed: 2 });
  assert.equal(parseConditionResult([{ requested_count: 1 }]), null);
  assert.equal(parseConditionResult([{ requested_count: 1, changed_count: -1 }]), null);
});

// ---- interface: seleção, provisório, reversão ----

test("idsToChange: só os marcados que ainda não estão na condição; todos já estão → nada a enviar", () => {
  const current: Record<string, "NM" | "LP" | null> = { [A]: "NM", [B]: "LP", [C]: null };
  const of = (id: string) => current[id] ?? null;
  assert.deepEqual(idsToChange([A, B, C], of, "LP"), [A, C]);
  assert.deepEqual(idsToChange([B], of, "LP"), [], "o banco não é chamado");
});

test("provisório da condição: vale enquanto as condições exibidas forem as do início; leitura nova do servidor manda", () => {
  const before = conditionSignature([{ physicalCardId: A, conditionCode: "NM" }, { physicalCardId: B, conditionCode: "NM" }]);
  const after = conditionSignature([{ physicalCardId: A, conditionCode: "LP" }, { physicalCardId: B, conditionCode: "NM" }]);
  const overlay = { ids: [A], code: "LP" as const, basis: before };
  assert.equal(activeProvisional(overlay, before), overlay, "durante o envio e até a lista nova");
  assert.equal(activeProvisional(overlay, after), null, "lista nova chegou → servidor manda");
  // Reversão em erro = provisório removido: nenhuma condição provisória sobra.
  assert.equal(activeProvisional(null, before), null);
  assert.notEqual(before, after);
  assert.equal(conditionSignature([{ physicalCardId: A, conditionCode: null }]), `${A}:-`);
});

test("sucesso: só o comprovado — changed_count do banco; os demais marcados já estavam na condição", () => {
  // Todos enviados, todos mudaram.
  assert.equal(conditionApplySuccess({ selected: 1, requested: 1, changed: 1 }, "LP"), "1 exemplar agora está em SP.");
  assert.equal(conditionApplySuccess({ selected: 3, requested: 3, changed: 3 }, "DMG"), "3 exemplares agora estão em DM.");
  // Alguns marcados já estavam na condição: a interface enviou só um subconjunto.
  assert.equal(
    conditionApplySuccess({ selected: 5, requested: 2, changed: 2 }, "MP"),
    "2 exemplares agora estão em MP; 3 outros já estavam nessa condição.",
  );
  // O banco mudou menos do que recebeu (outro lugar já tinha gravado a condição).
  assert.equal(
    conditionApplySuccess({ selected: 3, requested: 3, changed: 2 }, "HP"),
    "2 exemplares agora estão em HP; 1 outro já estava nessa condição.",
  );
  // Subconjunto enviado E banco mudando menos: os dois grupos somam, sem contar duas vezes.
  assert.equal(
    conditionApplySuccess({ selected: 6, requested: 4, changed: 1 }, "NM"),
    "1 exemplar agora está em NM; 5 outros já estavam nessa condição.",
  );
  // Zero alterações no servidor: nunca afirma que algo mudou.
  assert.equal(conditionApplySuccess({ selected: 1, requested: 1, changed: 0 }, "M"), "Nenhuma condição mudou — o exemplar já estava em M.");
  assert.equal(
    conditionApplySuccess({ selected: 4, requested: 2, changed: 0 }, "LP"),
    "Nenhuma condição mudou — os 4 exemplares marcados já estavam em SP.",
  );
  for (const text of [conditionApplySuccess({ selected: 2, requested: 2, changed: 0 }, "NM")]) {
    assert.doesNotMatch(text, /agora est/);
  }
});

test("sucesso: contagens incoerentes são limitadas, nunca extrapoladas", () => {
  // changed acima de requested (forma impossível: a action já recusa) → limitado a requested.
  assert.equal(conditionApplySuccess({ selected: 2, requested: 2, changed: 5 }, "LP"), "2 exemplares agora estão em SP.");
  // selected abaixo de requested (seleção esvaziada) → total usa o maior.
  assert.equal(conditionApplySuccess({ selected: 0, requested: 2, changed: 1 }, "LP"), "1 exemplar agora está em SP; 1 outro já estava nessa condição.");
});

// ---- guardas de fonte (componentes e action) ----

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");

test("action: só a 5364, revalida só o Meu acervo (sucesso e exemplar indisponível), sem mexer em local/coleção", () => {
  const src = read("app/colecoes/acervo/actions.ts");
  const start = src.indexOf("export async function setMyCopiesCondition");
  const body = src.slice(start, src.indexOf("\n}\n", start));
  assert.ok(start > 0);
  assert.match(body, /setCopiesCondition\(supabase, input\)/);
  assert.match(body, /if \(outcome\.reason === "copies_gone"\) revalidatePath\(ACERVO_PATH\);/);
  assert.match(body, /revalidatePath\(ACERVO_PATH\);\s*return outcome;/);
  assert.doesNotMatch(body, /LOCAIS_PATH|COLECOES_PATH|set_physical_cards_storage|rpc\(/);
  const lib = read("lib/colecoes/copy-condition.ts");
  assert.equal(lib.match(/client\.rpc\(/g)?.length, 1);
  assert.match(lib, /client\.rpc\("set_my_physical_cards_condition"/);
});

test("lista: seleção independe do contexto de local; Local preservado; Condição com provisório e reversão", () => {
  const src = read("components/colecoes/acervo/copy-storage-list.tsx");
  assert.match(src, /const selectable = copies\.length > 0;/);
  assert.match(src, /\{selectable \? \(\s*<label className=\{local\.check\}>/);
  assert.match(src, /const barMode: BarMode = editable \? mode : "condition";/, "sem local editável, só Condição");
  assert.match(src, /setConditionOverlay\(\{ ids, code, basis: shownConditions \}\);/, "provisório ao iniciar");
  assert.match(src, /setConditionOverlay\(null\);\s*setConditionError\(reason\);/, "reversão em erro");
  assert.match(src, /if \(reason === "copies_gone"\) setSelected\(\[\]\);/);
  assert.match(src, /setNotice\(conditionApplySuccess\(result, code\)\);/);
  // Local: fluxo existente intacto (confirmação, guardar, tirar do fichário).
  assert.match(src, /setMyCopiesStorage\(\{ physicalCardIds: ids, storageContainerId: target, unplaceFromBinder: binderConfirm \}\)/);
  assert.match(src, /confirmation\.action/);
  const action = read("components/colecoes/acervo/copy-condition-action.tsx");
  assert.match(action, /setMyCopiesCondition\(\{ physicalCardIds: ids, conditionCode: target \}\)/);
  assert.match(action, /const canApply = !pending && target !== null && selected\.length > 0 && !tooMany && toChange\.length > 0;/);
  assert.match(action, /cardConditionOptions\(\)\.map/);
  assert.doesNotMatch(action, /router\.refresh/);
});

test("seleção congelada durante o envio da condição; fora dele, seleção e Local como antes", () => {
  const src = read("components/colecoes/acervo/copy-storage-list.tsx");
  assert.match(src, /const busy = pending \|\| conditionPending;/);
  assert.match(src, /const toggle = \(id: string\) => \{\s*if \(busy\) return;/, "caixas individuais");
  assert.match(src, /className=\{local\.selectAll\}\s*aria-disabled=\{busy \|\| undefined\}\s*onClick=\{\(\) => \{\s*if \(busy\) return;/, "Marcar todos");
  assert.match(src, /checked=\{isSelected\}\s*aria-disabled=\{busy \|\| undefined\}/);
  assert.match(src, /aria-pressed=\{barMode === value\}\s*aria-disabled=\{busy \|\| undefined\}\s*onClick=\{\(\) => \{\s*if \(busy\) return;/, "troca Local | Condição");
  assert.match(src, /onBusyChange=\{setConditionPending\}/);
  assert.match(src, /blocked=\{conditionPending\}/, "lixeira espera");
  // Fora do envio de condição, o bloqueio é o mesmo de antes (só o envio de Local).
  assert.match(src, /const \[conditionPending, setConditionPending\] = useState\(false\);/);
  const action = read("components/colecoes/acervo/copy-condition-action.tsx");
  assert.match(action, /onBusyChange\(true\);/);
  assert.match(action, /finally \{[\s\S]*onBusyChange\(false\);/, "libera mesmo em erro");
  assert.match(action, /const selectedAtStart = selected\.length;/);
  assert.match(action, /onSuccess\(\{ selected: selectedAtStart, requested: result\.requested, changed: result\.changed \}, target\);/);
  const trash = read("components/colecoes/acervo/copy-remove-button.tsx");
  assert.match(trash, /blocked = false,/, "padrão: lixeira livre (comportamento anterior)");
  assert.match(trash, /if \(blocked\) return;\s*setConfirming\(true\);/);
  assert.match(trash, /disabled=\{pending \|\| blocked\}/);
});
