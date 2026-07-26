/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2032 - Create admin_update_game() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria admin_update_game(), função pública SECURITY DEFINER — única
via de atualização de Game (ADR-023).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- code é imutável por construção: a assinatura desta função nem
  aceita esse parâmetro — não há campo a proteger em tempo de
  execução, diferente de internal.write_card() (Query 2030), que
  precisa de uma checagem explícita porque seu parâmetro
  p_card_set_id existe na assinatura por causa do modo CREATE
  compartilhado.
- GET DIAGNOSTICS ... ROW_COUNT confirma que exatamente uma linha
  foi alterada — nunca assume sucesso apenas porque a chamada não
  retornou erro (mesmo padrão de admin_set_card_set_logo()).
- Toda atualização bem-sucedida grava uma linha em
  catalog_admin_action_log (GAME_UPDATED).

Pré-requisitos:
- Query 100 - Create Game Table.
- Query 1060 - Create is_admin() Function.
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_update_game(
    p_id UUID,
    p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_name TEXT;
    v_rows_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_GAME_FORBIDDEN: apenas administradores podem atualizar um Jogo.';
    END IF;

    IF p_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_GAME_MISSING_ID: p_id é obrigatório.';
    END IF;

    v_name := btrim(coalesce(p_name, ''));

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_GAME_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    UPDATE public.game
        SET name = v_name
        WHERE id = p_id;

    GET DIAGNOSTICS v_rows_affected = ROW_COUNT;

    IF v_rows_affected <> 1 THEN
        RAISE EXCEPTION 'ADMIN_UPDATE_GAME_NOT_FOUND: nenhum Jogo encontrado para o id informado (%).', p_id;
    END IF;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'GAME_UPDATED', 'GAME', p_id, jsonb_build_object('name', v_name));

    RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_game(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_game(UUID, TEXT) TO authenticated;
