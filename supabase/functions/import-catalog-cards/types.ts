// Project Mimikyu — Edge Function: import-catalog-cards
// Tipos do processador TCGdex do Ciclo 2 (ADR-024, Catalog Card Ingestion
// Strategy). Plano apresentado e aprovado por Fabrício em 2026-08-01, com
// dois ajustes: (1) localização automática do Set na TCGdex, sem exigir
// external_set_id manual no fluxo principal — resolvida ANTES desta função,
// fora dela; (2) categoria da TCGdex como fonte primária, heurística só
// como fallback quando a API não fornece categoria válida.
//
// 2026-08-06 (cadastro self-service de Raridade): ExistingCard, Rarity,
// CardCategoryRow, CategorySource, CategoryConfidence, NormalizedData e
// PreparedRow (renomeado ResolvedCatalogRow) foram movidos para
// _shared/catalog-normalization/types.ts — reexportados aqui para não
// quebrar nenhum import existente dentro desta função. Só o que é
// genuinamente específico deste processador (requisição HTTP, job,
// card_set+game) continua definido localmente.

export type {
  CardCategoryRow,
  CategoryConfidence,
  CategorySource,
  ExistingCard,
  NormalizedData,
  Rarity,
  ResolvedCatalogRow as PreparedRow,
} from "../_shared/catalog-normalization/types.ts";

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