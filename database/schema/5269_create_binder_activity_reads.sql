/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5269 - P3-B S1 · Histórico do Fichário — leituras
              binder_activity_category(text)                       — interna
              get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)
              get_my_binder_activity_coverage(uuid)
              list_my_closed_binder_histories(integer)
Versão......: 1.0 (2026-10-25, P3-B-S1-FOUNDATION-READINESS-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S1, autorização expressa de Fabrício — G8; G5b/G5c dispensados
              sob H-A só para a S1; ledger 20261027024829 `5269_create_binder_activity_reads`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              LIVE_90 12/12. Harness 5860 NÃO EXECUTADO (H-A). Ver README §28.34.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: C-204 (titularidade e acesso), C-208 (fichários encerrados);
              LDM-198, LDM-202; README v1.2 §3.1, §6.2, §9.

Autorização (deny by default): toda leitura filtra owner_user_id = auth.uid().
Fichário de outro usuário, chave inexistente ou sem sessão → zero linhas,
indistinguíveis (não enumera). Nada depende do fichário existir: o histórico
de um fichário desmontado ou transferido para fora continua legível pelo
titular dos eventos, e só por ele.

Ordenação e paginação: (occurred_at desc, id desc), cursor composto
(p_before_occurred_at, p_before_id) — ambos ou nenhum. Limite 1–50 (padrão
20). Itens: até 50 por evento, por ordinal, com item_count e items_truncated.

Categorias (filtros da interface, README §3.3):
  CARDS · RESERVATIONS · LOCKS · PAGES · CATALOG · BINDER.

Nota C-172: o predicado "pode ler estes eventos" está isolado nesta função;
quando a associação de membros existir, ele é ampliado aqui, sem mudar
tabelas nem eventos.
================================================================
*/
begin;

do $pre$
begin
  if to_regclass('public.binder_activity_event') is null then
    raise exception 'PRECHECK 5269: aplique a 5267 antes';
  end if;
  if to_regprocedure('public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer)') is not null then
    raise exception 'PRECHECK 5269: leituras já existem';
  end if;
end;
$pre$;

create function public.binder_activity_category(p_event_type text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case
    when p_event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                          'CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT') then 'CARDS'
    when p_event_type in ('POCKET_RESERVED','RESERVATIONS_RELEASED') then 'RESERVATIONS'
    when p_event_type in ('POCKETS_LOCKED','POCKETS_UNLOCKED') then 'LOCKS'
    when p_event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED') then 'PAGES'
    when p_event_type in ('CATALOG_NOVELTIES_INCORPORATED','LEGACY_CATALOG_INCORPORATION') then 'CATALOG'
    when p_event_type in ('BINDER_ASSEMBLED','COLLECTION_ATTACHED','COLLECTION_DETACHED',
                          'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED') then 'BINDER'
  end
$fn$;

create function public.get_my_binder_activity(
  p_layout_key         uuid,
  p_categories         text[]      default null,
  p_before_occurred_at timestamptz default null,
  p_before_id          bigint      default null,
  p_limit              integer     default 20
)
returns table (
  event_id        bigint,
  occurred_at     timestamptz,
  event_type      text,
  category        text,
  source          text,
  is_legacy       boolean,
  collection_id   uuid,
  collection_name text,
  binder_name     text,
  summary         jsonb,
  item_count      integer,
  items           jsonb,
  items_truncated boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid    := (select auth.uid());
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if v_uid is null or p_layout_key is null then
    return;
  end if;
  if (p_before_occurred_at is null) <> (p_before_id is null) then
    raise exception 'cursor must have occurred_at and id together' using errcode = '22023', hint = 'BINDER_ACTIVITY_CURSOR';
  end if;
  if p_categories is not null and not (p_categories <@ array['CARDS','RESERVATIONS','LOCKS','PAGES','CATALOG','BINDER']) then
    raise exception 'unknown category' using errcode = '22023', hint = 'BINDER_ACTIVITY_CATEGORY';
  end if;

  return query
  with page as (
    select e.*
    from public.binder_activity_event e
    where e.owner_user_id = v_uid
      and e.layout_key = p_layout_key
      and (p_categories is null or public.binder_activity_category(e.event_type) = any (p_categories))
      and (p_before_id is null or (e.occurred_at, e.id) < (p_before_occurred_at, p_before_id))
    order by e.occurred_at desc, e.id desc
    limit v_limit
  )
  select pg.id, pg.occurred_at, pg.event_type, public.binder_activity_category(pg.event_type), pg.source,
         pg.source = 'LEGADO',
         pg.collection_id,
         coalesce(pg.collection_name,
                  (select c.name from public.collection c where c.id = pg.collection_id and c.owner_user_id = v_uid)),
         pg.binder_name, pg.summary,
         ic.n::integer,
         coalesce(it.items, '[]'::jsonb),
         ic.n > 50
  from page pg
  cross join lateral (select count(*) as n from public.binder_activity_item i where i.event_id = pg.id) ic
  cross join lateral (
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'ordinal', i.ordinal, 'kind', i.item_kind, 'effect', i.effect,
             'card_id', i.card_id, 'card_name', i.card_name, 'collector_number', i.collector_number,
             'card_set_code', i.card_set_code, 'variant_type_code', i.variant_type_code,
             'variant_type_name', i.variant_type_name,
             'from_page', i.from_page, 'from_row', i.from_row, 'from_col', i.from_col,
             'to_page', i.to_page, 'to_row', i.to_row, 'to_col', i.to_col, 'detail', i.detail))
           order by i.ordinal) as items
    from (select * from public.binder_activity_item i0 where i0.event_id = pg.id order by i0.ordinal limit 50) i
  ) it
  order by pg.occurred_at desc, pg.id desc;
end;
$fn$;

create function public.get_my_binder_activity_coverage(p_layout_key uuid)
returns table (
  full_coverage_from timestamptz,
  covered_from       timestamptz,
  coverage_reason    text,
  has_legacy         boolean,
  binder_is_mine     boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or p_layout_key is null then
    return;
  end if;
  return query
  select s.full_coverage_from,
         greatest(s.full_coverage_from, cv.covered_from),
         cv.reason,
         exists (select 1 from public.binder_activity_event e
                 where e.owner_user_id = v_uid and e.layout_key = p_layout_key and e.source = 'LEGADO'),
         exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
                 where l.id = p_layout_key and c.owner_user_id = v_uid)
  from public.binder_activity_setting s
  left join public.binder_activity_coverage cv
         on cv.owner_user_id = v_uid and cv.layout_key = p_layout_key
  where s.id = 1
    and (exists (select 1 from public.binder_activity_event e where e.owner_user_id = v_uid and e.layout_key = p_layout_key)
         or cv.owner_user_id is not null
         or exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
                    where l.id = p_layout_key and c.owner_user_id = v_uid));
end;
$fn$;

create function public.list_my_closed_binder_histories(p_limit integer default 50)
returns table (
  layout_key    uuid,
  binder_name   text,
  last_event_at timestamptz,
  event_count   bigint,
  closed        boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return;
  end if;
  return query
  select e.layout_key,
         (array_agg(e.binder_name order by e.occurred_at desc, e.id desc)
            filter (where e.binder_name is not null))[1],
         max(e.occurred_at),
         count(*),
         bool_or(e.event_type in ('BINDER_DISMANTLED','BINDER_DELETED_EMPTY'))
  from public.binder_activity_event e
  where e.owner_user_id = v_uid
    and not exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
                    where l.id = e.layout_key and c.owner_user_id = v_uid)
  group by e.layout_key
  order by max(e.occurred_at) desc
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end;
$fn$;

revoke all on function public.binder_activity_category(text) from public, anon, authenticated, service_role;
revoke all on function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer) from public, anon;
revoke all on function public.get_my_binder_activity_coverage(uuid) from public, anon;
revoke all on function public.list_my_closed_binder_histories(integer) from public, anon;
grant execute on function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer) to authenticated;
grant execute on function public.get_my_binder_activity_coverage(uuid) to authenticated;
grant execute on function public.list_my_closed_binder_histories(integer) to authenticated;

comment on function public.get_my_binder_activity(uuid, text[], timestamptz, bigint, integer) is
  'P3-B 5269: eventos do fichário do titular (auth.uid()), do mais recente ao mais antigo, cursor (occurred_at, id), até 50 por página e 50 itens por evento. Outro usuário/chave inexistente/sem sessão → zero linhas.';
comment on function public.get_my_binder_activity_coverage(uuid) is
  'P3-B 5269: início da cobertura completa (global), marco do titular (exclusão definitiva/recebimento/montagem), presença de legado e se o fichário ainda é do titular.';
comment on function public.list_my_closed_binder_histories(integer) is
  'P3-B 5269 (C-208): fichários com histórico do titular que não existem mais ou já não são dele (desmontados, removidos ou transferidos para fora). Interface pós-MVP.';

commit;
