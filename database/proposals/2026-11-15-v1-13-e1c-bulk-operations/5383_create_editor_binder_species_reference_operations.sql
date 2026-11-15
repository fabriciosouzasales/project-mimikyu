/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5383 - Referências de espécie pelo EDITOR: prévia, aplicar, remover,
              mostrar e ocultar, só no fichário exclusivo da Pokédex autorizada
              (V1-13 · E1-C)
Versão......: 1.1 (2026-11-15, `BULK OPERATIONS SAFETY REVIEW-02`: referências de outra coleção
              no fichário → recusa; remover só apaga as de X). 1.0 (2026-11-15)
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-C | COLLECTION-SCOPED BULK OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-199 (referências de espécie), C-237 (aplicar, remover, mostrar e
              ocultar referências são "operações de página e em massa": num
              fichário de várias coleções, só o titular; num fichário de uma
              coleção, o EDITOR, sem deslocar, retirar nem descartar conteúdo de
              terceiros), C-242, C-243.
Depende de..: 5258 (plano canônico binder_species_reference_plan), E1-C 5382
              (assert_collection_binder_editor_exclusive).

Alcance real de cada operação (5258):
  aplicar   — grava UMA camada de rótulos em todos os bolsos do fichário (pares
              bolso n ↔ posição n), registrada para a Pokédex PROPRIETÁRIA;
  remover   — apaga a camada inteira;
  mostrar/ocultar — preferência única do fichário (vale para todas as coleções
              que o usam).
  Nenhuma toca carta, reserva, imagem, região, página, alocação ou local. Mas
  todas valem para o fichário INTEIRO. Por isso o EDITOR só as executa no
  fichário EXCLUSIVO de X (X proprietária, Pokédex, sem convidadas): ali a
  camada e a preferência só afetam X. No fichário com convidadas, mudariam a
  classificação (5378) e a exibição dos bolsos usados por outras coleções →
  OPERATION_RESERVED_TO_OWNER. Nenhuma permissão de escrita global.
  Bolso com conteúdo de terceiros (carta de convidada desassociada ou sem
  coleção, imagem do titular) também recebe o rótulo, como no titular: é
  alteração de classificação/visual, não patrimonial — o conteúdo não é tocado
  e o bolso continua FOREIGN para o EDITOR (a carta/imagem decide antes da
  referência). Referências de OUTRA coleção no fichário (proprietária anterior:
  a transferência 5254 não as move) são de terceiros → prévia, aplicar, remover
  e mostrar/ocultar → OPERATION_RESERVED_TO_OWNER; remover só apaga as de X.

Funções novas:
  editor_species_reference_summary(layout, pokedex, ref, scope, X)   — INTERNA, STABLE
      resumo do plano canônico (mesma fórmula de token da 5258).
  editor_preview_binder_species_references(p_collection_id)  — STABLE, RPC
      → (positions_in_scope, slots_total, pair_count, slots_left_free,
         positions_unplaced, first_page, last_page, first_number, last_number,
         existing_count, already_applied, plan_token)
      SEM "slots_with_content" da 5258: contar bolsos ocupados revelaria
      conteúdo que o fichário mascarado esconde do membro (C-243).
  editor_apply_binder_species_references(p_collection_id, p_plan_token)
      → (operation: APPLIED | ALREADY_APPLIED, reference_count, references_visible)
  editor_clear_binder_species_references(p_collection_id, p_expected_count)
      → (operation: REMOVED, removed_count)
  editor_set_binder_species_reference_visibility(p_collection_id, p_visible)
      → (references_visible, operation: UPDATED | UNCHANGED)
Regras de escrita iguais às da 5258 (PLAN_CHANGED, SPECIES_REFERENCES_PRESENT,
  NOTHING_TO_APPLY, COUNT_MISMATCH), sob as travas da 5382 (proprietária →
  layout → participação). Recusas de autorização: as da 5371/5382; Pokédex
  exigida (NOT_POKEDEX_COLLECTION) também para mostrar/ocultar.
Histórico: a 5258 do titular não grava evento; mantido igual (nenhum tipo novo).
Funções do titular (5258): não tocadas.
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5383 em ROLLBACK_E1C.sql.
Como validar: harness 5892, seção 3.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.binder_species_reference_plan(uuid, uuid, uuid, text)') is null
     or to_regprocedure('public.assert_collection_binder_editor_exclusive(uuid)') is null then
    raise exception 'PRECHECK 5383: 5258 ou 5382 ausentes';
  end if;
  if to_regprocedure('public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid)') is not null
     or to_regprocedure('public.editor_preview_binder_species_references(uuid)') is not null
     or to_regprocedure('public.editor_apply_binder_species_references(uuid, text)') is not null
     or to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)') is not null
     or to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)') is not null then
    raise exception 'PRECHECK 5383: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: resumo do plano canônico (mesma fórmula de token da 5258) ---------------
create function public.editor_species_reference_summary(
  p_layout_id               uuid,
  p_pokedex_id              uuid,
  p_collection_reference_id uuid,
  p_scope_kind              text,
  p_collection_id           uuid
)
returns table (
  positions_in_scope integer, slots_total integer, pair_count integer,
  first_page integer, last_page integer, first_number integer, last_number integer,
  existing_count integer, already_applied boolean, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_pos integer; v_slots integer; v_pairs integer; v_fp integer; v_lp integer;
  v_fn integer; v_ln integer; v_existing integer; v_token text;
begin
  select count(*)::integer into v_pos
  from public.pokedex_position pp
  join public.pokemon_species sp on sp.id = pp.species_id
  where pp.pokedex_id = p_pokedex_id
    and (p_scope_kind = 'FULL_REFERENCE'
         or exists (select 1 from public.collection_pokedex_scope_generation sg
                    where sg.collection_reference_id = p_collection_reference_id
                      and sg.generation_id = sp.generation_id));
  select count(*)::integer into v_slots
  from public.collection_layout_page pg
  join public.collection_layout_slot s on s.page_id = pg.id
  where pg.layout_id = p_layout_id;
  select count(*)::integer, min(p.page_number), max(p.page_number), min(p.position_number), max(p.position_number),
         encode(sha256(convert_to(p_layout_id::text || '|' ||
                coalesce(string_agg(p.slot_id::text || ':' || p.pokedex_position_id::text, ',' order by p.ord), ''), 'UTF8')), 'hex')
    into v_pairs, v_fp, v_lp, v_fn, v_ln, v_token
  from public.binder_species_reference_plan(p_layout_id, p_pokedex_id, p_collection_reference_id, p_scope_kind) p;
  select count(*)::integer into v_existing
  from public.collection_layout_slot_species_reference r where r.layout_id = p_layout_id;

  return query select v_pos, v_slots, v_pairs, v_fp, v_lp, v_fn, v_ln, v_existing,
    (v_existing = v_pairs and v_pairs > 0 and not exists (
       select 1 from public.binder_species_reference_plan(p_layout_id, p_pokedex_id, p_collection_reference_id, p_scope_kind) p
       where not exists (select 1 from public.collection_layout_slot_species_reference r
                         where r.slot_id = p.slot_id and r.pokedex_position_id = p.pokedex_position_id
                           and r.collection_id = p_collection_id))),
    v_token;
end;
$fn$;

-- Prévia (leitura, sem trava) ----------------------------------------------------------------
create function public.editor_preview_binder_species_references(p_collection_id uuid)
returns table (
  positions_in_scope integer, slots_total integer, pair_count integer, slots_left_free integer,
  positions_unplaced integer, first_page integer, last_page integer, first_number integer,
  last_number integer, existing_count integer, already_applied boolean, plan_token text
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid    uuid := (select auth.uid());
  v_status text;
  v_layout uuid;
  t        record;
  s        record;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select c.lifecycle_status into v_status
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id and c.owner_user_id <> v_uid;
  if v_status is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
        hint = 'num fichário com mais de uma coleção, esta operação é do titular';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout)
     or exists (select 1 from public.collection_layout_slot_species_reference r
                where r.layout_id = v_layout and r.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'num fichário com mais de uma coleção, esta operação é do titular';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;
  select cpr.pokedex_id, cr.id as ref_id, cpr.scope_kind::text as scope_kind into t
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id and c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION';
  if t.pokedex_id is null then
    raise exception 'NOT_POKEDEX_COLLECTION' using errcode = '22023';
  end if;

  select * into s from public.editor_species_reference_summary(v_layout, t.pokedex_id, t.ref_id, t.scope_kind, p_collection_id);
  return query select s.positions_in_scope, s.slots_total, s.pair_count, s.slots_total - s.pair_count,
                      s.positions_in_scope - s.pair_count, s.first_page, s.last_page, s.first_number, s.last_number,
                      s.existing_count, s.already_applied, s.plan_token;
end;
$fn$;

-- Ajudante interno de escrita: trava (5382) + Pokédex ----------------------------------------
create function public.editor_species_reference_target_locked(p_collection_id uuid)
returns table (layout_id uuid, pokedex_id uuid, collection_reference_id uuid, scope_kind text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_layout uuid;
begin
  select x.layout_id into v_layout from public.assert_collection_binder_editor_exclusive(p_collection_id) x;
  -- Referências registradas para OUTRA coleção (proprietária anterior: a 5254 não as
  -- move) são de terceiros: o EDITOR não as apaga, não as esconde e não aplica sobre elas.
  if exists (select 1 from public.collection_layout_slot_species_reference r
             where r.layout_id = v_layout and r.collection_id <> p_collection_id) then
    raise exception 'OPERATION_RESERVED_TO_OWNER' using errcode = '42501',
      hint = 'este fichário tem referências que só o titular pode alterar';
  end if;
  return query
  select v_layout, cpr.pokedex_id, cr.id, cpr.scope_kind::text
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id and c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION';
  if not found then
    raise exception 'NOT_POKEDEX_COLLECTION' using errcode = '22023';
  end if;
end;
$fn$;

-- Aplicar ---------------------------------------------------------------------------------------
create function public.editor_apply_binder_species_references(p_collection_id uuid, p_plan_token text)
returns table (operation text, reference_count integer, references_visible boolean)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  t       record;
  s       record;
  v_op    text;
  v_count integer;
begin
  if p_plan_token is null or p_plan_token !~ '^[0-9a-f]{64}$' then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into t from public.editor_species_reference_target_locked(p_collection_id);
  select * into s from public.editor_species_reference_summary(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind, p_collection_id);
  if s.plan_token <> p_plan_token then
    raise exception 'PLAN_CHANGED' using errcode = 'P0001',
      hint = 'o fichário mudou desde a prévia; revise e confirme de novo';
  end if;
  if s.already_applied then
    v_op := 'ALREADY_APPLIED';
  else
    if s.existing_count > 0 then
      raise exception 'SPECIES_REFERENCES_PRESENT' using errcode = 'P0001',
        hint = 'este fichário já tem referências; remova-as antes de aplicar de novo';
    end if;
    if s.pair_count = 0 then
      raise exception 'NOTHING_TO_APPLY' using errcode = 'P0001';
    end if;
    insert into public.collection_layout_slot_species_reference
      (slot_id, layout_id, collection_id, pokedex_position_id, source)
    select p.slot_id, t.layout_id, p_collection_id, p.pokedex_position_id, 'NATIONAL_ORDER'
    from public.binder_species_reference_plan(t.layout_id, t.pokedex_id, t.collection_reference_id, t.scope_kind) p;
    v_op := 'APPLIED';
  end if;
  insert into public.collection_layout_species_reference_setting as st (layout_id, references_visible, updated_at)
  values (t.layout_id, true, now())
  on conflict on constraint pk_cl_species_reference_setting
  do update set references_visible = true, updated_at = now()
  where st.references_visible is distinct from true;
  select count(*)::integer into v_count
  from public.collection_layout_slot_species_reference r where r.layout_id = t.layout_id;
  return query select v_op, v_count, true;
end;
$fn$;

-- Remover ---------------------------------------------------------------------------------------
create function public.editor_clear_binder_species_references(p_collection_id uuid, p_expected_count integer)
returns table (operation text, removed_count integer)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  t         record;
  v_current integer;
  v_removed integer;
begin
  if p_expected_count is null or p_expected_count < 0 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into t from public.editor_species_reference_target_locked(p_collection_id);
  select count(*)::integer into v_current
  from public.collection_layout_slot_species_reference r
  where r.layout_id = t.layout_id and r.collection_id = p_collection_id;
  if v_current <> p_expected_count then
    raise exception 'COUNT_MISMATCH' using errcode = 'P0001',
      hint = format('o fichário tem %s referências; revise antes de remover', v_current);
  end if;
  delete from public.collection_layout_slot_species_reference r
  where r.layout_id = t.layout_id and r.collection_id = p_collection_id;
  get diagnostics v_removed = row_count;
  return query select 'REMOVED'::text, v_removed;
end;
$fn$;

-- Mostrar / ocultar -----------------------------------------------------------------------------
create function public.editor_set_binder_species_reference_visibility(p_collection_id uuid, p_visible boolean)
returns table (references_visible boolean, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  t         record;
  v_current boolean;
begin
  if p_visible is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  select * into t from public.editor_species_reference_target_locked(p_collection_id);
  select st.references_visible into v_current
  from public.collection_layout_species_reference_setting st
  where st.layout_id = t.layout_id
  for update;
  if coalesce(v_current, true) = p_visible then
    return query select p_visible, 'UNCHANGED'::text;
    return;
  end if;
  insert into public.collection_layout_species_reference_setting (layout_id, references_visible, updated_at)
  values (t.layout_id, p_visible, now())
  on conflict on constraint pk_cl_species_reference_setting
  do update set references_visible = excluded.references_visible, updated_at = now();
  return query select p_visible, 'UPDATED'::text;
end;
$fn$;

comment on function public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid) is
  'V1-13 E1-C (5383, interna): resumo do plano canônico de referências de espécie (5258) para o EDITOR, com o mesmo token.';
comment on function public.editor_species_reference_target_locked(uuid) is
  'V1-13 E1-C (5383, interna): trava como a 5382 (fichário exclusivo) e devolve a Pokédex de X; NOT_POKEDEX_COLLECTION se não for.';
comment on function public.editor_preview_binder_species_references(uuid) is
  'V1-13 E1-C (5383): prévia das referências de espécie para o EDITOR do fichário exclusivo da Pokédex; sem contagem de bolsos ocupados.';
comment on function public.editor_apply_binder_species_references(uuid, text) is
  'V1-13 E1-C (5383): EDITOR aplica as referências de espécie no fichário exclusivo da Pokédex (espelho da 5258).';
comment on function public.editor_clear_binder_species_references(uuid, integer) is
  'V1-13 E1-C (5383): EDITOR remove as referências de espécie do fichário exclusivo da Pokédex, com a contagem atual (espelho da 5258).';
comment on function public.editor_set_binder_species_reference_visibility(uuid, boolean) is
  'V1-13 E1-C (5383): EDITOR mostra/oculta as referências no fichário exclusivo da Pokédex (espelho da 5258); nunca apaga vínculos.';

revoke all on function public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_species_reference_target_locked(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_preview_binder_species_references(uuid) from public, anon;
revoke all on function public.editor_apply_binder_species_references(uuid, text) from public, anon;
revoke all on function public.editor_clear_binder_species_references(uuid, integer) from public, anon;
revoke all on function public.editor_set_binder_species_reference_visibility(uuid, boolean) from public, anon;
grant execute on function public.editor_preview_binder_species_references(uuid) to authenticated;
grant execute on function public.editor_apply_binder_species_references(uuid, text) to authenticated;
grant execute on function public.editor_clear_binder_species_references(uuid, integer) to authenticated;
grant execute on function public.editor_set_binder_species_reference_visibility(uuid, boolean) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_preview_binder_species_references(uuid)'),
                           to_regprocedure('public.editor_apply_binder_species_references(uuid, text)'),
                           to_regprocedure('public.editor_clear_binder_species_references(uuid, integer)'),
                           to_regprocedure('public.editor_set_binder_species_reference_visibility(uuid, boolean)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5383: RPC fora do estado esperado (%)', f;
    end if;
  end loop;
  foreach f in array array[to_regprocedure('public.editor_species_reference_summary(uuid, uuid, uuid, text, uuid)'),
                           to_regprocedure('public.editor_species_reference_target_locked(uuid)')] loop
    if f is null
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5383: ajudante interno fora do estado esperado (%)', f;
    end if;
  end loop;
end;
$post$;

commit;
