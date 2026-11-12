// V1-07 — reservar bolso VAZIO para uma carta escolhida (EMPTY BINDER POCKET RESERVATION IMPLEMENTATION-01;
// D3 revisada em INVITED COLLECTION RESERVATION CORRECTION-01: coleção da reserva = a escolhida entre as do fichário).
// Executar: node --experimental-strip-types --test lib/colecoes/binder-reserve.test.ts (a partir de web/)
// Dados sintéticos — nenhum id real.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import type { BinderSlot } from "./binder.ts";
import {
  DUPLICATE_RESERVATION_WARNING,
  type ReserveCandidate,
  type ReserveContext,
  type ReserveTarget,
  applyReserveFor,
  candidateFromPosition,
  duplicateReservationCount,
  filterCandidates,
  initialReserveCollection,
  isReserveTarget,
  reservationCollectionOf,
  reserveContextOk,
  reserveForMode,
  reserveScopeOf,
  reserveScopeOfKind,
  reserveTargetsFrom,
  sameReservation,
} from "./binder-reserve.ts";

const read = (path: string) => readFileSync(new URL(`../../${path}`, import.meta.url), "utf8");
const code = (src: string) => src.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "");

const OWNER = "00000000-0000-4000-8000-0000000000a1";
const GUEST = "00000000-0000-4000-8000-0000000000b2";
const CARD = "00000000-0000-4000-8000-0000000000c3";
const OTHER_CARD = "00000000-0000-4000-8000-0000000000c4";
const HOLO = "00000000-0000-4000-8000-0000000000d5";
const REVERSE = "00000000-0000-4000-8000-0000000000d6";
const STRANGER = "00000000-0000-4000-8000-0000000000e7";
const T_OWNER: ReserveTarget = { collectionId: OWNER, name: "Celebração de 30 Anos", role: "OWNER", scope: "STANDARD_SET" };
const T_GUEST: ReserveTarget = { collectionId: GUEST, name: "Coleção Clássica", role: "GUEST", scope: "MASTER_SET" };

const ctx = (over: Partial<ReserveContext> = {}): ReserveContext => ({ editable: true, collectionId: OWNER, ownerCollectionId: OWNER, scope: "STANDARD_SET", ...over });

let seq = 0;
function slot(over: Partial<BinderSlot> = {}): BinderSlot {
  seq += 1;
  return {
    slotId: `00000000-0000-4000-8000-${String(seq).padStart(12, "0")}`,
    row: 1,
    column: 1,
    state: "EMPTY",
    locked: false,
    present: null,
    presentCardId: null,
    presentVariantTypeId: null,
    physicalCardId: null,
    expected: null,
    expectedCardId: null,
    expectedCardVariantId: null,
    expectedVariantTypeId: null,
    expectedCollectionId: null,
    image: null,
    regionId: null,
    ...over,
  } as BinderSlot;
}
const candidate = (over: Partial<ReserveCandidate> = {}): ReserveCandidate => ({
  key: CARD,
  cardId: CARD,
  variantTypeId: null,
  finishName: null,
  cardName: "Pikachu",
  collectorNumber: "025",
  collectorTotal: 165,
  setCode: "mew",
  setName: "151",
  imagePath: "cards/mew/025.webp",
  owned: false,
  ...over,
});

test("escopo: Set padrão, Master Set e livre; Pokédex e desconhecidos sem ação (D1)", () => {
  assert.deepEqual(
    ["STANDARD_SET", "MASTER_SET", "NONE", "REFERENCE_POSITION", null, "X"].map(reserveScopeOf),
    ["STANDARD_SET", "MASTER_SET", "FREE", null, null, null],
  );
  assert.deepEqual(["SET", "MASTER_SET", "FREE", "POKEDEX", "UNKNOWN"].map(reserveScopeOfKind), ["STANDARD_SET", "MASTER_SET", "FREE", null, null]);
});

test("contexto: só dono editável, aberto pela PROPRIETÁRIA, com escopo (D3; somente leitura / convidada / Pokédex fora)", () => {
  assert.equal(reserveContextOk(ctx()), true);
  assert.equal(reserveContextOk(ctx({ editable: false })), false, "arquivada ou somente leitura");
  assert.equal(reserveContextOk(ctx({ collectionId: GUEST })), false, "aberto pela convidada, antes de ler as coleções do fichário");
  assert.equal(reserveContextOk(ctx({ collectionId: GUEST, targets: [T_OWNER, T_GUEST] })), true, "com as coleções lidas, o fichário aberto pela convidada também reserva");
  assert.equal(reserveContextOk(ctx({ targets: [] })), false, "nenhuma coleção elegível (ex.: só Pokédex)");
  assert.equal(reserveContextOk(ctx({ ownerCollectionId: null })), false, "contexto incerto");
  assert.equal(reserveContextOk(ctx({ scope: null })), false, "Pokédex");
  assert.equal(reserveContextOk(ctx({ collectionId: OWNER.toUpperCase() })), true, "comparação sem caixa");
});

test("bolso vazio → reservar; vazio e travado também (trava independe da reserva, C-43)", () => {
  assert.equal(reserveForMode(slot(), ctx()), "reserve");
  assert.equal(reserveForMode(slot({ locked: true }), ctx()), "reserve");
});

test("bolso ocupado, com imagem ou em mesclagem: nenhuma ação nova (D4; gatilhos de imagem/mesclagem)", () => {
  assert.equal(reserveForMode(slot({ state: "FILLED" as BinderSlot["state"], presentCardId: CARD }), ctx()), null);
  assert.equal(reserveForMode(slot({ image: { path: "x" } as unknown as BinderSlot["image"] }), ctx()), null);
  assert.equal(reserveForMode(slot({ regionId: "r1" }), ctx()), null);
});

test("reservado e vazio: trocar só a reserva da proprietária (ou sem dona registrada); de convidada nunca", () => {
  const mine = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedCollectionId: OWNER });
  const legacy = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedCollectionId: null });
  const guest = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedCollectionId: GUEST });
  assert.equal(reserveForMode(mine, ctx()), "change");
  assert.equal(reserveForMode(legacy, ctx()), "change");
  assert.equal(reserveForMode(guest, ctx()), null, "nunca sobrescreve reserva de outra coleção");
  assert.equal(reserveForMode(mine, ctx({ editable: false })), null);
});

test("Master Set: carta + acabamento da posição; posição secreta = só carta (D2)", () => {
  const set = { code: "mew", name: "151", total: 165 };
  const holo = candidateFromPosition("MASTER_SET", { key: `${CARD}:${HOLO.toUpperCase()}`, cardId: CARD, number: "025", name: "Pikachu", finish: "Holo", owned: false }, set)!;
  assert.deepEqual([holo.variantTypeId, holo.finishName, holo.key], [HOLO, "Holo", `${CARD}:${HOLO.toUpperCase()}`]);
  const secret = candidateFromPosition("MASTER_SET", { key: `${CARD}:secreta`, cardId: CARD, number: "025", name: "Pikachu", finish: "Qualquer acabamento", owned: true }, set)!;
  assert.equal(secret.variantTypeId, null);
  const std = candidateFromPosition("STANDARD_SET", { key: CARD, cardId: CARD, number: "025", name: "Pikachu", finish: null, owned: false }, set)!;
  assert.deepEqual([std.variantTypeId, std.finishName], [null, null], "Set padrão = carta");
  assert.equal(candidateFromPosition("STANDARD_SET", { key: "x", number: "1", name: "?", finish: null, owned: false }, set), null, "sem carta → fora");
});

test("busca local: nome sem acento, número com ou sem zeros e '/total', acabamento", () => {
  const list = [
    candidate(),
    candidate({ key: "b", cardId: OTHER_CARD, cardName: "Flabébé", collectorNumber: "107" }),
    candidate({ key: "c", cardId: CARD, variantTypeId: REVERSE, finishName: "Reverse Holo" }),
  ];
  assert.equal(filterCandidates(list, "").length, 3);
  assert.deepEqual(filterCandidates(list, "flabebe").map((c) => c.key), ["b"]);
  assert.deepEqual(filterCandidates(list, "25").map((c) => c.key), [CARD, "c"]);
  assert.deepEqual(filterCandidates(list, "025/165").map((c) => c.key), [CARD, "c"]);
  assert.deepEqual(filterCandidates(list, "reverse").map((c) => c.key), ["c"]);
});

test("duplicidade: avisa (não bloqueia) com o texto aprovado; ignora o próprio bolso e acabamento diferente (D5)", () => {
  const target = slot();
  const a = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedVariantTypeId: HOLO });
  const b = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedVariantTypeId: REVERSE });
  assert.equal(duplicateReservationCount([target, a, b], candidate(), target.slotId, OWNER, OWNER), 2, "só carta: qualquer acabamento conta");
  assert.equal(duplicateReservationCount([target, a, b], candidate({ variantTypeId: HOLO }), target.slotId, OWNER, OWNER), 1);
  assert.equal(duplicateReservationCount([a], candidate({ variantTypeId: HOLO }), a.slotId, OWNER, OWNER), 0, "troca no próprio bolso não é duplicata");
  assert.equal(
    DUPLICATE_RESERVATION_WARNING,
    "Esta carta já possui outra reserva neste fichário. Reservas duplicadas podem gerar ambiguidade na organização automática.",
  );
  assert.equal(sameReservation(slot({ expectedCardId: OTHER_CARD }), candidate()), false);
});

test("prévia otimista: reservado e vazio, da proprietária, com a face da carta escolhida; trava preservada", () => {
  const before = slot({ locked: true });
  const after = applyReserveFor(before, candidate({ variantTypeId: HOLO, finishName: "Holo" }), OWNER);
  assert.equal(after.state, "RESERVED_EMPTY");
  assert.deepEqual([after.expectedCardId, after.expectedVariantTypeId, after.expectedCardVariantId, after.expectedCollectionId], [CARD, HOLO, null, OWNER]);
  assert.equal(after.expected?.cardName, "Pikachu");
  assert.equal(after.locked, true);
  assert.equal(after.presentCardId, null, "nada é movido para o bolso");
});

test("estrutura: gravação pela 5128 existente, sem coleção informada; leitura sem escrita; nada de organização automática", () => {
  const actions = code(read("app/colecoes/colecoes/[id]/fichario/actions.ts"));
  const reserve = actions.slice(actions.indexOf("export async function reserveSlot"), actions.indexOf("async function loadReserveTargets"));
  assert.ok(reserve.includes('"set_slot_expected_content"'));
  assert.ok(reserve.includes("...(target !== null ? { p_collection_id: target } : {})"), "coleção só quando escolhida; sem ela, o comportamento de antes (bolso ocupado)");
  assert.ok(reserve.includes("(target !== null && !isCollectionId(target))"), "id malformado recusado antes do banco");
  const readFn = actions.slice(actions.indexOf("export async function readReservationCandidates"), actions.indexOf("export async function clearReservations"));
  assert.ok(readFn.includes("getMyCollection") && readFn.includes("getChecklist") && readFn.includes('"search_cards"'));
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(|set_slot_expected_content/.test(readFn), "leitura de candidatas não grava");
  const picker = code(read("components/colecoes/fichario/binder-reserve-picker.tsx"));
  assert.ok(picker.includes("useDialogKeys(") && picker.includes('role="dialog"') && picker.includes('aria-modal="true"'), "Esc, foco preso e retorno");
  assert.ok(picker.includes("DUPLICATE_RESERVATION_WARNING") && picker.includes('aria-live="polite"'));
  assert.ok(!/arrange|auto_arrange|5343|5344/i.test(picker), "sem organização automática");
  const ws = code(read("components/colecoes/fichario/binder-workspace.tsx"));
  const run = ws.slice(ws.indexOf("const runReserveFor"), ws.indexOf("const runClearReservation"));
  assert.ok(/reserveSlot\(\{\s*collectionId,\s*slotId: before\.slotId,\s*cardId: candidate\.cardId,\s*variantTypeId: candidate\.variantTypeId,\s*reservationCollectionId,\s*\}\)/.test(run));
  assert.ok(run.includes("isReserveTarget(reserveCtx, reservationCollectionId)"), "só destino do fichário");
  assert.ok(run.includes("patchSlots([before])"), "recusa: o bolso volta como estava");
  assert.ok(run.includes("refreshPages([entry.page])"), "releitura confirma");
});

test("superfícies: fichário compartilhado não oferece a ação; Pokédex sem escopo; ação existente do bolso ocupado preservada", () => {
  const shared = code(read("components/colecoes/sharing/shared-binder-workspace.tsx"));
  assert.ok(!/reserveForMode|onReserveFor|reserveScope/.test(shared));
  const slotSrc = code(read("components/colecoes/fichario/binder-slot.tsx"));
  assert.ok(slotSrc.includes('"Reservar este bolso para a carta"') || slotSrc.includes("Reservar este bolso para a carta"), "D4: ação do bolso ocupado continua");
  assert.ok(slotSrc.includes("Reservar este bolso para uma carta…") && slotSrc.includes("Trocar carta reservada…") && slotSrc.includes("Liberar reserva deste bolso"));
  assert.ok(slotSrc.includes("reserveForMode?: (slot: BinderSlot)") && slotSrc.includes("onReserveFor?: (slot: BinderSlot)"), "handlers opcionais");
  const view = code(read("components/colecoes/fichario/binder-view.tsx"));
  const overlay = code(read("components/colecoes/fichario/binder-overlay.tsx"));
  assert.ok(view.includes("reserveScope={reserveScopeOf(collection.policy)}") && overlay.includes("reserveScope={reserveScopeOfKind(header.kind)}"));
});

// ---- D3 revisada: coleções convidadas (INVITED COLLECTION RESERVATION CORRECTION-01) ----

const participants = [
  { collectionId: GUEST.toUpperCase(), name: "Coleção Clássica", role: "GUEST" as const, active: true },
  { collectionId: OWNER, name: "Celebração de 30 Anos", role: "OWNER" as const, active: true },
  { collectionId: "00000000-0000-4000-8000-0000000000f1", name: "Pokédex Kanto", role: "GUEST" as const, active: true },
  { collectionId: "00000000-0000-4000-8000-0000000000f2", name: "Antiga", role: "GUEST" as const, active: false },
  { collectionId: "00000000-0000-4000-8000-0000000000f3", name: "Livre", role: "GUEST" as const, active: true },
];
const policies = new Map<string, string | null>([
  [GUEST, "MASTER_SET"],
  [OWNER, "STANDARD_SET"],
  ["00000000-0000-4000-8000-0000000000f1", "REFERENCE_POSITION"],
  ["00000000-0000-4000-8000-0000000000f2", "STANDARD_SET"],
  ["00000000-0000-4000-8000-0000000000f3", "NONE"],
]);

test("destinos: só coleções do fichário, ativas e com reserva por carta; dona primeiro; Pokédex e arquivada à parte", () => {
  const { targets, excluded } = reserveTargetsFrom(participants, policies);
  assert.deepEqual(
    targets.map((t) => [t.name, t.role, t.scope]),
    [
      ["Celebração de 30 Anos", "OWNER", "STANDARD_SET"],
      ["Coleção Clássica", "GUEST", "MASTER_SET"],
      ["Livre", "GUEST", "FREE"],
    ],
  );
  assert.equal(targets[1]!.collectionId, GUEST, "id normalizado");
  assert.deepEqual(excluded.map((e) => [e.name, e.reason]).sort(), [["Antiga", "archived"], ["Pokédex Kanto", "pokedex"]]);
  // Fichário com uma coleção: um destino só (o seletor não mostra escolha).
  assert.equal(reserveTargetsFrom([participants[1]!], policies).targets.length, 1);
  // Coleção que não está no fichário nunca vira destino, mesmo com política conhecida.
  assert.ok(!targets.some((t) => t.collectionId === STRANGER));
});

test("destino válido: só os do fichário; id arbitrário recusado (também antes da leitura)", () => {
  const read = ctx({ targets: [T_OWNER, T_GUEST] });
  assert.equal(isReserveTarget(read, OWNER), true);
  assert.equal(isReserveTarget(read, GUEST.toUpperCase()), true);
  assert.equal(isReserveTarget(read, STRANGER), false, "coleção não vinculada");
  assert.equal(isReserveTarget(ctx(), OWNER), true, "antes da leitura: só a proprietária aberta");
  assert.equal(isReserveTarget(ctx(), GUEST), false);
});

test("troca: reserva da convidada pode ser trocada (fica na convidada); de coleção fora da escolha, não", () => {
  const guestReserved = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedCollectionId: GUEST });
  assert.equal(reserveForMode(guestReserved, ctx({ targets: [T_OWNER, T_GUEST] })), "change");
  assert.equal(reserveForMode(guestReserved, ctx({ targets: [T_OWNER] })), null, "convidada arquivada/Pokédex: sem troca (Liberar continua)");
  assert.equal(reserveForMode(guestReserved, ctx()), null, "antes da leitura: nunca mexe na reserva da convidada");
  assert.equal(reservationCollectionOf(slot({ expectedCollectionId: null }), OWNER), OWNER, "sem registro = proprietária");
  assert.equal(
    initialReserveCollection({ mode: "change", slot: guestReserved, targets: [T_OWNER, T_GUEST], remembered: OWNER, openingCollectionId: OWNER, ownerCollectionId: OWNER }),
    GUEST,
    "a coleção original prevalece sobre a última escolha",
  );
});

test("coleção inicial: última escolhida neste fichário (se ainda vale) → aberta → dona", () => {
  const base = { mode: "reserve" as const, slot: slot(), targets: [T_OWNER, T_GUEST], openingCollectionId: OWNER, ownerCollectionId: OWNER };
  assert.equal(initialReserveCollection({ ...base, remembered: null }), OWNER);
  assert.equal(initialReserveCollection({ ...base, remembered: GUEST }), GUEST, "escolha lembrada");
  assert.equal(initialReserveCollection({ ...base, remembered: STRANGER }), OWNER, "lembrança obsoleta (ex.: de outro fichário) é ignorada");
  assert.equal(initialReserveCollection({ ...base, remembered: null, openingCollectionId: GUEST }), GUEST, "aberto pela convidada");
  assert.equal(initialReserveCollection({ ...base, remembered: null, targets: [] }), null);
});

test("reserva da convidada: prévia com a coleção escolhida; carta não possuída; Master Set com acabamento; duplicidade por coleção", () => {
  const holo = candidateFromPosition(
    "MASTER_SET",
    { key: `${CARD}:${HOLO}`, cardId: CARD, number: "025", name: "Pikachu", finish: "Holo", owned: false },
    { code: "mew", name: "151", total: 165 },
  )!;
  assert.equal(holo.owned, false, "posição que ainda falta na convidada");
  const after = applyReserveFor(slot(), holo, GUEST.toUpperCase());
  assert.deepEqual([after.expectedCollectionId, after.expectedVariantTypeId], [GUEST, HOLO]);
  const ownerSame = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedVariantTypeId: HOLO, expectedCollectionId: null });
  const guestSame = slot({ state: "RESERVED_EMPTY", expectedCardId: CARD, expectedVariantTypeId: HOLO, expectedCollectionId: GUEST });
  const target = slot();
  assert.equal(duplicateReservationCount([ownerSame, guestSame], holo, target.slotId, GUEST, OWNER), 1, "só a da convidada conta para a convidada");
  assert.equal(duplicateReservationCount([ownerSame, guestSame], holo, target.slotId, OWNER, OWNER), 1, "sem registro conta como proprietária");
});

test("estrutura (D3 revisada): destinos pela 5246; candidatas validam a coleção; seletor limpa ao trocar e não grava dados antigos", () => {
  const actions = code(read("app/colecoes/colecoes/[id]/fichario/actions.ts"));
  const load = actions.slice(actions.indexOf("async function loadReserveTargets"), actions.indexOf("export async function readReservationTargets"));
  assert.ok(load.includes('"get_my_binder_participants"') && load.includes("getMyCollectionsByIds") && load.includes("reserveTargetsFrom"), "mesma fonte das Coleções neste fichário");
  const cand = actions.slice(actions.indexOf("export async function readReservationCandidates"), actions.indexOf("export async function clearReservations"));
  assert.ok(cand.includes("loadReserveTargets(supabase, input.collectionId)") && cand.includes('return { ok: false, reason: "not_found" }'), "coleção fora do fichário recusada");
  assert.ok(cand.includes("getMyCollection(supabase, targetId)"), "origem pelo tipo da coleção escolhida");
  assert.ok(!/\.insert\(|\.update\(|\.delete\(|\.upsert\(/.test(load + cand));
  const picker = code(read("components/colecoes/fichario/binder-reserve-picker.tsx"));
  const sw = picker.slice(picker.indexOf("const switchCollection"), picker.indexOf("const visible"));
  for (const reset of ["setSelected(null)", 'setQuery("")', 'setLoad({ status: "loading" })', "onCollectionChange?.(next)"]) assert.ok(sw.includes(reset), reset);
  assert.ok(picker.includes('role="radiogroup"') && picker.includes("aria-labelledby={collectionLabelId}"), "escolha acessível por teclado/leitor");
  assert.ok(picker.includes('const canSwitch = mode === "reserve" && targets.length > 1;'), "uma coleção: sem escolha; troca: coleção original");
  assert.ok(picker.includes("selected && ready && onConfirm(selected, reserveCollection)") && picker.includes("load.collectionId === reserveCollection"), "nunca grava com cartas de outra coleção");
  const ws = code(read("components/colecoes/fichario/binder-workspace.tsx"));
  assert.ok(ws.includes("useState<string | null>(null)") && ws.includes("onCollectionChange={setRememberedReserveCollection}"), "lembrança só em memória deste fichário aberto");
  assert.ok(!/localStorage|sessionStorage/.test(picker), "nada persiste entre fichários");
  const css = read("components/colecoes/fichario/binder-reserve.module.css");
  assert.ok(/@media \(max-width: 639px\)[\s\S]*\.collectionOption \{\s*min-height: 44px/.test(css), "celular: alvo de 44 px");
  // Adicionar carta continua igual no bolso vazio.
  const slotSrc = code(read("components/colecoes/fichario/binder-slot.tsx"));
  assert.ok(slotSrc.includes('<QuickButton icon={Plus} label="Adicionar carta" onClick={() => handlers.onAddCard(slot)} size={size} />'));
});
