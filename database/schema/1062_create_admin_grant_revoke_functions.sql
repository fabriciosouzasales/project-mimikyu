/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1062 - Create admin_grant_admin() and admin_revoke_admin() Functions
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Functions SECURITY DEFINER para conceder/revogar o papel de
administrador, com registro em admin_action_log. Ver ADR-021.

Regras de Negócio:
- Ambas exigem is_admin() do chamador.
- Ambas adquirem a mesma trava consultiva de transação
  (pg_advisory_xact_lock), serializando concessões/revogações
  concorrentes — evita, por exemplo, duas revogações simultâneas
  removendo o último administrador ao mesmo tempo.
- admin_revoke_admin() bloqueia explicitamente a remoção do
  último administrador restante.
- metadata grava um retrato (username/e-mail de ator e alvo) no
  momento da ação, preservando contexto legível mesmo após uma
  eventual exclusão futura de qualquer um dos dois usuários.
================================================================
*/

CREATE OR REPLACE FUNCTION public.admin_grant_admin(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_id UUID := auth.uid();
    v_metadata JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'acesso restrito a administradores.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.user_profile WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'usuário não encontrado.';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('admin_user_mutation'));

    IF EXISTS (SELECT 1 FROM public.admin_user WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'usuário já é administrador.';
    END IF;

    INSERT INTO public.admin_user (id, granted_by)
    VALUES (p_user_id, v_actor_id);

    SELECT jsonb_build_object(
        'actor_username', actor.username,
        'actor_email', actor_auth.email,
        'target_username', target.username,
        'target_email', target_auth.email
    )
    INTO v_metadata
    FROM public.user_profile actor
    JOIN auth.users actor_auth ON actor_auth.id = actor.id
    JOIN public.user_profile target ON target.id = p_user_id
    JOIN auth.users target_auth ON target_auth.id = target.id
    WHERE actor.id = v_actor_id;

    INSERT INTO public.admin_action_log (actor_id, target_user_id, action, metadata)
    VALUES (v_actor_id, p_user_id, 'GRANT_ADMIN', v_metadata);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_grant_admin(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_grant_admin(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.admin_revoke_admin(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_id UUID := auth.uid();
    v_remaining INT;
    v_metadata JSONB;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'acesso restrito a administradores.';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('admin_user_mutation'));

    IF NOT EXISTS (SELECT 1 FROM public.admin_user WHERE id = p_user_id) THEN
        RAISE EXCEPTION 'usuário não é administrador.';
    END IF;

    SELECT count(*) INTO v_remaining FROM public.admin_user;
    IF v_remaining <= 1 THEN
        RAISE EXCEPTION 'não é possível remover o último administrador.';
    END IF;

    SELECT jsonb_build_object(
        'actor_username', actor.username,
        'actor_email', actor_auth.email,
        'target_username', target.username,
        'target_email', target_auth.email
    )
    INTO v_metadata
    FROM public.user_profile actor
    JOIN auth.users actor_auth ON actor_auth.id = actor.id
    JOIN public.user_profile target ON target.id = p_user_id
    JOIN auth.users target_auth ON target_auth.id = target.id
    WHERE actor.id = v_actor_id;

    DELETE FROM public.admin_user WHERE id = p_user_id;

    INSERT INTO public.admin_action_log (actor_id, target_user_id, action, metadata)
    VALUES (v_actor_id, p_user_id, 'REVOKE_ADMIN', v_metadata);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_revoke_admin(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_revoke_admin(UUID) TO authenticated;
