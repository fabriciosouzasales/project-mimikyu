/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2126 - Create internal.catalog_admin_action_category() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-09

Descrição...:
Function pura (sem acesso a dados, LANGUAGE sql IMMUTABLE) que
classifica cada `action` real de public.catalog_admin_action_log
em uma de 4 categorias de negócio: CADASTRO, ALTERACAO, EXCLUSAO,
OUTRAS. Fonte única de verdade para essa classificação — usada por
admin_list_catalog_action_log() (Query 2127, coluna `category` da
tabela) e admin_get_catalog_action_log_weekly_summary() (Query
2128, agregação dos 3 gráficos semanais). Vive no schema `internal`
(ADR-023 — não exposto pela API, EXECUTE revogado de PUBLIC/anon/
authenticated) porque não é um contrato RPC público: só é chamada
de dentro de outra função SECURITY DEFINER do mesmo owner.

Mapa completo aprovado por Fabrício (2026-08-09), classificado
semanticamente ação a ação contra as migrations 2098/2121 (não só
por sufixo de string) — o arquivo canônico 2010 estava desatualizado
(15 ações), universo real confirmado em 21:

- CADASTRO: GAME_CREATED, EXPANSION_CREATED, CARD_SET_CREATED,
  CARD_CREATED, RARITY_CREATED, RARITY_EXTERNAL_MAPPING_CREATED.
- ALTERACAO: GAME_UPDATED, EXPANSION_UPDATED, CARD_SET_UPDATED,
  CARD_UPDATED, RARITY_UPDATED, RARITY_EXTERNAL_MAPPING_UPDATED.
- EXCLUSAO: GAME_DELETED, EXPANSION_DELETED, CARD_SET_DELETED —
  confirmado via leitura das 3 functions (admin_delete_game/
  admin_delete_expansion/admin_delete_card_set) que todas fazem
  DELETE FROM real, não soft-delete.
- OUTRAS (ELSE, cobre as 6 restantes): CARD_DEACTIVATED/
  CARD_REACTIVATED (soft-delete reversível, decisão explícita de
  Fabrício de mantê-las fora de EXCLUSAO), CATALOG_IMPORT_JOB/
  CATALOG_IMPORT_CONFIRMED/CATALOG_IMPORT_ROWS_REVALIDATED/
  CARD_ASSET_MANUAL_IMPORT_COMPLETED (eventos agregados de
  pipeline/lote, não cadastro/alteração/exclusão pontual de uma
  entidade).

Regras de Negócio:
- IMMUTABLE: o mapeamento action → categoria nunca depende de
  estado do banco, só do argumento — permite ao planner do Postgres
  tratar chamadas repetidas na mesma query como determinísticas.
- ELSE 'OUTRAS' (não um valor sentinela como NULL/'DESCONHECIDA'):
  qualquer ação futura ainda não mapeada aqui cai em OUTRAS por
  padrão, nunca quebra a function nem precisa de RAISE EXCEPTION —
  decisão deliberada para não acoplar a evolução da lista de
  actions à manutenção obrigatória desta function.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
- Query 2098/2121 - CHECK constraints atuais (universo real de 21
  actions).
================================================================
*/

CREATE OR REPLACE FUNCTION internal.catalog_admin_action_category(p_action TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
    SELECT CASE p_action
        WHEN 'GAME_CREATED' THEN 'CADASTRO'
        WHEN 'EXPANSION_CREATED' THEN 'CADASTRO'
        WHEN 'CARD_SET_CREATED' THEN 'CADASTRO'
        WHEN 'CARD_CREATED' THEN 'CADASTRO'
        WHEN 'RARITY_CREATED' THEN 'CADASTRO'
        WHEN 'RARITY_EXTERNAL_MAPPING_CREATED' THEN 'CADASTRO'
        WHEN 'GAME_UPDATED' THEN 'ALTERACAO'
        WHEN 'EXPANSION_UPDATED' THEN 'ALTERACAO'
        WHEN 'CARD_SET_UPDATED' THEN 'ALTERACAO'
        WHEN 'CARD_UPDATED' THEN 'ALTERACAO'
        WHEN 'RARITY_UPDATED' THEN 'ALTERACAO'
        WHEN 'RARITY_EXTERNAL_MAPPING_UPDATED' THEN 'ALTERACAO'
        WHEN 'GAME_DELETED' THEN 'EXCLUSAO'
        WHEN 'EXPANSION_DELETED' THEN 'EXCLUSAO'
        WHEN 'CARD_SET_DELETED' THEN 'EXCLUSAO'
        ELSE 'OUTRAS'
    END;
$$;

REVOKE ALL ON FUNCTION internal.catalog_admin_action_category(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION internal.catalog_admin_action_category(TEXT) FROM anon;
REVOKE ALL ON FUNCTION internal.catalog_admin_action_category(TEXT) FROM authenticated;

-- ================================================================
-- Resultado esperado: "Success. No rows returned".
--
-- Como validar:
-- SELECT internal.catalog_admin_action_category('GAME_CREATED'),
--        internal.catalog_admin_action_category('CARD_UPDATED'),
--        internal.catalog_admin_action_category('CARD_SET_DELETED'),
--        internal.catalog_admin_action_category('CARD_DEACTIVATED');
-- ================================================================
--
-- CONFIRMADO EXECUTADO (2026-08-09): validado por Fabrício.
-- ================================================================
