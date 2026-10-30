"use server";

import { revalidatePath } from "next/cache";
import { COLECOES_PATH, collectionHref, isCollectionId } from "@/lib/colecoes/colecoes";
import {
  type InviteOutcome,
  type ReceivedInvite,
  type SharedBinderPage,
  type ShareMember,
  type SharingFailure,
  type SharingState,
  type Visibility,
  SHARED_BINDER_PAGES_PER_READ,
  SHARED_COLLECTION_PATH,
  attachSharedBinderImages,
  classifySharingFailure,
  publicBinderHref,
  normalizeUsername,
  parseInvite,
  parseInvites,
  parseSharedBinderPages,
  parseSharing,
} from "@/lib/colecoes/sharing";
import { readSharedBinderImages } from "@/lib/colecoes/sharing-queries";
import { createClient } from "@/lib/supabase/server";

/**
 * Compartilhamento de coleções (V1-12) — server actions finas sobre 5303–5309
 * (proposta). Toda autorização é do banco: estas funções só validam formato,
 * chamam a RPC com a sessão do usuário e traduzem o resultado. Nenhuma usa
 * service role. Sem as funções no banco, tudo devolve `unavailable`.
 */

type Fail = { ok: false; reason: SharingFailure };

function fail(fn: string, startedAt: number, error: { code?: string; message?: string } | null): Fail {
  const reason = classifySharingFailure(error?.code, error?.message);
  console.error(JSON.stringify({ scope: "colecoes.sharing", fn, ms: Date.now() - startedAt, code: error?.code ?? "BAD_SHAPE", reason }));
  return { ok: false, reason };
}

function revalidateCollection(collectionId: string) {
  revalidatePath(collectionHref(collectionId));
  revalidatePath(`${SHARED_COLLECTION_PATH}/${collectionId}`);
  // Vitrine pública: já é renderizada por requisição (cookies() → dinâmica);
  // invalidar aqui só garante que nenhum cache do roteador sobreviva à troca
  // de visibilidade ou à remoção de um participante.
  revalidatePath(publicBinderHref(collectionId));
}

/** Painel "Compartilhar" do titular (5308). */
export async function readCollectionSharing(input: { collectionId: string }): Promise<{ ok: true; state: SharingState } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_collection_sharing", { p_collection_id: input.collectionId });
  if (error) return fail("get_my_collection_sharing", startedAt, error);
  const state = parseSharing(data);
  if (!state) return { ok: false, reason: "not_found" };
  return { ok: true, state };
}

/** Convidar pelo nome de usuário exato (5303). */
export async function inviteCollectionMember(input: {
  collectionId: string;
  username: string;
}): Promise<{ ok: true; outcome: InviteOutcome; member: ShareMember } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const username = typeof input.username === "string" ? normalizeUsername(input.username) : null;
  if (!username) return { ok: false, reason: "invalid_username" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("invite_collection_member", { p_collection_id: input.collectionId, p_username: username });
  if (error) return fail("invite_collection_member", startedAt, error);
  const parsed = parseInvite(data);
  if (!parsed) return fail("invite_collection_member", startedAt, null);
  return { ok: true, ...parsed };
}

/** Cancelar convite, remover participante ou limpar recusa (5305). */
export async function removeCollectionMember(input: { collectionId: string; membershipId: string }): Promise<{ ok: true } | Fail> {
  if (!isCollectionId(input?.collectionId) || !isCollectionId(input.membershipId)) return { ok: false, reason: "not_found" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { error } = await supabase.rpc("remove_collection_member", {
    p_collection_id: input.collectionId,
    p_membership_id: input.membershipId,
  });
  if (error) return fail("remove_collection_member", startedAt, error);
  revalidateCollection(input.collectionId);
  return { ok: true };
}

/** Tornar pública ou privada — sempre por escolha explícita (5307). */
export async function setCollectionVisibility(input: {
  collectionId: string;
  visibility: Visibility;
}): Promise<{ ok: true; visibility: Visibility } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  if (input.visibility !== "PUBLIC" && input.visibility !== "PRIVATE") return { ok: false, reason: "unknown" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_collection_visibility", {
    p_collection_id: input.collectionId,
    p_visibility: input.visibility,
  });
  if (error) return fail("set_collection_visibility", startedAt, error);
  const visibility = (data as Record<string, unknown> | null)?.visibility;
  if (visibility !== "PUBLIC" && visibility !== "PRIVATE") return fail("set_collection_visibility", startedAt, null);
  revalidateCollection(input.collectionId);
  return { ok: true, visibility };
}

/**
 * Convites esperando resposta do usuário da sessão (5309) — leitura do Inbox
 * global do cabeçalho. Só lê; o banco decide (só os convites do próprio
 * auth.uid(), no máximo 50). Falha devolve `ok: false` para o Inbox manter o
 * que já mostrava, em vez de "sumir" com os convites por um erro de rede.
 */
export async function readMyCollectionInvites(): Promise<{ ok: true; invites: ReceivedInvite[] } | { ok: false }> {
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_my_collection_invites");
  if (error) {
    fail("get_my_collection_invites", startedAt, error);
    return { ok: false };
  }
  return { ok: true, invites: parseInvites(data) };
}

/** Aceitar ou recusar um convite recebido (5304). */
export async function respondCollectionInvite(input: {
  membershipId: string;
  accept: boolean;
}): Promise<{ ok: true; outcome: "ACTIVE" | "DECLINED" | "UNCHANGED"; collectionId: string | null } | Fail> {
  if (!isCollectionId(input?.membershipId) || typeof input.accept !== "boolean") return { ok: false, reason: "invite_not_found" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("respond_collection_invite", { p_membership_id: input.membershipId, p_accept: input.accept });
  if (error) return fail("respond_collection_invite", startedAt, error);
  const r = (data ?? {}) as Record<string, unknown>;
  const outcome = r.outcome;
  if (outcome !== "ACTIVE" && outcome !== "DECLINED" && outcome !== "UNCHANGED") return fail("respond_collection_invite", startedAt, null);
  revalidatePath(COLECOES_PATH);
  return { ok: true, outcome, collectionId: isCollectionId(r.collection_id) ? String(r.collection_id) : null };
}

/** Sair de uma coleção compartilhada (5306). */
export async function leaveSharedCollection(input: { collectionId: string }): Promise<{ ok: true } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_member" };
  const startedAt = Date.now();
  const supabase = await createClient();
  const { error } = await supabase.rpc("leave_shared_collection", { p_collection_id: input.collectionId });
  if (error) return fail("leave_shared_collection", startedAt, error);
  revalidatePath(COLECOES_PATH);
  revalidatePath(`${SHARED_COLLECTION_PATH}/${input.collectionId}`);
  return { ok: true };
}

/**
 * Páginas do fichário compartilhado (5315) — só leitura, já mascaradas pelo
 * banco para a coleção autorizada. A grade vem do cabeçalho lido no servidor
 * (5314) e serve só para validar o formato da resposta.
 */
export async function readSharedBinderPages(input: {
  collectionId: string;
  firstPage: number;
  columns: number;
  rows: number;
}): Promise<{ ok: true; pages: SharedBinderPage[] } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const { firstPage, columns, rows } = input;
  if (![firstPage, columns, rows].every((n) => Number.isInteger(n)) || firstPage < 1 || firstPage > 100000 || columns < 1 || columns > 10 || rows < 1 || rows > 10) {
    return { ok: false, reason: "not_found" };
  }
  return readBinderPagesVia("get_shared_collection_binder_pages", input.collectionId, firstPage, columns, rows);
}

/**
 * Páginas da vitrine pública (5318) — sem sessão. A autorização é só a
 * visibilidade PUBLIC da coleção, decidida no banco a cada chamada.
 */
export async function readPublicBinderPages(input: {
  collectionId: string;
  firstPage: number;
  columns: number;
  rows: number;
}): Promise<{ ok: true; pages: SharedBinderPage[] } | Fail> {
  if (!isCollectionId(input?.collectionId)) return { ok: false, reason: "not_found" };
  const { firstPage, columns, rows } = input;
  if (![firstPage, columns, rows].every((n) => Number.isInteger(n)) || firstPage < 1 || firstPage > 100000 || columns < 1 || columns > 10 || rows < 1 || rows > 10) {
    return { ok: false, reason: "not_found" };
  }
  return readBinderPagesVia("get_public_collection_binder_pages", input.collectionId, firstPage, columns, rows);
}

async function readBinderPagesVia(
  fn: "get_shared_collection_binder_pages" | "get_public_collection_binder_pages",
  collectionId: string,
  firstPage: number,
  columns: number,
  rows: number,
): Promise<{ ok: true; pages: SharedBinderPage[] } | Fail> {
  const startedAt = Date.now();
  const supabase = await createClient();
  // Imagens decorativas (5326/5327) em paralelo, mesma sessão; falha nelas nunca derruba o lote.
  const [{ data, error }, images] = await Promise.all([
    supabase.rpc(fn, {
      p_collection_id: collectionId,
      p_first_page: firstPage,
      p_page_count: SHARED_BINDER_PAGES_PER_READ,
    }),
    readSharedBinderImages(supabase, fn === "get_public_collection_binder_pages" ? "public" : "shared", collectionId, firstPage),
  ]);
  if (error) return fail(fn, startedAt, error);
  const pages = parseSharedBinderPages(data, columns, rows);
  if (!pages) return fail(fn, startedAt, null);
  return { ok: true, pages: attachSharedBinderImages(pages, images) };
}
