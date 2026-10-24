/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5858 - validação da 5261 (get_my_inventory_items) e da
              5262 (get_my_inventory_item_copies): códigos estáveis de
              acabamento (MY-INVENTORY-HOLOGRAPHIC-FINISH-FOUNDATION-01)
Versão......: 1.0
Status......: PROPOSTA. Seção A executada em 2026-10-24 como ensaio
              somente leitura (sintaxe e linha de base); B–D só depois
              da aplicação autorizada.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Todas as seções são SOMENTE LEITURA (begin transaction read only; o
set_config é local à transação). O usuário de teste é o dono do maior
acervo (resolvido aqui, nunca digitado).

Protocolo:
  A  ANTES de aplicar 5261/5262: rodar e GUARDAR as impressões digitais.
  —  aplicar 5261 e 5262 (cada uma na sua transação).
  B  estrutura (assinaturas, retorno, SECURITY DEFINER, search_path, ACL).
  C  rodar a MESMA consulta da Seção A e comparar: todas as linhas iguais
     → as colunas antigas não mudaram (valores e ordem).
  D  correção dos códigos novos contra o catálogo + autorização.

Resultado esperado: B, D com todas as linhas ok = true; C idêntico a A.
================================================================
*/

-- ============================================================
-- SEÇÃO A / C — impressões digitais das colunas ANTIGAS
-- (rodar igual antes e depois; comparar linha a linha)
-- ============================================================
begin transaction read only;
set local statement_timeout = '30s';

select set_config('request.jwt.claims',
         json_build_object('sub', i.owner_user_id, 'role', 'authenticated')::text, true)
from public.inventory i
join public.physical_card pc on pc.inventory_id = i.id
group by i.id, i.owner_user_id
order by count(*) desc
limit 1;

with combos(caso, p_search, p_set, p_lang, p_without_coll, p_sort, p_limit, p_offset, p_without_storage) as (
  values
    ('A1 padrão RECENT',        null::text, null::text, null::text, false, 'RECENT',     96, 0,  false),
    ('A2 SET_NUMBER',           null,       null,       null,       false, 'SET_NUMBER', 96, 0,  false),
    ('A3 SET_NUMBER pág. 2',    null,       null,       null,       false, 'SET_NUMBER', 96, 96, false),
    ('A4 busca "a"',            'a',        null,       null,       false, 'RECENT',     96, 0,  false),
    ('A5 sem coleção',          null,       null,       null,       true,  'RECENT',     96, 0,  false),
    ('A6 sem local',            null,       null,       null,       false, 'RECENT',     96, 0,  true),
    ('A7 idioma pt-BR',         null,       null,       'pt-BR',    false, 'SET_NUMBER', 96, 0,  false)
)
select c.caso,
       count(r.*) as linhas,
       md5(coalesce(string_agg(
         row(r.card_variant_id, r.language_code, r.language_name, r.card_name,
                   r.collector_number, r.collector_total, r.card_set_code, r.card_set_name,
                   r.is_default_variant, r.variant_label, r.copies_count, r.last_added_at,
                   r.image_path, r.total_count, r.copies_owned, r.total_copies)::text,
         '|' order by r.ordinality), '')) as impressao
from combos c
left join lateral public.get_my_inventory_items(
       c.p_search, c.p_set, c.p_lang, null, c.p_without_coll, c.p_sort, c.p_limit, c.p_offset, null, c.p_without_storage)
     with ordinality as r on true
group by c.caso
order by c.caso;

-- Detalhe (5162/5262): os 5 grupos com mais exemplares, 18 colunas antigas.
with grupos as (
  select pc.card_variant_id, l.code as language_code, count(*) as n
  from public.physical_card pc
  join public.inventory i on i.id = pc.inventory_id
  join public.language l on l.id = pc.language_id
  where i.owner_user_id = (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid
  group by pc.card_variant_id, l.code
  order by count(*) desc, pc.card_variant_id, l.code
  limit 5
)
select 'A8 detalhe top-5' as caso,
       count(d.*) as linhas,
       md5(coalesce(string_agg(
         row(d.card_variant_id, d.language_code, d.language_name, d.card_name,
                   d.collector_number, d.collector_total, d.card_set_code, d.card_set_name,
                   d.is_default_variant, d.variant_label, d.image_path, d.copies_total,
                   d.physical_card_id, d.copy_number, d.added_at, d.collection_id,
                   d.collection_name, d.storage_name)::text,
         '|' order by g.card_variant_id, g.language_code, d.ordinality), '')) as impressao
from grupos g
cross join lateral public.get_my_inventory_item_copies(g.card_variant_id, g.language_code)
     with ordinality as d;

rollback;

-- ============================================================
-- SEÇÃO B — estrutura (depois de aplicar)
-- ============================================================
begin transaction read only;
set local statement_timeout = '30s';

with f as (
  select p.oid, p.proname, p.prosecdef, p.provolatile, p.proconfig,
         pg_get_function_result(p.oid) as res, p.proacl::text as acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('get_my_inventory_items', 'get_my_inventory_item_copies')
)
select 'B1 uma sobrecarga de cada' as caso,
       (select count(*) from f where proname = 'get_my_inventory_items') = 1
   and (select count(*) from f where proname = 'get_my_inventory_item_copies') = 1 as ok
union all
select 'B2 5261 assinatura de entrada preservada',
       to_regprocedure('public.get_my_inventory_items(text, text, text, uuid, boolean, text, integer, integer, uuid, boolean)') is not null
union all
select 'B3 5261 retorno = 16 colunas da 5220 + 2 ao final',
       (select res from f where proname = 'get_my_inventory_items') =
       'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, copies_count integer, last_added_at timestamp with time zone, image_path text, total_count bigint, copies_owned integer, total_copies bigint, variant_type_code text, rarity_code text)'
union all
select 'B4 5262 retorno = 18 colunas da 5162 + 2 ao final',
       (select res from f where proname = 'get_my_inventory_item_copies') =
       'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_total integer, physical_card_id uuid, copy_number integer, added_at timestamp with time zone, collection_id uuid, collection_name text, storage_name text, variant_type_code text, rarity_code text)'
union all
select 'B5 SECURITY DEFINER + STABLE + search_path vazio (ambas)',
       bool_and(prosecdef and provolatile = 's' and proconfig = array['search_path=""']) from f
union all
select 'B6 EXECUTE: authenticated sim; anon e PUBLIC não (ambas)',
       bool_and(has_function_privilege('authenticated', oid, 'EXECUTE')
                and not has_function_privilege('anon', oid, 'EXECUTE')
                and not has_function_privilege('public', oid, 'EXECUTE'))
from f
union all
select 'B8 dono = postgres (SECURITY DEFINER executa com o mesmo dono de hoje; ACL final = {postgres,authenticated})',
       bool_and(pg_get_userbyid((select p.proowner from pg_proc p where p.oid = f.oid)) = 'postgres'
                and acl = '{postgres=X/postgres,authenticated=X/postgres}') from f
union all
select 'B7 sem dependentes (pg_depend)',
       not exists (select 1 from pg_depend d join f on d.refobjid = f.oid
                   where d.refclassid = 'pg_catalog.pg_proc'::regclass and d.deptype = 'n');

rollback;

-- ============================================================
-- SEÇÃO D — códigos novos corretos + autorização (depois de aplicar)
-- ============================================================
begin transaction read only;
set local statement_timeout = '30s';

select set_config('request.jwt.claims',
         json_build_object('sub', i.owner_user_id, 'role', 'authenticated')::text, true)
from public.inventory i
join public.physical_card pc on pc.inventory_id = i.id
group by i.id, i.owner_user_id
order by count(*) desc
limit 1;

with pagina as (
  select r.*
  from public.get_my_inventory_items(null, null, null, null, false, 'SET_NUMBER', 96, 0, null, false) r
),
esperado as (
  select pg.card_variant_id, vt.code::text as vt_code, ra.code::text as ra_code
  from pagina pg
  join public.card_variant cv on cv.id = pg.card_variant_id
  join public.card c on c.id = cv.card_id
  left join public.card_variant_type vt on vt.id = cv.variant_type_id
  left join public.rarity ra on ra.id = c.rarity_id
)
select 'D1 5261 variant_type_code = catálogo em todas as linhas' as caso,
       count(*) > 0 and bool_and(p.variant_type_code is not distinct from e.vt_code) as ok
from pagina p join esperado e using (card_variant_id)
union all
select 'D2 5261 rarity_code = catálogo em todas as linhas',
       count(*) > 0 and bool_and(p.rarity_code is not distinct from e.ra_code)
from pagina p join esperado e using (card_variant_id)
union all
select 'D3 5261 nenhum código nulo no acervo de teste',
       bool_and(p.variant_type_code is not null and p.rarity_code is not null)
from pagina p;

with grupos as (
  select pc.card_variant_id, l.code as language_code
  from public.physical_card pc
  join public.inventory i on i.id = pc.inventory_id
  join public.language l on l.id = pc.language_id
  where i.owner_user_id = (current_setting('request.jwt.claims', true)::json ->> 'sub')::uuid
  group by pc.card_variant_id, l.code
  order by count(*) desc
  limit 5
),
det as (
  select g.card_variant_id, d.variant_type_code, d.rarity_code
  from grupos g
  cross join lateral public.get_my_inventory_item_copies(g.card_variant_id, g.language_code) d
)
select 'D4 5262 códigos = catálogo e constantes por grupo' as caso,
       count(*) > 0 and bool_and(d.variant_type_code is not distinct from vt.code::text
                                 and d.rarity_code is not distinct from ra.code::text) as ok
from det d
join public.card_variant cv on cv.id = d.card_variant_id
join public.card c on c.id = cv.card_id
left join public.card_variant_type vt on vt.id = cv.variant_type_id
left join public.rarity ra on ra.id = c.rarity_id;

-- D5/D6 — sem sessão: as duas continuam exigindo auth.uid() (28000).
select set_config('request.jwt.claims', '', true);
do $d5$
begin
  begin
    perform 1 from public.get_my_inventory_items();
    raise notice 'D5 FAIL: 5261 respondeu sem sessão';
  exception when sqlstate '28000' then raise notice 'D5 ok: 5261 exige sessão (28000)';
  end;
  begin
    perform 1 from public.get_my_inventory_item_copies(gen_random_uuid(), 'pt-BR');
    raise notice 'D6 FAIL: 5262 respondeu sem sessão';
  exception when sqlstate '28000' then raise notice 'D6 ok: 5262 exige sessão (28000)';
  end;
end;
$d5$;

rollback;
