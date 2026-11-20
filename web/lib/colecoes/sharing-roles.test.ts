// V1-13 · E3-1 — papéis de colaboração na interface: leitura e linguagem.
// Executar: node --experimental-strip-types --test lib/colecoes/sharing-roles.test.ts (a partir de web/)
// Testes LOCAIS com respostas simuladas. Mostrar o papel não autoriza nada; as leituras reais
// (5308/5309/5311/5312) e a autorização são do servidor.

import assert from "node:assert/strict";
import { test } from "node:test";
import {
  ROLE_AVAILABILITY_NOTE,
  ROLE_LABEL,
  inviteRoleCopy,
  memberRole,
  parseInvite,
  parseInvites,
  parseSharedCollection,
  parseSharedWithMe,
  parseSharing,
  roleExplanation,
} from "./sharing.ts";

const C = "11111111-1111-4111-8111-111111111111";
const M = "22222222-2222-4222-8222-222222222222";

test("papel vem da leitura; qualquer coisa além de EDITOR vale como o de menor alcance", () => {
  assert.equal(memberRole("EDITOR"), "EDITOR");
  for (const v of ["VIEWER", "OWNER", "editor", null, undefined, 1]) assert.equal(memberRole(v), "VIEWER", String(v));
});

test("5308 (titular), 5309 (convite), 5311 (compartilhadas) e 5312 (cabeçalho) trazem o papel", () => {
  const sharing = parseSharing({ visibility: "PRIVATE", members: [{ membership_id: M, username: "ana", status: "ACTIVE", role: "EDITOR" }] });
  assert.equal(sharing?.members[0]?.role, "EDITOR");
  assert.equal(parseInvites([{ membership_id: M, collection_id: C, collection_name: "Base", role: "EDITOR" }])[0]?.role, "EDITOR");
  assert.equal(parseInvites([{ membership_id: M, collection_id: C, collection_name: "Base" }])[0]?.role, "VIEWER");
  assert.equal(parseSharedWithMe([{ collection_id: C, name: "Base", role: "EDITOR" }])[0]?.role, "EDITOR");
  assert.equal(parseSharedCollection({ collection_id: C, name: "Base", visibility: "PRIVATE", access: "VIEWER", role: "EDITOR" })?.role, "EDITOR");
  assert.equal(parseInvite({ outcome: "INVITED", membership_id: M, username: "ana" })?.member.role, "VIEWER", "convite desta rodada: só VIEWER");
});

test("linguagem: Titular / Pode organizar / Pode ver", () => {
  assert.deepEqual(ROLE_LABEL, { OWNER: "Titular", EDITOR: "Pode organizar", VIEWER: "Pode ver" });
});

test("explicações: o que cada papel permite e o que fica com o titular", () => {
  const viewer = roleExplanation("VIEWER");
  assert.ok(viewer.can.some((l) => /Ver a coleção/.test(l)) && viewer.can.some((l) => /fichário/.test(l)));
  assert.ok(viewer.cannot.some((l) => /Alterar/.test(l)));
  const editor = roleExplanation("EDITOR");
  assert.ok(editor.can.some((l) => /Organizar o fichário/.test(l)) && editor.can.some((l) => /nome, a descrição e a capa/.test(l)));
  const cannot = editor.cannot.join(" ");
  for (const word of ["pertencem", "guardadas", "condição", "visibilidade", "participantes", "administração"]) assert.ok(cannot.includes(word), word);
  assert.ok(/administrativo e patrimonial/.test(roleExplanation("OWNER").can.join(" ")));
  // Papel ≠ disponibilidade: nenhuma explicação promete que a ferramenta já está ligada.
  assert.match(ROLE_AVAILABILITY_NOTE, /ainda não estão disponíveis/);
  for (const r of ["VIEWER", "EDITOR", "OWNER"] as const) {
    const all = [...roleExplanation(r).can, ...roleExplanation(r).cannot].join(" ");
    assert.ok(!/já está|disponível agora|liberad/i.test(all), r);
  }
});

test("convite recebido: textos por papel oferecido", () => {
  assert.match(inviteRoleCopy("EDITOR").offer, /organizar/);
  assert.equal(inviteRoleCopy("EDITOR").accept, "Aceitar");
  assert.match(inviteRoleCopy("VIEWER").offer, /mostrar/);
  assert.equal(inviteRoleCopy("VIEWER").accept, "Aceitar e ver");
  for (const r of ["EDITOR", "VIEWER"] as const) assert.match(inviteRoleCopy(r).help, /nada do seu acervo é compartilhado/i);
});
