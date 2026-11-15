/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5376 - Metadados e capa da coleção pelo EDITOR (V1-13 · E1-B2)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B2 | EDITOR CURATION OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-239 (o EDITOR edita nome, descrição, objetivo textual e capa;
              Set, escopo do Master Set, política de completude, modalidade,
              visibilidade, arquivamento e exclusão ficam com o titular; arquivo
              de capa enviado fica no armazenamento do titular, sem acesso geral
              à pasta dele), C-234, C-238 (identidade e imagens do FICHÁRIO são do
              titular — esta migration não as toca).
Depende de..: E1-A (5366). Não depende do fichário.

OBJETIVO TEXTUAL — não implementado: o modelo vigente NÃO tem campo de objetivo
textual em `collection` (o "objetivo" existente é estrutural: referência do Set,
escopo do Master Set, política de completude — todos do titular). Criar campo
novo exige decisão de produto; nada foi inventado.

Funções:
  assert_collection_editor(p_collection_id) → owner_user_id      (INTERNA)
      EDITOR ACTIVE da coleção, de outro titular. Travas: coleção X (FOR
      UPDATE, como 5178/5180) → participação (FOR SHARE) — a mesma ordem de
      5369/5370 e da 5371 (coleção antes da participação). Recusas: as da 5371
      (COLLECTION_NOT_FOUND indistinguível; COLLECTION_ARCHIVED só depois de
      autorizado).
  editor_update_collection_metadata(p_collection_id, p_name, p_description)
      → (name, description)          espelho da 5035: nome sem brancos nas
      pontas e não vazio; descrição como recebida.
  editor_set_collection_cover_finish(p_collection_id, p_finish) → text
      espelho da 5172 (acabamento da CAPA DA COLEÇÃO: onix, vinho, floresta,
      marinho, caramelo, perola). Não toca a identidade do fichário (5245).
  editor_set_collection_cover_code(p_collection_id, p_code) → text
      espelho da 5180: só coleção livre ou Pokédex (NOT_FREE_COLLECTION).
  editor_set_collection_cover_logo(p_collection_id, p_path)
      → (cover_logo_path, removable_previous_path)
      espelho da 5178, com DUAS diferenças deliberadas:
        - o arquivo precisa estar na pasta DO TITULAR (`<titular>/<coleção>/`)
          — onde a política de envio do EDITOR (5377) permite gravar; arquivo
          na pasta do próprio EDITOR é recusado (INVALID_COVER_PATH);
        - o arquivo precisa ter sido enviado pelo EDITOR chamador ou pelo
          titular; removable_previous_path só volta preenchido quando o arquivo
          anterior foi enviado pelo próprio EDITOR (único que ele pode apagar,
          5377). Arquivo do titular nunca é oferecido para exclusão.
      NULL = remover a imagem da placa (como no titular).
Não permitido (não existe parâmetro nem caminho): referência do Set, escopo do
  Master Set, política de completude, modalidade, visibilidade, arquivar,
  excluir, membros, titularidade, identidade/acabamento/âncora/imagens do
  fichário.
Titular: 5035, 5172, 5178 e 5180 ficam BYTE A BYTE iguais (md5 no precheck e no
  postcheck; 5178/5180 com md5 já registrado como igual ao LIVE).
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5376 em ROLLBACK_E1B2.sql.
Como validar: harness 5890, seções 4–6.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5376: E1-A (5366) não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) is distinct from 'a581235db9cabaf7043707a290f963b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) is distinct from '4f48d9161b4a29ecb23e7443e31d1806'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) is distinct from 'd0d8cbfa517b9da3728a55af47de21cb'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) is distinct from '5868fb1c8de760787d1128ac20a09507' then
    raise exception 'PRECHECK 5376: ESTADO DIVERGENTE — funções do titular (5035/5172/5178/5180) diferem das canônicas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('assert_collection_editor', 'editor_update_collection_metadata', 'editor_set_collection_cover_finish',
                                 'editor_set_collection_cover_code', 'editor_set_collection_cover_logo')) then
    raise exception 'PRECHECK 5376: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno ------------------------------------------------------------------------------
create function public.assert_collection_editor(p_collection_id uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid    uuid := (select auth.uid());
  v_owner  uuid;
  v_status text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.owner_user_id into v_owner
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id
    and c.owner_user_id <> v_uid;
  if v_owner is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Coleção (FOR UPDATE) antes da participação (FOR SHARE).
  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform 1
  from public.collection_membership m
  where m.collection_id = p_collection_id and m.user_id = v_uid
    and m.status = 'ACTIVE' and m.role = 'EDITOR'
  for share;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  return v_owner;
end;
$fn$;

-- Nome e descrição ------------------------------------------------------------------------------
create function public.editor_update_collection_metadata(
  p_collection_id uuid,
  p_name          text,
  p_description   text
)
returns table (name text, description text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_owner uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_name is null or btrim(p_name) = '' then
    raise exception 'p_name não pode ser vazio' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  return query
  update public.collection c
  set name = btrim(p_name), description = p_description
  where c.id = p_collection_id and c.owner_user_id = v_owner
  returning c.name::text, c.description::text;
end;
$fn$;

-- Acabamento da capa da coleção ------------------------------------------------------------------
create function public.editor_set_collection_cover_finish(
  p_collection_id uuid,
  p_finish        text
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_owner  uuid;
  v_finish text := lower(btrim(coalesce(p_finish, '')));
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_finish not in ('onix', 'vinho', 'floresta', 'marinho', 'caramelo', 'perola') then
    raise exception 'INVALID_FINISH' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  update public.collection c
  set cover_finish = v_finish
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  return v_finish;
end;
$fn$;

-- Código da placa (coleção livre ou Pokédex) --------------------------------------------------------
create function public.editor_set_collection_cover_code(
  p_collection_id uuid,
  p_code          text
)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_owner uuid;
  v_code  text := nullif(upper(btrim(coalesce(p_code, ''))), '');
  v_free  boolean;
begin
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if v_code is not null and v_code !~ '^[A-Z0-9]{2,6}$' then
    raise exception 'INVALID_COVER_CODE' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  select ((c.completion_policy = 'NONE'
           and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
          or (c.completion_policy = 'REFERENCE_POSITION'
              and exists (select 1 from public.collection_reference cr
                          where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')))
    into v_free
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  if v_free is not true then
    raise exception 'NOT_FREE_COLLECTION' using errcode = '55000';
  end if;

  update public.collection c
  set cover_code = v_code
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  return v_code;
end;
$fn$;

-- Imagem da placa (arquivo na pasta do titular) ------------------------------------------------------
create function public.editor_set_collection_cover_logo(
  p_collection_id uuid,
  p_path          text
)
returns table (cover_logo_path text, removable_previous_path text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid       uuid := (select auth.uid());
  v_owner     uuid;
  v_path      text := nullif(btrim(coalesce(p_path, '')), '');
  v_prev      text;
  v_prev_mine boolean;
  v_free      boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_COVER_PATH' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);

  select c.cover_logo_path,
         ((c.completion_policy = 'NONE'
           and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
          or (c.completion_policy = 'REFERENCE_POSITION'
              and exists (select 1 from public.collection_reference cr
                          where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')))
    into v_prev, v_free
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_owner;
  if v_free is not true then
    raise exception 'NOT_FREE_COLLECTION' using errcode = '55000';
  end if;

  if v_path is not null then
    -- Pasta do TITULAR desta coleção, nome no formato do 5178.
    if left(v_path, 74) <> v_owner::text || '/' || p_collection_id::text || '/'
       or v_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$' then
      raise exception 'INVALID_COVER_PATH' using errcode = '22023';
    end if;
    -- Arquivo existe e foi enviado pelo EDITOR chamador ou pelo titular.
    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'collection-cover'
        and o.name = v_path
        and (o.owner_id in (v_uid::text, v_owner::text) or o.owner in (v_uid, v_owner))
    ) then
      raise exception 'COVER_FILE_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  -- O arquivo anterior só é oferecido para exclusão se foi enviado pelo próprio EDITOR.
  select exists (select 1 from storage.objects o
                 where o.bucket_id = 'collection-cover' and o.name = v_prev
                   and (o.owner_id = v_uid::text or o.owner = v_uid))
    into v_prev_mine;

  update public.collection c
  set cover_logo_path = v_path
  where c.id = p_collection_id and c.owner_user_id = v_owner;

  return query
  select v_path,
         case when v_prev is distinct from v_path and v_prev_mine then v_prev end;
end;
$fn$;

comment on function public.assert_collection_editor(uuid) is
  'V1-13 E1-B2 (5376, interna): autoriza o usuário da sessão como EDITOR ACTIVE da coleção; trava coleção → participação. Devolve o titular.';
comment on function public.editor_update_collection_metadata(uuid, text, text) is
  'V1-13 E1-B2 (5376): EDITOR altera nome e descrição da coleção (C-239). Nada estrutural.';
comment on function public.editor_set_collection_cover_finish(uuid, text) is
  'V1-13 E1-B2 (5376): EDITOR altera o acabamento da capa da coleção (não do fichário).';
comment on function public.editor_set_collection_cover_code(uuid, text) is
  'V1-13 E1-B2 (5376): EDITOR altera o código da placa de coleção livre ou Pokédex.';
comment on function public.editor_set_collection_cover_logo(uuid, text) is
  'V1-13 E1-B2 (5376): EDITOR define ou remove a imagem da placa com arquivo da pasta do titular enviado por ele ou pelo titular; só arquivo dele é devolvido para exclusão.';

revoke all on function public.assert_collection_editor(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_update_collection_metadata(uuid, text, text) from public, anon;
revoke all on function public.editor_set_collection_cover_finish(uuid, text) from public, anon;
revoke all on function public.editor_set_collection_cover_code(uuid, text) from public, anon;
revoke all on function public.editor_set_collection_cover_logo(uuid, text) from public, anon;
grant execute on function public.editor_update_collection_metadata(uuid, text, text) to authenticated;
grant execute on function public.editor_set_collection_cover_finish(uuid, text) to authenticated;
grant execute on function public.editor_set_collection_cover_code(uuid, text) to authenticated;
grant execute on function public.editor_set_collection_cover_logo(uuid, text) to authenticated;

do $post$
declare
  f oid;
begin
  f := to_regprocedure('public.assert_collection_editor(uuid)');
  if f is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5376: ajudante interno fora do estado esperado';
  end if;
  foreach f in array array[
      to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)'),
      to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)'),
      to_regprocedure('public.editor_set_collection_cover_code(uuid, text)'),
      to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5376: escrita do EDITOR fora do estado esperado (%)', f;
    end if;
    if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f)
       is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
                         where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) then
      raise exception 'POSTCHECK 5376: ACL difere da 5172 (%)', f;
    end if;
  end loop;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) is distinct from 'a581235db9cabaf7043707a290f963b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) is distinct from '4f48d9161b4a29ecb23e7443e31d1806'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) is distinct from 'd0d8cbfa517b9da3728a55af47de21cb'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) is distinct from '5868fb1c8de760787d1128ac20a09507' then
    raise exception 'POSTCHECK 5376: funções do titular mudaram';
  end if;
end;
$post$;

commit;
