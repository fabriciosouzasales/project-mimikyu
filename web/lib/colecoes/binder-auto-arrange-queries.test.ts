// Organização automática do fichário (P2 UI E2) — chamadas às RPCs 5343/5344.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-auto-arrange-queries.test.ts (a partir de web/)
//
// Client SIMULADO: nenhuma RPC real é chamada, nada é escrito no LIVE.
// Fixtures sintéticas no formato das canônicas 5343/5344.

import assert from "node:assert/strict";
import { afterEach, beforeEach, test } from "node:test";
import {
  APPLY_RPC,
  AUTO_ARRANGE_LOG_SCOPE,
  PREVIEW_RPC,
  applyMyBinderAutoArrange,
  previewMyBinderAutoArrange,
} from "./binder-auto-arrange-queries.ts";
import { type AutoArrangeFailure, failureMessage, writeDefinitelyNotApplied } from "./binder-auto-arrange.ts";

const COLLECTION = "11111111-2222-4333-8444-555555555555";
const TOKEN = `aa1:${"0123456789abcdef".repeat(4)}`;

function u(n: number): string {
  return `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
}

function item(ord: number, page: number): Record<string, unknown> {
  return {
    ord,
    slot_id: u(1000 + ord),
    physical_card_id: u(2000 + ord),
    page_number: page,
    row_index: 1,
    column_index: ord,
    card_id: u(3000 + ord),
    card_variant_id: u(4000 + ord),
  };
}

const READY = {
  status: "READY",
  insert_count: 3,
  limit: 500,
  plan_token: TOKEN,
  excluded_cards: { COMPETING_CANDIDATES: 2 },
  unfilled_slots: { NO_CANDIDATE: 4 },
  unfilled_count: 4,
  pages: [1, 3],
  items: [item(1, 1), item(2, 1), item(3, 3)],
};
const EMPTY = { ...READY, status: "EMPTY", insert_count: 0, excluded_cards: {}, pages: [], items: [] };
const LIMIT = { ...READY, status: "LIMIT_EXCEEDED", insert_count: 501, excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0, pages: [1, 2, 3], items: [] };

type Call = { fn: string; args: unknown };
type Reply = { data: unknown; error: { code?: string | null; message?: string | null; hint?: string } | null } | "throw";

function fakeClient(reply: Reply, calls: Call[]) {
  return {
    rpc: async (fn: string, args: unknown) => {
      calls.push({ fn, args });
      if (reply === "throw") throw new TypeError("fetch failed");
      return reply;
    },
    from: () => {
      throw new Error("acesso direto a tabela não é permitido");
    },
  } as never;
}

// Captura de logs (console.error / console.info) para provar ausência de token e IDs.
let logs: string[] = [];
const original = { error: console.error, info: console.info, log: console.log, warn: console.warn };
beforeEach(() => {
  logs = [];
  const capture = (...a: unknown[]) => void logs.push(a.map(String).join(" "));
  console.error = capture;
  console.info = capture;
  console.log = capture;
  console.warn = capture;
});
afterEach(() => Object.assign(console, original));

function assertCleanLogs() {
  for (const line of logs) {
    assert.ok(!line.includes(TOKEN) && !line.includes("aa1:"), `token no log: ${line}`);
    assert.ok(!line.includes(COLLECTION), `collectionId no log: ${line}`);
    assert.ok(!/[0-9a-f]{8}-[0-9a-f]{4}-/.test(line), `UUID no log: ${line}`);
    const parsed = JSON.parse(line) as Record<string, unknown>;
    assert.equal(parsed.scope, AUTO_ARRANGE_LOG_SCOPE);
    assert.equal("message" in parsed, false, "mensagem do banco não vai para o log");
  }
}

// ---------------------------------------------------------------------------
// Prévia
// ---------------------------------------------------------------------------

test("prévia: argumento inválido é recusado antes da RPC", async () => {
  for (const collectionId of [undefined, null, "", "abc", 42, `${COLLECTION} `, COLLECTION.toUpperCase().replace(/-/g, "")]) {
    const calls: Call[] = [];
    const out = await previewMyBinderAutoArrange(fakeClient({ data: READY, error: null }, calls), { collectionId });
    assert.deepEqual(out, { ok: false, reason: "invalid_argument" });
    assert.equal(calls.length, 0);
  }
  const calls: Call[] = [];
  assert.deepEqual(await previewMyBinderAutoArrange(fakeClient({ data: READY, error: null }, calls), undefined as never), {
    ok: false,
    reason: "invalid_argument",
  });
  assert.equal(calls.length, 0);
});

test("prévia: uma chamada a preview_my_binder_auto_arrange só com p_collection_id", async () => {
  const calls: Call[] = [];
  const out = await previewMyBinderAutoArrange(fakeClient({ data: READY, error: null }, calls), { collectionId: COLLECTION });
  assert.deepEqual(calls, [{ fn: PREVIEW_RPC, args: { p_collection_id: COLLECTION } }]);
  assert.equal(out.ok, true);
  if (!out.ok) return;
  assert.equal(out.preview.status, "READY");
  assert.equal(out.preview.insertCount, 3);
  assert.equal(out.preview.planToken, TOKEN);
  assert.deepEqual(out.preview.pages, [1, 3]);
  assert.equal(out.preview.items.length, 3);
  assert.equal(out.preview.excludedCount, 2);
  assert.equal(out.preview.unfilledCount, 4);
  assert.equal(logs.length, 0, "sucesso da prévia não gera log");
});

test("prévia: EMPTY e LIMIT_EXCEEDED preservados (LIMIT mantém páginas, itens vazios)", async () => {
  const empty = await previewMyBinderAutoArrange(fakeClient({ data: EMPTY, error: null }, []), { collectionId: COLLECTION });
  assert.equal(empty.ok && empty.preview.status, "EMPTY");
  const limit = await previewMyBinderAutoArrange(fakeClient({ data: LIMIT, error: null }, []), { collectionId: COLLECTION });
  assert.equal(limit.ok, true);
  if (!limit.ok) return;
  assert.equal(limit.preview.status, "LIMIT_EXCEEDED");
  assert.equal(limit.preview.insertCount, 501);
  assert.deepEqual(limit.preview.pages, [1, 2, 3]);
  assert.equal(limit.preview.items.length, 0);
});

test("prévia: erros do banco classificados, sem retry e sem dados privados no log", async () => {
  const cases: Array<[Reply, AutoArrangeFailure]> = [
    [{ data: null, error: { code: "28000", message: "NOT_AUTHENTICATED" } }, "not_authenticated"],
    [{ data: null, error: { code: "22023", message: "INVALID_ARGUMENT" } }, "invalid_argument"],
    [{ data: null, error: { code: "22023", message: "AUTO_ARRANGE_UNSUPPORTED_COLLECTION" } }, "unsupported"],
    [{ data: null, error: { code: "42501", message: "AUTO_ARRANGE_NOT_BINDER_OWNER" } }, "not_owner"],
    [{ data: null, error: { code: "42501", message: "permission denied for function" } }, "forbidden"],
    [{ data: null, error: { code: "P0002", message: "COLLECTION_NOT_FOUND" } }, "collection_not_found"],
    [{ data: null, error: { code: "P0002", message: "BINDER_NOT_FOUND" } }, "binder_not_found"],
    [{ data: null, error: { code: "55000", message: "COLLECTION_ARCHIVED" } }, "archived"],
    [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } }, "statement_timeout"],
    [{ data: null, error: { code: "PGRST202", message: "Could not find the function" } }, "unavailable"],
    [{ data: null, error: { code: "", message: "TypeError: fetch failed" } }, "uncertain"],
    ["throw", "uncertain"],
    [{ data: { status: "READY" }, error: null }, "invalid_response"],
    [{ data: null, error: null }, "invalid_response"],
  ];
  for (const [reply, reason] of cases) {
    const calls: Call[] = [];
    logs = [];
    const out = await previewMyBinderAutoArrange(fakeClient(reply, calls), { collectionId: COLLECTION });
    assert.deepEqual(out, { ok: false, reason }, JSON.stringify(reply));
    assert.equal(calls.length, 1, "exatamente uma chamada");
    assert.equal(logs.length, 1);
    assert.equal((JSON.parse(logs[0]!) as { reason: string }).reason, reason);
    assertCleanLogs();
  }
});

// ---------------------------------------------------------------------------
// Aplicação
// ---------------------------------------------------------------------------

test("aplicação: coleção ou token inválidos são recusados antes da RPC", async () => {
  const bad: Array<{ collectionId: unknown; planToken: unknown }> = [
    { collectionId: "x", planToken: TOKEN },
    { collectionId: COLLECTION, planToken: undefined },
    { collectionId: COLLECTION, planToken: "" },
    { collectionId: COLLECTION, planToken: TOKEN.toUpperCase() },
    { collectionId: COLLECTION, planToken: `${TOKEN}0` },
    { collectionId: COLLECTION, planToken: `v1:${"0".repeat(64)}` },
    { collectionId: COLLECTION, planToken: [TOKEN] },
  ];
  for (const input of bad) {
    const calls: Call[] = [];
    const out = await applyMyBinderAutoArrange(fakeClient({ data: { status: "APPLIED", inserted: 1, event_id: 1, pages: [1] }, error: null }, calls), input);
    assert.deepEqual(out, { ok: false, reason: "invalid_argument", write: "not_applied" });
    assert.equal(calls.length, 0);
  }
});

test("aplicação: só coleção + token; posições enviadas pelo cliente são ignoradas", async () => {
  const calls: Call[] = [];
  const input = { collectionId: COLLECTION, planToken: TOKEN, items: [item(1, 1)], slotIds: [u(9)] } as never;
  const out = await applyMyBinderAutoArrange(fakeClient({ data: { status: "APPLIED", inserted: 3, event_id: 77, pages: [1, 3] }, error: null }, calls), input);
  assert.deepEqual(calls, [{ fn: APPLY_RPC, args: { p_collection_id: COLLECTION, p_plan_token: TOKEN } }]);
  assert.deepEqual(out, { ok: true, result: { outcome: "APPLIED", inserted: 3, eventId: 77, pages: [1, 3] }, cache: "revalidated" });
  assert.equal(logs.length, 1);
  assert.deepEqual(
    (({ ms, ...rest }) => (assert.equal(typeof ms, "number"), rest))(JSON.parse(logs[0]!) as Record<string, unknown>),
    { scope: AUTO_ARRANGE_LOG_SCOPE, fn: APPLY_RPC, outcome: "APPLIED", inserted: 3, pages: 2 },
  );
  assertCleanLogs();
});

test("aplicação: NOTHING_TO_DO e ALREADY_APPLIED são sucessos distintos, sem gravação nova", async () => {
  const nothing = await applyMyBinderAutoArrange(fakeClient({ data: { status: "NOTHING_TO_DO", inserted: 0 }, error: null }, []), {
    collectionId: COLLECTION,
    planToken: TOKEN,
  });
  assert.deepEqual(nothing, { ok: true, result: { outcome: "NOTHING_TO_DO", inserted: 0 }, cache: "not_needed" });
  const already = await applyMyBinderAutoArrange(fakeClient({ data: { status: "ALREADY_APPLIED", inserted: 0, event_id: 77 }, error: null }, []), {
    collectionId: COLLECTION,
    planToken: TOKEN,
  });
  assert.deepEqual(already, { ok: true, result: { outcome: "ALREADY_APPLIED", inserted: 0, eventId: 77 }, cache: "revalidated" });
  assertCleanLogs();
});

test("aplicação: todos os erros do contrato preservados, uma única chamada, nenhum token no log", async () => {
  const cases: Array<[Reply, AutoArrangeFailure]> = [
    [{ data: null, error: { code: "40001", message: "AUTO_ARRANGE_PLAN_CHANGED", hint: "Gere uma nova prévia." } }, "plan_changed"],
    [{ data: null, error: { code: "55P03", message: "canceling statement due to lock timeout" } }, "lock_timeout"],
    [{ data: null, error: { code: "40P01", message: "deadlock detected" } }, "deadlock"],
    [{ data: null, error: { code: "57014", message: "canceling statement due to statement timeout" } }, "statement_timeout"],
    [{ data: null, error: { code: "54000", message: "AUTO_ARRANGE_LIMIT_EXCEEDED" } }, "limit_exceeded"],
    [{ data: null, error: { code: "22023", message: "INVALID_ARGUMENT" } }, "invalid_argument"],
    [{ data: null, error: { code: "22023", message: "AUTO_ARRANGE_UNSUPPORTED_COLLECTION" } }, "unsupported"],
    [{ data: null, error: { code: "42501", message: "AUTO_ARRANGE_NOT_BINDER_OWNER" } }, "not_owner"],
    [{ data: null, error: { code: "P0002", message: "COLLECTION_NOT_FOUND" } }, "collection_not_found"],
    [{ data: null, error: { code: "P0002", message: "BINDER_NOT_FOUND" } }, "binder_not_found"],
    [{ data: null, error: { code: "55000", message: "COLLECTION_ARCHIVED" } }, "archived"],
    [{ data: null, error: { code: "28000", message: "NOT_AUTHENTICATED" } }, "not_authenticated"],
    [{ data: null, error: { code: "XX000", message: `boom ${TOKEN}` } }, "unknown"],
    // Falha de rede / gateway: resultado incerto (não afirma que nada foi gravado).
    [{ data: null, error: { code: "", message: "TypeError: fetch failed" } }, "uncertain"],
    [{ data: null, error: { message: "504 Gateway Timeout" } }, "uncertain"],
    ["throw", "uncertain"],
    // Respostas fora do contrato: nunca sucesso aparente.
    [{ data: null, error: null }, "invalid_response"],
    [{ data: { status: "APPLIED", inserted: 0, event_id: 1, pages: [] }, error: null }, "invalid_response"],
    [{ data: { status: "OK", inserted: 3 }, error: null }, "invalid_response"],
    [{ data: { status: "NOTHING_TO_DO", inserted: 2 }, error: null }, "invalid_response"],
    [{ data: { status: "ALREADY_APPLIED", inserted: 0 }, error: null }, "invalid_response"],
  ];
  for (const [reply, reason] of cases) {
    const calls: Call[] = [];
    logs = [];
    const out = await applyMyBinderAutoArrange(fakeClient(reply, calls), { collectionId: COLLECTION, planToken: TOKEN });
    const expected = writeDefinitelyNotApplied(reason) ? { ok: false, reason, write: "not_applied" } : { ok: false, reason, write: "unknown", planToken: TOKEN };
    assert.deepEqual(out, expected, JSON.stringify(reply));
    assert.equal(calls.length, 1, "sem retry automático");
    assert.equal(calls[0]!.fn, APPLY_RPC);
    assert.equal(logs.length, 1);
    const entry = JSON.parse(logs[0]!) as { reason: string; code: string };
    assert.equal(entry.reason, reason);
    if (reply !== "throw" && reply.error?.code) assert.equal(entry.code, reply.error.code, "SQLSTATE preservado no log");
    assertCleanLogs();
  }
});

test("aplicação: o client simulado nunca é usado para leitura/escrita direta de tabela", async () => {
  // `from` lança; se o adaptador tentasse um caminho alternativo de escrita, o teste falharia.
  const calls: Call[] = [];
  const out = await applyMyBinderAutoArrange(fakeClient({ data: { status: "NOTHING_TO_DO", inserted: 0 }, error: null }, calls), {
    collectionId: COLLECTION,
    planToken: TOKEN,
  });
  assert.equal(out.ok, true);
  assert.deepEqual(
    calls.map((c) => c.fn),
    [APPLY_RPC],
  );
});

// ---------------------------------------------------------------------------
// CORRECTION-02 — resultado incerto e revalidação de cache
// ---------------------------------------------------------------------------

const NOT_WRITTEN = /nada foi posicionado|nada foi gravado|nada foi alterado/i;

test("aplicação incerta (rede, exceção, conexão perdida, servidor interrompido): write unknown, token devolvido, sem mensagem de ausência de escrita, sem retry", async () => {
  const replies: Reply[] = [
    "throw",
    { data: null, error: { code: "", message: "TypeError: fetch failed" } },
    { data: null, error: { message: "upstream connect error" } },
    { data: null, error: { code: "PGRST000", message: "Could not connect with the database" } },
    { data: null, error: { code: "08006", message: "connection failure" } },
    { data: null, error: { code: "08003", message: "connection does not exist" } },
    { data: null, error: { code: "57P01", message: "terminating connection due to administrator command" } },
    { data: null, error: { code: "57P02", message: "crash shutdown" } },
    { data: null, error: { code: "58030", message: "could not write to file" } },
  ];
  for (const reply of replies) {
    const calls: Call[] = [];
    let revalidated = 0;
    logs = [];
    const out = await applyMyBinderAutoArrange(fakeClient(reply, calls), { collectionId: COLLECTION, planToken: TOKEN }, () => void revalidated++);
    assert.deepEqual(out, { ok: false, reason: "uncertain", write: "unknown", planToken: TOKEN }, JSON.stringify(reply));
    assert.equal(calls.length, 1, "falha de transporte não provoca retry");
    assert.equal(revalidated, 0, "sem sucesso, sem revalidação de cache");
    assert.doesNotMatch(failureMessage(out.ok ? "unknown" : out.reason), NOT_WRITTEN);
    assertCleanLogs();
  }
});

test("payload malformado da aplicação: nunca sucesso, write unknown (a RPC pode ter gravado), sem cache e sem retry", async () => {
  for (const data of [null, undefined, "APPLIED", [], { status: "APPLIED" }, { status: "APPLIED", inserted: 3, event_id: 0, pages: [1] }, { status: "applied", inserted: 3, event_id: 7, pages: [1] }]) {
    const calls: Call[] = [];
    let revalidated = 0;
    const out = await applyMyBinderAutoArrange(fakeClient({ data, error: null }, calls), { collectionId: COLLECTION, planToken: TOKEN }, () => void revalidated++);
    assert.deepEqual(out, { ok: false, reason: "invalid_response", write: "unknown", planToken: TOKEN }, JSON.stringify(data));
    assert.equal(calls.length, 1);
    assert.equal(revalidated, 0);
    assert.doesNotMatch(failureMessage("invalid_response"), NOT_WRITTEN);
  }
});

test("erro SQL confirmado (inclusive XX000) e PGRST202: write not_applied, sem token na resposta", async () => {
  for (const [code, reason] of [["XX000", "unknown"], ["PGRST202", "unavailable"], ["40001", "plan_changed"], ["55P03", "lock_timeout"]] as const) {
    const out = await applyMyBinderAutoArrange(fakeClient({ data: null, error: { code, message: "x" } }, []), { collectionId: COLLECTION, planToken: TOKEN });
    assert.deepEqual(out, { ok: false, reason, write: "not_applied" }, code);
  }
});

test("cache: APPLIED e ALREADY_APPLIED revalidam; NOTHING_TO_DO não", async () => {
  const cases: Array<[unknown, number, string]> = [
    [{ status: "APPLIED", inserted: 2, event_id: 9, pages: [1] }, 1, "revalidated"],
    [{ status: "ALREADY_APPLIED", inserted: 0, event_id: 9 }, 1, "revalidated"],
    [{ status: "NOTHING_TO_DO", inserted: 0 }, 0, "not_needed"],
  ];
  for (const [data, expectedCalls, cache] of cases) {
    let revalidated = 0;
    const out = await applyMyBinderAutoArrange(fakeClient({ data, error: null }, []), { collectionId: COLLECTION, planToken: TOKEN }, () => void revalidated++);
    assert.equal(out.ok, true);
    assert.equal(out.ok && out.cache, cache);
    assert.equal(revalidated, expectedCalls);
  }
});

test("cache: revalidatePath lançando após APPLIED/ALREADY_APPLIED mantém o sucesso, não reaplica e não vaza o caminho no log", async () => {
  for (const [data, outcome] of [
    [{ status: "APPLIED", inserted: 2, event_id: 9, pages: [1, 2] }, "APPLIED"],
    [{ status: "ALREADY_APPLIED", inserted: 0, event_id: 9 }, "ALREADY_APPLIED"],
  ] as const) {
    const calls: Call[] = [];
    logs = [];
    const out = await applyMyBinderAutoArrange(fakeClient({ data, error: null }, calls), { collectionId: COLLECTION, planToken: TOKEN }, () => {
      throw new Error(`Invariant: revalidatePath /colecoes/colecoes/${COLLECTION}/fichario`);
    });
    assert.equal(out.ok, true, "falha de cache não vira erro de escrita");
    assert.equal(out.ok && out.result.outcome, outcome);
    assert.equal(out.ok && out.cache, "failed");
    assert.equal(calls.length, 1, "sem reaplicação");
    assert.equal(logs.length, 2, "log da aplicação + log da falha de cache");
    assert.equal((JSON.parse(logs[1]!) as { reason: string }).reason, "cache_revalidation_failed");
    assertCleanLogs();
  }
});

test("prévia não produz escrita: só a RPC STABLE de prévia, nunca a de aplicação, em sucesso ou falha", async () => {
  for (const reply of [{ data: READY, error: null }, { data: LIMIT, error: null }, { data: null, error: { code: "40001", message: "x" } }, "throw"] as Reply[]) {
    const calls: Call[] = [];
    await previewMyBinderAutoArrange(fakeClient(reply, calls), { collectionId: COLLECTION });
    assert.deepEqual(
      calls.map((c) => c.fn),
      [PREVIEW_RPC],
    );
  }
});
