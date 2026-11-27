/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5897 - Harness V1-13 · E3-6 / S3 (5393): estrutura, matriz de
              papéis, regressão 5316/5318, não inferência (A, B, B′, C, D, E)
              entre estados e entre consultas, controles positivos, barreira,
              anônimo/público, reversão — SESSÃO ÚNICA
Versão......: 1.0 (2026-11-26, `E3-6 / S3-5393 — SQL & HARNESS PREPARATION-01`)
Status......: PROPOSTA — NÃO EXECUTADA. Executar SOMENTE em PostgreSQL LOCAL
              descartável com o esquema da V1-13 (E1 completa) + 5393, dentro
              de uma transação explícita terminada em ROLLBACK (psql), depois
              de auditoria. Nunca no LIVE. Sem BEGIN/COMMIT próprios.
              Concorrência (duas sessões) e desempenho ficam em arquivos
              próprios: 5897_C_concurrency_LOCAL_TWO_SESSIONS.sql e
              5897_P_performance_LOCAL.sql.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-26

Uso (psql, banco local):
  begin;
  \i 5897_validate_shared_binder_species_HARNESS.sql
  select * from pg_temp.wh_5897_validate();
  rollback;
  -- GATE esperado: 24/24 PASS (4 estrutura + F.2 + 10 matriz + 1 regressão + 1 entre estados + 6 entre consultas/controles + 1 reversão).

Usuários efêmeros: U titular · E EDITOR de X · V VIEWER de X · W VIEWER de Y ·
D EDITOR de X depois rebaixado · R participante removido · P convite pendente ·
S estranho (sem participação).
Coleções de U: X Pokédex (geração da primeira espécie nacional), PROPRIETÁRIA do
fichário F (3 × 3), camada de referências aplicada pelo plano canônico (5258);
Y livre, CONVIDADA de F; Z livre com fichário próprio (outra modalidade).
Bolso-alvo T = (página 1, linha 1, coluna 1); vizinho N = (1, 1, 2) (usado pela
mesclagem D); bolso de fora O = (1, 3, 3).

Limitações declaradas:
  L1 SET LOCAL ROLE + request.jwt.claims prova o banco, não o JWT do PostgREST.
  L2 Concorrência real (duas sessões): só no 5897_C. Aqui as mudanças "entre
     consultas" são comandos sucessivos da MESMA transação — cada chamada é um
     comando novo e enxerga as mudanças anteriores (o que basta para C3).
  L3 Desempenho: só no 5897_P; nada aqui mede tempo (equivalência ≠ desempenho).
  L4 Conteúdo oculto (imagem, mesclagem, reserva alheia) é gravado direto como
     fixture privilegiada; os gatilhos de integridade continuam valendo.
================================================================
*/

create or replace function pg_temp.wh_5897_as(p_user uuid)
returns void language plpgsql volatile as $as$
begin
  execute 'reset role';
  if p_user is null then
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
  else
    perform set_config('request.jwt.claim.sub', p_user::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  end if;
end;
$as$;

create or replace function pg_temp.wh_5897_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlstate || ':' || sqlerrm;
end;
$try$;

-- Resposta completa da 5393 (janela 1..2), todas as colunas, na ordem: jsonb e hash.
create or replace function pg_temp.wh_5897_j(p_coll uuid)
returns jsonb language sql volatile as $j$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.page_number, x.row_index, x.column_index), '[]'::jsonb)
  from public.get_shared_collection_binder_pages_with_species(p_coll, 1, 2) x;
$j$;
create or replace function pg_temp.wh_5897_h(p_coll uuid)
returns text language sql volatile as $h$ select md5(pg_temp.wh_5897_j(p_coll)::text); $h$;

-- As 11 colunas da 5316 (janela 1..2) e as mesmas 11 colunas da 5393.
create or replace function pg_temp.wh_5897_j16(p_coll uuid)
returns jsonb language sql volatile as $j16$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.page_number, x.row_index, x.column_index), '[]'::jsonb)
  from public.get_shared_collection_binder_pages(p_coll, 1, 2) x;
$j16$;
create or replace function pg_temp.wh_5897_j11(p_coll uuid)
returns jsonb language sql volatile as $j11$
  select coalesce(jsonb_agg((to_jsonb(x) - 'species_national_number' - 'species_name' - 'species_artwork_path' - 'references_visible')
                            order by x.page_number, x.row_index, x.column_index), '[]'::jsonb)
  from public.get_shared_collection_binder_pages_with_species(p_coll, 1, 2) x;
$j11$;

-- Quantas linhas diferem entre duas respostas (mesmo tamanho), e quais (page:row:col).
create or replace function pg_temp.wh_5897_diff(a jsonb, b jsonb)
returns text[] language sql immutable as $d$
  select coalesce(array_agg((x.e->>'page_number') || ':' || (x.e->>'row_index') || ':' || (x.e->>'column_index') order by x.i), '{}')
  from jsonb_array_elements(a) with ordinality x(e, i)
  where x.e is distinct from (b -> (x.i::int - 1));
$d$;

-- Coerência interna de uma resposta (C2 "resposta inválida" nunca acontece): espécie só em EMPTY e com exibição ligada; exibição constante.
create or replace function pg_temp.wh_5897_coherent(a jsonb)
returns boolean language sql immutable as $c$
  select not exists (select 1 from jsonb_array_elements(a) e
                     where (e->>'species_national_number') is not null
                       and (e->>'pocket_state' <> 'EMPTY' or (e->>'references_visible') is distinct from 'true'))
     and (select count(distinct coalesce(e->>'references_visible', '<null>')) from jsonb_array_elements(a) e) <= 1;
$c$;

create or replace function pg_temp.wh_5897_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
as $fn$
#variable_conflict use_column
declare
  u_u uuid := gen_random_uuid(); u_e uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_w uuid := gen_random_uuid(); u_d uuid := gen_random_uuid(); u_r uuid := gen_random_uuid();
  u_p uuid := gen_random_uuid(); u_s uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_std uuid; v_cat uuid; v_rar uuid; v_exp uuid; v_set uuid; v_gen text;
  k1 uuid; k1s uuid; v_inv uuid;
  c_x uuid; c_y uuid; c_z uuid; b_x uuid; b_z uuid; l_x uuid; l_z uuid;
  s_t uuid; s_n uuid; s_o uuid; pg1 uuid;
  pc_y uuid; pc_free uuid; pc_x uuid;
  m_e uuid; m_v uuid; m_w uuid; m_d uuid; m_r uuid; m_p uuid;
  p record; v_tok text; n integer; v_err text;
  j0 jsonb; j1 jsonb; jv jsonb; je jsonb; v_ok boolean; v_txt text;
  h0v text; h0e text; hv text; he text; h16_0 text; v_hashes text[] := '{}'; v_hashes_e text[] := '{}';
  v_md5_15 text; v_md5_16 text; v_md5_18 text;
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
begin
  -- 0. Estrutura (antes de qualquer fixture) ----------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    (select count(*) = 1 from pg_proc q
      where q.oid = to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)')
        and q.prosecdef and q.proconfig = array['search_path=""'] and q.provolatile = 's'
        and q.proowner = (select q2.proowner from pg_proc q2 where q2.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)'))
        and has_function_privilege('authenticated', q.oid, 'EXECUTE')
        and not has_function_privilege('anon', q.oid, 'EXECUTE')
        and not exists (select 1 from aclexplode(q.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
        and pg_get_function_result(q.oid) = 'TABLE(page_number integer, row_index integer, column_index integer, pocket_state text, card_name text, collector_number text, collector_total integer, card_set_code text, variant_label text, language_code text, image_path text, species_national_number integer, species_name text, species_artwork_path text, references_visible boolean)'),
    'detail','5393: definer, search_path vazio, STABLE, mesmo dono do núcleo 5315, só authenticated (nem anon nem PUBLIC), retorno exato (11 + 4 colunas)');
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(q.provolatile in ('s','i')) and count(*) = 5 from pg_proc q
      where q.oid in (to_regprocedure('public.collection_share_role(uuid)'),
                      to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)'),
                      to_regprocedure('public.v1_13_assert_capability()'),
                      to_regprocedure('public.v1_13_capability_open()'),
                      to_regprocedure('auth.uid()'))),
    'detail','C1: todas as funções chamadas pela 5393 (5302, 5315, 5389 ×2, auth.uid) são STABLE/IMMUTABLE');
  res := res || jsonb_build_object('id','0.3','ok',
    (select q.prosrc !~* '\mexecute\M' and q.prosrc !~* 'slot_assignment|slot_image|layout_region|expected_content|physical_card|collection_allocation|storage_container|condition'
       from pg_proc q where q.oid = to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)')),
    'detail','sem SQL dinâmico; a parte nova não lê posição de exemplar, imagem, região, reserva, alocação, local nem condição');
  select md5(q.prosrc) into v_md5_15 from pg_proc q where q.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)');
  select md5(q.prosrc) into v_md5_16 from pg_proc q where q.oid = to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)');
  select md5(q.prosrc) into v_md5_18 from pg_proc q where q.oid = to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)');
  res := res || jsonb_build_object('id','0.4','ok',
    v_md5_15 = 'ce559a495a49571a6598c83bc3d59202' and v_md5_16 = '79f893c45a08909e0a61d661952ab750' and v_md5_18 = '0da2d28209cd85b6bdbf6c20ae47efd6',
    'detail','5315, 5316 e 5318 com os corpos canônicos (não alteradas)');

  begin
    -- F. Fixture ------------------------------------------------------------------------------
    update public.v1_13_barrier_state set mode = 'OPEN', change_note = 'harness 5897 local' where id = 1;
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select c0.rarity_id into v_rar from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
      join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    select g.code into v_gen from public.pokedex dx join public.pokedex_position pp on pp.pokedex_id = dx.id
      join public.pokemon_species sp on sp.id = pp.species_id join public.pokemon_generation g on g.id = sp.generation_id
      where dx.code = 'NATIONAL' order by pp.position_number limit 1;
    if v_game is null or v_pt is null or v_std is null or v_cat is null or v_rar is null or v_gen is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ou Pokédex NATIONAL ausentes no banco local');
      raise exception 'MS897' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'S3_' || upper(v_sfx), 'S3 Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game)) returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'S3' || upper(v_sfx), 'S3 Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'S3 K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh897' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh897' || u.t || '_' || v_sfx, 'display_name', 'WH 5897 ' || upper(u.t)), now(), now()
    from (values (u_u,'u'), (u_e,'e'), (u_v,'v'), (u_w,'w'), (u_d,'d'), (u_r,'r'), (u_p,'p'), (u_s,'s')) u(id, t);

    perform pg_temp.wh_5897_as(u_u);
    select x.storage_container_id into b_x from public.create_my_storage_container(gen_random_uuid(), 'BIN X 5897', 'BINDER') x;
    select x.storage_container_id into b_z from public.create_my_storage_container(gen_random_uuid(), 'BIN Z 5897', 'BINDER') x;
    select x.collection_id into c_x from public.create_my_pokedex_collection(gen_random_uuid(), 'X 5897', array[v_gen], b_x) x;
    select x.collection_id into c_z from public.create_my_free_collection(gen_random_uuid(), 'Z 5897', b_z) x;
    select * into p from public.preview_my_collection_binder(c_x, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(c_x, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(c_z, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(c_z, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id into l_x from public.collection_layout l where l.collection_id = c_x;
    select l.id into l_z from public.collection_layout l where l.collection_id = c_z;
    select pg.id into pg1 from public.collection_layout_page pg where pg.layout_id = l_x and pg.page_number = 1;
    select s.id into s_t from public.collection_layout_slot s where s.page_id = pg1 and s.row_index = 1 and s.column_index = 1;
    select s.id into s_n from public.collection_layout_slot s where s.page_id = pg1 and s.row_index = 1 and s.column_index = 2;
    select s.id into s_o from public.collection_layout_slot s where s.page_id = pg1 and s.row_index = 3 and s.column_index = 3;
    if (select count(*) from public.collection_layout_page pg where pg.layout_id = l_x) < 2 then
      perform pg_temp.wh_5897_as(u_u);
      perform count(*) from public.add_layout_page(l_x);  -- janela 1..2 com duas páginas (5125)
      execute 'reset role';
    end if;
    -- Camada de referências pelo plano canônico (titular, 5258), exibição ligada.
    perform pg_temp.wh_5897_as(u_u);
    select x.plan_token into v_tok from public.preview_my_binder_species_references(c_x) x;
    perform count(*) from public.apply_my_binder_species_references(c_x, v_tok);
    select x.collection_id into c_y from public.create_my_free_collection(gen_random_uuid(), 'Y 5897', b_x) x;
    perform public.attach_my_collection_to_binder(c_y, l_x);
    -- Exemplares guardados no fichário F: um de Y, um sem coleção, um de X (controle positivo).
    select i.id into v_inv from public.inventory i where i.owner_user_id = u_u;
    execute 'reset role';
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
    values (k1s, v_pt, v_inv, b_x) returning id into pc_y;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
    values (k1s, v_pt, v_inv, b_x) returning id into pc_free;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, storage_container_id)
    values (k1s, v_pt, v_inv, b_x) returning id into pc_x;
    perform pg_temp.wh_5897_as(u_u);
    perform public.allocate_physical_cards_to_collection(c_y, array[pc_y]);
    perform public.allocate_physical_cards_to_collection(c_x, array[pc_x]);
    -- Participações.
    m_e := (public.invite_collection_member(c_x, 'wh897e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(c_x, 'wh897v_' || v_sfx) ->> 'membership_id')::uuid;
    m_d := (public.invite_collection_member(c_x, 'wh897d_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(c_x, 'wh897r_' || v_sfx) ->> 'membership_id')::uuid;
    m_p := (public.invite_collection_member(c_x, 'wh897p_' || v_sfx) ->> 'membership_id')::uuid;
    m_w := (public.invite_collection_member(c_y, 'wh897w_' || v_sfx) ->> 'membership_id')::uuid;
    perform public.invite_collection_member(c_z, 'wh897v_' || v_sfx);
    perform pg_temp.wh_5897_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5897_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform public.respond_collection_invite((select m.id from public.collection_membership m where m.collection_id = c_z and m.user_id = u_v), true);
    perform pg_temp.wh_5897_as(u_d); perform public.respond_collection_invite(m_d, true);
    perform pg_temp.wh_5897_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5897_as(u_w); perform public.respond_collection_invite(m_w, true);
    execute 'reset role';
    res := res || jsonb_build_object('id','F.2','ok',
      s_t is not null and s_n is not null and s_o is not null and c_y is not null
      and (select count(*) from public.collection_layout_slot_species_reference r where r.layout_id = l_x and r.collection_id = c_x) > 0
      and exists (select 1 from public.collection_layout_slot_species_reference r where r.slot_id = s_t and r.collection_id = c_x),
      'detail','fixture: X proprietária Pokédex com camada aplicada (bolso-alvo com referência), Y convidada, Z outra modalidade, participações aceitas');

    -- 1. Matriz de papéis ---------------------------------------------------------------------
    perform pg_temp.wh_5897_as(u_v); jv := pg_temp.wh_5897_j(c_x); j0 := pg_temp.wh_5897_j16(c_x);
    perform pg_temp.wh_5897_as(u_e); je := pg_temp.wh_5897_j(c_x);
    perform pg_temp.wh_5897_as(u_u); j1 := pg_temp.wh_5897_j(c_x);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', jv = je and jv = j1 and jsonb_array_length(jv) = 18,
      'detail','VIEWER, EDITOR e titular: resposta idêntica (EDITOR não recebe nada a mais), 2 páginas × 9 bolsos');
    res := res || jsonb_build_object('id','1.2','ok',
      (jv -> 0 ->> 'species_national_number') is not null and (jv -> 0 ->> 'references_visible') = 'true'
      and pg_temp.wh_5897_coherent(jv),
      'detail','bolso-alvo vazio da camada de X: espécie preenchida, exibição ligada; resposta coerente');
    perform pg_temp.wh_5897_as(u_u); perform public.set_collection_member_role(c_x, m_d, 'VIEWER');
    perform pg_temp.wh_5897_as(u_d); v_ok := pg_temp.wh_5897_j(c_x) = jv;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.3','ok', v_ok, 'detail','EDITOR rebaixado para VIEWER: igual ao VIEWER');
    perform pg_temp.wh_5897_as(u_u); perform public.remove_collection_member(c_x, m_r);
    perform pg_temp.wh_5897_as(u_r); v_err := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x));
    perform pg_temp.wh_5897_as(u_p); v_txt := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x));
    perform pg_temp.wh_5897_as(u_s);
    res := res || jsonb_build_object('id','1.4','ok',
      v_err = 'P0002:COLLECTION_NOT_FOUND' and v_txt = 'P0002:COLLECTION_NOT_FOUND'
      and pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x)) = 'P0002:COLLECTION_NOT_FOUND'
      and pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', gen_random_uuid())) = 'P0002:COLLECTION_NOT_FOUND',
      'detail','removido, convite pendente, estranho e coleção inexistente: COLLECTION_NOT_FOUND (indistinguíveis)');
    perform pg_temp.wh_5897_as(u_v); jv := pg_temp.wh_5897_j(c_z); j0 := pg_temp.wh_5897_j16(c_z);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.5','ok',
      jsonb_array_length(jv) > 0
      and not exists (select 1 from jsonb_array_elements(jv) e where e->>'species_national_number' is not null or e->>'references_visible' is not null),
      'detail','outra modalidade (livre): linhas da 5316, espécie e exibição NULL');
    perform pg_temp.wh_5897_as(u_w); jv := pg_temp.wh_5897_j(c_y);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.6','ok',
      jsonb_array_length(jv) > 0
      and not exists (select 1 from jsonb_array_elements(jv) e where e->>'species_national_number' is not null or e->>'references_visible' is not null),
      'detail','Y convidada no fichário de X: a camada é de outra coleção — espécie e exibição NULL');
    perform pg_temp.wh_5897_as(null);
    v_err := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x));
    execute 'reset role';
    update public.collection set visibility = 'PUBLIC' where id = c_x;  -- fixture: coleção pública
    perform pg_temp.wh_5897_as(u_s);
    v_txt := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x));
    execute 'reset role';
    update public.collection set visibility = 'PRIVATE' where id = c_x;
    res := res || jsonb_build_object('id','1.7','ok',
      v_err like '42501:%' and v_err not like '%CAPABILITY_NOT_ENABLED%' and v_txt = 'P0002:COLLECTION_NOT_FOUND',
      'detail','anônimo: sem EXECUTE (permission denied); coleção pública vista por quem não participa: COLLECTION_NOT_FOUND (vitrine só pela 5318)');
    perform pg_temp.wh_5897_as(u_u); perform public.archive_collection(c_x);
    perform pg_temp.wh_5897_as(u_v);
    v_txt := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x));
    v_err := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages(%L, 1, 2)', c_x));
    perform pg_temp.wh_5897_as(u_u); perform public.reactivate_collection(c_x);
    execute 'reset role';
    res := res || jsonb_build_object('id','1.8','ok', v_txt = v_err,
      'detail','coleção arquivada: mesmo resultado da 5316 (leitura ou recusa iguais)');
    update public.v1_13_barrier_state set mode = 'CLOSED' where id = 1;
    perform pg_temp.wh_5897_as(u_v);
    v_txt := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x));
    v_err := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages(%L, 1, 2)', c_x));
    perform pg_temp.wh_5897_as(u_u);
    v_ok := pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x)) = '42501:CAPABILITY_NOT_ENABLED';
    execute 'reset role';
    update public.v1_13_barrier_state set mode = 'TEST' where id = 1;
    perform pg_temp.wh_5897_as(u_v);
    v_ok := v_ok and pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x)) = '42501:CAPABILITY_NOT_ENABLED';
    execute 'reset role';
    insert into public.v1_13_barrier_identity (user_id, note) values (u_v, 'harness 5897');
    perform pg_temp.wh_5897_as(u_v);
    v_ok := v_ok and pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x)) = 'OK';
    execute 'reset role';
    delete from public.v1_13_barrier_identity where user_id = u_v;
    update public.v1_13_barrier_state set mode = 'OPEN' where id = 1;
    res := res || jsonb_build_object('id','1.9','ok', v_ok and v_txt = '42501:CAPABILITY_NOT_ENABLED' and v_err = 'OK',
      'detail','barreira CLOSED (VIEWER e titular) e TEST fora do registro: CAPABILITY_NOT_ENABLED; TEST no registro: OK; a 5316 não depende da barreira');
    perform pg_temp.wh_5897_as(u_v);
    res := res || jsonb_build_object('id','1.10','ok',
      pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 5)', c_x)) like '22023:%'
      and pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, null, 1)', c_x)) like '22023:%'
      and (select count(*) from public.get_shared_collection_binder_pages_with_species(c_x, 900, 1)) = 0,
      'detail','janela: mais de 4 páginas e argumento nulo → INVALID_ARGUMENT (núcleo 5315); janela além do fim → zero linhas, como a 5316');
    execute 'reset role';

    -- 2. Regressão 5316/5318 e onze colunas -----------------------------------------------------
    perform pg_temp.wh_5897_as(u_v);
    v_ok := pg_temp.wh_5897_j11(c_x) = pg_temp.wh_5897_j16(c_x)
            and (select count(*) from public.get_shared_collection_binder_pages_with_species(c_x, 1, 4))
              = (select count(*) from public.get_shared_collection_binder_pages(c_x, 1, 4));
    execute 'reset role';
    update public.collection set visibility = 'PUBLIC' where id = c_x;
    perform pg_temp.wh_5897_as(null);
    v_txt := pg_temp.wh_5897_try(format('select * from public.get_public_collection_binder_pages(%L, 1, 2)', c_x));
    execute 'reset role';
    update public.collection set visibility = 'PRIVATE' where id = c_x;
    res := res || jsonb_build_object('id','2.1','ok', v_ok and v_txt in ('OK', 'P0002:COLLECTION_NOT_FOUND'),
      'detail','as 11 colunas da 5393 = 5316 linha a linha (mesma ordem, mesmas linhas, janela 1..4); 5318 continua respondendo como antes (sem colunas de espécie)');

    -- 3. Não inferência entre estados (A, B, B′, C, D, E) — sessões V e E --------------------------
    -- A: bolso-alvo realmente vazio.
    perform pg_temp.wh_5897_as(u_v); h0v := pg_temp.wh_5897_h(c_x); h16_0 := md5(pg_temp.wh_5897_j16(c_x)::text); j0 := pg_temp.wh_5897_j(c_x);
    perform pg_temp.wh_5897_as(u_e); h0e := pg_temp.wh_5897_h(c_x);
    execute 'reset role';
    -- B: carta de Y no bolso-alvo.
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id) values (s_t, pc_y);
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); v_txt := md5(pg_temp.wh_5897_j16(c_x)::text);
    perform pg_temp.wh_5897_as(u_e); v_hashes_e := v_hashes_e || pg_temp.wh_5897_h(c_x);
    execute 'reset role';
    v_ok := v_txt = h16_0;
    delete from public.collection_layout_slot_assignment where slot_id = s_t;
    -- B′: carta sem coleção.
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id) values (s_t, pc_free);
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); v_ok := v_ok and md5(pg_temp.wh_5897_j16(c_x)::text) = h16_0;
    perform pg_temp.wh_5897_as(u_e); v_hashes_e := v_hashes_e || pg_temp.wh_5897_h(c_x);
    execute 'reset role';
    delete from public.collection_layout_slot_assignment where slot_id = s_t;
    -- C: imagem personalizada do titular.
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (s_t, u_u, u_u::text || '/' || c_x::text || '/' || gen_random_uuid()::text || '.webp');
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); v_ok := v_ok and md5(pg_temp.wh_5897_j16(c_x)::text) = h16_0;
    perform pg_temp.wh_5897_as(u_e); v_hashes_e := v_hashes_e || pg_temp.wh_5897_h(c_x);
    execute 'reset role';
    delete from public.collection_layout_slot_image where slot_id = s_t;
    -- D: mesclagem (região 1 × 2 cobrindo o bolso-alvo e o vizinho).
    insert into public.collection_layout_region (page_id, top_row, left_column, height, width) values (pg1, 1, 1, 1, 2);
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); v_ok := v_ok and md5(pg_temp.wh_5897_j16(c_x)::text) = h16_0;
    perform pg_temp.wh_5897_as(u_e); v_hashes_e := v_hashes_e || pg_temp.wh_5897_h(c_x);
    execute 'reset role';
    delete from public.collection_layout_region where page_id = pg1;
    -- E: reserva de Y.
    insert into public.collection_layout_slot_expected_content (slot_id, card_id, card_variant_id, collection_id) values (s_t, k1, k1s, c_y);
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); v_ok := v_ok and md5(pg_temp.wh_5897_j16(c_x)::text) = h16_0;
    perform pg_temp.wh_5897_as(u_e); v_hashes_e := v_hashes_e || pg_temp.wh_5897_h(c_x);
    execute 'reset role';
    delete from public.collection_layout_slot_expected_content where slot_id = s_t;
    res := res || jsonb_build_object('id','3.1','ok',
      array_length(v_hashes, 1) = 5 and (select bool_and(h = h0v) from unnest(v_hashes) h)
      and array_length(v_hashes_e, 1) = 5 and (select bool_and(h = h0e) from unnest(v_hashes_e) h)
      and h0v = h0e and v_ok,
      'detail','A = B = B′ = C = D = E (resposta completa: linhas, ordem, 11 + 4 colunas, nulos, exibição, espécie), para VIEWER e EDITOR; VIEWER = EDITOR; a 5316 também constante');

    -- 4. Não inferência entre consultas (C3) + controles positivos ---------------------------------
    v_hashes := '{}';
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id) values (s_o, pc_y);        -- fora do alvo
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); execute 'reset role';
    delete from public.collection_layout_slot_assignment where slot_id = s_o;
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    values (s_o, u_u, u_u::text || '/' || c_x::text || '/' || gen_random_uuid()::text || '.webp');
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); execute 'reset role';
    delete from public.collection_layout_slot_image where slot_id = s_o;
    insert into public.collection_layout_slot_assignment (slot_id, physical_card_id) values (s_t, pc_y);        -- volta a B
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x); execute 'reset role';
    delete from public.collection_layout_slot_assignment where slot_id = s_t;                                   -- volta a A
    perform pg_temp.wh_5897_as(u_v); v_hashes := v_hashes || pg_temp.wh_5897_h(c_x);
    v_ok := md5(pg_temp.wh_5897_j16(c_x)::text) = h16_0;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', (select bool_and(h = h0v) from unnest(v_hashes) h) and v_ok,
      'detail','conteúdo oculto alterado entre consultas (no alvo e fora dele, ida e volta): resposta da 5393 e da 5316 idênticas a h0');
    -- Controle positivo: carta de X no alvo → só a linha do alvo muda; CARD; espécie NULL.
    perform pg_temp.wh_5897_as(u_u);
    perform public.place_my_physical_card_in_slot(c_x, s_t, pc_x);
    perform pg_temp.wh_5897_as(u_v); j1 := pg_temp.wh_5897_j(c_x); execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok',
      pg_temp.wh_5897_diff(j0, j1) = array['1:1:1'] and (j1 -> 0 ->> 'pocket_state') = 'CARD'
      and (j1 -> 0 ->> 'species_national_number') is null and pg_temp.wh_5897_coherent(j1),
      'detail','controle positivo: carta de X no alvo muda só a linha do alvo (CARD, espécie NULL)');
    delete from public.collection_layout_slot_assignment where slot_id = s_t;
    perform pg_temp.wh_5897_as(u_v); v_ok := pg_temp.wh_5897_h(c_x) = h0v; execute 'reset role';
    insert into public.collection_layout_slot_expected_content (slot_id, card_id, card_variant_id, collection_id) values (s_t, k1, k1s, c_x);
    perform pg_temp.wh_5897_as(u_v); j1 := pg_temp.wh_5897_j(c_x); execute 'reset role';
    delete from public.collection_layout_slot_expected_content where slot_id = s_t;
    perform pg_temp.wh_5897_as(u_v); v_ok := v_ok and pg_temp.wh_5897_h(c_x) = h0v; execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok',
      v_ok and pg_temp.wh_5897_diff(j0, j1) = array['1:1:1'] and (j1 -> 0 ->> 'pocket_state') = 'RESERVED'
      and (j1 -> 0 ->> 'species_national_number') is null,
      'detail','controle positivo: reserva de X no alvo muda só a linha do alvo (RESERVED, espécie NULL); desfazer volta a h0');
    perform pg_temp.wh_5897_as(u_u); perform public.set_my_binder_species_reference_visibility(c_x, false);
    perform pg_temp.wh_5897_as(u_v); j1 := pg_temp.wh_5897_j(c_x); execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok',
      not exists (select 1 from jsonb_array_elements(j1) e where e->>'species_national_number' is not null or (e->>'references_visible') is distinct from 'false')
      and (select bool_and((a.e - 'species_national_number' - 'species_name' - 'species_artwork_path' - 'references_visible')
                           = (b.e - 'species_national_number' - 'species_name' - 'species_artwork_path' - 'references_visible'))
           from jsonb_array_elements(j0) with ordinality a(e, i) join jsonb_array_elements(j1) with ordinality b(e, i) using (i)),
      'detail','ocultar: espécie NULL em todas as linhas, references_visible = false; nenhuma outra coluna muda');
    perform pg_temp.wh_5897_as(u_u); perform public.set_my_binder_species_reference_visibility(c_x, true);
    select x.reference_count into n from public.get_my_binder_species_reference_state(c_x) x;
    perform public.clear_my_binder_species_references(c_x, n);
    perform pg_temp.wh_5897_as(u_v); j1 := pg_temp.wh_5897_j(c_x); execute 'reset role';
    v_ok := not exists (select 1 from jsonb_array_elements(j1) e where e->>'species_national_number' is not null or (e->>'references_visible') is distinct from 'true');
    perform pg_temp.wh_5897_as(u_u);
    select x.plan_token into v_tok from public.preview_my_binder_species_references(c_x) x;
    perform count(*) from public.apply_my_binder_species_references(c_x, v_tok);
    perform pg_temp.wh_5897_as(u_v); v_ok := v_ok and pg_temp.wh_5897_h(c_x) = h0v; execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok', v_ok,
      'detail','remover a camada: espécie NULL, references_visible mantém true; reaplicar o mesmo plano volta a h0');
    -- Referências deixadas por outra coleção (simula proprietária anterior, fixture privilegiada).
    update public.collection_layout_slot_species_reference set collection_id = c_y where slot_id = s_t;
    perform pg_temp.wh_5897_as(u_v); j1 := pg_temp.wh_5897_j(c_x); execute 'reset role';
    update public.collection_layout_slot_species_reference set collection_id = c_x where slot_id = s_t;
    res := res || jsonb_build_object('id','4.6','ok',
      (j1 -> 0 ->> 'species_national_number') is null and pg_temp.wh_5897_diff(j0, j1) = array['1:1:1'],
      'detail','referência de outra coleção no bolso-alvo nunca aparece (só aquele bolso perde a espécie)');

    -- 5. Reversão (dentro de um ponto de salvamento) ---------------------------------------------
    perform pg_temp.wh_5897_as(u_v); j0 := pg_temp.wh_5897_j16(c_x); execute 'reset role';
    begin
      drop function public.get_shared_collection_binder_pages_with_species(uuid, integer, integer);
      perform pg_temp.wh_5897_as(u_v);
      v_ok := pg_temp.wh_5897_j16(c_x) = j0
              and pg_temp.wh_5897_try(format('select * from public.get_shared_collection_binder_pages_with_species(%L, 1, 2)', c_x)) like '42883:%';
      execute 'reset role';
      v_ok := v_ok
        and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)')) = v_md5_15
        and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)')) = v_md5_16
        and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)')) = v_md5_18;
      raise exception 'WH5897_RB' using errcode = 'P0001';
    exception when sqlstate 'P0001' then
      if sqlerrm <> 'WH5897_RB' then raise; end if;
    end;
    res := res || jsonb_build_object('id','5.1','ok', v_ok and to_regprocedure('public.get_shared_collection_binder_pages_with_species(uuid, integer, integer)') is not null,
      'detail','R5393 (ensaiada e desfeita): 5316 responde igual, a 5393 some (função inexistente), 5315/5316/5318 intactas');

    raise exception 'WH5897_END' using errcode = 'P0001';
  exception when sqlstate 'P0001' then
    if sqlerrm not in ('WH5897_END', 'MS897') then
      res := res || jsonb_build_object('id','X','ok', false, 'detail','erro inesperado: ' || sqlerrm);
    end if;
  end;

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if (r->>'ok')::boolean then passes := passes + 1; end if;
    seq := cnt; check_id := r->>'id'; status := case when (r->>'ok')::boolean then 'PASS' else 'FAIL' end; detail := r->>'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE'; status := case when passes = cnt and cnt = 24 then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' (esperado 24/24)';
  return next;
end;
$fn$;
