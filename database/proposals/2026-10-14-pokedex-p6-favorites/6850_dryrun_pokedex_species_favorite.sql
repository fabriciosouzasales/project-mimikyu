/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6850 - Dry-run Pokédex Species Favorite (6136 + 6137 + 6849)
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO. Ensaio transacional reversível;
              exige autorização expressa e auditoria independente.
              Quem executa é Fabrício.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-14 (Pokédex P6.1, decisão D-B = Opção A)
Gerado......: por script, a partir dos arquivos de origem (ver
              verify_6850_identity.py). NÃO EDITAR À MÃO: regenerar.

ORIGEM (sha256 dos arquivos completos)
- 6136_create_pokedex_species_favorite_table.sql      0d351bc163ee17f917ef7aac5efc0bb435fef96086a8fedebeac683e9a64fbdd
- 6137_create_pokedex_species_favorite_functions.sql  9c5173b24a0eca8feb9f11ae8412e77cd8c8ef358e8964c59e85d7e9aafc2b4e
- 6849_validate_pokedex_species_favorite.sql (v2.1)   ae02d68f5b6c7bd6605db188c7ff793c8ebf7c6117b74f2f4bd93ced4cdbf8a7

IDENTIDADE DO CONTEÚDO ENSAIADO (sha256, texto sem \r)
- DDL 6136 embutido = texto entre a linha "begin;" e a linha
  "commit;" de 6136 ........................... d4d5c2d75ea24771f4d56ee5bbc160e812ddcc1b98b07f1c598eb7e014d63223
- DDL 6137 embutido = idem para 6137 .......... 37ea65d7893b07c8681e85e09f4ca53c1e83f50081e9e969f5520f22a195d6c7
- Corpo (prosrc) de pg_temp.p6_6849_validate =
  texto entre os delimitadores $fn$ de 6849 ... 4bd0860ff50fdfe558c88dfd49952b3545037808bf82ebc6811fb2b5d4312b44
Conferido em dois pontos: (1) offline, por verify_6850_identity.py
(byte a byte contra os arquivos); (2) em execução, D.0.1–D.0.3
recalculam os hashes no banco e bloqueiam o ensaio se divergirem.

O QUE O ENSAIO FAZ (um único statement: o SELECT da Seção 3)
1. Pré-condições somente leitura (D.0.x): identidade dos textos,
   ausência dos objetos de 6136/6137, papel postgres, limites de
   lock/tempo, existência das duas contas de teste. Qualquer falha =>
   nada é escrito; GATE FAIL.
2. Dentro de UM savepoint (bloco BEGIN … EXCEPTION):
   a. EXECUTE do DDL de 6136 (tabela, índice, RLS, policy, grants);
   b. EXECUTE do DDL de 6137 (duas funções, grants);
   c. chamada de pg_temp.p6_6849_validate(A, B) — o validador 6849
      v2.1 inalterado, com as suas 47 verificações, o seu GATE e o
      seu próprio savepoint interno; o relatório é capturado numa
      variável;
   d. RAISE da sentinela P6D00 => o savepoint é revertido: objetos
      criados, linhas de teste, grants, policy, índice e eventuais
      NOTIFY emitidos por event triggers são desfeitos.
3. Depois da reversão: D.3.1 prova que nenhum objeto existe; se
   existir, o statement inteiro é abortado (nada persiste); D.3.2
   prova papel/claims restaurados.
4. Saída: linhas D.* + as 48 linhas do 6849 + GATE do ensaio.

SEGURANÇA OPERACIONAL
- lock_timeout = 5s e statement_timeout = 120s (SET LOCAL, Seção 0),
  exigidos por D.0.5: sem eles, o ensaio não roda.
- Erro de sintaxe/privilégio/execução em qualquer passo => linha D.X
  FAIL, savepoint revertido. Cancelamento por statement_timeout não é
  capturável por WHEN OTHERS: aborta o statement inteiro.
- Locks: a criação das FKs pede SHARE ROW EXCLUSIVE em auth.users e
  pokemon_species, mantido até a reversão (segundos). Escritas
  concorrentes nessas tabelas (ex.: atualização de login) esperam.
  Executar em horário de baixo uso.
- Nenhum COMMIT é possível dentro de uma função chamada por SELECT;
  o DDL embutido não contém controle de transação (verificado).

USUÁRIOS (D-A revisada em 2026-10-14)
- Exige dois UUIDs distintos de contas EXISTENTES e não administrativas,
  escolhidas por Fabrício no momento da execução autorizada. Nenhuma
  conta é criada nem alterada; o ensaio só lê auth.users, e as linhas
  de favoritos dessas contas existem apenas dentro do savepoint.
- Os UUIDs são informados SOMENTE na cópia enviada ao banco; este
  arquivo versionado mantém os placeholders. Com os placeholders, D.0.6
  reprova e o ensaio nem chega a executar DDL (nenhuma escrita).

EXECUÇÃO (quando autorizado)
  CALL 1 — este arquivo inteiro (Seções 0–3), com os dois UUIDs
           informados só na cópia enviada (Seção 3). Devolve o relatório.
  CALL 2 — POSTCHECK somente leitura, em nova chamada (bloco
           comentado no fim).
================================================================
*/

-- =============================================================
-- SEÇÃO 0 — transação e limites (escopo desta chamada)
-- =============================================================
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =============================================================
-- SEÇÃO 1 — validador 6849 v2.1 (cópia byte-idêntica; D.0.3)
-- =============================================================
create or replace function pg_temp.p6_6849_validate(p_user_a uuid, p_user_b uuid)
returns table (seq integer, check_id text, item text, status text, detail text)
language plpgsql
volatile
as $fn$
#variable_conflict use_column
declare
  v_tbl        regclass := to_regclass('public.pokedex_species_favorite');
  v_role0      text := current_user;
  v_claims0    text := coalesce(current_setting('request.jwt.claims', true), '');
  v_sub0       text := coalesce(current_setting('request.jwt.claim.sub', true), '');
  res          jsonb := '[]'::jsonb;
  v_unexpected text;
  v_base_ab    bigint;
  v_base_total bigint;
  v_after_ab   bigint;
  v_after_tot  bigint;
  n            integer;
  n2           integer;
  ok           boolean;
  r1           boolean;
  r2           boolean;
  st           text;
  v_nums       integer[];
  v_list       integer[];
  v_t0         timestamptz;
  v_ms         numeric;
  v_species_25 uuid;
  v_inactive   integer;
  v_bc bigint; v_ba bigint; v_bp bigint; v_bi bigint;
  v_expected   text[] := array[
    '0.1','0.2',
    '1.1','1.2','1.3a','1.3b','1.3c','1.4a','1.4b','1.4c','1.5a','1.5b','1.6','1.7',
    '2.1','2.2','2.3',
    '3.1','3.2',
    '4.0','4.1','4.2','4.3','4.4','4.5',
    '5.1','5.2','5.3','5.4',
    '6.1','6.2','6.3',
    '7.1','7.2','7.3','7.4','7.5','7.6','7.7','7.8',
    '8.1','8.2','8.3',
    '9.1','9.2',
    '10.1','10.2'];
begin
  -- Linha de base (somente leitura, papel administrativo, fora do savepoint).
  if v_tbl is not null then
    execute 'select count(*) from public.pokedex_species_favorite where user_id in ($1, $2)'
      into v_base_ab using p_user_a, p_user_b;
    execute 'select count(*) from public.pokedex_species_favorite' into v_base_total;
  end if;

  -- =================================================================
  -- BLOCO DE TESTE — tudo aqui é revertido pela exceção sentinela P6R00.
  -- =================================================================
  begin
    -- 0. Pré-condições ------------------------------------------------
    ok := v_tbl is not null
      and to_regprocedure('public.get_my_pokedex_favorites()') is not null
      and to_regprocedure('public.set_pokedex_species_favorite(integer, boolean)') is not null;
    res := res || jsonb_build_object('id','0.1','item','pré','status',case when ok then 'PASS' else 'FAIL' end,
      'detail','6136/6137 aplicadas');
    if not ok then
      raise exception using errcode = 'P6R00', message = 'P6_6849_ROLLBACK_SENTINEL';
    end if;

    select count(*) into n from auth.users u where u.id in (p_user_a, p_user_b);
    ok := p_user_a is not null and p_user_b is not null and p_user_a <> p_user_b and n = 2;
    res := res || jsonb_build_object('id','0.2','item','pré','status',case when ok then 'PASS' else 'FAIL' end,
      'detail', format('usuários de teste distintos e existentes: %s de 2', n));
    if not ok then
      raise exception using errcode = 'P6R00', message = 'P6_6849_ROLLBACK_SENTINEL';
    end if;

    -- Estado determinístico para A e B (revertido no fim).
    delete from public.pokedex_species_favorite f where f.user_id in (p_user_a, p_user_b);

    select array_agg(s.national_dex_number order by s.national_dex_number) into v_nums
    from public.pokemon_species s where s.is_active;
    select s.id into v_species_25 from public.pokemon_species s where s.national_dex_number = 25;
    select min(s.national_dex_number) into v_inactive from public.pokemon_species s where not s.is_active;

    select count(*) into v_bc from public.collection;
    select count(*) into v_ba from public.collection_allocation;
    select count(*) into v_bp from public.physical_card;
    select count(*) into v_bi from public.inventory;

    -- 1. Estrutura e privilégios (itens 5, 8, 10) ---------------------
    select c.relrowsecurity into ok from pg_class c where c.oid = v_tbl;
    res := res || jsonb_build_object('id','1.1','item','10','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','RLS ativa');

    select count(*) filter (where p.cmd = 'SELECT'
                              and p.roles = array['authenticated']::name[]
                              and p.permissive = 'PERMISSIVE'
                              and p.with_check is null
                              and p.qual ~* 'user_id\s*=\s*\(\s*select\s+auth\.uid\(\)'),
           count(*)
      into n, n2
    from pg_policies p
    where p.schemaname = 'public' and p.tablename = 'pokedex_species_favorite';
    res := res || jsonb_build_object('id','1.2','item','10','status',case when n = 1 and n2 = 1 then 'PASS' else 'FAIL' end,
      'detail', format('policies=%s; SELECT/authenticated/permissiva/user_id = auth.uid()=%s', n2, n));

    ok := has_table_privilege('authenticated', v_tbl, 'SELECT')
      and not has_table_privilege('authenticated', v_tbl, 'INSERT')
      and not has_table_privilege('authenticated', v_tbl, 'UPDATE')
      and not has_table_privilege('authenticated', v_tbl, 'DELETE')
      and not has_table_privilege('authenticated', v_tbl, 'TRUNCATE')
      and not has_table_privilege('authenticated', v_tbl, 'REFERENCES')
      and not has_table_privilege('authenticated', v_tbl, 'TRIGGER')
      and not has_table_privilege('authenticated', v_tbl, 'MAINTAIN');
    res := res || jsonb_build_object('id','1.3a','item','10','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','authenticated: só SELECT (sem INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN)');

    ok := not has_table_privilege('anon', v_tbl, 'SELECT')
      and not has_table_privilege('anon', v_tbl, 'INSERT')
      and not has_table_privilege('anon', v_tbl, 'UPDATE')
      and not has_table_privilege('anon', v_tbl, 'DELETE')
      and not has_table_privilege('anon', v_tbl, 'TRUNCATE')
      and not has_table_privilege('anon', v_tbl, 'REFERENCES')
      and not has_table_privilege('anon', v_tbl, 'TRIGGER')
      and not has_table_privilege('anon', v_tbl, 'MAINTAIN');
    res := res || jsonb_build_object('id','1.3b','item','10','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','anon: nenhum privilégio de tabela');

    select not exists (select 1 from pg_class c, aclexplode(c.relacl) x where c.oid = v_tbl and x.grantee = 0)
      into ok;
    res := res || jsonb_build_object('id','1.3c','item','10','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','PUBLIC: nenhuma entrada na ACL da tabela');

    select p.prosecdef
       and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                   where cfg like 'search_path=%' and btrim(substring(cfg from 13), '''" ') = '')
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')
       and not has_function_privilege('anon', p.oid, 'EXECUTE')
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
      into ok
    from pg_proc p where p.oid = 'public.get_my_pokedex_favorites()'::regprocedure;
    res := res || jsonb_build_object('id','1.4a','item','10','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','get_my_pokedex_favorites: SECURITY DEFINER, search_path vazio (normalizado), EXECUTE só authenticated');

    select p.prosecdef
       and exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) cfg
                   where cfg like 'search_path=%' and btrim(substring(cfg from 13), '''" ') = '')
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')
       and not has_function_privilege('anon', p.oid, 'EXECUTE')
       and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)
      into ok
    from pg_proc p where p.oid = 'public.set_pokedex_species_favorite(integer, boolean)'::regprocedure;
    res := res || jsonb_build_object('id','1.4b','item','10','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','set_pokedex_species_favorite: SECURITY DEFINER, search_path vazio (normalizado), EXECUTE só authenticated');

    select bool_and(p.proowner = c.relowner
                    and pg_get_userbyid(p.proowner) not in ('anon', 'authenticated')
                    and not c.relforcerowsecurity),
           count(*), max(pg_get_userbyid(p.proowner))
      into ok, n, st
    from pg_proc p, pg_class c
    where c.oid = v_tbl
      and p.oid in ('public.get_my_pokedex_favorites()'::regprocedure,
                    'public.set_pokedex_species_favorite(integer, boolean)'::regprocedure);
    res := res || jsonb_build_object('id','1.4c','item','10','status',case when coalesce(ok,false) and n = 2 then 'PASS' else 'FAIL' end,
      'detail', format('proprietário das funções = proprietário da tabela (%s), não anon/authenticated; RLS não forçada', st));

    select count(*) into n
    from pg_constraint c
    where c.conrelid = v_tbl and c.contype = 'f'
      and c.confrelid = 'auth.users'::regclass
      and c.conkey  = array[(select a.attnum from pg_attribute a where a.attrelid = v_tbl and a.attname = 'user_id')]
      and c.confkey = array[(select a.attnum from pg_attribute a where a.attrelid = 'auth.users'::regclass and a.attname = 'id')]
      and c.confdeltype = 'c' and c.confupdtype = 'r';
    res := res || jsonb_build_object('id','1.5a','item','8','status',case when n = 1 then 'PASS' else 'FAIL' end,
      'detail','FK user_id → auth.users(id): ON DELETE CASCADE, ON UPDATE RESTRICT');

    select count(*) filter (where c.confrelid = 'public.pokemon_species'::regclass
                              and c.conkey  = array[(select a.attnum from pg_attribute a where a.attrelid = v_tbl and a.attname = 'pokemon_species_id')]
                              and c.confkey = array[(select a.attnum from pg_attribute a where a.attrelid = 'public.pokemon_species'::regclass and a.attname = 'id')]
                              and c.confdeltype = 'r' and c.confupdtype = 'r'),
           count(*)
      into n, n2
    from pg_constraint c
    where c.conrelid = v_tbl and c.contype = 'f';
    res := res || jsonb_build_object('id','1.5b','item','8','status',case when n = 1 and n2 = 2 then 'PASS' else 'FAIL' end,
      'detail', format('FK pokemon_species_id → pokemon_species(id) RESTRICT/RESTRICT; total de FKs = %s', n2));

    select count(*) into n
    from pg_constraint c
    where c.conrelid = v_tbl and c.contype = 'p'
      and (select array_agg(a.attname::text order by k.ord)
             from unnest(c.conkey) with ordinality k(attnum, ord)
             join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum)
          = array['user_id','pokemon_species_id'];
    res := res || jsonb_build_object('id','1.6','item','5','status',case when n = 1 then 'PASS' else 'FAIL' end,
      'detail','PK (user_id, pokemon_species_id)');

    select count(*) into n
    from pg_index i
    where i.indrelid = v_tbl
      and i.indexrelid = to_regclass('public.ix_pokedex_species_favorite_pokemon_species_id')
      and i.indnatts = 1
      and i.indkey[0] = (select a.attnum from pg_attribute a where a.attrelid = v_tbl and a.attname = 'pokemon_species_id');
    res := res || jsonb_build_object('id','1.7','item','10','status',case when n = 1 then 'PASS' else 'FAIL' end,
      'detail','índice da FK de espécie sobre (pokemon_species_id)');

    -- 2. Acesso anônimo (item 1) -------------------------------------
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role anon';

    begin
      execute 'select count(*) from public.pokedex_species_favorite' into n;
      ok := false; st := 'leu ' || n || ' linhas';
    exception when others then ok := sqlstate = '42501'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','2.1','item','1','status',case when ok then 'PASS' else 'FAIL' end,'detail','anon SELECT na tabela: '||st);

    begin
      perform public.get_my_pokedex_favorites();
      ok := false; st := 'executou';
    exception when others then ok := sqlstate = '42501'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','2.2','item','1','status',case when ok then 'PASS' else 'FAIL' end,'detail','anon get_my_pokedex_favorites: '||st);

    begin
      perform public.set_pokedex_species_favorite(25, true);
      ok := false; st := 'executou';
    exception when others then ok := sqlstate = '42501'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','2.3','item','1','status',case when ok then 'PASS' else 'FAIL' end,'detail','anon set_pokedex_species_favorite: '||st);

    execute 'reset role';

    -- 3. authenticated sem identidade (item 10) ---------------------------
    execute 'set local role authenticated';
    begin
      perform public.get_my_pokedex_favorites();
      ok := false; st := 'executou';
    exception when others then ok := sqlstate = '28000'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','3.1','item','10','status',case when ok then 'PASS' else 'FAIL' end,'detail','get_my sem auth.uid(): '||st);

    begin
      perform public.set_pokedex_species_favorite(25, true);
      ok := false; st := 'executou';
    exception when others then ok := sqlstate = '28000'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','3.2','item','10','status',case when ok then 'PASS' else 'FAIL' end,'detail','set sem auth.uid(): '||st);
    execute 'reset role';

    -- 4. Isolamento (itens 2 e 3) ----------------------------------------
    -- 4.0 Leitura vazia: A sem favoritos recebe 0 linhas, sem erro.
    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      select count(*) into n from public.get_my_pokedex_favorites();
      ok := n = 0; st := n || ' linhas';
    exception when others then ok := false; st := sqlstate || ' ' || sqlerrm;
    end;
    res := res || jsonb_build_object('id','4.0','item','2','status',case when ok then 'PASS' else 'FAIL' end,'detail','A sem favoritos: '||st);

    -- A favorita 25.
    r1 := public.set_pokedex_species_favorite(25, true);
    execute 'reset role';

    -- B favorita 6 e tenta desfavoritar o 25 (que é de A).
    perform set_config('request.jwt.claim.sub', p_user_b::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_b, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    r2 := public.set_pokedex_species_favorite(6, true);

    select array_agg(x.n order by x.ord) into v_list from public.get_my_pokedex_favorites() with ordinality as x(n, ord);
    res := res || jsonb_build_object('id','4.1','item','2','status',case when v_list = array[6] then 'PASS' else 'FAIL' end,
      'detail','B vê só os próprios: '||coalesce(v_list::text,'{}'));

    execute 'select count(*) from public.pokedex_species_favorite where user_id = $1' into n using p_user_a;
    res := res || jsonb_build_object('id','4.3','item','3','status',case when n = 0 then 'PASS' else 'FAIL' end,
      'detail','B SELECT direto nas linhas de A (que existem): '||n);

    perform public.set_pokedex_species_favorite(25, false);
    execute 'reset role';

    select count(*) into n from public.pokedex_species_favorite f where f.user_id = p_user_a and f.pokemon_species_id = v_species_25;
    res := res || jsonb_build_object('id','4.4','item','3','status',case when n = 1 then 'PASS' else 'FAIL' end,
      'detail','favorito 25 de A intacto após B "desfavoritar 25": '||n);

    perform set_config('request.jwt.claim.sub', p_user_a::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', p_user_a, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select array_agg(x.n order by x.ord) into v_list from public.get_my_pokedex_favorites() with ordinality as x(n, ord);
    res := res || jsonb_build_object('id','4.2','item','2','status',case when v_list = array[25] then 'PASS' else 'FAIL' end,
      'detail','A vê só os próprios: '||coalesce(v_list::text,'{}'));

    execute 'select count(*) from public.pokedex_species_favorite' into n;
    res := res || jsonb_build_object('id','4.5','item','3','status',case when n = 1 then 'PASS' else 'FAIL' end,
      'detail','A SELECT sem filtro (B tem 1 linha) devolve só as próprias: '||n);

    -- 5. Escrita direta negada (item 4) — como A -------------------------
    begin
      execute 'insert into public.pokedex_species_favorite (user_id, pokemon_species_id) values ($1, $2)' using p_user_a, v_species_25;
      ok := false; st := 'inseriu';
    exception when others then ok := sqlstate = '42501'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','5.1','item','4','status',case when ok then 'PASS' else 'FAIL' end,'detail','INSERT direto (próprio user_id): '||st);

    begin
      execute 'insert into public.pokedex_species_favorite (user_id, pokemon_species_id) values ($1, $2)' using p_user_b, v_species_25;
      ok := false; st := 'inseriu';
    exception when others then ok := sqlstate = '42501'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','5.2','item','4','status',case when ok then 'PASS' else 'FAIL' end,'detail','INSERT direto em nome de B: '||st);

    begin
      execute 'update public.pokedex_species_favorite set created_at = now()';
      ok := false; st := 'atualizou';
    exception when others then ok := sqlstate = '42501'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','5.3','item','4','status',case when ok then 'PASS' else 'FAIL' end,'detail','UPDATE direto: '||st);

    begin
      execute 'delete from public.pokedex_species_favorite';
      ok := false; st := 'apagou';
    exception when others then ok := sqlstate = '42501'; st := sqlstate;
    end;
    res := res || jsonb_build_object('id','5.4','item','4','status',case when ok then 'PASS' else 'FAIL' end,'detail','DELETE direto: '||st);

    -- 6. Idempotência e duplicidade (itens 5 e 6) — retorno E estado ------
    r1 := public.set_pokedex_species_favorite(25, true);
    r2 := public.set_pokedex_species_favorite(25, true);
    execute 'reset role';
    select count(*) into n from public.pokedex_species_favorite f where f.user_id = p_user_a and f.pokemon_species_id = v_species_25;
    res := res || jsonb_build_object('id','6.1','item','6','status',case when r1 and r2 and n = 1 then 'PASS' else 'FAIL' end,
      'detail', format('true×2: retornos %s/%s; linhas (A,25) persistidas = %s', r1, r2, n));

    execute 'set local role authenticated';
    r1 := public.set_pokedex_species_favorite(25, false);
    r2 := public.set_pokedex_species_favorite(25, false);
    execute 'reset role';
    select count(*) into n from public.pokedex_species_favorite f where f.user_id = p_user_a and f.pokemon_species_id = v_species_25;
    res := res || jsonb_build_object('id','6.2','item','6','status',case when not r1 and not r2 and n = 0 then 'PASS' else 'FAIL' end,
      'detail', format('false×2: retornos %s/%s; linhas (A,25) persistidas = %s', r1, r2, n));

    insert into public.pokedex_species_favorite (user_id, pokemon_species_id) values (p_user_a, v_species_25);
    begin
      insert into public.pokedex_species_favorite (user_id, pokemon_species_id) values (p_user_a, v_species_25);
      ok := false; st := 'duplicou';
    exception when unique_violation then ok := true; st := '23505';
    end;
    res := res || jsonb_build_object('id','6.3','item','5','status',case when ok then 'PASS' else 'FAIL' end,
      'detail','INSERT duplicado (papel administrativo, prova da PK): '||st);
    delete from public.pokedex_species_favorite f where f.user_id = p_user_a;

    -- 7. Entradas inválidas (item 7) — como A ---------------------------
    execute 'set local role authenticated';

    begin perform public.set_pokedex_species_favorite(0, true); ok := false; st := 'aceitou';
    exception when others then ok := sqlstate = '22023'; st := sqlstate; end;
    res := res || jsonb_build_object('id','7.1','item','7','status',case when ok then 'PASS' else 'FAIL' end,'detail','número 0: '||st);

    begin perform public.set_pokedex_species_favorite(-1, true); ok := false; st := 'aceitou';
    exception when others then ok := sqlstate = '22023'; st := sqlstate; end;
    res := res || jsonb_build_object('id','7.2','item','7','status',case when ok then 'PASS' else 'FAIL' end,'detail','número negativo: '||st);

    begin perform public.set_pokedex_species_favorite(10000, true); ok := false; st := 'aceitou';
    exception when others then ok := sqlstate = '22023'; st := sqlstate; end;
    res := res || jsonb_build_object('id','7.3','item','7','status',case when ok then 'PASS' else 'FAIL' end,'detail','número 10000: '||st);

    begin perform public.set_pokedex_species_favorite(null::integer, true); ok := false; st := 'aceitou';
    exception when others then ok := sqlstate = '22023'; st := sqlstate; end;
    res := res || jsonb_build_object('id','7.4','item','7','status',case when ok then 'PASS' else 'FAIL' end,'detail','número nulo: '||st);

    begin perform public.set_pokedex_species_favorite(25, null::boolean); ok := false; st := 'aceitou';
    exception when others then ok := sqlstate = '22023'; st := sqlstate; end;
    res := res || jsonb_build_object('id','7.5','item','7','status',case when ok then 'PASS' else 'FAIL' end,'detail','estado nulo: '||st);

    begin perform public.set_pokedex_species_favorite(9999, true); ok := false; st := 'aceitou';
    exception when others then ok := sqlstate = 'P0002'; st := sqlstate; end;
    res := res || jsonb_build_object('id','7.6','item','7','status',case when ok then 'PASS' else 'FAIL' end,'detail','espécie inexistente (9999): '||st);

    if v_inactive is null then
      res := res || jsonb_build_object('id','7.7','item','7','status','NOT_PROVEN',
        'detail','nenhuma espécie inativa no banco (L4); regra coberta só por leitura do código da 6137');
    else
      begin perform public.set_pokedex_species_favorite(v_inactive, true); ok := false; st := 'aceitou';
      exception when others then ok := sqlstate = 'P0002'; st := sqlstate; end;
      res := res || jsonb_build_object('id','7.7','item','7','status',case when ok then 'PASS' else 'FAIL' end,'detail','favoritar espécie inativa: '||st);
    end if;
    execute 'reset role';

    select count(*) into n from public.pokedex_species_favorite f where f.user_id = p_user_a;
    res := res || jsonb_build_object('id','7.8','item','7','status',case when n = 0 then 'PASS' else 'FAIL' end,
      'detail','nenhuma linha criada por entradas inválidas: '||n);

    -- 8. Capacidade (item 9) — como A ----------------------------------
    execute 'set local role authenticated';
    v_t0 := clock_timestamp();
    for n in select unnest(v_nums) loop
      perform public.set_pokedex_species_favorite(n, true);
    end loop;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    execute 'select count(*) from public.pokedex_species_favorite' into n2;
    res := res || jsonb_build_object('id','8.1','item','9',
      'status',case when coalesce(array_length(v_nums, 1), 0) > 0 and n2 = array_length(v_nums, 1) then 'PASS' else 'FAIL' end,
      'detail', format('linhas visíveis a A = %s; espécies ativas = %s; gravação em %s ms', n2, coalesce(array_length(v_nums, 1), 0), v_ms));

    v_t0 := clock_timestamp();
    select array_agg(x.n order by x.ord) into v_list from public.get_my_pokedex_favorites() with ordinality as x(n, ord);
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    res := res || jsonb_build_object('id','8.2','item','9','status',case when v_list = v_nums then 'PASS' else 'FAIL' end,
      'detail', format('leitura devolve %s números na ordem nacional (WITH ORDINALITY), em %s ms', coalesce(array_length(v_list, 1), 0), v_ms));
    execute 'reset role';

    select count(*) into n from public.pokedex_species_favorite f where f.user_id = p_user_a;
    select count(*) into n2 from public.pokedex_species_favorite f where f.user_id = p_user_b;
    res := res || jsonb_build_object('id','8.3','item','9','status',case when n = array_length(v_nums, 1) and n2 = 1 then 'PASS' else 'FAIL' end,
      'detail', format('A=%s linhas, B=%s (isolamento mantido sob volume)', n, n2));

    -- 9. Sem efeito em Collection/Inventory e no Favorite de Card (item 11)
    ok := (select count(*) from public.collection) = v_bc
      and (select count(*) from public.collection_allocation) = v_ba
      and (select count(*) from public.physical_card) = v_bp
      and (select count(*) from public.inventory) = v_bi;
    res := res || jsonb_build_object('id','9.1','item','11','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail','collection / collection_allocation / physical_card / inventory inalterados');

    select count(*) into n
    from pg_proc p
    where p.oid in ('public.get_my_pokedex_favorites()'::regprocedure,
                    'public.set_pokedex_species_favorite(integer, boolean)'::regprocedure)
      and p.prosrc ~* '\m(collection|inventory|physical_card|card|card_variant|wishlist)\M';
    res := res || jsonb_build_object('id','9.2','item','11','status',case when n = 0 then 'PASS' else 'FAIL' end,
      'detail','funções não referenciam Collection, Inventory, Card ou Wishlist');

    -- Fim do bloco: reverte TUDO o que foi escrito/trocado acima.
    raise exception using errcode = 'P6R00', message = 'P6_6849_ROLLBACK_SENTINEL';
  exception
    when sqlstate 'P6R00' then
      null;
    when others then
      v_unexpected := sqlstate || ': ' || sqlerrm;
  end;

  -- =================================================================
  -- 10. Prova da reversão (papel administrativo; fora do savepoint)
  -- =================================================================
  if v_unexpected is not null then
    res := res || jsonb_build_object('id','X.1','item','12','status','FAIL',
      'detail','erro inesperado no bloco de teste (revertido): '||v_unexpected);
  end if;

  if v_tbl is not null then
    execute 'select count(*) from public.pokedex_species_favorite where user_id in ($1, $2)'
      into v_after_ab using p_user_a, p_user_b;
    execute 'select count(*) from public.pokedex_species_favorite' into v_after_tot;
    ok := v_after_ab = v_base_ab and v_after_tot = v_base_total;
    res := res || jsonb_build_object('id','10.1','item','12','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
      'detail', format('reversão no próprio statement: A+B %s→%s, total %s→%s', v_base_ab, v_after_ab, v_base_total, v_after_tot));
    if not coalesce(ok, false) then
      -- Salvaguarda: aborta o statement inteiro (atômico) — nada persiste.
      raise exception 'P6_6849_ROLLBACK_NOT_CONFIRMED (A+B %→%, total %→%)', v_base_ab, v_after_ab, v_base_total, v_after_tot;
    end if;
  else
    res := res || jsonb_build_object('id','10.1','item','12','status','FAIL','detail','tabela ausente: reversão não verificável');
  end if;

  ok := current_user = v_role0
    and coalesce(current_setting('request.jwt.claims', true), '') = v_claims0
    and coalesce(current_setting('request.jwt.claim.sub', true), '') = v_sub0;
  res := res || jsonb_build_object('id','10.2','item','12','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
    'detail', format('papel restaurado (%s) e claims restauradas', current_user));

  -- =================================================================
  -- Saída: linhas + GATE (lista exata de ids esperados)
  -- =================================================================
  return query
  select e.ord::integer, e.v ->> 'id', e.v ->> 'item', e.v ->> 'status', e.v ->> 'detail'
  from jsonb_array_elements(res) with ordinality as e(v, ord);

  return query
  with r as (
    select e.v ->> 'id' as rid, e.v ->> 'status' as rst
    from jsonb_array_elements(res) as e(v)
  )
  select 9999,
         'GATE',
         '-',
         case
           when (select count(*) from r) = cardinality(v_expected)
            and (select count(distinct rid) from r) = cardinality(v_expected)
            and not exists (select 1 from r where rid <> all (v_expected))
            and not exists (select 1 from unnest(v_expected) ex(id) where not exists (select 1 from r where r.rid = ex.id))
            and not exists (select 1 from r where rst = 'FAIL')
            and not exists (select 1 from r where rst = 'NOT_PROVEN' and rid <> '7.7')
            and not exists (select 1 from r where rst not in ('PASS','FAIL','NOT_PROVEN'))
           then 'PASS' else 'FAIL'
         end,
         format('esperadas=%s; recebidas=%s; PASS=%s; FAIL=%s; NOT_PROVEN=%s',
                cardinality(v_expected),
                (select count(*) from r),
                (select count(*) from r where rst = 'PASS'),
                (select count(*) from r where rst = 'FAIL'),
                (select count(*) from r where rst = 'NOT_PROVEN'));
end;
$fn$;

-- =============================================================
-- SEÇÃO 2 — função de ensaio
-- =============================================================
create or replace function pg_temp.p6_6850_dry_run(p_user_a uuid, p_user_b uuid)
returns table (seq integer, origem text, verificacao text, item text, situacao text, detalhe text)
language plpgsql
volatile
as $dry$
#variable_conflict use_column
declare
  c_hash_6136  constant text := 'd4d5c2d75ea24771f4d56ee5bbc160e812ddcc1b98b07f1c598eb7e014d63223';
  c_hash_6137  constant text := '37ea65d7893b07c8681e85e09f4ca53c1e83f50081e9e969f5520f22a195d6c7';
  c_hash_6849  constant text := '4bd0860ff50fdfe558c88dfd49952b3545037808bf82ebc6811fb2b5d4312b44';
  v_ddl_6136   constant text := $p6136$
create table public.pokedex_species_favorite (
  user_id            uuid        not null,
  pokemon_species_id uuid        not null,
  created_at         timestamptz not null default now(),
  constraint pk_pokedex_species_favorite
    primary key (user_id, pokemon_species_id),
  constraint fk_pokedex_species_favorite_user_id
    foreign key (user_id) references auth.users(id)
    on update restrict on delete cascade,
  constraint fk_pokedex_species_favorite_pokemon_species_id
    foreign key (pokemon_species_id) references public.pokemon_species(id)
    on update restrict on delete restrict
);

create index ix_pokedex_species_favorite_pokemon_species_id
  on public.pokedex_species_favorite (pokemon_species_id);

comment on table public.pokedex_species_favorite is
  'Pokédex P6 (Query 6136): Espécie favorita — preferência pessoal de um User por uma Pokémon Species. Binária, independente de posse de cartas, de Collection e do Favorite de Card. Leitura só das próprias linhas (RLS); escrita só via set_pokedex_species_favorite().';

alter table public.pokedex_species_favorite enable row level security;

create policy pokedex_species_favorite_select_own
  on public.pokedex_species_favorite
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.pokedex_species_favorite from public;
revoke all on table public.pokedex_species_favorite from anon;
revoke all on table public.pokedex_species_favorite from authenticated;
grant select on table public.pokedex_species_favorite to authenticated;

$p6136$;
  v_ddl_6137   constant text := $p6137$
create or replace function public.get_my_pokedex_favorites()
returns table (national_dex_number integer)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select s.national_dex_number
  from public.pokedex_species_favorite f
  join public.pokemon_species s
    on s.id = f.pokemon_species_id
   and s.is_active
  where f.user_id = v_user
  order by s.national_dex_number;
end;
$$;

comment on function public.get_my_pokedex_favorites() is
  'Pokédex P6 (Query 6137): números nacionais das espécies favoritas do usuário da sessão, em ordem. Leitura agregada (uma por página); exige auth.uid(); sem UUIDs.';

create or replace function public.set_pokedex_species_favorite(
  p_national_dex_number integer,
  p_favorite boolean
)
returns boolean
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_species   uuid;
  v_is_active boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_favorite is null then
    raise exception 'INVALID_FAVORITE_STATE' using errcode = '22023';
  end if;

  if p_national_dex_number is null or p_national_dex_number not between 1 and 9999 then
    raise exception 'INVALID_NATIONAL_DEX_NUMBER' using errcode = '22023';
  end if;

  select s.id, s.is_active
    into v_species, v_is_active
  from public.pokemon_species s
  where s.national_dex_number = p_national_dex_number;

  if v_species is null or (p_favorite and not v_is_active) then
    raise exception 'SPECIES_NOT_FOUND' using errcode = 'P0002';
  end if;

  if p_favorite then
    insert into public.pokedex_species_favorite (user_id, pokemon_species_id)
    values (v_user, v_species)
    on conflict on constraint pk_pokedex_species_favorite do nothing;
  else
    delete from public.pokedex_species_favorite f
    where f.user_id = v_user
      and f.pokemon_species_id = v_species;
  end if;

  return p_favorite;
end;
$$;

comment on function public.set_pokedex_species_favorite(integer, boolean) is
  'Pokédex P6 (Query 6137): define (não alterna) se uma espécie é favorita do usuário da sessão; idempotente; devolve o estado final. Única via de escrita de pokedex_species_favorite.';

revoke all on function public.get_my_pokedex_favorites() from public;
revoke all on function public.get_my_pokedex_favorites() from anon;
grant execute on function public.get_my_pokedex_favorites() to authenticated;

revoke all on function public.set_pokedex_species_favorite(integer, boolean) from public;
revoke all on function public.set_pokedex_species_favorite(integer, boolean) from anon;
grant execute on function public.set_pokedex_species_favorite(integer, boolean) to authenticated;

$p6137$;
  v_role0      text := current_user;
  v_claims0    text := coalesce(current_setting('request.jwt.claims', true), '');
  v_sub0       text := coalesce(current_setting('request.jwt.claim.sub', true), '');
  d            jsonb := '[]'::jsonb;
  v_val        jsonb := '[]'::jsonb;
  v_step       text := 'pre';
  v_err        text;
  v_pre_ok     boolean := true;
  v_ran_6136   boolean := false;
  v_ran_6137   boolean := false;
  v_ran_val    boolean := false;
  v_sentinel   boolean := false;
  v_val_gate   text;
  v_val_rows   integer;
  v_absent     boolean;
  v_users      integer;
  ok           boolean;
  h            text;
  v_expected   text[] := array['D.0.1','D.0.2','D.0.3','D.0.4','D.0.5','D.0.6',
                               'D.1.1','D.1.2','D.2.1','D.3.1','D.3.2'];
begin
  -- -----------------------------------------------------------
  -- D.0 Pré-condições (somente leitura)
  -- -----------------------------------------------------------
  h := encode(sha256(convert_to(replace(v_ddl_6136, E'\r', ''), 'UTF8')), 'hex');
  ok := h = c_hash_6136;
  v_pre_ok := v_pre_ok and ok;
  d := d || jsonb_build_object('id','D.0.1','status',case when ok then 'PASS' else 'FAIL' end,
    'detail','identidade do DDL 6136 embutido: '||h);

  h := encode(sha256(convert_to(replace(v_ddl_6137, E'\r', ''), 'UTF8')), 'hex');
  ok := h = c_hash_6137;
  v_pre_ok := v_pre_ok and ok;
  d := d || jsonb_build_object('id','D.0.2','status',case when ok then 'PASS' else 'FAIL' end,
    'detail','identidade do DDL 6137 embutido: '||h);

  select encode(sha256(convert_to(replace(p.prosrc, E'\r', ''), 'UTF8')), 'hex') into h
  from pg_proc p where p.oid = to_regprocedure('pg_temp.p6_6849_validate(uuid,uuid)');
  ok := h is not null and h = c_hash_6849;
  v_pre_ok := v_pre_ok and ok;
  d := d || jsonb_build_object('id','D.0.3','status',case when ok then 'PASS' else 'FAIL' end,
    'detail','identidade do validador 6849 v2.1 (prosrc): '||coalesce(h,'ausente'));

  ok := to_regclass('public.pokedex_species_favorite') is null
    and to_regclass('public.ix_pokedex_species_favorite_pokemon_species_id') is null
    and to_regprocedure('public.get_my_pokedex_favorites()') is null
    and to_regprocedure('public.set_pokedex_species_favorite(integer, boolean)') is null
    and not exists (select 1 from pg_policies pp where pp.policyname = 'pokedex_species_favorite_select_own')
    and not exists (select 1 from pg_constraint k where k.conname in
          ('pk_pokedex_species_favorite','fk_pokedex_species_favorite_user_id','fk_pokedex_species_favorite_pokemon_species_id'));
  v_pre_ok := v_pre_ok and ok;
  d := d || jsonb_build_object('id','D.0.4','status',case when ok then 'PASS' else 'FAIL' end,
    'detail','objetos de 6136/6137 ausentes antes do ensaio (se presentes, o ensaio NÃO roda)');

  ok := current_user = 'postgres'
    and current_setting('lock_timeout')::interval between interval '1 second' and interval '10 seconds'
    and current_setting('statement_timeout')::interval between interval '10 seconds' and interval '5 minutes';
  v_pre_ok := v_pre_ok and coalesce(ok, false);
  d := d || jsonb_build_object('id','D.0.5','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
    'detail', format('papel=%s; lock_timeout=%s; statement_timeout=%s', current_user,
                     current_setting('lock_timeout'), current_setting('statement_timeout')));

  -- D.0.6 Contas de teste (D-A): só se valida a existência e a distinção — o ensaio
  -- não roda sem elas, evitando DDL inútil. UUIDs não são ecoados no relatório.
  select count(*) into v_users from auth.users u where u.id in (p_user_a, p_user_b);
  ok := p_user_a is not null and p_user_b is not null and p_user_a <> p_user_b and v_users = 2;
  v_pre_ok := v_pre_ok and ok;
  d := d || jsonb_build_object('id','D.0.6','status',case when ok then 'PASS' else 'FAIL' end,
    'detail', format('contas de teste distintas e existentes: %s de 2', v_users));

  -- -----------------------------------------------------------
  -- Bloco reversível (savepoint) — só roda com todas as pré-condições
  -- -----------------------------------------------------------
  if v_pre_ok then
    begin
      v_step := '6136';
      execute v_ddl_6136;
      v_ran_6136 := true;

      v_step := '6137';
      execute v_ddl_6137;
      v_ran_6137 := true;

      v_step := '6849';
      select coalesce(jsonb_agg(jsonb_build_object('seq', r.seq, 'id', r.check_id, 'item', r.item,
                                                   'status', r.status, 'detail', r.detail) order by r.seq),
                      '[]'::jsonb)
        into v_val
      from pg_temp.p6_6849_validate(p_user_a, p_user_b) r;
      v_ran_val := true;

      v_step := 'sentinela';
      raise exception using errcode = 'P6D00', message = 'P6_6850_DRY_RUN_ROLLBACK_SENTINEL';
    exception
      when sqlstate 'P6D00' then
        v_sentinel := true;
      when others then
        v_err := v_step || ': ' || sqlstate || ': ' || sqlerrm;
    end;

    if not v_sentinel and v_err is null then
      -- Caminho impossível por construção; abortar por segurança.
      raise exception 'P6_6850_SENTINEL_NOT_REACHED';
    end if;
  end if;

  -- -----------------------------------------------------------
  -- D.1 / D.2 Resultado dos passos
  -- -----------------------------------------------------------
  d := d || jsonb_build_object('id','D.1.1','status',
    case when v_ran_6136 then 'PASS' when not v_pre_ok then 'NOT_RUN' else 'FAIL' end,
    'detail','DDL 6136 executado sem erro');
  d := d || jsonb_build_object('id','D.1.2','status',
    case when v_ran_6137 then 'PASS' when not v_pre_ok then 'NOT_RUN' else 'FAIL' end,
    'detail','DDL 6137 executado sem erro');

  v_val_rows := jsonb_array_length(v_val);
  select e.v ->> 'status' into v_val_gate from jsonb_array_elements(v_val) as e(v) where e.v ->> 'id' = 'GATE';
  ok := v_ran_val and v_val_gate = 'PASS' and v_val_rows = 48;
  d := d || jsonb_build_object('id','D.2.1','status',
    case when coalesce(ok,false) then 'PASS' when not v_pre_ok then 'NOT_RUN' else 'FAIL' end,
    'detail', format('GATE do 6849 = %s; linhas do 6849 = %s (esperado PASS e 48)', coalesce(v_val_gate,'ausente'), v_val_rows));

  -- -----------------------------------------------------------
  -- D.3 Prova da reversão (fora do savepoint)
  -- -----------------------------------------------------------
  v_absent := to_regclass('public.pokedex_species_favorite') is null
    and to_regclass('public.ix_pokedex_species_favorite_pokemon_species_id') is null
    and to_regprocedure('public.get_my_pokedex_favorites()') is null
    and to_regprocedure('public.set_pokedex_species_favorite(integer, boolean)') is null
    and not exists (select 1 from pg_policies pp where pp.policyname = 'pokedex_species_favorite_select_own')
    and not exists (select 1 from pg_constraint k where k.conname in
          ('pk_pokedex_species_favorite','fk_pokedex_species_favorite_user_id','fk_pokedex_species_favorite_pokemon_species_id'));
  if v_pre_ok then
    d := d || jsonb_build_object('id','D.3.1','status',case when v_absent then 'PASS' else 'FAIL' end,
      'detail','após a reversão: tabela, índice, funções, policy e constraints inexistentes');
    if not v_absent then
      -- Salvaguarda: aborta o statement inteiro (atômico) — nada persiste.
      raise exception 'P6_6850_REVERT_NOT_CONFIRMED';
    end if;
  else
    d := d || jsonb_build_object('id','D.3.1','status','NOT_RUN',
      'detail','ensaio não executado (pré-condição falhou); nenhuma escrita ocorreu');
  end if;

  ok := current_user = v_role0
    and coalesce(current_setting('request.jwt.claims', true), '') = v_claims0
    and coalesce(current_setting('request.jwt.claim.sub', true), '') = v_sub0;
  d := d || jsonb_build_object('id','D.3.2','status',case when coalesce(ok,false) then 'PASS' else 'FAIL' end,
    'detail', format('papel restaurado (%s) e claims restauradas', current_user));

  if v_err is not null then
    d := d || jsonb_build_object('id','D.X','status','FAIL','detail','erro no ensaio (revertido): '||v_err);
  end if;

  -- -----------------------------------------------------------
  -- Saída: ensaio + 6849 + GATE do ensaio
  -- -----------------------------------------------------------
  return query
  select e.ord::integer, 'ENSAIO', e.v ->> 'id', '-', e.v ->> 'status', e.v ->> 'detail'
  from jsonb_array_elements(d) with ordinality as e(v, ord);

  return query
  select 1000 + (e.v ->> 'seq')::integer, '6849', e.v ->> 'id', e.v ->> 'item', e.v ->> 'status', e.v ->> 'detail'
  from jsonb_array_elements(v_val) as e(v);

  return query
  with r as (
    select e.v ->> 'id' as rid, e.v ->> 'status' as rst
    from jsonb_array_elements(d) as e(v)
  )
  select 99999, 'ENSAIO', 'GATE-ENSAIO', '-',
         case
           when (select count(*) from r) = cardinality(v_expected)
            and (select count(distinct rid) from r) = cardinality(v_expected)
            and not exists (select 1 from r where rid <> all (v_expected))
            and not exists (select 1 from unnest(v_expected) ex(id) where not exists (select 1 from r where r.rid = ex.id))
            and not exists (select 1 from r where rst <> 'PASS')
           then 'PASS' else 'FAIL'
         end,
         format('esperadas=%s; recebidas=%s; PASS=%s; não-PASS=%s; GATE 6849=%s',
                cardinality(v_expected), (select count(*) from r),
                (select count(*) from r where rst = 'PASS'),
                (select count(*) from r where rst <> 'PASS'),
                coalesce(v_val_gate, 'ausente'));
end;
$dry$;

-- =============================================================
-- SEÇÃO 3 — CALL 1: na CÓPIA enviada ao banco (nunca neste arquivo),
-- trocar os dois placeholders pelos UUIDs de duas contas existentes não
-- administrativas (D-A). Último statement: devolve o relatório completo.
-- =============================================================
select * from pg_temp.p6_6850_dry_run(
  '00000000-0000-0000-0000-00000000000A'::uuid,
  '00000000-0000-0000-0000-00000000000B'::uuid
) order by seq;

-- =============================================================
-- CALL 2 — POSTCHECK independente, somente leitura, em NOVA chamada.
-- Esperado: todas as colunas booleanas = true; funcoes_temporarias_residuais = 0;
-- transacoes_pendentes = 0. Alcance: esta consulta, feita em OUTRA conexão, prova
-- a ausência de objetos PERMANENTES e de funções pg_temp COMMITADAS. Ela NÃO prova
-- que a sessão da CALL 1 deixou de existir: se aquela transação ainda estiver
-- aberta, suas funções pg_temp não são visíveis daqui; transacoes_pendentes só a
-- detecta enquanto a última query daquela sessão for o próprio 6850 (R1 em
-- AUDIT-P6.1-DRYRUN.md §4 e §10).
-- =============================================================
-- begin transaction read only;
-- select
--   to_regclass('public.pokedex_species_favorite') is null                                as tabela_ausente,
--   to_regclass('public.ix_pokedex_species_favorite_pokemon_species_id') is null          as indice_ausente,
--   to_regprocedure('public.get_my_pokedex_favorites()') is null                          as fn_get_ausente,
--   to_regprocedure('public.set_pokedex_species_favorite(integer, boolean)') is null      as fn_set_ausente,
--   (select count(*) from pg_policies where policyname = 'pokedex_species_favorite_select_own') = 0 as policy_ausente,
--   (select count(*) from pg_constraint where conname in ('pk_pokedex_species_favorite',
--      'fk_pokedex_species_favorite_user_id','fk_pokedex_species_favorite_pokemon_species_id')) = 0 as constraints_ausentes,
--   (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and p.proname in ('get_my_pokedex_favorites','set_pokedex_species_favorite')) = 0 as sem_funcoes_publicas,
--   (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace
--     where c.relname ilike '%favor%' and n.nspname not in ('pg_catalog','information_schema')) = 0 as sem_objetos_favor,
--   (select count(*) from pg_proc where proname in ('p6_6849_validate','p6_6850_dry_run'))  as funcoes_temporarias_residuais,
--   (select count(*) from pg_stat_activity
--     where state like 'idle in transaction%' and query ilike '%p6_6850%')                 as transacoes_pendentes;
