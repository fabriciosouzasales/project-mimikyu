// V1-13 · E3-7b — fichário compartilhado do EDITOR por identidade opaca (5397).
// Executar: node --experimental-strip-types --test lib/colecoes/e3-7b-binder-identity.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { hasForbiddenKey, isCopyToken } from "./copy-token.ts";
import { findUndoCandidate, parsePlaceableCards } from "./editor-binder.ts";
import { parseEditorAutoArrangePreview } from "./editor-binder-arrange.ts";
import * as pokedex from "./editor-pokedex.ts";

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const read = (f: string) => readFileSync(join(WEB, f), "utf8");
const TK = `pc1.${"b".repeat(64)}`;
const PHYS = "44444444-4444-4444-8444-444444444444";

function sources(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    if (name === "node_modules" || name.startsWith(".")) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) sources(p, out);
    else if (/\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name)) out.push(p);
  }
  return out;
}

test("token: o mesmo da 5391 (módulo neutro), reexportado pela Pokédex sem mudança", () => {
  assert.equal(pokedex.isCopyToken, isCopyToken);
  assert.equal(pokedex.hasForbiddenKey, hasForbiddenKey);
  assert.equal(isCopyToken(TK), true);
  for (const bad of [PHYS, "", null, `pc1.${"B".repeat(64)}`, `pc1.${"b".repeat(63)}`]) assert.equal(isCopyToken(bad), false, String(bad));
});

test("lista elegível (5397): token opaco como chave; seleção, arrastar e desfazer seguem pela chave", () => {
  const row = (t: string, over: Record<string, unknown> = {}) => ({ copy_token: t, card_name: "Pikachu", collector_number: "25", collector_total: 102, card_set_code: "base1", variant_label: null, language_code: "en", image_path: null, total_count: 2, ...over });
  const page = parsePlaceableCards([row(TK), row(`pc1.${"c".repeat(64)}`, { card_name: "Raichu", collector_number: "26" })])!;
  assert.deepEqual(page.items.map((i) => i.physicalCardId), [TK, `pc1.${"c".repeat(64)}`]);
  assert.ok(page.items.every((i) => isCopyToken(i.physicalCardId)), "nenhum UUID físico entra na lista do EDITOR");
  // Desfazer: o exemplar retirado volta à lista e é reencontrado pela face (único) → token.
  const removed = { present: { cardName: "Pikachu", collectorNumber: "25", collectorTotal: 102, setCode: "base1", imagePath: null, finishCode: null, finishName: null, languageCode: "en", variantLabel: null } };
  assert.equal(findUndoCandidate(page.items, removed as never)?.physicalCardId, TK);
});

test("prévia da organização automática (5397): sem id físico; contagens e páginas preservadas", () => {
  const u = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
  const it = (ord: number, page: number, col: number) => ({ ord, page_number: page, row_index: 1, column_index: col, card_id: u(3000 + ord), card_variant_id: u(4000 + ord) });
  const raw = { status: "READY", insert_count: 2, limit: 500, plan_token: `aa1:${"c".repeat(64)}`, excluded_cards: {}, unfilled_slots: {}, unfilled_count: 0, pages: [2], items: [it(1, 2, 1), it(2, 2, 2)] };
  const parsed = parseEditorAutoArrangePreview(raw);
  assert.ok(parsed);
  assert.equal(parsed.preview.insertCount, 2);
  assert.deepEqual(parsed.perPage, { 2: 2 });
  assert.equal(parseEditorAutoArrangePreview({ ...raw, items: [{ ...it(1, 2, 1), physical_card_id: PHYS }, it(2, 2, 2)] }), null, "contrato antigo recusado");
});

test("server actions e área de trabalho: só as RPCs da 5397; token na entrada; nenhum id físico enviado", () => {
  const act = read("app/colecoes/compartilhada/[id]/fichario/actions.ts");
  assert.match(act, /rpc\("get_shared_binder_placeable_copies"/);
  assert.match(act, /rpc\("editor_place_copy_in_binder"/);
  assert.match(act, /p_copy_token: input\.copyToken/);
  assert.match(act, /!isCopyToken\(input\.copyToken\)/);
  assert.doesNotMatch(act, /p_physical_card_id|physicalCardId/);
  const ed = read("components/colecoes/sharing/shared-binder-editor.tsx");
  assert.equal(ed.match(/editorPlaceCard\(\{[^}]*copyToken:/g)?.length, 2, "colocar e desfazer por token");
  assert.doesNotMatch(ed, /editorPlaceCard\(\{[^}]*physicalCardId:/);
  assert.match(read("lib/colecoes/editor-binder.ts"), /export type UndoRemoval = \{ position: PocketPosition; copyToken: string; cardName: string \};/);
});

test("contratos antigos fora do front inteiro; fluxo do titular preservado", () => {
  for (const f of ["app", "components", "lib"].flatMap((d) => sources(join(WEB, d)))) {
    const src = readFileSync(f, "utf8");
    assert.ok(!src.includes('"get_shared_binder_placeable_cards"'), `${f}: 5373 antiga`);
    assert.ok(!src.includes('"editor_place_card_in_binder"'), `${f}: 5374 antiga`);
  }
  // O titular continua com o próprio acervo por UUID (fluxo dele, fora do P0).
  assert.match(read("lib/colecoes/binder-share.ts"), /const physicalCardId = uuid\(r\.physical_card_id\);/);
});
