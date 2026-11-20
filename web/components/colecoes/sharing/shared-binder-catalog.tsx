"use client";

import { useCallback, useMemo, useRef, useState } from "react";
import { editorApplyCatalog, editorPreviewCatalog, readEditorCatalogNovelties } from "@/app/colecoes/compartilhada/[id]/fichario/actions";
import type { CatalogDialogSource } from "@/components/colecoes/fichario/binder-catalog-dialog";
import type { SharedBinderEditor } from "@/components/colecoes/sharing/shared-binder-editor";
import { type CatalogApplyResult, type CatalogNoveltyState, applyResultMessage, ineligibleMessage } from "@/lib/colecoes/binder-catalog";
import { catalogApplyShifted, catalogOutcomeUncertain, editorCatalogFailureMessage } from "@/lib/colecoes/editor-binder-catalog";

type Fail = { ok: false; reason: Parameters<typeof catalogOutcomeUncertain>[0]; message: string; disables: boolean; recheck: boolean };

/**
 * V1-13 · E2-3D — novidades do Catálogo pelo EDITOR (5387), só Master Set.
 *
 * Sob demanda: nada é lido ao abrir o fichário. "Novidades do Catálogo" lê a
 * lista (prévia sem seleção + nomes da 5323) e abre o MESMO diálogo do
 * titular, com a fonte do EDITOR: seleção → prévia da seleção → confirmações
 * de outra página/página nova → uma incorporação com o token. Nada otimista;
 * plano mudou → o diálogo relê a lista e a prévia (nova confirmação);
 * resultado incerto → releitura do fichário, posições tratadas como alteradas,
 * nenhuma repetição.
 */
export function useEditorCatalog({
  editor,
  collectionId,
  available,
  syncAfter,
}: {
  editor: SharedBinderEditor;
  collectionId: string;
  /** Edição ligada, fichário sem prova de não exclusividade e coleção Master Set. */
  available: boolean;
  syncAfter: (renumbered: boolean) => Promise<void>;
}) {
  const [state, setState] = useState<Extract<CatalogNoveltyState, { eligible: true }> | null>(null);
  const [loading, setLoading] = useState(false);
  const editorRef = useRef(editor);
  editorRef.current = editor;

  /** Recusa que tira a permissão: a edição desliga nesta tela e o diálogo fecha. */
  const absorb = useCallback((fail: Fail) => {
    if (!fail.disables) return;
    setState(null);
    editorRef.current.loseAccess(fail.recheck);
    editorRef.current.notify({ tone: "error", text: fail.message });
  }, []);

  const open = useCallback(async () => {
    if (!available || loading) return;
    const current = editorRef.current;
    if (current.structuralBlocker) {
      current.notify({ tone: "info", text: current.structuralBlocker });
      return;
    }
    setLoading(true);
    current.notify({ tone: "info", text: "Procurando novidades do Catálogo…" });
    const r = await readEditorCatalogNovelties({ collectionId }).catch(() => null);
    setLoading(false);
    if (!r) {
      current.notify({ tone: "error", text: editorCatalogFailureMessage("unknown") });
      return;
    }
    if (!r.ok) {
      absorb(r);
      if (!r.disables) current.notify({ tone: "error", text: r.message });
      return;
    }
    if (!r.state.eligible) {
      current.notify({ tone: "info", text: ineligibleMessage(null) });
      return;
    }
    if (r.state.count === 0) {
      current.notify({ tone: "info", text: "Não há novidades do Catálogo pendentes neste fichário." });
      return;
    }
    current.notify(null);
    setState(r.state);
  }, [absorb, available, collectionId, loading]);

  const source = useMemo<CatalogDialogSource>(
    () => ({
      readList: async () => {
        const r = await readEditorCatalogNovelties({ collectionId }).catch(() => null);
        if (!r) return { ok: false, reason: "unknown", message: editorCatalogFailureMessage("unknown") };
        if (!r.ok) absorb(r);
        return r;
      },
      preview: async (keys) => {
        const r = await editorPreviewCatalog({ collectionId, keys }).catch(() => null);
        if (!r) return { ok: false, reason: "unknown", message: editorCatalogFailureMessage("unknown") };
        if (!r.ok) absorb(r);
        return r;
      },
      apply: async (input) => {
        const current = editorRef.current;
        if (!current.beginStructural()) {
          return { ok: false, reason: "lock_busy", message: current.structuralBlocker ?? "Aguarde a alteração em andamento terminar." };
        }
        try {
          // Uma única escrita por confirmação.
          const r = await editorApplyCatalog({ collectionId, ...input }).catch(() => null);
          if (!r) {
            await syncAfter(true);
            return { ok: false, reason: "unknown", message: editorCatalogFailureMessage("unknown") };
          }
          if (!r.ok) {
            // Recusas do banco desfazem a transação (nada andou); só o resultado incerto pode ter mexido nas posições.
            if (catalogOutcomeUncertain(r.reason)) await syncAfter(true);
            absorb(r);
            return r;
          }
          if (r.result.outcome !== "NOTHING_TO_DO") await syncAfter(r.result.outcome === "APPLIED" && catalogApplyShifted(r.result));
          return r;
        } finally {
          current.endStructural();
        }
      },
    }),
    [absorb, collectionId, syncAfter],
  );

  return {
    available,
    loading,
    state,
    source,
    open: () => void open(),
    close: () => setState(null),
    /** Lista relida pelo diálogo: sem novidade pendente (ou inelegível), o diálogo fecha. */
    onStateChange: (next: CatalogNoveltyState) => setState(next.eligible && next.count > 0 ? next : null),
    /** O fichário já foi relido dentro da incorporação; aqui só a mensagem e o fechamento. */
    onApplied: (result: CatalogApplyResult) => {
      setState(null);
      editorRef.current.notify({ tone: "success", text: applyResultMessage(result) });
    },
  };
}

export type EditorCatalog = ReturnType<typeof useEditorCatalog>;
