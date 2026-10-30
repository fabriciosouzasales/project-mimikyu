"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Loader2, Mail } from "lucide-react";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { collectionKindLabel } from "@/lib/colecoes/colecoes";
import { answerInvite, invitesStore, useInvites } from "@/lib/colecoes/invites-client";
import { type ReceivedInvite, sharedCollectionHref, sharingFailureMessage } from "@/lib/colecoes/sharing";
import styles from "./share.module.css";

/**
 * Caixa de convites (V1-12), no topo de Minhas coleções — o lugar onde o
 * colecionador já está. Sem notificação externa (C-153). Some por completo
 * quando não há convite. As coleções já aceitas não aparecem aqui: entram na
 * própria Biblioteca, como qualquer coleção, com selo "Compartilhada".
 *
 * Aceitar leva direto à coleção; recusar tira o convite da caixa na hora. O
 * resultado vem do banco (5304): convite cancelado no meio do caminho vira um
 * aviso, não um erro técnico.
 */
export function SharingInbox({ invites }: { invites: ReceivedInvite[] }) {
  const router = useRouter();
  // Mesmo estado do Inbox do cabeçalho (V1-12 GLOBAL INBOX-01): a leitura do
  // servidor semeia o estado; responder aqui ou lá tira o convite dos dois.
  const live = useInvites().invites;
  const list = live ?? invites;
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ tone: "success" | "error" | "warning"; text: string } | null>(null);

  useEffect(() => {
    invitesStore.seed(invites);
  }, [invites]);

  if (list.length === 0 && !notice) return null;

  const respond = async (invite: ReceivedInvite, accept: boolean) => {
    setBusy(invite.membershipId);
    setNotice(null);
    const result = await answerInvite(invite, accept);
    setBusy(null);
    if (result.settled) invitesStore.remove(invite.membershipId);
    if (!result.ok) {
      setNotice({ tone: result.settled ? "warning" : "error", text: sharingFailureMessage(result.reason) });
      return;
    }
    if (accept) {
      router.push(sharedCollectionHref(invite.collectionId));
      return;
    }
    setNotice({ tone: "success", text: `Convite de ${invite.ownerDisplayName} recusado. Nada foi compartilhado com você.` });
    router.refresh();
  };

  return (
    <div className={styles.inbox}>
      <div className={styles.live} role="status" aria-live="polite">
        {notice ? <InlineFeedback tone={notice.tone}>{notice.text}</InlineFeedback> : null}
      </div>

      {list.length > 0 ? (
        <section aria-labelledby="convites-recebidos" className="flex flex-col gap-3">
          <h2 id="convites-recebidos" className={styles.inboxTitle}>
            Convites para você
            <span className={styles.inboxCount} aria-label={`${list.length} convites`}>
              {list.length}
            </span>
          </h2>
          <ul className={styles.inviteList}>
            {list.map((invite) => {
              const working = busy === invite.membershipId;
              const kind = invite.cardSetName ?? collectionKindLabel(invite.completionPolicy);
              return (
                <li key={invite.membershipId} className={styles.invite}>
                  <div className={styles.inviteHead}>
                    <span className={styles.inviteIcon} aria-hidden="true">
                      <Mail className="h-4 w-4" />
                    </span>
                    <p className={styles.inviteText}>
                      <strong>{invite.collectionName}</strong>
                      {invite.ownerDisplayName}
                      {invite.ownerUsername ? ` (@${invite.ownerUsername})` : ""} quer mostrar esta coleção para você · {kind}
                    </p>
                  </div>
                  <p className={styles.help}>Ao aceitar, você vê as cartas e o progresso. Nada do seu acervo é compartilhado.</p>
                  <div className={styles.inviteActions}>
                    <Button size="sm" disabled={busy !== null} onClick={() => void respond(invite, true)} aria-busy={working || undefined}>
                      {working ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" aria-hidden="true" /> : null}
                      Aceitar e ver
                    </Button>
                    <Button variant="ghost" size="sm" disabled={busy !== null} onClick={() => void respond(invite, false)}>
                      Recusar
                    </Button>
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
