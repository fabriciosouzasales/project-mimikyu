"use client";

import { useCallback, useRef, useState } from "react";
import { editorCloseGap, editorInsertGap, editorPreviewGap } from "@/app/colecoes/compartilhada/[id]/fichario/actions";
import type { GapDialogState } from "@/components/colecoes/fichario/binder-layout-tools";
import type { SharedBinderEditor } from "@/components/colecoes/sharing/shared-binder-editor";
import type { BinderSlot } from "@/lib/colecoes/binder";
import type { GapPreview } from "@/lib/colecoes/binder-insert";
import { type PocketPosition, sharedSlotPosition } from "@/lib/colecoes/editor-binder";
import {
  AT_BARRIER_MESSAGE,
  type EditorGapFailure,
  type EditorGapUndo,
  editorGapFailureDisablesEditing,
  editorGapFailureMessage,
  editorGapFailureRechecksAccess,
  gapConfirmations,
  gapInsertedMessage,
  gapOutcomeUncertain,
  gapStep,
} from "@/lib/colecoes/editor-binder-gap";

type Target = { slotId: string; page: number; row: number; column: number; position: PocketPosition };

/**
 * V1-13 · E2-3B — abrir e fechar espaço pelo EDITOR (5385), por posição.
 *
 * Mesmo fluxo do titular: a prévia vem do servidor; mesma página abre direto
 * (com "Desfazer"), outra página ou página nova só depois da confirmação no
 * diálogo do titular. Nada otimista: cada escrita termina com a releitura
 * autorizada (cabeçalho + páginas carregadas). Uma chamada por pedido; plano
 * mudou → nova prévia, nunca a escrita anterior de novo. Resultado incerto →
 * relê e trata as posições como alteradas, sem repetir.
 */
export function useEditorGap({
  editor,
  collectionId,
  available,
  syncAfter,
}: {
  editor: SharedBinderEditor;
  collectionId: string;
  /** Edição ligada e fichário sem prova de não exclusividade (E2-3A, D1). */
  available: boolean;
  /** Releitura autorizada da E2-3A (`renumbered` = posições mudaram ou podem ter mudado). */
  syncAfter: (renumbered: boolean) => Promise<void>;
}) {
  const [dialog, setDialog] = useState<(GapDialogState & { position: PocketPosition }) | null>(null);
  const running = useRef(false);
  /** O "Desfazer" roda depois, a partir da mensagem: lê sempre o estado ATUAL da curadoria (Bandeja, escrita em curso). */
  const editorRef = useRef(editor);
  editorRef.current = editor;

  /** Recusa do servidor: mensagem neutra; perda de permissão desliga a edição (mesma regra da E2-1). */
  const refuse = useCallback(
    (op: "preview" | "insert" | "close", reason: EditorGapFailure) => {
      if (editorGapFailureDisablesEditing(reason)) {
        setDialog(null);
        editor.loseAccess(editorGapFailureRechecksAccess(reason));
      }
      editor.notify({ tone: "error", text: editorGapFailureMessage(op, reason) });
    },
    [editor],
  );

  const runClose = useCallback(
    async (undo: EditorGapUndo) => {
      const editor = editorRef.current;
      if (running.current) return;
      if (!editor.beginStructural()) {
        if (editor.structuralBlocker) editor.notify({ tone: "info", text: editor.structuralBlocker });
        return;
      }
      running.current = true;
      editor.notify({ tone: "info", text: "Desfazendo o espaço…" });
      const r = await editorCloseGap({ collectionId, undo }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      // Sucesso ou resultado incerto: posições mudaram (ou podem ter mudado) — fixação aprendida e desfazeres por posição deixam de valer.
      await syncAfter(r.ok || gapOutcomeUncertain(r.reason));
      running.current = false;
      editor.endStructural();
      if (r.ok) editor.notify({ tone: "success", text: r.pageRemoved ? "Espaço desfeito: os bolsos voltaram ao lugar e a página criada saiu." : "Espaço desfeito: os bolsos voltaram ao lugar." });
      else refuse("close", r.reason);
    },
    [collectionId, refuse, syncAfter],
  );

  const runInsert = useCallback(
    async (target: Target, preview: GapPreview) => {
      if (running.current || !preview.planToken) return;
      if (!editor.beginStructural()) {
        const text = editor.structuralBlocker ?? "Aguarde a alteração em andamento terminar.";
        setDialog((current) => (current ? { ...current, error: text } : current));
        if (!dialog) editor.notify({ tone: "info", text });
        return;
      }
      running.current = true;
      if (dialog) setDialog((current) => (current ? { ...current, running: true, error: null } : current));
      else editor.notify({ tone: "info", text: "Abrindo o espaço…" });
      const confirmations = gapConfirmations(preview);
      // Uma única escrita por confirmação.
      const r = await editorInsertGap({
        collectionId,
        position: target.position,
        planToken: preview.planToken,
        confirmCrossPage: confirmations.crossPage,
        confirmAddPage: confirmations.addPage,
      }).catch(() => ({ ok: false, reason: "unknown" }) as const);

      if (!r.ok && r.reason === "plan_changed") {
        // Nada andou. Nova prévia (leitura), mostrada para nova confirmação — nunca a escrita anterior de novo.
        const again = await editorPreviewGap({ collectionId, position: target.position }).catch(() => ({ ok: false, reason: "unknown" }) as const);
        await syncAfter(false);
        running.current = false;
        editor.endStructural();
        if (again.ok && gapStep(again.preview) !== "already_free" && gapStep(again.preview) !== "not_found" && gapStep(again.preview) !== "at_barrier") {
          setDialog({ ...target, preview: again.preview, running: false, error: null, refreshed: true });
          return;
        }
        setDialog(null);
        if (again.ok) editor.notify({ tone: "info", text: gapStep(again.preview) === "at_barrier" ? AT_BARRIER_MESSAGE : editorGapFailureMessage("insert", "plan_changed") });
        else refuse("preview", again.reason);
        return;
      }

      await syncAfter(r.ok ? r.result.outcome === "INSERTED" : gapOutcomeUncertain(r.reason));
      running.current = false;
      editor.endStructural();
      setDialog(null);
      if (!r.ok) {
        refuse("insert", r.reason);
        return;
      }
      if (r.result.outcome === "ALREADY_FREE") {
        editor.notify({ tone: "info", text: "Esse bolso já estava livre — nada precisou andar." });
        return;
      }
      const undo = r.result.undo;
      editor.notify({
        tone: "success",
        text: gapInsertedMessage(r.result.movedPockets, r.result.addedPageNumber !== null),
        action: { label: "Desfazer", run: () => void runClose(undo) },
      });
    },
    [collectionId, dialog, editor, refuse, runClose, syncAfter],
  );

  /** Pedido de abrir espaço antes do bolso: prévia do servidor e, conforme o resultado, aplica ou pede confirmação. */
  const start = useCallback(
    async (slot: BinderSlot) => {
      const position = sharedSlotPosition(slot.slotId);
      if (!available || !position || running.current) return;
      if (!editor.beginStructural()) {
        if (editor.structuralBlocker) editor.notify({ tone: "info", text: editor.structuralBlocker });
        return;
      }
      running.current = true;
      editor.notify({ tone: "info", text: "Calculando o espaço…" });
      const r = await editorPreviewGap({ collectionId, position }).catch(() => ({ ok: false, reason: "unknown" }) as const);
      running.current = false;
      editor.endStructural();
      if (!r.ok) {
        refuse("preview", r.reason);
        if (r.reason === "slot_not_found") void syncAfter(false);
        return;
      }
      const target: Target = { slotId: slot.slotId, page: position.page, row: position.row, column: position.column, position };
      switch (gapStep(r.preview)) {
        case "already_free":
          editor.notify({ tone: "info", text: "Esse bolso já está livre." });
          return;
        case "at_barrier":
          editor.notify({ tone: "info", text: AT_BARRIER_MESSAGE });
          return;
        case "not_found":
          editor.notify({ tone: "error", text: editorGapFailureMessage("preview", "slot_not_found") });
          void syncAfter(false);
          return;
        case "run":
          editor.notify(null);
          await runInsert(target, r.preview);
          return;
        case "confirm":
        case "explain":
          editor.notify(null);
          setDialog({ ...target, preview: r.preview, running: false, error: null, refreshed: false });
      }
    },
    [available, collectionId, editor, refuse, runInsert, syncAfter],
  );

  return {
    dialog,
    start,
    confirm: () => {
      if (dialog) void runInsert(dialog, dialog.preview);
    },
    close: () => {
      if (dialog && !dialog.running) setDialog(null);
    },
  };
}

export type EditorGap = ReturnType<typeof useEditorGap>;
