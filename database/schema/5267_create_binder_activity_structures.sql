/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5267 - P3-B S1 · Histórico do Fichário — estruturas
              binder_activity_event · binder_activity_item ·
              binder_activity_coverage · binder_activity_setting
              + gatilhos de imutabilidade (exceção controlada)
Versão......: 1.1 (2026-10-25, P3-B-S1-SECURITY-CORRECTION-01: B1 e W8)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-27
              (P3-B S1, autorização expressa de Fabrício — G8; G5b/G5c dispensados
              sob H-A só para a S1; ledger 20261027024607 `5267_create_binder_activity_structures`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-25-p3b-binder-
              activity-history/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              LIVE_90 12/12. Harness 5860 NÃO EXECUTADO (H-A). Ver README §28.34.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-25
Autoridade..: concept-decisions.md C-201–C-209; logical-model.md LDM-196–LDM-203;
              README da proposta (v1.3) §3, §6, §12, §19.

O que cria (só objetos novos; nenhuma função ou tabela existente é tocada):
  1. binder_activity_event   — um evento por operação lógica concluída.
     · owner_user_id  = titular (dono do fichário NO MOMENTO do evento),
       FK auth.users ON DELETE CASCADE  → exclusão de conta (A5).
     · layout_key     = id do fichário SEM FK → o evento sobrevive à
       desmontagem e à remoção do fichário (A1).
     · actor_user_id  = quem executou, guardado como VALOR (sem FK, B1).
       Validado na gravação (5268: precisa ser auth.uid() e, na V1, o
       titular). Nunca é reescrito: nenhuma ação referencial, nenhum UPDATE.
       NULL só em legado (D4). Se a conta de um ator que não é o titular for
       excluída (só possível com colaboração futura), o valor permanece como
       identificador opaco, sem resolução para auth.users; anonimização, se
       exigida, é decisão própria (README §19.1), nunca UPDATE silencioso.
     · id identity    = desempate da ordem e cursor de paginação. A sequência
       da identidade tem REVOKE explícito (W8), independente dos privilégios
       padrão do papel executor.
  2. binder_activity_item    — itens do evento (efeitos internos), com cópia
     de carta e posições (R3). Cascata a partir do evento.
  3. binder_activity_coverage — marco mínimo por (titular, fichário):
     só data e motivo, nenhum conteúdo histórico (exclusão definitiva,
     recebimento futuro entre usuários, montagem). Não é histórico.
  4. binder_activity_setting  — linha única com a data de início da
     cobertura completa (NULL até a última fatia S2–S6, O4).

Imutabilidade (C-179 + exceção controlada, C-203):
  · UPDATE em evento/item → sempre recusado.
  · DELETE em evento → recusado, EXCETO:
      (a) exclusão definitiva: a função 5270 marca a transação com
          mmkyu.binder_activity_purge = '<titular>:<fichário>' e só apaga
          eventos desse par;
      (b) exclusão da conta: a linha do titular em auth.users já não existe
          (cascata da FK).
  · DELETE em item → só quando o evento-pai já não existe (cascata).
  · TRUNCATE → recusado.
  · Clientes não têm nenhum privilégio nas tabelas (só funções 5269).

Índices (hipóteses de desempenho, a medir na S1 — README §10.3):
  · ix_bae_owner_layout_time: (owner_user_id, layout_key, occurred_at desc, id desc)
    → leitura paginada por chave composta; prefixo serve à cascata da conta
    e à listagem de fichários encerrados.
  · (removido na v1.1) ix_bae_actor: só existia para a ação SET NULL da FK
    do ator, que deixou de existir (B1). Nenhuma leitura filtra por ator.
  · PK do item (event_id, ordinal) → itens de uma página de eventos.

Dependências: auth.users; collection_layout (só para os prechecks).
================================================================
*/
begin;

do $pre$
begin
  if to_regclass('public.binder_activity_event') is not null
     or to_regclass('public.binder_activity_item') is not null
     or to_regclass('public.binder_activity_coverage') is not null
     or to_regclass('public.binder_activity_setting') is not null then
    raise exception 'PRECHECK 5267: estruturas do histórico já existem';
  end if;
  if to_regclass('public.collection_layout') is null then
    raise exception 'PRECHECK 5267: collection_layout ausente';
  end if;
end;
$pre$;

-- 1. Evento --------------------------------------------------------------------------------
create table public.binder_activity_event (
  id              bigint      generated always as identity primary key,
  owner_user_id   uuid        not null
                  references auth.users (id) on update restrict on delete cascade,
  layout_key      uuid        not null,
  occurred_at     timestamptz not null default now(),
  actor_user_id   uuid        null,   -- valor, sem FK (B1): nunca alterado após a gravação
  event_type      text        not null,
  source          text        not null,
  collection_id   uuid        null,
  collection_name text        null,
  binder_name     text        null,
  summary         jsonb       not null default '{}'::jsonb,
  created_xact    xid8        not null default pg_current_xact_id(),
  constraint chk_bae_event_type check (event_type in (
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
    'LEGACY_CATALOG_INCORPORATION'      -- L01
  )),
  constraint chk_bae_source check (source in ('FICHARIO','ACERVO','COLECAO','CATALOGO','LEGADO')),
  constraint chk_bae_legacy check ((source = 'LEGADO') = (event_type = 'LEGACY_CATALOG_INCORPORATION')),
  constraint chk_bae_legacy_actor check (source <> 'LEGADO' or actor_user_id is null),
  constraint chk_bae_summary check (jsonb_typeof(summary) = 'object' and octet_length(summary::text) <= 2048),
  constraint chk_bae_names check (
    (collection_name is null or char_length(collection_name) <= 200)
    and (binder_name is null or char_length(binder_name) <= 200)),
  constraint chk_bae_collection_name check (collection_name is null or collection_id is not null)
);

create index ix_bae_owner_layout_time
  on public.binder_activity_event (owner_user_id, layout_key, occurred_at desc, id desc);

comment on table public.binder_activity_event is
  'Histórico do Fichário (P3-B, 5267): um evento por operação lógica concluída (C-205). Titular gravado no evento e nunca recalculado (C-204); layout_key sem FK para sobreviver à desmontagem (A1, C-202). Imutável; exclusão só pela 5270 (titular) ou pela exclusão da conta (C-203). Sem acesso de clientes.';
comment on column public.binder_activity_event.owner_user_id is
  'Titular: dono do fichário no instante do evento. Leitura sempre filtrada por ele (segregação por proprietário, C-207).';
comment on column public.binder_activity_event.layout_key is
  'Identificador do fichário guardado como valor (sem FK): o evento sobrevive à desmontagem e à remoção do fichário.';
comment on column public.binder_activity_event.actor_user_id is
  'Quem executou, guardado como valor (sem FK, B1): validado na gravação pela 5268 (auth.uid() = titular na V1) e nunca reescrito. NULL só no legado. Não exposto pelas leituras da S1.';
comment on column public.binder_activity_event.created_xact is
  'Transação que gravou o evento. Diagnóstico e provas de atomicidade do harness; não é exposto ao cliente.';

-- 2. Item ----------------------------------------------------------------------------------
create table public.binder_activity_item (
  event_id          bigint  not null
                    references public.binder_activity_event (id) on update restrict on delete cascade,
  ordinal           integer not null,
  item_kind         text    not null,
  effect            text    not null,
  card_id           uuid    null,
  card_name         text    null,
  collector_number  text    null,
  card_set_code     text    null,
  variant_type_code text    null,
  variant_type_name text    null,
  from_page         integer null,
  from_row          integer null,
  from_col          integer null,
  to_page           integer null,
  to_row            integer null,
  to_col            integer null,
  detail            jsonb   null,
  constraint pk_binder_activity_item primary key (event_id, ordinal),
  constraint chk_bai_ordinal check (ordinal >= 1),
  constraint chk_bai_kind check (item_kind in ('CARD','RESERVATION','POCKET','PAGE','COLLECTION','BINDER')),
  constraint chk_bai_effect check (effect in (
    'PLACED','MOVED','SWAPPED','REMOVED','LEFT','RESERVED','RELEASED','LOCKED','UNLOCKED',
    'SHIFTED','PAGE_ADDED','PAGE_REMOVED','PAGE_RENUMBERED','INCORPORATED','ATTACHED',
    'DETACHED','CLOSED','TRANSFERRED')),
  constraint chk_bai_card_snapshot check (card_id is null or card_name is not null),
  constraint chk_bai_from_position check (
    (from_page is null and from_row is null and from_col is null)
    or (from_page >= 1 and (from_row is null) = (from_col is null)
        and (from_row is null or (from_row >= 1 and from_col >= 1)))),
  constraint chk_bai_to_position check (
    (to_page is null and to_row is null and to_col is null)
    or (to_page >= 1 and (to_row is null) = (to_col is null)
        and (to_row is null or (to_row >= 1 and to_col >= 1)))),
  constraint chk_bai_detail check (detail is null or (jsonb_typeof(detail) = 'object' and octet_length(detail::text) <= 1024)),
  constraint chk_bai_text_sizes check (
    coalesce(char_length(card_name), 0) <= 200 and coalesce(char_length(collector_number), 0) <= 40
    and coalesce(char_length(card_set_code), 0) <= 40 and coalesce(char_length(variant_type_code), 0) <= 60
    and coalesce(char_length(variant_type_name), 0) <= 120)
);

comment on table public.binder_activity_item is
  'Itens do evento (P3-B, 5267): efeitos internos da operação lógica, com cópia da carta e das posições no momento do evento (R3). Imutável; só sai em cascata do evento.';

-- 3. Marco de cobertura --------------------------------------------------------------------
create table public.binder_activity_coverage (
  owner_user_id uuid        not null
                references auth.users (id) on update restrict on delete cascade,
  layout_key    uuid        not null,
  covered_from  timestamptz not null,
  reason        text        not null,
  updated_at    timestamptz not null default now(),
  constraint pk_binder_activity_coverage primary key (owner_user_id, layout_key),
  constraint chk_bac_reason check (reason in ('BINDER_ASSEMBLED','HISTORY_PURGED','OWNERSHIP_RECEIVED'))
);

comment on table public.binder_activity_coverage is
  'Marco mínimo de início de cobertura por (titular, fichário) (P3-B, 5267, C-203/C-207): só data e motivo. Após exclusão definitiva, é o único rastro e não contém conteúdo histórico recuperável. Sai com a conta.';

-- 4. Configuração (linha única) --------------------------------------------------------------
create table public.binder_activity_setting (
  id                 smallint    primary key default 1,
  full_coverage_from timestamptz null,
  updated_at         timestamptz not null default now(),
  constraint chk_bas_singleton check (id = 1)
);
insert into public.binder_activity_setting (id, full_coverage_from) values (1, null);

comment on table public.binder_activity_setting is
  'Data global de início da cobertura completa (O4): NULL até a última fatia S2–S6 ser comprovada; definida por migration própria de encerramento.';

-- 5. Imutabilidade ---------------------------------------------------------------------------
create function public.binder_activity_event_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' then
    raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
  elsif tg_op = 'DELETE' then
    if coalesce(current_setting('mmkyu.binder_activity_purge', true), '') = old.owner_user_id::text || ':' || old.layout_key::text then
      return old;  -- (a) exclusão definitiva pela 5270
    end if;
    if not exists (select 1 from auth.users u where u.id = old.owner_user_id) then
      return old;  -- (b) exclusão da conta do titular (cascata)
    end if;
    raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
  elsif tg_op = 'TRUNCATE' then
    raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
  end if;
  return null;
end;
$fn$;

create function public.binder_activity_item_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    if not exists (select 1 from public.binder_activity_event e where e.id = old.event_id) then
      return old;  -- cascata do evento (exclusão definitiva ou da conta)
    end if;
  end if;
  raise exception 'binder activity is immutable' using errcode = 'P0001', hint = 'BINDER_ACTIVITY_IMMUTABLE';
end;
$fn$;

create trigger trg_bae_immutable
  before update or delete on public.binder_activity_event
  for each row execute function public.binder_activity_event_guard();
create trigger trg_bae_no_truncate
  before truncate on public.binder_activity_event
  for each statement execute function public.binder_activity_event_guard();
create trigger trg_bai_immutable
  before update or delete on public.binder_activity_item
  for each row execute function public.binder_activity_item_guard();
create trigger trg_bai_no_truncate
  before truncate on public.binder_activity_item
  for each statement execute function public.binder_activity_item_guard();

revoke all on function public.binder_activity_event_guard() from public, anon, authenticated, service_role;
revoke all on function public.binder_activity_item_guard() from public, anon, authenticated, service_role;

-- 6. Privilégios -----------------------------------------------------------------------------
alter table public.binder_activity_event    enable row level security;
alter table public.binder_activity_item     enable row level security;
alter table public.binder_activity_coverage enable row level security;
alter table public.binder_activity_setting  enable row level security;

revoke all on table public.binder_activity_event    from public, anon, authenticated, service_role;
revoke all on table public.binder_activity_item     from public, anon, authenticated, service_role;
revoke all on table public.binder_activity_coverage from public, anon, authenticated, service_role;
revoke all on table public.binder_activity_setting  from public, anon, authenticated, service_role;

-- W8: sequência da identidade sem privilégio de cliente, explicitamente. Hoje os
-- privilégios padrão de sequências do dono postgres no schema public não concedem
-- nada a anon/authenticated/service_role (leitura LIVE de 2026-10-25), mas a S1 não
-- depende disso: o REVOKE vale qualquer que seja o papel executor ou seus padrões.
do $seq$
declare
  v_seq text := pg_get_serial_sequence('public.binder_activity_event', 'id');
begin
  if v_seq is null or v_seq <> 'public.binder_activity_event_id_seq' then
    raise exception 'PRECHECK 5267: sequência da identidade inesperada (%)', coalesce(v_seq, 'NULL');
  end if;
end;
$seq$;
revoke all on sequence public.binder_activity_event_id_seq from public, anon, authenticated, service_role;

commit;
