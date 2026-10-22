"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { Loader2 } from "lucide-react";
import { organizeCollectionStorage, readCollectionStoragePlan } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  type OrganizeFailure,
  type OrganizeMode,
  type OrganizePlan,
  type ProposalOrigin,
  atTargetSentence,
  autoProposalKind,
  confirmationSentence,
  eligibleFor,
  exemplares,
  leavingOtherPlaces,
  leavingSentence,
  limitNotice,
  modeOptions,
  organizeFailureMessage,
  planFailureMessage,
  planVerdict,
  proposalSubtitle,
  proposalTitle,
  reconcileMode,
  recoveryFor,
  resultSentence,
  verdictMessage,
} from "@/lib/colecoes/collection-organize";
import objectiveStyles from "./collection-objective.module.css";
import styles from "./collection-organize.module.css";

/**
 * WHERE-05A — "Organizar cartas neste local", dentro de Ajustes → Onde guardo.
 *
 * Um único fluxo para os dois pontos de entrada:
 *  - `after_save`: logo depois de salvar o local padrão (5036). Só aparece se
 *    houver o que organizar; acima do teto, só um aviso discreto. O padrão já
 *    está salvo — "Agora não" apenas fecha;
 *  - `later`: pela ação "Organizar cartas neste local", com o padrão vigente.
 *
 * Proposta (5221) → confirmação → escrita (5222). Só "Confirmar organização"
 * escreve. Fica em linha no painel de Ajustes (sem diálogo sobreposto).
 */

export type OrganizeTarget = { id: string; name: string; kindCode: string | null };

type Step =
  | { kind: "loading" }
  | { kind: "plan_error"; reason: OrganizeFailure }
  | { kind: "hidden" }
  | { kind: "info"; plan: OrganizePlan }
  | { kind: "choose"; plan: OrganizePlan; mode: OrganizeMode | null }
  | { kind: "confirm"; plan: OrganizePlan; mode: OrganizeMode; running: boolean; error: OrganizeFailure | null }
  | { kind: "done"; moved: number; total: number; atTarget: number };

export function OrganizeStorageFlow({
  collectionId,
  collectionName,
  target,
  origin,
  onBusyChange,
  onDismiss,
  onDefaultChanged,
}: {
  collectionId: string;
  collectionName: string;
  target: OrganizeTarget;
  origin: ProposalOrigin;
  onBusyChange: (busy: boolean) => void;
  onDismiss: () => void;
  /** O padrão mudou desde a prévia: o painel relê "Onde guardo" e explica. */
  onDefaultChanged: (message: string) => void;
}) {
  const router = useRouter();
  const [, startRefresh] = useTransition();
  const headingId = useId();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const inFlight = useRef(false);
  const [step, setStep] = useState<Step>({ kind: "loading" });
  /** Aviso sobre a prévia atual (ex.: "as cartas mudaram desde a prévia"). */
  const [notice, setNotice] = useState<string | null>(null);
  /**
   * A prévia foi refeita depois de uma tentativa (ex.: PLAN_CHANGED): a partir
   * daí os estados especiais são sempre explicados e o subtítulo deixa de
   * falar em "foi atualizado".
   */
  const [refreshed, setRefreshed] = useState(false);

  const loadPlan = useCallback(
    async (opts: { keepMode?: OrganizeMode | null; notice?: string | null; explain?: boolean } = {}) => {
      setStep({ kind: "loading" });
      const result = await readCollectionStoragePlan({ collectionId, storageContainerId: target.id }).catch(
        () => ({ ok: false, reason: "unknown" }) as const,
      );
      if (!result.ok) {
        setNotice(null);
        setStep({ kind: "plan_error", reason: result.reason });
        return;
      }
      const plan = result.plan;
      setNotice(opts.notice ?? null);
      const explain = opts.explain ?? false;
      if (explain) setRefreshed(true);
      if (!explain && origin === "after_save") {
        // Proposta automática só quando pertinente; nada aparece nos demais casos.
        const auto = autoProposalKind(plan);
        if (auto === "none") return setStep({ kind: "hidden" });
        if (auto === "limit_notice") return setStep({ kind: "info", plan });
      }
      if (planVerdict(plan) !== "ready") return setStep({ kind: "info", plan });
      setStep({ kind: "choose", plan, mode: reconcileMode(plan, opts.keepMode ?? null) });
    },
    [collectionId, origin, target.id],
  );

  useEffect(() => {
    void loadPlan();
  }, [loadPlan]);

  useEffect(() => {
    onBusyChange(step.kind === "confirm" && step.running);
  }, [step, onBusyChange]);

  // Cada etapa nova recebe o foco no título (leitores de tela anunciam a mudança).
  const stepKey = step.kind;
  useEffect(() => {
    if (stepKey !== "loading" && stepKey !== "hidden") headingRef.current?.focus();
  }, [stepKey]);

  const confirm = async () => {
    if (step.kind !== "confirm" || step.running || inFlight.current) return;
    const { plan, mode } = step;
    inFlight.current = true;
    setStep({ ...step, running: true, error: null });
    const result = await organizeCollectionStorage({
      collectionId,
      storageContainerId: target.id,
      mode,
      expectedCount: eligibleFor(plan, mode),
      planToken: plan.planToken,
    }).catch(() => ({ ok: false, reason: "unknown" }) as const);
    inFlight.current = false;
    if (result.ok) {
      setStep({ kind: "done", moved: result.moved, total: result.total, atTarget: result.atTarget });
      startRefresh(() => router.refresh());
      return;
    }
    switch (recoveryFor(result.reason)) {
      case "refresh_plan":
        // Nunca repete a escrita sozinho: nova prévia, nova confirmação.
        await loadPlan({ keepMode: mode, notice: organizeFailureMessage(result.reason), explain: true });
        return;
      case "reload_destination":
        onDefaultChanged(organizeFailureMessage(result.reason));
        return;
      default:
        setStep({ kind: "confirm", plan, mode, running: false, error: result.reason });
    }
  };

  if (step.kind === "hidden") return null;
  // Logo após salvar: nada aparece enquanto a prévia não diz se há o que organizar (sem piscar).
  if (step.kind === "loading" && origin === "after_save" && !refreshed) return null;

  const title = step.kind === "done" ? "Cartas organizadas" : step.kind === "confirm" ? "Confirmar organização" : proposalTitle(target.kindCode);

  return (
    <section className={`${objectiveStyles.review} ${styles.flow}`} aria-labelledby={headingId} aria-busy={step.kind === "loading"}>
      <div className={styles.head}>
        <h4 id={headingId} ref={headingRef} tabIndex={-1} className={objectiveStyles.reviewTitle}>
          {title}
        </h4>
        {step.kind === "choose" || step.kind === "loading" ? (
          <p className={styles.subtitle}>{proposalSubtitle(refreshed ? "later" : origin)}</p>
        ) : null}
      </div>

      {step.kind === "loading" ? (
        <div className={objectiveStyles.reviewLoading}>
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
          Conferindo as cartas desta coleção…
        </div>
      ) : step.kind === "plan_error" ? (
        <div className="flex flex-col gap-3" role="alert">
          <InlineFeedback tone="error">{planFailureMessage(step.reason, origin)}</InlineFeedback>
          <div className={objectiveStyles.reviewActions}>
            <Button className="min-h-11" onClick={() => void loadPlan({ explain: refreshed })}>
              Tentar novamente
            </Button>
            <Button variant="outline" className="min-h-11" onClick={onDismiss}>
              Agora não
            </Button>
          </div>
        </div>
      ) : step.kind === "info" ? (
        <InfoBody plan={step.plan} notice={notice} onDismiss={onDismiss} />
      ) : step.kind === "choose" ? (
        <ChooseBody
          plan={step.plan}
          mode={step.mode}
          target={target}
          notice={notice}
          onMode={(mode) => setStep({ ...step, mode })}
          onContinue={() => {
            if (!step.mode) return;
            setNotice(null);
            setStep({ kind: "confirm", plan: step.plan, mode: step.mode, running: false, error: null });
          }}
          onDismiss={onDismiss}
        />
      ) : step.kind === "confirm" ? (
        <ConfirmBody
          plan={step.plan}
          mode={step.mode}
          running={step.running}
          error={step.error}
          target={target}
          collectionName={collectionName}
          onConfirm={() => void confirm()}
          onBack={() => setStep({ kind: "choose", plan: step.plan, mode: step.mode })}
        />
      ) : (
        <div className="flex flex-col gap-3">
          <div aria-live="polite">
            <InlineFeedback tone="success">
              <span>{resultSentence(step.moved, target.name)}</span>
            </InlineFeedback>
          </div>
          <p className={objectiveStyles.reassure}>{atTargetSentence(step.atTarget, step.total)}</p>
          <div className={objectiveStyles.reviewActions}>
            <Button variant="outline" className="min-h-11" onClick={onDismiss}>
              Concluir
            </Button>
          </div>
        </div>
      )}
    </section>
  );
}

function Counts({ plan }: { plan: OrganizePlan }) {
  const items = [
    { label: "Na coleção", value: plan.totalCount },
    { label: "Sem localização", value: plan.unlocatedCount },
    { label: "Já neste local", value: plan.atTargetCount },
    { label: "Em outros locais", value: plan.elsewhereCount },
  ];
  return (
    <dl className={styles.counts} aria-label="Exemplares desta coleção">
      {items.map((item) => (
        <div key={item.label} className={styles.count}>
          <dt className={styles.countLabel}>{item.label}</dt>
          <dd className={styles.countValue}>{formatCount(item.value)}</dd>
        </div>
      ))}
    </dl>
  );
}

function Destination({ target }: { target: OrganizeTarget }) {
  return (
    <p className={styles.destination}>
      <span className={styles.destinationLabel}>Destino</span>
      <span className={styles.destinationName}>{target.name}</span>
    </p>
  );
}

function ChooseBody({
  plan,
  mode,
  target,
  notice,
  onMode,
  onContinue,
  onDismiss,
}: {
  plan: OrganizePlan;
  mode: OrganizeMode | null;
  target: OrganizeTarget;
  notice: string | null;
  onMode: (mode: OrganizeMode) => void;
  onContinue: () => void;
  onDismiss: () => void;
}) {
  const groupName = useId();
  const options = modeOptions(plan);
  return (
    <div className={objectiveStyles.reviewBody}>
      {notice ? (
        <div role="status">
          <InlineFeedback tone="warning">{notice}</InlineFeedback>
        </div>
      ) : null}
      <Destination target={target} />
      <Counts plan={plan} />
      <fieldset className={`${objectiveStyles.choices} ${styles.modes}`}>
        <legend className={styles.modesLegend}>O que organizar</legend>
        {options.map((option) => {
          const checked = mode === option.mode;
          const leaving = leavingOtherPlaces(plan, option.mode);
          return (
            <label
              key={option.mode}
              className={objectiveStyles.choice}
              data-checked={checked || undefined}
              data-disabled={!option.available || undefined}
            >
              <input
                type="radio"
                name={groupName}
                value={option.mode}
                className={objectiveStyles.choiceInput}
                checked={checked}
                disabled={!option.available}
                onChange={() => onMode(option.mode)}
              />
              <span className={objectiveStyles.choiceMark} aria-hidden="true" />
              <span className={objectiveStyles.choiceText}>
                <span className={objectiveStyles.choiceTitle}>
                  {option.title}
                  {option.available ? <span className={styles.modeCount}>{exemplares(option.count)}</span> : null}
                </span>
                <span className={objectiveStyles.choiceSubtitle}>{option.available ? option.description : option.unavailableReason}</span>
                {option.available && leaving > 0 ? (
                  <span className={styles.leaving}>
                    {leaving === 1 ? "1 sairá de outro local" : `${formatCount(leaving)} sairão de outros locais`}
                  </span>
                ) : null}
              </span>
            </label>
          );
        })}
      </fieldset>
      {mode === null ? <p className={objectiveStyles.inlineHint}>Escolha o que organizar para continuar.</p> : null}
      <div className={objectiveStyles.reviewActions}>
        <Button className="min-h-11" onClick={onContinue} disabled={mode === null}>
          Continuar
        </Button>
        <Button variant="outline" className="min-h-11" onClick={onDismiss}>
          Agora não
        </Button>
      </div>
    </div>
  );
}

function ConfirmBody({
  plan,
  mode,
  running,
  error,
  target,
  collectionName,
  onConfirm,
  onBack,
}: {
  plan: OrganizePlan;
  mode: OrganizeMode;
  running: boolean;
  error: OrganizeFailure | null;
  target: OrganizeTarget;
  collectionName: string;
  onConfirm: () => void;
  onBack: () => void;
}) {
  const count = eligibleFor(plan, mode);
  const leaving = leavingSentence(leavingOtherPlaces(plan, mode));
  const option = modeOptions(plan).find((o) => o.mode === mode);
  const retry = error === "lock_busy";
  const blocked = error !== null && !retry;
  return (
    <div className={objectiveStyles.reviewBody}>
      <dl className={styles.summary}>
        <div className={styles.summaryRow}>
          <dt>Coleção</dt>
          <dd>{collectionName}</dd>
        </div>
        <div className={styles.summaryRow}>
          <dt>Destino</dt>
          <dd>{target.name}</dd>
        </div>
        <div className={styles.summaryRow}>
          <dt>O que organizar</dt>
          <dd>{option?.title}</dd>
        </div>
        <div className={styles.summaryRow}>
          <dt>Exemplares</dt>
          <dd className={styles.summaryStrong}>{formatCount(count)}</dd>
        </div>
      </dl>
      <p className={objectiveStyles.reviewLine}>{confirmationSentence(count, target.name)}</p>
      {leaving ? <p className={styles.leavingLine}>{leaving}</p> : null}
      <p className={objectiveStyles.reassure}>
        Isso altera a localização física registrada desses exemplares. Coleção, versão, idioma e condição não mudam.
      </p>
      <div aria-live="polite">{error ? <InlineFeedback tone="error">{organizeFailureMessage(error)}</InlineFeedback> : null}</div>
      <div className={objectiveStyles.reviewActions}>
        {blocked ? null : (
          <Button className="min-h-11" onClick={onConfirm} disabled={running} aria-disabled={running}>
            {running ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
            {running ? "Organizando…" : retry ? "Tentar novamente" : "Confirmar organização"}
          </Button>
        )}
        <Button variant="outline" className="min-h-11" onClick={onBack} disabled={running}>
          Voltar
        </Button>
      </div>
    </div>
  );
}

function InfoBody({ plan, notice, onDismiss }: { plan: OrganizePlan; notice: string | null; onDismiss: () => void }) {
  const verdict = planVerdict(plan);
  const text = verdict === "ready" ? limitNotice(plan.maxPerOperation) : verdictMessage(verdict, plan);
  return (
    <div className="flex flex-col gap-3">
      {notice ? (
        <div role="status">
          <InlineFeedback tone="warning">{notice}</InlineFeedback>
        </div>
      ) : null}
      <p className={objectiveStyles.reviewLine}>{text}</p>
      {verdict === "all_at_target" && plan.totalCount > 0 ? (
        <p className={objectiveStyles.reassure}>{atTargetSentence(plan.atTargetCount, plan.totalCount)}</p>
      ) : null}
      <div className={objectiveStyles.reviewActions}>
        <Button variant="outline" className="min-h-11" onClick={onDismiss}>
          Fechar
        </Button>
      </div>
    </div>
  );
}
