"use client";

import { useEffect, useMemo, useState } from "react";
import { useTheme } from "next-themes";
import { PremiumGrid } from "@/components/experimental/collection-gallery-spike-01/premium-grid";
import {
  generateManyMockCollections,
  MOCK_COLLECTIONS,
} from "@/components/experimental/collection-gallery-spike-01/mock-collections";
import { CollectionListView } from "./collection-list-view";

type ViewMode = "lista" | "cards" | "carrossel";
type Scale = 6 | 12 | 24;
type UiTheme = "light" | "dark";

const SCALES: Scale[] = [6, 12, 24];

const MODES: { id: ViewMode; label: string }[] = [
  { id: "lista", label: "Lista" },
  { id: "cards", label: "Cards" },
  { id: "carrossel", label: "Carrossel" },
];

/**
 * COLLECTION-LIBRARY-VIEW-MODES-01 (pedido de Fabrício, 2026-08-29).
 *
 * ENCERRAMENTO DA FRENTE VISUAL DA COLLECTION LIBRARY. Consolida em UMA
 * experiência os três modos oficiais de visualização de "Minhas
 * Collections", decisão fechada depois de toda a exploração anterior
 * (COLLECTION-GALLERY-SPIKE-01, COLLECTION-LIBRARY-VISUAL-01,
 * COLLECTION-WAVE-SPIKE-01, discovery ThreeUI Complete Shelf/Character
 * Carousel, COLLECTION-FILMSTRIP-BINDER-FIDELITY-01, COLLECTION-FILMSTRIP-
 * HERO-COVER-01):
 *
 * - **Lista** — máxima densidade/escaneabilidade, uso operacional, muitas
 *   Collections. `CollectionListView` (novo, `collection-list-view.tsx`).
 * - **Cards** — equilíbrio informação/presença visual, MODO PADRÃO INICIAL.
 *   `PremiumGrid` (`collection-gallery-spike-01/premium-grid.tsx`),
 *   refinado nesta rodada só para exibir `code` (mesmo núcleo de
 *   informação dos outros 2 modos).
 * - **Carrossel** — exploração visual, experiência premium/signature,
 *   Binder como protagonista. Character Filmstrip (engine real do ThreeUI,
 *   DOM + CSS 3D, mecânica intocada) + variante "Binder MMKYU" (decisão
 *   final de COLLECTION-FILMSTRIP-HERO-COVER-01: textura portada de
 *   `binder-cover-closed.tsx`, sem borda colorida, costura periférica,
 *   marca d'água central, círculo de progresso coletadas/total). Hero
 *   Card/Hero Artwork NÃO reabertos.
 *
 * NOMENCLATURA: o seletor mostra só "Lista"/"Cards"/"Carrossel" — nomes
 * internos de discovery (Signature View, Operational View, Filmstrip,
 * Premium Grid) não aparecem na UI, só nesta doc-comment/no código.
 *
 * DATASET ÚNICO: os 3 modos consomem o MESMO `MockCollection[]`
 * (`collection-gallery-spike-01/mock-collections.ts` — `id`, `name`,
 * `code`, `totalCards`, `ownedCards`; `code` é NOVO nesta rodada,
 * propagado retroativamente para Lista/Cards porque o Carrossel já usava
 * um código curto por Collection desde as rodadas de discovery). Lista e
 * Cards são React puro, então recebem o array diretamente via prop. O
 * Carrossel é um documento HTML separado dentro de um iframe sandboxed
 * (mesma limitação já documentada em COLLECTION-WAVE-SPIKE-01) — os 6
 * arquivos novos (`public/ui-elements/collection-library-carousel-mmkyu-
 * {6,12,24}{,-light}.html`) foram gerados a partir do MESMO array
 * `MOCK_COLLECTIONS`/`generateManyMockCollections()`, rodado uma vez em
 * Node para produzir os valores exatos (não reconstruído à mão) e bakeado
 * como dados estáticos no HTML — mesmos nomes/códigos/coletadas/total que
 * Lista e Cards mostram para a mesma escala. Confirmado por diff: o
 * `<style>` e todo o `<script>` a partir de `const stage = document.
 * querySelector` (moveTo, wrappedDelta, nearestIndex, pointermove/
 * pointerleave/wheel/keydown, render loop, fórmula de profundidade,
 * spacing, easing, breakpoint responsivo, reduced-motion) são BYTE A BYTE
 * idênticos entre as 3 escalas e entre dark/light — só o array `profiles`
 * muda.
 *
 * Tema (Light/Dark): mesmo mecanismo já usado nos spikes anteriores —
 * `useTheme()`/`setTheme()` do `next-themes` já global no app. Lista/Cards
 * reagem sozinhos (tokens globais); o Carrossel troca de arquivo HTML
 * conforme `resolvedTheme` (iframe sandboxed não herda tema do pai). O
 * Binder mantém a mesma identidade física nos dois temas (só o stage ao
 * redor muda) — regra já validada em rodadas anteriores.
 *
 * Default do spike: Cards (`useState<ViewMode>("cards")`), conforme
 * decisão de que Cards é o modo padrão inicial do produto. Persistência de
 * preferência do usuário fica fora de escopo desta rodada.
 */
export function CollectionLibraryViewModesView() {
  const [mode, setMode] = useState<ViewMode>("cards");
  const [scale, setScale] = useState<Scale>(6);
  const { resolvedTheme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const uiTheme: UiTheme = mounted && resolvedTheme === "light" ? "light" : "dark";
  const fileSuffix = uiTheme === "light" ? "-light" : "";

  const collections = useMemo(
    () => (scale === 6 ? MOCK_COLLECTIONS : generateManyMockCollections(scale)),
    [scale],
  );

  return (
    <main className="min-h-screen bg-background px-6 py-10 text-foreground">
      <div className="mx-auto flex max-w-5xl flex-col gap-8">
        <header className="flex flex-col gap-1">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Spike experimental — não indexado, não é destino de produto
          </p>
          <h1 className="text-xl font-semibold">COLLECTION-LIBRARY-VIEW-MODES-01</h1>
          <p className="max-w-2xl text-sm text-muted-foreground">
            Os três modos oficiais de &quot;Minhas Collections&quot; — Lista, Cards e Carrossel — na mesma
            experiência, mesmo dataset, mesmos dois temas. Encerra a frente visual da Collection Library.
          </p>
        </header>

        <div className="flex flex-wrap items-center gap-4">
          <div className="inline-flex rounded-lg border border-border bg-surface p-1" role="tablist" aria-label="Modo de visualização">
            {MODES.map((m) => (
              <button
                key={m.id}
                type="button"
                role="tab"
                aria-selected={mode === m.id}
                onClick={() => setMode(m.id)}
                className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                  mode === m.id ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
                }`}
              >
                {m.label}
              </button>
            ))}
          </div>

          <div className="inline-flex rounded-lg border border-border bg-surface p-1" role="tablist" aria-label="Escala">
            {SCALES.map((s) => (
              <button
                key={s}
                type="button"
                role="tab"
                aria-selected={scale === s}
                onClick={() => setScale(s)}
                className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                  scale === s ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
                }`}
              >
                {s} Collections
              </button>
            ))}
          </div>

          <div className="inline-flex rounded-lg border border-border bg-surface p-1" role="tablist" aria-label="Tema">
            <button
              type="button"
              role="tab"
              aria-selected={uiTheme === "light"}
              onClick={() => setTheme("light")}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                uiTheme === "light" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Light
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={uiTheme === "dark"}
              onClick={() => setTheme("dark")}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                uiTheme === "dark" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Dark
            </button>
          </div>
        </div>

        <section className="overflow-hidden rounded-2xl border border-border bg-background">
          {mode === "lista" ? (
            <div className="p-2">
              <CollectionListView collections={collections} />
            </div>
          ) : mode === "cards" ? (
            <div className="p-6">
              <PremiumGrid collections={collections} />
            </div>
          ) : (
            <div style={{ position: "relative", width: "100%", height: "70vh", minHeight: 480 }}>
              <iframe
                key={`${scale}-${uiTheme}`}
                title="MMKYU Collector — Minhas Collections (Carrossel)"
                src={`/ui-elements/collection-library-carousel-mmkyu-${scale}${fileSuffix}.html`}
                sandbox="allow-scripts"
                loading="eager"
                style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: 0 }}
              />
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
