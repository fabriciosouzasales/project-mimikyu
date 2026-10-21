/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5212 - storage_container_kind: tipos de local físico
              (opcionais e extensíveis) — WHERE-02
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-21 UTC (autorização
              de Fabrício, WHERE-02 LIVE) — ledger 20261021024045; 5847 v1.0
              26/26 PASS (GATE PASS, 99.1 resíduo zero). CANÔNICA em
              database/schema/. Corpo SQL = texto aplicado via apply_migration
              (WHERE-02-CANONICAL-PROMOTION-01).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Contexto:
C-55: tipos de Storage Container (fichário físico, caixa, ETB, deck box,
maleta, cofre…) existem conceitualmente, "não fixados como enum
fechado". N24 (North Star) registrava a ressalva "até haver atributo de
tipo, a UI mostra só o nome". Diretriz de Fabrício (WHERE-02): tipos
opcionais e extensíveis, sem hierarquia.

Contrato:
  Tabela de referência (vocabulário), não dado do usuário:
    code        text PK — identificador estável (MAIÚSCULAS_COM_SUBLINHADO)
    label       text    — rótulo pt-BR exibido ao colecionador
    sort_order  smallint UNIQUE — ordem de exibição
    is_active   boolean — tipos inativos não aparecem para escolha, mas
                          locais que já os usam continuam válidos
  Extensível por migration (INSERT), sem DDL: atende C-55 (lista aberta)
  sem criar enum fechado nem texto livre sem controle.

  "Fichário físico" (e não "Fichário"): NS-09 reserva "Fichário" para o
  Layout digital.

Segurança: RLS habilitada; SELECT para authenticated apenas de tipos
ativos; nenhuma escrita por papel de cliente; anon sem acesso.
Recuperação: drop table public.storage_container_kind (só antes de 5213).
Como validar: 5847, seção 0.
================================================================
*/

begin;

create table public.storage_container_kind (
  code       text     primary key,
  label      text     not null,
  sort_order smallint not null,
  is_active  boolean  not null default true,
  constraint chk_storage_container_kind_code check (code ~ '^[A-Z][A-Z0-9_]{1,31}$'),
  constraint chk_storage_container_kind_label check (btrim(label) <> '' and label = btrim(label) and char_length(label) <= 40),
  constraint uq_storage_container_kind_sort unique (sort_order)
);

comment on table public.storage_container_kind is
  'WHERE-02 (Query 5212): vocabulário aberto de tipos de local físico (C-55). Opcional em storage_container.kind_code. Extensível por migration; sem hierarquia.';

insert into public.storage_container_kind (code, label, sort_order) values
  ('BINDER',   'Fichário físico', 10),
  ('BOX',      'Caixa',           20),
  ('FOLDER',   'Pasta',           30),
  ('DECK_BOX', 'Deck box',        40),
  ('ETB',      'ETB',             50),
  ('CASE',     'Maleta',          60),
  ('SAFE',     'Cofre',           70),
  ('OTHER',    'Outro',           80);

alter table public.storage_container_kind enable row level security;

create policy storage_container_kind_select_active
  on public.storage_container_kind
  for select
  to authenticated
  using (is_active);

revoke all on table public.storage_container_kind from public;
revoke all on table public.storage_container_kind from anon;
revoke all on table public.storage_container_kind from authenticated;
grant select on table public.storage_container_kind to authenticated;

commit;
