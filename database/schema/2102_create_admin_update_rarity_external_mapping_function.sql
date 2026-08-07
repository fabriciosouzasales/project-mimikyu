/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2102 - Create admin_update_rarity_external_mapping() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_update_rarity_external_mapping(), corrige o vínculo de
um mapeamento existente para outra Raridade (ex. um mapeamento
apontado para a Raridade errada). game_id/asset_source_id/
external_value permanecem imutáveis — apenas rarity_id é
editável; corrigir o valor bruto em si equivaleria a criar um
mapeamento novo, não a corrigir este.

Regras de Negócio:
- A nova rarity_id deve pertencer ao mesmo game_id do mapeamento
  original (mesma checagem de admin_create_rarity_external_mapping(),
  Query 2101).
- Grava catalog_admin_action_log
  (RARITY_EXTERNAL_MAPPING_UPDATED) — ação habilitada pela Query
  2098.

Pré-requisitos:
- Query 2096 - Create rarity_external_mapping Table.
- Query 2098 - Add Rarity Actions to Catalog Admin Action Log.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_update_rarity_external_mapping(
    p_id UUID,
    p_rarity_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_game_id UUID;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_EXTERNAL_MAPPING_FORBIDDEN: apenas administradores podem atualizar um mapeamento de raridade.';
    END IF;

    IF p_id IS NULL OR p_rarity_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_EXTERNAL_MAPPING_MISSING_IDS: p_id e p_rarity_id são obrigatórios.';
    END IF;

    SELECT game_id INTO v_game_id
        FROM public.rarity_external_mapping
        WHERE id = p_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_EXTERNAL_MAPPING_NOT_FOUND: nenhum mapeamento encontrado para o id informado (%).', p_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.rarity WHERE id = p_rarity_id AND game_id = v_game_id) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_EXTERNAL_MAPPING_RARITY_MISMATCH: a Raridade informada não existe ou não pertence ao Game deste mapeamento.';
    END IF;

    UPDATE public.rarity_external_mapping
        SET rarity_id = p_rarity_id
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_EXTERNAL_MAPPING_NOT_FOUND: nenhum mapeamento encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'RARITY_EXTERNAL_MAPPING_UPDATED', 'RARITY_EXTERNAL_MAPPING', p_id,
            jsonb_build_object('rarity_id', p_rarity_id)
        );

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_rarity_external_mapping(UUID, UUID) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-07): definição em produção lida
-- via pg_get_functiondef() e conferida idêntica a este arquivo.
-- ================================================================
