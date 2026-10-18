/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5191 - get_my_master_set_finish_options(): acabamentos
              disponíveis no Set de uma coleção (Ajustes → Objetivo)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Autoridade: C-188 (edição permanente em Ajustes), C-187 (só acabamentos
existentes no Set), C-189 (bloco de secretas, informativo).

Contrato:
  get_my_master_set_finish_options(p_collection_id uuid)
  Funciona com a coleção em STANDARD_SET (para ativar) ou MASTER_SET
  (para editar). Linhas:
    row_kind = 'FINISH' — uma por acabamento com ≥ 1 carta ativa com
      variante ativa no Set: variant_type_id, code, name, display_order,
      positions (cartas do Set nesse acabamento), owned_positions (dessas,
      quantas a coleção já satisfaz), is_selected (está gravado em
      collection_master_set_finish — inclusive quando a coleção está em
      STANDARD_SET, para "restaurar o objetivo guardado").
    row_kind = 'SECRET_CARDS' — no máximo uma: positions = cartas secretas
      do Set (sempre no objetivo); owned_positions = quantas têm ao menos
      um exemplar na coleção. Campos de acabamento NULL.
  Acabamentos gravados que deixaram de existir no Set não aparecem como
  opção; continuam gravados e não geram posição (LDM-195).
  A sugestão inicial (Padrão, Holográfica, Holográfica Reverse) é
  decidida na interface, não aqui.
  Coleção alheia, inexistente, livre ou Pokédex → zero linhas.

Segurança: SECURITY DEFINER, STABLE, search_path '', dono por auth.uid()
antes do catálogo, EXECUTE só authenticated. Erro: 28000.
Como validar: 5836 casos 2.x e 6.x.
================================================================
*/

begin;

create or replace function public.get_my_master_set_finish_options(
  p_collection_id uuid
)
returns table (
  row_kind          text,
  variant_type_id   uuid,
  variant_type_code text,
  variant_type_name text,
  display_order     integer,
  positions         integer,
  owned_positions   integer,
  is_selected       boolean
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_set  uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select ccsr.card_set_id into v_set
  from public.collection c
  join public.collection_reference cr            on cr.collection_id = c.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where c.id = p_collection_id
    and c.owner_user_id = v_user
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy in ('STANDARD_SET', 'MASTER_SET');

  if v_set is null then
    return;
  end if;

  return query
  with owned as (
    select distinct cv.card_id, cv.variant_type_id
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    where ca.collection_id = p_collection_id
  ),
  pairs as (
    select distinct c.id as card_id, cv.variant_type_id
    from public.card c
    join public.card_variant cv on cv.card_id = c.id and cv.is_active
    where c.card_set_id = v_set
      and c.is_active
  ),
  secrets as (
    select p.card_id
    from public.master_set_positions(v_set, '{}'::uuid[]) p
    where p.is_secret
  )
  select 'FINISH'::text, t.id, t.code::text, t.name::text, t.display_order,
         count(*)::integer,
         count(o.card_id)::integer,
         exists (select 1 from public.collection_master_set_finish f
                 where f.collection_id = p_collection_id and f.variant_type_id = t.id)
  from pairs pr
  join public.card_variant_type t on t.id = pr.variant_type_id
  left join owned o on o.card_id = pr.card_id and o.variant_type_id = pr.variant_type_id
  group by t.id, t.code, t.name, t.display_order
  union all
  select 'SECRET_CARDS'::text, null::uuid, null::text, null::text, null::integer,
         count(*)::integer,
         count(*) filter (where exists (select 1 from owned o where o.card_id = s.card_id))::integer,
         true
  from secrets s
  having count(*) > 0
  order by 1, 5, 2;
end;
$$;

comment on function public.get_my_master_set_finish_options(uuid) is
  'Master Set (Query 5191): acabamentos existentes no Set de uma coleção de Set do usuário, com posições, posições já satisfeitas e seleção gravada; mais o bloco de cartas secretas (sempre no objetivo). Coleção alheia → zero linhas.';

revoke all on function public.get_my_master_set_finish_options(uuid) from public, anon;
grant execute on function public.get_my_master_set_finish_options(uuid) to authenticated;

commit;
