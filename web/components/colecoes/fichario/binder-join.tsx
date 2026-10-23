"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useState, useTransition } from "react";
import { BookOpen, Hand, Layers, Loader2, ShieldCheck, X } from "lucide-react";
import { attachToBinder, listJoinCandidates } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { binderHref, modelLabel } from "@/lib/colecoes/binder";
import { type JoinCandidate, type ShareFailure, plural, shareFailureMessage } from "@/lib/colecoes/binder-share";
import styles from "./binder-join.module.css";

/**
 * "Usar o fichário existente" (P2-SHARED-BINDER-FRONTEND-01, C-195).
 *
 * Quando a coleção ainda não tem fichário digital, mas outra coleção guardada
 * no MESMO fichário físico já tem (5230 `join_candidate_count`), a primeira
 * opção é usar esse fichário — não montar outro. O painel mostra de quem é o
 * fichário e o que acontece, e só associa depois do clique de confirmação
 * (5229 `attach_my_collection_to_binder`; nada é associado sozinho):
 *  - a organização atual não muda (páginas, cartas, reservas, cadeados);
 *  - as cartas desta coleção NÃO são posicionadas automaticamente — ficam em
 *    "Cartas disponíveis" dentro do fichário;
 *  - o progresso de cada coleção continua separado; dá para sair em Ajustes.
 *
 * Sucesso só é anunciado com a resposta do banco (`ATTACHED` ou
 * `ALREADY_ATTACHED`); qualquer outra coisa é erro com a mensagem do motivo.
 */
type LoadState = { status: "loading" } | { status: "error"; reason: ShareFailure } | { status: "ready"; candidates: JoinCandidate[] };

export function BinderJoinPanel({
  collectionId,
  collectionName,
  initialCandidates,
  variant,
  onCancel,
  onCreateOwn,
  onBusyChange,
}: {
  collectionId: string;
  collectionName: string;
  /** Lidos no servidor (rota /fichario); sem eles, o painel lê sozinho. */
  initialCandidates?: JoinCandidate[];
  variant: "dialog" | "page";
  onCancel?: () => void;
  /** Rota /fichario: alternativa discreta de montar um fichário só desta coleção. */
  onCreateOwn?: () => void;
  onBusyChange?: (busy: boolean) => void;
}) {
  const router = useRouter();
  const [, startRefresh] = useTransition();
  const [load, setLoad] = useState<LoadState>(() =>
    initialCandidates ? { status: "ready", candidates: initialCandidates } : { status: "loading" },
  );
  const [attempt, setAttempt] = useState(initialCandidates ? 0 : 1);
  const [choice, setChoice] = useState<string | null>(initialCandidates?.[0]?.layoutId ?? null);
  const [busy, setBusy] = useState(false);
  const [failure, setFailure] = useState<ShareFailure | null>(null);
  const [done, setDone] = useState<JoinCandidate | null>(null);

  useEffect(() => onBusyChange?.(busy), [busy, onBusyChange]);

  useEffect(() => {
    if (attempt === 0) return;
    let alive = true;
    setLoad({ status: "loading" });
    listJoinCandidates({ collectionId })
      .then((result) => {
        if (!alive) return;
        if (!result.ok) return setLoad({ status: "error", reason: result.reason });
        setLoad({ status: "ready", candidates: result.candidates });
        setChoice((current) => (result.candidates.some((c) => c.layoutId === current) ? current : (result.candidates[0]?.layoutId ?? null)));
      })
      .catch(() => alive && setLoad({ status: "error", reason: "unknown" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId]);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);
  const candidates = load.status === "ready" ? load.candidates : [];
  const chosen = candidates.find((candidate) => candidate.layoutId === choice) ?? null;

  const confirm = async () => {
    if (!chosen || busy) return;
    setBusy(true);
    setFailure(null);
    const result = await attachToBinder({ collectionId, layoutId: chosen.layoutId }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    setBusy(false);
    if (!result.ok) {
      setFailure(result.reason);
      // O conjunto de candidatos pode ter mudado: relê antes de nova tentativa.
      if (result.reason === "binder_not_found" || result.reason === "not_same_location" || result.reason === "binder_archived") reload();
      return;
    }
    setDone(chosen);
    startRefresh(() => router.refresh());
  };

  const titleId = `fichario-usar-${collectionId}`;
  const owner = chosen?.ownerCollectionName ?? "a outra coleção";

  if (done) {
    return (
      <section className={styles.panel} data-variant={variant} aria-labelledby={titleId} aria-live="polite">
        <div className={styles.success}>
          <p className={styles.eyebrow}>Fichário compartilhado</p>
          <h2 id={titleId} className={styles.title}>
            {collectionName} agora usa o fichário de {done.ownerCollectionName}
          </h2>
          <p className={styles.lead}>
            Nada da organização atual mudou. Abra o fichário e escolha os bolsos das suas cartas em <strong>Cartas disponíveis</strong>.
          </p>
          <div className={styles.actions}>
            {variant === "dialog" && onCancel ? (
              <Button variant="outline" onClick={onCancel}>
                Fechar
              </Button>
            ) : null}
            <Button asChild>
              <Link href={binderHref(collectionId)}>
                <BookOpen className="mr-1.5 h-4 w-4" aria-hidden />
                Abrir o fichário
              </Link>
            </Button>
          </div>
        </div>
      </section>
    );
  }

  return (
    <section className={styles.panel} data-variant={variant} aria-labelledby={titleId} aria-busy={busy || undefined}>
      <div className={styles.head}>
        <div>
          <p className={styles.eyebrow}>Fichário digital</p>
          <h2 id={titleId} className={styles.title}>
            {candidates.length > 1 ? "Este local já tem fichários digitais" : "Este local já tem um fichário digital"}
          </h2>
          <p className={styles.lead}>
            {collectionName} fica guardada no mesmo fichário físico. Use o fichário que já existe em vez de montar outro.
          </p>
        </div>
        {variant === "dialog" && onCancel ? (
          <DialogPrimitive.Close className={styles.close} aria-label="Fechar" disabled={busy}>
            <X className="h-4 w-4" aria-hidden />
          </DialogPrimitive.Close>
        ) : null}
      </div>

      {load.status === "loading" ? (
        <div className={styles.skeleton} aria-busy="true" aria-label="Procurando o fichário deste local" />
      ) : load.status === "error" ? (
        <div className="flex flex-col items-start gap-3" role="alert">
          <InlineFeedback tone="error">{shareFailureMessage(load.reason)}</InlineFeedback>
          <Button variant="outline" onClick={reload}>
            Tentar de novo
          </Button>
        </div>
      ) : candidates.length === 0 ? (
        <InlineFeedback tone="warning">
          Não há mais um fichário disponível neste local. {onCreateOwn ? "Você pode montar um fichário só para esta coleção." : "Feche e abra a coleção de novo."}
        </InlineFeedback>
      ) : (
        <>
          <div className={styles.candidates} role={candidates.length > 1 ? "radiogroup" : undefined} aria-label="Fichários deste local">
            {candidates.map((candidate) =>
              candidates.length > 1 ? (
                <button
                  key={candidate.layoutId}
                  type="button"
                  role="radio"
                  aria-checked={candidate.layoutId === choice}
                  className={styles.candidate}
                  onClick={() => setChoice(candidate.layoutId)}
                  disabled={busy}
                >
                  <CandidateFace candidate={candidate} />
                </button>
              ) : (
                <div key={candidate.layoutId} className={styles.candidate} data-single>
                  <CandidateFace candidate={candidate} />
                </div>
              ),
            )}
          </div>

          <ul className={styles.facts}>
            <li className={styles.fact}>
              <span className={styles.factIcon} aria-hidden>
                <ShieldCheck />
              </span>
              <span>
                <span className={styles.factTitle}>A organização atual é preservada.</span>{" "}
                <span className={styles.factBody}>Páginas, cartas, reservas e bolsos fixados de {owner} continuam exatamente como estão.</span>
              </span>
            </li>
            <li className={styles.fact}>
              <span className={styles.factIcon} aria-hidden>
                <Hand />
              </span>
              <span>
                <span className={styles.factTitle}>Você escolhe os bolsos.</span>{" "}
                <span className={styles.factBody}>
                  As cartas de {collectionName} não são posicionadas automaticamente — elas ficam em <em>Cartas disponíveis</em>, dentro do fichário.
                </span>
              </span>
            </li>
            <li className={styles.fact}>
              <span className={styles.factIcon} aria-hidden>
                <Layers />
              </span>
              <span>
                <span className={styles.factTitle}>Cada coleção continua com o seu progresso.</span>{" "}
                <span className={styles.factBody}>Para sair do fichário compartilhado depois, use Ajustes da coleção.</span>
              </span>
            </li>
          </ul>
        </>
      )}

      <div aria-live="polite">{failure ? <InlineFeedback tone="error">{shareFailureMessage(failure)}</InlineFeedback> : null}</div>

      <div className={styles.actions} data-variant={variant}>
        {variant === "page" && onCreateOwn ? (
          <button type="button" className={styles.quiet} onClick={onCreateOwn} disabled={busy}>
            Prefiro montar um fichário só para esta coleção
          </button>
        ) : variant === "dialog" && onCancel ? (
          <Button variant="outline" onClick={onCancel} disabled={busy}>
            Cancelar
          </Button>
        ) : null}
        <Button onClick={() => void confirm()} disabled={!chosen || busy || load.status !== "ready"}>
          {busy ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden /> : <BookOpen className="mr-1.5 h-4 w-4" aria-hidden />}
          {busy ? "Associando…" : chosen ? `Usar o fichário de ${chosen.ownerCollectionName}` : "Usar este fichário"}
        </Button>
      </div>
    </section>
  );
}

function CandidateFace({ candidate }: { candidate: JoinCandidate }) {
  return (
    <>
      <Glyph columns={candidate.columns} rows={candidate.rows} />
      <span className={styles.candidateText}>
        <span className={styles.candidateName}>Fichário de {candidate.ownerCollectionName}</span>
        <span className={styles.candidateMeta}>
          {modelLabel(candidate.columns, candidate.rows)} · {plural(candidate.pageCount, "página", "páginas")} · {plural(candidate.freeSlotCount, "bolso livre", "bolsos livres")}
          {candidate.participantCount > 1 ? ` · ${plural(candidate.participantCount, "coleção", "coleções")}` : ""}
        </span>
      </span>
    </>
  );
}

function Glyph({ columns, rows }: { columns: number; rows: number }) {
  const pockets = Array.from({ length: Math.min(columns * rows, 25) });
  return (
    <span className={styles.glyph} style={{ "--cols": columns } as React.CSSProperties} aria-hidden>
      <span className={styles.leaf}>
        {pockets.map((_, index) => (
          <span key={index} />
        ))}
      </span>
      <span className={styles.leaf}>
        {pockets.map((_, index) => (
          <span key={index} />
        ))}
      </span>
    </span>
  );
}

/** Confirmação em diálogo, aberta pela entrada "Usar fichário existente" no hero da coleção. */
export function BinderJoinDialog({ collectionId, collectionName, onClose }: { collectionId: string; collectionName: string; onClose: () => void }) {
  const restoreFocus = useRestoreFocus();
  const [busy, setBusy] = useState(false);
  return (
    <DialogPrimitive.Root open onOpenChange={(open) => !open && !busy && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className={styles.overlay} />
        <DialogPrimitive.Content
          className={styles.dialog}
          aria-describedby={undefined}
          onEscapeKeyDown={(event) => busy && event.preventDefault()}
          onPointerDownOutside={(event) => busy && event.preventDefault()}
          onCloseAutoFocus={restoreFocus}
        >
          <DialogPrimitive.Title className="sr-only">Usar o fichário existente</DialogPrimitive.Title>
          <BinderJoinPanel collectionId={collectionId} collectionName={collectionName} variant="dialog" onCancel={onClose} onBusyChange={setBusy} />
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

/**
 * Rota /fichario de uma coleção que pode usar um fichário existente: a
 * associação vem primeiro; montar um fichário próprio fica como alternativa
 * discreta (decisão do colecionador, nunca induzida).
 */
export function BinderJoinOrCreate({
  collectionId,
  collectionName,
  candidates,
  createOwn,
}: {
  collectionId: string;
  collectionName: string;
  candidates: JoinCandidate[];
  createOwn: React.ReactNode;
}) {
  const [mode, setMode] = useState<"join" | "create">("join");
  if (mode === "create") {
    return (
      <>
        <div className="mb-4 mt-2">
          <button type="button" className={styles.quiet} onClick={() => setMode("join")}>
            Voltar: usar o fichário que já existe neste local
          </button>
        </div>
        {createOwn}
      </>
    );
  }
  return (
    <BinderJoinPanel
      collectionId={collectionId}
      collectionName={collectionName}
      initialCandidates={candidates}
      variant="page"
      onCreateOwn={() => setMode("create")}
    />
  );
}
