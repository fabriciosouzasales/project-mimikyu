/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5881 - HARNESS da 5354 (get_my_inventory_group_locations) — termina em ROLLBACK
Status......: PROPOSTO — NÃO EXECUTADO (precisa de autorização própria)
Data........: 2026-11-07

Objetivo
  Criar a 5354 DENTRO de uma transação, provar segurança, isolamento, contrato, conciliação e
  desempenho, e desfazer tudo (ROLLBACK). Nada persiste: nem a função nem dado algum.

Asserções (qualquer falha aborta; sem correção improvisada)
  S1 sem sessão (claims vazias) → 28000
  S2 anon não tem EXECUTE; PUBLIC revogado; authenticated tem EXECUTE; prosecdef + search_path ''
  S3 entrada: null, '{}', 2 dimensões, 501 ids → 22023
  I1 titular A: Σ copies por grupo = exemplares do grupo (conciliação com physical_card/5159)
  I2 titular A: Σ locations[].copies = copies em todas as linhas; uma linha por (variante, idioma)
  I3 titular B pedindo as variantes de A: zero linhas de A — nenhum nome de recipiente, id de
     slot/página ou contagem de A vaza (B só vê os próprios exemplares dessas variantes, se tiver)
  I4 ids inexistentes: zero linhas
  I5 "Sem local definido" (storage_container_id null) sempre por último na lista
  P1 EXPLAIN ANALYZE com as 448 variantes repetidas do titular A: execução < 500 ms
================================================================
*/
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ===== Corpo da 5354 (idêntico ao arquivo da proposta) =====
\ir 5354_create_get_my_inventory_group_locations_PROPOSAL.sql
-- (No SQL Editor do Supabase, colar aqui o corpo da 5354 em vez do \ir.)

create temp table _q5881_users on commit drop as
select i.owner_user_id as user_id, i.id as inventory_id,
       row_number() over (order by (select count(*) from public.physical_card pc where pc.inventory_id = i.id) desc) as rk
from public.inventory i;

do $$
declare v_n integer; v_ok boolean;
begin
  select count(*) into v_n from _q5881_users;
  if v_n < 2 then raise exception 'Q5881_PRE: são necessários 2 titulares com inventário (há %)', v_n; end if;

  -- S2: privilégios e propriedades
  select p.prosecdef and p.proconfig @> array['search_path=""'] into v_ok
  from pg_proc p where p.oid = 'public.get_my_inventory_group_locations(uuid[])'::regprocedure;
  if not coalesce(v_ok, false) then raise exception 'Q5881_S2_DEFINER_SEARCH_PATH'; end if;
  if has_function_privilege('anon', 'public.get_my_inventory_group_locations(uuid[])', 'execute') then raise exception 'Q5881_S2_ANON_EXECUTE'; end if;
  if not has_function_privilege('authenticated', 'public.get_my_inventory_group_locations(uuid[])', 'execute') then raise exception 'Q5881_S2_AUTH_EXECUTE'; end if;
  raise notice 'Q5881 S2 PASS';
end $$;

-- S1: sem sessão
select set_config('request.jwt.claims', '', true);
do $$ begin
  begin
    perform 1 from public.get_my_inventory_group_locations(array[gen_random_uuid()]);
    raise exception 'Q5881_S1_NO_ERROR';
  exception when sqlstate '28000' then raise notice 'Q5881 S1 PASS';
  end;
end $$;

-- Titular A (maior acervo)
select set_config('request.jwt.claims', json_build_object('sub', (select user_id from _q5881_users where rk = 1), 'role', 'authenticated')::text, true);

do $$
declare v_ids uuid[]; v_n integer;
begin
  -- S3: entradas inválidas
  begin perform 1 from public.get_my_inventory_group_locations(null); raise exception 'Q5881_S3_NULL'; exception when sqlstate '22023' then null; end;
  begin perform 1 from public.get_my_inventory_group_locations('{}'::uuid[]); raise exception 'Q5881_S3_EMPTY'; exception when sqlstate '22023' then null; end;
  begin perform 1 from public.get_my_inventory_group_locations(array[[gen_random_uuid()],[gen_random_uuid()]]); raise exception 'Q5881_S3_DIMS'; exception when sqlstate '22023' then null; end;
  begin perform 1 from public.get_my_inventory_group_locations(array(select gen_random_uuid() from generate_series(1, 501))); raise exception 'Q5881_S3_501'; exception when sqlstate '22023' then null; end;
  raise notice 'Q5881 S3 PASS';

  -- Variantes repetidas do titular A (o uso real do relatório)
  select array_agg(distinct pc.card_variant_id) into v_ids
  from public.physical_card pc
  where pc.inventory_id = (select inventory_id from _q5881_users where rk = 1)
    and (pc.card_variant_id, pc.language_id) in (
      select card_variant_id, language_id from public.physical_card
      where inventory_id = (select inventory_id from _q5881_users where rk = 1)
      group by 1, 2 having count(*) >= 2);
  if cardinality(v_ids) > 500 then v_ids := v_ids[1:500]; end if;

  -- I1: conciliação por grupo com os exemplares físicos
  select count(*) into v_n
  from public.get_my_inventory_group_locations(v_ids) r
  full join (
    select pc.card_variant_id, l.code as language_code, count(*)::integer as copies
    from public.physical_card pc join public.language l on l.id = pc.language_id
    where pc.inventory_id = (select inventory_id from _q5881_users where rk = 1) and pc.card_variant_id = any (v_ids)
    group by 1, 2) e on e.card_variant_id = r.card_variant_id and e.language_code = r.language_code
  where r.copies is distinct from e.copies;
  if v_n <> 0 then raise exception 'Q5881_I1_RECONCILIATION: % grupo(s) divergente(s)', v_n; end if;

  -- I2: Σ locations = copies; I5: null por último
  select count(*) into v_n from public.get_my_inventory_group_locations(v_ids) r
  where r.copies <> (select sum((x ->> 'copies')::integer) from jsonb_array_elements(r.locations) x)
     or exists (select 1 from jsonb_array_elements(r.locations) with ordinality x(e, n)
                where (e ->> 'storage_container_id') is null and n < jsonb_array_length(r.locations));
  if v_n <> 0 then raise exception 'Q5881_I2_I5: % linha(s)', v_n; end if;

  -- I4: ids inexistentes
  select count(*) into v_n from public.get_my_inventory_group_locations(array[gen_random_uuid(), gen_random_uuid()]);
  if v_n <> 0 then raise exception 'Q5881_I4: %', v_n; end if;

  perform set_config('q5881.ids', array_to_string(v_ids, ','), true);
  raise notice 'Q5881 I1 I2 I4 I5 PASS (% variantes)', cardinality(v_ids);
end $$;

-- I3: titular B pede as variantes de A
select set_config('request.jwt.claims', json_build_object('sub', (select user_id from _q5881_users where rk = 2), 'role', 'authenticated')::text, true);
do $$
declare v_ids uuid[] := string_to_array(current_setting('q5881.ids'), ',')::uuid[]; v_leak integer;
begin
  select count(*) into v_leak
  from public.get_my_inventory_group_locations(v_ids) r, jsonb_array_elements(r.locations) x
  where (x ->> 'storage_container_id')::uuid in (
          select sc.id from public.storage_container sc where sc.inventory_id = (select inventory_id from _q5881_users where rk = 1))
     or r.copies > (select count(*) from public.physical_card pc
                    where pc.inventory_id = (select inventory_id from _q5881_users where rk = 2) and pc.card_variant_id = r.card_variant_id);
  if v_leak <> 0 then raise exception 'Q5881_I3_LEAK: %', v_leak; end if;
  raise notice 'Q5881 I3 PASS';
end $$;

-- P1: desempenho com o titular A
select set_config('request.jwt.claims', json_build_object('sub', (select user_id from _q5881_users where rk = 1), 'role', 'authenticated')::text, true);
explain (analyze, buffers)
select * from public.get_my_inventory_group_locations(string_to_array(current_setting('q5881.ids'), ',')::uuid[]);

rollback;
