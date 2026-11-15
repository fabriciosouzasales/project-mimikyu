/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5369 - invite_collection_member com papel (VIEWER | EDITOR)
              (V1-13 · E1-A) — substitui a assinatura (uuid, text) da 5303
Versão......: 1.1 (2026-11-15, `V1-13 / E1-A | VALIDATION STRATEGY CORRECTION-01`:
              ACL da assinatura antiga guardada e exigida idêntica na nova (inclui service_role e privilégios padrão))
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-A | EDITOR ROLE FOUNDATION IMPLEMENTATION-01`
              (2026-11-14). Execução só pelo proprietário, depois de
              auditoria independente, da prova 5888 em PostgreSQL isolado e
              de autorização expressa (README desta pasta).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-14
Contrato....: C-240 (convite com papel; padrão VIEWER; papel do convite
              pendente imutável), C-153/C-154 (só o titular convida);
              05d V1-13, entrega E1.1.
Depende de..: 5366 (CHECK aceita EDITOR).

Assinatura..: invite_collection_member(p_collection_id uuid,
                                       p_username text,
                                       p_role text DEFAULT 'VIEWER') → jsonb
  A assinatura antiga (uuid, text) é REMOVIDA na mesma transação (DROP +
  CREATE). Não ficam duas sobrecargas: com as duas, a chamada atual do
  frontend ({p_collection_id, p_username}) seria ambígua no PostgREST.
  Com o DEFAULT, a mesma chamada resolve para a nova função e grava VIEWER
  — comportamento idêntico ao da V1-12.

Regras (inalteradas da 5303, salvo o papel):
- Só o titular, coleção ACTIVE; alheia/inexistente → COLLECTION_NOT_FOUND;
  username exato normalizado; CANNOT_INVITE_SELF; limite 50 sob FOR UPDATE
  da coleção; devolve só username/display_name do convidado.
- p_role: NULL → 'VIEWER' (padrão); normalizado (trim, maiúsculas); fora de
  VIEWER/EDITOR → INVALID_ROLE (22023), validado ANTES de qualquer leitura
  da coleção.
- ACTIVE → ALREADY_MEMBER (23505), sem mudar o papel: troca de papel de
  membro ativo é só pela 5370 (C-240).
- PENDING com o MESMO papel → ALREADY_PENDING (idempotente).
- PENDING com OUTRO papel → INVITE_PENDING_ROLE_IMMUTABLE (55000), nada
  muda: o papel de convite pendente é imutável; o titular cancela
  (remove_collection_member, 5305) e convida de novo (C-240).
- DECLINED com o MESMO papel → volta a PENDING na mesma linha (REINVITED,
  mesmo membership_id — comportamento da V1-12).
- DECLINED com OUTRO papel → a linha recusada é apagada e nasce um convite
  NOVO (REINVITED, membership_id NOVO). Assim nenhuma aba antiga do
  convidado consegue aceitar, com o id anterior, um papel que ele não viu
  (respond_collection_invite responde INVITE_NOT_FOUND).
- Retorno ganha "role" (papel do convite gravado). Nada de id/e-mail.
Canal.......: psql. Precheck: corpo vigente = 5303 canônica (md5 derivado
              do arquivo; confirmar na S0), sobrecarga única, sem
              dependentes. Idempotência: só a nova assinatura presente com
              o corpo desta proposta → 'JÁ APLICADA'.
Reversão....: R5369 em ROLLBACK_E1A.sql (só sem convite/participação EDITOR).
Como validar: 5888, itens 0.4 e 1.x/2.x/5.x.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_old oid := to_regprocedure('public.invite_collection_member(uuid, text)');
  v_new oid := to_regprocedure('public.invite_collection_member(uuid, text, text)');
begin
  if to_regclass('public.collection_membership') is null
     or (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
          where k.conrelid = 'public.collection_membership'::regclass
            and k.conname = 'chk_collection_membership_role')
        is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5369: 5366 não aplicada';
  end if;
  if v_old is null and v_new is not null
     and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_new) = '52b17e64b1daca51d1d615763d41c77b' then
    raise exception 'PRECHECK 5369: JÁ APLICADA — não reaplicar';
  end if;
  if v_old is null or v_new is not null then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — assinaturas vigentes inesperadas (antiga=% nova=%)', v_old, v_new;
  end if;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'invite_collection_member') <> 1 then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — mais de uma sobrecarga de invite_collection_member';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_old)
     is distinct from 'ed7418f20c1004b23c58c68c84a6ae73' then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — corpo vigente difere da 5303 canônica';
  end if;
  if exists (select 1 from pg_catalog.pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid = v_old and d.deptype = 'n') then
    raise exception 'PRECHECK 5369: há objetos dependentes da assinatura antiga';
  end if;
  if (select p.proacl from pg_catalog.pg_proc p where p.oid = v_old) is null then
    raise exception 'PRECHECK 5369: ESTADO DIVERGENTE — ACL nula na assinatura antiga';
  end if;
  -- ACL da assinatura antiga guardada para o postcheck: o DROP a apaga, e a nova
  -- função recebe privilégios padrão do esquema (podem incluir service_role/anon).
  perform pg_catalog.set_config('mmkyu.e1a_5369_acl', (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_old), true);
end;
$pre$;

DROP FUNCTION public.invite_collection_member(UUID, TEXT);

CREATE FUNCTION public.invite_collection_member(
    p_collection_id UUID,
    p_username TEXT,
    p_role TEXT DEFAULT 'VIEWER'
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
    v_role        TEXT := upper(btrim(coalesce(p_role, 'VIEWER')));
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
    IF v_role NOT IN ('VIEWER', 'EDITOR') THEN
        RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';
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
      AND m.user_id = v_target
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.status = 'ACTIVE' THEN
            RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = '23505';
        ELSIF v_existing.status = 'PENDING' THEN
            IF v_existing.role IS DISTINCT FROM v_role THEN
                RAISE EXCEPTION 'INVITE_PENDING_ROLE_IMMUTABLE' USING ERRCODE = '55000',
                    HINT = 'Cancele o convite pendente e convide novamente com o outro papel.';
            END IF;
            RETURN jsonb_build_object(
                'outcome', 'ALREADY_PENDING',
                'membership_id', v_existing.id,
                'username', v_username,
                'display_name', v_display,
                'status', 'PENDING',
                'role', v_existing.role
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
        IF v_existing.role IS NOT DISTINCT FROM v_role THEN
            -- DECLINED → PENDING, mesmo papel: mesma linha (V1-12).
            UPDATE public.collection_membership m
            SET status = 'PENDING',
                responded_at = NULL,
                invited_by = v_user,
                invited_at = now()
            WHERE m.id = v_existing.id
              AND m.status = 'DECLINED'
            RETURNING m.id INTO v_id;
        ELSE
            -- DECLINED → convite NOVO com outro papel: id novo, o antigo deixa de existir.
            DELETE FROM public.collection_membership m
            WHERE m.id = v_existing.id
              AND m.status = 'DECLINED';
            INSERT INTO public.collection_membership (collection_id, user_id, role, status, invited_by)
            VALUES (p_collection_id, v_target, v_role, 'PENDING', v_user)
            RETURNING id INTO v_id;
        END IF;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'INVITE_STATE_CHANGED' USING ERRCODE = '40001';
        END IF;
        RETURN jsonb_build_object(
            'outcome', 'REINVITED',
            'membership_id', v_id,
            'username', v_username,
            'display_name', v_display,
            'status', 'PENDING',
            'role', v_role
        );
    END IF;

    INSERT INTO public.collection_membership (collection_id, user_id, role, status, invited_by)
    VALUES (p_collection_id, v_target, v_role, 'PENDING', v_user)
    ON CONFLICT (collection_id, user_id) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        -- Corrida residual (a trava da coleção já serializa convites): só
        -- devolve ALREADY_PENDING se o que ficou gravado for exatamente o pedido.
        SELECT * INTO v_existing FROM public.collection_membership m
        WHERE m.collection_id = p_collection_id AND m.user_id = v_target;
        IF v_existing.status = 'PENDING' AND v_existing.role = v_role THEN
            RETURN jsonb_build_object('outcome', 'ALREADY_PENDING', 'membership_id', v_existing.id,
                'username', v_username, 'display_name', v_display, 'status', 'PENDING', 'role', v_role);
        END IF;
        RAISE EXCEPTION 'INVITE_STATE_CHANGED' USING ERRCODE = '40001';
    END IF;

    RETURN jsonb_build_object(
        'outcome', 'INVITED',
        'membership_id', v_id,
        'username', v_username,
        'display_name', v_display,
        'status', 'PENDING',
        'role', v_role
    );
END;
$$;

COMMENT ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) IS
    'V1-12 (5303) + V1-13 E1-A (5369): titular convida pelo username exato com papel VIEWER (padrão) ou EDITOR. Papel de convite PENDING é imutável (INVITE_PENDING_ROLE_IMMUTABLE); recusado com outro papel vira convite novo (id novo). Membro ativo: troca só pela set_collection_member_role (5370).';

REVOKE ALL ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_collection_member(UUID, TEXT, TEXT) TO authenticated;

do $post$
declare
  v_new oid := to_regprocedure('public.invite_collection_member(uuid, text, text)');
begin
  if to_regprocedure('public.invite_collection_member(uuid, text)') is not null then
    raise exception 'POSTCHECK 5369: assinatura antiga ainda existe';
  end if;
  if (select count(*) from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'invite_collection_member') <> 1 then
    raise exception 'POSTCHECK 5369: sobrecarga inesperada';
  end if;
  if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_new)
     is distinct from pg_catalog.current_setting('mmkyu.e1a_5369_acl', true) then
    raise exception 'POSTCHECK 5369: ACL da nova assinatura difere da antiga (%)', (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_new);
  end if;
  if v_new is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_new) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_new) is distinct from array['search_path=""']
     or (select p.pronargdefaults from pg_catalog.pg_proc p where p.oid = v_new) is distinct from 1::int2
     or pg_catalog.has_function_privilege('authenticated', v_new, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_new, 'EXECUTE') is not false
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_new) is distinct from '52b17e64b1daca51d1d615763d41c77b' then
    raise exception 'POSTCHECK 5369: invite_collection_member fora do estado esperado';
  end if;
end;
$post$;

commit;
