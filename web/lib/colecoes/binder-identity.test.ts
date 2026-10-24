// Identidade e Centro de Controle do Fichário (P3-A) — regras puras.
// Executar: node --experimental-strip-types --test lib/colecoes/binder-identity.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  BINDER_NAME_MAX,
  classifyIdentityFailure,
  identityFailureMessage,
  nameLength,
  normalizeBinderName,
  occupancyPercent,
  binderProgressView,
  buildBinderProgress,
  parseBinderIdentity,
  parseBinderOccupancy,
  parseBinderParticipants,
  parseControlPanelPrefs,
  parseIdentityWrite,
  resolveIdentity,
} from "./binder-identity.ts";

const LAYOUT = "11111111-1111-4111-8111-111111111111";
const OWNER = "22222222-2222-4222-8222-222222222222";

test("normaliza como o servidor: colapsa espaços e apara as pontas", () => {
  assert.deepEqual(normalizeBinderName("  Meu   Fichário  "), { ok: true, value: "Meu Fichário" });
  assert.deepEqual(normalizeBinderName("   "), { ok: true, value: null });
  assert.deepEqual(normalizeBinderName(""), { ok: true, value: null });
});

test("recusa quebra de linha, tab e outros caracteres de controle (não 'conserta')", () => {
  assert.deepEqual(normalizeBinderName("Linha\nquebrada"), { ok: false, reason: "control" });
  assert.deepEqual(normalizeBinderName("Tab\tdentro"), { ok: false, reason: "control" });
  assert.deepEqual(normalizeBinderName("Nulo\u0000"), { ok: false, reason: "control" });
});

test("limite de 60 caracteres conta caracteres, não bytes nem unidades UTF-16", () => {
  assert.equal(normalizeBinderName("é".repeat(60)).ok, true);
  assert.deepEqual(normalizeBinderName("a".repeat(61)), { ok: false, reason: "too_long" });
  // Emoji ocupa 2 unidades UTF-16 mas é 1 caractere (char_length no Postgres).
  assert.equal(nameLength("🃏".repeat(BINDER_NAME_MAX)), BINDER_NAME_MAX);
  assert.equal(normalizeBinderName("🃏".repeat(BINDER_NAME_MAX)).ok, true);
  assert.deepEqual(normalizeBinderName("x".repeat(201)), { ok: false, reason: "too_long" });
  // Espaços extras não contam depois de colapsados.
  assert.equal(normalizeBinderName(`  ${"a".repeat(60)}   `).ok, true);
});

test("lê a identidade do banco e recusa forma inesperada", () => {
  const row = {
    layout_id: LAYOUT,
    binder_role: "OWNER",
    owner_collection_id: OWNER,
    owner_collection_name: "Escarlate e Violeta",
    display_name: "Fichário Azul",
    effective_name: "Fichário Azul",
    show_brand_mark: false,
    can_edit_identity: true,
  };
  assert.deepEqual(parseBinderIdentity([row]), {
    layoutId: LAYOUT,
    role: "OWNER",
    ownerCollectionId: OWNER,
    ownerCollectionName: "Escarlate e Violeta",
    displayName: "Fichário Azul",
    effectiveName: "Fichário Azul",
    showBrandMark: false,
    canEdit: true,
  });
  assert.equal(parseBinderIdentity([]), "absent");
  assert.equal(parseBinderIdentity([{ ...row, show_brand_mark: "yes" }]), null);
  assert.equal(parseBinderIdentity([{ ...row, binder_role: "ADMIN" }]), null);
  assert.equal(parseBinderIdentity([row, row]), null);
  assert.equal(parseBinderIdentity(null), null);
  // can_edit ausente nunca vira "pode editar".
  const { can_edit_identity: _ignored, ...noEdit } = row;
  assert.equal((parseBinderIdentity([noEdit]) as { canEdit: boolean }).canEdit, false);
});

test("fallback: sem leitura do banco usa o nome da coleção proprietária, logomarca exibida e sem edição", () => {
  assert.deepEqual(resolveIdentity(null, { collectionName: "Convidada", ownerCollectionName: "Dona" }), {
    name: "Dona",
    displayName: null,
    showBrandMark: true,
    canEdit: false,
    source: "fallback",
  });
  assert.equal(resolveIdentity(null, { collectionName: "Própria", ownerCollectionName: null }).name, "Própria");
});

test("resultado da gravação: UPDATED/UNCHANGED e estado canônico", () => {
  assert.deepEqual(parseIdentityWrite([{ layout_id: LAYOUT, display_name: null, effective_name: "Dona", show_brand_mark: true, operation: "UPDATED" }]), {
    displayName: null,
    effectiveName: "Dona",
    showBrandMark: true,
    changed: true,
  });
  assert.equal(parseIdentityWrite([{ display_name: "X", effective_name: "X", show_brand_mark: true, operation: "UNCHANGED" }])?.changed, false);
  assert.equal(parseIdentityWrite([{ effective_name: "X", show_brand_mark: true, operation: "DONE" }]), null);
});

test("ocupação: cada bolso conta uma vez — soma incoerente é recusada", () => {
  const base = {
    grid_columns: 3,
    grid_rows: 3,
    page_count: 2,
    pocket_count: 18,
    card_pocket_count: 9,
    image_pocket_count: 1,
    merged_pocket_count: 2,
    reserved_empty_count: 2,
    free_pocket_count: 4,
    merged_region_count: 1,
    merged_image_count: 1,
    participant_count: 2,
  };
  const ok = parseBinderOccupancy([base]);
  assert.ok(ok && ok !== "absent");
  assert.equal(ok.pockets, 18);
  assert.equal(occupancyPercent(ok), 67); // (9 + 1 + 2) / 18
  assert.equal(parseBinderOccupancy([{ ...base, free_pocket_count: 5 }]), null);
  assert.equal(parseBinderOccupancy([{ ...base, card_pocket_count: -1 }]), null);
  assert.equal(parseBinderOccupancy([]), "absent");
  assert.equal(occupancyPercent({ pockets: 0, cards: 0, images: 0, merged: 0 }), 0);
});

test("participantes: lê papel, estado e cartas; linha malformada invalida a lista", () => {
  const list = parseBinderParticipants([
    { collection_id: OWNER, collection_name: "Dona", binder_role: "OWNER", lifecycle_status: "ACTIVE", is_current: true, card_pocket_count: 3 },
    { collection_id: LAYOUT, collection_name: "Convidada", binder_role: "GUEST", lifecycle_status: "ARCHIVED", is_current: false, card_pocket_count: 0 },
  ]);
  assert.deepEqual(list?.map((p) => [p.role, p.active, p.current, p.cards]), [
    ["OWNER", true, true, 3],
    ["GUEST", false, false, 0],
  ]);
  assert.equal(parseBinderParticipants([{ collection_id: OWNER, binder_role: "OWNER", card_pocket_count: 1 }]), null);
  assert.deepEqual(parseBinderParticipants([]), []);
});

test("falhas do servidor viram mensagens do colecionador", () => {
  assert.equal(classifyIdentityFailure("22023", "INVALID_BINDER_NAME"), "invalid_name");
  assert.equal(classifyIdentityFailure("42501", "BINDER_OWNER_ONLY"), "owner_only");
  assert.equal(classifyIdentityFailure("55000", "COLLECTION_ARCHIVED"), "archived");
  assert.equal(classifyIdentityFailure("P0002", "COLLECTION_NOT_FOUND"), "not_found");
  assert.equal(classifyIdentityFailure("PGRST202", "Could not find the function"), "unavailable");
  assert.equal(classifyIdentityFailure("55P03", "lock timeout"), "lock_busy");
  assert.equal(classifyIdentityFailure("XX000", "boom"), "unknown");
  assert.match(identityFailureMessage("owner_only"), /coleção dona/);
  assert.doesNotMatch(identityFailureMessage("unknown"), /[A-Z_]{6,}/); // nunca expõe código interno
});

test("preferências do painel (navegador): tolerantes a lixo e a seções desconhecidas", () => {
  assert.deepEqual(parseControlPanelPrefs(null), { open: false, collapsed: [] });
  assert.deepEqual(parseControlPanelPrefs("{oops"), { open: false, collapsed: [] });
  assert.deepEqual(parseControlPanelPrefs(JSON.stringify({ open: true, collapsed: ["info", "x", "info"] })), { open: true, collapsed: ["info"] });
});

// ---- Progresso das coleções do fichário (OWNER-PROGRESS-01 → MULTI-COLLECTION-PROGRESS-01) ----

const base = { name: "Base Set", completionPolicy: "STANDARD_SET", lifecycleStatus: "ACTIVE", isComplete: false };

test("progresso da dona: usa os números do resumo oficial, sem recontar", () => {
  const v = binderProgressView({ ...base, totalPositions: 102, satisfiedPositions: 87 });
  assert.equal(v.kind, "goal");
  if (v.kind !== "goal") return;
  assert.equal(v.satisfied, 87);
  assert.equal(v.total, 102);
  assert.equal(v.percent, 85);
  assert.equal(v.percentText, "85%");
  assert.equal(v.label, "87 de 102 cartas");
  assert.equal(v.unit, "cartas");
  assert.equal(v.archived, false);
});

test("progresso da dona: nunca passa do total nem fica negativo", () => {
  const over = binderProgressView({ ...base, totalPositions: 10, satisfiedPositions: 12, isComplete: true });
  assert.ok(over.kind === "goal" && over.satisfied === 10 && over.percent === 100 && over.complete);
  const neg = binderProgressView({ ...base, totalPositions: 10, satisfiedPositions: -3 });
  assert.ok(neg.kind === "goal" && neg.satisfied === 0 && neg.percent === 0);
});

test("progresso da dona: 99,6% não vira 100% e 1 de 1.025 não vira 0%", () => {
  const almost = binderProgressView({ ...base, totalPositions: 250, satisfiedPositions: 249 });
  assert.ok(almost.kind === "goal" && almost.percent === 99);
  const tiny = binderProgressView({ ...base, completionPolicy: "REFERENCE_POSITION", totalPositions: 1025, satisfiedPositions: 1 });
  assert.ok(tiny.kind === "goal" && tiny.percentText === "<1%" && tiny.barPercent === 1);
});

test("progresso da dona: Pokédex conta Pokémon, não cartas", () => {
  const v = binderProgressView({ ...base, name: "Kanto", completionPolicy: "REFERENCE_POSITION", totalPositions: 151, satisfiedPositions: 40 });
  assert.ok(v.kind === "goal" && v.unit === "Pokémon" && v.label === "40 de 151 Pokémon");
});

test("progresso da dona: Coleção livre não tem total previsto; arquivada é sinalizada", () => {
  assert.deepEqual(binderProgressView({ ...base, completionPolicy: "NONE", totalPositions: 0, satisfiedPositions: 0 }), {
    kind: "free",
    name: "Base Set",
    archived: false,
  });
  const archived = binderProgressView({ ...base, lifecycleStatus: "ARCHIVED", totalPositions: 102, satisfiedPositions: 50 });
  assert.equal(archived.archived, true);
});

function nth<T>(list: readonly T[], index: number): T {
  const value = list[index];
  assert.ok(value !== undefined, `sem item ${index}`);
  return value;
}

const G1 = "33333333-3333-4333-8333-333333333333";
const G2 = "44444444-4444-4444-8444-444444444444";
const G3 = "55555555-5555-4555-8555-555555555555";
const part = (collectionId: string, name: string, role: "OWNER" | "GUEST", extra: Partial<{ current: boolean; active: boolean; cards: number }> = {}) => ({
  collectionId,
  name,
  role,
  current: extra.current ?? false,
  active: extra.active ?? true,
  cards: extra.cards ?? 0,
});
const prog = (name: string, satisfied: number, total: number, extra: Partial<typeof base> = {}) => ({
  ...base,
  name,
  totalPositions: total,
  satisfiedPositions: satisfied,
  ...extra,
});

test("multi-coleção: dona com uma convidada — dona primeiro, cada uma com o próprio número (nada somado)", () => {
  const entries = buildBinderProgress([part(G1, "Coleção Clássica", "GUEST"), part(OWNER, "Celebração de 30 Anos", "OWNER", { current: true })], {
    [OWNER]: prog("Celebração de 30 Anos", 148, 158),
    [G1]: prog("Coleção Clássica", 7, 102),
  });
  assert.deepEqual(
    entries.map((e) => [e.role, e.name, e.view?.kind === "goal" ? e.view.label : null, e.view?.kind === "goal" ? e.view.percentText : null]),
    [
      ["OWNER", "Celebração de 30 Anos", "148 de 158 cartas", "93%"],
      ["GUEST", "Coleção Clássica", "7 de 102 cartas", "6%"],
    ],
  );
  assert.equal(nth(entries, 0).current, true);
});

test("multi-coleção: várias convidadas em ordem estável por nome (pt-BR, sem acento/caixa) e id no empate", () => {
  const participants = [
    part(G3, "zeta", "GUEST"),
    part(G2, "Álbum", "GUEST"),
    part(OWNER, "Principal", "OWNER"),
    part(G1, "álbum", "GUEST"),
  ];
  const progress = { [OWNER]: prog("Principal", 1, 2), [G1]: prog("álbum", 1, 2), [G2]: prog("Álbum", 1, 2), [G3]: prog("zeta", 1, 2) };
  const ids = buildBinderProgress(participants, progress).map((e) => e.collectionId);
  assert.deepEqual(ids, [OWNER, G1, G2, G3]);
  // Mesma entrada em outra ordem → mesma saída.
  assert.deepEqual(buildBinderProgress([...participants].reverse(), progress).map((e) => e.collectionId), ids);
});

test("multi-coleção: sem resumo autorizado/disponível vira indisponível, nunca um valor inventado", () => {
  const entries = buildBinderProgress([part(OWNER, "Principal", "OWNER"), part(G1, "Outra", "GUEST", { cards: 40 })], {
    [OWNER]: prog("Principal", 10, 20),
  });
  assert.equal(nth(entries, 1).view, null);
  assert.equal(nth(entries, 1).name, "Outra");
});

test("multi-coleção: livre, completa e arquivada preservadas por coleção; ids repetidos aparecem uma vez", () => {
  const entries = buildBinderProgress(
    [part(OWNER, "Dona", "OWNER"), part(G1, "Livre", "GUEST"), part(G2, "Velha", "GUEST", { active: false }), part(G2, "Velha", "GUEST")],
    {
      [OWNER]: prog("Dona", 30, 30, { isComplete: true }),
      [G1]: prog("Livre", 0, 0, { completionPolicy: "NONE" }),
      [G2]: prog("Velha", 5, 10, { lifecycleStatus: "ARCHIVED" }),
    },
  );
  assert.equal(entries.length, 3);
  const owner = nth(entries, 0).view;
  assert.ok(owner?.kind === "goal" && owner.complete && owner.percentText === "100%");
  assert.equal(nth(entries, 1).view?.kind, "free");
  assert.ok(nth(entries, 2).view?.archived === true);
});

test("multi-coleção: ids em caixa alta do banco casam com o mapa normalizado", () => {
  const entries = buildBinderProgress([part(OWNER.toUpperCase(), "Dona", "OWNER")], { [OWNER]: prog("Dona", 1, 3) });
  const view = nth(entries, 0).view;
  assert.ok(view?.kind === "goal" && view.percentText === "33%");
});
