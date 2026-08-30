"use client";

import "./proof.css";

/**
 * MMKYU-SHELF-VISUAL-POLISH-01 (2026-08-29, mesmo dia — rodada 2): após
 * comparação lado a lado, Fabrício aprovou máquina de estados/composição/
 * continuidade do objeto e reprovou a representação visual do Binder
 * ("ainda parece livro adaptado"). Causa raiz encontrada em
 * `mmkyu-shelf-v1.html`: `makeCoverTexture` tinha um atalho
 * `if (coverAtlasReady)` que, quase sempre verdadeiro, retornava um recorte
 * da arte de capa ORIGINAL do ThreeUI ("Working Volumes", `COVER_ATLAS_DATA`)
 * antes de chegar no desenho procedural por `book.color`/`foil`/`motifKey` —
 * ou seja, a capa frontal (a face mais visível) nunca refletia nenhum dado
 * MMKYU, mesmo depois da Fase 1. Corrigido junto com: geometria mais
 * robusta (capa/lombada/cantos, `depth` maior — proporcional ao progresso de
 * cada Collection, coleção mais completa = binder mais cheio), capa
 * redesenhada (sem título grande em serifa; selo de código curto + trilha
 * de zíper + costura discreta, motif como protagonista), paleta recalibrada
 * pra grafite/preto neutro (menos marrom/sépia), painel Focus com título
 * compacto (sem quebra), "Reset view" oculto, microcopy mais leve. Câmera,
 * timing, easing, máquina de estados e navegação NÃO foram tocados.
 *
 * MMKYU SHELF ADAPTATION V1 (pedido de Fabrício, 2026-08-29).
 *
 * Primeira adaptação visual do baseline ThreeUI `CompleteShelfLandingPage`
 * (prova exact-source em `components/experimental/threeui-complete-shelf-proof/`,
 * que continua intocada e funcionando para comparação lado a lado).
 *
 * SOURCE OWNERSHIP (pedido explícito, seção 7):
 *   Este componente NÃO importa `CompleteShelfLandingPage` nem
 *   `LandingPageFrame` do pacote `@designcodeio/threeui`. Motivo: o export
 *   público `CompleteShelfLandingPage` hardcoda
 *   `sourceUrl="/landing-pages/complete-shelf-v2.html"` dentro de
 *   `lib-dist/shaders/landing-pages/LandingPages.js` (confirmado lendo o
 *   pacote instalado) — não aceita um `sourceUrl` customizado. O wrapper
 *   genérico `LandingPageFrame`, que aceitaria qualquer `sourceUrl`, só é
 *   exportado pelo barrel `index.js` do pacote — e o barrel arrasta módulos
 *   não usados (`Gallery.js`, que quebra com o `three` mais novo instalado,
 *   ver histórico desta rota-irmã). O mapa `exports` do `package.json` do
 *   pacote também não expõe `./shaders/*`, então um deep-import direto seria
 *   depender de caminho interno não publicado (API privada) — exatamente o
 *   que a instrução pediu para evitar.
 *   Solução: este arquivo reimplementa o host de iframe (mesmos atributos de
 *   sandbox e estilo do `LandingPageFrame` original, confirmados lendo
 *   `lib-dist/shaders/landing-pages/LandingPages.js`), source-owned, sem
 *   depender de nenhum export do pacote. ~15 linhas, comportamento idêntico.
 *   A MECÂNICA 3D (estados hero/opening/detail/closing, câmera, timing,
 *   easing, navegação por wheel/teclado/pointer, responsive) não foi
 *   reimplementada — ela é 100% a authored pelo ThreeUI, preservada dentro
 *   do HTML servido (ver `public/landing-pages/mmkyu-shelf-v1.html`).
 *
 * O QUE MUDOU EM `mmkyu-shelf-v1.html` (cópia de `complete-shelf-v2.html`,
 * gerada a partir do arquivo com SHA-256 verificado `606f200f…198e`):
 *   - Conteúdo: array `BOOKS` (7 entradas) trocado de "Working Volumes"
 *     (Codex, Claude Code, Cursor, Antigravity, Figma, Framer, Xcode) para
 *     7 Collections mockadas do MMKYU (ME1, ME2, ME2.5 — Heróis Excelsos,
 *     ME3, ME4, ME5, Base Set), mantendo TODOS os campos originais (o motor
 *     3D usa `binding`/`format`/`theme`/`motif`/`deck`/`chapters` para
 *     bakear texto em canvas na capa/lombada/páginas internas — remover
 *     esses campos quebraria o desenho; foram preenchidos com texto MMKYU
 *     em vez de removidos).
 *   - Geometria (`width`/`height`/`depth`/`seed`) NÃO foi alterada — testada
 *     primeiro a estratégia mais simples (A: só trocar identidade/cor),
 *     conforme pedido, antes de cogitar ajustar proporção/espessura (B).
 *   - Painel Focus simplificado: Binding/Format/Theme/Motif (4 campos)
 *     viraram Progresso/Idioma·Edição (2 campos); parágrafo editorial longo
 *     (`.detail-deck`) ocultado via CSS; eyebrow passou a mostrar
 *     "Collection baseada em Set" (Tipo) em vez de "Volume {roman}".
 *   - Botão principal do Focus: "Open book" → "Abrir Collection". Após a
 *     animação de abertura da capa (preservada, é a única do estado OPEN
 *     que sobrevive — page-turn interno foi ocultado via CSS, não
 *     implementado de novo), o mesmo botão passa a exibir "Entrar no Binder
 *     Workspace" — ainda sem navegação real (`binder-nav-01` não foi
 *     tocado; é só o rótulo do estado terminal pedido na Fase).
 *   - Cor: `foil` (accent/aro do binder + rim light 3D) virou a mesma cor
 *     dourada do design system MMKYU em todas as 7 Collections
 *     (`#dda54b`, convertida de `--primary` em `app/globals.css`, tema
 *     escuro) — dourado como identidade/foco, não pintando a estante
 *     inteira. `color` (pano da capa) varia por Collection para
 *     distinguibilidade na estante (seção 4). `palette` (ambiente/luz de
 *     cena) foi UNIFICADA num tom neutro escuro MMKYU em vez de mudar
 *     drasticamente de cor a cada seleção como no original — decisão
 *     deliberada: o binder continua protagonista, a sala não pisca de cor.
 *     `--serif`/`--mono` (tipografia da UI 2D) trocados para
 *     Manrope/Inter (fonte real do MMKYU, confirmada em `app/layout.tsx`).
 *     IMPORTANTE: cores não puderam ir via prop/customização React (that
 *     path existe — `usePageTypography`/`applyPageCustomization` — mas a
 *     função `applyBookTheme` do próprio HTML sobrescreve as CSS vars de
 *     cor em runtime a partir de `book.palette`/`book.foil` a cada seleção;
 *     só tipografia sobrevive a essa sobrescrita). Por isso cor E tipografia
 *     acabaram no mesmo arquivo fonte, por consistência.
 *   - "WORKING VOLUMES" (literal bakeado em 4 lugares do canvas, fora do
 *     array de dados) trocado para "MMKYU COLLECTOR".
 *   - Textos de UI (botões, aria-labels, microcopy, loading, fallback
 *     sem-WebGL) traduzidos para pt-BR.
 *   - `complete-shelf-v2.html` NÃO foi tocado — continua servindo a rota
 *     de prova original, SHA-256 conferido igual ao original nesta mesma
 *     rodada.
 *
 * NÃO ALTERADO (baseline preservado, conforme pedido):
 *   máquina de estados (hero/opening/detail/closing), câmera, timing,
 *   easing, seleção, profundidade, iluminação principal (rig de luzes do
 *   Three.js — só os alvos de cor por-book mudaram, o mecanismo em si não),
 *   navegação por wheel/teclado/pointer, responsive behavior.
 */
const FRAME_SANDBOX =
  "allow-downloads allow-forms allow-modals allow-popups allow-same-origin allow-scripts";

export function Scene() {
  return (
    <div className="shader-frame">
      <div
        className="threeui-background landing-page-frame"
        style={{
          position: "relative",
          overflow: "hidden",
          background: "#080808",
          pointerEvents: "auto",
          inset: 0,
          width: "100%",
          height: "100%",
        }}
      >
        <iframe
          title="MMKYU Collector — Minhas Collections"
          src="/landing-pages/mmkyu-shelf-v1.html"
          sandbox={FRAME_SANDBOX}
          loading="eager"
          style={{
            position: "absolute",
            inset: 0,
            display: "block",
            width: "100%",
            height: "100%",
            border: 0,
            background: "#080808",
          }}
        />
      </div>
    </div>
  );
}
