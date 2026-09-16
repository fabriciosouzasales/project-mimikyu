// Project Mimikyu — Contrato de ESCOPO POR TAMANHO no lado da revisão editorial.
//
// Módulo puro e sem dependências (nem React, nem Supabase) de propósito: é o
// ponto ÚNICO onde a UI decide o que uma linha de staging significa quando
// `size` entra na conversa, e precisa ser testável fora do bundle do Next.
//
// CONTEXTO (incidente JUMBO, 2026-09-15). Antes deste guard, "NEEDS_REVIEW"
// tinha um significado só na tela: "sem mapeamento — resolva em Card Variant
// Type". Isso deixou de ser verdade. Hoje há TRÊS naturezas distintas, e
// tratá-las como uma só produziria dois erros graves de UX:
//
//   1. oferecer "Resolver mapeamento" para uma linha cujo problema é de
//      ESCOPO, não de vocabulário — um botão que não pode funcionar; e
//   2. contar variantes JUMBO como pendência editorial, inflando para sempre
//      um contador que o administrador nunca conseguiria zerar.
//
// AS TRÊS NATUREZAS
//
//   IN_SCOPE          linha normal. NEEDS_REVIEW aqui significa, como sempre,
//                     falta de mapeamento — e só aqui cabem os controles
//                     editoriais de mapeamento.
//   OUT_OF_SCOPE      JUMBO. validation_status INVALID + decision_status
//                     SKIPPED. Não é erro e não é pendência: é uma variante
//                     que o sistema deliberadamente não cataloga.
//   UNSUPPORTED_SIZE  `size` desconhecido. É pendência HUMANA (NEEDS_REVIEW),
//                     mas NÃO de mapeamento: não existe "mapeamento de
//                     tamanho". O que falta é decisão de escopo.
//
// Espelha, do lado da leitura, o guard server-side da Query 2198 e o gate da
// Edge import-card-variants (services/size-scope.ts).

/** normalized_data.skip_reason das linhas fora de escopo por tamanho. */
export const VARIANT_SKIP_REASON_SIZE_OUT_OF_SCOPE = "SIZE_OUT_OF_SCOPE";

/** normalized_data.review_reason das linhas com `size` desconhecido. */
export const VARIANT_REVIEW_REASON_UNSUPPORTED_SIZE = "UNSUPPORTED_SIZE_VALUE";

export type VariantRowScope = "IN_SCOPE" | "OUT_OF_SCOPE" | "UNSUPPORTED_SIZE";

/** Subconjunto mínimo de CatalogVariantImportRowView de que este contrato depende. */
export type VariantRowScopeInput = {
  validationStatus: string;
  /**
   * PENDING | APPROVED | REJECTED | SKIPPED.
   *
   * Acrescentado em 2026-09-16 (SV5-DEFERRED-UI-SEMANTICS-01). Sem ele, este
   * contrato não conseguia distinguir "ainda não decidida" de "decidida, e a
   * decisão foi deferir" — e contava as duas como pendência. Ver DEFERIMENTO,
   * abaixo.
   */
  decisionStatus: string;
  skipReason: string | null;
  reviewReason: string | null;
};

/**
 * Classifica a natureza de uma linha de staging quanto ao eixo de tamanho.
 *
 * Deliberadamente guiada pelos MARCADORES gravados em normalized_data, não
 * por `validation_status` sozinho: é o marcador que carrega o motivo, e um
 * status sem motivo não distingue as três naturezas.
 */
export function classifyVariantRowScope(row: VariantRowScopeInput): VariantRowScope {
  if (row.skipReason === VARIANT_SKIP_REASON_SIZE_OUT_OF_SCOPE) return "OUT_OF_SCOPE";
  if (row.reviewReason === VARIANT_REVIEW_REASON_UNSUPPORTED_SIZE) return "UNSUPPORTED_SIZE";
  return "IN_SCOPE";
}

/**
 * A linha é uma pendência de MAPEAMENTO — a única que o fluxo "resolver em
 * Card Variant Type" consegue atender.
 *
 * Tamanho desconhecido é NEEDS_REVIEW e continua exigindo decisão humana, mas
 * fica fora daqui de propósito: oferecer resolução por mapeamento converteria
 * uma decisão de escopo em tradução de vocabulário.
 */
export function isVariantRowMappingPending(row: VariantRowScopeInput): boolean {
  return (
    row.validationStatus === "NEEDS_REVIEW" &&
    // DEFERIMENTO (2026-09-16). Pendência é o que ainda espera decisão. Uma
    // linha já decidida — SKIPPED (deferida) ou REJECTED — não é pendência,
    // por mais que continue sem mapeamento: a ausência de mapeamento virou
    // consequência de uma escolha, não uma tarefa em aberto.
    row.decisionStatus === "PENDING" &&
    classifyVariantRowScope(row) === "IN_SCOPE"
  );
}

/**
 * A linha foi DEFERIDA por decisão humana consciente?
 *
 * `decision_status = SKIPPED` fora do eixo de tamanho. É decisão FINAL, e
 * ganha contador próprio justamente para não ser confundida com pendência
 * nem desaparecer da tela: "12 deferidas" é informação; "12 sem mapeamento"
 * num job COMPLETED é mentira.
 *
 * OUT_OF_SCOPE (JUMBO) também chega SKIPPED, mas fica FORA daqui: é decisão
 * do SISTEMA, não do administrador, e já tem contador próprio
 * (`outOfScopeRows`). Misturar as duas apagaria a diferença entre "o sistema
 * não cataloga isso" e "eu decidi não catalogar isso agora".
 */
export function isVariantRowDeferred(row: VariantRowScopeInput): boolean {
  return row.decisionStatus === "SKIPPED" && classifyVariantRowScope(row) !== "OUT_OF_SCOPE";
}

/**
 * Pode exibir controles editoriais de mapeamento (botão "Resolver mapeamento",
 * seleção para aprovação em lote com essa mensagem)?
 *
 * Idêntico a isVariantRowMappingPending por construção — existe como nome
 * próprio para que a intenção fique explícita no ponto de uso da UI e para
 * que uma futura divergência entre "é pendência" e "tem controle" tenha de
 * ser escrita aqui, deliberadamente, e não surgir por descuido em um JSX.
 */
export function canResolveVariantRowMapping(row: VariantRowScopeInput): boolean {
  return isVariantRowMappingPending(row);
}

/**
 * Rótulo curto do motivo, para a coluna de status. `null` quando a linha é
 * IN_SCOPE — nesse caso o rótulo de validação existente já diz tudo.
 */
export function variantRowScopeLabel(row: VariantRowScopeInput): string | null {
  switch (classifyVariantRowScope(row)) {
    case "OUT_OF_SCOPE":
      return "Fora de escopo";
    case "UNSUPPORTED_SIZE":
      return "Tamanho desconhecido";
    default:
      return null;
  }
}

// ===========================================================================
// INVARIANTE DE DECISÃO AUTOMÁTICA (2026-09-16, BLOCKER-1 da auditoria
// SIZE-SCOPE-EDGE-UI-DIFF-AUDIT-01)
//
// `skip_reason = SIZE_OUT_OF_SCOPE` implica `validation_status = INVALID` e
// `decision_status = SKIPPED`. Essa tripla é decisão do SISTEMA, tomada no
// momento da importação, e NÃO é uma decisão editorial em aberto.
//
// A primeira implementação deste guard fechou os eixos "aprovar" e "mapear",
// mas deixou "selecionar", "rejeitar" e "pular" abertos: um clique em
// Rejeitar — ou um "Selecionar todas" que arrastava a linha sem avisar —
// mudava `decision_status` de SKIPPED para REJECTED. A linha saía do universo
// `decision_status IN ('APPROVED','SKIPPED')` da confirmação (Query 2145/2179)
// e ficava com `persistence_status = 'PENDING'` para sempre, além de poluir
// `rejected_rows` com variantes que nunca foram decisão de ninguém.
//
// Daqui em diante a linha fora de escopo é TRAVADA na UI. A garantia real é
// server-side (Query 2199, proposta) — isto aqui é a primeira barreira e o
// que impede o administrador de tentar.
// ===========================================================================

/**
 * A decisão desta linha é automática e imutável?
 *
 * Só OUT_OF_SCOPE. Tamanho desconhecido continua sendo decisão HUMANA em
 * aberto (pode ser rejeitada ou pulada como qualquer pendência) — o que ela
 * não tem é caminho de resolução por mapeamento.
 */
export function isVariantRowScopeLocked(row: VariantRowScopeInput): boolean {
  return classifyVariantRowScope(row) === "OUT_OF_SCOPE";
}

/**
 * A linha pode ser marcada na tabela de revisão?
 *
 * Seleção existe para alimentar as ações em lote. Deixar selecionar uma linha
 * travada só criaria a expectativa de uma ação que vai ser filtrada adiante —
 * pior do que não deixar marcar.
 */
export function isVariantRowSelectable(row: VariantRowScopeInput): boolean {
  return !isVariantRowScopeLocked(row);
}

/** Status de decisão que a UI sabe enviar à RPC `admin_decide_catalog_variant_import_row`. */
export type VariantDecisionStatus = "PENDING" | "APPROVED" | "REJECTED" | "SKIPPED";

/**
 * Esta linha aceita ESTA decisão?
 *
 * Linha travada só aceita `SKIPPED` — e aceita de propósito, para que uma
 * chamada idempotente (a linha já está SKIPPED) continue sendo um no-op
 * legítimo, sem exigir que todo caller conheça o eixo de tamanho.
 * `APPROVED`, `REJECTED` e `PENDING` são recusados.
 */
export function canDecideVariantRow(row: VariantRowScopeInput, status: VariantDecisionStatus): boolean {
  if (!isVariantRowScopeLocked(row)) return true;
  return status === "SKIPPED";
}

export type VariantImportScopeCounters = {
  /**
   * PENDÊNCIA de mapeamento: NEEDS_REVIEW + decisão ainda PENDING + IN_SCOPE.
   * É a única população que a tela de Card Variant Type consegue atender.
   */
  mappingPendingRows: number;
  /**
   * PENDÊNCIA de escopo: `size` desconhecido + decisão ainda PENDING.
   * Decisão humana, sem mapeamento a resolver.
   */
  unsupportedSizeRows: number;
  /** INVALID por JUMBO — decisão automática do sistema, não é pendência. */
  outOfScopeRows: number;
  /**
   * DEFERIDAS: decisão humana FINAL de pular (SKIPPED), fora do eixo JUMBO.
   * Não é pendência e não é erro — é escolha registrada.
   */
  deferredRows: number;
};

/**
 * Deriva os três contadores de escopo de uma coleção COMPLETA de linhas.
 *
 * Ponto único de verdade (2026-09-16, BLOCKER-2/RISCO-3). O desenho anterior
 * fazia três `HEAD count` independentes no servidor e derivava o resumo da
 * tabela no cliente — duas populações distintas, que divergiam em qualquer
 * job acima do teto de paginação do PostgREST, e cujo `count ?? 0` convertia
 * falha de leitura em "zero pendências".
 *
 * Esta função não lê nada: recebe as linhas que o chamador já garantiu
 * completas (via `fetchAllRowsStrict`) e conta. Painel e tabela chamam a
 * MESMA função sobre a MESMA população, então não têm como divergir.
 */
export function deriveVariantImportScopeCounters(rows: VariantRowScopeInput[]): VariantImportScopeCounters {
  let mappingPendingRows = 0;
  let unsupportedSizeRows = 0;
  let outOfScopeRows = 0;
  let deferredRows = 0;

  for (const row of rows) {
    // 1. JUMBO primeiro e incondicionalmente: decisão automática do sistema,
    //    contador próprio, nunca reclassificada por decisão humana.
    if (classifyVariantRowScope(row) === "OUT_OF_SCOPE") {
      outOfScopeRows++;
      continue;
    }

    // 2. Deferida: decisão humana FINAL. Precede as pendências de propósito —
    //    uma linha SKIPPED não é pendência de nada, seja qual for o motivo
    //    que a levou a NEEDS_REVIEW.
    if (isVariantRowDeferred(row)) {
      deferredRows++;
      continue;
    }

    // 3. As duas naturezas de PENDÊNCIA — ambas exigem decisão ainda em
    //    aberto. REJECTED cai fora das duas: é decisão final e já aparece no
    //    contador "Rejeitadas" do painel.
    if (row.decisionStatus !== "PENDING") continue;

    if (classifyVariantRowScope(row) === "UNSUPPORTED_SIZE") unsupportedSizeRows++;
    else if (row.validationStatus === "NEEDS_REVIEW") mappingPendingRows++;
  }

  return { mappingPendingRows, unsupportedSizeRows, outOfScopeRows, deferredRows };
}
