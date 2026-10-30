"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { Archive, ArchiveRestore, Check, Loader2 } from "lucide-react";
import { archiveCollection, reactivateCollection } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { ARCHIVE_EFFECTS, type LifecycleFailure, lifecycleFailureMessage } from "@/lib/colecoes/collection-lifecycle";
import manageStyles from "./collection-manage.module.css";
import styles from "./collection-lifecycle.module.css";

/**
 * Ciclo de vida da coleção (V1-04, incremento 01) — arquivar e reativar.
 *
 * - `ArchiveCollectionSection`: última seção dos Ajustes. Confirmação no
 *   próprio painel, dizendo o que acontece; só o titular vê os Ajustes e o
 *   banco recusa qualquer outro usuário (5037).
 * - `CollectionLifecycleNotice`: aviso fixo na página da coleção. Arquivada →
 *   explica o modo de consulta e oferece "Reativar coleção" (5038). Fica
 *   montado nos dois estados para, depois de reativar, confirmar o resultado
 *   em vez de a página simplesmente voltar ao normal.
 *
 * Nenhum dos dois toca exemplares, vínculos, fichário ou locais.
 */

export function ArchiveCollectionSection({
  collectionId,
  collectionName,
  onBusyChange,
}: {
  collectionId: string;
  collectionName: string;
  onBusyChange: (busy: boolean) => void;
}) {
  const router = useRouter();
  const [, startRefresh] = useTransition();
  const titleId = useId();
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<LifecycleFailure | null>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);
  const askRef = useRef<HTMLButtonElement>(null);
  const wasConfirming = useRef(false);

  useEffect(() => onBusyChange(busy), [busy, onBusyChange]);

  // Foco acompanha a confirmação: vai para "Arquivar" ao abrir e volta ao botão ao cancelar.
  useEffect(() => {
    if (confirming) confirmRef.current?.focus();
    else if (wasConfirming.current) askRef.current?.focus();
    wasConfirming.current = confirming;
  }, [confirming]);

  const archive = async () => {
    if (busy) return;
    setBusy(true);
    setFailure(null);
    const result = await archiveCollection({ collectionId }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
    if (!result.ok) {
      setBusy(false);
      setFailure(result.reason);
      return;
    }
    // A página volta do servidor em modo de consulta: os Ajustes somem e o aviso
    // de coleção arquivada assume o feedback (com "Reativar").
    startRefresh(() => router.refresh());
  };

  return (
    <section className={styles.zone} aria-labelledby={titleId}>
      <div className={styles.zoneCard}>
        <span className={styles.zoneIcon} aria-hidden="true">
          <Archive className="h-4 w-4" />
        </span>
        <h3 id={titleId} className={styles.zoneTitle}>
          Arquivar coleção
        </h3>
        <p className={styles.zoneText}>
          Tira a coleção da estante sem perder nada. Ela fica disponível para consulta e pode ser reativada quando quiser.
        </p>
        <div className={styles.zoneBody}>
          {!confirming ? (
            <div className={styles.zoneActions}>
              <Button
                ref={askRef}
                className="min-h-11"
                onClick={() => {
                  setFailure(null);
                  setConfirming(true);
                }}
              >
                <Archive className="mr-1.5 h-4 w-4" aria-hidden="true" />
                Arquivar coleção
              </Button>
            </div>
          ) : (
            <div className="flex flex-col gap-3" role="group" aria-label="Confirmar arquivamento">
              <p className={manageStyles.confirmText}>
                Arquivar <strong>{collectionName}</strong>?
              </p>
              <ul className={styles.effects}>
                {ARCHIVE_EFFECTS.map((effect) => (
                  <li key={effect}>
                    <Check className="h-3.5 w-3.5" aria-hidden="true" />
                    <span>{effect}</span>
                  </li>
                ))}
              </ul>
              <div aria-live="polite">
                {failure ? <InlineFeedback tone="error">{lifecycleFailureMessage(failure, "archive")}</InlineFeedback> : null}
              </div>
              <div className={styles.zoneActions}>
                <Button ref={confirmRef} className="min-h-11" onClick={() => void archive()} disabled={busy} aria-busy={busy || undefined}>
                  {busy ? (
                    <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" />
                  ) : (
                    <Archive className="mr-1.5 h-4 w-4" aria-hidden="true" />
                  )}
                  {busy ? "Arquivando…" : "Confirmar arquivamento"}
                </Button>
                <Button
                  variant="ghost"
                  className="min-h-11"
                  onClick={() => {
                    setConfirming(false);
                    setFailure(null);
                  }}
                  disabled={busy}
                >
                  Cancelar
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}

/**
 * Estado arquivado no cabeçalho da coleção (V1-04, ARCHIVED-HEADER-REFINEMENT-02):
 * sem faixa nem card de aviso. O título continua protagonista; ao lado dele, um
 * selo discreto "Arquivada" (com a explicação do modo de consulta para leitores
 * de tela) e, na barra do cabeçalho — no lugar dos Ajustes —, o botão "Reativar".
 */
export function ArchivedBadge() {
  return (
    <span className={styles.archivedBadge}>
      <Archive className="h-3.5 w-3.5" aria-hidden="true" />
      Arquivada
      <span className="sr-only"> — coleção em modo de consulta; cartas, organização e progresso preservados</span>
    </span>
  );
}

export function ReactivateCollectionButton({ collectionId, collectionName }: { collectionId: string; collectionName: string }) {
  const router = useRouter();
  const [refreshing, startRefresh] = useTransition();
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<LifecycleFailure | null>(null);
  const working = busy || refreshing;

  const reactivate = async () => {
    if (working) return;
    setBusy(true);
    setFailure(null);
    const result = await reactivateCollection({ collectionId }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
    setBusy(false);
    if (!result.ok) {
      setFailure(result.reason);
      return;
    }
    putReactivatedMark(collectionId);
    startRefresh(() => router.refresh());
  };

  return (
    <div className={styles.headerAction}>
      {failure ? (
        <span className={styles.headerError} role="alert">
          {lifecycleFailureMessage(failure, "reactivate")}
        </span>
      ) : null}
      <Button
        variant="outline"
        className="min-h-11"
        onClick={() => void reactivate()}
        disabled={working}
        aria-busy={working || undefined}
        aria-label={working ? `Reativando ${collectionName}` : `Reativar ${collectionName}`}
      >
        {working ? (
          <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" />
        ) : (
          <ArchiveRestore className="mr-1.5 h-4 w-4" aria-hidden="true" />
        )}
        {working ? "Reativando…" : "Reativar"}
      </Button>
    </div>
  );
}

/**
 * Confirmação discreta depois de reativar, na barra do cabeçalho (ao lado dos
 * Ajustes). A página ativa e a arquivada não têm a mesma árvore, então o
 * resultado atravessa a recarga por um marcador de sessão lido uma vez.
 */
export function ReactivatedStatus({ collectionId }: { collectionId: string }) {
  const [shown, setShown] = useState(false);
  useEffect(() => {
    if (takeReactivatedMark(collectionId)) setShown(true);
  }, [collectionId]);
  return (
    <span className={styles.headerStatus} role="status" aria-live="polite">
      {shown ? (
        <>
          <Check className="h-3.5 w-3.5" aria-hidden="true" />
          Coleção reativada
        </>
      ) : null}
    </span>
  );
}

const REACTIVATED_KEY = "mmkyu:colecao-reativada";

function putReactivatedMark(collectionId: string) {
  try {
    window.sessionStorage.setItem(REACTIVATED_KEY, collectionId);
  } catch {
    // Armazenamento bloqueado: a página reativada continua correta, só sem a confirmação.
  }
}

function takeReactivatedMark(collectionId: string): boolean {
  try {
    if (window.sessionStorage.getItem(REACTIVATED_KEY) !== collectionId) return false;
    window.sessionStorage.removeItem(REACTIVATED_KEY);
    return true;
  } catch {
    return false;
  }
}
