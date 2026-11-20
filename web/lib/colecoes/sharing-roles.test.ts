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

// ---------------------------------------------------------------------------
// V1-13 · E3-2 — convite com papel e troca de papel (5369/5370). Respostas simuladas.

import { readFileSync } from "node:fs";
import {
  classifySharingFailure,
  inviteOutcomeMessage,
  parseRoleChange,
  roleChangeMessage,
  roleChangeNeedsConfirmation,
  sharingFailureMessage,
} from "./sharing.ts";

test("E3-2: recusas da 5369/5370 → motivo estável e mensagem neutra", () => {
  assert.equal(classifySharingFailure("42501", "CAPABILITY_NOT_ENABLED"), "capability_closed", "barreira fechada antes do 42501 genérico");
  assert.equal(classifySharingFailure("42501", "permission denied"), "unavailable");
  assert.equal(classifySharingFailure("22023", "INVALID_ROLE"), "invalid_role");
  assert.equal(classifySharingFailure("55000", "INVITE_PENDING_ROLE_IMMUTABLE"), "pending_role_immutable");
  assert.equal(classifySharingFailure("55000", "MEMBER_NOT_ACTIVE"), "member_not_active");
  assert.equal(classifySharingFailure("P0002", "MEMBERSHIP_NOT_FOUND"), "not_found", "participação alheia, inexistente ou sem titularidade: indistinguíveis");
  assert.equal(classifySharingFailure("40001", "INVITE_STATE_CHANGED"), "state_changed");
  assert.equal(classifySharingFailure("40001", "OTHER"), "unknown", "40001 de outras funções não vira 'lista mudou'");
  for (const r of ["capability_closed", "invalid_role", "pending_role_immutable", "member_not_active", "state_changed", "uncertain", "not_found"] as const) {
    const text = sharingFailureMessage(r);
    assert.ok(text.length > 0 && !/[A-Z]{3,}_[A-Z]/.test(text) && !/@|uuid|id /i.test(text), `${r}: ${text}`);
  }
  assert.match(sharingFailureMessage("pending_role_immutable"), /cancele o convite e convide de novo/);
  assert.match(sharingFailureMessage("uncertain"), /confira antes de tentar de novo/);
});

test("E3-2: troca de papel — CHANGED/UNCHANGED; confirmação só no rebaixamento", () => {
  assert.deepEqual(parseRoleChange({ outcome: "CHANGED", role: "EDITOR", previous_role: "VIEWER", membership_id: M }), { outcome: "CHANGED", role: "EDITOR" });
  assert.deepEqual(parseRoleChange({ outcome: "UNCHANGED", role: "VIEWER" }), { outcome: "UNCHANGED", role: "VIEWER" });
  assert.equal(parseRoleChange({ outcome: "CHANGED", role: "OWNER" }), null);
  assert.equal(parseRoleChange({ outcome: "OK", role: "EDITOR" }), null);
  assert.equal(parseRoleChange(null), null);
  assert.equal(roleChangeNeedsConfirmation("EDITOR", "VIEWER"), true, "rebaixar confirma (D-E3-5)");
  assert.equal(roleChangeNeedsConfirmation("VIEWER", "EDITOR"), false, "promover não confirma");
  assert.match(roleChangeMessage({ outcome: "CHANGED", role: "EDITOR" }, "Ana"), /Ana agora pode organizar/);
  assert.match(roleChangeMessage({ outcome: "CHANGED", role: "VIEWER" }, "Ana"), /só pode ver.*vale na hora/);
  assert.match(roleChangeMessage({ outcome: "UNCHANGED", role: "EDITOR" }, "Ana"), /já estava como “Pode organizar”/);
});

test("E3-2: mensagens do convite — 'Pode ver' igual ao de sempre; 'Pode organizar' com texto próprio", () => {
  const who = { displayName: "Ana", username: "ana" };
  assert.equal(inviteOutcomeMessage("INVITED", who), "Convite enviado para Ana (@ana). Assim que aceitar, a coleção aparece para essa pessoa.");
  assert.equal(inviteOutcomeMessage("INVITED", { ...who, role: "VIEWER" }), inviteOutcomeMessage("INVITED", who));
  assert.match(inviteOutcomeMessage("INVITED", { ...who, role: "EDITOR" }), /para organizar/);
  assert.match(inviteOutcomeMessage("ALREADY_PENDING", { ...who, role: "EDITOR" }), /para organizar esperando resposta/);
  assert.equal(parseInvite({ outcome: "INVITED", membership_id: M, username: "ana", role: "EDITOR" })?.member.role, "EDITOR");
});

test("E3-2: ações — 'Pode ver' com a chamada de sempre; 'Pode organizar' só com a configuração; uma chamada; sem hint", () => {
  const src = readFileSync(new URL("../../app/colecoes/compartilhar/actions.ts", import.meta.url), "utf8");
  const invite = src.slice(src.indexOf("export async function inviteCollectionMember"), src.indexOf("export async function setCollectionMemberRole"));
  assert.ok(invite.includes('role === "EDITOR" && !editorRolesOn()') && invite.includes('return { ok: false, reason: "capability_closed" }'), "EDITOR sem a configuração nem chama o banco");
  assert.ok(invite.includes("{ p_collection_id: input.collectionId, p_username: username }"), "VIEWER: mesmos parâmetros de antes (padrão do banco)");
  assert.ok(invite.includes('p_role: "EDITOR"'));
  const change = src.slice(src.indexOf("export async function setCollectionMemberRole"), src.indexOf("/** Cancelar convite"));
  assert.ok(change.includes("if (!editorRolesOn()) return { ok: false, reason: \"capability_closed\" }"));
  assert.equal((change.match(/supabase\.rpc\(/g) ?? []).length, 1, "uma chamada");
  assert.ok(!/\.hint|\.details/.test(invite + change), "hint/details nunca lidos");
  const panel = readFileSync(new URL("../../components/colecoes/sharing/share-panel.tsx", import.meta.url), "utf8");
  const changeRole = panel.slice(panel.indexOf("const changeRole = async"), panel.indexOf("const remove = async"));
  const submit = panel.slice(panel.indexOf("const submit = async"), panel.indexOf("return (", panel.indexOf("const submit = async")));
  for (const block of [changeRole, submit]) {
    assert.ok(block.length > 0 && !/setTimeout\(|retry|while\s*\(|for\s*\(/i.test(block.replace(/\/\/.*$/gm, "")), "sem repetição automática");
  }
  assert.equal((changeRole.match(/setCollectionMemberRole\(/g) ?? []).length, 1, "uma escrita por troca");
});

test("E3-2 (V1): 'Convidar de novo' — papel recusado só é reaproveitado com a configuração; sem desvio nem repetição", () => {
  const panel = readFileSync(new URL("../../components/colecoes/sharing/share-panel.tsx", import.meta.url), "utf8");
  const reinvite = panel.slice(panel.indexOf("const reinvite = async"), panel.indexOf("const count = state.members"));
  // 1 e 2: desligada → sempre a chamada de sempre, sem papel (VIEWER pelo padrão do banco), qualquer que tenha sido o papel recusado.
  assert.ok(reinvite.includes('editorRoles && member.role === "EDITOR" ? { collectionId, username: member.username, role: "EDITOR" as const } : { collectionId, username: member.username }'));
  // 3: ligada + papel EDITOR → envia EDITOR; o servidor ainda decide (ação exige a configuração; banco exige a barreira).
  const actions = readFileSync(new URL("../../app/colecoes/compartilhar/actions.ts", import.meta.url), "utf8");
  assert.ok(actions.includes('if (role === "EDITOR" && !editorRolesOn()) return { ok: false, reason: "capability_closed" };'), "chamar a ação direto com EDITOR, desligada, não chega ao banco");
  // 4: uma chamada, sem laço nem temporizador.
  const code = reinvite.replace(/\/\/.*$/gm, "");
  assert.equal((code.match(/inviteCollectionMember\(/g) ?? []).length, 1);
  assert.ok(!/setTimeout\(|retry|while\s*\(|for\s*\(/i.test(code));
  assert.ok(code.includes('editorRoles ? "uncertain" : "unknown"'));
  assert.match(sharingFailureMessage("uncertain"), /A lista foi atualizada/);
});
