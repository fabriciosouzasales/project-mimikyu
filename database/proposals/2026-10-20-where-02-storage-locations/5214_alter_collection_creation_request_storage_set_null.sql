/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5214 - collection_creation_request: excluir um local não
              apaga mais o registro de idempotência da criação de
              coleção (R4) — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024126; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Problema (R4, READINESS WHERE-01):
  5166 criou collection_creation_request.storage_container_id NOT NULL
  com FK ON DELETE CASCADE ("nunca bloqueia a remoção futura de um
  local"). Com a exclusão de locais (5218), apagar um local que foi o
  local de criação de uma coleção APAGARIA a linha de idempotência
  dessa coleção: um retry com a mesma chave criaria uma coleção
  duplicada. A linha precisa sobreviver à exclusão do local.

Solução:
  storage_container_id passa a aceitar NULL e a FK passa a ON DELETE
  SET NULL. A linha (dono, chave, hash, collection_id,
  storage_container_created) é preservada; só a referência ao local
  removido vira NULL.

Efeito nos contratos existentes (nenhuma função é alterada):
  - 5167/5175/5202 no caminho de replay devolvem
    v_prev.storage_container_id: passa a poder ser NULL quando o local
    de criação foi excluído depois. collection_id e replayed seguem
    corretos — o replay continua devolvendo a MESMA coleção, sem criar
    outra. O frontend não lê storage_container_id desse retorno
    (web/app/colecoes/colecoes/actions.ts usa collection_id,
    storage_container_created e replayed).
  - O caminho de criação continua gravando o local (sempre não-nulo).
  - collection_id ON DELETE CASCADE (delete_collection, 5039) inalterado.
  - O índice ix_collection_creation_request_storage (5166) atende o SET
    NULL sem varredura.

Recuperação (só se nenhuma linha estiver com NULL):
  alter table ... drop constraint collection_creation_request_storage_container_id_fkey;
  alter table ... add constraint ... foreign key (storage_container_id)
    references public.storage_container(id) on update restrict on delete cascade;
  alter table ... alter column storage_container_id set not null;
Como validar: 5847, seções 0.1 e 6.3.
================================================================
*/

begin;

alter table public.collection_creation_request
  alter column storage_container_id drop not null;

alter table public.collection_creation_request
  drop constraint collection_creation_request_storage_container_id_fkey;

alter table public.collection_creation_request
  add constraint collection_creation_request_storage_container_id_fkey
    foreign key (storage_container_id)
    references public.storage_container(id)
    on update restrict on delete set null;

comment on column public.collection_creation_request.storage_container_id is
  'Local da criação (5167/5175/5202). NULL = esse local foi excluído depois (WHERE-02, 5214): a idempotência da coleção é preservada.';

commit;
