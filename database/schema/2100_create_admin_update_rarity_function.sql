/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2100 - Create admin_update_rarity() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_update_rarity(), edição administrativa de Raridade
canônica via UI (/catalogo/raridades, Dialog de edição). `game_id`/
`code` continuam imutáveis por construção — a função nem aceita
esses parâmetros, mesmo princípio já aplicado a outras entidades
estruturais do catálogo.

Regras de Negócio:
- name/symbol_code/display_order são os únicos campos editáveis.
- Mesma validação de formato de symbol_code de
  admin_create_rarity() (Query 2099).
- Grava catalog_admin_action_log (RARITY_UPDATED) — ação
  habilitada pela Query 2098.

Pré-requisitos:
- Query 130 - Create Rarity Table.
- Query 2098 - Add Rarity Actions to Catalog Admin Action Log.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_update_rarity(
    p_id UUID,
    p_name TEXT,
    p_symbol_code TEXT,
    p_display_order INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT;
    v_symbol_code TEXT;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_FORBIDDEN: apenas administradores podem atualizar uma Raridade.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_MISSING_ID: p_id é obrigatório.';
    END IF;

    v_name := btrim(coalesce(p_name, ''));
    v_symbol_code := upper(btrim(coalesce(p_symbol_code, '')));

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF v_symbol_code = '' OR v_symbol_code !~ '^[A-Z0-9][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_INVALID_SYMBOL_CODE: o código de símbolo deve começar com letra ou número e conter apenas letras maiúsculas, números e sublinhado.';
    END IF;

    IF p_display_order IS NULL OR p_display_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_INVALID_DISPLAY_ORDER: a ordem de exibição deve ser um número positivo.';
    END IF;

    UPDATE public.rarity
        SET name = v_name,
            symbol_code = v_symbol_code,
            display_order = p_display_order
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_RARITY_NOT_FOUND: nenhuma Raridade encontrada para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'RARITY_UPDATED', 'RARITY', p_id,
            jsonb_build_object('name', v_name, 'symbol_code', v_symbol_code, 'display_order', p_display_order)
        );

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_rarity(UUID, TEXT, TEXT, INTEGER) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-07): definição em produção lida
-- via pg_get_functiondef() e conferida idêntica a este arquivo.
-- ================================================================
