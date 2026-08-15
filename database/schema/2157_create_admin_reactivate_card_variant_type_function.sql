/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2157 - Create admin_reactivate_card_variant_type() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_reactivate_card_variant_type(), espelho exato de
admin_deactivate_card_variant_type() (Query 2156) — restaura
is_active = true. Como card_variant/card_variant_type_external_
mapping nunca são tocados pela inativação, nenhuma ação de
"recriar" é necessária — o tipo volta a ficar disponível para
seleção em novos cadastros/mappings assim que is_active = true.

Regras de Negócio:
- Mesmo raciocínio de admin_deactivate_card_variant_type(): UPDATE
  direto em public.card_variant_type.
- Erro claro se o tipo já estiver ativo
  (ADMIN_REACTIVATE_CARD_VARIANT_TYPE_ALREADY_ACTIVE) — simetria com
  ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_ALREADY_INACTIVE.
- Grava catalog_admin_action_log (CARD_VARIANT_TYPE_REACTIVATED) —
  ação habilitada pela Query 2153.

Pré-requisitos:
- Query 2152 - Add is_active to Card Variant Type.
- Query 2153 - Widen Catalog Admin Action Log for Card Variant Type.
- Query 2156 - Create admin_deactivate_card_variant_type() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_reactivate_card_variant_type(p_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_VARIANT_TYPE_FORBIDDEN: apenas administradores podem reativar um Card Variant Type.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_VARIANT_TYPE_MISSING_ID: p_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_variant_type WHERE id = p_id) THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_VARIANT_TYPE_NOT_FOUND: nenhum Card Variant Type encontrado para o id informado (%).', p_id;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant_type WHERE id = p_id AND is_active = true) THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_VARIANT_TYPE_ALREADY_ACTIVE: este Card Variant Type já está ativo.';
    END IF;

    UPDATE public.card_variant_type
        SET is_active = true
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_VARIANT_TYPE_NOT_FOUND: nenhum Card Variant Type encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'CARD_VARIANT_TYPE_REACTIVATED', 'CARD_VARIANT_TYPE', p_id, jsonb_build_object());

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reactivate_card_variant_type(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_reactivate_card_variant_type(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_reactivate_card_variant_type(UUID) FROM anon;

-- ================================================================
-- Confirmado executado e validado (2026-08-15): dentro de
-- BEGIN...ROLLBACK, restaura is_active = true de COSMOS_HOLO após a
-- inativação de teste, com a contagem de card_variant referenciando-o
-- inalterada (7/7) — nada precisou ser "recriado", confirmando que a
-- desativação nunca cascateia. Segunda chamada sobre um tipo já ativo
-- corretamente recusada (ADMIN_REACTIVATE_CARD_VARIANT_TYPE_ALREADY_
-- ACTIVE, testado no dry-run). has_function_privilege confirma
-- authenticated=true, anon=false.
-- ================================================================
