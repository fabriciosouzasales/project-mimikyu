// Project Mimikyu — Edge Function: import-catalog-cards
// Tipos do processador TCGdex do Ciclo 2 (ADR-024, Catalog Card Ingestion
// Strategy). Plano apresentado e aprovado por Fabrício em 2026-08-01, com
// dois ajustes: (1) localização automática do Set na TCGdex, sem exigir
// external_set_id manual no fluxo principal — resolvida ANTES desta função,
// fora dela; (2) categoria da TCGdex como fonte primária, heurística só
// como fallback quando a API não fornece categoria válida.

export type RequestBody = {
  job_id?: string;
};

export type CatalogImportJob = {
  id: string;
  card_set_id: string;
  source: string;
  external_set_id: string | null;
  status: string;
  progress_step: string | null;
};

// card_set + game_id (via expansion) — rarity/card_category são catálogos
// por Game (Query 130/132), não globais.
export type CardSetWithGame = {
  id: string;
  code: string;
  name: string;
  total_set_size: number;
  expansion_id: string;
  game_id: string;
};

export type ExistingCard = {
  id: string;
  collector_number: string;
  name: string;
  rarity_id: string;
  category_id: string;
  collector_total: number | null;
};

export type Rarity = {
  id: string;
  code: string;
  name: string;
};

export type CardCategoryRow = {
  id: string;
  code: string; // POKEMON | TRAINER | ENERGY
  name: string;
};

export type CategorySource =
  | "API"
  | "ENERGY_PREFIX"
  | "POKEMON_MATCH"
  | "TRAINER_FALLBACK";

export type CategoryConfidence = "HIGH" | "MEDIUM" | "LOW";

// Formato exigido por catalog_import_row.normalized_data — nomes de campo
// exatamente como lidos por admin_confirm_catalog_import() (Query 2082) e
// documentados em database/schema/2070_create_catalog_import_row.sql.
// review_notes é um campo extra (o JSONB é aberto — "inclui, entre outros"
// no comentário da coluna), usado só para a tela de Revisão explicar por
// que uma linha nasceu NEEDS_REVIEW; nunca lido por admin_confirm_catalog_import().
export type NormalizedData = {
  name: string;
  collector_number: string;
  collector_total: number | null;
  collector_order: number;
  rarity_id: string | null;
  category_id: string | null;
  category: string | null;
  category_source: CategorySource | null;
  category_confidence: CategoryConfidence | null;
  review_notes: string[] | null;
};

export type PreparedRow = {
  raw_data: Record<string, unknown>;
  normalized_data: NormalizedData;
  validation_status: "VALID" | "NEEDS_REVIEW" | "INVALID";
  match_status: "NEW" | "MATCHED" | "CONFLICT";
  decision_status: "PENDING" | "SKIPPED";
  matched_card_id: string | null;
};