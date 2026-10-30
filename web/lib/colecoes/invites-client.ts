"use client";

import { useSyncExternalStore } from "react";
import { readMyCollectionInvites, respondCollectionInvite } from "@/app/colecoes/compartilhar/actions";
import { type InvitesSnapshot, createInvitesStore } from "./invites-store";
import type { ReceivedInvite, SharingFailure } from "./sharing";

/**
 * Instância única (por aba) do estado de convites — usada pelo Inbox do
 * cabeçalho e pela caixa de Minhas coleções. Vive no módulo, então sobrevive
 * à navegação do cliente (o cabeçalho remonta a cada página; o TTL segura as
 * leituras).
 */
export const invitesStore = createInvitesStore(async () => {
  const result = await readMyCollectionInvites();
  return result.ok ? result.invites : null;
});

const SERVER_SNAPSHOT: InvitesSnapshot = { invites: null, loadedAt: 0, loading: false };

export function useInvites(): InvitesSnapshot {
  return useSyncExternalStore(invitesStore.subscribe, invitesStore.getSnapshot, () => SERVER_SNAPSHOT);
}

/**
 * Aceitar ou recusar pelo contrato existente (5304). Quem chama tira o
 * convite da lista (`invitesStore.remove`) quando `settled` — na hora ou
 * depois da animação de saída; `settled` também cobre o convite que o
 * titular cancelou no meio do caminho (não existe mais para responder).
 */
export async function answerInvite(
  invite: ReceivedInvite,
  accept: boolean,
): Promise<{ ok: true; settled: true } | { ok: false; settled: boolean; reason: SharingFailure }> {
  const result = await respondCollectionInvite({ membershipId: invite.membershipId, accept }).catch(
    () => ({ ok: false, reason: "unknown" }) as const,
  );
  if (result.ok) return { ok: true, settled: true };
  return { ok: false, settled: result.reason === "invite_not_found", reason: result.reason };
}
