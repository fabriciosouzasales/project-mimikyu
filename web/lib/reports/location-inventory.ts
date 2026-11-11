/**
 * V1-14 — bloco Locais, relatório 2: "Relação de cartas armazenadas em um local"
 * (título editorial "Inventário do Local"). Núcleo PURO, sem banco.
 *
 * Base = TODO o conteúdo do local pela mesma leitura do Meu acervo filtrado pelo
 * local (5159/5220, todas as páginas, `readAllLocationItems`): cada linha é uma
 * identidade física do acervo (carta + variante + idioma) com os exemplares
 * DESTE local (`copies_count`). Agrupado por Card Set na ordem do catálogo
 * (lançamento, código, número). Unidades: cartas diferentes (identidades) e
 * exemplares físicos — nunca somadas entre si; nada de capacidade/ocupação.
 *
 * Conferência: leitura completa (todas as páginas, sem repetição, Σ = total da
 * leitura) e Σ exemplares = exemplares do local na 5219. Divergência → incompleto
 * com motivo e impressão bloqueada.
 */

export const LOCATION_INVENTORY_TITLE = "Inventário do Local";

export type InventoryItemInput = {
  cardVariantId: string;
  languageCode: string;
  languageName: string;
  cardName: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  isDefaultVariant: boolean;
  variantLabel: string | null;
  copiesCount: number;
};

export type InventoryLine = {
  key: string;
  number: string;
  name: string;
  variant: string;
  language: string;
  copies: number;
};

export type InventorySet = { code: string; name: string; lines: InventoryLine[]; cards: number; copies: number };

export type LocationInventoryReport = {
  sets: InventorySet[];
  cards: number;
  copies: number;
  complete: boolean;
  incompleteReason: "read" | "mismatch" | null;
};

function numberText(number: string, total: number | null): string {
  if (total === null || total <= 0) return number;
  const width = String(total).length;
  const padded = /^\d+$/.test(number) ? number.padStart(width, "0") : number;
  return `${padded}/${String(total).padStart(width, "0")}`;
}

export function buildLocationInventory(input: {
  items: readonly InventoryItemInput[];
  /** A leitura fechou (todas as páginas, sem repetição, Σ = total da leitura). */
  readComplete: boolean;
  /** Exemplares do local na 5219 (`card_count`). */
  locationCopies: number;
}): LocationInventoryReport {
  const sets: InventorySet[] = [];
  for (const item of input.items) {
    let set = sets[sets.length - 1];
    if (!set || set.code !== item.cardSetCode) {
      set = { code: item.cardSetCode, name: item.cardSetName, lines: [], cards: 0, copies: 0 };
      sets.push(set);
    }
    set.lines.push({
      key: `${item.cardVariantId}|${item.languageCode}`,
      number: numberText(item.collectorNumber, item.collectorTotal),
      name: item.cardName,
      variant: item.isDefaultVariant || !item.variantLabel?.trim() ? "Padrão" : item.variantLabel.trim(),
      language: item.languageName || item.languageCode,
      copies: item.copiesCount,
    });
    set.cards += 1;
    set.copies += item.copiesCount;
  }
  const cards = sets.reduce((n, s) => n + s.cards, 0);
  const copies = sets.reduce((n, s) => n + s.copies, 0);
  const incompleteReason = !input.readComplete ? "read" : copies !== input.locationCopies ? "mismatch" : null;
  return { sets, cards, copies, complete: incompleteReason === null, incompleteReason };
}

export function locationInventoryIncompleteText(reason: LocationInventoryReport["incompleteReason"]): string | null {
  if (reason === "read") return "Inventário incompleto: o conteúdo do local não pôde ser lido por inteiro agora. Tente novamente; nada foi alterado.";
  if (reason === "mismatch")
    return "Inventário incompleto: as quantidades lidas não conferem com o total do local (algo mudou durante a leitura?). Tente novamente; nada foi alterado.";
  return null;
}

const N = new Intl.NumberFormat("pt-BR");
export const plural = (n: number, one: string, many: string) => `${N.format(n)} ${n === 1 ? one : many}`;
export const formatInt = (n: number) => N.format(n);
