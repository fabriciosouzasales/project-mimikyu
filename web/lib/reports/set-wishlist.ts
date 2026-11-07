/**
 * V1-14 R2-C — "Cartas desejadas do Card Set" (relatório da Coleção). Regras puras, sem banco,
 * sem rede. Contrato: D7 §4k.
 *
 * Seleção CONTEXTUAL da Lista de Desejos: TODOS os desejos do titular cuja carta pertence ao Card
 * Set de referência da coleção (filtro `p_card_set_id` da 5351, aplicado no banco), numa ÚNICA
 * lista na ordem canônica "Set e número" (número, variante, idioma) — sem filtro nem agrupamento
 * por situação de posse (`WISHLIST PRESENTATION SIMPLIFICATION-01`). A posse (os quatro estados
 * C-213 da 5351) é informação de cada desejo, nunca critério de inclusão. Nada de completude,
 * posições faltantes, alocação ou acabamentos do Master Set (C-94, C-211).
 *
 * Regras reutilizadas da R1-E, sem cópia: `buildWishlistReport` (unidade = desejo; referência NM
 * UMA por variante distinta, em centavos; cotada · sem cotação · indisponível; completude da
 * leitura). O valor deste relatório é o de TODA a lista do Set (`wishlist.all`: variantes com
 * desejos atendidos e pendentes), cada variante uma única vez. Aqui só se confere que todas as
 * linhas são do Card Set da coleção e se contam cartas e variantes distintas.
 */
import { type WishReportLine, type WishValue, type WishlistIncompleteReason, type WishlistReport } from "./wishlist-report.ts";

export type SetWishlistIncompleteReason = WishlistIncompleteReason | "set_mismatch";

export type SetWishlistReport = {
  /** Desejos (variante + condição de idioma) do Card Set — todos, qualquer que seja a posse. */
  entryCount: number;
  /** Cartas canônicas distintas desejadas. */
  cardCount: number;
  /** Variantes distintas desejadas. */
  variantCount: number;
  /** Referência NM de todas as variantes distintas da lista do Set (uma vez cada). */
  value: WishValue;
  /** Lista única, na ordem canônica. */
  lines: WishReportLine[];
  /** "empty" = nenhum desejo deste Set; "list" = há desejos (mesmo que todos já no acervo). */
  state: "empty" | "list";
  complete: boolean;
  incompleteReason: SetWishlistIncompleteReason;
};

export function buildSetWishlistReport(input: { wishlist: WishlistReport; cardSetCode: string | null }): SetWishlistReport {
  const { wishlist } = input;
  const lines = wishlist.sets.flatMap((set) => set.lines);
  const foreign = wishlist.sets.some((set) => set.code !== input.cardSetCode);
  const incompleteReason: SetWishlistIncompleteReason = foreign ? "set_mismatch" : wishlist.incompleteReason;
  return {
    entryCount: wishlist.entryCount,
    cardCount: new Set(lines.map((line) => line.cardId.toLowerCase())).size,
    variantCount: wishlist.variantCount,
    value: wishlist.all,
    lines,
    state: wishlist.entryCount === 0 ? "empty" : "list",
    complete: incompleteReason === null,
    incompleteReason,
  };
}

export function setWishlistIncompleteText(reason: SetWishlistIncompleteReason, fallback: (r: WishlistIncompleteReason) => string | null): string | null {
  if (reason === "set_mismatch")
    return "A leitura trouxe desejos de outro Card Set; a lista não é confiável e a impressão fica indisponível. Tente novamente.";
  return fallback(reason);
}
