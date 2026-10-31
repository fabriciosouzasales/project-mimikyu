/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5332 - get_my_collection(p_collection_id): resumo de UMA
              coleção do usuário da sessão (leitura por id)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-31 (autorização
              de Fabrício) — ledger 20261031130535; 5865 v1.3 17/17 PASS.
              Consumida por getMyCollection() (FRONTEND INTEGRATION-07)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Objetivo
  Abrir uma coleção (página da coleção e do fichário) sem calcular o
  resumo de todas as coleções do usuário. Hoje `getMyCollection()` chama
  `get_my_collections(true, 100, offset)` (R1, Query 5182) e filtra o id
  no Node: para cada coleção da página o banco executa
  `collection_completion_summary()`, a contagem de exemplares e a busca
  da capa. Esta função devolve exatamente a mesma linha de R1 para uma
  coleção, executando esses três cálculos uma única vez.

Contrato (idêntico a R1, Query 5182 v3.0, para a coleção pedida)
  - Mesmas 19 colunas, mesmos nomes, tipos e ordem (RETURNS TABLE
    copiado de 5182). Os 18 primeiros campos têm o mesmo valor que a
    linha correspondente de R1 com p_include_archived = true.
  - `total_count` = 1 (quantidade de linhas devolvidas por esta leitura;
    em R1 é o total de coleções do usuário). Mantido só para o frontend
    reaproveitar o mesmo mapeamento de linha; nenhum consumidor da
    leitura por id usa esse campo.
  - Coleções arquivadas são devolvidas (como R1 com archived = true,
    que é o que `getMyCollection()` usa hoje).
  - Coleção inexistente ou de outro usuário: zero linhas, sem distinguir
    os dois casos (não enumera ids). Mesmo comportamento atual.
  - `p_collection_id` nulo: 22023 INVALID_COLLECTION_ID (erro do chamador;
    o frontend já valida o formato com isCollectionId()).
  - Sessão sem identidade: 28000 not_authenticated (como R1).

Desempenho (por que reduz trabalho de fato)
  O filtro `c.id = p_collection_id AND c.owner_user_id = v_user` está no
  CTE `mine`, ANTES dos três LATERAL. A busca é pela PK de `collection`
  (uma linha) e os laterais rodam para essa linha só. Um parâmetro de id
  aplicado depois dos laterais não reduziria nada; aqui ele limita a
  entrada deles.

Segurança
  SECURITY DEFINER com search_path vazio e objetos qualificados (padrão
  de R1). Titularidade reconstituída manualmente na primeira CTE
  (owner_user_id = auth.uid()); `collection_completion_summary()` volta
  a exigir a titularidade por conta própria (5188). Grants: só
  `authenticated`; REVOKE de PUBLIC e anon. Nenhuma tabela nova, nenhuma
  escrita, nenhuma mudança em R1 (Biblioteca inalterada).

Espelhamento obrigatório
  A projeção é cópia de 5182. Qualquer mudança futura em R1 (colunas,
  capa, progresso) precisa ser repetida aqui; o harness 5865 compara as
  duas leituras coluna a coluna.

Depende de: 5182 (R1 v3), 5188 (collection_completion_summary v6).
Resultado esperado: função criada; uma versão; ACL postgres + authenticated.
Como validar: Query 5865 (harness, GATE 17/17).
Como reverter: DROP FUNCTION public.get_my_collection(uuid);
               (nenhum objeto depende dela; o frontend volta a R1 ao
               reverter o commit correspondente).
================================================================
*/

begin;

create or replace function public.get_my_collection(
  p_collection_id uuid
)
returns table (
  collection_id        uuid,
  name                 text,
  mode                 text,
  completion_policy    text,
  lifecycle_status     text,
  card_set_id          uuid,
  card_set_code        text,
  card_set_name        text,
  card_set_logo_path   text,
  cover_finish         text,
  total_positions      bigint,
  satisfied_positions  bigint,
  progress_percentage  numeric,
  is_complete          boolean,
  copies_count         bigint,
  cover_image_path     text,
  created_at           timestamptz,
  updated_at           timestamptz,
  total_count          bigint
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

  if p_collection_id is null then
    raise exception 'INVALID_COLLECTION_ID' using errcode = '22023';
  end if;

  return query
  with mine as (
    -- Fronteira de autorização e filtro por id ANTES de qualquer cálculo.
    select c.id, c.name, c.mode, c.completion_policy, c.lifecycle_status, c.cover_finish,
           c.created_at, c.updated_at
    from public.collection c
    where c.id = p_collection_id
      and c.owner_user_id = v_user
  )
  select
    m.id, m.name, m.mode, m.completion_policy, m.lifecycle_status,
    cs.id, cs.code::text, cs.name::text, cs.logo_storage_path::text,
    m.cover_finish,
    s.total_positions, s.satisfied_positions, s.progress_percentage, s.is_complete,
    coalesce(alloc.copies, 0)::bigint,
    cover.storage_path::text,
    m.created_at, m.updated_at, 1::bigint
  from mine m
  left join public.collection_reference cr         on cr.collection_id = m.id
  left join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  left join public.card_set cs                     on cs.id = ccsr.card_set_id
  left join lateral (
    select sm.total_positions, sm.satisfied_positions, sm.progress_percentage, sm.is_complete
    from public.collection_completion_summary(m.id) sm
  ) s on true
  left join lateral (
    select count(*) as copies
    from public.collection_allocation ca
    where ca.collection_id = m.id
  ) alloc on true
  left join lateral (
    select ast.storage_path
    from public.collection_allocation ca
    join public.physical_card pc on pc.id = ca.physical_card_id
    join public.card_variant cv  on cv.id = pc.card_variant_id
    join public.card_asset ast   on ast.card_id = cv.card_id
    join public.card_asset_type cat on cat.id = ast.asset_type_id and cat.code = 'CARD_FRONT'
    join public.language al      on al.id = ast.language_id
    where ca.collection_id = m.id
      and ast.is_primary
      and ast.is_active
      and ast.storage_path is not null
    order by ca.created_at desc, ca.id,
             (ast.language_id = pc.language_id) desc,
             (al.code = 'pt-BR') desc,
             (al.code = 'en') desc,
             al.language_order asc
    limit 1
  ) cover on true;
end;
$$;

comment on function public.get_my_collection(uuid) is
  'Uma coleção do usuário da sessão (Query 5332): mesma linha de get_my_collections (5182) para o id pedido, com total_count = 1. Filtra id e titular antes de calcular progresso, exemplares e capa. Arquivadas incluídas; alheia ou inexistente = zero linhas.';

revoke all on function public.get_my_collection(uuid) from public;
revoke all on function public.get_my_collection(uuid) from anon;
grant execute on function public.get_my_collection(uuid) to authenticated;

commit;

-- Como validar (confirmação rápida; a validação completa é a Query 5865):
-- select p.oid::regprocedure, p.prosecdef, p.proconfig, p.provolatile,
--        has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec,
--        pg_get_function_result(p.oid) = pg_get_function_result('public.get_my_collections(boolean,integer,integer)'::regprocedure) as mesmo_retorno
-- from pg_proc p where p.oid = 'public.get_my_collection(uuid)'::regprocedure;
-- Esperado: t | {search_path=""} | s | f | t | t
