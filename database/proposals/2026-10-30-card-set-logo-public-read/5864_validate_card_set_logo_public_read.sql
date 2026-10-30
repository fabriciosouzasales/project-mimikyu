/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5864 - Harness da leitura anon do logo atual de Card Set (5330)
Versão......: 1.0 (2026-10-30)
Status......: PROPOSTA — NÃO EXECUTADA. Executar só depois da 5330, com
              autorização de Fabrício.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Protocolo: um único statement, como dono do banco, SEM escrita (só troca
de papel para anon/authenticated e leitura de storage.objects com a RLS
real — a mesma checagem da API ao assinar e ao listar):

  select * from pg_temp.wh_5864_validate();

Gate: GATE PASS 7/7.
================================================================
*/

create or replace function pg_temp.wh_5864_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
declare
  f_cur oid := to_regprocedure('public.card_set_logo_is_current(text)');
  v_current bigint; v_orphans bigint; v_anon bigint; v_anon_orphans bigint; v_anon_other bigint;
  v_sample text; v_orphan text; b1 boolean; b2 boolean; b3 boolean; b4 boolean;
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 7;
begin
  res := res || jsonb_build_object('id','S.1','ok',
    f_cur is not null
    and (select q.prosecdef and q.proconfig @> array['search_path=""'] from pg_proc q where q.oid = f_cur)
    and has_function_privilege('anon', f_cur, 'EXECUTE')
    and not exists (select 1 from pg_proc q, aclexplode(coalesce(q.proacl, '{}')) a where q.oid = f_cur and a.grantee = 0),
    'detail','função definer, search_path vazio, EXECUTE anon, nada para PUBLIC');
  res := res || jsonb_build_object('id','S.2','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname = 'card_set_logo_public_current_select' and cmd = 'SELECT'
       and roles = array['anon']::name[] and qual like '%card_set_logo_is_current%' and qual like '%card-set-logo%') = 1
    and not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and 'anon' = any(roles) and cmd <> 'SELECT'
       and (coalesce(qual, '') || coalesce(with_check, '')) like '%card-set-logo%'),
    'detail','uma política SELECT só anon, só card-set-logo, delegando à função; nenhuma escrita anon');
  res := res || jsonb_build_object('id','S.3','ok',
    (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects'
       and policyname in ('card_set_logo_authenticated_select','card_set_logo_admin_select','card_set_logo_admin_insert',
                          'card_set_logo_admin_update','card_set_logo_admin_delete')) = 5,
    'detail','políticas existentes do bucket intactas (5174 + admin)');

  select count(*) into v_current from storage.objects o
   where o.bucket_id = 'card-set-logo' and exists (select 1 from public.card_set cs where cs.logo_storage_path = o.name);
  select count(*) into v_orphans from storage.objects o
   where o.bucket_id = 'card-set-logo' and not exists (select 1 from public.card_set cs where cs.logo_storage_path = o.name);
  select min(cs.logo_storage_path) into v_sample from public.card_set cs
   where exists (select 1 from storage.objects o where o.bucket_id = 'card-set-logo' and o.name = cs.logo_storage_path);
  select min(o.name) into v_orphan from storage.objects o
   where o.bucket_id = 'card-set-logo' and not exists (select 1 from public.card_set cs where cs.logo_storage_path = o.name);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role anon';
  select count(*) into v_anon from storage.objects o where o.bucket_id = 'card-set-logo';
  select count(*) into v_anon_orphans from storage.objects o
   where o.bucket_id = 'card-set-logo' and o.name = coalesce(v_orphan, '-');
  select count(*) into v_anon_other from storage.objects o
   where o.bucket_id = 'expansion-logo';
  b1 := public.card_set_logo_is_current(coalesce(v_sample, '-'));
  b2 := public.card_set_logo_is_current(coalesce(v_orphan, '-'));
  b3 := public.card_set_logo_is_current('00000000-0000-0000-0000-000000000000/inventado.png');
  b4 := exists (select 1 from storage.objects o where o.bucket_id = 'card-set-logo' and o.name = coalesce(v_sample, '-'));
  execute 'reset role';

  res := res || jsonb_build_object('id','A.1','ok', v_sample is not null and b1 and b4,
    'detail','anon lê o logo atual de um Set (função e RLS real)');
  res := res || jsonb_build_object('id','A.2','ok', v_anon = v_current,
    'detail','anon lista exatamente os logos atuais: ' || v_anon || ' de ' || v_current || ' (objetos no bucket: ' || (v_current + v_orphans) || ')');
  res := res || jsonb_build_object('id','A.3','ok', not b2 and not b3 and v_anon_orphans = 0,
    'detail','logo antigo/substituído (' || v_orphans || ' no bucket) e caminho inventado negados');
  res := res || jsonb_build_object('id','A.4','ok', v_anon_other = 0 and current_user = session_user,
    'detail','anon continua sem nada em expansion-logo (bucket vizinho, sem mudança); papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if (r ->> 'ok')::boolean then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when (r ->> 'ok')::boolean then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;

-- Executar (uma única vez, depois da 5330, com autorização):
-- select * from pg_temp.wh_5864_validate();
