/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6849 - Validate Pokédex Species Favorite (6136/6137)
Versão......: 2.1 (Correction-02, 2026-10-14)
Status......: PROPOSTO — NÃO EXECUTADO (roda depois de 6136 e 6137;
              quem executa é Fabrício, após auditoria independente)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-14 (Pokédex P6.1)

MUDANÇAS 2.0 -> 2.1 (Correction-02, após a 1ª execução do 6850)
----------------------------------------------------------------
1.7        Falso negativo corrigido. pg_index.indkey é int2vector com
           limite inferior 0; indkey::int2[] gera '[0:0]={n}' e a
           igualdade de arrays compara também os limites, logo nunca
           casava com array[n] (limite 1). Agora: indnatts = 1 e
           indkey[0] = attnum de pokemon_species_id. Mantidos: mesma
           tabela (indrelid), mesmo índice nomeado (indexrelid) e
           contagem exata n = 1. Nenhum outro critério alterado.

MUDANÇAS 1.0 -> 2.0 (Correction-01, AUDIT-P6.1-STATIC.md)
----------------------------------------------------------
BLOCKER-1  Protocolo. A v1.0 dependia de um ROLLBACK numa chamada
           posterior e devolvia o relatório antes do ROLLBACK. Agora
           o rollback dos efeitos de teste acontece DENTRO do mesmo
           statement que produz o relatório (savepoint + exceção
           sentinela), sem depender do comportamento do canal. Ver
           "PROTOCOLO" abaixo.
BLOCKER-2  8.1 deixa de ser PASS incondicional: compara as linhas
           visíveis ao usuário A com o número de espécies ativas.
GAP-3      6.1/6.2 avaliam retorno E estado persistido.
GAP-4      1.3a/1.3b/1.3c cobrem SELECT, INSERT, UPDATE, DELETE,
           TRUNCATE, REFERENCES, TRIGGER, MAINTAIN e PUBLIC.
GAP-5      1.4a/1.4b normalizam search_path (precedente 5818).
GAP-6      1.5a/1.5b amarram coluna → tabela/coluna referenciada e
           conferem confdeltype/confupdtype.
GAP-7      4.0 prova leitura vazia (usuário sem favoritos, sem erro).
GAP-8      1.4c confere proprietário das funções = proprietário da
           tabela, que não é anon/authenticated, e RLS não forçada.
GAP-9      8.2 usa WITH ORDINALITY (ordem garantida).
GAP-10     Três estados explícitos: PASS / FAIL / NOT_PROVEN.
           Resultado nulo de verificação obrigatória = FAIL. Só 7.7
           pode ser NOT_PROVEN (L4).
GAP-11     GATE confere a lista exata de 47 ids esperados (não só a
           contagem).

PROTOCOLO (reconciliado com o canal documentado em 5818 §B/§14)
----------------------------------------------------------------
Fatos do canal (medidos e registrados em 5818): (a) devolve só o
resultado do ÚLTIMO statement; (b) não preserva sessão nem
transação entre chamadas. Logo, um ROLLBACK numa chamada posterior
NÃO é aceito como garantia de reversão.

Garantia adotada — independente do canal:
1. Todo o teste roda num ÚNICO statement:
     SELECT * FROM pg_temp.p6_6849_validate(<A>, <B>);
   Um statement é atômico: não existe commit entre as operações
   dele.
2. Dentro da função, todas as escritas e trocas de papel ocorrem
   num bloco BEGIN … EXCEPTION (savepoint). O bloco termina SEMPRE
   com RAISE da exceção sentinela P6R00, que reverte o savepoint:
   linhas inseridas/apagadas, SET LOCAL ROLE e claims voltam ao
   estado anterior. Os resultados sobrevivem porque ficam em
   variáveis PL/pgSQL (não transacionais).
3. Erro inesperado dentro do bloco: também reverte o savepoint e
   vira a linha X.1 = FAIL (GATE FAIL). Erro fora do bloco aborta o
   statement inteiro (atômico: nada persiste).
4. Depois do bloco, 10.1 prova a reversão (contagens de A, B e total
   iguais à linha de base) e 10.2 prova papel/claims restaurados. Se
   a reversão NÃO se confirmar, a função levanta
   P6_6849_ROLLBACK_NOT_CONFIRMED, abortando o statement (nada
   persiste; o relatório se perde, mas a integridade não).
5. Único objeto criado fora desse statement: a função pg_temp, que
   é local da sessão e não toca dados; desaparece no fim da sessão.

Execução (2 chamadas, ambas por Fabrício, após autorização):
  CALL 1 — este arquivo inteiro (CREATE FUNCTION pg_temp + SELECT).
           Preencher os dois UUIDs no SELECT final. Devolve o
           relatório (47 linhas + GATE).
  CALL 2 — POSTCHECK independente, somente leitura, em nova
           chamada/sessão (bloco comentado no fim do arquivo).

Limitações (README §5.2): L1 papel administrativo + SET LOCAL ROLE
(prova o banco, não o JWT do PostgREST); L2 sem concorrência real;
L3 exclusão de conta só estrutural; L4 espécie inativa (7.7
NOT_PROVEN se não houver); L5 exige dois usuários de teste do
Supabase Auth; L6 sintaxe não validada por parser.

Pré-requisitos: Queries 6136 e 6137 executadas; PostgreSQL 17
(MAINTAIN — mesmo requisito já satisfeito por 5000).
================================================================
*/

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

-- >>> CALL 1 — preencher os UUIDs dos dois usuários de teste (distintos). <<<
-- Último statement da chamada: devolve o relatório completo.
select * from pg_temp.p6_6849_validate(
  '00000000-0000-0000-0000-00000000000A'::uuid,
  '00000000-0000-0000-0000-00000000000B'::uuid
) order by seq;

-- >>> CALL 2 — POSTCHECK independente (somente leitura), em NOVA chamada. <<<
-- Esperado: test_user_rows e total_rows iguais à linha de base informada
-- em 10.1 (0 e 0 se a tabela acabou de ser criada).
-- select
--   (select count(*) from public.pokedex_species_favorite
--     where user_id in ('<UUID_USUARIO_A>'::uuid, '<UUID_USUARIO_B>'::uuid)) as test_user_rows,
--   (select count(*) from public.pokedex_species_favorite)                   as total_rows;
