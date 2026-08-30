"use client";

import { useMemo, useState } from "react";
import { CollectionLibraryGrid } from "./collection-library-grid";
import {
  generateManyMockCollections,
  MOCK_COLLECTIONS,
} from "@/components/experimental/collection-gallery-spike-01/mock-collections";

type Scale = "poucas" | "muitas";

/**
 * COLLECTION-LIBRARY-VISUAL-01 (2026-08-29) — view de refinamento visual do
 * Premium Grid/List aprovado como arquitetura de UX para "Minhas
 * Collections" após o spike COLLECTION-GALLERY-SPIKE-01. Única rodada de
 * refinamento visual da Collection Library antes de voltar ao interior do
 * Binder (per pedido explícito de Fabrício) — sem backend, sem persistência,
 * sem alteração de domínio, fora de `AppShell`.
 */
export function CollectionLibraryVisualView() {
  const [scale, setScale] = useState<Scale>("poucas");

  const collections = useMemo(
    () => (scale === "poucas" ? MOCK_COLLECTIONS : generateManyMockCollections(24)),
    [scale],
  );

  return (
    <main className="min-h-screen bg-background px-6 py-10 text-foreground">
      <div className="mx-auto flex max-w-5xl flex-col gap-8">
        <header className="flex flex-col gap-1">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Spike experimental — não indexado, não é destino de produto
          </p>
          <h1 className="text-xl font-semibold">COLLECTION-LIBRARY-VISUAL-01</h1>
          <p className="max-w-2xl text-sm text-muted-foreground">
            Refinamento visual do Premium Grid/List aprovado no spike COLLECTION-GALLERY-SPIKE-01: uma
            biblioteca digital premium de Binders, não cards contendo Binders.
          </p>
        </header>

        <div
          className="inline-flex w-fit rounded-lg border border-border bg-surface p-1"
          role="tablist"
          aria-label="Escala"
        >
          <button
            type="button"
            role="tab"
            aria-selected={scale === "poucas"}
            onClick={() => setScale("poucas")}
            className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              scale === "poucas" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
            }`}
          >
            Poucas ({MOCK_COLLECTIONS.length})
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={scale === "muitas"}
            onClick={() => setScale("muitas")}
            className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
              scale === "muitas" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
            }`}
          >
            Muitas (24, sintético)
          </button>
        </div>

        <section className="rounded-2xl border border-border/60 bg-background p-8">
          <CollectionLibraryGrid collections={collections} />
        </section>
      </div>
    </main>
  );
}
