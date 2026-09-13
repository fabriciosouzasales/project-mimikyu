/**
 * Rótulos amigáveis para `/catalogo/log-atualizacoes` — fonte única em todo
 * o frontend (filtros e tabela importam daqui, nunca duplicam a lista) para
 * os `entity_type`/`action` reais de `catalog_admin_action_log`. Universo
 * original (7 entity_type / 21 action) confirmado em 2026-08-09 contra as
 * migrations `2098`/`2121` (ver `ADR-023` e `05e-catalogo-editorial.md`);
 * ampliado em 2026-08-16 com os 3 entity_type / 4 action do módulo
 * Governança de Variantes (`ADR-028`), que passaram a gravar em
 * `catalog_admin_action_log` sem que este dicionário fosse atualizado —
 * causa raiz do diagnóstico de 2026-08-16. A classificação Cadastro/
 * Alteração/Exclusão/Outras é calculada no banco (`internal.catalog_admin_
 * action_category()`), nunca aqui — este arquivo só traduz para exibição,
 * nunca reclassifica nada.
 *
 * STAGED / NOT DEPLOYED (2026-09-12, `PRINTING-ROUTING — STAGING-REVISION-01`):
 * as entradas marcadas `CARD_PRINTING_EXTERNAL_MAPPING*` referem-se a valores
 * que só passam a existir no banco com a Query 2185 (PHASE B do rollout de
 * Impressão), ainda NÃO aplicada. Antes disso elas são inertes: filtros
 * simplesmente não retornam nada. Depois disso elas são obrigatórias — sem
 * elas a tela exibiria o enum técnico cru, que foi a causa raiz do
 * diagnóstico de 2026-08-16.
 *
 * RESÍDUO CONHECIDO, fora do escopo desta rodada: a coluna "Registro" do Log
 * de Atualizações resolve o nome da entidade por um ramo dedicado dentro de
 * `admin_list_catalog_action_log()` (Query 2127). Não existe ramo para
 * `CARD_PRINTING_EXTERNAL_MAPPING`, então esses eventos exibirão o UUID cru
 * até que esse ramo seja criado. Decisão consciente: alterar aquela RPC é
 * mudança de contrato de leitura do log, não de roteamento.
 */

export const ENTITY_TYPE_OPTIONS: { value: string; label: string }[] = [
  { value: "GAME", label: "Jogo" },
  { value: "EXPANSION", label: "Expansão" },
  { value: "CARD_SET", label: "Coleção" },
  { value: "CARD", label: "Carta" },
  { value: "CATALOG_IMPORT_JOB", label: "Importação" },
  { value: "RARITY", label: "Raridade" },
  { value: "RARITY_EXTERNAL_MAPPING", label: "Mapeamento de Raridade" },
  { value: "CARD_VARIANT_TYPE", label: "Tipo de Variação" },
  { value: "CATALOG_VARIANT_IMPORT_JOB", label: "Importação de Variações" },
  { value: "CARD_VARIANT_TYPE_EXTERNAL_MAPPING", label: "Mapeamento Externo" },
  // STAGED / NOT DEPLOYED — passa a existir com a Query 2185 (PHASE B do
  // rollout de Impressão). Sem esta entrada o Log de Atualizações exibiria
  // o enum técnico cru, que foi o incidente de 2026-08-16.
  { value: "CARD_PRINTING_EXTERNAL_MAPPING", label: "Mapeamento de Impressão" },
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
  { value: "CARD_VARIANT_TYPE_CREATED", label: "Tipo de variação criado" },
  { value: "CARD_VARIANT_TYPE_UPDATED", label: "Tipo de variação atualizado" },
  { value: "CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED", label: "Mapeamento externo criado" },
  { value: "CARD_VARIANT_IMPORT_CONFIRMED", label: "Importação de variações confirmada" },
  // STAGED / NOT DEPLOYED — ver comentário em ENTITY_TYPE_OPTIONS.
  { value: "CARD_PRINTING_EXTERNAL_MAPPING_CREATED", label: "Mapeamento de impressão criado" },
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
  // STAGED / NOT DEPLOYED — metadata gravado pela Query 2181 (Impressão).
  asset_source_id: "Fonte (id)",
  raw_field: "Campo externo",
  external_token: "Token externo",
  normalized_token: "Token normalizado",
  trait_ids: "Características de impressão (ids)",
  supersedes_mapping_id: "Substitui o mapeamento (id)",
  origin_row_id: "Linha de origem (id)",
  rows_revalidated: "Linhas revalidadas",
  rows_still_pending: "Linhas ainda pendentes",
  jobs_affected: "Importações afetadas",
};

export function humanizeMetadataKey(key: string): string {
  return METADATA_KEY_LABEL[key] ?? key.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}
