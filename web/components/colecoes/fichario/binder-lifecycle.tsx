"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState, useTransition } from "react";
import { ArrowLeftRight, Check, Loader2, Minus, PackageOpen, Trash2 } from "lucide-react";
import { deleteEmptyBinder, dismantleBinder, readBinderLifecycle, transferBinderOwnership } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import {
  BINDER_ENDED_KEY,
  BINDER_ENDING_KEEPS,
  type BinderEndedKind,
  type BinderLifecyclePreview,
  TRANSFER_EFFECTS,
  type TransferCandidate,
  binderEndedMessage,
  binderEnding,
  binderLifecycleMessage,
  dismantleRemovals,
  transferFailureMessage,
} from "@/lib/colecoes/binder-lifecycle";
import { cn } from "@/lib/utils";
import { removeDismantledImageFiles } from "./binder-image-io";
import styles from "./binder-lifecycle.module.css";

/**
 * Gerenciar fichário (V1-05) — transferir (E20), desmontar (E19) e excluir
 * vazio (E19b). Composição do bloco "Arquivar coleção" (V1-04): ícone, título,
 * texto curto e a confirmação no próprio bloco, dizendo o que acontece.
 *
 * - Nada é lido ao abrir o painel: a prévia (5242) e os destinos (R1 + RLS)
 *   só vêm quando a pessoa pede uma ação. Contexto já conhecido (papel,
 *   convidadas, páginas) decide o que é oferecido.
 * - Transferir é reversível (dá para transferir de volta): borda e botões
 *   dourados. Desmontar/excluir são definitivos: borda e botões vermelhos,
 *   números da prévia e, para desmontar, reconhecimento explícito.
 * - A autorização é do banco (dono, ativo, convidadas, token do plano).
 */

export type BinderExit = { kind: "close"; onClose: () => void } | { kind: "link"; href: string };

type Mode =
  | { step: "idle" }
  | { step: "loading"; action: "transfer" | "end" }
  | { step: "transfer"; candidates: TransferCandidate[]; selected: string | null }
  | { step: "end"; preview: BinderLifecyclePreview };

export function BinderLifecycleSection({
  collectionId,
  collectionName,
  layoutId,
  role,
  editable,
  pageCount,
  participantCount,
  ownerCollectionName = null,
  exit,
}: {
  collectionId: string;
  collectionName: string;
  layoutId: string;
  role: "OWNER" | "GUEST" | null;
  /** 5223 `is_editable`: coleção ativa. Arquivada = só a transferência (saída da arquivada, 5254). */
  editable: boolean;
  pageCount: number;
  /** Coleções que usam o fichário (dona + convidadas). > 1 = há convidadas. */
  participantCount: number;
  ownerCollectionName?: string | null;
  exit: BinderExit;
}) {
  const router = useRouter();
  const [, startRefresh] = useTransition();
  const [mode, setMode] = useState<Mode>({ step: "idle" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const transferId = useId();
  const endId = useId();
  const firstFieldRef = useRef<HTMLElement | null>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);

  const ending = pageCount === 0 ? "delete" : "dismantle";
  const hasGuests = participantCount > 1;

  // Foco acompanha a confirmação: entra no primeiro controle e volta ao botão que abriu.
  const open = mode.step === "transfer" || mode.step === "end";
  const wasOpen = useRef(false);
  useEffect(() => {
    if (open && !wasOpen.current) firstFieldRef.current?.focus();
    else if (!open && wasOpen.current) triggerRef.current?.focus();
    wasOpen.current = open;
  }, [open]);

  if (role === "GUEST" && !done) {
    return (
      <p className={styles.note}>
        {ownerCollectionName ? (
          <>
            Este fichário pertence a <strong>{ownerCollectionName}</strong>.{" "}
          </>
        ) : (
          "Este fichário pertence a outra coleção. "
        )}
        Só a coleção principal desmonta ou transfere o fichário. Para esta coleção deixar de usá-lo, vá em Ajustes da coleção.
      </p>
    );
  }

  const cancel = () => {
    if (busy) return;
    setMode({ step: "idle" });
    setError(null);
    setAcknowledged(false);
  };

  const load = async (action: "transfer" | "end", trigger: HTMLButtonElement | null) => {
    if (busy) return;
    triggerRef.current = trigger;
    setError(null);
    setDone(null);
    setAcknowledged(false);
    setMode({ step: "loading", action });
    const read = await readBinderLifecycle({ collectionId, layoutId }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    if (!read.ok) {
      setMode({ step: "idle" });
      setError(binderLifecycleMessage(read.reason, "preview"));
      return;
    }
    if (action === "transfer") {
      if (read.candidates === null) {
        setMode({ step: "idle" });
        setError("Não conseguimos listar suas coleções agora. Tente novamente.");
        return;
      }
      setMode({ step: "transfer", candidates: read.candidates, selected: read.candidates[0]?.collectionId ?? null });
      return;
    }
    const kind = binderEnding(read.preview);
    if (kind === "blocked_guests" || kind === "blocked_is_guest" || kind === "archived" || kind === "absent") {
      setMode({ step: "idle" });
      setError(
        binderLifecycleMessage(
          kind === "blocked_guests" ? "has_guests" : kind === "blocked_is_guest" ? "is_guest" : kind === "archived" ? "archived" : "not_found",
          "preview",
        ),
      );
      if (kind === "absent" || kind === "blocked_is_guest") startRefresh(() => router.refresh());
      return;
    }
    setMode({ step: "end", preview: read.preview });
  };

  const leave = (kind: BinderEndedKind) => {
    try {
      window.sessionStorage.setItem(BINDER_ENDED_KEY, JSON.stringify({ collectionId, kind }));
    } catch {
      // Armazenamento bloqueado: a coleção volta correta, só sem a confirmação.
    }
    if (exit.kind === "close") {
      exit.onClose();
      startRefresh(() => router.refresh());
    } else {
      router.replace(exit.href);
      startRefresh(() => router.refresh());
    }
  };

  const confirmTransfer = async () => {
    if (busy || mode.step !== "transfer" || !mode.selected) return;
    const target = mode.candidates.find((c) => c.collectionId === mode.selected);
    setBusy(true);
    setError(null);
    const result = await transferBinderOwnership({ fromCollectionId: collectionId, toCollectionId: mode.selected }).catch(
      () => ({ ok: false, reason: "unknown" }) as const,
    );
    setBusy(false);
    if (!result.ok) {
      setError(transferFailureMessage(result.reason));
      if (result.reason === "target_archived" || result.reason === "target_has_binder" || result.reason === "target_is_guest") {
        void load("transfer", triggerRef.current);
      }
      return;
    }
    setMode({ step: "idle" });
    setDone(
      result.result.outcome === "UNCHANGED"
        ? "O fichário já estava com essa coleção. Nada mudou."
        : `Fichário transferido para ${target?.name ?? "a coleção escolhida"}. ${collectionName} continua usando o fichário como convidada.`,
    );
    startRefresh(() => router.refresh());
  };

  const confirmEnd = async () => {
    if (busy || mode.step !== "end") return;
    const preview = mode.preview;
    const kind = binderEnding(preview);
    if (kind === "dismantle" && !acknowledged) return;
    setBusy(true);
    setError(null);
    if (kind === "delete" && preview.layoutId) {
      const result = await deleteEmptyBinder({ collectionId, layoutId: preview.layoutId }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      if (!result.ok) {
        setBusy(false);
        setError(binderLifecycleMessage(result.reason, "delete"));
        if (result.reason === "has_pages" || result.reason === "has_guests") void load("end", triggerRef.current);
        return;
      }
      leave("deleted");
      return;
    }
    if (!preview.token) {
      setBusy(false);
      setError(binderLifecycleMessage("plan_changed", "dismantle"));
      return;
    }
    const result = await dismantleBinder({ collectionId, token: preview.token }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    if (!result.ok) {
      setBusy(false);
      setError(binderLifecycleMessage(result.reason, "dismantle"));
      // Plano mudou: relê a prévia para a pessoa revisar os números novos.
      if (result.reason === "plan_changed") void load("end", triggerRef.current);
      return;
    }
    // Arquivos das imagens só depois da resposta do banco; o que falhar é recolhido depois.
    if (result.result.imagePaths.length > 0) await removeDismantledImageFiles(result.result.imagePaths);
    leave("dismantled");
  };

  const loadingTransfer = mode.step === "loading" && mode.action === "transfer";
  const loadingEnd = mode.step === "loading" && mode.action === "end";
  const locked = busy || mode.step === "loading";

  return (
    <div className={styles.stack}>
      <div aria-live="polite" className={styles.live}>
        {done ? <p className={styles.success}><Check aria-hidden />{done}</p> : null}
        {error && !open ? <InlineFeedback tone="error">{error}</InlineFeedback> : null}
      </div>

      {role !== "GUEST" ? (
        <>
          {/* Transferir — reversível. */}
          <section className={cn(styles.card, styles.reversible)} data-open={mode.step === "transfer" || undefined} aria-labelledby={`${transferId}-t`}>
            <span className={styles.icon} aria-hidden>
              <ArrowLeftRight />
            </span>
            <h4 id={`${transferId}-t`} className={styles.title}>
              Transferir fichário
            </h4>
            <p className={styles.text}>Escolha outra coleção sua para ser a principal deste fichário. Tudo dentro dele continua igual.</p>
            <div className={styles.body}>
              {mode.step !== "transfer" ? (
                <div className={styles.actions}>
                  <Button
                    size="sm"
                    onClick={(event) => void load("transfer", event.currentTarget)}
                    disabled={locked}
                    aria-busy={loadingTransfer || undefined}
                  >
                    {loadingTransfer ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> : null}
                    {loadingTransfer ? "Carregando…" : "Transferir…"}
                  </Button>
                </div>
              ) : mode.candidates.length === 0 ? (
                <div className={styles.confirm}>
                  <p className={styles.text}>
                    Nenhuma outra coleção pode receber este fichário agora. Ela precisa estar ativa, sem fichário próprio e sem usar outro fichário.
                  </p>
                  <div className={styles.actions}>
                    <Button
                      ref={(node) => {
                        firstFieldRef.current = node;
                      }}
                      variant="ghost"
                      size="sm"
                      onClick={cancel}
                    >
                      Fechar
                    </Button>
                  </div>
                </div>
              ) : (
                <div className={styles.confirm} role="group" aria-label="Confirmar transferência">
                  <fieldset className={styles.choices} disabled={busy}>
                    <legend className={styles.legend}>Nova coleção principal</legend>
                    {mode.candidates.map((c, index) => (
                      <label key={c.collectionId} className={styles.choice} data-selected={mode.selected === c.collectionId || undefined}>
                        <input
                          ref={(node) => {
                            if (index === 0) firstFieldRef.current = node;
                          }}
                          type="radio"
                          name={`${transferId}-to`}
                          value={c.collectionId}
                          checked={mode.selected === c.collectionId}
                          onChange={() => setMode({ ...mode, selected: c.collectionId })}
                        />
                        <span className={styles.choiceName}>{c.name}</span>
                        {c.sharesThisBinder ? <span className={styles.choiceTag}>já usa este fichário</span> : null}
                      </label>
                    ))}
                  </fieldset>
                  <ul className={styles.effects}>
                    {TRANSFER_EFFECTS.map((effect) => (
                      <li key={effect}>
                        <Check aria-hidden />
                        <span>{effect}</span>
                      </li>
                    ))}
                  </ul>
                  {error ? <InlineFeedback tone="error">{error}</InlineFeedback> : null}
                  <div className={styles.actions}>
                    <Button size="sm" onClick={() => void confirmTransfer()} disabled={busy || !mode.selected} aria-busy={busy || undefined}>
                      {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> : <ArrowLeftRight className="h-3.5 w-3.5" aria-hidden />}
                      {busy ? "Transferindo…" : "Confirmar transferência"}
                    </Button>
                    <Button variant="ghost" size="sm" onClick={cancel} disabled={busy}>
                      Cancelar
                    </Button>
                  </div>
                </div>
              )}
            </div>
          </section>

          {/* Desmontar / excluir — definitivos. */}
          <section className={cn(styles.card, styles.danger)} data-open={mode.step === "end" || undefined} aria-labelledby={`${endId}-t`}>
            <span className={styles.icon} aria-hidden>
              {ending === "delete" ? <Trash2 /> : <PackageOpen />}
            </span>
            <h4 id={`${endId}-t`} className={styles.title}>
              {ending === "delete" ? "Excluir fichário" : "Desmontar fichário"}
            </h4>
            <p className={styles.text}>
              {ending === "delete"
                ? "O fichário está sem páginas. Excluir remove só o fichário vazio — suas cartas não são tocadas."
                : "Remove o fichário digital inteiro — páginas, bolsos e organização. Suas cartas físicas continuam no acervo e na coleção, e você pode montar um novo depois."}
            </p>
            <div className={styles.body}>
              {!editable ? (
                <p className={styles.blocked}>A coleção está arquivada. Reative-a para {ending === "delete" ? "excluir" : "desmontar"} o fichário.</p>
              ) : hasGuests ? (
                <p className={styles.blocked}>
                  Outras coleções usam este fichário. Desassocie-as em Ajustes de cada uma — ou transfira o fichário — antes de{" "}
                  {ending === "delete" ? "excluí-lo" : "desmontá-lo"}.
                </p>
              ) : mode.step !== "end" ? (
                <div className={styles.actions}>
                  <Button
                    variant="destructive"
                    size="sm"
                    onClick={(event) => void load("end", event.currentTarget)}
                    disabled={locked}
                    aria-busy={loadingEnd || undefined}
                  >
                    {loadingEnd ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> : null}
                    {loadingEnd ? "Carregando…" : ending === "delete" ? "Excluir…" : "Desmontar…"}
                  </Button>
                </div>
              ) : (
                <EndConfirm
                  preview={mode.preview}
                  busy={busy}
                  error={error}
                  acknowledged={acknowledged}
                  onAcknowledge={setAcknowledged}
                  onConfirm={() => void confirmEnd()}
                  onCancel={cancel}
                  firstFieldRef={firstFieldRef}
                />
              )}
            </div>
          </section>
        </>
      ) : null}
    </div>
  );
}

function EndConfirm({
  preview,
  busy,
  error,
  acknowledged,
  onAcknowledge,
  onConfirm,
  onCancel,
  firstFieldRef,
}: {
  preview: BinderLifecyclePreview;
  busy: boolean;
  error: string | null;
  acknowledged: boolean;
  onAcknowledge: (value: boolean) => void;
  onConfirm: () => void;
  onCancel: () => void;
  firstFieldRef: React.MutableRefObject<HTMLElement | null>;
}) {
  const kind = binderEnding(preview);
  const ackId = useId();
  if (kind === "delete") {
    return (
      <div className={styles.confirm} role="group" aria-label="Confirmar exclusão">
        <ul className={styles.effects}>
          {BINDER_ENDING_KEEPS.map((effect) => (
            <li key={effect}>
              <Check aria-hidden />
              <span>{effect}</span>
            </li>
          ))}
        </ul>
        {error ? <InlineFeedback tone="error">{error}</InlineFeedback> : null}
        <div className={styles.actions}>
          <Button
            ref={(node) => {
              firstFieldRef.current = node;
            }}
            variant="destructive"
            size="sm"
            onClick={onConfirm}
            disabled={busy}
            aria-busy={busy || undefined}
          >
            {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> : <Trash2 className="h-3.5 w-3.5" aria-hidden />}
            {busy ? "Excluindo…" : "Excluir fichário vazio"}
          </Button>
          <Button variant="ghost" size="sm" onClick={onCancel} disabled={busy}>
            Cancelar
          </Button>
        </div>
      </div>
    );
  }
  const removals = dismantleRemovals(preview);
  return (
    <div className={styles.confirm} role="group" aria-label="Confirmar desmontagem">
      <p className={styles.groupLabel}>Será removido do fichário digital</p>
      <ul className={cn(styles.effects, styles.removals)}>
        {removals.map((item) => (
          <li key={item}>
            <Minus aria-hidden />
            <span>{item}</span>
          </li>
        ))}
      </ul>
      <p className={styles.groupLabel}>Continua como está</p>
      <ul className={styles.effects}>
        {BINDER_ENDING_KEEPS.map((effect) => (
          <li key={effect}>
            <Check aria-hidden />
            <span>{effect}</span>
          </li>
        ))}
      </ul>
      <label className={styles.ack} htmlFor={ackId}>
        <input
          id={ackId}
          ref={(node) => {
            firstFieldRef.current = node;
          }}
          type="checkbox"
          checked={acknowledged}
          onChange={(event) => onAcknowledge(event.target.checked)}
          disabled={busy}
        />
        <span>Entendo que a desmontagem não pode ser desfeita. Para usar um fichário de novo, será preciso montá-lo do zero.</span>
      </label>
      {error ? <InlineFeedback tone="error">{error}</InlineFeedback> : null}
      <div className={styles.actions}>
        <Button variant="destructive" size="sm" onClick={onConfirm} disabled={busy || !acknowledged} aria-busy={busy || undefined}>
          {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden /> : <PackageOpen className="h-3.5 w-3.5" aria-hidden />}
          {busy ? "Desmontando…" : "Desmontar fichário"}
        </Button>
        <Button variant="ghost" size="sm" onClick={onCancel} disabled={busy}>
          Cancelar
        </Button>
      </div>
    </div>
  );
}

/**
 * Confirmação na coleção depois de desmontar/excluir: o fichário some da
 * página, e o resultado atravessa a navegação por um marcador lido uma vez.
 */
export function BinderEndedStatus({ collectionId }: { collectionId: string }) {
  const [kind, setKind] = useState<BinderEndedKind | null>(null);
  useEffect(() => {
    try {
      const raw = window.sessionStorage.getItem(BINDER_ENDED_KEY);
      if (!raw) return;
      const value = JSON.parse(raw) as { collectionId?: unknown; kind?: unknown };
      if (value.collectionId !== collectionId || (value.kind !== "dismantled" && value.kind !== "deleted")) return;
      window.sessionStorage.removeItem(BINDER_ENDED_KEY);
      setKind(value.kind);
    } catch {
      // Sem armazenamento: nada a mostrar.
    }
  }, [collectionId]);
  return (
    <p className={styles.endedStatus} role="status" aria-live="polite">
      {kind ? (
        <>
          <Check aria-hidden />
          {binderEndedMessage(kind)}
        </>
      ) : null}
    </p>
  );
}
