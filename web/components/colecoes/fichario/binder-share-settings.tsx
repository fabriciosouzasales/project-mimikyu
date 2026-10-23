"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useId, useState, useTransition } from "react";
import { Link2, Loader2, Unlink } from "lucide-react";
import { detachFromBinder, previewDetach } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { type DetachPreview, type ShareFailure, plural, shareFailureMessage } from "@/lib/colecoes/binder-share";
import styles from "../colecoes/collection-manage.module.css";

type State =
  | { status: "loading" }
  | { status: "error"; reason: ShareFailure }
  | { status: "none" }
  | { status: "guest"; preview: DetachPreview };

/**
 * Ajustes → Fichário compartilhado (P2-SHARED-BINDER-FRONTEND-01, C-197).
 *
 * Só aparece quando a coleção é CONVIDADA do fichário de outra coleção
 * (5229 `preview_my_collection_binder_detach` devolve uma linha). Sair do
 * fichário remove apenas as posições e as reservas DESTA coleção; cartas
 * físicas, alocações, progresso e a organização da outra coleção não mudam.
 * Bolsos fixados afetados só são soltos com confirmação explícita. A prévia
 * traz um token: se algo mudou desde então, o banco recusa
 * (`DETACH_PLAN_CHANGED`) e a prévia é relida — nada é feito às cegas.
 */
export function SharedBinderSettingsSection({ collectionId, onBusyChange }: { collectionId: string; onBusyChange: (busy: boolean) => void }) {
  const router = useRouter();
  const [, startRefresh] = useTransition();
  const titleId = useId();
  const releaseId = useId();
  const [state, setState] = useState<State>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [confirming, setConfirming] = useState(false);
  const [releaseLocks, setReleaseLocks] = useState(false);
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<ShareFailure | null>(null);
  const [done, setDone] = useState<string | null>(null);

  useEffect(() => onBusyChange(busy), [busy, onBusyChange]);

  useEffect(() => {
    let alive = true;
    previewDetach({ collectionId })
      .then((result) => {
        if (!alive) return;
        if (!result.ok) return setState({ status: "error", reason: result.reason });
        setState(result.preview ? { status: "guest", preview: result.preview } : { status: "none" });
      })
      .catch(() => alive && setState({ status: "error", reason: "unknown" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId]);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  if (done) {
    return (
      <section className={styles.section} aria-labelledby={titleId} aria-live="polite">
        <h3 id={titleId} className={styles.sectionTitle}>
          Fichário compartilhado
        </h3>
        <InlineFeedback tone="success">{done}</InlineFeedback>
      </section>
    );
  }

  // Coleções que não são convidadas não veem esta seção (nem enquanto carrega).
  if (state.status === "loading" || state.status === "none") return null;

  if (state.status === "error") {
    return (
      <section className={styles.section} aria-labelledby={titleId}>
        <h3 id={titleId} className={styles.sectionTitle}>
          Fichário compartilhado
        </h3>
        <div className="flex flex-col items-start gap-3" role="alert">
          <InlineFeedback tone="error">Não conseguimos verificar se esta coleção usa um fichário compartilhado.</InlineFeedback>
          <Button variant="outline" className="min-h-11" onClick={reload}>
            Tentar novamente
          </Button>
        </div>
      </section>
    );
  }

  const p = state.preview;

  const detach = async () => {
    if (busy) return;
    if (p.lockedCount > 0 && !releaseLocks) return;
    setBusy(true);
    setFailure(null);
    const result = await detachFromBinder({ collectionId, token: p.token, releaseLocks: p.lockedCount > 0 && releaseLocks }).catch(
      () => ({ ok: false, reason: "unknown" }) as const,
    );
    setBusy(false);
    if (!result.ok) {
      setFailure(result.reason);
      // Prévia velha ou cadeados novos: relê os números antes de qualquer nova tentativa.
      if (result.reason === "plan_changed" || result.reason === "locks_need_confirmation") {
        setReleaseLocks(false);
        reload();
      }
      return;
    }
    const r = result.result;
    setDone(
      r.outcome === "ALREADY_DETACHED"
        ? `Esta coleção já não usava o fichário de ${p.ownerCollectionName}.`
        : `Esta coleção saiu do fichário de ${p.ownerCollectionName}. ${
            r.assignmentsRemoved > 0 ? `${plural(r.assignmentsRemoved, "carta saiu", "cartas saíram")} dos bolsos e continua${r.assignmentsRemoved === 1 ? "" : "m"} na coleção. ` : ""
          }O progresso não mudou.`,
    );
    startRefresh(() => router.refresh());
  };

  return (
    <section className={styles.section} aria-labelledby={titleId}>
      <h3 id={titleId} className={styles.sectionTitle}>
        Fichário compartilhado
      </h3>
      <p className={`${styles.note} flex items-start gap-2`}>
        <Link2 className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
        <span>
          Esta coleção usa o fichário digital de <strong>{p.ownerCollectionName}</strong>.{" "}
          {p.assignmentsCount > 0 || p.reservationsCount > 0
            ? `Nele, ${plural(p.assignmentsCount, "carta desta coleção ocupa um bolso", "cartas desta coleção ocupam bolsos")}${
                p.reservationsCount > 0 ? ` e há ${plural(p.reservationsCount, "reserva desta coleção", "reservas desta coleção")}` : ""
              }.`
            : "Nenhuma carta desta coleção está nos bolsos ainda."}
        </span>
      </p>

      {!confirming ? (
        <Button
          variant="outline"
          className="min-h-11 self-start"
          onClick={() => {
            setFailure(null);
            setConfirming(true);
          }}
        >
          <Unlink className="mr-1.5 h-4 w-4" aria-hidden="true" />
          Sair do fichário compartilhado
        </Button>
      ) : (
        <div className="flex flex-col gap-3 rounded-lg border border-border p-3" role="group" aria-label="Confirmar saída do fichário compartilhado">
          <p className="text-sm font-semibold">Ao sair do fichário de {p.ownerCollectionName}:</p>
          <ul className="flex list-disc flex-col gap-1 pl-5 text-sm text-muted-foreground">
            <li>
              {p.assignmentsCount > 0
                ? `${plural(p.assignmentsCount, "carta desta coleção sai do bolso", "cartas desta coleção saem dos bolsos")} — continua${p.assignmentsCount === 1 ? "" : "m"} na coleção e no seu acervo.`
                : "Nenhuma carta desta coleção está nos bolsos."}
            </li>
            {p.reservationsCount > 0 ? <li>{plural(p.reservationsCount, "reserva desta coleção é liberada", "reservas desta coleção são liberadas")}.</li> : null}
            {p.lockedCount > 0 ? <li>{plural(p.lockedCount, "bolso fixado com carta ou reserva desta coleção precisa ser solto", "bolsos fixados com cartas ou reservas desta coleção precisam ser soltos")}.</li> : null}
            <li>
              Nada muda em {p.ownerCollectionName}, e o progresso das duas coleções continua o mesmo. Nenhuma carta é excluída.
            </li>
          </ul>
          {p.lockedCount > 0 ? (
            <label htmlFor={releaseId} className="flex items-start gap-2 text-sm">
              <input
                id={releaseId}
                type="checkbox"
                className="mt-0.5 h-4 w-4 accent-[hsl(var(--primary))]"
                checked={releaseLocks}
                onChange={(event) => setReleaseLocks(event.target.checked)}
                disabled={busy}
              />
              <span>Pode soltar {p.lockedCount === 1 ? "esse bolso fixado" : `esses ${p.lockedCount} bolsos fixados`}.</span>
            </label>
          ) : null}
          <div aria-live="polite">{failure ? <InlineFeedback tone="error">{shareFailureMessage(failure)}</InlineFeedback> : null}</div>
          <div className="flex flex-wrap justify-end gap-2">
            <Button
              variant="outline"
              className="min-h-11"
              onClick={() => {
                setConfirming(false);
                setReleaseLocks(false);
                setFailure(null);
              }}
              disabled={busy}
            >
              Cancelar
            </Button>
            <Button variant="destructive" className="min-h-11" onClick={() => void detach()} disabled={busy || (p.lockedCount > 0 && !releaseLocks)}>
              {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : <Unlink className="mr-1.5 h-4 w-4" aria-hidden="true" />}
              {busy ? "Saindo…" : "Sair do fichário"}
            </Button>
          </div>
        </div>
      )}
    </section>
  );
}
