/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2034 - Create admin_update_expansion() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria admin_update_expansion(), função pública SECURITY DEFINER —
única via de atualização de Expansion (ADR-023).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- game_id e code são imutáveis por construção: a assinatura desta
  função não aceita nenhum dos dois — mudar o Game de uma
  Expansion ou seu código muda a identidade do registro, mesmo
  princípio já aplicado a card_set_id/collector_number em Card
  (ADR-023) e a code em Game (Query 2032).
- release_order é editável, mas continua único dentro do mesmo
  Game (uq_expansion_game_release_order) — duplicidade verificada
  explicitamente antes do UPDATE, excluindo a própria linha.
- GET DIAGNOSTICS ... ROW_COUNT confirma que exatamente uma linha
  foi alterada.
- Toda atualização bem-sucedida grava uma linha em
  catalog_admin_action_log (EXPANSION_UPDATED).

Pré-requisitos:
- Query 110 - Create Expansion Table.
- Query 1060 - Create is_admin() Function.
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_update_expansion(
    p_id UUID,
    p_name TEXT,
    p_release_order INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT;
    v_game_id UUID;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_EXPANSION_FORBIDDEN: apenas administradores podem atualizar uma Expansão.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_EXPANSION_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT game_id INTO v_game_id FROM public.expansion WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_EXPANSION_NOT_FOUND: nenhuma Expansão encontrada para o id informado (%).', p_id;
    END IF;

    v_name := btrim(coalesce(p_name, ''));

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_EXPANSION_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_release_order IS NULL OR p_release_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_EXPANSION_INVALID_RELEASE_ORDER: a ordem de lançamento deve ser um número positivo.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.expansion
        WHERE game_id = v_game_id AND release_order = p_release_order AND id <> p_id
    ) THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_EXPANSION_DUPLICATE_RELEASE_ORDER: já existe outra Expansão com a ordem de lançamento % para este Jogo.', p_release_order;
    END IF;

    UPDATE public.expansion
        SET name = v_name,
            release_order = p_release_order
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_EXPANSION_NOT_FOUND: nenhuma Expansão encontrada para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'EXPANSION_UPDATED', 'EXPANSION', p_id, jsonb_build_object('name', v_name, 'release_order', p_release_order));

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_expansion(UUID, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_expansion(UUID, TEXT, INTEGER) TO authenticated;
