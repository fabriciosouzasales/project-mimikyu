"use client";

import { useEffect, useMemo, useState } from "react";
import { useTheme } from "next-themes";
import { PremiumGrid } from "@/components/experimental/collection-gallery-spike-01/premium-grid";
import {
  generateManyMockCollections,
  MOCK_COLLECTIONS,
} from "@/components/experimental/collection-gallery-spike-01/mock-collections";

type Mode = "wave" | "filmstrip" | "grid";
type Scale = 6 | 12 | 24;
type UiTheme = "light" | "dark";

const SCALES: Scale[] = [6, 12, 24];

/**
 * COLLECTION-WAVE-SPIKE-01 (pedido de Fabrício, 2026-08-29).
 *
 * Objetivo único: "Character Wave agrega valor suficiente para funcionar
 * como modo visual/signature de Minhas Collections, mantendo Premium Grid
 * como modo operacional?" — NÃO substituir o Premium Grid, NÃO reabrir a
 * arquitetura da tela inteira. Mesmo padrão de view de comparação já usado
 * em `collection-gallery-spike-01/collection-gallery-spike-view.tsx`
 * (mesmos tokens/Tailwind, mesma estrutura de tabs).
 *
 * SOURCE OWNERSHIP: as 3 páginas HTML servidas pelo Wave
 * (`public/ui-elements/collection-wave-mmkyu-{06,12,24}.html`) são um fork
 * do source REAL do ThreeUI — extraído com Node (`import` do módulo real
 * `@designcodeio/threeui/lib-dist/shaders/character-carousel/sources/
 * character-wave.html.js` já instalado, não reconstruído de screenshot).
 * O wrapper React do pacote (`CharacterWave`) não aceita um array de itens
 * customizado — os dados ficam bakeados dentro do HTML — por isso o fork,
 * mesmo padrão já usado no spike `mmkyu-shelf-adaptation-v1`. Mecânica
 * preservada 1:1 (wave, foco, depth, pointer, teclado, reduced-motion,
 * orientação mobile, aria-current); só o conteúdo mudou: perfis/"Follow
 * me" viraram 6 Collections mockadas (MESMO pool oficial do
 * COLLECTION-GALLERY-SPIKE-01 — Base Set/Jungle/Fossil/Team Rocket/Gym
 * Heroes/Neo Genesis — pra comparação ser 1:1 com o Grid), retrato virou
 * um SVG placeholder (capa quase-preta + aro/acento por Collection — NÃO é
 * o Binder CSS real: não dá pra montar React dentro do iframe
 * sandboxed/cross-origin do Character Wave, e a instrução pediu "apenas
 * renders/imagens", não reconstrução 3D).
 *
 * AMPLIAÇÃO 2026-08-29 — modo Carousel/Filmstrip: extensão do mesmo spike
 * (pedido explícito de Fabrício, "não criar novo projeto/spike separado")
 * para julgar visualmente o modelo BASE do Character Carousel — confirmado
 * no discovery técnico que `Character Carousel` sem `variant` explícito É
 * o próprio Filmstrip (não existe uma terceira variante). As 3 páginas
 * HTML (`public/ui-elements/collection-filmstrip-mmkyu-{6,12,24}.html`)
 * seguem o MESMO método de source ownership do Wave: extraídas via Node
 * `import()` do módulo real `@designcodeio/threeui/lib-dist/shaders/
 * character-carousel/sources/character-filmstrip.html.js`, com replaces
 * asserted (`assert count==1`) e diff linha-a-linha conferido contra o
 * original antes de copiar para `public/`. MESMO dataset do Wave (6/12/24,
 * mesmas Collections/nomes/códigos/progresso, mesmos placeholders SVG de
 * Binder). Removido da identidade original: pessoas (`profiles` de nome+
 * cargo), copy em inglês, paleta bege/creme + "Arial Narrow" (estética de
 * contact-sheet), filtro `sepia()` do retrato (tom fotográfico vintage).
 * Aplicado da identidade MMKYU: paleta escura + acento dourado (`#dda54b`),
 * fonte monoespaçada consistente com o Wave, copy em pt-BR — o suficiente
 * para comparação justa com o Wave, sem inventar uma variante nova.
 * MECÂNICA NÃO TOCADA (verificado por diff linha-a-linha contra o source
 * original extraído): fórmula de profundidade (`z = focus×145 −
 * distance×148`), espaçamento (`horizontalSpacing`/`verticalSpacing`),
 * easing do render loop, pointermove/pointerleave/wheel/keydown, breakpoint
 * responsivo (650px), detecção de `prefers-reduced-motion` — todos
 * idênticos byte-a-byte ao source real do pacote. O Filmstrip real não tem
 * hook de cor por item nem gesto de `dblclick`/`pointerdown` para orientação
 * (diferença já registrada no discovery anterior) — nenhum dos dois foi
 * adicionado artificialmente aqui.
 *
 * AMPLIAÇÃO 2026-08-29 — suporte Light/Dark: reaproveita o `next-themes`
 * já usado no app inteiro (`components/theme-provider.tsx`, ver
 * `app/layout.tsx`) via `useTheme()` — sem mecanismo novo. O toggle desta
 * página seta o tema REAL do site (mesmo `setTheme()` do `ThemeToggle`
 * global); é intencional (pedido explícito: "não complicar a arquitetura
 * apenas para este experimento") e consistente com a regra 2 do pedido
 * ("Grid usa diretamente os tokens já existentes do MMKYU") — o Grid não
 * precisou de nenhuma mudança, `PremiumGrid` já usa só tokens globais
 * (`bg-surface`/`text-foreground`/`border-border`/`text-muted-foreground`)
 * e reage sozinho. `<main>` desta página também já usava `bg-background
 * text-foreground`, então o "ambiente visual do spike inteiro" (regra 1)
 * já vem de graça.
 *
 * Wave e Filmstrip são documentos HTML separados dentro de um iframe
 * sandboxed (`sandbox="allow-scripts"`, sem `allow-same-origin`) — o tema
 * do React pai não atravessa a fronteira do iframe automaticamente. Por
 * isso existem 2 arquivos por escala/variante (`collection-wave-mmkyu-
 * {6,12,24}.html` = dark, `-{6,12,24}-light.html` = light; mesmo padrão
 * para o Filmstrip) e o `src` do iframe troca de arquivo conforme
 * `resolvedTheme`. Cada par dark/light foi gerado a partir do MESMO
 * arquivo dark já aprovado, com replaces cirúrgicos (`assert count==1`)
 * tocando SÓ `:root`/`html,body`/`.stage`/`.stage::before`/`.stage::after`
 * (+ a réplica desses mesmos valores na media query mobile) — cor de fundo
 * do workspace (`#121212` escuro → `#e0dad2` warm stone claro, mesmo tom
 * já aprovado em `--binder-page-bg` claro de BINDER-NAV-01) e os realces/
 * grão decorativos do stage (invertidos de branco-sobre-escuro para
 * morno-escuro-sobre-claro, mesma magnitude de alfa). Confirmado por diff
 * linha-a-linha e por comparação do `<script>` inteiro (`ds === ls`): ZERO
 * mudança em `.card`/`.portrait`/`.identity`/`.footer`/`.index`/`.name`/
 * `.role` e ZERO mudança de JS — regra "UI theme != cor física do Binder"
 * (pedido explícito): o CARD_TINT por Collection e o texto sobre o card
 * continuam exatamente os mesmos nos dois temas, só o workspace ao redor
 * muda. `mounted` evita mismatch de hidratação (mesmo padrão de
 * `components/theme-toggle.tsx`) — antes de montar, assume dark (mesmo
 * fallback do arquivo sem sufixo `-light`).
 */
export function CollectionWaveSpikeView() {
  const [mode, setMode] = useState<Mode>("wave");
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
          <h1 className="text-xl font-semibold">COLLECTION-WAVE-SPIKE-01</h1>
          <p className="max-w-2xl text-sm text-muted-foreground">
            Character Wave e Character Carousel/Filmstrip (ThreeUI, DOM + CSS 3D, sem Three.js/WebGL/GSAP)
            como candidatos a modo Signature View experimental de &quot;Minhas Collections&quot;, comparados
            lado a lado entre si e com o Premium Grid operacional já aprovado. Mesmos mocks nos três modos,
            nos dois temas oficiais (Light/Dark) do MMKYU.
          </p>
        </header>

        <div className="flex flex-wrap items-center gap-4">
          <div className="inline-flex rounded-lg border border-border bg-surface p-1" role="tablist" aria-label="Modo">
            <button
              type="button"
              role="tab"
              aria-selected={mode === "wave"}
              onClick={() => setMode("wave")}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                mode === "wave" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Wave (signature)
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mode === "filmstrip"}
              onClick={() => setMode("filmstrip")}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                mode === "filmstrip" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Carousel / Filmstrip
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mode === "grid"}
              onClick={() => setMode("grid")}
              className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                mode === "grid" ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Grid (operacional)
            </button>
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
          {mode === "wave" ? (
            <div style={{ position: "relative", width: "100%", height: "70vh", minHeight: 480 }}>
              <iframe
                key={`${scale}-${uiTheme}`}
                title="MMKYU Collector — Minhas Collections (Wave)"
                src={`/ui-elements/collection-wave-mmkyu-${scale}${fileSuffix}.html`}
                sandbox="allow-scripts"
                loading="eager"
                style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: 0 }}
              />
            </div>
          ) : mode === "filmstrip" ? (
            <div style={{ position: "relative", width: "100%", height: "70vh", minHeight: 480 }}>
              <iframe
                key={`${scale}-${uiTheme}`}
                title="MMKYU Collector — Minhas Collections (Carousel / Filmstrip)"
                src={`/ui-elements/collection-filmstrip-mmkyu-${scale}${fileSuffix}.html`}
                sandbox="allow-scripts"
                loading="eager"
                style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: 0 }}
              />
            </div>
          ) : (
            <div className="p-6">
              <PremiumGrid collections={collections} />
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
