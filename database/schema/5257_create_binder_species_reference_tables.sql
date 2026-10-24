/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5257 - Referências de espécie por bolso (Fichário da Pokédex)
              collection_layout_slot_species_reference   — vínculo bolso → posição da Pokédex
              collection_layout_species_reference_setting — preferência de exibição do fichário
Versão......: 1.0 (2026-10-24, POKEDEX-BINDER-SPECIES-REFERENCE-IMPLEMENTATION-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-24
              (LIVE-EXECUTION-01, autorização expressa de Fabrício; ledger
              20261024163436 `5257_create_binder_species_reference_tables`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-24-pokedex-
              binder-species-reference/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo (md5). Harness 5857
              não executado. Ver LIVE-EXECUTION-2026-10-24.md da proposta.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Decisões (README §2, D1–D3 e ajustes A/B aprovados):
  - A referência pertence ao BOLSO (slot_id é a PK): é um rótulo impresso
    no plástico, não um conteúdo. Não é carta, reserva, exemplar nem
    progresso; nenhuma leitura de inventário, progresso, montagem ou
    armazenamento lê esta tabela.
  - D1: inserir/fechar vão (5243), mover/trocar (5132) e retirar carta não
    tocam a tabela — a referência fica no bolso físico.
  - (layout_id, pokedex_position_id) único: a mesma espécie não aparece duas
    vezes no mesmo fichário.
  - collection_id = coleção PROPRIETÁRIA no momento da aplicação. A leitura
    (5259) só mostra referências cuja collection_id é a proprietária atual
    do fichário: se o fichário for transferido (5254), elas ficam ocultas,
    sem apagar nada.
  - source: 'NATIONAL_ORDER' (único valor nesta versão). Ampliável em fase
    futura de personalização sem mudar a chave.
  - Bolso apagado → referência apagada (ON DELETE CASCADE). Motivo: a
    desmontagem do fichário (5242) apaga páginas/bolsos e continua
    funcionando sem alteração. A remoção de UMA página não apaga
    referências em silêncio: a 5260 exige confirmação explícita com a
    contagem (ajuste B).
  - Ajuste A: a preferência de exibição fica numa tabela própria, separada
    das referências. Ocultar NUNCA apaga vínculos. Sem linha = visível.
  - Deny by default: RLS ligada, SEM policies e SEM grants para
    anon/authenticated. Todo acesso passa pelas RPCs SECURITY DEFINER da
    5258/5259/5260.
  - Gatilho de integridade (defesa em profundidade, as RPCs já garantem):
    bolso pertence ao layout; coleção é a proprietária do layout e é uma
    coleção de Pokédex; a posição é da Pokédex da coleção.

Volume: ~1.025 linhas por fichário de Pokédex Nacional. Leitura sempre por
layout + páginas (índice cl_ssr_layout_idx); a PK cobre o acesso por bolso.

Nada aqui toca cartas, alocações, reservas, travas, regiões, imagens,
páginas, exemplares, armazenamento ou progresso.
Dependências: 5104–5108 (fichário), 5229 (guest), 5085–5099 (Pokédex),
6030–6051 (pokedex/pokedex_position).
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if to_regclass('public.collection_layout_slot') is null
     or to_regclass('public.collection_layout_page') is null
     or to_regclass('public.pokedex_position') is null
     or to_regclass('public.collection_pokedex_reference') is null then
    raise exception 'PRECHECK 5257: dependências ausentes (fichário ou Pokédex)';
  end if;
  if to_regclass('public.collection_layout_slot_species_reference') is not null
     or to_regclass('public.collection_layout_species_reference_setting') is not null then
    raise exception 'PRECHECK 5257: tabelas já existem';
  end if;
end;
$pre$;

-- 1. Vínculo bolso → posição -------------------------------------------------------------
create table public.collection_layout_slot_species_reference (
  slot_id             uuid        not null,
  layout_id           uuid        not null,
  collection_id       uuid        not null,
  pokedex_position_id uuid        not null,
  source              text        not null default 'NATIONAL_ORDER',
  created_at          timestamptz not null default now(),
  constraint pk_cl_slot_species_reference primary key (slot_id),
  constraint fk_cl_ssr_slot foreign key (slot_id)
    references public.collection_layout_slot (id) on update restrict on delete cascade,
  constraint fk_cl_ssr_layout foreign key (layout_id)
    references public.collection_layout (id) on update restrict on delete cascade,
  constraint fk_cl_ssr_collection foreign key (collection_id)
    references public.collection (id) on update restrict on delete cascade,
  constraint fk_cl_ssr_position foreign key (pokedex_position_id)
    references public.pokedex_position (id) on update restrict on delete restrict,
  constraint uq_cl_ssr_layout_position unique (layout_id, pokedex_position_id),
  constraint chk_cl_ssr_source check (source in ('NATIONAL_ORDER'))
);

create index cl_ssr_layout_idx
  on public.collection_layout_slot_species_reference (layout_id);
create index cl_ssr_collection_idx
  on public.collection_layout_slot_species_reference (collection_id);
create index cl_ssr_position_idx
  on public.collection_layout_slot_species_reference (pokedex_position_id);

comment on table public.collection_layout_slot_species_reference is
  'Referência visual de espécie por bolso do fichário (POKEDEX-BINDER-SPECIES-REFERENCE). Não é carta, reserva, exemplar nem progresso.';

-- 2. Preferência de exibição (ajuste A) --------------------------------------------------
create table public.collection_layout_species_reference_setting (
  layout_id          uuid        not null,
  references_visible boolean     not null default true,
  updated_at         timestamptz not null default now(),
  constraint pk_cl_species_reference_setting primary key (layout_id),
  constraint fk_cl_srs_layout foreign key (layout_id)
    references public.collection_layout (id) on update restrict on delete cascade
);

comment on table public.collection_layout_species_reference_setting is
  'Preferência de exibição das referências de espécie do fichário. Ocultar não apaga vínculos; sem linha = visível.';

-- 3. Deny by default ---------------------------------------------------------------------
alter table public.collection_layout_slot_species_reference enable row level security;
alter table public.collection_layout_species_reference_setting enable row level security;
revoke all on table public.collection_layout_slot_species_reference from public, anon, authenticated;
revoke all on table public.collection_layout_species_reference_setting from public, anon, authenticated;

-- 4. Integridade -------------------------------------------------------------------------
create function public.enforce_collection_layout_slot_species_reference_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_layout_of_slot uuid;
  v_owner          uuid;
  v_dex            uuid;
begin
  select pg.layout_id into v_layout_of_slot
  from public.collection_layout_slot s
  join public.collection_layout_page pg on pg.id = s.page_id
  where s.id = new.slot_id;
  if v_layout_of_slot is null or v_layout_of_slot <> new.layout_id then
    raise exception 'SPECIES_REFERENCE_SLOT_LAYOUT_MISMATCH' using errcode = '23514';
  end if;

  select l.collection_id into v_owner
  from public.collection_layout l where l.id = new.layout_id;
  if v_owner is null or v_owner <> new.collection_id then
    raise exception 'SPECIES_REFERENCE_OWNER_MISMATCH' using errcode = '23514';
  end if;

  select cpr.pokedex_id into v_dex
  from public.collection c
  join public.collection_reference cr
    on cr.collection_id = c.id and cr.reference_kind = 'POKEDEX'
  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
  where c.id = new.collection_id
    and c.mode = 'REFERENCE_BASED'
    and c.completion_policy = 'REFERENCE_POSITION';
  if v_dex is null then
    raise exception 'SPECIES_REFERENCE_NOT_POKEDEX' using errcode = '23514';
  end if;

  perform 1 from public.pokedex_position pp
  where pp.id = new.pokedex_position_id and pp.pokedex_id = v_dex;
  if not found then
    raise exception 'SPECIES_REFERENCE_POSITION_MISMATCH' using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_collection_layout_slot_species_reference_integrity()
  from public, anon, authenticated;

create trigger trg_cl_slot_species_reference_integrity
  before insert or update on public.collection_layout_slot_species_reference
  for each row execute function public.enforce_collection_layout_slot_species_reference_integrity();

commit;

/*
Como validar (somente leitura):

select c.relname, c.relrowsecurity,
       has_table_privilege('authenticated', c.oid, 'SELECT') as auth_select,
       has_table_privilege('anon', c.oid, 'SELECT')          as anon_select,
       (select count(*) from pg_policies p where p.tablename = c.relname) as policies
from pg_class c
where c.relnamespace = 'public'::regnamespace
  and c.relname in ('collection_layout_slot_species_reference',
                    'collection_layout_species_reference_setting');
-- esperado: relrowsecurity true, auth_select false, anon_select false, policies 0

Como reverter (antes de qualquer dado): drop table de ambas + drop function do gatilho.
*/
