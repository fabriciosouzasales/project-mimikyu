/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5218 - delete_my_storage_container(): excluir local vazio
              e elegível, sem destruir histórico — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024221; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Autoridade: C-63 (remoção só quando estruturalmente vazio; sem cascade
sobre cartas), C-36 (toda coleção tem local padrão), C-58/C-59, diretriz
WHERE-02 ("exclusão de locais utilizados deve ser bloqueada").
Sem hierarquia nesta etapa: "vazio" = zero exemplares diretamente no local.

Contrato:
  delete_my_storage_container(p_storage_container_id uuid)
  → storage_container_id, deleted

  1. 28000 not_authenticated; 22023 INVALID_REQUEST (id nulo).
  2. Trava o local do Inventory do chamador (FOR UPDATE). Inexistente ou
     de outro usuário → P0002 STORAGE_NOT_FOUND (indistinguíveis).
     Retry depois de uma exclusão bem-sucedida também recebe
     STORAGE_NOT_FOUND; a interface trata como "já excluído".
  3. Bloqueios (nada é alterado):
     - 55000 STORAGE_HAS_CARDS: algum exemplar está neste local;
     - 55000 STORAGE_IS_COLLECTION_DEFAULT: é o local padrão de alguma
       coleção (ativa ou arquivada) — trocar antes em Ajustes → Onde guardo.
  4. DELETE. Concorrência: quem atribui carta (5024), troca local padrão
     (5036) ou cria coleção com este local (CT-01) precisa de FOR KEY
     SHARE neste registro e espera a trava; se algo passar a referenciar
     o local, a FK RESTRICT recusa e a função devolve 55000 STORAGE_IN_USE.

Histórico preservado (R4):
  - collection_creation_request.storage_container_id → SET NULL (5214);
  - storage_container_creation_request.storage_container_id → SET NULL (5215).
  Nenhum registro de idempotência é apagado; nenhum exemplar, alocação,
  coleção ou vínculo é tocado.

Segurança: SECURITY DEFINER, VOLATILE, search_path '', objetos
qualificados; EXECUTE só authenticated.
Pré-requisito: 5214 aplicada (senão o DELETE apagaria pedidos de criação
de coleção por CASCADE).
Recuperação: drop function if exists public.delete_my_storage_container(uuid);
Como validar: 5847, seção 6.
================================================================
*/

begin;

do $pre$
begin
  if exists (
    select 1 from pg_constraint c
    where c.conname = 'collection_creation_request_storage_container_id_fkey'
      and c.conrelid = 'public.collection_creation_request'::regclass
      and c.confdeltype <> 'n'
  ) then
    raise exception 'PRECHECK 5218: aplique 5214 antes (FK de collection_creation_request ainda não é SET NULL)';
  end if;
end;
$pre$;

create or replace function public.delete_my_storage_container(
  p_storage_container_id uuid
)
returns table (
  storage_container_id uuid,
  deleted              boolean
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_storage_container_id is null then
    raise exception 'INVALID_REQUEST' using errcode = '22023';
  end if;

  perform 1
  from public.storage_container sc
  join public.inventory i on i.id = sc.inventory_id
  where sc.id = p_storage_container_id
    and i.owner_user_id = v_user
  for update of sc;

  if not found then
    raise exception 'STORAGE_NOT_FOUND' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.physical_card pc
    where pc.storage_container_id = p_storage_container_id
  ) then
    raise exception 'STORAGE_HAS_CARDS' using errcode = '55000';
  end if;

  if exists (
    select 1 from public.collection c
    where c.default_storage_container_id = p_storage_container_id
  ) then
    raise exception 'STORAGE_IS_COLLECTION_DEFAULT' using errcode = '55000';
  end if;

  begin
    delete from public.storage_container sc
    where sc.id = p_storage_container_id;
  exception when foreign_key_violation then
    raise exception 'STORAGE_IN_USE' using errcode = '55000';
  end;

  return query select p_storage_container_id, true;
end;
$$;

revoke all on function public.delete_my_storage_container(uuid) from public;
revoke all on function public.delete_my_storage_container(uuid) from anon;
grant execute on function public.delete_my_storage_container(uuid) to authenticated;

commit;
