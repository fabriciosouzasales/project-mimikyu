"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useMemo, useState } from "react";
import { History, X } from "lucide-react";
import { readSharedActivity } from "@/app/colecoes/compartilhada/[id]/activity-actions";
import { BinderHistory, type BinderHistorySource } from "@/components/colecoes/fichario/binder-history";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import {
  SHARED_ACTIVITY_FILTERS,
  sharedActivityFailureMessage,
  sharedActivityRetry,
  sharedEmptyMessage,
} from "@/lib/colecoes/shared-binder-activity";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import manageStyles from "../colecoes/collection-manage.module.css";
import styles from "./share.module.css";

/** Fonte do histórico para o participante: a 5388, com os filtros que ela suporta. */
export function sharedActivitySource(collectionId: string): BinderHistorySource {
  return {
    filters: SHARED_ACTIVITY_FILTERS,
    readPage: async (filter, cursor) => {
      const r = await readSharedActivity({ collectionId, filter, cursor }).catch(() => null);
      if (!r) return { ok: false, message: sharedActivityFailureMessage("unknown"), retry: true };
      return r.ok ? r : { ok: false, message: sharedActivityFailureMessage(r.reason), retry: sharedActivityRetry(r.reason) };
    },
    emptyMessage: sharedEmptyMessage,
    noteOnEveryFilter: true,
  };
}

/**
 * V1-13 · E3-5 — "Atividade" da coleção compartilhada, para EDITOR e VIEWER
 * (configuração D-E3-1 ligada e fichário visível, decidido no servidor da
 * página — não autoriza nada). Abre a MESMA lista do histórico do titular,
 * alimentada pela leitura de participante (5388): só eventos e itens desta
 * coleção no fichário atual, com o nome de exibição público de quem fez.
 * A leitura só acontece com o painel aberto.
 */
export function SharedCollectionActivityButton({ collectionId, collectionName }: { collectionId: string; collectionName: string }) {
  const [open, setOpen] = useState(false);
  const restoreFocus = useRestoreFocus();
  const source = useMemo(() => sharedActivitySource(collectionId), [collectionId]);

  return (
    <>
      <button type="button" className={manageStyles.settingsButton} onClick={() => setOpen(true)} aria-haspopup="dialog">
        <History className="h-4 w-4" aria-hidden="true" />
        <span>Atividade</span>
      </button>
      {open ? (
        <DialogPrimitive.Root open onOpenChange={(next) => !next && setOpen(false)}>
          <DialogPrimitive.Portal>
            <DialogPrimitive.Overlay className={acervoStyles.overlay} />
            <DialogPrimitive.Content className={`${acervoStyles.drawer} ${manageStyles.panel}`} aria-describedby={undefined} onCloseAutoFocus={restoreFocus}>
              <div className={acervoStyles.drawerHeader}>
                <div className="min-w-0">
                  <DialogPrimitive.Title className={addStyles.panelTitle}>Atividade do fichário</DialogPrimitive.Title>
                  <p className="truncate text-xs text-muted-foreground">{collectionName}</p>
                </div>
                <DialogPrimitive.Close
                  className="flex h-11 w-11 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-surface-muted hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                  aria-label="Fechar"
                >
                  <X className="h-4 w-4" aria-hidden="true" />
                </DialogPrimitive.Close>
              </div>
              <div className={manageStyles.body}>
                <p className={styles.lead}>Mudanças desta coleção no fichário e quem as fez. O que é de outras coleções não aparece.</p>
                <BinderHistory source={source} />
              </div>
            </DialogPrimitive.Content>
          </DialogPrimitive.Portal>
        </DialogPrimitive.Root>
      ) : null}
    </>
  );
}
