/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1020 - Create handle_new_user function and trigger
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria a function handle_new_user() e o trigger em auth.users que a
dispara a cada novo cadastro, populando public.user_profile a
partir de raw_user_meta_data (username/display_name enviados pelo
formulário via options.data do supabase.auth.signUp()).

Regras de Negócio:
- raw_user_meta_data é tratado como dado não confiável: username e
  display_name são normalizados (trim/lower) e revalidados aqui,
  mesmo que o frontend já tenha validado antes.
- Qualquer falha (username ausente/inválido/reservado,
  display_name ausente) cancela a transação inteira do INSERT em
  auth.users — nunca existe usuário sem perfil, a partir de agora.
- SECURITY DEFINER + search_path vazio + referências qualificadas:
  a function roda com privilégio elevado para gravar em
  user_profile e ler reserved_username, então precisa das mesmas
  proteções contra sequestro de search_path já aplicadas em
  username_available() (Query 1030).
- REVOKE EXECUTE FROM PUBLIC: só o próprio trigger a invoca; não é
  chamável diretamente pela API.
================================================================
*/

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_username TEXT;
    v_display_name TEXT;
BEGIN
    v_username := lower(trim(NEW.raw_user_meta_data->>'username'));
    v_display_name := trim(NEW.raw_user_meta_data->>'display_name');

    IF v_username IS NULL OR v_username = '' THEN
        RAISE EXCEPTION 'username é obrigatório.';
    END IF;

    IF v_username !~ '^[a-z0-9_]{3,20}$' THEN
        RAISE EXCEPTION 'username inválido: use 3 a 20 caracteres, apenas letras minúsculas, números e underscore.';
    END IF;

    IF EXISTS (SELECT 1 FROM public.reserved_username WHERE username = v_username) THEN
        RAISE EXCEPTION 'username indisponível.';
    END IF;

    IF v_display_name IS NULL OR v_display_name = '' THEN
        RAISE EXCEPTION 'nome de exibição é obrigatório.';
    END IF;

    INSERT INTO public.user_profile (id, username, display_name)
    VALUES (NEW.id, v_username, v_display_name);

    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();
