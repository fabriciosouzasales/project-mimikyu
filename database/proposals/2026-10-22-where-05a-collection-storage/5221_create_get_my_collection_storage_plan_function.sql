/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5221 - get_my_collection_storage_plan(): prévia da organização
              física de uma coleção em um local — WHERE-05A
              (+ helper interno collection_storage_plan_snapshot)
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA. Aguarda auditoria independente e
              autorização expressa de Fabrício (WHERE-05A CONTRACT GAP
              RESOLUTION). Não aplicar no LIVE sem essa autorização.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-22

Por que existe (WHERE-05A READINESS: CONTRACT GAP): organizar fisicamente,
numa operação só, os exemplares JÁ VINCULADOS a uma coleção exige mostrar
antes números reais — total, sem localização, já no destino, em outros
locais, quanto cada modalidade moveria — sem levar a lista de exemplares ao
navegador e sem depender da paginação do Meu acervo. E exige uma
identificação verificável da prévia, que a 5222 recalcula sob trava antes
de gravar (o usuário autoriza exatamente o que viu).

Objetos criados:

  1. public.collection_storage_plan_snapshot(p_collection_id uuid,
                                             p_storage_container_id uuid)
     HELPER INTERNO — FONTE ÚNICA das contagens e da identificação da prévia,
     usada dos DOIS lados (prévia 5221 e confirmação 5222). Mesmo padrão da
     5149 (preview_fingerprint): SECURITY INVOKER, VOLATILE, search_path
     vazio, EXECUTE revogado de PUBLIC/anon/authenticated/service_role —
     alcançável só de dentro das RPCs SECURITY DEFINER que já validaram dono,
     coleção e local. VOLATILE (não STABLE) pelo mesmo motivo da 5149: na
     5222 o recálculo precisa enxergar o estado confirmado depois de obter as
     travas, nunca um snapshot anterior. Somente leitura, sem trava.

  2. public.get_my_collection_storage_plan(p_collection_id uuid,
                                           p_storage_container_id uuid)
     RPC pública de leitura (authenticated). Valida sessão, dono da coleção
     e local do próprio acervo e devolve UMA linha:

       collection_id        uuid     a coleção pedida
       storage_container_id uuid     o destino pedido
       collection_active    boolean  coleção ATIVA (a 5222 recusa arquivada)
       target_is_default    boolean  destino = local padrão vigente (a 5222
                                     exige; D2 — DEFAULT_CHANGED)
       total_count          integer  exemplares efetivamente alocados à coleção
       unlocated_count      integer  desses, sem localização definida
       at_target_count      integer  desses, já no destino
       elsewhere_count      integer  desses, em outro local do acervo
       eligible_unlocated   integer  o que a modalidade UNLOCATED moveria
                                     (= unlocated_count)
       eligible_all         integer  o que a modalidade ALL moveria
                                     (= total_count − at_target_count)
       max_per_operation    integer  teto de exemplares por operação (10.000,
                                     D3); a interface avisa antes de oferecer
       plan_token           text     identificação da prévia: 'v1:' + md5

Semântica das contagens (só exemplares FÍSICOS ALOCADOS):
  Universo = collection_allocation.collection_id = p_collection_id (0..1
  coleção por exemplar, UNIQUE em physical_card_id — 5040). NÃO entram:
  cartas do catálogo da expansão, posições do checklist/Master Set/Pokédex
  sem exemplar, exemplares do acervo fora da coleção. Invariantes:
  total = unlocated + at_target + elsewhere; eligible_unlocated = unlocated;
  eligible_all = unlocated + elsewhere.

Identificação da prévia (plan_token):
  'v1:' || md5( collection_id | destino |
                 lista ordenada por id de "id:local_atual" de TODOS os
                 exemplares alocados à coleção ('-' = sem localização) )
  Cobre: destino, composição da coleção (entrada/saída de exemplares),
  identidade e local anterior de cada exemplar — portanto também o conjunto
  elegível de cada modalidade e as quantidades exibidas. A modalidade e a
  quantidade esperada são conferidas à parte pela 5222. Não revela nada
  além do que o próprio dono já pode ler (hash de ids do próprio acervo).
  Custo: O(exemplares da coleção), pelo índice ix_collection_allocation_
  collection + PK de physical_card; string de ~75 bytes por exemplar.

Segurança (deny by default):
  - sem auth.uid() → 28000 not_authenticated;
  - argumento nulo → 22023 INVALID_ARGUMENT;
  - coleção inexistente OU de outro usuário → P0002 COLLECTION_NOT_FOUND
    (mesma resposta: não enumera);
  - local inexistente OU de outro acervo → P0002 STORAGE_NOT_FOUND;
  - SECURITY DEFINER, search_path vazio, objetos qualificados; EXECUTE só
    authenticated; o helper sem EXECUTE para nenhum papel de API.
  - Coleção arquivada NÃO é erro na prévia: collection_active = false (a
    interface explica); a 5222 recusa.

Desempenho: NÃO MEDIDO (D4). Sem carga sintética no LIVE. Critérios e plano
de medição no README.
================================================================
*/

begin;

-- Pré-checagem (falha alto, nada é alterado).
do $pre$
begin
  if to_regprocedure('public.get_my_collection_storage_plan(uuid, uuid)') is not null
     or to_regprocedure('public.collection_storage_plan_snapshot(uuid, uuid)') is not null then
    raise exception 'PRECHECK 5221: objetos já existem';
  end if;
  if to_regclass('public.collection_allocation') is null
     or to_regclass('public.ix_collection_allocation_collection') is null
     or to_regclass('public.physical_card') is null
     or to_regclass('public.storage_container') is null then
    raise exception 'PRECHECK 5221: tabelas/índices de base ausentes (5010/5020/5040)';
  end if;
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection'
                   and column_name = 'default_storage_container_id') then
    raise exception 'PRECHECK 5221: collection.default_storage_container_id ausente (5030/5036)';
  end if;
end;
$pre$;

-- 1. Helper interno: contagens + identificação da prévia (fonte única) -------
create function public.collection_storage_plan_snapshot(
  p_collection_id        uuid,
  p_storage_container_id uuid
)
returns table (
  total_count        integer,
  unlocated_count    integer,
  at_target_count    integer,
  elsewhere_count    integer,
  eligible_unlocated integer,
  eligible_all       integer,
  plan_token         text
)
language sql
volatile
security invoker
set search_path = ''
as $$
  select
    count(*)::integer,
    count(*) filter (where pc.storage_container_id is null)::integer,
    count(*) filter (where pc.storage_container_id = p_storage_container_id)::integer,
    count(*) filter (where pc.storage_container_id is not null
                       and pc.storage_container_id <> p_storage_container_id)::integer,
    count(*) filter (where pc.storage_container_id is null)::integer,
    count(*) filter (where pc.storage_container_id is distinct from p_storage_container_id)::integer,
    'v1:' || md5(
      p_collection_id::text || '|' || p_storage_container_id::text || '|' ||
      coalesce(string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'),
                          ',' order by pc.id), '')
    )
  from public.collection_allocation ca
  join public.physical_card pc on pc.id = ca.physical_card_id
  where ca.collection_id = p_collection_id;
$$;

comment on function public.collection_storage_plan_snapshot(uuid, uuid) is
  'WHERE-05A (Query 5221): FONTE ÚNICA das contagens e do plan_token da organização física de uma coleção (exemplares alocados × destino). Helper INTERNO: EXECUTE revogado de PUBLIC/anon/authenticated/service_role; chamado só por 5221/5222 (SECURITY DEFINER), que já validaram dono, coleção e local. VOLATILE para o recálculo da 5222 enxergar o estado após as travas. Somente leitura.';

revoke all on function public.collection_storage_plan_snapshot(uuid, uuid) from public;
revoke all on function public.collection_storage_plan_snapshot(uuid, uuid) from anon;
revoke all on function public.collection_storage_plan_snapshot(uuid, uuid) from authenticated;
revoke all on function public.collection_storage_plan_snapshot(uuid, uuid) from service_role;

-- 2. RPC pública de prévia ---------------------------------------------------
create function public.get_my_collection_storage_plan(
  p_collection_id        uuid,
  p_storage_container_id uuid
)
returns table (
  collection_id        uuid,
  storage_container_id uuid,
  collection_active    boolean,
  target_is_default    boolean,
  total_count          integer,
  unlocated_count      integer,
  at_target_count      integer,
  elsewhere_count      integer,
  eligible_unlocated   integer,
  eligible_all         integer,
  max_per_operation    integer,
  plan_token           text
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  c_max_per_operation constant integer := 10000;   -- D3 (proposta); mesmo valor na 5222
  v_uid       uuid := auth.uid();
  v_inventory uuid;
  v_status    text;
  v_default   uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_storage_container_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select i.id into v_inventory from public.inventory i where i.owner_user_id = v_uid;

  select c.lifecycle_status, c.default_storage_container_id
    into v_status, v_default
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found or v_inventory is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not exists (select 1 from public.storage_container sc
                 where sc.id = p_storage_container_id and sc.inventory_id = v_inventory) then
    raise exception 'STORAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  return query
  select p_collection_id,
         p_storage_container_id,
         v_status = 'ACTIVE',
         v_default is not distinct from p_storage_container_id,
         s.total_count, s.unlocated_count, s.at_target_count, s.elsewhere_count,
         s.eligible_unlocated, s.eligible_all,
         c_max_per_operation,
         s.plan_token
  from public.collection_storage_plan_snapshot(p_collection_id, p_storage_container_id) s;
end;
$$;

comment on function public.get_my_collection_storage_plan(uuid, uuid) is
  'WHERE-05A (Query 5221): prévia da organização física de uma coleção do usuário da sessão em um local do próprio acervo — contagens dos exemplares efetivamente alocados (total, sem localização, no destino, em outros locais, elegíveis por modalidade), destino = local padrão?, coleção ativa?, teto por operação e plan_token verificável pela 5222. Não devolve lista de exemplares. Exige auth.uid(); não enumera coleção/local de outro usuário.';

revoke all on function public.get_my_collection_storage_plan(uuid, uuid) from public;
revoke all on function public.get_my_collection_storage_plan(uuid, uuid) from anon;
grant execute on function public.get_my_collection_storage_plan(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
