/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5833 - Harness: capa enviada pelo usuário na Coleção livre
              (5176 bucket + 5177 coluna + 5178 RPC)
Versão......: 1.2 (LIVE 2026-10-18: 4.5 aceita bloqueio por 42501 — RLS
              preexistente com is_admin() recusa anon antes de filtrar; isolado em
              subbloco). Antes 1.1 (READINESS-01: +3.12 pasta de outra coleção própria, +4.3 inserção
              na pasta alheia, +4.4 alteração de arquivo alheio, +4.5 anon sem
              leitura; owner_id nos arquivos de teste)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 — v1.2 25/25 PASS,
              GATE PASS, resíduo zero (v1.1: GATE FAIL 22/23 em 4.5, defeito do harness)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Mesmo protocolo de 5832: um único statement (criar a função temporária e
chamar `select * from pg_temp.rc_5833_validate();` na mesma chamada),
usuários de teste efêmeros em auth.users, tudo desfeito pela sentinela
LI000 e resíduo zero conferido no fim (9.1). Não toca dados reais.

Os arquivos de teste são linhas em storage.objects inseridas pelo próprio
harness (nenhum byte enviado ao Storage) e desfeitas junto.

Checagens:
  0.x  estrutura: bucket privado, limite e tipos; 4 políticas; coluna e
       CHECK; função SECURITY DEFINER, search_path vazio, ACL só
       authenticated.
  1.1  anon → 42501        2.1  sem identidade → 28000
  3.x  RPC: define, idempotente, troca (devolve anterior), remove;
       arquivo inexistente; pasta de outra pessoa; pasta de outra coleção;
       coleção alheia (não enumera); coleção de Set recusada; CHECK
       recusa valor fora do formato; nenhuma carta/alocação tocada.
  4.x  Storage RLS: dono vê o próprio arquivo; outro usuário não vê, não
       grava na pasta alheia e não altera arquivo alheio; anon não lê.
       (Exclusão direta por SQL é barrada pelo gatilho do próprio Storage,
       protect_objects_delete; a exclusão pela API passa pela política
       collection_cover_delete_own, com a mesma condição de pasta.)
  9.1  resíduo zero.
GATE: n = 25 e todas PASS.
================================================================
*/

create or replace function pg_temp.rc_5833_validate()
returns table (seq integer, check_id text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_fn      oid := to_regprocedure('public.set_my_collection_cover_logo(uuid,text)');
  p_user_a  uuid := gen_random_uuid();
  p_user_b  uuid := gen_random_uuid();
  v_sfx     text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_set     uuid;
  v_free_a  uuid;
  v_free_b  uuid;
  v_set_a   uuid;
  v_path1   text;
  v_path2   text;
  v_path_b  text;
  v_rec     record;
  v_state   text;
  v_msg     text;
  v_cnt     bigint;
  v_base_us bigint;
  v_base_co bigint;
  v_base_ca bigint;
  v_base_ob bigint;
  v_base_sc bigint;
  res       jsonb := '[]'::jsonb;
  r         jsonb;
  n         integer := 0;
  passes    integer := 0;
begin
  -- 0. Estrutura
  res := res || jsonb_build_object('id','0.1','ok',
    exists (select 1 from storage.buckets b
            where b.id = 'collection-cover' and b.public = false and b.file_size_limit = 1048576
              and b.allowed_mime_types @> array['image/png','image/jpeg','image/webp']
              and cardinality(b.allowed_mime_types) = 3),
    'detail','bucket collection-cover privado, 1 MB, png/jpeg/webp');
  res := res || jsonb_build_object('id','0.2','ok',
    (select count(*) from pg_policies p
      where p.schemaname = 'storage' and p.tablename = 'objects'
        and p.policyname in ('collection_cover_select_own','collection_cover_insert_own',
                             'collection_cover_update_own','collection_cover_delete_own')
        and p.roles = '{authenticated}') = 4,
    'detail','4 políticas por dono em storage.objects, só authenticated');
  res := res || jsonb_build_object('id','0.3','ok',
    exists (select 1 from information_schema.columns c
            where c.table_schema = 'public' and c.table_name = 'collection'
              and c.column_name = 'cover_logo_path' and c.is_nullable = 'YES')
    and exists (select 1 from pg_constraint k
                where k.conrelid = 'public.collection'::regclass and k.conname = 'chk_collection_cover_logo_path'),
    'detail','collection.cover_logo_path (nulo) + CHECK de formato');
  res := res || jsonb_build_object('id','0.4','ok',
    coalesce((select p.prosecdef and p.proconfig = array['search_path=""'] from pg_proc p where p.oid = v_fn), false)
    and v_fn is not null
    and has_function_privilege('authenticated', v_fn, 'EXECUTE')
    and not has_function_privilege('anon', v_fn, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = v_fn and a.grantee = 0),
    'detail','5178: SECURITY DEFINER, search_path vazio, EXECUTE só authenticated');
  res := res || jsonb_build_object('id','0.5','ok',
    coalesce((select position('collection_allocation' in p.prosrc) = 0 and position('physical_card' in p.prosrc) = 0
              from pg_proc p where p.oid = v_fn), false),
    'detail','5178 não referencia cartas nem alocações');

  select count(*) into v_base_us from auth.users;
  select count(*) into v_base_co from public.collection;
  select count(*) into v_base_ca from public.collection_allocation;
  select count(*) into v_base_ob from storage.objects;
  select count(*) into v_base_sc from public.storage_container;

  begin
    insert into auth.users (id, aud, role, email, raw_user_meta_data, created_at, updated_at)
    values (p_user_a, 'authenticated', 'authenticated', 'rc5833-a-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5833a_'||v_sfx, 'display_name', 'RC 5833 A'), now(), now()),
           (p_user_b, 'authenticated', 'authenticated', 'rc5833-b-'||v_sfx||'@example.invalid',
            jsonb_build_object('username', 'rc5833b_'||v_sfx, 'display_name', 'RC 5833 B'), now(), now());

    select cs.id into v_set
    from public.card_set cs join public.expansion e on e.id = cs.expansion_id
    join public.game g on g.id = e.game_id and g.code = 'POKEMON'
    order by cs.id limit 1;

    -- Coleções de teste pelos contratos oficiais (5175 livre, 5167 de Set).
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_free_a from public.create_my_free_collection(gen_random_uuid(), 'Livre A 5833', null) c;
    select c.collection_id into v_set_a
    from public.create_my_card_set_collection(gen_random_uuid(), v_set, 'Set A 5833',
      (select sc.id from public.storage_container sc join public.inventory i on i.id = sc.inventory_id
        where i.owner_user_id = p_user_a limit 1)) c;
    execute 'reset role';
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select c.collection_id into v_free_b from public.create_my_free_collection(gen_random_uuid(), 'Livre B 5833', null) c;
    execute 'reset role';

    v_path1  := p_user_a::text || '/' || v_free_a::text || '/' || gen_random_uuid()::text || '.webp';
    v_path2  := p_user_a::text || '/' || v_free_a::text || '/' || gen_random_uuid()::text || '.png';
    v_path_b := p_user_b::text || '/' || v_free_b::text || '/' || gen_random_uuid()::text || '.jpg';
    insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
    values ('collection-cover', v_path1, p_user_a, p_user_a::text, '{"mimetype":"image/webp","size":1000}'::jsonb),
           ('collection-cover', v_path2, p_user_a, p_user_a::text, '{"mimetype":"image/png","size":1000}'::jsonb),
           ('collection-cover', v_path_b, p_user_b, p_user_b::text, '{"mimetype":"image/jpeg","size":1000}'::jsonb);

    -- 1.1 anon / 2.1 sem identidade
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';
    begin perform public.set_my_collection_cover_logo(v_free_a, v_path1); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','1.1','ok', v_state = '42501', 'detail','anon: '||v_state);

    execute 'set local role authenticated';
    begin perform public.set_my_collection_cover_logo(v_free_a, v_path1); v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    execute 'reset role';
    res := res || jsonb_build_object('id','2.1','ok', v_state = '28000', 'detail','sem identidade: '||v_state);

    -- 3.x como A
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role','authenticated')::text, true);
    execute 'set local role authenticated';

    select * into v_rec from public.set_my_collection_cover_logo(v_free_a, v_path1);
    res := res || jsonb_build_object('id','3.1','ok',
      v_rec.cover_logo_path = v_path1 and v_rec.previous_path is null,
      'detail','define a capa (sem anterior)');

    select * into v_rec from public.set_my_collection_cover_logo(v_free_a, v_path1);
    res := res || jsonb_build_object('id','3.2','ok',
      v_rec.cover_logo_path = v_path1 and v_rec.previous_path is null,
      'detail','repetir o mesmo caminho é idempotente (nada a apagar)');

    select * into v_rec from public.set_my_collection_cover_logo(v_free_a, v_path2);
    res := res || jsonb_build_object('id','3.3','ok',
      v_rec.cover_logo_path = v_path2 and v_rec.previous_path = v_path1,
      'detail','troca devolve o caminho anterior');

    begin perform public.set_my_collection_cover_logo(v_free_a, p_user_a::text || '/' || v_free_a::text || '/' || gen_random_uuid()::text || '.webp');
      v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.4','ok', v_msg = 'COVER_FILE_NOT_FOUND', 'detail','arquivo inexistente: '||v_state||' '||v_msg);

    begin perform public.set_my_collection_cover_logo(v_free_a, v_path_b); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.5','ok', v_msg = 'INVALID_COVER_PATH', 'detail','arquivo de outra pessoa: '||v_msg);

    begin perform public.set_my_collection_cover_logo(v_set_a, v_path1); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.6','ok', v_msg = 'NOT_FREE_COLLECTION', 'detail','coleção de Set: '||v_state||' '||v_msg);

    begin perform public.set_my_collection_cover_logo(v_free_b, v_path_b); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.7','ok', v_msg = 'COLLECTION_NOT_FOUND', 'detail','coleção alheia (não enumera): '||v_msg);

    begin perform public.set_my_collection_cover_logo(gen_random_uuid(), v_path1); v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.8','ok', v_msg = 'COLLECTION_NOT_FOUND', 'detail','coleção inexistente: mesma resposta');

    -- 3.12 arquivo na pasta de OUTRA coleção do próprio A (a de Set) não vale para a livre
    begin perform public.set_my_collection_cover_logo(v_free_a, p_user_a::text || '/' || v_set_a::text || '/' || gen_random_uuid()::text || '.png');
      v_state := 'executou'; v_msg := '';
    exception when others then v_state := sqlstate; v_msg := sqlerrm; end;
    res := res || jsonb_build_object('id','3.12','ok', v_msg = 'INVALID_COVER_PATH', 'detail','pasta de outra coleção do mesmo dono: '||v_msg);

    select * into v_rec from public.set_my_collection_cover_logo(v_free_a, null);
    res := res || jsonb_build_object('id','3.9','ok',
      v_rec.cover_logo_path is null and v_rec.previous_path = v_path2,
      'detail','remover devolve o anterior e volta a placa tipográfica');

    -- 4.x Storage RLS (ainda como A)
    select count(*) into v_cnt from storage.objects o where o.bucket_id = 'collection-cover' and o.name in (v_path1, v_path_b);
    execute 'reset role';
    res := res || jsonb_build_object('id','4.1','ok', v_cnt = 1, 'detail', format('A vê só o próprio arquivo (%s de 2)', v_cnt));

    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role','authenticated')::text, true);
    execute 'set local role authenticated';
    select count(*) into v_cnt from storage.objects o where o.bucket_id = 'collection-cover' and o.name in (v_path1, v_path2);
    res := res || jsonb_build_object('id','4.2','ok', v_cnt = 0, 'detail', format('B não vê arquivos de A (%s)', v_cnt));

    begin
      insert into storage.objects (bucket_id, name, owner, owner_id)
      values ('collection-cover', p_user_a::text || '/' || v_free_a::text || '/' || gen_random_uuid()::text || '.png', p_user_b, p_user_b::text);
      v_state := 'executou';
    exception when others then v_state := sqlstate; end;
    res := res || jsonb_build_object('id','4.3','ok', v_state = '42501', 'detail','B gravando na pasta de A: '||v_state);

    update storage.objects o set name = p_user_b::text || '/' || v_free_b::text || '/' || gen_random_uuid()::text || '.webp'
    where o.bucket_id = 'collection-cover' and o.name = v_path1;
    get diagnostics v_cnt = row_count;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.4','ok', v_cnt = 0
        and exists (select 1 from storage.objects o where o.bucket_id = 'collection-cover' and o.name = v_path1),
      'detail', format('B alterando arquivo de A: %s linha(s); arquivo intacto', v_cnt));

    -- 4.5 anon: sem política para anon neste bucket. No LIVE, qualquer SELECT
    -- de anon em storage.objects já é recusado inteiro (42501) porque políticas
    -- preexistentes de outros buckets (card_set_logo_admin_select,
    -- expansion_logo_admin_select, role public) chamam is_admin(), que anon não
    -- executa. Bloqueio por 0 linhas OU por 42501 = PASS (fail-closed); o
    -- subbloco isola o erro para o harness continuar (v1.2).
    perform set_config('request.jwt.claims', '', true);
    begin
      execute 'set local role anon';
      select count(*) into v_cnt from storage.objects o where o.bucket_id = 'collection-cover';
      v_state := 'leu';
      execute 'reset role';
    exception when insufficient_privilege then
      v_state := '42501';
      v_cnt := 0;
    end;
    execute 'reset role';
    res := res || jsonb_build_object('id','4.5','ok', v_cnt = 0,
      'detail', format('anon no bucket: %s (%s linha(s) lidas)', v_state, v_cnt));

    -- 3.10 CHECK como defesa em profundidade (escrita direta privilegiada)
    begin
      update public.collection set cover_logo_path = 'qualquer/coisa.gif' where id = v_free_a;
      v_state := 'executou';
    exception when check_violation then v_state := '23514'; end;
    res := res || jsonb_build_object('id','3.10','ok', v_state = '23514', 'detail','CHECK recusa formato inválido: '||v_state);

    res := res || jsonb_build_object('id','3.11','ok',
      not exists (select 1 from public.collection_allocation ca where ca.collection_id in (v_free_a, v_free_b, v_set_a)),
      'detail','nenhuma alocação criada nas coleções de teste');

    raise exception 'LI000' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> 'LI000' then
      res := res || jsonb_build_object('id','X.1','ok', false, 'detail','erro inesperado: '||sqlstate||' '||sqlerrm);
    end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  res := res || jsonb_build_object('id','9.1','ok',
    (select count(*) from auth.users) = v_base_us
      and (select count(*) from public.collection) = v_base_co
      and (select count(*) from public.collection_allocation) = v_base_ca
      and (select count(*) from public.storage_container) = v_base_sc
      and (select count(*) from storage.objects) = v_base_ob
      and current_user = session_user,
    'detail','resíduo zero (usuários, coleções, alocações, locais, objetos do Storage) e papel restaurado');

  for r in select * from jsonb_array_elements(res) loop
    n := n + 1;
    if coalesce((r->>'ok')::boolean, false) then passes := passes + 1; end if;
    seq := n; check_id := r->>'id';
    status := case when coalesce((r->>'ok')::boolean, false) then 'PASS' else 'FAIL' end;
    detail := r->>'detail';
    return next;
  end loop;
  seq := 99; check_id := 'GATE';
  status := case when passes = n and n = 25 then 'PASS' else 'FAIL' end;
  detail := format('%s/%s PASS (esperado 25)', passes, n);
  return next;
end;
$fn$;

select * from pg_temp.rc_5833_validate();
