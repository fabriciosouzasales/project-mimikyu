/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5213 - storage_container: tipo opcional, regra de nome e
              índice por acervo — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024104; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Mudanças (aditivas; nenhuma linha existente é reescrita):
  1. kind_code text NULL → storage_container_kind(code), ON UPDATE/DELETE
     RESTRICT. NULL = "sem tipo" (o tipo é opcional). Locais existentes
     ficam sem tipo.
  2. chk_storage_container_name: nome sem espaços nas pontas, não vazio,
     até 60 caracteres. 5022 já grava btrim(p_name); CT-01 grava a
     constante "Local padrão". Pré-requisito: nenhuma linha atual viola
     a regra (5847 0.4 e a pré-checagem abaixo falham alto se violar).
  3. ix_storage_container_inventory (inventory_id): listar os locais de
     um acervo sem varrer a tabela (a UNIQUE (id, inventory_id) começa
     por id e não serve a esse acesso).
  4. ix_collection_default_storage (collection.default_storage_container_id):
     a FK de collection para storage_container (5030) não tem índice;
     sem ele, cada exclusão de local (checagem RESTRICT da FK e a
     verificação de 5218) e a contagem de 5219 varrem collection inteira.

Não muda: identidade, ownership por Inventory (C-57), RLS select-own,
FK composta physical_card → storage_container (C-61), 5020–5024,
nenhuma coluna de collection.
Sem hierarquia, capacidade ou arquivamento (fora do escopo WHERE-02).

Recuperação:
  alter table public.storage_container drop constraint chk_storage_container_name;
  drop index public.ix_storage_container_inventory;
  drop index public.ix_collection_default_storage;
  alter table public.storage_container drop column kind_code;
Como validar: 5847, seção 0.
================================================================
*/

begin;

do $pre$
begin
  if exists (
    select 1 from public.storage_container sc
    where sc.name <> btrim(sc.name) or btrim(sc.name) = '' or char_length(sc.name) > 60
  ) then
    raise exception 'PRECHECK 5213: há nome de local fora da regra; revisar antes de aplicar';
  end if;
end;
$pre$;

alter table public.storage_container
  add column kind_code text null
    references public.storage_container_kind(code)
    on update restrict on delete restrict;

alter table public.storage_container
  add constraint chk_storage_container_name
    check (name = btrim(name) and name <> '' and char_length(name) <= 60);

create index ix_storage_container_inventory
  on public.storage_container (inventory_id);

create index ix_collection_default_storage
  on public.collection (default_storage_container_id);

comment on column public.storage_container.kind_code is
  'WHERE-02 (5213): tipo opcional do local (storage_container_kind). NULL = sem tipo.';

commit;
