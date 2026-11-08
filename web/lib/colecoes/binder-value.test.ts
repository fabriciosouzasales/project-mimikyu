// Valor do Fichário (BINDER-VALUE, 05d v2.74, D1–D9): leitura (5223/5252 → 5357 → 3989),
// reaproveitamento do núcleo financeiro da R2-E, textos do cartão e reaproveitamento (D4).
// Executar: node --experimental-strip-types --test lib/colecoes/binder-value.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { buildCollectionValueReport } from "../reports/collection-value.ts";
import {
  BINDER_VALUE_REUSE_MS,
  type BinderValueSummary,
  binderValueCoveragePercent,
  binderValueCoverageText,
  binderValueNeedsRead,
  binderValueNotices,
  binderValueObservedText,
  binderValueSetKey,
  binderValueTotalText,
} from "./binder-value.ts";
import { BINDER_VALUE_PAGE, RPC_5357, prepareBinderValue } from "./binder-value-queries.ts";

console.error = () => {};
console.warn = () => {};
console.info = () => {};

const uuid = (n: number) => `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
const COLLECTION = uuid(9001);
const NOW = Date.parse("2026-11-08T12:00:00Z");
const PRICES_RPC = "get_card_variants_pricing_summary";

type Group = { variant: number; lang?: string; copies: number };

/** "Banco" falso: cabeçalho do fichário (5223/5252), grupos dos bolsos (5357) e preços (3989). */
function fakeClient(
  groups: Group[],
  options: {
    header?: "missing" | "error" | "no_binder";
    filled?: number;
    failGroups?: string;
    failPricesFor?: number;
    priced?: (variant: number) => number | null;
    observedAt?: (variant: number) => string;
    duplicateOnPage2?: boolean;
    totalChangesOnPage2?: boolean;
  } = {},
) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const copiesTotal = groups.reduce((s, g) => s + g.copies, 0);
  const client = {
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      await new Promise((resolve) => setTimeout(resolve, 1));
      if (fn === "get_my_collection_binder") {
        if (options.header === "error") return { data: null, error: { code: "57014", message: "canceling statement" } };
        if (options.header === "missing" || args.p_collection_id !== COLLECTION) return { data: null, error: { code: "P0002", message: "COLLECTION_NOT_FOUND" } };
        const hasBinder = options.header !== "no_binder";
        return {
          data: [
            {
              collection_id: COLLECTION,
              collection_name: "Minha coleção",
              collection_kind: "SET",
              lifecycle_status: "ACTIVE",
              has_binder: hasBinder,
              layout_id: hasBinder ? uuid(8001) : null,
              grid_columns: hasBinder ? 3 : null,
              grid_rows: hasBinder ? 3 : null,
              page_count: hasBinder ? 10 : 0,
              slot_count: hasBinder ? 90 : 0,
              filled_count: hasBinder ? (options.filled ?? copiesTotal) : 0,
              binder_role: hasBinder ? "OWNER" : null,
            },
          ],
          error: null,
        };
      }
      if (fn === RPC_5357) {
        if (options.failGroups) return { data: null, error: { code: options.failGroups } };
        if (args.p_collection_id !== COLLECTION) return { data: null, error: { code: "P0002" } };
        const offset = Number(args.p_offset);
        const limit = Number(args.p_limit);
        let page = groups.slice(offset, offset + limit);
        if (options.duplicateOnPage2 && offset > 0) page = [groups[0] as Group, ...page.slice(1)];
        const totalCount = groups.length + (options.totalChangesOnPage2 && offset > 0 ? 1 : 0);
        return {
          data: page.map((g) => ({
            card_variant_id: uuid(g.variant),
            language_code: g.lang ?? "en",
            language_name: "Inglês",
            card_name: `Carta ${g.variant}`,
            collector_number: String(g.variant),
            collector_total: 200,
            card_set_code: "ME5.5",
            card_set_name: "Celebração",
            is_default_variant: true,
            variant_label: null,
            image_path: `cards/${g.variant}.webp`,
            copies_count: g.copies,
            total_count: totalCount,
            total_copies: copiesTotal,
          })),
          error: null,
        };
      }
      if (fn === PRICES_RPC) {
        const ids = args.p_card_variant_ids as string[];
        if (options.failPricesFor !== undefined && ids.includes(uuid(options.failPricesFor))) return { data: null, error: { code: "42501" } };
        return {
          data: ids.map((id) => {
            const v = Number.parseInt(id.slice(-12), 16);
            const brl = options.priced ? options.priced(v) : v;
            return {
              card_variant_id: id,
              has_pricing: brl !== null && brl > 0,
              brl_amount: brl,
              price_basis: "VARIANT",
              price_origin: "AUTOMATIC",
              fx_status: "CONVERTED",
              observed_at: options.observedAt ? options.observedAt(v) : "2026-11-07T12:00:00Z",
            };
          }),
          error: null,
        };
      }
      return { data: null, error: { code: "PGRST202" } };
    },
  };
  return { client, calls };
}

const groupsOf = (n: number, copies = 1): Group[] => Array.from({ length: n }, (_, i) => ({ variant: i + 1, copies }));

async function prepare(fake: ReturnType<typeof fakeClient>) {
  return prepareBinderValue(fake.client as never, COLLECTION, new Date(NOW));
}

function summaryOf(result: Awaited<ReturnType<typeof prepareBinderValue>>): BinderValueSummary {
  assert.equal(result.status, "ready");
  return (result as { status: "ready"; summary: BinderValueSummary }).summary;
}

// ---------------------------------------------------------------------------
// Leitura e cálculo

test("ordem: cabeçalho (titularidade + filled_count) → 5357 em sequência, páginas de 200 → 3989; só leitura", async () => {
  const fake = fakeClient(groupsOf(450, 1));
  const s = summaryOf(await prepare(fake));
  assert.equal(fake.calls[0]?.fn, "get_my_collection_binder");
  const groupCalls = fake.calls.filter((c) => c.fn === RPC_5357);
  assert.deepEqual(
    groupCalls.map((c) => [c.args.p_offset, c.args.p_limit]),
    [
      [0, BINDER_VALUE_PAGE],
      [200, BINDER_VALUE_PAGE],
      [400, BINDER_VALUE_PAGE],
    ],
  );
  // O navegador nunca escolhe outro id: toda chamada usa só a coleção informada.
  for (const c of [...groupCalls, fake.calls[0]]) assert.equal(c?.args.p_collection_id, COLLECTION);
  assert.deepEqual([...new Set(fake.calls.map((c) => c.fn))].sort(), [PRICES_RPC, RPC_5357, "get_my_collection_binder"].sort());
  assert.equal(s.copies, 450);
  assert.equal(s.complete, true);
});

test("valor = cálculo da R2-E (centavos), sem segundo mecanismo: mesmo total que buildCollectionValueReport", async () => {
  const groups: Group[] = [
    { variant: 1, copies: 3 },
    { variant: 2, copies: 2 },
    { variant: 3, lang: "ja", copies: 1 },
  ];
  const prices: Record<number, number> = { 1: 10.005, 2: 0.1, 3: 1234.56 };
  const s = summaryOf(await prepare(fakeClient(groups, { priced: (v) => prices[v] ?? null })));
  assert.equal(s.totalCents, Math.round(10.005 * 100) * 3 + 10 * 2 + 123456);
  assert.equal(binderValueTotalText(s).replace(/\s/g, " "), "R$ 1.264,79");
  // O mesmo núcleo, chamado direto, dá o mesmo número.
  const direct = buildCollectionValueReport({
    items: groups.map((g, order) => ({
      cardVariantId: uuid(g.variant),
      languageCode: g.lang ?? "en",
      cardName: "x",
      collectorNumber: null,
      collectorTotal: null,
      cardSetCode: "S",
      cardSetName: "S",
      variantLabel: null,
      isDefaultVariant: true,
      copies: g.copies,
      order,
    })),
    prices: new Map(groups.map((g) => [uuid(g.variant), { brl: prices[g.variant] as number, basis: "VARIANT" as const, observedAt: "2026-11-07T12:00:00Z" }])),
    unavailable: new Set(),
    read: { totalCount: 3, totalCopies: 6, duplicate: false, inconsistentPages: false },
    collectionCopies: 6,
    now: NOW,
  });
  assert.equal(s.totalCents, direct.totalCents);
});

test("cópias repetidas somam individualmente; idiomas diferentes são grupos diferentes; sem dupla contagem", async () => {
  const s = summaryOf(
    await prepare(
      fakeClient(
        [
          { variant: 1, copies: 4 },
          { variant: 1, lang: "pt", copies: 1 },
        ],
        { priced: () => 2 },
      ),
    ),
  );
  assert.equal(s.copies, 5);
  assert.equal(s.totalCents, 1000);
  assert.equal(s.complete, true);
});

test("fichário vazio: nenhum exemplar nos bolsos → estado vazio, sem 5357 nem preços", async () => {
  const fake = fakeClient([], { filled: 0 });
  const s = summaryOf(await prepare(fake));
  assert.equal(s.state, "empty");
  assert.equal(s.totalCents, null);
  assert.deepEqual(
    fake.calls.map((c) => c.fn),
    ["get_my_collection_binder"],
  );
});

test("sem cotação (B): fica fora da soma e nunca vale zero; cobertura conta só as cotadas", async () => {
  const s = summaryOf(await prepare(fakeClient(groupsOf(4, 1), { priced: (v) => (v <= 2 ? 5 : null) })));
  assert.equal(s.totalCents, 1000);
  assert.equal(s.unpricedCopies, 2);
  assert.equal(binderValueCoverageText(s), "2 de 4 cartas cotadas");
  assert.equal(binderValueCoveragePercent(s), 50);
  assert.ok(binderValueNotices(s).some((t) => t.includes("2 cartas sem cotação ficam fora da soma")));
  const none = summaryOf(await prepare(fakeClient(groupsOf(2, 1), { priced: () => null })));
  assert.equal(none.totalCents, null);
  assert.equal(binderValueTotalText(none), "Sem cotação");
});

test("erro de preço (C): parcial explícito, nunca B nem zero; todo indisponível → 'Indisponível'", async () => {
  const s = summaryOf(await prepare(fakeClient(groupsOf(150, 1), { failPricesFor: 140 })));
  assert.equal(s.provisional, true);
  assert.equal(s.unavailableCopies, 50); // o bloco de 100 ids com a variante 140 falhou
  assert.equal(s.unpricedCopies, 0);
  assert.ok(binderValueNotices(s).some((t) => t.includes("falha temporária")));
  const all = summaryOf(await prepare(fakeClient(groupsOf(3, 1), { failPricesFor: 1 })));
  assert.equal(all.totalCents, null);
  assert.equal(binderValueTotalText(all), "Indisponível");
});

test("conferência: Σ ≠ filled_count, grupo repetido ou total mudando entre páginas → não definitivo", async () => {
  const mismatch = summaryOf(await prepare(fakeClient(groupsOf(3, 1), { filled: 4 })));
  assert.equal(mismatch.complete, false);
  assert.equal(mismatch.incompleteReason, "collection_mismatch");
  assert.ok(binderValueNotices(mismatch)[0]?.includes("não definitivo"));
  const dup = summaryOf(await prepare(fakeClient(groupsOf(250, 1), { duplicateOnPage2: true })));
  assert.equal(dup.complete, false);
  const moving = summaryOf(await prepare(fakeClient(groupsOf(250, 1), { totalChangesOnPage2: true })));
  assert.equal(moving.complete, false);
});

test("isolamento: coleção alheia/inexistente → not_found sem nenhuma leitura de grupos ou preços", async () => {
  const missing = fakeClient(groupsOf(3, 1), { header: "missing" });
  assert.deepEqual(await prepare(missing), { status: "not_found" });
  assert.deepEqual(
    missing.calls.map((c) => c.fn),
    ["get_my_collection_binder"],
  );
  // A 5357 também recusa (defesa no banco): P0002 vira not_found, nunca dado.
  const refused = fakeClient(groupsOf(3, 1), { failGroups: "P0002" });
  assert.deepEqual(await prepare(refused), { status: "not_found" });
  assert.equal(refused.calls.some((c) => c.fn === PRICES_RPC), false);
  const noBinder = fakeClient([], { header: "no_binder" });
  assert.deepEqual(await prepare(noBinder), { status: "no_binder" });
  const broken = fakeClient(groupsOf(3, 1), { header: "error" });
  assert.deepEqual(await prepare(broken), { status: "error" });
  const failing = fakeClient(groupsOf(3, 1), { failGroups: "57014" });
  assert.deepEqual(await prepare(failing), { status: "error" });
});

test("resumo para o navegador: sem linhas nem ids; sinais de atualização das referências", async () => {
  const s = summaryOf(
    await prepare(
      fakeClient(groupsOf(3, 2), { observedAt: (v) => (v === 1 ? "2026-10-01T12:00:00Z" : "2026-11-07T12:00:00Z") }),
    ),
  );
  assert.equal(JSON.stringify(s).includes(uuid(1)), false);
  assert.equal("lines" in s, false);
  assert.equal(s.staleCopies, 2);
  assert.equal(binderValueObservedText(s), "Preços de 01/10/2026 a 07/11/2026");
  assert.ok(binderValueNotices(s).some((t) => t.includes("mais de 14 dias")));
});

// ---------------------------------------------------------------------------
// Reaproveitamento e invalidação (D4)

const ready = (over: Partial<BinderValueSummary> = {}): BinderValueSummary => ({
  state: "ready",
  totalCents: 100,
  copies: 1,
  pricedCopies: 1,
  unpricedCopies: 0,
  unavailableCopies: 0,
  provisional: false,
  complete: true,
  incompleteReason: null,
  staleCopies: 0,
  generalCopies: 0,
  observedFrom: null,
  observedTo: null,
  ...over,
});

test("chave do conjunto: muda com a contagem ou com escrita que muda os bolsos; mover não muda", () => {
  assert.equal(binderValueSetKey(10, 0), binderValueSetKey(10, 0));
  assert.notEqual(binderValueSetKey(10, 0), binderValueSetKey(11, 0)); // carta entrou
  assert.notEqual(binderValueSetKey(10, 0), binderValueSetKey(10, 1)); // substituição/organização com troca de cartas
});

test("reaproveita só o mesmo conjunto, recente, completo e não parcial; relê no resto", () => {
  const key = binderValueSetKey(5, 2);
  const entry = { setKey: key, readAt: NOW, summary: ready() };
  assert.equal(binderValueNeedsRead(undefined, key, NOW), true);
  assert.equal(binderValueNeedsRead(entry, key, NOW + 60_000), false); // reabrir a seção: reaproveita
  assert.equal(binderValueNeedsRead(entry, binderValueSetKey(5, 3), NOW), true); // conjunto mudou
  assert.equal(binderValueNeedsRead(entry, key, NOW + BINDER_VALUE_REUSE_MS + 1), true); // referência envelheceu
  assert.equal(binderValueNeedsRead(entry, key, NOW - 1), true); // relógio voltou: não confia
  assert.equal(binderValueNeedsRead({ ...entry, summary: ready({ complete: false }) }, key, NOW), true);
  assert.equal(binderValueNeedsRead({ ...entry, summary: ready({ provisional: true }) }, key, NOW), true);
});

test("textos: cobertura no singular, sem datas → sem linha de atualização", () => {
  assert.equal(binderValueCoverageText({ pricedCopies: 1, copies: 1 }), "1 de 1 carta cotada");
  assert.equal(binderValueCoveragePercent({ pricedCopies: 0, copies: 0 }), 0);
  assert.equal(binderValueObservedText({ observedFrom: null, observedTo: null }), null);
  assert.equal(binderValueObservedText({ observedFrom: "2026-11-07T12:00:00Z", observedTo: "2026-11-07T12:00:00Z" }), "Preços de 07/11/2026");
});
