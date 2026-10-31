/**
 * Preço NM por posição nas coleções de Set, Master Set e Pokédex (V1-09 Fase B)
 * — regras puras.
 *
 * Contrato (docs/05f-pricing.md, "Preço NM na Collection (V1-09)", Fase B):
 *  - Posição com exemplares de UMA única variante → etiqueta dessa variante
 *    (preço unitário, mesmo com várias cópias).
 *  - Variantes diferentes na mesma posição → nenhuma etiqueta (nunca o preço de
 *    uma variante atribuído a outra; nenhum "a partir de" nem soma).
 *  - Posição sem exemplar → nada.
 *  - Master Set: a posição é carta + acabamento; só contam os exemplares desse
 *    acabamento. Posição genérica de carta secreta: todos os exemplares da carta.
 *  - Pokédex: a arte da posição é de UM exemplar (o representante); o preço é o
 *    da variante desse exemplar, e só aparece se a carta lida (número + Set)
 *    coincidir com a carta exibida pela 5204.
 * Fontes: 5333 (variantes por carta) e 5334 (representante da Pokédex).
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function uuid(value: unknown): string | null {
  return typeof value === "string" && UUID.test(value) ? value.toLowerCase() : null;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : null;
}

/** Variante resolvida de uma posição: a chave do preço e o que o detalhe exibe. */
export type PositionVariant = {
  cardVariantId: string;
  /** Etiqueta do catálogo (tipo · impressão · edição) — nome da variante no detalhe. */
  variantLabel: string | null;
  /** Idioma dos exemplares, quando único (nota D4 do detalhe); senão `null`. */
  languageCode: string | null;
};

// ---------------------------------------------------------------------------
// 5333 — variantes por carta (Set e Master Set)
// ---------------------------------------------------------------------------

export type CardVariantRow = {
  cardId: string;
  variantTypeId: string | null;
  cardVariantId: string;
  variantLabel: string | null;
  languageCode: string | null;
  copies: number;
};

/** Linhas da 5333 → registros. `null` = resposta que não é lista (falha de leitura). */
export function parseCardVariantRows(data: unknown): CardVariantRow[] | null {
  if (!Array.isArray(data)) return null;
  const rows: CardVariantRow[] = [];
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row) continue;
    const cardId = uuid(row.card_id);
    const cardVariantId = uuid(row.card_variant_id);
    const copies = Number(row.copies);
    if (!cardId || !cardVariantId || !Number.isFinite(copies) || copies <= 0) continue;
    rows.push({
      cardId,
      variantTypeId: uuid(row.variant_type_id),
      cardVariantId,
      variantLabel: text(row.variant_label),
      languageCode: text(row.language_code),
      copies: Math.floor(copies),
    });
  }
  return rows;
}

/** Uma variante só entre as linhas → essa variante; zero ou mais de uma → `null`. */
export function singleVariant(rows: readonly CardVariantRow[]): PositionVariant | null {
  const variants = new Set(rows.map((row) => row.cardVariantId));
  const first = rows[0];
  if (variants.size !== 1 || !first) return null;
  const languages = new Set(rows.map((row) => row.languageCode));
  return {
    cardVariantId: first.cardVariantId,
    variantLabel: first.variantLabel,
    languageCode: languages.size === 1 ? first.languageCode : null,
  };
}

/** Set padrão: posição = carta. Mapa carta → variante (só posições não ambíguas). */
export function setPositionVariants(rows: readonly CardVariantRow[]): Map<string, PositionVariant> {
  const byCard = new Map<string, CardVariantRow[]>();
  for (const row of rows) {
    const list = byCard.get(row.cardId);
    if (list) list.push(row);
    else byCard.set(row.cardId, [row]);
  }
  const result = new Map<string, PositionVariant>();
  for (const [cardId, list] of byCard) {
    const variant = singleVariant(list);
    if (variant) result.set(cardId, variant);
  }
  return result;
}

/**
 * Master Set: posição = carta + acabamento (`variantTypeId`), ou carta secreta
 * genérica (`variantTypeId` nulo, qualquer acabamento). Chave = `positionKey`.
 */
export function masterPositionVariants(
  rows: readonly CardVariantRow[],
  positions: readonly { key: string; cardId: string; variantTypeId: string | null }[],
): Map<string, PositionVariant> {
  const result = new Map<string, PositionVariant>();
  for (const position of positions) {
    const cardId = position.cardId.toLowerCase();
    const typeId = position.variantTypeId ? position.variantTypeId.toLowerCase() : null;
    const matching = rows.filter((row) => row.cardId === cardId && (typeId === null || row.variantTypeId === typeId));
    const variant = singleVariant(matching);
    if (variant) result.set(position.key, variant);
  }
  return result;
}

// ---------------------------------------------------------------------------
// 5334 — representante da Pokédex
// ---------------------------------------------------------------------------

export type RepresentativeVariantRow = PositionVariant & {
  positionId: string;
  collectorNumber: string | null;
  cardSetCode: string | null;
};

/** Linhas da 5334 → registros. `null` = resposta que não é lista. */
export function parseRepresentativeRows(data: unknown): RepresentativeVariantRow[] | null {
  if (!Array.isArray(data)) return null;
  const rows: RepresentativeVariantRow[] = [];
  for (const raw of data) {
    const row = raw as Record<string, unknown> | null;
    if (!row) continue;
    const positionId = uuid(row.pokedex_position_id);
    const cardVariantId = uuid(row.card_variant_id);
    if (!positionId || !cardVariantId) continue;
    rows.push({
      positionId,
      cardVariantId,
      variantLabel: text(row.variant_label),
      languageCode: text(row.language_code),
      collectorNumber: text(row.collector_number),
      cardSetCode: text(row.card_set_code),
    });
  }
  return rows;
}

/**
 * Pokédex: posição → variante do representante, só quando a carta lida pela
 * 5334 é a mesma exibida pela 5204 (número e Set). Divergência (regra de
 * representante mudou de um lado só, vínculo alterado entre as leituras) →
 * nenhuma etiqueta.
 */
export function pokedexPositionVariants(
  rows: readonly RepresentativeVariantRow[],
  positions: readonly {
    positionId: string;
    isSatisfied: boolean;
    representative: { collectorNumber: string | null; setCode: string | null } | null;
  }[],
): Map<string, PositionVariant> {
  const byPosition = new Map(rows.map((row) => [row.positionId, row]));
  const result = new Map<string, PositionVariant>();
  for (const position of positions) {
    if (!position.isSatisfied || !position.representative) continue;
    const id = position.positionId.toLowerCase();
    const row = byPosition.get(id);
    if (!row) continue;
    const sameNumber = row.collectorNumber !== null && row.collectorNumber === position.representative.collectorNumber;
    const sameSet =
      row.cardSetCode !== null &&
      position.representative.setCode !== null &&
      row.cardSetCode.toLowerCase() === position.representative.setCode.toLowerCase();
    if (!sameNumber || !sameSet) continue;
    result.set(id, { cardVariantId: row.cardVariantId, variantLabel: row.variantLabel, languageCode: row.languageCode });
  }
  return result;
}

/** Ids de variante distintos de um mapa de posições (entrada do lote de preços, 3983). */
export function positionVariantIds(map: ReadonlyMap<string, PositionVariant>): string[] {
  return [...new Set([...map.values()].map((variant) => variant.cardVariantId))];
}
