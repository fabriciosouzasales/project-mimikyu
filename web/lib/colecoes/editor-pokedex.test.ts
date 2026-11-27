// V1-13 · E3 / F3-1 — Pokédex colaborativa do EDITOR: contratos, resultados e privacidade.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-pokedex.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import {
  COPY_OFFSET_MAX,
  COPY_PAGE_MAX,
  EDITOR_POKEDEX_RPC,
  buildChooseCall,
  buildCopiesCall,
  buildMoveCall,
  buildRestoreCall,
  buildUnassignCall,
  canShowEditorPokedexActions,
  classifyEditorPokedexFailure,
  emptyKind,
  failurePolicy,
  hasForbiddenKey,
  invalidateTokens,
  isCopyToken,
  nextOffset,
  parseChooseResult,
  parseCopiesPage,
  parseMoveResult,
  parseRestoreResult,
  parseUnassignResult,
  resultChanged,
  resultMessage,
  safeLogFields,
  seenRepresentative,
  tokenUsable,
  type EditorPokedexFailure,
} from "./editor-pokedex.ts";

const COL = "11111111-1111-4111-8111-111111111111";
const POS = "22222222-2222-4222-8222-222222222222";
const POS2 = "33333333-3333-4333-8333-333333333333";
const PHYS = "44444444-4444-4444-8444-444444444444";
const tok = (c: string) => `pc1.${c.repeat(64)}`;
const T1 = tok("a");
const T2 = tok("b");
const T3 = tok("c");

function atRow(token: string, over: Record<string, unknown> = {}) {
  return {
    copy_token: token, card_name: "Pikachu", collector_number: "25", card_set_code: "base1", variant_label: "Normal",
    language_code: "pt-BR", image_path: "cards/x.png", species_match: true, current_position_id: POS, current_position_number: 25,
    assignment_basis: "SPECIES_MATCH", is_primary_representative: false, is_effective_representative: false,
    position_representative_mode: "AUTOMATIC", total_count: 2, ...over,
  };
}
function asRow(token: string, over: Record<string, unknown> = {}) {
  return {
    copy_token: token, card_name: "Raichu", collector_number: "26", card_set_code: "base1", variant_label: null,
    language_code: "en", image_path: null, species_match: false, current_position_id: null, current_position_number: null,
    assignment_basis: null, is_primary_representative: null, is_effective_representative: null,
    position_representative_mode: null, total_count: 1, ...over,
  };
}
const atCall = buildCopiesCall({ collectionId: COL, positionId: POS, scope: "AT_POSITION" })!;
const asCall = buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ASSIGNABLE", query: " pika " })!;

// ---------------------------------------------------------------------------

test("token opaco: só o formato da 5391 (pc1. + 64 hex minúsculos)", () => {
  assert.equal(isCopyToken(T1), true);
  for (const bad of [null, undefined, 1, "", PHYS, "pc1.", `pc1.${"A".repeat(64)}`, `pc2.${"a".repeat(64)}`, `pc1.${"a".repeat(63)}`, ` ${T1}`]) {
    assert.equal(isCopyToken(bad), false, String(bad));
  }
});

test("leitura: parâmetros, escopos, busca e limites como no SQL", () => {
  assert.deepEqual(atCall, {
    fn: "get_editor_pokedex_position_copies",
    args: { p_collection_id: COL, p_pokedex_position_id: POS, p_scope: "AT_POSITION", p_query: null, p_limit: 30, p_offset: 0 },
  });
  assert.equal(asCall.args.p_query, "pika");
  assert.equal(buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ASSIGNABLE", query: "   " })!.args.p_query, null);
  // Busca só em ASSIGNABLE e até 64 caracteres.
  assert.equal(buildCopiesCall({ collectionId: COL, positionId: POS, scope: "AT_POSITION", query: "x" }), null);
  assert.equal(buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ASSIGNABLE", query: "x".repeat(65) }), null);
  assert.ok(buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ASSIGNABLE", query: "x".repeat(64) }));
  // Limite 1–100 e deslocamento 0–10000 (INVALID_PAGE no servidor).
  for (const [limit, offset] of [[0, 0], [COPY_PAGE_MAX + 1, 0], [1.5, 0], [10, -1], [10, COPY_OFFSET_MAX + 1]]) {
    assert.equal(buildCopiesCall({ collectionId: COL, positionId: POS, scope: "AT_POSITION", limit, offset }), null, `${limit}/${offset}`);
  }
  assert.ok(buildCopiesCall({ collectionId: COL, positionId: POS, scope: "AT_POSITION", limit: COPY_PAGE_MAX, offset: COPY_OFFSET_MAX }));
  // Identificadores ausentes ou inválidos; escopo desconhecido.
  assert.equal(buildCopiesCall({ collectionId: "x", positionId: POS, scope: "AT_POSITION" }), null);
  assert.equal(buildCopiesCall({ collectionId: COL, positionId: "", scope: "AT_POSITION" }), null);
  assert.equal(buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ALL" as never }), null);
});

test("leitura AT_POSITION: representante efetiva na 1ª linha; contexto dos tokens", () => {
  const page = parseCopiesPage([atRow(T1, { is_primary_representative: true, is_effective_representative: true, position_representative_mode: "CHOSEN" }), atRow(T2, { position_representative_mode: "CHOSEN" })], atCall)!;
  assert.ok(page);
  assert.equal(page.items.length, 2);
  assert.equal(page.total, 2);
  assert.equal(page.hasMore, false);
  assert.equal(page.collectionId, COL);
  assert.deepEqual(seenRepresentative(page), { token: T1, mode: "CHOSEN" });
  // Duas efetivas, nenhuma na 1ª linha, posição diferente da pedida, colunas de ASSIGNABLE → fora do contrato.
  assert.equal(parseCopiesPage([atRow(T1, { is_effective_representative: true }), atRow(T2, { is_effective_representative: true })], atCall), null);
  assert.equal(parseCopiesPage([atRow(T1), atRow(T2, { is_effective_representative: true })], atCall), null);
  assert.equal(parseCopiesPage([atRow(T1, { is_effective_representative: true, current_position_id: POS2 })], atCall), null);
  assert.equal(parseCopiesPage([atRow(T1, { is_effective_representative: true, position_representative_mode: null })], atCall), null);
});

test("leitura ASSIGNABLE: sem colunas de representante; posição atual coerente com a base", () => {
  const page = parseCopiesPage([asRow(T3)], asCall)!;
  assert.equal(page.items[0]?.currentPositionId, null);
  assert.equal(page.items[0]?.isPrimaryRepresentative, null);
  assert.equal(seenRepresentative(page), null);
  assert.ok(parseCopiesPage([asRow(T3, { current_position_id: POS2, current_position_number: 26, assignment_basis: "USER_OVERRIDE" })], asCall));
  assert.equal(parseCopiesPage([asRow(T3, { is_primary_representative: false })], asCall), null);
  assert.equal(parseCopiesPage([asRow(T3, { current_position_id: POS, assignment_basis: "SPECIES_MATCH" })], asCall), null);
  assert.equal(parseCopiesPage([asRow(T3, { current_position_id: POS2 })], asCall), null); // posição sem base
});

test("leitura: formatos inválidos, duplicatas, total incoerente e paginação", () => {
  assert.equal(parseCopiesPage(null, atCall), null);
  assert.equal(parseCopiesPage({}, atCall), null);
  assert.equal(parseCopiesPage([asRow("pc1.x")], asCall), null);
  assert.equal(parseCopiesPage([asRow(T3, { card_name: "" })], asCall), null);
  assert.equal(parseCopiesPage([asRow(T3, { species_match: "sim" })], asCall), null);
  assert.equal(parseCopiesPage([asRow(T3, { total_count: 2 }), asRow(T3, { total_count: 2 })], asCall), null);
  assert.equal(parseCopiesPage([asRow(T1, { total_count: 2 }), asRow(T2, { total_count: 3 })], asCall), null);
  assert.ok(parseCopiesPage([asRow(T3, { total_count: "1" })], asCall), "bigint como texto");
  const p2 = buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ASSIGNABLE", limit: 1, offset: 0 })!;
  const page = parseCopiesPage([asRow(T1, { total_count: 3 })], p2)!;
  assert.equal(page.hasMore, true);
  assert.equal(nextOffset(page, 1), 1);
  assert.equal(parseCopiesPage([asRow(T1, { total_count: 3 }), asRow(T2, { total_count: 3 })], p2), null, "mais linhas que o limite");
});

test("zero linhas: sem cópias ou sem acesso (indistinguível); depois da 1ª página: estado mudou", () => {
  const first = parseCopiesPage([], atCall)!;
  assert.equal(first.total, 0);
  assert.equal(emptyKind(first), "none_or_unavailable");
  const later = parseCopiesPage([], buildCopiesCall({ collectionId: COL, positionId: POS, scope: "AT_POSITION", offset: 30 })!)!;
  assert.equal(emptyKind(later), "stale");
  assert.equal(nextOffset(later), null);
});

test("escritas: só token opaco e posições de catálogo; parâmetros exatos da 5392", () => {
  assert.deepEqual(buildMoveCall({ collectionId: COL, copyToken: T1, targetPositionId: POS, expectedPositionId: null }), {
    fn: "editor_move_pokedex_copy",
    args: { p_collection_id: COL, p_copy_token: T1, p_target_position_id: POS, p_expected_position_id: null, p_confirm_override: false },
  });
  assert.equal(buildMoveCall({ collectionId: COL, copyToken: T1, targetPositionId: POS, expectedPositionId: POS2, confirmOverride: true })!.args.p_confirm_override, true);
  assert.deepEqual(buildUnassignCall({ collectionId: COL, copyToken: T1, expectedPositionId: POS })!.args, { p_collection_id: COL, p_copy_token: T1, p_expected_position_id: POS });
  assert.deepEqual(buildChooseCall({ collectionId: COL, copyToken: T2, expectedPositionId: POS, expectedRepresentativeToken: null })!.args.p_expected_representative_token, null);
  assert.equal(buildChooseCall({ collectionId: COL, copyToken: T2, expectedPositionId: POS, expectedRepresentativeToken: T1 })!.fn, "editor_choose_pokedex_representative");
  assert.deepEqual(buildRestoreCall({ collectionId: COL, positionId: POS, expectedRepresentativeToken: T1 }), {
    fn: "editor_restore_pokedex_automatic_representative",
    args: { p_collection_id: COL, p_pokedex_position_id: POS, p_expected_representative_token: T1 },
  });
  // Negativos: identificador físico no lugar do token, campos ausentes, tipos errados.
  assert.equal(buildMoveCall({ collectionId: COL, copyToken: PHYS, targetPositionId: POS, expectedPositionId: null }), null);
  assert.equal(buildMoveCall({ collectionId: COL, copyToken: T1, targetPositionId: "", expectedPositionId: null }), null);
  assert.equal(buildMoveCall({ collectionId: COL, copyToken: T1, targetPositionId: POS, expectedPositionId: null, confirmOverride: "true" as never }), null);
  assert.equal(buildUnassignCall({ collectionId: COL, copyToken: T1, expectedPositionId: null as never }), null);
  assert.equal(buildChooseCall({ collectionId: COL, copyToken: T1, expectedPositionId: POS, expectedRepresentativeToken: PHYS }), null);
  assert.equal(buildRestoreCall({ collectionId: COL, positionId: POS, expectedRepresentativeToken: null }), null);
  for (const call of [
    buildMoveCall({ collectionId: COL, copyToken: T1, targetPositionId: POS, expectedPositionId: POS2 }),
    buildUnassignCall({ collectionId: COL, copyToken: T1, expectedPositionId: POS }),
    buildChooseCall({ collectionId: COL, copyToken: T1, expectedPositionId: POS, expectedRepresentativeToken: T2 }),
    buildRestoreCall({ collectionId: COL, positionId: POS, expectedRepresentativeToken: T1 }),
    atCall,
  ]) {
    assert.equal(hasForbiddenKey(call!.args), false);
    assert.ok(!JSON.stringify(call).includes(PHYS));
  }
});

test("resultados: os 7 efetivos e UNCHANGED, com coerência; desconhecidos → null", () => {
  assert.equal(parseMoveResult([{ operation: "CREATED", pokedex_position_id: POS, previous_position_id: null, assignment_basis: "SPECIES_MATCH", representative_cleared: false }])!.operation, "CREATED");
  const moved = parseMoveResult([{ operation: "MOVED", pokedex_position_id: POS, previous_position_id: POS2, assignment_basis: "USER_OVERRIDE", representative_cleared: true }])!;
  assert.match(resultMessage(moved), /deixou de ser a representante/);
  const same = parseMoveResult([{ operation: "UNCHANGED", pokedex_position_id: POS, previous_position_id: POS, assignment_basis: "SPECIES_MATCH", representative_cleared: false }])!;
  assert.equal(resultChanged(same), false);
  assert.equal(parseUnassignResult([{ operation: "REMOVED", previous_position_id: POS, representative_cleared: false }])!.operation, "REMOVED");
  assert.equal(resultChanged(parseUnassignResult([{ operation: "UNCHANGED", previous_position_id: null, representative_cleared: false }])!), false);
  assert.equal(parseChooseResult([{ operation: "SET", pokedex_position_id: POS }])!.operation, "SET");
  assert.equal(parseChooseResult([{ operation: "REPLACED", pokedex_position_id: POS }])!.operation, "REPLACED");
  assert.equal(parseRestoreResult([{ operation: "CLEARED" }])!.operation, "CLEARED");
  const restoreSame = parseRestoreResult([{ operation: "UNCHANGED" }])!;
  assert.equal(resultChanged(restoreSame), false);
  assert.equal(resultMessage(restoreSame), "Nada mudou: a posição já estava assim.");
  assert.doesNotMatch(resultMessage(restoreSame), /salv|sucesso|gravad/i);
  // Desconhecidos e incoerentes.
  assert.equal(parseMoveResult([{ operation: "DONE", pokedex_position_id: POS, previous_position_id: null, assignment_basis: null, representative_cleared: false }]), null);
  assert.equal(parseMoveResult([{ operation: "CREATED", pokedex_position_id: POS, previous_position_id: POS2, assignment_basis: "SPECIES_MATCH", representative_cleared: false }]), null);
  assert.equal(parseMoveResult([{ operation: "MOVED", pokedex_position_id: POS, previous_position_id: POS, assignment_basis: "SPECIES_MATCH", representative_cleared: false }]), null);
  assert.equal(parseUnassignResult([{ operation: "REMOVED", previous_position_id: null, representative_cleared: false }]), null);
  assert.equal(parseChooseResult([{ operation: "SET" }]), null);
  assert.equal(parseRestoreResult([]), null);
  assert.equal(parseRestoreResult([{ operation: "CLEARED" }, { operation: "CLEARED" }]), null);
  // Linha com identidade física → recusada (falha fechada).
  assert.equal(parseChooseResult([{ operation: "SET", pokedex_position_id: POS, physical_card_id: PHYS }]), null);
});

test("recusas: nome da exceção primeiro (P0002 e 22023 são compartilhados)", () => {
  const cases: [string | null, string, EditorPokedexFailure][] = [
    ["42501", "CAPABILITY_NOT_ENABLED", "barrier_closed"],
    ["22023", "STATE_CHANGED", "state_changed"],
    ["22023", "CONFIRMATION_REQUIRED", "confirmation_required"],
    ["P0002", "COPY_NOT_FOUND", "copy_not_found"],
    ["22023", "POKEDEX_POSITION_NOT_FOUND", "position_not_found"],
    ["P0002", "COLLECTION_NOT_FOUND", "access_lost"],
    ["55000", "COLLECTION_ARCHIVED", "archived"],
    ["22023", "NOT_POKEDEX_COLLECTION", "not_pokedex"],
    ["22023", "INVALID_PAGE", "invalid"],
    ["22023", "INVALID_ARGUMENT", "invalid"],
    ["28000", "not_authenticated", "not_authenticated"],
    ["PGRST202", "Could not find the function", "unavailable"],
    ["55P03", "canceling statement due to lock timeout", "lock_busy"],
    [null, "fetch failed", "unknown"],
  ];
  for (const [code, msg, want] of cases) assert.equal(classifyEditorPokedexFailure(code, msg), want, msg);
});

test("política: conflito recarrega; token inválido invalida a lista; confirmação explícita; sem repetição automática", () => {
  const sc = failurePolicy("state_changed");
  assert.equal(sc.reloadState && sc.invalidateTokens && sc.nothingWritten, true);
  const cnf = failurePolicy("copy_not_found");
  assert.equal(cnf.invalidateTokens && cnf.reloadState, true);
  const conf = failurePolicy("confirmation_required");
  assert.equal(conf.requireConfirmation && conf.nothingWritten && !conf.reloadState, true);
  for (const r of ["barrier_closed", "unavailable", "not_authenticated", "access_lost", "archived", "not_pokedex"] as EditorPokedexFailure[]) {
    const p = failurePolicy(r);
    assert.equal(p.disables, true, r);
    assert.equal(p.manualRetry, false, r);
  }
  const unk = failurePolicy("unknown");
  assert.equal(unk.uncertain && !unk.nothingWritten && unk.reloadState && !unk.manualRetry, true);
  // Mensagens: sem ids, tokens, códigos internos nem enums.
  for (const r of Object.keys({ barrier_closed: 1, unavailable: 1, not_authenticated: 1, access_lost: 1, archived: 1, not_pokedex: 1, state_changed: 1, confirmation_required: 1, copy_not_found: 1, position_not_found: 1, lock_busy: 1, invalid: 1, unknown: 1 }) as EditorPokedexFailure[]) {
    assert.doesNotMatch(failurePolicy(r).message, /pc1\.|[0-9a-f]{8}-|[A-Z]{3,}_[A-Z]|P0002|22023/);
  }
});

test("barreira fechada e papel: ações indisponíveis", () => {
  const base = { flagOn: true, role: "EDITOR" as const, archived: false, refusal: null };
  assert.equal(canShowEditorPokedexActions(base), true);
  assert.equal(canShowEditorPokedexActions({ ...base, flagOn: false }), false);
  assert.equal(canShowEditorPokedexActions({ ...base, role: "VIEWER" }), false);
  assert.equal(canShowEditorPokedexActions({ ...base, archived: true }), false);
  assert.equal(canShowEditorPokedexActions({ ...base, refusal: "barrier_closed" }), false);
  assert.equal(canShowEditorPokedexActions({ ...base, refusal: "state_changed" }), true);
});

test("época: tokens valem só para a página da geração vigente e da mesma coleção", () => {
  const page = parseCopiesPage([atRow(T1, { is_effective_representative: true })], atCall)!;
  let scope = { collectionId: COL, generation: 0 };
  assert.equal(tokenUsable(T1, page, scope, 0), true);
  assert.equal(tokenUsable(T2, page, scope, 0), false, "token que a página não trouxe");
  assert.equal(tokenUsable(T1, page, { collectionId: "55555555-5555-4555-8555-555555555555", generation: 0 }, 0), false);
  scope = invalidateTokens(scope);
  assert.equal(tokenUsable(T1, page, scope, 0), false, "COPY_NOT_FOUND/STATE_CHANGED/troca de papel → nova geração");
});

test("registro seguro: só função e motivo", () => {
  assert.deepEqual(safeLogFields("editor_move_pokedex_copy", "state_changed"), { fn: "editor_move_pokedex_copy", reason: "state_changed" });
  assert.deepEqual(safeLogFields(`x ${T1}`, "unknown"), { fn: "editor_pokedex_unknown", reason: "unknown" });
});

// ---------------------------------------------------------------------------
// Verificação estática de privacidade (regressão): vale para o código atual e para F3-2+.

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const LEGACY = [
  "editor_set_pokedex_position_assignment", "editor_remove_pokedex_position_assignment",
  "editor_set_pokedex_position_primary_representative", "editor_clear_pokedex_position_primary_representative",
];

function sources(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    if (name === "node_modules" || name.startsWith(".")) continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) sources(p, out);
    else if (/\.(ts|tsx)$/.test(name) && !/\.test\.tsx?$/.test(name)) out.push(p);
  }
  return out;
}

test("estático: nenhuma integração da Pokédex do EDITOR usa identificador físico nem o caminho legado", () => {
  const files = ["app", "components", "lib"].flatMap((d) => sources(join(WEB, d)));
  assert.ok(files.length > 50);
  const rpcs = Object.values(EDITOR_POKEDEX_RPC);
  // Quem chama as RPCs pelo nome OU usa os módulos colaborativos (actions e painel usam as constantes).
  const users = files.filter((f) => {
    const src = readFileSync(f, "utf8");
    return rpcs.some((r) => src.includes(r)) || /colecoes\/editor-pokedex(-panel)?["']|\.\/editor-pokedex(-panel)?(\.ts)?["']/.test(src);
  });
  assert.ok(users.length >= 5, `integrações encontradas: ${users.length}`);
  assert.ok(users.some((f) => f.endsWith(join("lib", "colecoes", "editor-pokedex.ts"))));
  for (const f of users) {
    const src = readFileSync(f, "utf8");
    assert.doesNotMatch(src, /physical_card_id|physicalCardId|p_physical_card_id|collection_allocation_id|allocationId/, f);
    assert.doesNotMatch(src, /get_shared_binder_placeable_cards/, `${f}: caminho 5373`);
    assert.doesNotMatch(src, /console\.(log|info|warn|error)\([^)]*(token|copyToken)/i, `${f}: token em log`);
  }
  for (const f of files) {
    const src = readFileSync(f, "utf8");
    for (const fn of LEGACY) assert.ok(!src.includes(`"${fn}"`), `${f}: escrita 5380 revogada (${fn})`);
  }
});
