/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5263 - Fichário Digital × Catálogo: estruturas persistentes da
              reconciliação de novidades
              collection_layout_catalog_incorporation — novidades incorporadas (W5)
              collection_layout_catalog_marker        — marco de participação (A7)
Versão......: 2.1 (2026-10-24, BINDER-CATALOG-RECONCILIATION-A7-FINAL-CORRECTION-01:
              fim de participação marcado (ended_xact) em vez de apagado, com
              gatilhos IMEDIATOS — o resultado não depende mais de gatilhos
              diferidos nem de SET CONSTRAINTS; trava convidadas → fichários
              dentro de bloco PL/pgSQL.)
              Anterior 2.0 (2026-10-24, BINDER-CATALOG-RECONCILIATION-A7-CORRECTION-01:
              marco de participação persistente por (fichário, coleção),
              independente do papel de dona ou convidada; arquivo renomeado
              de 5263_create_collection_layout_catalog_incorporation.sql).
              Anterior 1.0 (W5-FOUNDATION-01): só o registro de incorporações.
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-25
              (LIVE-EXECUTION-AUTHORIZATION-01, autorização expressa de Fabrício;
              ledger 20261025145025 `5263_create_binder_catalog_reconciliation_structures`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-24-binder-catalog-
              reconciliation/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo da proposta (md5).
              Harness 5859 NÃO EXECUTADO (estratégia H-A). Homologada pelo
              proprietário (funcional e visual). Ver README §16–§18 da proposta.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

== Parte A — collection_layout_catalog_incorporation (W5, inalterada) ==
  I1  Uma linha = uma incorporação BEM-SUCEDIDA da posição item_key, para a
      coleção collection_id, no fichário layout_id. PK (layout_id,
      collection_id, item_key).
  I2  Só a aplicação apply_my_binder_catalog_reconciliation (5266) escreve,
      na mesma transação das reservas, depois das pós-condições. Prévia,
      recusa e falha não deixam linha.
  I3  Registra criação de reserva e conversão genérica → específica (W3).
  I4  Histórico, não estado: a linha permanece quando a reserva é liberada.
  I5  collection_id é sempre a coleção real (dona ou convidada), nunca NULL.
  I6  Cascata com o fichário e com a coleção.
  I7  Deny by default: RLS sem políticas e sem grants (nem service_role).

== Parte B — collection_layout_catalog_marker (A7) ==
Problema (FINAL-AUDIT-01, A7): o marco era derivado do papel ATUAL —
collection_layout.created_at para a dona, collection_layout_guest.created_at
para a convidada. A transferência (5254) troca os papéis: a convidada que vira
dona passava a ter como marco a criação do fichário (anterior à sua entrada) e
ganhava como "novidades" posições que já existiam quando entrou — inclusive
as que ela havia reservado manualmente e liberado (regra 5); a antiga dona
virava convidada com marco = transferência e perdia novidades pendentes.

Mecanismo (opção A aprovada): uma linha por participação contínua de uma
coleção num fichário, com o marco fixado no INÍCIO da participação e mantido
enquanto ela durar, qualquer que seja o papel.
  M1  PK (layout_id, collection_id); FKs para o fichário e a coleção ON
      DELETE CASCADE (desmontagem e exclusão limpam).
  M2  marker_at = início da participação contínua:
        fichário criado         → collection_layout.created_at   (LAYOUT_CREATED)
        convidada associada     → collection_layout_guest.created_at (GUEST_ATTACHED)
        dona nova sem participação anterior (transferência para coleção
        que não era convidada) → instante da transferência (OWNERSHIP_TRANSFER)
      role = último papel (OWNER | GUEST).
      ended_xact = NULL enquanto a participação dura; preenchido com o id da
      transação (pg_current_xact_id(), nível superior) em que ela terminou.
      Só linhas com ended_xact NULL valem como marco.
  M3  Transferência (5254, NÃO alterada): a função apaga a linha de
      convidada do destino, troca collection_layout.collection_id e insere a
      origem como convidada. Os gatilhos desta migration:
        - AFTER UPDATE OF collection_id: destino passa a role OWNER mantendo o
          marco que já tinha como convidada (ou ganha um, = transferência);
        - AFTER INSERT em convidadas: origem (linha role OWNER) passa a GUEST
          mantendo o marco de dona.
      Nenhum marco muda de valor numa transferência.
  M4  Fim da participação (desassociação 5229/5253; troca de dona): gatilhos
      AFTER comuns (imediatos), ao fim de cada comando, conferem se a coleção
      ainda é dona ou convidada do fichário; se não, a linha recebe
      ended_xact = transação atual (não é apagada). Dentro da 5254 o destino
      fica alguns comandos sem papel: sua linha é encerrada e REATIVADA pelo
      gatilho seguinte da MESMA transação, com o mesmo marco.
      Regra de reativação (B2/B3): linha ativa, ou encerrada NESTA transação,
      preserva o marco quando a continuidade é real —
        dona nova (B2): preserva sempre (era convidada até o comando anterior);
        convidada nova (B3): preserva só se o último papel era OWNER (é a
        antiga dona na transferência); se era GUEST, é reassociação → marco
        novo.
      Linha encerrada em transação ANTERIOR → marco novo (participação
      interrompida).
  M5  Reassociação em OUTRA transação: linha encerrada antes → marco novo.
      Na MESMA transação: último papel GUEST → marco novo (B3).
  M5b Independência de SET CONSTRAINTS: não há gatilho de restrição nem
      diferido; o resultado é o mesmo em qualquer modo (proteção da A7
      FINAL-CORRECTION contra antecipação de gatilhos).
  M6  Fichários e participantes já existentes na aplicação: preenchidos a
      partir das datas que já existem (collection_layout.created_at,
      collection_layout_guest.created_at) — as mesmas que valiam até aqui.
      Nenhuma data é inventada. Se houver indício de transferência anterior
      (convidada com reserva própria mais antiga que a sua entrada — só a
      5254 produz isso, porque a desassociação apaga as reservas da
      convidada), o marco da dona atual é desconhecido: a migration FALHA
      (fail-closed) para decisão de Fabrício. LIVE em 2026-10-24 (somente
      leitura): 3 fichários, 1 convidada, 0 indícios.
  M7  Deny by default: RLS ligada sem políticas; REVOKE ALL de PUBLIC, anon,
      authenticated e service_role; funções de gatilho SECURITY DEFINER,
      search_path vazio, sem EXECUTE para clientes. Leitura só por
      binder_catalog_context (5264).
  M8  Falha segura: sem linha ativa (ex.: participante criado com gatilhos
      desligados por session_replication_role = replica), a 5264 trata a
      coleção como inelegível (MARKER_MISSING) — nunca usa outra data.

Gatilhos em tabelas homologadas (aditivos, só escrevem na tabela nova; não
alteram linhas, mensagens, travas nem resultados de 5105/5229/5253/5254/5255):
  collection_layout       AFTER INSERT                     → marco LAYOUT_CREATED
  collection_layout       AFTER UPDATE OF collection_id    → nova dona (OWNER)
  collection_layout       AFTER UPDATE OF collection_id    → encerra a antiga se não participa mais
  collection_layout_guest AFTER INSERT                     → convidada (GUEST)
  collection_layout_guest AFTER DELETE                     → encerra se não participa mais
Ordem na mesma operação: gatilhos AFTER da mesma tabela/evento disparam em
ordem alfabética (…_owner_change antes de …_owner_cleanup); as duas tratam
coleções diferentes (nova e antiga dona) e não dependem uma da outra.

Volume: uma linha por (fichário, coleção) — ativa enquanto participa, encerrada
depois (histórico; some por cascata com o fichário ou a coleção). Acesso por PK.
Dependências: 5105 (fichário), 5229 (convidadas), 5030–5033 (coleção).
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regclass('public.collection_layout') is null
     or to_regclass('public.collection') is null
     or to_regclass('public.collection_layout_guest') is null
     or to_regclass('public.collection_layout_slot_expected_content') is null then
    raise exception 'PRECHECK 5263: dependências ausentes (fichário, coleção, convidadas, reservas)';
  end if;
  if to_regclass('public.collection_layout_catalog_incorporation') is not null
     or to_regclass('public.collection_layout_catalog_marker') is not null then
    raise exception 'PRECHECK 5263: já aplicada';
  end if;
end;
$pre$;

do $pre2$
begin
  -- Sem associações, criações de fichário ou transferências durante o preenchimento.
  -- Dentro do bloco (sempre há transação) e na ordem da 5254: convidadas → fichários.
  lock table public.collection_layout_guest, public.collection_layout in share row exclusive mode;
  -- M6: indício de transferência anterior → marco da dona atual desconhecido.
  if exists (
    select 1
    from public.collection_layout_guest g
    join public.collection_layout_page p on p.layout_id = g.layout_id
    join public.collection_layout_slot s on s.page_id = p.id
    join public.collection_layout_slot_expected_content e on e.slot_id = s.id
    where e.collection_id = g.collection_id
      and e.created_at < g.created_at) then
    raise exception 'PRECHECK 5263: há fichário com indício de transferência de propriedade anterior — o marco da proprietária atual não pode ser derivado sem inventar data; decisão necessária';
  end if;
end;
$pre2$;

-- A. Registro de incorporações (W5) -------------------------------------------------------
create table public.collection_layout_catalog_incorporation (
  layout_id       uuid        not null,
  collection_id   uuid        not null,
  item_key        text        not null,
  incorporated_at timestamptz not null default now(),
  constraint pk_cl_catalog_incorporation primary key (layout_id, collection_id, item_key),
  constraint fk_cl_ci_layout foreign key (layout_id)
    references public.collection_layout (id) on update restrict on delete cascade,
  constraint fk_cl_ci_collection foreign key (collection_id)
    references public.collection (id) on update restrict on delete cascade,
  constraint chk_cl_ci_item_key check (
    item_key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\*)$'
  )
);

create index cl_ci_collection_idx
  on public.collection_layout_catalog_incorporation (collection_id);

comment on table public.collection_layout_catalog_incorporation is
  'Fichário Digital × Catálogo (5263, W5): novidades do Catálogo incorporadas com sucesso ao fichário de uma coleção Master Set (reserva criada ou convertida). Histórico — a linha permanece quando a reserva é liberada, para a novidade não voltar a ser oferecida. Escrita só pela 5266; sem acesso de clientes.';

alter table public.collection_layout_catalog_incorporation enable row level security;
revoke all on table public.collection_layout_catalog_incorporation
  from public, anon, authenticated, service_role;

-- B. Marco de participação (A7) -------------------------------------------------------------
create table public.collection_layout_catalog_marker (
  layout_id     uuid        not null,
  collection_id uuid        not null,
  marker_at     timestamptz not null,
  marker_source text        not null,
  role          text        not null,
  ended_xact    xid8        null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint pk_cl_catalog_marker primary key (layout_id, collection_id),
  constraint fk_cl_cm_layout foreign key (layout_id)
    references public.collection_layout (id) on update restrict on delete cascade,
  constraint fk_cl_cm_collection foreign key (collection_id)
    references public.collection (id) on update restrict on delete cascade,
  constraint chk_cl_cm_source check (marker_source in
    ('LAYOUT_CREATED', 'GUEST_ATTACHED', 'OWNERSHIP_TRANSFER', 'BACKFILL_OWNER', 'BACKFILL_GUEST')),
  constraint chk_cl_cm_role check (role in ('OWNER', 'GUEST'))
);

create index cl_cm_collection_idx
  on public.collection_layout_catalog_marker (collection_id);

comment on table public.collection_layout_catalog_marker is
  'Fichário Digital × Catálogo (5263, A7): início da participação contínua de cada coleção num fichário, preservado em transferência de propriedade (5254); referência temporal da detecção de novidades. Escrita só pelos gatilhos desta migration; sem acesso de clientes.';

alter table public.collection_layout_catalog_marker enable row level security;
revoke all on table public.collection_layout_catalog_marker
  from public, anon, authenticated, service_role;

-- M6: participantes existentes, com as datas que já existem
insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
select l.id, l.collection_id, l.created_at, 'BACKFILL_OWNER', 'OWNER'
from public.collection_layout l;

insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
select g.layout_id, g.collection_id, g.created_at, 'BACKFILL_GUEST', 'GUEST'
from public.collection_layout_guest g;

-- B1. Fichário criado → marco da dona
create function public.binder_catalog_marker_on_layout_insert()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  insert into public.collection_layout_catalog_marker (layout_id, collection_id, marker_at, marker_source, role)
  values (new.id, new.collection_id, new.created_at, 'LAYOUT_CREATED', 'OWNER')
  on conflict (layout_id, collection_id) do nothing;
  return null;
end;
$$;

revoke all on function public.binder_catalog_marker_on_layout_insert()
  from public, anon, authenticated, service_role;

create trigger trg_cl_catalog_marker_layout_insert
  after insert on public.collection_layout
  for each row execute function public.binder_catalog_marker_on_layout_insert();

-- B2. Nova dona (transferência): mantém o marco que já tinha (linha ativa ou encerrada nesta
--     transação); sem participação contínua → agora
create function public.binder_catalog_marker_on_owner_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  insert into public.collection_layout_catalog_marker as m (layout_id, collection_id, marker_at, marker_source, role)
  values (new.id, new.collection_id, now(), 'OWNERSHIP_TRANSFER', 'OWNER')
  on conflict (layout_id, collection_id) do update
    set marker_at     = case when m.ended_xact is null or m.ended_xact = pg_current_xact_id()
                             then m.marker_at else excluded.marker_at end,
        marker_source = case when m.ended_xact is null or m.ended_xact = pg_current_xact_id()
                             then m.marker_source else excluded.marker_source end,
        role          = 'OWNER',
        ended_xact    = null,
        updated_at    = now();
  return null;
end;
$$;

revoke all on function public.binder_catalog_marker_on_owner_change()
  from public, anon, authenticated, service_role;

create trigger trg_cl_catalog_marker_owner_change
  after update of collection_id on public.collection_layout
  for each row
  when (old.collection_id is distinct from new.collection_id)
  execute function public.binder_catalog_marker_on_owner_change();

-- B3. Convidada associada: marco novo; se a linha é de DONA ativa ou encerrada nesta transação
--     (antiga dona na transferência), preserva o marco
create function public.binder_catalog_marker_on_guest_insert()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  insert into public.collection_layout_catalog_marker as m (layout_id, collection_id, marker_at, marker_source, role)
  values (new.layout_id, new.collection_id, new.created_at, 'GUEST_ATTACHED', 'GUEST')
  on conflict (layout_id, collection_id) do update
    set marker_at     = case when m.role = 'OWNER'
                              and (m.ended_xact is null or m.ended_xact = pg_current_xact_id())
                             then m.marker_at else excluded.marker_at end,
        marker_source = case when m.role = 'OWNER'
                              and (m.ended_xact is null or m.ended_xact = pg_current_xact_id())
                             then m.marker_source else excluded.marker_source end,
        role          = 'GUEST',
        ended_xact    = null,
        updated_at    = now();
  return null;
end;
$$;

revoke all on function public.binder_catalog_marker_on_guest_insert()
  from public, anon, authenticated, service_role;

create trigger trg_cl_catalog_marker_guest_insert
  after insert on public.collection_layout_guest
  for each row execute function public.binder_catalog_marker_on_guest_insert();

-- B4. Fim da participação: encerra (não apaga), ao fim de cada comando
create function public.binder_catalog_marker_cleanup()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_layout uuid;
  v_coll   uuid;
begin
  if tg_table_name = 'collection_layout_guest' then
    v_layout := (to_jsonb(old) ->> 'layout_id')::uuid;
  else
    v_layout := (to_jsonb(old) ->> 'id')::uuid;
  end if;
  v_coll := (to_jsonb(old) ->> 'collection_id')::uuid;

  if not exists (select 1 from public.collection_layout l
                 where l.id = v_layout and l.collection_id = v_coll)
     and not exists (select 1 from public.collection_layout_guest g
                     where g.layout_id = v_layout and g.collection_id = v_coll) then
    update public.collection_layout_catalog_marker m
       set ended_xact = pg_current_xact_id(), updated_at = now()
     where m.layout_id = v_layout and m.collection_id = v_coll and m.ended_xact is null;
  end if;
  return null;
end;
$$;

revoke all on function public.binder_catalog_marker_cleanup()
  from public, anon, authenticated, service_role;

create trigger trg_cl_catalog_marker_guest_cleanup
  after delete on public.collection_layout_guest
  for each row execute function public.binder_catalog_marker_cleanup();

create trigger trg_cl_catalog_marker_owner_cleanup
  after update of collection_id on public.collection_layout
  for each row
  when (old.collection_id is distinct from new.collection_id)
  execute function public.binder_catalog_marker_cleanup();

commit;

/*
Como validar (somente leitura):

select c.relname, c.relrowsecurity,
       (select count(*) from pg_policy p where p.polrelid = c.oid)                           as policies,
       has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE')          as auth_any,
       has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE')                   as anon_any,
       has_table_privilege('service_role', c.oid, 'SELECT,INSERT,UPDATE,DELETE')           as service_any
from pg_class c
where c.oid in ('public.collection_layout_catalog_incorporation'::regclass,
                'public.collection_layout_catalog_marker'::regclass);
-- esperado: true | 0 | false | false | false (duas linhas)

-- LIVE_90: participantes × marcos ativos (as três contagens têm de ser 0)
with p as (select l.id as layout_id, l.collection_id from public.collection_layout l
           union all
           select g.layout_id, g.collection_id from public.collection_layout_guest g),
     m as (select m.layout_id, m.collection_id from public.collection_layout_catalog_marker m
           where m.ended_xact is null)
select (select count(*) from p where not exists (select 1 from m where m.layout_id = p.layout_id and m.collection_id = p.collection_id)) as participante_sem_marco,
       (select count(*) from m where not exists (select 1 from p where p.layout_id = m.layout_id and p.collection_id = m.collection_id)) as marco_sem_participante,
       (select count(*) from public.collection_layout_catalog_marker m where m.ended_xact is not null)                                     as encerrados;
-- esperado logo após a migration: 0 | 0 | 0

select t.tgname, t.tgdeferrable, t.tgconstraint <> 0 as constraint_trigger
from pg_trigger t where t.tgname like 'trg_cl_catalog_marker_%' order by 1;
-- esperado: 5 gatilhos, todos tgdeferrable = false e constraint_trigger = false

Como reverter (só antes de 5264–5266): drop dos 5 gatilhos, das 4 funções e das 2 tabelas.
*/
