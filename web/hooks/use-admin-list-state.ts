"use client";

import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Estado compartilhado das telas de cadastro do Catálogo Editorial (Game,
 * Expansion, Card Set) — cadastro inline, edição inline, seleção em massa e
 * feedback de sucesso, todos coordenados num único lugar para garantir que
 * cadastro/edição e seleção em massa nunca fiquem ativos ao mesmo tempo
 * (pedido de Fabrício, 2026-07-26, no fechamento do ciclo de Game).
 *
 * Extraído do que antes vivia só em `jogos-table.tsx`, para reuso direto
 * pelos ciclos seguintes sem duplicar a lógica de mutuamente exclusão.
 */
export function useAdminListState() {
  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [confirmingDelete, setConfirmingDelete] = useState(false);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [highlightId, setHighlightId] = useState<string | null>(null);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const isFormOpen = creating || editingId !== null;

  const clearSelection = useCallback(() => {
    setSelectedIds(new Set());
    setConfirmingDelete(false);
  }, []);

  const startCreate = useCallback(() => {
    setEditingId(null);
    clearSelection();
    setCreating((v) => !v);
  }, [clearSelection]);

  const cancelCreate = useCallback(() => setCreating(false), []);

  const startEdit = useCallback(
    (id: string) => {
      setCreating(false);
      clearSelection();
      setEditingId(id);
    },
    [clearSelection],
  );

  const cancelEdit = useCallback(() => setEditingId(null), []);

  const toggleOne = useCallback((id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const toggleAll = useCallback((ids: string[]) => {
    setSelectedIds((prev) => (ids.length > 0 && prev.size === ids.length ? new Set() : new Set(ids)));
  }, []);

  const startConfirmDelete = useCallback(() => setConfirmingDelete(true), []);
  const cancelConfirmDelete = useCallback(() => setConfirmingDelete(false), []);

  /** Ação rápida de exclusão por linha (2026-07-31, tela Jogos): seleciona
   * só aquele item e já abre a confirmação, sem passar pelo fluxo de
   * seleção em massa (checkboxes) — usada por telas com botão de lixeira
   * direto na linha em vez de uma barra de seleção. */
  const startQuickDelete = useCallback((id: string) => {
    setCreating(false);
    setEditingId(null);
    setSelectedIds(new Set([id]));
    setConfirmingDelete(true);
  }, []);

  /** Chamado após criação/edição/exclusão bem-sucedidas: fecha formulários,
   * limpa seleção, mostra a mensagem de sucesso e destaca a linha afetada
   * por alguns segundos. */
  const onSuccess = useCallback((message: string, rowId?: string) => {
    setCreating(false);
    setEditingId(null);
    setConfirmingDelete(false);
    setSelectedIds(new Set());
    setSuccessMessage(message);
    setHighlightId(rowId ?? null);

    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
    }
    timeoutRef.current = setTimeout(() => {
      setSuccessMessage(null);
      setHighlightId(null);
    }, 3000);
  }, []);

  useEffect(
    () => () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    },
    [],
  );

  return {
    creating,
    editingId,
    selectedIds,
    confirmingDelete,
    successMessage,
    highlightId,
    isFormOpen,
    startCreate,
    cancelCreate,
    startEdit,
    cancelEdit,
    toggleOne,
    toggleAll,
    clearSelection,
    startConfirmDelete,
    cancelConfirmDelete,
    startQuickDelete,
    onSuccess,
  };
}
