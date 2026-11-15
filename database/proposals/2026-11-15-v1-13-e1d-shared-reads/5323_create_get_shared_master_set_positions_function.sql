/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5323 - get_shared_master_set_positions(): grade Master Set do
              participante (V1-13 · E1-D)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-D | SECURE SHARED READS-01` (2026-11-15). Execução só
              com prova dinâmica sob protocolo controlado (C-244) e autorização
              expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-242 (leitura de participante do Master Set, para EDITOR e
              VIEWER), C-243 (nada do acervo fora da coleção), C-187–C-190
              (posições por acabamento), padrão das leituras compartilhadas da
              V1-12 (5320).
Número......: 5323 reservado desde a V1-12 para esta leitura (README da E1-A).

O que faz: a mesma grade da leitura do titular (5198) — posições (carta +
  acabamento, e carta secreta), arte, satisfação e exemplares NESTA coleção —
  para quem lê a coleção pela 5302 (OWNER ou VIEWER; o EDITOR é VIEWER para
  leitura, E1-A). Mesmo filtro (ALL/OWNED/MISSING), mesma paginação (≤ 500,
  deslocamento ≤ 100.000), mesma ordem e mesma regra de satisfação.

Diferenças deliberadas em relação à 5198 (o espelho é só da parte segura):
  - autorização por collection_share_role (5302) ∈ {OWNER, VIEWER}; qualquer
    outro caso (não membro, convite pendente, membro removido, PUBLIC, sessão
    anônima) → zero linhas, indistinguível de coleção inexistente;
  - SEM copies_available e SEM a CTE "available": o acervo livre do titular
    nunca é lido (C-243). Nenhuma leitura de inventory, local, condição,
    certificação, valores ou outras coleções;
  - sessão sem usuário não levanta 'not_authenticated' (como a 5320): zero linhas.

Mantém da 5198: master_set_positions(set, acabamentos da coleção) — escopo e
  acabamentos do titular (C-239); exemplares na coleção = alocações desta
  coleção; posição com acabamento soma o par exato, posição secreta soma a
  carta; idioma da imagem = menor language_id dos exemplares da coleção.

Custo: igual ou menor que a 5198 (uma agregação a menos; nenhuma varredura do
  acervo). Não medido (E1-E).
Canal.......: psql. Precheck: dependências presentes e função ausente.
Reversão....: R5323 em ROLLBACK_E1D.sql (DROP FUNCTION; não toca dados).
Como validar: harness 5894, seção 2.
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.collection_share_role(uuid)') is null
     or to_regprocedure('public.master_set_positions(uuid, uuid[])') is null
     or to_regprocedure('public.get_my_master_set_positions(uuid, text, integer, integer)') is null then
    raise exception 'PRECHECK 5323: dependências ausentes (5302, 5187, 5198)';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'get_shared_master_set_positions') then
    raise exception 'PRECHECK 5323: JÁ APLICADA ou ESTADO DIVERGENTE — get_shared_master_set_positions já existe';
  end if;
end;
$pre$;

create function public.get_shared_master_set_positions(
  p_collection_id uuid,
  p_filter        text    default 'ALL',
  p_limit         integer default 200,
  p_offset        integer default 0
)
returns table (
  card_id              uuid,
  collector_number     text,
  collector_total      integer,
  card_name            text,
  variant_type_id      uuid,
  variant_type_code    text,
  variant_type_name    text,
  is_secret            boolean,
  image_path           text,
  is_satisfied         boolean,
  copies_in_collection integer,
  total_count          bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_filter text := upper(btrim(coalesce(p_filter, 'ALL')));
  v_role   text;
  v_set    uuid;
  v_types  uuid[];
begin
  if v_filter not in ('ALL', 'OWNED', 'MISSING') then
    raise exception 'INVALID_FILTER' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 500 or p_offset is null or p_offset < 0 or p_offset > 100000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;
  if p_collection_id is null then
    return;
  end if;

  -- Fronteira de autorização antes de qualquer tabela de catálogo (padrão 5320).
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    return;
  end if;

  select ccsr.card_set_id into v_set
  from public.collection c
  join public.collection_reference cr            on cr.collection_id = c.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'MASTER_SET';
  if v_set is null then
    return;
  end if;

  select array_agg(f.variant_type_id) into v_types
  from public.collection_master_set_finish f
  where f.collection_id = p_collection_id;

  return query
  with positions as (
    select p.card_id, p.variant_type_id, p.is_secret
    from public.master_set_positions(v_set, v_types) p
  ),
  in_collection as (
    -- só as alocações DESTA coleção (nenhuma leitura do acervo livre)
    select cv.card_id, cv.variant_type_id, count(*)::integer as copies,
           min(pc.language_id::text)::uuid as lang
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
    group by cv.card_id, cv.variant_type_id
  ),
  in_by_card as (
    select ic.card_id, sum(ic.copies)::integer as copies, min(ic.lang::text) as lang
    from in_collection ic
    group by ic.card_id
  ),
  pos_rows as (
    select
      c.id                         as card_id,
      c.collector_number::text     as number,
      c.collector_total            as collector_total,
      c.name::text                 as card_name,
      c.collector_order            as collector_order,
      p.variant_type_id            as variant_type_id,
      t.code::text                 as type_code,
      t.name::text                 as type_name,
      coalesce(t.display_order, 2147483647) as type_order,
      p.is_secret                  as is_secret,
      case when p.variant_type_id is null then icc.copies else icp.copies end as in_copies,
      (case when p.variant_type_id is null then icc.lang else icp.lang::text end)::uuid as lang
    from positions p
    join public.card c                    on c.id = p.card_id
    left join public.card_variant_type t  on t.id = p.variant_type_id
    left join in_collection icp           on icp.card_id = p.card_id and icp.variant_type_id = p.variant_type_id
    left join in_by_card icc              on icc.card_id = p.card_id
  ),
  filtered as (
    select r.*, (coalesce(r.in_copies, 0) > 0) as satisfied, count(*) over () as total
    from pos_rows r
    where v_filter = 'ALL'
       or (v_filter = 'OWNED'   and coalesce(r.in_copies, 0) > 0)
       or (v_filter = 'MISSING' and coalesce(r.in_copies, 0) = 0)
    order by r.collector_order, r.number, r.type_order, r.card_id
    limit p_limit offset p_offset
  )
  select f.card_id, f.number, f.collector_total, f.card_name,
         f.variant_type_id, f.type_code, f.type_name, f.is_secret,
         img.storage_path::text,
         f.satisfied,
         coalesce(f.in_copies, 0),
         f.total
  from filtered f
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = f.card_id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = f.lang) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by f.collector_order, f.number, f.type_order, f.card_id;
end;
$$;

comment on function public.get_shared_master_set_positions(uuid, text, integer, integer) is
  'V1-13 E1-D (5323): grade Master Set do participante (OWNER/VIEWER pela 5302; EDITOR lê como VIEWER) — posições por acabamento, arte, satisfação e exemplares desta coleção. Sem copies_available e sem leitura do acervo (C-243). Mesmo filtro, paginação e ordem da 5198. Sem acesso → zero linhas.';

revoke all on function public.get_shared_master_set_positions(uuid, text, integer, integer) from public, anon;
grant execute on function public.get_shared_master_set_positions(uuid, text, integer, integer) to authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.get_shared_master_set_positions(uuid, text, integer, integer)');
begin
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception 'POSTCHECK 5323: get_shared_master_set_positions fora do estado esperado';
  end if;
end;
$post$;

commit;
