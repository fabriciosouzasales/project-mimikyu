/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5238 - Guard Binder Layout Regions (mesclagem só decorativa)
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23 (P2-BINDER-LAYOUT-CUSTOMIZATION-IMPLEMENTATION-PROPOSAL-01)
Descrição...:
Fecha as brechas de integridade da Layout Region (5119/5121/5134/5135)
antes de qualquer uso pela interface. Decisões D5/D6 aprovadas.

1. As RPCs genéricas merge_layout_region()/unmerge_layout_region()
   deixam de ser executáveis por `authenticated`. Elas aceitam mesclar
   bolsos COM carta e nunca foram usadas pelo app; a mesclagem passa a
   existir só pelas RPCs do colecionador (5240), com imagem.
2. Bolso dentro de mesclagem recusa carta e reserva
   (INSERT/UPDATE OF slot_id em slot_assignment e slot_expected_content)
   → SLOT_IN_REGION. Cobre arrastar, trocar, posicionar, reservar e o
   deslocamento de "Inserir espaço" (5243).
3. Mesclagem não pode cobrir bolso com carta ou reserva
   (INSERT/UPDATE em collection_layout_region) → REGION_SLOTS_NOT_FREE.
   Simétrico ao gatilho de imagem da 5232.
4. Bolso dentro de mesclagem não pode ser fixado (locked false→true)
   → SLOT_IN_REGION. Sem isto, fixar a metade de uma mesclagem impediria
   para sempre separá-la (o gatilho 5121 recusa DELETE com bolso fixado).
   Destravar continua sempre permitido.

Nada aqui altera cartas, reservas, alocações, imagens, progresso ou valor.
Gatilhos de checagem somente; nenhuma escrita em dados existentes.

Dependências: 5113, 5115, 5119, 5121, 5134, 5135 (canônicas).
Pré-condição de dados (fail-loud): nenhuma Region existente cobre bolso
com carta ou reserva, e nenhum bolso fixado está dentro de Region.
Esperado no LIVE: 0 Regions (nenhuma interface as cria hoje).
================================================================
*/

begin;

do $pre$
declare
  v_bad integer;
begin
  if to_regclass('public.collection_layout_region') is null
     or to_regprocedure('public.merge_layout_region(uuid, integer, integer, integer, integer)') is null
     or to_regprocedure('public.unmerge_layout_region(uuid)') is null then
    raise exception 'PRECHECK 5238: fundação de Layout Region (5119/5134/5135) ausente';
  end if;
  if to_regprocedure('public.enforce_slot_outside_layout_region()') is not null then
    raise exception 'PRECHECK 5238: já aplicada';
  end if;
  if to_regclass('public.ix_collection_layout_region_page') is not null then
    raise exception 'PRECHECK 5238: índice ix_collection_layout_region_page já existe';
  end if;

  select count(*) into v_bad
  from public.collection_layout_region r
  join public.collection_layout_slot s
    on s.page_id = r.page_id
   and s.row_index    between r.top_row     and r.top_row     + r.height - 1
   and s.column_index between r.left_column and r.left_column + r.width  - 1
  where s.locked
     or exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
     or exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id);
  if v_bad > 0 then
    raise exception 'PRECHECK 5238: % bolso(s) em mesclagem com carta, reserva ou fixação — reconciliar antes', v_bad;
  end if;
end;
$pre$;

-- 1. RPCs genéricas fora do alcance do cliente ---------------------------------------
revoke execute on function public.merge_layout_region(uuid, integer, integer, integer, integer)
  from public, anon, authenticated;
revoke execute on function public.unmerge_layout_region(uuid)
  from public, anon, authenticated;

-- 2. Bolso em mesclagem recusa carta e reserva -----------------------------------------
create function public.enforce_slot_outside_layout_region()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.collection_layout_slot s
    join public.collection_layout_region r
      on r.page_id = s.page_id
     and s.row_index    between r.top_row     and r.top_row     + r.height - 1
     and s.column_index between r.left_column and r.left_column + r.width  - 1
    where s.id = new.slot_id
  ) then
    raise exception 'SLOT_IN_REGION' using errcode = '55000',
      hint = 'este bolso faz parte de uma imagem em 2 bolsos';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_slot_outside_layout_region()
  from public, anon, authenticated;

create trigger trg_slot_assignment_outside_region
  before insert or update of slot_id on public.collection_layout_slot_assignment
  for each row execute function public.enforce_slot_outside_layout_region();

create trigger trg_slot_expected_content_outside_region
  before insert or update of slot_id on public.collection_layout_slot_expected_content
  for each row execute function public.enforce_slot_outside_layout_region();

-- 3. Mesclagem só sobre bolsos sem carta e sem reserva ---------------------------------
create function public.enforce_region_slots_without_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.collection_layout_slot s
    where s.page_id = new.page_id
      and s.row_index    between new.top_row     and new.top_row     + new.height - 1
      and s.column_index between new.left_column and new.left_column + new.width  - 1
      and (exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)
           or exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id))
  ) then
    raise exception 'REGION_SLOTS_NOT_FREE' using errcode = '55000',
      hint = 'os bolsos da mesclagem precisam estar sem carta e sem reserva';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_region_slots_without_content()
  from public, anon, authenticated;

create trigger trg_region_slots_without_content
  before insert or update on public.collection_layout_region
  for each row execute function public.enforce_region_slots_without_content();

-- 4. Bolso em mesclagem não é fixado -------------------------------------------------------
create function public.enforce_slot_lock_outside_region()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.locked and not old.locked
     and exists (
       select 1 from public.collection_layout_region r
       where r.page_id = new.page_id
         and new.row_index    between r.top_row     and r.top_row     + r.height - 1
         and new.column_index between r.left_column and r.left_column + r.width  - 1) then
    raise exception 'SLOT_IN_REGION' using errcode = '55000',
      hint = 'bolso de uma imagem em 2 bolsos não é fixado';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_slot_lock_outside_region()
  from public, anon, authenticated;

create trigger trg_slot_lock_outside_region
  before update of locked on public.collection_layout_slot
  for each row execute function public.enforce_slot_lock_outside_region();

-- 5. Índice do caminho crítico (LIVE-READINESS-01) ---------------------------------------
-- Os gatilhos acima, a 5121 (sobreposição), a cadeia do "Abrir espaço" (5243) e a leitura
-- (5241) procuram mesclagens por página. No LIVE a tabela só tem a PK: sem este índice,
-- cada carta posicionada varreria as mesclagens de todos os usuários. Tabela vazia no
-- LIVE (PRE-3) → criação instantânea, sem CONCURRENTLY.
create index ix_collection_layout_region_page
  on public.collection_layout_region (page_id);

-- Pós-checagem na mesma transação -------------------------------------------------------
do $post$
begin
  if to_regclass('public.ix_collection_layout_region_page') is null then
    raise exception 'POSTCHECK 5238: índice por página ausente';
  end if;
  if has_function_privilege('authenticated', 'public.merge_layout_region(uuid, integer, integer, integer, integer)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.unmerge_layout_region(uuid)', 'EXECUTE') then
    raise exception 'POSTCHECK 5238: merge/unmerge ainda executáveis por authenticated';
  end if;
  if (select count(*) from pg_trigger
      where tgname in ('trg_slot_assignment_outside_region', 'trg_slot_expected_content_outside_region',
                       'trg_region_slots_without_content', 'trg_slot_lock_outside_region')
        and not tgisinternal) <> 4 then
    raise exception 'POSTCHECK 5238: gatilhos ausentes';
  end if;
end;
$post$;

commit;

/*
Resultado esperado: 4 gatilhos novos; índice ix_collection_layout_region_page; merge/unmerge sem EXECUTE para
PUBLIC/anon/authenticated (continuam existindo, chamáveis só pelo dono).
Como validar (LIVE_90, POST-1): has_function_privilege(...) = false nas 2
RPCs; os 4 gatilhos presentes e habilitados (tgenabled = 'O').
*/
