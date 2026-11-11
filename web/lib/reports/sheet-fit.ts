/** Largura de composição da folha na tela: 210 mm a 96 dpi (a mesma `max-w-[210mm]` da RelatorioFolha). */
export const A4_SCREEN_PX = 794;

/**
 * Escala que faz a folha A4 caber na largura disponível (prévia no celular,
 * MOBILE RESPONSIVENESS CORRECTION-01); `null` = cabe sem redução (desktop).
 */
export function sheetFitScale(available: number, sheet: number = A4_SCREEN_PX): number | null {
  if (!(available > 0) || available >= sheet) return null;
  return available / sheet;
}
