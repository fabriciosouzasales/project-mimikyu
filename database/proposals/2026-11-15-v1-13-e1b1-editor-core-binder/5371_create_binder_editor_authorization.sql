/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5371 - Autorização do EDITOR no fichário e classificação de bolsos
              (V1-13 · E1-B1) — três funções INTERNAS
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-B1 | EDITOR AUTHORIZATION AND CORE BINDER OPERATIONS-01`
              (2026-11-15). Execução só pelo proprietário, depois de auditoria,
              de prova dinâmica sob protocolo controlado (C-244) e de
              autorização expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-234 (autorização por coleção e operação, no servidor), C-235,
              C-236, C-237 (classificação de bolsos), C-243 (recusas neutras);
              05d V1-13, entregas E1.3/E1.4.
Depende de..: E1-A aplicada (5366: papel EDITOR em collection_membership).
              NÃO depende de 5367 (o papel é lido aqui com trava própria).

Funções (todas internas: SECURITY DEFINER, search_path vazio, sem EXECUTE
para PUBLIC/anon/authenticated/service_role):

1. assert_collection_binder_editor(p_collection_id uuid)
   → (layout_id, anchor_collection_id, owner_user_id, container_id)
   Autoriza o usuário da sessão como EDITOR ACTIVE da coleção X e devolve o
   fichário de que X participa (proprietária ou convidada). NÃO substitui nem
   amplia a 5122 (assert_collection_layout_mutable), que continua exclusiva do
   titular e intocada.
   Ordem de travas = a do titular (5122/5272) + participação por último:
     coleção proprietária (FOR UPDATE) → layout (FOR UPDATE) → X convidada
     (FOR SHARE) → participação (FOR SHARE).
   A participação é travada DEPOIS da coleção X, a mesma ordem de 5369/5370
   (coleção → participação): troca de papel, remoção e saída concorrentes
   esperam a escrita do EDITOR terminar, ou a escrita vê o estado novo — sem
   ciclo de travas.
   Recusas: sem sessão → not_authenticated (28000); X inexistente, alheia,
   sem participação, participação PENDING/DECLINED, papel VIEWER, titular
   chamando o caminho do EDITOR → COLLECTION_NOT_FOUND (P0002), todas
   indistinguíveis; X sem fichário → BINDER_NOT_FOUND (P0002); proprietária
   ou X arquivada → COLLECTION_ARCHIVED (55000), só depois de autorizado.

2. binder_slot_editor_scope(p_layout_id, p_anchor_collection_id,
                            p_collection_id, p_slot_id) → 'OWN' | 'FREE' | 'FOREIGN'
   Classificação C-237, lida sob as travas do chamador (o chamador trava o
   bolso FOR UPDATE antes). Um bolso aparentemente vazio só é FREE se não tiver
   NADA: carta (de qualquer coleção ou sem coleção), reserva, imagem própria,
   região mesclada, referência de espécie e trava.
     OWN     — tudo o que existe no bolso é de X: carta alocada a X; reserva
               de X (reserva sem coleção pertence à proprietária, C-196);
               referência de espécie de X; trava só conta como OWN se o bolso
               também tiver carta ou reserva de X.
     FOREIGN — qualquer outro conteúdo: carta de outra coleção ou sem
               coleção, reserva de outra coleção, imagem personalizada
               (C-238, do titular), região mesclada (mesclagens = E1-B2),
               referência de espécie de outra coleção, trava em bolso sem
               conteúdo de X, bolso fora deste fichário.
     FREE    — nada disso.
   Só lê; nunca revela o conteúdo — o chamador converte FOREIGN em recusa
   neutra.

3. binder_slot_at(p_layout_id, p_page_number, p_row_index, p_column_index) → uuid
   Endereçamento por POSIÇÃO VISÍVEL. As leituras compartilhadas (5315/5316)
   expõem página/linha/coluna e nenhum id; as escritas do EDITOR usam a mesma
   referência. Nenhum id interno de bolso vai para o EDITOR, e não há id de
   bolso para forjar. NULL se a posição não existir neste fichário.
Canal.......: psql (várias instruções entre begin/commit).
Idempotência: funções já presentes com o corpo desta proposta → 'JÁ APLICADA'.
Reversão....: R5371 em ROLLBACK_E1B1.sql.
Como validar: harness 5889 (seções 0, 1 e 2); static_check_e1b1.py.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if (select pg_catalog.pg_get_constraintdef(k.oid) from pg_catalog.pg_constraint k
       where k.conrelid = 'public.collection_membership'::regclass
         and k.conname = 'chk_collection_membership_role')
     is distinct from 'CHECK ((role = ANY (ARRAY[''VIEWER''::text, ''EDITOR''::text])))' then
    raise exception 'PRECHECK 5371: E1-A (5366) não aplicada';
  end if;
  if to_regprocedure('public.assert_collection_layout_mutable(uuid)') is null
     or to_regclass('public.collection_layout_guest') is null
     or to_regclass('public.collection_layout_slot_image') is null
     or to_regclass('public.collection_layout_region') is null
     or to_regclass('public.collection_layout_slot_species_reference') is null then
    raise exception 'PRECHECK 5371: ESTADO DIVERGENTE — objetos do fichário ausentes';
  end if;
  -- md5 da 5122 já conferido no LIVE em 2026-10-23 (P2 LIVE_00, item 5122).
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)'))
     is distinct from 'd600f36fade0b67c0fd5af33e9965070' then
    raise exception 'PRECHECK 5371: ESTADO DIVERGENTE — 5122 difere da canônica';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public'
               and p.proname in ('assert_collection_binder_editor', 'binder_slot_editor_scope', 'binder_slot_at')) then
    raise exception 'PRECHECK 5371: funções já existem — JÁ APLICADA ou ESTADO DIVERGENTE (conferir 5889 seção 0)';
  end if;
end;
$pre$;

-- 1 -----------------------------------------------------------------------------------------
create function public.assert_collection_binder_editor(p_collection_id uuid)
returns table (layout_id uuid, anchor_collection_id uuid, owner_user_id uuid, container_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_uid       uuid := (select auth.uid());
  v_owner     uuid;
  v_layout    uuid;
  v_anchor    uuid;
  v_container uuid;
  v_status    text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- 1. Sem trava: X existe e o usuário é EDITOR ACTIVE dela. Titular nunca tem
  --    participação (C-141/C-156) e cai aqui também.
  select c.owner_user_id into v_owner
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = v_uid and m.status = 'ACTIVE' and m.role = 'EDITOR'
  where c.id = p_collection_id
    and c.owner_user_id <> v_uid;
  if v_owner is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 2. Fichário de que X participa (proprietária ou convidada).
  select l.id, l.collection_id into v_layout, v_anchor
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    select g.layout_id, l.collection_id into v_layout, v_anchor
    from public.collection_layout_guest g
    join public.collection_layout l on l.id = g.layout_id
    where g.collection_id = p_collection_id;
  end if;
  if v_layout is null then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 3. Proprietária (FOR UPDATE), do MESMO titular — mesma trava da 5122.
  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = v_anchor and c.owner_user_id = v_owner
  for update;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_status <> 'ACTIVE' then
    raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
  end if;

  -- 4. Layout (FOR UPDATE), ainda da proprietária.
  select l.storage_container_id into v_container
  from public.collection_layout l
  where l.id = v_layout and l.collection_id = v_anchor
  for update;
  if not found then
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- 5. X convidada (FOR SHARE) depois da proprietária e do layout (ordem da 5272).
  if p_collection_id <> v_anchor then
    select c.lifecycle_status into v_status
    from public.collection c
    where c.id = p_collection_id and c.owner_user_id = v_owner
    for share;
    if not found then
      raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
    end if;
    if v_status <> 'ACTIVE' then
      raise exception 'COLLECTION_ARCHIVED' using errcode = '55000';
    end if;
    if not exists (select 1 from public.collection_layout_guest g
                   where g.layout_id = v_layout and g.collection_id = p_collection_id) then
      raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  -- 6. Participação (FOR SHARE), por último; papel e estado relidos sob a trava.
  perform 1
  from public.collection_membership m
  where m.collection_id = p_collection_id and m.user_id = v_uid
    and m.status = 'ACTIVE' and m.role = 'EDITOR'
  for share;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  return query select v_layout, v_anchor, v_owner, v_container;
end;
$fn$;

-- 2 -----------------------------------------------------------------------------------------
create function public.binder_slot_editor_scope(
  p_layout_id            uuid,
  p_anchor_collection_id uuid,
  p_collection_id        uuid,
  p_slot_id              uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_page    uuid;
  v_row     integer;
  v_col     integer;
  v_locked  boolean;
  v_card    uuid;
  v_card_cl uuid;
  v_res_cl  uuid;
  v_res     boolean;
  v_spc_cl  uuid;
  v_own     boolean := false;
begin
  select s.page_id, s.row_index, s.column_index, s.locked
    into v_page, v_row, v_col, v_locked
  from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where s.id = p_slot_id and p.layout_id = p_layout_id;
  if v_page is null then
    return 'FOREIGN';
  end if;

  -- Carta: só é de X se o exemplar estiver alocado a X.
  select a.physical_card_id, ca.collection_id into v_card, v_card_cl
  from public.collection_layout_slot_assignment a
  left join public.collection_allocation ca on ca.physical_card_id = a.physical_card_id
  where a.slot_id = p_slot_id;
  if v_card is not null then
    if v_card_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Reserva: sem coleção registrada = da proprietária (C-196).
  select true, coalesce(e.collection_id, p_anchor_collection_id) into v_res, v_res_cl
  from public.collection_layout_slot_expected_content e
  where e.slot_id = p_slot_id;
  if v_res then
    if v_res_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
    v_own := true;
  end if;

  -- Imagem personalizada e região mesclada: sempre do titular / fora da E1-B1.
  if exists (select 1 from public.collection_layout_slot_image i where i.slot_id = p_slot_id) then
    return 'FOREIGN';
  end if;
  if exists (select 1 from public.collection_layout_region r
             where r.page_id = v_page
               and v_row between r.top_row and r.top_row + r.height - 1
               and v_col between r.left_column and r.left_column + r.width - 1) then
    return 'FOREIGN';
  end if;

  -- Referência de espécie: só é de X se registrada para X.
  select sr.collection_id into v_spc_cl
  from public.collection_layout_slot_species_reference sr
  where sr.slot_id = p_slot_id;
  if found then
    if v_spc_cl is distinct from p_collection_id then
      return 'FOREIGN';
    end if;
  end if;

  -- Trava: sem carta nem reserva de X, o bolso fixado é do titular.
  if v_locked and not v_own then
    return 'FOREIGN';
  end if;

  return case when v_own then 'OWN' else 'FREE' end;
end;
$fn$;

-- 3 -----------------------------------------------------------------------------------------
create function public.binder_slot_at(
  p_layout_id    uuid,
  p_page_number  integer,
  p_row_index    integer,
  p_column_index integer
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $fn$
  select s.id
  from public.collection_layout_page p
  join public.collection_layout_slot s on s.page_id = p.id
  where p.layout_id = p_layout_id
    and p.page_number = p_page_number
    and s.row_index = p_row_index
    and s.column_index = p_column_index;
$fn$;

comment on function public.assert_collection_binder_editor(uuid) is
  'V1-13 E1-B1 (5371, interna): autoriza o usuário da sessão como EDITOR ACTIVE da coleção e trava proprietária → layout → convidada → participação. Não amplia a 5122.';
comment on function public.binder_slot_editor_scope(uuid, uuid, uuid, uuid) is
  'V1-13 E1-B1 (5371, interna): classificação C-237 do bolso para a coleção autorizada — OWN | FREE | FOREIGN. Só lê.';
comment on function public.binder_slot_at(uuid, integer, integer, integer) is
  'V1-13 E1-B1 (5371, interna): bolso pela posição visível (página, linha, coluna) do fichário.';

revoke all on function public.assert_collection_binder_editor(uuid) from public, anon, authenticated, service_role;
revoke all on function public.binder_slot_editor_scope(uuid, uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.binder_slot_at(uuid, integer, integer, integer) from public, anon, authenticated, service_role;

do $post$
declare
  f oid;
begin
  foreach f in array array[to_regprocedure('public.assert_collection_binder_editor(uuid)'),
                           to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)'),
                           to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or pg_catalog.has_function_privilege('authenticated', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('anon', f, 'EXECUTE') is not false
       or pg_catalog.has_function_privilege('service_role', f, 'EXECUTE') is not false then
      raise exception 'POSTCHECK 5371: função interna fora do estado esperado (%)', f;
    end if;
  end loop;
  -- A 5122 (ajudante do titular) continua exatamente a canônica: nada aqui a amplia.
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p
       where p.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)'))
     is distinct from 'd600f36fade0b67c0fd5af33e9965070' then
    raise exception 'POSTCHECK 5371: 5122 difere da canônica';
  end if;
end;
$post$;

commit;
