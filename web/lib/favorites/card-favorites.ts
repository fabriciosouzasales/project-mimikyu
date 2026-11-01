/**
 * Favoritos de cartas (V1-10) — regras puras.
 *
 * Contrato (C-82–C-90; Queries 5335/5336, propostas): o favorito é da Card (`card_id`),
 * pertence ao usuário (identidade só por `auth.uid()` no banco — o cliente nunca envia
 * `user_id`), é binário e independe de acervo, coleção e variante.
 * `set_card_favorite(card, desejado)` DEFINE o estado (não alterna) e é idempotente.
 *
 * Reaproveita a Espécie favorita da Pokédex (P6, `lib/pokedex/favorites.ts`) sem
 * alterá-la: a máquina de intenção (otimista, uma gravação por vez, última intenção
 * vence), o mapeamento de erros e os textos são os mesmos — aqui só muda a chave
 * (UUID da carta em vez do número nacional).
 */

import {
  type FavoriteEntry,
  type FavoriteOutcome,
  type SetFavoriteResult,
  favoriteAnnouncement,
  favoriteErrorMessage,
  favoriteFailureReason,
  favoriteSpeciesNameFromLabel,
  favoriteToggleLabel,
  initialFavoriteEntry,
  settleFavorite,
  toggleFavorite,
} from "../pokedex/favorites.ts";

export {
  type FavoriteEntry,
  type FavoriteOutcome,
  type SetFavoriteResult,
  favoriteAnnouncement,
  favoriteErrorMessage,
  favoriteFailureReason,
  favoriteToggleLabel,
  initialFavoriteEntry,
};

/** Nome da carta a partir do nome acessível do botão ("Favoritar Pikachu"). */
export const favoriteCardNameFromLabel = favoriteSpeciesNameFromLabel;

// ---------------------------------------------------------------------------
// Identificadores e lotes
// ---------------------------------------------------------------------------

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** UUID válido em minúsculas, ou `null`. */
export function normalizeId(value: unknown): string | null {
  return typeof value === "string" && UUID.test(value) ? value.toLowerCase() : null;
}

/** Teto por chamada das leituras em lote (5336: 1..500 ids). */
export const FAVORITE_IDS_PER_CALL = 500;

/** Ids válidos, distintos, em blocos de até 500 — nunca uma chamada por carta. */
export function chunkIds(ids: readonly unknown[], size = FAVORITE_IDS_PER_CALL): string[][] {
  const unique = [...new Set(ids.map(normalizeId).filter((id): id is string => id !== null))];
  const out: string[][] = [];
  for (let i = 0; i < unique.length; i += size) out.push(unique.slice(i, i + size));
  return out;
}

/** Linhas de `get_my_card_favorite_ids` → conjunto. Linhas fora do contrato são descartadas. */
export function toFavoriteIdSet(rows: readonly { card_id?: unknown }[]): Set<string> {
  const set = new Set<string>();
  for (const row of rows) {
    const id = normalizeId(row?.card_id);
    if (id) set.add(id);
  }
  return set;
}

/** Estado favorito de uma variante (Acervo): a carta dela e se é favorita. */
export type VariantFavorite = { cardId: string; isFavorite: boolean };

/** Linhas de `get_my_card_favorites_by_variant` → mapa variante → carta + estado. */
export function toVariantFavoriteMap(
  rows: readonly { card_variant_id?: unknown; card_id?: unknown; is_favorite?: unknown }[],
): Map<string, VariantFavorite> {
  const map = new Map<string, VariantFavorite>();
  for (const row of rows) {
    const variantId = normalizeId(row?.card_variant_id);
    const cardId = normalizeId(row?.card_id);
    if (!variantId || !cardId || typeof row.is_favorite !== "boolean") continue;
    map.set(variantId, { cardId, isFavorite: row.is_favorite });
  }
  return map;
}

// ---------------------------------------------------------------------------
// Página "Cartas favoritas"
// ---------------------------------------------------------------------------

export type FavoriteCard = {
  cardId: string;
  name: string;
  collectorNumber: string;
  collectorTotal: number | null;
  cardSetCode: string;
  cardSetName: string;
  imagePathPt: string | null;
  imagePathEn: string | null;
  favoritedAt: string;
};

export type FavoriteCardsPage = { cards: FavoriteCard[]; totalCount: number };

/** Tamanho da página de favoritos (5336 aceita 1..100). */
export const FAVORITES_PAGE_SIZE = 60;

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

/** Linhas de `get_my_favorite_cards` → página. `null` = resposta fora do contrato. */
export function parseFavoriteCardsPage(data: unknown): FavoriteCardsPage | null {
  if (!Array.isArray(data)) return null;
  const cards: FavoriteCard[] = [];
  let totalCount = 0;
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row) continue;
    const cardId = normalizeId(row.card_id);
    const name = text(row.card_name);
    const favoritedAt = text(row.favorited_at);
    if (!cardId || !name || !favoritedAt) continue;
    const total = Number(row.total_count);
    if (Number.isFinite(total) && total > totalCount) totalCount = Math.floor(total);
    const collectorTotal = row.collector_total === null || row.collector_total === undefined ? null : Number(row.collector_total);
    cards.push({
      cardId,
      name,
      collectorNumber: text(row.collector_number) ?? "",
      collectorTotal: collectorTotal !== null && Number.isFinite(collectorTotal) ? collectorTotal : null,
      cardSetCode: text(row.card_set_code) ?? "",
      cardSetName: text(row.card_set_name) ?? "",
      imagePathPt: text(row.image_path_pt),
      imagePathEn: text(row.image_path_en),
      favoritedAt,
    });
  }
  return { cards, totalCount: Math.max(totalCount, cards.length) };
}

/** Página pedida na URL (`?pagina=`) → número válido (1 por padrão). */
export function parsePageParam(value: string | string[] | undefined): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const page = Number(raw);
  return Number.isInteger(page) && page >= 1 && page <= 1000 ? page : 1;
}

// ---------------------------------------------------------------------------
// Máquina de intenção por carta (a da P6, chaveada por UUID)
// ---------------------------------------------------------------------------

/** Gravação a disparar: `set_card_favorite(cardId, value)`. */
export type CardFavoriteSend = { cardId: string; value: boolean };

export type CardFavoriteStep = { entry: FavoriteEntry; send: CardFavoriteSend | null };

/** Clique no coração: inverte o que está na tela e grava, se nada estiver em andamento. */
export function toggleCardFavorite(cardId: string, entry: FavoriteEntry): CardFavoriteStep {
  const step = toggleFavorite(0, entry);
  return { entry: step.entry, send: step.send ? { cardId, value: step.send.value } : null };
}

/** Fim de uma gravação: confirma, reenvia a intenção atual ou reverte (falha). */
export function settleCardFavorite(
  cardId: string,
  entry: FavoriteEntry,
  outcome: FavoriteOutcome,
): CardFavoriteStep & { reverted: boolean } {
  const step = settleFavorite(0, entry, outcome);
  return { entry: step.entry, send: step.send ? { cardId, value: step.send.value } : null, reverted: step.reverted };
}

/* ---- Painel de números da página Cartas favoritas (PREMIUM HERO & KPI REFINEMENT-07) ----
 * Quatro indicadores no mesmo painel de Minhas coleções. Só entram números que um
 * contrato sustenta; leitura indisponível aparece como "—", nunca como zero.
 *  Ordem (MOBILE KPI VISUAL CORRECTION-24): o valor de referência abre o painel e é o
 *  destaque (lead) — no celular ocupa a primeira linha inteira.
 *  1. Valor de referência — soma de UMA referência NM por carta favorita ativa
 *     (get_cards_pricing_summary, a mesma da Pesquisa), sem multiplicar por exemplares,
 *     sempre com cobertura "X de Y com cotação" (5340). Exibido em reais inteiros
 *     (arredondado só na apresentação). Sem cobertura nenhuma: "—", nunca "R$ 0".
 *  2. Cartas favoritas — card_id distintos (total_count da 5336; preferência, não posse).
 *  3. No meu acervo — card_id favoritos ativos com ≥ 1 exemplar no Inventory do próprio
 *     usuário; cópias, variantes e idiomas contam uma vez; independe de coleção (5339).
 *  4. Card Sets com cartas favoritas — card_set_id distintos das favoritas ativas
 *     (5338, CORRECTION-13). Independe de posse, acervo e coleção; vínculo
 *     canônico card.card_set_id. Substitui "Coleções com favoritas" (5337, sem consumidor).
 */
export type FavoritesKpi = {
  key: "favorites" | "reference_value" | "owned" | "favorite_card_sets";
  /** Já formatado; `null` = indicador sem dado (sem cobertura ou leitura falhou) — exibir "—". */
  value: string | null;
  name: string;
  hint: string;
  lead?: boolean;
};

/** Leitura agregada da 5340 (contagens já validadas como inteiros ≥ 0). */
export type FavoriteReferenceValue = {
  favoriteCount: number;
  pricedCount: number;
  /** BRL; `null` quando nenhuma favorita tem cotação. */
  totalBrl: number | null;
};

/**
 * Lê a resposta da 5340 (uma linha: favorite_count, priced_count, total_brl). Aceita a
 * linha solta ou dentro de array (PostgREST devolve conjunto). Contagens inteiras ≥ 0,
 * priced ≤ favorite; total finito ≥ 0 ou nulo, e nulo exatamente quando priced = 0.
 * Qualquer outra forma → `null` (o painel mostra "—", nunca um número inventado).
 */
export function parseFavoriteReferenceValue(data: unknown): FavoriteReferenceValue | null {
  const row = Array.isArray(data) ? (data.length === 1 ? data[0] : null) : data;
  if (!row || typeof row !== "object") return null;
  const record = row as Record<string, unknown>;
  const toInt = (value: unknown) => {
    const n = typeof value === "number" ? value : typeof value === "string" ? Number(value) : NaN;
    return Number.isInteger(n) && n >= 0 ? n : null;
  };
  const favoriteCount = toInt(record.favorite_count);
  const pricedCount = toInt(record.priced_count);
  if (favoriteCount === null || pricedCount === null || pricedCount > favoriteCount) return null;
  const rawTotal = record.total_brl;
  let totalBrl: number | null = null;
  if (rawTotal !== null && rawTotal !== undefined) {
    const n = typeof rawTotal === "number" ? rawTotal : typeof rawTotal === "string" ? Number(rawTotal) : NaN;
    if (!Number.isFinite(n) || n < 0) return null;
    totalBrl = n;
  }
  if ((pricedCount === 0) !== (totalBrl === null)) return null;
  return { favoriteCount, pricedCount, totalBrl };
}

/**
 * Reais inteiros para o painel (CORRECTION-24): "R$ 3.207". Só apresentação — o valor
 * original (com centavos) segue intacto em `FavoriteReferenceValue.totalBrl`.
 */
const brlWhole = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL",
  minimumFractionDigits: 0,
  maximumFractionDigits: 0,
});

export function formatBrlWhole(value: number): string {
  return brlWhole.format(value);
}

function referenceValueKpi(
  reference: FavoriteReferenceValue | null,
  format: (value: number) => string,
  formatMoney: (value: number) => string,
): FavoritesKpi {
  const base = { key: "reference_value" as const, name: "Valor de referência", lead: true };
  if (reference === null) return { ...base, value: null, hint: "indisponível agora" };
  const { favoriteCount, pricedCount, totalBrl } = reference;
  if (favoriteCount === 0) return { ...base, value: null, hint: "sem cartas favoritas" };
  const coverage = `${format(pricedCount)} de ${format(favoriteCount)} com cotação`;
  if (pricedCount === 0 || totalBrl === null) return { ...base, value: null, hint: coverage };
  return { ...base, value: formatMoney(totalBrl), hint: coverage };
}

export function favoritesKpis(input: {
  favoriteCount: number;
  /** Valor de referência (5340); `null` = leitura indisponível. */
  referenceValue: FavoriteReferenceValue | null;
  /** Favoritas que o usuário possui (5339); `null` = leitura indisponível. */
  ownedCount: number | null;
  /** Card Sets com cartas favoritas (5338); `null` = leitura indisponível. */
  favoriteCardSetCount: number | null;
  format: (value: number) => string;
  formatMoney: (value: number) => string;
}): FavoritesKpi[] {
  const { favoriteCount, referenceValue, ownedCount, favoriteCardSetCount: count, format, formatMoney } = input;
  return [
    referenceValueKpi(referenceValue, format, formatMoney),
    {
      key: "favorites",
      value: format(favoriteCount),
      name: favoriteCount === 1 ? "Carta favorita" : "Cartas favoritas",
      hint: "marcadas por você",
    },
    {
      key: "owned",
      value: ownedCount === null ? null : format(ownedCount),
      name: "No meu acervo",
      hint: ownedCount === null ? "indisponível agora" : "favoritas que você possui",
    },
    {
      key: "favorite_card_sets",
      value: count === null ? null : format(count),
      name: count === 1 ? "Card Set" : "Card Sets",
      hint: count === null ? "indisponível agora" : "com cartas favoritas",
    },
  ];
}
