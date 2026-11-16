/* G1 (D-E1) — VERSÃO PROTEGIDA GERADA. Não editar à mão: g1/build_g1_protected.py.
   Base auditada: database/proposals/2026-11-15-v1-13-e1d-shared-reads/5324_create_get_shared_pokedex_positions_function.sql
   sha256 da base: 1e504d6af6a52f2d51604ba5599a539d176ad4ee9e9648fe10e721dffedeb5ff
   Única mudança: porta 5389 consultada antes de qualquer leitura ou efeito em 1 função(ões); precheck da 5389.
   Status: PROPOSTA — NÃO EXECUTADA. Mecanismo não homologado (G1). */
/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5324 - get_shared_pokedex_positions(): grade Pokédex do
              participante (V1-13 · E1-D)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Preparada em
              `V1-13 / E1-D | SECURE SHARED READS-01` (2026-11-15). Execução só
              com prova dinâmica sob protocolo controlado (C-244) e autorização
              expressa e específica.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15
Contrato....: C-242 (leitura de participante da Pokédex, para EDITOR e VIEWER),
              C-243 (nada do acervo fora da coleção), padrão das leituras
              compartilhadas da V1-12 (5320).
Número......: 5324 reservado desde a V1-12 para esta leitura (README da E1-A).

O que faz: a mesma grade da leitura do titular (5204) — espécies do escopo da
  coleção (Pokédex inteira ou gerações escolhidas pelo titular), número
  nacional, geração, arte da espécie, satisfação, exemplares atribuídos NESTA
  coleção e a carta representante (escolhida entre os exemplares desta
  coleção: representante principal, senão a atribuição mais antiga) — para
  quem lê a coleção pela 5302 (OWNER ou VIEWER; o EDITOR é VIEWER para
  leitura, E1-A). Mesmo filtro (ALL/OWNED/MISSING), filtro por geração,
  paginação (≤ 500, deslocamento ≤ 100.000) e ordem nacional.

Diferenças deliberadas em relação à 5204:
  - autorização por collection_share_role (5302) ∈ {OWNER, VIEWER}; qualquer
    outro caso → zero linhas, indistinguível de coleção inexistente;
  - SEM copies_available, copies_elsewhere e acervo_state e SEM a CTE "inv":
    o acervo do titular (exemplares livres ou em outras coleções) nunca é
    lido (C-243). Não há como inferir, pela resposta, se o titular tem a
    espécie fora da coleção;
  - sessão sem usuário → zero linhas (como a 5320).

Mantém da 5204: escopo (FULL_REFERENCE ou collection_pokedex_scope_generation),
  regra de satisfação (posição com ≥ 1 atribuição de exemplar desta coleção),
  escolha do representante, preferência de idioma da imagem (o do exemplar
  representante), arte da espécie IMPORTED. A representante expõe só dados de
  catálogo (nome, número, código do Set, imagem) de um exemplar desta coleção,
  o mesmo nível que a 5313 já expõe; nenhum id de exemplar, alocação, local ou
  condição.

Progresso (total/satisfeitas) do participante já vem da 5310
  (collection_completion_summary_shared, ramo REFERENCE_POSITION); não muda.
Custo: menor que a 5204 (sem a varredura do acervo por espécie). Não medido (E1-E).
Canal.......: psql. Precheck: dependências presentes e função ausente.
Reversão....: R5324 em ROLLBACK_E1D.sql (DROP FUNCTION; não toca dados).
Como validar: harness 5894, seção 3.
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null or to_regprocedure('public.v1_13_capability_open()') is null then raise exception 'PRECHECK G1: barreira 5389 ausente'; end if;  -- G1 (D-E1)
  if to_regprocedure('public.collection_share_role(uuid)') is null
     or to_regprocedure('public.get_my_pokedex_positions(uuid, text, text, integer, integer)') is null
     or to_regclass('public.collection_pokedex_position_assignment') is null
     or to_regclass('public.collection_pokedex_position_primary_representative') is null then
    raise exception 'PRECHECK 5324: dependências ausentes (5302, 5204 e estruturas da Pokédex)';
  end if;
  if exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'get_shared_pokedex_positions') then
    raise exception 'PRECHECK 5324: JÁ APLICADA ou ESTADO DIVERGENTE — get_shared_pokedex_positions já existe';
  end if;
end;
$pre$;

create function public.get_shared_pokedex_positions(
  p_collection_id   uuid,
  p_filter          text    default 'ALL',
  p_generation_code text    default null,
  p_limit           integer default 120,
  p_offset          integer default 0
)
returns table (
  pokedex_position_id             uuid,
  position_number                 integer,
  species_id                      uuid,
  species_name                    text,
  generation_code                 text,
  generation_ordinal              integer,
  species_artwork_path            text,
  is_satisfied                    boolean,
  copies_in_collection            integer,
  representative_card_name        text,
  representative_collector_number text,
  representative_set_code         text,
  representative_image_path       text,
  total_count                     bigint
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
  v_ref    uuid;
  v_dex    uuid;
  v_scope  text;
begin
  if not public.v1_13_capability_open() then return; end if;  -- G1 (D-E1)
  if v_filter not in ('ALL', 'OWNED', 'MISSING') then
    raise exception 'INVALID_FILTER' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 500
     or p_offset is null or p_offset < 0 or p_offset > 100000 then
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

  select cr.id, cpr.pokedex_id, cpr.scope_kind into v_ref, v_dex, v_scope
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr
    on cpr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';
  if v_ref is null then
    return;
  end if;

  return query
  with scope as (
    select pp.id as pos_id, pp.position_number as pnum, s.id as sp_id,
           s.canonical_name::text as sp_name, g.code::text as gcode, g.ordinal_number as gord
    from public.pokedex_position pp
    join public.pokemon_species s    on s.id = pp.species_id
    join public.pokemon_generation g on g.id = s.generation_id
    where pp.pokedex_id = v_dex
      and (v_scope = 'FULL_REFERENCE'
           or exists (select 1 from public.collection_pokedex_scope_generation sg
                      where sg.collection_reference_id = v_ref and sg.generation_id = s.generation_id))
      and (p_generation_code is null or g.code = p_generation_code)
  ),
  links as (
    -- só exemplares alocados a ESTA coleção e atribuídos a uma posição
    select a.pokedex_position_id as pos_id, ca.id as alloc_id, ca.physical_card_id as pc_id,
           a.assigned_at, (pr.collection_allocation_id is not null) as is_rep
    from public.collection_allocation ca
    join public.collection_pokedex_position_assignment a on a.collection_allocation_id = ca.id
    left join public.collection_pokedex_position_primary_representative pr
      on pr.collection_allocation_id = ca.id and pr.collection_id = p_collection_id
    where ca.collection_id = p_collection_id
  ),
  assigned as (
    select l.pos_id, count(*)::integer as n
    from links l
    group by l.pos_id
  ),
  page as (
    select sc.pos_id, sc.pnum, sc.sp_id, sc.sp_name, sc.gcode, sc.gord,
           coalesce(asg.n, 0) as n_in, (asg.pos_id is not null) as sat,
           count(*) over () as total
    from scope sc
    left join assigned asg on asg.pos_id = sc.pos_id
    where v_filter = 'ALL'
       or (v_filter = 'OWNED'   and asg.pos_id is not null)
       or (v_filter = 'MISSING' and asg.pos_id is null)
    order by sc.pnum, sc.pos_id
    limit p_limit offset p_offset
  ),
  rep as (
    select distinct on (l.pos_id) l.pos_id, l.pc_id
    from links l
    where l.pos_id in (select pg.pos_id from page pg where pg.sat)
    order by l.pos_id, l.is_rep desc, l.assigned_at, l.alloc_id
  )
  select p.pos_id, p.pnum, p.sp_id, p.sp_name, p.gcode, p.gord,
         art.path,
         p.sat, p.n_in,
         rc.card_name, rc.number, rc.set_code, rc.image_path,
         p.total
  from page p
  left join lateral (
    select w.display_storage_path::text as path
    from public.pokemon_species_artwork w
    where w.pokemon_species_id = p.sp_id
      and w.status = 'IMPORTED'
      and w.display_storage_path is not null
    order by w.created_at, w.id
    limit 1
  ) art on true
  left join lateral (
    select c.name::text as card_name, c.collector_number::text as number, cs.code::text as set_code,
           img.storage_path::text as image_path
    from rep r
    join public.physical_card pc on pc.id = r.pc_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card c           on c.id = cv.card_id
    join public.card_set cs      on cs.id = c.card_set_id
    left join lateral (
      select ast.storage_path
      from public.card_asset ast
      join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
      join public.language al         on al.id = ast.language_id
      where ast.card_id = c.id
        and ast.is_primary
        and ast.is_active
        and ast.storage_path is not null
      order by (ast.language_id = pc.language_id) desc nulls last,
               (al.code = 'pt-BR') desc,
               (al.code = 'en') desc,
               al.language_order asc
      limit 1
    ) img on true
    where r.pos_id = p.pos_id
  ) rc on true
  order by p.pnum, p.pos_id;
end;
$$;

comment on function public.get_shared_pokedex_positions(uuid, text, text, integer, integer) is
  'V1-13 E1-D (5324): grade Pokédex do participante (OWNER/VIEWER pela 5302; EDITOR lê como VIEWER) — espécies do escopo, arte, satisfação, exemplares e representante desta coleção. Sem copies_available, copies_elsewhere nem acervo_state; nenhuma leitura do acervo (C-243). Mesmo filtro, geração, paginação e ordem da 5204. Sem acesso → zero linhas.';

revoke all on function public.get_shared_pokedex_positions(uuid, text, text, integer, integer) from public, anon;
grant execute on function public.get_shared_pokedex_positions(uuid, text, text, integer, integer) to authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.get_shared_pokedex_positions(uuid, text, text, integer, integer)');
begin
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from 's'
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception 'POSTCHECK 5324: get_shared_pokedex_positions fora do estado esperado';
  end if;
end;
$post$;

commit;
