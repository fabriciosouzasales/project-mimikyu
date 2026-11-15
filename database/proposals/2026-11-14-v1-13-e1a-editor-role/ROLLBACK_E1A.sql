/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_E1A — reversão de 5366–5370 (V1-13 · E1-A)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Uso exclusivo de recuperação, pelo
              proprietário, com autorização expressa. Ordem obrigatória:
              R5370 → R5369 → R5368 → R5367 → R5366 (inversa da aplicação).
              Cada bloco é uma transação própria (psql).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-14
Corpos......: os corpos restaurados são cópia literal de database/schema/
              5303, 5309, 5311 e 5312 (V1-12, canônicos). O POSTCHECK de
              cada bloco compara o md5 com os valores canônicos.
Pré-condição: nenhuma participação ou convite EDITOR (R5369/R5366). Se
              houver, o titular primeiro rebaixa (5370) ou remove (5305) —
              a reversão nunca converte papel silenciosamente.
================================================================
*/

-- R5370 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
drop function if exists public.set_collection_member_role(uuid, uuid, text);
commit;

-- R5369 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
do $pre$
begin
  if exists (select 1 from public.collection_membership m where m.role <> 'VIEWER') then
    raise exception 'R5369: há participação/convite EDITOR — rebaixar ou remover antes';
  end if;
  if to_regprocedure('public.invite_collection_member(uuid, text, text)') is null
     or to_regprocedure('public.invite_collection_member(uuid, text)') is not null then
    raise exception 'R5369: estado inesperado das assinaturas do convite';
  end if;
end;
$pre$;
DROP FUNCTION public.invite_collection_member(UUID, TEXT, TEXT);

CREATE FUNCTION public.invite_collection_member(
    p_collection_id UUID,
    p_username TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user        UUID := auth.uid();
    v_lifecycle   TEXT;
    v_username    TEXT := lower(btrim(coalesce(p_username, '')));
    v_target      UUID;
    v_display     TEXT;
    v_existing    public.collection_membership%ROWTYPE;
    v_count       INTEGER;
    v_id          UUID;
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;

    IF left(v_username, 1) = '@' THEN
        v_username := substr(v_username, 2);
    END IF;
    IF v_username !~ '^[a-z0-9_]{3,20}$' THEN
        RAISE EXCEPTION 'INVALID_USERNAME' USING ERRCODE = '22023';
    END IF;

    SELECT c.lifecycle_status INTO v_lifecycle
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND c.owner_user_id = v_user
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'COLLECTION_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    IF v_lifecycle <> 'ACTIVE' THEN
        RAISE EXCEPTION 'COLLECTION_ARCHIVED' USING ERRCODE = '55000';
    END IF;

    SELECT up.id, up.display_name INTO v_target, v_display
    FROM public.user_profile up
    WHERE up.username = v_username;

    IF v_target IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;
    IF v_target = v_user THEN
        RAISE EXCEPTION 'CANNOT_INVITE_SELF' USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_existing
    FROM public.collection_membership m
    WHERE m.collection_id = p_collection_id
      AND m.user_id = v_target;

    IF FOUND THEN
        IF v_existing.status = 'ACTIVE' THEN
            RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = '23505';
        ELSIF v_existing.status = 'PENDING' THEN
            RETURN jsonb_build_object(
                'outcome', 'ALREADY_PENDING',
                'membership_id', v_existing.id,
                'username', v_username,
                'display_name', v_display,
                'status', 'PENDING'
            );
        END IF;
    END IF;

    SELECT count(*) INTO v_count
    FROM public.collection_membership m
    WHERE m.collection_id = p_collection_id
      AND m.status IN ('PENDING', 'ACTIVE');
    IF v_count >= 50 THEN
        RAISE EXCEPTION 'MEMBER_LIMIT' USING ERRCODE = '54000';
    END IF;

    IF v_existing.id IS NOT NULL THEN
        -- DECLINED → PENDING (novo convite explícito do titular).
        UPDATE public.collection_membership m
        SET status = 'PENDING',
            responded_at = NULL,
            invited_by = v_user,
            invited_at = now()
        WHERE m.id = v_existing.id
        RETURNING m.id INTO v_id;
        RETURN jsonb_build_object(
            'outcome', 'REINVITED',
            'membership_id', v_id,
            'username', v_username,
            'display_name', v_display,
            'status', 'PENDING'
        );
    END IF;

    INSERT INTO public.collection_membership (collection_id, user_id, role, status, invited_by)
    VALUES (p_collection_id, v_target, 'VIEWER', 'PENDING', v_user)
    ON CONFLICT (collection_id, user_id) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        -- Corrida com outro convite idêntico: devolve o que ficou gravado.
        SELECT m.id INTO v_id FROM public.collection_membership m
        WHERE m.collection_id = p_collection_id AND m.user_id = v_target;
        RETURN jsonb_build_object('outcome', 'ALREADY_PENDING', 'membership_id', v_id,
            'username', v_username, 'display_name', v_display, 'status', 'PENDING');
    END IF;

    RETURN jsonb_build_object(
        'outcome', 'INVITED',
        'membership_id', v_id,
        'username', v_username,
        'display_name', v_display,
        'status', 'PENDING'
    );
END;
$$;

REVOKE ALL ON FUNCTION public.invite_collection_member(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_collection_member(UUID, TEXT) TO authenticated;
do $post$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.invite_collection_member(uuid, text)'))
     is distinct from 'ed7418f20c1004b23c58c68c84a6ae73' then
    raise exception 'R5369 POSTCHECK: corpo restaurado difere da 5303 canônica';
  end if;
end;
$post$;
commit;

-- R5368 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.get_my_collection_invites()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.invited_at DESC, x.membership_id), '[]'::jsonb)
    FROM (
        SELECT m.id                 AS membership_id,
               c.id                 AS collection_id,
               c.name               AS collection_name,
               c.mode               AS mode,
               c.completion_policy  AS completion_policy,
               cs.name::text        AS card_set_name,
               owner.display_name   AS owner_display_name,
               owner.username       AS owner_username,
               m.invited_at         AS invited_at
        FROM public.collection_membership m
        JOIN public.collection c         ON c.id = m.collection_id
        JOIN public.user_profile owner   ON owner.id = c.owner_user_id
        LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
        LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
        WHERE (select auth.uid()) IS NOT NULL
          AND m.user_id = (select auth.uid())
          AND m.status = 'PENDING'
        ORDER BY m.invited_at DESC, m.id
        LIMIT 50
    ) x;
$$;

CREATE OR REPLACE FUNCTION public.get_collections_shared_with_me()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.accepted_at DESC, x.collection_id), '[]'::jsonb)
    FROM (
        SELECT c.id                AS collection_id,
               c.name              AS name,
               c.mode              AS mode,
               c.completion_policy AS completion_policy,
               c.lifecycle_status  AS lifecycle_status,
               c.cover_finish      AS cover_finish,
               cs.code::text       AS card_set_code,
               cs.name::text       AS card_set_name,
               owner.display_name  AS owner_display_name,
               m.responded_at      AS accepted_at,
               (SELECT count(*) FROM public.collection_allocation ca WHERE ca.collection_id = c.id) AS copies_count,
               s.total_positions, s.satisfied_positions, s.progress_percentage, s.is_complete
        FROM public.collection_membership m
        JOIN public.collection c       ON c.id = m.collection_id
        JOIN public.user_profile owner ON owner.id = c.owner_user_id
        LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
        LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
        LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
        LEFT JOIN LATERAL public.collection_completion_summary_shared(c.id) s ON true
        WHERE (select auth.uid()) IS NOT NULL
          AND m.user_id = (select auth.uid())
          AND m.status = 'ACTIVE'
        ORDER BY m.responded_at DESC, c.id
        LIMIT 100
    ) x;
$$;

CREATE OR REPLACE FUNCTION public.get_shared_collection(p_collection_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_role   TEXT;
    v_result JSONB;
BEGIN
    v_role := public.collection_share_role(p_collection_id);
    IF v_role IS NULL OR v_role NOT IN ('OWNER', 'VIEWER') THEN
        RETURN NULL;
    END IF;

    SELECT jsonb_build_object(
        'collection_id', c.id,
        'name', c.name,
        'description', c.description,
        'mode', c.mode,
        'completion_policy', c.completion_policy,
        'lifecycle_status', c.lifecycle_status,
        'visibility', c.visibility,
        'cover_finish', c.cover_finish,
        'card_set_code', cs.code,
        'card_set_name', cs.name,
        'card_set_logo_path', cs.logo_storage_path,
        'owner_display_name', owner.display_name,
        'access', v_role,
        'membership_id', CASE WHEN v_role = 'VIEWER' THEN (
            SELECT m.id FROM public.collection_membership m
            WHERE m.collection_id = c.id AND m.user_id = (select auth.uid()) AND m.status = 'ACTIVE'
        ) END,
        'copies_count', (SELECT count(*) FROM public.collection_allocation ca WHERE ca.collection_id = c.id),
        'total_positions', s.total_positions,
        'satisfied_positions', s.satisfied_positions,
        'progress_percentage', s.progress_percentage,
        'is_complete', s.is_complete
    )
    INTO v_result
    FROM public.collection c
    JOIN public.user_profile owner ON owner.id = c.owner_user_id
    LEFT JOIN public.collection_reference cr            ON cr.collection_id = c.id
    LEFT JOIN public.collection_card_set_reference ccsr ON ccsr.collection_reference_id = cr.id
    LEFT JOIN public.card_set cs                        ON cs.id = ccsr.card_set_id
    LEFT JOIN LATERAL public.collection_completion_summary_shared(c.id) s ON true
    WHERE c.id = p_collection_id;

    RETURN v_result;
END;
$$;

do $post$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_collection_invites()')) is distinct from '74ea7dc1af9032e337b6c0e04ae7c478'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_collections_shared_with_me()')) is distinct from '67b4395f013a2591fcb1e1585ba53a16'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection(uuid)')) is distinct from '254d56f3f9c8097ee3d36e580c851c29' then
    raise exception 'R5368 POSTCHECK: corpos restaurados diferem da V1-12 canônica';
  end if;
end;
$post$;
commit;

-- R5367 (depois da R5368: a 5312 da E1-A chama collection_member_role) ----------------------
begin;
set local lock_timeout = '5s';
do $pre$
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection(uuid)'))
     is distinct from '254d56f3f9c8097ee3d36e580c851c29' then
    raise exception 'R5367: aplicar R5368 antes';
  end if;
end;
$pre$;
drop function if exists public.collection_member_role(uuid);
commit;

-- R5366 -------------------------------------------------------------------------------------
begin;
set local lock_timeout = '5s';
do $pre$
begin
  if exists (select 1 from public.collection_membership m where m.role <> 'VIEWER') then
    raise exception 'R5366: há participação/convite EDITOR — rebaixar ou remover antes';
  end if;
end;
$pre$;
alter table public.collection_membership drop constraint chk_collection_membership_role;
alter table public.collection_membership add constraint chk_collection_membership_role check (role in ('VIEWER'));
comment on table public.collection_membership is
    'Collection Membership (C-142/C-143/C-153, V1-12): participação de usuário não titular. Titular = collection.owner_user_id (C-141), nunca uma linha aqui. Acesso só pelas funções 5303–5313.';
commit;
