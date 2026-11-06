/**
 * V1-14 — rodapé institucional de impressão (INSTITUTIONAL PRINT FOOTER STANDARD-01, contrato D7
 * §2). Regras puras, sem DOM, sem rede.
 *
 * Em toda página impressa de um relatório contextual: à esquerda a data e a hora efetivas da
 * impressão (`dd/MM/yyyy HH:mm`, horário local do navegador); ao centro "Gerado por MMKYU
 * Collector"; à direita "Página X de Y" — números da paginação REAL do navegador, pelas caixas de
 * margem do CSS Paged Media (`@page mmkyu-relatorio` + `counter(page)`/`counter(pages)`, regra
 * estática em `app/globals.css`). A data/hora entra por uma regra dinâmica (`stampRule`) escrita
 * ao abrir o relatório, no botão Imprimir e no `beforeprint`.
 *
 * Suporte: só Chrome/Edge 131+ (decisão do proprietário). A detecção exige as DUAS evidências —
 * o navegador interpreta as regras de margem (sinal de recurso) E se identifica como Chromium 131+
 * (UA-CH) — para não haver falso positivo; sem elas, vale o rodapé alternativo (data/hora +
 * identificação institucional, sem paginação), nunca a ausência de rodapé.
 */

/** Nome da página de impressão dos relatórios contextuais (`@page mmkyu-relatorio`). */
export const PRINT_PAGE_NAME = "mmkyu-relatorio";
/** Texto fixo do centro. */
export const PRINT_FOOTER_CENTER = "Gerado por MMKYU Collector";
/** Conteúdo exato da caixa da direita (contadores nativos de página). */
export const PRINT_FOOTER_PAGE_CONTENT = '"Página " counter(page) " de " counter(pages)';
/** Primeira versão do Chromium com caixas de margem em `@page`. */
export const MIN_CHROMIUM_MARGIN_BOXES = 131;

const two = (n: number) => String(n).padStart(2, "0");

/** `dd/MM/yyyy HH:mm` no horário LOCAL do navegador (24 h, zeros à esquerda). */
export function formatPrintStamp(date: Date): string {
  return `${two(date.getDate())}/${two(date.getMonth() + 1)}/${date.getFullYear()} ${two(date.getHours())}:${two(date.getMinutes())}`;
}

/** Texto como string CSS segura (aspas, barra invertida e quebras escapadas). */
export function cssString(text: string): string {
  return `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/[\n\r\f]/g, " ")}"`;
}

/** Regra dinâmica da data/hora: sobrepõe o `@bottom-left` vazio da regra estática. */
export function stampRule(stamp: string): string {
  return `@page ${PRINT_PAGE_NAME} { @bottom-left { content: ${cssString(stamp)}; } }`;
}

/** Marca do navegador pelo UA-CH (`navigator.userAgentData.brands`). */
export type BrandVersion = { brand: string; version: string };

/** Versão principal do Chromium declarada; `null` sem UA-CH (Firefox, Safari) ou sem a marca. */
export function chromiumMajor(brands: readonly BrandVersion[] | null | undefined): number | null {
  if (!Array.isArray(brands)) return null;
  const entry = brands.find((item) => item && item.brand === "Chromium");
  const major = entry ? Number.parseInt(entry.version, 10) : Number.NaN;
  return Number.isInteger(major) ? major : null;
}

/**
 * Rodapé paginado só com as duas evidências: regras de margem interpretadas pelo navegador e
 * Chromium 131+. Qualquer dúvida → `false` (rodapé alternativo).
 */
export function supportsPagedFooter(input: { marginRulesParsed: boolean; brands: readonly BrandVersion[] | null | undefined }): boolean {
  const major = chromiumMajor(input.brands);
  return input.marginRulesParsed && major !== null && major >= MIN_CHROMIUM_MARGIN_BOXES;
}
