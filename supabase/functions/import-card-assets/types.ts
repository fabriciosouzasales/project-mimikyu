// Project Mimikyu — Edge Function: import-card-assets
// Tipos extraídos do index.ts monolítico (Sprint B2.4.1 — CONFIRMADO CONCLUÍDO).
// Ver docs/06-pipeline-importacao.md, "Sprint B2.4.1", para o contexto completo.

export type RequestBody = {
  run_code?: string;
};

export type ImportRun = {
  id: string;
  run_code: string;
  asset_source_id: string;
  card_set_id: string;
  language_id: string;
  run_type: string;
  status: string;
};

export type CardSet = {
  id: string;
  expansion_id: string;
  code: string;
  name: string;
  set_type: string;
  release_order: number;
  release_date: string | null;
  base_set_size: number;
  total_set_size: number;
};

export type Card = {
  id: string;
  card_set_id: string;
  rarity_id: string;
  category_id: string;
  collector_number: string;
  collector_total: number | null;
  collector_order: number;
  name: string;
};
