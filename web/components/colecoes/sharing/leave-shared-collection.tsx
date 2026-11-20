"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState } from "react";
import { ChevronDown, Eye, Loader2, LogOut, Pencil } from "lucide-react";
import { leaveSharedCollection } from "@/app/colecoes/compartilhar/actions";
import { Button } from "@/components/ui/button";
import { COLECOES_PATH } from "@/lib/colecoes/colecoes";
import { type MemberRole, ROLE_AVAILABILITY_NOTE, ROLE_LABEL, roleExplanation, sharingFailureMessage } from "@/lib/colecoes/sharing";
import styles from "./share.module.css";

/**
 * Selo de acesso da coleção compartilhada com um menu discreto (V1-12 VIEWER
 * EXPERIENCE PARITY CORRECTION-02). O selo continua dizendo "Compartilhada
 * com você · somente visualização"; aberto, o painel identifica o titular,
 * explica o que a visualização permite e oferece "Sair desta coleção" —
 * ação secundária, fora da área principal, que nunca compete com "Abrir o
 * fichário".
 *
 * Sair (C-154/C-155, 5306) pede confirmação no próprio painel: o
 * participante deixa de ver a coleção na hora e só volta com um novo convite.
 *
 * Acessibilidade: botão com `aria-expanded`/`aria-controls`; Esc e clique
 * fora fecham e devolvem o foco ao selo; no celular o painel ocupa a largura
 * útil. Movimento só opacidade/deslocamento, desligado em reduced-motion.
 */
export function SharedAccessMenu({
  collectionId,
  collectionName,
  ownerDisplayName,
  role = "VIEWER",
}: {
  collectionId: string;
  collectionName: string;
  ownerDisplayName: string;
  /** V1-13 · E3-1: papel do próprio usuário, lido da 5312. Só explica; não autoriza nada. */
  role?: MemberRole;
}) {
  const explanation = roleExplanation(role);
  const router = useRouter();
  const panelId = useId();
  const rootRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const close = (restoreFocus: boolean) => {
    if (busy) return;
    setOpen(false);
    setConfirming(false);
    setError(null);
    if (restoreFocus) triggerRef.current?.focus();
  };

  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        event.preventDefault();
        close(true);
      }
    };
    const onPointer = (event: PointerEvent) => {
      if (rootRef.current && !rootRef.current.contains(event.target as Node)) close(false);
    };
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps -- `close` só lê estado atual
  }, [open, busy]);

  const leave = async () => {
    setBusy(true);
    setError(null);
    const result = await leaveSharedCollection({ collectionId }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    if (!result.ok && result.reason !== "not_member") {
      setBusy(false);
      setError(sharingFailureMessage(result.reason));
      return;
    }
    router.replace(COLECOES_PATH);
    router.refresh();
  };

  return (
    <div ref={rootRef} className={styles.accessMenu}>
      <button
        ref={triggerRef}
        type="button"
        className={styles.accessTrigger}
        aria-expanded={open}
        aria-controls={panelId}
        aria-haspopup="true"
        onClick={() => (open ? close(false) : setOpen(true))}
      >
        {role === "EDITOR" ? <Pencil aria-hidden="true" /> : <Eye aria-hidden="true" />}
        <span>
          Compartilhada com você<span className={styles.accessTriggerMode}> · {ROLE_LABEL[role].toLowerCase()}</span>
        </span>
        <ChevronDown className={styles.accessChevron} aria-hidden="true" />
      </button>

      {open ? (
        <div id={panelId} className={styles.accessPanel} role="group" aria-label="Sobre esta coleção compartilhada">
          <p className={styles.accessOwner}>
            Coleção de <strong>{ownerDisplayName}</strong> · {ROLE_LABEL.OWNER.toLowerCase()}
          </p>
          <p className={styles.accessHelp}>
            Seu papel: <strong>{explanation.title}</strong>
          </p>
          <ul className={`${styles.accessHelp} list-disc space-y-0.5 pl-4`} aria-label="O que o seu papel permite">
            {explanation.can.map((line) => (
              <li key={line}>{line}</li>
            ))}
          </ul>
          <ul className={`${styles.accessHelp} list-disc space-y-0.5 pl-4`} aria-label="O que fica com o titular">
            {explanation.cannot.map((line) => (
              <li key={line}>Não pode: {line.charAt(0).toLowerCase() + line.slice(1)}</li>
            ))}
          </ul>
          {role === "EDITOR" ? <p className={styles.accessHelp}>{ROLE_AVAILABILITY_NOTE}</p> : null}
          <p className={styles.accessHelp}>Nada do seu acervo é compartilhado.</p>

          {confirming ? (
            <div className={styles.confirm} role="group" aria-label="Confirmar saída">
              <p>
                Você deixa de ver <strong>{collectionName}</strong>. Para voltar, o titular precisa convidar você de novo. Nada muda na coleção.
              </p>
              {error ? (
                <p className={styles.error} role="alert">
                  {error}
                </p>
              ) : null}
              <div className={styles.confirmActions}>
                <Button variant="destructive" size="sm" disabled={busy} onClick={() => void leave()} aria-busy={busy || undefined}>
                  {busy ? <Loader2 className="mr-1.5 h-3.5 w-3.5 animate-spin" aria-hidden="true" /> : null}
                  Sair da coleção
                </Button>
                <Button variant="ghost" size="sm" disabled={busy} onClick={() => setConfirming(false)}>
                  Ficar
                </Button>
              </div>
            </div>
          ) : (
            <button type="button" className={styles.accessLeave} onClick={() => setConfirming(true)}>
              <LogOut aria-hidden="true" />
              Sair desta coleção
            </button>
          )}
        </div>
      ) : null}
    </div>
  );
}
