"use client";

import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useId, useRef, useState, useTransition } from "react";
import { ArrowRight, Check, Loader2 } from "lucide-react";
import { readPokedexGenerations, savePokedexGenerations } from "@/app/colecoes/colecoes/actions";
import { Button } from "@/components/ui/button";
import { InlineFeedback } from "@/components/ui/feedback";
import { formatCount } from "@/lib/colecoes/acervo";
import {
  type GenerationOption,
  type GenerationPlan,
  type PokedexFailure,
  POKEDEX_COLLECTION_ENABLED,
  currentSelection,
  generationLine,
  generationRange,
  generationTitle,
  planGenerationChange,
  pokedexFailureMessage,
  selectionLabel,
  speciesInSelection,
  toggleGeneration,
} from "@/lib/colecoes/pokedex";
import styles from "./collection-objective.module.css";
import manageStyles from "./collection-manage.module.css";
import pkxStyles from "./pokedex.module.css";

/**
 * Lista de gerações da Pokédex Nacional (PKX-02) — mesma linguagem visual e de
 * interação dos acabamentos do Master Set (checkbox nativo invisível, marca
 * dourada só no item escolhido). Usada na criação e em Ajustes.
 */
export function GenerationChecklist({
  options,
  selection,
  onChange,
  disabled = false,
  showProgress = false,
  legend,
  hint,
}: {
  options: readonly GenerationOption[];
  selection: readonly string[];
  onChange: (next: string[]) => void;
  disabled?: boolean;
  /** Ajustes: conquistadas por geração (5201 com coleção). */
  showProgress?: boolean;
  legend: string;
  hint?: ReactNode;
}) {
  const all = selection.length === options.length;
  const species = speciesInSelection(selection, options);
  return (
    <fieldset className={styles.finishes} disabled={disabled}>
      <legend className={styles.finishesLegend}>{legend}</legend>
      {hint ? <p className={styles.finishesHint}>{hint}</p> : null}
      <div className={pkxStyles.checklistBar}>
        <p className={pkxStyles.checklistSum} aria-live="polite">
          <strong>{formatCount(species)}</strong> Pokémon ·{" "}
          {selection.length === 1 ? "1 geração" : `${formatCount(selection.length)} gerações`}
        </p>
        <button
          type="button"
          className={pkxStyles.textAction}
          onClick={() => onChange(all ? [] : options.map((option) => option.code))}
          disabled={disabled}
        >
          {all ? "Desmarcar todas" : "Marcar todas"}
        </button>
      </div>
      <ul className={`${styles.finishList} ${pkxStyles.genList}`}>
        {options.map((option) => {
          const checked = selection.includes(option.code);
          const satisfied = option.satisfied ?? 0;
          const pct = option.speciesCount > 0 ? Math.round((satisfied / option.speciesCount) * 100) : 0;
          return (
            <li key={option.code}>
              <label className={`${styles.finish} ${pkxStyles.genRow}`} data-checked={checked || undefined}>
                <input
                  type="checkbox"
                  className={styles.finishInput}
                  checked={checked}
                  aria-label={`${generationLine(option)}, ${generationRange(option)}${showProgress ? `, você tem ${formatCount(satisfied)}` : ""}`}
                  onChange={() => onChange(toggleGeneration(selection, option.code, options))}
                />
                <span className={styles.check} aria-hidden="true">
                  <Check className="h-3.5 w-3.5" strokeWidth={3} />
                </span>
                <span className={styles.finishBody} aria-hidden="true">
                  <span className={pkxStyles.genRowHead}>
                    <span className={pkxStyles.genRowName}>
                      <strong>{generationTitle(option.code)}</strong>
                      {option.region ? <span className={pkxStyles.genRowRegion}> · {option.region}</span> : null}
                    </span>
                    <span className={pkxStyles.genRowCount}>
                      {formatCount(option.speciesCount)} Pokémon
                    </span>
                  </span>
                  <span className={styles.finishMeta}>
                    {generationRange(option)}
                    {showProgress ? ` · você tem ${formatCount(satisfied)}` : null}
                  </span>
                  {showProgress ? (
                    <span className={styles.meter} aria-hidden="true">
                      <span className={styles.meterFill} style={{ width: `${pct}%` }} />
                    </span>
                  ) : null}
                </span>
              </label>
            </li>
          );
        })}
      </ul>
    </fieldset>
  );
}

// ---------------------------------------------------------------------------
// Ajustes → Gerações (5201 + 5203)
// ---------------------------------------------------------------------------

type Load = { status: "loading" } | { status: "error"; reason: PokedexFailure } | { status: "ready"; options: GenerationOption[] };

type Review = { status: "idle" } | { status: "ready"; plan: Extract<GenerationPlan, { kind: "change" }> } | { status: "error"; reason: PokedexFailure };

/**
 * Fluxo (mesmo do Objetivo do Master Set): marcar/desmarcar → "Revisar
 * mudança" mostra a prévia (gerações que entram e saem, total antes e
 * depois, a partir das contagens da 5201) → "Confirmar" grava com UMA chamada
 * à 5203, que devolve o progresso real. Nada aqui move, apaga ou desvincula
 * exemplar; gerações novas no catálogo nunca entram sozinhas.
 */
export function PokedexGenerationsSection({
  collectionId,
  onBusyChange,
}: {
  collectionId: string;
  onBusyChange: (busy: boolean) => void;
}) {
  const router = useRouter();
  const reviewId = useId();
  const reviewHeadingRef = useRef<HTMLHeadingElement>(null);
  const [load, setLoad] = useState<Load>({ status: "loading" });
  const [attempt, setAttempt] = useState(0);
  const [selection, setSelection] = useState<string[]>([]);
  const [review, setReview] = useState<Review>({ status: "idle" });
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<{ tone: "success" | "error"; text: string } | null>(null);
  const [, startRefresh] = useTransition();

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  useEffect(() => {
    let alive = true;
    setLoad((current) => (current.status === "ready" ? current : { status: "loading" }));
    readPokedexGenerations({ collectionId })
      .then((result) => {
        if (!alive) return;
        if (!result.ok) {
          setLoad({ status: "error", reason: result.reason });
          return;
        }
        setLoad({ status: "ready", options: result.options });
        setSelection(currentSelection(result.options));
        setReview({ status: "idle" });
      })
      .catch(() => alive && setLoad({ status: "error", reason: "unavailable" }));
    return () => {
      alive = false;
    };
  }, [attempt, collectionId]);

  useEffect(() => onBusyChange(saving), [saving, onBusyChange]);

  useEffect(() => {
    if (review.status === "ready") reviewHeadingRef.current?.focus();
  }, [review.status]);

  if (load.status === "loading") {
    return (
      <Shell>
        <div className={styles.finishList} aria-busy="true" aria-label="Carregando gerações">
          <div className={manageStyles.skeleton} />
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
              ? pokedexFailureMessage(load.reason)
              : "Não conseguimos carregar as gerações agora. Nada foi alterado — tente novamente."}
          </InlineFeedback>
          <Button variant="outline" className="min-h-11 self-start" onClick={reload}>
            Tentar novamente
          </Button>
        </div>
      </Shell>
    );
  }

  const options = load.options;
  const current = currentSelection(options);
  const plan = planGenerationChange(options, selection);
  const reviewing = review.status !== "idle";
  const editable = POKEDEX_COLLECTION_ENABLED;

  const startReview = () => {
    if (plan.kind !== "change") return;
    setDone(null);
    setReview({ status: "ready", plan });
  };

  const confirm = async () => {
    if (review.status !== "ready") return;
    setSaving(true);
    const result = await savePokedexGenerations({ collectionId, generationCodes: review.plan.codes }).catch(
      () => ({ ok: false, reason: "unavailable" }) as const,
    );
    setSaving(false);
    if (!result.ok) {
      if (result.reason === "generation_unavailable") {
        // Catálogo mudou: relê as opções e devolve à escolha, com o aviso.
        setReview({ status: "idle" });
        setDone({ tone: "error", text: pokedexFailureMessage(result.reason) });
        reload();
        return;
      }
      setReview({ status: "error", reason: result.reason });
      return;
    }
    setReview({ status: "idle" });
    setDone({
      tone: "success",
      text: result.changed
        ? `Gerações atualizadas: ${formatCount(result.satisfied)} de ${formatCount(result.total)} Pokémon conquistados. Nenhuma carta saiu da coleção.`
        : "As gerações já eram essas — nada precisou mudar.",
    });
    reload();
    startRefresh(() => router.refresh());
  };

  return (
    <Shell>
      <p className={manageStyles.note}>
        Hoje: <strong>{selectionLabel(current, options)}</strong>. Incluir ou remover gerações só muda o que conta para o
        progresso — nenhuma carta sai da coleção, muda de lugar ou é apagada. Gerações novas no catálogo aparecem aqui,
        mas só entram se você marcar.
      </p>

      {editable ? (
        <GenerationChecklist
          options={options}
          selection={selection}
          onChange={(next) => {
            setSelection(next);
            setDone(null);
          }}
          disabled={saving || reviewing}
          showProgress
          legend="Gerações no objetivo"
        />
      ) : (
        <ul className={styles.finishList} aria-label="Gerações no objetivo">
          {options
            .filter((option) => option.selected)
            .map((option) => (
              <li key={option.code} className={styles.finishMeta}>
                {generationTitle(option.code)} · {formatCount(option.satisfied ?? 0)} de {formatCount(option.speciesCount)}
              </li>
            ))}
        </ul>
      )}

      <div aria-live="polite" className="flex flex-col gap-3">
        {done ? <InlineFeedback tone={done.tone}>{done.text}</InlineFeedback> : null}
        {editable && !reviewing && plan.kind === "invalid" ? (
          <p className={styles.inlineHint}>Marque pelo menos uma geração para continuar.</p>
        ) : null}
      </div>

      {!editable ? null : !reviewing ? (
        <Button className="min-h-11 self-start" disabled={plan.kind !== "change"} onClick={startReview}>
          Revisar mudança
          <ArrowRight className="ml-1.5 h-4 w-4" aria-hidden="true" />
        </Button>
      ) : review.status === "error" ? (
        <section className={styles.review} role="alert">
          <InlineFeedback tone="error">{pokedexFailureMessage(review.reason)}</InlineFeedback>
          <div className={styles.reviewActions}>
            <Button className="min-h-11" onClick={startReview} disabled={plan.kind !== "change"}>
              Revisar de novo
            </Button>
            <Button variant="outline" className="min-h-11" onClick={() => setReview({ status: "idle" })}>
              Voltar
            </Button>
          </div>
        </section>
      ) : (
        <section className={styles.review} aria-labelledby={reviewId}>
          <h4 id={reviewId} ref={reviewHeadingRef} tabIndex={-1} className={styles.reviewTitle}>
            Atualizar gerações
          </h4>
          <div className={styles.reviewBody}>
            <div className={styles.compare}>
              <div className={styles.compareCell}>
                <span className={styles.compareLabel}>Hoje</span>
                <span className={styles.compareValue}>
                  {formatCount(review.plan.preview.currentSatisfied)}{" "}
                  <span className={styles.compareOf}>de {formatCount(review.plan.preview.currentTotal)}</span>
                </span>
              </div>
              <ArrowRight className={styles.compareArrow} aria-hidden="true" />
              <div className={styles.compareCell} data-next>
                <span className={styles.compareLabel}>Depois</span>
                <span className={styles.compareValue}>
                  {formatCount(review.plan.preview.nextSatisfied)}{" "}
                  <span className={styles.compareOf}>de {formatCount(review.plan.preview.nextTotal)}</span>
                </span>
              </div>
            </div>
            {review.plan.added.length > 0 ? (
              <p className={styles.reviewLine}>
                Entram: <strong>{review.plan.added.map((option) => generationTitle(option.code)).join(", ")}</strong>
              </p>
            ) : null}
            {review.plan.removed.length > 0 ? (
              <p className={styles.reviewLine}>
                Saem do objetivo: <strong>{review.plan.removed.map((option) => generationTitle(option.code)).join(", ")}</strong>. As
                cartas desses Pokémon continuam na coleção e voltam a contar se a geração voltar.
              </p>
            ) : null}
            <p className={styles.reassure}>Nenhuma carta sai da coleção, muda de lugar ou é apagada.</p>
          </div>
          <div className={styles.reviewActions}>
            <Button className="min-h-11" onClick={() => void confirm()} disabled={saving} aria-busy={saving}>
              {saving ? <Loader2 className="mr-1.5 h-4 w-4 animate-spin" aria-hidden="true" /> : null}
              {saving ? "Salvando…" : "Confirmar"}
            </Button>
            <Button variant="outline" className="min-h-11" onClick={() => setReview({ status: "idle" })} disabled={saving}>
              Voltar
            </Button>
          </div>
        </section>
      )}
    </Shell>
  );
}

function Shell({ children }: { children: ReactNode }) {
  return (
    <section className={manageStyles.section} aria-labelledby="ajustes-geracoes">
      <h3 id="ajustes-geracoes" className={manageStyles.sectionTitle}>
        Gerações
      </h3>
      {children}
    </section>
  );
}
