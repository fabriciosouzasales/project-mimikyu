/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2117 - Create admin_reactivate_card() Function
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria admin_reactivate_card(), espelho exato de
admin_deactivate_card() (Query 2116) — restaura is_active = true.
Como card_variant/card_asset/card_external_reference nunca foram
tocados pela desativação, a Card volta a aparecer nas consultas
operacionais automaticamente (is_active = true por padrão) sem
nenhuma ação adicional — não há nada para "recriar" (ADR-023).

Regras de Negócio:
- Mesmo raciocínio de admin_deactivate_card(): UPDATE direto,
  sem internal.write_card() (is_active fora daquela camada).
- Erro claro se a Card já estiver ativa
  (ADMIN_REACTIVATE_CARD_ALREADY_ACTIVE) — simetria com
  ADMIN_DEACTIVATE_CARD_ALREADY_INACTIVE.
- Grava catalog_admin_action_log (CARD_REACTIVATED) — ação já
  prevista no CHECK original da Query 2010.
- REVOKE ALL de PUBLIC/anon explícito desde a criação.

Pré-requisitos:
- Query 2020 - Add is_active to Card.
- Query 2116 - Create admin_deactivate_card() Function.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_reactivate_card(p_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_FORBIDDEN: apenas administradores podem reativar uma Card.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_MISSING_ID: p_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card WHERE id = p_id) THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_id;
    END IF;

    IF EXISTS (SELECT 1 FROM public.card WHERE id = p_id AND is_active = true) THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_ALREADY_ACTIVE: esta Card já está ativa.';
    END IF;

    UPDATE public.card
        SET is_active = true
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_REACTIVATE_CARD_NOT_FOUND: nenhuma Card encontrada para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'CARD_REACTIVATED', 'CARD', p_id, jsonb_build_object());

    RETURN p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reactivate_card(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_reactivate_card(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_reactivate_card(UUID) FROM anon;

-- ================================================================
-- Confirmado executado (2026-08-07): has_function_privilege()
-- confirmado authenticated=true, anon=false, correto desde a
-- primeira execução. Validação funcional completa fica para a
-- Query 2817, ao final do subciclo.
-- ================================================================
