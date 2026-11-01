/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5341 - Histórico do Fichário: tipo de evento CARDS_AUTO_ARRANGED
Versão......: 1.0
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-11-01
              (P2 LIVE GATE 02, ledger 20261101135916 `p2_5341_extend_binder_activity_auto_arrange_event`). Do `begin;` ao fim
              idêntica ao arquivo de database/proposals/2026-11-01-binder-auto-arrange/
              (só este bloco Status difere). md5 do corpo instalado = arquivo:
              a7f9f99fa1f98171897904ed6d380bc4 (binder_activity_category) (GATE 04 SRC). Harness 5872 v1.5 54/54 PASS (GATE 03 RERUN-15);
              postcheck e medição ME3 PASS (GATE 04). Homologada em
              P2 SQL FOUNDATION CLOSEOUT-16. Ver README da proposta.
              Histórico da proposta: (P2 AUTO-ARRANGE SQL FOUNDATION-06, 2026-11-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Objetivo
  A organização automática (5344) grava UM evento por operação (C-205) com um
  item por carta posicionada. Nenhum tipo existente descreve a operação:
  CARD_PLACED é "uma carta posicionada pelo usuário" (E02). Esta migration
  acrescenta o tipo CARDS_AUTO_ARRANGED ao CHECK chk_bae_event_type (5267) e o
  classifica na categoria CARDS em binder_activity_category (5269).

O que muda
  1. chk_bae_event_type: DROP + ADD com a mesma lista e o tipo novo no fim
     (linhas existentes continuam válidas; a validação percorre a tabela).
  2. binder_activity_category: CREATE OR REPLACE — mesmo corpo da 5269 com
     'CARDS_AUTO_ARRANGED' no ramo CARDS. Assinatura, IMMUTABLE e search_path
     inalterados.
  Nada mais: itens, efeitos (PLACED já existe), leitura e purga inalterados.

Dependência de frontend (registrada, não implementada aqui)
  web/lib/colecoes/binder-activity.ts espelha a lista de tipos; o evento novo
  cai no ramo default até a interface aprender o rótulo — aplicar antes da
  publicação do botão.

Resultado esperado: CHECK aceita CARDS_AUTO_ARRANGED; categoria = 'CARDS'.
Como validar: harness 5872, S0.5.
Como reverter (somente se nenhum evento CARDS_AUTO_ARRANGED existir):
  recriar o CHECK sem o tipo e o corpo da 5269.
================================================================
*/

begin;

do $pre$
begin
  if to_regclass('public.binder_activity_event') is null
     or to_regprocedure('public.binder_activity_category(text)') is null then
    raise exception 'PRECHECK 5341: estruturas do histórico (5267/5269) ausentes';
  end if;
  if not exists (select 1 from pg_constraint
                 where conrelid = 'public.binder_activity_event'::regclass
                   and conname = 'chk_bae_event_type') then
    raise exception 'PRECHECK 5341: chk_bae_event_type ausente';
  end if;
  if position('CARDS_AUTO_ARRANGED' in pg_get_constraintdef(
       (select oid from pg_constraint where conrelid = 'public.binder_activity_event'::regclass
          and conname = 'chk_bae_event_type'))) > 0 then
    raise exception 'PRECHECK 5341: tipo já existe';
  end if;
end;
$pre$;

alter table public.binder_activity_event drop constraint chk_bae_event_type;
alter table public.binder_activity_event add constraint chk_bae_event_type check (event_type in (
    'BINDER_ASSEMBLED',                 -- E01
    'CARD_PLACED',                      -- E02
    'CARD_MOVED',                       -- E03
    'CARDS_SWAPPED',                    -- E04
    'CARDS_REMOVED',                    -- E05
    'CARDS_LEFT_BY_STORAGE',            -- E06a
    'CARDS_LEFT_BY_COLLECTION_STORAGE', -- E06b
    'CARD_LEFT_BY_INVENTORY_EXIT',      -- E07
    'POCKET_RESERVED',                  -- E08
    'RESERVATIONS_RELEASED',            -- E09
    'POCKETS_LOCKED',                   -- E10
    'POCKETS_UNLOCKED',                 -- E10
    'GAP_OPENED',                       -- E11
    'GAP_CLOSED',                       -- E12
    'PAGES_ADDED',                      -- E13
    'PAGE_REMOVED',                     -- E14
    'PAGES_REORDERED',                  -- E15
    'CATALOG_NOVELTIES_INCORPORATED',   -- E16
    'COLLECTION_ATTACHED',              -- E17
    'COLLECTION_DETACHED',              -- E18
    'BINDER_DISMANTLED',                -- E19
    'BINDER_DELETED_EMPTY',             -- E19b
    'BINDER_OWNERSHIP_TRANSFERRED',     -- E20
    'LEGACY_CATALOG_INCORPORATION',     -- L01
    'CARDS_AUTO_ARRANGED'               -- E21 (organização automática, 5344)
  ));

create or replace function public.binder_activity_category(p_event_type text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case
    when p_event_type in ('CARD_PLACED','CARD_MOVED','CARDS_SWAPPED','CARDS_REMOVED',
                          'CARDS_LEFT_BY_STORAGE','CARDS_LEFT_BY_COLLECTION_STORAGE','CARD_LEFT_BY_INVENTORY_EXIT',
                          'CARDS_AUTO_ARRANGED') then 'CARDS'
    when p_event_type in ('POCKET_RESERVED','RESERVATIONS_RELEASED') then 'RESERVATIONS'
    when p_event_type in ('POCKETS_LOCKED','POCKETS_UNLOCKED') then 'LOCKS'
    when p_event_type in ('GAP_OPENED','GAP_CLOSED','PAGES_ADDED','PAGE_REMOVED','PAGES_REORDERED') then 'PAGES'
    when p_event_type in ('CATALOG_NOVELTIES_INCORPORATED','LEGACY_CATALOG_INCORPORATION') then 'CATALOG'
    when p_event_type in ('BINDER_ASSEMBLED','COLLECTION_ATTACHED','COLLECTION_DETACHED',
                          'BINDER_DISMANTLED','BINDER_DELETED_EMPTY','BINDER_OWNERSHIP_TRANSFERRED') then 'BINDER'
  end
$fn$;

-- CREATE OR REPLACE preserva a ACL; o revoke repete a 5269 por defesa.
revoke all on function public.binder_activity_category(text) from public, anon, authenticated, service_role;

notify pgrst, 'reload schema';

commit;
