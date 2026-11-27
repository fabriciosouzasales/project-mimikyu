// V1-13 · E3 / F3-4 — histórico da Pokédex da coleção (5395): contrato, rótulos, autoria e privacidade.
// Executar: node --experimental-strip-types --test lib/colecoes/collection-activity.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { attributionByline, cursorAfter, describeEvent, detailFields, headlineEvent } from "./binder-activity.ts";
import {
  COLLECTION_ACTIVITY_PAGE_SIZE,
  POKEDEX_ACTIVITY_TYPES,
  classifyCollectionActivityFailure,
  collectionActivityEmptyMessage,
  collectionActivityFailureMessage,
  parseCollectionActivityEvent,
  parseCollectionActivityPage,
  pokedexActorLabel,
} from "./collection-activity.ts";

const POS = { number: 25, species: "Pikachu" };
const POS2 = { number: 26, species: "Raichu" };
const CARD = { name: "Pikachu ex", number: "063", set: "sv8", variant: "Holo" };
const PREV = { name: "Pikachu", number: "025", set: "base1" };

const SUMMARIES: Record<string, Record<string, unknown>> = {
  POKEDEX_POSITION_ASSIGNED: { to: POS, card: CARD, basis: "SPECIES_MATCH" },
  POKEDEX_POSITION_MOVED: { from: POS2, to: POS, card: CARD, basis: "USER_OVERRIDE", representative_cleared: true },
  POKEDEX_POSITION_REMOVED: { from: POS, card: CARD, representative_cleared: false },
  POKEDEX_REPRESENTATIVE_SET: { position: POS, card: CARD },
  POKEDEX_REPRESENTATIVE_REPLACED: { position: POS, card: CARD, previous_card: PREV },
  POKEDEX_REPRESENTATIVE_RESTORED: { position: POS, previous_card: PREV },
  POKEDEX_POSITIONS_CHANGED: { assigned: 2, removed: 1, representatives_set: 0, representatives_cleared: 1 },
};

function row(type: string, over: Record<string, unknown> = {}) {
  const derived = type === "POKEDEX_POSITIONS_CHANGED";
  return {
    event_id: 10,
    occurred_at: "2026-11-27T15:00:00Z",
    event_type: type,
    origin: derived ? "DERIVED" : "EXPLICIT",
    actor_role: "EDITOR",
    actor_display_name: "Ana",
    summary: SUMMARIES[type],
    ...over,
  };
}

test("contrato 5395: colunas exatas, tipos, origem coerente com o tipo", () => {
  assert.equal(POKEDEX_ACTIVITY_TYPES.length, 7);
  for (const type of POKEDEX_ACTIVITY_TYPES) assert.ok(parseCollectionActivityEvent(row(type)), type);
  assert.equal(parseCollectionActivityEvent(row("CARD_PLACED")), null, "tipo do fichário não entra");
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { origin: "DERIVED" })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITIONS_CHANGED", { origin: "EXPLICIT" })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { event_id: 0 })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { occurred_at: "ontem" })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { actor_role: "VIEWER" })), null);
  assert.equal(parseCollectionActivityEvent(null), null);
});

test("privacidade: coluna ou chave fora do contrato (ids, alocação, exemplar) invalida o evento", () => {
  assert.equal(parseCollectionActivityEvent({ ...row("POKEDEX_POSITION_ASSIGNED"), actor_user_id: "u1" }), null);
  assert.equal(parseCollectionActivityEvent({ ...row("POKEDEX_POSITION_ASSIGNED"), owner_user_id: "u1" }), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { summary: { ...SUMMARIES.POKEDEX_POSITION_ASSIGNED, card: { ...CARD, physical_card_id: "x" } } })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { summary: { ...SUMMARIES.POKEDEX_POSITION_ASSIGNED, to: { ...POS, id: "p1" } } })), null);
  // Chave de resumo desconhecida é descartada (não exibida).
  const e = parseCollectionActivityEvent(row("POKEDEX_REPRESENTATIVE_SET", { summary: { ...SUMMARIES.POKEDEX_REPRESENTATIVE_SET, allocation_id: "a1" } }))!;
  assert.deepEqual(Object.keys(e.summary).sort(), ["card", "position"]);
  for (const type of POKEDEX_ACTIVITY_TYPES) {
    const ev = parseCollectionActivityEvent(row(type))!;
    const text = JSON.stringify([describeEvent(ev), headlineEvent(ev), detailFields(ev)]);
    assert.doesNotMatch(text, /[0-9a-f]{8}-[0-9a-f]{4}|POKEDEX_|EXPLICIT|DERIVED|SPECIES_MATCH|USER_OVERRIDE/, type);
  }
});

test("resumos incompletos ou incoerentes → evento recusado", () => {
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { summary: { to: POS, card: CARD } })), null, "sem base");
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_MOVED", { summary: { to: POS, card: CARD, basis: "SPECIES_MATCH", representative_cleared: false } })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_REPRESENTATIVE_REPLACED", { summary: { position: POS, card: CARD } })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITIONS_CHANGED", { summary: { assigned: -1, removed: 0, representatives_set: 0, representatives_cleared: 0 } })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { summary: { ...SUMMARIES.POKEDEX_POSITION_ASSIGNED, to: { number: 0, species: "X" } } })), null);
});

test("rótulos do colecionador para os 7 tipos (frase própria, sem genérico)", () => {
  const seen = new Set<string>();
  for (const type of POKEDEX_ACTIVITY_TYPES) {
    const ev = parseCollectionActivityEvent(row(type))!;
    const v = describeEvent(ev);
    assert.notEqual(v.title, "Atividade no fichário", type);
    assert.notEqual(v.title, "Atividade na Pokédex", type);
    seen.add(v.title);
    assert.ok(headlineEvent(ev).length <= 40, headlineEvent(ev));
  }
  assert.equal(seen.size, 7);
  const moved = describeEvent(parseCollectionActivityEvent(row("POKEDEX_POSITION_MOVED"))!);
  assert.equal(moved.title, "Pikachu ex movida de #0026 Raichu para #0025 Pikachu");
  assert.match(moved.context ?? "", /Deixou de representar a posição anterior/);
  assert.match(moved.context ?? "", /Exceção/);
  const derived = describeEvent(parseCollectionActivityEvent(row("POKEDEX_POSITIONS_CHANGED"))!);
  assert.equal(derived.context, "2 cartas colocadas · 1 carta retirada · 1 representante desfeita");
});

test("autoria e papel: só o que a 5395 devolveu; SYSTEM sem autor; nada inferido", () => {
  const ed = parseCollectionActivityEvent(row("POKEDEX_REPRESENTATIVE_SET"))!;
  assert.equal(attributionByline(ed), "por Ana");
  const f = Object.fromEntries(detailFields(ed).map((x) => [x.label, x.value]));
  assert.equal(f.Por, "Ana");
  assert.equal(f.Papel, "Pode organizar");
  assert.ok(f.Quando);
  const owner = parseCollectionActivityEvent(row("POKEDEX_REPRESENTATIVE_SET", { actor_role: "OWNER", actor_display_name: null }))!;
  assert.equal(attributionByline(owner), "por Titular");
  assert.equal(Object.fromEntries(detailFields(owner).map((x) => [x.label, x.value])).Papel, "Titular");
  const sys = parseCollectionActivityEvent(row("POKEDEX_POSITIONS_CHANGED", { actor_role: "SYSTEM", actor_display_name: null }))!;
  assert.equal(attributionByline(sys), null);
  assert.match(Object.fromEntries(detailFields(sys).map((x) => [x.label, x.value])).Por ?? "", /Registro automático/);
  // SYSTEM com nome ou em evento explícito: fora do contrato.
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITIONS_CHANGED", { actor_role: "SYSTEM", actor_display_name: "Ana" })), null);
  assert.equal(parseCollectionActivityEvent(row("POKEDEX_POSITION_ASSIGNED", { actor_role: "SYSTEM", actor_display_name: null })), null);
  assert.equal(pokedexActorLabel("EDITOR"), "Pode organizar");
});

test("ordem e paginação: (occurred_at, id) decrescente; cursor = último evento; teto de 100", () => {
  const a = row("POKEDEX_POSITION_ASSIGNED", { event_id: 30, occurred_at: "2026-11-27T15:00:02Z" });
  const b = row("POKEDEX_POSITION_REMOVED", { event_id: 29, occurred_at: "2026-11-27T15:00:01Z" });
  const c = row("POKEDEX_REPRESENTATIVE_SET", { event_id: 28, occurred_at: "2026-11-27T15:00:01Z" });
  const page = parseCollectionActivityPage([a, b, c])!;
  assert.deepEqual(page.map((e) => e.id), [30, 29, 28]);
  assert.deepEqual(cursorAfter(page), { occurredAt: "2026-11-27T15:00:01Z", id: 28 });
  assert.equal(parseCollectionActivityPage([b, a]), null, "fora de ordem");
  assert.equal(parseCollectionActivityPage([c, b]), null, "mesmo instante: id decrescente");
  assert.equal(parseCollectionActivityPage([a, a]), null, "repetido");
  assert.equal(parseCollectionActivityPage(Array.from({ length: 101 }, () => a)), null);
  assert.equal(parseCollectionActivityPage({}), null);
  assert.ok(COLLECTION_ACTIVITY_PAGE_SIZE >= 1 && COLLECTION_ACTIVITY_PAGE_SIZE <= 100);
});

test("vazio, barreira CLOSED e erros: texto neutro, sem afirmar inexistência nem causa", () => {
  assert.deepEqual(parseCollectionActivityPage([]), []);
  assert.doesNotMatch(collectionActivityEmptyMessage(), /não houve|nunca|nenhuma alteração foi feita/i);
  assert.equal(classifyCollectionActivityFailure("42501", "CAPABILITY_NOT_ENABLED"), "unavailable");
  assert.equal(classifyCollectionActivityFailure("PGRST202", "x"), "unavailable");
  assert.equal(classifyCollectionActivityFailure("28000", "not_authenticated"), "not_authenticated");
  assert.equal(classifyCollectionActivityFailure("22023", "INVALID_PAGE"), "invalid");
  assert.equal(classifyCollectionActivityFailure(null, "fetch failed"), "unknown");
  assert.match(collectionActivityFailureMessage("unknown"), /Tente de novo/);
  assert.doesNotMatch(collectionActivityFailureMessage("unknown"), /nenhuma|não há/i, "falha de leitura não é prova de vazio");
  // Mesma linguagem do painel da Pokédex para sessão expirada.
  assert.match(collectionActivityFailureMessage("not_authenticated"), /^Sua sessão expirou\. Entre de novo/);
  for (const r of ["unavailable", "not_authenticated", "invalid", "unknown"] as const) {
    assert.doesNotMatch(collectionActivityFailureMessage(r), /CAPABILITY|42501|barreira|[0-9a-f]{8}-/i);
  }
});

// Participante removido/pendente/recusado: a 5395 devolve ZERO linhas (sem erro) — a tela trata como vazio neutro.
test("participante sem acesso ACTIVE: zero linhas = lista vazia neutra (nada vazado, nada inferido)", () => {
  assert.deepEqual(parseCollectionActivityPage([]), []);
});

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

test("estático: action e painel usam só a 5395 com a sessão; sem ids nos logs; históricos separados", () => {
  const action = readFileSync(join(WEB, "app/colecoes/collection-activity-actions.ts"), "utf8");
  assert.match(action, /editorCurationFlagOn\(process\.env\)/);
  assert.match(action, /p_before_id: input\.cursor\?\.id \?\? null/);
  assert.doesNotMatch(action, /service_role|SUPABASE_SERVICE|user_profile|auth\.users/);
  assert.doesNotMatch(action, /console\.(log|info|warn|error)\([^;]*(collectionId|events|data|display)/);
  const ui = readFileSync(join(WEB, "components/colecoes/sharing/shared-collection-activity.tsx"), "utf8");
  assert.match(ui, /readCollectionActivity/);
  assert.match(ui, /readSharedActivity/);
  assert.doesNotMatch(ui, /physical_card_id|physicalCardId|copyToken/);
});
