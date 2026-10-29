/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5294 - P3-B S6 · Histórico do Fichário — instrumentação E19 (Fichário desmontado)
              dismantle_my_collection_binder(uuid, text)
Versão......: 1.0 (2026-10-28, P3-B S6 — instrumentação E01, E16–E20)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-28
Base........: 5242 (corpo do LIVE: código idêntico, sem comentários) (md5(prosrc) LIVE 6aa90085a3a97c5b149fde6f3c4a6096, conferido em 2026-10-28;
              canônico: database/schema/5242_update_binder_dismantle_for_region_images.sql).
Autoridade..: README da proposta §4.1, §4.2, §14.7, §20 (W3), §33 (S6).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S6". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s6.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento BINDER_DISMANTLED (lote), coleção = a proprietária; resumo = contagens do plano:
  · CARD/REMOVED por carta e RESERVATION/RELEASED por reserva (origem), depois BINDER/CLOSED —
    tudo ANTES de apagar (I-10); ALREADY_ABSENT e recusas saem antes do begin.
  Base: o corpo LIVE não tem os comentários `--` da canônica 5242 (mesmo achado da 5243 na S4;
  código idêntico — md5 normalizado igual). Sem caminho na interface atual.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_card_item(text, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null
     or to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null
     or to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)') is null then
    raise exception 'PRECHECK 5294: dependências ausentes (5268/5271/5275/5279)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.dismantle_my_collection_binder(uuid, text)')) is distinct from '6aa90085a3a97c5b149fde6f3c4a6096' then
    raise exception 'PRECHECK 5294: função no LIVE diverge da base 5242 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.dismantle_my_collection_binder(
  p_collection_id   uuid,
  p_dismantle_token text
)
returns table (
  outcome              text,
  pages_removed        integer,
  slots_removed        integer,
  assignments_removed  integer,
  reservations_removed integer,
  regions_removed      integer,
  locks_released       integer,
  images_removed       integer,   -- 5236
  image_paths          text[]     -- 5236: o cliente apaga estes arquivos DEPOIS
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_layout  uuid;
  r         record;
  v_unlock  integer;
  v_asg     integer;
  v_exc     integer;
  v_rg      integer;
  v_pg      integer;
  v_left    integer;
  v_img_n   integer;
  v_img     integer;
  v_paths   text[];
  v_rimg    integer;
  v_rpaths  text[];
  v_act     record;  -- P3B-S6
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_dismantle_token is null or p_dismantle_token !~ '^d1:[0-9a-f]{64}$' then
    raise exception 'INVALID_DISMANTLE_TOKEN' using errcode = '22023';
  end if;

  perform 1
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid
  for update;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout
  from public.collection_layout l
  where l.collection_id = p_collection_id
  for update;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'COLLECTION_IS_BINDER_GUEST'
        using hint = 'esta coleção usa o fichário de outra coleção — desassocie-a em vez de desmontar';
    end if;
    outcome := 'ALREADY_ABSENT';
    pages_removed := 0; slots_removed := 0; assignments_removed := 0;
    reservations_removed := 0; regions_removed := 0; locks_released := 0;
    images_removed := 0; image_paths := '{}'::text[];
    return next;
    return;
  end if;

  if exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout) then
    raise exception 'BINDER_HAS_GUESTS'
      using hint = 'desassocie as outras coleções deste fichário antes de desmontá-lo';
  end if;

  select * into r from public.collection_binder_dismantle_snapshot(p_collection_id);
  if r.dismantle_token is distinct from p_dismantle_token then
    raise exception 'DISMANTLE_PLAN_CHANGED';
  end if;
  -- P3B-S6
  -- E19: encerramento registrado ANTES de apagar (I-10; o cabeçalho e as posições leem o  -- P3B-S6
  -- fichário). O histórico sobrevive ao fichário (A1); contagens do plano no resumo.  -- P3B-S6
  perform public.binder_activity_begin(v_layout, 'BINDER_DISMANTLED', 'FICHARIO', p_collection_id,  -- P3B-S6
    jsonb_build_object('pages', r.pages_count, 'slots', r.slots_count, 'regions', r.regions_count, 'locks', r.locked_count));  -- P3B-S6
  for v_act in  -- P3B-S6
    select a.physical_card_id, a.slot_id  -- P3B-S6
    from public.collection_layout_slot_assignment a  -- P3B-S6
    join public.collection_layout_slot s on s.id = a.slot_id  -- P3B-S6
    join public.collection_layout_page p on p.id = s.page_id  -- P3B-S6
    where p.layout_id = v_layout  -- P3B-S6
    order by p.page_number, s.row_index, s.column_index  -- P3B-S6
  loop  -- P3B-S6
    perform public.binder_activity_add_card_item('REMOVED', v_act.physical_card_id, v_act.slot_id, null);  -- P3B-S6
  end loop;  -- P3B-S6
  for v_act in  -- P3B-S6
    select e.slot_id  -- P3B-S6
    from public.collection_layout_slot_expected_content e  -- P3B-S6
    join public.collection_layout_slot s on s.id = e.slot_id  -- P3B-S6
    join public.collection_layout_page p on p.id = s.page_id  -- P3B-S6
    where p.layout_id = v_layout  -- P3B-S6
    order by p.page_number, s.row_index, s.column_index  -- P3B-S6
  loop  -- P3B-S6
    perform public.binder_activity_add_reservation_item('RELEASED', v_act.slot_id);  -- P3B-S6
  end loop;  -- P3B-S6
  perform public.binder_activity_add_item('BINDER', 'CLOSED', null, null, null, null, null, null,  -- P3B-S6
                                          jsonb_build_object('reason', 'DISMANTLED'));  -- P3B-S6

  select count(*)::integer into v_img_n
  from public.collection_layout_slot_image i
  join public.collection_layout_slot s on s.id = i.slot_id
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = v_layout;
  v_img_n := v_img_n + (
    select count(*)::integer
    from public.collection_layout_region_image ri
    join public.collection_layout_region rg on rg.id = ri.region_id
    join public.collection_layout_page p    on p.id = rg.page_id
    where p.layout_id = v_layout);

  update public.collection_layout_slot s
     set locked = false
   where s.locked
     and s.page_id in (select p.id from public.collection_layout_page p where p.layout_id = v_layout);
  get diagnostics v_unlock = row_count;

  delete from public.collection_layout_slot_assignment a
   using public.collection_layout_slot s, public.collection_layout_page p
   where a.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_asg = row_count;

  delete from public.collection_layout_slot_expected_content e
   using public.collection_layout_slot s, public.collection_layout_page p
   where e.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_exc = row_count;

  with d as (
    delete from public.collection_layout_region_image ri
     using public.collection_layout_region rg, public.collection_layout_page p
     where ri.region_id = rg.id and rg.page_id = p.id and p.layout_id = v_layout
    returning ri.storage_path as path
  )
  select count(*)::integer, coalesce(array_agg(d.path), '{}'::text[])
    into v_rimg, v_rpaths
  from d;

  delete from public.collection_layout_region rg
   using public.collection_layout_page p
   where rg.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_rg = row_count;

  with d as (
    delete from public.collection_layout_slot_image i
     using public.collection_layout_slot s, public.collection_layout_page p
     where i.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout
    returning i.storage_path as path
  )
  select count(*)::integer, coalesce(array_agg(d.path order by d.path), '{}'::text[])
    into v_img, v_paths
  from d;

  v_img   := v_img + v_rimg;
  v_paths := array(select unnest(v_paths || v_rpaths) as x order by x);

  delete from public.collection_layout_page p where p.layout_id = v_layout;
  get diagnostics v_pg = row_count;

  delete from public.collection_layout l where l.id = v_layout;

  select count(*)::integer into v_left
  from public.collection_layout l where l.collection_id = p_collection_id;

  if v_left <> 0
     or v_unlock <> r.locked_count
     or v_asg <> r.assignments_count
     or v_exc <> r.reservations_count
     or v_rg <> r.regions_count
     or v_pg <> r.pages_count
     or v_img <> v_img_n then
    raise exception 'BINDER_DISMANTLE_INCONSISTENT';
  end if;

  perform public.binder_activity_end();  -- P3B-S6
  outcome              := 'DISMANTLED';
  pages_removed        := v_pg;
  slots_removed        := r.slots_count;
  assignments_removed  := v_asg;
  reservations_removed := v_exc;
  regions_removed      := v_rg;
  locks_released       := v_unlock;
  images_removed       := v_img;
  image_paths          := v_paths;
  return next;
end;
$fn$;

revoke all on function public.dismantle_my_collection_binder(uuid, text) from public;
revoke all on function public.dismantle_my_collection_binder(uuid, text) from anon;
grant execute on function public.dismantle_my_collection_binder(uuid, text) to authenticated;

commit;

/*
Resultado esperado: dismantle_my_collection_binder(uuid, text) recriada com o mesmo contrato; nenhum evento gravado pela instalação.
Como validar (só leitura): LIVE_S6_90_postcheck_readonly.sql, bloco A.
*/
