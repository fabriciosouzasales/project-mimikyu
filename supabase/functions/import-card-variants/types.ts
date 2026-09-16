// Project Mimikyu — Edge Function: import-card-variants
// Tipos do processador de importação de Card Variant (Incremento 2 do
// bloco Card Variant, ADR-028). Recebe um Card Set MMKYU, resolve o
// dataset-fonte da TCGdex no GitHub, correlaciona cada Card externa via
// card_external_reference e grava propostas em catalog_variant_import_row
// — nunca em card_variant (Princípio da Fonte Canônica, ADR-024).
//
// Diferença deliberada frente a import-catalog-cards: aqui não existe
// ainda uma tela/RPC que abra o job com external_set_id já resolvido
// (CV-02 — sem tela dedicada no V1). Por isso o contrato de entrada desta
// function é { card_set_id }, não { job_id } — a resolução do
// external_set_id e a criação do catalog_variant_import_job acontecem
// dentro desta própria function (ver index.ts).

export type RequestBody = {
  card_set_id?: string;
};

export type CardSetWithGame = {
  id: string;
  code: string;
  name: string;
  total_set_size: number;
  expansion_id: string;
  game_id: string;
};

export type VariantImportJob = {
  id: string;
  card_set_id: string;
  source: string;
  external_set_id: string;
  status: string;
  progress_step: string | null;
};

// Combinação bruta de variante extraída de um arquivo-fonte do GitHub —
// ver services/github-source.ts. stamp preserva fielmente zero, um ou
// múltiplos elementos, exatamente como a Query 2140 (v1.1) modela.
//
// size (2026-09-15, incidente JUMBO): o dataset-fonte da TCGdex emite um
// atributo `size` por variante (na prática `standard` ou `jumbo`). Ele era
// silenciosamente descartado pelo extrator, o que fazia uma variante JUMBO
// entrar no pipeline como se fosse STANDARD. Passa a ser preservado aqui e
// classificado no index.ts ANTES de routePrinting/dedupe. size NÃO entra na
// identidade da variante (não participa de residual signature nem do
// pareamento de mapeamento) — é exclusivamente um eixo de ESCOPO.
export type ExternalVariantCombo = {
  type: string;
  foil: string | null;
  subtype: string | null;
  stamp: string[] | null;
  size: string | null;
};

// Linha pronta para INSERT em catalog_variant_import_row.
//
// validation_status = "INVALID" (2026-09-15): reservado para linhas fora do
// escopo do sistema por tamanho (JUMBO). Não é erro de importação e não é
// pendência editorial — ver normalized_data.skip_reason = SIZE_OUT_OF_SCOPE.
export type ResolvedVariantRow = {
  card_id: string;
  raw_data: Record<string, unknown>;
  normalized_data: Record<string, unknown>;
  validation_status: "VALID" | "NEEDS_REVIEW" | "INVALID";
  match_status: "NEW" | "MATCHED";
  decision_status: "PENDING" | "SKIPPED";
  matched_variant_id: string | null;
};
