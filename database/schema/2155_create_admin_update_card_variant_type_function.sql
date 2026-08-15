/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2155 - Create admin_update_card_variant_type() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_update_card_variant_type(), edição administrativa de
Card Variant Type canônico. game_id/code permanecem imutáveis por
construção — a função nem aceita esses parâmetros, mesmo princípio
já aplicado a Raridade (Query 2100) e às demais entidades
estruturais do catálogo.

Regras de Negócio:
- name/description/display_order são os únicos campos editáveis.
- display_order deve permanecer único por Game
  (uq_card_variant_type_game_display_order, Query 150) — checagem
  explícita excluindo a própria linha (id <> p_id), mesmo cuidado
  de admin_create_card_variant_type() (Query 2154).
- description normalizado: string vazia vira NULL, mesma regra da
  Query 2154.
- is_active nunca é tocado por esta função — pertence exclusivamente
  a admin_deactivate_card_variant_type()/admin_reactivate_card_
  variant_type() (Queries 2156/2157), mesmo princípio já usado para
  Card (Query 2114/2116: "is_active fora do escopo da função de
  update").
- Grava catalog_admin_action_log (CARD_VARIANT_TYPE_UPDATED) — ação
  habilitada pela Query 2153.

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 2153 - Widen Catalog Admin Action Log for Card Variant Type.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_update_card_variant_type(
    p_id UUID,
    p_name TEXT,
    p_description TEXT,
    p_display_order INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT;
    v_description TEXT;
    v_game_id UUID;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_VARIANT_TYPE_FORBIDDEN: apenas administradores podem atualizar um Card Variant Type.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_VARIANT_TYPE_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT game_id INTO v_game_id
        FROM public.card_variant_type
        WHERE id = p_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_VARIANT_TYPE_NOT_FOUND: nenhum Card Variant Type encontrado para o id informado (%).', p_id;
    END IF;

    v_name := btrim(coalesce(p_name, ''));
    v_description := btrim(coalesce(p_description, ''));

    IF v_description = '' THEN
        v_description := NULL;
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_VARIANT_TYPE_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_display_order IS NULL OR p_display_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_VARIANT_TYPE_INVALID_DISPLAY_ORDER: a ordem de exibição deve ser um número positivo.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card_variant_type
        WHERE game_id = v_game_id AND display_order = p_display_order AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_VARIANT_TYPE_DUPLICATE_DISPLAY_ORDER: já existe outro Card Variant Type com a ordem % para este Game.', p_display_order;
    END IF;

    UPDATE public.card_variant_type
        SET name = v_name,
            description = v_description,
            display_order = p_display_order
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_CARD_VARIANT_TYPE_NOT_FOUND: nenhum Card Variant Type encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_VARIANT_TYPE_UPDATED', 'CARD_VARIANT_TYPE', p_id,
            jsonb_build_object('name', v_name, 'description', v_description, 'display_order', p_display_order)
        );

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_card_variant_type(UUID, TEXT, TEXT, INTEGER) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_update_card_variant_type(UUID, TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_card_variant_type(UUID, TEXT, TEXT, INTEGER) FROM anon;

-- ================================================================
-- Confirmado executado e validado (2026-08-15): dentro de
-- BEGIN...ROLLBACK, criou-se um tipo de teste e chamou-se esta função
-- para editar name/description/display_order — code e game_id
-- confirmados idênticos antes/depois (a função nem aceita esses
-- parâmetros, garantia estrutural, não só de dado). has_function_
-- privilege confirma authenticated=true, anon=false; search_path=""
-- endurecido.
-- ================================================================
