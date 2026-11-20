"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { editorApplyAutoArrange, editorPreviewAutoArrange } from "@/app/colecoes/compartilhada/[id]/fichario/actions";
import type { SharedBinderEditor } from "@/components/colecoes/sharing/shared-binder-editor";
import type { AutoArrangeFailure, AutoArrangeTarget } from "@/lib/colecoes/binder-auto-arrange";
import {
  ARRANGE_CLOSED,
  type ArrangeView,
  type LocalVersion,
  closePreview,
  finishPreview,
  isStale,
  startPreview,
} from "@/lib/colecoes/binder-auto-arrange-view";
import {
  type ApplyFlow,
  type ApplyOutcome,
  FLOW_IDLE,
  beginApply,
  failureFollowUp,
  finishApply,
  finishRevalidation,
  flowLocksWrites,
  isReviewValid,
  reviewablePreview,
  startReview,
  startRevalidation,
} from "@/lib/colecoes/binder-auto-arrange-flow";
import { editorArrangeDisablesEditing, editorArrangeFailureText, editorArrangeRechecksAccess } from "@/lib/colecoes/editor-binder-arrange";

/**
 * V1-13 · E2-3C — organização automática pelo EDITOR (5386), com o MESMO fluxo
 * e as MESMAS regras puras do titular (`binder-auto-arrange-view`/`-flow`):
 * prévia por ação explícita → "Posicionar cartas" (revisão) → "Confirmar e
 * posicionar" (única escrita, com o token da prévia) → resultado. Nenhuma
 * escrita é repetida sozinha: plano mudou, limite ou falha temporária só
 * releem a prévia; resultado incerto revalida por leitura e pede nova
 * confirmação explícita. Nada otimista: o fichário é relido depois.
 *
 * Diferença em relação ao titular: a prévia do EDITOR não tem `slot_id`, então
 * não há destaque dos bolsos na grade; as cartas por página vêm agregadas.
 */
export function useEditorArrange({
  editor,
  collectionId,
  target,
  available,
  layoutEpoch,
  syncAfter,
}: {
  editor: SharedBinderEditor;
  collectionId: string;
  /** Modalidade da coleção (Set padrão/Master Set = RESERVED; Pokédex = SPECIES); `null` = sem organização automática. */
  target: AutoArrangeTarget | null;
  /** Edição ligada e fichário sem prova de não exclusividade (E2-3A, D1). */
  available: boolean;
  /** Muda quando o fichário é relido por inteiro (páginas, espaços, organização). */
  layoutEpoch: number;
  /** Releitura autorizada da E2-3A (`renumbered` = posições podem ter mudado). */
  syncAfter: (renumbered: boolean) => Promise<void>;
}) {
  const localVersion = useMemo<LocalVersion>(() => ({ activity: editor.activity, layout: layoutEpoch }), [editor.activity, layoutEpoch]);
  const localVersionRef = useRef(localVersion);
  useEffect(() => {
    localVersionRef.current = localVersion;
  }, [localVersion]);
  const editorRef = useRef(editor);
  editorRef.current = editor;

  const viewRef = useRef<ArrangeView>(ARRANGE_CLOSED);
  const [view, setViewState] = useState<ArrangeView>(ARRANGE_CLOSED);
  const setView = useCallback((next: ArrangeView) => {
    viewRef.current = next;
    setViewState(next);
  }, []);
  const flowRef = useRef<ApplyFlow>(FLOW_IDLE);
  const [flow, setFlowState] = useState<ApplyFlow>(FLOW_IDLE);
  const setFlow = useCallback((next: ApplyFlow) => {
    flowRef.current = next;
    setFlowState(next);
  }, []);
  /** Cartas por página da leitura exibida (a 5386 não entrega bolsos). */
  const [perPage, setPerPage] = useState<{ seq: number; counts: Record<number, number> } | null>(null);
  /** Trava síncrona contra duplo clique. */
  const applyingRef = useRef(false);

  const enabled = available && target !== null;
  const open = view.status !== "closed";

  /** Recusa que tira a permissão: a edição desliga nesta tela (mesma regra da E2-1). */
  const absorb = useCallback((reason: AutoArrangeFailure, phase: "preview" | "apply") => {
    if (!editorArrangeDisablesEditing(reason)) return;
    const current = editorRef.current;
    current.loseAccess(editorArrangeRechecksAccess(reason));
    current.notify({ tone: "error", text: editorArrangeFailureText(reason, phase) });
  }, []);

  /** Leitura da prévia (5386, só leitura). Devolve o estado final dessa leitura. */
  const readPreview = useCallback(async (): Promise<ArrangeView> => {
    const started = startPreview(viewRef.current, localVersionRef.current);
    if (started.status !== "loading") return viewRef.current;
    setView(started);
    const outcome = await editorPreviewAutoArrange({ collectionId }).catch(() => ({ ok: false as const, reason: "uncertain" as const }));
    const finished = finishPreview(viewRef.current, started.seq, outcome.ok ? { ok: true, preview: outcome.preview } : outcome);
    if (outcome.ok && finished.status === "ready" && finished.seq === started.seq) setPerPage({ seq: started.seq, counts: outcome.perPage });
    setView(finished);
    if (!outcome.ok) absorb(outcome.reason, "preview");
    return finished;
  }, [absorb, collectionId, setView]);

  const close = useCallback(() => {
    if (viewRef.current.status === "closed") return;
    // Aplicando (ou conferindo um resultado incerto): o painel não fecha.
    if (applyingRef.current || flowLocksWrites(flowRef.current)) return;
    setFlow(FLOW_IDLE);
    setView(closePreview(viewRef.current));
  }, [setFlow, setView]);

  const toggle = useCallback(() => {
    if (!enabled) return;
    if (viewRef.current.status !== "closed") {
      close();
      return;
    }
    const current = editorRef.current;
    if (current.structuralBlocker) {
      current.notify({ tone: "info", text: current.structuralBlocker });
      return;
    }
    current.closeAvailable();
    setFlow(FLOW_IDLE);
    void readPreview();
  }, [close, enabled, readPreview, setFlow]);

  const refresh = useCallback(() => {
    if (applyingRef.current || flowLocksWrites(flowRef.current)) return;
    setFlow(FLOW_IDLE);
    void readPreview();
  }, [readPreview, setFlow]);

  const beginReview = useCallback(() => {
    if (editorRef.current.structuralBlocker) return; // o painel mostra o motivo
    const next = startReview(viewRef.current, localVersionRef.current);
    if (next) setFlow(next);
  }, [setFlow]);

  const cancelReview = useCallback(() => {
    if (flowRef.current.kind === "review") setFlow(FLOW_IDLE);
  }, [setFlow]);

  /** Revalidação SÓ LEITURA depois de falha: nunca grava e nunca confirma sozinha. */
  const revalidate = useCallback(
    async (failed: ApplyFlow) => {
      const started = startRevalidation(failed);
      if (started.kind !== "revalidating") return;
      setFlow(started);
      const fresh = await readPreview();
      setFlow(finishRevalidation(flowRef.current, fresh, localVersionRef.current));
    },
    [readPreview, setFlow],
  );

  /** "Confirmar e posicionar": UMA chamada (coleção + token da prévia), sem repetição. */
  const confirm = useCallback(async () => {
    if (applyingRef.current) return;
    const current = editorRef.current;
    const begun = beginApply(flowRef.current, viewRef.current, localVersionRef.current);
    if (!begun) return; // revisão inválida: prévia antiga, desatualizada ou bloqueada
    if (!current.beginStructural()) {
      if (current.structuralBlocker) current.notify({ tone: "info", text: current.structuralBlocker });
      return;
    }
    applyingRef.current = true;
    setFlow(begun.flow);
    try {
      const outcome: ApplyOutcome = await editorApplyAutoArrange({ collectionId, planToken: begun.planToken }).catch(() => ({
        ok: false as const,
        reason: "uncertain" as const,
        write: "unknown" as const,
      }));
      applyingRef.current = false;
      const next = finishApply(flowRef.current, begun.planToken, outcome);
      setFlow(next);
      if (next.kind === "done") {
        // Só inseriu posições (nada andou): a fixação aprendida continua valendo. Relê cabeçalho e páginas.
        if (next.result.outcome !== "NOTHING_TO_DO") {
          await syncAfter(false);
          if (current.availableOpen) current.retryAvailable();
        }
        return;
      }
      if (next.kind !== "failed") return;
      absorb(next.reason, "apply");
      if (editorArrangeDisablesEditing(next.reason)) return;
      // Resultado incerto: posições podem ter mudado — o que dependia delas deixa de valer. Relê o fichário
      // ANTES da revalidação, para a prévia revalidada já nascer com a versão local nova (não "desatualizada").
      if (next.write === "unknown") await syncAfter(true);
      if (failureFollowUp(next).read === "now") await revalidate(next);
    } finally {
      applyingRef.current = false;
      current.endStructural();
    }
  }, [absorb, collectionId, revalidate, setFlow, syncAfter]);

  /** 55P03 / 40P01 / 57014: nova tentativa controlada — começa SEMPRE por revalidação (leitura). */
  const retry = useCallback(() => {
    if (failureFollowUp(flowRef.current).read === "on_request") void revalidate(flowRef.current);
  }, [revalidate]);

  const stale = isStale(view, localVersion);
  const canReview = (flow.kind === "idle" || flow.kind === "review") && reviewablePreview(view, localVersion) !== null;
  const reviewValid = isReviewValid(flow, view, localVersion);
  const counts = perPage && view.status === "ready" && perPage.seq === view.seq ? perPage.counts : null;

  // Edição desligada (permissão, barreira, arquivada) ou fichário sem exclusividade: o painel fecha.
  useEffect(() => {
    if (!enabled && viewRef.current.status !== "closed" && !applyingRef.current) {
      setFlow(FLOW_IDLE);
      setView(closePreview(viewRef.current));
    }
  }, [enabled, setFlow, setView]);

  return {
    enabled,
    target,
    open,
    view,
    flow,
    stale,
    canReview,
    reviewValid,
    countOnPage: (page: number) => counts?.[page] ?? 0,
    describeFailure: editorArrangeFailureText,
    locked: applyingRef.current || flowLocksWrites(flow),
    toggle,
    close,
    refresh,
    beginReview,
    cancelReview,
    confirm: () => void confirm(),
    retry,
    /** Depois do sucesso o fichário já foi relido; "Atualizar a tela" só relê de novo (leitura). */
    refreshScreen: () => void syncAfter(false),
  };
}

export type EditorArrange = ReturnType<typeof useEditorArrange>;
