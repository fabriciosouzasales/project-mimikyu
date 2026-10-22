// WHERE-04 — filtro "Localização física" do Meu acervo (regras puras).
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-storage-filter.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  copyMatchesStorageFilter,
  storageEmptyReason,
  storageFilterChipLabel,
  storageFilterFromValue,
  storageFilterName,
  storageFilterOptions,
  storageFilterStatus,
  storageFilterValue,
} from "./acervo-storage-filter.ts";
import type { StorageLocation } from "./storage-locations.ts";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";
const GONE = "33333333-3333-4333-8333-333333333333";

const loc = (id: string, name: string, cardCount: number, kindLabel: string | null = null): StorageLocation => ({
  id,
  name,
  kindCode: kindLabel ? "BINDER" : null,
  kindLabel,
  cardCount,
  defaultCollectionCount: 0,
  canDelete: cardCount === 0,
});

const LOCATIONS = [loc(A, "Fichário A", 1200, "Fichário"), loc(B, "Caixa B", 0)];

test("situação do filtro: todos, sem local, local, excluído e lista indisponível", () => {
  assert.deepEqual(storageFilterStatus({ kind: "all" }, LOCATIONS), { kind: "all" });
  assert.deepEqual(storageFilterStatus({ kind: "none" }, null), { kind: "none" });
  const found = storageFilterStatus({ kind: "location", id: A }, LOCATIONS);
  assert.equal(found.kind, "location");
  assert.equal(storageFilterName(found), "Fichário A");
  assert.deepEqual(storageFilterStatus({ kind: "location", id: GONE }, LOCATIONS), { kind: "missing", id: GONE });
  assert.deepEqual(storageFilterStatus({ kind: "location", id: A }, null), { kind: "unknown", id: A });
  assert.equal(storageFilterName({ kind: "unknown", id: A }), null);
});

test("valor do seletor: ida e volta com a URL", () => {
  for (const filter of [{ kind: "all" }, { kind: "none" }, { kind: "location", id: A }] as const) {
    assert.deepEqual(storageFilterFromValue(storageFilterValue(filter)), filter);
  }
  assert.deepEqual(storageFilterFromValue("__vazio__"), { kind: "all" });
  assert.deepEqual(storageFilterFromValue("__indisponivel__"), { kind: "all" });
  assert.deepEqual(storageFilterFromValue(A.toUpperCase()), { kind: "location", id: A });
});

test("opções: locais do usuário com tipo e contagem da 5219", () => {
  const { base, locations } = storageFilterOptions({ kind: "all" }, LOCATIONS);
  assert.deepEqual(base.map((o) => o.label), ["Todos os locais", "Sem localização definida"]);
  assert.deepEqual(locations, [
    { value: A, label: "Fichário A · Fichário (1.200)" },
    { value: B, label: "Caixa B (0)" },
  ]);
});

test("opções: nenhum local cadastrado e lista indisponível", () => {
  const empty = storageFilterOptions({ kind: "all" }, []);
  assert.deepEqual(empty.locations, [{ value: "__vazio__", label: "Nenhum local criado ainda", disabled: true }]);
  const failed = storageFilterOptions({ kind: "all" }, null);
  assert.equal(failed.locations.length, 1);
  assert.equal(failed.locations[0]?.disabled, true);
  // Sem locais, "Sem localização definida" continua disponível (todo o acervo está sem local).
  assert.ok(empty.base.some((o) => o.value === "sem"));
});

test("opções: local excluído continua representado no seletor", () => {
  const { locations } = storageFilterOptions({ kind: "location", id: GONE }, LOCATIONS);
  assert.deepEqual(locations[0], { value: GONE, label: "Local indisponível" });
  const unknown = storageFilterOptions({ kind: "location", id: A }, null);
  assert.deepEqual(unknown.locations[0], { value: A, label: "Local selecionado" });
});

test("chip do filtro ativo", () => {
  assert.equal(storageFilterChipLabel({ kind: "all" }), null);
  assert.equal(storageFilterChipLabel({ kind: "none" }), "Sem localização");
  assert.equal(storageFilterChipLabel(storageFilterStatus({ kind: "location", id: A }, LOCATIONS)), "Local: Fichário A");
  assert.equal(storageFilterChipLabel({ kind: "missing", id: GONE }), "Local indisponível");
  assert.equal(storageFilterChipLabel({ kind: "unknown", id: A }), "Local selecionado");
});

test("exemplar corresponde ao filtro (por id, nunca por nome)", () => {
  assert.equal(copyMatchesStorageFilter(A, { kind: "all" }), undefined);
  assert.equal(copyMatchesStorageFilter(A, { kind: "location", id: A }), true);
  assert.equal(copyMatchesStorageFilter(B, { kind: "location", id: A }), false);
  assert.equal(copyMatchesStorageFilter(null, { kind: "location", id: A }), false);
  assert.equal(copyMatchesStorageFilter(null, { kind: "none" }), true);
  assert.equal(copyMatchesStorageFilter(A, { kind: "none" }), false);
  // Local do exemplar desconhecido (contexto indisponível): sem destaque, nunca um falso "não".
  assert.equal(copyMatchesStorageFilter(undefined, { kind: "none" }), undefined);
});

test("motivo do vazio", () => {
  const status = (id: string) => storageFilterStatus({ kind: "location", id }, LOCATIONS);
  assert.equal(storageEmptyReason({ kind: "all" }, true), null);
  assert.equal(storageEmptyReason(status(GONE), false), "missing");
  assert.equal(storageEmptyReason(status(B), false), "empty_location");
  assert.equal(storageEmptyReason(status(B), true), "empty_location");
  assert.equal(storageEmptyReason(status(A), true), "combination");
  assert.equal(storageEmptyReason({ kind: "none" }, false), "all_located");
  assert.equal(storageEmptyReason({ kind: "none" }, true), "combination");
  assert.equal(storageEmptyReason({ kind: "unknown", id: A }, false), "combination");
});
