import assert from "node:assert/strict";
import { test } from "node:test";
import { effectiveRegisterMode, registerHref, wantsRegister } from "./collection-add.ts";

test("wantsRegister só aceita cartas e set", () => {
  assert.equal(wantsRegister({ cadastrar: "cartas" }), "cards");
  assert.equal(wantsRegister({ cadastrar: ["set", "x"] }), "set");
  assert.equal(wantsRegister({ cadastrar: "1" }), null);
  assert.equal(wantsRegister({}), null);
});

test("registerHref preserva query existente", () => {
  assert.equal(registerHref("/colecoes/colecoes/a", "set"), "/colecoes/colecoes/a?cadastrar=set");
  assert.equal(registerHref("/colecoes/colecoes/a?filtro=x", "cards"), "/colecoes/colecoes/a?filtro=x&cadastrar=cartas");
});

test("Set inteiro só com Set de referência", () => {
  assert.equal(effectiveRegisterMode("set", true), "set");
  assert.equal(effectiveRegisterMode("set", false), "cards");
  assert.equal(effectiveRegisterMode("cards", false), "cards");
});
