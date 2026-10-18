/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5183 - move_my_collection(): reordena a Biblioteca do
              próprio colecionador (LIBRARY-ORDER-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018012519; 5835 v1.0 22/22 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18

Contrato:
  move_my_collection(p_collection_id uuid,
                     p_after_collection_id  uuid default null,
                     p_before_collection_id uuid default null)
  RETURNS integer  -- nova posição (1 = primeira) da coleção movida

  - Exatamente UM âncora: "depois de" (p_after) ou "antes de" (p_before).
    "Antes de" existe para a paginação: na primeira posição de uma página
    o cliente não conhece a coleção anterior (está na página de antes).
  - A ordem de partida é a mesma do R1 (5182): ativas primeiro →
    library_position NULLS FIRST → created_at DESC → id. A função tira a
    coleção dessa sequência, recoloca junto da âncora e renumera TODAS as
    coleções do dono 1..n — grava só as linhas cuja posição mudou.
  - Trava as linhas do dono (FOR UPDATE, em ordem de id): dois movimentos
    simultâneos do mesmo colecionador serializam; nunca há números
    repetidos nem buracos.
  - Idempotente: repetir o mesmo movimento devolve a mesma posição e não
    altera nada.
  - Dono por auth.uid(); coleção ou âncora alheia/inexistente → mesma
    resposta (COLLECTION_NOT_FOUND), sem enumerar.
  - Vale para coleção ativa ou arquivada (é apresentação).
  - Não toca cartas, alocações, locais, referência, progresso nem capa.

Erros: 28000 not_authenticated; 22023 INVALID_MOVE;
       P0002 COLLECTION_NOT_FOUND.
Segurança: SECURITY DEFINER, search_path '', EXECUTE só authenticated.
Performance: lê e trava só as coleções do dono (índice em owner_user_id);
             cardinalidade por colecionador pequena.
Como validar: Query 5835.
Como reverter: drop function public.move_my_collection(uuid, uuid, uuid).
================================================================
*/

begin;

create or replace function public.move_my_collection(
  p_collection_id        uuid,
  p_after_collection_id  uuid default null,
  p_before_collection_id uuid default null
)
returns integer
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_anchor uuid := coalesce(p_after_collection_id, p_before_collection_id);
  v_ids    uuid[];
  v_rest   uuid[];
  v_new    uuid[];
  v_idx    integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_collection_id is null
     or (p_after_collection_id is null) = (p_before_collection_id is null)
     or v_anchor = p_collection_id then
    raise exception 'INVALID_MOVE' using errcode = '22023';
  end if;

  -- Trava as coleções do dono em ordem estável (sem deadlock entre movimentos).
  perform 1
  from public.collection c
  where c.owner_user_id = v_user
  order by c.id
  for update;

  select array_agg(c.id order by (c.lifecycle_status = 'ACTIVE') desc,
                                 c.library_position asc nulls first,
                                 c.created_at desc,
                                 c.id)
    into v_ids
  from public.collection c
  where c.owner_user_id = v_user;

  if v_ids is null
     or array_position(v_ids, p_collection_id) is null
     or array_position(v_ids, v_anchor) is null then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_rest := array_remove(v_ids, p_collection_id);
  v_idx  := array_position(v_rest, v_anchor);

  if p_after_collection_id is not null then
    v_new := v_rest[1:v_idx] || p_collection_id || coalesce(v_rest[v_idx + 1:], '{}'::uuid[]);
  else
    v_new := coalesce(v_rest[1:v_idx - 1], '{}'::uuid[]) || p_collection_id || v_rest[v_idx:];
  end if;

  update public.collection c
  set library_position = t.pos::integer   -- updated_at: trigger trg_collection_set_updated_at
  from unnest(v_new) with ordinality as t(id, pos)
  where c.id = t.id
    and c.owner_user_id = v_user
    and c.library_position is distinct from t.pos::integer;

  return array_position(v_new, p_collection_id);
end;
$$;

comment on function public.move_my_collection(uuid, uuid, uuid) is
  'Minhas coleções (Query 5183): move uma coleção do usuário da sessão para depois (ou antes) de outra e renumera a Biblioteca 1..n. Idempotente; não toca cartas.';

revoke all on function public.move_my_collection(uuid, uuid, uuid) from public;
revoke all on function public.move_my_collection(uuid, uuid, uuid) from anon;
grant execute on function public.move_my_collection(uuid, uuid, uuid) to authenticated;

commit;
