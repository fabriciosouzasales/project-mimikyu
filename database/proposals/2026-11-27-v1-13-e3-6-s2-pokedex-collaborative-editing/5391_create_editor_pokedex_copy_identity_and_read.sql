/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5391 - Época da participação, identificador opaco do exemplar e
              leitura da posição da Pokédex para o EDITOR (V1-13 · E3-6 / S2)
Versão......: 1.0 (2026-11-27, `E3-6 / S2 + S4 — CONTRACT CONSOLIDATION,
              IMPLEMENTATION PREPARATION & GOVERNANCE OPTIMIZATION-01`)
Status......: PROPOSTA — NÃO EXECUTADA. Execução só com PRE somente leitura
              aprovado (S2_5391_readonly_checks.sql), auditoria independente e
              autorização expressa e específica. Barreira continua CLOSED.
Autor.......: Fabrício Sales / Claude
Decisões....: P0-A (identificador opaco), S2 D1 (época em tabela lateral com
              sequência), D2 (AT_POSITION / ASSIGNABLE + filtro por nome ou número
              nacional), D3 (arquivar/reativar não invalida; escritas revalidam), D4
              (5391 → S4 → 5392 → F3).
Cria........: sequência collection_membership_epoch_seq; tabelas
              collection_membership_epoch e v1_13_copy_token_secret (internas, RLS
              sem políticas, sem privilégios para a API); gatilho
              trg_collection_membership_epoch (AFTER INSERT OR UPDATE OF role, status)
              em collection_membership; ajudantes internos
              collection_membership_epoch_touch(), v1_13_editor_membership(uuid),
              v1_13_pokedex_copy_token(uuid, uuid, bigint); RPC
              get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer).
Não toca....: estrutura de collection_membership (só ganha o gatilho); funções de
              convite/resposta/remoção/saída/papel (5369, 5304, 5305, 5306, 5370 —
              md5 conferido antes e depois); 5367; 5324; 5380; 6118–6126; barreira.
              Nenhuma linha de dado do produto é alterada (só o backfill da tabela
              lateral nova e o segredo).
Travas......: lock_timeout 3 s; `lock table collection_membership in share row
              exclusive mode nowait` antes do gatilho e do backfill (nenhuma
              participação nasce ou muda entre os dois). Conflito → 55P03, nada
              persiste, sem repetição automática.
Requisito...: pgcrypto no esquema `extensions` (hmac, gen_random_bytes); senão o
              precheck aborta (STOP — não adaptar no LIVE).
Reversão....: ROLLBACK_5391.sql (remove tudo o que esta migration cria; nada do
              produto depende dela enquanto a 5392 não existir).
Como validar: static_check_5391.py; S2_5391_readonly_checks.sql (PRE antes, POST
              depois); provas funcionais na homologação autorizada.
================================================================
*/

begin;
set local lock_timeout = '3s';

do $pre$
begin
  -- Barreira presente, canônica, CLOSED, sem identidades.
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0' then
    raise exception 'PRECHECK 5391: barreira 5389 ausente ou divergente';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'PRECHECK 5391: barreira não está CLOSED ou há identidades TEST';
  end if;
  -- pgcrypto no esquema esperado.
  if to_regprocedure('extensions.hmac(bytea, bytea, text)') is null
     or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception 'PRECHECK 5391: pgcrypto ausente do esquema extensions (hmac/gen_random_bytes)';
  end if;
  -- Funções de participação intocadas: corpo canônico.
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.invite_collection_member(uuid, text, text)')) is distinct from '5a5ea20616ded5b1a8e8bfe0487743ff'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_collection_member_role(uuid, uuid, text)')) is distinct from '840d1e5c3cc55f253a2579eda7b7703d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.respond_collection_invite(uuid, boolean)')) is distinct from '08f28dcd1bce04bcf50ad2077bddeaa7'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_collection_member(uuid, uuid)')) is distinct from '2c267678b7ff711fb47d8f6b2ee8071a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.leave_shared_collection(uuid)')) is distinct from 'da8aeedd4a155794e794757590d86f62'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_member_role(uuid)')) is distinct from '1e90ce8a9f4d88c067e9125bf602eff8' then
    raise exception 'PRECHECK 5391: ESTADO DIVERGENTE — funções de participação diferem do canônico';
  end if;
  -- Nenhum gatilho do usuário em collection_membership (o novo é o único).
  if exists (select 1 from pg_catalog.pg_trigger t where t.tgrelid = 'public.collection_membership'::regclass and not t.tgisinternal) then
    raise exception 'PRECHECK 5391: ESTADO DIVERGENTE — gatilho inesperado em collection_membership';
  end if;
  -- Tabelas da Pokédex presentes.
  if to_regclass('public.collection_pokedex_position_assignment') is null
     or to_regclass('public.collection_pokedex_position_primary_representative') is null
     or to_regclass('public.card_primary_species') is null
     or to_regclass('public.collection_pokedex_scope_generation') is null then
    raise exception 'PRECHECK 5391: dependências da Pokédex ausentes';
  end if;
  -- Ainda não aplicada.
  if to_regclass('public.collection_membership_epoch') is not null
     or to_regclass('public.collection_membership_epoch_seq') is not null
     or to_regclass('public.v1_13_copy_token_secret') is not null
     or to_regprocedure('public.collection_membership_epoch_touch()') is not null
     or to_regprocedure('public.v1_13_editor_membership(uuid)') is not null
     or to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)') is not null
     or exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = 'get_editor_pokedex_position_copies') then
    raise exception 'PRECHECK 5391: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

-- Nenhuma participação nasce ou muda entre o gatilho e o backfill.
lock table public.collection_membership in share row exclusive mode nowait;

-- D1 — época da participação (tabela lateral; collection_membership não muda de forma).
create sequence public.collection_membership_epoch_seq as bigint start with 1 increment by 1 no cycle;

create table public.collection_membership_epoch (
  membership_id uuid   primary key
                references public.collection_membership (id) on update restrict on delete cascade,
  role_epoch    bigint not null,
  constraint uq_collection_membership_epoch_value unique (role_epoch),
  constraint chk_collection_membership_epoch_positive check (role_epoch > 0)
);
alter table public.collection_membership_epoch enable row level security;

create function public.collection_membership_epoch_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' then
    if new.role is not distinct from old.role and new.status is not distinct from old.status then
      return null;
    end if;
  end if;
  insert into public.collection_membership_epoch (membership_id, role_epoch)
  values (new.id, nextval('public.collection_membership_epoch_seq'::regclass))
  on conflict (membership_id) do update set role_epoch = excluded.role_epoch;
  return null;
end;
$fn$;

create trigger trg_collection_membership_epoch
after insert or update of role, status on public.collection_membership
for each row execute function public.collection_membership_epoch_touch();

insert into public.collection_membership_epoch (membership_id, role_epoch)
select m.id, nextval('public.collection_membership_epoch_seq'::regclass)
from public.collection_membership m
order by m.id;

-- P0-A — segredo do servidor (nunca devolvido por nenhuma função).
create table public.v1_13_copy_token_secret (
  id         smallint    primary key default 1,
  secret     bytea       not null,
  created_at timestamptz not null default now(),
  constraint chk_v113_copy_token_secret_singleton check (id = 1),
  constraint chk_v113_copy_token_secret_length check (octet_length(secret) = 32)
);
alter table public.v1_13_copy_token_secret enable row level security;
insert into public.v1_13_copy_token_secret (id, secret) values (1, extensions.gen_random_bytes(32));

-- Participação EDITOR ACTIVE da sessão numa coleção ACTIVE de outro titular, com a época vigente.
create function public.v1_13_editor_membership(p_collection_id uuid)
returns table (membership_id uuid, role_epoch bigint, owner_user_id uuid)
language sql
stable
security definer
set search_path = ''
as $fn$
  select m.id, e.role_epoch, c.owner_user_id
  from public.collection c
  join public.collection_membership m
    on m.collection_id = c.id and m.user_id = (select auth.uid()) and m.status = 'ACTIVE' and m.role = 'EDITOR'
  join public.collection_membership_epoch e on e.membership_id = m.id
  where c.id = p_collection_id
    and c.owner_user_id <> (select auth.uid())
    and c.lifecycle_status = 'ACTIVE'
    and (select auth.uid()) is not null;
$fn$;

-- Identificador opaco: alocação + participação + época, HMAC-SHA256 com o segredo. NULL se faltar algo.
create function public.v1_13_pokedex_copy_token(p_allocation_id uuid, p_membership_id uuid, p_role_epoch bigint)
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select 'pc1.' || encode(extensions.hmac(
           convert_to(p_allocation_id::text || '|' || p_membership_id::text || '|' || p_role_epoch::text, 'UTF8'),
           s.secret, 'sha256'), 'hex')
  from public.v1_13_copy_token_secret s
  where s.id = 1
    and p_allocation_id is not null and p_membership_id is not null and p_role_epoch is not null;
$fn$;

create function public.get_editor_pokedex_position_copies(
  p_collection_id       uuid,
  p_pokedex_position_id uuid,
  p_scope               text,
  p_query               text    default null,
  p_limit               integer default 30,
  p_offset              integer default 0
)
returns table (
  copy_token                   text,
  card_name                    text,
  collector_number             text,
  card_set_code                text,
  variant_label                text,
  language_code                text,
  image_path                   text,
  species_match                boolean,
  current_position_id          uuid,
  current_position_number      integer,
  assignment_basis             text,
  is_primary_representative    boolean,
  is_effective_representative  boolean,
  position_representative_mode text,
  total_count                  bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_scope   text := upper(btrim(coalesce(p_scope, '')));
  v_q       text := nullif(btrim(coalesce(p_query, '')), '');
  v_q_num   integer;
  v_like    text;
  v_mid     uuid;
  v_epoch   bigint;
  v_owner   uuid;
  v_ref     uuid;
  v_dex     uuid;
  v_dscope  text;
  v_pos_spc uuid;
  v_pos_num integer;
begin
  perform public.v1_13_assert_capability();  -- barreira: CLOSED → CAPABILITY_NOT_ENABLED (42501)
  if v_scope not in ('AT_POSITION', 'ASSIGNABLE') then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 or p_offset is null or p_offset < 0 or p_offset > 10000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if v_q is not null then
    if v_scope <> 'ASSIGNABLE' or char_length(v_q) > 64 then
      raise exception 'INVALID_ARGUMENT' using errcode = '22023';
    end if;
    if v_q ~ '^[0-9]{1,4}$' then
      v_q_num := v_q::integer;
    else
      v_like := '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    end if;
  end if;
  if p_collection_id is null or p_pokedex_position_id is null then
    return;
  end if;

  -- Fronteira de autorização antes de qualquer leitura de exemplar: só EDITOR ACTIVE de X (ACTIVE).
  select em.membership_id, em.role_epoch, em.owner_user_id into v_mid, v_epoch, v_owner
  from public.v1_13_editor_membership(p_collection_id) em;
  if v_mid is null then
    return;
  end if;

  select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_dscope
  from public.collection c
  join public.collection_reference cr on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id and c.mode = 'REFERENCE_BASED' and c.completion_policy = 'REFERENCE_POSITION';
  if v_ref is null then
    return;
  end if;

  select pp.species_id, pp.position_number into v_pos_spc, v_pos_num
  from public.pokedex_position pp
  join public.pokemon_species s on s.id = pp.species_id
  where pp.id = p_pokedex_position_id
    and pp.pokedex_id = v_dex
    and (v_dscope = 'FULL_REFERENCE'
         or exists (select 1 from public.collection_pokedex_scope_generation sg
                    where sg.collection_reference_id = v_ref and sg.generation_id = s.generation_id));
  if v_pos_spc is null then
    return;
  end if;

  if v_scope = 'AT_POSITION' then
    return query
    with links as (
      select ca.id as alloc_id, ca.physical_card_id as pc_id, a.assignment_basis as basis, a.assigned_at as at_,
             (pr.collection_allocation_id is not null) as is_rep
      from public.collection_allocation ca
      join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
      left join public.collection_pokedex_position_primary_representative pr
        on pr.collection_allocation_id = ca.id and pr.collection_id = p_collection_id
      where ca.collection_id = p_collection_id
        and a.pokedex_position_id = p_pokedex_position_id
    ),
    ranked as (
      select l.alloc_id, l.pc_id, l.basis, l.is_rep,
             row_number() over (order by l.is_rep desc, l.at_, l.alloc_id) as rk,
             bool_or(l.is_rep) over () as any_rep,
             count(*) over () as n_total
      from links l
    ),
    pg as (
      select r.* from ranked r order by r.rk limit p_limit offset p_offset
    )
    select public.v1_13_pokedex_copy_token(pg.alloc_id, v_mid, v_epoch),
           k.name::text, k.collector_number::text, cs.code::text,
           nullif(concat_ws(' · ', vt.name, ppf.name, ecx.name), '')::text,
           lg.code::text,
           img.storage_path::text,
           coalesce((cc.code = 'POKEMON' and cps.pokemon_species_id is not null and cps.pokemon_species_id = v_pos_spc), false),
           p_pokedex_position_id, v_pos_num, pg.basis::text,
           pg.is_rep, (pg.rk = 1),
           case when pg.any_rep then 'CHOSEN' else 'AUTOMATIC' end,
           pg.n_total
    from pg
    join public.physical_card pc                       on pc.id = pg.pc_id
    join public.card_variant cv                        on cv.id = pc.card_variant_id
    join public.card k                                 on k.id = cv.card_id
    join public.card_set cs                            on cs.id = k.card_set_id
    left join public.card_category cc                  on cc.id = k.category_id
    left join public.card_primary_species cps          on cps.card_id = k.id
    left join public.card_variant_type vt              on vt.id = cv.variant_type_id
    left join public.card_printing_profile ppf         on ppf.id = cv.printing_profile_id
    left join public.card_edition_context_profile ecx  on ecx.id = cv.edition_context_profile_id
    left join public.language lg                       on lg.id = pc.language_id
    left join lateral (
      select ast.storage_path
      from public.card_asset ast
      join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
      join public.language al         on al.id = ast.language_id
      where ast.card_id = k.id and ast.is_primary and ast.is_active and ast.storage_path is not null
      order by (ast.language_id = pc.language_id) desc nulls last, (al.code = 'pt-BR') desc, (al.code = 'en') desc, al.language_order asc
      limit 1
    ) img on true
    order by pg.rk;
    return;
  end if;

  -- ASSIGNABLE: só exemplares ALOCADOS a X (nunca o acervo), sem posição ou em outra posição.
  return query
  with el as (
    select ca.id as alloc_id, ca.physical_card_id as pc_id,
           a.pokedex_position_id as cur_pos, a.assignment_basis as basis,
           k.id as k_id, k.name::text as k_name, k.collector_number::text as k_num, k.collector_order as k_ord,
           cs.code::text as s_code, lg.code::text as l_code,
           coalesce((cc.code = 'POKEMON' and cps.pokemon_species_id is not null and cps.pokemon_species_id = v_pos_spc), false) as is_match
    from public.collection_allocation ca
    join public.physical_card pc              on pc.id = ca.physical_card_id
    join public.card_variant cv               on cv.id = pc.card_variant_id
    join public.card k                        on k.id = cv.card_id
    join public.card_set cs                   on cs.id = k.card_set_id
    left join public.card_category cc         on cc.id = k.category_id
    left join public.card_primary_species cps on cps.card_id = k.id
    left join public.pokemon_species ps       on ps.id = cps.pokemon_species_id
    left join public.language lg              on lg.id = pc.language_id
    left join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    where ca.collection_id = p_collection_id
      and a.pokedex_position_id is distinct from p_pokedex_position_id
      and (v_q is null
           or (v_q_num is not null and ps.national_dex_number = v_q_num)
           or (v_like is not null and (k.name ilike v_like escape '\' or ps.canonical_name ilike v_like escape '\')))
  ),
  ranked as (
    select el.*,
           row_number() over (order by el.is_match desc, (el.cur_pos is null) desc, el.k_name, el.s_code,
                                       el.k_ord, el.k_num, el.l_code, el.alloc_id) as rk,
           count(*) over () as n_total
    from el
  ),
  pg as (
    select r.* from ranked r order by r.rk limit p_limit offset p_offset
  )
  select public.v1_13_pokedex_copy_token(pg.alloc_id, v_mid, v_epoch),
         pg.k_name, pg.k_num, pg.s_code,
         nullif(concat_ws(' · ', vt.name, ppf.name, ecx.name), '')::text,
         pg.l_code,
         img.storage_path::text,
         pg.is_match,
         pg.cur_pos, cp.position_number, pg.basis::text,
         null::boolean, null::boolean, null::text,
         pg.n_total
  from pg
  join public.physical_card pc                       on pc.id = pg.pc_id
  join public.card_variant cv                        on cv.id = pc.card_variant_id
  left join public.card_variant_type vt              on vt.id = cv.variant_type_id
  left join public.card_printing_profile ppf         on ppf.id = cv.printing_profile_id
  left join public.card_edition_context_profile ecx  on ecx.id = cv.edition_context_profile_id
  left join public.pokedex_position cp               on cp.id = pg.cur_pos
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = pg.k_id and ast.is_primary and ast.is_active and ast.storage_path is not null
    order by (ast.language_id = pc.language_id) desc nulls last, (al.code = 'pt-BR') desc, (al.code = 'en') desc, al.language_order asc
    limit 1
  ) img on true
  order by pg.rk;
end;
$fn$;

comment on table public.collection_membership_epoch is
  'V1-13 E3-6/S2 (5391, interna): época da participação. Novo valor da sequência a cada inclusão e a cada mudança de role/status; nunca reutilizado. Invalida os identificadores opacos (P0-A). Sem acesso pela API.';
comment on table public.v1_13_copy_token_secret is
  'V1-13 E3-6/S2 (5391, interna): segredo do HMAC dos identificadores opacos de exemplar. Nunca devolvido. Trocar o segredo invalida todos os identificadores (emergência, nunca automático).';
comment on function public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer) is
  'V1-13 E3-6/S2 (5391): exemplares da posição (AT_POSITION) ou atribuíveis a ela (ASSIGNABLE, só exemplares alocados à coleção) para o EDITOR ACTIVE. Identificador opaco por alocação+participação+época; só catálogo e organização da coleção; nunca identificadores físicos, local, condição ou valores. Sem acesso → zero linhas.';

revoke all on sequence public.collection_membership_epoch_seq from public, anon, authenticated, service_role;
revoke all on table public.collection_membership_epoch from public, anon, authenticated, service_role;
revoke all on table public.v1_13_copy_token_secret from public, anon, authenticated, service_role;
revoke all on function public.collection_membership_epoch_touch() from public, anon, authenticated, service_role;
revoke all on function public.v1_13_editor_membership(uuid) from public, anon, authenticated, service_role;
revoke all on function public.v1_13_pokedex_copy_token(uuid, uuid, bigint) from public, anon, authenticated, service_role;
revoke all on function public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer) from public, anon, service_role;
grant execute on function public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer) to authenticated;

do $post$
declare
  v_read oid := to_regprocedure('public.get_editor_pokedex_position_copies(uuid, uuid, text, text, integer, integer)');
  f      oid;
  r      text;
begin
  -- RPC: definer, search_path vazio, STABLE, só authenticated.
  if v_read is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_read) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_read) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_read) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', v_read, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_read, 'EXECUTE') is not false
     or pg_catalog.has_function_privilege('service_role', v_read, 'EXECUTE') is not false
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_read and a.grantee = 0) then
    raise exception 'POSTCHECK 5391: RPC fora do estado esperado';
  end if;
  -- Ajudantes internos: definer, search_path vazio, nenhum papel da API executa.
  foreach f in array array[to_regprocedure('public.collection_membership_epoch_touch()'),
                           to_regprocedure('public.v1_13_editor_membership(uuid)'),
                           to_regprocedure('public.v1_13_pokedex_copy_token(uuid, uuid, bigint)')] loop
    if f is null
       or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = f) is not true
       or (select p.proconfig from pg_catalog.pg_proc p where p.oid = f) is distinct from array['search_path=""']
       or exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                  and pg_catalog.has_function_privilege(x.oid, f, 'EXECUTE')) then
      raise exception 'POSTCHECK 5391: ajudante interno fora do estado esperado (%)', f;
    end if;
  end loop;
  -- Tabelas e sequência internas: RLS ligada (tabelas), nenhum privilégio para a API.
  foreach r in array array['public.collection_membership_epoch', 'public.v1_13_copy_token_secret'] loop
    if (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = to_regclass(r)) is not true
       or exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
                  and (pg_catalog.has_table_privilege(x.oid, to_regclass(r), 'SELECT')
                       or pg_catalog.has_table_privilege(x.oid, to_regclass(r), 'INSERT')
                       or pg_catalog.has_table_privilege(x.oid, to_regclass(r), 'UPDATE')
                       or pg_catalog.has_table_privilege(x.oid, to_regclass(r), 'DELETE'))) then
      raise exception 'POSTCHECK 5391: tabela interna exposta (%)', r;
    end if;
  end loop;
  if exists (select 1 from pg_catalog.pg_roles x where x.rolname in ('anon', 'authenticated', 'service_role', 'authenticator')
             and (pg_catalog.has_sequence_privilege(x.oid, 'public.collection_membership_epoch_seq', 'USAGE')
                  or pg_catalog.has_sequence_privilege(x.oid, 'public.collection_membership_epoch_seq', 'SELECT')
                  or pg_catalog.has_sequence_privilege(x.oid, 'public.collection_membership_epoch_seq', 'UPDATE'))) then
    raise exception 'POSTCHECK 5391: sequência exposta';
  end if;
  -- Gatilho presente e habilitado; época para toda participação; valores únicos.
  if not exists (select 1 from pg_catalog.pg_trigger t
                 where t.tgrelid = 'public.collection_membership'::regclass and t.tgname = 'trg_collection_membership_epoch'
                   and t.tgenabled = 'O' and not t.tgisinternal) then
    raise exception 'POSTCHECK 5391: gatilho de época ausente ou desabilitado';
  end if;
  if (select count(*) from public.collection_membership) <> (select count(*) from public.collection_membership_epoch)
     or exists (select 1 from public.collection_membership m
                where not exists (select 1 from public.collection_membership_epoch e where e.membership_id = m.id)) then
    raise exception 'POSTCHECK 5391: participação sem época';
  end if;
  if (select count(*) from public.v1_13_copy_token_secret where id = 1 and octet_length(secret) = 32) <> 1 then
    raise exception 'POSTCHECK 5391: segredo ausente';
  end if;
  -- Funções de participação intocadas.
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.invite_collection_member(uuid, text, text)')) is distinct from '5a5ea20616ded5b1a8e8bfe0487743ff'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.set_collection_member_role(uuid, uuid, text)')) is distinct from '840d1e5c3cc55f253a2579eda7b7703d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.respond_collection_invite(uuid, boolean)')) is distinct from '08f28dcd1bce04bcf50ad2077bddeaa7'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.remove_collection_member(uuid, uuid)')) is distinct from '2c267678b7ff711fb47d8f6b2ee8071a'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.leave_shared_collection(uuid)')) is distinct from 'da8aeedd4a155794e794757590d86f62'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_member_role(uuid)')) is distinct from '1e90ce8a9f4d88c067e9125bf602eff8' then
    raise exception 'POSTCHECK 5391: funções de participação alteradas';
  end if;
  if (select s.mode from public.v1_13_barrier_state s where s.id = 1) is distinct from 'CLOSED'
     or (select count(*) from public.v1_13_barrier_identity) <> 0 then
    raise exception 'POSTCHECK 5391: barreira não está CLOSED';
  end if;
end;
$post$;

commit;
