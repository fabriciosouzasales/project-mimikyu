/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5333 - get_my_collection_card_variants(): variantes dos
              exemplares de uma coleção, por carta (V1-09 Fase B —
              preço NM em coleções de Set e Master Set)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-31 (autorização de
              Fabrício, PHASE B CONTROLLED LIVE EXECUTION-03) — ledger
              20261031181928; corpo md5 c43d9d01… = arquivo; 5866 v1.1 12/12
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Por que existe
  As leituras de posições (5169 Set, 5189/5198 Master Set) devolvem a
  carta (e, no Master Set, o tipo de acabamento), mas não a variante
  dos exemplares da posição. O preço NM é por variante (3983) e
  card_variant não é legível pelo usuário final (RLS admin). Sem esta
  leitura, a grade não consegue associar preço à variante certa
  (docs/05f-pricing.md, seção "Preço NM na Collection (V1-09)", Fase B).

Contrato
  get_my_collection_card_variants(p_collection_id uuid, p_card_ids uuid[])
  Uma linha por (carta, variante, idioma) com exemplares alocados a esta
  coleção, restrita às cartas pedidas:
    card_id          — carta (posição de Set; no Master Set, junto com
                       variant_type_id identifica a posição);
    variant_type_id  — tipo de acabamento da variante (Master Set);
    card_variant_id  — variante dos exemplares (chave do preço, 3983);
    variant_label    — etiqueta de exibição, mesma regra da 5159/5261
                       (tipo · impressão · edição);
    language_code    — idioma dos exemplares;
    copies           — exemplares desta variante/idioma nesta coleção.
  Quem decide se a posição tem uma variante só (e portanto preço) é o
  frontend (regra pura testada): esta leitura só informa o que existe.
  Coleção alheia ou inexistente → zero linhas (não enumera).

Limites e erros
  p_card_ids: 1..500 ids (página da grade: 5169 até 500, 5198 até 120).
  28000 not_authenticated; 22023 INVALID_CARD_IDS (nulo, vazio ou >500).

Desempenho
  Uma passada: collection_allocation pelo índice de collection_id
  (ix_collection_allocation_collection), physical_card/card_variant por
  PK, filtro por card_id = any(p_card_ids). Nada de catálogo inteiro,
  nenhum cálculo de progresso. Custo proporcional aos exemplares da
  coleção nas cartas da página.

Segurança
  SECURITY DEFINER, STABLE, search_path '', objetos qualificados; dono
  verificado (collection.owner_user_id = auth.uid()) antes de ler
  exemplares; EXECUTE só authenticated (REVOKE de PUBLIC e anon).
  Somente leitura. Não substitui nem altera 5169/5189/5198/3983.

Como validar: Query 5866 (mesma pasta).
Como reverter: DROP FUNCTION public.get_my_collection_card_variants(uuid, uuid[]);
================================================================
*/

begin;

create or replace function public.get_my_collection_card_variants(
  p_collection_id uuid,
  p_card_ids      uuid[]
)
returns table (
  card_id         uuid,
  variant_type_id uuid,
  card_variant_id uuid,
  variant_label   text,
  language_code   text,
  copies          integer
)
language plpgsql
security definer
stable
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_card_ids is null or cardinality(p_card_ids) = 0 or cardinality(p_card_ids) > 500 then
    raise exception 'INVALID_CARD_IDS' using errcode = '22023';
  end if;

  if p_collection_id is null or not exists (
    select 1 from public.collection c
    where c.id = p_collection_id and c.owner_user_id = v_user
  ) then
    return;
  end if;

  return query
  select
    cv.card_id,
    cv.variant_type_id,
    cv.id,
    nullif(concat_ws(' · ', vt.name, pp.name, ec.name), '')::text,
    l.code::text,
    count(*)::integer
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  join public.card_variant cv  on cv.id = pc.card_variant_id
  join public.language l       on l.id = pc.language_id
  left join public.card_variant_type vt            on vt.id = cv.variant_type_id
  left join public.card_printing_profile pp        on pp.id = cv.printing_profile_id
  left join public.card_edition_context_profile ec on ec.id = cv.edition_context_profile_id
  where ca.collection_id = p_collection_id
    and cv.card_id = any(p_card_ids)
  group by cv.card_id, cv.variant_type_id, cv.id, vt.name, pp.name, ec.name, l.code
  order by cv.card_id, cv.id, l.code;
end;
$$;

comment on function public.get_my_collection_card_variants(uuid, uuid[]) is
  'V1-09 Fase B (Query 5333): variantes e idiomas dos exemplares alocados a uma coleção do usuário, por carta pedida (até 500). Coleção alheia ou inexistente = zero linhas. Base para associar o preço NM (3983) à variante certa nas grades de Set e Master Set.';

revoke all on function public.get_my_collection_card_variants(uuid, uuid[]) from public;
revoke all on function public.get_my_collection_card_variants(uuid, uuid[]) from anon;
grant execute on function public.get_my_collection_card_variants(uuid, uuid[]) to authenticated;

commit;

-- Como validar (rápido; completo na 5866):
-- select p.oid::regprocedure, p.prosecdef, p.proconfig, p.provolatile,
--        has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
-- from pg_proc p where p.oid = 'public.get_my_collection_card_variants(uuid,uuid[])'::regprocedure;
-- Esperado: t | {search_path=""} | s | f | t
