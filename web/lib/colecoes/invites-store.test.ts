// Inbox global de convites (V1-12) — estado compartilhado.
// Executar: node --experimental-strip-types --test lib/colecoes/invites-store.test.ts (a partir de web/)

import assert from "node:assert/strict";
import { test } from "node:test";
import { createInvitesStore } from "./invites-store.ts";
import type { ReceivedInvite } from "./sharing.ts";

const invite = (id: string): ReceivedInvite => ({
  membershipId: id,
  collectionId: `c-${id}`,
  collectionName: `Coleção ${id}`,
  completionPolicy: "STANDARD_SET",
  cardSetName: null,
  ownerDisplayName: "Ana",
  ownerUsername: "ana",
  invitedAt: null,
});

test("lê uma vez; dentro do TTL não lê de novo; force lê", async () => {
  let clock = 0;
  let reads = 0;
  const store = createInvitesStore(async () => (reads++, [invite("a")]), { ttlMs: 1000, now: () => clock });
  await store.refresh();
  assert.equal(reads, 1);
  assert.equal(store.getSnapshot().invites?.length, 1);
  clock = 500;
  await store.refresh();
  assert.equal(reads, 1);
  await store.refresh({ force: true });
  assert.equal(reads, 2);
  clock = 2000;
  await store.refresh();
  assert.equal(reads, 3);
});

test("leituras simultâneas viram uma só", async () => {
  let reads = 0;
  const store = createInvitesStore(async () => (reads++, []));
  await Promise.all([store.refresh(), store.refresh(), store.refresh({ force: true })]);
  assert.equal(reads, 1);
});

test("semente evita leitura; falha de leitura preserva a lista", async () => {
  let reads = 0;
  let fail = false;
  const store = createInvitesStore(async () => {
    reads++;
    if (fail) throw new Error("rede");
    return [invite("x")];
  });
  store.seed([invite("a"), invite("b")]);
  await store.refresh();
  assert.equal(reads, 0);
  fail = true;
  await store.refresh({ force: true });
  assert.deepEqual(store.getSnapshot().invites?.map((i) => i.membershipId), ["a", "b"]);
  assert.equal(store.getSnapshot().loading, false);
});

test("convite respondido sai na hora e não volta por leitura em voo", async () => {
  let release: (list: ReceivedInvite[]) => void = () => {};
  const store = createInvitesStore(() => new Promise<ReceivedInvite[]>((resolve) => (release = resolve)));
  store.seed([invite("a"), invite("b")]);
  let notified = 0;
  const unsubscribe = store.subscribe(() => notified++);
  const pending = store.refresh({ force: true });
  store.remove("a");
  assert.deepEqual(store.getSnapshot().invites?.map((i) => i.membershipId), ["b"]);
  release([invite("a"), invite("b")]);
  await pending;
  assert.deepEqual(store.getSnapshot().invites?.map((i) => i.membershipId), ["b"]);
  assert.ok(notified >= 2);
  unsubscribe();
});
