"use client";

import { useEffect, useState } from "react";
import { useTheme } from "next-themes";

type Variant = "a" | "b" | "c";
type UiTheme = "light" | "dark";

const VARIANTS: { id: Variant; label: string; description: string }[] = [
  {
    id: "a",
    label: "A · Binder MMKYU",
    description:
      "Direção final (2026-08-29, COLLECTION-FILMSTRIP-HERO-COVER-01 encerrado, A vence): textura portada de binder-cover-closed.tsx (capa preta premium), costura periférica em vez de borda colorida, marca d'água MMKYU centralizada, nome + código discretos e círculo de progresso \"coletadas/total\" no footer.",
  },
  {
    id: "b",
    label: "B · Hero Card pura",
    description:
      "A carta de destaque da Collection como elemento principal. Nome e progresso mantidos. Risco semântico assumido (deixa de comunicar \"Binder\").",
  },
  {
    id: "c",
    label: "C · Binder + Hero Artwork",
    description:
      "Correção 2026-08-29 (COLLECTION-FILMSTRIP-HERO-COVER-01): a carta REAL de destaque da Collection preenche a capa (crop/object-fit, sem mostrar a carta inteira), com lombada + pull tab + gradiente inferior sobrepostos por CSS — Binder continua claramente o objeto. Código/nome/progresso discretos. Hipótese principal de Fabrício.",
  },
];

/**
 * COLLECTION-FILMSTRIP-BINDER-FIDELITY-01 (pedido de Fabrício, 2026-08-29).
 *
 * Pergunta: "Qual representação faz o usuário perceber imediatamente que
 * está escolhendo uma COLLECTION, mas permite reconhecer visualmente cada
 * uma sem depender de leitura?" — comparação de 3 tratamentos para o
 * retrato do card do Filmstrip, ANTES de fechar a fidelidade do Filmstrip
 * como Signature View. Decisão puramente visual — nenhuma das 3 é feature
 * definitiva de custom cover, nenhuma é persistida, nenhuma mexe no
 * domínio.
 *
 * MECÂNICA: as 6 páginas HTML (`public/ui-elements/collection-filmstrip-
 * binder-fidelity-{a,b,c}-6{,-light}.html`) partem dos MESMOS arquivos
 * dark/light do Filmstrip já aprovados em COLLECTION-WAVE-SPIKE-01 — só o
 * dict `portraits` (o SVG de cada Collection) foi trocado por variante;
 * `.stage`/`.card`/`.footer`/`.index`/`.name`/`.role` e o `<script>`
 * inteiro (profiles, moveTo, wrappedDelta, nearestIndex, pointermove/
 * pointerleave/wheel/keydown, render loop com a fórmula de profundidade
 * `z = focus×145 − distance×148`, breakpoint 650px, `prefers-reduced-
 * motion`) ficam BYTE A BYTE idênticos entre A/B/C e entre os dois temas —
 * confirmado por diff (`<style>` idêntico completo; `<script>` idêntico
 * fora do próprio dict `portraits`). Nome da Collection e progresso
 * continuam vindo do MESMO template (`.name`/`.role`), não mudam por
 * variante.
 *
 * ARTE: nenhum asset real de carta foi usado (sem acesso a artwork oficial
 * e para evitar qualquer questão de direito autoral) — B usa uma moldura
 * de carta TCG genérica (frame + janela de arte em gradiente + tarja de
 * nome), C usa a MESMA silhueta de Binder de A (retângulo arredondado +
 * linha de lombada + pull tab circular) só trocando o preenchimento da
 * capa de um gradiente escuro flat para um gradiente radial mais rico
 * ("cover treatment"). As 6 cores de identidade por Collection são as
 * mesmas já usadas em A (mesmo princípio: UI theme muda o stage, a
 * identidade da Collection não muda).
 *
 * Tema (Light/Dark): mesmo mecanismo já usado no spike anterior —
 * `useTheme()`/`setTheme()` do `next-themes` já global no app; o `src` do
 * iframe troca de arquivo conforme `resolvedTheme`.
 *
 * Escopo fixo: 6 Collections (mesmo pool oficial de sempre — Base Set/
 * Jungle/Fossil/Team Rocket/Gym Heroes/Neo Genesis), sem seletor de escala
 * — não é o objetivo desta rodada. Wave, Grid e o Binder operacional não
 * foram tocados; nenhuma dependência nova.
 *
 * CORREÇÃO 2026-08-29 — COLLECTION-FILMSTRIP-HERO-COVER-01: a variante C
 * original usava só um gradiente radial mais rico (não era Hero Artwork de
 * verdade). Corrigida para usar 6 cartas REAIS já hospedadas no bucket
 * público `card-front` do Supabase (mesma fonte já usada no BINDER-NAV-01
 * aprovado — `web/app/experimental/binder-nav-01/mock-data.ts`, `ME2_CARDS`
 * — pt-BR, Card Set "Fogo Fantasmagórico"), preenchendo a `.portrait` via
 * `object-fit: cover` + `object-position: center 22%` (favorece a arte do
 * personagem, evita mostrar a caixa de texto da carta). A silhueta de
 * Binder (lombada + pull tab + moldura de acento por Collection) volta a
 * aparecer como camada CSS sobreposta (`.portrait-spine`/`.portrait-tab`,
 * `--hero-accent` setado via `card.style.setProperty`), e um gradiente
 * inferior (`.portrait::before`) funde a arte com o footer escuro — evita
 * o efeito "carta colada". Mapeamento carta↔Collection é arbitrário (mock
 * sem relação semântica com os nomes dos Card Sets reais), escolhido só
 * por paletas visualmente distintas entre si. `.stage`/`.card`/`.footer`/
 * `.index`/`.name`/`.role`/media queries e TODA a engine (profiles fora do
 * template, moveTo, wrappedDelta, nearestIndex, pointermove/pointerleave/
 * wheel/keydown, render loop) confirmados intocados por diff — só o dict
 * `portraits` (agora URLs reais), o novo dict `ACCENT` e 3 linhas do
 * template do card mudaram.
 *
 * DECISÃO 2026-08-29 — COLLECTION-FILMSTRIP-HERO-COVER-01 encerrado: A
 * (Binder puro) vence, B rejeitada (comunica "carta", não "Collection"), C
 * descontinuada (mesmo com Hero Cover real, o Binder deixava de ser
 * protagonista). A foi refinada para a versão final "Binder MMKYU":
 * textura portada de `binder-cover-closed.tsx` (`BLACK_HUE=30`,
 * `closedCoverWeave()`, lightness da capa frontal `[15,10,6]` — receita de
 * cor lida e reaplicada como CSS 2D estático no `.card` inteiro; o
 * componente 3D original não foi importado/alterado); borda colorida por
 * Collection removida (era o antigo `.index` com `border:#dda54b` e o
 * stroke do SVG do binder); costura periférica portada 1:1 da "costura
 * periférica" do binder real (`inset:9px; border:1.25px dashed hsl(0 0%
 * 100% / 0.1)`); marca d'água "MMKYU" centralizada com a mesma técnica
 * debossed de `MmkyuWordmark.tsx` (textShadow claro+escuro, uppercase,
 * letter-spacing largo), baixa opacidade; footer com nome (principal) +
 * código (secundário) + círculo de progresso "coletadas/total" (anel SVG
 * com arco proporcional + fração no centro, mock com tamanhos de set
 * aproximados de referência histórica). B e C permanecem nos arquivos do
 * spike (não apagados) só para referência — não são mais avaliadas nesta
 * rodada. Confirmado por diff: tudo a partir de `const count =
 * cards.length` (moveTo, wrappedDelta, nearestIndex, pointermove/
 * pointerleave/wheel/keydown, render loop) idêntico byte a byte ao
 * baseline anterior; `.stage` e a media query mobile também idênticos;
 * dark e light do card são o MESMO arquivo de conteúdo (Binder não muda
 * por tema, só o stage ao redor).
 */
export function CollectionFilmstripBinderFidelityView() {
  const [variant, setVariant] = useState<Variant>("a");
  const { resolvedTheme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const uiTheme: UiTheme = mounted && resolvedTheme === "light" ? "light" : "dark";
  const fileSuffix = uiTheme === "light" ? "-light" : "";

  return (
    <main className="min-h-screen bg-background px-6 py-10 text-foreground">
      <div className="mx-auto flex max-w-5xl flex-col gap-8">
        <header className="flex flex-col gap-1">
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Spike experimental — não indexado, não é destino de produto
          </p>
          <h1 className="text-xl font-semibold">COLLECTION-FILMSTRIP-BINDER-FIDELITY-01</h1>
          <p className="max-w-2xl text-sm text-muted-foreground">
            Três tratamentos para o retrato do card do Filmstrip, mesma mecânica, mesmas 6 Collections,
            nos dois temas oficiais. Decisão puramente visual — sem custom cover definitivo ainda.
          </p>
        </header>

        <div className="flex flex-wrap items-center gap-4">
          <div className="inline-flex rounded-lg border border-border bg-surface p-1" role="tablist" aria-label="Variante">
            {VARIANTS.map((v) => (
              <button
                key={v.id}
                type="button"
                role="tab"
                aria-selected={variant === v.id}
                onClick={() => setVariant(v.id)}
                className={`rounded-md px-3 py-1.5 text-sm font-medium transition-colors ${
                  variant === v.id ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground"
                }`}
              >
                {v.label}
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

        <p className="max-w-2xl text-sm text-muted-foreground">
          {VARIANTS.find((v) => v.id === variant)?.description}
        </p>

        <section className="overflow-hidden rounded-2xl border border-border bg-background">
          <div style={{ position: "relative", width: "100%", height: "70vh", minHeight: 480 }}>
            <iframe
              key={`${variant}-${uiTheme}`}
              title={`MMKYU Collector — Binder Fidelity ${variant.toUpperCase()}`}
              src={`/ui-elements/collection-filmstrip-binder-fidelity-${variant}-6${fileSuffix}.html`}
              sandbox="allow-scripts"
              loading="eager"
              style={{ position: "absolute", inset: 0, width: "100%", height: "100%", border: 0 }}
            />
          </div>
        </section>
      </div>
    </main>
  );
}
