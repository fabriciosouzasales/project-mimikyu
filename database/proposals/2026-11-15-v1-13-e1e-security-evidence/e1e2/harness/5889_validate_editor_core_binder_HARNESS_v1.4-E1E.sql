/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5889 - Harness V1-13 · E1-B1 (5371–5374): autorização do EDITOR,
              classificação de bolsos, exemplares elegíveis, colocar, mover/trocar,
              retirar, histórico com ator EDITOR, titular intocado, sem efeito
              patrimonial, resíduo zero
Versão......: 1.4-E1E (2026-11-16, `G2_B v2 LIVE FAIL — CONSOLIDATED HARNESS CORRECTION-01`, só o harness):
              C1: caminho da imagem de bolso da fixture passa a <dono>/<fichário>/<uuid>.webp
              (gen_random_uuid), como exigem chk_collection_layout_slot_image_path_format e
              _path_owner (5232); o nome literal "wh589N.webp" violava o CHECK (23514 no
              G2_B v2 LIVE, TXID 815477) na 10.1. A 10.2 passa a exigir a fixture (página 2 com
              imagem em r1c1 e mesclagem r2c1–r2c2) antes de aceitar SLOT_NOT_EDITABLE: no LIVE ela
              passou sem a página 2 (falso positivo). Linhas "-- E1E". Nenhum critério enfraquecido.
              1.3-E1E (2026-11-16, `G2_B/G2_C — MGMTAPI READINESS CORRECTION-01`, só o harness):
              conferências internas de estado (classe B) que liam tabelas de fichário,
              histórico, alocação ou referências sob o papel do CLIENTE (EDITOR/estranho)
              passam a ler no contexto do dono (reset role → instrução → wh_5889_as do mesmo
              usuário). Sob o cliente, a RLS "select_own" devolvia vazio (resultado falso) e
              as tabelas revogadas (histórico, referências) dariam 42501. Linhas "-- E1E".
              Chamadas às RPCs (classe A) e negativas (classe C) intactas; nenhuma
              verificação removida, nenhum critério alterado. Original preservado.
              1.2 (2026-11-15, `V1-13 / E1-B3 | HISTORY INTEGRITY REVIEW-02`: 0.4 aceita
              a gravação da 5372 ou a da 5379, que a estende, para a 5889 continuar
              válida como regressão depois da E1-B3). 1.1 (2026-11-15,
              `CORE BINDER SECURITY REVIEW-02`: seção 10 — imagem, mesclagem, estado
              composto e convidada arquivada). 1.0 (2026-11-15)
Status......: PROPOSTA — NÃO EXECUTADA. Prova DINÂMICA da E1-B1. Sem ambiente
              isolado (C-244): executar SOMENTE sob protocolo controlado
              equivalente ao P1 da E1-A (transação explícita READ WRITE
              terminada em erro/ROLLBACK, conexão direta única, psql), depois da
              E1-A, com autorização expressa e específica. Este arquivo não tem
              BEGIN/COMMIT e não é comando pronto para produção.
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-15

Pressupõe aplicadas (na mesma transação do ensaio ou antes): E1-A 5366–5370
e E1-B1 5371–5374.

Protocolo (o da 5861/5888): uma chamada; usuários efêmeros
  A titular · B EDITOR de CO · V VIEWER de CO · E EDITOR de CX
  R EDITOR de CO depois removido · C estranho (com exemplar próprio b1)
catálogo SINTÉTICO (K1, K2, K3); sentinela MS889 desfaz a fixture por
subtransação; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5889_validate();
  -- GATE esperado: 56/56 PASS (55 verificações + F.2)

Fixture (fichário 3×3 de CO, CX convidada, página 1):
  r1c1 a1 (CO)        r1c2 x1 (CX)          r1c3 reserva de CX (K3)
  r2c1 reserva de CO  r2c2 FIXADO e vazio   r2c3 livre
  r3c1 livre          r3c2 livre            r3c3 livre
  No local do fichário: a1, a2, a5 (CO), a4 (sem coleção), x1, x2 (CX).
  Em OUTRO local: a3 (CO). Acervo de C: b1.

Seções:
  0  estrutura: internas sem EXECUTE; RPCs só authenticated; titular e 5122
     intactos; 5268 com a mudança mínima
  1  autorização: EDITOR, VIEWER, estranho, anon, titular no caminho do EDITOR,
     ex-EDITOR, EDITOR de outra coleção, troca de papel imediata
  2  exemplares elegíveis: só alocado + no fichário + fora de bolso; sem
     colunas privadas; não EDITOR → zero linhas
  3  colocar: bolsos de terceiros (carta, reserva, fixado vazio, inexistente)
     com a MESMA recusa; exemplar inelegível (outro local, sem coleção, outra
     coleção, alheio, forjado) com a MESMA recusa; UNCHANGED; já posicionado;
     reserva própria; REPLACE só de X
  4  mover/trocar: dentro de X; nunca de/para terceiros; origem sem carta
  5  retirar: só X; posição sai, alocação/local/acervo ficam
  6  fichário com várias coleções: EDITOR de CX atua só em CX
  7  histórico: ator EDITOR, coleção registrada; internas fora da API
  8  titular: 5272–5274 seguem funcionando sobre qualquer bolso
  9  patrimônio: alocações, locais, exemplares e participações intactos
  99 resíduo zero

Limitações declaradas:
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST.
  L2 Imagem personalizada e região mesclada: exercitadas na seção 10 (inseridas
     por passo privilegiado, com os gatilhos de integridade 5232/5238 ativos).
     Referência de espécie: só por inspeção — o gatilho 5257 exige coleção
     proprietária Pokédex com posições reais; a fixture Pokédex pertence à
     E1-B3 (dependência de fixture, não vulnerabilidade da E1-B1).
  L3 Concorrência real titular × EDITOR (S10) e troca de papel durante a
     escrita (S8 concorrente) exigem duas sessões com dados confirmados —
     PENDENTES (VALIDATION-STRATEGY-E1A.md §4).
  L4 Coleção arquivada: exercitada na seção 10.4 (convidada arquivada). A
     proprietária arquivada fica por inspeção (5371, passo 3).
================================================================
*/

create or replace function pg_temp.wh_5889_as(p_user uuid)
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

create or replace function pg_temp.wh_5889_slot(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $sl$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = 1 and s.row_index = p_row and s.column_index = p_col;
$sl$;

create or replace function pg_temp.wh_5889_at(p_layout uuid, p_row integer, p_col integer)
returns uuid language sql stable as $at$
  -- exemplar no bolso (page 1, row, col), ou NULL
  select a.physical_card_id from public.collection_layout_slot_assignment a
  where a.slot_id = pg_temp.wh_5889_slot(p_layout, p_row, p_col);
$at$;

create or replace function pg_temp.wh_5889_slotp(p_layout uuid, p_page integer, p_row integer, p_col integer)
returns uuid language sql stable as $sp$
  select s.id from public.collection_layout_slot s
  join public.collection_layout_page p on p.id = s.page_id
  where p.layout_id = p_layout and p.page_number = p_page and s.row_index = p_row and s.column_index = p_col;
$sp$;

create or replace function pg_temp.wh_5889_try(p_sql text)
returns text language plpgsql volatile as $try$
begin
  execute p_sql;
  return 'OK';
exception when others then
  return sqlerrm;
end;
$try$;

create or replace function pg_temp.wh_5889_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_auth oid := to_regprocedure('public.assert_collection_binder_editor(uuid)');
  f_scp  oid := to_regprocedure('public.binder_slot_editor_scope(uuid, uuid, uuid, uuid)');
  f_at   oid := to_regprocedure('public.binder_slot_at(uuid, integer, integer, integer)');
  f_rd   oid := to_regprocedure('public.get_shared_binder_placeable_cards(uuid, integer, integer)');
  f_pl   oid := to_regprocedure('public.editor_place_card_in_binder(uuid, integer, integer, integer, uuid)');
  f_mv   oid := to_regprocedure('public.editor_move_binder_card(uuid, integer, integer, integer, integer, integer, integer)');
  f_rm   oid := to_regprocedure('public.editor_remove_binder_card(uuid, integer, integer, integer)');
  u_a uuid := gen_random_uuid(); u_b uuid := gen_random_uuid(); u_v uuid := gen_random_uuid();
  u_e uuid := gen_random_uuid(); u_r uuid := gen_random_uuid(); u_c uuid := gen_random_uuid();
  v_sfx text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid; v_exp uuid; v_set uuid;
  k1 uuid; k1s uuid; k2 uuid; k2s uuid; k3 uuid; k3s uuid;
  v_inv_a uuid; v_inv_c uuid;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; x1 uuid; x2 uuid; b1 uuid;
  v_bin uuid; v_other uuid; v_co uuid; v_cx uuid; v_layout uuid; v_lc uuid;
  m_b uuid; m_v uuid; m_e uuid; m_r uuid; v_pc uuid;
  p record; j jsonb; v_err text; v_ok boolean; n integer; n2 integer; v_ids uuid[];
  alloc0 text; stor0 text; pc0 bigint; mem0 text; ev0 bigint;
  b_counts bigint[]; e_counts bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 56;
begin
  -- 0. Estrutura -------------------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_auth is not null and f_scp is not null and f_at is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                         and not has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         and not has_function_privilege('anon', q.oid, 'EXECUTE')
                         and not has_function_privilege('service_role', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_auth, f_scp, f_at)),
    'detail','5371: três funções internas, definer, search_path vazio, sem EXECUTE para API nem service_role');
  res := res || jsonb_build_object('id','0.2','ok',
    f_rd is not null and f_pl is not null and f_mv is not null and f_rm is not null
    and (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                         and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                         and not has_function_privilege('anon', q.oid, 'EXECUTE'))
           from pg_proc q where q.oid in (f_rd, f_pl, f_mv, f_rm)),
    'detail','5373/5374: leitura e três escritas do EDITOR, definer, search_path vazio, só authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.assert_collection_layout_mutable(uuid)')) = 'd600f36fade0b67c0fd5af33e9965070'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.place_my_physical_card_in_slot(uuid, uuid, uuid)')) = '2672da179d73797ec5329c649b594202'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.move_slot_assignment(uuid, uuid)')) = 'fe149c755b5f3b9181172e600c2238a3'
    and (select md5(q.prosrc) from pg_proc q where q.oid = to_regprocedure('public.remove_slot_assignment(uuid[])')) = 'e4b6c8cd8e8c61554ddc92304d602a73',
    'detail','5122 e funções do titular 5272–5274 byte a byte canônicas');
  res := res || jsonb_build_object('id','0.4','ok',
    (select md5(q.prosrc) from pg_proc q
      where q.oid = to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'))
        in ('59ec5791e514026b7a8340e104d66f30',   -- 5372 (estágio E1-B1/E1-B2)
            'f8cfba40e442e85056e7c8ce7954d4f4')   -- 5379 (E1-B3: mesma regra do ator + coleção por item)
    and not has_function_privilege('authenticated', to_regprocedure('public.binder_activity_add_item(text, text, uuid, uuid, uuid, uuid, integer, integer, jsonb)'), 'EXECUTE')
    and not has_function_privilege('authenticated', to_regprocedure('public.binder_activity_begin(uuid, text, text, uuid, jsonb)'), 'EXECUTE'),
    'detail','gravação do histórico da 5372 (ou da 5379, que a estende); continua sem EXECUTE para a API');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout_slot_assignment), (select count(*) from public.binder_activity_event)]
    into b_counts;

  begin
    -- F. Fixture -------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS889' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'EB1_' || upper(v_sfx), 'EB1 Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'EB1' || upper(v_sfx), 'EB1 Set ' || v_sfx, 'REGULAR', 1, 3, 3) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'EB1 K1', true) returning id into k1;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '2', 2, 'EB1 K2', true) returning id into k2;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '3', 3, 'EB1 K3', true) returning id into k3;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k1, v_std, 1, true) returning id into k1s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k2, v_std, 1, true) returning id into k2s;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default) values (k3, v_std, 1, true) returning id into k3s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    select u.id, 'authenticated', 'authenticated', 'wh889' || u.t || '_' || v_sfx || '@example.invalid',
           jsonb_build_object('username', 'wh889' || u.t || '_' || v_sfx, 'display_name', 'WH 5889 ' || upper(u.t)), now(), now()
    from (values (u_a, 'a'), (u_b, 'b'), (u_v, 'v'), (u_e, 'e'), (u_r, 'r'), (u_c, 'c')) u(id, t);
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_c from public.inventory i where i.owner_user_id = u_c;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at)
    select v.cv, v_pt, v_inv_a, now() - (v.o || ' min')::interval
    from (values (k1s, 7), (k1s, 6), (k1s, 5), (k2s, 4), (k1s, 3), (k3s, 2), (k3s, 1)) v(cv, o);
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    a1 := v_ids[1]; a2 := v_ids[2]; a3 := v_ids[3]; a4 := v_ids[4]; a5 := v_ids[5]; x1 := v_ids[6]; x2 := v_ids[7];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_c) returning id into b1;

    perform pg_temp.wh_5889_as(u_a);
    select x.storage_container_id into v_bin from public.create_my_storage_container(gen_random_uuid(), 'BIN 5889', 'BINDER') x;
    select x.storage_container_id into v_other from public.create_my_storage_container(gen_random_uuid(), 'BOX 5889', 'BOX') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5889', v_bin) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[a1, a2, a3, a5]);
    select * into p from public.preview_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 3, 3, 'PRINCIPAL_ONLY', p.plan_token);
    execute 'reset role';
    select l.id, l.storage_container_id into v_layout, v_lc from public.collection_layout l where l.collection_id = v_co;
    -- CX nasce com o local físico do fichário como padrão (exigência da associação, 5255).
    perform pg_temp.wh_5889_as(u_a);
    select x.collection_id into v_cx from public.create_my_free_collection(gen_random_uuid(), 'CX 5889', v_lc) x;
    perform public.allocate_physical_cards_to_collection(v_cx, array[x1, x2]);
    execute 'reset role';
    -- Normaliza o fichário (passo privilegiado, como o catálogo): sem posições/reservas da montagem.
    delete from public.collection_layout_slot_assignment a using public.collection_layout_slot s, public.collection_layout_page p2
     where a.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    delete from public.collection_layout_slot_expected_content e using public.collection_layout_slot s, public.collection_layout_page p2
     where e.slot_id = s.id and s.page_id = p2.id and p2.layout_id = v_layout;
    update public.physical_card pc set storage_container_id = v_lc where pc.id in (a1, a2, a4, a5, x1, x2);
    update public.physical_card pc set storage_container_id = v_other where pc.id = a3;
    perform pg_temp.wh_5889_as(u_a);
    perform public.attach_my_collection_to_binder(v_cx, v_layout);
    perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5889_slot(v_layout, 1, 1), a1);
    perform public.place_my_physical_card_in_slot(v_cx, pg_temp.wh_5889_slot(v_layout, 1, 2), x1);
    perform public.set_slot_expected_content(pg_temp.wh_5889_slot(v_layout, 1, 3), k3, null, null, v_cx);
    perform public.set_slot_expected_content(pg_temp.wh_5889_slot(v_layout, 2, 1), k1, null, null, v_co);
    perform public.set_slot_lock(array[pg_temp.wh_5889_slot(v_layout, 2, 2)], true);
    m_b := (public.invite_collection_member(v_co, 'wh889b_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_v := (public.invite_collection_member(v_co, 'wh889v_' || v_sfx) ->> 'membership_id')::uuid;
    m_r := (public.invite_collection_member(v_co, 'wh889r_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    m_e := (public.invite_collection_member(v_cx, 'wh889e_' || v_sfx, 'EDITOR') ->> 'membership_id')::uuid;
    perform pg_temp.wh_5889_as(u_b); perform public.respond_collection_invite(m_b, true);
    perform pg_temp.wh_5889_as(u_v); perform public.respond_collection_invite(m_v, true);
    perform pg_temp.wh_5889_as(u_r); perform public.respond_collection_invite(m_r, true);
    perform pg_temp.wh_5889_as(u_e); perform public.respond_collection_invite(m_e, true);
    perform pg_temp.wh_5889_as(u_a); perform public.remove_collection_member(v_co, m_r);
    execute 'reset role';
    select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id) into alloc0
      from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, a4, a5, x1, x2, b1);
    select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id) into stor0
      from public.physical_card pc where pc.id in (a1, a2, a3, a4, a5, x1, x2, b1);
    select count(*) into pc0 from public.physical_card pc where pc.inventory_id in (v_inv_a, v_inv_c);
    select string_agg(m.id::text || ':' || m.role || ':' || m.status, ',' order by m.id) into mem0
      from public.collection_membership m where m.collection_id in (v_co, v_cx);
    select count(*) into ev0 from public.binder_activity_event e where e.layout_key = v_layout;
    res := res || jsonb_build_object('id','F.2','ok',
      v_lc is not null and pg_temp.wh_5889_at(v_layout, 1, 1) = a1 and pg_temp.wh_5889_at(v_layout, 1, 2) = x1
      and (select count(*) from public.collection_layout_slot s join public.collection_layout_page p2 on p2.id = s.page_id
            where p2.layout_id = v_layout and p2.page_number = 1) = 9
      and exists (select 1 from public.collection_layout_guest g where g.layout_id = v_layout and g.collection_id = v_cx),
      'detail','fixture: fichário 3×3 de CO com CX convidada; carta, reserva e trava nos bolsos previstos');

    -- 1. Autorização -----------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_v);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.1','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','VIEWER não escreve: ' || v_err);
    perform pg_temp.wh_5889_as(u_c);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.2','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','estranho não escreve: ' || v_err);
    perform pg_temp.wh_5889_as(u_a);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.3','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','titular não usa o caminho do EDITOR: ' || v_err);
    perform pg_temp.wh_5889_as(u_r);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.4','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','EDITOR removido não escreve: ' || v_err);
    perform pg_temp.wh_5889_as(u_e);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.5','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','EDITOR de CX não escreve em CO, mesmo fichário: ' || v_err);
    perform pg_temp.wh_5889_as(null);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','1.6','ok', v_err like 'permission denied%', 'detail','anon sem EXECUTE: ' || v_err);
    perform pg_temp.wh_5889_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'VIEWER');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, a2));
    perform pg_temp.wh_5889_as(u_a); perform public.set_collection_member_role(v_co, m_b, 'EDITOR');
    res := res || jsonb_build_object('id','1.7','ok', v_err = 'COLLECTION_NOT_FOUND' and pg_temp.wh_5889_at(v_layout, 3, 1) is null,
      'detail','EDITOR rebaixado a VIEWER perde a escrita na hora: ' || v_err);

    -- 2. Exemplares elegíveis ----------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_b);
    select array_agg(x.physical_card_id order by x.physical_card_id), max(x.total_count) into v_ids, n
      from public.get_shared_binder_placeable_cards(v_co, 96, 0) x;
    res := res || jsonb_build_object('id','2.1','ok',
      v_ids = (select array_agg(y order by y) from unnest(array[a2, a5]) y) and n = 2,
      'detail','lista do EDITOR = a2 e a5 (alocados a CO, no fichário, fora de bolso); nunca a1 (no bolso), a3 (outro local), a4 (sem coleção), x1/x2 (CX)');
    res := res || jsonb_build_object('id','2.2','ok',
      not exists (select 1 from pg_proc q, unnest(q.proargnames, q.proargmodes) a(name, mode)
                  where q.oid = f_rd and a.mode = 't'
                    and a.name ~ '(storage|location|condition|price|value|paid|acqui|note|favorite|wish|owner|collection|allocation)'),
      'detail','leitura sem colunas de local, condição, valores, aquisição, favoritos, wishlist, titular ou alocação');
    perform pg_temp.wh_5889_as(u_v); n := (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_c); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_a); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_r); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    perform pg_temp.wh_5889_as(u_e); n := n + (select count(*) from public.get_shared_binder_placeable_cards(v_co, 96, 0));
    res := res || jsonb_build_object('id','2.3','ok', n = 0,
      'detail','VIEWER, estranho, titular, ex-EDITOR e EDITOR de outra coleção recebem zero linhas');
    perform pg_temp.wh_5889_as(u_e);
    select array_agg(x.physical_card_id) into v_ids from public.get_shared_binder_placeable_cards(v_cx, 96, 0) x;
    res := res || jsonb_build_object('id','2.4','ok', v_ids = array[x2],
      'detail','EDITOR de CX vê só x2 (de CX, no fichário, fora de bolso)');

    -- 3. Colocar --------------------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 2, %L)', v_co, a2));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','3.1','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1,
      'detail','bolso com carta de CX → SLOT_NOT_EDITABLE; x1 intacto');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 1, 3, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.2','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','bolso "vazio" com reserva de CX → mesma recusa');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 2, 2, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.3','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','bolso fixado e vazio → mesma recusa (não revela a trava)');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 99, 1, 1, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.4','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','posição inexistente → mesma recusa');
    v_err := '';
    foreach v_pc in array array[a3, a4, x2, b1, gen_random_uuid()] loop
      v_err := v_err || pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 1, %L)', v_co, v_pc)) || ';';
    end loop;
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','3.5','ok',
      v_err = repeat('PHYSICAL_CARD_NOT_ELIGIBLE;', 5) and pg_temp.wh_5889_at(v_layout, 3, 1) is null,
      'detail','outro local, sem coleção, de CX, de outro titular e forjado → a MESMA recusa; nada posicionado');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 3, 1, a2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.6','ok', v_err = 'ADD' and pg_temp.wh_5889_at(v_layout, 3, 1) = a2,
      'detail','a2 colocado num bolso livre (ADD)');
    perform pg_temp.wh_5889_as(u_b);
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 3, 1, a2) x;
    res := res || jsonb_build_object('id','3.7','ok', v_err = 'UNCHANGED', 'detail','mesmo bolso → UNCHANGED');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 1, 3, 2, %L)', v_co, a2));
    res := res || jsonb_build_object('id','3.8','ok', v_err = 'CARD_ALREADY_PLACED', 'detail','exemplar já em outro bolso → CARD_ALREADY_PLACED');
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 2, 1, a5) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.9','ok', v_err = 'ADD' and pg_temp.wh_5889_at(v_layout, 2, 1) = a5
      and exists (select 1 from public.collection_layout_slot_expected_content e where e.slot_id = pg_temp.wh_5889_slot(v_layout, 2, 1)),
      'detail','bolso com reserva de CO aceita a carta; a reserva continua no bolso');
    perform pg_temp.wh_5889_as(u_b);
    perform public.editor_remove_binder_card(v_co, 1, 2, 1);
    select x.operation into v_err from public.editor_place_card_in_binder(v_co, 1, 1, 1, a5) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.10','ok', v_err = 'REPLACE' and pg_temp.wh_5889_at(v_layout, 1, 1) = a5
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a1),
      'detail','REPLACE de carta de CO: a1 sai do bolso, a5 entra');

    -- 4. Mover / trocar ---------------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_b);
    select x.operation into v_err from public.editor_move_binder_card(v_co, 1, 3, 1, 1, 3, 2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', v_err = 'MOVE' and pg_temp.wh_5889_at(v_layout, 3, 2) = a2 and pg_temp.wh_5889_at(v_layout, 3, 1) is null,
      'detail','MOVE de a2 entre bolsos livres/próprios');
    perform pg_temp.wh_5889_as(u_b);
    select x.operation into v_err from public.editor_move_binder_card(v_co, 1, 3, 2, 1, 1, 1) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok', v_err = 'SWAP' and pg_temp.wh_5889_at(v_layout, 1, 1) = a2 and pg_temp.wh_5889_at(v_layout, 3, 2) = a5,
      'detail','SWAP entre duas cartas de CO');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 1, 2)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','4.3','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1 and pg_temp.wh_5889_at(v_layout, 1, 1) = a2,
      'detail','trocar com carta de CX → SLOT_NOT_EDITABLE; nada muda');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 2, 1, 3, 3)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','4.4','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1,
      'detail','mover carta de CX → SLOT_NOT_EDITABLE');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 1, 3)', v_co));
    res := res || jsonb_build_object('id','4.5','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','mover para bolso com reserva de CX → SLOT_NOT_EDITABLE');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 2, 2)', v_co));
    res := res || jsonb_build_object('id','4.6','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','mover para bolso fixado vazio → SLOT_NOT_EDITABLE');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 2, 1, 1, 3, 3)', v_co));
    res := res || jsonb_build_object('id','4.7','ok', v_err = 'SLOT_EMPTY', 'detail','origem só com reserva de CO → SLOT_EMPTY');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 3, 3, 1, 3, 1)', v_co));
    res := res || jsonb_build_object('id','4.8','ok', v_err = 'SLOT_NOT_EDITABLE', 'detail','origem livre (sem nada) → SLOT_NOT_EDITABLE');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 1, 1, 1)', v_co));
    res := res || jsonb_build_object('id','4.9','ok', v_err = 'INVALID_ARGUMENT', 'detail','origem = destino → INVALID_ARGUMENT');

    -- 5. Retirar ----------------------------------------------------------------------------------
    select x.operation into v_err from public.editor_remove_binder_card(v_co, 1, 3, 2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok', v_err = 'REMOVED' and pg_temp.wh_5889_at(v_layout, 3, 2) is null
      and exists (select 1 from public.collection_allocation ca where ca.physical_card_id = a5 and ca.collection_id = v_co)
      and (select pc.storage_container_id from public.physical_card pc where pc.id = a5) = v_lc,
      'detail','retirar a5: posição sai; alocação a CO e local do fichário ficam');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 1, 2)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','5.2','ok', v_err = 'SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 2) = x1,
      'detail','retirar carta de CX → SLOT_NOT_EDITABLE; x1 fica');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 2, 1)', v_co));
    n := 0; if v_err = 'SLOT_EMPTY' then n := 1; end if;
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 3, 3)', v_co));
    res := res || jsonb_build_object('id','5.3','ok', n = 1 and v_err = 'SLOT_NOT_EDITABLE',
      'detail','retirar de bolso só com reserva de CO → SLOT_EMPTY; de bolso livre → SLOT_NOT_EDITABLE');
    perform pg_temp.wh_5889_as(u_v);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 1, 1)', v_co));
    res := res || jsonb_build_object('id','5.4','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','VIEWER não retira');

    -- 6. Várias coleções: EDITOR de CX --------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_e);
    select x.operation into v_err from public.editor_place_card_in_binder(v_cx, 1, 3, 3, x2) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.1','ok', v_err = 'ADD' and pg_temp.wh_5889_at(v_layout, 3, 3) = x2,
      'detail','EDITOR de CX (convidada) coloca x2 num bolso livre do fichário compartilhado');
    perform pg_temp.wh_5889_as(u_e);
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 1, 1)', v_cx))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 3, 3, 1, 2, 1)', v_cx));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','6.2','ok', v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE' and pg_temp.wh_5889_at(v_layout, 1, 1) = a2,
      'detail','EDITOR de CX não retira carta de CO nem move para bolso com reserva de CO');
    perform pg_temp.wh_5889_as(u_e);  -- E1E: volta ao mesmo cliente
    select x.operation into v_err from public.editor_move_binder_card(v_cx, 1, 1, 2, 1, 1, 3) x;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.3','ok', v_err = 'MOVE' and pg_temp.wh_5889_at(v_layout, 1, 3) = x1
      and exists (select 1 from public.collection_layout_slot_expected_content e
                  where e.slot_id = pg_temp.wh_5889_slot(v_layout, 1, 3) and e.collection_id = v_cx),
      'detail','EDITOR de CX move x1 para o bolso reservado para CX; a reserva fica');

    -- 7. Histórico ------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','7.1','ok',
      (select count(*) from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_b) >= 6
      and not exists (select 1 from public.binder_activity_event e
                      where e.layout_key = v_layout and e.actor_user_id = u_b
                        and (e.owner_user_id <> u_a or e.collection_id is distinct from v_co))
      and not exists (select 1 from public.binder_activity_event e
                      where e.layout_key = v_layout and e.actor_user_id = u_e
                        and (e.owner_user_id <> u_a or e.collection_id is distinct from v_cx)),
      'detail','eventos do EDITOR: titular A como dono do evento, ator EDITOR, coleção autorizada registrada');
    res := res || jsonb_build_object('id','7.2','ok',
      not exists (select 1 from public.binder_activity_event e
                  where e.layout_key = v_layout and e.actor_user_id in (u_v, u_c, u_r)),
      'detail','nenhuma tentativa recusada gerou evento');
    perform pg_temp.wh_5889_as(u_b);
    v_err := pg_temp.wh_5889_try(format('select public.binder_activity_begin(%L, %L, %L, %L)', v_layout, 'CARD_PLACED', 'FICHARIO', v_co))
          || ';' || pg_temp.wh_5889_try(format('select public.assert_collection_binder_editor(%L)', v_co))
          || ';' || pg_temp.wh_5889_try(format('select public.binder_slot_editor_scope(%L, %L, %L, %L)', v_layout, v_co, v_co, gen_random_uuid()));
    res := res || jsonb_build_object('id','7.3','ok', v_err ~ '^permission denied.*;permission denied.*;permission denied',
      'detail','internas (histórico, autorização, classificação) fora do alcance direto do EDITOR');

    -- 8. Titular intocado ------------------------------------------------------------------------------
    perform pg_temp.wh_5889_as(u_a);
    perform public.move_slot_assignment(pg_temp.wh_5889_slot(v_layout, 1, 3), pg_temp.wh_5889_slot(v_layout, 2, 3));
    perform public.remove_slot_assignment(array[pg_temp.wh_5889_slot(v_layout, 2, 3)]);
    perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5889_slot(v_layout, 3, 1), a1);
    execute 'reset role';
    res := res || jsonb_build_object('id','8.1','ok',
      pg_temp.wh_5889_at(v_layout, 2, 3) is null and pg_temp.wh_5889_at(v_layout, 3, 1) = a1
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = x1),
      'detail','titular continua movendo e retirando carta de CX e colocando carta de CO (5272–5274)');
    res := res || jsonb_build_object('id','8.2','ok',
      exists (select 1 from public.binder_activity_event e where e.layout_key = v_layout and e.actor_user_id = u_a
              and e.event_type = 'CARD_PLACED' and e.collection_id = v_co),
      'detail','eventos do titular seguem com o titular como ator');

    -- 9. Patrimônio ------------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','9.1','ok',
      (select string_agg(ca.physical_card_id::text || ':' || ca.collection_id::text, ',' order by ca.physical_card_id)
         from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, a4, a5, x1, x2, b1)) = alloc0,
      'detail','alocações intactas');
    res := res || jsonb_build_object('id','9.2','ok',
      (select string_agg(pc.id::text || ':' || coalesce(pc.storage_container_id::text, '-'), ',' order by pc.id)
         from public.physical_card pc where pc.id in (a1, a2, a3, a4, a5, x1, x2, b1)) = stor0
      and (select count(*) from public.physical_card pc where pc.inventory_id in (v_inv_a, v_inv_c)) = pc0,
      'detail','locais físicos e exemplares intactos (nada excluído, nada movido de local)');
    res := res || jsonb_build_object('id','9.3','ok',
      (select string_agg(m.id::text || ':' || m.role || ':' || m.status, ',' order by m.id)
         from public.collection_membership m where m.collection_id in (v_co, v_cx)) = mem0
      and (select c.owner_user_id from public.collection c where c.id = v_co) = u_a,
      'detail','participações e titularidade intactas');
    res := res || jsonb_build_object('id','9.4','ok',
      not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id in (a3, a4, b1)),
      'detail','nenhum exemplar inelegível chegou a um bolso');

    -- 10. Estados compostos e coleção arquivada (REVIEW-02) ------------------------------------------
    -- Página 2 (titular). Imagem e região inseridas por passo privilegiado, como o catálogo:
    -- os gatilhos de integridade (5232/5238) continuam valendo; o caminho de escrita delas
    -- (imagens do titular, mesclagem) não é objeto da E1-B1.
    v_err := 'OK';
    begin
      perform pg_temp.wh_5889_as(u_a);
      perform public.add_layout_page(v_layout);
      execute 'reset role';
      insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
      values (pg_temp.wh_5889_slotp(v_layout, 2, 1, 1), u_a, u_a::text || '/' || v_layout::text || '/' || gen_random_uuid()::text || '.webp');  -- E1E: C1 — caminho canônico (uuid), atende aos CHECKs 5232
      insert into public.collection_layout_region (page_id, top_row, left_column, height, width)
      values ((select p2.id from public.collection_layout_page p2 where p2.layout_id = v_layout and p2.page_number = 2), 2, 1, 1, 2);
    exception when others then
      v_err := sqlerrm;
    end;
    execute 'reset role';
    perform pg_temp.wh_5889_as(u_b);
    select count(*) filter (where x.pocket_state = 'EMPTY'
                              and (x.row_index, x.column_index) in ((1, 1), (2, 1), (2, 2))) into n
      from public.get_shared_collection_binder_pages(v_co, 2, 1) x;
    res := res || jsonb_build_object('id','10.1','ok', v_err = 'OK' and n = 3,
      'detail','fixture página 2 (' || v_err || '): para o EDITOR, os bolsos com imagem (r1c1) e com mesclagem (r2c1–r2c2) aparecem como vazios');
    v_err := pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 2, 1, 1, %L)', v_co, a5))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 2, 2, 2, %L)', v_co, a5))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 2, 1, 1)', v_co))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 1, 1, 1, 2, 2, 1)', v_co));
    execute 'reset role';  -- E1E: conferência interna (classe B) no contexto do dono
    res := res || jsonb_build_object('id','10.2','ok',
      v_err = 'SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE'
      and pg_temp.wh_5889_at(v_layout, 1, 1) = a2
      and exists (select 1 from public.collection_layout_slot_image ximg  -- E1E: pré-condição — a fixture existe: página 2 com imagem em r1c1
                  where ximg.slot_id = pg_temp.wh_5889_slotp(v_layout, 2, 1, 1))  -- E1E
      and exists (select 1 from public.collection_layout_region xreg join public.collection_layout_page xpg on xpg.id = xreg.page_id  -- E1E: e mesclagem r2c1–r2c2
                  where xpg.layout_id = v_layout and xpg.page_number = 2 and xreg.top_row = 2 and xreg.left_column = 1  -- E1E
                    and xreg.height = 1 and xreg.width = 2)  -- E1E
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.physical_card_id = a5),
      'detail','bolso "vazio" com imagem ou em mesclagem: colocar e mover recusam com a mesma SLOT_NOT_EDITABLE; nada muda');
    perform pg_temp.wh_5889_as(u_b);  -- E1E: volta ao mesmo cliente
    -- Estado composto: carta de CO + reserva de CX no mesmo bolso (titular monta).
    v_err := 'OK';
    begin
      perform pg_temp.wh_5889_as(u_a);
      perform public.set_slot_expected_content(pg_temp.wh_5889_slotp(v_layout, 2, 3, 1), k3, null, null, v_cx);
      perform public.place_my_physical_card_in_slot(v_co, pg_temp.wh_5889_slotp(v_layout, 2, 3, 1), a5);
    exception when others then
      v_err := sqlerrm;
    end;
    perform pg_temp.wh_5889_as(u_b);
    v_err := v_err || ';' || pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 2, 3, 1)', v_co))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_move_binder_card(%L, 2, 3, 1, 1, 3, 1)', v_co));
    perform pg_temp.wh_5889_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5889_try(format('select * from public.editor_place_card_in_binder(%L, 2, 3, 1, %L)', v_cx, x1))
          || ';' || pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 2, 3, 1)', v_cx));
    execute 'reset role';
    res := res || jsonb_build_object('id','10.3','ok',
      v_err = 'OK;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE;SLOT_NOT_EDITABLE'
      and (select a.physical_card_id from public.collection_layout_slot_assignment a
            where a.slot_id = pg_temp.wh_5889_slotp(v_layout, 2, 3, 1)) = a5,
      'detail','carta de CO + reserva de CX no mesmo bolso: nem o EDITOR de CO nem o de CX alteram (' || v_err || ')');
    -- Coleção arquivada (convidada CX).
    v_err := 'OK';
    begin
      perform pg_temp.wh_5889_as(u_a);
      perform public.archive_collection(v_cx);
    exception when others then
      v_err := sqlerrm;
    end;
    perform pg_temp.wh_5889_as(u_e);
    v_err := v_err || ';' || pg_temp.wh_5889_try(format('select * from public.editor_remove_binder_card(%L, 1, 3, 3)', v_cx));
    n := (select count(*) from public.get_shared_binder_placeable_cards(v_cx, 96, 0));
    execute 'reset role';
    res := res || jsonb_build_object('id','10.4','ok', v_err = 'OK;COLLECTION_ARCHIVED' and n = 0
      and pg_temp.wh_5889_at(v_layout, 3, 3) = x2,
      'detail','convidada arquivada: EDITOR de CX recebe COLLECTION_ARCHIVED e lista vazia; x2 fica (' || v_err || ')');

    execute 'reset role';
    raise exception 'MS889' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS889' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_membership), (select count(*) from public.card),
               (select count(*) from public.collection_layout_slot_assignment), (select count(*) from public.binder_activity_event)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (8 contagens) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    cnt := cnt + 1;
    if coalesce((r ->> 'ok')::boolean, false) then passes := passes + 1; end if;
    seq := cnt; check_id := r ->> 'id';
    status := case when coalesce((r ->> 'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r ->> 'detail';
    return next;
  end loop;
  seq := cnt + 1; check_id := 'GATE';
  status := case when passes = cnt and cnt = v_expected then 'PASS' else 'FAIL' end;
  detail := passes || '/' || cnt || ' PASS (esperado ' || v_expected || ')';
  return next;
end;
$fn$;

-- Execução: somente sob protocolo controlado (C-244), com autorização específica.
-- Chamada: select * from pg_temp.wh_5889_validate();
