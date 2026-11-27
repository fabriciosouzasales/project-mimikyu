/*
================================================================
Projeto.....: Project Mimikyu
Query.......: ROLLBACK_S1 — reversão da 5390 (V1-13 · E3-6 / S1)
Versão......: 1.0 (2026-11-27)
Status......: PROPOSTA — NÃO EXECUTADA. ATENÇÃO: REINTRODUZ as capacidades de
              imagem da capa do EDITOR (I1–I4) que a D-E3-6 proíbe. Uso exclusivo de
              recuperação, pelo proprietário, com autorização expressa — nunca
              automático depois de uma falha (a 5390 é uma transação: se falhou,
              nada mudou e NÃO há o que reverter).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-27
Efeito......: recria os dois ajudantes e as três políticas com o texto EXATO da
              5377 protegida implantada na E1 (copiado do arquivo
              e1e-security-evidence/g1/protected/5377_…, do `create function` até
              antes do postcheck) e devolve EXECUTE da I1 a `authenticated` (e a
              `service_role` só se o PRE da 5390 o registrou no ACL original —
              conferir a evidência antes). Não toca arquivo algum do Storage nem
              qualquer outra função. As capacidades continuam atrás da barreira
              5389 (CLOSED ⇒ inertes).
Pré-cond....: 5390 aplicada (ajudantes e políticas ausentes; I1 presente).
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  if to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)') is null
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')) is distinct from '8d211f8fa20bb064fc7085038281ab24' then
    raise exception 'PRECHECK R5390: I1 ausente ou alterada';
  end if;
  if to_regprocedure('public.collection_cover_editor_folder_ok(text)') is not null
     or to_regprocedure('public.collection_cover_editor_can_upload(text)') is not null
     or exists (select 1 from pg_catalog.pg_policies p
                where p.schemaname = 'storage' and p.tablename = 'objects' and p.policyname like 'collection_cover_%_editor') then
    raise exception 'PRECHECK R5390: 5390 não aplicada (ajudantes ou políticas já presentes)';
  end if;
end;
$pre$;

lock table storage.objects in access exclusive mode nowait;

-- Texto exato da 5377 protegida (E1) -------------------------------------------------------------
create function public.collection_cover_editor_folder_ok(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_parts text[];
  v_owner uuid;
  v_coll  uuid;
  v_cur   text;
begin
  if not public.v1_13_capability_open() then return false; end if;  -- G1 (D-E1)
  if v_uid is null or p_name is null
     or p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$' then
    return false;
  end if;
  v_parts := storage.foldername(p_name);
  begin
    v_owner := v_parts[1]::uuid;
    v_coll  := v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  if v_owner = v_uid then
    return false;   -- pasta do próprio usuário: regida pelas políticas do dono (5176)
  end if;

  select c.cover_logo_path into v_cur
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = v_coll
    and c.owner_user_id = v_owner
    and c.lifecycle_status = 'ACTIVE'
    and ((c.completion_policy = 'NONE'
          and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
         or (c.completion_policy = 'REFERENCE_POSITION'
             and exists (select 1 from public.collection_reference cr
                         where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')));
  if not found then
    return false;
  end if;
  -- Nunca a capa atual por este caminho (a leitura da capa atual por participantes
  -- é da 5329; a exclusão dela só pelo titular, 5176).
  return p_name is distinct from v_cur;
end;
$fn$;

comment on function public.collection_cover_editor_folder_ok(text) is
  'V1-13 E1-B2 (5377 v1.1): usada pelas políticas collection_cover_select_editor e collection_cover_delete_editor (e pelo envio). Verdadeiro só se o usuário da sessão é EDITOR ACTIVE da coleção da pasta <titular>/<coleção>/, coleção ativa com imagem de placa, e o arquivo não é a capa atual.';

revoke all on function public.collection_cover_editor_folder_ok(text) from public, anon, service_role;
grant execute on function public.collection_cover_editor_folder_ok(text) to authenticated;

create function public.collection_cover_editor_can_upload(p_name text)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_parts text[];
  v_owner uuid;
  v_coll  uuid;
  v_cur   text;
  v_n     integer;
begin
  if not public.v1_13_capability_open() then return false; end if;  -- G1 (D-E1)
  if v_uid is null or p_name is null
     or p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$' then
    return false;
  end if;
  v_parts := storage.foldername(p_name);
  begin
    v_owner := v_parts[1]::uuid;
    v_coll  := v_parts[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  if v_owner = v_uid then
    return false;
  end if;

  -- Serializa os envios do MESMO EDITOR na MESMA coleção até o fim da transação.
  -- Cada comando seguinte desta função VOLÁTIL usa snapshot novo (READ COMMITTED):
  -- depois da espera, o envio concorrente já confirmado entra na contagem.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('mmkyu:collection-cover-editor:' || v_uid::text || ':' || v_coll::text, 5377));

  if public.collection_cover_editor_folder_ok(p_name) is not true then
    return false;
  end if;

  select c.cover_logo_path into v_cur from public.collection c where c.id = v_coll;
  select count(*) into v_n
  from storage.objects o
  where o.bucket_id = 'collection-cover'
    and o.name like v_owner::text || '/' || v_coll::text || '/%'
    and (o.owner_id = v_uid::text or o.owner = v_uid)
    and o.name is distinct from v_cur;
  return v_n < 3;
end;
$fn$;

comment on function public.collection_cover_editor_can_upload(text) is
  'V1-13 E1-B2 (5377 v1.1): usada só pela política collection_cover_insert_editor. Trava (EDITOR, coleção) até o fim da transação, reavalia collection_cover_editor_folder_ok e permite o envio só com menos de 3 arquivos dele ainda não usados na pasta. Proteção contra corrida depende de READ COMMITTED e de a API do Storage gravar sob esta política; sem prova real.';

revoke all on function public.collection_cover_editor_can_upload(text) from public, anon, service_role;
grant execute on function public.collection_cover_editor_can_upload(text) to authenticated;

create policy collection_cover_insert_editor
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'collection-cover'
    and public.collection_cover_editor_can_upload(name)
  );

create policy collection_cover_select_editor
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'collection-cover'
    and owner_id = (select auth.uid())::text
    and public.collection_cover_editor_folder_ok(name)
  );

create policy collection_cover_delete_editor
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'collection-cover'
    and owner_id = (select auth.uid())::text
    and public.collection_cover_editor_folder_ok(name)
  );

-- I1 de volta -----------------------------------------------------------------------------------
grant execute on function public.editor_set_collection_cover_logo(uuid, text) to authenticated;
-- grant execute on function public.editor_set_collection_cover_logo(uuid, text) to service_role;  -- só se constava no ACL do PRE
comment on function public.editor_set_collection_cover_logo(uuid, text) is
  'V1-13 E1-B2 (5376): EDITOR define ou remove a imagem da placa com arquivo da pasta do titular enviado por ele ou pelo titular; só arquivo dele é devolvido para exclusão.';

do $post$
begin
  if to_regprocedure('public.collection_cover_editor_folder_ok(text)') is null
     or to_regprocedure('public.collection_cover_editor_can_upload(text)') is null
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_cover_editor_folder_ok(text)')) is distinct from '5e9fdc4b2dec92663594ddd2cc427711'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_cover_editor_can_upload(text)')) is distinct from 'abce88d6802c00982735bc286a3edfc3'
     or (select count(*) from pg_catalog.pg_policies p
          where p.schemaname = 'storage' and p.tablename = 'objects'
            and p.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')) <> 3
     or pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)'), 'EXECUTE') is not true then
    raise exception 'POSTCHECK R5390: estado da 5377/5376 não restaurado';
  end if;
end;
$post$;

commit;
