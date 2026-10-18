"use client";

import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { ArrowRight, Check, Loader2, Sparkles } from "lucide-react";
import {
  type ObjectiveChange,
  previewCollectionObjective,
  readCollectionObjective,
  saveCollectionObjective,
} from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  type CompletionObjective,
  type ObjectiveFailure,
  type ObjectivePlan,
  type ObjectivePreview,
  type ObjectiveState,
  initialSelection,
  objectiveFailureMessage,
  objectiveSubtitle,
  objectiveTitle,
  planObjectiveChange,
  positionsDelta,
  previewFinishIds,
  savedSelection,
  selectionOrigin,
  toggleFinish,
} from "@/lib/colecoes/master-set";
import styles from "./collection-objective.module.css";
import manageStyles from "./collection-manage.module.css";

/**
 * Ajustes → Objetivo (MASTER-SET-FRONTEND-PHASE-01).
 *
 * Fluxo: escolher Set padrão ou Master Set → (Master Set) marcar acabamentos →
 * "Revisar mudança" mostra a prévia do banco (5192) → "Confirmar" grava com
 * UMA chamada (5194/5195/5081). Contagens e regra das cartas secretas vêm só
 * do banco. Nada aqui move, apaga ou desvincula exemplar.
 */

type Load = { status: "loading" } | { status: "error"; reason: ObjectiveFailure } | { status: "ready"; state: ObjectiveState };

type Review =
  | { status: "idle" }
  | { status: "loading"; plan: ObjectivePlan }
  | { status: "ready"; plan: ObjectivePlan; preview: ObjectivePreview | null }
  | { status: "error"; plan: ObjectivePlan; reason: ObjectiveFailure };

type Done = { tone: "success" | "error"; text: string } | null;

export function CollectionObjectiveSection({
  collectionId,
  onBusyChange,
}: {
  collectionId: string;
  /** Bloqueia o fechamento do painel enquanto grava. */
  onBusyChange: (busy: boolean) => void;
}) {
  const router = useRouter();
  const groupName = useId();
  const reviewHeadingRef = useRef<HTMLHeadingElement>(null);
  const [load, setLoad] = useState<Load>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [target, setTarget] = useState<CompletionObjective>("STANDARD_SET");
  const [selection, setSelection] = useState<string[]>([]);
  const [review, setReview] = useState<Review>({ status: "idle" });
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<Done>(null);
  const [, startRefresh] = useTransition();

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  useEffect(() => {
    let alive = true;
    // Releitura depois de gravar mantém o conteúdo na tela (sem piscar).
    setLoad((current) => (current.status === "ready" ? current : { status: "loading" }));
    readCollectionObjective({ collectionId })
      .then((result) => {
        if (!alive) return;
        if (!result.ok) {
          setLoad({ status: "error", reason: result.reason });
          return;
        }
        const state: ObjectiveState = { policy: result.policy, finishes: result.finishes, secrets: result.secrets };
        setLoad({ status: "ready", state });
        setTarget(state.policy);
        setSelection(state.policy === "MASTER_SET" ? savedSelection(state.finishes) : initialSelection(state.finishes));
        setReview({ status: "idle" });
      })
      .catch(() => alive && setLoad({ status: "error", reason: "unavailable" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId]);

  useEffect(() => onBusyChange(saving), [saving, onBusyChange]);

  // Foco acompanha a revisão: vai para o título da prévia quando ela abre.
  useEffect(() => {
    if (review.status === "loading") reviewHeadingRef.current?.focus();
  }, [review.status]);

  if (load.status === "loading") {
    return (
      <Shell>
        <div className={styles.choices} aria-busy="true" aria-label="Carregando objetivo">
          <div className={manageStyles.skeleton} />
          <div className={manageStyles.skeleton} />
        </div>
      </Shell>
    );
  }

  if (load.status === "error") {
    return (
      <Shell>
        <div className="flex flex-col gap-3" role="alert">
          <InlineFeedback tone="error">
            {load.reason === "not_found" || load.reason === "not_authenticated"
              ? objectiveFailureMessage(load.reason)
              : "Não conseguimos carregar o objetivo agora. Nada foi alterado — tente novamente."}
          </InlineFeedback>
          <Button variant="outline" className="min-h-11 self-start" onClick={reload}>
            Tentar novamente
          </Button>
        </div>
      </Shell>
    );
  }

  const state = load.state;
  const hasFinishes = state.finishes.length > 0;
  const plan = planObjectiveChange(state, target, selection);
  const reviewing = review.status !== "idle";
  const locked = saving || reviewing;
  const origin = selectionOrigin(state.finishes);
  const savedCount = savedSelection(state.finishes).length;

  const choose = (next: CompletionObjective) => {
    if (locked) return;
    setTarget(next);
    setDone(null);
    // Reabrir o Master Set começa sempre pela seleção guardada (ou sugestão).
    if (next === "MASTER_SET" && state.policy === "STANDARD_SET") setSelection(initialSelection(state.finishes));
    if (next === "MASTER_SET" && state.policy === "MASTER_SET") setSelection(savedSelection(state.finishes));
  };

  // Opções desatualizadas: relê e devolve o colecionador à escolha, com o aviso.
  const handleFailure = (failedPlan: ObjectivePlan, reason: ObjectiveFailure) => {
    if (reason === "stale") {
      setReview({ status: "idle" });
      setDone({ tone: "error", text: objectiveFailureMessage(reason) });
      reload();
      return;
    }
    setReview({ status: "error", plan: failedPlan, reason });
  };

  const startReview = async () => {
    if (plan.kind === "none" || plan.kind === "invalid") return;
    setDone(null);
    setReview({ status: "loading", plan });
    const ids = previewFinishIds(plan, state) ?? (savedCount > 0 ? savedSelection(state.finishes) : null);
    if (!ids || ids.length === 0) {
      // Voltar ao padrão sem acabamentos guardados: não há o que prever além do texto.
      setReview({ status: "ready", plan, preview: null });
      return;
    }
    const result = await previewCollectionObjective({ collectionId, finishIds: ids }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    if (!result.ok) {
      handleFailure(plan, result.reason);
      return;
    }
    setReview({ status: "ready", plan, preview: result.preview });
  };

  const confirm = async () => {
    if (review.status !== "ready") return;
    const change = toChange(review.plan);
    if (!change) return;
    setSaving(true);
    const result = await saveCollectionObjective({ collectionId, change }).catch(() => ({ ok: false, reason: "unavailable" }) as const);
    setSaving(false);
    if (!result.ok) {
      handleFailure(review.plan, result.reason);
      return;
    }
    setReview({ status: "idle" });
    setDone({ tone: "success", text: successText(change, result.total, result.satisfied) });
    reload();
    startRefresh(() => router.refresh());
  };

  return (
    <Shell>
      <p className={manageStyles.note}>
        Defina o que conta para completar esta coleção. Mudar o objetivo nunca tira, move ou apaga cartas — só muda a
        forma de contar o progresso.
      </p>

      <fieldset className={styles.choices} disabled={locked}>
        <legend className="sr-only">Objetivo da coleção</legend>
        {(["STANDARD_SET", "MASTER_SET"] as const).map((objective) => {
          const unavailable = objective === "MASTER_SET" && !hasFinishes;
          return (
            <label key={objective} className={styles.choice} data-checked={target === objective || undefined} data-disabled={unavailable || undefined}>
              <input
                type="radio"
                name={groupName}
                className={styles.choiceInput}
                checked={target === objective}
                disabled={unavailable}
                onChange={() => choose(objective)}
              />
              <span className={styles.choiceMark} aria-hidden="true" />
              <span className={styles.choiceText}>
                <span className={styles.choiceTitle}>
                  {objectiveTitle(objective)}
                  {state.policy === objective ? <span className={styles.currentTag}>atual</span> : null}
                </span>
                <span className={styles.choiceSubtitle}>
                  {unavailable ? "este Set ainda não tem acabamentos no catálogo" : objectiveSubtitle(objective)}
                </span>
              </span>
            </label>
          );
        })}
      </fieldset>

      {target === "MASTER_SET" && hasFinishes ? (
        <fieldset className={styles.finishes} disabled={locked}>
          <legend className={styles.finishesLegend}>Acabamentos</legend>
          <p className={styles.finishesHint}>
            {state.policy === "STANDARD_SET" && origin === "saved"
              ? "Restauramos os acabamentos que você tinha escolhido. Ajuste se quiser."
              : state.policy === "STANDARD_SET"
                ? "Sugestão inicial — marque os acabamentos que você quer completar."
                : "Marque os acabamentos que fazem parte do seu objetivo."}
          </p>
          <ul className={styles.finishList}>
            {state.finishes.map((finish) => {
              const checked = selection.includes(finish.id);
              const pct = finish.positions > 0 ? Math.round((finish.ownedPositions / finish.positions) * 100) : 0;
              return (
                <li key={finish.id}>
                  <label className={styles.finish} data-checked={checked || undefined}>
                    <input
                      type="checkbox"
                      className={styles.finishInput}
                      checked={checked}
                      onChange={() => {
                        setSelection((current) => toggleFinish(current, finish.id, state.finishes));
                        setDone(null);
                      }}
                    />
                    <span className={styles.check} aria-hidden="true">
                      <Check className="h-3.5 w-3.5" strokeWidth={3} />
                    </span>
                    <span className={styles.finishBody}>
                      <span className={styles.finishName}>{finish.name}</span>
                      <span className={styles.finishMeta}>
                        {formatCount(finish.positions)} {finish.positions === 1 ? "carta" : "cartas"} · você tem{" "}
                        {formatCount(finish.ownedPositions)}
                      </span>
                      <span className={styles.meter} aria-hidden="true">
                        <span className={styles.meterFill} style={{ width: `${pct}%` }} />
                      </span>
                    </span>
                  </label>
                </li>
              );
            })}
          </ul>

          {state.secrets ? (
            <div className={styles.secrets}>
              <span className={styles.secretsIcon} aria-hidden="true">
                <Sparkles className="h-4 w-4" />
              </span>
              <span className={styles.finishBody}>
                <span className={styles.finishName}>
                  Cartas secretas <span className={styles.alwaysTag}>sempre no objetivo</span>
                </span>
                <span className={styles.finishMeta}>
                  {formatCount(state.secrets.positions)} {state.secrets.positions === 1 ? "carta" : "cartas"} · você tem{" "}
                  {formatCount(state.secrets.ownedPositions)}
                </span>
                <span className={styles.secretsNote}>
                  Cada secreta conta uma vez. Se ela não existir nos acabamentos marcados, qualquer exemplar dela vale.
                </span>
              </span>
            </div>
          ) : null}
        </fieldset>
      ) : null}

      <div aria-live="polite" className="flex flex-col gap-3">
        {done ? <InlineFeedback tone={done.tone}>{done.text}</InlineFeedback> : null}
        {!reviewing && plan.kind === "invalid" ? (
          <p className={styles.inlineHint}>
            {plan.reason === "empty_selection" ? "Marque pelo menos um acabamento para continuar." : "Escolha no máximo 64 acabamentos."}
          </p>
        ) : null}
      </div>

      {!reviewing ? (
        <Button
          className="min-h-11 self-start"
          disabled={plan.kind === "none" || plan.kind === "invalid"}
          onClick={() => void startReview()}
        >
          Revisar mudança
          <ArrowRight className="ml-1.5 h-4 w-4" aria-hidden="true" />
        </Button>
      ) : (
        <section className={styles.review} aria-labelledby={`${groupName}-review`} aria-busy={review.status === "loading"}>
          <h4 id={`${groupName}-review`} ref={reviewHeadingRef} tabIndex={-1} className={styles.reviewTitle}>
            {reviewTitle(review.plan)}
          </h4>

          {review.status === "loading" ? (
            <div className={styles.reviewLoading}>
              <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" />
              Calculando o impacto no progresso…
            </div>
          ) : review.status === "error" ? (
            <div className="flex flex-col gap-3" role="alert">
              <InlineFeedback tone="error">{objectiveFailureMessage(review.reason)}</InlineFeedback>
              <div className={styles.reviewActions}>
                <Button className="min-h-11" onClick={() => void startReview()}>
                  Tentar novamente
                </Button>
                <Button variant="outline" className="min-h-11" onClick={() => setReview({ status: "idle" })}>
                  Voltar
                </Button>
              </div>
            </div>
          ) : (
            <>
              <ReviewBody plan={review.plan} preview={review.preview} savedCount={savedCount} />
              <div className={styles.reviewActions}>
                <Button className="min-h-11" onClick={() => void confirm()} disabled={saving}>
                  {saving ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
                  {saving ? "Salvando…" : "Confirmar"}
                </Button>
                <Button variant="outline" className="min-h-11" onClick={() => setReview({ status: "idle" })} disabled={saving}>
                  Voltar
                </Button>
              </div>
            </>
          )}
        </section>
      )}
    </Shell>
  );
}

function Shell({ children }: { children: ReactNode }) {
  return (
    <section className={manageStyles.section} aria-labelledby="ajustes-objetivo">
      <h3 id="ajustes-objetivo" className={manageStyles.sectionTitle}>
        Objetivo
      </h3>
      {children}
    </section>
  );
}

function ReviewBody({ plan, preview, savedCount }: { plan: ObjectivePlan; preview: ObjectivePreview | null; savedCount: number }) {
  if (plan.kind === "to_standard") {
    return (
      <div className={styles.reviewBody}>
        {preview ? (
          <p className={styles.reviewLine}>
            Hoje no Master Set: <strong>{formatCount(preview.currentSatisfied)}</strong> de {formatCount(preview.currentTotal)} posições.
          </p>
        ) : null}
        <p className={styles.reviewLine}>
          O progresso volta a contar <strong>uma de cada carta</strong> do Set.
        </p>
        {savedCount > 0 ? (
          <p className={styles.reviewLine}>
            Seus {savedCount === 1 ? "acabamento fica guardado" : `${savedCount} acabamentos ficam guardados`} para quando você quiser voltar ao
            Master Set.
          </p>
        ) : null}
        <Reassurance />
      </div>
    );
  }
  if (!preview) return <Reassurance />;
  const added = positionsDelta(preview.positionsAdded, "+");
  const removed = positionsDelta(preview.positionsRemoved, "−");
  return (
    <div className={styles.reviewBody}>
      <div className={styles.compare}>
        <div className={styles.compareCell}>
          <span className={styles.compareLabel}>Hoje · {objectiveTitle(preview.currentPolicy)}</span>
          <span className={styles.compareValue}>
            {formatCount(preview.currentSatisfied)} <span className={styles.compareOf}>de {formatCount(preview.currentTotal)}</span>
          </span>
        </div>
        <ArrowRight className={styles.compareArrow} aria-hidden="true" />
        <div className={styles.compareCell} data-next>
          <span className={styles.compareLabel}>Depois · Master Set</span>
          <span className={styles.compareValue}>
            {formatCount(preview.proposedSatisfied)} <span className={styles.compareOf}>de {formatCount(preview.proposedTotal)}</span>
          </span>
        </div>
      </div>
      {added || removed ? (
        <p className={styles.deltas}>
          {added ? <span className={styles.deltaUp}>{added}</span> : null}
          {removed ? <span className={styles.deltaDown}>{removed}</span> : null}
          <span className={styles.deltaNote}>em relação ao Master Set de hoje</span>
        </p>
      ) : null}
      {preview.proposedSecretPositions > 0 ? (
        <p className={styles.reviewLine}>
          {preview.proposedSecretPositions === 1
            ? "1 carta secreta entra como posição própria (fora dos acabamentos marcados)."
            : `${formatCount(preview.proposedSecretPositions)} cartas secretas entram como posição própria (fora dos acabamentos marcados).`}
        </p>
      ) : null}
      {preview.copiesOutsideAfter > 0 ? (
        <p className={styles.reviewLine}>
          {preview.copiesOutsideAfter === 1
            ? "1 exemplar continua na coleção sem contar para este objetivo."
            : `${formatCount(preview.copiesOutsideAfter)} exemplares continuam na coleção sem contar para este objetivo.`}
        </p>
      ) : null}
      <Reassurance />
    </div>
  );
}

function Reassurance() {
  return <p className={styles.reassure}>Nenhuma carta sai da coleção, muda de lugar ou é apagada.</p>;
}

function reviewTitle(plan: ObjectivePlan): string {
  if (plan.kind === "to_standard") return "Voltar ao Set padrão";
  if (plan.kind === "activate") return plan.finishIds === null ? "Reativar o Master Set" : "Ativar o Master Set";
  return "Atualizar acabamentos";
}

function toChange(plan: ObjectivePlan): ObjectiveChange | null {
  if (plan.kind === "to_standard") return { kind: "to_standard" };
  if (plan.kind === "activate") return { kind: "activate", finishIds: plan.finishIds };
  if (plan.kind === "replace") return { kind: "replace", finishIds: plan.finishIds };
  return null;
}

function successText(change: ObjectiveChange, total: number | null, satisfied: number | null): string {
  const progress = total !== null && satisfied !== null ? ` ${formatCount(satisfied)} de ${formatCount(total)} posições.` : "";
  if (change.kind === "to_standard") return "Pronto: a coleção voltou ao Set padrão. Seus acabamentos ficaram guardados.";
  if (change.kind === "activate") {
    return change.finishIds === null
      ? `Master Set reativado com os acabamentos que você tinha escolhido.${progress}`
      : `Master Set ativado.${progress}`;
  }
  return `Acabamentos atualizados.${progress}`;
}
