import { flushSync } from "react-dom";

/**
 * View Transitions API (`document.startViewTransition`) — mecanismo do
 * "morph" de miniatura do grid → imagem ampliada, usado pelo preview
 * compartilhado de carta (`components/card/`). Extraído em 2026-08-17
 * (pedido de Fabrício: o preview de carta deve ser estruturalmente
 * compartilhado entre `/catalogo/cartas` e `/pesquisa`, não reimplementado
 * por página) — antes duplicado, funcionalmente idêntico, dentro de
 * `cartas-gallery.tsx` e `card-set-cartas-grid.tsx`. `card-set-cartas-grid.tsx`
 * mantém sua própria cópia por ora (fora do escopo desta extração, que
 * cobriu só `Cartas` e `Pesquisa` — ver `docs/adr/ADR-030-card-search-projection.md`).
 *
 * Sem suporte no navegador, ou com `prefers-reduced-motion: reduce`, cai
 * direto para a atualização de estado normal — quem usa isto (via
 * `CardPreviewOverlay`, prop `useViewTransition`) volta ao zoom+fade padrão
 * do Dialog nesse caso, mesmo comportamento de fallback já usado por
 * `CartaZoomDialog` desde 2026-07-31.
 *
 * `flushSync` força o `setState` a commitar de forma síncrona dentro do
 * callback — `startViewTransition` exige isso para capturar o DOM "antigo"
 * e o "novo" em dois instantes bem definidos; sem `flushSync` o React
 * adiaria o commit para depois do callback já ter retornado.
 */
type DocumentWithViewTransitions = Document & {
  startViewTransition?: (callback: () => void) => unknown;
};

export function canUseViewTransitions(): boolean {
  if (typeof document === "undefined" || typeof window === "undefined") return false;
  if (!(document as DocumentWithViewTransitions).startViewTransition) return false;
  return !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export function runWithViewTransition(update: () => void) {
  if (canUseViewTransitions()) {
    (document as DocumentWithViewTransitions).startViewTransition?.(() => flushSync(update));
  } else {
    update();
  }
}

/**
 * Nome compartilhado entre a miniatura do grid e a imagem do preview
 * ampliado — mesmo princípio de "shared element" que faz o navegador
 * morfar uma na outra em vez de só cross-fade. Prefixo garante um
 * `<custom-ident>` válido em CSS mesmo quando o identificador (UUID) começa
 * com dígito.
 */
export function cardImagePreviewTransitionName(id: string): string {
  return `card-img-preview-${id}`;
}
