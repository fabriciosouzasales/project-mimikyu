/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5245 - Identidade e Centro de Controle do Fichário
              set_my_binder_identity(uuid, text, boolean)  — escrita (só proprietária)
              get_my_binder_identity(uuid)                 — leitura leve (proprietária e convidada)
              get_my_binder_occupancy(uuid)                — leitura sob demanda (painel Informações)
Versão......: 1.0 (2026-10-23, P3A-BINDER-CONTROL-IDENTITY-IMPLEMENTATION-01)
Status......: PROPOSTA — NÃO EXECUTADA. Aplicação só com autorização
              expressa de Fabrício, depois da 5244 (README §11).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

set_my_binder_identity — regras (README §5):
  R3  Normalização no servidor: entrada > 200 caracteres ou com caractere
      de controle (quebra de linha, tab…) → INVALID_BINDER_NAME, sem
      tentar "consertar". Espaços internos colapsados, pontas aparadas.
      Vazio/NULL → NULL (volta ao fallback: nome da coleção proprietária).
      Resultado com mais de 60 caracteres → INVALID_BINDER_NAME.
  R4  Só a coleção PROPRIETÁRIA edita. Convidada → BINDER_OWNER_ONLY
      (42501), sem tocar em nada. Coleção arquivada → COLLECTION_ARCHIVED.
      Coleção alheia ou inexistente → COLLECTION_NOT_FOUND (mesma
      mensagem nos dois casos; não enumera).
  R5  Trava canônica COLLECTION → LAYOUT via assert_collection_layout_mutable
      (5122) — a mesma de todas as escritas do fichário. Mesmo valor →
      operation = 'UNCHANGED', sem UPDATE (updated_at intacto). Último a
      gravar vence (nome não tem token de concorrência: não há dado
      derivado que possa ficar incoerente).
  R6  p_show_brand_mark obrigatório (NULL → INVALID_ARGUMENT).
  Só atualiza display_name/show_brand_mark. Nada em cartas, reservas,
  páginas, mesclagens, imagens ou progresso.

Leituras — separadas por custo (decisão de implementação, README §12):
  get_my_binder_identity — LEVE (PK/UNIQUE), lida no servidor junto com o
    cabeçalho na página da coleção e na rota /fichario (contracapa e
    título aparecem já na primeira pintura, sem piscar).
  get_my_binder_occupancy — agregado de bolsos, lido SÓ quando o painel
    Informações é aberto (não pesa a abertura do fichário).
  Ambas:
  - Fronteira: coleção do usuário (owner-scoped) antes de qualquer outra
    tabela; resolve o fichário próprio OU convidado (mesma regra da
    5230/5234). Sem fichário → nenhuma linha.
  Identidade: nome gravado (pode ser NULL), nome efetivo (fallback =
    nome da coleção proprietária), show_brand_mark, papel e se esta
    coleção pode editar (proprietária E ativa).
  Ocupação, cada BOLSO FÍSICO contado UMA vez, nesta precedência:
      card_pocket_count       bolso com carta (com ou sem reserva)
      image_pocket_count      bolso com imagem personalizada (5232)
      merged_pocket_count     bolso coberto por mesclagem (5119/5238)
      reserved_empty_count    reservado (5113) e sem carta
      free_pocket_count       livre de verdade
    Soma das cinco = pocket_count (verificado no harness 5853).
    merged_region_count / merged_image_count: mesclagens e quantas têm
    imagem (5239). Nada financeiro.
  - Custo: uma passagem pelos bolsos do fichário (≤ 100 páginas × 100
    bolsos), com EXISTS por PK/UNIQUE e regiões pelo índice da 5238
    (ix_collection_layout_region_page). Sem paginação: é agregado.
Dependências: 5122, 5234 (binder_slot_image_resolve_layout), 5229, 5232, 5238,
5239, 5244.
================================================================
*/

begin;

do $pre$
begin
  if not exists (select 1 from information_schema.columns
                 where table_schema = 'public' and table_name = 'collection_layout'
                   and column_name = 'display_name') then
    raise exception 'PRECHECK 5245: aplique a 5244 antes';
  end if;
  if to_regclass('public.collection_layout_region_image') is null
     or to_regclass('public.collection_layout_slot_image') is null
     or to_regclass('public.collection_layout_guest') is null then
    raise exception 'PRECHECK 5245: dependências 5229/5232/5239 ausentes';
  end if;
  if to_regprocedure('public.set_my_binder_identity(uuid, text, boolean)') is not null
     or to_regprocedure('public.get_my_binder_identity(uuid)') is not null
     or to_regprocedure('public.get_my_binder_occupancy(uuid)') is not null then
    raise exception 'PRECHECK 5245: funções já existem';
  end if;
end;
$pre$;

-- 1. Escrita ------------------------------------------------------------------------------
create function public.set_my_binder_identity(
  p_collection_id   uuid,
  p_display_name    text,
  p_show_brand_mark boolean
)
returns table (
  layout_id       uuid,
  display_name    text,
  effective_name  text,
  show_brand_mark boolean,
  operation       text
)
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
#variable_conflict use_column
declare
  v_uid       uuid := auth.uid();
  v_name      text;
  v_layout    uuid;
  v_old_name  text;
  v_old_mark  boolean;
  v_owner_nm  text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null or p_show_brand_mark is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  -- R3: valida a entrada antes de qualquer leitura (não revela nada).
  if p_display_name is not null then
    if char_length(p_display_name) > 200 or p_display_name ~ '[[:cntrl:]]' then
      raise exception 'INVALID_BINDER_NAME' using errcode = '22023',
        hint = 'use de 1 a 60 caracteres, sem quebras de linha';
    end if;
    v_name := btrim(regexp_replace(p_display_name, '\s+', ' ', 'g'));
    if v_name = '' then
      v_name := null;
    elsif char_length(v_name) > 60 then
      raise exception 'INVALID_BINDER_NAME' using errcode = '22023',
        hint = 'use de 1 a 60 caracteres, sem quebras de linha';
    end if;
  end if;

  -- Fronteira de autorização: coleção do usuário.
  perform 1 from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout
  from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is null then
    -- R4: convidada só lê; coleção sem fichário não tem identidade.
    if exists (select 1 from public.collection_layout_guest g where g.collection_id = p_collection_id) then
      raise exception 'BINDER_OWNER_ONLY' using errcode = '42501',
        hint = 'o nome e a contracapa são definidos pela coleção dona do fichário';
    end if;
    raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- R5: trava canônica COLLECTION → LAYOUT e ACTIVE lido sob a trava.
  begin
    perform public.assert_collection_layout_mutable(v_layout);
  exception
    when others then
      if sqlerrm like 'collection layout not found%' then
        raise exception 'BINDER_NOT_FOUND' using errcode = 'P0002';
      elsif sqlerrm like 'collection is ARCHIVED%' then
        raise exception 'COLLECTION_ARCHIVED' using errcode = '55000',
          hint = 'reative a coleção para editar o fichário';
      end if;
      raise;
  end;

  select l.display_name, l.show_brand_mark, c.name::text
    into v_old_name, v_old_mark, v_owner_nm
  from public.collection_layout l
  join public.collection c on c.id = l.collection_id
  where l.id = v_layout;

  if v_old_name is not distinct from v_name and v_old_mark = p_show_brand_mark then
    operation := 'UNCHANGED';
  else
    update public.collection_layout l
       set display_name = v_name,
           show_brand_mark = p_show_brand_mark
     where l.id = v_layout;
    operation := 'UPDATED';
  end if;

  layout_id       := v_layout;
  display_name    := v_name;
  effective_name  := coalesce(v_name, v_owner_nm);
  show_brand_mark := p_show_brand_mark;
  return next;
end;
$$;

comment on function public.set_my_binder_identity(uuid, text, boolean) is
  'P3-A (5245): grava nome próprio (1..60, normalizado; vazio = volta ao nome da coleção proprietária) e exibir/ocultar logomarca do fichário. Só a proprietária ativa; convidada → BINDER_OWNER_ONLY. Trava 5122. Idempotente (UNCHANGED). Não toca em cartas, reservas, páginas, mesclagens ou progresso.';

revoke all on function public.set_my_binder_identity(uuid, text, boolean) from public;
revoke all on function public.set_my_binder_identity(uuid, text, boolean) from anon;
grant execute on function public.set_my_binder_identity(uuid, text, boolean) to authenticated;

-- 2. Leitura leve da identidade --------------------------------------------------------
create function public.get_my_binder_identity(p_collection_id uuid)
returns table (
  layout_id              uuid,
  binder_role            text,
  owner_collection_id    uuid,
  owner_collection_name  text,
  display_name           text,
  effective_name         text,
  show_brand_mark        boolean,
  can_edit_identity      boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid     uuid := auth.uid();
  v_status  text;
  v_layout  uuid;
  v_role    text;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;

  select c.lifecycle_status into v_status
  from public.collection c
  where c.id = p_collection_id and c.owner_user_id = v_uid;
  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  select l.id into v_layout from public.collection_layout l where l.collection_id = p_collection_id;
  if v_layout is not null then
    v_role := 'OWNER';
  else
    select g.layout_id into v_layout from public.collection_layout_guest g where g.collection_id = p_collection_id;
    if v_layout is null then
      return;
    end if;
    v_role := 'GUEST';
  end if;

  return query
  select l.id,
         v_role,
         l.collection_id,
         oc.name::text,
         l.display_name,
         coalesce(l.display_name, oc.name::text),
         l.show_brand_mark,
         (v_role = 'OWNER' and v_status = 'ACTIVE')
  from public.collection_layout l
  join public.collection oc on oc.id = l.collection_id
  where l.id = v_layout;
end;
$$;

comment on function public.get_my_binder_identity(uuid) is
  'P3-A (5245): identidade do fichário — nome gravado, nome efetivo (fallback: coleção proprietária), logomarca, papel e se esta coleção pode editar. Proprietária e convidada; alheia → COLLECTION_NOT_FOUND; sem fichário → 0 linhas. Leitura leve (PK/UNIQUE).';

revoke all on function public.get_my_binder_identity(uuid) from public;
revoke all on function public.get_my_binder_identity(uuid) from anon;
grant execute on function public.get_my_binder_identity(uuid) to authenticated;

-- 3. Ocupação (sob demanda) ---------------------------------------------------------------
create function public.get_my_binder_occupancy(p_collection_id uuid)
returns table (
  layout_id              uuid,
  grid_columns           integer,
  grid_rows              integer,
  page_count             integer,
  pocket_count           integer,
  card_pocket_count      integer,
  image_pocket_count     integer,
  merged_pocket_count    integer,
  reserved_empty_count   integer,
  free_pocket_count      integer,
  merged_region_count    integer,
  merged_image_count     integer,
  participant_count      integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_layout  uuid;
begin
  -- Fronteira e resolução compartilhadas (5234): owner-scoped, próprio ou convidado.
  v_layout := public.binder_slot_image_resolve_layout(p_collection_id);
  if v_layout is null then
    return;
  end if;

  return query
  with pockets as (
    select
      exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s.id)     as has_card,
      exists (select 1 from public.collection_layout_slot_image i where i.slot_id = s.id)          as has_image,
      exists (select 1 from public.collection_layout_region r
              where r.page_id = s.page_id
                and s.row_index    between r.top_row     and r.top_row + r.height - 1
                and s.column_index between r.left_column and r.left_column + r.width - 1)          as in_region,
      exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = s.id) as reserved
    from public.collection_layout_page p
    join public.collection_layout_slot s on s.page_id = p.id
    where p.layout_id = v_layout
  ),
  occ as (
    select
      count(*)::integer                                                                         as total,
      count(*) filter (where has_card)::integer                                                 as cards,
      count(*) filter (where not has_card and has_image)::integer                               as images,
      count(*) filter (where not has_card and not has_image and in_region)::integer             as merged,
      count(*) filter (where not has_card and not has_image and not in_region and reserved)::integer as resv,
      count(*) filter (where not has_card and not has_image and not in_region and not reserved)::integer as free
    from pockets
  ),
  reg as (
    select count(*)::integer as regions,
           count(ri.region_id)::integer as region_images
    from public.collection_layout_page p
    join public.collection_layout_region r on r.page_id = p.id
    left join public.collection_layout_region_image ri on ri.region_id = r.id
    where p.layout_id = v_layout
  )
  select l.id,
         l.grid_columns,
         l.grid_rows,
         (select count(*) from public.collection_layout_page p where p.layout_id = l.id)::integer,
         occ.total,
         occ.cards,
         occ.images,
         occ.merged,
         occ.resv,
         occ.free,
         reg.regions,
         reg.region_images,
         1 + (select count(*) from public.collection_layout_guest g where g.layout_id = l.id)::integer
  from public.collection_layout l
  cross join occ
  cross join reg
  where l.id = v_layout;
end;
$$;

comment on function public.get_my_binder_occupancy(uuid) is
  'P3-A (5245): ocupação do fichário — cada bolso físico contado uma vez (carta > imagem > mesclagem > reservado vazio > livre), mesclagens e imagens de mesclagem, participantes. Proprietária e convidada; alheia → COLLECTION_NOT_FOUND; sem fichário → 0 linhas. Sem valores financeiros. Lida sob demanda.';

revoke all on function public.get_my_binder_occupancy(uuid) from public;
revoke all on function public.get_my_binder_occupancy(uuid) from anon;
grant execute on function public.get_my_binder_occupancy(uuid) to authenticated;

commit;

/*
Resultado esperado: 3 funções novas, SECURITY DEFINER, search_path='',
EXECUTE só para authenticated (e postgres). Nenhum dado alterado.

Como validar (só leitura):
select p.proname, p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_exec,   -- false
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec    -- true
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('set_my_binder_identity', 'get_my_binder_identity', 'get_my_binder_occupancy')
order by 1;
*/
