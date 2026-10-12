/**
 * Apresentação da Pokédex (Pokédex P1, 2026-10-12).
 *
 * D5 — pt-BR prioritário, nomes oficiais preservados: o nome da espécie vem
 * do banco exatamente como é (oficial, igual em pt-BR). Rótulos de geração
 * são derivados dos CÓDIGOS estáveis (`GENERATION_IV`), nunca do
 * `canonical_name` em inglês ("Generation IV") — um idioma novo é só mais
 * uma entrada em `GENERATION_LABEL`, sem tocar no banco nem nos componentes.
 * Nomes de região (Kanto, Johto...) são nomes próprios oficiais e passam
 * sem tradução.
 */

const GENERATION_LABEL: Record<string, string> = {
  "pt-BR": "Geração",
};

/** "GENERATION_IV" -> "IV". Códigos fora do padrão voltam inteiros, sem quebrar a tela. */
export function generationRoman(code: string): string {
  return code.startsWith("GENERATION_") ? code.slice("GENERATION_".length) : code;
}

export function generationLabel(code: string, locale: keyof typeof GENERATION_LABEL = "pt-BR"): string {
  return `${GENERATION_LABEL[locale]} ${generationRoman(code)}`;
}

/** Número nacional no formato de Pokédex: 25 -> "0025" (4 dígitos cobrem até 9999). */
export function formatDexNumber(value: number): string {
  return String(value).padStart(4, "0");
}

export function formatCount(value: number): string {
  return new Intl.NumberFormat("pt-BR").format(value);
}

/**
 * Normaliza `?geracao=` da URL: só ordinais inteiros 1..99 são aceitos; o
 * resto vira "todas" — nunca um erro para o usuário por causa de um link
 * editado à mão.
 */
export function parseGenerationParam(value: string | string[] | undefined): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d{1,2}$/.test(raw)) return null;
  const parsed = Number(raw);
  return parsed >= 1 ? parsed : null;
}

export function parseQueryParam(value: string | string[] | undefined, maxLength: number): string | null {
  const raw = Array.isArray(value) ? value[0] : value;
  const trimmed = raw?.trim().slice(0, maxLength) ?? "";
  return trimmed === "" ? null : trimmed;
}
