/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5284 - P3-B S4 · Histórico do Fichário — instrumentação E12 (Espaço fechado)
              close_my_binder_gap(uuid, uuid, uuid, text, uuid)
Versão......: 1.0 (2026-10-27, P3-B S4 — instrumentação E11–E15)
Status......: PROPOSTA — NÃO EXECUTADA. Exige autorização própria para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-27
Base........: 5243 (corpo do LIVE; o arquivo canônico difere só por comentários) (md5(prosrc) LIVE eef3073f5ad98ffe6fdfe36f1adb9f49, conferido em 2026-10-27).
Autoridade..: README da proposta §4.1, §5.2, §7.2 (R5), §20 (W3), §31 (S4).

Diff mínimo: o corpo é o da base LIVE, byte a byte, mais as linhas marcadas com
"-- P3B-S4". Removidas essas linhas e trocado o delimitador $fn$ → $$, o corpo volta a
ter o md5 acima (static_check_p3b_s4.py). Assinatura, retorno, SET, mensagens, códigos de
erro, ordem de travas e permissões inalterados (REVOKE/GRANT originais reaplicados).

Evento GAP_CLOSED (lote atômico, até 500 linhas):
  · por bolso devolvido: CARD/SHIFTED, RESERVATION/SHIFTED e POCKET/SHIFTED (imagem),
    origem → destino, gravados antes da remoção da página (5279);
  · página criada pela inserção, removida aqui → itens PAGE_REMOVED (+ renumeração, se houver)
    via remove_layout_page (R5);
  · cadeia sem conteúdo e sem página removida → nenhum item, nenhum evento.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)') is null then
    raise exception 'PRECHECK 5284: dependência ausente (binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb))';
  end if;
  if to_regprocedure('public.binder_activity_add_pocket_shift_items(uuid, uuid)') is null then
    raise exception 'PRECHECK 5284: dependência ausente (binder_activity_add_pocket_shift_items(uuid, uuid))';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('public.close_my_binder_gap(uuid, uuid, uuid, text, uuid)')) is distinct from 'eef3073f5ad98ffe6fdfe36f1adb9f49' then
    raise exception 'PRECHECK 5284: função no LIVE diverge da base 5243 (md5)';
  end if;
end;
$pre$;

CREATE OR REPLACE FUNCTION public.close_my_binder_gap(
  p_collection_id uuid,
  p_gap_slot_id   uuid,
  p_end_slot_id   uuid,
  p_undo_token    text,
  p_added_page_id uuid default null
)
returns table (
  outcome       text,      -- CLOSED
  moved_pockets integer,
  rows_moved    integer,
  page_removed  boolean
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  c_row_limit constant integer := 500;
  v_layout uuid;
  v_chain  uuid[];
  v_rows   integer := 0;
  v_count  integer;
  i        integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_gap_slot_id is null or p_end_slot_id is null
     or p_undo_token is null or p_undo_token !~ '^u1:[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  v_layout := public.binder_layout_lock_for_collection(p_collection_id);

  if public.binder_gap_undo_token(v_layout, p_gap_slot_id, p_end_slot_id, p_added_page_id)
       is distinct from p_undo_token then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001',
      hint = 'o fichário mudou desde que o espaço foi aberto';
  end if;

  with s as (
    select sl.id, sl.locked,
           (row_number() over (order by p.page_number, sl.row_index, sl.column_index))::integer as ord,
           exists (select 1 from public.collection_layout_region r
                   where r.page_id = sl.page_id
                     and sl.row_index    between r.top_row     and r.top_row     + r.height - 1
                     and sl.column_index between r.left_column and r.left_column + r.width  - 1) as in_region
    from public.collection_layout_slot sl
    join public.collection_layout_page p on p.id = sl.page_id
    where p.layout_id = v_layout
  ), c as (
    select s.* from s
    where s.ord between (select s1.ord from s s1 where s1.id = p_gap_slot_id)
                    and (select s2.ord from s s2 where s2.id = p_end_slot_id)
  )
  select array_agg(c.id order by c.ord), count(*) filter (where c.locked or c.in_region)
    into v_chain, v_count
  from c;
  if v_chain is null or cardinality(v_chain) < 2 or v_count > 0 then
    raise exception 'GAP_UNDO_EXPIRED' using errcode = '40001';
  end if;

  perform 1 from public.collection_layout_slot s where s.id = any (v_chain) order by s.id for update;

  -- E12: depois da validação do token e da cadeia. Página removida embutida entra como  -- P3B-S4
  -- item PAGE_REMOVED deste evento (R5).  -- P3B-S4
  perform public.binder_activity_begin(v_layout, 'GAP_CLOSED', 'FICHARIO');  -- P3B-S4
  for i in 2..cardinality(v_chain) loop
    v_rows := v_rows + public.binder_gap_move_pocket(v_chain[i], v_chain[i - 1]);
    if v_rows > c_row_limit then
      raise exception 'GAP_OVER_LIMIT' using errcode = '54000';
    end if;
  end loop;

  -- Conteúdo devolvido: o que está agora em v_chain[i-1] veio de v_chain[i]. Antes de  -- P3B-S4
  -- remover a página (I-10: a posição de origem pode estar nela).  -- P3B-S4
  for i in 2..cardinality(v_chain) loop  -- P3B-S4
    perform public.binder_activity_add_pocket_shift_items(v_chain[i], v_chain[i - 1]);  -- P3B-S4
  end loop;  -- P3B-S4
  -- P3B-S4
  page_removed := false;
  if p_added_page_id is not null then
    if exists (select 1 from public.collection_layout_page p
               where p.id = p_added_page_id and p.layout_id = v_layout
                 and p.page_number = (select max(p2.page_number) from public.collection_layout_page p2 where p2.layout_id = v_layout))
       and not exists (
         select 1 from public.collection_layout_slot s
         where s.page_id = p_added_page_id
           and (s.locked
                or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
                or exists (select 1 from public.collection_layout_slot_expected_content x where x.slot_id = s.id)
                or exists (select 1 from public.collection_layout_slot_image im where im.slot_id = s.id)))
       and not exists (select 1 from public.collection_layout_region r where r.page_id = p_added_page_id) then
      perform public.remove_layout_page(p_added_page_id);
      page_removed := true;
    end if;
  end if;

  outcome       := 'CLOSED';
  moved_pockets := cardinality(v_chain) - 1;
  rows_moved    := v_rows;
  return next;
  perform public.binder_activity_end();  -- P3B-S4
end;
$fn$;

revoke all on function public.close_my_binder_gap(uuid, uuid, uuid, text, uuid) from public, anon;
grant execute on function public.close_my_binder_gap(uuid, uuid, uuid, text, uuid) to authenticated;

commit;
