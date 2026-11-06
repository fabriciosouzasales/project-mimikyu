/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5880C - v1.1 | Segurança e permissões da 3989 (somente leitura)
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-11-06 (R1-B PRICING 3989 VALIDATION RECOVERY-03)
Autor.......: Fabrício Sales / Claude

Rastreabilidade com o 5880 v1.0: 0.2/0.3 (contrato e definição), 7.1 (ACL), 7.2 (anon 42501 /
sem identidade 28000), 7.3 (entradas inválidas 22023 + mensagens), 7.4 (independência de
identidade) e isolamento do acervo (physical_card sob RLS).

Execução: uma chamada. Transação READ ONLY; nenhuma escrita, nenhum objeto temporário.
Os resultados dos casos com erro esperado são guardados por set_config (local) dentro de DO
e lidos no SELECT final. Termina em ROLLBACK.
PASS = todas as colunas *_ok verdadeiras.
================================================================
*/
begin isolation level repeatable read read only;
set local statement_timeout = '30s';

do $c$
declare
  v_ids uuid[];
  v_state text; v_msg text;
begin
  -- 12 variantes reais do acervo (lidas como postgres; o papel authenticated não as enxerga)
  select array_agg(id) into v_ids from (select distinct card_variant_id as id from public.physical_card order by 1 limit 12) s;
  perform set_config('mmkyu.c_ids', v_ids::text, true);

  -- 7.2a anon → 42501
  begin
    execute 'set local role anon';
    perform * from public.get_card_variants_pricing_summary(v_ids);
    v_state := 'NO_ERROR';
  exception when others then v_state := sqlstate; end;
  execute 'reset role';
  perform set_config('mmkyu.c_anon', v_state, true);

  -- 7.2b authenticated sem identidade → 28000
  perform set_config('request.jwt.claims', '', true);
  begin
    execute 'set local role authenticated';
    perform * from public.get_card_variants_pricing_summary(v_ids);
    v_state := 'NO_ERROR'; v_msg := null;
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  execute 'reset role';
  perform set_config('mmkyu.c_noid', v_state || ' ' || coalesce(v_msg, ''), true);

  -- 7.3 entradas inválidas (identidade válida)
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000058c1","role":"authenticated"}', true);
  execute 'set local role authenticated';
  begin perform * from public.get_card_variants_pricing_summary(null); v_state := 'NO_ERROR'; v_msg := null;
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  perform set_config('mmkyu.c_null', v_state || ' ' || coalesce(v_msg, ''), true);
  begin perform * from public.get_card_variants_pricing_summary('{}'::uuid[]); v_state := 'NO_ERROR'; v_msg := null;
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  perform set_config('mmkyu.c_empty', v_state || ' ' || coalesce(v_msg, ''), true);
  begin perform * from public.get_card_variants_pricing_summary(array[[v_ids[1], v_ids[2]], [v_ids[3], v_ids[4]]]); v_state := 'NO_ERROR'; v_msg := null;
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  perform set_config('mmkyu.c_shape', v_state || ' ' || coalesce(v_msg, ''), true);
  begin perform * from public.get_card_variants_pricing_summary(array(select gen_random_uuid() from generate_series(1, 101))); v_state := 'NO_ERROR'; v_msg := null;
  exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
  perform set_config('mmkyu.c_101', v_state || ' ' || coalesce(v_msg, ''), true);
  -- 100 ids aleatórios (limite exato) → aceito, 0 linhas (ids inexistentes)
  begin perform set_config('mmkyu.c_100', (select count(*)::text from public.get_card_variants_pricing_summary(array(select gen_random_uuid() from generate_series(1, 100)))), true);
  exception when others then perform set_config('mmkyu.c_100', 'ERR ' || sqlstate, true); end;

  -- Isolamento: o mesmo papel/identidade não enxerga exemplares de outras contas
  perform set_config('mmkyu.c_iso', (select count(*)::text from public.physical_card), true);

  -- 7.4 independência de identidade: duas identidades → mesmo resultado
  perform set_config('mmkyu.c_res1', (select md5(string_agg(r::text, '|' order by r.card_variant_id)) from public.get_card_variants_pricing_summary(v_ids) r), true);
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000058c2","role":"authenticated"}', true);
  perform set_config('mmkyu.c_res2', (select md5(string_agg(r::text, '|' order by r.card_variant_id)) from public.get_card_variants_pricing_summary(v_ids) r), true);
  perform set_config('mmkyu.c_rows', (select count(*)::text from public.get_card_variants_pricing_summary(v_ids)), true);
  execute 'reset role';
end
$c$;

with f as (
  select p.oid, md5(p.prosrc) as body, p.prosecdef, p.provolatile, p.proconfig, p.proacl::text as acl,
         pg_catalog.pg_get_function_result(p.oid) as result
    from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_card_variants_pricing_summary(uuid[])')
)
select
  (f.body = 'e253fcc5613bbef1181c6564b56f5b8a') as definicao_3989_ok,
  (f.result = 'TABLE(card_variant_id uuid, card_id uuid, has_pricing boolean, brl_amount numeric, source_amount numeric, source_currency text, fx_status text, printing_label text, price_basis text, price_origin text, observed_at timestamp with time zone)') as contrato_11_colunas_ok,
  (f.prosecdef and f.provolatile = 's' and f.proconfig = array['search_path=""']) as secdef_stable_searchpath_ok,
  (f.acl = '{postgres=X/postgres,authenticated=X/postgres}') as acl_ok,
  (not has_function_privilege('anon', f.oid, 'EXECUTE') and has_function_privilege('authenticated', f.oid, 'EXECUTE')
   and not exists (select 1 from aclexplode((select proacl from pg_proc where oid = f.oid)) a where a.grantee = 0)) as grants_ok,
  current_setting('mmkyu.c_anon', true) as anon_sqlstate,
  (current_setting('mmkyu.c_anon', true) = '42501') as anon_ok,
  current_setting('mmkyu.c_noid', true) as sem_identidade,
  (current_setting('mmkyu.c_noid', true) like '28000 VARIANT_PRICING_SUMMARY_REQUIRES_AUTHENTICATION%') as sem_identidade_ok,
  (current_setting('mmkyu.c_null', true) = '22023 VARIANT_PRICING_SUMMARY_EMPTY_INPUT'
   and current_setting('mmkyu.c_empty', true) = '22023 VARIANT_PRICING_SUMMARY_EMPTY_INPUT'
   and current_setting('mmkyu.c_shape', true) = '22023 VARIANT_PRICING_SUMMARY_INVALID_PAYLOAD_SHAPE'
   and current_setting('mmkyu.c_101', true) = '22023 VARIANT_PRICING_SUMMARY_TOO_MANY_IDS') as entradas_invalidas_ok,
  current_setting('mmkyu.c_100', true) as linhas_100_ids_inexistentes,
  (current_setting('mmkyu.c_100', true) = '0') as limite_100_ok,
  current_setting('mmkyu.c_iso', true) as physical_card_visiveis_outra_identidade,
  (current_setting('mmkyu.c_iso', true) = '0') as isolamento_ok,
  current_setting('mmkyu.c_rows', true) as linhas_12_ids,
  (current_setting('mmkyu.c_res1', true) = current_setting('mmkyu.c_res2', true)
   and current_setting('mmkyu.c_rows', true) = '12') as independencia_identidade_ok
from f;
rollback;
