/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5367 - collection_member_role() — papel real (interna) (V1-13 · E1-A)
Versão......: 1.1 (2026-11-15, `V1-13 / E1-A | VALIDATION STRATEGY CORRECTION-01`:
              postcheck exige ACL idêntica à da 5302, inclusive papéis além de anon/authenticated)
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-A | EDITOR ROLE FOUNDATION IMPLEMENTATION-01`
              (2026-11-14). Execução só pelo proprietário, depois de
              auditoria independente, da prova 5888 em PostgreSQL isolado e
              de autorização expressa (README desta pasta).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-14
Contrato....: C-234 (autorização por coleção, avaliada no servidor),
              C-240; 05d V1-13, entrega E1.1.

Descrição...:
Devolve o PAPEL REAL do usuário da sessão na coleção:
  'OWNER'  — titular (collection.owner_user_id);
  'EDITOR' — participação ACTIVE com role EDITOR;
  'VIEWER' — participação ACTIVE com role VIEWER;
  NULL     — qualquer outro caso (sem sessão, convite PENDING ou DECLINED,
             estranho, coleção inexistente — indistinguíveis).

Separação deliberada de collection_share_role (5302), que NÃO muda:
  5302 = NÍVEL DE LEITURA ('OWNER' | 'VIEWER' | 'PUBLIC' | NULL). Todo
  membro ACTIVE, de qualquer papel, continua recebendo 'VIEWER' ali — é o
  que mantém as nove leituras compartilhadas (5312–5316, 5320, 5321,
  5326, 5328) e as rotas `compartilhada/[id]` funcionando para o EDITOR
  sem alteração. Esta função é a fonte do papel para exibição (5368) e,
  na E1-B, para a autorização de escrita (que acrescentará trava própria;
  esta função só lê).

Regras:
- Visibilidade PUBLIC não é papel: nunca devolve 'PUBLIC'.
- Não considera lifecycle (mesma regra da 5302); escrita em coleção
  arquivada continua barrada pelas funções de escrita.
- Interna: sem EXECUTE para PUBLIC/anon/authenticated. Só funções
  SECURITY DEFINER do mesmo dono a chamam.
Canal.......: psql. Idempotência: já presente com o mesmo corpo →
              'JÁ APLICADA'. Reversão: R5367 em ROLLBACK_E1A.sql.
Como validar: 5888, itens 0.2 e 3.x.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regclass('public.collection_membership') is null then
    raise exception 'PRECHECK 5367: collection_membership ausente';
  end if;
  if to_regprocedure('public.collection_member_role(uuid)') is not null
     and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
           where p.oid = to_regprocedure('public.collection_member_role(uuid)')) = '1e90ce8a9f4d88c067e9125bf602eff8' then
    raise exception 'PRECHECK 5367: JÁ APLICADA — não reaplicar';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'collection_member_role') then
    raise exception 'PRECHECK 5367: ESTADO DIVERGENTE — já existe collection_member_role com outro corpo/assinatura';
  end if;
end;
$pre$;

CREATE FUNCTION public.collection_member_role(p_collection_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
    SELECT CASE
        WHEN (select auth.uid()) IS NULL THEN NULL
        WHEN c.owner_user_id = (select auth.uid()) THEN 'OWNER'
        ELSE (
            SELECT m.role
            FROM public.collection_membership m
            WHERE m.collection_id = c.id
              AND m.user_id = (select auth.uid())
              AND m.status = 'ACTIVE'
        )
    END
    FROM public.collection c
    WHERE c.id = p_collection_id;
$$;

COMMENT ON FUNCTION public.collection_member_role(UUID) IS
    'V1-13 E1-A (5367): papel real do usuário da sessão na coleção — OWNER | EDITOR | VIEWER | NULL. Interna (sem EXECUTE para API). Não substitui collection_share_role (5302), que segue sendo o nível de leitura.';

REVOKE ALL ON FUNCTION public.collection_member_role(UUID) FROM PUBLIC, anon, authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.collection_member_role(uuid)');
  v_ref oid := to_regprocedure('public.collection_share_role(uuid)');
begin
  -- Paridade de ACL com a 5302 (mesma classe: interna). Inclui papéis fora de
  -- anon/authenticated (ex.: service_role por privilégio padrão). ACL nula = erro.
  if v_ref is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_oid) is null or (select p.proacl from pg_catalog.pg_proc p where p.oid = v_ref) is null
     or (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_oid)
        is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = v_ref) then
    raise exception 'POSTCHECK 5367: ACL difere da collection_share_role (5302)';
  end if;
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from '1e90ce8a9f4d88c067e9125bf602eff8' then
    raise exception 'POSTCHECK 5367: collection_member_role fora do estado esperado';
  end if;
end;
$post$;

commit;
