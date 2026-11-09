/**
 * Caderno de Cartas — renditions JPEG para a impressão/PDF (CARD BOOKLET PDF OPTIMIZATION-01). Sem DOM.
 *
 * Causa do peso: o motor de PDF do Chrome NÃO embute WebP; decodifica cada imagem e a regrava como
 * bitmap sem perdas (Flate, RGB + máscara alfa), no tamanho original em pixels — ~0,8 MB por carta,
 * contra ~65 KB do WebP. JPEG, ao contrário, é embutido como está (DCT). Por isso, só no preparo da
 * impressão, cada carta vira um JPEG no tamanho que a folha usa:
 *  - carta impressa com 34 mm de largura → 520 px ≈ 390 dpi (acima dos 300 dpi da impressão
 *    doméstica, sem perder o texto miúdo da carta); nunca amplia uma imagem menor;
 *  - qualidade 0,88 e fundo branco (sem canal alfa).
 */
export const PRINT_JPEG_MAX_WIDTH = 520;
export const PRINT_JPEG_QUALITY = 0.88;

/** Dimensões do JPEG: largura limitada a `maxWidth`, proporção preservada, nunca ampliada. */
export function printJpegSize(width: number, height: number, maxWidth = PRINT_JPEG_MAX_WIDTH): { width: number; height: number } {
  if (!(width > 0) || !(height > 0)) return { width: 0, height: 0 };
  if (width <= maxWidth) return { width: Math.round(width), height: Math.round(height) };
  const scale = maxWidth / width;
  return { width: maxWidth, height: Math.max(1, Math.round(height * scale)) };
}
