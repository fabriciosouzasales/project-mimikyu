/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5390 - Remove do EDITOR as capacidades de imagem da capa
              (V1-13 · E3-6 / S1, D-E3-6)
Versão......: 1.0 (2026-11-27, `E3-6 / S1-5390 — COVER IMAGE PERMISSIONS | SQL PREPARATION-01`)
Status......: PROPOSTA — NÃO EXECUTADA. Execução só com PRE somente leitura
              aprovado (S1_DEPLOY_readonly_checks.sql), auditoria independente e
              autorização expressa e específica. Barreira continua CLOSED.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-27
Decisão.....: D-E3-6 (imagem da capa só do titular); P0-C (remoção controlada);
              alternativa A do README deste pacote.
Remove......: I2–I4 — políticas collection_cover_insert_editor,
              collection_cover_select_editor, collection_cover_delete_editor em
              storage.objects (5377) e os ajudantes
              collection_cover_editor_can_upload(text) e
              collection_cover_editor_folder_ok(text) (5377), nesta ordem.
Revoga......: I1 — EXECUTE de editor_set_collection_cover_logo(uuid, text)
              (5376) para PUBLIC, anon, authenticated e service_role. A função
              FICA no catálogo: EMERGENCY_STOP_V1_13.sql (linha 45) a revoga sem
              guarda; removê-la quebraria o bloco E2 do script de emergência.
Não toca....: titular (5176, 5177, 5178, 5328, 5329; update_collection_metadata,
              set_my_collection_cover_finish/_code/_logo), E3-3 (assert_collection_editor,
              editor_update_collection_metadata, editor_set_collection_cover_finish,
              editor_set_collection_cover_code), 5380, a barreira 5389, nenhum
              arquivo do Storage, nenhuma linha de tabela.
Travas......: lock_timeout 3 s; `lock table storage.objects in access exclusive
              mode nowait` antes de qualquer DROP POLICY (o DROP POLICY pede a
              mesma trava). Conflito → 55P03, transação abortada, nada persiste;
              sem repetição automática (nova janela, decisão do operador).
Canal.......: o da implantação aceita da S3 (Management API `database/query`,
              papel postgres) ou o da E1 — decidido na autorização. Uma chamada.
Reversão....: ROLLBACK_S1.sql (R5390) — REINTRODUZ as capacidades indevidas;
              só para emergência, nunca automática.
Como validar: S1_DEPLOY_readonly_checks.sql (PRE antes, POST depois) e
              static_check_s1.py; provas funcionais com identidades reais na E4.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
declare
  v_i1     oid := to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)');
  v_fold   oid := to_regprocedure('public.collection_cover_editor_folder_ok(text)');
  v_upl    oid := to_regprocedure('public.collection_cover_editor_can_upload(text)');
  v_owner  oid;
  v_bad    text;
begin
  -- Barreira CLOSED, registro vazio.
  if to_regclass('public.v1_13_barrier_state') is null
     or (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5390: barreira não está CLOSED ou há identidades TEST';
  end if;
  -- Objetos a remover/revogar: presentes e com o corpo implantado da E1 (5376/5377 protegidas).
  if v_i1 is null or v_fold is null or v_upl is null then
    raise exception 'PRECHECK 5390: ESTADO DIVERGENTE — I1 ou ajudantes ausentes';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_i1) is distinct from '8d211f8fa20bb064fc7085038281ab24'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fold) is distinct from '5e9fdc4b2dec92663594ddd2cc427711'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_upl) is distinct from 'abce88d6802c00982735bc286a3edfc3' then
    raise exception 'PRECHECK 5390: ESTADO DIVERGENTE — corpo de I1/ajudantes difere do implantado na E1';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')
         and p.roles = array['authenticated']::name[]) <> 3 then
    raise exception 'PRECHECK 5390: ESTADO DIVERGENTE — políticas do EDITOR (5377) ausentes ou alteradas';
  end if;
  -- Ajudantes: os únicos dependentes são as 3 políticas do EDITOR (e a chamada interna can_upload → folder_ok).
  if exists (select 1 from pg_catalog.pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.refobjid in (v_fold, v_upl)
               and not (d.classid = 'pg_catalog.pg_policy'::regclass
                        and d.objid in (select pol.oid from pg_catalog.pg_policy pol
                                        where pol.polrelid = 'storage.objects'::regclass
                                          and pol.polname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')))) then
    raise exception 'PRECHECK 5390: dependência inesperada dos ajudantes';
  end if;
  select string_agg(n.nspname || '.' || p.proname, ', ') into v_bad
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where p.oid not in (v_fold, v_upl)
    and p.prokind = 'f'
    and (p.prosrc like '%collection_cover_editor_folder_ok%' or p.prosrc like '%collection_cover_editor_can_upload%');
  if v_bad is not null then
    raise exception 'PRECHECK 5390: função fora do conjunto referencia os ajudantes (%)', v_bad;
  end if;
  if exists (select 1 from pg_catalog.pg_policies p
             where p.policyname not in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor')
               and (coalesce(p.qual, '') || coalesce(p.with_check, '')) ~ 'collection_cover_editor_(folder_ok|can_upload)') then
    raise exception 'PRECHECK 5390: outra política referencia os ajudantes';
  end if;
  -- Privilégios atuais da I1: só o dono, authenticated e (padrão da plataforma) service_role. Qualquer outro → STOP.
  select p.proowner into v_owner from pg_catalog.pg_proc p where p.oid = v_i1;
  select string_agg(coalesce(r.rolname, 'PUBLIC'), ', ') into v_bad
  from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
  left join pg_catalog.pg_roles r on r.oid = a.grantee
  where p.oid = v_i1 and a.privilege_type = 'EXECUTE'
    and a.grantee <> v_owner
    and coalesce(r.rolname, 'PUBLIC') not in ('authenticated', 'service_role');
  if v_bad is not null then
    raise exception 'PRECHECK 5390: privilégio inesperado na I1 (%)', v_bad;
  end if;
  -- Preservados: titular (5176/5178/5035/5172/5180) e E3-3 (5376), com o corpo canônico.
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) is distinct from '5868fb1c8de760787d1128ac20a09507'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_finish(uuid, text)')) is distinct from '4f48d9161b4a29ecb23e7443e31d1806'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_code(uuid, text)')) is distinct from 'd0d8cbfa517b9da3728a55af47de21cb'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.update_collection_metadata(uuid, text, text)')) is distinct from 'a581235db9cabaf7043707a290f963b7'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)')) is distinct from '81da7a37d4b9d126a565074b706aaea8'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)')) is distinct from '8fc815a4ff48f5a7896e84ad367e86c3'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_code(uuid, text)')) is distinct from '4feb35ab58042b11aa1df00c329f379b'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.assert_collection_editor(uuid)')) is distinct from '9a7482588b5c7995f40a5d945c957f31' then
    raise exception 'PRECHECK 5390: ESTADO DIVERGENTE — funções do titular ou da E3-3 diferem do canônico';
  end if;
  if (select count(*) from pg_catalog.pg_policies p
       where p.schemaname = 'storage' and p.tablename = 'objects'
         and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own', 'collection_cover_update_own',
                              'collection_cover_delete_own', 'collection_cover_select_shared')) <> 5 then
    raise exception 'PRECHECK 5390: ESTADO DIVERGENTE — políticas do dono (5176) ou da leitura compartilhada (5329) ausentes';
  end if;
  -- Retrato das políticas que ficam (comparado no postcheck, mesma transação).
  perform set_config('mmkyu.s1_5390_keep',
    (select md5(string_agg(p.policyname || '|' || p.cmd || '|' || array_to_string(p.roles, ',') || '|' ||
                           coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''), E'\n' order by p.policyname))
     from pg_catalog.pg_policies p
     where p.schemaname = 'storage' and p.tablename = 'objects'
       and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own', 'collection_cover_update_own',
                            'collection_cover_delete_own', 'collection_cover_select_shared')), true);
  perform set_config('mmkyu.s1_5390_e33_acl',
    (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '<NULL>'), ';' order by p.proname)
     from pg_catalog.pg_proc p
     where p.oid in (to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)'),
                     to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)'),
                     to_regprocedure('public.editor_set_collection_cover_code(uuid, text)'),
                     to_regprocedure('public.set_my_collection_cover_logo(uuid, text)'))), true);
end;
$pre$;

-- I2–I4: políticas do EDITOR (trava sem espera; conflito → 55P03, nada persiste).
lock table storage.objects in access exclusive mode nowait;
drop policy collection_cover_insert_editor on storage.objects;
drop policy collection_cover_select_editor on storage.objects;
drop policy collection_cover_delete_editor on storage.objects;

do $dep$
begin
  if exists (select 1 from pg_catalog.pg_depend d
             where d.refclassid = 'pg_catalog.pg_proc'::regclass
               and d.refobjid in (to_regprocedure('public.collection_cover_editor_folder_ok(text)'),
                                  to_regprocedure('public.collection_cover_editor_can_upload(text)'))) then
    raise exception '5390: ajudantes ainda têm dependentes depois do DROP POLICY';
  end if;
end;
$dep$;

drop function public.collection_cover_editor_can_upload(text);
drop function public.collection_cover_editor_folder_ok(text);

-- I1: sem EXECUTE para clientes; a função fica (EMERGENCY_STOP_V1_13.sql a revoga sem guarda).
revoke all on function public.editor_set_collection_cover_logo(uuid, text) from public, anon, authenticated, service_role;
comment on function public.editor_set_collection_cover_logo(uuid, text) is
  'V1-13 E1-B2 (5376) — DESATIVADA pela 5390 (D-E3-6/S1, 2026-11-27): sem EXECUTE para PUBLIC, anon, authenticated e service_role. Imagem da capa é só do titular (5178). Mantida no catálogo por compatibilidade com EMERGENCY_STOP_V1_13.sql.';

do $post$
declare
  v_i1    oid := to_regprocedure('public.editor_set_collection_cover_logo(uuid, text)');
  v_owner oid;
  v_bad   text;
begin
  -- I2–I4 removidas.
  if exists (select 1 from pg_catalog.pg_policies p
             where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname in ('collection_cover_insert_editor', 'collection_cover_select_editor', 'collection_cover_delete_editor'))
     or to_regprocedure('public.collection_cover_editor_folder_ok(text)') is not null
     or to_regprocedure('public.collection_cover_editor_can_upload(text)') is not null then
    raise exception 'POSTCHECK 5390: política ou ajudante do EDITOR ainda presente';
  end if;
  if exists (select 1 from pg_catalog.pg_policies p
             where p.schemaname = 'storage' and p.tablename = 'objects'
               and p.policyname like 'collection_cover_%' and p.policyname like '%editor%') then
    raise exception 'POSTCHECK 5390: resta política de capa do EDITOR';
  end if;
  -- I1: presente (emergência), corpo intacto, sem EXECUTE para nenhum papel além do dono.
  if v_i1 is null or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_i1) is distinct from '8d211f8fa20bb064fc7085038281ab24' then
    raise exception 'POSTCHECK 5390: I1 ausente ou alterada';
  end if;
  select p.proowner into v_owner from pg_catalog.pg_proc p where p.oid = v_i1;
  select string_agg(coalesce(r.rolname, 'PUBLIC'), ', ') into v_bad
  from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
  left join pg_catalog.pg_roles r on r.oid = a.grantee
  where p.oid = v_i1 and a.privilege_type = 'EXECUTE' and a.grantee <> v_owner;
  if v_bad is not null then
    raise exception 'POSTCHECK 5390: EXECUTE remanescente na I1 (%)', v_bad;
  end if;
  -- Papéis de cliente (e o que entra pela API) sem EXECUTE efetivo, inclusive por herança.
  select string_agg(r.rolname, ', ') into v_bad
  from pg_catalog.pg_roles r
  where r.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
    and pg_catalog.has_function_privilege(r.oid, v_i1, 'EXECUTE');
  if v_bad is not null then
    raise exception 'POSTCHECK 5390: papel de cliente ainda executa a I1 (%)', v_bad;
  end if;
  -- Preservados.
  if (select md5(string_agg(p.policyname || '|' || p.cmd || '|' || array_to_string(p.roles, ',') || '|' ||
                            coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''), E'\n' order by p.policyname))
      from pg_catalog.pg_policies p
      where p.schemaname = 'storage' and p.tablename = 'objects'
        and p.policyname in ('collection_cover_select_own', 'collection_cover_insert_own', 'collection_cover_update_own',
                             'collection_cover_delete_own', 'collection_cover_select_shared'))
     is distinct from current_setting('mmkyu.s1_5390_keep', true) then
    raise exception 'POSTCHECK 5390: políticas do dono ou da leitura compartilhada mudaram';
  end if;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '<NULL>'), ';' order by p.proname)
      from pg_catalog.pg_proc p
      where p.oid in (to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)'),
                      to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)'),
                      to_regprocedure('public.editor_set_collection_cover_code(uuid, text)'),
                      to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')))
     is distinct from current_setting('mmkyu.s1_5390_e33_acl', true)
     or pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)'), 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('authenticated', to_regprocedure('public.set_my_collection_cover_logo(uuid, text)'), 'EXECUTE') is not true then
    raise exception 'POSTCHECK 5390: privilégios do titular ou da E3-3 mudaram';
  end if;
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_my_collection_cover_logo(uuid, text)')) is distinct from '5868fb1c8de760787d1128ac20a09507'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_update_collection_metadata(uuid, text, text)')) is distinct from '81da7a37d4b9d126a565074b706aaea8'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_finish(uuid, text)')) is distinct from '8fc815a4ff48f5a7896e84ad367e86c3'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.editor_set_collection_cover_code(uuid, text)')) is distinct from '4feb35ab58042b11aa1df00c329f379b'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.assert_collection_editor(uuid)')) is distinct from '9a7482588b5c7995f40a5d945c957f31' then
    raise exception 'POSTCHECK 5390: funções do titular ou da E3-3 alteradas';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED' then
    raise exception 'POSTCHECK 5390: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
