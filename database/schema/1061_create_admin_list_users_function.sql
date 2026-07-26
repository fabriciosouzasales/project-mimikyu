/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1061 - Create admin_list_users() Function
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Function SECURITY DEFINER que lista usuários para fins
administrativos: única via de leitura de e-mail (auth.users)
para esse propósito — o frontend nunca consulta auth.users
diretamente. Paginada desde a origem (limit/offset com teto
máximo), mesmo sem busca/filtros nesta fase (ver ADR-021).

Regras de Negócio:
- Verifica is_admin() internamente; não-admin recebe
  RAISE EXCEPTION, não uma lista vazia.
- p_limit é sempre restrito ao intervalo [1, 100],
  independente do valor recebido — teto controlado no servidor,
  não confiado ao chamador.
- total_count (via count(*) OVER()) acompanha cada linha,
  permitindo à interface montar a paginação sem uma segunda
  chamada.
- Campos retornados: apenas os definidos no Incremento 2 —
  username, display_name, avatar_path, email, created_at,
  is_admin. Nenhum outro dado de auth.users é exposto.

Revisão 1.1: au.email convertido explicitamente para TEXT
(auth.users.email é character varying(255) — Postgres exige
tipo exato no RETURN QUERY contra o RETURNS TABLE declarado;
sem o cast, a function falhava com "structure of query does not
match function result type", erro 42804, achado ao integrar a
Fase 3 do frontend).
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_list_users(
    p_limit INT DEFAULT 20,
    p_offset INT DEFAULT 0
)
RETURNS TABLE (
    id UUID,
    username TEXT,
    display_name TEXT,
    avatar_path TEXT,
    email TEXT,
    created_at TIMESTAMPTZ,
    is_admin BOOLEAN,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_limit INT;
    v_offset INT;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'acesso restrito a administradores.';
    END IF;

    v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
    v_offset := GREATEST(COALESCE(p_offset, 0), 0);

    RETURN QUERY
    SELECT
        up.id,
        up.username,
        up.display_name,
        up.avatar_path,
        au.email::text,
        au.created_at,
        (adm.id IS NOT NULL) AS is_admin,
        count(*) OVER() AS total_count
    FROM public.user_profile up
    JOIN auth.users au ON au.id = up.id
    LEFT JOIN public.admin_user adm ON adm.id = up.id
    ORDER BY up.created_at DESC
    LIMIT v_limit
    OFFSET v_offset;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_list_users(INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_users(INT, INT) TO authenticated;
