/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5160 - get_my_inventory_summary(): resumo de Meu acervo
              (MY-INVENTORY-IMPLEMENTATION-01, Etapa A)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17
              (MY-INVENTORY-LIVE-DEPLOYMENT-01); validado pelo 5827 (52/52 PASS)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-16

Descrição...:
Uma linha com os números do cabeçalho de Meu acervo, sempre do
acervo inteiro do usuário da sessão (independente de filtros):

  total_copies     — exemplares (Physical Cards) no Inventory
  distinct_items   — grupos Card Variant + idioma ("diferentes")
  distinct_sets    — Card Sets com ao menos um exemplar
  duplicate_copies — "repetidas" = exemplares além do primeiro de
                     cada grupo = total_copies − distinct_items
                     (decisão de UX aprovada)

Usuário sem Inventory ou sem exemplares: uma linha com zeros (nunca
zero linhas — a interface não precisa distinguir).

Segurança: SECURITY DEFINER, STABLE, search_path '', auth.uid()
obrigatório (28000), dono resolvido no servidor, EXECUTE só para
authenticated.

Performance: ix_physical_card_inventory_variant; um agrupamento
sobre os exemplares do usuário + junção card_variant→card por PK
apenas para contar Sets. B4: p95 ≤ 150 ms em VR (5827, Seção P).

Como validar: Query 5827.
================================================================
*/

begin;

create or replace function public.get_my_inventory_summary()
returns table (
  total_copies     bigint,
  distinct_items   bigint,
  distinct_sets    bigint,
  duplicate_copies bigint
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  with grouped as (
    select pc.card_variant_id, pc.language_id, count(*) as n
    from public.inventory i
    join public.physical_card pc on pc.inventory_id = i.id
    where i.owner_user_id = v_user
    group by pc.card_variant_id, pc.language_id
  ),
  sets as (
    select count(distinct c.card_set_id) as n
    from (select distinct g.card_variant_id from grouped g) v
    join public.card_variant cv on cv.id = v.card_variant_id
    join public.card c on c.id = cv.card_id
  )
  select
    coalesce(sum(g.n), 0)::bigint,
    count(g.*)::bigint,
    (select s.n from sets s)::bigint,
    (coalesce(sum(g.n), 0) - count(g.*))::bigint
  from grouped g;
end;
$$;

comment on function public.get_my_inventory_summary() is
  'Meu acervo (Query 5160): totais do acervo do usuário da sessão — exemplares, diferentes (Card Variant + idioma), Sets e repetidas (exemplares além do primeiro de cada grupo). Exige auth.uid().';

revoke all on function public.get_my_inventory_summary() from public;
revoke all on function public.get_my_inventory_summary() from anon;
grant execute on function public.get_my_inventory_summary() to authenticated;

commit;
