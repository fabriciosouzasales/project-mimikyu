/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5368 - Papel real nas leituras de convites, "Compartilhadas com
              você" e cabeçalho do participante (V1-13 · E1-A)
Versão......: 1.1 (2026-11-15, `V1-13 / E1-A | VALIDATION STRATEGY CORRECTION-01`:
              ACL das três leituras guardada no precheck e exigida idêntica no postcheck)
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-A | EDITOR ROLE FOUNDATION IMPLEMENTATION-01`
              (2026-11-14). Execução só pelo proprietário, depois de
              auditoria independente, da prova 5888 em PostgreSQL isolado e
              de autorização expressa (README desta pasta).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-14
Contrato....: C-240 (papel visível ao convidado e ao membro), C-243
              (nenhum dado novo além do papel); 05d V1-13, entrega E1.1.
Depende de..: 5367 (collection_member_role).

Mudança mínima, CREATE OR REPLACE (todas devolvem JSONB — assinatura,
ACL e SECURITY DEFINER preservados):
  5309 get_my_collection_invites()      + chave "role" (papel OFERECIDO no
                                          convite PENDING do próprio usuário)
  5311 get_collections_shared_with_me() + chave "role" (papel do próprio
                                          usuário em cada coleção ACTIVE)
  5312 get_shared_collection(uuid)      + chave "role" = collection_member_role
                                          ('OWNER' | 'EDITOR' | 'VIEWER')
Inalterados de propósito:
  - "access" da 5312 continua 'OWNER' | 'VIEWER' (nível de leitura da
    5302): as rotas `compartilhada/[id]` testam access === 'VIEWER' e
    continuam valendo para o EDITOR.
  - "membership_id" da 5312 continua para todo participante (botão Sair).
  - 5308 get_my_collection_sharing já devolve "role" de cada participante
    ao titular desde a V1-12 — nenhuma mudança.
Privacidade: o papel exposto é só o do próprio usuário (5309/5311/5312);
  nenhum membro vê papel, existência ou identidade de outro membro. Os
  analisadores do frontend publicado (web/lib/colecoes/sharing.ts) leem
  por nome de chave e ignoram chaves novas.
Canal.......: psql. Precheck: md5 do corpo vigente = canônico V1-12
              (valores derivados de database/schema/; confirmar na S0).
Idempotência: corpos já iguais aos desta proposta → 'JÁ APLICADA'.
Reversão....: R5368 em ROLLBACK_E1A.sql (reaplica os corpos 5309/5311/5312).
Como validar: 5888, itens 0.3 e 3.x/6.x.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  f9  oid := to_regprocedure('public.get_my_collection_invites()');
  f11 oid := to_regprocedure('public.get_collections_shared_with_me()');
  f12 oid := to_regprocedure('public.get_shared_collection(uuid)');
  m9 text; m11 text; m12 text;
begin
  if to_regprocedure('public.collection_member_role(uuid)') is null then
    raise exception 'PRECHECK 5368: 5367 não aplicada';
  end if;
  if f9 is null or f11 is null or f12 is null then
    raise exception 'PRECHECK 5368: ESTADO DIVERGENTE — leitura V1-12 ausente';
  end if;
  select pg_catalog.md5(p.prosrc) into m9  from pg_catalog.pg_proc p where p.oid = f9;
  select pg_catalog.md5(p.prosrc) into m11 from pg_catalog.pg_proc p where p.oid = f11;
  select pg_catalog.md5(p.prosrc) into m12 from pg_catalog.pg_proc p where p.oid = f12;
  if m9 = '5f38c1ec0471b07344aec5551292a392' and m11 = '5599f4f8ac5db1cfe893345d4884b244' and m12 = '69d69fd11dddcaedabe7368a3e038368' then
    raise exception 'PRECHECK 5368: JÁ APLICADA — não reaplicar';
  end if;
  if m9  is distinct from '74ea7dc1af9032e337b6c0e04ae7c478'
     or m11 is distinct from '67b4395f013a2591fcb1e1585ba53a16'
     or m12 is distinct from '254d56f3f9c8097ee3d36e580c851c29' then
    raise exception 'PRECHECK 5368: ESTADO DIVERGENTE — corpos vigentes diferem da V1-12 canônica (5309=% 5311=% 5312=%)', m9, m11, m12;
  end if;
  if (select p.proacl from pg_catalog.pg_proc p where p.oid = f9) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = f11) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = f12) is null then
    raise exception 'PRECHECK 5368: ESTADO DIVERGENTE — ACL nula (privilégio padrão, inclui PUBLIC)';
  end if;
  -- ACL vigente guardada na transação para o postcheck (preservação total de EXECUTE).
  perform pg_catalog.set_config('mmkyu.e1a_5368_acl',
    (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f9) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f11) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f12), true);
end;
$pre$;

-- 5309 + role ------------------------------------------------------------------------
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
               m.role               AS role,
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

REVOKE ALL ON FUNCTION public.get_my_collection_invites() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_collection_invites() TO authenticated;

-- 5311 + role ------------------------------------------------------------------------
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
               m.role              AS role,
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

REVOKE ALL ON FUNCTION public.get_collections_shared_with_me() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_collections_shared_with_me() TO authenticated;

-- 5312 + role ------------------------------------------------------------------------
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
        'role', public.collection_member_role(c.id),
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

REVOKE ALL ON FUNCTION public.get_shared_collection(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shared_collection(uuid) TO authenticated;

do $post$
declare
  f oid;
  f9  oid := to_regprocedure('public.get_my_collection_invites()');
  f11 oid := to_regprocedure('public.get_collections_shared_with_me()');
  f12 oid := to_regprocedure('public.get_shared_collection(uuid)');
begin
  if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f9) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f11) || '|' || (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f12)
     is distinct from pg_catalog.current_setting('mmkyu.e1a_5368_acl', true) then
    raise exception 'POSTCHECK 5368: ACL das leituras mudou';
  end if;
  foreach f in array array[to_regprocedure('public.get_my_collection_invites()'),
                           to_regprocedure('public.get_collections_shared_with_me()'),
                           to_regprocedure('public.get_shared_collection(uuid)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5368: leitura fora do estado esperado (%)', f::regprocedure;
    end if;
  end loop;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_my_collection_invites()')) is distinct from '5f38c1ec0471b07344aec5551292a392'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_collections_shared_with_me()')) is distinct from '5599f4f8ac5db1cfe893345d4884b244'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection(uuid)')) is distinct from '69d69fd11dddcaedabe7368a3e038368' then
    raise exception 'POSTCHECK 5368: corpo gravado difere do arquivo (fim de linha/canal?)';
  end if;
end;
$post$;

commit;
