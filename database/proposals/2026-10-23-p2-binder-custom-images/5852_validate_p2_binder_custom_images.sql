/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5852 - Harness P2-BINDER-CUSTOM-IMAGES (5231–5236): imagem
              personalizada do bolso — estrutura, políticas de arquivo,
              outro usuário, exclusividade com carta/reserva/trava/mesclagem,
              caminho e metadados, substituição, enquadramento, limite,
              leituras compartilhadas, remoção de página, desmontagem,
              não regressão e resíduo zero
Versão......: 1.1 (2026-10-23, AUDIT-CORRECTION-01: 0.8 e 2.12 — arquivo
              vinculado indelével; FOR SHARE; GUC de exclusão do Storage)
              1.0 (2026-10-23, P2-BINDER-CUSTOM-IMAGES-PROPOSAL-01)
Status......: PROPOSTA — NÃO EXECUTADA. Executar só com autorização de
              Fabrício, DEPOIS de 5231 → 5236 aplicadas no ambiente-alvo.
              A função inteira CRIA dados (desfeitos pela sentinela) e
              segue a regra da 5851: não executar no LIVE sem autorização
              expressa. As consultas da Seção 0 são somente leitura e
              servem de base para o LIVE_90 (pós-checagem) a escrever na
              rodada de aplicação.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-23

Protocolo (o mesmo da 5851): um único statement, usuários efêmeros A e B,
catálogo SINTÉTICO mínimo (1 Set, 1 carta, 1 variante STANDARD); linhas de
storage.objects SINTÉTICAS (só metadados — nenhum arquivo é enviado);
a sentinela MS852 desfaz tudo; 99.1 prova resíduo zero.

  select * from pg_temp.wh_5852_validate();

Fixture:
  A — local BIN (BINDER); CO Livre com o1 → fichário 2×2 (o1 no bolso 1,1);
      CG Livre com g1 → convidada do fichário de CO;
      local BIN2; CH Livre com h1 → fichário próprio 2×2 (+126 páginas
      pelo RPC add_layout_page, para o limite e a desmontagem).
  B — local LB; CB Livre com b1 e fichário 2×2.
  Bolsos de CO, página 1: s1 (1,1, o1) · s2 (1,2) · s3 (2,1) · s4 (2,2).

Seções:
  0  estrutura (somente leitura): bucket, políticas, tabela, gatilhos, RPCs
  1  arquivos e segurança: políticas do bucket como A; anon; B não lê nem
     escreve no fichário de A (sem enumerar); A não lê a tabela direto
  2  escrita e exclusividade: ocupado/travado/reservado recusados; ADDED
     pela proprietária e pela convidada (D2); UNCHANGED; carta, reserva,
     trava e mesclagem recusadas em bolso com imagem; caminho/metadados;
     REPLACED sem apagar o antigo; enquadramento
  3  leituras: mesmas imagens pela proprietária e pela convidada; resumo;
     arquivos sem vínculo (carência de 1 h)
  4  limite de 500 (ADDED no 500º, recusa no 501º); remoção de página com
     imagem recusada; remover (REMOVED/ALREADY_ABSENT); desmontagem com
     images_removed e image_paths; não regressão de cartas/alocações
  99 resíduo zero e papel restaurado

Provas deliberadamente FORA (proporcionalidade, declaradas):
  L1 SET LOCAL ROLE prova o banco, não o JWT do PostgREST nem a API do
     Storage. Tamanho/tipo no envio são aplicados pela API do Storage com
     a configuração do bucket (Seção 0 confere a configuração).
  L2 Um único statement não tem duas sessões: a serialização pela trava
     do fichário (5122) e o advisory lock do limite não são exercitados.
  L3 O teto de 550 arquivos da política de INSERT é conferido só
     estruturalmente (criar 550 linhas não acrescenta prova útil).
  L4 Inserir em storage.objects como dono do banco exige o privilégio
     padrão do Supabase para `postgres`; sem ele, F.2 falha e o resto
     não roda. Versões recentes do Storage bloqueiam DELETE direto em
     storage.objects por gatilho, liberado por `storage.allow_delete_query`;
     o harness liga esse GUC só na transação (1.2, 2.12). Se o nome do GUC
     divergir no ambiente, 1.2/2.12 falham com o erro do gatilho e devem
     ser lidos como "proteção extra do Storage", não como defeito da 5232.
  L5 A corrida limpeza × vínculo (FOR SHARE + reavaliação da política DELETE)
     exige duas sessões: roteiro manual K5 no README.
================================================================
*/

create or replace function pg_temp.wh_5852_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  f_set  oid := to_regprocedure('public.set_my_binder_slot_image(uuid, uuid, text, smallint)');
  f_foc  oid := to_regprocedure('public.set_my_binder_slot_image_focus(uuid, uuid, smallint)');
  f_clr  oid := to_regprocedure('public.clear_my_binder_slot_image(uuid, uuid)');
  f_get  oid := to_regprocedure('public.get_my_collection_binder_slot_images(uuid, integer, integer)');
  f_sum  oid := to_regprocedure('public.get_my_binder_slot_image_summary(uuid)');
  f_unl  oid := to_regprocedure('public.list_my_unlinked_binder_slot_images(integer)');
  f_lck  oid := to_regprocedure('public.binder_slot_image_lock_target(uuid, uuid)');
  f_res  oid := to_regprocedure('public.binder_slot_image_resolve_layout(uuid)');
  f_rmp  oid := to_regprocedure('public.remove_layout_page(uuid)');
  f_dpv  oid := to_regprocedure('public.preview_my_collection_binder_dismantle(uuid)');
  f_dis  oid := to_regprocedure('public.dismantle_my_collection_binder(uuid, text)');
  u_a uuid := gen_random_uuid();
  u_b uuid := gen_random_uuid();
  v_sfx text := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  v_game uuid; v_pt uuid; v_rar uuid; v_cat uuid; v_std uuid;
  v_exp uuid; v_set uuid; k1 uuid; k1s uuid;
  v_inv_a uuid; v_inv_b uuid; v_ids uuid[];
  o1 uuid; g1 uuid; h1 uuid; b1 uuid;
  v_bin uuid; v_bin2 uuid; v_lb uuid;
  v_co uuid; v_cg uuid; v_ch uuid; v_cb uuid;
  l_o uuid; l_h uuid; l_b uuid; pg_o1 uuid; pg_h2 uuid;
  s1 uuid; s2 uuid; s3 uuid; s4 uuid; s_b1 uuid; s_q1 uuid; s_q2 uuid;
  a_g1 uuid;
  pa text; pf1 text; pf2 text; pf3 text; pbig text; pmis text; pother text; precent text; pb text;
  pq1 text; pq2 text; pown text;
  p record; o record; d record;
  v_ok boolean; v_err text; n integer; n2 integer;
  b_counts bigint[]; e_counts bigint[]; c_before bigint[]; c_after bigint[];
  res jsonb := '[]'::jsonb; r jsonb; cnt integer := 0; passes integer := 0;
  v_expected integer := 39;
begin
  -- 0. Estrutura (somente leitura) ------------------------------------------------------
  res := res || jsonb_build_object('id','0.1','ok',
    to_regclass('public.collection_layout_slot_image') is not null
    and f_set is not null and f_foc is not null and f_clr is not null and f_get is not null
    and f_sum is not null and f_unl is not null and f_lck is not null and f_res is not null,
    'detail','5232–5234 presentes');
  if (res -> 0 ->> 'ok')::boolean is not true then
    res := res || jsonb_build_object('id','X.0','ok', false, 'detail','aplique 5231 → 5236 antes deste harness');
  else
  res := res || jsonb_build_object('id','0.2','ok',
    exists (select 1 from storage.buckets b where b.id = 'binder-slot-image' and not b.public
            and b.file_size_limit = 524288
            and b.allowed_mime_types @> array['image/webp','image/jpeg']
            and cardinality(b.allowed_mime_types) = 2),
    'detail','bucket privado, 512 KB, só webp/jpeg');
  res := res || jsonb_build_object('id','0.3','ok',
    (select count(*) from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
       and p.policyname in ('binder_slot_image_select_own','binder_slot_image_insert_own','binder_slot_image_delete_own')
       and p.roles = array['authenticated']::name[]) = 3
    and not exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
       and p.policyname like 'binder\_slot\_image\_%' and p.cmd in ('UPDATE','ALL'))
    and exists (select 1 from pg_policies p where p.policyname = 'binder_slot_image_insert_own'
       and p.with_check like '%550%'),
    'detail','3 políticas só authenticated; nenhuma UPDATE/ALL; teto de 550 arquivos no INSERT');
  res := res || jsonb_build_object('id','0.4','ok',
    (select c.relrowsecurity from pg_class c where c.oid = 'public.collection_layout_slot_image'::regclass)
    and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'SELECT')
    and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'INSERT')
    and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'UPDATE')
    and not has_table_privilege('authenticated', 'public.collection_layout_slot_image', 'DELETE')
    and not has_table_privilege('anon', 'public.collection_layout_slot_image', 'SELECT')
    and (select count(*) from pg_constraint k where k.conrelid = 'public.collection_layout_slot_image'::regclass
           and k.conname in ('uq_collection_layout_slot_image_path','chk_collection_layout_slot_image_focal',
                             'chk_collection_layout_slot_image_path_format','chk_collection_layout_slot_image_path_owner')) = 4
    and exists (select 1 from pg_constraint k where k.conrelid = 'public.collection_layout_slot_image'::regclass
           and k.contype = 'f' and k.confdeltype = 'r'),
    'detail','tabela com RLS e sem privilégio para a API; UNIQUE/CHECKs; FK do bolso RESTRICT');
  res := res || jsonb_build_object('id','0.5','ok',
    (select count(*) from pg_trigger t where not t.tgisinternal and t.tgname in (
       'trg_collection_layout_slot_image_updated_at','trg_collection_layout_slot_image_integrity',
       'trg_slot_assignment_without_custom_image','trg_slot_expected_content_without_custom_image',
       'trg_slot_lock_without_custom_image','trg_region_without_custom_image')) = 6
    and (select bool_and(not has_function_privilege('authenticated', q.oid, 'EXECUTE') and q.prosecdef
                         and q.proconfig @> array['search_path=""'])
         from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname in (
           'set_collection_layout_slot_image_updated_at','enforce_collection_layout_slot_image_integrity',
           'enforce_slot_without_custom_image','enforce_slot_lock_without_custom_image','enforce_region_without_custom_image')),
    'detail','6 gatilhos; funções de gatilho definer, search_path vazio, sem EXECUTE para a API');
  res := res || jsonb_build_object('id','0.6','ok',
    (select bool_and(q.prosecdef and q.proconfig @> array['search_path=""']
                     and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                     and not has_function_privilege('anon', q.oid, 'EXECUTE'))
     from pg_proc q where q.oid in (f_set, f_foc, f_clr, f_get, f_sum, f_unl, f_rmp, f_dpv, f_dis))
    and not exists (select 1 from pg_proc q, aclexplode(q.proacl) x
                    where q.oid in (f_set, f_foc, f_clr, f_get, f_sum, f_unl, f_dpv, f_dis) and x.grantee = 0)
    and not has_function_privilege('authenticated', f_lck, 'EXECUTE')
    and not has_function_privilege('authenticated', f_res, 'EXECUTE')
    and (select bool_and(q.proconfig @> array['lock_timeout=5s']) from pg_proc q where q.oid in (f_set, f_foc, f_clr)),
    'detail','RPCs definer, search_path vazio, EXECUTE só authenticated; internas sem EXECUTE; escrita com lock_timeout 5s');
  res := res || jsonb_build_object('id','0.7','ok',
    (select q.prosrc like '%collection_layout_slot_image%' from pg_proc q where q.oid = f_rmp)
    and (select 'image_paths' = any(q.proargnames) and 'images_removed' = any(q.proargnames) from pg_proc q where q.oid = f_dis)
    and (select 'images_count' = any(q.proargnames) from pg_proc q where q.oid = f_dpv),
    'detail','remove_layout_page conta imagens (5235); desmontagem e prévia com colunas novas (5236)');
  res := res || jsonb_build_object('id','0.8','ok',
    exists (select 1 from pg_policies p where p.schemaname = 'storage' and p.tablename = 'objects'
            and p.policyname = 'binder_slot_image_delete_own' and p.cmd = 'DELETE'
            and p.qual like '%binder_slot_image_path_is_linked%')
    and (select q.provolatile = 'v' and q.prosecdef and q.proconfig @> array['search_path=""']
                and has_function_privilege('authenticated', q.oid, 'EXECUTE')
                and not has_function_privilege('anon', q.oid, 'EXECUTE')
         from pg_proc q where q.oid = to_regprocedure('public.binder_slot_image_path_is_linked(text)'))
    and (select q.prosrc like '%for share of o%' from pg_proc q where q.oid = f_set)
    and has_table_privilege((select pg_get_userbyid(q.proowner) from pg_proc q where q.oid = f_set), 'storage.objects', 'UPDATE'),
    'detail','DELETE do bucket recusa arquivo vinculado (função volátil, definer); vínculo trava o objeto FOR SHARE com privilégio do dono');

  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_layout), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_slot_image),
               (select count(*) from storage.objects ob where ob.bucket_id = 'binder-slot-image'),
               (select count(*) from public.card)]
    into b_counts;

  begin
    -- F. Fixture ---------------------------------------------------------------------------
    select g.id into v_game from public.game g where g.code = 'POKEMON';
    select l.id into v_pt from public.language l where l.code = 'pt-BR';
    select t.id into v_std from public.card_variant_type t where t.game_id = v_game and t.code = 'STANDARD';
    select c0.rarity_id, c0.category_id into v_rar, v_cat
    from public.card c0 join public.card_set cs0 on cs0.id = c0.card_set_id
    join public.expansion e0 on e0.id = cs0.expansion_id
    where e0.game_id = v_game limit 1;
    if v_game is null or v_pt is null or v_std is null or v_rar is null then
      res := res || jsonb_build_object('id','F.1','ok', false, 'detail','pré-requisitos de catálogo ausentes');
      raise exception 'MS852' using errcode = 'P0001';
    end if;
    insert into public.expansion (game_id, code, name, release_order)
    values (v_game, 'BCI_' || v_sfx, 'BCI Harness ' || v_sfx,
            (select coalesce(max(x.release_order), 0) + 1000 from public.expansion x where x.game_id = v_game))
    returning id into v_exp;
    insert into public.card_set (expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
    values (v_exp, 'BCI' || v_sfx, 'BCI Set ' || v_sfx, 'REGULAR', 1, 1, 1) returning id into v_set;
    insert into public.card (card_set_id, rarity_id, category_id, collector_number, collector_order, name, is_active)
    values (v_set, v_rar, v_cat, '1', 1, 'BCI K1', true) returning id into k1;
    insert into public.card_variant (card_id, variant_type_id, variant_order, is_default)
    values (k1, v_std, 1, true) returning id into k1s;

    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (u_a, 'authenticated', 'authenticated', 'wh5852-a-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5852a_'||lower(v_sfx), 'display_name', 'WH 5852 A'), now(), now()),
           (u_b, 'authenticated', 'authenticated', 'wh5852-b-'||lower(v_sfx)||'@example.invalid',
            jsonb_build_object('username', 'wh5852b_'||lower(v_sfx), 'display_name', 'WH 5852 B'), now(), now());
    select i.id into v_inv_a from public.inventory i where i.owner_user_id = u_a;
    select i.id into v_inv_b from public.inventory i where i.owner_user_id = u_b;
    insert into public.physical_card (card_variant_id, language_id, inventory_id, created_at) values
      (k1s, v_pt, v_inv_a, now() - interval '3 min'), (k1s, v_pt, v_inv_a, now() - interval '2 min'),
      (k1s, v_pt, v_inv_a, now() - interval '1 min');
    select array_agg(pc.id order by pc.created_at) into v_ids from public.physical_card pc where pc.inventory_id = v_inv_a;
    o1 := v_ids[1]; g1 := v_ids[2]; h1 := v_ids[3];
    insert into public.physical_card (card_variant_id, language_id, inventory_id) values (k1s, v_pt, v_inv_b) returning id into b1;

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_lb from public.create_my_storage_container(gen_random_uuid(), 'LB 5852', 'BINDER') x;
    select x.collection_id into v_cb from public.create_my_free_collection(gen_random_uuid(), 'CB 5852', v_lb) x;
    perform public.allocate_physical_cards_to_collection(v_cb, array[b1]);
    select * into p from public.preview_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_cb, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select x.storage_container_id into v_bin  from public.create_my_storage_container(gen_random_uuid(), 'BIN 5852', 'BINDER') x;
    select x.storage_container_id into v_bin2 from public.create_my_storage_container(gen_random_uuid(), 'BIN2 5852', 'BINDER') x;
    select x.collection_id into v_co from public.create_my_free_collection(gen_random_uuid(), 'CO 5852', v_bin) x;
    select x.collection_id into v_cg from public.create_my_free_collection(gen_random_uuid(), 'CG 5852', v_bin) x;
    select x.collection_id into v_ch from public.create_my_free_collection(gen_random_uuid(), 'CH 5852', v_bin2) x;
    perform public.allocate_physical_cards_to_collection(v_co, array[o1]);
    perform public.allocate_physical_cards_to_collection(v_cg, array[g1]);
    perform public.allocate_physical_cards_to_collection(v_ch, array[h1]);
    select * into p from public.preview_my_collection_binder(v_co, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_co, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select * into p from public.preview_my_collection_binder(v_ch, 2, 2, 'PRINCIPAL_ONLY');
    perform count(*) from public.create_my_collection_binder(v_ch, 2, 2, 'PRINCIPAL_ONLY', p.plan_token);
    select l.id into l_o from public.collection_layout l where l.collection_id = v_co;
    select l.id into l_h from public.collection_layout l where l.collection_id = v_ch;
    perform public.attach_my_collection_to_binder(v_cg, l_o);
    perform public.add_layout_page(l_h) from generate_series(1, 126);
    execute 'reset role';

    select l.id into l_b from public.collection_layout l where l.collection_id = v_cb;
    select pg.id into pg_o1 from public.collection_layout_page pg where pg.layout_id = l_o and pg.page_number = 1;
    select array_agg(s.id order by s.row_index, s.column_index) into v_ids
    from public.collection_layout_slot s where s.page_id = pg_o1;
    s1 := v_ids[1]; s2 := v_ids[2]; s3 := v_ids[3]; s4 := v_ids[4];
    select s.id into s_b1 from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
    where pg.layout_id = l_b order by pg.page_number, s.row_index, s.column_index limit 1;
    select pg.id into pg_h2 from public.collection_layout_page pg where pg.layout_id = l_h and pg.page_number = 2;
    select ca.id into a_g1 from public.collection_allocation ca where ca.physical_card_id = g1;

    -- Arquivos sintéticos (só linhas de metadados; created_at 2 h atrás, exceto "recente").
    pa := u_a::text || '/' || l_o::text || '/';
    pf1 := pa || gen_random_uuid()::text || '.webp';
    pf2 := pa || gen_random_uuid()::text || '.jpg';
    pf3 := pa || gen_random_uuid()::text || '.webp';
    pbig := pa || gen_random_uuid()::text || '.webp';
    pmis := pa || gen_random_uuid()::text || '.webp';
    precent := pa || gen_random_uuid()::text || '.webp';
    pother := u_a::text || '/' || l_h::text || '/' || gen_random_uuid()::text || '.webp';
    pb := u_b::text || '/' || l_b::text || '/' || gen_random_uuid()::text || '.webp';
    pq1 := u_a::text || '/' || l_h::text || '/' || gen_random_uuid()::text || '.webp';
    pq2 := u_a::text || '/' || l_h::text || '/' || gen_random_uuid()::text || '.webp';
    insert into storage.objects (bucket_id, name, owner, owner_id, metadata, created_at)
    select 'binder-slot-image', x.nm, x.ow, x.ow::text,
           jsonb_build_object('mimetype', x.mt, 'size', x.sz),
           case when x.nm = precent then now() else now() - interval '2 hours' end
    from (values (pf1, u_a, 'image/webp', 100000), (pf2, u_a, 'image/jpeg', 50000),
                 (pf3, u_a, 'image/webp', 90000), (pbig, u_a, 'image/webp', 600000),
                 (pmis, u_a, 'image/jpeg', 80000), (precent, u_a, 'image/webp', 70000),
                 (pother, u_a, 'image/webp', 70000), (pb, u_b, 'image/webp', 70000),
                 (pq1, u_a, 'image/webp', 70000), (pq2, u_a, 'image/webp', 70000)) as x(nm, ow, mt, sz);

    res := res || jsonb_build_object('id','F.1','ok',
      l_o is not null and l_h is not null and l_b is not null and s4 is not null and pg_h2 is not null
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s1)
      and exists (select 1 from public.collection_layout_guest g where g.collection_id = v_cg and g.layout_id = l_o)
      and (select count(*) from public.collection_layout_page pg where pg.layout_id = l_h) = 127,
      'detail','fixture: CO (o1 em s1) com CG convidada; CH com 127 páginas; CB de B');
    res := res || jsonb_build_object('id','F.2','ok',
      (select count(*) from storage.objects ob where ob.bucket_id = 'binder-slot-image'
         and ob.name in (pf1, pf2, pf3, pbig, pmis, precent, pother, pb, pq1, pq2)) = 10,
      'detail','10 linhas sintéticas em storage.objects');
    select array[(select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
                 (select count(*) from public.collection_layout_slot_assignment)]
      into c_before;

    -- 1. Arquivos e segurança --------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into n from storage.objects ob where ob.bucket_id = 'binder-slot-image' and ob.name = pb;
    v_err := null;
    begin insert into storage.objects (bucket_id, name) values ('binder-slot-image', u_b::text || '/' || l_b::text || '/' || gen_random_uuid()::text || '.webp');
    exception when others then v_err := sqlstate; end;
    v_ok := v_err = '42501';
    v_err := null;
    begin insert into storage.objects (bucket_id, name) values ('binder-slot-image', u_a::text || '/x/nome-livre.png');
    exception when others then v_err := sqlstate; end;
    v_ok := v_ok and v_err = '42501';
    update storage.objects ob set metadata = '{}'::jsonb where ob.bucket_id = 'binder-slot-image' and ob.name = pf1;
    get diagnostics n2 = row_count;
    res := res || jsonb_build_object('id','1.1','ok', n = 0 and v_ok and n2 = 0,
      'detail','A não vê arquivo de B; não envia na pasta de B nem fora do formato; UPDATE não existe para ninguém');
    pown := pa || gen_random_uuid()::text || '.webp';
    insert into storage.objects (bucket_id, name) values ('binder-slot-image', pown);
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects ob where ob.bucket_id = 'binder-slot-image' and ob.name = pown;
    get diagnostics n = row_count;
    res := res || jsonb_build_object('id','1.2','ok', n = 1, 'detail','A envia e apaga na própria pasta');
    v_err := null;
    begin perform count(*) from public.collection_layout_slot_image;
    exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','1.3','ok', v_err = '42501', 'detail','A não lê a tabela diretamente (só RPC)');
    execute 'reset role';

    execute 'set local role anon';
    v_err := null;
    begin perform * from public.set_my_binder_slot_image(v_co, s2, pf1, 50::smallint);
    exception when others then v_err := sqlstate; end;
    res := res || jsonb_build_object('id','1.4','ok', v_err = '42501', 'detail','anon sem EXECUTE');
    execute 'reset role';

    perform set_config('request.jwt.claim.sub', u_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null;
    begin perform * from public.set_my_binder_slot_image(v_co, s2, pb, 50::smallint);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.5','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','B pela coleção de A → COLLECTION_NOT_FOUND');
    v_err := null;
    begin perform * from public.set_my_binder_slot_image(v_cb, s2, pb, 50::smallint);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.6','ok', v_err = 'SLOT_NOT_FOUND', 'detail','B no bolso de A pela própria coleção → SLOT_NOT_FOUND (sem enumerar)');
    v_err := null;
    begin perform * from public.get_my_collection_binder_slot_images(v_co, 1, 1);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','1.7','ok', v_err = 'COLLECTION_NOT_FOUND', 'detail','B não lê as imagens de A');
    execute 'reset role';

    -- 2. Escrita e exclusividade -------------------------------------------------------------
    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    v_err := null;
    begin perform * from public.set_my_binder_slot_image(v_co, s1, pf1, 50::smallint);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.1','ok', v_err = 'SLOT_OCCUPIED', 'detail','bolso com carta → SLOT_OCCUPIED');
    perform public.set_slot_lock(array[s4], true);
    v_err := null;
    begin perform * from public.set_my_binder_slot_image(v_co, s4, pf1, 50::smallint);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.2','ok', v_err = 'SLOT_LOCKED', 'detail','bolso fixado → SLOT_LOCKED');
    perform public.set_slot_lock(array[s4], false);
    perform * from public.set_slot_expected_content(s4, k1);
    v_err := null;
    begin perform * from public.set_my_binder_slot_image(v_co, s4, pf1, 50::smallint);
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.3','ok', v_err = 'SLOT_RESERVED', 'detail','bolso reservado → SLOT_RESERVED');

    select * into d from public.set_my_binder_slot_image(v_co, s2, pf1, 40::smallint);
    res := res || jsonb_build_object('id','2.4','ok', d.operation = 'ADDED' and d.previous_path is null and d.focal_y = 40,
      'detail','ADDED pela proprietária');
    select * into d from public.set_my_binder_slot_image(v_cg, s3, pf2, 50::smallint);
    res := res || jsonb_build_object('id','2.5','ok', d.operation = 'ADDED' and d.storage_path = pf2,
      'detail','ADDED pela convidada no mesmo fichário (D2)');
    select * into d from public.set_my_binder_slot_image(v_co, s2, pf1, 60::smallint);
    res := res || jsonb_build_object('id','2.6','ok', d.operation = 'UNCHANGED' and d.previous_path is null and d.focal_y = 60
      and (select count(*) from public.get_my_collection_binder_slot_images(v_co, 1, 1)) = 2,
      'detail','repetição → UNCHANGED (só enquadramento), sem duplicar');

    v_ok := true;
    v_err := null; begin perform * from public.assign_card_to_slot(s2, a_g1); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'SLOT_HAS_IMAGE';
    v_err := null; begin perform * from public.set_slot_expected_content(s2, k1); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'SLOT_HAS_IMAGE';
    v_err := null; begin perform public.set_slot_lock(array[s2], true); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'SLOT_HAS_IMAGE';
    v_err := null; begin perform * from public.merge_layout_region(pg_o1, 1, 1, 1, 2); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'SLOT_HAS_IMAGE';
    res := res || jsonb_build_object('id','2.7','ok', v_ok
      and exists (select 1 from public.collection_layout_slot_assignment a where a.slot_id = s1)
      and not exists (select 1 from public.collection_layout_slot_assignment a where a.collection_allocation_id = a_g1),
      'detail','carta, reserva, trava e mesclagem num bolso com imagem → SLOT_HAS_IMAGE; nada substituído');

    v_ok := true;
    v_err := null; begin perform * from public.set_my_binder_slot_image(v_co, s4, pb, 50::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'INVALID_IMAGE_PATH';
    v_err := null; begin perform * from public.set_my_binder_slot_image(v_co, s2, pother, 50::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'INVALID_IMAGE_PATH';
    v_err := null; begin perform * from public.set_my_binder_slot_image(v_co, s2, pa || gen_random_uuid()::text || '.webp', 50::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'IMAGE_FILE_NOT_FOUND';
    res := res || jsonb_build_object('id','2.8','ok', v_ok,
      'detail','pasta de outro usuário / de outro fichário → INVALID_IMAGE_PATH; arquivo inexistente → IMAGE_FILE_NOT_FOUND');
    v_ok := true;
    v_err := null; begin perform * from public.set_my_binder_slot_image(v_co, s2, pbig, 50::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'INVALID_IMAGE_FILE';
    v_err := null; begin perform * from public.set_my_binder_slot_image(v_co, s2, pmis, 50::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'INVALID_IMAGE_FILE';
    v_err := null; begin perform * from public.set_my_binder_slot_image(v_co, s2, pf2, 50::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'IMAGE_PATH_IN_USE';
    res := res || jsonb_build_object('id','2.9','ok', v_ok
      and (select i.storage_path from public.get_my_collection_binder_slot_images(v_co, 1, 1) i where i.slot_id = s2) = pf1,
      'detail','metadados acima de 512 KB ou tipo ≠ extensão → INVALID_IMAGE_FILE; arquivo de outro bolso → IMAGE_PATH_IN_USE; imagem em uso intacta');

    select * into d from public.set_my_binder_slot_image(v_co, s2, pf3, 50::smallint);
    res := res || jsonb_build_object('id','2.10','ok', d.operation = 'REPLACED' and d.previous_path = pf1 and d.storage_path = pf3
      and exists (select 1 from storage.objects ob where ob.bucket_id = 'binder-slot-image' and ob.name = pf1),
      'detail','REPLACED devolve o anterior; o SQL não apaga o arquivo antigo');

    select * into d from public.set_my_binder_slot_image_focus(v_co, s2, 20::smallint);
    v_ok := d.focal_y = 20;
    v_err := null; begin perform * from public.set_my_binder_slot_image_focus(v_co, s2, 101::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'INVALID_FOCAL';
    v_err := null; begin perform * from public.set_my_binder_slot_image_focus(v_co, s4, 30::smallint); exception when others then v_err := sqlerrm; end;
    v_ok := v_ok and v_err = 'IMAGE_NOT_FOUND';
    res := res || jsonb_build_object('id','2.11','ok', v_ok, 'detail','enquadramento 0–100; fora do intervalo e bolso sem imagem recusados');

    perform set_config('storage.allow_delete_query', 'true', true);
    v_err := null; n := -1; n2 := -1;
    begin
      delete from storage.objects ob where ob.bucket_id = 'binder-slot-image' and ob.name in (pf2, pf3);
      get diagnostics n = row_count;
      delete from storage.objects ob where ob.bucket_id = 'binder-slot-image' and ob.name = pbig;
      get diagnostics n2 = row_count;
    exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','2.12','ok', v_err is null and n = 0 and n2 = 1
      and (select count(*) from storage.objects ob where ob.bucket_id = 'binder-slot-image' and ob.name in (pf2, pf3)) = 2,
      'detail','arquivos vinculados (s2, s3) não são apagados por DELETE do próprio dono; arquivo sem vínculo é apagado'
                || coalesce(' — erro: ' || v_err, ''));

    -- 3. Leituras ------------------------------------------------------------------------------
    res := res || jsonb_build_object('id','3.1','ok',
      (select array_agg(i.slot_id order by i.slot_id) from public.get_my_collection_binder_slot_images(v_co, 1, 1) i)
      = (select array_agg(i.slot_id order by i.slot_id) from public.get_my_collection_binder_slot_images(v_cg, 1, 1) i)
      and (select count(*) from public.get_my_collection_binder_slot_images(v_cg, 1, 1)) = 2,
      'detail','proprietária e convidada veem as mesmas imagens do fichário');
    select * into o from public.get_my_binder_slot_image_summary(v_cg);
    res := res || jsonb_build_object('id','3.2','ok', o.layout_image_count = 2 and o.user_image_count = 2 and o.user_image_limit = 500,
      'detail','resumo: 2 no fichário, 2 do usuário, limite 500');
    res := res || jsonb_build_object('id','3.3','ok',
      exists (select 1 from public.list_my_unlinked_binder_slot_images(100) x where x.storage_path = pf1)
      and not exists (select 1 from public.list_my_unlinked_binder_slot_images(100) x where x.storage_path in (pf2, pf3, precent, pb)),
      'detail','sem vínculo: o arquivo substituído aparece; vinculados, recentes (< 1 h) e de B não');
    res := res || jsonb_build_object('id','3.4','ok',
      (select count(*) from public.get_my_collection_binder_slot_images(v_ch, 1, 4)) = 0,
      'detail','outro fichário do mesmo usuário não mistura imagens');
    execute 'reset role';

    -- 4. Limite, página, remoção, desmontagem ----------------------------------------------------
    -- 497 imagens no fichário CH (páginas 3–127, 500 bolsos) como dono do banco (gatilhos ativos): total 499.
    insert into storage.objects (bucket_id, name, owner, owner_id, metadata, created_at)
    select 'binder-slot-image', u_a::text || '/' || l_h::text || '/' || gen_random_uuid()::text || '.webp',
           u_a, u_a::text, jsonb_build_object('mimetype','image/webp','size', 1000), now()
    from generate_series(1, 497);
    insert into public.collection_layout_slot_image (slot_id, owner_user_id, storage_path)
    select q.slot_id, u_a, q.name
    from (select s.id as slot_id, row_number() over (order by pg.page_number, s.row_index, s.column_index) as rn
          from public.collection_layout_slot s join public.collection_layout_page pg on pg.id = s.page_id
          where pg.layout_id = l_h and pg.page_number >= 3) q
    join (select ob.name, row_number() over (order by ob.name) as rn
          from storage.objects ob
          where ob.bucket_id = 'binder-slot-image' and ob.name like u_a::text || '/' || l_h::text || '/%'
            and ob.name not in (pother, pq1, pq2)) f on f.rn = q.rn;
    select s.id into s_q1 from public.collection_layout_slot s where s.page_id = pg_h2 order by s.row_index, s.column_index limit 1;
    select s.id into s_q2 from public.collection_layout_slot s where s.page_id = pg_h2 order by s.row_index, s.column_index offset 1 limit 1;

    perform set_config('request.jwt.claim.sub', u_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select * into d from public.set_my_binder_slot_image(v_ch, s_q1, pq1, 50::smallint);
    v_ok := d.operation = 'ADDED';
    v_err := null;
    begin perform * from public.set_my_binder_slot_image(v_ch, s_q2, pq2, 50::smallint); exception when others then v_err := sqlerrm; end;
    select * into o from public.get_my_binder_slot_image_summary(v_ch);
    res := res || jsonb_build_object('id','4.1','ok', v_ok and v_err = 'IMAGE_QUOTA_REACHED' and o.user_image_count = 500,
      'detail','500ª imagem ADDED; 501ª → IMAGE_QUOTA_REACHED');
    v_err := null;
    begin perform public.remove_layout_page(pg_h2); exception when others then v_err := sqlerrm; end;
    res := res || jsonb_build_object('id','4.2','ok', v_err like 'page has 1 custom image(s)%'
      and exists (select 1 from public.collection_layout_page pg where pg.id = pg_h2),
      'detail','remoção de página com imagem recusada com mensagem explicativa (5235)');

    select * into d from public.clear_my_binder_slot_image(v_co, s2);
    v_ok := d.outcome = 'REMOVED' and d.previous_path = pf3;
    select * into d from public.clear_my_binder_slot_image(v_cg, s2);
    res := res || jsonb_build_object('id','4.3','ok', v_ok and d.outcome = 'ALREADY_ABSENT' and d.previous_path is null
      and exists (select 1 from storage.objects ob where ob.bucket_id = 'binder-slot-image' and ob.name = pf3),
      'detail','REMOVED devolve o caminho; repetição (pela convidada) → ALREADY_ABSENT; arquivo não apagado pelo SQL');

    select * into p from public.preview_my_collection_binder_dismantle(v_ch);
    select * into d from public.dismantle_my_collection_binder(v_ch, p.dismantle_token);
    res := res || jsonb_build_object('id','4.4','ok', p.images_count = 498 and d.outcome = 'DISMANTLED'
      and d.images_removed = 498 and cardinality(d.image_paths) = 498 and pq1 = any(d.image_paths)
      and (select count(*) from public.get_my_binder_slot_image_summary(v_ch) x where x.user_image_count = 1) = 1,
      'detail','prévia e desmontagem com 498 imagens; caminhos devolvidos; resta 1 imagem do usuário (CO)');
    execute 'reset role';

    select array[(select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
                 (select count(*) from public.collection_layout_slot_assignment)]
      into c_after;
    res := res || jsonb_build_object('id','4.5','ok', c_after[1] = c_before[1] and c_after[2] = c_before[2]
      and c_after[3] = c_before[3] - 1,
      'detail','alocações e cartas físicas intactas; só a posição de h1 saiu com a desmontagem');

    raise exception 'MS852' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'MS852' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select array[(select count(*) from auth.users), (select count(*) from public.collection),
               (select count(*) from public.collection_allocation), (select count(*) from public.physical_card),
               (select count(*) from public.collection_layout), (select count(*) from public.collection_layout_page),
               (select count(*) from public.collection_layout_slot_assignment),
               (select count(*) from public.collection_layout_slot_expected_content),
               (select count(*) from public.collection_layout_slot_image),
               (select count(*) from storage.objects ob where ob.bucket_id = 'binder-slot-image'),
               (select count(*) from public.card)]
    into e_counts;
  res := res || jsonb_build_object('id','99.1','ok', b_counts = e_counts and current_user = session_user,
    'detail','resíduo zero (11 contagens) e papel restaurado');
  end if;

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
