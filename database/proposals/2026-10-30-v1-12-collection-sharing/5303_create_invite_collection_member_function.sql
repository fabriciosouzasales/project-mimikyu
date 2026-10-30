/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5303 - Create invite_collection_member()
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA (V1-12)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Descrição...:
Titular convida um usuário existente pelo username exato (C-153/C-154).
Papel único neste incremento: VIEWER.

Regras de Negócio:
- Só o titular, em coleção ACTIVE (C-37/C-162). Coleção alheia ou
  inexistente → COLLECTION_NOT_FOUND (indistinguíveis — não enumera
  coleções).
- Username exato, normalizado (trim, sem '@' inicial, minúsculas) e no
  formato de user_profile (^[a-z0-9_]{3,20}$). Sem busca parcial, sem
  sugestão: não lista usuários. USER_NOT_FOUND revela só o que
  username_available() (1030) já revela publicamente.
- CANNOT_INVITE_SELF (titular nunca é membro, C-141/C-156).
- Idempotente: convite PENDING existente → outcome ALREADY_PENDING;
  ACTIVE → ALREADY_MEMBER (erro de domínio, nada muda); DECLINED → volta a
  PENDING (outcome REINVITED).
- Limite de 50 participações (PENDING+ACTIVE) por coleção, sob lock da
  linha da coleção (FOR UPDATE) — concorrência não ultrapassa o limite.
- Devolve só username e display_name do convidado (nada de id/e-mail).
================================================================
*/

CREATE OR REPLACE FUNCTION public.invite_collection_member(
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
