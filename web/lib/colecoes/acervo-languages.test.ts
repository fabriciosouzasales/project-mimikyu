// Meu acervo — leitura de idiomas do cadastro (INVENTORY-LANGUAGE-READ-01, Query 5164).
// Executar: node --experimental-strip-types --test lib/colecoes/acervo-languages.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { getAddLanguages, toAddLanguages } from "./acervo-queries.ts";

const PT = "7a7d7c56-80f7-49c6-a837-24486e820484";
const EN = "138849d1-79d9-41e4-bd36-1413980bca3d";

type RpcResult = { data: unknown; error: { code?: string; message?: string } | null };

function fakeClient(result: RpcResult, calls: string[] = []) {
  return {
    rpc: async (fn: string) => {
      calls.push(fn);
      return result;
    },
    from: () => {
      throw new Error("leitura direta de tabela não é permitida aqui");
    },
  } as never;
}

test("toAddLanguages mapeia language_id → id e preserva a ordem do banco", () => {
  assert.deepEqual(
    toAddLanguages([
      { language_id: PT, code: "pt-BR", name: "Português (Brasil)", language_order: 1 },
      { language_id: EN, code: "en", name: "English", language_order: 2 },
    ]),
    [
      { id: PT, code: "pt-BR", name: "Português (Brasil)" },
      { id: EN, code: "en", name: "English" },
    ],
  );
});

test("toAddLanguages descarta linhas malformadas", () => {
  assert.deepEqual(toAddLanguages([{ language_id: null, code: "x", name: "X", language_order: 1 } as never]), []);
});

test("getAddLanguages usa só a RPC get_registrable_languages (nunca a tabela)", async () => {
  const calls: string[] = [];
  const result = await getAddLanguages(
    fakeClient({ data: [{ language_id: PT, code: "pt-BR", name: "Português (Brasil)", language_order: 1 }], error: null }, calls),
  );
  assert.deepEqual(calls, ["get_registrable_languages"]);
  assert.equal(result.length, 1);
});

test("getAddLanguages: erro, função ausente ou sem sessão → lista vazia (ações ocultas)", async () => {
  const original = console.error;
  console.error = () => {};
  try {
    for (const error of [{ code: "PGRST202" }, { code: "28000" }, { code: "42501" }]) {
      assert.deepEqual(await getAddLanguages(fakeClient({ data: null, error })), []);
    }
    assert.deepEqual(await getAddLanguages(fakeClient({ data: { not: "array" }, error: null })), []);
  } finally {
    console.error = original;
  }
});
