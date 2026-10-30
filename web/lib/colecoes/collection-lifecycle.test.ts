import assert from "node:assert/strict";
import { test } from "node:test";
import {
  archivedCount,
  archivedLibraryHref,
  archivedOffset,
  classifyLifecycleFailure,
  isArchivedView,
  isLifecycleStatus,
  lifecycleFailureMessage,
} from "./collection-lifecycle.ts";

test("isArchivedView só aceita arquivadas=1", () => {
  assert.equal(isArchivedView({ arquivadas: "1" }), true);
  assert.equal(isArchivedView({ arquivadas: ["1", "0"] }), true);
  assert.equal(isArchivedView({ arquivadas: "true" }), false);
  assert.equal(isArchivedView({}), false);
});

test("archivedLibraryHref com e sem página", () => {
  assert.equal(archivedLibraryHref(), "/colecoes/colecoes?arquivadas=1");
  assert.equal(archivedLibraryHref(1), "/colecoes/colecoes?arquivadas=1");
  assert.equal(archivedLibraryHref(3), "/colecoes/colecoes?arquivadas=1&pagina=3");
});

test("archivedOffset começa depois de todas as ativas (5182: ativas primeiro)", () => {
  assert.equal(archivedOffset(0, 1, 24), 0);
  assert.equal(archivedOffset(7, 1, 24), 7);
  assert.equal(archivedOffset(7, 2, 24), 31);
  assert.equal(archivedOffset(-3, 0, 24), 0);
  assert.equal(archivedOffset(Number.NaN, 2, 24), 24);
});

test("archivedCount nunca é negativo", () => {
  assert.equal(archivedCount(10, 7), 3);
  assert.equal(archivedCount(7, 7), 0);
  assert.equal(archivedCount(5, 7), 0);
  assert.equal(archivedCount(Number.NaN, 2), 0);
});

test("isLifecycleStatus", () => {
  assert.equal(isLifecycleStatus("ACTIVE"), true);
  assert.equal(isLifecycleStatus("ARCHIVED"), true);
  assert.equal(isLifecycleStatus("archived"), false);
  assert.equal(isLifecycleStatus(null), false);
});

test("classifyLifecycleFailure mapeia as recusas das 5037/5038 sem expor texto cru", () => {
  assert.equal(classifyLifecycleFailure("P0001", "collection not found or not owned by caller"), "not_found");
  assert.equal(classifyLifecycleFailure("P0001", "authentication required"), "not_authenticated");
  assert.equal(classifyLifecycleFailure("42501", "permission denied for function archive_collection"), "not_authenticated");
  assert.equal(classifyLifecycleFailure("22P02", "invalid input syntax for type uuid"), "invalid");
  assert.equal(classifyLifecycleFailure(null, null), "unavailable");
});

test("mensagens dizem o que continua igual", () => {
  assert.match(lifecycleFailureMessage("unavailable", "archive"), /continua ativa/);
  assert.match(lifecycleFailureMessage("unavailable", "reactivate"), /continua arquivada/);
  assert.match(lifecycleFailureMessage("not_found", "archive"), /Nada foi alterado/);
});
