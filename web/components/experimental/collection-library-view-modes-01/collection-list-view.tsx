"use client";

import { useState } from "react";
import { ChevronRight } from "lucide-react";
import { BinderMiniPreview } from "@/components/experimental/collection-gallery-spike-01/binder-mini-preview";
import { collectionProgress, type MockCollection } from "@/components/experimental/collection-gallery-spike-01/mock-collections";

/**
 * COLLECTION-LIBRARY-VIEW-MODES-01 (2026-08-29) — Modo "Lista".
 *
 * Terceiro modo oficial da Collection Library, ao lado de Cards (Premium
 * Grid) e Carrossel (Character Filmstrip + Binder MMKYU). Objetivo: máxima
 * densidade/escaneabilidade para muitas Collections — "lista client-facing
 * premium", explicitamente NÃO uma tabela administrativa (sem colunas de
 * metadado técnico, sem checkbox/seleção em massa, sem ação secundária
 * visível por padrão).
 *
 * Mesmo núcleo de informação dos outros 2 modos (Binder, nome, código,
 * progresso) — só densidade/apresentação mudam: uma linha compacta por
 * Collection, `BinderMiniPreview` bem pequeno (mesmo componente do modo
 * Cards, só reduz `targetWidth`) em vez do Binder grande, barra de
 * progresso fina, percentual + coletadas/total à direita, chevron como
 * affordance implícita de abrir (não é um botão separado — a linha inteira
 * é clicável, mesmo padrão do Premium Grid).
 */
export function CollectionListView({ collections }: { collections: MockCollection[] }) {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  return (
    <div className="divide-y divide-border overflow-hidden rounded-2xl border border-border bg-surface">
      {collections.map((collection) => {
        const progress = collectionProgress(collection);
        const isSelected = collection.id === selectedId;
        return (
          <button
            key={collection.id}
            type="button"
            aria-pressed={isSelected}
            aria-label={`${collection.name}, ${collection.code}, ${collection.ownedCards} de ${collection.totalCards}, ${progress}% completo`}
            onClick={() => {
              if (isSelected) {
                console.log(`[COLLECTION-LIBRARY-VIEW-MODES-01] Abrir Collection: ${collection.id}`);
                return;
              }
              setSelectedId(collection.id);
            }}
            className={`group flex w-full items-center gap-3 px-3 py-2.5 text-left transition-colors hover:bg-surface-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-inset ${
              isSelected ? "bg-surface-muted" : ""
            }`}
          >
            <BinderMiniPreview targetWidth={28} />

            <div className="min-w-0 flex-1">
              <div className="flex items-baseline gap-2">
                <p className="truncate text-sm font-medium text-foreground">{collection.name}</p>
                <p className="shrink-0 text-[10px] uppercase tracking-wide text-muted-foreground/70">
                  {collection.code}
                </p>
              </div>
              <div className="mt-1.5 h-1 w-full max-w-[240px] overflow-hidden rounded-full bg-surface-muted">
                <div className="h-full rounded-full bg-foreground" style={{ width: `${progress}%` }} />
              </div>
            </div>

            <div className="shrink-0 text-right">
              <p className="text-xs font-medium tabular-nums text-foreground">{progress}%</p>
              <p className="text-[10px] tabular-nums text-muted-foreground">
                {collection.ownedCards}/{collection.totalCards}
              </p>
            </div>

            <ChevronRight
              className="h-4 w-4 shrink-0 text-muted-foreground/40 transition-transform group-hover:translate-x-0.5 group-hover:text-foreground"
              aria-hidden
            />
          </button>
        );
      })}
    </div>
  );
}
