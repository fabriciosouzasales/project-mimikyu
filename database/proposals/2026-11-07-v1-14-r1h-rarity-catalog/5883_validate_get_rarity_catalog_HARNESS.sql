/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5883 - HARNESS da 5355 (get_rarity_catalog) — termina em ROLLBACK
Status......: PROPOSTO — NÃO EXECUTADO (precisa de autorização própria)
Data........: 2026-11-07

Objetivo
  Criar a 5355 DENTRO de uma transação, provar esquema, segurança, integridade, ordem,
  compatibilidade com a 5159 e desempenho, e desfazer tudo (ROLLBACK). Nada persiste.

Asserções (qualquer falha aborta com Q5883_*; sem correção improvisada)
  E1 esquema efetivo de public.rarity/public.game = o da proposta (nomes, tipos, NOT NULL)
     e Game POKEMON existente
  E2 RLS de public.rarity ativa e policies inalteradas (impressão digital antes = depois)
  S1 prosecdef, search_path '', STABLE; retorno com exatamente 4 colunas declaradas
  S2 anon e PUBLIC sem EXECUTE; authenticated com EXECUTE; chamada real como anon → 42501
  S3 authenticated sem sessão (claims sem sub) → 28000
  S4 colecionador NÃO administrador: a função devolve o catálogo e o SELECT direto em
     public.rarity continua devolvendo 0 linhas (RLS intacta; a função é o único caminho)
  I1 integridade: saída = raridades do Game POKEMON (nos dois sentidos, todas as colunas)
  I2 uma linha por code; nenhum valor nulo ou em branco
  I3 ordem: display_order crescente, empate por code (determinística)
  I4 compatibilidade com a 5159: todo rarity.code alcançável pelos exemplares físicos
     (physical_card → card_variant → card → rarity) está na saída; cartas sem raridade
     apenas contadas (o relatório as mostra como "Sem raridade definida")
  P1 EXPLAIN ANALYZE como colecionador: execução < 50 ms
  Pós-ROLLBACK (bloco final, fora da transação): função inexistente, 0 transações ociosas,
  0 bloqueios em espera
================================================================
*/
begin;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

-- E1/E2 (antes da criação)
do $$
declare v_bad integer;
begin
  select count(*) into v_bad from (values
      ('rarity', 'code', 'character varying', 'NO'),
      ('rarity', 'name', 'character varying', 'NO'),
      ('rarity', 'symbol_code', 'character varying', 'NO'),
      ('rarity', 'display_order', 'integer', 'NO'),
      ('rarity', 'game_id', 'uuid', 'NO'),
      ('game', 'id', 'uuid', 'NO'),
      ('game', 'code', 'character varying', 'NO')) as e(tbl, col, typ, nul)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = e.tbl and c.column_name = e.col
      and c.data_type = e.typ and c.is_nullable = e.nul);
  if v_bad <> 0 then raise exception 'Q5883_E1_SCHEMA: % coluna(s) divergente(s)', v_bad; end if;
  if not exists (select 1 from public.game where code = 'POKEMON') then raise exception 'Q5883_E1_NO_POKEMON'; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.rarity'::regclass) then raise exception 'Q5883_E2_RLS_OFF'; end if;
  perform set_config('q5883.policies', (
    select coalesce(md5(string_agg(policyname || cmd || array_to_string(roles, ',') || coalesce(qual, '') || coalesce(with_check, ''), '|' order by policyname)), '-')
    from pg_policies where schemaname = 'public' and tablename = 'rarity'), true);
  raise notice 'Q5883 E1 PASS';
end $$;

-- ===== Corpo da 5355 (idêntico ao arquivo da proposta) =====
\ir 5355_create_get_rarity_catalog_PROPOSAL.sql
-- (No SQL Editor do Supabase, colar aqui o corpo da 5355 em vez do \ir.)

-- S1/S2 (catálogo)
do $$
declare v_ok boolean;
begin
  select p.prosecdef and p.proconfig @> array['search_path=""'] and p.provolatile = 's'
         and pg_get_function_result(p.oid) = 'TABLE(code text, name text, symbol_code text, display_order integer)'
    into v_ok
  from pg_proc p where p.oid = 'public.get_rarity_catalog()'::regprocedure;
  if not coalesce(v_ok, false) then raise exception 'Q5883_S1_PROPERTIES'; end if;
  if has_function_privilege('anon', 'public.get_rarity_catalog()', 'execute') then raise exception 'Q5883_S2_ANON_EXECUTE'; end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'public.get_rarity_catalog()'::regprocedure and a.grantee = 0) then
    raise exception 'Q5883_S2_PUBLIC_EXECUTE';
  end if;
  if not has_function_privilege('authenticated', 'public.get_rarity_catalog()', 'execute') then raise exception 'Q5883_S2_AUTH_EXECUTE'; end if;
  raise notice 'Q5883 S1 S2(catálogo) PASS';
end $$;

-- Colecionador não administrador (o titular de inventário que não é admin; aborta se não houver)
create temp table _q5883_user on commit drop as
select i.owner_user_id as user_id
from public.inventory i
where not exists (select 1 from public.admin_user au where au.id = i.owner_user_id)
order by i.owner_user_id
limit 1;

do $$ begin
  if not exists (select 1 from _q5883_user) then raise exception 'Q5883_PRE_NO_NON_ADMIN_USER'; end if;
end $$;

-- S2 (chamada real como anon)
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$ begin
  begin
    perform 1 from public.get_rarity_catalog();
    raise exception 'Q5883_S2_ANON_CALLED';
  exception when insufficient_privilege then raise notice 'Q5883 S2(anon) PASS';
  end;
end $$;
reset role;

-- S3 (authenticated sem sessão)
select set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin
  begin
    perform 1 from public.get_rarity_catalog();
    raise exception 'Q5883_S3_NO_ERROR';
  exception when sqlstate '28000' then raise notice 'Q5883 S3 PASS';
  end;
end $$;
reset role;

-- S4, I1–I3, P1 como colecionador
select set_config('request.jwt.claims', json_build_object('sub', (select user_id from _q5883_user), 'role', 'authenticated')::text, true);
set local role authenticated;
create temp table _q5883_out on commit drop as
select row_number() over () as rn, * from public.get_rarity_catalog();
do $$
declare v_direct integer; v_n integer;
begin
  if public.is_admin() then raise exception 'Q5883_S4_USER_IS_ADMIN'; end if;
  select count(*) into v_direct from public.rarity;
  if v_direct <> 0 then raise exception 'Q5883_S4_RLS_LEAK: % linha(s) lidas direto', v_direct; end if;
  select count(*) into v_n from _q5883_out;
  if v_n = 0 then raise exception 'Q5883_S4_EMPTY'; end if;
  raise notice 'Q5883 S4 PASS (% raridades; SELECT direto = 0)', v_n;
end $$;
explain (analyze, buffers) select * from public.get_rarity_catalog();
reset role;

do $$
declare v_n integer;
begin
  -- I1: igualdade nos dois sentidos com o catálogo canônico
  select count(*) into v_n from (
    (select code, name, symbol_code, display_order from _q5883_out
     except
     select r.code::text, r.name::text, r.symbol_code::text, r.display_order from public.rarity r join public.game g on g.id = r.game_id where g.code = 'POKEMON')
    union all
    (select r.code::text, r.name::text, r.symbol_code::text, r.display_order from public.rarity r join public.game g on g.id = r.game_id where g.code = 'POKEMON'
     except
     select code, name, symbol_code, display_order from _q5883_out)) d;
  if v_n <> 0 then raise exception 'Q5883_I1_INTEGRITY: % diferença(s)', v_n; end if;
  -- I2: unicidade e valores
  select count(*) - count(distinct code) into v_n from _q5883_out;
  if v_n <> 0 then raise exception 'Q5883_I2_DUP_CODE'; end if;
  select count(*) into v_n from _q5883_out where code is null or btrim(name) = '' or name is null or symbol_code is null or display_order is null;
  if v_n <> 0 then raise exception 'Q5883_I2_NULLS'; end if;
  -- I3: ordem
  select count(*) into v_n from (
    select rn, row_number() over (order by display_order, code) as expected from _q5883_out) o where o.rn <> o.expected;
  if v_n <> 0 then raise exception 'Q5883_I3_ORDER: % linha(s) fora de ordem', v_n; end if;
  -- I4: compatibilidade com o rarity_code da 5159 (todas as raridades dos exemplares físicos)
  select count(distinct r.code) into v_n
  from public.physical_card pc
  join public.card_variant cv on cv.id = pc.card_variant_id
  join public.card c on c.id = cv.card_id
  join public.rarity r on r.id = c.rarity_id
  where r.code::text not in (select code from _q5883_out);
  if v_n <> 0 then raise exception 'Q5883_I4_UNKNOWN_CODES: %', v_n; end if;
  select count(*) into v_n
  from public.physical_card pc join public.card_variant cv on cv.id = pc.card_variant_id join public.card c on c.id = cv.card_id
  where c.rarity_id is null;
  raise notice 'Q5883 I1 I2 I3 I4 PASS (exemplares de cartas sem raridade: %)', v_n;
  -- E2: policies inalteradas
  if current_setting('q5883.policies') <> (
    select coalesce(md5(string_agg(policyname || cmd || array_to_string(roles, ',') || coalesce(qual, '') || coalesce(with_check, ''), '|' order by policyname)), '-')
    from pg_policies where schemaname = 'public' and tablename = 'rarity') then
    raise exception 'Q5883_E2_POLICIES_CHANGED';
  end if;
  raise notice 'Q5883 E2 PASS';
end $$;

rollback;

-- Pós-ROLLBACK (somente leitura)
select (select count(*) from pg_proc where proname = 'get_rarity_catalog') as fn_exists,
       (select count(*) from pg_stat_activity where state like 'idle in transaction%' and datname = current_database()) as idle_tx,
       (select count(*) from pg_locks where not granted) as waiting_locks;
