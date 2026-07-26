/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1030 - Create username_available function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-25

Descrição...:
Cria a function username_available(text), chamável por anon e
authenticated, para checagem de disponibilidade de username
durante o cadastro (formulário roda sem sessão).

Regras de Negócio:
- Antecipação de UX, sujeita a condição de corrida: dois
  cadastros simultâneos podem passar por aqui para o mesmo
  username, mas só um consegue de fato se cadastrar — a
  autoridade final é o UNIQUE de user_profile, verificado no
  INSERT real (Query 1020).
- Normaliza (trim + lower) o argumento antes de checar, igual ao
  que handle_new_user() faz.
- Retorno estritamente BOOLEAN — nunca diferencia "reservado" de
  "já em uso", para não vazar esse detalhe a quem está checando.
- SECURITY DEFINER + search_path vazio + referências qualificadas:
  única forma de ler user_profile/reserved_username sem exigir
  política de SELECT ampla para anon.
================================================================
*/

CREATE OR REPLACE FUNCTION public.username_available(p_username TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_username TEXT;
BEGIN
    v_username := lower(trim(p_username));

    IF v_username !~ '^[a-z0-9_]{3,20}$' THEN
        RETURN FALSE;
    END IF;

    IF EXISTS (SELECT 1 FROM public.reserved_username WHERE username = v_username) THEN
        RETURN FALSE;
    END IF;

    IF EXISTS (SELECT 1 FROM public.user_profile WHERE username = v_username) THEN
        RETURN FALSE;
    END IF;

    RETURN TRUE;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.username_available(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.username_available(TEXT) TO anon, authenticated;
