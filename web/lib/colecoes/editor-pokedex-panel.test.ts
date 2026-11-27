// V1-13 · E3 / F3-2 — painel colaborativo da Pokédex do EDITOR: regras puras do painel.
// Executar: node --experimental-strip-types --test lib/colecoes/editor-pokedex-panel.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { type CopiesPage, buildChooseCall, buildCopiesCall, buildMoveCall, buildRestoreCall, buildUnassignCall, hasForbiddenKey, parseCopiesPage } from "./editor-pokedex.ts";
import {
  actionsEnabled,
  failureClass,
  positionStateLine,
  readFailure,
  writeNoticeTitle,
  beginWrite,
  confirmationUsable,
  mergeCopiesPages,
  planAfter,
  prepareConfirmation,
  syncAfterReload,
  syncMessage,
  chooseIntent,
  editorPokedexPanelOpenable,
  emptyListMessage,
  isBusy,
  isWriteIntent,
  moveIntent,
  moveLabel,
  originLine,
  reactToFailure,
  reactToSuccess,
  restoreIntent,
  unassignIntent,
} from "./editor-pokedex-panel.ts";

const COL = "11111111-1111-4111-8111-111111111111";
const POS = "22222222-2222-4222-8222-222222222222";
const POS2 = "33333333-3333-4333-8333-333333333333";
const OTHER = "55555555-5555-4555-8555-555555555555";
const tok = (c: string) => `pc1.${c.repeat(64)}`;
const [T1, T2, T3, T4] = [tok("a"), tok("b"), tok("c"), tok("d")];

const at = (token: string, over: Record<string, unknown> = {}) => ({
  copy_token: token, card_name: "Pikachu", collector_number: "25", card_set_code: "base1", variant_label: null, language_code: "pt-BR",
  image_path: null, species_match: true, current_position_id: POS, current_position_number: 25, assignment_basis: "SPECIES_MATCH",
  is_primary_representative: false, is_effective_representative: false, position_representative_mode: "AUTOMATIC", total_count: 2, ...over,
});
const as = (token: string, over: Record<string, unknown> = {}) => ({
  copy_token: token, card_name: "Raichu", collector_number: "26", card_set_code: "base1", variant_label: null, language_code: "en",
  image_path: null, species_match: false, current_position_id: null, current_position_number: null, assignment_basis: null,
  is_primary_representative: null, is_effective_representative: null, position_representative_mode: null, total_count: 2, ...over,
});

function page(scope: "AT_POSITION" | "ASSIGNABLE", rows: unknown[], offset = 0): CopiesPage {
  const call = buildCopiesCall({ collectionId: COL, positionId: POS, scope, offset })!;
  const p = parseCopiesPage(rows, call);
  assert.ok(p, "página válida");
  return p;
}
const hereAuto = page("AT_POSITION", [at(T1, { is_effective_representative: true }), at(T2)]);
const hereChosen = page("AT_POSITION", [at(T1, { is_primary_representative: true, is_effective_representative: true, position_representative_mode: "CHOSEN" }), at(T2, { position_representative_mode: "CHOSEN" })]);
const assign = page("ASSIGNABLE", [as(T3), as(T4, { current_position_id: POS2, current_position_number: 26, assignment_basis: "USER_OVERRIDE", species_match: true })]);

test("abertura: só configuração ligada + EDITOR + coleção ativa; VIEWER mantém a grade de sempre", () => {
  assert.equal(editorPokedexPanelOpenable({ flagOn: true, role: "EDITOR", archived: false }), true);
  assert.equal(editorPokedexPanelOpenable({ flagOn: true, role: "VIEWER", archived: false }), false);
  assert.equal(editorPokedexPanelOpenable({ flagOn: true, role: null, archived: false }), false);
  assert.equal(editorPokedexPanelOpenable({ flagOn: false, role: "EDITOR", archived: false }), false);
  assert.equal(editorPokedexPanelOpenable({ flagOn: true, role: "EDITOR", archived: true }), false);
});

test("colocar/mover: estado esperado = posição atual que a lista mostrou; nada inventado", () => {
  const put = moveIntent(COL, POS, assign, assign.items[0]!)!;
  assert.deepEqual(put, { kind: "move", collectionId: COL, copyToken: T3, targetPositionId: POS, expectedPositionId: null, confirmOverride: false });
  const mv = moveIntent(COL, POS, assign, assign.items[1]!, true)!;
  assert.equal(mv.kind === "move" && mv.expectedPositionId, POS2);
  assert.equal(mv.kind === "move" && mv.confirmOverride, true);
  assert.equal(moveLabel(assign.items[0]!), "Colocar aqui");
  assert.equal(moveLabel(assign.items[1]!), "Mover para cá");
  assert.equal(originLine(assign.items[1]!), "Hoje na posição nº 0026");
  // Lista errada (AT_POSITION), de outra coleção/posição, ou carta que a lista não trouxe → sem intenção.
  assert.equal(moveIntent(COL, POS, hereAuto, hereAuto.items[0]!), null);
  assert.equal(moveIntent(OTHER, POS, assign, assign.items[0]!), null);
  assert.equal(moveIntent(COL, POS2, assign, assign.items[0]!), null);
  assert.equal(moveIntent(COL, POS, assign, { ...assign.items[0]!, token: T1 as never }), null);
  assert.equal(moveIntent(COL, POS, null, assign.items[0]!), null);
});

test("retirar: só cartas listadas nesta posição", () => {
  assert.deepEqual(unassignIntent(COL, POS, hereAuto, hereAuto.items[1]!), { kind: "unassign", collectionId: COL, copyToken: T2, expectedPositionId: POS });
  assert.equal(unassignIntent(COL, POS, assign, assign.items[0]!), null);
});

test("representante: AUTOMÁTICA → esperado NULL; ESCOLHIDA → token da escolhida; restaurar só com escolhida", () => {
  assert.deepEqual(chooseIntent(COL, POS, hereAuto, hereAuto.items[1]!), { kind: "choose", collectionId: COL, copyToken: T2, expectedPositionId: POS, expectedRepresentativeToken: null });
  // Na automática, escolher a própria representante efetiva fixa a escolha (SET) — permitido.
  assert.ok(chooseIntent(COL, POS, hereAuto, hereAuto.items[0]!));
  assert.deepEqual(chooseIntent(COL, POS, hereChosen, hereChosen.items[1]!), { kind: "choose", collectionId: COL, copyToken: T2, expectedPositionId: POS, expectedRepresentativeToken: T1 });
  assert.equal(chooseIntent(COL, POS, hereChosen, hereChosen.items[0]!), null, "já é a escolhida");
  assert.equal(restoreIntent(COL, POS, hereAuto), null);
  assert.deepEqual(restoreIntent(COL, POS, hereChosen), { kind: "restore", collectionId: COL, positionId: POS, expectedRepresentativeToken: T1 });
  // Página 2 não traz a representante efetiva → sem escolha nem restauração.
  const p2 = page("AT_POSITION", [at(T2, { total_count: 31 })], 30);
  assert.equal(chooseIntent(COL, POS, p2, p2.items[0]!), null);
  assert.equal(restoreIntent(COL, POS, p2), null);
});

test("intenções: montam exatamente as chamadas da F3-1, sem identidade física", () => {
  const intents = [
    moveIntent(COL, POS, assign, assign.items[1]!)!,
    unassignIntent(COL, POS, hereAuto, hereAuto.items[0]!)!,
    chooseIntent(COL, POS, hereChosen, hereChosen.items[1]!)!,
    restoreIntent(COL, POS, hereChosen)!,
  ];
  for (const i of intents) {
    assert.equal(isWriteIntent(i), true, i.kind);
    assert.equal(hasForbiddenKey(i), false);
    const call = i.kind === "move" ? buildMoveCall(i) : i.kind === "unassign" ? buildUnassignCall(i) : i.kind === "choose" ? buildChooseCall(i) : buildRestoreCall(i);
    assert.ok(call, i.kind);
  }
});

test("revalidação na server action: forma exata, sem campos extras nem ids físicos", () => {
  const ok = unassignIntent(COL, POS, hereAuto, hereAuto.items[0]!)!;
  assert.equal(isWriteIntent({ ...ok, physicalCardId: OTHER }), false);
  assert.equal(isWriteIntent({ ...ok, copyToken: OTHER }), false);
  assert.equal(isWriteIntent({ ...ok, kind: "remove" }), false);
  assert.equal(isWriteIntent(null), false);
  assert.equal(isWriteIntent({ kind: "restore", collectionId: COL, positionId: POS, expectedRepresentativeToken: null }), false);
  assert.equal(isWriteIntent({ kind: "move", collectionId: COL, copyToken: T1, targetPositionId: POS, expectedPositionId: null, confirmOverride: "true" }), false);
});

test("uma ação por vez: clique repetido durante a requisição é ignorado", () => {
  const i = unassignIntent(COL, POS, hereAuto, hereAuto.items[0]!)!;
  const writing = beginWrite({ kind: "idle" }, i)!;
  assert.equal(isBusy(writing), true);
  assert.equal(beginWrite(writing, i), null);
  assert.equal(beginWrite({ kind: "reading" }, i), null);
});

test("reações: sucesso relê; UNCHANGED neutro; conflito relê e descarta tokens; confirmação sem reler; barreira desliga", () => {
  const done = reactToSuccess(true, "A carta saiu da posição.");
  assert.equal(done.tone === "success" && done.reload && done.dropTokens && done.changed, true);
  const same = reactToSuccess(false, "Nada mudou: a posição já estava assim.");
  assert.equal(same.tone, "neutral");
  assert.equal(same.changed, false);
  const sc = reactToFailure("state_changed");
  assert.equal(sc.reload && sc.dropTokens && !sc.changed, true);
  const cnf = reactToFailure("copy_not_found");
  assert.equal(cnf.reload && cnf.dropTokens, true);
  const conf = reactToFailure("confirmation_required");
  assert.equal(conf.askConfirmation && !conf.reload && conf.tone === "warning", true);
  const closed = reactToFailure("barrier_closed");
  assert.equal(closed.disable && !closed.policy.manualRetry, true);
  const unk = reactToFailure("unknown");
  assert.equal(unk.reload && unk.policy.uncertain && !unk.changed, true);
  for (const r of [done, same, sc, cnf, conf, closed, unk]) assert.doesNotMatch(r.message, /pc1\.|[0-9a-f]{8}-/);
});

test("lista vazia: mensagem neutra (zero linhas também pode ser falta de acesso)", () => {
  assert.equal(emptyListMessage("AT_POSITION", false), "Nenhuma carta aparece nesta posição agora.");
  assert.match(emptyListMessage("ASSIGNABLE", true), /busca/);
  assert.match(emptyListMessage("ASSIGNABLE", false), /agora/);
});

// ---------------------------------------------------------------------------
// F3-3 — consistência e concorrência

test("F3-3 sucesso efetivo: relê o painel, descarta tokens e atualiza a grade (origem e destino vêm da página do servidor)", () => {
  for (const changed of [true]) {
    const p = planAfter({ ok: true, changed });
    assert.deepEqual(p, { reloadPanel: true, dropTokens: true, refreshGrid: true, confirmed: true, uncertain: false, askConfirmation: false, disable: false });
  }
});

test("F3-3 UNCHANGED: relê o painel, NÃO afirma alteração e não atualiza a grade", () => {
  const p = planAfter({ ok: true, changed: false });
  assert.equal(p.confirmed || p.refreshGrid, false);
  assert.equal(p.reloadPanel && p.dropTokens, true);
});

test("F3-3 conflito, token obsoleto e incerto: estado do servidor no painel E na grade; nunca repete", () => {
  for (const reason of ["state_changed", "copy_not_found", "position_not_found", "unknown"] as const) {
    const p = planAfter({ ok: false, reason });
    assert.equal(p.reloadPanel && p.dropTokens && p.refreshGrid, true, reason);
    assert.equal(p.confirmed, false, reason);
  }
  assert.equal(planAfter({ ok: false, reason: "unknown" }).uncertain, true);
});

test("F3-3 perda de autorização/barreira: desliga e descarta tokens, sem releitura inútil", () => {
  for (const reason of ["access_lost", "not_authenticated", "barrier_closed"] as const) {
    const p = planAfter({ ok: false, reason });
    assert.equal(p.disable && p.dropTokens && !p.reloadPanel && !p.confirmed, true, reason);
  }
});

test("F3-3 confirmação: presa à intenção recusada (mesmo estado esperado) e à geração da lista", () => {
  const card = assign.items[1]!; // vem de POS2
  const refused = moveIntent(COL, POS, assign, card)!;
  assert.deepEqual(planAfter({ ok: false, reason: "confirmation_required" }).askConfirmation, true);
  assert.equal(planAfter({ ok: false, reason: "confirmation_required" }).reloadPanel, false, "nada gravado: não relê");
  const pc = prepareConfirmation(COL, POS, assign, refused, 7)!;
  assert.equal(pc.intent.confirmOverride, true);
  assert.equal(pc.intent.expectedPositionId, POS2, "segunda chamada com o estado esperado ORIGINAL");
  assert.equal(pc.intent.copyToken, card.token);
  assert.equal(pc.cardName, "Raichu");
  assert.equal(pc.fromLine, "Hoje na posição nº 0026");
  assert.equal(confirmationUsable(pc, 7), true);
  assert.equal(confirmationUsable(pc, 8), false, "depois de reler, a confirmação antiga é descartada");
  assert.equal(confirmationUsable(null, 7), false);
  // Recusa de outra coisa, intenção já confirmada ou carta que mudou de posição na lista → sem confirmação.
  assert.equal(prepareConfirmation(COL, POS, assign, unassignIntent(COL, POS, hereAuto, hereAuto.items[0]!)!, 7), null);
  assert.equal(prepareConfirmation(COL, POS, assign, { ...refused, confirmOverride: true } as never, 7), null);
  assert.equal(prepareConfirmation(COL, POS, assign, { ...refused, expectedPositionId: null } as never, 7), null);
  assert.equal(prepareConfirmation(COL, POS, null, refused, 7), null);
});

test("F3-3 escrita confirmada + releitura falha: 'confirmada, visual pendente', nunca fracasso; ações suspensas", () => {
  assert.equal(syncAfterReload(true, true), "synced");
  assert.equal(syncAfterReload(true, false), "confirmed_stale");
  assert.equal(syncAfterReload(false, false), "stale");
  assert.match(syncMessage("confirmed_stale")!, /foi confirmada/);
  assert.doesNotMatch(syncMessage("confirmed_stale")!, /Nada foi alterado|falhou|não foi/i);
  assert.equal(syncMessage("synced"), null);
  const idle = { kind: "idle" } as const;
  assert.equal(actionsEnabled({ busy: idle, disabled: false, sync: "synced", loading: false }), true);
  assert.equal(actionsEnabled({ busy: idle, disabled: false, sync: "confirmed_stale", loading: false }), false);
  assert.equal(actionsEnabled({ busy: idle, disabled: false, sync: "stale", loading: false }), false);
  assert.equal(actionsEnabled({ busy: idle, disabled: false, sync: "synced", loading: true }), false, "lista sendo relida");
  assert.equal(actionsEnabled({ busy: { kind: "writing", intent: "move", token: null }, disabled: false, sync: "synced", loading: false }), false);
  assert.equal(actionsEnabled({ busy: idle, disabled: true, sync: "synced", loading: false }), false);
});

test("F3-3 'Mostrar mais': a lista acumulada mantém intenção válida para TODAS as cartas; incoerência → reler", () => {
  const c1 = buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ASSIGNABLE", limit: 1 })!;
  const c2 = buildCopiesCall({ collectionId: COL, positionId: POS, scope: "ASSIGNABLE", limit: 1, offset: 1 })!;
  const p1 = parseCopiesPage([as(T3)], c1)!;
  const p2 = parseCopiesPage([as(T4)], c2)!;
  const merged = mergeCopiesPages(p1, p2)!;
  assert.deepEqual(merged.items.map((i) => i.token), [T3, T4]);
  assert.equal(merged.offset, 0);
  assert.equal(merged.hasMore, false);
  assert.ok(moveIntent(COL, POS, merged, merged.items[0]!), "carta da 1ª página continua acionável");
  assert.equal(moveIntent(COL, POS, p2, p1.items[0]!), null, "sem a junção, a 1ª página perderia a ação");
  assert.equal(mergeCopiesPages(p1, p1), null, "deslocamento incoerente");
  assert.equal(mergeCopiesPages(p1, parseCopiesPage([as(T3)], c2)!), null, "carta repetida: a ordem mudou");
  assert.equal(mergeCopiesPages(p1, page("AT_POSITION", [at(T1, { is_effective_representative: true })])), null);
});

test("F3-3 mudança de posição: intenções e confirmação não atravessam posições nem coleções", () => {
  const refused = moveIntent(COL, POS, assign, assign.items[0]!)!;
  assert.equal(prepareConfirmation(COL, POS2, assign, refused, 1), null);
  assert.equal(prepareConfirmation(OTHER, POS, assign, refused, 1), null);
  assert.equal(chooseIntent(COL, POS2, hereChosen, hereChosen.items[1]!), null);
  assert.equal(restoreIntent(OTHER, POS, hereChosen), null);
});

// ---------------------------------------------------------------------------
// F3-5 — estados excepcionais

const ALL_REASONS = ["barrier_closed", "unavailable", "not_authenticated", "access_lost", "archived", "not_pokedex", "state_changed", "confirmation_required", "copy_not_found", "position_not_found", "lock_busy", "invalid", "unknown"] as const;

test("F3-5 classes: acesso, conflito, incerto e recusa sem escrita", () => {
  const want: Record<string, string> = {
    barrier_closed: "access", unavailable: "access", not_authenticated: "access", access_lost: "access", archived: "access", not_pokedex: "access", position_not_found: "access",
    state_changed: "conflict", copy_not_found: "conflict",
    unknown: "uncertain",
    confirmation_required: "refused", lock_busy: "refused", invalid: "refused",
  };
  for (const r of ALL_REASONS) assert.equal(failureClass(r), want[r], r);
});

test("F3-5 bloqueios de acesso: sem repetição, ações desligadas (inclui posição fora da Pokédex)", () => {
  for (const r of ALL_REASONS.filter((x) => failureClass(x) === "access")) {
    const p = planAfter({ ok: false, reason: r });
    assert.equal(p.disable, true, r);
    assert.equal(p.confirmed, false, r);
    assert.equal(writeNoticeTitle(r), "Ação indisponível", r);
    const rf = readFailure(r);
    assert.equal(rf.blocks && !rf.retry, true, r);
  }
  const closed = readFailure("disabled");
  assert.equal(closed.blocks, true);
  assert.equal(closed.message, "A edição compartilhada da Pokédex ainda não está disponível.");
});

test("F3-5 conflitos: título 'A posição mudou', releitura, nunca 'Nada foi alterado' quando incerto", () => {
  assert.equal(writeNoticeTitle("state_changed"), "A posição mudou");
  assert.equal(writeNoticeTitle("copy_not_found"), "A posição mudou");
  assert.equal(writeNoticeTitle("unknown"), "Resultado não confirmado");
  assert.equal(writeNoticeTitle("confirmation_required"), "Confirme antes de continuar");
  assert.equal(writeNoticeTitle("lock_busy"), "Nada foi alterado");
  assert.equal(writeNoticeTitle("invalid"), "Nada foi alterado");
});

test("F3-5 falhas de LEITURA: comunicação, resposta inválida e trava permitem nova consulta; nunca 'nenhuma carta'", () => {
  for (const r of ["unknown", "lock_busy", "state_changed", "copy_not_found"] as const) {
    const f = readFailure(r);
    assert.equal(f.retry && !f.blocks, true, r);
    assert.doesNotMatch(f.message, /nenhuma|não há|vazi/i, r);
  }
  assert.equal(readFailure("invalid").retry, false, "pedido malformado não melhora repetindo");
});

test("F3-5 zero linhas ambíguo: topo do painel não afirma 'Falta'; erro não fica 'Conferindo…'", () => {
  assert.equal(positionStateLine({ status: "ready", total: 0 }), "Nenhuma carta aparece nesta posição agora.");
  assert.doesNotMatch(positionStateLine({ status: "ready", total: 0 }), /Falta|não tem|nenhuma carta nesta posição$/);
  assert.equal(positionStateLine({ status: "ready", total: 1 }), "1 carta nesta posição");
  assert.equal(positionStateLine({ status: "ready", total: 1234 }), "1.234 cartas nesta posição");
  assert.equal(positionStateLine({ status: "loading" }), "Conferindo as cartas desta posição…");
  assert.match(positionStateLine({ status: "error" }), /Não conseguimos conferir/);
  assert.match(positionStateLine({ status: "blocked" }), /Não conseguimos conferir/);
});

test("F3-5 nenhuma mensagem expõe token, UUID, código técnico ou enum", () => {
  const texts = [
    ...ALL_REASONS.flatMap((r) => [readFailure(r).message, writeNoticeTitle(r), reactToFailure(r).message]),
    syncMessage("confirmed_stale")!, syncMessage("stale")!,
    positionStateLine({ status: "error" }), emptyListMessage("AT_POSITION", false), emptyListMessage("ASSIGNABLE", true),
  ];
  for (const t of texts) assert.doesNotMatch(t, /pc1\.|[0-9a-f]{8}-[0-9a-f]{4}|42501|P0002|22023|55P03|28000|CAPABILITY|STATE_CHANGED|COPY_NOT_FOUND|_/);
});

// ---------------------------------------------------------------------------
// Estático: o painel e as actions só usam o contrato colaborativo.

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const FILES = [
  "components/colecoes/sharing/shared-pokedex-editor-panel.tsx",
  "components/colecoes/sharing/shared-pokedex-grid.tsx",
  "app/colecoes/compartilhada/[id]/pokedex-editor-actions.ts",
  "lib/colecoes/editor-pokedex-panel.ts",
];

test("estático: painel, grade e actions sem identificador físico, sem 5373/5380, sem token em log ou URL", () => {
  for (const f of FILES) {
    const src = readFileSync(join(WEB, f), "utf8");
    assert.doesNotMatch(src, /physical_card_id|physicalCardId|allocationId|collection_allocation/, f);
    assert.doesNotMatch(src, /get_shared_binder_placeable_cards|editor_set_pokedex_position_assignment|editor_remove_pokedex_position_assignment|editor_set_pokedex_position_primary_representative|editor_clear_pokedex_position_primary_representative/, f);
    assert.doesNotMatch(src, /console\.(log|info|warn|error)\([^;]*(copyToken|\.token|p_copy_token|args)/, `${f}: token/argumentos em log`);
    assert.doesNotMatch(src, /searchParams|router\.push\(|href=\{[^}]*token/i, `${f}: token em URL`);
  }
  const panel = readFileSync(join(WEB, FILES[0]!), "utf8");
  // O painel do titular (escritas por exemplar físico) não é importado.
  assert.doesNotMatch(panel, /pokedex-position-panel|app\/colecoes\/colecoes\/actions/);
  // Nenhuma afirmação de sucesso antes da resposta: mensagens só de resultMessage/reações.
  assert.doesNotMatch(panel, /setFeedback\(\{ tone: "success"/);
  // F3-3: sem atualização otimista — a grade só muda pela página do servidor e a confirmação só roda se ainda vale.
  assert.doesNotMatch(panel, /setItems|setOpenPosition|optimistic/i);
  assert.match(panel, /planAfter\(outcome\)/);
  assert.match(panel, /confirmationUsable\(confirm, generation\.current\) \? confirm\.intent : null/);
  assert.doesNotMatch(panel, /moveIntent\([^)]*true\)/, "confirmação nunca é recriada a partir de uma lista nova");
  assert.match(panel, /prepareConfirmation\([^;]*genAtStart\)/, "confirmação presa à geração do início da escrita");
  // F3-5: uma única chamada de escrita (sem repetição automática em catch, laço ou temporizador).
  assert.equal(panel.match(/writeEditorPokedex\(/g)?.length, 1);
  assert.doesNotMatch(panel, /setTimeout\([^)]*run\(|setInterval/);
  // Perda de acesso descarta listas, tokens e confirmação; "Tentar de novo" só relê (resync), nunca escreve.
  assert.match(panel, /if \(plan\.disable\) \{\s*block\(/);
  assert.match(panel, /onRetry=\{\(\) => void resync\(\)\}/);
  assert.match(panel, /const resync = async[\s\S]*?reloadAll\(/);
  assert.doesNotMatch(panel.slice(panel.indexOf("const resync"), panel.indexOf("const close")), /writeEditorPokedex|run\(/);
  const actions = readFileSync(join(WEB, FILES[2]!), "utf8");
  assert.match(actions, /isWriteIntent\(intent\)/, "revalida a intenção no servidor");
  assert.match(actions, /editorCurationFlagOn\(process\.env\)/);
  assert.doesNotMatch(actions, /service_role|SUPABASE_SERVICE/);
});

// ---------------------------------------------------------------------------
// F3-6 — celular e acessibilidade (estrutura; sem renderização no ambiente).

test("F3-6 estrutura: folha de tela cheia com rolagem interna, alvos de 44 px, sem rolagem lateral, busca sem zoom", () => {
  const css = readFileSync(join(WEB, "components/colecoes/sharing/shared-pokedex-editor-panel.module.css"), "utf8");
  const panel = readFileSync(join(WEB, FILES[0]!), "utf8");
  const drawer = readFileSync(join(WEB, "components/colecoes/acervo/acervo.module.css"), "utf8");
  // O drawer do projeto já vira folha de largura total abaixo de 768 px; o corpo rola por dentro.
  assert.match(drawer, /@media \(max-width: 767px\)[\s\S]*?\.drawer \{\s*width: 100%;/);
  assert.match(readFileSync(join(WEB, "components/colecoes/acervo/acervo-add.module.css"), "utf8"), /\.body \{[^}]*overflow-y: auto;/);
  assert.match(panel, /\$\{acervoStyles\.drawer\} \$\{addStyles\.panel\} \$\{local\.root\}/);
  assert.match(css, /\.root \{[^}]*overflow-x: hidden;[^}]*overflow-wrap: anywhere;/);
  assert.match(css, /\.root \.action \{[^}]*min-height: 2\.75rem;/);
  assert.match(css, /\.root \.confirmActions :is\(button\) \{[^}]*min-height: 2\.75rem;/);
  assert.match(css, /@media \(max-width: 767px\)[\s\S]*\.root \.search input \{\s*font-size: 16px;/);
  assert.match(css, /env\(safe-area-inset-bottom/);
  assert.match(css, /\.root \.cardName \{[^}]*white-space: normal;/, "nome da carta inteiro");
  // Todas as ações por carta usam o alvo de 44 px.
  assert.equal(panel.match(/className=\{styles\.copyAction\}/g), null);
  assert.ok((panel.match(/\$\{styles\.copyAction\} \$\{local\.action\}/g)?.length ?? 0) >= 3);
});

test("F3-6 confirmações: nada confirma sozinho; origem e destino explícitos; retirar pede confirmação", () => {
  const panel = readFileSync(join(WEB, FILES[0]!), "utf8");
  assert.doesNotMatch(panel, /autoFocus/, "o botão de confirmar nunca recebe o foco automaticamente");
  assert.match(panel, /ref=\{confirmRef\} tabIndex=\{-1\}/);
  assert.equal(panel.match(/role="alertdialog" aria-labelledby=\{`\$\{uid\}-[a-z-]+`\} aria-describedby=\{`\$\{uid\}-[a-z-]+`\}/g)?.length, 2);
  assert.match(panel, /<dt>De<\/dt>[\s\S]*<dt>Para<\/dt>/);
  assert.match(panel, /"Confirmar e colocar" : "Confirmar e mover"/);
  assert.doesNotMatch(panel, /onClick=\{\(\) => void run\(unassign\)\}/, "retirar não executa no primeiro toque");
  assert.match(panel, /run\(liveRemove \? unassign : null\)/, "retirar confirmado só na geração em que foi pedido");
  assert.match(panel, /onEscapeKeyDown=\{\(event\) => writing && event\.preventDefault\(\)\}/);
  assert.match(panel, /<DialogPrimitive\.Close\s+disabled=\{writing\}/);
});

test("F3-6 anúncios: sem região viva no topo (evita repetição a cada releitura); resultado com foco e uma região só", () => {
  const panel = readFileSync(join(WEB, FILES[0]!), "utf8");
  assert.doesNotMatch(panel, /className=\{styles\.panelState\} aria-live/);
  assert.equal(panel.match(/role="status" aria-live="polite"/g)?.length, 1);
  assert.match(panel, /if \(!plan\.askConfirmation\) window\.requestAnimationFrame\(\(\) => feedbackRef\.current\?\.focus\(\)\)/);
  assert.match(panel, /onCloseAutoFocus=\{restoreFocus\}/);
});

test("F3-6 histórico: alternância Pokédex/Fichário com estado anunciado e alvo de 44 px; painel do titular intocado", () => {
  const ui = readFileSync(join(WEB, "components/colecoes/sharing/shared-collection-activity.tsx"), "utf8");
  assert.equal(ui.match(/aria-pressed=\{current === "(POKEDEX|BINDER)"\}/g)?.length, 2);
  assert.match(ui, /role="group" aria-label="Qual histórico mostrar"/);
  const pk = readFileSync(join(WEB, "components/colecoes/colecoes/pokedex.module.css"), "utf8");
  assert.match(pk, /\.segmentButton \{[^}]*min-height: 2\.75rem;/);
  const owner = readFileSync(join(WEB, "components/colecoes/colecoes/pokedex-position-panel.tsx"), "utf8");
  assert.doesNotMatch(owner, /shared-pokedex-editor-panel/);
});
