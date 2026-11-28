// V1-13 · E4 — testes da sonda (sem rede). Executar: node --test scripts/v1-13/e4-probe.test.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { capture, evaluate, expand, forbiddenKeys, validateCases } from "./e4-probe.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TK = `pc1.${"a".repeat(64)}`;

test("modelo de casos do pacote é válido (com e-mails de exemplo)", () => {
  const p = join(HERE, "..", "..", "database", "proposals", "2026-11-27-v1-13-e4-homologation");
  for (const f of ["E4_PROBE_G3_CLOSED.template.json", "E4_PROBE_TEST.template.json"]) {
    const c = JSON.parse(readFileSync(join(p, f), "utf8"));
    for (const k of Object.keys(c.sessions)) c.sessions[k] = `${k.toLowerCase()}@exemplo.test`;
    assert.deepEqual(validateCases(c), [], f);
  }
});

test("validação recusa sessão desconhecida, expect inválido, id repetido e Storage com aceite", () => {
  const base = { sessions: { E: "e@x.test" }, steps: [{ id: "a", as: "E", rpc: "abc", expect: "ok" }] };
  assert.deepEqual(validateCases(base), []);
  assert.ok(validateCases({ ...base, steps: [{ id: "a", as: "Z", rpc: "abc", expect: "ok" }] }).length);
  assert.ok(validateCases({ ...base, steps: [{ id: "a", as: "E", rpc: "abc", expect: "talvez" }] }).length);
  assert.ok(validateCases({ ...base, steps: [base.steps[0], base.steps[0]] }).length);
  assert.ok(validateCases({ ...base, steps: [{ id: "s", as: "E", storage_upload: { bucket: "b", path: "p" }, expect: "ok" }] }).length);
  assert.ok(validateCases({ sessions: { E: "sem-arroba" }, steps: base.steps }).length);
});

test("expansão: variáveis, uid, capturas, token forjado; variável ausente é erro", () => {
  const ctx = { vars: { X: "11111111-1111-4111-8111-111111111111" }, captured: { TK_E: TK }, uids: { T: "u-t" } };
  assert.deepEqual(expand({ a: "{X}", b: ["{uid:T}/{X}/f.png"], c: "{TK_E}", d: 3 }, ctx),
    { a: ctx.vars.X, b: [`u-t/${ctx.vars.X}/f.png`], c: TK, d: 3 });
  const f = expand("{FORGED_TOKEN}", ctx);
  assert.match(f, /^pc1\.[0-9a-f]{64}$/);
  assert.notEqual(f, TK);
  assert.deepEqual(expand({ p: "{P}", t: "p{P}" }, { ...ctx, vars: { ...ctx.vars, P: 66 } }), { p: 66, t: "p66" }, "número continua número");
  assert.throws(() => expand("{Y}", ctx), /variável ausente/);
  assert.throws(() => expand("{uid:V}", ctx), /uid desconhecido/);
});

test("avaliação: ok, refused, empty, code, msg; chave proibida derruba qualquer PASS", () => {
  const s = (expect, extra = {}) => ({ id: "x", expect, ...extra });
  assert.equal(evaluate(s("ok"), { http: 200, body: [{ copy_token: TK }] }).pass, true);
  assert.equal(evaluate(s("ok"), { http: 403, body: null }).pass, false);
  assert.equal(evaluate(s("refused"), { http: 401, body: null }).pass, true);
  assert.equal(evaluate(s("refused"), { http: 200, body: [] }).pass, false, "aceite inesperado");
  assert.equal(evaluate(s("empty"), { http: 200, body: [] }).pass, true);
  assert.equal(evaluate(s("empty"), { http: 200, body: [{ a: 1 }] }).pass, false);
  assert.equal(evaluate(s("code:42501"), { http: 403, code: "42501", body: null }).pass, true);
  assert.equal(evaluate(s("code:42501"), { http: 400, code: "22023", body: null }).pass, false);
  assert.equal(evaluate(s("msg:CAPABILITY_NOT_ENABLED"), { http: 403, msg: "CAPABILITY_NOT_ENABLED", body: null }).pass, true);
  const leak = evaluate(s("ok"), { http: 200, body: { items: [{ ord: 1, physical_card_id: "x" }] } });
  assert.equal(leak.pass, false);
  assert.deepEqual(leak.keys, ["physical_card_id"]);
  assert.deepEqual(forbiddenKeys([{ image_path: "a", card_name: "b", total_count: 1 }]), [], "image_path é catálogo");
  assert.deepEqual(forbiddenKeys({ a: { owner_user_id: 1, email: 2 } }), ["email", "owner_user_id"]);
});

test("captura: copy_token só token opaco; demais campos só UUID", () => {
  const c = {};
  const U = "11111111-1111-4111-8111-111111111111";
  assert.equal(capture({ id: "a", capture: { TK_E: "copy_token" } }, [{ copy_token: TK }], c), null);
  assert.equal(c.TK_E, TK);
  assert.match(capture({ id: "b", capture: { X: "copy_token" } }, [{ copy_token: U }], {}), /sem token/);
  assert.match(capture({ id: "c", capture: { X: "copy_token" } }, [], {}), /sem token/);
  assert.equal(capture({ id: "d", capture: { POS: "pokedex_position_id" } }, [{ pokedex_position_id: U }], c), null);
  assert.equal(c.POS, U);
  assert.match(capture({ id: "e", capture: { POS: "pokedex_position_id" } }, [{ pokedex_position_id: TK }], {}), /sem identificador/);
});

test("a sonda não executa SQL, não muda barreira e não imprime corpo nem token", () => {
  const src = readFileSync(join(HERE, "e4-probe.mjs"), "utf8");
  assert.doesNotMatch(src, /v1_13_barrier|\/rest\/v1\/(?!rpc)|service_role|SUPABASE_SERVICE/);
  assert.doesNotMatch(src, /console\.log\([^)]*(body|token|password)/);
  assert.doesNotMatch(src, /writeFileSync\([^)]*(password|token)/);
});
