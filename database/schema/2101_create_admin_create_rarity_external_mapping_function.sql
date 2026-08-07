/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2101 - Create admin_create_rarity_external_mapping() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_create_rarity_external_mapping(), vincula um valor
bruto de raridade de uma Fonte externa a uma Raridade canônica já
existente ("Raridade existente", tela /catalogo/raridades →
"Resolver raridade"). Chamada diretamente pela UI e internamente
por admin_create_rarity_with_external_mapping() (Query 2103).

Regras de Negócio:
- rarity_id deve pertencer ao mesmo game_id informado
  (ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_RARITY_MISMATCH) — nunca
  aceita silenciosamente um cruzamento entre Games.
- external_value normalizado via normalize_external_catalog_value()
  (Query 2095) antes de checar duplicidade — dois valores brutos
  que só diferem em acento/caixa/espaço são o mesmo mapeamento aos
  olhos desta função (uq_rarity_external_mapping, Query 2096).
- Grava catalog_admin_action_log
  (RARITY_EXTERNAL_MAPPING_CREATED) — ação habilitada pela Query
  2098.

Pré-requisitos:
- Query 2095 - Create normalize_external_catalog_value() Function.
- Query 2096 - Create rarity_external_mapping Table.
- Query 2098 - Add Rarity Actions to Catalog Admin Action Log.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_rarity_external_mapping(
    p_game_id UUID,
    p_asset_source_id UUID,
    p_rarity_id UUID,
    p_external_value TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_external_value TEXT;
    v_normalized_value TEXT;
    v_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_FORBIDDEN: apenas administradores podem cadastrar um mapeamento de raridade.';
    END IF;

    IF p_game_id IS NULL OR p_asset_source_id IS NULL OR p_rarity_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_MISSING_IDS: p_game_id, p_asset_source_id e p_rarity_id são obrigatórios.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.game WHERE id = p_game_id) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_GAME_NOT_FOUND: nenhum Game encontrado para o id informado (%).', p_game_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.asset_source WHERE id = p_asset_source_id) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_SOURCE_NOT_FOUND: nenhuma Fonte encontrada para o id informado (%).', p_asset_source_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.rarity WHERE id = p_rarity_id AND game_id = p_game_id) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_RARITY_MISMATCH: a Raridade informada não existe ou não pertence ao Game informado.';
    END IF;

    v_external_value := btrim(coalesce(p_external_value, ''));

    IF v_external_value = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_INVALID_VALUE: o valor bruto não pode ser vazio.';
    END IF;

    v_normalized_value := public.normalize_external_catalog_value(v_external_value);

    IF EXISTS (
        SELECT 1 FROM public.rarity_external_mapping
        WHERE game_id = p_game_id
          AND asset_source_id = p_asset_source_id
          AND normalized_external_value = v_normalized_value
    ) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_EXTERNAL_MAPPING_DUPLICATE: já existe um mapeamento para o valor % nesta Fonte e Game.', v_external_value;
    END IF;

    INSERT INTO public.rarity_external_mapping (game_id, asset_source_id, external_value, normalized_external_value, rarity_id)
        VALUES (p_game_id, p_asset_source_id, v_external_value, v_normalized_value, p_rarity_id)
        RETURNING id INTO v_id;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'RARITY_EXTERNAL_MAPPING_CREATED', 'RARITY_EXTERNAL_MAPPING', v_id,
            jsonb_build_object(
                'game_id', p_game_id, 'asset_source_id', p_asset_source_id,
                'rarity_id', p_rarity_id, 'external_value', v_external_value,
                'normalized_external_value', v_normalized_value
            )
        );

    RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_rarity_external_mapping(UUID, UUID, UUID, TEXT) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-07): definição em produção lida
-- via pg_get_functiondef() e conferida idêntica a este arquivo.
-- ================================================================
