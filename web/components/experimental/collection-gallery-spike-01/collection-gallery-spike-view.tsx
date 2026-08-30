"use client";

import { useMemo, useState } from "react";
import { PremiumGrid } from "./premium-grid";
import { VisualGallery } from "./visual-gallery";
import { generateManyMockCollections, MOCK_COLLECTIONS } from "./mock-collections";

type Mode = "visual-gallery" | "premium-grid";
type Scale = "poucas" | "muitas";

/**
 * COLLECTION-GALLERY-SPIKE-01 (2026-08-29) — view de comparação isolada.
 *
 * Objetivo único: responder se a experiência visual de navegação entre
 * Binders (Modo A) agrega valor suficiente sobre um Premium Grid/List
 * (Modo B) — ou se os dois deveriam coexistir. Sem backend, sem
 * persistência, sem alteração de domínio. Fora de `AppShell` (mesmo padrão
 * já usado pelos outros spikes em `app/experimental/`).
 */
export function CollectionGallerySpikeView() {
  const [mode, setMode] = useState<Mode>("visual-gallery");
  const [scale, setScale] = useState<Scale>("poucas");

  const collections = useMemo(
    () => (scale === "poucas" ? MOCK_COLLECTIONS : generateManyMockCollections(24)),
    [scale],
  );

  return (
    <main className="min-h-screen bg-background px-6 py-10 text-foreground">
      <div className="mx-auto flex max-w-4xl flex-col gap-8">
        <header className="flex flex-col gap-1">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Spike experimental — não indexado, não é destino de produto
          </p>
          <h1 className="text-xl font-semibold">COLLECTION-GALLERY-SPIKE-01</h1>
          <p className="max-w-2xl text-sm text-muted-foreground">
            Comparação isolada: a experiência visual de navegação entre Binders (A) agrega valor
            suficiente para ser superior ou complementar a um Premium Grid/List (B)? Mesmos mocks nos
            dois modos — Binder, nome e progresso, sem chrome administrativo.
          </p>
        </header>

        <div className="flex flex-wrap items-center gap-4">
          <div className="inline-flex rounded-lg border border-border bg-surface p-1" role="tablist" aria-label="Modo">
            <button
              type="button"
              role="tab"
              aria-selected={mode === "visual-gallery"}
              onClick={() => setMode("visual-gallery")}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                mode === "visual-gallery" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              A — Visual Gallery
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mode === "premium-grid"}
              onClick={() => setMode("premium-grid")}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                mode === "premium-grid" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              B — Premium Grid/List
            </button>
          </div>

          <div className="inline-flex rounded-lg border border-border bg-surface p-1" role="tablist" aria-label="Escala">
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
        </div>

        <section className="rounded-2xl border border-border bg-background p-6">
          {mode === "visual-gallery" ? (
            <VisualGallery collections={collections} />
          ) : (
            <PremiumGrid collections={collections} />
          )}
        </section>
      </div>
    </main>
  );
}
