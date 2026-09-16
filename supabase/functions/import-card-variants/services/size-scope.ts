// Project Mimikyu — Edge Function: import-card-variants
// Eixo de ESCOPO POR TAMANHO (`size`) — espelho client-side do guard
// server-side da Query 2198 (internal.compute_variant_residual_signature).
//
// CONTEXTO (incidente JUMBO, 2026-09-15)
// A TCGdex modela `size` no objeto de variante (`size: "jumbo"`). O extractor
// da Edge lia apenas type/foil/subtype/stamp — `size` era silenciosamente
// descartado, e uma variante JUMBO entrava no pipeline indistinguível da sua
// gêmea STANDARD.
//
// DECISÃO EDITORIAL PRESERVADA
// `size` NÃO integra a identidade da variante: não entra na assinatura
// residual, não participa do pareamento de mapeamento, não distingue duas
// Card Variants canônicas. Ele decide APENAS se a linha está dentro ou fora
// do escopo do sistema. Por isso a classificação acontece ANTES do
// roteamento de Impressão e do dedupe — uma linha fora de escopo não deve
// sequer consumir mapeamentos de Printing nem gerar pendência editorial.
//
// QUATRO RAMOS, FAIL-CLOSED — idênticos aos da Query 2198 (linhas 206-218):
//
//   ausente / null / string em branco  -> IN_SCOPE (fluxo legado, bit a bit)
//   normalizado = 'STANDARD'           -> IN_SCOPE (fluxo legado, bit a bit)
//   normalizado = 'JUMBO'              -> OUT_OF_SCOPE  (SIZE_OUT_OF_SCOPE)
//   qualquer outro valor não vazio     -> UNSUPPORTED   (UNSUPPORTED_SIZE_VALUE)
//
// O quarto ramo é fail-closed por construção: um valor que a TCGdex passe a
// emitir amanhã (`oversized`, `mini`, …) não entra em produção por omissão —
// para revisão humana, e SEM caminho de resolução editorial por mapeamento,
// porque não existe "mapeamento de tamanho": o que falta é decisão de
// ESCOPO, não tradução de vocabulário.
//
// A paridade com o SQL é do ALGORITMO, não do código — mesma razão já
// documentada em _shared/catalog-normalization/normalize-value.ts.

import { normalizeExternalCatalogValue } from "../../_shared/catalog-normalization/mod.ts";

/** Marcador gravado em normalized_data.skip_reason para linhas JUMBO. */
export const SIZE_OUT_OF_SCOPE = "SIZE_OUT_OF_SCOPE";

/** Marcador gravado em normalized_data.review_reason para `size` desconhecido. */
export const UNSUPPORTED_SIZE_VALUE = "UNSUPPORTED_SIZE_VALUE";

/** Único valor de `size` que o sistema trata como dentro de escopo. */
export const SIZE_IN_SCOPE = "STANDARD";

/** Único valor conhecido e deliberadamente fora de escopo. */
export const SIZE_OUT_OF_SCOPE_VALUE = "JUMBO";

export type SizeScopeClassification =
  /** Fluxo legado — segue para routePrinting/dedupe exatamente como antes. */
  | { kind: "IN_SCOPE"; normalizedSize: string | null }
  /** JUMBO — fora do escopo do sistema. Não é erro e não é pendência editorial. */
  | { kind: "OUT_OF_SCOPE"; normalizedSize: string; skipReason: typeof SIZE_OUT_OF_SCOPE }
  /** Valor desconhecido — revisão humana, sem resolução por mapeamento. */
  | { kind: "UNSUPPORTED"; normalizedSize: string; reviewReason: typeof UNSUPPORTED_SIZE_VALUE };

/**
 * Classifica o `size` bruto de uma variante externa.
 *
 * Espelha `internal.compute_variant_residual_signature` (Query 2198). Só
 * `IN_SCOPE` deve prosseguir para o roteamento de Impressão.
 */
export function classifyVariantSize(rawSize: string | null | undefined): SizeScopeClassification {
  if (rawSize === null || rawSize === undefined) {
    return { kind: "IN_SCOPE", normalizedSize: null };
  }

  const normalized = normalizeExternalCatalogValue(rawSize);

  // `btrim(v_size) <> ''` no SQL. normalizeExternalCatalogValue já apara as
  // pontas, então uma string só de espaços chega aqui como "".
  if (normalized === "") {
    return { kind: "IN_SCOPE", normalizedSize: null };
  }

  if (normalized === SIZE_IN_SCOPE) {
    return { kind: "IN_SCOPE", normalizedSize: normalized };
  }

  if (normalized === SIZE_OUT_OF_SCOPE_VALUE) {
    return { kind: "OUT_OF_SCOPE", normalizedSize: normalized, skipReason: SIZE_OUT_OF_SCOPE };
  }

  return { kind: "UNSUPPORTED", normalizedSize: normalized, reviewReason: UNSUPPORTED_SIZE_VALUE };
}
