/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2031 - Create admin_create_game() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria admin_create_game(), função pública SECURITY DEFINER — única
via de cadastro de Game (ADR-023). Sem camada interna própria: ao
contrário de Card, Game não converge três canais de entrada nem
tem campos protegidos contra atualização, então o INSERT acontece
diretamente aqui, mesmo padrão já usado em
admin_set_card_set_logo() (ADR-022).

Regras de Negócio:
- Só um administrador pode chamar esta função (is_admin()).
- code é normalizado para maiúsculas e sem espaços nas pontas
  antes de qualquer validação — mais tolerante que exigir que o
  chamador já envie o formato exato.
- Duplicidade de code verificada explicitamente antes do INSERT,
  com mensagem clara — antecipa o erro bruto de
  uq_game_code (mesmo espírito de admin_set_card_set_logo()).
- Formato de code e nome não vazio também verificados
  explicitamente antes do INSERT, pela mesma razão.
- Toda criação bem-sucedida grava uma linha em
  catalog_admin_action_log (GAME_CREATED).

Pré-requisitos:
- Query 100 - Create Game Table.
- Query 1060 - Create is_admin() Function.
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_create_game(
    p_code TEXT,
    p_name TEXT
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
        RAISE EXCEPTION 'ADMIN_CREATE_GAME_FORBIDDEN: apenas administradores podem cadastrar um Jogo.';
    END IF;

    v_code := upper(btrim(coalesce(p_code, '')));
    v_name := btrim(coalesce(p_name, ''));

    IF v_code = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_GAME_INVALID_CODE: o código não pode ser vazio.';
    END IF;

    IF v_code !~ '^[A-Z][A-Z0-9_]*$' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_GAME_INVALID_CODE: o código deve começar com uma letra e conter apenas letras maiúsculas, números e "_".';
    END IF;

    IF v_name = '' THEN
        RAISE EXCEPTION 'ADMIN_CREATE_GAME_INVALID_NAME: o nome não pode ser vazio.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.game WHERE code = v_code) THEN
        RAISE EXCEPTION 'ADMIN_CREATE_GAME_DUPLICATE_CODE: já existe um Jogo com o código %.', v_code;
    END IF;

    INSERT INTO public.game (code, name)
        VALUES (v_code, v_name)
        RETURNING id INTO v_id;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (auth.uid(), 'GAME_CREATED', 'GAME', v_id, jsonb_build_object('code', v_code, 'name', v_name));

    RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_game(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_game(TEXT, TEXT) TO authenticated;
