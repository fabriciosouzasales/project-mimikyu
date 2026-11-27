/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5393 - get_shared_collection_binder_pages_with_species():
              páginas mascaradas do fichário do participante + referências
              de espécie autorizadas (V1-13 · E3-6 / S3)
Versão......: 1.0 (2026-11-26, `E3-6 / S3-5393 — SQL & HARNESS PREPARATION-01`)
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core (qjfutqujxrbzgrtkpgkg,
              PG 17.6) em 2026-11-27 (`E3-6 / S3-5393 — AUTHORIZED LIVE DEPLOYMENT-01`,
              autorização expressa do proprietário): PRE 15/15, transação única
              confirmada (precheck e postcheck internos sem erro), POST 11/11, md5 do
              prosrc = 34c87736937dd09b6495f435c80ccbe6. Do `begin;` ao `commit;`
              idêntica ao arquivo da proposta (só este bloco Status difere). Canal:
              Management API `database/query` (papel postgres), sem gravar
              supabase_migrations (como a E1). Barreira CLOSED (inerte para clientes).
              Harness 5897 NÃO executado (prova funcional no gate de abertura).
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-26
Decisão.....: D-E3-9 (EDITOR e VIEWER veem as referências de espécie, pela
              apresentação mascarada, sem inferência patrimonial). Contrato:
              README deste pacote (§2–§6, §10.1) com C1–C3.
Depende de..: 5302 collection_share_role (STABLE), 5315
              collection_binder_masked_pages (STABLE, interna), 5257
              (collection_layout_slot_species_reference,
              collection_layout_species_reference_setting), 5108/5110
              (página e bolso únicos por posição), 5389
              v1_13_assert_capability (STABLE). Não toca 5315, 5316, 5318,
              5257–5260, 5383 nem dado algum.

Regras (README §3):
  1. Barreira: v1_13_assert_capability() → fechada: CAPABILITY_NOT_ENABLED
     (42501). Desvio deliberado do padrão de leitura G1 (zero linhas seria
     indistinguível de "janela além do fim").
  2. Acesso: collection_share_role(X) ∈ {OWNER, VIEWER}, senão
     COLLECTION_NOT_FOUND (P0002) — idêntico à 5316, antes de qualquer
     tabela do fichário. O EDITOR lê como VIEWER (5302): mesma resposta.
  3. Linhas: exatamente as do núcleo 5315 (mesma janela 1..4, mesmas
     validações, mesma ordem página → linha → coluna); as 11 primeiras
     colunas são as do núcleo, sem transformação.
  4. Camada autorizada: o fichário tem X como PROPRIETÁRIA
     (collection_layout.collection_id = X) E X é Pokédex.
  5. references_visible: camada autorizada → preferência do fichário
     (sem linha = true, como 5259); senão NULL.
  6. Espécie (número nacional, nome, arte) só se camada autorizada,
     references_visible = true, pocket_state = 'EMPTY' (estado MASCARADO,
     nada mais) e a referência do bolso tem collection_id = X. A parte nova
     da consulta não lê posição de exemplar, imagem, região nem reserva.
Consistência (README §6, C1): função STABLE; em READ COMMITTED, as consultas
  de uma função não volátil usam o instantâneo da consulta que a chamou.
  Autorização (5302, STABLE), núcleo (5315, STABLE, chamado na mesma
  consulta) e referências enxergam o mesmo instantâneo. Sem garantia entre
  chamadas. Toda função chamada é STABLE (5389, 5302, 5315; auth.uid() da
  plataforma — conferir na S0). Sem SQL dinâmico.
Desempenho: ≤ 400 linhas por janela; junção por chaves únicas
  (uq_collection_layout_page_number, uq_collection_layout_slot_position,
  pk_cl_slot_species_reference, PKs de posição/espécie, no máximo uma arte
  IMPORTED por espécie). Não medido (harness 5897 §4).
Canal.......: psql, transação única. Precheck: dependências presentes com os
              corpos canônicos (md5 do prosrc derivado de database/schema e do
              pacote G1; confirmar no LIVE na S0) e função ausente.
Reversão....: R5393 em ROLLBACK_S3.sql (drop function; não toca dados).
Como validar: harness 5897 (seções 0–6) e scripts locais 5897_C (concorrência)
              e 5897_P (desempenho).
================================================================
*/

begin;
set local lock_timeout = '5s';

do $pre$
begin
  if to_regprocedure('public.v1_13_assert_capability()') is null then
    raise exception 'PRECHECK 5393: barreira 5389 ausente';
  end if;
  if to_regprocedure('public.collection_share_role(uuid)') is null
     or to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)') is null
     or to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)') is null
     or to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)') is null
     or to_regclass('public.collection_layout_slot_species_reference') is null
     or to_regclass('public.collection_layout_species_reference_setting') is null then
    raise exception 'PRECHECK 5393: dependências ausentes (5302, 5315, 5316, 5318, 5257)';
  end if;
  -- Corpos canônicos (md5 do prosrc, derivados dos arquivos; a S0 confirma no LIVE).
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_share_role(uuid)')) is distinct from 'efdb495b5b703e9f093eb0f49a1d0a5d'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')) is distinct from 'ce559a495a49571a6598c83bc3d59202'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)')) is distinct from '79f893c45a08909e0a61d661952ab750'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)')) is distinct from '0da2d28209cd85b6bdbf6c20ae47efd6'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_assert_capability()')) is distinct from 'e4f710904f50e6e8c3f1d8e2337639e0'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.v1_13_capability_open()')) is distinct from '32e2f636361732b497e8401e50f0bbe0' then
    raise exception 'PRECHECK 5393: ESTADO DIVERGENTE — corpo de 5302/5315/5316/5318/5389 difere do canônico';
  end if;
  -- C1: toda função chamada precisa ser STABLE (ou IMMUTABLE).
  if exists (select 1 from pg_catalog.pg_proc p
             where p.oid in (to_regprocedure('public.collection_share_role(uuid)'),
                             to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)'),
                             to_regprocedure('public.v1_13_assert_capability()'),
                             to_regprocedure('public.v1_13_capability_open()'),
                             to_regprocedure('auth.uid()'))
               and p.provolatile not in ('s', 'i'))
     or to_regprocedure('auth.uid()') is null then
    raise exception 'PRECHECK 5393: dependência VOLÁTIL ou auth.uid() ausente — a garantia de instantâneo único (C1) não vale';
  end if;
  if to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)') is not null
     or exists (select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = 'get_shared_collection_binder_pages_with_species') then
    raise exception 'PRECHECK 5393: JÁ APLICADA ou ESTADO DIVERGENTE';
  end if;
end;
$pre$;

create function public.get_shared_collection_binder_pages_with_species(
  p_collection_id uuid,
  p_first_page    integer,
  p_page_count    integer
)
returns table (
  page_number             integer,
  row_index               integer,
  column_index            integer,
  pocket_state            text,
  card_name               text,
  collector_number        text,
  collector_total         integer,
  card_set_code           text,
  variant_label           text,
  language_code           text,
  image_path              text,
  species_national_number integer,
  species_name            text,
  species_artwork_path    text,
  references_visible      boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
#variable_conflict use_column
declare
  v_role text;
begin
  perform public.v1_13_assert_capability();  -- G1 (D-E1): fechada → CAPABILITY_NOT_ENABLED (42501)

  -- Fronteira de autorização: a mesma da 5316, antes de qualquer tabela do fichário.
  v_role := public.collection_share_role(p_collection_id);
  if v_role is null or v_role not in ('OWNER', 'VIEWER') then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Uma única consulta de dados (C1): núcleo mascarado + camada autorizada, no mesmo instantâneo.
  return query
  with lay as (
    -- Camada autorizada: X é a PROPRIETÁRIA do fichário e é Pokédex. Convidada → nenhuma linha.
    select l.id as layout_id,
           coalesce((select st.references_visible
                     from public.collection_layout_species_reference_setting st
                     where st.layout_id = l.id), true) as visible
    from public.collection_layout l
    join public.collection c on c.id = l.collection_id
    where l.collection_id = p_collection_id
      and c.mode = 'REFERENCE_BASED'
      and c.completion_policy = 'REFERENCE_POSITION'
      and exists (select 1
                  from public.collection_reference cr
                  join public.collection_pokedex_reference cpr on cpr.collection_reference_id = cr.id
                  where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')
  ),
  m as (
    select mp.page_number, mp.row_index, mp.column_index, mp.pocket_state, mp.card_name,
           mp.collector_number, mp.collector_total, mp.card_set_code, mp.variant_label,
           mp.language_code, mp.image_path
    from public.collection_binder_masked_pages(p_collection_id, p_first_page, p_page_count) mp
  )
  select m.page_number, m.row_index, m.column_index, m.pocket_state, m.card_name,
         m.collector_number, m.collector_total, m.card_set_code, m.variant_label,
         m.language_code, m.image_path,
         sref.national_number, sref.species_name, sref.artwork_path,
         (select lay.visible from lay)
  from m
  left join lateral (
    -- Só o estado MASCARADO decide (C3): EMPTY. Nenhuma leitura de exemplar, imagem, região ou reserva.
    select pp.position_number as national_number,
           sp.canonical_name::text as species_name,
           aw.display_storage_path::text as artwork_path
    from lay
    join public.collection_layout_page pg
      on pg.layout_id = lay.layout_id and pg.page_number = m.page_number
    join public.collection_layout_slot s
      on s.page_id = pg.id and s.row_index = m.row_index and s.column_index = m.column_index
    join public.collection_layout_slot_species_reference r
      on r.slot_id = s.id and r.layout_id = lay.layout_id and r.collection_id = p_collection_id
    join public.pokedex_position pp on pp.id = r.pokedex_position_id
    join public.pokemon_species sp on sp.id = pp.species_id
    left join public.pokemon_species_artwork aw
      on aw.pokemon_species_id = sp.id and aw.status = 'IMPORTED' and aw.display_storage_path is not null
    where lay.visible
      and m.pocket_state = 'EMPTY'
  ) sref on true
  order by m.page_number, m.row_index, m.column_index;
end;
$fn$;

comment on function public.get_shared_collection_binder_pages_with_species(uuid, integer, integer) is
  'V1-13 E3-6/S3 (5393, D-E3-9): páginas mascaradas do fichário do participante (as 11 colunas e as linhas da 5316, núcleo 5315) + número nacional, nome e arte da espécie só em bolso EMPTY mascarado da camada de X (proprietária Pokédex, exibição ligada) e references_visible (NULL fora da camada). OWNER/VIEWER pela 5302 (EDITOR = VIEWER); sem acesso → COLLECTION_NOT_FOUND; barreira fechada → CAPABILITY_NOT_ENABLED. STABLE: um instantâneo por chamada. Sem ids.';

revoke all on function public.get_shared_collection_binder_pages_with_species(uuid, integer, integer) from public, anon;
grant execute on function public.get_shared_collection_binder_pages_with_species(uuid, integer, integer) to authenticated;

do $post$
declare
  v_oid oid := to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)');
  v_core oid := to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)');
begin
  if v_oid is null
     or (select p.prosecdef from pg_catalog.pg_proc p where p.oid = v_oid) is not true
     or (select p.proconfig from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from array['search_path=""']
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from 's'
     or (select p.proowner from pg_catalog.pg_proc p where p.oid = v_oid) is distinct from (select p.proowner from pg_catalog.pg_proc p where p.oid = v_core)
     or pg_catalog.has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
     or pg_catalog.has_function_privilege('anon', v_oid, 'EXECUTE') is not false
     or exists (select 1 from pg_catalog.pg_proc p cross join lateral pg_catalog.aclexplode(p.proacl) a
                where p.oid = v_oid and a.grantee = 0 and a.privilege_type = 'EXECUTE')
     or pg_catalog.pg_get_function_result(v_oid) is distinct from
        'TABLE(page_number integer, row_index integer, column_index integer, pocket_state text, card_name text, collector_number text, collector_total integer, card_set_code text, variant_label text, language_code text, image_path text, species_national_number integer, species_name text, species_artwork_path text, references_visible boolean)' then
    raise exception 'POSTCHECK 5393: função fora do estado esperado';
  end if;
  -- As leituras da V1-12 não mudaram.
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_core) is distinct from 'ce559a495a49571a6598c83bc3d59202'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)')) is distinct from '79f893c45a08909e0a61d661952ab750'
     or (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)')) is distinct from '0da2d28209cd85b6bdbf6c20ae47efd6' then
    raise exception 'POSTCHECK 5393: 5315/5316/5318 alteradas';
  end if;
end;
$post$;

commit;
