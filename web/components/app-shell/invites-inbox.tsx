"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useId, useRef, useState } from "react";
import { Bell, ChevronRight, Inbox, Library, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { COLECOES_PATH, collectionKindLabel } from "@/lib/colecoes/colecoes";
import { answerInvite, invitesStore, useInvites } from "@/lib/colecoes/invites-client";
import { type ReceivedInvite, invitedAgoLabel, sharedCollectionHref, sharingFailureMessage } from "@/lib/colecoes/sharing";
import { usePrefersReducedMotion } from "@/lib/use-prefers-reduced-motion";
import styles from "./invites-inbox.module.css";

/** Ao abrir, relê se o que está na tela tem mais que isto. */
const OPEN_REFRESH_MS = 5_000;
const CLOSE_MS = 140;
const LEAVE_MS = 220;
const NOTICE_MS = 4_000;

type Notice = { tone: "success" | "warning" | "error"; text: string };

/**
 * Inbox global de convites (V1-12 SHARED EXPERIENCE & GLOBAL INBOX-01), no
 * cabeçalho do app, ao lado do avatar. Só convites de coleção — não é um
 * sistema de notificações.
 *
 * Indicador dourado discreto quando há convite pendente (sem pulsar). Clique
 * abre uma superfície flutuante com os convites: "Aceitar e ver" leva direto à
 * coleção compartilhada; "Recusar" tira o convite com uma saída suave e um
 * aviso curto. Estado vazio dedicado.
 *
 * Leitura: a mesma RPC da caixa de Minhas coleções (5309), via estado
 * compartilhado (`invitesStore`) — ao montar (adiado um tique para a página
 * poder semear o estado já lido no servidor), ao abrir e ao recuperar o foco
 * da aba, sempre com TTL. Nada de polling, nada no caminho crítico do
 * cabeçalho (Server Component): a página não espera o Inbox.
 *
 * Acessível: botão com `aria-expanded`/`aria-controls`, painel `role="dialog"`
 * não modal, Esc fecha e devolve o foco, clique fora fecha, foco que sai do
 * Inbox fecha. Movimento só com opacidade/transform; nenhum com
 * prefers-reduced-motion. No celular, o painel ocupa a largura da tela.
 */
export function InvitesInbox() {
  const router = useRouter();
  const pathname = usePathname();
  const reducedMotion = usePrefersReducedMotion();
  const { invites, loadedAt, loading } = useInvites();
  const [open, setOpen] = useState(false);
  const [closing, setClosing] = useState(false);
  const [busy, setBusy] = useState<{ id: string; accept: boolean } | null>(null);
  const [leaving, setLeaving] = useState<Set<string>>(() => new Set());
  const [notice, setNotice] = useState<Notice | null>(null);
  const rootRef = useRef<HTMLDivElement>(null);
  const buttonRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const panelId = useId();
  const titleId = useId();

  const count = invites?.length ?? 0;

  // Leituras: ao montar/navegar e ao recuperar o foco da aba (TTL decide).
  useEffect(() => {
    const timer = window.setTimeout(() => void invitesStore.refresh(), 0);
    return () => window.clearTimeout(timer);
  }, [pathname]);
  useEffect(() => {
    const onFocus = () => {
      if (document.visibilityState === "visible") void invitesStore.refresh();
    };
    window.addEventListener("focus", onFocus);
    document.addEventListener("visibilitychange", onFocus);
    return () => {
      window.removeEventListener("focus", onFocus);
      document.removeEventListener("visibilitychange", onFocus);
    };
  }, []);

  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => setNotice(null), NOTICE_MS);
    return () => window.clearTimeout(timer);
  }, [notice]);

  const close = useCallback(
    (returnFocus: boolean) => {
      if (!open || closing) return;
      const finish = () => {
        setOpen(false);
        setClosing(false);
        if (returnFocus) buttonRef.current?.focus();
      };
      if (reducedMotion) return finish();
      setClosing(true);
      window.setTimeout(finish, CLOSE_MS);
    },
    [open, closing, reducedMotion],
  );

  const toggle = () => {
    if (open) return close(false);
    setNotice(null);
    setOpen(true);
    void invitesStore.refresh({ force: Date.now() - loadedAt > OPEN_REFRESH_MS });
  };

  // Foco no painel ao abrir; Esc, clique fora e foco fora fecham.
  useEffect(() => {
    if (!open || closing) return;
    panelRef.current?.focus({ preventScroll: true });
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        close(true);
      }
    };
    const onPointer = (event: PointerEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) close(false);
    };
    const onFocusIn = (event: FocusEvent) => {
      if (!rootRef.current?.contains(event.target as Node)) close(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("focusin", onFocusIn);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("focusin", onFocusIn);
    };
  }, [open, closing, close]);

  const respond = async (invite: ReceivedInvite, accept: boolean) => {
    setBusy({ id: invite.membershipId, accept });
    setNotice(null);
    const result = await answerInvite(invite, accept);
    setBusy(null);
    if (!result.ok) {
      if (result.settled) invitesStore.remove(invite.membershipId);
      setNotice({ tone: result.settled ? "warning" : "error", text: sharingFailureMessage(result.reason) });
      return;
    }
    if (accept) {
      invitesStore.remove(invite.membershipId);
      setOpen(false);
      router.push(sharedCollectionHref(invite.collectionId));
      return;
    }
    setNotice({ tone: "success", text: `Convite de ${invite.ownerDisplayName} recusado. Nada foi compartilhado com você.` });
    if (reducedMotion) {
      invitesStore.remove(invite.membershipId);
      return;
    }
    setLeaving((prev) => new Set(prev).add(invite.membershipId));
    window.setTimeout(() => {
      invitesStore.remove(invite.membershipId);
      setLeaving((prev) => {
        const next = new Set(prev);
        next.delete(invite.membershipId);
        return next;
      });
    }, LEAVE_MS);
  };

  const buttonLabel = count > 0 ? `Convites: ${count} ${count === 1 ? "pendente" : "pendentes"}` : "Convites";

  return (
    <div ref={rootRef} className={styles.root}>
      <button
        ref={buttonRef}
        type="button"
        className={styles.trigger}
        data-open={open || undefined}
        aria-label={buttonLabel}
        title="Convites"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? panelId : undefined}
        onClick={toggle}
      >
        <Bell className="h-4 w-4" aria-hidden="true" />
        {count > 0 ? <span className={styles.dot} aria-hidden="true" /> : null}
      </button>

      {open ? (
        <div
          ref={panelRef}
          id={panelId}
          role="dialog"
          aria-labelledby={titleId}
          tabIndex={-1}
          className={styles.panel}
          data-closing={closing || undefined}
        >
          <header className={styles.head}>
            <h2 id={titleId} className={styles.title}>
              Convites
            </h2>
            {count > 0 ? <span className={styles.count}>{count}</span> : null}
            {loading && invites !== null ? <Loader2 className={styles.syncing} aria-label="Atualizando" /> : null}
          </header>

          <div className={styles.live} role="status" aria-live="polite">
            {notice ? (
              <p className={styles.notice} data-tone={notice.tone}>
                {notice.text}
              </p>
            ) : null}
          </div>

          {invites === null ? (
            loading ? (
              <ul className={styles.list} aria-busy="true" aria-label="Carregando convites">
                {[0, 1].map((row) => (
                  <li key={row} className={styles.skeleton}>
                    <span />
                    <span />
                  </li>
                ))}
              </ul>
            ) : (
              <div className={styles.empty}>
                <p className={styles.emptyTitle}>Não conseguimos ver seus convites agora</p>
                <p className={styles.emptyText}>Nada foi perdido. Tente de novo em instantes.</p>
                <Button variant="outline" size="sm" className="mt-3" onClick={() => void invitesStore.refresh({ force: true })}>
                  Tentar de novo
                </Button>
              </div>
            )
          ) : invites.length === 0 ? (
            <div className={styles.empty}>
              <span className={styles.emptyMark} aria-hidden="true">
                <Inbox />
              </span>
              <p className={styles.emptyTitle}>Tudo em dia</p>
              <p className={styles.emptyText}>Quando alguém compartilhar uma coleção com você, o convite aparece aqui.</p>
            </div>
          ) : (
            <ul className={styles.list} aria-label="Convites para você">
              {invites.map((invite) => {
                const working = busy?.id === invite.membershipId;
                const ago = invitedAgoLabel(invite.invitedAt);
                const kind = invite.cardSetName ?? collectionKindLabel(invite.completionPolicy);
                return (
                  <li key={invite.membershipId} className={styles.item} data-leaving={leaving.has(invite.membershipId) || undefined}>
                    <div className={styles.itemInner}>
                      <span className={styles.mark} aria-hidden="true">
                        <Library />
                      </span>
                      <div className={styles.body}>
                        <p className={styles.name}>{invite.collectionName}</p>
                        <p className={styles.meta}>
                          <strong>{invite.ownerDisplayName}</strong>
                          {invite.ownerUsername ? ` @${invite.ownerUsername}` : ""} · {kind}
                          {ago ? ` · ${ago}` : ""}
                        </p>
                        <div className={styles.actions}>
                          <Button size="sm" disabled={busy !== null} onClick={() => void respond(invite, true)} aria-busy={(working && busy?.accept) || undefined}>
                            {working && busy?.accept ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" aria-hidden="true" /> : null}
                            Aceitar e ver
                          </Button>
                          <Button variant="ghost" size="sm" disabled={busy !== null} onClick={() => void respond(invite, false)} aria-busy={(working && !busy?.accept) || undefined}>
                            {working && !busy?.accept ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" aria-hidden="true" /> : null}
                            Recusar
                          </Button>
                        </div>
                      </div>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}

          <footer className={styles.foot}>
            <Link href={COLECOES_PATH} className={styles.footLink} onClick={() => setOpen(false)}>
              Coleções compartilhadas com você
              <ChevronRight aria-hidden="true" />
            </Link>
          </footer>
        </div>
      ) : null}
    </div>
  );
}
