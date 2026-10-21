/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5166 - collection_creation_request: registro de
              idempotência do CT-01 (MY-COLLECTIONS-FOUNDATION-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17 (autorização
              condicionada de Fabrício) — ledger 20261017152343; 5830 v1.1 35/35 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contexto:
North Star §2.6 (NS-06, D1 opção A) exige que a criação da primeira
coleção seja atômica e idempotente por chave do cliente. Decisão D-B
(Fabrício, 2026-10-17): tabela própria e mínima — não estender
bulk_operation (cujo CHECK de tipo e fingerprint de Revisão não se
aplicam aqui).

Contrato:
  Uma linha por (dono, chave de idempotência) que já produziu uma coleção.
  Só a função 5167 lê e escreve; nenhum papel de cliente tem acesso.

Integridade com contratos existentes (nenhum é alterado):
  - FK collection_id ON DELETE CASCADE: delete_collection (5039)
    continua funcionando; a linha some junto com a coleção.
  - FK storage_container_id ON DELETE CASCADE: nunca bloqueia a
    remoção futura de um local.
  - Escrita sempre na mesma transação da coleção (5167), então uma
    linha confirmada sempre aponta para coleção e local existentes.

ESTADO VIGENTE (alterado por 5214, WHERE-02, executada no LIVE em
2026-10-21 UTC, ledger 20261021024126 — nota documental; o corpo SQL
abaixo é o original da 5166 e NÃO deve ser reexecutado):
  - storage_container_id passou a aceitar NULL e a FK passou a
    ON DELETE SET NULL (o CASCADE descrito acima não vale mais).
    Excluir um local (5218) preserva a linha de idempotência; só a
    referência ao local vira NULL.
  - Replay de 5167/5175/5202 (contratos inalterados) continua
    devolvendo a MESMA coleção; storage_container_id pode voltar NULL
    quando o local de criação foi excluído depois.
  - Ver database/schema/5214_alter_collection_creation_request_storage_set_null.sql.

Segurança: RLS habilitada sem policies (nega tudo a anon/authenticated);
privilégios revogados de PUBLIC, anon, authenticated e service_role.

Como validar: Query 5830, seção 0.
================================================================
*/

begin;

create table public.collection_creation_request (
  id                        uuid        primary key default gen_random_uuid(),
  owner_user_id             uuid        not null references auth.users(id) on update restrict on delete restrict,
  idempotency_key           uuid        not null,
  request_hash              text        not null,
  collection_id             uuid        not null references public.collection(id) on update restrict on delete cascade,
  storage_container_id      uuid        not null references public.storage_container(id) on update restrict on delete cascade,
  storage_container_created boolean     not null,
  created_at                timestamptz not null default now(),
  constraint uq_collection_creation_request_owner_key unique (owner_user_id, idempotency_key),
  constraint chk_collection_creation_request_hash_not_blank check (btrim(request_hash) <> '')
);

create index ix_collection_creation_request_collection
  on public.collection_creation_request (collection_id);
create index ix_collection_creation_request_storage
  on public.collection_creation_request (storage_container_id);

comment on table public.collection_creation_request is
  'CT-01 (Query 5166): idempotência da criação de coleção com local padrão. Uma linha por (dono, chave do cliente). Acesso só via create_my_card_set_collection (5167).';

alter table public.collection_creation_request enable row level security;

revoke all on table public.collection_creation_request from public;
revoke all on table public.collection_creation_request from anon;
revoke all on table public.collection_creation_request from authenticated;
revoke all on table public.collection_creation_request from service_role;

commit;
