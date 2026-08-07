/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2103 - Create admin_create_rarity_with_external_mapping() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_create_rarity_with_external_mapping(), cadastro atômico
de uma Raridade canônica nova já vinculada a um valor externo —
fluxo "Nova raridade" da tela /catalogo/raridades ("Resolver
raridade"), usado quando o valor pendente não corresponde a
nenhuma Raridade já cadastrada (ex. RARE_HOLO/"Rara Holo",
RARE_HOLO_V/"Rara Holo V"). Wrapper fino sobre
admin_create_rarity() (Query 2099) + admin_create_rarity_external_
mapping() (Query 2101) — nenhuma lógica própria de negócio, só
orquestra as duas chamadas na mesma transação (falha em qualquer
uma reverte as duas, por estarem na mesma função `plpgsql`).

Regras de Negócio:
- is_admin() checado aqui também, apesar de ambas as funções
  chamadas já checarem — mesmo padrão defensivo (falha cedo, sem
  depender de comportamento transitivo).
- Retorna as duas chaves geradas (rarity_id, mapping_id) — a UI
  precisa da primeira para navegação/destaque, não usa a segunda
  hoje, mas expor as duas evita uma chamada extra futura.

Pré-requisitos:
- Query 2099 - Create admin_create_rarity() Function.
- Query 2101 - Create admin_create_rarity_external_mapping() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_rarity_with_external_mapping(
    p_game_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_symbol_code TEXT,
    p_display_order INTEGER,
    p_asset_source_id UUID,
    p_external_value TEXT
)
RETURNS TABLE(rarity_id UUID, mapping_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rarity_id UUID;
    v_mapping_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_RARITY_WITH_EXTERNAL_MAPPING_FORBIDDEN: apenas administradores podem cadastrar uma Raridade com mapeamento.';
    END IF;

    v_rarity_id := public.admin_create_rarity(p_game_id, p_code, p_name, p_symbol_code, p_display_order);

    v_mapping_id := public.admin_create_rarity_external_mapping(p_game_id, p_asset_source_id, v_rarity_id, p_external_value);

    RETURN QUERY SELECT v_rarity_id, v_mapping_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_rarity_with_external_mapping(UUID, TEXT, TEXT, TEXT, INTEGER, UUID, TEXT) TO authenticated;

-- ================================================================
-- Confirmado executado e validado funcionalmente (2026-08-07):
-- definição em produção lida via pg_get_functiondef() e conferida
-- idêntica a este arquivo. Usada para cadastrar RARE_HOLO,
-- RARE_HOLO_V, RARE_SECRET e RARE_HOLO_VMAX via UI, com rollback
-- corretamente demonstrado por erros de validação em tentativas
-- anteriores (ex. código duplicado).
-- ================================================================
