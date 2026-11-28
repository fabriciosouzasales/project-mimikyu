// V1-13 · D-E3-2 (5398): autoria no histórico do fichário do titular.
// Executar: node --experimental-strip-types --test lib/colecoes/d-e3-2-owner-history-author.test.ts (a partir de web/)
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { attributionByline, parseActivityActors, withActors, type ActivityEvent } from "./binder-activity.ts";

const WEB = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const ev = (id: number): ActivityEvent => ({ id, occurredAt: "2026-11-27T20:00:00Z", type: "CARD_MOVED", category: "CARDS", source: "FICHARIO", legacy: false, collectionName: null, binderName: null, summary: {}, itemCount: 0, items: [], truncated: false });

test("parse: papéis e nomes válidos; formato inválido descarta tudo", () => {
  const m = parseActivityActors([
    { event_id: 10, actor_role: "PARTICIPANT", actor_display_name: "Kauã Sales" },
    { event_id: "11", actor_role: "OWNER", actor_display_name: "Fabrício Sales" },
    { event_id: 12, actor_role: null, actor_display_name: null },
  ])!;
  assert.deepEqual(m.get(10), { role: "PARTICIPANT", displayName: "Kauã Sales" });
  assert.deepEqual(m.get(11), { role: "OWNER", displayName: "Fabrício Sales" });
  assert.deepEqual(m.get(12), { role: null, displayName: null });
  assert.equal(parseActivityActors([{ event_id: 1, actor_role: "ADMIN", actor_display_name: "x" }]), null);
  assert.equal(parseActivityActors([{ event_id: -1, actor_role: "OWNER", actor_display_name: "x" }]), null);
  assert.equal(parseActivityActors({}), null);
  assert.deepEqual(parseActivityActors(null), new Map());
});

test("junção: evento com linha ganha autor; sem linha continua sem autor (barreira fechada = tela de sempre)", () => {
  const actors = parseActivityActors([{ event_id: 2, actor_role: "PARTICIPANT", actor_display_name: "Ravi Sales" }]);
  const [a, b] = withActors([ev(1), ev(2)], actors) as [ActivityEvent, ActivityEvent];
  assert.equal(a.attribution, undefined);
  assert.equal(attributionByline(a), null);
  assert.equal(attributionByline(b), "por Ravi Sales");
  assert.deepEqual(withActors([ev(1)], new Map()), [ev(1)]);
  assert.deepEqual(withActors([ev(1)], null), [ev(1)]);
});

test("servidor: lê a 5398 só com a configuração D1 e só com os ids da página; falha não derruba o histórico", () => {
  const act = readFileSync(join(WEB, "app/colecoes/colecoes/[id]/fichario/actions.ts"), "utf8");
  assert.match(act, /rpc\("get_my_binder_activity_actors", \{ p_layout_key: input\.layoutId, p_event_ids: events\.map\(\(e\) => e\.id\) \}\)/);
  assert.match(act, /editorCurationFlagOn\(process\.env\) && events\.length > 0/);
  assert.match(act, /withActors\(events, actors\.error \? null : parseActivityActors\(actors\.data\)\)/);
});
