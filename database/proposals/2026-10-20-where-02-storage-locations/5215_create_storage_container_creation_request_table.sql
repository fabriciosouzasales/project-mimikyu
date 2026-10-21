/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5215 - storage_container_creation_request: idempotência
              da criação de local pelo colecionador — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024143; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Contexto:
create_storage_container (5022) não é idempotente: um retry após
timeout cria um segundo local. Mesmo padrão já aprovado para a criação
de coleção (D-B, 5166): tabela própria e mínima de idempotência, uma
linha por (dono, chave do cliente).

Contrato:
  Escrita e leitura só pela função 5216; nenhum papel de cliente acessa.
  storage_container_id NULL + ON DELETE SET NULL: excluir o local (5218)
  nunca apaga o registro de idempotência — um retry com a mesma chave
  informa que o local foi criado e depois excluído, sem recriá-lo (R4,
  mesma regra aplicada a collection_creation_request em 5214).
  owner_user_id ON DELETE RESTRICT: igual a 5166.

Segurança: RLS habilitada sem policies; privilégios revogados de
PUBLIC, anon, authenticated e service_role.
Recuperação: drop table public.storage_container_creation_request (antes de 5216).
Como validar: 5847, seções 0 e 3.
================================================================
*/

begin;

create table public.storage_container_creation_request (
  id                   uuid        primary key default gen_random_uuid(),
  owner_user_id        uuid        not null references auth.users(id) on update restrict on delete restrict,
  idempotency_key      uuid        not null,
  request_hash         text        not null,
  storage_container_id uuid        null references public.storage_container(id) on update restrict on delete set null,
  created_at           timestamptz not null default now(),
  constraint uq_storage_container_creation_request_owner_key unique (owner_user_id, idempotency_key),
  constraint chk_storage_container_creation_request_hash check (btrim(request_hash) <> '')
);

create index ix_storage_container_creation_request_storage
  on public.storage_container_creation_request (storage_container_id);

comment on table public.storage_container_creation_request is
  'WHERE-02 (Query 5215): idempotência de create_my_storage_container (5216). Uma linha por (dono, chave). Local excluído → storage_container_id NULL; a linha permanece.';

alter table public.storage_container_creation_request enable row level security;

revoke all on table public.storage_container_creation_request from public;
revoke all on table public.storage_container_creation_request from anon;
revoke all on table public.storage_container_creation_request from authenticated;
revoke all on table public.storage_container_creation_request from service_role;

commit;
