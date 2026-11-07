/**
 * V1-14 R2-D — "Cartas favoritas do Card Set" (relatório da Coleção). Regras puras, sem banco, sem
 * rede. Contrato: D7 §4l.
 *
 * Curadoria pessoal: TODAS as cartas favoritas do titular cujo Card Set canônico
 * (`card.card_set_id`) é o da coleção autorizada — lidas pela Query 5356 (filtro canônico no
 * banco) — numa ÚNICA lista na ordem do Set devolvida pela 5356 (número de colecionador
 * `collector_order`, nome, id), sem filtros nem agrupamentos. Unidade = a carta.
 *
 * Regras reutilizadas da R1-D, sem cópia: `buildFavoritesReport` (uma linha por carta; posse =
 * exemplares do acervo INTEIRO somando variantes e idiomas; referência NM geral da carta UMA vez,
 * em centavos, nunca × exemplares; sem cotação fora da soma; completude da leitura e da posse).
 * Aqui: preservar a ordem canônica da 5356, conferir que nenhuma linha é de outro Set e tratar a
 * falha temporária de preço como relatório provisório (impressão bloqueada).
 */
import { type FavoriteReportLine, type FavoritesIncompleteReason, type FavoritesReport } from "./favorites-report.ts";

export type SetFavoritesIncompleteReason = FavoritesIncompleteReason | "set_mismatch" | "prices_unavailable";

export type SetFavoritesReport = {
  /** Cartas favoritas elegíveis do Card Set. */
  cardCount: number;
  /** Cartas com ao menos um exemplar no acervo. */
  ownedCount: number;
  /** Σ exemplares no acervo das favoritas (todas as variantes e idiomas). */
  ownedCopies: number;
  /** Cartas com referência NM (> 0). */
  pricedCount: number;
  /** Σ de uma referência por carta cotada; `null` sem nenhuma cotada (nunca R$ 0). */
  totalReferenceBrl: number | null;
  /** A leitura de preços falhou agora: referências "Indisponível", relatório provisório. */
  pricesUnavailable: boolean;
  /** Lista única, na ordem canônica da 5356. */
  lines: FavoriteReportLine[];
  state: "empty" | "list";
  complete: boolean;
  incompleteReason: SetFavoritesIncompleteReason;
};

export function buildSetFavoritesReport(input: {
  favorites: FavoritesReport;
  /** Ordem canônica (ids na ordem da 5356). */
  order: readonly string[];
  /** Alguma linha da 5356 veio com `card_set_id` diferente do da coleção. */
  foreignSet: boolean;
  pricesUnavailable: boolean;
}): SetFavoritesReport {
  const { favorites } = input;
  const rank = new Map(input.order.map((id, index) => [id.toLowerCase(), index]));
  const lines = favorites.sets
    .flatMap((set) => set.cards)
    .sort((a, b) => (rank.get(a.cardId) ?? Number.MAX_SAFE_INTEGER) - (rank.get(b.cardId) ?? Number.MAX_SAFE_INTEGER));
  const incompleteReason: SetFavoritesIncompleteReason = input.foreignSet
    ? "set_mismatch"
    : (favorites.incompleteReason ?? (input.pricesUnavailable ? "prices_unavailable" : null));
  return {
    cardCount: favorites.favoriteCount,
    ownedCount: favorites.ownedCount,
    ownedCopies: lines.reduce((n, line) => n + line.ownedCopies, 0),
    pricedCount: favorites.pricedCount,
    totalReferenceBrl: favorites.totalReferenceBrl,
    pricesUnavailable: input.pricesUnavailable,
    lines,
    state: favorites.favoriteCount === 0 ? "empty" : "list",
    complete: incompleteReason === null,
    incompleteReason,
  };
}

/** "No acervo: 2 exemplares" · "Não está no acervo". */
export function setFavoriteOwnershipText(ownedCopies: number): string {
  if (ownedCopies <= 0) return "Não está no acervo";
  return `No acervo: ${new Intl.NumberFormat("pt-BR").format(ownedCopies)} ${ownedCopies === 1 ? "exemplar" : "exemplares"}`;
}

/** Referência de uma carta: valor, "Sem cotação" ou "Indisponível" (falha temporária). */
export function setFavoriteReferenceText(line: Pick<FavoriteReportLine, "referenceBrl">, pricesUnavailable: boolean, formatMoney: (brl: number) => string): string {
  if (pricesUnavailable) return "Indisponível";
  return line.referenceBrl === null ? "Sem cotação" : formatMoney(line.referenceBrl);
}

/** Valor do indicador: "Indisponível" com falha; "Sem cotação" sem nenhuma cotada. */
export function setFavoritesTotalText(report: Pick<SetFavoritesReport, "totalReferenceBrl" | "pricesUnavailable">, formatMoney: (brl: number) => string): string {
  if (report.pricesUnavailable) return "Indisponível";
  return report.totalReferenceBrl === null ? "Sem cotação" : formatMoney(report.totalReferenceBrl);
}

export function setFavoritesIncompleteText(reason: SetFavoritesIncompleteReason, fallback: (r: FavoritesIncompleteReason) => string | null): string | null {
  if (reason === "set_mismatch") return "A leitura trouxe favoritas de outro Card Set; a lista não é confiável e a impressão fica indisponível. Tente novamente.";
  if (reason === "prices_unavailable")
    return "As referências de preço não puderam ser carregadas agora (marcadas “Indisponível”); o relatório é provisório e a impressão fica indisponível. Tente novamente em instantes.";
  return fallback(reason);
}
