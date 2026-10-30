/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5861 - Harness V1-12 COLLECTION-SHARING-FOUNDATION-01
              (5300–5315): estrutura, convite/aceite, VIEWER, fichário
              só leitura, não enumeração, revogação, público, escrita
              negada, resíduo zero
Versão......: 1.2 (2026-10-30) — v1.1: fichário do VIEWER (0.6, F.2, 1.5,
              2.8, 3.8–3.11, 4.7, 5.7); v1.2 (PUBLIC BINDER EXPERIENCE):
              vitrine pública só do fichário (5315 núcleo, 5317/5318),
              5312/5313 só participante, privilégios excedentes (5319): 0.7, 0.8, 5.2,
              5.4, 5.5 reescritos, 5.8, 5.9
              v1.3 (2026-10-30, correção só do harness após a 1ª execução
              LIVE da v1.2 — GATE 26/29, 23 não executadas): 0.6/0.7 aplicam
              a regex de colunas privadas só às colunas de SAÍDA (proargmodes
              o/t) — a v1.2 casava o parâmetro de entrada p_collection_id;
              3.5 aceita COLLECTION_NOT_FOUND de get_my_collection_binder
              como negação válida (o contrato 5223/5252 nega por exceção, não
              por zero linhas) — na v1.2 a exceção abortava o bloco. Nenhuma
              asserção de segurança foi relaxada; migrations intocadas.
Status......: PROPOSTA — v1.3 NÃO EXECUTADA (v1.2 executada no LIVE em
              2026-10-30: FAIL por defeito do harness, 99.1 PASS). Executar só
              com autorização de Fabrício.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-30

Protocolo (o mesmo da 5850/5851): um único statement, usuários efêmeros
A (titular), B (convidado) e C (estranho), catálogo SINTÉTICO mínimo
(1 Set, 2 cartas, variante STANDARD) criado como dono do banco; a sentinela
MS861 desfaz tudo; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5861_validate();

Fixture (tudo de A pelas RPCs canônicas):
  CO  coleção livre (local BIN) com a1, a2 (carta K1) → a compartilhada
  CX  coleção livre (local BIN) com x1 (carta K2) → outra coleção de A
  CO tem fichário 3×3; CX entra nele como convidada (mesmo local BIN).
  No fichário: a1 (de CO) e x1 (de CX) em bolsos; reserva de K1 para CO
  e, se o banco aceitar, reserva de K2 para CX — prova de mascaramento:
  o VIEWER de CO vê a1 e a reserva de CO; x1 e a reserva de CX viram
  bolso vazio.
  B tem b1 (K1) no próprio acervo (prova de escrita negada)

Seções:
  0  estrutura: objetos, RLS sem política, sem privilégio de tabela,
     grants das RPCs, search_path vazio, CHECK de visibilidade, projeções
     sem colunas privadas
  1  estranho e anon: nada lê, nada escreve, nada enumera
  2  convite: normalização, idempotência, erros; pendente não dá acesso;
     caixa de convites; resposta só pelo convidado; aceite idempotente
  3  VIEWER: lê só CO (cabeçalho, cartas, progresso), não CX, não acervo,
     não os contratos get_my_* do fichário, não tabela; toda escrita
     recusada; fichário só leitura (5314/5315) mascarado; S-PROG: progresso
     compartilhado = progresso do titular para TODAS as coleções com
     referência do LIVE (leitura, sob a identidade de cada titular)
  4  revogação: remover, recusar, reconvidar, sair — acesso cai na hora
  5  público: PUBLIC abre SÓ a vitrine do fichário (5317/5318), sem
     sessão, com o mesmo mascaramento; nunca galeria, progresso ou
     cabeçalho do participante; PRIVATE e arquivar fecham na hora;
     arquivada não publica nem convida, mas remove e privatiza
  99 resíduo zero e papel restaurado

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Concorrência real (duas sessões) fica para o roteiro manual K1–K2 do
     README: convite duplo simultâneo e aceite em duas abas.
================================================================
*/

create or replace function pg_temp.wh_5861_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_inv  oid := to_regprocedure('public.invite_collection_member(uuid, text)');
  f_rsp  oid := to_regprocedure('public.respond_collection_invite(uuid, boolean)');
  f_rem  oid := to_regprocedure('public.remove_collection_member(uuid, uuid)');
  f_lev  oid := to_regprocedure('public.leave_shared_collection(uuid)');
  f_vis  oid := to_regprocedure('public.set_collection_visibility(uuid, text)');
  f_shr  oid := to_regprocedure('public.get_my_collection_sharing(uuid)');
  f_box  oid := to_regprocedure('public.get_my_collection_invites()');
  f_swm  oid := to_regprocedure('public.get_collections_shared_with_me()');
  f_get  oid := to_regprocedure('public.get_shared_collection(uuid)');
  f_crd  oid := to_regprocedure('public.get_shared_collection_cards(uuid, integer, integer)');
  f_rol  oid := to_regprocedure('public.collection_share_role(uuid)');
  f_sum  oid := to_regprocedure('public.collection_completion_summary_shared(uuid)');
  f_bh   oid := to_regprocedure('public.get_shared_collection_binder(uuid)');
  f_bp   oid := to_regprocedure('public.get_shared_collection_binder_pages(uuid, integer, integer)');
  f_mp   oid := to_regprocedure('public.collection_binder_masked_pages(uuid, integer, integer)');
  f_pb   oid := to_regprocedure('public.get_public_collection_binder(uuid)');
  f_pp   oid := to_regprocedure('public.get_public_collection_binder_pages(uuid, integer, integer)');
  pub_allowed text[] := array['collection_id','name','completion_policy','cover_finish','owner_display_name','card_set_code',
    'card_set_name','card_set_logo_path','has_binder','binder_name','show_brand_mark','grid_columns','grid_rows','page_count'];
  v_layout uuid; v_slots uuid[]; v_sl uuid; v_res_cx boolean := false; v_res_co boolean := false;
  o_cards integer; o_res integer; o_pages integer;
  b_card integer; b_res integer; b_bad integer; b_leak integer; b_odd integer; b_total integer;
  asg0 integer; exp0 integer; v_ok2 boolean; v_closed boolean;
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  n_a text; n_b text;
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid; k2 uuid; k2s uuid;
  v_inv_a uuid; v_inv_b uuid; v_ids uuid[];
  a1 uuid; a2 uuid; x1 uuid; b1 uuid;
  v_bin uuid; v_co uuid; v_cx uuid; m_b uuid;
  p record; j jsonb; j2 jsonb; v_err text; v_ok boolean; n integer; c record;
  allowed text[] := array['collection_id','name','description','mode','completion_policy','lifecycle_status',
    'visibility','cover_finish','card_set_code','card_set_name','card_set_logo_path','owner_display_name',
    'access','membership_id','copies_count','total_positions','satisfied_positions','progress_percentage','is_complete'];
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 51;
begin
  -- 0. Estrutura ---------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    to_regclass('public.collection_membership') is not null
    and f_inv is not null and f_rsp is not null and f_rem is not null and f_lev is not null and f_vis is not null
    and f_shr is not null and f_box is not null and f_swm is not null and f_get is not null and f_crd is not null
    and f_rol is not null and f_sum is not null,
    'detail','tabela e 12 funções presentes');
  res := res || jsonb_build_object('id','0.2','ok',
    (select c2.relrowsecurity from pg_class c2 where c2.oid = 'public.collection_membership'::regclass)
    and not exists (select 1 from pg_policy pl where pl.polrelid = 'public.collection_membership'::regclass)
    and not has_table_privilege('authenticated', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE')
    and not has_table_privilege('anon', 'public.collection_membership', 'SELECT,INSERT,UPDATE,DELETE'),
    'detail','RLS ligada, nenhuma política, nenhum privilégio de tabela para anon/authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'])
       from pg_proc q where q.oid in (f_inv, f_rsp, f_rem, f_lev, f_vis, f_shr, f_box, f_swm, f_get, f_crd, f_rol, f_sum))
    and (select bool_and(has_function_privilege('authenticated', q.oid, 'EXECUTE') and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_inv, f_rsp, f_rem, f_lev, f_vis, f_shr, f_box, f_swm, f_get, f_crd))
    and (select bool_and(not has_function_privilege('authenticated', q.oid, 'EXECUTE') and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_rol, f_sum)),
    'detail','definer + search_path vazio; convite, painel, cabeçalho e galeria do participante só authenticated; internas sem EXECUTE');
  res := res || jsonb_build_object('id','0.4','ok',
    (select pg_get_constraintdef(k.oid) from pg_constraint k where k.conname = 'chk_collection_visibility') like '%PUBLIC%'
    and (select column_default from information_schema.columns where table_schema='public' and table_name='collection' and column_name='visibility') like '%PRIVATE%',
    'detail','visibilidade aceita PUBLIC; default continua PRIVATE');
  res := res || jsonb_build_object('id','0.5','ok',
    not exists (select 1 from pg_proc q, unnest(q.proargnames) a(name)
                where q.oid = f_crd and (a.name ~ '(storage|price|paid|value|acqui|condition|certif|physical_card|owner)')),
    'detail','galeria compartilhada sem coluna de local, valor, aquisição, condição, exemplar ou titular');
  res := res || jsonb_build_object('id','0.6','ok',
    f_bh is not null and f_bp is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'] and q.provolatile = 's'
                         and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_bh, f_bp))
    and not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                    where q.oid = f_bp and a.mode in ('o','t')
                      and a.name ~ '(_id$|^id$|storage|physical|allocation|assignment|locked|region|collection|owner|price|value)'),
    'detail','fichário compartilhado: definer STABLE, search_path vazio, só authenticated; páginas sem ids, local, fixação, mesclagem, coleção ou valor');
  res := res || jsonb_build_object('id','0.7','ok',
    f_mp is not null and f_pb is not null and f_pp is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""'] and q.provolatile = 's')
           from pg_proc q where q.oid in (f_mp, f_pb, f_pp))
    and not has_function_privilege('anon', f_mp, 'EXECUTE') and not has_function_privilege('authenticated', f_mp, 'EXECUTE')
    and (select bool_and(has_function_privilege('anon', q.oid, 'EXECUTE') and has_function_privilege('authenticated', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_pb, f_pp))
    and not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                    where q.oid = f_pp and a.mode in ('o','t')
                      and a.name ~ '(_id$|^id$|storage|physical|allocation|assignment|locked|region|collection|owner|price|value)'),
    'detail','vitrine pública: núcleo 5315 interno (sem EXECUTE); 5317/5318 definer STABLE, anon+authenticated; páginas sem ids nem dados privados');
  res := res || jsonb_build_object('id','0.8','ok',
    (select count(*) from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.grantee in ('anon','authenticated')
        and g.privilege_type in ('TRUNCATE','REFERENCES','TRIGGER')) = 0
    and has_table_privilege('authenticated', 'public.user_profile', 'SELECT')
    and has_table_privilege('authenticated', 'public.user_profile', 'UPDATE')
    and has_table_privilege('authenticated', 'public.catalog_card_set_metrics', 'SELECT')
    and has_table_privilege('authenticated', 'public.catalog_card_set_image_coverage', 'SELECT')
    and has_table_privilege('authenticated', 'public.catalog_card_set_variant_coverage', 'SELECT')
    and (select count(*) from pg_policy pl where pl.polrelid = 'public.user_profile'::regclass) = 2,
    'detail','5319: nenhum TRUNCATE/REFERENCES/TRIGGER para anon/authenticated no schema; SELECT/UPDATE do perfil e SELECT das views do catálogo preservados; políticas de user_profile intactas');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection where visibility = 'PUBLIC')]
    into b_counts;

  begin
    -- F. Catálogo sintético e usuários --------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS861' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'SHR_' || upper(v_sfx), 'SHR Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'SHR' || upper(v_sfx), 'SHR Set ' || v_sfx, 'REGULAR', 1, 2, 2) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'SHR K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'SHR K2', true) returning id into k2;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;

    n_a := 'wh861a_' || v_sfx; n_b := 'wh861b_' || v_sfx;
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at) values
      (u_a, 'authenticated', 'authenticated', n_a || '@example.invalid', jsonb_build_object('username', n_a, 'display_name', 'WH 5861 A'), now(), now()),
      (u_b, 'authenticated', 'authenticated', n_b || '@example.invalid', jsonb_build_object('username', n_b, 'display_name', 'WH 5861 B'), now(), now()),
      (u_c, 'authenticated', 'authenticated', 'wh861c_' || v_sfx || '@example.invalid', jsonb_build_object('username', 'wh861c_' || v_sfx, 'display_name', 'WH 5861 C'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at) values
      (k1s, v_pt, v_inv_a, now() - interval '3 min'), (k1s, v_pt, v_inv_a, now() - interval '2 min'),
      (k2s, v_pt, v_inv_a, now() - interval '1 min');
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; a2 := v_ids[2]; x1 := v_ids[3];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_b) returning id into b1;

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5861', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5861', v_bin) x;
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5861', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2]);
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    res := res || jsonb_build_object('id','F.1','ok',
      v_co is not null and v_cx is not null
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 2
      and exists (select 1 from public.collection_layout l where l.collection_id = v_co),
      'detail','fixture: CO (2 cópias de K1, com fichário) e CX (K2) de A; b1 no acervo de B');

    -- F.2 Fichário compartilhado entre CO (dona) e CX (convidada), com uma carta e uma
    -- reserva de cada coleção. Exemplares guardados no local do fichário (passo
    -- privilegiado, como o catálogo); o resto pelas RPCs canônicas de A.
    select l.id into v_layout from public.collection_layout l where l.collection_id = v_co;
    update public.physical_card pc set storage_container_id = (select l.storage_container_id from public.collection_layout l where l.id = v_layout)
    where pc.id in (a1, a2, x1);
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    execute 'reset role';
    select array_agg(s.id order by p2.page_number, s.row_index, s.column_index) into v_slots
    from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
    where p2.layout_id = v_layout;
    execute 'set local role authenticated';
    if not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a1) then
      select sl into v_sl from unnest(v_slots) sl
      where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
        and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
      perform public.place_my_physical_card_in_slot(v_co, v_sl, a1);
    end if;
    select sl into v_sl from unnest(v_slots) sl
    where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
    perform public.place_my_physical_card_in_slot(v_cx, v_sl, x1);
    select sl into v_sl from unnest(v_slots) sl
    where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
    begin perform public.set_slot_expected_content(v_sl, k1, null, null, v_co); v_res_co := true; exception when others then v_res_co := false; end;
    select sl into v_sl from unnest(v_slots) sl
    where not exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = sl)
      and not exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = sl) limit 1;
    begin perform public.set_slot_expected_content(v_sl, k2, null, null, v_cx); v_res_cx := true; exception when others then v_res_cx := false; end;
    -- Verdade do titular (contrato 5252), para comparar com a visão do VIEWER.
    select count(*) filter (where o.present_collection_id = v_co),
           count(*) filter (where o.slot_state = 'RESERVED_EMPTY' and o.expected_collection_id = v_co),
           count(distinct o.page_number)
      into o_cards, o_res, o_pages
    from public.get_my_collection_binder_pages(v_co, 1, 4) o;
    execute 'reset role';
    select count(*) into asg0 from public.collection_layout_slot_assignment a
    join public.collection_layout_slot s on s.id = a.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
    where p2.layout_id = v_layout;
    select count(*) into exp0 from public.collection_layout_slot_expected_content e
    join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
    where p2.layout_id = v_layout;
    res := res || jsonb_build_object('id','F.2','ok',
      exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx)
      and exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a1)
      and exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = x1)
      and v_res_co and o_cards >= 1,
      'detail','fixture do fichário: CX convidada; a1 e x1 em bolsos; reserva de CO = ' || v_res_co
        || '; reserva de CX = ' || v_res_cx || ' (opcional); titular vê ' || coalesce(o_cards, 0) || ' carta(s) de CO e '
        || coalesce(o_res, 0) || ' reserva(s) de CO');

    -- 1. Estranho e anon -----------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform public.invite_collection_member(v_co, n_b); exception when others then v_err := sqlstate; end;
    v_ok := v_err = '42501';
    v_err := null; begin perform public.get_shared_collection(v_co); exception when others then v_err := sqlstate; end;
    v_ok := v_ok and v_err = '42501';
    v_err := null; begin perform count(*) from public.get_shared_collection_cards(v_co, 48, 0); exception when others then v_err := sqlstate; end;
    v_ok := v_ok and v_err = '42501';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.1','ok', v_ok and public.get_public_collection_binder(v_co) is null
      and public.get_public_collection_binder(gen_random_uuid()) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','anon: convite, cabeçalho e galeria do participante 42501; vitrine de coleção PRIVATE ≡ inexistente (NULL / COLLECTION_NOT_FOUND)');
    v_err := null; begin perform public.get_shared_collection_binder(v_co); exception when others then v_err := sqlstate; end;
    v_ok := v_err = '42501';
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlstate; end;
    v_ok := v_ok and v_err = '42501';
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_c::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','1.2','ok',
      public.get_shared_collection(v_co) is null and public.get_shared_collection(gen_random_uuid()) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and public.get_my_collection_sharing(v_co) is null,
      'detail','estranho: privada alheia ≡ inexistente (NULL, zero linhas, sem painel)');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.5','ok', v_ok and public.get_shared_collection_binder(v_co) is null
      and v_err = 'COLLECTION_NOT_FOUND',
      'detail','fichário: anon sem EXECUTE (42501); estranho → cabeçalho NULL e páginas COLLECTION_NOT_FOUND');
    v_err := null; begin perform public.invite_collection_member(v_co, n_b); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'COLLECTION_NOT_FOUND',
      'detail','estranho não convida em coleção alheia (COLLECTION_NOT_FOUND)');
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PUBLIC'); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'COLLECTION_NOT_FOUND'
      and (select c3.visibility from public.collection c3 where c3.id = v_co) is null,
      'detail','estranho não publica (e nem lê a coleção pela tabela — RLS select-own)');
    execute 'reset role';

    -- 2. Convite -------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.invite_collection_member(v_co, '  @' || upper(n_b) || ' ');
    m_b := (j ->> 'membership_id')::uuid;
    res := res || jsonb_build_object('id','2.1','ok', j ->> 'outcome' = 'INVITED' and j ->> 'username' = n_b
      and j ->> 'display_name' = 'WH 5861 B' and not (j ? 'user_id'),
      'detail','convite por @USERNAME normalizado → INVITED; devolve só username e nome de exibição');
    j := public.invite_collection_member(v_co, n_b);
    v_err := null; begin perform count(*) from public.collection_membership; exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','2.2','ok', j ->> 'outcome' = 'ALREADY_PENDING' and (j ->> 'membership_id')::uuid = m_b
      and v_err = '42501',
      'detail','repetição → ALREADY_PENDING, mesma participação; tabela inacessível direto (42501)');
    v_err := null; begin perform public.invite_collection_member(v_co, 'nao_existe_' || v_sfx); exception when others then v_err := sqlerrm; end;
    v_ok := v_err = 'USER_NOT_FOUND';
    v_err := null; begin perform public.invite_collection_member(v_co, n_a); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'CANNOT_INVITE_SELF';
    v_err := null; begin perform public.invite_collection_member(v_co, 'a b'); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'INVALID_USERNAME';
    res := res || jsonb_build_object('id','2.3','ok', v_ok, 'detail','USER_NOT_FOUND, CANNOT_INVITE_SELF, INVALID_USERNAME');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','2.4','ok', public.get_shared_collection(v_co) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','convite PENDING não dá acesso antecipado (cabeçalho, cartas, lista)');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.8','ok', public.get_shared_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','convite PENDING não abre o fichário');
    j := public.get_my_collection_invites();
    res := res || jsonb_build_object('id','2.5','ok', jsonb_array_length(j) = 1
      and j -> 0 ->> 'collection_name' = 'CO 5861' and j -> 0 ->> 'owner_username' = n_a
      and (j -> 0 ->> 'membership_id')::uuid = m_b
      and not (j -> 0 ? 'copies_count') and not (j -> 0 ? 'owner_user_id'),
      'detail','caixa de convites: só o necessário para decidir (nome, titular) — sem cartas, sem ids de usuário');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_c::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform public.respond_collection_invite(m_b, true); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.6','ok', v_err = 'INVITE_NOT_FOUND' and jsonb_array_length(public.get_my_collection_invites()) = 0,
      'detail','estranho não aceita convite alheio nem o vê na caixa');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.respond_collection_invite(m_b, true);
    j2 := public.respond_collection_invite(m_b, true);
    res := res || jsonb_build_object('id','2.7','ok', j ->> 'outcome' = 'ACTIVE' and j2 ->> 'outcome' = 'UNCHANGED'
      and jsonb_array_length(public.get_my_collection_invites()) = 0,
      'detail','aceite → ACTIVE; segundo aceite → UNCHANGED; caixa vazia');

    -- 3. VIEWER ---------------------------------------------------------------------------
    j := public.get_shared_collection(v_co);
    res := res || jsonb_build_object('id','3.1','ok', j ->> 'access' = 'VIEWER' and (j ->> 'copies_count')::int = 2
      and (j ->> 'membership_id')::uuid = m_b and j ->> 'owner_display_name' = 'WH 5861 A'
      and (select bool_and(k = any(allowed)) from jsonb_object_keys(j) k),
      'detail','VIEWER lê o cabeçalho de CO; só chaves permitidas (sem username/id do titular, sem local, sem valor)');
    select count(*), bool_and(x.card_name = 'SHR K1' and x.copies_count = 2) into n, v_ok
    from public.get_shared_collection_cards(v_co, 48, 0) x;
    res := res || jsonb_build_object('id','3.2','ok', n = 1 and v_ok,
      'detail','galeria: só as cartas alocadas a CO (K1 ×2), nunca K2 de CX');
    res := res || jsonb_build_object('id','3.3','ok', public.get_shared_collection(v_cx) is null
      and (select count(*) from public.get_shared_collection_cards(v_cx, 48, 0)) = 0,
      'detail','outra coleção do mesmo titular continua invisível');
    j := public.get_collections_shared_with_me();
    res := res || jsonb_build_object('id','3.4','ok', jsonb_array_length(j) = 1 and (j -> 0 ->> 'collection_id')::uuid = v_co
      and not (j -> 0 ? 'owner_username'),
      'detail','"Compartilhadas comigo" lista só CO');
    -- get_my_collection_binder nega coleção alheia por exceção (COLLECTION_NOT_FOUND);
    -- zero linhas também é negação. Qualquer outro erro reprova.
    v_closed := null;
    begin
      v_closed := not exists (select 1 from public.get_my_collection_binder(v_co) bh where bh.has_binder);
    exception when others then
      v_closed := (sqlerrm = 'COLLECTION_NOT_FOUND');
    end;
    res := res || jsonb_build_object('id','3.5','ok',
      not exists (select 1 from public.get_my_collections(true, 100, 0) g where g.collection_id = v_co)
      and not exists (select 1 from public.get_my_inventory_items(null, null, null, v_co) i)
      and coalesce(v_closed, false)
      and public.get_my_collection_sharing(v_co) is null,
      'detail','contratos get_my_* não se abrem ao VIEWER: coleção, acervo do titular, fichário e painel ficam fechados');
    v_ok := true;
    v_err := null; begin perform public.allocate_physical_cards_to_collection(v_co, array[b1]); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err is not null;
    v_err := null; begin perform public.update_collection_metadata(v_co, 'hack', null); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err is not null;
    v_err := null; begin perform public.archive_collection(v_co); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err is not null;
    v_err := null; begin perform public.invite_collection_member(v_co, 'wh861c_' || v_sfx); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_NOT_FOUND';
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PUBLIC'); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_NOT_FOUND';
    v_err := null; begin perform public.remove_collection_member(v_co, m_b); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'MEMBERSHIP_NOT_FOUND';

    -- Fichário só leitura (5314/5315).
    j := public.get_shared_collection_binder(v_co);
    res := res || jsonb_build_object('id','3.8','ok', (j ->> 'has_binder')::boolean
      and (j ->> 'grid_columns')::int = 3 and (j ->> 'grid_rows')::int = 3
      and (j ->> 'page_count')::int = o_pages and (j ->> 'own_filled_count')::int = o_cards
      and (select bool_and(k = any(array['has_binder','grid_columns','grid_rows','page_count','own_filled_count'])) from jsonb_object_keys(j) k)
      and public.get_shared_collection_binder(v_cx) is null,
      'detail','VIEWER: cabeçalho do fichário de CO (grade, páginas, cartas DE CO) sem local, participantes nem disponíveis; CX fechada');
    select count(*) filter (where b.pocket_state = 'CARD'),
           count(*) filter (where b.pocket_state = 'RESERVED'),
           count(*) filter (where b.pocket_state = 'CARD' and b.card_name is distinct from 'SHR K1'),
           count(*) filter (where b.pocket_state = 'EMPTY'
                              and (b.card_name is not null or b.image_path is not null or b.language_code is not null
                                   or b.collector_number is not null or b.variant_label is not null)),
           count(*) filter (where b.pocket_state not in ('CARD','RESERVED','EMPTY')),
           count(*)
      into b_card, b_res, b_bad, b_leak, b_odd, b_total
    from public.get_shared_collection_binder_pages(v_co, 1, 4) b;
    res := res || jsonb_build_object('id','3.9','ok', b_card = o_cards and b_bad = 0 and b_odd = 0 and b_total = 9,
      'detail','VIEWER: bolsos com carta = só os exemplares de CO (' || b_card || '/' || o_cards || '); x1 de CX nunca aparece; 9 bolsos, 3 estados');
    res := res || jsonb_build_object('id','3.10','ok', b_res = o_res and b_leak = 0
      and not exists (select 1 from public.get_shared_collection_binder_pages(v_co, 1, 4) b where b.card_name = 'SHR K2'),
      'detail','VIEWER: reservas = só as de CO (' || b_res || '/' || o_res || '); bolso vazio/de outra coleção não carrega texto nem imagem; K2 (CX) nunca aparece');
    -- Escrita no fichário pelo VIEWER: toda tentativa recusada (erro ou nenhum efeito);
    -- o estado, conferido como dono do banco logo abaixo, decide.
    v_ok2 := true;
    v_err := null; begin perform public.place_my_physical_card_in_slot(v_co, v_slots[9], b1); exception when others then v_err := sqlerrm; end;
    v_ok2 := v_ok2 and v_err is not null;
    begin perform public.move_slot_assignment(v_slots[1], v_slots[9]); exception when others then null; end;
    begin perform public.remove_slot_assignment(v_slots); exception when others then null; end;
    begin perform public.set_slot_lock(v_slots, true); exception when others then null; end;
    begin perform public.clear_slot_expected_content(v_slots); exception when others then null; end;
    begin perform public.set_slot_expected_content(v_slots[9], k1, null, null, v_co); exception when others then null; end;
    begin perform public.add_layout_page(v_layout); exception when others then null; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.11','ok', v_ok2
      and (select count(*) from public.collection_layout_slot_assignment a
           join public.collection_layout_slot s on s.id = a.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
           where p2.layout_id = v_layout) = asg0
      and (select count(*) from public.collection_layout_slot_expected_content e
           join public.collection_layout_slot s on s.id = e.slot_id join public.collection_layout_page p2 on p2.id = s.page_id
           where p2.layout_id = v_layout) = exp0
      and not exists (select 1 from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
                      where p2.layout_id = v_layout and s.locked)
      and (select count(*) from public.collection_layout_page p2 where p2.layout_id = v_layout) = o_pages
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = b1),
      'detail','VIEWER no fichário: posicionar, mover, tirar, fixar, reservar, limpar reserva e criar página — nada mudou');
    res := res || jsonb_build_object('id','3.6','ok', v_ok
      and (select c3.name from public.collection c3 where c3.id = v_co) = 'CO 5861'
      and (select c3.lifecycle_status from public.collection c3 where c3.id = v_co) = 'ACTIVE'
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_co) = 2
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id = b1),
      'detail','VIEWER: alocar, renomear, arquivar, convidar, publicar e remover recusados; nada mudou');

    -- S-PROG: para cada coleção com referência no banco, sob a identidade do titular.
    v_ok := true; n := 0;
    for c in select c4.id, c4.owner_user_id from public.collection c4 where c4.mode = 'REFERENCE_BASED' loop
      perform set_config('request.jwt.claim.sub', c.owner_user_id::text, true);
      perform set_config('request.jwt.claims', json_build_object('sub', c.owner_user_id, 'role', 'authenticated')::text, true);
      v_ok := v_ok and not exists (
        (select * from public.collection_completion_summary(c.id) except select * from public.collection_completion_summary_shared(c.id))
        union all
        (select * from public.collection_completion_summary_shared(c.id) except select * from public.collection_completion_summary(c.id)));
      n := n + 1;
    end loop;
    res := res || jsonb_build_object('id','3.7','ok', v_ok,
      'detail','S-PROG: progresso compartilhado idêntico ao do titular em ' || n || ' coleção(ões) com referência');

    -- 4. Revogação ------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.get_my_collection_sharing(v_co);
    res := res || jsonb_build_object('id','4.1','ok', j ->> 'visibility' = 'PRIVATE'
      and jsonb_array_length(j -> 'members') = 1 and j -> 'members' -> 0 ->> 'status' = 'ACTIVE'
      and j -> 'members' -> 0 ->> 'username' = n_b and not (j -> 'members' -> 0 ? 'user_id'),
      'detail','painel do titular: B participante, por username (sem id de usuário)');
    j := public.remove_collection_member(v_co, m_b);
    v_err := null; begin perform public.remove_collection_member(v_co, m_b); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.2','ok', j ->> 'outcome' = 'REMOVED' and v_err = 'MEMBERSHIP_NOT_FOUND',
      'detail','titular remove B; repetição → MEMBERSHIP_NOT_FOUND');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','4.3','ok', public.get_shared_collection(v_co) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','remoção revoga na hora: cabeçalho, cartas e lista');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.7','ok', public.get_shared_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','remoção revoga o fichário na hora (cabeçalho NULL, páginas COLLECTION_NOT_FOUND)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    m_b := (public.invite_collection_member(v_co, n_b) ->> 'membership_id')::uuid;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.respond_collection_invite(m_b, false);
    v_err := null; begin perform public.respond_collection_invite(m_b, true); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.4','ok', j ->> 'outcome' = 'DECLINED' and v_err = 'INVITE_NOT_FOUND'
      and public.get_shared_collection(v_co) is null,
      'detail','recusa → DECLINED, sem acesso; aceitar depois de recusar não reabre');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.get_my_collection_sharing(v_co);
    j2 := public.invite_collection_member(v_co, n_b);
    res := res || jsonb_build_object('id','4.5','ok', j -> 'members' -> 0 ->> 'status' = 'DECLINED'
      and j2 ->> 'outcome' = 'REINVITED' and (j2 ->> 'membership_id')::uuid = m_b,
      'detail','titular vê "recusou" e pode convidar de novo (REINVITED, mesma linha)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.respond_collection_invite(m_b, true);
    v_ok := public.get_shared_collection(v_co) ->> 'access' = 'VIEWER';
    j := public.leave_shared_collection(v_co);
    v_err := null; begin perform public.leave_shared_collection(v_co); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.6','ok', v_ok and j ->> 'outcome' = 'LEFT' and v_err = 'NOT_A_MEMBER'
      and public.get_shared_collection(v_co) is null,
      'detail','reaceite → VIEWER; sair → LEFT e acesso revogado; repetição → NOT_A_MEMBER');
    execute 'reset role';

    -- 5. Público ---------------------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    j := public.set_collection_visibility(v_co, 'public');
    j2 := public.set_collection_visibility(v_co, 'PUBLIC');
    res := res || jsonb_build_object('id','5.1','ok', j ->> 'outcome' = 'CHANGED' and j2 ->> 'outcome' = 'UNCHANGED'
      and jsonb_array_length(public.get_my_collection_sharing(v_co) -> 'members') = 0,
      'detail','titular publica (CHANGED, depois UNCHANGED); visibilidade não cria participação');
    execute 'reset role';

    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    j := public.get_public_collection_binder(v_co);
    res := res || jsonb_build_object('id','5.2','ok', (j ->> 'has_binder')::boolean
      and (j ->> 'grid_columns')::int = 3 and (j ->> 'grid_rows')::int = 3 and (j ->> 'page_count')::int = o_pages
      and j ->> 'owner_display_name' = 'WH 5861 A'
      and (select bool_and(k = any(pub_allowed)) from jsonb_object_keys(j) k)
      and public.get_public_collection_binder(v_cx) is null,
      'detail','sem sessão: vitrine de CO (capa, identidade, grade, páginas) só com chaves permitidas — sem progresso, contagem, descrição ou local; CX fechada');
    select count(*) filter (where b.pocket_state = 'CARD'),
           count(*) filter (where b.pocket_state = 'RESERVED'),
           count(*) filter (where b.pocket_state = 'EMPTY'
                              and (b.card_name is not null or b.image_path is not null or b.language_code is not null)),
           count(*)
      into b_card, b_res, b_leak, b_total
    from public.get_public_collection_binder_pages(v_co, 1, 4) b;
    res := res || jsonb_build_object('id','5.8','ok', b_card = o_cards and b_res = o_res and b_leak = 0 and b_total = 9
      and not exists (select 1 from public.get_public_collection_binder_pages(v_co, 1, 4) b where b.card_name = 'SHR K2'),
      'detail','sem sessão: bolsos da vitrine com o MESMO mascaramento do participante — x1 e a reserva de CX (outra coleção do fichário) nunca aparecem');
    v_err := null; begin perform public.get_collections_shared_with_me(); exception when others then v_err := sqlstate; end;
    v_ok := v_err = '42501';
    v_err := null; begin perform public.set_collection_visibility(v_co, 'PRIVATE'); exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','5.3','ok', v_ok and v_err = '42501',
      'detail','sem sessão: listas pessoais e escrita recusadas (42501)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_c::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_c, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null; begin perform public.invite_collection_member(v_co, n_b); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.4','ok', public.get_shared_collection(v_co) is null
      and (select count(*) from public.get_shared_collection_cards(v_co, 48, 0)) = 0
      and public.get_public_collection_binder(v_co) is not null
      and v_err = 'COLLECTION_NOT_FOUND' and jsonb_array_length(public.get_collections_shared_with_me()) = 0,
      'detail','pública ≠ participação: estranho com sessão vê só a vitrine; cabeçalho/galeria do participante fechados; não vira membro, não convida');
    v_err := null; begin perform count(*) from public.get_shared_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.7','ok', public.get_shared_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','coleção PUBLIC não abre o fichário para quem não é participante (decisão conservadora; anon já sem EXECUTE em 1.5)');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    perform public.set_collection_visibility(v_co, 'PRIVATE');
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.5','ok', public.get_public_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','despublicar (PRIVATE) revoga a vitrine na próxima leitura');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    m_b := (public.invite_collection_member(v_cx, n_b) ->> 'membership_id')::uuid;
    perform public.archive_collection(v_cx);
    v_ok := true;
    v_err := null; begin perform public.invite_collection_member(v_cx, 'wh861c_' || v_sfx); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_ARCHIVED';
    v_err := null; begin perform public.set_collection_visibility(v_cx, 'PUBLIC'); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'COLLECTION_ARCHIVED';
    v_ok := v_ok and public.set_collection_visibility(v_cx, 'PRIVATE') ->> 'outcome' = 'UNCHANGED';
    v_ok := v_ok and public.remove_collection_member(v_cx, m_b) ->> 'outcome' = 'REMOVED';
    res := res || jsonb_build_object('id','5.6','ok', v_ok,
      'detail','arquivada: não convida nem publica; remover participação e manter privada seguem possíveis');
    -- 5.9 Arquivar uma coleção publicada tira a vitrine do ar (sem despublicar).
    perform public.set_collection_visibility(v_co, 'PUBLIC');
    v_sl := null; v_ok2 := true;
    begin perform public.archive_collection(v_co); exception when others then v_ok2 := false; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    execute 'set local role anon';
    v_err := null; begin perform count(*) from public.get_public_collection_binder_pages(v_co, 1, 4); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.9','ok', v_ok2 and public.get_public_collection_binder(v_co) is null and v_err = 'COLLECTION_NOT_FOUND',
      'detail','coleção PUBLIC arquivada sai da vitrine na hora (arquivamento aceito = ' || v_ok2 || ')');
    execute 'reset role';

    raise exception 'MS861' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS861' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection where visibility = 'PUBLIC')]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (7 contagens) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if (r ->> 'ok')::boolean then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when (r ->> 'ok')::boolean then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;

-- Executar:
-- select * from pg_temp.wh_5861_validate();
