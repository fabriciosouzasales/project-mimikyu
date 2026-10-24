/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5247 - Identidade física do Fichário Digital
              collection_layout.storage_container_id (o fichário físico que
              o digital representa)
Versão......: 1.0 (2026-10-24, BINDER-PHYSICAL-LOCATION-ELIGIBILITY-DECISIONS-01)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-10-24
              (Fase A, autorização expressa de Fabrício; ledger
              20261024120931 `5247_add_collection_layout_storage_container`). Do `begin;` ao `commit;`
              idêntica ao arquivo de database/proposals/2026-10-24-binder-
              physical-location/ (só este bloco Status difere); enviada via
              apply_migration sem as linhas `begin;`/`commit;` externas — o texto
              gravado no ledger é igual ao corpo do arquivo (md5). LIVE_90 7/7 PASS.
              Ver LIVE-PHASE-A-2026-10-24.md da proposta.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Por quê (README §2): a elegibilidade para posicionar passa a decorrer do
LOCAL FÍSICO do exemplar. Hoje o fichário só conhece o local físico de forma
indireta (local padrão da coleção proprietária, mutável). Esta query dá ao
fichário a sua própria identidade física, estável.

Regras:
  - storage_container_id NOT NULL, FK → storage_container ON DELETE RESTRICT
    (o local de um fichário digital não pode ser excluído; 5218 já recusa
    local com exemplares).
  - UNIQUE: um fichário digital por fichário físico.
  - O local é do tipo BINDER e do MESMO dono da coleção proprietária.
  - Imutável depois de gravado (trocar de fichário físico = outro fichário).
  - Na inserção sem valor (montagem 5224, inalterada), herda o local padrão
    da coleção proprietária — que a 5224 já exige ser BINDER.
  - storage_container de um fichário digital não pode deixar de ser BINDER.
Backfill: o único layout atual recebe o local padrão da proprietária (F001),
sem tocar updated_at (gatilho de updated_at desligado só durante o UPDATE).
Dependências: 5105, 5106, 5212/5213, 5224, 5229.
================================================================
*/

begin;

set local lock_timeout = '5s';

do $pre$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'collection_layout'
               and column_name = 'storage_container_id') then
    raise exception 'PRECHECK 5247: collection_layout.storage_container_id já existe';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'trg_collection_layout_updated_at'
                 and tgrelid = 'public.collection_layout'::regclass) then
    raise exception 'PRECHECK 5247: trg_collection_layout_updated_at (5106) ausente';
  end if;
  -- Todo layout existente precisa ter proprietária com local padrão BINDER do mesmo dono.
  if exists (
    select 1
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    left join public.storage_container sc on sc.id = c.default_storage_container_id
    left join public.inventory i on i.id = sc.inventory_id
    where sc.id is null or sc.kind_code is distinct from 'BINDER' or i.owner_user_id is distinct from c.owner_user_id
  ) then
    raise exception 'PRECHECK 5247: há fichário cuja proprietária não tem local padrão BINDER do mesmo dono';
  end if;
  -- Dois fichários no mesmo local físico violariam a unicidade.
  if exists (
    select c.default_storage_container_id
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    group by c.default_storage_container_id
    having count(*) > 1
  ) then
    raise exception 'PRECHECK 5247: dois fichários digitais apontariam para o mesmo local físico';
  end if;
end;
$pre$;

alter table public.collection_layout add column storage_container_id uuid;

alter table public.collection_layout disable trigger trg_collection_layout_updated_at;

update public.collection_layout l
   set storage_container_id = c.default_storage_container_id
  from public.collection c
 where c.id = l.collection_id;

alter table public.collection_layout enable trigger trg_collection_layout_updated_at;

alter table public.collection_layout
  alter column storage_container_id set not null,
  add constraint fk_collection_layout_storage_container
    foreign key (storage_container_id) references public.storage_container(id)
    on update restrict on delete restrict,
  add constraint uq_collection_layout_storage_container unique (storage_container_id);

comment on column public.collection_layout.storage_container_id is
  'Fichário físico (storage_container BINDER) que este Fichário Digital representa (5247). Elegibilidade para bolso = exemplar guardado aqui. Imutável; único.';

-- Gatilho: herda na montagem, valida dono/tipo, impede troca ---------------------
create function public.enforce_collection_layout_storage_container()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner     uuid;
  v_sc_owner  uuid;
  v_kind      text;
begin
  if tg_op = 'UPDATE' then
    if new.storage_container_id is distinct from old.storage_container_id then
      raise exception 'BINDER_LOCATION_IMMUTABLE'
        using errcode = '55000',
              hint = 'o fichário digital representa sempre o mesmo fichário físico';
    end if;
    return new;
  end if;

  select c.owner_user_id into v_owner
  from public.collection c where c.id = new.collection_id;

  if new.storage_container_id is null then
    select c.default_storage_container_id into new.storage_container_id
    from public.collection c where c.id = new.collection_id;
  end if;

  select i.owner_user_id, sc.kind_code::text into v_sc_owner, v_kind
  from public.storage_container sc
  join public.inventory i on i.id = sc.inventory_id
  where sc.id = new.storage_container_id;

  if new.storage_container_id is null or v_sc_owner is null
     or v_sc_owner is distinct from v_owner or v_kind is distinct from 'BINDER' then
    raise exception 'BINDER_LOCATION_INVALID'
      using errcode = '22023',
            hint = 'o fichário digital precisa de um local físico do tipo Fichário, do mesmo dono';
  end if;

  if exists (select 1 from public.collection_layout l
             where l.storage_container_id = new.storage_container_id) then
    raise exception 'BINDER_LOCATION_TAKEN'
      using errcode = '23505',
            hint = 'este fichário físico já tem um fichário digital — use "Usar fichário existente"';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_collection_layout_storage_container() from public, anon, authenticated;

create trigger trg_collection_layout_storage_container
  before insert or update of storage_container_id on public.collection_layout
  for each row execute function public.enforce_collection_layout_storage_container();

-- Local de um fichário digital continua sendo BINDER ----------------------------
create function public.enforce_storage_container_binder_kind()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind_code is distinct from old.kind_code
     and new.kind_code is distinct from 'BINDER'
     and exists (select 1 from public.collection_layout l where l.storage_container_id = old.id) then
    raise exception 'STORAGE_IS_DIGITAL_BINDER'
      using errcode = '55000',
            hint = 'este local tem um fichário digital — o tipo precisa continuar Fichário';
  end if;
  return new;
end;
$$;

revoke all on function public.enforce_storage_container_binder_kind() from public, anon, authenticated;

create trigger trg_storage_container_binder_kind
  before update of kind_code on public.storage_container
  for each row execute function public.enforce_storage_container_binder_kind();

do $post$
begin
  if exists (select 1 from public.collection_layout where storage_container_id is null) then
    raise exception 'POSTCHECK 5247: layout sem local físico';
  end if;
  if exists (select 1 from public.collection_layout l join public.collection c on c.id = l.collection_id
             where l.storage_container_id is distinct from c.default_storage_container_id) then
    raise exception 'POSTCHECK 5247: backfill divergente do local padrão da proprietária';
  end if;
end;
$post$;

commit;

/*
Resultado esperado: 1 coluna NOT NULL + FK RESTRICT + UNIQUE; 2 gatilhos;
o layout existente aponta para F001; updated_at do layout inalterado.

Como validar (só leitura):
select l.id, sc.name, sc.kind_code, l.updated_at
from public.collection_layout l join public.storage_container sc on sc.id = l.storage_container_id;
*/
