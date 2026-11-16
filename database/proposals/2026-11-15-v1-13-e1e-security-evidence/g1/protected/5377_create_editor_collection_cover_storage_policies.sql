/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1b2-editor-curation/5377_create_editor_collection_cover_storage_policies.sql
   sha256 da base: ae49e2e8f117396501dc414bd34a6dc3e0c3b77fe6e91a850999e35881f74248
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 2 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5377 - Storage da capa da coleção para o EDITOR: enviar, ver e apagar só os
              próprios arquivos na pasta da coleção autorizada (V1-13 · E1-B2)
Versão......: 1.1
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B2 | EDITOR CURATION OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
              v1.1 (2026-11-15, `STORAGE HARDENING AND SCOPE REVIEW-02`): o teto de
              envio passa a ser serializado por EDITOR e coleção (trava
              transacional consultiva) num ajudante VOLÁTIL próprio do envio; a
              v1.0 contava sob o snapshot do comando e N envios simultâneos podiam
              passar todos.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-239 ("se a capa usar um arquivo enviado, ele é gravado no
              armazenamento do titular, com autorização própria do EDITOR para essa
              coleção; o EDITOR nunca recebe acesso geral à pasta do titular"),
              C-243.
Depende de..: E1-A (5366), 5176 (bucket collection-cover e políticas do dono),
              5329 (leitura compartilhada da capa ATUAL).

Regras de hoje (5176): bucket privado, 1 MB, png/jpeg/webp; quatro políticas por
dono — primeira pasta = auth.uid(). Nada aqui as altera. A leitura da capa atual
por participantes continua na 5329 (sem mudança).

Menor ampliação (três políticas novas, todas TO authenticated, nenhuma para anon):
  collection_cover_insert_editor  INSERT  — o EDITOR ACTIVE grava em
      `<titular>/<coleção>/<uuid>.(png|jpg|webp)` (o mesmo formato que a 5178/5376
      aceitam), só em coleção ACTIVE livre ou Pokédex (as únicas com imagem de
      placa) e com TETO de 3 arquivos dele ainda não usados como capa naquela
      pasta. O teto impede que o EDITOR encha o armazenamento do titular.
  collection_cover_select_editor  SELECT  — o EDITOR vê só os arquivos que ELE
      enviou na pasta da coleção autorizada (necessário para a pré-visualização e
      para a exclusão pela API do Storage).
  collection_cover_delete_editor  DELETE  — o EDITOR apaga só os arquivos que ELE
      enviou naquela pasta e que NÃO são a capa atual.
Nunca: ler, trocar ou apagar arquivo do titular; gravar fora da pasta da coleção
  autorizada; atualizar objeto (nenhuma política de UPDATE para o EDITOR);
  acesso para VIEWER, ex-membro, convite pendente, estranho ou anon.

As políticas consultam participação e coleção por duas funções SECURITY
DEFINER (o papel `authenticated` não tem privilégio nas tabelas — 5300):
  collection_cover_editor_folder_ok(p_name text) → boolean        STABLE
      ver/apagar: EDITOR ACTIVE da coleção da pasta, coleção ativa livre/Pokédex,
      nunca a capa atual.
  collection_cover_editor_can_upload(p_name text) → boolean       VOLATILE
      envio: trava `pg_advisory_xact_lock` pela chave (EDITOR, coleção), depois
      reavalia folder_ok e conta os arquivos dele ainda não usados com snapshot
      novo; verdadeiro só se forem menos de 3.
Elas só respondem sobre o PRÓPRIO usuário da sessão; não listam nem revelam nada.
EXECUTE para authenticated (a política roda com o papel de quem chama), nunca
para anon.

Concorrência do teto (v1.1):
  - a trava vale até o fim da transação que grava o objeto; um segundo envio do
    mesmo EDITOR na mesma coleção espera o primeiro terminar e, em READ
    COMMITTED (padrão do Postgres e da conexão do Storage), conta com o
    arquivo já gravado. A chave inclui o usuário: ninguém trava o envio de outro;
  - a trava só é tomada pelo envio do EDITOR (as políticas do dono, 5176, não
    a usam e não têm teto);
  - SEM PROVA: depende de a API do Storage gravar a linha de storage.objects sob
    esta política, na mesma transação, em READ COMMITTED. Se a API testar a
    permissão numa transação e gravar a linha em outra, ou usar REPEATABLE
    READ/SERIALIZABLE, o teto volta a ser só aproximado. Comprovação: teste real
    de envios paralelos pela API (homologação), não o harness 5890.

Limites declarados:
  - o arquivo antigo do TITULAR substituído pelo EDITOR fica no armazenamento do
    titular (o EDITOR não pode apagá-lo); limpeza é do titular (5176);
  - envios do EDITOR abandonados (enviados e nunca usados) contam no teto até
    ele os apagar; não há limpeza automática;
  - o comportamento real das políticas na API do Storage (upload, remove) só se
    comprova na execução e na homologação.
Canal.......: psql. Idempotência: políticas já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5377 em ROLLBACK_E1B2.sql.
Como validar: harness 5890, seção 6.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if not exists (select 1 from storage.buckets b where b.id = 'collection-cover' and b.public is false) then
    raise exception 'PRECHECK 5377: ESTADO DIVERGENTE — bucket collection-cover ausente ou público';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own',
                              'collection_cover_update_own', 'collection_cover_delete_own')) <> 4 then
    raise exception 'PRECHECK 5377: ESTADO DIVERGENTE — políticas do dono (5176) ausentes';
  end if;
  if exists (select 1 from pg_catalog.pg_policies p
             where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname like 'collection_cover_%_editor')
     or to_regprocedure('public.collection_cover_editor_folder_ok(text)') is not null
     or to_regprocedure('public.collection_cover_editor_folder_ok(text, boolean)') is not null
     or to_regprocedure('public.collection_cover_editor_can_upload(text)') is not null then
    raise exception 'PRECHECK 5377: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5377: E1-A (5366) não aplicada';
  end if;
end;
$pre$;

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

do $post$
declare
  f oid := to_regprocedure('public.collection_cover_editor_folder_ok(text)');
  g oid := to_regprocedure('public.collection_cover_editor_can_upload(text)');
begin
  if f is null or g is null
     or (select count(*) from pg_catalog.pg_proc p
          where p.oid in (f, g) and p.prosecdef and p.proconfig = array['search_path=""']) <> 2
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = f) <> 's'
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = g) <> 'v'
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('authenticated', g, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', g, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5377: ajudantes fora do estado esperado';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')
         and p.roles = array['authenticated']::name[]) <> 3 then
    raise exception 'POSTCHECK 5377: políticas do EDITOR fora do estado esperado';
  end if;
  if exists (select 1 from pg_catalog.pg_policies p
             where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname like 'collection_cover_%_editor' and p.cmd = 'UPDATE') then
    raise exception 'POSTCHECK 5377: política de UPDATE para o EDITOR não deveria existir';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own',
                              'collection_cover_update_own', 'collection_cover_delete_own')) <> 4 then
    raise exception 'POSTCHECK 5377: políticas do dono mudaram';
  end if;
end;
$post$;

commit;
