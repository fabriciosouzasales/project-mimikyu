// V1-13 · E3-6 / F2 — referências de espécie pelo EDITOR (5383). Respostas simuladas: não prova a 5383, a barreira nem sessões reais.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-binder-species.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import {
  applyMessage,
  classifyEditorSpeciesFailure,
  clearMessage,
  editorSpeciesFail,
  editorSpeciesFailureMessage,
  editorSpeciesStage,
  parseEditorSpeciesApply,
  parseEditorSpeciesClear,
  parseEditorSpeciesPreview,
  parseEditorSpeciesVisibility,
  speciesWriteUncertain,
  validExpectedCount,
  visibilityMessage,
} from "./editor-binder-species.ts";

const TOKEN = "a".repeat(64);
const row = (over: Record<string, unknown> = {}) => ({
  positions_in_scope: 151, slots_total: 180, pair_count: 151, slots_left_free: 29, positions_unplaced: 0,
  first_page: 1, last_page: 17, first_number: 1, last_number: 151, existing_count: 0, already_applied: false, plan_token: TOKEN, ...over,
});

test("prévia: campos da 5383; nada de bolsos ocupados (C-243)", () => {
  const p = parseEditorSpeciesPreview([row({ slots_with_content: 40 })]);
  assert.ok(p);
  assert.equal(p.pairCount, 151);
  assert.ok(!("slotsWithContent" in p), "contagem de bolsos ocupados não existe para o EDITOR");
  assert.equal(parseEditorSpeciesPreview([row({ plan_token: "x" })]), null);
  assert.equal(parseEditorSpeciesPreview([row({ existing_count: -1 })]), null);
  assert.equal(parseEditorSpeciesPreview([]), null, "zero linhas não é prévia");
  assert.equal(parseEditorSpeciesPreview([row(), row()]), null);
});

test("estágio só a partir da prévia: associar, associadas, desatualizadas, nada", () => {
  assert.equal(editorSpeciesStage(parseEditorSpeciesPreview(row())!), "apply");
  assert.equal(editorSpeciesStage(parseEditorSpeciesPreview(row({ pair_count: 0 }))!), "nothing");
  assert.equal(editorSpeciesStage(parseEditorSpeciesPreview(row({ existing_count: 151, already_applied: true }))!), "applied");
  assert.equal(editorSpeciesStage(parseEditorSpeciesPreview(row({ existing_count: 120, already_applied: false }))!), "outdated");
});

test("resultados das escritas e mensagens", () => {
  const a = parseEditorSpeciesApply([{ operation: "APPLIED", reference_count: 151, references_visible: true }]);
  assert.deepEqual(a, { operation: "APPLIED", referenceCount: 151, visible: true });
  assert.match(applyMessage(a!), /151 Pokémon foram associados/);
  assert.match(applyMessage({ operation: "APPLIED", referenceCount: 1, visible: false }), /exibição está desligada/);
  assert.match(applyMessage({ operation: "ALREADY_APPLIED", referenceCount: 9, visible: true }), /já estavam/);
  assert.equal(parseEditorSpeciesApply([{ operation: "X", reference_count: 1, references_visible: true }]), null);
  const c = parseEditorSpeciesClear([{ operation: "REMOVED", removed_count: 3 }]);
  assert.deepEqual(c, { removedCount: 3 });
  assert.match(clearMessage(c!), /3 referências foram removidas\. Cartas, reservas e páginas não mudaram/);
  assert.equal(parseEditorSpeciesClear([{ operation: "REMOVED" }]), null);
  const v = parseEditorSpeciesVisibility([{ references_visible: false, operation: "UNCHANGED" }]);
  assert.deepEqual(v, { visible: false, changed: false });
  assert.match(visibilityMessage(v!), /já estavam ocultos/);
  assert.match(visibilityMessage({ visible: true, changed: true }), /voltam a aparecer/);
  assert.match(visibilityMessage({ visible: false, changed: true }), /A associação continua/);
  assert.equal(parseEditorSpeciesVisibility([{ references_visible: "sim", operation: "UPDATED" }]), null);
  assert.ok(validExpectedCount(0) && validExpectedCount(151) && !validExpectedCount(-1) && !validExpectedCount(1.2));
});

test("recusas: só código e nome; barreira, permissão, arquivada, plano, contagem, trava", () => {
  const cases: [string | null, string, string][] = [
    ["42501", "CAPABILITY_NOT_ENABLED", "unavailable"],
    ["42501", "OPERATION_RESERVED_TO_OWNER", "owner_only"],
    ["P0002", "COLLECTION_NOT_FOUND", "access_lost"],
    ["P0002", "BINDER_NOT_FOUND", "access_lost"],
    ["55000", "COLLECTION_ARCHIVED", "archived"],
    ["22023", "NOT_POKEDEX_COLLECTION", "not_pokedex"],
    ["P0001", "PLAN_CHANGED", "plan_changed"],
    ["P0001", "SPECIES_REFERENCES_PRESENT", "present"],
    ["P0001", "NOTHING_TO_APPLY", "nothing"],
    ["P0001", "COUNT_MISMATCH", "count_mismatch"],
    ["55P03", "lock timeout", "lock_busy"],
    ["28000", "not_authenticated", "not_authenticated"],
    ["22023", "INVALID_ARGUMENT", "invalid"],
    [null, "fetch failed", "unknown"],
  ];
  for (const [code, msg, want] of cases) assert.equal(classifyEditorSpeciesFailure(code, msg), want, msg);
  for (const r of ["unavailable", "access_lost", "archived", "not_authenticated"] as const) assert.equal(editorSpeciesFail(r).disables, true, r);
  assert.equal(editorSpeciesFail("access_lost").recheck, true);
  for (const r of ["owner_only", "plan_changed", "present", "count_mismatch", "lock_busy", "unknown"] as const) assert.equal(editorSpeciesFail(r).disables, false, r);
  for (const r of ["plan_changed", "present", "count_mismatch", "nothing"] as const) assert.equal(editorSpeciesFail(r).reloadPreview, true, r);
  assert.equal(speciesWriteUncertain("unknown"), true);
  assert.equal(speciesWriteUncertain("plan_changed"), false);
  assert.match(editorSpeciesFailureMessage("unknown"), /confirmar o resultado/);
  const all = (["unavailable", "owner_only", "access_lost", "archived", "not_pokedex", "plan_changed", "present", "nothing", "count_mismatch", "lock_busy", "not_authenticated", "invalid", "unknown"] as const).map(editorSpeciesFailureMessage);
  assert.ok(all.every((m) => !/[A-Z_]{6,}|P0\d{3}|42501/.test(m)), "sem códigos internos");
});

test("ações e diálogo: só a 5383, uma chamada por ação, sem hint/details, sem repetição nem leitura ao abrir o fichário", () => {
  const actions = readFileSync(new URL("../../app/colecoes/compartilhada/[id]/fichario/actions.ts", import.meta.url), "utf8");
  const block = actions.slice(actions.indexOf("E3-6 / F2"));
  assert.ok(block.length > 0 && !/\.hint|\.details?\b/.test(block), "não lê hint nem details");
  assert.equal(block.match(/rpc\(/g)?.length, 4, "prévia, aplicar, remover, mostrar/ocultar");
  const fns = [...block.matchAll(/const fn = "([a-z_]+)"/g)].map((m) => m[1]);
  assert.deepEqual(fns, ["editor_preview_binder_species_references", "editor_apply_binder_species_references", "editor_clear_binder_species_references", "editor_set_binder_species_reference_visibility"]);
  assert.equal((block.match(/speciesGuard\(/g) ?? []).length, 5, "configuração conferida em todas as ações (+ definição)");
  const ui = readFileSync(new URL("../../components/colecoes/sharing/shared-binder-species.tsx", import.meta.url), "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
  assert.ok(!/setTimeout\(|setInterval\(/.test(ui), "sem repetição automática");
  assert.equal(ui.match(/editorApplySpeciesReferences\(/g)?.length, 1);
  assert.ok(!/physical|allocation|storage|condition/.test(ui), "nada patrimonial");
  // F2 integrada: interruptor só com o estado REAL (5393); desconhecido → duas ações explícitas, nada presumido.
  assert.ok(/visibility !== null \? \(/.test(ui) && /checked=\{visibility\}/.test(ui) && (ui.match(/<Switch\b/g) ?? []).length === 1, "interruptor ligado ao estado lido");
});
