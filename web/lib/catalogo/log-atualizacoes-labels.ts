/**
 * Rótulos amigáveis para `/catalogo/log-atualizacoes` — fonte única em todo
 * o frontend (filtros e tabela importam daqui, nunca duplicam a lista) para
 * as 7 `entity_type` e os 21 `action` reais de `catalog_admin_action_log`
 * (universo confirmado em 2026-08-09 contra as migrations `2098`/`2121` —
 * o arquivo canônico `2010` estava desatualizado, ver `ADR-023` e
 * `05e-catalogo-editorial.md`). A classificação Cadastro/Alteração/
 * Exclusão/Outras é calculada no banco (`internal.catalog_admin_action_
 * category()`), nunca aqui — este arquivo só traduz para exibição, nunca
 * reclassifica nada.
 */

export const ENTITY_TYPE_OPTIONS: { value: string; label: string }[] = [
  { value: "GAME", label: "Jogo" },
  { value: "EXPANSION", label: "Expansão" },
  { value: "CARD_SET", label: "Coleção" },
  { value: "CARD", label: "Carta" },
  { value: "CATALOG_IMPORT_JOB", label: "Importação" },
  { value: "RARITY", label: "Raridade" },
  { value: "RARITY_EXTERNAL_MAPPING", label: "Mapeamento de Raridade" },
];

export const ACTION_OPTIONS: { value: string; label: string }[] = [
  { value: "GAME_CREATED", label: "Jogo criado" },
  { value: "GAME_UPDATED", label: "Jogo atualizado" },
  { value: "GAME_DELETED", label: "Jogo excluído" },
  { value: "EXPANSION_CREATED", label: "Expansão criada" },
  { value: "EXPANSION_UPDATED", label: "Expansão atualizada" },
  { value: "EXPANSION_DELETED", label: "Expansão excluída" },
  { value: "CARD_SET_CREATED", label: "Coleção criada" },
  { value: "CARD_SET_UPDATED", label: "Coleção atualizada" },
  { value: "CARD_SET_DELETED", label: "Coleção excluída" },
  { value: "CARD_CREATED", label: "Carta criada" },
  { value: "CARD_UPDATED", label: "Carta atualizada" },
  { value: "CARD_DEACTIVATED", label: "Carta desativada" },
  { value: "CARD_REACTIVATED", label: "Carta reativada" },
  { value: "CATALOG_IMPORT_JOB", label: "Importação iniciada" },
  { value: "CATALOG_IMPORT_CONFIRMED", label: "Importação confirmada" },
  { value: "CATALOG_IMPORT_ROWS_REVALIDATED", label: "Importação revalidada" },
  { value: "RARITY_CREATED", label: "Raridade criada" },
  { value: "RARITY_UPDATED", label: "Raridade atualizada" },
  { value: "RARITY_EXTERNAL_MAPPING_CREATED", label: "Mapeamento de raridade criado" },
  { value: "RARITY_EXTERNAL_MAPPING_UPDATED", label: "Mapeamento de raridade atualizado" },
  { value: "CARD_ASSET_MANUAL_IMPORT_COMPLETED", label: "Importação manual de imagens concluída" },
];

export const ENTITY_TYPE_LABEL: Record<string, string> = Object.fromEntries(
  ENTITY_TYPE_OPTIONS.map((option) => [option.value, option.label]),
);

export const ACTION_LABEL: Record<string, string> = Object.fromEntries(
  ACTION_OPTIONS.map((option) => [option.value, option.label]),
);

export const CATEGORY_LABEL: Record<string, string> = {
  CADASTRO: "Cadastro",
  ALTERACAO: "Alteração",
  EXCLUSAO: "Exclusão",
  OUTRAS: "Outras",
};

/**
 * Rótulo amigável por chave de `metadata` — usado só pelo Dialog de
 * Detalhes, para não expor `snake_case` cru. Chave sem entrada aqui cai no
 * fallback de `humanizeMetadataKey` (humanização automática).
 */
export const METADATA_KEY_LABEL: Record<string, string> = {
  name: "Nome",
  code: "Código",
  card_set_id: "Coleção (id)",
  card_set_name: "Coleção",
  card_set_code: "Código da Coleção",
  source: "Origem",
  final_status: "Status final",
  rows_updated: "Linhas atualizadas",
  rows_unblocked: "Linhas destravadas",
  run_id: "Lote (id)",
  language_code: "Idioma",
  files_total: "Arquivos no lote",
  inserted_count: "Inseridos",
  updated_count: "Atualizados",
  failed_count: "Falharam",
  failures: "Falhas",
  symbol_code: "Código do símbolo",
  display_order: "Ordem de exibição",
  external_value: "Valor externo",
  normalized_external_value: "Valor externo normalizado",
  rarity_id: "Raridade (id)",
  category_id: "Categoria (id)",
  collector_total: "Total de cartas",
  collector_order: "Ordem no set",
  game_id: "Jogo (id)",
  release_order: "Ordem de lançamento",
  expansion_id: "Expansão (id)",
};

export function humanizeMetadataKey(key: string): string {
  return METADATA_KEY_LABEL[key] ?? key.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}
