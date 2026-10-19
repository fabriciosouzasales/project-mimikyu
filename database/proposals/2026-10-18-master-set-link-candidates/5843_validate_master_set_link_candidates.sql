/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5843 - Harness: get_my_master_set_link_candidates (5200)
              estrutura, segurança, escolha por posição, coerência com a
              grade e com a 5199, limite, isolamento, vínculo em lote
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18, após a 5200
              (ledger 20261019001438): GATE PASS 25/25, 99.1 resíduo zero.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-LINK-CANDIDATES-01)

Protocolo (o mesmo da 5842, já executada no LIVE): um único statement
no SQL Editor; usuários efêmeros A e B; catálogo SINTÉTICO próprio
criado e desfeito na mesma transação; a sentinela MS843 desfaz tudo;
a seção 99 prova resíduo zero. Nenhum dado real é lido além das
contagens de linha de base.

Fixture = a da 5842 (Set S, base 3, total 5; objetivo de v_ms {Padrão,
Reverse}; posições c1P, c1R, c3P, c4 genérica, c5P):
  c1P  faltante  livres a1, a10, a11 (padrão, pt-BR) e a2 (1ª Ed., en)
                 → escolhido o 1º da ordem documentada (oráculo)
  c1R  SATISFEITA por a4 (vinculado a v_ms) → fora, mesmo com a3 livre
  c3P  faltante, mas o único exemplar (a8) está na Coleção livre → fora
  c4   genérica faltante: a6 (Gold, padrão) e a7 (Cosmos, en) → a6
  c5P  faltante: a12
  a5 (c2 Holo) não tem posição; b1 é de B.
Esperado para A em v_ms: 3 candidatos, ordem c1 → c4 → c5.

Seções:
  0.x estrutura, privilégios, retorno
  1.x anon → 42501        2.x sem identidade → 28000; limite inválido → 22023
  3.x escolha por posição, exclusões, rótulos
  4.x coerência com a grade (5198) e com a 5199
  5.x limite e determinismo
  6.x isolamento
  7.x só leitura; vínculo do lote inteiro pela 5046; reenvio recusado
  99.1 resíduo zero
GATE: todas PASS e n = 25.
================================================================
*/

create or replace function pg_temp.ms_5843_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_lc  oid := to_regprocedure('public.get_my_master_set_link_candidates(uuid,integer)');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx    text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_game uuid; v_rar uuid; v_cat uuid; v_pt uuid; v_en uuid; v_fe uuid; v_lg uuid;
  t_std uuid; t_holo uuid; t_rev uuid; t_gold uuid; t_cos uuid;
  v_exp uuid := gen_random_uuid(); v_set uuid := gen_random_uuid();
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); c3 uuid := gen_random_uuid();
  c4 uuid := gen_random_uuid(); c5 uuid := gen_random_uuid();
  v_c1p uuid := gen_random_uuid(); v_c1pfe uuid := gen_random_uuid(); v_c1r uuid := gen_random_uuid();
  v_c1rl uuid := gen_random_uuid(); v_c2h uuid := gen_random_uuid(); v_c3p uuid := gen_random_uuid();
  v_c4g uuid := gen_random_uuid(); v_c4c uuid := gen_random_uuid(); v_c5p uuid := gen_random_uuid();
  v_inv_a uuid; v_inv_b uuid;
  a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid; a6 uuid; a7 uuid; a8 uuid; a10 uuid; a11 uuid; a12 uuid; b1 uuid;
  v_ms uuid; v_sd uuid; v_arch uuid; v_free uuid; v_box uuid; v_b uuid; v_box_name text;
  v_ids uuid[]; v_ids2 uuid[]; v_oracle uuid[];
  v_cnt bigint; v_cnt2 bigint; v_tot bigint; v_tot2 bigint; v_ok boolean; v_err text;
  v_fp text; v_fp2 text; v_rec record; v_k1 text; v_k2 text; v_first uuid;
  b_us bigint; b_co bigint; b_ca bigint; b_pc bigint; b_fn bigint; b_card bigint; b_cv bigint; b_cs bigint; b_ex bigint; b_sc bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  -- 0. Estrutura ------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    f_lc is not null
    and exists (select 1 from pg_proc p where p.oid = f_lc
                and p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""'])
    and (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
         where s.nspname = 'public' and p.proname = 'get_my_master_set_link_candidates') = 1,
    'detail','5200 existe com a assinatura do contrato, sem sobrecarga; SECURITY DEFINER, STABLE, search_path vazio');
  res := res || jsonb_build_object('id','0.2','ok',
    f_lc is not null
    and has_function_privilege('authenticated', f_lc, 'EXECUTE')
    and not has_function_privilege('anon', f_lc, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f_lc and a.grantee = 0),
    'detail','EXECUTE só authenticated; anon e PUBLIC sem acesso');
  res := res || jsonb_build_object('id','0.3','ok',
    f_lc is not null
    and pg_get_function_result(f_lc) = 'TABLE(physical_card_id uuid, card_id uuid, variant_type_id uuid, collector_number text, card_name text, variant_type_name text, is_secret boolean, language_code text, image_path text, total_count bigint)',
    'detail','retorno do contrato: único identificador de acervo é physical_card_id (sem card_variant_id, inventário ou local)');

  if f_lc is null then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','5200 ausente — aplique a 5200 antes deste harness');
  else
  -- linha de base -------------------------------------------------------------
  select count(*) into b_us from auth.users;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_fn from public.collection_master_set_finish;
  select count(*) into b_card from public.card;
  select count(*) into b_cv from public.card_variant;
  select count(*) into b_cs from public.card_set;
  select count(*) into b_ex from public.expansion;
  select count(*) into b_sc from public.storage_container;

  begin
    -- Fixture (como dono do banco) --------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select r.id into v_rar from public.rarity r where r.game_id = v_game and r.code = 'COMMON';
    select c.id into v_cat from public.card_category c where c.game_id = v_game and c.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select l.id into v_en from public.language l where l.code = 'en';
    select p.id into v_fe from public.card_printing_profile p where p.code = 'FIRST_EDITION';
    select p.id into v_lg from public.card_edition_context_profile p where p.code = 'PROGRAM_LEAGUE';
    select t.id into t_std  from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select t.id into t_holo from public.card_variant_type t where t.game_id = v_game and t.code = 'HOLO';
    select t.id into t_rev  from public.card_variant_type t where t.game_id = v_game and t.code = 'REVERSE_HOLO';
    select t.id into t_gold from public.card_variant_type t where t.game_id = v_game and t.code = 'GOLD_HOLO';
    select t.id into t_cos  from public.card_variant_type t where t.game_id = v_game and t.code = 'COSMOS_HOLO';

    insert into public.expansion (id, game_id, code, name, release_order)
    values (v_exp, v_game, 'ZZLC5843_'||upper(v_sfx), 'LC 5843 '||v_sfx,
            (select coalesce(max(e.release_order), 0) + 1 from public.expansion e where e.game_id = v_game));
    insert into public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_set, v_exp, 'ZZLC-'||upper(v_sfx), 'LC 5843 S', 'REGULAR', 1, 3, 5);
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
    values (c1, v_set, v_rar, v_cat, '001', 3, 1, 'LC Um'),
           (c2, v_set, v_rar, v_cat, '002', 3, 2, 'LC Dois'),
           (c3, v_set, v_rar, v_cat, '003', 3, 3, 'LC Três'),
           (c4, v_set, v_rar, v_cat, '004', 3, 4, 'LC Quatro Secreta'),
           (c5, v_set, v_rar, v_cat, '005', 3, 5, 'LC Cinco Secreta');
    insert into public.card_variant (id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id, variant_order, is_default, is_active)
    values (v_c1p,   c1, t_std,  null, null, 1, true,  true),
           (v_c1pfe, c1, t_std,  v_fe, null, 2, false, true),
           (v_c1r,   c1, t_rev,  null, null, 3, false, true),
           (v_c1rl,  c1, t_rev,  null, v_lg, 4, false, true),
           (v_c2h,   c2, t_holo, null, null, 1, true,  true),
           (v_c3p,   c3, t_std,  null, null, 1, true,  true),
           (v_c4g,   c4, t_gold, null, null, 1, true,  true),
           (v_c4c,   c4, t_cos,  null, null, 2, false, true),
           (v_c5p,   c5, t_std,  null, null, 1, true,  true);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'lc5843-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'lc5843a_'||v_sfx, 'display_name', 'LC 5843 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'lc5843-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'lc5843b_'||v_sfx, 'display_name', 'LC 5843 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_a) returning id into a1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1pfe, v_en, v_inv_a) returning id into a2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1rl,  v_pt, v_inv_a) returning id into a3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1r,   v_pt, v_inv_a) returning id into a4;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c2h,   v_pt, v_inv_a) returning id into a5;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c4g,   v_pt, v_inv_a) returning id into a6;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c4c,   v_en, v_inv_a) returning id into a7;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c3p,   v_pt, v_inv_a) returning id into a8;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_a) returning id into a10;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_a) returning id into a11;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c5p,   v_pt, v_inv_a) returning id into a12;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1p,   v_pt, v_inv_b) returning id into b1;

    -- coleções (como o próprio usuário, pelos contratos de produto)
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id, c.storage_container_id into v_ms, v_box
      from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'LC 5843 Master', null) c;
    select c.collection_id into v_sd   from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'LC 5843 Padrão', v_box) c;
    select c.collection_id into v_arch from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'LC 5843 Arquivada', v_box) c;
    select c.collection_id into v_free from public.create_my_free_collection(gen_random_uuid(), 'LC 5843 Livre', v_box) c;
    perform public.allocate_physical_cards_to_collection(v_ms, array[a4]);
    perform public.allocate_physical_cards_to_collection(v_free, array[a8]);
    perform public.set_collection_completion_policy_to_master_set(v_ms, array[t_std, t_rev]);
    perform public.set_collection_completion_policy_to_master_set(v_arch, array[t_std, t_rev]);
    perform public.archive_collection(v_arch);
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_b from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'LC 5843 B', null) c;
    perform public.set_collection_completion_policy_to_master_set(v_b, array[t_std, t_rev]);
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);

    -- local físico de a1 (para provar que o local é devolvido, nunca alterado)
    update public.physical_card set storage_container_id = v_box where id = a1;
    select sc.name into v_box_name from public.storage_container sc where sc.id = v_box;

    -- impressão digital do acervo sintético (variante, idioma, local, vínculo)
    select md5(string_agg(pc.id::text||pc.card_variant_id::text||pc.language_id::text||coalesce(pc.storage_container_id::text,'')
                          ||coalesce(ca.collection_id::text,'-'), ',' order by pc.id))
      into v_fp
    from public.physical_card pc left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.inventory_id in (v_inv_a, v_inv_b);

    -- Oráculos lidos como dono (catálogo tem RLS admin-only para authenticated):
    -- ordem documentada da 5199 (escolha da posição c1 Padrão).
    select array_agg(pc.id order by cv.is_default desc, l.language_order, pc.created_at, pc.id) into v_oracle
      from public.physical_card pc
      join public.card_variant cv on cv.id = pc.card_variant_id
      join public.language l on l.id = pc.language_id
      where pc.id = any(array[a1, a2, a10, a11]);

    res := res || jsonb_build_object('id','0.4','ok',
      v_game is not null and t_std is not null and t_rev is not null and t_gold is not null and t_cos is not null
      and t_holo is not null and v_fe is not null and v_lg is not null and v_en is not null
      and v_inv_a is not null and v_inv_b is not null and v_ms is not null and v_b is not null and v_box_name is not null
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 2
      and (select c.lifecycle_status from public.collection c where c.id = v_arch) <> 'ACTIVE'
      and cardinality(v_oracle) = 4,
      'detail','fixture sintética da 5842: 1 Set, 5 cartas, 9 variantes, 11 exemplares de A + 1 de B; v_ms e v_b em Master Set {Padrão, Reverse}; v_arch arquivada');

    -- 1. anon -----------------------------------------------------------------
    execute 'set local role anon';
    begin
      perform * from public.get_my_master_set_link_candidates(v_ms, 500);
      v_err := 'executou';
    exception when others then v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_err = '42501', 'detail','anon recusado: '||v_err);

    -- 2. sem identidade e limite inválido ---------------------------------------
    execute 'set local role authenticated';
    begin
      perform * from public.get_my_master_set_link_candidates(v_ms, 500);
      v_err := 'executou';
    exception when others then v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_err = '28000', 'detail','authenticated sem auth.uid() → 28000: '||v_err);

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_cnt := 0;
    begin perform * from public.get_my_master_set_link_candidates(v_ms, 0);    exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_master_set_link_candidates(v_ms, 501);  exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    begin perform * from public.get_my_master_set_link_candidates(v_ms, null); exception when others then if sqlstate = '22023' then v_cnt := v_cnt + 1; end if; end;
    res := res || jsonb_build_object('id','2.2','ok', v_cnt = 3,
      'detail','limite 0, 501 e nulo → 22023: '||v_cnt||'/3');

    -- 3. escolha por posição (como A) ---------------------------------------------
    select array_agg(x.physical_card_id order by x.ord), max(x.total_count), count(*) into v_ids, v_tot, v_cnt
      from public.get_my_master_set_link_candidates(v_ms, 500)
           with ordinality x(physical_card_id, card_id, variant_type_id, collector_number, card_name, variant_type_name, is_secret, language_code, image_path, total_count, ord);
    res := res || jsonb_build_object('id','3.1','ok',
      v_ids = array[v_oracle[1], a6, a12] and v_tot = 3 and v_cnt = 3,
      'detail','3 candidatos na ordem do Set: c1 Padrão (1º da ordem documentada), c4 genérica (a6, variante padrão), c5 Padrão (a12); total 3');
    res := res || jsonb_build_object('id','3.2','ok',
      not (a3 = any(v_ids)) and not (a4 = any(v_ids)) and not (a5 = any(v_ids)) and not (a7 = any(v_ids))
      and not (a8 = any(v_ids)) and not (b1 = any(v_ids)),
      'detail','fora: a3 (c1 Reverse já satisfeita por a4), a4 (vinculado), a5 (sem posição), a7 (genérica já atendida por a6), a8 (em outra coleção), b1 (de B)');
    res := res || jsonb_build_object('id','3.3','ok',
      (select count(distinct (x.card_id, coalesce(x.variant_type_id, '00000000-0000-0000-0000-000000000000'::uuid)))
         from public.get_my_master_set_link_candidates(v_ms, 500) x) = 3
      and (select count(distinct x.physical_card_id) from public.get_my_master_set_link_candidates(v_ms, 500) x) = 3,
      'detail','uma linha por posição e nenhum exemplar repetido');
    v_ok := true;
    for v_rec in select * from public.get_my_master_set_link_candidates(v_ms, 500) loop
      if v_rec.card_id = c1 then
        v_ok := v_ok and v_rec.variant_type_id = t_std and not v_rec.is_secret and v_rec.collector_number = '001'
                     and v_rec.card_name = 'LC Um' and v_rec.language_code = 'pt-BR' and v_rec.variant_type_name is not null;
      elsif v_rec.card_id = c4 then
        v_ok := v_ok and v_rec.variant_type_id is null and v_rec.is_secret and v_rec.variant_type_name is null
                     and v_rec.physical_card_id = a6;
      elsif v_rec.card_id = c5 then
        v_ok := v_ok and v_rec.variant_type_id = t_std and v_rec.is_secret and v_rec.physical_card_id = a12;
      else
        v_ok := false;
      end if;
    end loop;
    res := res || jsonb_build_object('id','3.4','ok', v_ok,
      'detail','rótulos: c1 Padrão (não secreta, número/nome/idioma); c4 secreta genérica sem acabamento; c5 secreta em Padrão');
    select count(*) into v_cnt from public.get_my_master_set_link_candidates(v_ms, 500) x where x.card_id in (c2, c3);
    res := res || jsonb_build_object('id','3.5','ok', v_cnt = 0,
      'detail','c2 (fora do objetivo) e c3 (sem exemplar livre) não aparecem');

    -- 4. coerência com a grade (5198) e com a 5199 -------------------------------
    select string_agg(x.card_id::text||'/'||coalesce(x.variant_type_id::text,'-'), ',' order by x.card_id, x.variant_type_id nulls first)
      into v_k1 from public.get_my_master_set_link_candidates(v_ms, 500) x;
    select string_agg(g.card_id::text||'/'||coalesce(g.variant_type_id::text,'-'), ',' order by g.card_id, g.variant_type_id nulls first)
      into v_k2 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
      where not g.is_satisfied and g.copies_available > 0;
    res := res || jsonb_build_object('id','4.1','ok', v_k1 is not null and v_k1 = v_k2,
      'detail','posições dos candidatos = posições faltantes da grade com exemplar no acervo (copies_available > 0)');
    v_ok := true;
    for v_rec in select * from public.get_my_master_set_link_candidates(v_ms, 500) loop
      select y.physical_card_id into v_first
        from public.get_my_master_set_position_copies(v_ms, v_rec.card_id, v_rec.variant_type_id, 1, 0) y;
      if v_first is distinct from v_rec.physical_card_id then v_ok := false; end if;
    end loop;
    res := res || jsonb_build_object('id','4.2','ok', v_ok,
      'detail','em cada posição o exemplar escolhido é o 1º da 5199 (mesma regra e mesma ordem do "Adicionar do acervo")');

    -- 5. limite e determinismo -----------------------------------------------------
    select array_agg(x.physical_card_id order by x.ord), max(x.total_count) into v_ids2, v_tot2
      from public.get_my_master_set_link_candidates(v_ms, 1)
           with ordinality x(physical_card_id, card_id, variant_type_id, collector_number, card_name, variant_type_name, is_secret, language_code, image_path, total_count, ord);
    select count(*) into v_cnt from public.get_my_master_set_link_candidates(v_ms, 2);
    res := res || jsonb_build_object('id','5.1','ok', v_ids2 = array[v_ids[1]] and v_tot2 = 3 and v_cnt = 2,
      'detail','limite 1 → só a 1ª linha da ordem, total_count 3 (antes do limite); limite 2 → 2 linhas');
    select array_agg(x.physical_card_id order by x.ord) into v_ids2
      from public.get_my_master_set_link_candidates(v_ms, 500)
           with ordinality x(physical_card_id, card_id, variant_type_id, collector_number, card_name, variant_type_name, is_secret, language_code, image_path, total_count, ord);
    res := res || jsonb_build_object('id','5.2','ok', v_ids2 = v_ids,
      'detail','duas leituras seguidas → mesma lista, mesma ordem');

    -- 6. isolamento ---------------------------------------------------------------
    select count(*) into v_cnt from public.get_my_master_set_link_candidates(v_b, 500);
    select count(*) into v_cnt2 from public.get_my_master_set_link_candidates(gen_random_uuid(), 500);
    res := res || jsonb_build_object('id','6.1','ok', v_cnt = 0 and v_cnt2 = 0,
      'detail','A lendo a coleção Master Set de B e uma coleção inexistente → zero linhas (mesma resposta)');
    select count(*) into v_cnt from public.get_my_master_set_link_candidates(v_arch, 500);
    res := res || jsonb_build_object('id','6.2','ok', v_cnt = 0,
      'detail','coleção arquivada (Master Set) → zero linhas');
    select count(*) into v_cnt from public.get_my_master_set_link_candidates(v_sd, 500);
    select count(*) into v_cnt2 from public.get_my_master_set_link_candidates(v_free, 500);
    res := res || jsonb_build_object('id','6.3','ok', v_cnt = 0 and v_cnt2 = 0,
      'detail','coleção em Set padrão e Coleção livre → zero linhas (o Set padrão continua na 5170)');
    execute 'reset role';

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(g.physical_card_id), max(g.total_count) into v_ids2, v_tot2
      from public.get_my_master_set_link_candidates(v_b, 500) g;
    select count(*) into v_cnt from public.get_my_master_set_link_candidates(v_ms, 500);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.4','ok', v_ids2 = array[b1] and v_tot2 = 1 and v_cnt = 0,
      'detail','B na própria coleção vê só b1; B na coleção de A → zero linhas');

    -- 7. só leitura; vínculo do lote pela 5046 --------------------------------------
    perform set_config('request.jwt.claims', '', true);
    select md5(string_agg(pc.id::text||pc.card_variant_id::text||pc.language_id::text||coalesce(pc.storage_container_id::text,'')
                          ||coalesce(ca.collection_id::text,'-'), ',' order by pc.id))
      into v_fp2
    from public.physical_card pc left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.inventory_id in (v_inv_a, v_inv_b);
    res := res || jsonb_build_object('id','7.1','ok', v_fp = v_fp2,
      'detail','depois de todas as leituras: exemplares de A e B com a mesma variante, idioma, local e vínculo');

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(x.physical_card_id) into v_ids2 from public.get_my_master_set_link_candidates(v_ms, 500) x;
    perform public.allocate_physical_cards_to_collection(v_ms, v_ids2);
    select count(*) into v_cnt from public.get_my_master_set_link_candidates(v_ms, 500);
    select count(*) into v_cnt2 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
      where not g.is_satisfied and g.copies_available > 0;
    res := res || jsonb_build_object('id','7.2','ok', v_cnt = 0 and v_cnt2 = 0,
      'detail','lote inteiro aceito pela 5046 numa chamada; releitura → zero candidatos; grade sem posição faltante com exemplar disponível');
    begin
      perform public.allocate_physical_cards_to_collection(v_ms, v_ids2);
      v_err := 'executou';
    exception when others then v_err := sqlstate;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','7.3','ok', v_err <> 'executou',
      'detail','reenvio do mesmo lote recusado pela 5046 (sem duplicar): '||v_err);
    res := res || jsonb_build_object('id','7.4','ok',
      (select count(*) from public.collection_allocation ca where ca.collection_id = v_ms) = 4
      and (select count(*) from public.collection_allocation ca where ca.physical_card_id = any(v_ids2)) = 3
      and not exists (select 1 from public.collection_allocation ca where ca.physical_card_id in (a2, a3, a7))
      and (select pc.storage_container_id from public.physical_card pc where pc.id = a1) = v_box,
      'detail','v_ms com 4 vínculos (a4 + 3 do lote); a2, a3 e a7 seguem livres; local de a1 intacto');

    raise exception 'MS843' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS843' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','99.1','ok',
    (select count(*) from auth.users) = b_us
      and (select count(*) from public.collection) = b_co
      and (select count(*) from public.collection_allocation) = b_ca
      and (select count(*) from public.physical_card) = b_pc
      and (select count(*) from public.collection_master_set_finish) = b_fn
      and (select count(*) from public.card) = b_card
      and (select count(*) from public.card_variant) = b_cv
      and (select count(*) from public.card_set) = b_cs
      and (select count(*) from public.expansion) = b_ex
      and (select count(*) from public.storage_container) = b_sc
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, vínculos, exemplares, acabamentos, locais, catálogo) e papel restaurado');
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
  status := case when passes = n and n = 25 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 25)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5843_validate();
