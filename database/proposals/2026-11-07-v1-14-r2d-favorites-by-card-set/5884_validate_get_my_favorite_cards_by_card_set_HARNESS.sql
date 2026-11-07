/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5884 - HARNESS da 5356 (get_my_favorite_cards_by_card_set) — termina em ROLLBACK
Status......: PROPOSTO — NÃO EXECUTADO (precisa de autorização própria)
Data........: 2026-11-07

Objetivo
  Criar a 5356 DENTRO de uma transação, provar esquema, segurança, isolamento,
  equivalência com a 5336, pertencimento canônico, ordem, paginação e desempenho,
  e desfazer tudo (ROLLBACK). Usuários: só titulares EXISTENTES (nenhum inventado).
  O cenário de isolamento usa favoritos sintéticos de um titular existente,
  inseridos e revertidos na própria transação.

Asserções (qualquer falha aborta com Q5884_*; sem correção improvisada)
  E1 esquema efetivo: card_favorite(user_id, card_id, created_at), card.card_set_id,
     card.collector_order, card.is_active; UNIQUE (card_set_id, collector_order);
     5336 presente; impressões digitais de policies (card_favorite + catálogo),
     corpos da 5336 e permissões das demais funções guardadas
  S1 SECURITY DEFINER, search_path '', STABLE, retorno com as 11 colunas
  S2 anon e PUBLIC sem EXECUTE; authenticated com EXECUTE; chamada real como anon → 42501
  S3 sem sessão → 28000; entrada inválida (Card Set nulo, limite 0/101, offset −1) → 22023
  I1 equivalência com a 5336: favoritas do titular A no Set S pela 5356 (todas as páginas)
     = favoritas da 5336 (todas as páginas) cuja carta tem card.card_set_id = S —
     mesmas cartas, nome, número, total, imagens e data
  I2 pertencimento canônico: toda linha tem card_set_id = S; Set sem favoritas e
     Card Set inexistente → 0 linhas; favorita de outro Set (sintética) nunca aparece em S
  I3 uma linha por carta
  I4 ordem determinística (collector_order, nome, id) e paginação: páginas de 2 somadas =
     lista completa, sem repetição nem falta; total_count igual em todas as páginas
  I5 isolamento: titular B (existente) com favoritos SINTÉTICOS no Set S vê só os dele;
     A não vê os de B; nenhuma carta de A aparece para B
  P1 EXPLAIN ANALYZE como titular A no Set S: execução < 50 ms
  E2 policies, corpos da 5336 e permissões das demais funções idênticos ao início
  Pós-ROLLBACK (bloco final, fora da transação): função inexistente, nenhum favorito
  sintético, 0 transações ociosas, 0 bloqueios em espera
================================================================
*/
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- Contexto real: titular A = quem tem mais favoritas ativas num mesmo Set S; B = outro titular existente.
create temp table _q5884_ctx on commit drop as
with top as (
  select f.user_id as user_a, c.card_set_id as set_s, count(*) as n
  from public.card_favorite f
  join public.card c on c.id = f.card_id and c.is_active
  group by 1, 2
  order by n desc, 1, 2
  limit 1
)
select t.user_a, t.set_s, t.n,
       (select u.id from auth.users u where u.id <> t.user_a order by u.created_at, u.id limit 1) as user_b,
       (select c2.card_set_id from public.card c2 where c2.card_set_id <> t.set_s and c2.is_active order by c2.card_set_id limit 1) as set_other
from top t;

-- E1 (antes da criação)
do $$
declare v_bad integer;
begin
  if not exists (select 1 from _q5884_ctx where user_a is not null and user_b is not null and set_other is not null) then
    raise exception 'Q5884_PRE_CONTEXT: é preciso um titular com favoritas, um segundo titular existente e outro Card Set';
  end if;
  select count(*) into v_bad from (values
      ('card_favorite', 'user_id', 'uuid', 'NO'),
      ('card_favorite', 'card_id', 'uuid', 'NO'),
      ('card_favorite', 'created_at', 'timestamp with time zone', 'NO'),
      ('card', 'card_set_id', 'uuid', 'NO'),
      ('card', 'is_active', 'boolean', 'NO')) as e(tbl, col, typ, nul)
  where not exists (
    select 1 from information_schema.columns c
    where c.table_schema = 'public' and c.table_name = e.tbl and c.column_name = e.col and c.data_type = e.typ and c.is_nullable = e.nul);
  if v_bad <> 0 then raise exception 'Q5884_E1_SCHEMA: % coluna(s) divergente(s)', v_bad; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'card' and column_name = 'collector_order') then
    raise exception 'Q5884_E1_COLLECTOR_ORDER';
  end if;
  if not exists (
    select 1 from pg_constraint k where k.conrelid = 'public.card'::regclass and k.contype = 'u'
      and pg_get_constraintdef(k.oid) ilike 'UNIQUE (card_set_id, collector_order)') then
    raise exception 'Q5884_E1_UNIQUE_ORDER';
  end if;
  if to_regprocedure('public.get_my_favorite_cards(integer, integer)') is null then raise exception 'Q5884_E1_5336_MISSING'; end if;
  if to_regprocedure('public.get_my_favorite_cards_by_card_set(uuid, integer, integer)') is not null then raise exception 'Q5884_E1_ALREADY_EXISTS'; end if;
  perform set_config('q5884.policies', (
    select coalesce(md5(string_agg(tablename || policyname || cmd || array_to_string(roles, ',') || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)), '-')
    from pg_policies where schemaname = 'public' and tablename in ('card_favorite', 'card', 'card_set', 'card_asset')), true);
  perform set_config('q5884.f5336', (
    select md5(string_agg(p.proname || md5(p.prosrc) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname))
    from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('set_card_favorite', 'get_my_card_favorite_ids', 'get_my_card_favorites_by_variant', 'get_my_favorite_cards')), true);
  perform set_config('q5884.acl', (
    select md5(string_agg(oid::regprocedure::text || coalesce(array_to_string(proacl, ','), ''), '|' order by oid))
    from pg_proc where pronamespace = 'public'::regnamespace), true);
  raise notice 'Q5884 E1 PASS';
end $$;

-- ===== Corpo da 5356 (idêntico ao arquivo da proposta) =====
\ir 5356_create_get_my_favorite_cards_by_card_set_PROPOSAL.sql
-- (No SQL Editor do Supabase, colar aqui o corpo da 5356 em vez do \ir.)

-- S1/S2 (catálogo)
do $$
declare v_ok boolean;
begin
  select p.prosecdef and p.proconfig @> array['search_path=""'] and p.provolatile = 's'
         and pg_get_function_result(p.oid) = 'TABLE(card_id uuid, card_name text, collector_number text, collector_total integer, card_set_id uuid, card_set_code text, card_set_name text, image_path_pt text, image_path_en text, favorited_at timestamp with time zone, total_count bigint)'
    into v_ok
  from pg_proc p where p.oid = 'public.get_my_favorite_cards_by_card_set(uuid, integer, integer)'::regprocedure;
  if not coalesce(v_ok, false) then raise exception 'Q5884_S1_PROPERTIES'; end if;
  if has_function_privilege('anon', 'public.get_my_favorite_cards_by_card_set(uuid, integer, integer)', 'execute') then raise exception 'Q5884_S2_ANON_EXECUTE'; end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'public.get_my_favorite_cards_by_card_set(uuid, integer, integer)'::regprocedure and a.grantee = 0) then
    raise exception 'Q5884_S2_PUBLIC_EXECUTE';
  end if;
  if not has_function_privilege('authenticated', 'public.get_my_favorite_cards_by_card_set(uuid, integer, integer)', 'execute') then raise exception 'Q5884_S2_AUTH_EXECUTE'; end if;
  raise notice 'Q5884 S1 S2(catálogo) PASS';
end $$;

-- Favoritos SINTÉTICOS do titular B (existente), revertidos no ROLLBACK: uma carta de A no Set S e uma carta de outro Set.
insert into public.card_favorite (user_id, card_id)
select x.user_b, x.card_id from (
  (select ctx.user_b, f.card_id from _q5884_ctx ctx
     join public.card_favorite f on f.user_id = ctx.user_a
     join public.card c on c.id = f.card_id and c.card_set_id = ctx.set_s and c.is_active
   order by c.collector_order limit 1)
  union all
  (select ctx.user_b, c.id from _q5884_ctx ctx join public.card c on c.card_set_id = ctx.set_other and c.is_active order by c.collector_order limit 1)
) x
on conflict do nothing;

-- S2 (chamada real como anon)
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $$ begin
  begin
    perform 1 from public.get_my_favorite_cards_by_card_set(gen_random_uuid(), 10, 0);
    raise exception 'Q5884_S2_ANON_CALLED';
  exception when insufficient_privilege then raise notice 'Q5884 S2(anon) PASS';
  end;
end $$;
reset role;

-- S3 (sem sessão; entradas inválidas)
select set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
set local role authenticated;
do $$ begin
  begin
    perform 1 from public.get_my_favorite_cards_by_card_set(gen_random_uuid(), 10, 0);
    raise exception 'Q5884_S3_NO_ERROR';
  exception when sqlstate '28000' then raise notice 'Q5884 S3(sem sessão) PASS';
  end;
end $$;
reset role;

-- Como titular A
select set_config('request.jwt.claims', json_build_object('sub', (select user_a from _q5884_ctx), 'role', 'authenticated')::text, true);
select set_config('q5884.set_s', (select set_s::text from _q5884_ctx), true);
select set_config('q5884.set_other', (select set_other::text from _q5884_ctx), true);
select set_config('q5884.n', (select n::text from _q5884_ctx), true);
set local role authenticated;
do $$
declare v_set uuid := current_setting('q5884.set_s')::uuid;
begin
  begin perform 1 from public.get_my_favorite_cards_by_card_set(null, 10, 0); raise exception 'Q5884_S3_NULL_SET'; exception when sqlstate '22023' then null; end;
  begin perform 1 from public.get_my_favorite_cards_by_card_set(v_set, 0, 0); raise exception 'Q5884_S3_LIMIT0'; exception when sqlstate '22023' then null; end;
  begin perform 1 from public.get_my_favorite_cards_by_card_set(v_set, 101, 0); raise exception 'Q5884_S3_LIMIT101'; exception when sqlstate '22023' then null; end;
  begin perform 1 from public.get_my_favorite_cards_by_card_set(v_set, 10, -1); raise exception 'Q5884_S3_OFFSET'; exception when sqlstate '22023' then null; end;
  raise notice 'Q5884 S3(entradas) PASS';
end $$;
create temp table _q5884_a_5356 on commit drop as
  select row_number() over () as rn, r.*
  from generate_series(0, 4900, 100) o
  cross join lateral public.get_my_favorite_cards_by_card_set(current_setting('q5884.set_s')::uuid, 100, o) r;
create temp table _q5884_a_5336 on commit drop as
  select r.* from generate_series(0, 4900, 100) o cross join lateral public.get_my_favorite_cards(100, o) r;
create temp table _q5884_a_pages on commit drop as
  select o as page_offset, r.*
  from generate_series(0, current_setting('q5884.n')::integer + 1, 2) o
  cross join lateral public.get_my_favorite_cards_by_card_set(current_setting('q5884.set_s')::uuid, 2, o) r;
create temp table _q5884_a_other on commit drop as
  select (select count(*) from public.get_my_favorite_cards_by_card_set(gen_random_uuid(), 100, 0))::integer as n_unknown_set;
explain (analyze, buffers) select * from public.get_my_favorite_cards_by_card_set(current_setting('q5884.set_s')::uuid, 100, 0);
reset role;

-- Como titular B (favoritos sintéticos)
select set_config('request.jwt.claims', json_build_object('sub', (select user_b from _q5884_ctx), 'role', 'authenticated')::text, true);
set local role authenticated;
create temp table _q5884_b_5356 on commit drop as
  select r.* from generate_series(0, 4900, 100) o
  cross join lateral public.get_my_favorite_cards_by_card_set(current_setting('q5884.set_s')::uuid, 100, o) r;
reset role;

do $$
declare v_n integer; v_s uuid; v_a uuid; v_b uuid; v_other uuid;
begin
  select set_s, user_a, user_b, set_other into v_s, v_a, v_b, v_other from _q5884_ctx;
  -- I1: equivalência com a 5336 filtrada pelo vínculo canônico (dos dois lados, todas as colunas comuns)
  select count(*) into v_n from (
    (select card_id, card_name, collector_number, collector_total, card_set_code, card_set_name, image_path_pt, image_path_en, favorited_at from _q5884_a_5356
     except
     select x.card_id, x.card_name, x.collector_number, x.collector_total, x.card_set_code, x.card_set_name, x.image_path_pt, x.image_path_en, x.favorited_at
     from _q5884_a_5336 x join public.card c on c.id = x.card_id where c.card_set_id = v_s)
    union all
    (select x.card_id, x.card_name, x.collector_number, x.collector_total, x.card_set_code, x.card_set_name, x.image_path_pt, x.image_path_en, x.favorited_at
     from _q5884_a_5336 x join public.card c on c.id = x.card_id where c.card_set_id = v_s
     except
     select card_id, card_name, collector_number, collector_total, card_set_code, card_set_name, image_path_pt, image_path_en, favorited_at from _q5884_a_5356)) d;
  if v_n <> 0 then raise exception 'Q5884_I1_EQUIVALENCE: % diferença(s)', v_n; end if;
  if (select count(*) from _q5884_a_5356) = 0 then raise exception 'Q5884_I1_EMPTY'; end if;
  -- I2: pertencimento canônico
  select count(*) into v_n from _q5884_a_5356 where card_set_id <> v_s;
  if v_n <> 0 then raise exception 'Q5884_I2_FOREIGN_SET: %', v_n; end if;
  select count(*) into v_n from _q5884_a_5356 r join public.card c on c.id = r.card_id where c.card_set_id <> v_s or not c.is_active;
  if v_n <> 0 then raise exception 'Q5884_I2_CANONICAL: %', v_n; end if;
  if (select n_unknown_set from _q5884_a_other) <> 0 then raise exception 'Q5884_I2_UNKNOWN_SET'; end if;
  -- I3: uma linha por carta
  select count(*) - count(distinct card_id) into v_n from _q5884_a_5356;
  if v_n <> 0 then raise exception 'Q5884_I3_DUPLICATE: %', v_n; end if;
  -- I4: ordem, paginação e total
  select count(*) into v_n from (
    select r.rn, row_number() over (order by c.collector_order, c.name, r.card_id) as expected
    from _q5884_a_5356 r join public.card c on c.id = r.card_id) o where o.rn <> o.expected;
  if v_n <> 0 then raise exception 'Q5884_I4_ORDER: %', v_n; end if;
  if (select count(*) from _q5884_a_pages) <> (select count(*) from _q5884_a_5356)
     or (select count(distinct card_id) from _q5884_a_pages) <> (select count(*) from _q5884_a_5356)
     or exists (select card_id from _q5884_a_pages except select card_id from _q5884_a_5356) then
    raise exception 'Q5884_I4_PAGINATION';
  end if;
  if (select count(distinct total_count) from _q5884_a_pages) <> 1 or (select max(total_count) from _q5884_a_pages) <> (select count(*) from _q5884_a_5356) then
    raise exception 'Q5884_I4_TOTAL';
  end if;
  -- I5: isolamento — B vê só os próprios favoritos (sintéticos) no Set S; nada de A além do que B também favoritou
  select count(*) into v_n from _q5884_b_5356 r
  where not exists (select 1 from public.card_favorite f where f.user_id = v_b and f.card_id = r.card_id);
  if v_n <> 0 then raise exception 'Q5884_I5_LEAK_TO_B: %', v_n; end if;
  if (select count(*) from _q5884_b_5356) <> (select count(*) from public.card_favorite f join public.card c on c.id = f.card_id and c.is_active and c.card_set_id = v_s where f.user_id = v_b) then
    raise exception 'Q5884_I5_B_COUNT';
  end if;
  if exists (select 1 from _q5884_b_5356 r join public.card c on c.id = r.card_id where c.card_set_id = v_other) then raise exception 'Q5884_I5_OTHER_SET_IN_S'; end if;
  select count(*) into v_n from _q5884_a_5356 r
  where not exists (select 1 from public.card_favorite f where f.user_id = v_a and f.card_id = r.card_id);
  if v_n <> 0 then raise exception 'Q5884_I5_LEAK_TO_A: %', v_n; end if;
  -- E2: nada mais mudou (a função nova é a única diferença de permissões)
  if current_setting('q5884.policies') <> (
    select coalesce(md5(string_agg(tablename || policyname || cmd || array_to_string(roles, ',') || coalesce(qual, '') || coalesce(with_check, ''), '|' order by tablename, policyname)), '-')
    from pg_policies where schemaname = 'public' and tablename in ('card_favorite', 'card', 'card_set', 'card_asset')) then
    raise exception 'Q5884_E2_POLICIES';
  end if;
  if current_setting('q5884.f5336') <> (
    select md5(string_agg(p.proname || md5(p.prosrc) || coalesce(array_to_string(p.proacl, ','), ''), '|' order by p.proname))
    from pg_proc p where p.pronamespace = 'public'::regnamespace
      and p.proname in ('set_card_favorite', 'get_my_card_favorite_ids', 'get_my_card_favorites_by_variant', 'get_my_favorite_cards')) then
    raise exception 'Q5884_E2_5336_CHANGED';
  end if;
  if current_setting('q5884.acl') <> (
    select md5(string_agg(oid::regprocedure::text || coalesce(array_to_string(proacl, ','), ''), '|' order by oid))
    from pg_proc where pronamespace = 'public'::regnamespace and proname <> 'get_my_favorite_cards_by_card_set') then
    raise exception 'Q5884_E2_ACL';
  end if;
  raise notice 'Q5884 I1 I2 I3 I4 I5 E2 PASS (% favoritas no Set; B: %)', (select count(*) from _q5884_a_5356), (select count(*) from _q5884_b_5356);
end $$;

rollback;

-- Pós-ROLLBACK (somente leitura)
select (select count(*) from pg_proc where proname = 'get_my_favorite_cards_by_card_set') as fn_exists,
       (select count(*) from pg_stat_activity where state like 'idle in transaction%' and datname = current_database()) as idle_tx,
       (select count(*) from pg_locks where not granted) as waiting_locks;
