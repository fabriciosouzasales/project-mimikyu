// Project Mimikyu — Núcleo compartilhado de normalização de catálogo.
// Extraído de supabase/functions/import-catalog-cards/{types.ts,services/
// normalize.ts} em 2026-08-06, como parte do cadastro self-service de
// Raridade (Ajuste arquitetural, ponto 2: "não duplicar lógica de
// normalização — uma única implementação reutilizável deve servir tanto
// import-catalog-cards quanto a futura revalidate-catalog-import-rows").
//
// Tipos aqui são a forma canônica usada pelas DUAS Edge Functions: quem
// resolve uma carta pela primeira vez (import-catalog-cards, a partir da
// TCGdex) e quem revalida uma linha já em staging (revalidate-catalog-
// import-rows, a partir de raw_data já armazenado) devem enxergar
// exatamente os mesmos formatos de entrada/saída.

// Forma mínima de "uma carta bruta", como recebida da TCGdex e como
// persistida em catalog_import_row.raw_data. Só os campos que a resolução
// de raridade/categoria/sequência realmente lê — não é o tipo completo de
// TcgdexCardDetail (que continua vivendo em import-catalog-cards/services/
// tcgdex.ts, específico do cliente HTTP). Na revalidação, row.raw_data (já
// armazenado como JSONB) é lido de volta nesta mesma forma.
export type RawCatalogCard = {
  name: string;
  localId: string | number;
  category: string;
  rarity?: string | null;
  dexId?: unknown[] | null;
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

export type ExistingCard = {
  id: string;
  collector_number: string;
  name: string;
  rarity_id: string;
  category_id: string;
  collector_total: number | null;
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
// review_notes é um campo extra (o JSONB é aberto), usado só para a tela de
// Revisão explicar por que uma linha nasceu NEEDS_REVIEW; nunca lido por
// admin_confirm_catalog_import().
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

export type ResolvedCatalogRow = {
  raw_data: Record<string, unknown>;
  normalized_data: NormalizedData;
  validation_status: "VALID" | "NEEDS_REVIEW" | "INVALID";
  match_status: "NEW" | "MATCHED" | "CONFLICT";
  decision_status: "PENDING" | "SKIPPED";
  matched_card_id: string | null;
};
