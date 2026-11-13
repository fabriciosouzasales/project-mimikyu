/**
 * V1-16 — Condição física por exemplar (C-227–C-233): mapa ÚNICO de códigos e
 * rótulos da interface.
 *
 * - O código gravado é sempre o canônico de `card_condition` (C-106): `M`,
 *   `NM`, `LP`, `MP`, `HP`, `DMG`, nesta ordem (`condition_order` 1–6).
 * - O que se exibe vem só daqui (C-229): `LP` aparece como **SP** e `DMG` como
 *   **DM**. Nenhum rótulo exibido é gravado; a escrita (incrementos seguintes)
 *   envia sempre o código canônico.
 * - É a condição declarada pelo colecionador, não uma graduação profissional,
 *   e não muda o preço de referência (sempre NM, C-233).
 * - O app não lê `card_condition` (RLS administrativa): as funções do usuário
 *   devolvem o código, e este mapa o traduz. Código ausente ou inesperado não
 *   vira rótulo inventado — fica `null` e a interface não mostra condição.
 */

export const CARD_CONDITION_CODES = ["M", "NM", "LP", "MP", "HP", "DMG"] as const;

export type CardConditionCode = (typeof CARD_CONDITION_CODES)[number];

/** Padrão de todo exemplar novo e de todo exemplar anterior ao V1-16 (C-228/C-230). */
export const DEFAULT_CARD_CONDITION: CardConditionCode = "NM";

export type CardConditionLabel = {
  code: CardConditionCode;
  /** Sigla exibida (SP para LP, DM para DMG). */
  short: string;
  /** Nome por extenso, em inglês, como no mercado. */
  name: string;
  /** "SP · Slightly Played". */
  label: string;
};

const LABELS: Readonly<Record<CardConditionCode, CardConditionLabel>> = {
  M: { code: "M", short: "M", name: "Mint", label: "M · Mint" },
  NM: { code: "NM", short: "NM", name: "Near Mint", label: "NM · Near Mint" },
  LP: { code: "LP", short: "SP", name: "Slightly Played", label: "SP · Slightly Played" },
  MP: { code: "MP", short: "MP", name: "Moderately Played", label: "MP · Moderately Played" },
  HP: { code: "HP", short: "HP", name: "Heavily Played", label: "HP · Heavily Played" },
  DMG: { code: "DMG", short: "DM", name: "Damaged", label: "DM · Damaged" },
};

/** Só os seis códigos canônicos, com caixa exata (`nm` não é NM — C-106). */
export function isCardConditionCode(value: unknown): value is CardConditionCode {
  return typeof value === "string" && Object.prototype.hasOwnProperty.call(LABELS, value);
}

/** Lê um código vindo do banco: canônico → o próprio código; ausente ou inesperado → `null`. */
export function toCardConditionCode(value: unknown): CardConditionCode | null {
  return isCardConditionCode(value) ? value : null;
}

/** Rótulos de um código canônico; `null` para qualquer outro valor. */
export function cardConditionLabel(value: unknown): CardConditionLabel | null {
  return isCardConditionCode(value) ? LABELS[value] : null;
}

/** Os seis rótulos, na ordem canônica (para seletores dos próximos incrementos). */
export function cardConditionOptions(): CardConditionLabel[] {
  return CARD_CONDITION_CODES.map((code) => LABELS[code]);
}

/** Descrição acessível de um exemplar: "Condição declarada: SP · Slightly Played". */
export function cardConditionAccessibleText(value: unknown): string | null {
  const label = cardConditionLabel(value);
  return label ? `Condição declarada: ${label.label}` : null;
}
