"use client";

import { useState } from "react";
import { BinderMiniPreview } from "./binder-mini-preview";
import { collectionProgress, type MockCollection } from "./mock-collections";

/**
 * COLLECTION-GALLERY-SPIKE-01 — Modo B "Premium Grid/List".
 *
 * Alternativa operacional: grid responsivo simples, stack existente (React
 * + Tailwind + tokens do design system), zero dependência nova. Mesmo
 * conteúdo por item que o Modo A (Binder, nome, progresso, acesso à
 * Collection) — sem dashboard/chrome administrativo dentro do card.
 *
 * Refinamento 2026-08-29 (COLLECTION-LIBRARY-VIEW-MODES-01) — este
 * componente passa a ser a base oficial do modo "Cards" da Collection
 * Library (3 modos oficiais: Lista/Cards/Carrossel, mesmo núcleo de
 * informação nos três). Único ajuste: label de `collection.code` abaixo do
 * nome — Lista e Carrossel (Character Filmstrip + Binder MMKYU) já mostram
 * código, faltava só aqui para os 3 modos ficarem equivalentes em
 * informação. Nenhum dashboard/estatística nova, nenhuma dependência.
 */

interface PremiumGridProps {
  collections: MockCollection[];
}

export function PremiumGrid({ collections }: PremiumGridProps) {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  return (
    <div
      className="grid gap-4"
      style={{ gridTemplateColumns: "repeat(auto-fill, minmax(140px, 1fr))" }}
    >
      {collections.map((collection) => {
        const progress = collectionProgress(collection);
        const isSelected = collection.id === selectedId;
        return (
          <button
            key={collection.id}
            type="button"
            aria-pressed={isSelected}
            aria-label={`${collection.name}, ${collection.code}, ${progress}% completo`}
            onClick={() => {
              if (isSelected) {
                console.log(`[COLLECTION-GALLERY-SPIKE-01] Abrir Collection: ${collection.id}`);
                return;
              }
              setSelectedId(collection.id);
            }}
            className={`group flex flex-col items-center gap-2 rounded-xl border bg-surface p-3 text-left transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent ${
              isSelected ? "border-foreground" : "border-border hover:border-foreground/40"
            }`}
          >
            <BinderMiniPreview targetWidth={104} />
            <div className="flex w-full flex-col items-center gap-1">
              <p className="w-full truncate text-center text-xs font-medium text-foreground">{collection.name}</p>
              <p className="text-[9px] uppercase tracking-wide text-muted-foreground/70">{collection.code}</p>
              <div className="h-1 w-full overflow-hidden rounded-full bg-surface-muted">
                <div className="h-full rounded-full bg-foreground" style={{ width: `${progress}%` }} />
              </div>
              <p className="text-[10px] text-muted-foreground">
                {collection.ownedCards}/{collection.totalCards} · {progress}%
              </p>
            </div>
          </button>
        );
      })}
    </div>
  );
}
