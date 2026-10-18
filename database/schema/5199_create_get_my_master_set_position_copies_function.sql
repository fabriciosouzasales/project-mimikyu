/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5199 - get_my_master_set_position_copies(): exemplares
              livres do acervo que satisfazem UMA posição do Master Set
Versão......: 1.1 (READINESS-01: paginação por offset; coleção arquivada
              → zero linhas; card_variant_id removido do retorno)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização de
              Fabrício, POSITION-COPIES-LIVE-GATE-01) — ledger
              20261018204909; 5842 v1.1 30/30 PASS (GATE PASS, 99.1
              resíduo zero, conferido também fora do harness); p95 14,38 ms
              no maior Set real (304 exemplares elegíveis). CANÔNICA desde
              2026-10-18 (5199-CLOSEOUT): corpo idêntico ao LIVE — md5 de
              prosrc 7b54d663a0dc05fd0707cb430b63bbfa = corpo deste arquivo.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-FRONTEND-PHASE-02 /
              MASTER-SET-POSITION-COPIES-READINESS-01)

Por quê (lacuna real, não preferência):
  A grade do Master Set (5189/5198) informa, por posição (carta +
  acabamento), quantos exemplares do acervo estão livres
  (copies_available), mas nenhum contrato customer-facing diz QUAIS são.
  Os contratos do Meu acervo (5159/5162) agrupam por card_variant_id +
  idioma e não expõem o acabamento (variant_type); card_variant e seus
  eixos têm RLS admin-only (ADR-022). Sem esta leitura, a interface só
  poderia escolher o exemplar comparando textos de rótulo — heurística
  que não garante que o exemplar vinculado satisfaça a posição.

Contrato:
  get_my_master_set_position_copies(
      p_collection_id   uuid,
      p_card_id         uuid,
      p_variant_type_id uuid    default null,  -- null = posição genérica de carta secreta
      p_limit           integer default 50,    -- 1..100
      p_offset          integer default 0)     -- 0..10000
  → physical_card_id, variant_label, is_default_variant, language_code,
    language_name, storage_name, added_at, total_count

  Fronteira (respostas idênticas, sem enumerar):
  - coleção inexistente, de outro usuário, arquivada, livre, Pokédex ou
    em Set padrão → zero linhas;
  - posição (p_card_id, p_variant_type_id) fora do objetivo vigente
    (master_set_positions com os acabamentos gravados; comparação
    NULL-safe) → zero linhas. A posição genérica de secreta só existe
    quando a secreta não tem nenhum acabamento escolhido.

  Elegibilidade (mesma regra de copies_available em 5189/5198 — o total
  desta leitura é igual a copies_available da posição):
  - exemplar do acervo do usuário da sessão;
  - da carta, no acabamento da posição (qualquer acabamento na posição
    genérica);
  - SEM vínculo com nenhuma coleção (collection_allocation, UNIQUE por
    exemplar);
  - qualquer idioma, contexto de edição ou perfil de impressão (C-187):
    eles não criam posições nem impedem a satisfação.

  Só leitura (STABLE). Quem vincula continua sendo a 5046
  (allocate_physical_cards_to_collection), sem mudança: trava a coleção,
  confere dono/Set/coleção ativa e recusa exemplar já vinculado. Esta
  leitura não promete exclusividade entre a leitura e o vínculo.

  Retorno mínimo: physical_card_id é o único identificador (necessário
  para a 5046); nada de card_variant_id, inventário, local por id ou
  dados de outro usuário. storage_name só do próprio acervo.

  Ordem determinística: variante padrão primeiro, idioma do catálogo
  (language_order), mais antigo primeiro, id do exemplar como desempate.

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes de qualquer tabela de catálogo ou acervo, EXECUTE só authenticated.
Erros: 28000 not_authenticated; 22023 INVALID_PAGE; 22023
INVALID_POSITION (p_card_id nulo).
Desempenho: master_set_positions do Set (algumas centenas de linhas, uma
vez) + card_variant por card_id (ix_card_variant_card_id) →
physical_card por (inventory_id, card_variant_id)
(ix_physical_card_inventory_variant) → allocation por physical_card_id
(UNIQUE). Custo proporcional às variantes e exemplares de UMA carta.
Como validar: 5842 v1.1.
Recuperação: drop function if exists
  public.get_my_master_set_position_copies(uuid, uuid, uuid, integer, integer);
================================================================
*/

begin;

create or replace function public.get_my_master_set_position_copies(
  p_collection_id   uuid,
  p_card_id         uuid,
  p_variant_type_id uuid    default null,
  p_limit           integer default 50,
  p_offset          integer default 0
)
returns table (
  physical_card_id   uuid,
  variant_label      text,
  is_default_variant boolean,
  language_code      text,
  language_name      text,
  storage_name       text,
  added_at           timestamptz,
  total_count        bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user      uuid := auth.uid();
  v_set       uuid;
  v_types     uuid[];
  v_inventory uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
     or p_offset is null or p_offset < 0 or p_offset > 10000 then
    raise exception 'INVALID_PAGE' using errcode = '22023';
  end if;

  if p_card_id is null then
    raise exception 'INVALID_POSITION' using errcode = '22023';
  end if;

  -- Fronteira de autorização antes de qualquer tabela de catálogo/acervo.
  select ccsr.card_set_id into v_set
  from public.collection c
  join public.collection_reference cr            on cr.collection_id = c.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.lifecycle_status = 'ACTIVE'
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'MASTER_SET';

  if v_set is null then
    return;
  end if;

  select array_agg(f.variant_type_id) into v_types
  from public.collection_master_set_finish f
  where f.collection_id = p_collection_id;

  -- A posição precisa existir no objetivo vigente (NULL-safe).
  if not exists (
    select 1
    from public.master_set_positions(v_set, coalesce(v_types, '{}'::uuid[])) p
    where p.card_id = p_card_id
      and p.variant_type_id is not distinct from p_variant_type_id
  ) then
    return;
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;
  end if;

  return query
  with eligible as (
    select pc.id, pc.language_id, pc.storage_container_id, pc.created_at,
           cv.is_default,
           nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text as label
    from public.card_variant cv
    join public.physical_card pc on pc.card_variant_id = cv.id
                                and pc.inventory_id = v_inventory
    left join public.card_variant_type vt            on vt.id = cv.variant_type_id
    left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
    left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
    where cv.card_id = p_card_id
      and (p_variant_type_id is null or cv.variant_type_id = p_variant_type_id)
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
  )
  select e.id, e.label, e.is_default,
         l.code::text, l.name::text,
         sc.name::text,
         e.created_at,
         count(*) over ()
  from eligible e
  join public.language l                 on l.id = e.language_id
  left join public.storage_container sc  on sc.id = e.storage_container_id
                                        and sc.inventory_id = v_inventory
  order by e.is_default desc, l.language_order asc nulls last, e.created_at asc, e.id asc
  limit p_limit offset p_offset;
end;
$$;

comment on function public.get_my_master_set_position_copies(uuid, uuid, uuid, integer, integer) is
  'Master Set (Query 5199): exemplares do acervo do usuário, sem vínculo com coleção, que satisfazem uma posição (carta + acabamento, ou carta secreta genérica) do objetivo vigente de uma coleção MASTER_SET ativa dele. Só leitura, paginada; quem vincula é a 5046. Coleção alheia/arquivada ou posição fora do objetivo → zero linhas.';

revoke all on function public.get_my_master_set_position_copies(uuid, uuid, uuid, integer, integer) from public, anon;
grant execute on function public.get_my_master_set_position_copies(uuid, uuid, uuid, integer, integer) to authenticated;

commit;
