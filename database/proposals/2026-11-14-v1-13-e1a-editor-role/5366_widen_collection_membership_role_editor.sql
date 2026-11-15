/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5366 - collection_membership aceita o papel EDITOR (V1-13 · E1-A)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-A | EDITOR ROLE FOUNDATION IMPLEMENTATION-01`
              (2026-11-14). Execução só pelo proprietário, depois de
              auditoria independente, da prova 5888 em PostgreSQL isolado e
              de autorização expressa (README desta pasta).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-14
Contrato....: concept-decisions C-234, C-240 (V1-13); 05d seção
              "Compartilhamento com EDITOR (V1-13)", entrega E1.1.
Objetivo....: Alargar chk_collection_membership_role de ('VIEWER') para
              ('VIEWER','EDITOR'). Nada mais muda na tabela: default
              continua 'VIEWER', RLS ligada sem políticas, nenhum
              privilégio de tabela para anon/authenticated.

Efeito no acesso: NENHUM por si só. Nenhuma função grava EDITOR antes da
  5369 (convite com papel) e da 5370 (troca de papel); a leitura
  compartilhada continua decidida por collection_share_role (5302), que
  devolve 'VIEWER' para qualquer participação ACTIVE, de qualquer papel.
  O papel EDITOR não concede escrita nesta etapa (E1-B).
Canal.......: psql (várias instruções entre begin/commit — protocolo da
              V1-16, §2 e §11). Não usar o SQL Editor.
Idempotência: CHECK já alargado → 'PRECHECK 5366: JÁ APLICADA' (nada muda).
Reversão....: R5366 em ROLLBACK_E1A.sql (só se não houver linha EDITOR).
Como validar: 5888, item 0.1.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
declare
  v_def text;
begin
  if to_regclass('public.collection_membership') is null then
    raise exception 'PRECHECK 5366: collection_membership ausente (5300 não aplicada)';
  end if;
  select pg_catalog.pg_get_constraintdef(k.oid) into v_def
  from pg_catalog.pg_constraint k
  where k.conrelid = 'public.collection_membership'::regclass
    and k.conname = 'chk_collection_membership_role';
  if v_def is null then
    raise exception 'PRECHECK 5366: ESTADO DIVERGENTE — chk_collection_membership_role ausente';
  end if;
  if v_def = 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5366: JÁ APLICADA — não reaplicar';
  end if;
  if v_def not in ('CHECK ((role = ''VIEWER''::text))',
                   'CHECK ((role = ANY (ARRAY[''VIEWER''::text])))') then
    raise exception 'PRECHECK 5366: ESTADO DIVERGENTE — CHECK vigente inesperado: %', v_def;
  end if;
  if exists (select 1 from public.collection_membership m where m.role is distinct from 'VIEWER') then
    raise exception 'PRECHECK 5366: ESTADO DIVERGENTE — há papel diferente de VIEWER';
  end if;
end;
$pre$;

alter table public.collection_membership
  drop constraint chk_collection_membership_role;

alter table public.collection_membership
  add constraint chk_collection_membership_role check (role in ('VIEWER', 'EDITOR'));

comment on table public.collection_membership is
  'Collection Membership (C-142/C-143/C-153, V1-12; papel EDITOR desde a V1-13, C-234/C-240): participação de usuário não titular. Titular = collection.owner_user_id (C-141), nunca uma linha aqui. Acesso só por funções SECURITY DEFINER (5303–5313, 5367–5370).';

do $post$
begin
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'POSTCHECK 5366: CHECK de papel não ficou no estado esperado';
  end if;
  if (select column_default from information_schema.columns
       where table_schema = 'public' and table_name = 'collection_membership' and column_name = 'role')
     is distinct from '''VIEWER''::text' then
    raise exception 'POSTCHECK 5366: default do papel mudou';
  end if;
  if (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = 'public.collection_membership'::regclass) is not true
     or exists (select 1 from pg_catalog.pg_policy p where p.polrelid = 'public.collection_membership'::regclass)
     or pg_catalog.has_table_privilege('authenticated', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE')
     or pg_catalog.has_table_privilege('anon', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'POSTCHECK 5366: RLS/privilégios da tabela mudaram';
  end if;
end;
$post$;

commit;
