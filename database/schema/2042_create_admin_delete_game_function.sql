/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2042 - Create admin_delete_game() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria admin_delete_game(), função pública SECURITY DEFINER — via de
exclusão real (não desativação) de Game. Ver ADR-023, emenda
2026-07-26 ("Game: exclusão real via UI").

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- code/name são capturados por SELECT antes do DELETE — depois de
  excluído, não há mais como consultar esses dados para a
  auditoria.
- A FK fk_expansion_game (ON DELETE RESTRICT, Query 110) impede a
  exclusão de um Game com Expansions associadas; esta função
  antecipa esse erro bruto (foreign_key_violation) com uma
  mensagem administrativa clara, mesmo padrão de "antecipar o
  erro" já usado em admin_set_card_set_logo()/admin_create_game().
- GET DIAGNOSTICS ... ROW_COUNT confirma o efeito real do DELETE.
- Toda exclusão bem-sucedida grava uma linha em
  catalog_admin_action_log (GAME_DELETED) com code/name em
  metadata.
- Exclusão definitiva — sem "lixeira", sem forma de desfazer pela
  UI.

Pré-requisitos:
- Query 100 - Create Game Table.
- Query 110 - Create Expansion Table (fk_expansion_game).
- Query 1060 - Create is_admin() Function.
- Query 2041 - Add GAME_DELETED to Catalog Admin Action Log.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_delete_game(
    p_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_code TEXT;
    v_name TEXT;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_DELETE_GAME_FORBIDDEN: apenas administradores podem excluir um Jogo.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_DELETE_GAME_MISSING_ID: p_id é obrigatório.';
    END IF;

    SELECT code, name INTO v_code, v_name FROM public.game WHERE id = p_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_DELETE_GAME_NOT_FOUND: nenhum Jogo encontrado para o id informado (%).', p_id;
    END IF;

    BEGIN
        DELETE FROM public.game WHERE id = p_id;
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'ADMIN_DELETE_GAME_HAS_DEPENDENTS: não é possível excluir o Jogo % (%) porque já existem Expansões cadastradas para ele.', v_name, v_code;
    END;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_DELETE_GAME_NOT_FOUND: nenhum Jogo encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'GAME_DELETED', 'GAME', p_id, jsonb_build_object('code', v_code, 'name', v_name));

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_game(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_game(UUID) TO authenticated;
