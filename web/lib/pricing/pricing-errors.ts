/**
 * Traduz as mensagens `RAISE EXCEPTION` das RPCs administrativas de
 * Pendências + Resolução de Mapeamentos (Bloco 2 do Pricing Admin,
 * migration 3940) para o texto exibido ao usuário. Mesmo espírito de
 * `traduzirErroCatalogo` (lib/supabase/catalogo-errors.ts) — códigos em
 * `CODIGO_MAIUSCULO: ...` —, mas com mapa explícito por código em vez de só
 * extrair o texto após o `:`: várias destas exceções carregam detalhe
 * técnico depois dos dois-pontos (ex.: `id=% status=%`), que não deve
 * chegar cru à tela.
 */
const KNOWN_CODES: Record<string, string> = {
  ADMIN_LIST_PRICING_PENDING_MAPPINGS_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_GET_PRICING_MAPPING_DETAIL_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_RESOLVE_PRICING_MAPPING_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_GET_PRICING_MAPPING_DETAIL_NOT_FOUND: "Mapeamento não encontrado — ele pode ter sido removido.",
  ADMIN_RESOLVE_PRICING_MAPPING_NOT_FOUND: "Mapeamento não encontrado — ele pode ter sido removido.",
  ADMIN_RESOLVE_PRICING_MAPPING_ALREADY_DECIDED:
    "Este mapeamento já foi decidido por outro administrador. Volte para Pendências e atualize a lista.",
  ADMIN_RESOLVE_PRICING_MAPPING_INVALID_DECISION: "Decisão inválida — escolha Confirmar ou Rejeitar.",
  ADMIN_RESOLVE_PRICING_MAPPING_REJECT_REASON_REQUIRED: "Informe o motivo da rejeição.",
  ADMIN_RESOLVE_PRICING_MAPPING_ASSIGNMENTS_REQUIRED: "Selecione ao menos uma identidade para confirmar.",
  ADMIN_RESOLVE_PRICING_MAPPING_IDENTITY_INCOMPATIBLE:
    "Uma ou mais identidades selecionadas não estão mais disponíveis para confirmação. Atualize a página e tente novamente.",
  ADMIN_RESOLVE_PRICING_MAPPING_NO_PRIMARY_CONFIRMED:
    "É necessário confirmar uma identidade como Principal (PRIMARY) para concluir.",
  // Bloco 3 (migration 3941 + 3937/3938, já validadas) — Saúde das Fontes,
  // Histórico de Execuções, Sincronizações.
  ADMIN_GET_PRICING_SOURCE_HEALTH_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_LIST_PRICING_SYNC_RUNS_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_GET_PRICING_SYNC_RUN_DETAIL_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_LIST_PRICING_SET_REFRESH_STATES_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_GET_PRICING_SYNC_RUN_DETAIL_NOT_FOUND: "Execução não encontrada — ela pode ter sido removida.",
  ADMIN_SET_PRICING_REFRESH_FREQUENCY_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_SET_PRICING_REFRESH_FREQUENCY_MISSING_SOURCE: "Fonte de preço não informada.",
  ADMIN_SET_PRICING_REFRESH_FREQUENCY_INVALID_VALUE: "Frequência inválida — escolha 1, 2, 3 ou 5 dias.",
  ADMIN_SET_PRICING_REFRESH_FREQUENCY_SOURCE_NOT_FOUND: "Fonte de preço não encontrada.",
  // Bloco 4 (migration 3942) — Cadastros: Fontes de Preço, Mapeamentos de
  // Sets, Mapeamentos de Cartas, Condições.
  ADMIN_LIST_PRICING_SOURCES_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_LIST_PRICING_SET_MAPPINGS_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_LIST_PRICING_CARD_MAPPINGS_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_LIST_CARD_CONDITIONS_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_UPDATE_PRICING_SOURCE_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_UPDATE_PRICING_SOURCE_NOT_FOUND: "Fonte de preço não encontrada — ela pode ter sido removida.",
  ADMIN_UPDATE_PRICING_SOURCE_MISSING_NAME: "Informe o nome da fonte.",
  ADMIN_UPDATE_PRICING_SET_MAPPING_DETAILS_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_UPDATE_PRICING_SET_MAPPING_DETAILS_NOT_FOUND: "Mapeamento de Set não encontrado — ele pode ter sido removido.",
  SET_MAPPING_HAS_DEPENDENT_PRICING_DATA:
    "Este Set já tem mapeamentos de carta confirmados ou dados de preço vinculados a esta fonte — alterar o identificador externo ou reclassificar fica reservado para um fluxo de reconciliação futuro.",
  ADMIN_RECLASSIFY_PRICING_SET_MAPPING_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_RECLASSIFY_PRICING_SET_MAPPING_INVALID_STATUS: "Escolha Confirmar ou Rejeitar.",
  ADMIN_RECLASSIFY_PRICING_SET_MAPPING_MISSING_REASON: "Informe o motivo da reclassificação.",
  ADMIN_RECLASSIFY_PRICING_SET_MAPPING_NOT_FOUND: "Mapeamento de Set não encontrado — ele pode ter sido removido.",
  ADMIN_RECLASSIFY_PRICING_SET_MAPPING_INVALID_CURRENT_STATUS:
    "Só é possível reclassificar mapeamentos já Confirmados ou Rejeitados.",
  ADMIN_RECLASSIFY_PRICING_SET_MAPPING_NO_OP: "Este mapeamento já está neste status. Atualize a página e tente novamente.",
  ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_INVALID_STATUS: "Escolha Confirmar ou Rejeitar.",
  ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_MISSING_REASON: "Informe o motivo da reclassificação.",
  ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_NOT_FOUND: "Mapeamento de carta não encontrado — ele pode ter sido removido.",
  ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_INVALID_CURRENT_STATUS:
    "Só é possível reclassificar mapeamentos já Confirmados ou Rejeitados — use Resolução de Mapeamentos para os demais.",
  ADMIN_RECLASSIFY_PRICING_CARD_MAPPING_NO_OP: "Este mapeamento já está neste status. Atualize a página e tente novamente.",
  CARD_MAPPING_HAS_DEPENDENT_PRICING_DATA:
    "Este mapeamento já tem produto ou observação de preço vinculado — reclassificação direta bloqueada, fica reservada para um fluxo de reconciliação futuro.",
  ADMIN_UPSERT_CARD_CONDITION_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_UPSERT_CARD_CONDITION_MISSING_CODE: "Informe o código da condição.",
  ADMIN_UPSERT_CARD_CONDITION_MISSING_NAME: "Informe o nome da condição.",
  ADMIN_UPSERT_CARD_CONDITION_INVALID_ORDER: "Ordem inválida — use um número inteiro maior que zero.",
  ADMIN_UPSERT_CARD_CONDITION_DUPLICATE_CODE: "Já existe uma condição com este código.",
  ADMIN_UPSERT_CARD_CONDITION_DUPLICATE_NAME: "Já existe uma condição com este nome.",
  ADMIN_UPSERT_CARD_CONDITION_NOT_FOUND: "Condição não encontrada — ela pode ter sido removida.",
  ADMIN_UPSERT_PRICING_CONDITION_MAPPING_FORBIDDEN: "Acesso restrito a administradores.",
  ADMIN_UPSERT_PRICING_CONDITION_MAPPING_MISSING_EXTERNAL_CODE: "Informe o código externo da condição.",
  ADMIN_UPSERT_PRICING_CONDITION_MAPPING_MISSING_SOURCE: "Fonte de preço não informada.",
  ADMIN_UPSERT_PRICING_CONDITION_MAPPING_MISSING_CONDITION: "Condição não informada.",
  ADMIN_UPSERT_PRICING_CONDITION_MAPPING_CONDITION_NOT_FOUND: "Condição não encontrada — ela pode ter sido removida.",
  CONDITION_INACTIVE_CANNOT_RECEIVE_MAPPING: "Esta condição está inativa — reative-a antes de vinculá-la a uma fonte.",
  ADMIN_UPSERT_PRICING_CONDITION_MAPPING_NOT_FOUND: "Vínculo não encontrado — ele pode ter sido removido.",
};

export function traduzirErroPricing(message: string): string {
  const match = message.match(/^([A-Z][A-Z0-9_]*):\s*(.*)$/);
  if (!match) {
    return "Não foi possível concluir a ação. Tente novamente em instantes.";
  }

  const code = match[1];
  const rest = match[2];
  if (code && KNOWN_CODES[code]) {
    return KNOWN_CODES[code];
  }

  // Código desconhecido mas com texto legível após os dois-pontos (sem
  // "=" de interpolação técnica) — mesmo fallback de traduzirErroCatalogo.
  if (rest && !rest.includes("=")) {
    return rest;
  }

  return "Não foi possível concluir a ação. Tente novamente em instantes.";
}
