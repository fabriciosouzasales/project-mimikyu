/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5200 - get_my_master_set_link_candidates(): um exemplar
              livre do acervo por posição ainda faltante do Master Set
              ("Adicionar cartas" em lote, irmã da 5170)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização de
              Fabrício, MASTER-SET-LINK-CANDIDATES-LIVE-01) — ledger
              20261019001438; 5843 v1.0 25/25 PASS (GATE PASS, 99.1
              resíduo zero, conferido também fora do harness). Na coleção
              real ME5 (194 posições): 93 candidatos em 23,5 ms; limite 1
              em 7,2 ms. CANÔNICA em database/schema/ (corpo = LIVE, md5
              de prosrc e3808d1cac7f7e8fe87325ef63bc17f1).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-LINK-CANDIDATES-01)

Por quê (lacuna real):
  O "Adicionar cartas (N)" do Set padrão usa a 5170, que escolhe UM
  exemplar por CARTA e só aceita coleção STANDARD_SET. No Master Set a
  unidade é a POSIÇÃO (carta + acabamento; carta secreta sem acabamento
  escolhido = posição genérica). Sem esta leitura, a interface teria de
  chamar a 5199 uma vez por posição (N+1: 194 chamadas no ME5).

Contrato:
  get_my_master_set_link_candidates(p_collection_id uuid,
                                    p_limit integer default 500)   -- 1..500
  → physical_card_id, card_id, variant_type_id, collector_number,
    card_name, variant_type_name, is_secret, language_code, image_path,
    total_count

  - Uma linha por posição do objetivo vigente (master_set_positions com
    os acabamentos gravados) que ainda NÃO está satisfeita nesta coleção
    e para a qual existe exemplar livre no acervo do usuário.
  - Exemplar elegível = a mesma regra da 5199/5198 (copies_available):
    do acervo do usuário, da carta, no acabamento da posição (qualquer
    acabamento na genérica), sem vínculo com nenhuma coleção. Idioma,
    edição e impressão não criam posição nem impedem (C-187).
  - Escolha determinística por posição (a mesma ordem da 5199): variante
    padrão, language_order, mais antigo, id.
  - Um exemplar nunca aparece em duas posições: cada exemplar tem um
    único acabamento e uma carta tem OU posições por acabamento OU a
    genérica (nunca as duas) — então o lote inteiro é aceito pela 5046.
  - Ordem do Set (collector_order, número, ordem do acabamento).
    total_count = total antes do limite; ≤ 500 = teto da 5046. O cliente
    relê depois de cada lote (a leitura recalcula do estado atual; um
    reenvio não duplica — a 5046 recusa exemplar já vinculado).
  - Coleção inexistente, de outro usuário, arquivada, livre, Pokédex ou
    em Set padrão → zero linhas (mesma resposta).
  - Retorno mínimo: physical_card_id é o único identificador de acervo
    (necessário para a 5046); card_id/variant_type_id identificam a
    posição (catálogo público do Set já exposto pela 5189/5198).

A escrita continua sendo a 5046 (allocate_physical_cards_to_collection),
sem alteração.

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes de qualquer tabela de catálogo/acervo, EXECUTE só authenticated.
Erros: 28000 not_authenticated; 22023 INVALID_LIMIT.
Desempenho: mesma forma da 5198 (agregações únicas; janela por posição
sobre os exemplares livres do Set; anti-join por UNIQUE de
collection_allocation(physical_card_id)); arte só nas linhas devolvidas.
Como validar: 5843 v1.0.
Recuperação: drop function if exists
  public.get_my_master_set_link_candidates(uuid, integer);
================================================================
*/

begin;

create or replace function public.get_my_master_set_link_candidates(
  p_collection_id uuid,
  p_limit         integer default 500
)
returns table (
  physical_card_id  uuid,
  card_id           uuid,
  variant_type_id   uuid,
  collector_number  text,
  card_name         text,
  variant_type_name text,
  is_secret         boolean,
  language_code     text,
  image_path        text,
  total_count       bigint
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

  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'INVALID_LIMIT' using errcode = '22023';
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

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return;
  end if;

  return query
  with positions as (
    select p.card_id, p.variant_type_id, p.is_secret
    from public.master_set_positions(v_set, coalesce(v_types, '{}'::uuid[])) p
  ),
  in_collection as (
    select distinct cv.card_id, cv.variant_type_id
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
  ),
  missing as (
    select p.*
    from positions p
    where not exists (
      select 1 from in_collection ic
      where ic.card_id = p.card_id
        and (p.variant_type_id is null or ic.variant_type_id = p.variant_type_id)
    )
  ),
  free_copies as (
    select pc.id, pc.language_id, pc.created_at, cv.card_id, cv.variant_type_id, cv.is_default
    from public.physical_card pc
    join public.card_variant cv on cv.id = pc.card_variant_id
    join public.card c          on c.id = cv.card_id and c.card_set_id = v_set
    where pc.inventory_id = v_inventory
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = pc.id)
  ),
  ranked as (
    select m.card_id, m.variant_type_id, m.is_secret,
           f.id as pc_id, f.language_id,
           row_number() over (partition by m.card_id, m.variant_type_id
                              order by f.is_default desc, l.language_order asc nulls last, f.created_at, f.id) as rn
    from missing m
    join free_copies f on f.card_id = m.card_id
                      and (m.variant_type_id is null or f.variant_type_id = m.variant_type_id)
    left join public.language l on l.id = f.language_id
  ),
  picked as (
    select r.*, c.collector_order, c.collector_number::text as number, c.name::text as card_name,
           t.name::text as type_name, coalesce(t.display_order, 2147483647) as type_order,
           count(*) over () as total
    from ranked r
    join public.card c                   on c.id = r.card_id
    left join public.card_variant_type t on t.id = r.variant_type_id
    where r.rn = 1
    order by c.collector_order, c.collector_number, coalesce(t.display_order, 2147483647), r.card_id
    limit p_limit
  )
  select k.pc_id, k.card_id, k.variant_type_id, k.number, k.card_name, k.type_name, k.is_secret,
         lang.code::text,
         img.storage_path::text,
         k.total
  from picked k
  left join public.language lang on lang.id = k.language_id
  left join lateral (
    select ast.storage_path
    from public.card_asset ast
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al         on al.id = ast.language_id
    where ast.card_id = k.card_id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by (ast.language_id = k.language_id) desc nulls last,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) img on true
  order by k.collector_order, k.number, k.type_order, k.card_id;
end;
$$;

comment on function public.get_my_master_set_link_candidates(uuid, integer) is
  'Master Set (Query 5200): um exemplar livre do acervo do usuário por posição ainda faltante (carta + acabamento, ou carta secreta genérica) do objetivo vigente de uma coleção MASTER_SET ativa dele — "Adicionar cartas" em lote. ≤ 500 por chamada (teto de 5046). Coleção alheia/arquivada/não Master Set → zero linhas.';

revoke all on function public.get_my_master_set_link_candidates(uuid, integer) from public, anon;
grant execute on function public.get_my_master_set_link_candidates(uuid, integer) to authenticated;

commit;
