"use client";

import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useMemo, useState } from "react";
import { History, X } from "lucide-react";
import { readSharedActivity } from "@/app/colecoes/compartilhada/[id]/activity-actions";
import { readCollectionActivity } from "@/app/colecoes/collection-activity-actions";
import { BinderHistory, type BinderHistorySource } from "@/components/colecoes/fichario/binder-history";
import { useRestoreFocus } from "@/hooks/use-restore-focus";
import { historyFilters } from "@/lib/colecoes/binder-activity";
import { collectionActivityEmptyMessage, collectionActivityFailureMessage } from "@/lib/colecoes/collection-activity";
import {
  SHARED_ACTIVITY_FILTERS,
  sharedActivityFailureMessage,
  sharedActivityRetry,
  sharedEmptyMessage,
} from "@/lib/colecoes/shared-binder-activity";
import acervoStyles from "../acervo/acervo.module.css";
import addStyles from "../acervo/acervo-add.module.css";
import manageStyles from "../colecoes/collection-manage.module.css";
import pokedexStyles from "../colecoes/pokedex.module.css";
import styles from "./share.module.css";

/** Fonte do histórico para o participante: a 5388, com os filtros que ela suporta. */
export function sharedActivitySource(collectionId: string, speciesEnabled = false): BinderHistorySource {
  return {
    // E3-7a: "Pokémon nos bolsos" só em coleção Pokédex (já sabido pela página; sem consulta nova).
    filters: historyFilters(SHARED_ACTIVITY_FILTERS, speciesEnabled),
    readPage: async (filter, cursor) => {
      const r = await readSharedActivity({ collectionId, filter, cursor }).catch(() => null);
      if (!r) return { ok: false, message: sharedActivityFailureMessage("unknown"), retry: true };
      return r.ok
        ? r
        : { ok: false, message: sharedActivityFailureMessage(r.reason), retry: sharedActivityRetry(r.reason), signIn: r.reason === "not_authenticated" };
    },
    emptyMessage: sharedEmptyMessage,
    noteOnEveryFilter: true,
  };
}

/**
 * V1-13 · F3-4: histórico da Pokédex da coleção (5395) — posições e representantes. Um só
 * filtro ("Todas"); cursor = último evento; zero linhas tem texto neutro (pode ser falta de acesso).
 */
export function pokedexActivitySource(collectionId: string): BinderHistorySource {
  return {
    filters: [{ key: "ALL", label: "Todas" }],
    readPage: async (_filter, cursor) => {
      const r = await readCollectionActivity({ collectionId, cursor }).catch(() => null);
      if (!r) return { ok: false, message: collectionActivityFailureMessage("unknown"), retry: true };
      return r.ok
        ? r
        : { ok: false, message: collectionActivityFailureMessage(r.reason), retry: r.reason === "unknown", signIn: r.reason === "not_authenticated" };
    },
    emptyMessage: () => collectionActivityEmptyMessage(),
    noteOnEveryFilter: true,
  };
}

type ActivityTab = "POKEDEX" | "BINDER";

/**
 * V1-13 · E3-5 — "Atividade" da coleção compartilhada, para EDITOR e VIEWER
 * (configuração D-E3-1 ligada e fichário visível, decidido no servidor da
 * página — não autoriza nada). Abre a MESMA lista do histórico do titular,
 * alimentada pela leitura de participante (5388): só eventos e itens desta
 * coleção no fichário atual, com o nome de exibição público de quem fez.
 * A leitura só acontece com o painel aberto.
 */
export function SharedCollectionActivityButton({
  collectionId,
  collectionName,
  binder = true,
  pokedex = false,
  label = "Atividade",
  className,
  labelClassName,
}: {
  collectionId: string;
  collectionName: string;
  /** Histórico do fichário (5388): só com fichário visível. */
  binder?: boolean;
  /** F3-4: histórico da Pokédex (5395): só em coleções Pokédex. */
  pokedex?: boolean;
  /** E3-7a: a página do titular usa "Atividade da Pokédex" e o estilo da cápsula de ações. */
  label?: string;
  className?: string;
  labelClassName?: string;
}) {
  const [open, setOpen] = useState(false);
  const restoreFocus = useRestoreFocus();
  const source = useMemo(() => sharedActivitySource(collectionId, pokedex), [collectionId, pokedex]);
  const pokedexSource = useMemo(() => pokedexActivitySource(collectionId), [collectionId]);
  const [tab, setTab] = useState<ActivityTab>(pokedex ? "POKEDEX" : "BINDER");
  if (!binder && !pokedex) return null;
  const both = binder && pokedex;
  const current: ActivityTab = !pokedex ? "BINDER" : !binder ? "POKEDEX" : tab;

  return (
    <>
      <button type="button" className={className ?? manageStyles.settingsButton} onClick={() => setOpen(true)} aria-haspopup="dialog">
        <History className="h-4 w-4" aria-hidden="true" />
        <span className={labelClassName}>{label}</span>
      </button>
      {open ? (
        <DialogPrimitive.Root open onOpenChange={(next) => !next && setOpen(false)}>
          <DialogPrimitive.Portal>
            <DialogPrimitive.Overlay className={acervoStyles.overlay} />
            <DialogPrimitive.Content className={`${acervoStyles.drawer} ${manageStyles.panel}`} aria-describedby={undefined} onCloseAutoFocus={restoreFocus}>
              <div className={acervoStyles.drawerHeader}>
                <div className="min-w-0">
                  <DialogPrimitive.Title className={addStyles.panelTitle}>{both ? "Atividade da coleção" : current === "POKEDEX" ? "Atividade da Pokédex" : "Atividade do fichário"}</DialogPrimitive.Title>
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
                {both ? (
                  <div className={pokedexStyles.segment} role="group" aria-label="Qual histórico mostrar">
                    <button type="button" aria-pressed={current === "POKEDEX"} className={pokedexStyles.segmentButton} onClick={() => setTab("POKEDEX")}>
                      Pokédex
                    </button>
                    <button type="button" aria-pressed={current === "BINDER"} className={pokedexStyles.segmentButton} onClick={() => setTab("BINDER")}>
                      Fichário
                    </button>
                  </div>
                ) : null}
                {current === "POKEDEX" ? (
                  <>
                    <p className={styles.lead}>Cartas colocadas, movidas ou retiradas das posições da Pokédex, representantes escolhidas e quem fez.</p>
                    <BinderHistory key="pokedex" source={pokedexSource} />
                  </>
                ) : (
                  <>
                    <p className={styles.lead}>Mudanças desta coleção no fichário — cartas, reservas, páginas e Pokémon nos bolsos — e quem as fez. O que é de outras coleções não aparece.</p>
                    <BinderHistory key="binder" source={source} />
                  </>
                )}
              </div>
            </DialogPrimitive.Content>
          </DialogPrimitive.Portal>
        </DialogPrimitive.Root>
      ) : null}
    </>
  );
}
