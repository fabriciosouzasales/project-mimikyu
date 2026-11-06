/**
 * Posição do menu de Relatórios (V1-14 — compartilhado por Coleção e Acervo). Regra pura:
 *  - largura útil = `document.documentElement.clientWidth` (desconta a barra de rolagem
 *    vertical, ao contrário de `innerWidth`) — o painel nunca fica sob a barra;
 *  - preferência: alinhado à esquerda do gatilho (como antes); se não couber, alinhado à
 *    borda direita da cápsula (gatilho no canto direito do cabeçalho);
 *  - sempre dentro de `[margem, largura útil − margem − painel]`, sem cortes;
 *  - o traço dourado continua apontando para o centro do gatilho (limitado à largura do painel).
 */
export const MENU_PANEL_WIDTH = 288; // 18rem — o mesmo valor do CSS.
export const MENU_VIEWPORT_GUTTER = 12;
const NOTCH_INSET = 16;

export function placeReportMenu(input: {
  triggerLeft: number;
  triggerWidth: number;
  capsuleRight: number;
  capsuleBottom: number;
  /** Largura útil da viewport, sem a barra de rolagem. */
  viewportWidth: number;
  panelWidth?: number;
  gutter?: number;
}): { top: number; left: number; notch: number; width: number } {
  const gutter = input.gutter ?? MENU_VIEWPORT_GUTTER;
  const width = Math.max(0, Math.min(input.panelWidth ?? MENU_PANEL_WIDTH, input.viewportWidth - gutter * 2));
  const maxLeft = Math.max(gutter, input.viewportWidth - gutter - width);
  let left = input.triggerLeft - 6;
  if (left + width > input.viewportWidth - gutter) left = input.capsuleRight - width;
  left = Math.round(Math.min(Math.max(gutter, left), maxLeft));
  const center = input.triggerLeft + input.triggerWidth / 2 - left;
  const notch = Math.round(Math.min(Math.max(NOTCH_INSET, center), Math.max(NOTCH_INSET, width - NOTCH_INSET)));
  return { top: Math.round(input.capsuleBottom + 8), left, notch, width };
}
