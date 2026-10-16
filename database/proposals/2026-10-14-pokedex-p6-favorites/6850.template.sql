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
- 6136_create_pokedex_species_favorite_table.sql      @@F6136@@
- 6137_create_pokedex_species_favorite_functions.sql  @@F6137@@
- 6849_validate_pokedex_species_favorite.sql (v2.1)   @@F6849@@

IDENTIDADE DO CONTEÚDO ENSAIADO (sha256, texto sem \r)
- DDL 6136 embutido = texto entre a linha "begin;" e a linha
  "commit;" de 6136 ........................... @@H6136@@
- DDL 6137 embutido = idem para 6137 .......... @@H6137@@
- Corpo (prosrc) de pg_temp.p6_6849_validate =
  texto entre os delimitadores $fn$ de 6849 ... @@H6849@@
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
@@VALIDATOR_FUNCTION@@

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
  c_hash_6136  constant text := '@@H6136@@';
  c_hash_6137  constant text := '@@H6137@@';
  c_hash_6849  constant text := '@@H6849@@';
  v_ddl_6136   constant text := @@DDL_6136@@;
  v_ddl_6137   constant text := @@DDL_6137@@;
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
