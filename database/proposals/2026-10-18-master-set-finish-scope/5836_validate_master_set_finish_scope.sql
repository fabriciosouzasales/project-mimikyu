/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5836 - Harness: Master Set por acabamento (5184–5197)
              funcional, segurança, regressão e preservação
Versão......: 1.1 (AUDIT-CORRECTION-01: seções 11 e 12; casos 2.3, 4.8, 9.4)
Status......: PROPOSTO — NÃO EXECUTADO (executar só depois de 5184–5197,
              com autorização de Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18 (MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01)

Protocolo (mesmo de 5830–5835): um único statement; usuários efêmeros A e
B; catálogo SINTÉTICO próprio (expansão, 3 Sets, cartas e variantes
criadas e desfeitas na mesma transação — nenhum dado real de catálogo é
alterado); sentinela MS000 desfaz tudo; seção 99 prova resíduo zero.
Leituras de dados reais só em 8.1 (resumo das coleções STANDARD_SET
existentes, sem escrita).

Catálogo sintético (Set S, base 4, total 6):
  c1 001  Padrão (padrão) · Padrão 1ª Edição · Reverse · Reverse Liga
  c2 002  Holo (padrão) · Reverse
  c3 003  Padrão (padrão) · Energia Reverse
  c4 004  Padrão (padrão)
  c5 005  Gold (padrão)                    → secreta (5 > 4)
  c6 006  Holo (padrão) · Gold             → secreta (6 > 4)
  c7 TG01 Rainbow (padrão)                 → não numérica: não secreta
  Set S2 (base 1): c9 001 Padrão — usado só em 5.15 (EMPTY_OBJECTIVE).
Exemplares de A: p1 c1 Padrão 1ª Ed. · p2/p3 c1 Reverse Liga (repetida) ·
p4 c6 Gold · p5 c3 Energia Reverse · p6 c2 Holo (inglês) — vinculados;
p7 c4 Padrão — só no acervo.
Set S3 (base 2, seção 12): r1 001 Padrão · r2 002 Padrão · r3 003 Gold
(secreta); na 12.3 entram r2 Reverse, r1 Padrão 1ª Ed. e a carta r4 004
(secreta, Padrão). Exemplares p8 (r1 Padrão) e p9 (r3 Gold) vinculados à
coleção v_r.

Esperado com {Padrão, Holo, Reverse}: 8 posições (c1P, c1R, c2H, c2R,
c3P, c4P, c6H + secreta c5), 3 satisfeitas (c1P, c1R, c2H).

Seções:
  0.x estrutura e privilégios; objetos 02F aposentados
  1.x anon → 42501          2.x sem identidade → 28000
  3.x cálculo (ativação, resumo, grade, opções, fora do objetivo)
  4.x validação do conjunto de acabamentos (prévia = gravação)
  5.x edição, idempotência, presença, alternância de política
  6.x evolução do catálogo (novas combinações, desativações,
      reclassificação, nova secreta, mudança do Set base)
  7.x prévia
  8.x regressão Set padrão e Pokédex
  9.x isolamento entre usuários e estados inválidos
  10.x preservação dos exemplares
  11.x transições da posição de carta secreta (genérica ↔ específica)
  12.x reativação após mudança de catálogo durante o Set padrão (Set S3)
  99.1 resíduo zero
GATE: todas PASS e n = total esperado (calculado no fim do arquivo).
================================================================
*/

create or replace function pg_temp.ms_5836_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  -- funções sob teste
  f_act   oid := to_regprocedure('public.set_collection_completion_policy_to_master_set(uuid,uuid[])');
  f_rep   oid := to_regprocedure('public.replace_master_set_finishes(uuid,uuid[])');
  f_std   oid := to_regprocedure('public.set_collection_completion_policy_to_standard_set(uuid)');
  f_pos   oid := to_regprocedure('public.get_my_master_set_positions(uuid,text,integer,integer)');
  f_opt   oid := to_regprocedure('public.get_my_master_set_finish_options(uuid)');
  f_pre   oid := to_regprocedure('public.preview_my_master_set_finishes(uuid,uuid[])');
  f_out   oid := to_regprocedure('public.get_my_master_set_out_of_scope_copies(uuid,integer,integer)');
  f_sum   oid := to_regprocedure('public.collection_completion_summary(uuid)');
  f_msp   oid := to_regprocedure('public.master_set_positions(uuid,uuid[])');
  f_nrm   oid := to_regprocedure('public.normalize_master_set_finishes(uuid,uuid,uuid[])');
  f_apl   oid := to_regprocedure('public.apply_master_set_finishes(uuid,uuid,uuid[])');
  f_chk   oid := to_regprocedure('public.check_master_set_scope_presence(uuid)');
  p_user_a uuid := gen_random_uuid();
  p_user_b uuid := gen_random_uuid();
  v_sfx    text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  -- catálogo
  v_game uuid; v_rar uuid; v_cat uuid; v_pt uuid; v_en uuid; v_fe uuid; v_lg uuid;
  t_std uuid; t_holo uuid; t_rev uuid; t_er uuid; t_gold uuid; t_rb uuid; t_cos uuid;
  v_exp uuid := gen_random_uuid(); v_set uuid := gen_random_uuid(); v_set2 uuid := gen_random_uuid();
  c1 uuid := gen_random_uuid(); c2 uuid := gen_random_uuid(); c3 uuid := gen_random_uuid();
  c4 uuid := gen_random_uuid(); c5 uuid := gen_random_uuid(); c6 uuid := gen_random_uuid();
  c7 uuid := gen_random_uuid(); c8 uuid := gen_random_uuid(); c9 uuid := gen_random_uuid();
  v_c1p uuid := gen_random_uuid(); v_c1pfe uuid := gen_random_uuid(); v_c1r uuid := gen_random_uuid();
  v_c1rl uuid := gen_random_uuid(); v_c2h uuid := gen_random_uuid(); v_c2r uuid := gen_random_uuid();
  v_c3p uuid := gen_random_uuid(); v_c3er uuid := gen_random_uuid(); v_c4p uuid := gen_random_uuid();
  v_c5g uuid := gen_random_uuid(); v_c6h uuid := gen_random_uuid(); v_c6g uuid := gen_random_uuid();
  v_c7rb uuid := gen_random_uuid(); v_c9p uuid := gen_random_uuid();
  v_set3 uuid := gen_random_uuid();
  r1 uuid := gen_random_uuid(); r2 uuid := gen_random_uuid(); r3 uuid := gen_random_uuid(); r4 uuid := gen_random_uuid();
  v_r1p uuid := gen_random_uuid(); v_r2p uuid := gen_random_uuid(); v_r3g uuid := gen_random_uuid();
  -- usuários / coleções
  v_inv_a uuid; v_inv_b uuid;
  p1 uuid; p2 uuid; p3 uuid; p4 uuid; p5 uuid; p6 uuid; p7 uuid; p8 uuid; p9 uuid; v_r uuid;
  v_ms uuid; v_sd uuid; v_s2 uuid; v_arch uuid; v_free uuid; v_box uuid; v_b uuid;
  v_def uuid[]; v_err text; v_state text; v_rec record; v_rec2 record;
  v_cnt bigint; v_cnt2 bigint; v_ok boolean; v_fp text; v_fp2 text; v_fp_pres text;
  v_adopt timestamptz; v_msg_dummy text;
  -- base de resíduo
  b_us bigint; b_co bigint; b_ca bigint; b_pc bigint; b_fn bigint; b_card bigint; b_cv bigint; b_cs bigint; b_ex bigint;
  res jsonb := '[]'::jsonb; r jsonb; n integer := 0; passes integer := 0;
begin
  -- 0. Estrutura ------------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    to_regclass('public.collection_master_set_finish') is not null
    and (select c.relrowsecurity from pg_class c where c.oid = 'public.collection_master_set_finish'::regclass)
    and has_table_privilege('authenticated','public.collection_master_set_finish','SELECT')
    and not has_table_privilege('authenticated','public.collection_master_set_finish','INSERT')
    and not has_table_privilege('authenticated','public.collection_master_set_finish','UPDATE')
    and not has_table_privilege('authenticated','public.collection_master_set_finish','DELETE')
    and not has_table_privilege('anon','public.collection_master_set_finish','SELECT')
    and (select count(*) from pg_policy p where p.polrelid = 'public.collection_master_set_finish'::regclass) = 1,
    'detail','5184: RLS, só SELECT para authenticated, 1 policy, anon sem acesso');
  res := res || jsonb_build_object('id','0.2','ok',
    (select count(*) from unnest(array[f_act,f_rep,f_pos,f_opt,f_pre,f_out]) x(o)
      join pg_proc p on p.oid = x.o
      where p.prosecdef and p.proconfig = array['search_path=""']
        and has_function_privilege('authenticated', p.oid, 'EXECUTE')
        and not has_function_privilege('anon', p.oid, 'EXECUTE')
        and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)) = 6,
    'detail','6 contratos públicos: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    (select count(*) from unnest(array[f_msp,f_nrm,f_apl,f_chk,
        to_regprocedure('public.validate_master_set_finish_eligibility()'),
        to_regprocedure('public.reject_collection_master_set_finish_update()'),
        to_regprocedure('public.enforce_master_set_finish_presence_on_delete()')]) x(o)
      join pg_proc p on p.oid = x.o
      where p.prosecdef and p.proconfig = array['search_path=""']
        and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
        and not has_function_privilege('anon', p.oid, 'EXECUTE')) = 7,
    'detail','7 funções internas/gatilho sem EXECUTE para clientes');
  res := res || jsonb_build_object('id','0.4','ok',
    to_regclass('public.collection_master_set_scope') is null
    and to_regprocedure('public.collection_master_set_scope_positions(uuid,boolean)') is null
    and to_regprocedure('public.apply_master_set_scope_diff(uuid,jsonb)') is null
    and to_regprocedure('public.set_collection_completion_policy_to_master_set(uuid,jsonb)') is null
    and to_regprocedure('public.replace_master_set_scope(uuid,jsonb)') is null
    and to_regprocedure('public.validate_master_set_scope_eligibility()') is null
    and (select count(*) from pg_proc where proname = 'set_collection_completion_policy_to_master_set') = 1,
    'detail','objetos 02F aposentados (5197); uma única versão da ativação');
  res := res || jsonb_build_object('id','0.5','ok',
    exists (select 1 from pg_trigger t where t.tgrelid = 'public.collection_master_set_finish'::regclass
            and t.tgname = 'trg_collection_master_set_finish_presence_on_delete' and t.tgdeferrable and t.tginitdeferred)
    and exists (select 1 from pg_trigger t where t.tgrelid = 'public.collection'::regclass
            and t.tgname = 'trg_collection_master_set_scope_presence')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'public.collection_master_set_finish'::regclass
            and t.tgname = 'trg_collection_master_set_finish_eligibility')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'public.collection_master_set_finish'::regclass
            and t.tgname = 'trg_collection_master_set_finish_reject_update'),
    'detail','gatilhos: elegibilidade, bloqueio de UPDATE, presença diferida (acabamentos e coleção)');
  select res || jsonb_build_object('id','0.6','ok',
    md5(regexp_replace(regexp_replace(
      substring(p.prosrc from position('standard_denom AS (' in p.prosrc)
                         for position(E'\n    -- Ramo MASTER_SET' in p.prosrc) - position('standard_denom AS (' in p.prosrc)),
      '--[^\n]*', '', 'g'), '\s+', '', 'g')) = 'e8e0de6fd4871627ce49fc9ae73c6e6e'
    and md5(regexp_replace(regexp_replace(
      substring(p.prosrc from position('reference_position_target AS (' in p.prosrc)
                         for position(E'\n    denom AS (' in p.prosrc) - position('reference_position_target AS (' in p.prosrc)),
      '--[^\n]*', '', 'g'), '\s+', '', 'g')) = '812240ec1562dc0d6e53e0a8d2412ae5'
    and pg_get_function_result(p.oid) like 'TABLE(collection_id uuid, completion_policy text, total_positions bigint%',
    'detail','5188: ramos STANDARD_SET e REFERENCE_POSITION idênticos a 5102 (md5 normalizado); assinatura igual')
  into res
  from pg_proc p where p.oid = f_sum;
  if not found then
    res := res || jsonb_build_object('id','0.6','ok', false, 'detail','collection_completion_summary ausente');
  end if;

  -- linha de base ------------------------------------------------------------
  select count(*) into b_us from auth.users;
  select count(*) into b_co from public.collection;
  select count(*) into b_ca from public.collection_allocation;
  select count(*) into b_pc from public.physical_card;
  select count(*) into b_fn from public.collection_master_set_finish;
  select count(*) into b_card from public.card;
  select count(*) into b_cv from public.card_variant;
  select count(*) into b_cs from public.card_set;
  select count(*) into b_ex from public.expansion;

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
    select t.id into t_er   from public.card_variant_type t where t.game_id = v_game and t.code = 'ENERGY_REVERSE';
    select t.id into t_gold from public.card_variant_type t where t.game_id = v_game and t.code = 'GOLD_HOLO';
    select t.id into t_rb   from public.card_variant_type t where t.game_id = v_game and t.code = 'RAINBOW_HOLO';
    select t.id into t_cos  from public.card_variant_type t where t.game_id = v_game and t.code = 'COSMOS_HOLO';
    v_def := array[t_std, t_holo, t_rev];

    insert into public.expansion (id, game_id, code, name, release_order)
    values (v_exp, v_game, 'ZZMS5836_'||upper(v_sfx), 'MS 5836 '||v_sfx,
            (select coalesce(max(e.release_order), 0) + 1 from public.expansion e where e.game_id = v_game));
    insert into public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_set,  v_exp, 'ZZMS-'||upper(v_sfx),  'MS 5836 S',  'REGULAR', 1, 4, 6),
           (v_set2, v_exp, 'ZZMS2-'||upper(v_sfx), 'MS 5836 S2', 'REGULAR', 2, 1, 1);
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
    values (c1, v_set, v_rar, v_cat, '001', 4, 1, 'MS Um'),
           (c2, v_set, v_rar, v_cat, '002', 4, 2, 'MS Dois'),
           (c3, v_set, v_rar, v_cat, '003', 4, 3, 'MS Três'),
           (c4, v_set, v_rar, v_cat, '004', 4, 4, 'MS Quatro'),
           (c5, v_set, v_rar, v_cat, '005', 4, 5, 'MS Cinco Secreta'),
           (c6, v_set, v_rar, v_cat, '006', 4, 6, 'MS Seis Secreta'),
           (c7, v_set, v_rar, v_cat, 'TG01', 4, 7, 'MS Galeria'),
           (c9, v_set2, v_rar, v_cat, '001', 1, 1, 'MS S2 Um');
    insert into public.card_variant (id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id, variant_order, is_default, is_active)
    values (v_c1p,   c1, t_std,  null,  null, 1, true,  true),
           (v_c1pfe, c1, t_std,  v_fe,  null, 2, false, true),
           (v_c1r,   c1, t_rev,  null,  null, 3, false, true),
           (v_c1rl,  c1, t_rev,  null,  v_lg, 4, false, true),
           (v_c2h,   c2, t_holo, null,  null, 1, true,  true),
           (v_c2r,   c2, t_rev,  null,  null, 2, false, true),
           (v_c3p,   c3, t_std,  null,  null, 1, true,  true),
           (v_c3er,  c3, t_er,   null,  null, 2, false, true),
           (v_c4p,   c4, t_std,  null,  null, 1, true,  true),
           (v_c5g,   c5, t_gold, null,  null, 1, true,  true),
           (v_c6h,   c6, t_holo, null,  null, 1, true,  true),
           (v_c6g,   c6, t_gold, null,  null, 2, false, true),
           (v_c7rb,  c7, t_rb,   null,  null, 1, true,  true),
           (v_c9p,   c9, t_std,  null,  null, 1, true,  true);
    -- Set S3 (base 2): r1 001 Padrão · r2 002 Padrão · r3 003 Gold (secreta) — seção 12
    insert into public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_set3, v_exp, 'ZZMS3-'||upper(v_sfx), 'MS 5836 S3', 'REGULAR', 3, 2, 3);
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
    values (r1, v_set3, v_rar, v_cat, '001', 2, 1, 'MS S3 Um'),
           (r2, v_set3, v_rar, v_cat, '002', 2, 2, 'MS S3 Dois'),
           (r3, v_set3, v_rar, v_cat, '003', 2, 3, 'MS S3 Três Secreta');
    insert into public.card_variant (id, card_id, variant_type_id, printing_profile_id, edition_context_profile_id, variant_order, is_default, is_active)
    values (v_r1p, r1, t_std,  null, null, 1, true, true),
           (v_r2p, r2, t_std,  null, null, 1, true, true),
           (v_r3g, r3, t_gold, null, null, 1, true, true);

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'ms5836-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'ms5836a_'||v_sfx, 'display_name', 'MS 5836 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'ms5836-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'ms5836b_'||v_sfx, 'display_name', 'MS 5836 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = p_user_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = p_user_b;

    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1pfe, v_pt, v_inv_a) returning id into p1;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1rl,  v_pt, v_inv_a) returning id into p2;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c1rl,  v_pt, v_inv_a) returning id into p3;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c6g,   v_pt, v_inv_a) returning id into p4;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c3er,  v_pt, v_inv_a) returning id into p5;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c2h,   v_en, v_inv_a) returning id into p6;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_c4p,   v_pt, v_inv_a) returning id into p7;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_r1p,   v_pt, v_inv_a) returning id into p8;
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (v_r3g,   v_pt, v_inv_a) returning id into p9;

    -- coleções de A (como A)
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id, c.storage_container_id into v_ms, v_box
      from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'MS 5836 Master', null) c;
    select c.collection_id into v_sd   from public.create_my_card_set_collection(gen_random_uuid(), v_set,  'MS 5836 Padrão', v_box) c;
    select c.collection_id into v_s2   from public.create_my_card_set_collection(gen_random_uuid(), v_set2, 'MS 5836 S2', v_box) c;
    select c.collection_id into v_arch from public.create_my_card_set_collection(gen_random_uuid(), v_set,  'MS 5836 Arquivada', v_box) c;
    select c.collection_id into v_free from public.create_my_free_collection(gen_random_uuid(), 'MS 5836 Livre', v_box) c;
    perform public.allocate_physical_cards_to_collection(v_ms, array[p1,p2,p3,p4,p5,p6]);
    perform public.archive_collection(v_arch);
    select c.collection_id into v_r from public.create_my_card_set_collection(gen_random_uuid(), v_set3, 'MS 5836 S3', v_box) c;
    perform public.allocate_physical_cards_to_collection(v_r, array[p8,p9]);
    execute 'reset role';

    select md5(string_agg(pc.id::text||pc.card_variant_id::text||pc.language_id::text||coalesce(pc.storage_container_id::text,'')
                          ||coalesce(ca.collection_id::text,'-'), ',' order by pc.id))
      into v_fp_pres
    from public.physical_card pc left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.inventory_id = v_inv_a;

    res := res || jsonb_build_object('id','0.7','ok',
      v_game is not null and t_std is not null and t_rev is not null and t_er is not null and t_gold is not null
      and t_rb is not null and t_cos is not null and v_fe is not null and v_lg is not null and v_en is not null
      and v_inv_a is not null and v_ms is not null and v_sd is not null and v_free is not null
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_ms) = 6
      and v_r is not null and (select count(*) from public.collection_allocation ca where ca.collection_id = v_r) = 2,
      'detail','fixture sintética: 3 Sets, 11 cartas, 17 variantes, 9 exemplares de A (6 em v_ms, 2 em v_r)');

    -- 1. anon --------------------------------------------------------------------
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    v_cnt := 0;
    begin perform public.preview_my_master_set_finishes(v_ms, v_def); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.set_collection_completion_policy_to_master_set(v_ms, v_def); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.replace_master_set_finishes(v_ms, v_def); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.get_my_master_set_positions(v_ms, 'ALL', 10, 0); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.get_my_master_set_finish_options(v_ms); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.get_my_master_set_out_of_scope_copies(v_ms, 10, 0); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_cnt = 6, 'detail','anon recusado (42501) nos 6 contratos: '||v_cnt||'/6');

    -- 2. sem identidade -------------------------------------------------------
    execute 'set local role authenticated';
    v_cnt := 0;
    begin perform public.set_collection_completion_policy_to_master_set(v_ms, v_def); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.get_my_master_set_positions(v_ms, 'ALL', 10, 0); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.preview_my_master_set_finishes(v_ms, v_def); exception when others then if sqlstate = '28000' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.master_set_positions(v_set, v_def); v_state := 'executou'; exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_cnt = 3, 'detail','sem identidade → 28000 em 3 contratos: '||v_cnt||'/3');
    res := res || jsonb_build_object('id','2.2','ok', v_state = '42501', 'detail','função interna master_set_positions inacessível ao cliente: '||v_state);
    -- 2.3 funções internas de escrita/validação não executáveis pelo cliente, mesmo identificado como dono
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    v_cnt := 0;
    begin perform public.apply_master_set_finishes(v_ms, p_user_a, v_def); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.normalize_master_set_finishes(v_set, v_game, v_def); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.check_master_set_scope_presence(v_ms); exception when others then if sqlstate = '42501' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    res := res || jsonb_build_object('id','2.3','ok', v_cnt = 3
      and not exists (select 1 from public.collection_master_set_finish f where f.collection_id = v_ms),
      'detail','apply/normalize/presença internos recusados (42501) para o dono autenticado: '||v_cnt||'/3; nada gravado');

    -- 7.1 prévia antes de ativar (coleção ainda em Set padrão) ------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.preview_my_master_set_finishes(v_ms, v_def);
    res := res || jsonb_build_object('id','7.1','ok',
      v_rec.current_policy = 'STANDARD_SET' and v_rec.current_total = 7 and v_rec.current_satisfied = 4
      and v_rec.proposed_total = 8 and v_rec.proposed_satisfied = 3 and v_rec.proposed_secret_positions = 1
      and v_rec.positions_added = 8 and v_rec.positions_removed = 0
      and v_rec.copies_in_collection = 6 and v_rec.copies_outside_after = 2,
      'detail', format('prévia em Set padrão: atual %s/%s → proposto %s/%s (secretas %s), fora do objetivo %s',
        v_rec.current_satisfied, v_rec.current_total, v_rec.proposed_satisfied, v_rec.proposed_total,
        v_rec.proposed_secret_positions, v_rec.copies_outside_after));

    -- 3. cálculo -----------------------------------------------------------------
    select * into v_rec2 from public.set_collection_completion_policy_to_master_set(v_ms, v_def);
    res := res || jsonb_build_object('id','3.1','ok',
      v_rec2.completion_policy = 'MASTER_SET' and v_rec2.finishes_added = 3 and v_rec2.finishes_removed = 0
      and v_rec2.total_positions = 8 and v_rec2.satisfied_positions = 3,
      'detail', format('ativação {Padrão, Holo, Reverse}: %s/%s, +%s', v_rec2.satisfied_positions, v_rec2.total_positions, v_rec2.finishes_added));
    res := res || jsonb_build_object('id','7.2','ok',
      v_rec2.total_positions = v_rec.proposed_total and v_rec2.satisfied_positions = v_rec.proposed_satisfied,
      'detail','gravação = prévia (total e satisfeitas)');
    select s.total_positions, s.satisfied_positions into v_cnt, v_cnt2 from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','3.2','ok', v_cnt = 8 and v_cnt2 = 3, 'detail','resumo (5188) 3/8');

    select count(*) into v_cnt from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0);
    res := res || jsonb_build_object('id','3.3','ok', v_cnt = 8
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
                  where g.card_id = c5 and g.variant_type_id is null and g.is_secret and not g.is_satisfied)
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
                  where g.card_id = c6 and g.variant_type_id = t_holo and g.is_secret)
      and not exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.card_id = c7)
      and not exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.card_id = c6 and g.variant_type_id is null),
      'detail','grade: 8 posições; c5 secreta como posição de carta; c6 secreta contemplada pelo Holo (sem duplicar); TG01 não é secreta');
    res := res || jsonb_build_object('id','3.4','ok',
      exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
              where g.card_id = c1 and g.variant_type_id = t_rev and g.is_satisfied and g.copies_in_collection = 2)
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
              where g.card_id = c1 and g.variant_type_id = t_std and g.is_satisfied and g.copies_in_collection = 1)
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
              where g.card_id = c2 and g.variant_type_id = t_holo and g.is_satisfied)
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
              where g.card_id = c4 and g.variant_type_id = t_std and not g.is_satisfied and g.copies_available = 1),
      'detail','contexto Liga, 1ª Edição e idioma inglês satisfazem; repetida conta 2 exemplares e 1 posição; acervo disponível contado');
    res := res || jsonb_build_object('id','3.5','ok',
      (select count(*) from public.get_my_master_set_positions(v_ms, 'OWNED', 500, 0)) = 3
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'MISSING', 500, 0)) = 5
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 3, 3)) = 3
      and (select max(g.total_count) from public.get_my_master_set_positions(v_ms, 'ALL', 3, 3)) = 8,
      'detail','filtros OWNED 3 / MISSING 5; paginação com total do filtro');
    res := res || jsonb_build_object('id','3.6','ok',
      (select count(*) from public.get_my_master_set_finish_options(v_ms) o where o.row_kind = 'FINISH') = 6
      and exists (select 1 from public.get_my_master_set_finish_options(v_ms) o
                  where o.variant_type_id = t_std and o.positions = 3 and o.owned_positions = 1 and o.is_selected)
      and exists (select 1 from public.get_my_master_set_finish_options(v_ms) o
                  where o.variant_type_id = t_er and o.positions = 1 and o.owned_positions = 1 and not o.is_selected)
      and exists (select 1 from public.get_my_master_set_finish_options(v_ms) o
                  where o.row_kind = 'SECRET_CARDS' and o.positions = 2 and o.owned_positions = 1)
      and not exists (select 1 from public.get_my_master_set_finish_options(v_ms) o where o.variant_type_id = t_cos),
      'detail','opções: 6 acabamentos existentes no Set (sem Cosmos), seleção marcada, bloco de 2 secretas');
    res := res || jsonb_build_object('id','3.7','ok',
      (select count(*) from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0)) = 2
      and (select bool_and(o.reason = 'FINISH_NOT_SELECTED') from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0) o)
      and exists (select 1 from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0) o where o.physical_card_id = p4)
      and exists (select 1 from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0) o where o.physical_card_id = p5),
      'detail','fora do objetivo: Gold da c6 e Energia Reverse da c3, motivo FINISH_NOT_SELECTED, ainda vinculados');

    -- 4. validação ------------------------------------------------------------
    v_cnt := 0;
    begin perform public.replace_master_set_finishes(v_ms, null); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_FINISHES' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.replace_master_set_finishes(v_ms, '{}'::uuid[]); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_FINISHES' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.replace_master_set_finishes(v_ms, array[t_std, t_std]); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_FINISHES' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.replace_master_set_finishes(v_ms, array[t_std, null]); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_FINISHES' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.replace_master_set_finishes(v_ms, (select array_agg(gen_random_uuid()) from generate_series(1, 65))); exception when others then if sqlstate = '22023' and sqlerrm = 'INVALID_FINISHES' then v_cnt := v_cnt + 1; end if; end;
    res := res || jsonb_build_object('id','4.1','ok', v_cnt = 5, 'detail','nulo, vazio, repetido, elemento nulo, > 64 → INVALID_FINISHES: '||v_cnt||'/5');
    begin perform public.replace_master_set_finishes(v_ms, array[t_std, t_cos]); v_err := 'executou'; exception when others then v_err := sqlstate||' '||sqlerrm; end;
    res := res || jsonb_build_object('id','4.2','ok', v_err = 'P0001 FINISH_NOT_IN_SET', 'detail','acabamento inexistente no Set (Cosmos): '||v_err);
    begin perform public.preview_my_master_set_finishes(v_ms, array[t_std, t_cos]); v_err := 'executou'; exception when others then v_err := sqlstate||' '||sqlerrm; end;
    res := res || jsonb_build_object('id','4.3','ok', v_err = 'P0001 FINISH_NOT_IN_SET', 'detail','prévia recusa igual à gravação: '||v_err);
    begin insert into public.collection_master_set_finish (collection_id, variant_type_id, adopted_by_user_id) values (v_ms, t_er, p_user_a); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    begin update public.collection_master_set_finish set adopted_at = now() where collection_id = v_ms; v_err := 'executou';
    exception when others then v_err := sqlstate; end;
    begin delete from public.collection_master_set_finish where collection_id = v_ms; v_msg_dummy := 'executou';
    exception when others then v_msg_dummy := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok', v_state = '42501', 'detail','escrita direta na tabela pelo cliente: '||v_state);
    res := res || jsonb_build_object('id','4.8','ok', v_err = '42501' and v_msg_dummy = '42501'
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 3,
      'detail','UPDATE e DELETE diretos pelo próprio dono recusados: '||v_err||' / '||v_msg_dummy||'; 3 acabamentos intactos');
    begin insert into public.collection_master_set_finish (collection_id, variant_type_id, adopted_by_user_id) values (v_ms, t_cos, p_user_a); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    res := res || jsonb_build_object('id','4.5','ok', v_state = '23514', 'detail','gatilho 5185 barra acabamento sem carta no Set mesmo sem RPC: '||v_state);
    begin update public.collection_master_set_finish set adopted_at = now() where collection_id = v_ms; v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    res := res || jsonb_build_object('id','4.6','ok', v_state = '23514', 'detail','UPDATE bloqueado (insert/delete-only): '||v_state);
    begin insert into public.collection_master_set_finish (collection_id, variant_type_id, adopted_by_user_id) values (v_free, t_std, p_user_a); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    res := res || jsonb_build_object('id','4.7','ok', v_state = '23514', 'detail','gatilho 5185 barra coleção livre: '||v_state);

    -- 5. edição, idempotência, presença, alternância --------------------------
    select f.adopted_at into v_adopt from public.collection_master_set_finish f where f.collection_id = v_ms and f.variant_type_id = t_std;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.preview_my_master_set_finishes(v_ms, array[t_std]);
    select string_agg(f.variant_type_id::text||f.xmin::text, ',' order by f.variant_type_id) into v_fp
      from public.collection_master_set_finish f where f.collection_id = v_ms;
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_std]);
    res := res || jsonb_build_object('id','7.3','ok',
      v_rec.proposed_total = 5 and v_rec.proposed_satisfied = 2 and v_rec.positions_added = 1 and v_rec.positions_removed = 4
      and v_rec.copies_outside_after = 4,
      'detail', format('prévia {Padrão} em Master Set: %s/%s, +%s −%s, fora %s', v_rec.proposed_satisfied, v_rec.proposed_total,
        v_rec.positions_added, v_rec.positions_removed, v_rec.copies_outside_after));
    res := res || jsonb_build_object('id','5.1','ok',
      v_rec2.total_positions = 5 and v_rec2.satisfied_positions = 2
      and v_rec2.finishes_added = 0 and v_rec2.finishes_removed = 2 and v_rec2.finishes_kept = 1
      and v_rec2.total_positions = v_rec.proposed_total and v_rec2.satisfied_positions = v_rec.proposed_satisfied,
      'detail','um acabamento só ({Padrão}): 2/5 (secretas c5 e c6 como posição de carta; Gold da c6 satisfaz), = prévia');
    execute 'reset role';
    res := res || jsonb_build_object('id','5.2','ok',
      (select f.adopted_at from public.collection_master_set_finish f where f.collection_id = v_ms and f.variant_type_id = t_std) = v_adopt,
      'detail','acabamento mantido preserva adopted_at');
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select string_agg(f.variant_type_id::text||f.xmin::text, ',' order by f.variant_type_id) into v_fp
      from public.collection_master_set_finish f where f.collection_id = v_ms;
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_std]);
    select string_agg(f.variant_type_id::text||f.xmin::text, ',' order by f.variant_type_id) into v_fp2
      from public.collection_master_set_finish f where f.collection_id = v_ms;
    res := res || jsonb_build_object('id','5.3','ok',
      v_rec2.finishes_added = 0 and v_rec2.finishes_removed = 0 and v_rec2.finishes_kept = 1 and v_fp = v_fp2,
      'detail','mesmo conjunto de novo: zero escrita (idempotente)');
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_er]);
    res := res || jsonb_build_object('id','5.4','ok', v_rec2.total_positions = 3 and v_rec2.satisfied_positions = 2,
      'detail','{Energia Reverse}: 2/3 (c3 ER + secretas c5 e c6)');
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_gold]);
    res := res || jsonb_build_object('id','5.5','ok', v_rec2.total_positions = 2 and v_rec2.satisfied_positions = 1,
      'detail','{Gold}: secretas viram posições de acabamento, sem duplicar: 1/2');
    -- 11. transições da posição de carta secreta (estado de partida: {Gold}) ---
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_std]);
    res := res || jsonb_build_object('id','11.1','ok',
      v_rec2.total_positions = 5 and v_rec2.satisfied_positions = 2
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.variant_type_id is null) = 2
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
                  where g.card_id = c6 and g.variant_type_id is null and g.is_satisfied and g.copies_in_collection = 1),
      'detail','{Padrão}: c5 e c6 sem acabamento escolhido → 2 posições genéricas; Gold da c6 satisfaz a genérica (2/5)');
    select * into v_rec from public.preview_my_master_set_finishes(v_ms, array[t_std, t_gold]);
    res := res || jsonb_build_object('id','11.2','ok',
      v_rec.proposed_total = 5 and v_rec.proposed_satisfied = 2 and v_rec.positions_added = 2 and v_rec.positions_removed = 2
      and v_rec.proposed_secret_positions = 0,
      'detail', format('prévia incluir Gold: %s/%s, +%s (c5/c6 Gold) −%s (genéricas), genéricas restantes %s',
        v_rec.proposed_satisfied, v_rec.proposed_total, v_rec.positions_added, v_rec.positions_removed, v_rec.proposed_secret_positions));
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_std, t_gold]);
    res := res || jsonb_build_object('id','11.3','ok',
      v_rec2.total_positions = 5 and v_rec2.satisfied_positions = 2
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.variant_type_id is null) = 0
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
                  where g.card_id = c6 and g.variant_type_id = t_gold and g.is_secret and g.is_satisfied and g.copies_in_collection = 1)
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
                  where g.card_id = c5 and g.variant_type_id = t_gold and g.is_secret and not g.is_satisfied)
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.card_id = c6) = 1
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0))
          = (select count(distinct (g.card_id, g.variant_type_id)) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g),
      'detail','incluir Gold: genéricas substituídas pelas específicas, sem duplicar; progresso preservado (2/5, mesmo exemplar)');
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_std]);
    res := res || jsonb_build_object('id','11.4','ok',
      v_rec2.total_positions = 5 and v_rec2.satisfied_positions = 2
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.variant_type_id is null) = 2
      and not exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.variant_type_id = t_gold),
      'detail','retirar Gold: posições genéricas restauradas para c5 e c6 (2/5)');
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, array[t_std, t_holo]);
    res := res || jsonb_build_object('id','11.5','ok',
      v_rec2.total_positions = 6 and v_rec2.satisfied_positions = 2
      and exists (select 1 from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g
                  where g.card_id = c6 and g.variant_type_id = t_holo and g.is_secret and not g.is_satisfied)
      and (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0) g where g.variant_type_id is null) = 1
      and exists (select 1 from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0) o
                  where o.physical_card_id = p4 and o.reason = 'FINISH_NOT_SELECTED'),
      'detail','incluir Holo: c6 passa a exigir Holo; o Gold deixa de satisfazer (fora do objetivo, ainda vinculado); c5 segue genérica (2/6)');
    select * into v_rec2 from public.replace_master_set_finishes(v_ms, v_def);
    res := res || jsonb_build_object('id','5.6','ok', v_rec2.total_positions = 8 and v_rec2.satisfied_positions = 3,
      'detail','volta a {Padrão, Holo, Reverse}: 3/8');
    -- alternância
    perform public.set_collection_completion_policy_to_standard_set(v_ms);
    select s.completion_policy, s.total_positions, s.satisfied_positions into v_rec from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','5.7','ok',
      v_rec.completion_policy = 'STANDARD_SET' and v_rec.total_positions = 7 and v_rec.satisfied_positions = 4
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 3,
      'detail','Set padrão: 4/7 por carta; os 3 acabamentos continuam guardados');
    begin perform public.replace_master_set_finishes(v_ms, v_def); v_err := 'executou'; exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.8','ok', v_err = 'MASTER_SET_NOT_ACTIVE', 'detail','editar em Set padrão: '||v_err);
    select * into v_rec2 from public.set_collection_completion_policy_to_master_set(v_ms, null);
    res := res || jsonb_build_object('id','5.9','ok',
      v_rec2.total_positions = 8 and v_rec2.satisfied_positions = 3 and v_rec2.finishes_kept = 3 and v_rec2.finishes_added = 0,
      'detail','reativar sem lista restaura a seleção guardada: 3/8');
    select * into v_rec2 from public.set_collection_completion_policy_to_master_set(v_ms, null);
    res := res || jsonb_build_object('id','5.10','ok', v_rec2.total_positions = 8 and v_rec2.finishes_added = 0 and v_rec2.finishes_removed = 0,
      'detail','reenvio da ativação: no-op, sem erro');
    begin perform public.set_collection_completion_policy_to_master_set(v_sd, null); v_err := 'executou'; exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.11','ok', v_err = 'NO_SAVED_FINISHES', 'detail','ativar sem lista e sem seleção guardada: '||v_err);
    perform public.set_collection_completion_policy_to_master_set(v_s2, array[t_std]);
    perform public.set_collection_completion_policy_to_standard_set(v_s2);
    execute 'reset role';
    update public.card set is_active = false where id = c9;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.set_collection_completion_policy_to_master_set(v_s2, null); v_err := 'executou'; exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','5.12','ok',
      v_err = 'EMPTY_OBJECTIVE' and (select c.completion_policy from public.collection c where c.id = v_s2) = 'STANDARD_SET',
      'detail','restaurar seleção que não gera nenhuma posição: '||v_err||'; política inalterada');
    execute 'reset role';
    -- presença diferida: apagar todos os acabamentos sem repor
    begin
      delete from public.collection_master_set_finish where collection_id = v_ms;
      execute 'set constraints all immediate';
      v_err := 'passou';
    exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','5.13','ok', v_err = '23514'
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 3,
      'detail','Master Set sem acabamento recusado no fim da transação: '||v_err);
    begin
      delete from public.collection_master_set_finish where collection_id = v_ms;
      insert into public.collection_master_set_finish (collection_id, variant_type_id, adopted_by_user_id)
      select v_ms, x, p_user_a from unnest(v_def) x;
      execute 'set constraints all immediate';
      v_err := 'passou';
    exception when others then v_err := sqlstate; end;
    execute 'set constraints all deferred';
    res := res || jsonb_build_object('id','5.14','ok', v_err = 'passou', 'detail','trocar todos os acabamentos numa mesma transação: '||v_err);

    -- 6. evolução do catálogo (como dono do banco) ----------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'reset role';
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active) values (c4, t_holo, 2, false, true);
    select s.total_positions, s.satisfied_positions into v_cnt, v_cnt2 from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.1','ok', v_cnt = 9 and v_cnt2 = 3
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 3,
      'detail','novo acabamento escolhido numa carta existente (c4 Holo) entra sozinho: 3/9; seleção intacta');
    insert into public.card_variant (card_id, variant_type_id, printing_profile_id, variant_order, is_default, is_active) values (c2, t_rev, v_fe, 3, false, true);
    select s.total_positions into v_cnt from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.2','ok', v_cnt = 9, 'detail','nova variante num par existente (c2 Reverse 1ª Ed.) não cria posição');
    update public.card_variant set is_active = false where id = v_c1rl;
    select s.total_positions, s.satisfied_positions into v_cnt, v_cnt2 from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.3','ok', v_cnt = 9 and v_cnt2 = 3,
      'detail','desativar a Reverse Liga com a Reverse comum ativa: exemplares Liga continuam satisfazendo (3/9)');
    update public.card_variant set is_active = false where id = v_c1r;
    select s.total_positions, s.satisfied_positions into v_cnt, v_cnt2 from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.4','ok', v_cnt = 8 and v_cnt2 = 2,
      'detail','última Reverse da c1 desativada: posição sai (2/8)');
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0) o
      where o.reason = 'PAIR_NOT_IN_CATALOG' and o.physical_card_id in (p2, p3);
    execute 'reset role';
    res := res || jsonb_build_object('id','6.5','ok', v_cnt = 2
      and (select count(*) from public.collection_allocation ca where ca.physical_card_id in (p2,p3) and ca.collection_id = v_ms) = 2,
      'detail','exemplares Liga ficam fora do objetivo com motivo PAIR_NOT_IN_CATALOG, ainda vinculados');
    update public.card set is_active = false where id = c2;
    select s.total_positions, s.satisfied_positions into v_cnt, v_cnt2 from public.collection_completion_summary(v_ms) s;
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select o.reason into v_err from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0) o where o.physical_card_id = p6;
    execute 'reset role';
    res := res || jsonb_build_object('id','6.6','ok', v_cnt = 6 and v_cnt2 = 1 and v_err = 'CARD_INACTIVE',
      'detail','carta c2 desativada: suas posições saem (1/6); exemplar com motivo '||coalesce(v_err,'-'));
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
      values (c8, v_set, v_rar, v_cat, '007', 4, 8, 'MS Sete Secreta');
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active) values (c8, t_gold, 1, true, true);
    select s.total_positions into v_cnt from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.7','ok', v_cnt = 7, 'detail','nova carta secreta no Set entra obrigatoriamente: 7 posições');
    update public.card_variant set variant_type_id = t_rev where id = v_c3er;
    select s.total_positions, s.satisfied_positions into v_cnt, v_cnt2 from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.8','ok', v_cnt = 8 and v_cnt2 = 2,
      'detail','reclassificação Energia Reverse → Reverse: par novo c3 Reverse, satisfeito pelo mesmo exemplar (2/8)');
    update public.card_set set base_set_size = 8 where id = v_set;
    select s.total_positions, s.satisfied_positions into v_cnt, v_cnt2 from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.9','ok', v_cnt = 6 and v_cnt2 = 2,
      'detail','Set base ampliado para 8: c5/c6/c8 deixam de ser secretas; c6 segue pelo Holo (2/6)');
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active) values (c3, t_gold, 3, false, true);
    select s.total_positions into v_cnt from public.collection_completion_summary(v_ms) s;
    res := res || jsonb_build_object('id','6.10','ok', v_cnt = 6,
      'detail','novo acabamento NÃO escolhido numa carta existente (c3 Gold) não entra no objetivo');

    -- 8. regressão -------------------------------------------------------------
    v_ok := true; v_cnt := 0;
    for v_rec in
      select c.id, c.owner_user_id, ccsr.card_set_id
      from public.collection c
      join public.collection_reference cr on cr.collection_id = c.id
      join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
      where c.completion_policy = 'STANDARD_SET'
      order by c.id
    loop
      perform set_config('request.jwt.claims', json_build_object('sub', v_rec.owner_user_id, 'role','authenticated')::text, true);
      v_cnt := v_cnt + 1;
      if not coalesce((
        select s.total_positions = (select count(*) from public.card k where k.card_set_id = v_rec.card_set_id)
           and s.satisfied_positions = (select count(distinct cv.card_id)
                                        from public.collection_allocation ca
                                        join public.physical_card pc on pc.id = ca.physical_card_id
                                        join public.card_variant cv on cv.id = pc.card_variant_id
                                        join public.card k on k.id = cv.card_id and k.card_set_id = v_rec.card_set_id
                                        where ca.collection_id = v_rec.id)
        from public.collection_completion_summary(v_rec.id) s), false) then
        v_ok := false;
      end if;
    end loop;
    perform set_config('request.jwt.claims', '', true);
    res := res || jsonb_build_object('id','8.1','ok', v_ok and v_cnt >= 3,
      'detail', format('Set padrão: resumo = contagem independente em %s coleção(ões) STANDARD_SET (inclui as reais, só leitura)', v_cnt));
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from public.get_my_collection_positions(v_sd, 'ALL', 500, 0);
    select count(*) into v_cnt2 from public.get_my_master_set_positions(v_sd, 'ALL', 500, 0);
    execute 'reset role';
    res := res || jsonb_build_object('id','8.2','ok', v_cnt = 8 and v_cnt2 = 0,
      'detail','R2 do Set padrão (5169) segue funcionando (8 cartas); leitura do Master Set não lê coleção STANDARD_SET');
    res := res || jsonb_build_object('id','8.3','ok',
      not exists (select 1 from public.collection c where c.completion_policy = 'REFERENCE_POSITION'
                  and c.id in (select collection_id from public.collection_master_set_finish)),
      'detail','Pokédex: nenhuma coleção REFERENCE_POSITION com acabamento (ramo Pokédex coberto pelo md5 de 0.6)');

    -- 9. isolamento -------------------------------------------------------------
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    res := res || jsonb_build_object('id','9.1','ok',
      (select count(*) from public.get_my_master_set_positions(v_ms, 'ALL', 500, 0)) = 0
      and (select count(*) from public.get_my_master_set_finish_options(v_ms)) = 0
      and (select count(*) from public.get_my_master_set_out_of_scope_copies(v_ms, 500, 0)) = 0
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 0,
      'detail','B não lê grade, opções, fora do objetivo nem a tabela de acabamentos de A');
    v_cnt := 0;
    begin perform public.preview_my_master_set_finishes(v_ms, v_def); exception when others then if sqlerrm = 'COLLECTION_NOT_FOUND' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.set_collection_completion_policy_to_master_set(v_ms, v_def); exception when others then if sqlerrm = 'COLLECTION_NOT_FOUND' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.replace_master_set_finishes(v_ms, v_def); exception when others then if sqlerrm = 'COLLECTION_NOT_FOUND' then v_cnt := v_cnt + 1; end if; end;
    begin perform public.replace_master_set_finishes(gen_random_uuid(), v_def); exception when others then if sqlerrm = 'COLLECTION_NOT_FOUND' then v_cnt := v_cnt + 1; end if; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','9.2','ok', v_cnt = 4, 'detail','B em coleção de A e coleção inexistente: mesma resposta COLLECTION_NOT_FOUND ('||v_cnt||'/4)');
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin perform public.set_collection_completion_policy_to_master_set(v_free, v_def); v_err := 'executou'; exception when others then v_err := sqlerrm; end;
    begin perform public.set_collection_completion_policy_to_master_set(v_arch, v_def); v_state := 'executou'; exception when others then v_state := sqlerrm; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','9.3','ok', v_err = 'MASTER_SET_REQUIRES_SET_COLLECTION' and v_state = 'COLLECTION_ARCHIVED',
      'detail','coleção livre: '||v_err||'; arquivada: '||v_state);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    begin delete from public.collection_master_set_finish where collection_id = v_ms; v_err := 'executou'; exception when others then v_err := sqlstate; end;
    begin insert into public.collection_master_set_finish (collection_id, variant_type_id, adopted_by_user_id) values (v_ms, t_er, p_user_b); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','9.4','ok', v_err = '42501' and v_state = '42501'
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_ms) = 3,
      'detail','B: DELETE/INSERT direto nos acabamentos de A recusados ('||v_err||'/'||v_state||'); intactos');

    -- 12. reativação após mudança de catálogo durante o Set padrão (Set S3) ----
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec2 from public.set_collection_completion_policy_to_master_set(v_r, array[t_std]);
    res := res || jsonb_build_object('id','12.1','ok', v_rec2.total_positions = 3 and v_rec2.satisfied_positions = 2,
      'detail','S3 ativado com {Padrão}: r1, r2 + secreta r3 genérica (satisfeita pelo Gold) = 2/3');
    perform public.set_collection_completion_policy_to_standard_set(v_r);
    select s.completion_policy, s.total_positions, s.satisfied_positions into v_rec from public.collection_completion_summary(v_r) s;
    res := res || jsonb_build_object('id','12.2','ok',
      v_rec.completion_policy = 'STANDARD_SET' and v_rec.total_positions = 3 and v_rec.satisfied_positions = 2
      and (select count(*) from public.collection_master_set_finish f where f.collection_id = v_r) = 1,
      'detail','volta ao Set padrão: 2/3 por carta; acabamento guardado');
    execute 'reset role';
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active) values (r2, t_rev, 2, false, true);
    insert into public.card_variant (card_id, variant_type_id, printing_profile_id, variant_order, is_default, is_active) values (r1, t_std, v_fe, 2, false, true);
    insert into public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
      values (r4, v_set3, v_rar, v_cat, '004', 2, 4, 'MS S3 Quatro Secreta');
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default, is_active) values (r4, t_std, 1, true, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select * into v_rec from public.preview_my_master_set_finishes(v_r, array[t_std]);
    select string_agg(f.variant_type_id::text||f.xmin::text||f.adopted_at::text, ',') into v_fp
      from public.collection_master_set_finish f where f.collection_id = v_r;
    select * into v_rec2 from public.set_collection_completion_policy_to_master_set(v_r, null);
    res := res || jsonb_build_object('id','12.3','ok',
      v_rec2.total_positions = 4 and v_rec2.satisfied_positions = 2
      and v_rec2.finishes_kept = 1 and v_rec2.finishes_added = 0 and v_rec2.finishes_removed = 0,
      'detail','reativar restaurando {Padrão}: novo denominador 4 (r1, r2, r4 Padrão secreta, r3 genérica); Reverse novo não entra; 1ª Ed. não cria posição (2/4)');
    res := res || jsonb_build_object('id','12.4','ok',
      v_rec.current_policy = 'STANDARD_SET' and v_rec.proposed_total = v_rec2.total_positions
      and v_rec.proposed_satisfied = v_rec2.satisfied_positions,
      'detail','prévia feita em Set padrão = resultado da reativação');
    select * into v_rec2 from public.set_collection_completion_policy_to_master_set(v_r, null);
    select string_agg(f.variant_type_id::text||f.xmin::text||f.adopted_at::text, ',') into v_fp2
      from public.collection_master_set_finish f where f.collection_id = v_r;
    res := res || jsonb_build_object('id','12.5','ok',
      v_rec2.total_positions = 4 and v_rec2.finishes_added = 0 and v_rec2.finishes_removed = 0 and v_fp = v_fp2,
      'detail','reativar de novo: no-op idempotente; acabamento guardado sem regravação (mesmo xmin e adopted_at)');
    res := res || jsonb_build_object('id','12.6','ok',
      exists (select 1 from public.get_my_master_set_positions(v_r, 'ALL', 500, 0) g
              where g.card_id = r4 and g.variant_type_id = t_std and g.is_secret and not g.is_satisfied)
      and exists (select 1 from public.get_my_master_set_positions(v_r, 'ALL', 500, 0) g
              where g.card_id = r3 and g.variant_type_id is null and g.is_satisfied)
      and not exists (select 1 from public.get_my_master_set_positions(v_r, 'ALL', 500, 0) g where g.variant_type_id = t_rev)
      and (select count(*) from public.get_my_master_set_out_of_scope_copies(v_r, 500, 0)) = 0,
      'detail','grade do objetivo restaurado: r4 secreta pelo Padrão, r3 genérica satisfeita, nenhum Reverse, nenhum exemplar fora do objetivo');
    execute 'reset role';

    -- 10. preservação -----------------------------------------------------------
    select md5(string_agg(pc.id::text||pc.card_variant_id::text||pc.language_id::text||coalesce(pc.storage_container_id::text,'')
                          ||coalesce(ca.collection_id::text,'-'), ',' order by pc.id))
      into v_fp
    from public.physical_card pc left join public.collection_allocation ca on ca.physical_card_id = pc.id
    where pc.inventory_id = v_inv_a;
    res := res || jsonb_build_object('id','10.1','ok', v_fp = v_fp_pres,
      'detail','exemplares de A: mesma variante, idioma, local e vínculo depois de todas as operações de objetivo e catálogo');
    res := res || jsonb_build_object('id','10.2','ok',
      (select count(*) from public.collection_allocation ca where ca.collection_id = v_ms) = 6
      and (select count(*) from public.collection_allocation ca where ca.collection_id = v_r) = 2
      and (select count(*) from public.physical_card pc where pc.inventory_id = v_inv_a) = 9,
      'detail','6 + 2 vínculos e 9 exemplares — nenhum criado, apagado ou desvinculado');

    raise exception 'MS000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS000' then
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
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, vínculos, exemplares, acabamentos, catálogo) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 999; check_id := 'GATE';
  status := case when passes = n and n = 74 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 74)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.ms_5836_validate();
