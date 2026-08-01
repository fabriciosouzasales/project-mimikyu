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

// Inclui as duas formas (inglês e português) porque `tcgCard.category` vem
// da própria TCGdex no idioma pedido (TCGDEX_LANGUAGE) — com "pt" ela
// devolve "Pokémon"/"Treinador"/"Energia", não "Pokemon"/"Trainer"/"Energy".
// Bug real, descoberto junto com o de raridade na remediação do ME5
// (2026-08-01): só as chaves em inglês existiam aqui, então toda carta
// Treinador caía no fallback heurístico (resolveCategoryByHeuristic) com
// confidence "LOW" — o valor final (TRAINER) até saía certo por coincidência
// (é o default do fallback), mas "LOW" bloqueia a linha em NEEDS_REVIEW à
// toa (ver blockingIssues em buildImportRow). Cartas Pokémon não travavam
// porque o fallback por dexId dá confidence "MEDIUM" (não bloqueia), mas
// ainda assim classificava via heurística em vez de via API por engano.
const CATEGORY_BY_TCGDEX_VALUE: Record<string, string> = {
  Pokemon: "POKEMON",
  "Pokémon": "POKEMON",
  Trainer: "TRAINER",
  Treinador: "TRAINER",
  Energy: "ENERGY",
  Energia: "ENERGY",
};

// Normaliza um nome de raridade para comparação: remove acentos, deixa em
// maiúsculas, colapsa espaços. Usado tanto para o nome vindo da TCGdex
// (raw_data.rarity, em português desde a correção do idioma para "pt") quanto
// para o `name` cadastrado em public.rarity — evita depender de bater
// caractere a caractere (ex.: "Ilustração Rara" vs "ilustração  rara").
//
// Bug real, descoberto na remediação do ME5 (2026-08-01): a versão anterior
// desta função normalizava para comparar contra `rarity.code` (em inglês,
// ex. "ULTRA_RARE"), mas a TCGdex em "pt" devolve o nome em português
// ("Ultra Rara"), então nada batia e as 120 linhas caíam em NEEDS_REVIEW.
// A comparação correta é contra `rarity.name` (também em português).
export function normalizeRarityLookupKey(raw: string): string {
  return raw
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .toUpperCase()
    .replace(/\s+/g, " ");
}

// A TCGdex ("pt") e a nossa tabela `rarity` às vezes usam ordem de palavras
// ou flexão de gênero diferentes para o mesmo conceito de raridade — a
// normalização acima (acentos/caixa/espaços) não resolve isso sozinha.
// Mapeamento explícito descoberto na remediação do ME5 (2026-08-01), chave e
// valor já passados por normalizeRarityLookupKey:
// - TCGdex "Ultra Rara" vs. cadastrado "Rara Ultra"
// - TCGdex "Mega Hiper Raro" vs. cadastrado "Mega Rara Hiper"
// Se surgir uma raridade nova sem alias aqui, ela cai em NEEDS_REVIEW (não
// silenciosamente errada) — comportamento seguro por desenho.
const RARITY_NAME_ALIASES: Record<string, string> = {
  "ULTRA RARA": "RARA ULTRA",
  "MEGA HIPER RARO": "MEGA RARA HIPER",
};

export function resolveRarityLookupKey(raw: string): string {
  const normalized = normalizeRarityLookupKey(raw);
  return RARITY_NAME_ALIASES[normalized] ?? normalized;
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
  // Chaveado por normalizeRarityLookupKey(rarity.name) — não por rarity.code.
  // Ver comentário de resolveRarityLookupKey acima.
  raritiesByName: Map<string, Rarity>;
  categoriesByCode: Map<string, CardCategoryRow>;
  existingCardsByCollectorNumber: Map<string, ExistingCard>;
  seenCollectorNumbers: Set<string>;
  extraNote?: string | null;
};

export function buildImportRow(input: BuildRowInput): PreparedRow {
  const {
    tcgCard, indexInSet, collectorTotal, raritiesByName, categoriesByCode,
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
    rarityRow = raritiesByName.get(resolveRarityLookupKey(tcgCard.rarity));
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