// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Extraído de import-catalog-cards/services/normalize.ts (buildImportRow)
// em 2026-08-06, generalizado para servir tanto a resolução inicial
// (import-catalog-cards, a partir da TCGdex) quanto a revalidação
// (revalidate-catalog-import-rows, a partir de raw_data já armazenado) —
// mesma função, dois chamadores, nenhuma lógica duplicada (Ajuste
// arquitetural, ponto 2).
//
// Ponto 4 do mesmo Ajuste ("recalcular o estado por completo, nunca
// depender do texto de review_notes"): esta função nunca lê um
// normalized_data/review_notes anterior — recebe sempre dado bruto
// (rawCard) e mapas de referência atuais (raridade, categoria, cards já
// cadastrados), e recalcula normalized_data/validation_status/
// match_status/matched_card_id/review_notes inteiramente do zero a cada
// chamada. collector_total é a única exceção: não é recalculável sem uma
// nova chamada HTTP à TCGdex (é uma propriedade do Set, não da carta), e
// não depende de nenhuma tabela de mapeamento que a revalidação exista
// para corrigir — por isso é sempre recebido como parâmetro (a importação
// inicial busca do Set recém-obtido; a revalidação lê do normalized_data
// já armazenado na própria linha, sem nunca reformular a partir dele
// nenhum outro campo).

import { resolveCategory } from "./category.ts";
import { resolveRarity } from "./rarity.ts";
import type { RarityMappingLookup } from "./rarity.ts";
import type { CardCategoryRow, ExistingCard, NormalizedData, RawCatalogCard, ResolvedCatalogRow } from "./types.ts";

export function deriveCollectorOrder(localId: string, indexInSet: number): number {
  const numeric = Number(localId);
  return Number.isInteger(numeric) && numeric > 0 ? numeric : indexInSet + 1;
}

/**
 * Preenche `collectorNumber` com zeros à esquerda até a mesma quantidade de
 * dígitos de `collectorTotal` — bug real corrigido (2026-08-11, Fabrício:
 * cartas apareciam como "#1/185" em vez de "#001/185" na galeria). A TCGdex
 * devolve `localId` sem padding ("1", não "001") e este era o único ponto
 * de resolução que gravava o valor bruto direto em `collector_number`.
 *
 * Largura derivada de `collectorTotal` (não de um número fixo de dígitos)
 * porque o padrão correto varia por Coleção — "01/88" para uma Coleção de
 * 88 cartas, "001/185" para uma de 185; nunca forçar 3 dígitos
 * universalmente (produziria "010/88", exatamente o formato que Fabrício
 * pediu para nunca permitir). Só aplica padding a números puramente
 * numéricos — preserva formatos alfanuméricos da TCGdex sem alteração
 * (ex.: "TG01", "SWSH001" já vêm formatados pela própria fonte).
 * `collectorTotal` nulo (Set sem total conhecido) mantém o valor bruto,
 * sem largura de referência para calcular o padding.
 */
export function padCollectorNumber(rawNumber: string, collectorTotal: number | null): string {
  if (collectorTotal === null || collectorTotal <= 0) return rawNumber;
  if (!/^[0-9]+$/.test(rawNumber)) return rawNumber;
  const width = String(collectorTotal).length;
  return rawNumber.padStart(width, "0");
}

export type ResolveCatalogRowInput = {
  rawCard: RawCatalogCard;
  // Objeto completo a persistir em catalog_import_row.raw_data — hoje
  // sempre o próprio rawCard (cast), mantido como parâmetro separado para
  // a revalidação poder repassar o raw_data já armazenado sem precisar
  // reconstruí-lo.
  rawData: Record<string, unknown>;
  indexInSet: number;
  collectorTotal: number | null;
  rarityMappingByNormalizedValue: RarityMappingLookup;
  categoriesByCode: Map<string, CardCategoryRow>;
  existingCardsByCollectorNumber: Map<string, ExistingCard>;
  // Mutado pela função — mesmo padrão de buildImportRow original: cada
  // carta processada em sequência marca seu próprio collector_number como
  // visto, para detectar duplicidade dentro do mesmo lote.
  seenCollectorNumbers: Set<string>;
  extraNote?: string | null;
};

export function resolveCatalogImportRow(input: ResolveCatalogRowInput): ResolvedCatalogRow {
  const {
    rawCard, rawData, indexInSet, collectorTotal, rarityMappingByNormalizedValue, categoriesByCode,
    existingCardsByCollectorNumber, seenCollectorNumbers, extraNote,
  } = input;

  const notes: string[] = extraNote ? [extraNote] : [];

  const rawCollectorNumber = String(rawCard.localId);
  const collectorOrder = deriveCollectorOrder(rawCollectorNumber, indexInSet);
  const collectorNumber = padCollectorNumber(rawCollectorNumber, collectorTotal);

  const duplicate = seenCollectorNumbers.has(collectorNumber);
  seenCollectorNumbers.add(collectorNumber);
  if (duplicate) notes.push(`COLLECTOR_NUMBER_DUPLICADO: ${collectorNumber}`);

  const { category, source: categorySource, confidence: categoryConfidence } = resolveCategory(rawCard);
  const categoryRow = categoriesByCode.get(category);
  if (!categoryRow) notes.push(`CATEGORIA_NAO_CADASTRADA: ${category}`);

  const { rarity: rarityRow, note: rarityNote } = resolveRarity(rawCard.rarity, rarityMappingByNormalizedValue);
  if (rarityNote) notes.push(rarityNote);

  const normalizedData: NormalizedData = {
    name: rawCard.name,
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
  const validationStatus = !rawCard.name || !collectorNumber
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
    raw_data: rawData,
    normalized_data: normalizedData,
    validation_status: validationStatus,
    match_status: matchStatus,
    decision_status: decisionStatus,
    matched_card_id: matchedCardId,
  };
}
