"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { ChevronDown, Clock3, Eye, HelpCircle, RefreshCw } from "lucide-react";
import { readBinderValue } from "@/app/colecoes/colecoes/[id]/fichario/actions";
import {
  BINDER_VALUE_METHOD,
  BINDER_VALUE_NOTE,
  type BinderValueCacheEntry,
  type BinderValueSummary,
  binderValueCoveragePercent,
  binderValueCoverageText,
  binderValueNeedsRead,
  binderValueNotices,
  binderValueObservedText,
  binderValueTotalText,
} from "@/lib/colecoes/binder-value";
import { cn } from "@/lib/utils";
import styles from "./binder-control.module.css";

/**
 * Resultado por coleção, guardado fora do componente: fechar e reabrir o painel
 * (ou a seção) reaproveita o valor enquanto o conjunto de cartas nos bolsos for
 * o mesmo e a leitura for recente (D4). Só na memória desta aba.
 */
const valueCache = new Map<string, BinderValueCacheEntry>();

type ViewState =
  | { status: "loading"; previous: BinderValueSummary | null }
  | { status: "ready"; summary: BinderValueSummary }
  | { status: "unavailable" }
  | { status: "error" };

/**
 * "Valor do Fichário" (BINDER-VALUE, 05d v2.74, D1–D9) no Centro de Controle.
 *
 * - Só existe no espaço do titular (proprietária ou convidada, mesmo dono); o
 *   fichário compartilhado com terceiros e a vitrine pública não montam este
 *   componente (D6). O servidor confere a titularidade de novo.
 * - Lê sob demanda: só com a seção aberta e com "Exibir preços" ligado; sem
 *   polling, sem leitura por renderização (D4).
 * - `setKey` muda quando uma escrita pode ter mudado o conjunto de cartas nos
 *   bolsos: o resultado anterior é descartado (consistência acima de economia);
 *   reorganizações que só movem cartas não mudam a chave.
 * - Respostas antigas nunca sobrescrevem a mais recente (contador de leituras).
 */
export function BinderValueSection({
  collectionId,
  setKey,
  enabled,
  onShowPrices,
}: {
  collectionId: string;
  /** Conjunto de cartas nos bolsos (ver `binderValueSetKey`). */
  setKey: string;
  /** "Exibir preços" ligado e preferência já lida. Desligado: nada é lido. */
  enabled: boolean;
  onShowPrices?: () => void;
}) {
  const [view, setView] = useState<ViewState>(() => {
    const entry = valueCache.get(collectionId);
    return entry && !binderValueNeedsRead(entry, setKey, Date.now()) ? { status: "ready", summary: entry.summary } : { status: "loading", previous: null };
  });
  const requestRef = useRef(0);

  const load = useCallback(
    async (keep: BinderValueSummary | null) => {
      const request = ++requestRef.current;
      setView({ status: "loading", previous: keep });
      const result = await readBinderValue({ collectionId }).catch(() => ({ ok: false as const, reason: "error" as const }));
      if (request !== requestRef.current) return; // outra leitura (ou a desmontagem) veio depois
      if (result.ok) {
        valueCache.set(collectionId, { setKey, readAt: Date.now(), summary: result.summary });
        setView({ status: "ready", summary: result.summary });
      } else {
        valueCache.delete(collectionId);
        setView(result.reason === "error" ? { status: "error" } : { status: "unavailable" });
      }
    },
    [collectionId, setKey],
  );

  useEffect(() => {
    if (!enabled) {
      requestRef.current += 1; // descarta leitura em curso
      return;
    }
    const entry = valueCache.get(collectionId);
    if (entry && !binderValueNeedsRead(entry, setKey, Date.now())) {
      setView({ status: "ready", summary: entry.summary });
      return;
    }
    // Mesmo conjunto, só a referência envelheceu: mantém o valor à vista enquanto relê.
    void load(entry && entry.setKey === setKey ? entry.summary : null);
  }, [enabled, collectionId, setKey, load]);

  useEffect(
    () => () => {
      requestRef.current += 1;
    },
    [],
  );

  if (!enabled) {
    return (
      <div className={styles.valueCard} data-tone="muted">
        <p className={styles.valueEyebrow}>Valor estimado</p>
        <p className={styles.valueHidden}>Preços ocultos</p>
        <p className={styles.hint}>O valor aparece com &ldquo;Exibir preços&rdquo; ligado. Nada é lido enquanto os preços estiverem ocultos.</p>
        {onShowPrices ? (
          <button type="button" className={cn(styles.linkButton, "mt-2")} onClick={onShowPrices}>
            <Eye aria-hidden />
            Mostrar preços
          </button>
        ) : null}
      </div>
    );
  }

  if (view.status === "loading" && view.previous === null) {
    return (
      <div className={styles.valueCard} aria-busy="true" aria-label="Calculando o valor do fichário">
        <div className={styles.skeleton} style={{ width: "38%" }} />
        <div className={cn(styles.skeleton, styles.valueSkeletonAmount)} style={{ width: "62%" }} />
        <div className={styles.skeleton} style={{ width: "100%" }} />
        <div className={styles.skeleton} style={{ width: "48%" }} />
      </div>
    );
  }

  if (view.status === "error") {
    return (
      <div className={styles.valueCard} role="alert">
        <p className={styles.valueEyebrow}>Valor estimado</p>
        <p className={styles.hint}>
          Não foi possível calcular o valor agora.{" "}
          <button type="button" className="font-semibold text-foreground underline underline-offset-2" onClick={() => void load(null)}>
            Tentar novamente
          </button>
        </p>
      </div>
    );
  }

  if (view.status === "unavailable") {
    return (
      <div className={styles.valueCard}>
        <p className={styles.valueEyebrow}>Valor estimado</p>
        <p className={styles.hint}>O valor deste fichário não está disponível.</p>
      </div>
    );
  }

  const summary = view.status === "ready" ? view.summary : view.previous;
  if (!summary) return null;
  return <ValueCard summary={summary} refreshing={view.status === "loading"} onRefresh={() => void load(summary)} />;
}

function ValueCard({ summary, refreshing, onRefresh }: { summary: BinderValueSummary; refreshing: boolean; onRefresh: () => void }) {
  const titleId = useId();
  if (summary.state === "empty") {
    return (
      <div className={styles.valueCard} aria-live="polite">
        <p className={styles.valueEyebrow}>Valor estimado</p>
        <p className={styles.valueHidden}>Nenhuma carta nos bolsos</p>
        <p className={styles.hint}>Coloque cartas nos bolsos para ver o valor estimado do fichário.</p>
      </div>
    );
  }
  const noValue = summary.totalCents === null;
  const percent = binderValueCoveragePercent(summary);
  const observed = binderValueObservedText(summary);
  const notices = binderValueNotices(summary);
  return (
    <section className={styles.valueCard} aria-labelledby={titleId} aria-busy={refreshing || undefined}>
      <div className={styles.valueHead}>
        <p id={titleId} className={styles.valueEyebrow}>
          Valor estimado
        </p>
        <span className={styles.tag}>Referência NM</span>
        <button
          type="button"
          className={styles.valueRefresh}
          onClick={onRefresh}
          disabled={refreshing}
          aria-label="Atualizar o valor do fichário"
          title="Atualizar"
        >
          <RefreshCw aria-hidden data-spin={refreshing || undefined} />
        </button>
      </div>
      <p className={styles.valueAmount} data-muted={noValue || undefined} aria-live="polite">
        {binderValueTotalText(summary)}
        {summary.provisional && !noValue ? <span className={styles.valueFlag}>parcial</span> : null}
        {!summary.complete ? <span className={styles.valueFlag} data-tone="warning">não definitivo</span> : null}
      </p>

      <div className={styles.valueCoverage}>
        <div className={styles.meterHead}>
          <span className={styles.factLabel}>Cobertura</span>
          <span className={styles.valueCoverageText}>{binderValueCoverageText(summary)}</span>
        </div>
        <div
          className={styles.track}
          role="meter"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={percent}
          aria-label={`Cobertura de preços: ${binderValueCoverageText(summary)}`}
        >
          <div className={styles.fill} style={{ transform: `scaleX(${percent / 100})` }} />
        </div>
      </div>

      {observed ? (
        <p className={styles.valueObserved}>
          <Clock3 aria-hidden />
          {observed}
        </p>
      ) : null}

      {notices.length > 0 ? (
        <ul className={styles.valueNotices}>
          {notices.map((text) => (
            <li key={text}>{text}</li>
          ))}
        </ul>
      ) : null}

      {/* Explicações sob demanda: valor, cobertura, data e alertas ficam sempre à vista; o método fica num detalhe discreto. */}
      <details className={styles.valueHelp}>
        <summary>
          <HelpCircle aria-hidden />
          Como o valor é calculado
          <ChevronDown className={styles.valueHelpChevron} aria-hidden />
        </summary>
        <p>{BINDER_VALUE_NOTE}</p>
        <p>{BINDER_VALUE_METHOD}</p>
      </details>
    </section>
  );
}
