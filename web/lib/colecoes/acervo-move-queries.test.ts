// WHERE-05B — resolução no servidor e execução revalidada, contra um cliente
// Supabase FALSO em memória (filtros, contagem exata, paginação e `max-rows`
// do PostgREST simulados). Nenhuma rede, nenhum banco.
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-move-queries.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { type AcervoItemKey, parseAcervoState } from "./acervo.ts";
import { type MoveScope, scopeOf, scopeSignature } from "./acervo-move.ts";
import { type MoveClient, executeMove, resolveMoveSet } from "./acervo-move-queries.ts";

type Row = Record<string, unknown>;
type Result = { data: unknown; error: { code?: string; message?: string } | null; count?: number | null };

const USER = "99999999-9999-4999-8999-999999999999";
const INV = "88888888-8888-4888-8888-888888888888";
const OTHER_INV = "77777777-7777-4777-8777-777777777777";
const V1 = "11111111-1111-4111-8111-111111111111";
const V2 = "22222222-2222-4222-8222-222222222222";
const L_PT = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const L_EN = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const LOC_A = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const LOC_B = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const COL_1 = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";

const K1: AcervoItemKey = { cardVariantId: V1, languageCode: "pt" };
const K2: AcervoItemKey = { cardVariantId: V2, languageCode: "en" };

function id(n: number): string {
  return `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
}

class FakeDb {
  tables: Record<string, Row[]> = {
    inventory: [{ id: INV, owner_user_id: USER }],
    storage_container: [
      { id: LOC_A, name: "Fichário" },
      { id: LOC_B, name: "Caixa" },
    ],
    physical_card: [],
    collection_allocation: [],
  };
  maxRows = 1000;
  user: string | null = USER;
  writes: { ids: string[]; target: string | null }[] = [];
  writeResult: ((ids: string[], target: string | null) => Result) | null = null;
  writeThrows = false;
  onRead: ((table: string, call: number) => void) | null = null;
  private reads = 0;

  addCopies(n: number, from: number, partial: Partial<{ variant: string; language: string; storage: string | null; inventory: string }> = {}) {
    for (let i = 0; i < n; i++) {
      this.tables.physical_card!.push({
        id: id(from + i),
        card_variant_id: partial.variant ?? V1,
        language_id: partial.language ?? L_PT,
        storage_container_id: partial.storage === undefined ? null : partial.storage,
        inventory_id: partial.inventory ?? INV,
      });
    }
  }

  client(): MoveClient {
    const db = this;
    return {
      auth: { getUser: async () => ({ data: { user: db.user ? { id: db.user } : null }, error: null }) },
      from: (table: string) => db.query(table),
      rpc(fn: string, args?: Record<string, unknown>) {
        if (fn === "get_registrable_languages") {
          return Promise.resolve({
            data: [
              { language_id: L_PT, code: "pt", name: "Português" },
              { language_id: L_EN, code: "en", name: "English" },
            ],
            error: null,
          });
        }
        if (fn === "set_physical_cards_storage") {
          if (db.writeThrows) return Promise.reject(new Error("network"));
          const ids = args?.p_physical_card_ids as string[];
          const target = (args?.p_storage_container_id ?? null) as string | null;
          db.writes.push({ ids, target });
          if (db.writeResult) return Promise.resolve(db.writeResult(ids, target));
          const rows = db.tables.physical_card!.filter((r) => ids.includes(r.id as string));
          for (const row of rows) row.storage_container_id = target;
          return Promise.resolve({ data: rows.map((r) => ({ id: r.id, storage_container_id: target })), error: null });
        }
        return Promise.resolve({ data: null, error: { code: "42883", message: "no fn" } });
      },
    };
  }

  private query(table: string) {
    const db = this;
    const filters: ((row: Row) => boolean)[] = [];
    let orderBy: string | null = null;
    let from = 0;
    let to = Number.POSITIVE_INFINITY;
    let limit = Number.POSITIVE_INFINITY;
    let wantCount = false;
    const q = {
      select(_cols: string, options?: { count?: "exact" }) {
        wantCount = options?.count === "exact";
        return q;
      },
      eq(column: string, value: string) {
        filters.push((row) => row[column] === value);
        return q;
      },
      is(column: string, _value: null) {
        filters.push((row) => row[column] === null);
        return q;
      },
      in(column: string, values: readonly string[]) {
        filters.push((row) => values.includes(row[column] as string));
        return q;
      },
      or(filter: string) {
        const pairs = [...filter.matchAll(/and\(card_variant_id\.eq\.([^,]+),language_id\.eq\.([^)]+)\)/g)].map((m) => [m[1], m[2]]);
        filters.push((row) => pairs.some(([v, l]) => row.card_variant_id === v && row.language_id === l));
        return q;
      },
      order(column: string) {
        orderBy = column;
        return q;
      },
      range(a: number, b: number) {
        from = a;
        to = b;
        return q;
      },
      limit(n: number) {
        limit = n;
        return q;
      },
      then<T1 = Result, T2 = never>(
        onfulfilled?: ((value: Result) => T1 | PromiseLike<T1>) | null,
        onrejected?: ((reason: unknown) => T2 | PromiseLike<T2>) | null,
      ): Promise<T1 | T2> {
        db.onRead?.(table, ++db.reads);
        let rows = (db.tables[table] ?? []).filter((row) => filters.every((f) => f(row)));
        if (orderBy) {
          const key = orderBy;
          rows = [...rows].sort((a, b) => ((a[key] as string) < (b[key] as string) ? -1 : 1));
        }
        const count = rows.length;
        const page = rows.slice(from, Math.min(to + 1, rows.length)).slice(0, Math.min(limit, db.maxRows));
        return Promise.resolve({ data: page.map((r) => ({ ...r })), error: null, count: wantCount ? count : null } as Result).then(onfulfilled, onrejected);
      },
    };
    return q;
  }
}

function req(keys: AcervoItemKey[], params: Record<string, string>, target: string | null) {
  const scope: MoveScope = scopeOf(parseAcervoState(params));
  return { keys, scope, scopeSignature: scopeSignature(scope), target };
}

// ---------------------------------------------------------------- prévia
test("prévia sem filtros: contagens e nome do destino", async () => {
  const db = new FakeDb();
  db.addCopies(2, 1);
  db.addCopies(1, 3, { storage: LOC_A });
  db.addCopies(1, 4, { storage: LOC_B });
  const r = await resolveMoveSet(db.client(), req([K1], {}, LOC_A));
  assert.ok(r.ok);
  assert.equal(r.preview.targetName, "Fichário");
  assert.equal(r.preview.total, 4);
  assert.equal(r.preview.toMove, 3);
  assert.equal(r.preview.atTarget, 1);
  assert.equal(r.preview.fromNone, 2);
  assert.equal(r.preview.fromOther, 1);
  assert.match(r.preview.token, /^v1:[0-9a-f]{64}$/);
});

test("filtro por local, por coleção e combinados", async () => {
  const db = new FakeDb();
  db.addCopies(3, 1, { storage: LOC_A });
  db.addCopies(2, 10, { storage: LOC_B });
  db.tables.collection_allocation = [
    { physical_card_id: id(1), collection_id: COL_1 },
    { physical_card_id: id(10), collection_id: COL_1 },
  ];
  const byLocal = await resolveMoveSet(db.client(), req([K1], { local: LOC_A }, LOC_B));
  assert.ok(byLocal.ok);
  assert.equal(byLocal.preview.total, 3);
  const byCol = await resolveMoveSet(db.client(), req([K1], { colecao: COL_1 }, null));
  assert.ok(byCol.ok);
  assert.deepEqual(byCol.plan.toMove, [id(1), id(10)]);
  const none = await resolveMoveSet(db.client(), req([K1], { colecao: "sem" }, null));
  assert.ok(none.ok);
  assert.equal(none.preview.total, 3);
  const both = await resolveMoveSet(db.client(), req([K1], { colecao: COL_1, local: LOC_A }, LOC_B));
  assert.ok(both.ok);
  assert.deepEqual(both.plan.toMove, [id(1)]);
});

test("salvaguarda 2: leitura completa mesmo com max-rows menor que a página", async () => {
  const db = new FakeDb();
  db.maxRows = 7;
  db.addCopies(20, 1);
  const r = await resolveMoveSet(db.client(), req([K1], {}, LOC_A));
  assert.ok(r.ok);
  assert.equal(r.preview.total, 20);
  // alocações também paginadas
  db.tables.collection_allocation = Array.from({ length: 20 }, (_, i) => ({ physical_card_id: id(i + 1), collection_id: COL_1 }));
  const c = await resolveMoveSet(db.client(), req([K1], { colecao: COL_1 }, LOC_A), { pageSize: 5 });
  assert.ok(c.ok);
  assert.equal(c.preview.total, 20);
});

test("salvaguarda 2: 500 passa, 501 é too_large (sem e com filtro de coleção)", async () => {
  const ok = new FakeDb();
  ok.addCopies(500, 1);
  const r500 = await resolveMoveSet(ok.client(), req([K1], {}, LOC_A));
  assert.ok(r500.ok);
  assert.equal(r500.preview.total, 500);

  const big = new FakeDb();
  big.addCopies(501, 1);
  assert.deepEqual(await resolveMoveSet(big.client(), req([K1], {}, LOC_A)), { ok: false, reason: "too_large" });

  const col = new FakeDb();
  col.addCopies(501, 1);
  col.tables.collection_allocation = Array.from({ length: 501 }, (_, i) => ({ physical_card_id: id(i + 1), collection_id: COL_1 }));
  assert.deepEqual(await resolveMoveSet(col.client(), req([K1], { colecao: COL_1 }, LOC_A)), { ok: false, reason: "too_large" });

  const many = new FakeDb();
  many.addCopies(2001, 1); // candidatos acima do teto de leitura → fail-closed
  assert.deepEqual(await resolveMoveSet(many.client(), req([K1], { colecao: COL_1 }, LOC_A)), { ok: false, reason: "too_large" });
});

test("salvaguarda 2: conjunto mudando durante a leitura → unavailable, nunca parcial", async () => {
  const db = new FakeDb();
  db.maxRows = 5;
  db.addCopies(12, 1);
  db.onRead = (table, call) => {
    if (table === "physical_card" && call === 5) db.addCopies(1, 100);
  };
  assert.deepEqual(await resolveMoveSet(db.client(), req([K1], {}, LOC_A)), { ok: false, reason: "unavailable" });
});

test("salvaguarda 3: só o inventário do chamador; destino alheio → storage_gone; sem sessão", async () => {
  const db = new FakeDb();
  db.addCopies(2, 1);
  db.addCopies(3, 50, { inventory: OTHER_INV });
  const r = await resolveMoveSet(db.client(), req([K1], {}, LOC_A));
  assert.ok(r.ok);
  assert.equal(r.preview.total, 2);
  const otherTarget = "12121212-1212-4212-8212-121212121212";
  assert.deepEqual(await resolveMoveSet(db.client(), req([K1], {}, otherTarget)), { ok: false, reason: "storage_gone" });
  db.user = null;
  assert.deepEqual(await resolveMoveSet(db.client(), req([K1], {}, LOC_A)), { ok: false, reason: "not_authenticated" });
});

test("salvaguarda 1: chave sem exemplar aparece na prévia e bloqueia a escrita", async () => {
  const db = new FakeDb();
  db.addCopies(2, 1);
  const r = await resolveMoveSet(db.client(), req([K1, K2], {}, LOC_A));
  assert.ok(r.ok);
  assert.deepEqual(r.preview.unresolvedKeys, [`${V2}.en`]);
  const e = await executeMove(db.client(), { ...req([K1, K2], {}, LOC_A), planToken: r.preview.token, expectedCount: 2 });
  assert.deepEqual(e, { ok: false, reason: "unresolved" });
  assert.equal(db.writes.length, 0);
  const nothing = await resolveMoveSet(db.client(), req([K2], {}, LOC_A));
  assert.deepEqual(nothing, { ok: false, reason: "empty" });
});

// ---------------------------------------------------------------- execução
async function preview(db: FakeDb, params: Record<string, string>, target: string | null, keys = [K1]) {
  const r = await resolveMoveSet(db.client(), req(keys, params, target));
  assert.ok(r.ok);
  return r.preview;
}

test("confirmação: uma única chamada à 5024 com exatamente os ids a mover", async () => {
  const db = new FakeDb();
  db.addCopies(2, 1);
  db.addCopies(1, 3, { storage: LOC_A });
  const p = await preview(db, {}, LOC_A);
  const e = await executeMove(db.client(), { ...req([K1], {}, LOC_A), planToken: p.token, expectedCount: p.toMove });
  assert.deepEqual(e, { ok: true, updated: 2, atTarget: 1, targetName: "Fichário" });
  assert.equal(db.writes.length, 1);
  assert.deepEqual(db.writes[0], { ids: [id(1), id(2)], target: LOC_A });
});

test("destino nulo remove a localização", async () => {
  const db = new FakeDb();
  db.addCopies(2, 1, { storage: LOC_A });
  const p = await preview(db, { local: LOC_A }, null);
  const e = await executeMove(db.client(), { ...req([K1], { local: LOC_A }, null), planToken: p.token, expectedCount: p.toMove });
  assert.ok(e.ok);
  assert.deepEqual(db.writes[0], { ids: [id(1), id(2)], target: null });
});

test("todos já no destino: nada a gravar, sem chamar a 5024", async () => {
  const db = new FakeDb();
  db.addCopies(2, 1, { storage: LOC_A });
  const p = await preview(db, {}, LOC_A);
  assert.equal(p.toMove, 0);
  const e = await executeMove(db.client(), { ...req([K1], {}, LOC_A), planToken: p.token, expectedCount: 0 });
  assert.deepEqual(e, { ok: true, updated: 0, atTarget: 2, targetName: "Fichário" });
  assert.equal(db.writes.length, 0);
});

test("exemplar removido, adicionado ou movido entre prévia e confirmação → plan_changed", async () => {
  for (const change of ["removed", "added", "moved"] as const) {
    const db = new FakeDb();
    db.addCopies(3, 1);
    const p = await preview(db, {}, LOC_A);
    if (change === "removed") db.tables.physical_card!.pop();
    if (change === "added") db.addCopies(1, 9);
    if (change === "moved") db.tables.physical_card![0]!.storage_container_id = LOC_B;
    const e = await executeMove(db.client(), { ...req([K1], {}, LOC_A), planToken: p.token, expectedCount: p.toMove });
    assert.equal(e.ok, false, change);
    assert.equal(!e.ok && e.reason, "plan_changed", change);
    assert.ok(!e.ok && e.reason === "plan_changed" && "preview" in e && e.preview.token !== p.token, change);
    assert.equal(db.writes.length, 0, change);
  }
});

test("quantidade confirmada diferente da prévia → plan_changed", async () => {
  const db = new FakeDb();
  db.addCopies(3, 1);
  const p = await preview(db, {}, LOC_A);
  const e = await executeMove(db.client(), { ...req([K1], {}, LOC_A), planToken: p.token, expectedCount: 99 });
  assert.equal(!e.ok && e.reason, "plan_changed");
  assert.equal(db.writes.length, 0);
});

test("confirmação duplicada: a segunda não grava de novo", async () => {
  const db = new FakeDb();
  db.addCopies(3, 1);
  const p = await preview(db, {}, LOC_A);
  const input = { ...req([K1], {}, LOC_A), planToken: p.token, expectedCount: p.toMove };
  const [first, second] = [await executeMove(db.client(), input), await executeMove(db.client(), input)];
  assert.ok(first.ok);
  assert.equal(!second.ok && second.reason, "plan_changed");
  assert.equal(db.writes.length, 1);
});

test("resultado desconhecido (rede/forma) e erros definitivos do banco", async () => {
  const cases: [Partial<FakeDb>, string][] = [
    [{ writeThrows: true }, "unknown"],
    [{ writeResult: () => ({ data: null, error: { message: "TypeError: fetch failed" } }) }, "unknown"],
    [{ writeResult: () => ({ data: { weird: true }, error: null }) }, "unknown"],
    [{ writeResult: () => ({ data: null, error: { code: "P0001", message: "um ou mais physical_card_ids não pertencem ao inventory do chamador" } }) }, "plan_changed"],
    [{ writeResult: () => ({ data: null, error: { code: "P0001", message: "storage container not found" } }) }, "storage_gone"],
    [{ writeResult: () => ({ data: null, error: { code: "57014", message: "statement timeout" } }) }, "unavailable"],
  ];
  for (const [patch, expected] of cases) {
    const db = Object.assign(new FakeDb(), patch);
    db.addCopies(2, 1);
    const p = await preview(db, {}, LOC_A);
    const e = await executeMove(db.client(), { ...req([K1], {}, LOC_A), planToken: p.token, expectedCount: p.toMove });
    assert.equal(!e.ok && e.reason, expected);
    assert.ok(db.writes.length <= 1, "nunca repete a escrita");
  }
});

test("destino excluído entre prévia e confirmação → storage_gone, sem escrita", async () => {
  const db = new FakeDb();
  db.addCopies(2, 1);
  const p = await preview(db, {}, LOC_A);
  db.tables.storage_container = db.tables.storage_container!.filter((r) => r.id !== LOC_A);
  const e = await executeMove(db.client(), { ...req([K1], {}, LOC_A), planToken: p.token, expectedCount: p.toMove });
  assert.deepEqual(e, { ok: false, reason: "storage_gone" });
  assert.equal(db.writes.length, 0);
});
