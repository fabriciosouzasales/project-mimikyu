/**
 * V1-14 R1-D — relatório "Minhas favoritas" da página Cartas favoritas: curadoria pessoal das
 * cartas favoritas do usuário, por Card Set. Sem banco, sem rede.
 *
 * Unidade = a CARTA favoritada (`card_favorite`, PK (user_id, card_id) — V1-10): uma linha por
 * carta, sem variante nem idioma. Favorito é preferência, independente de posse: a coluna
 * "No acervo" mostra quantos exemplares físicos do titular existem da carta (todas as variantes
 * e idiomas somados) ou "—"; a referência NM nunca é multiplicada por exemplares.
 *
 * Referência = `get_cards_pricing_summary` (referência geral da carta, BRL, NM — a mesma da 5340
 * e da Pesquisa): uma por carta; ausente ou ≤ 0 = "Sem cotação", fora da soma (nunca zero).
 * Soma das referências = Σ de uma referência por carta cotada, em centavos — não é patrimônio
 * físico nem valor de revenda.
 *
 * Ordem: Card Sets por nome (pt-BR), depois código; cartas por número de colecionador crescente
 * (comparação numérica), depois nome e id (estável).
 * Completude: lista lida por inteiro e coerente com o total do banco (sem repetição nem falta),
 * dentro do teto de 5.000 favoritas, e posse calculada sobre o acervo inteiro; senão o relatório
 * é marcado incompleto (impressão bloqueada), nunca truncado em silêncio.
 */
import { formatCount, plural, shareText } from "./acervo-reports.ts";

/** Teto de favoritas lidas pelo relatório (páginas de 100 da 5336). */
export const FAVORITES_REPORT_MAX = 5000;
export const FAVORITES_REPORT_PAGE = 100;

export type FavoriteReportCardInput = {
  cardId: string;
  name: string;
  collectorNumber: string | null;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  favoritedAt: string;
  /** Frente primária da carta no bucket público `card-front` (pt-BR, senão en); só para a miniatura. */
  imagePath?: string | null;
};

export type FavoriteReportLine = FavoriteReportCardInput & {
  /** Referência NM unitária da carta; `null` = sem cotação. */
  referenceBrl: number | null;
  /** Exemplares físicos do titular (todas as variantes e idiomas); 0 = não possui. */
  ownedCopies: number;
  /** URL pública da miniatura (tela); `null` = sem imagem. Não entra na impressão. */
  imageUrl: string | null;
};

export type FavoriteReportSet = { code: string; name: string; cards: FavoriteReportLine[] };

export type FavoritesIncompleteReason = "changed" | "too_large" | "ownership_too_large" | null;

export type FavoritesReport = {
  favoriteCount: number;
  setCount: number;
  ownedCount: number;
  pricedCount: number;
  /** Soma de uma referência por carta cotada; `null` sem nenhuma cotada (nunca R$ 0). */
  totalReferenceBrl: number | null;
  sets: FavoriteReportSet[];
  complete: boolean;
  incompleteReason: FavoritesIncompleteReason;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const str = (v: unknown) => (typeof v === "string" && v.trim() !== "" ? v : null);

/**
 * Uma página de `get_my_favorite_cards` (5336) em modo estrito: qualquer linha fora do contrato
 * invalida a página (`null`) — o relatório nunca descarta favoritas em silêncio.
 */
export function parseFavoriteReportPage(data: unknown): { cards: FavoriteReportCardInput[]; totalCount: number } | null {
  if (!Array.isArray(data)) return null;
  const cards: FavoriteReportCardInput[] = [];
  let totalCount = 0;
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row || typeof row !== "object") return null;
    const cardId = str(row.card_id);
    const name = str(row.card_name);
    const setCode = str(row.card_set_code);
    const favoritedAt = str(row.favorited_at);
    const total = Number(row.total_count);
    if (!cardId || !UUID.test(cardId) || !name || !setCode || !favoritedAt || !Number.isInteger(total) || total < 0) return null;
    const collectorTotal = row.collector_total === null || row.collector_total === undefined ? null : Number(row.collector_total);
    totalCount = Math.max(totalCount, total);
    cards.push({
      cardId: cardId.toLowerCase(),
      name,
      collectorNumber: str(row.collector_number),
      collectorTotal: collectorTotal !== null && Number.isInteger(collectorTotal) && collectorTotal > 0 ? collectorTotal : null,
      cardSetCode: setCode,
      cardSetName: str(row.card_set_name) ?? setCode,
      favoritedAt,
      imagePath: str(row.image_path_pt) ?? str(row.image_path_en),
    });
  }
  return { cards, totalCount };
}

/** Linhas de `get_cards_pricing_summary` → referência > 0 por carta; formato inesperado → `null`. */
export function parseCardReferenceRows(data: unknown): Map<string, number> | null {
  if (!Array.isArray(data)) return null;
  const map = new Map<string, number>();
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row || typeof row !== "object") return null;
    const cardId = str(row.card_id);
    if (!cardId || !UUID.test(cardId) || typeof row.has_pricing !== "boolean") return null;
    const brl = row.brl_amount === null || row.brl_amount === undefined ? null : Number(row.brl_amount);
    if (brl !== null && !Number.isFinite(brl)) return null;
    if (row.has_pricing && brl !== null && brl > 0) map.set(cardId.toLowerCase(), brl);
  }
  return map;
}

/**
 * Exemplares por carta: grupos do acervo (variante + idioma, 5159) somados pela carta de cada
 * variante (`get_my_card_favorites_by_variant`, 5336). Variante sem carta conhecida → `null`
 * (posse não confiável, nunca contada pela metade).
 */
export function ownedCopiesByCard(
  groups: readonly { cardVariantId: string; copies: number }[],
  variantToCard: ReadonlyMap<string, string>,
): Map<string, number> | null {
  const byCard = new Map<string, number>();
  for (const group of groups) {
    const cardId = variantToCard.get(group.cardVariantId.toLowerCase());
    if (!cardId) return null;
    byCard.set(cardId, (byCard.get(cardId) ?? 0) + group.copies);
  }
  return byCard;
}

const ORDER = new Intl.Collator("pt-BR", { sensitivity: "base", numeric: true });
const cents = (brl: number) => Math.round(brl * 100);

export function buildFavoritesReport(input: {
  cards: readonly FavoriteReportCardInput[];
  /** `total_count` do banco (favoritas ativas). */
  totalCount: number;
  references: ReadonlyMap<string, number>;
  ownedCopies: ReadonlyMap<string, number>;
  /** Todas as páginas couberam no teto. */
  withinLimit: boolean;
  /** Posse calculada sobre o acervo inteiro. */
  ownershipComplete: boolean;
  /** Caminho no bucket → URL pública (síncrono); ausente = sem miniaturas. */
  imageUrl?: (path: string) => string | null;
}): FavoritesReport {
  const seen = new Set<string>();
  let duplicated = false;
  const groups = new Map<string, FavoriteReportSet>();
  let pricedCount = 0;
  let ownedCount = 0;
  let totalCents = 0;
  for (const card of input.cards) {
    const id = card.cardId.toLowerCase();
    if (seen.has(id)) {
      duplicated = true; // a lista mudou entre páginas: uma linha por carta, e o relatório fica incompleto
      continue;
    }
    seen.add(id);
    const reference = input.references.get(id);
    const referenceBrl = reference !== undefined && reference > 0 ? reference : null;
    const ownedCopies = input.ownedCopies.get(id) ?? 0;
    if (referenceBrl !== null) {
      pricedCount += 1;
      totalCents += cents(referenceBrl); // uma referência por carta, nunca × exemplares
    }
    if (ownedCopies > 0) ownedCount += 1;
    let set = groups.get(card.cardSetCode);
    if (!set) {
      set = { code: card.cardSetCode, name: card.cardSetName, cards: [] };
      groups.set(card.cardSetCode, set);
    }
    const { imagePath, ...base } = card;
    const imageUrl = imagePath && input.imageUrl ? input.imageUrl(imagePath) : null;
    set.cards.push({ ...base, cardId: id, referenceBrl, ownedCopies, imageUrl });
  }
  const sets = [...groups.values()].sort((a, b) => ORDER.compare(a.name, b.name) || ORDER.compare(a.code, b.code));
  for (const set of sets) {
    set.cards.sort(
      (a, b) =>
        ORDER.compare(a.collectorNumber ?? "￿", b.collectorNumber ?? "￿") || ORDER.compare(a.name, b.name) || (a.cardId < b.cardId ? -1 : 1),
    );
  }
  const favoriteCount = seen.size;
  const incompleteReason: FavoritesIncompleteReason = !input.withinLimit
    ? "too_large"
    : duplicated || favoriteCount !== input.totalCount
      ? "changed"
      : !input.ownershipComplete
        ? "ownership_too_large"
        : null;
  return {
    favoriteCount,
    setCount: sets.length,
    ownedCount,
    pricedCount,
    totalReferenceBrl: pricedCount > 0 ? totalCents / 100 : null,
    sets,
    complete: incompleteReason === null,
    incompleteReason,
  };
}

export function collectorText(card: Pick<FavoriteReportLine, "collectorNumber" | "collectorTotal">): string {
  if (!card.collectorNumber) return "—";
  return card.collectorTotal ? `${card.collectorNumber}/${card.collectorTotal}` : card.collectorNumber;
}

const DATE = new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "America/Sao_Paulo" });

export function favoritedAtText(iso: string): string {
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? "—" : DATE.format(date);
}

export function favoritesSummaryLine(report: Pick<FavoritesReport, "favoriteCount" | "setCount">): string {
  return [plural(report.favoriteCount, "carta favorita", "cartas favoritas"), plural(report.setCount, "Card Set", "Card Sets")].join(" · ");
}

/** "X de Y cartas favoritas com ao menos um exemplar". */
export function favoritesOwnedText(report: Pick<FavoritesReport, "ownedCount" | "favoriteCount">): string {
  return `${formatCount(report.ownedCount)} de ${plural(report.favoriteCount, "carta favorita", "cartas favoritas")} com ao menos um exemplar`;
}

/** "X de Y cartas cotadas (N%)" — proporção de cartas com referência. */
export function favoritesCoverageText(report: Pick<FavoritesReport, "pricedCount" | "favoriteCount">): string {
  return `${formatCount(report.pricedCount)} de ${plural(report.favoriteCount, "carta cotada", "cartas cotadas")} (${shareText(report.pricedCount, report.favoriteCount)})`;
}

export function favoritesIncompleteText(reason: FavoritesIncompleteReason): string | null {
  if (reason === "too_large") return `Você tem mais de ${formatCount(FAVORITES_REPORT_MAX)} cartas favoritas; esta versão não lista todas e a impressão fica indisponível para não sair incompleta.`;
  if (reason === "changed") return "Suas favoritas mudaram durante a leitura. Tente novamente; a impressão fica indisponível.";
  if (reason === "ownership_too_large") return "Não foi possível conferir a posse em todo o acervo; a coluna No acervo pode estar incompleta e a impressão fica indisponível.";
  return null;
}
