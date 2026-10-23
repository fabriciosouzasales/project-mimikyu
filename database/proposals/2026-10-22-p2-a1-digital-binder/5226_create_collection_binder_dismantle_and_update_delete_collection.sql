/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5226 - Fichário Digital (P2-A1): desmontagem confirmada e
              atômica + evolução de delete_collection (5039)
              collection_binder_dismantle_snapshot(uuid)          — helper INTERNO
              preview_my_collection_binder_dismantle(uuid)
              dismantle_my_collection_binder(uuid, text)
              delete_collection(uuid)                             — CREATE OR REPLACE (5039 v1.4)
Versão......: 1.1 (2026-10-23, AUDIT-CORRECTION-01: só a ordem do pacote,
              agora com a 5227; corpo inalterado)
Status......: PROPOSTA — NÃO EXECUTADA. Aguarda auditoria independente e
              autorização expressa de Fabrício. Não aplicar no LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22 (P2-A1-PROPOSAL-01)

Dependências: 5105–5137 (Layout), 5039 v1.3 (5048), 5225 (coluna
expected_variant_type_id entra no token). Ordem do pacote:
5225 → 5223 → 5224 → 5226 → 5227 → 5228.

──────────────────────────────────────────────────────────────────────
POR QUE EXISTE (R4)
  Hoje uma coleção com fichário NÃO pode ser excluída por caminho algum
  do produto: collection_layout.collection_id é ON DELETE RESTRICT (5105)
  e delete_collection_layout (5124) exige zero páginas e coleção ACTIVE;
  remove_layout_page (5126) também exige ACTIVE e a página vazia. Uma
  coleção ARQUIVADA com fichário fica presa. A desmontagem é a saída
  explícita, confirmada e atômica — sem cascata automática.

O QUE A DESMONTAGEM FAZ (uma transação)
  1. trava a coleção (FOR UPDATE, dono no WHERE — QUALQUER lifecycle:
     ACTIVE ou ARCHIVED) e o layout (FOR UPDATE) — ordem coleção → layout,
     a mesma de assert_collection_layout_mutable (5122);
  2. recalcula o retrato do fichário e compara com o token da prévia
     (DISMANTLE_PLAN_CHANGED se qualquer coisa mudou);
  3. destrava os bolsos travados (o usuário confirmou ver N travados);
  4. remove posições (slot_assignment) → reservas (expected_content) →
     mesclagens (region) → páginas (os bolsos caem por ON DELETE CASCADE
     de 5110) → layout;
  5. confere as contagens contra o retrato; divergência desfaz tudo.
  NUNCA altera physical_card, collection_allocation, storage_container,
  vínculos da Pokédex, objetivo do Master Set ou a coleção.

  Bolsos travados: a trava (C-45) protege contra edição ACIDENTAL; a
  desmontagem é uma remoção INTENCIONAL e confirmada do fichário inteiro
  — a prévia mostra quantos bolsos travados e quantas mesclagens serão
  descartados, e eles entram no token. Sem isso, um único bolso travado
  num fichário arquivado tornaria a exclusão impossível.

D4 (confirmação ao remover carta posicionada) continua SEPARADA: é a
confirmação da UI para remover UMA carta de um bolso no uso diário. A
confirmação da desmontagem é outra, própria, do fichário inteiro.

IDEMPOTÊNCIA
  Repetir a chamada depois de concluída: não há layout → outcome
  ALREADY_ABSENT, nada muda. Se um NOVO fichário foi criado entretanto,
  o token antigo não confere → DISMANTLE_PLAN_CHANGED (nunca desmonta
  um fichário que o usuário não viu).

TOKEN ('d1:' + SHA-256) — serialização canônica do fichário inteiro:
  layout (id, colunas, linhas) | páginas (id, número) | bolsos (id,
  página, linha, coluna, travado) | posições (bolso, alocação) | reservas
  (bolso, carta, variante, acabamento) | mesclagens (id, página, caixa).
  Qualquer edição do fichário entre prévia e confirmação muda o token.

CONCORRÊNCIA
  Toda edição de layout (5122) e toda criação (5224) tomam a trava da
  coleção primeiro → serializadas com a desmontagem. Desalocação
  concorrente (5047) também trava a coleção. Exclusão da coleção (5039)
  trava a coleção → espera; depois do commit da desmontagem, prossegue.
  lock_timeout 5s.

ERROS
  28000 not_authenticated · 22023 INVALID_ARGUMENT / INVALID_DISMANTLE_TOKEN ·
  P0002 COLLECTION_NOT_FOUND (inexistente e alheia: mesma resposta) ·
  P0001 DISMANTLE_PLAN_CHANGED / BINDER_DISMANTLE_INCONSISTENT · 55P03.

5039 v1.4 (delete_collection)
  Mesma assinatura, mesmo retorno, mesma ordem: auth → trava/dono →
  alocações. Acrescenta, DEPOIS da checagem de alocações (comportamento
  atual preservado para coleções sem fichário):
    se existe collection_layout → 'collection has a digital binder —
    dismantle it before deleting' (P0001, HINT BINDER_EXISTS).
  Antes: violação crua de FK (23503). Nenhuma cascata é adicionada.
================================================================
*/

begin;

do $pre$
declare
  v_src text;
begin
  if to_regprocedure('public.collection_binder_dismantle_snapshot(uuid)') is not null
     or to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)') is not null
     or to_regprocedure('public.dismantle_my_collection_binder(uuid, text)') is not null then
    raise exception 'PRECHECK 5226: funções já existem';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public'
                   and table_name = 'collection_layout_slot_expected_content'
                   and column_name = 'expected_variant_type_id') then
    raise exception 'PRECHECK 5226: aplique a 5225 antes';
  end if;
  select p.prosrc into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'delete_collection'
    and pg_get_function_identity_arguments(p.oid) = 'p_collection_id uuid';
  if v_src is null then
    raise exception 'PRECHECK 5226: delete_collection(uuid) ausente';
  end if;
  -- Fail-loud: o corpo vivo precisa ser o 5039 v1.3 (com o pré-check da 5048)
  -- e ainda sem a regra do fichário. Qualquer outra versão: parar e auditar.
  if position('deallocate them before deleting' in v_src) = 0
     or position('digital binder' in v_src) > 0 then
    raise exception 'PRECHECK 5226: delete_collection no banco difere da 5039 v1.3 canônica';
  end if;
end;
$pre$;

-- 1. Helper INTERNO: retrato do fichário + token -----------------------------------
create function public.collection_binder_dismantle_snapshot(p_collection_id uuid)
returns table (
  layout_id          uuid,
  grid_columns       integer,
  grid_rows          integer,
  pages_count        integer,
  slots_count        integer,
  locked_count       integer,
  assignments_count  integer,
  reservations_count integer,
  regions_count      integer,
  dismantle_token    text
)
language sql
stable
security invoker
set search_path = ''
as $$
  with l as (
    select x.id, x.grid_columns, x.grid_rows
    from public.collection_layout x
    where x.collection_id = p_collection_id
  ),
  pg as (
    select p.id, p.page_number from public.collection_layout_page p join l on l.id = p.layout_id
  ),
  sl as (
    select s.id, s.page_id, s.row_index, s.column_index, s.locked
    from public.collection_layout_slot s join pg on pg.id = s.page_id
  ),
  asg as (
    select a.slot_id, a.collection_allocation_id
    from public.collection_layout_slot_assignment a join sl on sl.id = a.slot_id
  ),
  exc as (
    select e.slot_id, e.card_id, e.card_variant_id, e.expected_variant_type_id
    from public.collection_layout_slot_expected_content e join sl on sl.id = e.slot_id
  ),
  rg as (
    select r.id, r.page_id, r.top_row, r.left_column, r.height, r.width
    from public.collection_layout_region r join pg on pg.id = r.page_id
  ),
  ser as (
    select
      (select 'L|' || l.id || '|' || l.grid_columns || 'x' || l.grid_rows from l)
      || E'\nP|' || coalesce((select string_agg(pg.id || ':' || pg.page_number, ',' order by pg.page_number, pg.id) from pg), '')
      || E'\nS|' || coalesce((select string_agg(sl.id || ':' || sl.page_id || ':' || sl.row_index || ':' || sl.column_index || ':' || sl.locked::text, ',' order by sl.id) from sl), '')
      || E'\nA|' || coalesce((select string_agg(asg.slot_id || ':' || asg.collection_allocation_id, ',' order by asg.slot_id) from asg), '')
      || E'\nE|' || coalesce((select string_agg(exc.slot_id || ':' || exc.card_id || ':' || coalesce(exc.card_variant_id::text, '-') || ':' || coalesce(exc.expected_variant_type_id::text, '-'), ',' order by exc.slot_id) from exc), '')
      || E'\nR|' || coalesce((select string_agg(rg.id || ':' || rg.page_id || ':' || rg.top_row || ':' || rg.left_column || ':' || rg.height || ':' || rg.width, ',' order by rg.id) from rg), '')
      as s
  )
  select l.id, l.grid_columns, l.grid_rows,
         (select count(*) from pg)::integer,
         (select count(*) from sl)::integer,
         (select count(*) from sl where sl.locked)::integer,
         (select count(*) from asg)::integer,
         (select count(*) from exc)::integer,
         (select count(*) from rg)::integer,
         'd1:' || encode(sha256(convert_to(ser.s, 'UTF8')), 'hex')
  from l cross join ser;
$$;

comment on function public.collection_binder_dismantle_snapshot(uuid) is
  'Fichário Digital (Query 5226): retrato completo do fichário de uma coleção (contagens + token SHA-256 de páginas, bolsos/travas, posições, reservas e mesclagens). Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role; chamado só por preview_my_collection_binder_dismantle e dismantle_my_collection_binder (SECURITY DEFINER), que já validaram o dono. Zero linhas = sem fichário.';

revoke all on function public.collection_binder_dismantle_snapshot(uuid) from public;
revoke all on function public.collection_binder_dismantle_snapshot(uuid) from anon;
revoke all on function public.collection_binder_dismantle_snapshot(uuid) from authenticated;
revoke all on function public.collection_binder_dismantle_snapshot(uuid) from service_role;

-- 2. Prévia da desmontagem ------------------------------------------------------------
create function public.preview_my_collection_binder_dismantle(p_collection_id uuid)
returns table (
  collection_id      uuid,
  lifecycle_status   text,
  has_binder         boolean,
  layout_id          uuid,
  grid_columns       integer,
  grid_rows          integer,
  pages_count        integer,
  slots_count        integer,
  locked_count       integer,
  assignments_count  integer,
  reservations_count integer,
  regions_count      integer,
  dismantle_token    text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := auth.uid();
  v_status text;
  r        record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into r from public.collection_binder_dismantle_snapshot(p_collection_id);

  collection_id    := p_collection_id;
  lifecycle_status := v_status;
  has_binder       := r.layout_id is not null;
  if has_binder then
    layout_id          := r.layout_id;
    grid_columns       := r.grid_columns;
    grid_rows          := r.grid_rows;
    pages_count        := r.pages_count;
    slots_count        := r.slots_count;
    locked_count       := r.locked_count;
    assignments_count  := r.assignments_count;
    reservations_count := r.reservations_count;
    regions_count      := r.regions_count;
    dismantle_token    := r.dismantle_token;
  end if;
  return next;
end;
$$;

comment on function public.preview_my_collection_binder_dismantle(uuid) is
  'Fichário Digital (Query 5226): prévia da desmontagem do fichário da coleção do usuário da sessão (ativa ou arquivada) — páginas, bolsos, travados, cartas posicionadas, reservas, mesclagens e dismantle_token. Não grava nada. Exige auth.uid(); não enumera.';

revoke all on function public.preview_my_collection_binder_dismantle(uuid) from public;
revoke all on function public.preview_my_collection_binder_dismantle(uuid) from anon;
grant execute on function public.preview_my_collection_binder_dismantle(uuid) to authenticated;

-- 3. Desmontagem atômica ------------------------------------------------------------
create function public.dismantle_my_collection_binder(
  p_collection_id   uuid,
  p_dismantle_token text
)
returns table (
  outcome              text,     -- DISMANTLED | ALREADY_ABSENT
  pages_removed        integer,
  slots_removed        integer,
  assignments_removed  integer,
  reservations_removed integer,
  regions_removed      integer,
  locks_released       integer
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
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

  -- 1. Coleção (qualquer lifecycle) → layout -------------------------------------------
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
    outcome := 'ALREADY_ABSENT';
    pages_removed := 0; slots_removed := 0; assignments_removed := 0;
    reservations_removed := 0; regions_removed := 0; locks_released := 0;
    return next;
    return;
  end if;

  -- 2. O usuário autoriza exatamente o que viu --------------------------------------
  select * into r from public.collection_binder_dismantle_snapshot(p_collection_id);
  if r.dismantle_token is distinct from p_dismantle_token then
    raise exception 'DISMANTLE_PLAN_CHANGED';
  end if;

  -- 3. Travas confirmadas na prévia ---------------------------------------------------
  update public.collection_layout_slot s
     set locked = false
   where s.locked
     and s.page_id in (select p.id from public.collection_layout_page p where p.layout_id = v_layout);
  get diagnostics v_unlock = row_count;

  -- 4. Remoção na ordem das FKs (todas RESTRICT, exceto slot → page CASCADE) ---------
  delete from public.collection_layout_slot_assignment a
   using public.collection_layout_slot s, public.collection_layout_page p
   where a.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_asg = row_count;

  delete from public.collection_layout_slot_expected_content e
   using public.collection_layout_slot s, public.collection_layout_page p
   where e.slot_id = s.id and s.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_exc = row_count;

  delete from public.collection_layout_region rg
   using public.collection_layout_page p
   where rg.page_id = p.id and p.layout_id = v_layout;
  get diagnostics v_rg = row_count;

  delete from public.collection_layout_page p where p.layout_id = v_layout;
  get diagnostics v_pg = row_count;

  delete from public.collection_layout l where l.id = v_layout;

  -- 5. Conferência --------------------------------------------------------------------
  select count(*)::integer into v_left
  from public.collection_layout l where l.collection_id = p_collection_id;

  if v_left <> 0
     or v_unlock <> r.locked_count
     or v_asg <> r.assignments_count
     or v_exc <> r.reservations_count
     or v_rg <> r.regions_count
     or v_pg <> r.pages_count then
    raise exception 'BINDER_DISMANTLE_INCONSISTENT';
  end if;

  outcome              := 'DISMANTLED';
  pages_removed        := v_pg;
  slots_removed        := r.slots_count;   -- removidos pelo CASCADE page → slot
  assignments_removed  := v_asg;
  reservations_removed := v_exc;
  regions_removed      := v_rg;
  locks_released       := v_unlock;
  return next;
end;
$$;

comment on function public.dismantle_my_collection_binder(uuid, text) is
  'Fichário Digital (Query 5226): desmonta, de forma confirmada (dismantle_token da prévia) e atômica, o fichário inteiro da coleção do usuário da sessão — inclusive de coleção ARQUIVADA. Libera travas confirmadas, remove posições, reservas, mesclagens, páginas, bolsos e o layout. Nunca altera exemplares, alocações, locais físicos, vínculos ou objetivo. Repetição após sucesso → ALREADY_ABSENT.';

revoke all on function public.dismantle_my_collection_binder(uuid, text) from public;
revoke all on function public.dismantle_my_collection_binder(uuid, text) from anon;
grant execute on function public.dismantle_my_collection_binder(uuid, text) to authenticated;

-- 4. delete_collection (5039 v1.4): recusa com erro de domínio se houver fichário ---
create or replace function public.delete_collection(p_collection_id uuid)
returns table (id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'authentication required';
    end if;

    perform 1
    from public.collection col
    where col.id = p_collection_id
      and col.owner_user_id = auth.uid()
    for update;

    if not found then
        raise exception 'collection not found or not owned by caller';
    end if;

    if exists (
        select 1
        from public.collection_allocation ca
        where ca.collection_id = p_collection_id
    ) then
        raise exception 'collection has allocated physical cards — deallocate them before deleting';
    end if;

    -- 5226: sem cascata. O fichário é desmontado explicitamente
    -- (preview_my_collection_binder_dismantle → dismantle_my_collection_binder).
    if exists (
        select 1
        from public.collection_layout l
        where l.collection_id = p_collection_id
    ) then
        raise exception 'collection has a digital binder — dismantle it before deleting'
            using hint = 'BINDER_EXISTS';
    end if;

    return query
    delete from public.collection
    where collection.id = p_collection_id and collection.owner_user_id = auth.uid()
    returning collection.id;

    if not found then
        raise exception 'collection not found or not owned by caller';
    end if;
end;
$$;

revoke execute on function public.delete_collection(uuid) from public, anon;
grant execute on function public.delete_collection(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

/*
Reversão (só se a 5226 tiver sido aplicada e precisar ser desfeita;
pré-requisito: nenhum caller do app usando as funções novas):
  begin;
  drop function public.dismantle_my_collection_binder(uuid, text);
  drop function public.preview_my_collection_binder_dismantle(uuid);
  drop function public.collection_binder_dismantle_snapshot(uuid);
  -- restaurar delete_collection: reaplicar o corpo canônico de
  -- database/schema/5039_create_delete_collection_function.sql (v1.3).
  commit;

Como validar (estrutura):
  select p.proname, p.prosecdef, p.proconfig,
         has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_exec,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('collection_binder_dismantle_snapshot',
                      'preview_my_collection_binder_dismantle',
                      'dismantle_my_collection_binder',
                      'delete_collection');
  Esperado: snapshot prosecdef=false, auth_exec=false; as três demais
  prosecdef=true, search_path='', anon_exec=false, auth_exec=true.
  Prova comportamental: harness 5850, Seções 12 e 13.
*/
