/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5885 - HARNESS da 5357 (get_my_binder_value_groups) — AMBIENTE LOCAL
              ISOLADO, dois titulares SINTÉTICOS, termina em ROLLBACK
Versão......: 0.2 (B2 STATIC AUDIT CORRECTION-01)
Status......: PROPOSTO — NÃO EXECUTADO. Proibido no LIVE (gate E0 exige a
              sentinela local q5885_local_sandbox). Execução depende de
              autorização própria.
Data........: 2026-11-08

Execução: psql -v ON_ERROR_STOP=1 -f 5885_... a partir desta pasta (o \ir inclui o
arquivo 5357_..._PROPOSAL.sql; registrar o md5 do arquivo antes da execução).

Proteção contra execução acidental fora do ambiente isolado
  O gate real é a SENTINELA: o schema vazio q5885_local_sandbox, criado só pelo
  protocolo de preparação do ambiente local e nunca no LIVE. Sem ele, o E0 aborta
  antes de qualquer escrita. O endereço do servidor é só defesa adicional (aceita
  socket, loopback e redes privadas, porque um contêiner Docker responde com o IP
  da rede interna) — sozinho ele NÃO distingue local de LIVE.

Pré-requisitos (verificados pelo E0 — qualquer falta aborta com Q5885_E0_*)
  - sentinela q5885_local_sandbox;
  - esquema public com as tabelas, constraints e gatilhos do fichário até a 5256
    (inclui 5248), collection_membership (5300), storage_container_kind com BINDER
    e o catálogo mínimo (game, expansion, card_set, card, card_variant, language,
    card_asset, card_asset_type, card_variant_type, perfis de variante);
  - get_my_collection_binder (5252) e get_my_inventory_items (5261) instaladas;
  - esquema auth com auth.users e auth.uid() no padrão Supabase (lê
    request.jwt.claim.sub / request.jwt.claims); papéis anon e authenticated sem
    BYPASSRLS, com USAGE em public; o papel que cria a 5357 (dono = definer)
    com BYPASSRLS ou superusuário, como o postgres do Supabase;
  - pelo menos 2 Card Variants do mesmo Game e 2 idiomas.
  Os dois titulares (A e B) e todos os dados do fichário são SINTÉTICOS, criados e
  desfeitos nesta transação. Nenhum dado real é lido além do catálogo.

Transação: REPEATABLE READ (um único retrato para todas as leituras, com as
escritas da própria transação visíveis) e SET CONSTRAINTS ALL IMMEDIATE (as
constraints e os gatilhos DEFERRABLE INITIALLY DEFERRED — ex.: 5057/5059 e os
UNIQUE adiados de página/ocupação — passam a ser checados a cada statement; sem
isso, o ROLLBACK esconderia um fixture que o COMMIT recusaria).

Asserções (falha aborta com Q5885_*; sem correção improvisada)
  E0 sentinela, objetos, auth.uid() Supabase, papéis, definer, colunas NOT NULL
     sem default dentro do conjunto que este harness preenche (senão STOP)
  F1 fidelidade da sessão: auth.uid() = A/B com o claim; NULL sem sub
  S1 SECURITY DEFINER, search_path '', STABLE, retorno com as 14 colunas
  S2 PUBLIC e anon sem EXECUTE; authenticated com EXECUTE; chamada real como anon →
     42501; EXECUTE de service_role registrado (NOTICE), sem asserção
  S3 authenticated sem sub → 28000
  S4 coleção nula, limite 0/201, offset −1/10001 → 22023; uuid malformado → 22P02
  S5 B com a coleção proprietária de A, com a convidada de A e com uuid inexistente →
     P0002, MESMA mensagem; B com coleção própria sem fichário → 0 linhas
  S6 B como VIEWER ACTIVE (collection_membership) da proprietária de A → P0002
  S7 A pela coleção CONVIDADA → mesmo resultado que pela proprietária
  I1 perímetro: entram exemplar da proprietária, da convidada, de coleção NÃO
     participante, SEM coleção e de coleção ARQUIVADA; ficam fora o exemplar guardado
     no fichário sem bolso e o de outro local; bolso vazio, reservado, com imagem e
     mesclado não contam
  I2 agrupamento variante + idioma
  I3 Σ copies_count = total_copies = filled_count (5252) = 5; linhas = total_count
  I4 páginas de 1 somadas = lista completa, na ordem; totais iguais; além do fim → 0
  I5 desalocar exemplar posicionado NÃO o tira do bolso nem da leitura
  I6 referência do Acervo = 5261 SEM filtro (p_collection_id NULL e
     p_without_collection FALSE), que inclui exemplares sem coleção: prova
     explícita (acervo de A = 7 exemplares em 4 grupos, com P4/P6/P7 sem coleção;
     grupo (v2,l2) do acervo = 1, só o P4 sem coleção) e depois subconjunto
  I7 isolamento: o exemplar (v2,l2) de B não entra na contagem de A
  Pós-ROLLBACK: função ausente; contagens de auth.users, inventory, collection e
  storage_container iguais às de antes; sessão sem transação aberta
================================================================
*/

-- ---------------------------------------------------------------------------
-- E0 — ambiente (ANTES de qualquer escrita)
-- ---------------------------------------------------------------------------
do $e0$
declare v_addr inet := inet_server_addr(); v_missing text; v_def text;
begin
  if to_regnamespace('q5885_local_sandbox') is null then
    raise exception 'Q5885_E0_NO_SANDBOX: sentinela q5885_local_sandbox ausente — harness só roda no ambiente local preparado';
  end if;
  if v_addr is not null
     and not (v_addr <<= '127.0.0.0/8'::inet or v_addr = '::1'::inet or v_addr <<= '10.0.0.0/8'::inet
              or v_addr <<= '172.16.0.0/12'::inet or v_addr <<= '192.168.0.0/16'::inet) then
    raise exception 'Q5885_E0_PUBLIC_ADDRESS: servidor % em endereço público', v_addr;
  end if;
  select string_agg(t, ', ') into v_missing from unnest(array[
    'public.collection','public.collection_layout','public.collection_layout_page',
    'public.collection_layout_slot','public.collection_layout_slot_assignment',
    'public.collection_layout_guest','public.collection_layout_slot_expected_content',
    'public.collection_layout_slot_image','public.collection_layout_region',
    'public.collection_allocation','public.physical_card','public.inventory',
    'public.storage_container','public.storage_container_kind','public.collection_membership',
    'public.game','public.expansion','public.card_set','public.card','public.card_variant',
    'public.language','public.card_asset','public.card_asset_type','public.card_variant_type',
    'public.card_printing_profile','public.card_edition_context_profile','auth.users']) t
  where to_regclass(t) is null;
  if v_missing is not null then raise exception 'Q5885_E0_MISSING_TABLES: %', v_missing; end if;
  if to_regprocedure('auth.uid()') is null then raise exception 'Q5885_E0_NO_AUTH_UID'; end if;
  v_def := pg_get_functiondef('auth.uid()'::regprocedure);
  if v_def !~ 'request\.jwt\.claim' then
    raise exception 'Q5885_E0_AUTH_UID_NOT_SUPABASE: auth.uid() não lê request.jwt.claim(s)';
  end if;
  if to_regprocedure('public.get_my_collection_binder(uuid)') is null
     or to_regprocedure('public.get_my_inventory_items(text,text,text,uuid,boolean,text,integer,integer,uuid,boolean)') is null then
    raise exception 'Q5885_E0_MISSING_READS: 5252/5261 ausentes';
  end if;
  if to_regprocedure('public.get_my_binder_value_groups(uuid,integer,integer)') is not null then
    raise exception 'Q5885_E0_ALREADY_EXISTS: 5357 já existe neste banco';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema='public' and table_name='collection_layout_slot_assignment' and column_name='physical_card_id' and is_nullable='NO') then
    raise exception 'Q5885_E0_PRE_5248: ocupação ainda não referencia physical_card_id';
  end if;
  if not exists (select 1 from public.storage_container_kind where code = 'BINDER') then
    raise exception 'Q5885_E0_NO_BINDER_KIND: storage_container_kind sem BINDER (5212/5213)';
  end if;
  if (select count(*) from pg_roles where rolname in ('anon','authenticated') and not rolbypassrls and not rolsuper) <> 2
     or not has_schema_privilege('anon', 'public', 'usage')
     or not has_schema_privilege('authenticated', 'public', 'usage') then
    raise exception 'Q5885_E0_ROLES';
  end if;
  if not (select rolsuper or rolbypassrls from pg_roles where rolname = current_user) then
    raise exception 'Q5885_E0_DEFINER: % (dono da 5357) sem BYPASSRLS — difere do postgres do Supabase', current_user;
  end if;
  -- Colunas obrigatórias sem default fora do conjunto que o fixture preenche → STOP.
  select string_agg(table_name || '.' || column_name, ', ') into v_missing
  from information_schema.columns
  where table_schema = 'public'
    and table_name in ('inventory','storage_container','collection','collection_layout','collection_layout_page',
                       'collection_layout_slot','collection_layout_slot_assignment','collection_layout_guest',
                       'collection_allocation','physical_card','collection_layout_slot_expected_content',
                       'collection_layout_slot_image','collection_layout_region','collection_membership')
    and is_nullable = 'NO' and column_default is null
    and (table_name || '.' || column_name) not in (
      'inventory.owner_user_id','storage_container.inventory_id','storage_container.name',
      'collection.owner_user_id','collection.game_id','collection.default_storage_container_id','collection.name',
      'collection_layout.collection_id','collection_layout.grid_rows','collection_layout.grid_columns','collection_layout.storage_container_id',
      'collection_layout_page.layout_id','collection_layout_page.page_number',
      'collection_layout_slot.page_id','collection_layout_slot.row_index','collection_layout_slot.column_index',
      'collection_layout_slot_assignment.slot_id','collection_layout_slot_assignment.physical_card_id',
      'collection_layout_guest.collection_id','collection_layout_guest.layout_id',
      'collection_allocation.physical_card_id','collection_allocation.collection_id',
      'physical_card.card_variant_id','physical_card.language_id',
      'collection_layout_slot_expected_content.slot_id','collection_layout_slot_expected_content.card_id',
      'collection_layout_slot_image.slot_id','collection_layout_slot_image.owner_user_id','collection_layout_slot_image.storage_path',
      'collection_layout_region.page_id','collection_layout_region.top_row','collection_layout_region.left_column',
      'collection_layout_region.height','collection_layout_region.width',
      'collection_membership.collection_id','collection_membership.user_id','collection_membership.invited_by');
  if v_missing is not null then raise exception 'Q5885_E0_FIXTURE_REVIEW: colunas obrigatórias não previstas: %', v_missing; end if;
end;
$e0$;

-- Contagens de referência para o pós-ROLLBACK (somente leitura).
select (select count(*) from auth.users)               as q5885_users_before,
       (select count(*) from public.inventory)         as q5885_inv_before,
       (select count(*) from public.collection)        as q5885_col_before,
       (select count(*) from public.storage_container) as q5885_sc_before
\gset

begin isolation level repeatable read;
set constraints all immediate;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- Fixture sintético (desfeito no ROLLBACK). Escolhas determinísticas do catálogo:
-- v1 = menor card_variant.id; Game = o de v1 (card → card_set → expansion);
-- v2 = menor variante de OUTRA carta do mesmo Game (exigência do gatilho 5042);
-- l1, l2 = os dois primeiros idiomas por language_order, id.
-- ---------------------------------------------------------------------------
create temp table _q5885 on commit drop as
with v1 as (
  select cv.id, cv.card_id, ex.game_id
  from public.card_variant cv
  join public.card c      on c.id = cv.card_id
  join public.card_set cs on cs.id = c.card_set_id
  join public.expansion ex on ex.id = cs.expansion_id
  order by cv.id limit 1
)
select gen_random_uuid() as user_a, gen_random_uuid() as user_b,
       (select game_id from v1) as game_id,
       array[(select id from v1),
             (select cv.id
              from public.card_variant cv
              join public.card c      on c.id = cv.card_id
              join public.card_set cs on cs.id = c.card_set_id
              join public.expansion ex on ex.id = cs.expansion_id
              where ex.game_id = (select game_id from v1) and cv.card_id <> (select card_id from v1)
              order by cv.id limit 1)] as variants,
       (select array_agg(id order by language_order, id) from (select id, language_order from public.language order by language_order, id limit 2) l) as langs;

do $fx$
declare
  x record; a uuid; b uuid; v1 uuid; v2 uuid; l1 uuid; l2 uuid;
  inv_a uuid; inv_b uuid; sc_bind uuid; sc_other uuid; sc_b uuid;
  c_owner uuid; c_guest uuid; c_other uuid; c_arch uuid; c_b uuid;
  lay uuid; pg uuid; s uuid[]; pc uuid[] := array[]::uuid[]; i int;
begin
  select * into x from _q5885;
  a := x.user_a; b := x.user_b; v1 := x.variants[1]; v2 := x.variants[2]; l1 := x.langs[1]; l2 := x.langs[2];
  if v1 is null or v2 is null or l1 is null or l2 is null or x.game_id is null then raise exception 'Q5885_E0_CATALOG'; end if;

  insert into auth.users (id) values (a), (b);
  insert into public.inventory (owner_user_id) values (a) returning id into inv_a;
  insert into public.inventory (owner_user_id) values (b) returning id into inv_b;
  insert into public.storage_container (inventory_id, name, kind_code) values (inv_a, 'Q5885 fichário', 'BINDER') returning id into sc_bind;
  insert into public.storage_container (inventory_id, name) values (inv_a, 'Q5885 caixa') returning id into sc_other;
  insert into public.storage_container (inventory_id, name) values (inv_b, 'Q5885 B') returning id into sc_b;

  insert into public.collection (owner_user_id, game_id, default_storage_container_id, name) values (a, x.game_id, sc_bind, 'Q5885 proprietária') returning id into c_owner;
  insert into public.collection (owner_user_id, game_id, default_storage_container_id, name) values (a, x.game_id, sc_other, 'Q5885 convidada') returning id into c_guest;
  insert into public.collection (owner_user_id, game_id, default_storage_container_id, name) values (a, x.game_id, sc_other, 'Q5885 não participante') returning id into c_other;
  insert into public.collection (owner_user_id, game_id, default_storage_container_id, name) values (a, x.game_id, sc_other, 'Q5885 arquivada') returning id into c_arch;
  insert into public.collection (owner_user_id, game_id, default_storage_container_id, name) values (b, x.game_id, sc_b, 'Q5885 B sem fichário') returning id into c_b;

  insert into public.collection_layout (collection_id, grid_rows, grid_columns, storage_container_id) values (c_owner, 3, 3, sc_bind) returning id into lay;
  insert into public.collection_layout_guest (collection_id, layout_id) values (c_guest, lay);
  insert into public.collection_layout_page (layout_id, page_number) values (lay, 1) returning id into pg;
  for i in 1..9 loop
    insert into public.collection_layout_slot (page_id, row_index, column_index) values (pg, ((i - 1) / 3) + 1, ((i - 1) % 3) + 1) returning id into s[i];
  end loop;

  -- Exemplares de A, um por statement: P1..P5 no fichário e posicionados;
  -- P6 no fichário SEM bolso; P7 em outro local.
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v1, l1, inv_a, sc_bind) returning id into pc[1];
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v1, l1, inv_a, sc_bind) returning id into pc[2];
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v2, l1, inv_a, sc_bind) returning id into pc[3];
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v2, l2, inv_a, sc_bind) returning id into pc[4];
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v1, l2, inv_a, sc_bind) returning id into pc[5];
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v2, l1, inv_a, sc_bind) returning id into pc[6];
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v1, l1, inv_a, sc_other) returning id into pc[7];

  -- Alocações: P1 proprietária, P2 convidada, P3 NÃO participante, P5 arquivada (arquiva depois).
  -- P4, P6 e P7 ficam SEM coleção.
  insert into public.collection_allocation (physical_card_id, collection_id) values (pc[1], c_owner), (pc[2], c_guest), (pc[3], c_other), (pc[5], c_arch);

  -- Bolsos 1..5 ocupados; 6 reservado; 7 imagem; 8–9 mesclados (região, vazios).
  for i in 1..5 loop
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id) values (s[i], pc[i]);
  end loop;
  insert into public.collection_layout_slot_expected_content (slot_id, card_id, card_variant_id)
  select s[6], cv.card_id, cv.id from public.card_variant cv where cv.id = v1;
  insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
  values (s[7], a, a::text || '/' || gen_random_uuid()::text || '/' || gen_random_uuid()::text || '.webp');
  insert into public.collection_layout_region (page_id, top_row, left_column, height, width) values (pg, 3, 2, 1, 2);

  -- Arquiva depois de alocar (a alocação permanece).
  update public.collection set lifecycle_status = 'ARCHIVED', archived_at = now() where id = c_arch;

  -- B: um exemplar próprio (v2, l2) igual a um de A, e VIEWER ACTIVE da proprietária de A.
  insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id) values (v2, l2, inv_b, sc_b);
  insert into public.collection_membership (collection_id, user_id, invited_by, status, responded_at) values (c_owner, b, a, 'ACTIVE', now());

  -- Conferência do fixture (como dono da sessão, antes de qualquer papel).
  if (select count(*) from public.collection_layout_slot_assignment where slot_id = any(s)) <> 5
     or (select count(*) from public.physical_card where inventory_id = inv_a) <> 7
     or (select count(*) from public.physical_card p where p.inventory_id = inv_a
           and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = p.id)) <> 3
     or not exists (select 1 from public.collection_membership m where m.collection_id = c_owner and m.user_id = b and m.status = 'ACTIVE') then
    raise exception 'Q5885_FX_STATE';
  end if;

  perform set_config('q5885.a', a::text, true);
  perform set_config('q5885.b', b::text, true);
  perform set_config('q5885.c_owner', c_owner::text, true);
  perform set_config('q5885.c_guest', c_guest::text, true);
  perform set_config('q5885.c_b', c_b::text, true);
  perform set_config('q5885.v1', v1::text, true);
  perform set_config('q5885.v2', v2::text, true);
  perform set_config('q5885.pc3', pc[3]::text, true);
  perform set_config('q5885.l1code', (select code from public.language where id = l1)::text, true);
  perform set_config('q5885.l2code', (select code from public.language where id = l2)::text, true);
end;
$fx$;

-- ---------------------------------------------------------------------------
-- Criação da 5357 (inclui o arquivo da proposta; md5 registrado antes)
-- ---------------------------------------------------------------------------
\ir 5357_create_get_my_binder_value_groups_PROPOSAL.sql

-- S1/S2 — configuração e privilégios
do $s1$
declare r record;
begin
  select p.prosecdef, p.provolatile, p.proconfig, pg_get_function_result(p.oid) as res into r
  from pg_proc p where p.oid = 'public.get_my_binder_value_groups(uuid,integer,integer)'::regprocedure;
  if not r.prosecdef or r.provolatile <> 's' or r.proconfig is distinct from array['search_path=""'] then
    raise exception 'Q5885_S1_CONFIG: %', r;
  end if;
  if r.res <> 'TABLE(card_variant_id uuid, language_code text, language_name text, card_name text, collector_number text, collector_total integer, card_set_code text, card_set_name text, is_default_variant boolean, variant_label text, image_path text, copies_count integer, total_count bigint, total_copies bigint)' then
    raise exception 'Q5885_S1_RESULT: %', r.res;
  end if;
  if has_function_privilege('anon', 'public.get_my_binder_value_groups(uuid,integer,integer)', 'execute')
     or not has_function_privilege('authenticated', 'public.get_my_binder_value_groups(uuid,integer,integer)', 'execute')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) e
                where p.oid = 'public.get_my_binder_value_groups(uuid,integer,integer)'::regprocedure and e.grantee = 0) then
    raise exception 'Q5885_S2_PRIVILEGES';
  end if;
  raise notice 'Q5885_S2_SERVICE_ROLE_EXECUTE=%',
    case when exists (select 1 from pg_roles where rolname = 'service_role')
         then has_function_privilege('service_role', 'public.get_my_binder_value_groups(uuid,integer,integer)', 'execute')::text
         else 'papel ausente' end;
end;
$s1$;

-- S2 — chamada real como anon → 42501
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
set local role anon;
do $s2$
begin
  perform * from public.get_my_binder_value_groups(current_setting('q5885.c_owner')::uuid, 200, 0);
  raise exception 'Q5885_S2_ANON_EXECUTED';
exception when insufficient_privilege then null;
end;
$s2$;
reset role;

-- F1/S3 — authenticated sem sub: auth.uid() nulo → 28000
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
set local role authenticated;
do $s3$
begin
  if auth.uid() is not null then raise exception 'Q5885_F1_UID_NOT_NULL'; end if;
  perform * from public.get_my_binder_value_groups(current_setting('q5885.c_owner')::uuid, 200, 0);
  raise exception 'Q5885_S3_NO_SESSION_EXECUTED';
exception when sqlstate '28000' then null;
end;
$s3$;
reset role;

-- Como A: F1, S4, S7, I1–I4, I6
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', json_build_object('sub', current_setting('q5885.a'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $a$
declare
  c_owner uuid := current_setting('q5885.c_owner')::uuid;
  c_guest uuid := current_setting('q5885.c_guest')::uuid;
  v1 uuid := current_setting('q5885.v1')::uuid; v2 uuid := current_setting('q5885.v2')::uuid;
  code1 text := current_setting('q5885.l1code'); code2 text := current_setting('q5885.l2code');
  full_list text; guest_list text; paged text := ''; n_rows int; sum_copies int; t_count bigint; t_copies bigint;
  filled int; inv_copies bigint; inv_groups bigint; inv_v2l2 int; k int; r record; bad int;
begin
  if auth.uid() is distinct from current_setting('q5885.a')::uuid then raise exception 'Q5885_F1_UID_A'; end if;

  -- S4 — entradas inválidas
  begin perform * from public.get_my_binder_value_groups(null, 200, 0); raise exception 'Q5885_S4_NULL'; exception when sqlstate '22023' then null; end;
  begin perform * from public.get_my_binder_value_groups(c_owner, 0, 0); raise exception 'Q5885_S4_LIMIT0'; exception when sqlstate '22023' then null; end;
  begin perform * from public.get_my_binder_value_groups(c_owner, 201, 0); raise exception 'Q5885_S4_LIMIT201'; exception when sqlstate '22023' then null; end;
  begin perform * from public.get_my_binder_value_groups(c_owner, 10, -1); raise exception 'Q5885_S4_OFFSETNEG'; exception when sqlstate '22023' then null; end;
  begin perform * from public.get_my_binder_value_groups(c_owner, 10, 10001); raise exception 'Q5885_S4_OFFSETBIG'; exception when sqlstate '22023' then null; end;
  begin perform * from public.get_my_binder_value_groups('not-a-uuid'::uuid, 10, 0); raise exception 'Q5885_S4_MALFORMED'; exception when sqlstate '22P02' then null; end;

  -- Resultado completo pela proprietária e pela convidada (S7)
  select string_agg(g.card_variant_id::text || '|' || g.language_code || '|' || g.copies_count, ';' order by ord),
         count(*), sum(g.copies_count), max(g.total_count), max(g.total_copies)
    into full_list, n_rows, sum_copies, t_count, t_copies
  from public.get_my_binder_value_groups(c_owner, 200, 0) with ordinality g(card_variant_id, language_code, language_name, card_name, collector_number, collector_total, card_set_code, card_set_name, is_default_variant, variant_label, image_path, copies_count, total_count, total_copies, ord);
  select string_agg(g.card_variant_id::text || '|' || g.language_code || '|' || g.copies_count, ';' order by ord) into guest_list
  from public.get_my_binder_value_groups(c_guest, 200, 0) with ordinality g(card_variant_id, language_code, language_name, card_name, collector_number, collector_total, card_set_code, card_set_name, is_default_variant, variant_label, image_path, copies_count, total_count, total_copies, ord);
  if guest_list is distinct from full_list then raise exception 'Q5885_S7_GUEST_DIFFERS: % <> %', guest_list, full_list; end if;

  -- I1/I2/I7 — (v1,l1)=2 [proprietária + convidada], (v2,l1)=1 [não participante],
  --            (v2,l2)=1 [sem coleção; o (v2,l2) de B não entra], (v1,l2)=1 [arquivada];
  --            P6 (fichário sem bolso) e P7 (outro local) fora.
  for r in select g.card_variant_id, g.language_code, g.copies_count from public.get_my_binder_value_groups(c_owner, 200, 0) g loop
    if not ((r.card_variant_id = v1 and r.language_code = code1 and r.copies_count = 2)
         or (r.card_variant_id = v2 and r.language_code = code1 and r.copies_count = 1)
         or (r.card_variant_id = v2 and r.language_code = code2 and r.copies_count = 1)
         or (r.card_variant_id = v1 and r.language_code = code2 and r.copies_count = 1)) then
      raise exception 'Q5885_I1_UNEXPECTED_GROUP: %', r;
    end if;
  end loop;
  if n_rows <> 4 or sum_copies <> 5 then raise exception 'Q5885_I1_PERIMETER: grupos=% exemplares=% (esperado 4/5)', n_rows, sum_copies; end if;

  -- I3 — totais e filled_count (5252), mesmo retrato (REPEATABLE READ)
  select b.filled_count into filled from public.get_my_collection_binder(c_owner) b;
  if filled <> 5 or t_copies <> sum_copies or t_copies <> filled or t_count <> n_rows then
    raise exception 'Q5885_I3_TOTALS: soma=% total_copies=% filled=% linhas=% total_count=%', sum_copies, t_copies, filled, n_rows, t_count;
  end if;

  -- I4 — paginação de 1 em 1 = lista completa, sem repetição; além do fim → 0
  for k in 0..n_rows - 1 loop
    select paged || case when paged = '' then '' else ';' end || g.card_variant_id::text || '|' || g.language_code || '|' || g.copies_count
      into paged from public.get_my_binder_value_groups(c_owner, 1, k) g;
    if (select count(distinct (g.total_count, g.total_copies)) from public.get_my_binder_value_groups(c_owner, 1, k) g) <> 1 then
      raise exception 'Q5885_I4_PAGE_TOTALS: página %', k;
    end if;
  end loop;
  if paged is distinct from full_list then raise exception 'Q5885_I4_PAGING: % <> %', paged, full_list; end if;
  if exists (select 1 from public.get_my_binder_value_groups(c_owner, 10, n_rows)) then raise exception 'Q5885_I4_PAST_END'; end if;

  -- I6 — referência do Acervo = 5261 SEM filtro de coleção (inclui exemplares sem coleção).
  -- Prova da referência: 7 exemplares de A em 4 grupos (P4, P6 e P7 sem coleção);
  -- o grupo (v2,l2) do acervo tem 1 exemplar, que é o P4 sem coleção.
  select max(i.total_copies), max(i.total_count),
         max(i.copies_count) filter (where i.card_variant_id = v2 and i.language_code = code2)
    into inv_copies, inv_groups, inv_v2l2
  from public.get_my_inventory_items(null, null, null, null, false, 'SET_NUMBER', 96, 0, null, false) i;
  if inv_copies <> 7 or inv_groups <> 4 or inv_v2l2 is distinct from 1 then
    raise exception 'Q5885_I6_REFERENCE: acervo exemplares=% grupos=% (v2,l2)=% (esperado 7/4/1)', inv_copies, inv_groups, inv_v2l2;
  end if;
  if t_copies > inv_copies then raise exception 'Q5885_I6_TOTAL: fichário % > acervo %', t_copies, inv_copies; end if;
  select count(*) into bad
  from public.get_my_binder_value_groups(c_owner, 200, 0) g
  left join public.get_my_inventory_items(null, null, null, null, false, 'SET_NUMBER', 96, 0, null, false) i
    on i.card_variant_id = g.card_variant_id and i.language_code = g.language_code
  where i.card_variant_id is null or i.copies_count < g.copies_count;
  if bad > 0 then raise exception 'Q5885_I6_SUBSET: % grupos fora do acervo ou com mais cópias', bad; end if;

  perform set_config('q5885.full_list', full_list, true);
end;
$a$;
reset role;

-- I5 — desalocar o exemplar posicionado (não participante) NÃO o tira do bolso nem da leitura
delete from public.collection_allocation where physical_card_id = current_setting('q5885.pc3')::uuid;
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', json_build_object('sub', current_setting('q5885.a'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $i5$
declare after_list text;
begin
  select string_agg(g.card_variant_id::text || '|' || g.language_code || '|' || g.copies_count, ';' order by ord) into after_list
  from public.get_my_binder_value_groups(current_setting('q5885.c_owner')::uuid, 200, 0) with ordinality g(card_variant_id, language_code, language_name, card_name, collector_number, collector_total, card_set_code, card_set_name, is_default_variant, variant_label, image_path, copies_count, total_count, total_copies, ord);
  if after_list is distinct from current_setting('q5885.full_list') then raise exception 'Q5885_I5_DEALLOCATE_CHANGED: %', after_list; end if;
end;
$i5$;
reset role;

-- Como B: F1, S5, S6
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', json_build_object('sub', current_setting('q5885.b'), 'role', 'authenticated')::text, true);
set local role authenticated;
do $b$
declare m_owner text; m_guest text; m_none text;
begin
  if auth.uid() is distinct from current_setting('q5885.b')::uuid then raise exception 'Q5885_F1_UID_B'; end if;
  -- S5/S6: B é VIEWER ACTIVE da proprietária de A (fixture) e mesmo assim recebe P0002.
  begin perform * from public.get_my_binder_value_groups(current_setting('q5885.c_owner')::uuid, 200, 0); raise exception 'Q5885_S5_OWNER_LEAK';
  exception when sqlstate 'P0002' then m_owner := sqlerrm; end;
  begin perform * from public.get_my_binder_value_groups(current_setting('q5885.c_guest')::uuid, 200, 0); raise exception 'Q5885_S5_GUEST_LEAK';
  exception when sqlstate 'P0002' then m_guest := sqlerrm; end;
  begin perform * from public.get_my_binder_value_groups(gen_random_uuid(), 200, 0); raise exception 'Q5885_S5_INEXISTENT';
  exception when sqlstate 'P0002' then m_none := sqlerrm; end;
  if m_owner <> m_none or m_guest <> m_none then raise exception 'Q5885_S5_ENUMERATION: % / % / %', m_owner, m_guest, m_none; end if;
  if exists (select 1 from public.get_my_binder_value_groups(current_setting('q5885.c_b')::uuid, 200, 0)) then
    raise exception 'Q5885_S5_OWN_WITHOUT_BINDER_NOT_EMPTY';
  end if;
end;
$b$;
reset role;

rollback;

-- ---------------------------------------------------------------------------
-- Pós-ROLLBACK (somente leitura)
-- ---------------------------------------------------------------------------
select
  to_regprocedure('public.get_my_binder_value_groups(uuid,integer,integer)') is null as funcao_ausente,
  (select count(*) from auth.users)               = :q5885_users_before as usuarios_iguais,
  (select count(*) from public.inventory)         = :q5885_inv_before   as inventarios_iguais,
  (select count(*) from public.collection)        = :q5885_col_before   as colecoes_iguais,
  (select count(*) from public.storage_container) = :q5885_sc_before    as locais_iguais,
  pg_current_xact_id_if_assigned() is null                               as sem_transacao_aberta;
