/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2156 - Create admin_deactivate_card_variant_type() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Cria admin_deactivate_card_variant_type(), inativação administrativa
de Card Variant Type — is_active = false. Diferente de
admin_deactivate_card() (Query 2116, soft delete real e irrestrito
que também governa visibilidade em consultas operacionais), aqui
is_active só controla DISPONIBILIDADE PARA NOVOS cadastros/mappings
(ver Query 2152) — nenhuma linha de card_variant ou
card_variant_type_external_mapping que já referencia este tipo é
tocada, afetada ou deixa de ser válida.

Regras de Negócio:
- UPDATE direto em public.card_variant_type — não há camada
  internal.write_*() para esta entidade (mesmo raciocínio de
  admin_deactivate_card(): operação de um único campo).
- Erro claro se o tipo já estiver inativo
  (ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_ALREADY_INACTIVE) — evita um
  UPDATE sem efeito e uma linha de auditoria sem sentido.
- GET DIAGNOSTICS ... ROW_COUNT confirma o efeito real do UPDATE.
- Grava catalog_admin_action_log (CARD_VARIANT_TYPE_DEACTIVATED) —
  ação habilitada pela Query 2153.
- Sem exclusão física nesta versão (decisão explícita de Fabrício:
  card_variant_type é taxonomia canônica, preserva histórico) —
  esta função é o único mecanismo de remoção "suave" previsto na V1.

Pré-requisitos:
- Query 2152 - Add is_active to Card Variant Type.
- Query 2153 - Widen Catalog Admin Action Log for Card Variant Type.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_deactivate_card_variant_type(p_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_FORBIDDEN: apenas administradores podem inativar um Card Variant Type.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_MISSING_ID: p_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_variant_type WHERE id = p_id) THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_NOT_FOUND: nenhum Card Variant Type encontrado para o id informado (%).', p_id;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant_type WHERE id = p_id AND is_active = false) THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_ALREADY_INACTIVE: este Card Variant Type já está inativo.';
    END IF;

    UPDATE public.card_variant_type
        SET is_active = false
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_NOT_FOUND: nenhum Card Variant Type encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'CARD_VARIANT_TYPE_DEACTIVATED', 'CARD_VARIANT_TYPE', p_id, jsonb_build_object());

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_deactivate_card_variant_type(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_deactivate_card_variant_type(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_deactivate_card_variant_type(UUID) FROM anon;

-- ================================================================
-- Confirmado executado e validado (2026-08-15): dentro de
-- BEGIN...ROLLBACK, aplicado sobre COSMOS_HOLO real (7 card_variant +
-- 1 card_variant_type_external_mapping referenciando-o em produção) —
-- contagens de ambas as tabelas idênticas antes/depois da inativação
-- (7/7, 1/1), confirmando que nenhuma referência existente é tocada.
-- Segunda chamada sobre o mesmo id corretamente recusada
-- (ADMIN_DEACTIVATE_CARD_VARIANT_TYPE_ALREADY_INACTIVE). has_function_
-- privilege confirma authenticated=true, anon=false.
-- ================================================================
