/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5886 - Verificações da fundação R2-F (5358/5359)
Versão......: 0.2 (R2-F B1 SQL CORRECTION-05: P0 com as configurações exatas lidas por
              auth.uid(); A2 confere processadas = alvo e identidade aceita pela
              5188; A3 com identidade nas duas configurações e leitura válida do
              titular; N1 confere o balanço dos contadores)
Status......: PROPOSTO — NÃO EXECUTADO. Cada bloco com autorização própria,
              na ordem P0 → (5358) → A1 → A2 → A3 → A4 → (5359) → N1 → N2.
Data........: 2026-11-08

Forma: blocos autocontidos, um resultado (jsonb ou linha) por bloco. Todos
são READ ONLY com statement_timeout, lock_timeout e
idle_in_transaction_session_timeout, EXCETO o A4 (uma linha no registro de
execuções — status OUTSIDE_WINDOW — e nada mais). Saída sem ids de usuário,
de coleção ou de carta.
================================================================
*/

-- P0 [GATE, antes da 5358] nomes livres e dependências (catálogo)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select jsonb_build_object(
  'tabelas_livres', to_regclass('public.collection_completion_capture_run') is null
                    and to_regclass('public.collection_completion_snapshot') is null
                    and to_regclass('public.collection_completion_coverage') is null,
  'funcoes_livres', to_regprocedure('internal.capture_collection_completion(boolean)') is null
                    and to_regprocedure('public.get_my_collection_completion_history(uuid)') is null,
  'job_livre', not exists (select 1 from cron.job where jobname = 'collection-completion-daily-capture'),
  'pg_cron', exists (select 1 from pg_extension where extname = 'pg_cron'),
  'schema_internal_sem_uso_cliente', not has_schema_privilege('authenticated', 'internal', 'usage')
                                     and not has_schema_privilege('anon', 'internal', 'usage'),
  'r5188_assinatura', coalesce(pg_get_function_result(to_regprocedure('public.collection_completion_summary(uuid)'))
                      = 'TABLE(collection_id uuid, completion_policy text, total_positions bigint, satisfied_positions bigint, missing_positions bigint, progress_percentage numeric, is_complete boolean)', false),
  -- Configurações exatas que auth.uid() lê hoje (a 5358 grava o titular nas duas;
  -- GATE: ao menos uma presente e nenhuma outra fonte de identidade).
  'auth_uid_le_claim_sub', coalesce(position('request.jwt.claim.sub' in pg_get_functiondef(to_regprocedure('auth.uid()'))) > 0, false),
  'auth_uid_le_claims', coalesce(position('''request.jwt.claims''' in pg_get_functiondef(to_regprocedure('auth.uid()'))) > 0, false),
  'auth_uid_definicao', regexp_replace(coalesce(pg_get_functiondef(to_regprocedure('auth.uid()')), ''), '\s+', ' ', 'g'),
  'fuso_existe', exists (select 1 from pg_timezone_names where name = 'America/Sao_Paulo'),
  'colecoes_alvo', (select count(*) from public.collection col
                    join public.collection_reference cr on cr.collection_id = col.id
                    join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
                    where col.mode = 'REFERENCE_BASED' and col.completion_policy in ('STANDARD_SET', 'MASTER_SET'))
) as resultado_p0;
rollback;

-- A1 [GATE, logo após a 5358] definição, RLS e privilégios efetivos (catálogo)
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with t(nome) as (values ('public.collection_completion_capture_run'), ('public.collection_completion_snapshot'), ('public.collection_completion_coverage')),
papeis(r) as (values ('anon'), ('authenticated'), ('service_role')),
cap as (select to_regprocedure('internal.capture_collection_completion(boolean)') as oid),
rd  as (select to_regprocedure('public.get_my_collection_completion_history(uuid)') as oid)
select jsonb_build_object(
  'tabelas_com_rls', (select bool_and(c.relrowsecurity) from t join pg_class c on c.oid = to_regclass(t.nome)),
  'tabelas_sem_politica', not exists (select 1 from pg_policy p join t on p.polrelid = to_regclass(t.nome)),
  'tabelas_sem_privilegio_cliente', not exists (
      select 1 from t cross join papeis p
      where has_table_privilege(p.r, t.nome, 'select') or has_table_privilege(p.r, t.nome, 'insert')
         or has_table_privilege(p.r, t.nome, 'update') or has_table_privilege(p.r, t.nome, 'delete')),
  'captura_existe_definer', coalesce((select prosecdef and proconfig = array['search_path=""'] from pg_proc where oid = (select oid from cap)), false),
  'captura_sem_execute_cliente', (select oid from cap) is not null and not exists (
      select 1 from papeis p where has_function_privilege(p.r, (select oid from cap), 'execute')),
  'captura_sem_public', (select oid from cap) is not null and not exists (
      select 1 from pg_proc pr cross join lateral aclexplode(coalesce(pr.proacl, acldefault('f', pr.proowner))) a
      where pr.oid = (select oid from cap) and a.grantee = 0),
  'leitura_definer_stable', coalesce((select prosecdef and provolatile = 's' and proconfig = array['search_path=""'] from pg_proc where oid = (select oid from rd)), false),
  'leitura_acl', (select string_agg(coalesce(nullif(a.grantee, 0)::regrole::text, 'PUBLIC') || ':' || a.privilege_type, ', ' order by 1)
                  from pg_proc pr cross join lateral aclexplode(coalesce(pr.proacl, acldefault('f', pr.proowner))) a
                  where pr.oid = (select oid from rd)),
  'leitura_anon_sem_execute', (select oid from rd) is not null and not has_function_privilege('anon', (select oid from rd), 'execute'),
  'nada_gravado_ainda', (select count(*) from public.collection_completion_snapshot) = 0
                        and (select count(*) from public.collection_completion_coverage) = 0
) as resultado_a1;
-- PASS: todos true; leitura_acl = "authenticated:EXECUTE, postgres:EXECUTE".
rollback;

-- A2 [GATE] percurso completo SEM escrita (identidade + 5188 + conferências) e desempenho
-- READ ONLY imposto pelo servidor: qualquer escrita acidental falharia (25006).
-- A rotina confere auth.uid() = titular antes da 5188 (R2F_IDENTITY_MISMATCH) e
-- exige da 5188 uma linha da própria coleção (R2F_SUMMARY_MISMATCH): failed = 0 com
-- processed = alvo prova que a identidade gravada é a que auth.uid() e a 5188 aceitam.
begin transaction isolation level repeatable read read only;
set local statement_timeout = '60s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with r as (select internal.capture_collection_completion(true) as j),
alvo as (select count(*) as n from public.collection col
         join public.collection_reference cr on cr.collection_id = col.id
         join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
         where col.mode = 'REFERENCE_BASED' and col.completion_policy in ('STANDARD_SET', 'MASTER_SET'))
select r.j as resultado_a2,
       jsonb_build_object(
         'alvo', alvo.n,
         'alcancou_todas', (r.j->>'expected')::int = alvo.n and (r.j->>'processed')::int = alvo.n and alvo.n > 0,
         'sem_falha', (r.j->>'failed')::int = 0 and (r.j->>'late')::int = 0 and (r.j->>'skipped')::int = 0,
         'nada_gravado', (r.j->>'written')::int = 0,
         'identidade_limpa', (r.j->>'identity_clear')::boolean
                             and coalesce(current_setting('request.jwt.claims', true), '') = ''
                             and coalesce(current_setting('request.jwt.claim.sub', true), '') = '',
         'pass', r.j->>'status' = 'COMPLETED' and (r.j->>'processed')::int = alvo.n and alvo.n > 0
                 and (r.j->>'failed')::int = 0 and (r.j->>'written')::int = 0 and (r.j->>'identity_clear')::boolean) as conferencia_a2
from r, alvo;
-- PASS: conferencia_a2.pass true; "ms" do resultado registra o custo.
rollback;

-- A3 [GATE] acesso de clientes (negativos) e leitura do titular
-- Identidade simulada nas DUAS configurações lidas por auth.uid() (mesma técnica da 5358).
-- Cada caso só conta se alcançar a condição pretendida (ex.: "outro titular" exige uma
-- coleção existente que não seja do usuário simulado; "titular" exige ler a própria).
begin transaction isolation level repeatable read read only;
set local statement_timeout = '10s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
do $a3$
declare
  st text; r jsonb := '{}'::jsonb; v_col uuid; v_owner uuid; v_stranger uuid := gen_random_uuid();
  m_other text; m_none text; v_doc jsonb;
begin
  -- Coleção-alvo real (Set/Master) e seu titular, escolhidos aqui dentro (nunca exibidos).
  select col.id, col.owner_user_id into v_col, v_owner
  from public.collection col
  join public.collection_reference cr on cr.collection_id = col.id
  join public.collection_card_set_reference ccsr on ccsr.collection_reference_id = cr.id
  where col.mode = 'REFERENCE_BASED' and col.completion_policy in ('STANDARD_SET', 'MASTER_SET')
  order by col.id limit 1;
  r := r || jsonb_build_object('alvo_encontrado', v_col is not null and v_owner is not null and v_owner <> v_stranger);

  -- 1) anon sem EXECUTE → 42501
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  begin perform public.get_my_collection_completion_history(gen_random_uuid()); st := 'EXECUTOU'; exception when others then st := sqlstate; end;
  reset role;
  r := r || jsonb_build_object('anon_leitura', st);

  -- 2) authenticated sem identidade → 28000 (as duas configurações vazias)
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  set local role authenticated;
  r := r || jsonb_build_object('sem_identidade_uid_nulo', auth.uid() is null);
  begin perform public.get_my_collection_completion_history(gen_random_uuid()); st := 'EXECUTOU'; exception when others then st := sqlstate; end;
  reset role;
  r := r || jsonb_build_object('sem_sub', st);

  -- 3) usuário autenticado que não é titular de nada (uuid aleatório) — nas duas configurações
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_stranger, 'role', 'authenticated')::text, true);
  set local role authenticated;
  r := r || jsonb_build_object('estranho_uid_ok', auth.uid() is not distinct from v_stranger);
  begin perform public.get_my_collection_completion_history(null); st := 'EXECUTOU'; exception when others then st := sqlstate; end;
  r := r || jsonb_build_object('colecao_nula', st);
  begin perform public.get_my_collection_completion_history(gen_random_uuid()); st := 'EXECUTOU'; exception when others then st := sqlstate; m_none := sqlerrm; end;
  r := r || jsonb_build_object('inexistente', st);
  if v_col is not null then
    begin perform public.get_my_collection_completion_history(v_col); st := 'EXECUTOU'; exception when others then st := sqlstate; m_other := sqlerrm; end;
  else
    st := 'NAO_EXECUTADO';
  end if;
  r := r || jsonb_build_object('de_outro_titular', st, 'mesma_mensagem', m_other is not null and m_other is not distinct from m_none);
  begin perform 1 from public.collection_completion_snapshot limit 1; st := 'LEU'; exception when others then st := sqlstate; end;
  r := r || jsonb_build_object('tabela_fotografias', st);
  begin perform 1 from public.collection_completion_coverage limit 1; st := 'LEU'; exception when others then st := sqlstate; end;
  r := r || jsonb_build_object('tabela_cobertura', st);
  begin perform 1 from public.collection_completion_capture_run limit 1; st := 'LEU'; exception when others then st := sqlstate; end;
  r := r || jsonb_build_object('tabela_execucoes', st);
  begin perform internal.capture_collection_completion(true); st := 'EXECUTOU'; exception when others then st := sqlstate; end;
  r := r || jsonb_build_object('rotina_interna', st);
  reset role;

  -- 4) titular lê a própria coleção → objeto com as chaves do contrato
  if v_col is not null then
    perform set_config('request.jwt.claim.sub', v_owner::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      v_doc := public.get_my_collection_completion_history(v_col);
      st := case when v_doc ? 'tracking_since' and v_doc ? 'last_covered_day'
                      and jsonb_typeof(v_doc->'coverage') = 'array' and jsonb_typeof(v_doc->'snapshots') = 'array'
                 then 'OK' else 'FORMATO' end;
    exception when others then st := sqlstate; end;
    reset role;
  else
    st := 'NAO_EXECUTADO';
  end if;
  r := r || jsonb_build_object('titular_leitura', st);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  perform set_config('mmkyu.a3', (r || jsonb_build_object('pass',
      (r->>'alvo_encontrado')::boolean
      and r->>'anon_leitura' = '42501'
      and (r->>'sem_identidade_uid_nulo')::boolean and r->>'sem_sub' = '28000'
      and (r->>'estranho_uid_ok')::boolean and r->>'colecao_nula' = '22023'
      and r->>'inexistente' = 'P0002' and r->>'de_outro_titular' = 'P0002' and (r->>'mesma_mensagem')::boolean
      and r->>'tabela_fotografias' = '42501' and r->>'tabela_cobertura' = '42501' and r->>'tabela_execucoes' = '42501'
      and r->>'rotina_interna' = '42501'
      and r->>'titular_leitura' = 'OK'))::text, true);
end $a3$;
select current_setting('mmkyu.a3')::jsonb as resultado_a3;
rollback;

-- A4 [GATE, ESCREVE UMA LINHA OPERACIONAL — autorização própria] trava de horário
-- Executar durante o dia (fora de 00h00–03h00 de Brasília). Esperado: status
-- OUTSIDE_WINDOW, nenhuma fotografia e nenhuma cobertura gravadas.
select internal.capture_collection_completion() as resultado_a4,
       (select count(*) from public.collection_completion_snapshot) = 0 as sem_fotografia,
       (select count(*) from public.collection_completion_coverage) = 0 as sem_cobertura;

-- N1 [GATE, manhã seguinte ao primeiro fechamento — somente leitura] primeiro fechamento
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
with ultima as (
  select * from public.collection_completion_capture_run
  where status not in ('OUTSIDE_WINDOW', 'SKIPPED_CONCURRENT')
  order by started_at desc limit 1)
select jsonb_build_object(
  'status', u.status,
  'dia_referencia', u.reference_day,
  'lido_em_brasilia', (u.started_at at time zone 'America/Sao_Paulo'),
  'dentro_da_janela', (u.started_at at time zone 'America/Sao_Paulo')::time < time '03:00'
                      and (u.started_at at time zone 'America/Sao_Paulo')::date = u.reference_day + 1,
  'esperadas', u.expected_count, 'processadas', u.processed_count, 'gravadas', u.written_count, 'falhas', u.failed_count,
  'fora_da_janela', u.late_count,
  'balanco', u.expected_count = u.processed_count + u.skipped_count + u.failed_count + u.late_count,
  'ms', round(extract(epoch from (u.finished_at - u.started_at)) * 1000),
  'cobertura_um_dia_por_colecao', (select count(*) = u.processed_count and bool_and(k.covered_from = u.reference_day and k.covered_to = u.reference_day)
                                   from public.collection_completion_coverage k),
  'uma_fotografia_inicial_por_colecao', (select count(*) = u.processed_count and bool_and(l.opens_coverage and l.reference_day = u.reference_day)
                                         from public.collection_completion_snapshot l),
  'fotografias_coerentes', not exists (select 1 from public.collection_completion_snapshot l
                                       where (l.completion_policy = 'MASTER_SET') <> (l.finish_type_ids is not null))
) as resultado_n1
from ultima u;
-- PASS: status COMPLETED, dentro_da_janela true, falhas 0, fora_da_janela 0, processadas = esperadas, balanco true, demais true.
rollback;

-- N2 [GATE, manhã do segundo fechamento — somente leitura] continuidade e mudança
begin transaction isolation level repeatable read read only;
set local statement_timeout = '5s'; set local lock_timeout = '2s'; set local idle_in_transaction_session_timeout = '30s';
select jsonb_build_object(
  'execucoes_validas', (select count(*) from public.collection_completion_capture_run where status in ('COMPLETED', 'PARTIAL')),
  'intervalos_por_colecao_max', (select max(n) from (select count(*) n from public.collection_completion_coverage group by collection_id) z),
  'cobertura_estendida', (select bool_and(k.covered_to = k.covered_from + 1) from public.collection_completion_coverage k),
  'fotografias_novas_sem_abrir_intervalo', (select count(*) from public.collection_completion_snapshot where not opens_coverage),
  'um_fechamento_por_dia', not exists (select 1 from public.collection_completion_snapshot group by collection_id, reference_day having count(*) > 1)
) as resultado_n2;
-- PASS: intervalos_por_colecao_max 1, cobertura_estendida true, um_fechamento_por_dia true;
-- fotografias_novas_sem_abrir_intervalo = coleções que mudaram no dia (informativo).
rollback;
