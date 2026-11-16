/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1b1-editor-core-binder/5374_create_editor_binder_core_writes.sql
   sha256 da base: 18e3d1b277093cc5f5e515b15e75d765dc87f349f34d9c425dc0222c705ae714
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 3 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5374 - Escritas fundamentais do EDITOR no fichário: colocar, mover/trocar
              e retirar (V1-13 · E1-B1)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B1 | EDITOR AUTHORIZATION AND CORE BINDER OPERATIONS-01`
              (2026-11-15). Execução só com prova dinâmica sob protocolo
              controlado (C-244) e autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-234, C-235 (+DR-1), C-236, C-237, C-241 (evento com ator EDITOR),
              C-243 (recusa neutra).
Depende de..: E1-A (5366), 5371 (autorização e classificação), 5372 (histórico).

Funções novas (RPC, EXECUTE só authenticated):
  editor_place_card_in_binder(p_collection_id uuid, p_page integer, p_row integer,
                              p_column integer, p_physical_card_id uuid)
      → (operation text: ADD | REPLACE | UNCHANGED)
  editor_move_binder_card(p_collection_id uuid,
                          p_from_page integer, p_from_row integer, p_from_column integer,
                          p_to_page integer, p_to_row integer, p_to_column integer)
      → (operation text: MOVE | SWAP)
  editor_remove_binder_card(p_collection_id uuid, p_page integer, p_row integer,
                            p_column integer)
      → (operation text: REMOVED)

Por que funções DEDICADAS e não um ramo nas funções do titular
(place_my_physical_card_in_slot 5272, move_slot_assignment 5273,
remove_slot_assignment 5274):
  - o titular fica BYTE A BYTE igual (md5 conferido no precheck e no
    postcheck): nenhuma regressão possível no caminho que está em produção;
  - o EDITOR precisa de outra entrada: a coleção autorizada explícita (a 5273
    não recebe coleção) e endereçamento por POSIÇÃO visível, não por id de
    bolso (as leituras compartilhadas não expõem ids);
  - a regra de autorização é outra (classificação C-237 por bolso), não uma
    troca de "auth.uid()" por "titular".
  Duplicação limitada às instruções de escrita (INSERT/UPDATE/DELETE de
  collection_layout_slot_assignment e os itens do histórico), com DEVER DE
  ESPELHO registrado no README e conferido por static_check_e1b1.py.

Regras comuns (OWNER × EDITOR × VIEWER):
  - Só EDITOR ACTIVE da coleção X (5371). VIEWER, não membro, ex-membro,
    convite pendente/recusado e o próprio titular → COLLECTION_NOT_FOUND
    (P0002), indistinguíveis. O titular continua usando as 5272–5274.
  - Bolso pela posição (página, linha, coluna) do fichário de X. Posição
    inexistente e bolso de terceiros → SLOT_NOT_EDITABLE (42501), a MESMA
    recusa, sem revelar o que ocupa o bolso nem se ele existe.
  - Ordem de travas: a da 5371 (proprietária → layout → convidada →
    participação) e depois bolso(s) por id, exemplar, posições — a mesma
    sequência do titular depois da 5122.
  - Bolso fixado (locked) de X → SLOT_LOCKED (55000), como no titular.
  - Nenhuma alteração patrimonial: alocação, local físico, condição,
    titularidade e acervo ficam intocados. Só collection_layout_slot_assignment
    muda.

Colocar (C-235 + DR-1):
  - bolso de destino OWN ou FREE;
  - exemplar do titular, ALOCADO A X e guardado no local do fichário, tudo
    relido sob trava (FOR UPDATE do exemplar, FOR SHARE da alocação). Qualquer
    falha (alheio, inexistente, sem alocação, alocado a outra coleção, em outro
    local) → PHYSICAL_CARD_NOT_ELIGIBLE (P0002), uma só recusa: o EDITOR nunca
    descobre onde o exemplar está;
  - já no mesmo bolso → UNCHANGED (sem evento); em outro bolso →
    CARD_ALREADY_PLACED (é um exemplar de X, o EDITOR já o vê);
  - REPLACE só tira exemplar de X (o bolso é OWN).
Mover/trocar (C-148/C-237):
  - origem OWN e com exemplar de X; destino OWN ou FREE; troca só com exemplar
    de X; reservas e referências ficam no bolso (são do bolso, não da carta).
Retirar (C-236):
  - bolso OWN com exemplar de X; apaga só a posição; o exemplar continua
    alocado, no mesmo local e no acervo.
Histórico: evento com a coleção X registrada (exigido pela 5372) e o EDITOR
  como ator; itens iguais aos do titular.
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5374 em ROLLBACK_E1B1.sql.
Como validar: harness 5889, seções 3–7.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.assert_collection_binder_editor(uuid)') is null
     or to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)') is null
     or to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)') is null then
    raise exception 'PRECHECK 5374: 5371 não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5374: 5372 não aplicada';
  end if;
  -- Funções do titular: canônicas (md5 conferido no LIVE em 2026-10-27, LIVE_S2_90).
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) is distinct from '2672da179d73797ec5329c649b594202'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) is distinct from 'fe149c755b5f3b9181172e600c2238a3'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.remove_slot_assignment(uuid[])')) is distinct from 'e4b6c8cd8e8c61554ddc92304d602a73' then
    raise exception 'PRECHECK 5374: ESTADO DIVERGENTE — funções do titular (5272–5274) diferem das canônicas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('editor_place_card_in_binder', 'editor_move_binder_card', 'editor_remove_binder_card')) then
    raise exception 'PRECHECK 5374: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Colocar -------------------------------------------------------------------------------------
create function public.editor_place_card_in_binder(
  p_collection_id    uuid,
  p_page             integer,
  p_row              integer,
  p_column           integer,
  p_physical_card_id uuid
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_locked    boolean;
  v_card_cont uuid;
  v_here      uuid;
  v_here_slot uuid;
  v_old_asg   uuid;
  v_old_card  uuid;
  v_op        text;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null or p_physical_card_id is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Autorização EDITOR + travas proprietária → layout → convidada → participação.
  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  -- 2. Bolso pela posição, travado; classificação sob a trava.
  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select s.locked into v_locked from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope not in ('OWN', 'FREE') then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_locked then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  -- 3. Exemplar elegível (C-235 + DR-1), relido sob trava: do titular, alocado a X,
  --    guardado no local do fichário. Uma só recusa para qualquer falha.
  select pc.storage_container_id into v_card_cont
  from public.physical_card pc
  join public.inventory i            on i.id = pc.inventory_id
  join public.collection_allocation ca on ca.physical_card_id = pc.id
  where pc.id = p_physical_card_id
    and i.owner_user_id = v_owner
    and ca.collection_id = p_collection_id
  for update of pc for share of ca;
  if not found or v_container is null or v_card_cont is distinct from v_container then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  -- 4. Já posicionado? (igual ao titular)
  select a.id, a.slot_id into v_here, v_here_slot
  from public.collection_layout_slot_assignment a
  where a.physical_card_id = p_physical_card_id
  for update;
  if v_here is not null then
    if v_here_slot = v_slot then
      return query select 'UNCHANGED'::text;
      return;
    end if;
    raise exception 'CARD_ALREADY_PLACED' using errcode = '23505',
      hint = 'o exemplar já está em outro bolso — mova-o em vez de posicioná-lo de novo';
  end if;

  -- 5. Escrita (espelho da 5272): evento com a coleção X; REPLACE só de exemplar de X.
  perform public.binder_activity_begin(v_layout, 'CARD_PLACED', 'FICHARIO', p_collection_id);
  select a.id, a.physical_card_id into v_old_asg, v_old_card
  from public.collection_layout_slot_assignment a
  where a.slot_id = v_slot
  for update;
  if v_old_asg is not null then
    if not exists (select 1 from public.collection_allocation ca
                   where ca.physical_card_id = v_old_card and ca.collection_id = p_collection_id) then
      raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
    end if;
    perform public.binder_activity_add_card_item('REMOVED', v_old_card, v_slot, null);
    delete from public.collection_layout_slot_assignment where id = v_old_asg;
    v_op := 'REPLACE';
  else
    v_op := 'ADD';
  end if;

  begin
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id)
    values (v_slot, p_physical_card_id);
  exception
    when unique_violation then
      raise exception 'CARD_ALREADY_PLACED' using errcode = '23505';
  end;

  perform public.binder_activity_add_card_item('PLACED', p_physical_card_id, null, v_slot);
  return query select v_op;
  perform public.binder_activity_end();
end;
$fn$;

-- Mover / trocar --------------------------------------------------------------------------------
create function public.editor_move_binder_card(
  p_collection_id uuid,
  p_from_page     integer,
  p_from_row      integer,
  p_from_column   integer,
  p_to_page       integer,
  p_to_row        integer,
  p_to_column     integer
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout     uuid;
  v_anchor     uuid;
  v_owner      uuid;
  v_container  uuid;
  v_from       uuid;
  v_to         uuid;
  v_scope_from text;
  v_scope_to   text;
  v_locked     integer;
  v_from_asg   uuid;
  v_from_card  uuid;
  v_to_asg     uuid;
  v_to_card    uuid;
  v_op         text;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_from_page is null or p_from_row is null or p_from_column is null
     or p_to_page is null or p_to_row is null or p_to_column is null
     or least(p_from_page, p_from_row, p_from_column, p_to_page, p_to_row, p_to_column) < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if (p_from_page, p_from_row, p_from_column) = (p_to_page, p_to_row, p_to_column) then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023', hint = 'origem e destino são o mesmo bolso';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_from := public.binder_slot_at(v_layout, p_from_page, p_from_row, p_from_column);
  v_to   := public.binder_slot_at(v_layout, p_to_page, p_to_row, p_to_column);
  if v_from is null or v_to is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Bolsos em ordem determinística (igual à 5273), depois classificação sob trava.
  perform 1 from public.collection_layout_slot s
  where s.id in (v_from, v_to) order by s.id for update;
  v_scope_from := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_from);
  v_scope_to   := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_to);
  if v_scope_from <> 'OWN' or v_scope_to not in ('OWN', 'FREE') then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select count(*) into v_locked from public.collection_layout_slot s where s.id in (v_from, v_to) and s.locked;
  if v_locked > 0 then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  -- Posições envolvidas em ordem determinística (igual à 5273).
  perform 1 from public.collection_layout_slot_assignment a
  where a.slot_id in (v_from, v_to) order by a.id for update;
  select a.id, a.physical_card_id into v_from_asg, v_from_card
  from public.collection_layout_slot_assignment a where a.slot_id = v_from;
  if v_from_asg is null
     or not exists (select 1 from public.collection_allocation ca
                    where ca.physical_card_id = v_from_card and ca.collection_id = p_collection_id) then
    raise exception 'SLOT_EMPTY' using errcode = 'P0002', hint = 'não há carta desta coleção no bolso de origem';
  end if;
  select a.id, a.physical_card_id into v_to_asg, v_to_card
  from public.collection_layout_slot_assignment a where a.slot_id = v_to;
  if v_to_asg is not null
     and not exists (select 1 from public.collection_allocation ca
                     where ca.physical_card_id = v_to_card and ca.collection_id = p_collection_id) then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Escrita (espelho da 5273).
  if v_to_asg is not null then
    v_op := 'SWAP';
    update public.collection_layout_slot_assignment set slot_id = v_to   where id = v_from_asg;
    update public.collection_layout_slot_assignment set slot_id = v_from where id = v_to_asg;
  else
    v_op := 'MOVE';
    update public.collection_layout_slot_assignment set slot_id = v_to where id = v_from_asg;
  end if;

  perform public.binder_activity_begin(v_layout, case v_op when 'SWAP' then 'CARDS_SWAPPED' else 'CARD_MOVED' end,
                                       'FICHARIO', p_collection_id);
  perform public.binder_activity_add_card_item(case v_op when 'SWAP' then 'SWAPPED' else 'MOVED' end,
                                               v_from_card, v_from, v_to);
  if v_op = 'SWAP' then
    perform public.binder_activity_add_card_item('SWAPPED', v_to_card, v_to, v_from);
  end if;
  return query select v_op;
  perform public.binder_activity_end();
end;
$fn$;

-- Retirar ----------------------------------------------------------------------------------------
create function public.editor_remove_binder_card(
  p_collection_id uuid,
  p_page          integer,
  p_row           integer,
  p_column        integer
)
returns table (operation text)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $fn$
#variable_conflict use_column
declare
  v_layout    uuid;
  v_anchor    uuid;
  v_owner     uuid;
  v_container uuid;
  v_slot      uuid;
  v_scope     text;
  v_locked    boolean;
  v_asg       uuid;
  v_card      uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  select s.locked into v_locked from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope <> 'OWN' then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_locked then
    raise exception 'SLOT_LOCKED' using errcode = '55000';
  end if;

  select a.id, a.physical_card_id into v_asg, v_card
  from public.collection_layout_slot_assignment a where a.slot_id = v_slot for update;
  if v_asg is null
     or not exists (select 1 from public.collection_allocation ca
                    where ca.physical_card_id = v_card and ca.collection_id = p_collection_id) then
    raise exception 'SLOT_EMPTY' using errcode = 'P0002', hint = 'não há carta desta coleção neste bolso';
  end if;

  -- Escrita (espelho da 5274, um bolso): item antes do DELETE; só a posição sai.
  perform public.binder_activity_begin(v_layout, 'CARDS_REMOVED', 'FICHARIO', p_collection_id);
  perform public.binder_activity_add_card_item('REMOVED', v_card, v_slot, null);
  delete from public.collection_layout_slot_assignment where id = v_asg;
  return query select 'REMOVED'::text;
  perform public.binder_activity_end();
end;
$fn$;

comment on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) is
  'V1-13 E1-B1 (5374): EDITOR coloca no bolso (posição visível) um exemplar alocado à coleção e guardado no fichário (C-235/DR-1). Bolso de terceiros → SLOT_NOT_EDITABLE.';
comment on function public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer) is
  'V1-13 E1-B1 (5374): EDITOR move ou troca cartas da coleção entre bolsos permitidos (C-237).';
comment on function public.editor_remove_binder_card(uuid, integer, integer, integer) is
  'V1-13 E1-B1 (5374): EDITOR retira do bolso uma carta da coleção; alocação, local e acervo intactos (C-236).';

revoke all on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) from public, anon;
revoke all on function public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer) from public, anon;
revoke all on function public.editor_remove_binder_card(uuid, integer, integer, integer) from public, anon;
grant execute on function public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid) to authenticated;
grant execute on function public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer) to authenticated;
grant execute on function public.editor_remove_binder_card(uuid, integer, integer, integer) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[
      to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'),
      to_regprocedure('public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer)'),
      to_regprocedure('public.editor_remove_binder_card(uuid, integer, integer, integer)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or not ((select p.proconfig from pg_catalog.pg_proc p where p.oid = f) @> array['search_path=""'])
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5374: escrita do EDITOR fora do estado esperado (%)', f;
    end if;
  end loop;
  -- ACL das novas igual à do titular correspondente (paridade, inclusive service_role).
  if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
       where p.oid = to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)'))
     is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
       where p.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) then
    raise exception 'POSTCHECK 5374: ACL difere da 5272';
  end if;
  -- Titular intocado.
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) is distinct from '2672da179d73797ec5329c649b594202'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) is distinct from 'fe149c755b5f3b9181172e600c2238a3'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.remove_slot_assignment(uuid[])')) is distinct from 'e4b6c8cd8e8c61554ddc92304d602a73' then
    raise exception 'POSTCHECK 5374: funções do titular mudaram';
  end if;
end;
$post$;

commit;
