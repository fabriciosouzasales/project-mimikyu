// Project Mimikyu — Edge Function: import-catalog-cards
// Normalize Service — resolve cada carta da TCGdex para o formato exigido
// por catalog_import_row.normalized_data e decide validation_status/
// match_status/decision_status.

import type {
  CardCategoryRow,
  CategoryConfidence,
  CategorySource,
  ExistingCard,
  NormalizedData,
  PreparedRow,
  Rarity,
} from "../types.ts";
import type { TcgdexCardDetail, TcgdexSetDetail } from "./tcgdex.ts";

const CATEGORY_BY_TCGDEX_VALUE: Record<string, string> = {
  Pokemon: "POKEMON",
  Trainer: "TRAINER",
  Energy: "ENERGY",
};

export function normalizeRarityCode(raw: string): string {
  return raw.trim().toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_+|_+$/g, "");
}

export function resolveCategory(
  tcgCard: TcgdexCardDetail,
): { category: string; source: CategorySource; confidence: CategoryConfidence } {
  const apiCategory = CATEGORY_BY_TCGDEX_VALUE[tcgCard.category];
  if (apiCategory) {
    return { category: apiCategory, source: "API", confidence: "HIGH" };
  }
  return resolveCategoryByHeuristic(tcgCard);
}

function resolveCategoryByHeuristic(
  tcgCard: TcgdexCardDetail,
): { category: string; source: CategorySource; confidence: CategoryConfidence } {
  const name = tcgCard.name ?? "";

  if (/^energia\b/i.test(name) || /^energy\b/i.test(name)) {
    return { category: "ENERGY", source: "ENERGY_PREFIX", confidence: "MEDIUM" };
  }
  if (Array.isArray(tcgCard.dexId) && tcgCard.dexId.length > 0) {
    return { category: "POKEMON", source: "POKEMON_MATCH", confidence: "MEDIUM" };
  }
  return { category: "TRAINER", source: "TRAINER_FALLBACK", confidence: "LOW" };
}

export function deriveCollectorOrder(localId: string, indexInSet: number): number {
  const numeric = Number(localId);
  return Number.isInteger(numeric) && numeric > 0 ? numeric : indexInSet + 1;
}

export function resolveCollectorTotal(set: TcgdexSetDetail): number | null {
  return set.cardCount?.official ?? set.cardCount?.total ?? null;
}

type BuildRowInput = {
  tcgCard: TcgdexCardDetail;
  indexInSet: number;
  collectorTotal: number | null;
  raritiesByCode: Map<string, Rarity>;
  categoriesByCode: Map<string, CardCategoryRow>;
  existingCardsByCollectorNumber: Map<string, ExistingCard>;
  seenCollectorNumbers: Set<string>;
  extraNote?: string | null;
};

export function buildImportRow(input: BuildRowInput): PreparedRow {
  const {
    tcgCard, indexInSet, collectorTotal, raritiesByCode, categoriesByCode,
    existingCardsByCollectorNumber, seenCollectorNumbers, extraNote,
  } = input;

  const notes: string[] = extraNote ? [extraNote] : [];

  const collectorNumber = String(tcgCard.localId);
  const collectorOrder = deriveCollectorOrder(collectorNumber, indexInSet);

  const duplicate = seenCollectorNumbers.has(collectorNumber);
  seenCollectorNumbers.add(collectorNumber);
  if (duplicate) notes.push(`COLLECTOR_NUMBER_DUPLICADO: ${collectorNumber}`);

  const { category, source: categorySource, confidence: categoryConfidence } = resolveCategory(tcgCard);
  const categoryRow = categoriesByCode.get(category);
  if (!categoryRow) notes.push(`CATEGORIA_NAO_CADASTRADA: ${category}`);

  let rarityRow: Rarity | undefined;
  if (tcgCard.rarity) {
    rarityRow = raritiesByCode.get(normalizeRarityCode(tcgCard.rarity));
    if (!rarityRow) notes.push(`RARIDADE_NAO_MAPEADA: ${tcgCard.rarity}`);
  } else {
    notes.push("RARIDADE_AUSENTE_NA_TCGDEX");
  }

  const normalizedData: NormalizedData = {
    name: tcgCard.name,
    collector_number: collectorNumber,
    collector_total: collectorTotal,
    collector_order: collectorOrder,
    rarity_id: rarityRow?.id ?? null,
    category_id: categoryRow?.id ?? null,
    category,
    category_source: categorySource,
    category_confidence: categoryConfidence,
    review_notes: notes.length > 0 ? notes : null,
  };

  const blockingIssues = !rarityRow || !categoryRow || duplicate || categoryConfidence === "LOW";
  const validationStatus = !tcgCard.name || !collectorNumber
    ? "INVALID"
    : blockingIssues
    ? "NEEDS_REVIEW"
    : "VALID";

  const existingCard = existingCardsByCollectorNumber.get(collectorNumber);
  let matchStatus: "NEW" | "MATCHED" | "CONFLICT" = "NEW";
  let matchedCardId: string | null = null;

  if (existingCard) {
    matchedCardId = existingCard.id;
    const identical = existingCard.name === normalizedData.name &&
      existingCard.rarity_id === normalizedData.rarity_id &&
      existingCard.category_id === normalizedData.category_id &&
      (existingCard.collector_total ?? null) === (normalizedData.collector_total ?? null);
    matchStatus = identical ? "MATCHED" : "CONFLICT";
  }

  const decisionStatus: "PENDING" | "SKIPPED" = matchStatus === "MATCHED" ? "SKIPPED" : "PENDING";

  return {
    raw_data: tcgCard as unknown as Record<string, unknown>,
    normalized_data: normalizedData,
    validation_status: validationStatus,
    match_status: matchStatus,
    decision_status: decisionStatus,
    matched_card_id: matchedCardId,
  };
}