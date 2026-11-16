/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-14-v1-13-e1a-editor-role/5370_create_set_collection_member_role_function.sql
   sha256 da base: 83e42ca54e4bedc55bee9912dff79ca1065c9246a12da5c761241bcdf8541f43
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 1 função(ões); precheck da 5389; constantes md5 do próprio corpo atualizadas.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5370 - set_collection_member_role() — troca direta VIEWER ↔ EDITOR
              (V1-13 · E1-A)
Versão......: 1.1 (2026-11-15, `V1-13 / E1-A | VALIDATION STRATEGY CORRECTION-01`:
              postcheck exige ACL idêntica à da 5305, inclusive papéis além de anon/authenticated)
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-A | EDITOR ROLE FOUNDATION IMPLEMENTATION-01`
              (2026-11-14). Execução só pelo proprietário, depois de
              auditoria independente, da prova 5888 em PostgreSQL isolado e
              de autorização expressa (README desta pasta).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-14
Contrato....: C-240 (troca direta pelo titular, sem novo convite nem
              aceite, efeito imediato; convite pendente imutável), C-154
              (só o titular gerencia participações), C-141/C-156 (titular
              nunca é membro); 05d V1-13, entrega E1.1.
Depende de..: 5366.

Assinatura..: set_collection_member_role(p_collection_id uuid,
                                         p_membership_id uuid,
                                         p_role text) → jsonb
  Mesmo par (coleção, participação) da remove_collection_member (5305):
  a participação precisa pertencer à coleção informada, e a coleção ao
  usuário da sessão.

Regras:
- Sem sessão → NOT_AUTHENTICATED (28000).
- p_role normalizado (trim, maiúsculas); fora de VIEWER/EDITOR (inclusive
  NULL e 'OWNER') → INVALID_ROLE (22023). Nunca altera titularidade:
  a função só escreve collection_membership.role.
- Coleção alheia/inexistente, participação inexistente ou de outra coleção
  → MEMBERSHIP_NOT_FOUND (P0002), indistinguíveis. Um membro (VIEWER ou
  EDITOR) não é titular e cai aqui: não promove a si mesmo nem a outros.
- Defesa adicional: participação do próprio usuário da sessão →
  MEMBERSHIP_NOT_FOUND (impossível pelo invariante C-141, verificado mesmo assim).
- PENDING → INVITE_PENDING_ROLE_IMMUTABLE (55000): cancelar e convidar de novo.
- DECLINED → MEMBER_NOT_ACTIVE (55000).
- ACTIVE com o mesmo papel → outcome UNCHANGED (idempotente, nada grava).
- ACTIVE com outro papel → outcome CHANGED, previous_role. Coleção
  arquivada também aceita (é gestão de participação, como a remoção 5305;
  escrita do EDITOR em coleção arquivada continua barrada na E1-B).
- Efeito imediato: a próxima leitura de collection_member_role (5367) já
  vê o papel novo. Travas: coleção (FOR UPDATE) → participação (FOR
  UPDATE) — mesma ordem do convite 5369; a E1-B lerá a participação com
  trava compartilhada para serializar com esta troca.
- Retorno: outcome, membership_id, role, previous_role, status. Sem ids de
  usuário, username ou e-mail.
Canal.......: psql. Idempotência: função já presente com o corpo desta
              proposta → 'JÁ APLICADA'. Reversão: R5370 em ROLLBACK_E1A.sql.
Como validar: 5888, itens 0.5 e 4.x.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_oid oid := to_regprocedure('public.set_collection_member_role(uuid, uuid, text)');
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5370: 5366 não aplicada';
  end if;
  if v_oid is not null
     and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) = '840d1e5c3cc55f253a2579eda7b7703d' then
    raise exception 'PRECHECK 5370: JÁ APLICADA — não reaplicar';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'set_collection_member_role') then
    raise exception 'PRECHECK 5370: ESTADO DIVERGENTE — já existe set_collection_member_role com outro corpo/assinatura';
  end if;
end;
$pre$;

CREATE FUNCTION public.set_collection_member_role(
    p_collection_id UUID,
    p_membership_id UUID,
    p_role TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_role   TEXT := upper(btrim(p_role));
    v_row    public.collection_membership%ROWTYPE;
BEGIN
    perform public.v1_13_assert_capability();  -- G1 (D-E1)
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '28000';
    END IF;
    IF v_role IS NULL OR v_role NOT IN ('VIEWER', 'EDITOR') THEN
        RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';
    END IF;

    PERFORM 1
    FROM public.collection c
    WHERE c.id = p_collection_id
      AND c.owner_user_id = v_user
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MEMBERSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    SELECT * INTO v_row
    FROM public.collection_membership m
    WHERE m.id = p_membership_id
      AND m.collection_id = p_collection_id
    FOR UPDATE;
    IF NOT FOUND OR v_row.user_id = v_user THEN
        RAISE EXCEPTION 'MEMBERSHIP_NOT_FOUND' USING ERRCODE = 'P0002';
    END IF;

    IF v_row.status = 'PENDING' THEN
        RAISE EXCEPTION 'INVITE_PENDING_ROLE_IMMUTABLE' USING ERRCODE = '55000',
            HINT = 'Cancele o convite pendente e convide novamente com o outro papel.';
    END IF;
    IF v_row.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'MEMBER_NOT_ACTIVE' USING ERRCODE = '55000';
    END IF;

    IF v_row.role = v_role THEN
        RETURN jsonb_build_object('outcome', 'UNCHANGED', 'membership_id', v_row.id,
            'role', v_role, 'previous_role', v_row.role, 'status', 'ACTIVE');
    END IF;

    UPDATE public.collection_membership m
    SET role = v_role
    WHERE m.id = v_row.id
      AND m.status = 'ACTIVE';

    RETURN jsonb_build_object('outcome', 'CHANGED', 'membership_id', v_row.id,
        'role', v_role, 'previous_role', v_row.role, 'status', 'ACTIVE');
END;
$$;

COMMENT ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) IS
    'V1-13 E1-A (5370): o titular troca diretamente o papel de um participante ACTIVE entre VIEWER e EDITOR (C-240), com efeito imediato. Convite PENDING é imutável; não altera titularidade.';

REVOKE ALL ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_collection_member_role(UUID, UUID, TEXT) TO authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.set_collection_member_role(uuid, uuid, text)');
  v_ref oid := to_regprocedure('public.remove_collection_member(uuid, uuid)');
begin
  -- Paridade de ACL com a 5305 (gestão de participação pelo titular). ACL nula = erro.
  if v_ref is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_oid) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_ref) is null
     or (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_oid)
        is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_ref) then
    raise exception 'POSTCHECK 5370: ACL difere da remove_collection_member (5305)';
  end if;
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from '840d1e5c3cc55f253a2579eda7b7703d' then
    raise exception 'POSTCHECK 5370: set_collection_member_role fora do estado esperado';
  end if;
end;
$post$;

commit;
