/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5382 - Páginas do fichário pelo EDITOR, só no fichário que atende
              apenas a coleção autorizada (V1-13 · E1-C)
Versão......: 1.1 (2026-11-15, `BULK OPERATIONS SAFETY REVIEW-02`: remoção classifica cada bolso;
              conteúdo de terceiros → OPERATION_RESERVED_TO_OWNER). 1.0 (2026-11-15)
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-C | COLLECTION-SCOPED BULK OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-237 ("operações de página e em massa": num fichário de VÁRIAS
              coleções são do titular; num fichário de UMA coleção o EDITOR pode,
              desde que não desloque, retire nem descarte conteúdo de terceiros;
              reordenar preserva o conteúdo de cada bolso), C-238 (identidade,
              grade, imagens e estrutura de participação continuam do titular),
              C-241, C-243 (recusa neutra).
Depende de..: E1-B1 (5371), E1-B3 (5378/5379), E1-C (5381).

Funções novas:
  assert_collection_binder_editor_exclusive(p_collection_id)       — INTERNA
      → (layout_id, owner_user_id, container_id)
      Autoriza como a 5371 (proprietária FOR UPDATE → layout FOR UPDATE →
      participação FOR SHARE) e exige fichário EXCLUSIVO de X: X é a coleção
      proprietária e não há nenhuma convidada. Associar/desassociar passam pela
      mesma trava da proprietária (5122), então o conjunto de coleções não muda
      até o fim da transação. Senão → OPERATION_RESERVED_TO_OWNER (42501), sem
      dizer o que há no fichário.
  editor_add_binder_page(p_collection_id) → (page_number, slots_created)
      Espelho da 5280: página nova no fim, vazia, com a grade do fichário.
  editor_remove_binder_page(p_collection_id, p_page_number,
                            p_confirm_species_references default null)
      → (removed_page_number, species_references_removed)
      Espelho da 5286. Só página VAZIA. Cada bolso é classificado (5371/5378):
      qualquer bolso FOREIGN (carta de outra coleção ou sem coleção — inclusive
      de convidada já desassociada, 5253 —, imagem ou mesclagem do titular,
      trava sem conteúdo de X, referência de outra coleção) →
      OPERATION_RESERVED_TO_OWNER (42501), a recusa da C-237; conteúdo de X
      (carta, reserva, trava) → PAGE_NOT_EMPTY (55000), que o EDITOR pode
      esvaziar. Sem contagens. Referências de espécie de X exigem a contagem
      como confirmação (SPECIES_REFERENCES_ON_PAGE:n). Fichário fica com pelo
      menos uma página.
  editor_reorder_binder_pages(p_collection_id, p_page_numbers_ordered int[])
      → (page_number, previous_page_number)
      Espelho da 5282 endereçado por NÚMERO de página (o EDITOR não recebe id de
      página): o i-ésimo elemento é o número atual da página que passa a ser a
      página i. Permutação completa de 1..N; ordem igual → sem evento.
Isolamento: as três só existem no fichário exclusivo de X. Exclusivo NÃO
  significa livre de terceiros: ficam cartas de convidadas desassociadas (5253),
  cartas sem coleção, imagens, mesclagens e travas do titular e referências de
  uma proprietária anterior (5254 não as move). Adicionar cria conteúdo vazio;
  remover recusa qualquer página com conteúdo de terceiros; reordenar move
  páginas inteiras sem tocar bolso (a C-237 o permite por isso). Nada de
  terceiros é deslocado de bolso, retirado ou descartado.
Atomicidade: validação completa sob as travas antes de qualquer escrita; toda
  recusa desfaz a chamada inteira.
Histórico: PAGES_ADDED, PAGE_REMOVED, PAGES_REORDERED com o EDITOR como ator e X
  como coleção (5372, 5379, 5381); itens PAGE iguais aos do titular.
Funções do titular (5280, 5282, 5286, 5122): não tocadas.
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5382 em ROLLBACK_E1C.sql.
Como validar: harness 5892, seções 1–2.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.assert_collection_binder_editor(uuid)') is null
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'))
        is distinct from '21f1b51a3a0f6c80337c2c593cc6054f'
     or not exists (select 1 from pg_catalog.pg_trigger t
                    where t.tgrelid = 'public.binder_activity_event'::regclass and t.tgname = 'trg_bae_editor_event_type') then
    raise exception 'PRECHECK 5382: E1-B1, E1-B3 (5378) ou 5381 não aplicadas';
  end if;
  if to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)') is not null
     or to_regprocedure('public.editor_add_binder_page(uuid)') is not null
     or to_regprocedure('public.editor_remove_binder_page(uuid, integer, integer)') is not null
     or to_regprocedure('public.editor_reorder_binder_pages(uuid, integer[])') is not null then
    raise exception 'PRECHECK 5382: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: fichário exclusivo da coleção autorizada ---------------------------------
create function public.assert_collection_binder_editor_exclusive(p_collection_id uuid)
returns table (layout_id uuid, owner_user_id uuid, container_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  r record;
begin
  select * into r from public.assert_collection_binder_editor(p_collection_id) a;
  if r.anchor_collection_id is distinct from p_collection_id
     or exists (select 1 from public.collection_layout_guest g where g.layout_id = r.layout_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'num fichário com mais de uma coleção, esta operação é do titular';
  end if;
  return query select r.layout_id, r.owner_user_id, r.container_id;
end;
$fn$;

-- Adicionar página --------------------------------------------------------------------------
create function public.editor_add_binder_page(p_collection_id uuid)
returns table (page_number integer, slots_created integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_rows   integer;
  v_cols   integer;
  v_next   integer;
  v_page   uuid;
  v_n      integer;
begin
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;

  select l.grid_rows, l.grid_columns into v_rows, v_cols
  from public.collection_layout l where l.id = v_layout;
  select coalesce(max(p.page_number), 0) + 1 into v_next
  from public.collection_layout_page p where p.layout_id = v_layout;

  perform public.binder_activity_begin(v_layout, 'PAGES_ADDED', 'FICHARIO', p_collection_id);
  insert into public.collection_layout_page as clp (layout_id, page_number)
  values (v_layout, v_next)
  returning clp.id into v_page;
  insert into public.collection_layout_slot (page_id, row_index, column_index)
  select v_page, r, c
  from generate_series(1, v_rows) as r
  cross join generate_series(1, v_cols) as c;
  get diagnostics v_n = row_count;
  if v_n <> v_rows * v_cols then
    raise exception 'inconsistência estrutural: % bolsos criados, esperado %', v_n, v_rows * v_cols;
  end if;
  perform public.binder_activity_add_item('PAGE', 'PAGE_ADDED', null, null, null, null, null, v_next);
  perform public.binder_activity_end();

  return query select v_next, v_n;
end;
$fn$;

-- Remover página vazia ------------------------------------------------------------------------
create function public.editor_remove_binder_page(
  p_collection_id              uuid,
  p_page_number                integer,
  p_confirm_species_references integer default null
)
returns table (removed_page_number integer, species_references_removed integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_page   uuid;
  v_n      integer;
  v_refs   integer;
  v_renum  record;
begin
  if p_page_number is null or p_page_number < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;

  select p.id into v_page
  from public.collection_layout_page p
  where p.layout_id = v_layout and p.page_number = p_page_number
  for update;
  if v_page is null then
    raise exception 'PAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  select count(*) into v_n from public.collection_layout_page p where p.layout_id = v_layout;
  if v_n <= 1 then
    raise exception 'BINDER_MUST_KEEP_ONE_PAGE' using errcode = '55000';
  end if;

  -- Conteúdo que não é de X em qualquer bolso da página (carta de outra coleção ou
  -- sem coleção — inclusive de convidada já desassociada, cujas posições ficam (5253) —,
  -- reserva de outra coleção, imagem ou mesclagem do titular, trava sem conteúdo de X,
  -- referência de outra coleção): recusa da C-237, "reservada ao titular", sem dizer o quê.
  if exists (select 1 from public.collection_layout_slot s
             where s.page_id = v_page
               and public.binder_slot_editor_scope(v_layout, p_collection_id, p_collection_id, s.id) = 'FOREIGN') then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'esta página tem conteúdo que só o titular pode retirar';
  end if;
  -- Conteúdo de X (carta, reserva, trava): o EDITOR pode esvaziar antes.
  if exists (select 1 from public.collection_layout_slot_assignment a
             join public.collection_layout_slot s on s.id = a.slot_id where s.page_id = v_page)
     or exists (select 1 from public.collection_layout_slot_expected_content e
                join public.collection_layout_slot s on s.id = e.slot_id where s.page_id = v_page)
     or exists (select 1 from public.collection_layout_region rg where rg.page_id = v_page)
     or exists (select 1 from public.collection_layout_slot_image i
                join public.collection_layout_slot s on s.id = i.slot_id where s.page_id = v_page)
     or exists (select 1 from public.collection_layout_slot s where s.page_id = v_page and s.locked) then
    raise exception 'PAGE_NOT_EMPTY' using errcode = '55000',
      hint = 'esvazie a página antes de removê-la';
  end if;

  -- Referências de espécie: só da Pokédex proprietária (= X, 5257); confirmar a contagem.
  select count(*)::integer into v_refs
  from public.collection_layout_slot_species_reference sr
  join public.collection_layout_slot s on s.id = sr.slot_id
  where s.page_id = v_page and sr.layout_id = v_layout and sr.collection_id = p_collection_id;
  if v_refs > 0 and p_confirm_species_references is distinct from v_refs then
    raise exception 'SPECIES_REFERENCES_ON_PAGE' using errcode = 'P0001',
      hint = 'SPECIES_REFERENCES_ON_PAGE:' || v_refs;
  end if;

  perform public.binder_activity_begin(v_layout, 'PAGE_REMOVED', 'FICHARIO', p_collection_id);
  perform public.binder_activity_add_item('PAGE', 'PAGE_REMOVED', null, null, null, null, p_page_number, null,
                                          case when v_refs > 0 then jsonb_build_object('species_references_removed', v_refs) end);
  for v_renum in
    select p.page_number as n from public.collection_layout_page p
    where p.layout_id = v_layout and p.page_number > p_page_number
    order by p.page_number
  loop
    perform public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', null, null, null, null, v_renum.n, v_renum.n - 1);
  end loop;
  delete from public.collection_layout_slot_species_reference sr
  using public.collection_layout_slot s
  where s.id = sr.slot_id and s.page_id = v_page;
  delete from public.collection_layout_page p where p.id = v_page;
  update public.collection_layout_page p
     set page_number = p.page_number - 1
   where p.layout_id = v_layout and p.page_number > p_page_number;
  perform public.binder_activity_end();

  return query select p_page_number, v_refs;
end;
$fn$;

-- Reordenar páginas ---------------------------------------------------------------------------
create function public.editor_reorder_binder_pages(
  p_collection_id         uuid,
  p_page_numbers_ordered  integer[]
)
returns table (page_number integer, previous_page_number integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
  v_total  integer;
  r        record;
begin
  if p_page_numbers_ordered is null or cardinality(p_page_numbers_ordered) = 0
     or array_ndims(p_page_numbers_ordered) <> 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;

  -- Todas as páginas, em ordem determinística (igual à 5282), antes de validar.
  perform 1 from public.collection_layout_page p where p.layout_id = v_layout order by p.id for update;
  select count(*) into v_total from public.collection_layout_page p where p.layout_id = v_layout;
  if cardinality(p_page_numbers_ordered) <> v_total
     or (select count(distinct x) from unnest(p_page_numbers_ordered) x) <> v_total
     or exists (select 1 from unnest(p_page_numbers_ordered) x where x is null or x < 1 or x > v_total) then
    raise exception 'INVALID_PAGE_ORDER' using errcode = '22023',
      hint = 'informe cada página atual do fichário exatamente uma vez';
  end if;

  if exists (select 1 from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord) where u.old_n <> u.ord) then
    perform public.binder_activity_begin(v_layout, 'PAGES_REORDERED', 'FICHARIO', p_collection_id);
    for r in
      select u.old_n, u.ord::integer as new_n
      from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord)
      where u.old_n <> u.ord
      order by u.ord
    loop
      perform public.binder_activity_add_item('PAGE', 'PAGE_RENUMBERED', null, null, null, null, r.old_n, r.new_n);
    end loop;
    update public.collection_layout_page p
       set page_number = src.new_n
      from (select u.old_n, u.ord::integer as new_n
              from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord)) src
     where p.layout_id = v_layout and p.page_number = src.old_n;
    perform public.binder_activity_end();
  end if;

  return query
  select src.new_n, src.old_n
  from (select u.old_n, u.ord::integer as new_n
          from unnest(p_page_numbers_ordered) with ordinality u(old_n, ord)) src
  order by src.new_n;
end;
$fn$;

comment on function public.assert_collection_binder_editor_exclusive(uuid) is
  'V1-13 E1-C (5382, interna): autoriza o EDITOR como a 5371 e exige fichário exclusivo da coleção (proprietária, sem convidadas); senão OPERATION_RESERVED_TO_OWNER.';
comment on function public.editor_add_binder_page(uuid) is
  'V1-13 E1-C (5382): EDITOR adiciona página vazia no fim do fichário exclusivo da coleção (espelho da 5280).';
comment on function public.editor_remove_binder_page(uuid, integer, integer) is
  'V1-13 E1-C (5382): EDITOR remove página totalmente vazia do fichário exclusivo da coleção (espelho da 5286); referências de espécie de X exigem a contagem.';
comment on function public.editor_reorder_binder_pages(uuid, integer[]) is
  'V1-13 E1-C (5382): EDITOR reordena páginas inteiras do fichário exclusivo da coleção, por número (espelho da 5282).';

revoke all on function public.assert_collection_binder_editor_exclusive(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_add_binder_page(uuid) from public, anon;
revoke all on function public.editor_remove_binder_page(uuid, integer, integer) from public, anon;
revoke all on function public.editor_reorder_binder_pages(uuid, integer[]) from public, anon;
grant execute on function public.editor_add_binder_page(uuid) to authenticated;
grant execute on function public.editor_remove_binder_page(uuid, integer, integer) to authenticated;
grant execute on function public.editor_reorder_binder_pages(uuid, integer[]) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_add_binder_page(uuid)'),
                           to_regprocedure('public.editor_remove_binder_page(uuid, integer, integer)'),
                           to_regprocedure('public.editor_reorder_binder_pages(uuid, integer[])')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5382: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  f := to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)');
  if f is null
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5382: ajudante interno fora do estado esperado';
  end if;
end;
$post$;

commit;
