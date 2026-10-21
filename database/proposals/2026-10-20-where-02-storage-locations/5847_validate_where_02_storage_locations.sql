/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5847 - Harness WHERE-02 (5212–5219): estrutura, segurança,
              criação idempotente, renomear/tipo, leitura com contagens,
              exclusão segura, R4 (histórico de idempotência preservado),
              isolamento, regressão D-A, resíduo zero
Versão......: 1.0
Status......: EXECUTADO no LIVE em 2026-10-21 UTC após 5212–5219 — 26/26 PASS,
              GATE PASS, 99.1 resíduo zero. Mantido aqui como evidência.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-20

Protocolo (o mesmo da 5844/5846): um único statement no SQL Editor;
usuários efêmeros A e B (o inventário nasce pelo trigger de auth.users);
exemplares de A e B sobre uma variante ATIVA já existente (catálogo só
lido); a sentinela MS847 desfaz tudo; a seção 99 prova resíduo zero.
Exercita também contratos canônicos reutilizados: 5022 (via 5216), 5024
(atribuir local), 5036 (trocar local padrão) e 5175 (Coleção livre, D-A
e replay).

Fixture:
  A: a1, a2, a3.  B: b1.
  A cria X (Caixa, BOX), Y (sem tipo), Z (BINDER). a1, a2 → X (5024).
  C = Coleção livre de A com local padrão Z (5175).

Seções:
  0.x estrutura, privilégios, retorno, fixture e vocabulário
  1.1 anon → 42501;  2.1 sem identidade → 28000
  3.x criar: sucesso, replay, chave reutilizada, entradas, sem tipo
  4.x renomear/tipo: mudança, no-op, outro usuário
  5.x leitura: locais com contagens, resumo, isolamento
  6.x excluir: com cartas, local padrão, R4 coleção, vazio, R4 local,
      outro usuário, exemplares e coleção intactos
  7.1 regressão D-A (CT-01 cria "Local padrão" para quem não tem local)
  99.1 resíduo zero
GATE: todas PASS e n = 26.

Prova manual complementar (duas sessões, não cabe num statement):
  K1 sessão 1 begin; delete_my_storage_container(Y) sem commit;
     sessão 2 set_physical_cards_storage(Y, [a3]) → espera; commit da 1
     → sessão 2 falha pela FK (local não existe). Inverso: sessão 2
     atribui primeiro → exclusão devolve STORAGE_HAS_CARDS ou
     STORAGE_IN_USE. Em nenhum caso fica carta apontando para local
     inexistente.
================================================================
*/

create or replace function pg_temp.ms_5847_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_create oid := to_regprocedure('public.create_my_storage_container(uuid,text,text)');
  f_update oid := to_regprocedure('public.update_my_storage_container(uuid,text,text)');
  f_delete oid := to_regprocedure('public.delete_my_storage_container(uuid)');
  f_list   oid := to_regprocedure('public.get_my_storage_locations()');
  f_sum    oid := to_regprocedure('public.get_my_storage_summary()');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx    text := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_pt uuid; v_cv uuid;
  v_inv_a uuid; v_inv_b uuid;
  a1 uuid; a2 uuid; a3 uuid; b1 uuid;
  k_x uuid := gen_random_uuid(); k_y uuid := gen_random_uuid(); k_z uuid := gen_random_uuid();
  k_w uuid := gen_random_uuid(); k_c uuid := gen_random_uuid(); k_b uuid := gen_random_uuid();
  v_x uuid; v_y uuid; v_z uuid; v_w uuid; v_c uuid;
  v_rec record; v_rec2 record;
  v_snap text; v_snap2 text; v_upd timestamptz;
  v_cnt bigint; v_cnt2 bigint; v_ok boolean; v_err text;
  b_us bigint; b_sc bigint; b_co bigint; b_ca bigint; b_pc bigint; b_ccr bigint; b_scr bigint; b_kind bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  -- 0. Estrutura ---------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_create is not null and f_update is not null and f_delete is not null and f_list is not null and f_sum is not null
    and (select count(*) from pg_proc p where p.oid in (f_create, f_update, f_delete, f_list, f_sum)
           and p.prosecdef and p.proconfig = array['search_path=""']) = 5
    and (select count(*) from pg_proc p where p.oid in (f_create, f_update, f_delete) and p.provolatile = 'v') = 3
    and (select count(*) from pg_proc p where p.oid in (f_list, f_sum) and p.provolatile = 's') = 2
    and to_regclass('public.storage_container_kind') is not null
    and to_regclass('public.storage_container_creation_request') is not null
    and exists (select 1 from pg_constraint c where c.conrelid = 'public.storage_container'::regclass
                and c.contype = 'f' and c.confrelid = to_regclass('public.storage_container_kind'))
    and exists (select 1 from pg_constraint c where c.conrelid = 'public.storage_container'::regclass
                and c.conname = 'chk_storage_container_name')
    and (select c.confdeltype from pg_constraint c
         where c.conname = 'collection_creation_request_storage_container_id_fkey'
           and c.conrelid = 'public.collection_creation_request'::regclass) = 'n'
    and (select a.attnotnull from pg_attribute a
         where a.attrelid = 'public.collection_creation_request'::regclass and a.attname = 'storage_container_id') = false
    and (select c.confdeltype from pg_constraint c
         where c.conrelid = to_regclass('public.storage_container_creation_request') and c.contype = 'f'
           and c.confrelid = 'public.storage_container'::regclass) = 'n'
    and to_regclass('public.ix_storage_container_inventory') is not null
    and to_regclass('public.ix_collection_default_storage') is not null
    and (select bool_and(c.relrowsecurity) from pg_class c
         where c.oid in (to_regclass('public.storage_container_kind'), to_regclass('public.storage_container_creation_request'))),
    'detail','5212–5219: funções (DEFINER, search_path vazio, escritas VOLATILE, leituras STABLE); kind_code com FK; regra de nome; FKs de pedidos SET NULL e coluna anulável (R4); índices; RLS');

  if f_create is null or f_update is null or f_delete is null or f_list is null or f_sum is null
     or to_regclass('public.storage_container_kind') is null or to_regclass('public.storage_container_creation_request') is null then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','contratos ausentes — aplique 5212–5219 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    (select bool_and(has_function_privilege('authenticated', f, 'EXECUTE') and not has_function_privilege('anon', f, 'EXECUTE'))
       from unnest(array[f_create, f_update, f_delete, f_list, f_sum]) f)
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (f_create, f_update, f_delete, f_list, f_sum) and a.grantee = 0)
    and not exists (
      select 1 from unnest(array['storage_container','storage_container_kind','storage_container_creation_request','collection_creation_request']) t,
                    unnest(array['INSERT','UPDATE','DELETE']) pv
      where has_table_privilege('authenticated', 'public.' || t, pv) or has_table_privilege('anon', 'public.' || t, pv))
    and has_table_privilege('authenticated', 'public.storage_container_kind', 'SELECT')
    and not has_table_privilege('anon', 'public.storage_container_kind', 'SELECT')
    and not has_table_privilege('authenticated', 'public.storage_container_creation_request', 'SELECT'),
    'detail','EXECUTE só authenticated (anon e PUBLIC sem acesso); nenhuma escrita direta em locais, tipos ou pedidos; tipos legíveis por authenticated; pedidos inacessíveis');
  res := res || jsonb_build_object('id','0.3','ok',
    pg_get_function_result(f_create) = 'TABLE(storage_container_id uuid, name text, kind_code text, replayed boolean)'
    and pg_get_function_result(f_update) = 'TABLE(storage_container_id uuid, name text, kind_code text, updated_at timestamp with time zone, changed boolean)'
    and pg_get_function_result(f_delete) = 'TABLE(storage_container_id uuid, deleted boolean)'
    and pg_get_function_result(f_list) = 'TABLE(storage_container_id uuid, name text, kind_code text, kind_label text, card_count bigint, default_collection_count bigint, can_delete boolean, created_at timestamp with time zone, updated_at timestamp with time zone)'
    and pg_get_function_result(f_sum) = 'TABLE(total_cards bigint, located_cards bigint, unlocated_cards bigint, location_count bigint)',
    'detail','retorno de 5216–5219 exatamente o do contrato');

  -- linha de base -------------------------------------------------------------
  select count(*) into b_us from auth.users;
  select count(*) into b_sc from public.storage_container;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_ccr from public.collection_creation_request;
  select count(*) into b_scr from public.storage_container_creation_request;
  select count(*) into b_kind from public.storage_container_kind;

  begin
    -- Fixture (como dono do banco) --------------------------------------------
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select cv.id into v_cv from public.card_variant cv where cv.is_active order by cv.id limit 1;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'wh5847-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'wh5847a_'||v_sfx, 'display_name', 'WH 5847 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'wh5847-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'wh5847b_'||v_sfx, 'display_name', 'WH 5847 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_cv, v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_cv, v_pt, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_cv, v_pt, v_inv_a) returning id into a3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_cv, v_pt, v_inv_b) returning id into b1;

    res := res || jsonb_build_object('id','0.4','ok',
      v_pt is not null and v_cv is not null and v_inv_a is not null and v_inv_b is not null
      and b_kind = 8
      and (select count(*) from public.storage_container_kind k where k.is_active) = 8
      and not exists (select 1 from public.storage_container sc
                      where sc.name <> btrim(sc.name) or sc.name = '' or char_length(sc.name) > 60),
      'detail','fixture: A (3 exemplares) e B (1); 8 tipos ativos semeados; nenhum local existente fora da regra de nome');

    -- 1. anon ------------------------------------------------------------------
    execute 'set local role anon';
    v_cnt := 0;
    begin perform * from public.create_my_storage_container(gen_random_uuid(), 'x', null); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.update_my_storage_container(gen_random_uuid(), 'x', null); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.delete_my_storage_container(gen_random_uuid()); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_storage_locations(); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_storage_summary(); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_cnt = 5, 'detail','anon recusado (42501) nas 5 funções: '||v_cnt||'/5');

    -- 2. sem identidade ----------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role authenticated';
    v_cnt := 0;
    begin perform * from public.create_my_storage_container(gen_random_uuid(), 'x', null); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.update_my_storage_container(gen_random_uuid(), 'x', null); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.delete_my_storage_container(gen_random_uuid()); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_storage_locations(); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_storage_summary(); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_cnt = 5, 'detail','authenticated sem auth.uid() → 28000 nas 5 funções: '||v_cnt||'/5');

    -- 3. Criar (5216) ------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.create_my_storage_container(k_x, '  Caixa azul  ', 'BOX');
    v_x := v_rec.storage_container_id;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.1','ok',
      v_x is not null and v_rec.name = 'Caixa azul' and v_rec.kind_code = 'BOX' and not v_rec.replayed
      and (select sc.inventory_id from public.storage_container sc where sc.id = v_x) = v_inv_a
      and (select count(*) from public.storage_container_creation_request q
           where q.owner_user_id = p_user_a and q.idempotency_key = k_x and q.storage_container_id = v_x) = 1
      and not exists (select 1 from public.physical_card pc where pc.storage_container_id = v_x),
      'detail','local criado no acervo de A, nome sem espaços nas pontas, tipo BOX, pedido gravado, nenhuma carta atribuída');

    select count(*) into v_cnt from public.storage_container sc where sc.inventory_id = v_inv_a;
    execute 'set local role authenticated';
    select * into v_rec2 from public.create_my_storage_container(k_x, 'Caixa azul', 'BOX');
    execute 'reset role';
    res := res || jsonb_build_object('id','3.2','ok',
      v_rec2.storage_container_id = v_x and v_rec2.replayed
      and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = v_cnt,
      'detail','replay com a mesma chave e o mesmo pedido: mesmo local, replayed = true, nenhum local novo');

    execute 'set local role authenticated';
    v_err := '';
    begin perform * from public.create_my_storage_container(k_x, 'Outro nome', 'BOX'); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.3','ok',
      v_err = '22023 IDEMPOTENCY_KEY_REUSED'
      and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = v_cnt,
      'detail','mesma chave com outro pedido → '||v_err||'; nada criado');

    execute 'set local role authenticated';
    v_cnt2 := 0;
    begin perform * from public.create_my_storage_container(gen_random_uuid(), '   ', null); exception when others then if sqlstate||' '||sqlerrm = '22023 INVALID_NAME' then v_cnt2 := v_cnt2 + 1; end if; end;
    begin perform * from public.create_my_storage_container(gen_random_uuid(), repeat('a', 61), null); exception when others then if sqlstate||' '||sqlerrm = '22023 INVALID_NAME' then v_cnt2 := v_cnt2 + 1; end if; end;
    begin perform * from public.create_my_storage_container(gen_random_uuid(), 'Ok', 'NOPE'); exception when others then if sqlstate||' '||sqlerrm = '22023 INVALID_KIND' then v_cnt2 := v_cnt2 + 1; end if; end;
    begin perform * from public.create_my_storage_container(null, 'Ok', null); exception when others then if sqlstate||' '||sqlerrm = '22023 INVALID_REQUEST' then v_cnt2 := v_cnt2 + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.4','ok',
      v_cnt2 = 4 and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = v_cnt,
      'detail','entradas inválidas recusadas com código (nome vazio, nome > 60, tipo inexistente, chave nula): '||v_cnt2||'/4; nada criado');

    execute 'set local role authenticated';
    select * into v_rec from public.create_my_storage_container(k_y, 'Pasta verde', null);
    v_y := v_rec.storage_container_id;
    select c.storage_container_id into v_z from public.create_my_storage_container(k_z, 'Fichário 1', 'BINDER') c;
    execute 'reset role';
    res := res || jsonb_build_object('id','3.5','ok',
      v_y is not null and v_rec.kind_code is null and v_z is not null
      and (select sc.kind_code from public.storage_container sc where sc.id = v_y) is null,
      'detail','local sem tipo (tipo opcional) e local com tipo BINDER');

    -- Atribuição pela 5024 (contrato reutilizado) -----------------------------
    execute 'set local role authenticated';
    perform public.set_physical_cards_storage(v_x, array[a1, a2]);
    select c.collection_id into v_c from public.create_my_free_collection(k_c, 'WH Livre', v_z) c;
    execute 'reset role';
    select string_agg(pc.id::text||':'||coalesce(pc.storage_container_id::text,'-')||':'||pc.card_variant_id::text||':'||pc.inventory_id::text, ',' order by pc.id)
      into v_snap from public.physical_card pc where pc.inventory_id = v_inv_a;

    -- 4. Renomear / tipo (5217) ---------------------------------------------------
    select sc.updated_at into v_upd from public.storage_container sc where sc.id = v_x;
    execute 'set local role authenticated';
    select * into v_rec from public.update_my_storage_container(v_x, ' Caixa azul grande ', 'ETB');
    execute 'reset role';
    select string_agg(pc.id::text||':'||coalesce(pc.storage_container_id::text,'-')||':'||pc.card_variant_id::text||':'||pc.inventory_id::text, ',' order by pc.id)
      into v_snap2 from public.physical_card pc where pc.inventory_id = v_inv_a;
    res := res || jsonb_build_object('id','4.1','ok',
      v_rec.changed and v_rec.name = 'Caixa azul grande' and v_rec.kind_code = 'ETB'
      and v_snap2 = v_snap
      and (select c.default_storage_container_id from public.collection c where c.id = v_c) = v_z,
      'detail','renomear e trocar tipo: changed = true; exemplares (local, variante, acervo) e local padrão da coleção intactos');

    select sc.updated_at into v_upd from public.storage_container sc where sc.id = v_x;
    execute 'set local role authenticated';
    select * into v_rec from public.update_my_storage_container(v_x, 'Caixa azul grande', 'ETB');
    execute 'reset role';
    res := res || jsonb_build_object('id','4.2','ok',
      not v_rec.changed and (select sc.updated_at from public.storage_container sc where sc.id = v_x) = v_upd,
      'detail','repetir a mesma alteração: changed = false, nada escrito (updated_at preservado)');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := '';
    begin perform * from public.update_my_storage_container(v_x, 'Invasor', null); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.3','ok',
      v_err = 'P0002 STORAGE_NOT_FOUND'
      and (select sc.name from public.storage_container sc where sc.id = v_x) = 'Caixa azul grande',
      'detail','B renomeando local de A → '||v_err||' (igual a inexistente); nada alterado');

    -- 5. Leitura (5219) -------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*),
           bool_and(case l.storage_container_id
                      when v_x then l.card_count = 2 and l.default_collection_count = 0 and not l.can_delete and l.kind_label = 'ETB'
                      when v_y then l.card_count = 0 and l.default_collection_count = 0 and l.can_delete and l.kind_label is null
                      when v_z then l.card_count = 0 and l.default_collection_count = 1 and not l.can_delete and l.kind_label = 'Fichário físico'
                      else false end)
      into v_cnt, v_ok
    from public.get_my_storage_locations() l;
    select * into v_rec from public.get_my_storage_summary();
    execute 'reset role';
    res := res || jsonb_build_object('id','5.1','ok',
      v_cnt = 3 and v_ok,
      'detail','A vê 3 locais: X 2 cartas (não excluível), Y vazio (excluível), Z local padrão de coleção (não excluível); rótulos de tipo humanos');
    res := res || jsonb_build_object('id','5.2','ok',
      v_rec.total_cards = 3 and v_rec.located_cards = 2 and v_rec.unlocated_cards = 1 and v_rec.location_count = 3,
      'detail','resumo de A: 3 exemplares, 2 com local, 1 "Sem localização definida", 3 locais');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_storage_locations();
    select * into v_rec from public.get_my_storage_summary();
    execute 'reset role';
    res := res || jsonb_build_object('id','5.3','ok',
      v_cnt = 0 and v_rec.total_cards = 1 and v_rec.located_cards = 0 and v_rec.unlocated_cards = 1 and v_rec.location_count = 0,
      'detail','isolamento: B não vê os locais de A; resumo só do acervo de B');

    -- 6. Excluir (5218) ---------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := '';
    begin perform * from public.delete_my_storage_container(v_x); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.1','ok',
      v_err = '55000 STORAGE_HAS_CARDS' and exists (select 1 from public.storage_container sc where sc.id = v_x)
      and (select count(*) from public.physical_card pc where pc.storage_container_id = v_x) = 2,
      'detail','local com cartas → '||v_err||'; local e cartas intactos');

    execute 'set local role authenticated';
    v_err := '';
    begin perform * from public.delete_my_storage_container(v_z); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.2','ok',
      v_err = '55000 STORAGE_IS_COLLECTION_DEFAULT' and exists (select 1 from public.storage_container sc where sc.id = v_z),
      'detail','local padrão de coleção → '||v_err||'; local intacto');

    select count(*) into v_cnt from public.collection c where c.owner_user_id = p_user_a;
    execute 'set local role authenticated';
    perform public.set_collection_default_storage(v_c, v_y);
    select * into v_rec from public.delete_my_storage_container(v_z);
    select * into v_rec2 from public.create_my_free_collection(k_c, 'WH Livre', v_z);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.3','ok',
      v_rec.deleted and not exists (select 1 from public.storage_container sc where sc.id = v_z)
      and (select count(*) from public.collection_creation_request q
           where q.owner_user_id = p_user_a and q.idempotency_key = k_c and q.collection_id = v_c and q.storage_container_id is null) = 1
      and v_rec2.replayed and v_rec2.collection_id = v_c and v_rec2.storage_container_id is null
      and (select count(*) from public.collection c where c.owner_user_id = p_user_a) = v_cnt
      and (select c.default_storage_container_id from public.collection c where c.id = v_c) = v_y,
      'detail','R4: após trocar o local padrão (5036), Z é excluído; o pedido de criação da coleção sobrevive (local NULL) e o replay devolve a MESMA coleção, sem criar outra');

    execute 'set local role authenticated';
    select c.storage_container_id into v_w from public.create_my_storage_container(k_w, 'Temporário', 'OTHER') c;
    select * into v_rec from public.delete_my_storage_container(v_w);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.4','ok',
      v_rec.deleted and not exists (select 1 from public.storage_container sc where sc.id = v_w)
      and (select count(*) from public.storage_container_creation_request q
           where q.owner_user_id = p_user_a and q.idempotency_key = k_w and q.storage_container_id is null) = 1,
      'detail','local vazio e sem coleção excluído; o pedido de criação do local é preservado (local NULL)');

    select count(*) into v_cnt from public.storage_container sc where sc.inventory_id = v_inv_a;
    execute 'set local role authenticated';
    select * into v_rec from public.create_my_storage_container(k_z, 'Fichário 1', 'BINDER');
    execute 'reset role';
    res := res || jsonb_build_object('id','6.5','ok',
      v_rec.replayed and v_rec.storage_container_id is null
      and (select count(*) from public.storage_container sc where sc.inventory_id = v_inv_a) = v_cnt,
      'detail','replay da criação de um local já excluído: replayed = true, local NULL, nada recriado');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := '';
    begin perform * from public.delete_my_storage_container(v_x); exception when others then v_err := sqlstate||' '||sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.6','ok',
      v_err = 'P0002 STORAGE_NOT_FOUND' and exists (select 1 from public.storage_container sc where sc.id = v_x),
      'detail','B excluindo local de A → '||v_err||' (igual a inexistente); nada alterado');

    select string_agg(pc.id::text||':'||coalesce(pc.storage_container_id::text,'-')||':'||pc.card_variant_id::text||':'||pc.inventory_id::text, ',' order by pc.id)
      into v_snap2 from public.physical_card pc where pc.inventory_id = v_inv_a;
    res := res || jsonb_build_object('id','6.7','ok',
      v_snap2 = v_snap
      and (select pc.storage_container_id from public.physical_card pc where pc.id = b1) is null
      and (select count(*) from public.collection_allocation ca where ca.physical_card_id in (a1, a2, a3, b1)) = 0
      and exists (select 1 from public.collection c where c.id = v_c),
      'detail','depois de todas as exclusões: exemplares de A e B idênticos (identidade, local, variante, acervo), nenhuma alocação criada ou removida, coleção intacta');

    -- 7. Regressão D-A (CT-01) ------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.create_my_free_collection(k_b, 'WH B', null);
    select count(*), bool_and(l.name = 'Local padrão' and l.default_collection_count = 1 and not l.can_delete and l.card_count = 0)
      into v_cnt, v_ok from public.get_my_storage_locations() l;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.1','ok',
      v_rec.storage_container_created and not v_rec.replayed and v_cnt = 1 and v_ok
      and (select pc.storage_container_id from public.physical_card pc where pc.id = b1) is null,
      'detail','D-A inalterada: B sem local cria coleção → "Local padrão" criado, listado como local padrão, nenhuma carta atribuída');

    raise exception 'MS847' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS847' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','99.1','ok',
    (select count(*) from auth.users) = b_us
      and (select count(*) from public.storage_container) = b_sc
      and (select count(*) from public.collection) = b_co
      and (select count(*) from public.collection_allocation) = b_ca
      and (select count(*) from public.physical_card) = b_pc
      and (select count(*) from public.collection_creation_request) = b_ccr
      and (select count(*) from public.storage_container_creation_request) = b_scr
      and (select count(*) from public.storage_container_kind) = b_kind
      and current_user = session_user,
    'detail','resíduo zero (usuários, locais, coleções, alocações, exemplares, pedidos, tipos) e papel restaurado');
  end if;

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case when passes = n and n = 26 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 26)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5847_validate();
