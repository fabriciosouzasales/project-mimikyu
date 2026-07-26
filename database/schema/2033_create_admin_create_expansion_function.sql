/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2033 - Create admin_create_expansion() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria admin_create_expansion(), função pública SECURITY DEFINER —
única via de cadastro de Expansion (ADR-023). Mesmo padrão de
admin_create_game() (Query 2031): sem camada interna própria, o
INSERT acontece diretamente aqui.

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- game_id deve corresponder a um Game existente — checado
  explicitamente antes do INSERT, com mensagem clara (antecipa o
  erro bruto de fk_expansion_game).
- code é normalizado para maiúsculas e sem espaços nas pontas
  antes de validar formato (^[A-Z][A-Z0-9_]*$) e duplicidade
  dentro do mesmo Game (uq_expansion_game_code é por game_id+code,
  não global — duas Expansions de Games diferentes podem
  compartilhar o mesmo code).
- release_order deve ser positivo e único dentro do mesmo Game
  (uq_expansion_game_release_order) — duplicidade verificada
  explicitamente antes do INSERT.
- Toda criação bem-sucedida grava uma linha em
  catalog_admin_action_log (EXPANSION_CREATED) — ação já prevista
  no CHECK original da tabela (Query 2010), nenhuma alteração de
  schema necessária.

Pré-requisitos:
- Query 110 - Create Expansion Table.
- Query 1060 - Create is_admin() Function.
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_expansion(
    p_game_id UUID,
    p_code TEXT,
    p_name TEXT,
    p_release_order INTEGER
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_code TEXT;
    v_name TEXT;
    v_id UUID;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_FORBIDDEN: apenas administradores podem cadastrar uma Expansão.';
    END IF;

    IF p_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_MISSING_GAME: p_game_id é obrigatório.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.game WHERE id = p_game_id) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_GAME_NOT_FOUND: nenhum Jogo encontrado para o id informado (%).', p_game_id;
    END IF;

    v_code := upper(btrim(coalesce(p_code, '')));
    v_name := btrim(coalesce(p_name, ''));

    IF v_code = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_INVALID_CODE: o código não pode ser vazio.';
    END IF;

    IF v_code !~ '^[A-Z][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_INVALID_CODE: o código deve começar com uma letra e conter apenas letras maiúsculas, números e "_".';
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF p_release_order IS NULL OR p_release_order <= 0 THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_INVALID_RELEASE_ORDER: a ordem de lançamento deve ser um número positivo.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.expansion WHERE game_id = p_game_id AND code = v_code) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_DUPLICATE_CODE: já existe uma Expansão com o código % para este Jogo.', v_code;
    END IF;

    IF EXISTS (SELECT 1 FROM public.expansion WHERE game_id = p_game_id AND release_order = p_release_order) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_EXPANSION_DUPLICATE_RELEASE_ORDER: já existe uma Expansão com a ordem de lançamento % para este Jogo.', p_release_order;
    END IF;

    INSERT INTO public.expansion (game_id, code, name, release_order)
        VALUES (p_game_id, v_code, v_name, p_release_order)
        RETURNING id INTO v_id;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'EXPANSION_CREATED', 'EXPANSION', v_id,
            jsonb_build_object('game_id', p_game_id, 'code', v_code, 'name', v_name, 'release_order', p_release_order)
        );

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_expansion(UUID, TEXT, TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_expansion(UUID, TEXT, TEXT, INTEGER) TO authenticated;
