/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1b3-pokedex-history/5380_create_editor_pokedex_position_writes.sql
   sha256 da base: 32d4657c94b3157692ce00e14374f5e751b1d6df047917d3db5bd1d256bfb5e0
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 4 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5380 - Pokédex pelo EDITOR: posição e representante entre
              exemplares JÁ ALOCADOS à coleção (V1-13 · E1-B3)
Versão......: 1.1 (2026-11-15, `E1-E2 | CANONICAL BASELINE RECONCILIATION AND G2 CORRECTION-02`,
              defeito E2-D1: o md5 conferido de set_pokedex_position_assignment era o
              da 6122; o corpo canônico vigente é o da 6123 — só as duas constantes
              mudam; lógica do EDITOR inalterada). 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B3 | POKÉDEX AND ACTIVITY HISTORY FOUNDATION-01`
              (2026-11-15). Execução só com prova dinâmica sob protocolo
              controlado (C-244) e autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-242 (EDITOR muda a posição de um exemplar já alocado —
              6122/6124 — e escolhe o representante entre exemplares já
              alocados — 6125; nada disso cria ou desfaz alocação; a atribuição
              automática da alocação, 6119, continua só com o titular), C-234,
              C-243 (recusa neutra, sem acervo).
Depende de..: E1-A (5366), E1-B2 (5376: assert_collection_editor), 6117–6126.

Funções novas (RPC, EXECUTE só authenticated). O exemplar é identificado pelo
physical_card_id que as leituras compartilhadas já devolvem; o EDITOR nunca
recebe collection_allocation_id.
  editor_set_pokedex_position_assignment(p_collection_id, p_physical_card_id,
                                         p_pokedex_position_id,
                                         p_confirm_override default false)
      → (pokedex_position_id, assignment_basis, operation: CREATED | MOVED | UNCHANGED)
  editor_remove_pokedex_position_assignment(p_collection_id, p_physical_card_id)
      → (pokedex_position_id, operation: REMOVED | UNCHANGED)
  editor_set_pokedex_position_primary_representative(p_collection_id, p_physical_card_id)
      → (pokedex_position_id, operation: SET | REPLACED | UNCHANGED)
  editor_clear_pokedex_position_primary_representative(p_collection_id, p_pokedex_position_id)
      → (pokedex_position_id, operation: CLEARED | UNCHANGED)

Regras (espelho de 6122, 6124, 6125/6126, com coleção explícita):
  Autorização  — assert_collection_editor (5376): EDITOR ACTIVE de X, coleção
                 X (FOR UPDATE) → participação (FOR SHARE); X arquivada →
                 COLLECTION_ARCHIVED (55000) só depois de autorizado; todo o
                 resto → COLLECTION_NOT_FOUND (P0002), indistinguível.
  Modalidade   — X precisa ser Pokédex (REFERENCE_BASED, REFERENCE_POSITION,
                 referência POKEDEX) → senão NOT_POKEDEX_COLLECTION (22023).
  Exemplar     — precisa estar ALOCADO A X (alocação travada FOR UPDATE, depois
                 da coleção: mesma ordem de 6124/6125). Exemplar inexistente, de
                 outra conta, de outra coleção ou sem alocação →
                 PHYSICAL_CARD_NOT_ELIGIBLE (P0002), a mesma recusa da E1-B1.
  Posição      — da mesma Pokédex de X → senão POKEDEX_POSITION_NOT_FOUND
                 (22023). Correspondência de espécie (SPECIES_MATCH) ou
                 confirmação explícita (p_confirm_override → USER_OVERRIDE, com
                 assigned_by_user_id = EDITOR, exigido pelo gatilho 6118) →
                 senão CONFIRMATION_REQUIRED (22023). Mesma posição → UNCHANGED
                 antes de qualquer validação de espécie (regra v1.1 da 6122).
                 Mover = DELETE + INSERT (linha imutável, 6118); o representante
                 da posição antiga sai em cascata (6120), como no titular.
  Representante— só exemplar de X com posição atribuída
                 (POKEDEX_ASSIGNMENT_NOT_FOUND, 22023); gatilho 6121 confere.
                 Limpar só a posição de X; sem representante → UNCHANGED.
Nunca: alocar, desalocar, mudar local, condição, acervo fora de X, Set, escopo,
  política, titularidade; nenhuma leitura de dados privados (a resposta só
  devolve a posição, a base e a operação).
Histórico: posição e representante são dados da coleção, não do fichário; o
  titular (6122/6124/6125) também não registra evento. Mantido igual.
Funções do titular (6123 — corpo vigente de set_pokedex_position_assignment, que
  substituiu o da 6122 —, 6124, 6126, clear da 6125): BYTE A BYTE iguais — md5
  no precheck e no postcheck (derivados dos arquivos de database/schema; a S0
  de qualquer execução precisa confirmá-los no LIVE).
Canal.......: psql. Idempotência: funções já presentes → 'JÁ APLICADA ou
              DIVERGENTE'. Reversão: R5380 em ROLLBACK_E1B3.sql.
Como validar: harness 5891, seção 6.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.assert_collection_editor(uuid)') is null then
    raise exception 'PRECHECK 5380: E1-B2 (5376) não aplicada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'PRECHECK 5380: ESTADO DIVERGENTE — funções do titular da Pokédex diferem de 6123/6124/6126/6125';
  end if;
  if to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)') is not null
     or to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)') is not null
     or to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)') is not null
     or to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)') is not null then
    raise exception 'PRECHECK 5380: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Ajudante interno: Pokédex da coleção autorizada (sem EXECUTE para a API) -----------------
create function public.editor_pokedex_of_collection(p_collection_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_dex uuid;
begin
  select cpr.pokedex_id into v_dex
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';
  if v_dex is null then
    raise exception 'NOT_POKEDEX_COLLECTION' using errcode = '22023';
  end if;
  return v_dex;
end;
$fn$;

-- Posição: criar ou mover -----------------------------------------------------------------
create function public.editor_set_pokedex_position_assignment(
  p_collection_id       uuid,
  p_physical_card_id    uuid,
  p_pokedex_position_id uuid,
  p_confirm_override    boolean default false
)
returns table (pokedex_position_id uuid, assignment_basis text, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid      uuid := (select auth.uid());
  v_owner    uuid;
  v_dex      uuid;
  v_alloc    uuid;
  v_cur      uuid;
  v_cur_base text;
  v_pos_dex  uuid;
  v_pos_spc  uuid;
  v_cat      text;
  v_spc      uuid;
  v_base     text;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_physical_card_id is null or p_pokedex_position_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  v_dex := public.editor_pokedex_of_collection(p_collection_id);

  -- Coleção já travada (assert) → alocação de X, travada.
  select ca.id into v_alloc
  from public.collection_allocation ca
  where ca.physical_card_id = p_physical_card_id and ca.collection_id = p_collection_id
  for update;
  if v_alloc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  select a.pokedex_position_id, a.assignment_basis into v_cur, v_cur_base
  from public.collection_pokedex_position_assignment a
  where a.collection_allocation_id = v_alloc;
  if v_cur = p_pokedex_position_id then
    return query select v_cur, v_cur_base, 'UNCHANGED'::text;
    return;
  end if;

  select pp.pokedex_id, pp.species_id into v_pos_dex, v_pos_spc
  from public.pokedex_position pp
  where pp.id = p_pokedex_position_id;
  if v_pos_dex is distinct from v_dex then
    raise exception 'POKEDEX_POSITION_NOT_FOUND' using errcode = '22023';
  end if;

  select cc.code, cps.pokemon_species_id into v_cat, v_spc
  from public.physical_card pc
  join public.card_variant cv on cv.id = pc.card_variant_id
  join public.card k on k.id = cv.card_id
  join public.card_category cc on cc.id = k.category_id
  left join public.card_primary_species cps on cps.card_id = k.id
  where pc.id = p_physical_card_id;
  if v_cat = 'POKEMON' and v_spc is not null and v_spc = v_pos_spc then
    v_base := 'SPECIES_MATCH';
  elsif coalesce(p_confirm_override, false) then
    v_base := 'USER_OVERRIDE';
  else
    raise exception 'CONFIRMATION_REQUIRED' using errcode = '22023',
      hint = 'a carta não corresponde à espécie da posição; confirme para posicionar mesmo assim';
  end if;

  if v_cur is not null then
    delete from public.collection_pokedex_position_assignment a
    where a.collection_allocation_id = v_alloc;
  end if;
  insert into public.collection_pokedex_position_assignment
    (collection_allocation_id, pokedex_position_id, assignment_basis, assigned_at, assigned_by_user_id)
  values (v_alloc, p_pokedex_position_id, v_base, now(),
          case when v_base = 'USER_OVERRIDE' then v_uid end);

  return query select p_pokedex_position_id, v_base,
                      case when v_cur is null then 'CREATED' else 'MOVED' end::text;
end;
$fn$;

-- Posição: retirar (sem desalocar) ------------------------------------------------------------
create function public.editor_remove_pokedex_position_assignment(
  p_collection_id    uuid,
  p_physical_card_id uuid
)
returns table (pokedex_position_id uuid, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_alloc uuid;
  v_cur   uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_physical_card_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);

  select ca.id into v_alloc
  from public.collection_allocation ca
  where ca.physical_card_id = p_physical_card_id and ca.collection_id = p_collection_id
  for update;
  if v_alloc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  delete from public.collection_pokedex_position_assignment a
  where a.collection_allocation_id = v_alloc
  returning a.pokedex_position_id into v_cur;
  return query select v_cur, case when v_cur is null then 'UNCHANGED' else 'REMOVED' end::text;
end;
$fn$;

-- Representante: escolher entre exemplares de X com posição ------------------------------------
create function public.editor_set_pokedex_position_primary_representative(
  p_collection_id    uuid,
  p_physical_card_id uuid
)
returns table (pokedex_position_id uuid, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_alloc uuid;
  v_pos   uuid;
  v_prev  uuid;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_physical_card_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);

  select ca.id into v_alloc
  from public.collection_allocation ca
  where ca.physical_card_id = p_physical_card_id and ca.collection_id = p_collection_id
  for update;
  if v_alloc is null then
    raise exception 'PHYSICAL_CARD_NOT_ELIGIBLE' using errcode = 'P0002';
  end if;

  select a.pokedex_position_id into v_pos
  from public.collection_pokedex_position_assignment a
  where a.collection_allocation_id = v_alloc;
  if v_pos is null then
    raise exception 'POKEDEX_ASSIGNMENT_NOT_FOUND' using errcode = '22023';
  end if;

  select r.collection_allocation_id into v_prev
  from public.collection_pokedex_position_primary_representative r
  where r.collection_id = p_collection_id and r.pokedex_position_id = v_pos
  for update;
  if v_prev = v_alloc then
    return query select v_pos, 'UNCHANGED'::text;
    return;
  end if;

  insert into public.collection_pokedex_position_primary_representative
    (collection_id, pokedex_position_id, collection_allocation_id)
  values (p_collection_id, v_pos, v_alloc)
  on conflict on constraint pk_collection_pokedex_position_primary_representative
  do update set collection_allocation_id = excluded.collection_allocation_id;

  return query select v_pos, case when v_prev is null then 'SET' else 'REPLACED' end::text;
end;
$fn$;

-- Representante: limpar ------------------------------------------------------------------------
create function public.editor_clear_pokedex_position_primary_representative(
  p_collection_id       uuid,
  p_pokedex_position_id uuid
)
returns table (pokedex_position_id uuid, operation text)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_uid   uuid := (select auth.uid());
  v_owner uuid;
  v_n     integer;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1)
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_pokedex_position_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  v_owner := public.assert_collection_editor(p_collection_id);
  perform public.editor_pokedex_of_collection(p_collection_id);

  delete from public.collection_pokedex_position_primary_representative r
  where r.collection_id = p_collection_id and r.pokedex_position_id = p_pokedex_position_id;
  get diagnostics v_n = row_count;
  return query select p_pokedex_position_id, case when v_n = 0 then 'UNCHANGED' else 'CLEARED' end::text;
end;
$fn$;

comment on function public.editor_pokedex_of_collection(uuid) is
  'V1-13 E1-B3 (5380, interna): Pokédex referenciada pela coleção; NOT_POKEDEX_COLLECTION (22023) se a coleção não for Pokédex.';
comment on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) is
  'V1-13 E1-B3 (5380): EDITOR cria ou move a posição Pokédex de um exemplar já alocado à coleção (espelho da 6122). Não aloca nem desaloca.';
comment on function public.editor_remove_pokedex_position_assignment(uuid, uuid) is
  'V1-13 E1-B3 (5380): EDITOR retira a posição Pokédex de um exemplar da coleção, sem desalocar (espelho da 6124). Sem posição → UNCHANGED.';
comment on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) is
  'V1-13 E1-B3 (5380): EDITOR escolhe o representante da posição entre exemplares da coleção com posição (espelho da 6125/6126).';
comment on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) is
  'V1-13 E1-B3 (5380): EDITOR remove o representante de uma posição da coleção (espelho do clear da 6125). Sem representante → UNCHANGED.';

revoke all on function public.editor_pokedex_of_collection(uuid) from public, anon, authenticated, service_role;
revoke all on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) from public, anon;
revoke all on function public.editor_remove_pokedex_position_assignment(uuid, uuid) from public, anon;
revoke all on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) from public, anon;
revoke all on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) from public, anon;
grant execute on function public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean) to authenticated;
grant execute on function public.editor_remove_pokedex_position_assignment(uuid, uuid) to authenticated;
grant execute on function public.editor_set_pokedex_position_primary_representative(uuid, uuid) to authenticated;
grant execute on function public.editor_clear_pokedex_position_primary_representative(uuid, uuid) to authenticated;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.editor_set_pokedex_position_assignment(uuid, uuid, uuid, boolean)'),
                           to_regprocedure('public.editor_remove_pokedex_position_assignment(uuid, uuid)'),
                           to_regprocedure('public.editor_set_pokedex_position_primary_representative(uuid, uuid)'),
                           to_regprocedure('public.editor_clear_pokedex_position_primary_representative(uuid, uuid)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not true
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5380: RPC do EDITOR fora do estado esperado (%)', f;
    end if;
  end loop;
  f := to_regprocedure('public.editor_pokedex_of_collection(uuid)');
  if f is null
     or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
    raise exception 'POSTCHECK 5380: ajudante interno fora do estado esperado';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.set_pokedex_position_assignment(uuid, uuid, boolean)')) is distinct from '8c572182a03025503e993e5ecc25e07a'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.remove_pokedex_position_assignment(uuid)')) is distinct from '26ef2d5da3312661111df0194dfc8ba2'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.set_pokedex_position_primary_representative(uuid)')) is distinct from '6353dffe6c3877967997033dcc2bfd4c'
     or (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
          where p.oid = to_regprocedure('public.clear_pokedex_position_primary_representative(uuid, uuid)')) is distinct from 'eeede3a5b871fbf07f81eb59ecea932f' then
    raise exception 'POSTCHECK 5380: funções do titular da Pokédex mudaram';
  end if;
end;
$post$;

commit;
