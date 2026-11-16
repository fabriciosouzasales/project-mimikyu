/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1b2-editor-curation/5375_create_editor_binder_curation_writes.sql
   sha256 da base: 1a2b4cdb28502509c551e844a80769b4cf94da628ec225994c65455456d5258d
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 3 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5375 - Curadoria do EDITOR no fichário: reservar, liberar reserva,
              fixar e soltar (V1-13 · E1-B2)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B2 | EDITOR CURATION OPERATIONS-01` (2026-11-15).
              Execução só com prova dinâmica sob protocolo controlado (C-244) e
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-237 (reservar só em bolso livre ou da coleção, sempre registrada
              para a coleção; liberar só reservas da coleção; fixar e soltar só
              bolsos da coleção), C-196 (reserva pertence a uma coleção), C-241
              (evento com ator EDITOR), C-243 (recusa neutra).
Depende de..: E1-A (5366) e E1-B1 (5371 autorização/classificação/posição, 5372
              histórico com ator EDITOR).

Funções novas (RPC, EXECUTE só authenticated), endereçadas por POSIÇÃO visível
(página, linha, coluna), como as da E1-B1:
  editor_set_binder_reservation(p_collection_id, p_page, p_row, p_column,
                                p_card_id, p_card_variant_id default null,
                                p_expected_variant_type_id default null)
      → (operation: RESERVED | REPLACED | UNCHANGED)
  editor_clear_binder_reservation(p_collection_id, p_page, p_row, p_column)
      → (operation: RELEASED | UNCHANGED)
  editor_set_binder_lock(p_collection_id, p_page, p_row, p_column, p_locked boolean)
      → (operation: LOCKED | UNLOCKED | UNCHANGED)

Funções do titular (set_slot_expected_content 5276, clear_slot_expected_content
5277, set_slot_lock 5278) ficam BYTE A BYTE iguais — md5 conferido no precheck e
no postcheck (valores já lidos no LIVE em LIVE_S3_90, 2026-10-27). O EDITOR
precisa de coleção explícita e de endereçamento por posição, que elas não
recebem; a regra é a classificação C-237 por bolso. Duplicação limitada à
escrita e aos itens do histórico, com DEVER DE ESPELHO (README).

Regras (todas sob as travas da 5371: proprietária → layout → convidada →
participação; depois o bolso FOR UPDATE; classificação lida sob a trava):
  Reservar  — bolso OWN ou FREE (5371). Qualquer reserva existente no bolso é
              de X (garantido pela classificação). A reserva nova SEMPRE fica
              registrada para X (nunca a da carta, nunca a proprietária quando
              X é convidada). Variante específica e acabamento são exclusivos
              (mesma regra e mesma mensagem da 5276). Reserva idêntica →
              UNCHANGED, sem evento. Reservar NÃO aloca nada: só
              collection_layout_slot_expected_content muda.
              Bolso fixado de X aceita reserva, como no titular (5276 não
              recusa trava). Bolso em mesclagem é FOREIGN (e o gatilho 5238
              recusaria de qualquer forma).
  Liberar   — bolso OWN e reserva registrada para X (sem coleção = proprietária,
              C-196). Sem reserva → UNCHANGED, sem evento (o titular devolve 0
              e não registra evento).
  Fixar     — só bolso OWN (com carta ou reserva de X). Bolso FREE não pode ser
              fixado pelo EDITOR: fixar um bolso vazio ocupa o espaço de todas as
              coleções (C-237). Já fixado → UNCHANGED.
  Soltar    — só bolso fixado e OWN. Bolso fixado sem conteúdo de X é FOREIGN
              (é do titular) e é recusado.
Recusas: bolso de terceiros e posição inexistente → SLOT_NOT_EDITABLE (42501),
  a mesma, sem revelar conteúdo. Autorização → as da 5371.
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5375 em ROLLBACK_E1B2.sql.
Como validar: harness 5890, seções 1–3.
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
    raise exception 'PRECHECK 5375: E1-B1 (5371) não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
     is distinct from '59ec5791e514026b7a8340e104d66f30' then
    raise exception 'PRECHECK 5375: E1-B1 (5372) não aplicada';
  end if;
  if to_regprocedure('public.binder_activity_add_reservation_item(text, uuid)') is null then
    raise exception 'PRECHECK 5375: ESTADO DIVERGENTE — 5275 ausente';
  end if;
  -- Funções do titular: canônicas (md5 lido no LIVE em LIVE_S3_90, 2026-10-27).
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) is distinct from '33dde5013dbb491bd4a0452ab7ce8132'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.clear_slot_expected_content(uuid[])')) is distinct from '0b8f26825ff713a24226548ffe3a63b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) is distinct from '651048a4bf7d3229904ef2a073c509c5' then
    raise exception 'PRECHECK 5375: ESTADO DIVERGENTE — funções do titular (5276–5278) diferem das canônicas';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('editor_set_binder_reservation', 'editor_clear_binder_reservation', 'editor_set_binder_lock')) then
    raise exception 'PRECHECK 5375: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Reservar -------------------------------------------------------------------------------------
create function public.editor_set_binder_reservation(
  p_collection_id            uuid,
  p_page                     integer,
  p_row                      integer,
  p_column                   integer,
  p_card_id                  uuid,
  p_card_variant_id          uuid default null,
  p_expected_variant_type_id uuid default null
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
  v_prev_coll uuid;
  v_had       boolean := false;
  v_same      boolean;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null
     or p_page < 1 or p_row < 1 or p_column < 1 then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_card_id is null then
    raise exception 'p_card_id é obrigatório' using errcode = '22023';
  end if;
  if p_card_variant_id is not null and p_expected_variant_type_id is not null then
    raise exception 'EXPECTED_CONTENT_VARIANT_AND_TYPE_EXCLUSIVE: informe a variante específica OU o acabamento, não os dois'
      using errcode = '22023';
  end if;

  select x.layout_id, x.anchor_collection_id, x.owner_user_id, x.container_id
    into v_layout, v_anchor, v_owner, v_container
  from public.assert_collection_binder_editor(p_collection_id) x;

  v_slot := public.binder_slot_at(v_layout, p_page, p_row, p_column);
  if v_slot is null then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  perform 1 from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope not in ('OWN', 'FREE') then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Reserva existente (já travada pelo bolso): só pode ser de X.
  select true, coalesce(e.collection_id, v_anchor),
         (e.card_id, e.card_variant_id, e.expected_variant_type_id, e.collection_id)
           is not distinct from (p_card_id, p_card_variant_id, p_expected_variant_type_id, p_collection_id)
    into v_had, v_prev_coll, v_same
  from public.collection_layout_slot_expected_content e
  where e.slot_id = v_slot;
  if v_had is true and v_prev_coll is distinct from p_collection_id then   -- SELECT INTO sem linha deixa NULL
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_had is true and v_same is true then
    return query select 'UNCHANGED'::text;
    return;
  end if;

  -- Escrita (espelho da 5276), sempre registrada para X.
  perform public.binder_activity_begin(v_layout, 'POCKET_RESERVED', 'FICHARIO', p_collection_id);
  if v_had is true then
    perform public.binder_activity_add_reservation_item('RELEASED', v_slot);
  end if;
  begin
    insert into public.collection_layout_slot_expected_content as ec
      (slot_id, card_id, card_variant_id, expected_variant_type_id, collection_id)
    values
      (v_slot, p_card_id, p_card_variant_id, p_expected_variant_type_id, p_collection_id)
    on conflict on constraint collection_layout_slot_expected_content_pkey
    do update set card_id                  = excluded.card_id,
                  card_variant_id          = excluded.card_variant_id,
                  expected_variant_type_id = excluded.expected_variant_type_id,
                  collection_id            = excluded.collection_id;
  exception
    when foreign_key_violation then
      raise exception
        'Card/Card Variant/acabamento inválido — quando informada, a Card Variant deve pertencer à Card indicada e o acabamento deve existir';
  end;
  perform public.binder_activity_add_reservation_item('RESERVED', v_slot);
  return query select case when v_had is true then 'REPLACED' else 'RESERVED' end;
  perform public.binder_activity_end();
end;
$fn$;

-- Liberar reserva ------------------------------------------------------------------------------
create function public.editor_clear_binder_reservation(
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
  v_had       boolean := false;
  v_coll      uuid;
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
  perform 1 from public.collection_layout_slot s where s.id = v_slot for update;
  v_scope := public.binder_slot_editor_scope(v_layout, v_anchor, p_collection_id, v_slot);
  if v_scope = 'FREE' then
    return query select 'UNCHANGED'::text;
    return;
  end if;
  if v_scope <> 'OWN' then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  select true, coalesce(e.collection_id, v_anchor) into v_had, v_coll
  from public.collection_layout_slot_expected_content e
  where e.slot_id = v_slot;
  if v_had is not true then   -- SELECT INTO sem linha deixa NULL
    return query select 'UNCHANGED'::text;
    return;
  end if;
  if v_coll is distinct from p_collection_id then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;

  -- Escrita (espelho da 5277, um bolso): item antes do DELETE.
  perform public.binder_activity_begin(v_layout, 'RESERVATIONS_RELEASED', 'FICHARIO', p_collection_id);
  perform public.binder_activity_add_reservation_item('RELEASED', v_slot);
  delete from public.collection_layout_slot_expected_content where slot_id = v_slot;
  return query select 'RELEASED'::text;
  perform public.binder_activity_end();
end;
$fn$;

-- Fixar / soltar -------------------------------------------------------------------------------
create function public.editor_set_binder_lock(
  p_collection_id uuid,
  p_page          integer,
  p_row           integer,
  p_column        integer,
  p_locked        boolean
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
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if (select auth.uid()) is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_page is null or p_row is null or p_column is null or p_locked is null
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
  -- Fixar e soltar: só bolso OWN (com carta ou reserva de X). FREE e FOREIGN → mesma recusa.
  if v_scope <> 'OWN' then
    raise exception 'SLOT_NOT_EDITABLE' using errcode = '42501';
  end if;
  if v_locked is not distinct from p_locked then
    return query select 'UNCHANGED'::text;
    return;
  end if;

  -- Escrita (espelho da 5278, um bolso).
  perform public.binder_activity_begin(v_layout, case when p_locked then 'POCKETS_LOCKED' else 'POCKETS_UNLOCKED' end,
                                       'FICHARIO', p_collection_id);
  perform public.binder_activity_add_item('POCKET', case when p_locked then 'LOCKED' else 'UNLOCKED' end, null, null,
                                          case when p_locked then null else v_slot end, case when p_locked then v_slot end);
  update public.collection_layout_slot set locked = p_locked
  where id = v_slot and locked is distinct from p_locked;
  return query select case when p_locked then 'LOCKED' else 'UNLOCKED' end;
  perform public.binder_activity_end();
end;
$fn$;

comment on function public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid) is
  'V1-13 E1-B2 (5375): EDITOR reserva um bolso livre ou da coleção (posição visível) para uma carta; a reserva fica registrada para a coleção (C-196/C-237). Não aloca nada.';
comment on function public.editor_clear_binder_reservation(uuid, integer, integer, integer) is
  'V1-13 E1-B2 (5375): EDITOR libera uma reserva da coleção (C-237). Reserva de outra coleção → SLOT_NOT_EDITABLE.';
comment on function public.editor_set_binder_lock(uuid, integer, integer, integer, boolean) is
  'V1-13 E1-B2 (5375): EDITOR fixa ou solta um bolso da coleção (com carta ou reserva dela). Bolso livre ou de terceiros → SLOT_NOT_EDITABLE (C-237).';

revoke all on function public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid) from public, anon;
revoke all on function public.editor_clear_binder_reservation(uuid, integer, integer, integer) from public, anon;
revoke all on function public.editor_set_binder_lock(uuid, integer, integer, integer, boolean) from public, anon;
grant execute on function public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid) to authenticated;
grant execute on function public.editor_clear_binder_reservation(uuid, integer, integer, integer) to authenticated;
grant execute on function public.editor_set_binder_lock(uuid, integer, integer, integer, boolean) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[
      to_regprocedure('public.editor_set_binder_reservation(uuid, integer, integer, integer, uuid, uuid, uuid)'),
      to_regprocedure('public.editor_clear_binder_reservation(uuid, integer, integer, integer)'),
      to_regprocedure('public.editor_set_binder_lock(uuid, integer, integer, integer, boolean)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or not ((select p.proconfig from pg_catalog.pg_proc p where p.oid = f) @> array['search_path=""'])
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5375: escrita do EDITOR fora do estado esperado (%)', f;
    end if;
    if (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a where p.oid = f)
       is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '<NULL>') from pg_catalog.pg_proc p cross join lateral unnest(p.proacl) a
                         where p.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) then
      raise exception 'POSTCHECK 5375: ACL difere da 5276 (%)', f;
    end if;
  end loop;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_expected_content(uuid, uuid, uuid, uuid, uuid)')) is distinct from '33dde5013dbb491bd4a0452ab7ce8132'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.clear_slot_expected_content(uuid[])')) is distinct from '0b8f26825ff713a24226548ffe3a63b7'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_slot_lock(uuid[], boolean)')) is distinct from '651048a4bf7d3229904ef2a073c509c5' then
    raise exception 'POSTCHECK 5375: funções do titular mudaram';
  end if;
end;
$post$;

commit;
