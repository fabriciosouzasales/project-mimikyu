/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5265 - Fichário Digital × Catálogo: leituras (aviso de
              novidades e prévia da incorporação)
Versão......: 1.3 (2026-10-24, A7-CORRECTION-01: corpo inalterado; motivo
              MARKER_MISSING documentado.) Anterior 1.2 (2026-10-24, W5-FOUNDATION-01: corpo inalterado; renumerada
              de 5264 para 5265. Por herdar binder_catalog_novelties, a
              novidade já incorporada — mesmo com a reserva liberada — não
              aparece no aviso nem na prévia; selecioná-la explicitamente na
              prévia → SELECTION_INVALID.) Anterior 1.1 (AUDIT-CORRECTION-01):
              placed_in_binder substitui placed_unreserved — W6.
Status......: PROPOSTA — NÃO EXECUTADA. Sem autorização para o LIVE.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-24

Descrição...:
  get_my_binder_catalog_novelties(collection)
    Aviso leve. Nunca falha por inelegibilidade: devolve eligible=false e o
    motivo (NOT_MASTER_SET, BINDER_NOT_FOUND, BINDER_OWNER_POKEDEX,
    SPECIES_REFERENCES_PRESENT, COLLECTION_REFERENCE_MISSING,
    COLLECTION_ARCHIVED, MARKER_MISSING — A7: marco de participação ausente,
    fail-closed). Elegível: uma linha por novidade (ou uma linha com
    novelty_count = 0). placed_in_binder = já há exemplar desta coleção dessa
    posição colocado em algum bolso do fichário: se for o bolso natural, a
    prévia reserva ali (RESERVE_PLACED); em qualquer outro, a carta fica onde
    está e o item vai para revisão (OUT_OF_ORDER, decisão W6).

  preview_my_binder_catalog_reconciliation(collection, keys)
    Prévia SOMENTE LEITURA da seleção (keys = null → todas as novidades).
    Linha HEADER (resultado, totais, confirmações exigidas, páginas
    adicionadas — números exatos —, capacidade antes/depois, bolsos livres
    depois, plan_token) + uma linha ITEM por novidade selecionada (tipo,
    destino, fim da cadeia, âncora, bolsos/linhas movidos, reservas de outras
    coleções movidas, mudança de página, página nova, barreira).
    Inelegível → erro (NOT_MASTER_SET 22023, BINDER_NOT_ELIGIBLE 22023 com o
    motivo no hint, BINDER_NOT_FOUND P0002, COLLECTION_ARCHIVED 55000).

Autorização: binder_slot_image_resolve_layout (5234) — sessão obrigatória
(28000) e coleção do usuário (alheia/inexistente → COLLECTION_NOT_FOUND,
sem enumerar). Só lê (inclusive o registro W5 da 5263, via 5264). Pokédex
nunca é processada.
Dependências: 5263, 5264.
================================================================
*/

begin;

do $pre$
begin
  if to_regprocedure('public.binder_catalog_plan(uuid, text[])') is null then
    raise exception 'PRECHECK 5265: aplique 5264 antes';
  end if;
  if to_regprocedure('public.preview_my_binder_catalog_reconciliation(uuid, text[])') is not null then
    raise exception 'PRECHECK 5265: já aplicada';
  end if;
end;
$pre$;

-- 1. Aviso de novidades --------------------------------------------------------------------------
create function public.get_my_binder_catalog_novelties(p_collection_id uuid)
returns table (
  eligible          boolean,
  reason            text,
  novelty_count     integer,
  item_key          text,
  card_id           uuid,
  variant_type_id   uuid,
  collector_number  text,
  card_name         text,
  variant_type_code text,
  variant_type_name text,
  born_at           timestamptz,
  placed_in_binder  boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  x   record;
  v_n integer;
begin
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform public.binder_slot_image_resolve_layout(p_collection_id);   -- 28000 / COLLECTION_NOT_FOUND

  select * into x from public.binder_catalog_context(p_collection_id);
  if not coalesce(x.eligible, false) then
    eligible := false; reason := x.reason; novelty_count := 0;
    return next; return;
  end if;

  select count(*)::integer into v_n
  from public.binder_catalog_novelties(p_collection_id) nv where nv.is_novelty;
  if v_n = 0 then
    eligible := true; novelty_count := 0;
    return next; return;
  end if;

  return query
  select true, null::text, v_n, nv.item_key, nv.card_id, nv.variant_type_id,
         c.collector_number::text, c.name::text, t.code::text, t.name::text, nv.born_at,
         exists (
           select 1
           from public.collection_layout_page pg
           join public.collection_layout_slot s on s.page_id = pg.id
           join public.collection_layout_slot_assignment a0 on a0.slot_id = s.id
           join public.physical_card pc on pc.id = a0.physical_card_id
           join public.card_variant cv on cv.id = pc.card_variant_id
           where pg.layout_id = x.layout_id
             and cv.card_id = nv.card_id
             and (nv.variant_type_id is null or cv.variant_type_id = nv.variant_type_id)
             and (exists (select 1 from public.collection_allocation ca
                          where ca.physical_card_id = pc.id and ca.collection_id = p_collection_id)
                  or (p_collection_id = x.owner_collection_id
                      and not exists (select 1 from public.collection_allocation ca
                                      where ca.physical_card_id = pc.id
                                        and (ca.collection_id = x.owner_collection_id
                                             or ca.collection_id in (select g.collection_id
                                                                     from public.collection_layout_guest g
                                                                     where g.layout_id = x.layout_id)))))
         )
  from public.binder_catalog_novelties(p_collection_id) nv
  join public.card c on c.id = nv.card_id
  left join public.card_variant_type t on t.id = nv.variant_type_id
  where nv.is_novelty
  order by nv.pos_ord;
end;
$$;

comment on function public.get_my_binder_catalog_novelties(uuid) is
  'Fichário Digital × Catálogo (5265): novidades do Catálogo ainda sem lugar no fichário de uma coleção Master Set (posições criadas depois da montagem/associação). Só lê. Inelegível (Pokédex, Set, Livre, fichário de dona Pokédex, arquivada) → eligible=false com o motivo.';

revoke all on function public.get_my_binder_catalog_novelties(uuid) from public, anon;
grant execute on function public.get_my_binder_catalog_novelties(uuid) to authenticated;

-- 2. Prévia ----------------------------------------------------------------------------------------
create function public.preview_my_binder_catalog_reconciliation(p_collection_id uuid, p_keys text[] default null)
returns table (
  row_kind             text,
  step_no              integer,
  item_key             text,
  card_id              uuid,
  variant_type_id      uuid,
  pos_ord              integer,
  kind                 text,
  target_page          integer,
  target_row           integer,
  target_column        integer,
  end_page             integer,
  end_row              integer,
  end_column           integer,
  anchor_page          integer,
  anchor_row           integer,
  anchor_column        integer,
  pockets_moved        integer,
  rows_moved           integer,
  other_reserves_moved integer,
  crosses_page         boolean,
  adds_page            boolean,
  barrier_page         integer,
  barrier_row          integer,
  barrier_column       integer,
  barrier_kind         text,
  outcome              text,
  reason               text,
  layout_id            uuid,
  total_items          integer,
  total_rows_moved     integer,
  row_limit            integer,
  item_limit           integer,
  requires_cross_page  boolean,
  requires_add_page    boolean,
  pages_added          integer,
  added_page_numbers   integer[],
  capacity_before      integer,
  capacity_after       integer,
  free_pockets_after   integer,
  plan_token           text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_collection_id is null then
    raise exception 'INVALID_ARGUMENT' using errcode = '22023';
  end if;
  perform public.binder_slot_image_resolve_layout(p_collection_id);   -- 28000 / COLLECTION_NOT_FOUND
  perform 1 from public.binder_catalog_assert_eligible(p_collection_id);
  return query select * from public.binder_catalog_plan(p_collection_id, p_keys);
end;
$$;

comment on function public.preview_my_binder_catalog_reconciliation(uuid, text[]) is
  'Fichário Digital × Catálogo (5265): prévia da incorporação das novidades selecionadas (null = todas) — destino de cada uma, bolsos que andam, mudança de página, páginas adicionadas, capacidade antes/depois e plan_token. Não grava nada. Só Master Set.';

revoke all on function public.preview_my_binder_catalog_reconciliation(uuid, text[]) from public, anon;
grant execute on function public.preview_my_binder_catalog_reconciliation(uuid, text[]) to authenticated;

commit;

/*
Resultado esperado: 2 RPCs SECURITY DEFINER, STABLE, search_path vazio,
EXECUTE só para authenticated.
Como validar: harness 5859 seções 0, 2, 3 e 4.
*/
