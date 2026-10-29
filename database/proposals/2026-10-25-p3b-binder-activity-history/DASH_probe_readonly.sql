/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: DASH_probe_readonly.sql — sonda SOMENTE LEITURA do executor
              "mensagem única" (Supabase Dashboard SQL Editor / execute_sql)
Versão......: 1.0 (2026-10-25, P3-B-S1-LIVE-DASHBOARD-EXECUTOR-READINESS-01)
Status......: PROPOSTA. NÃO EXECUTADA. Exige autorização própria (não autoriza o ensaio).
              README §28.

Objetivo: exercitar, sem gravar nada, o mesmo formato do ensaio v2.1
(T0 → BEGIN → SET TRANSACTION → SET LOCAL → DO com raise P0001 → ROLLBACK → RESET)
e observar no executor real:
  - texto do erro devolvido por inteiro (SQLSTATE, mensagem com JSON, DETAIL, HINT, CONTEXT);
  - todos os comandos na MESMA mensagem (statement_timestamp() = now(); elapsed >= 200 ms);
  - acentos preservados (UTF-8);
  - conexão descartada depois do erro (bloco B, em chamada separada).
Nada é escrito: a transação do bloco A é READ ONLY; o bloco B é um SELECT.

Uso: bloco A como UMA execução; anotar o JSON do erro (pid_a). Depois, bloco B como
outra execução, e conferir que pid_a NÃO aparece em client_pids.
================================================================
*/

-- BLOCO A — uma execução; resultado esperado: ERRO P0001 "MSPROBE {...}" --------------------
set session default_transaction_read_only = on;
begin;
set transaction read only;
set local statement_timeout = '5s';
set local lock_timeout = '1s';
select pg_sleep(0.2);
do $msprobe$
begin
  raise exception 'MSPROBE %', json_build_object(
    'pid_a', pg_backend_pid(),
    'usuario', current_user,
    'transacao_somente_leitura', current_setting('transaction_read_only'),
    'mesma_mensagem', statement_timestamp() = now(),
    'elapsed_ms', round(extract(epoch from clock_timestamp() - statement_timestamp()) * 1000),
    'application_name', current_setting('application_name'),
    'acentos', 'ação-ç-ã-é'
  )::text using errcode = 'P0001', detail = 'MSPROBE_DETAIL', hint = 'MSPROBE_HINT';
end
$msprobe$;
rollback;
reset default_transaction_read_only;

-- BLOCO B — outra execução, logo depois; resultado esperado: 1 linha --------------------------
select pg_backend_pid() as pid_b,
       current_setting('default_transaction_read_only') as default_read_only,
       (select array_agg(pid order by pid) from pg_stat_activity
         where backend_type = 'client backend') as client_pids,
       (select count(*) from pg_stat_activity
         where pid <> pg_backend_pid() and state like 'idle in transaction%') as idle_in_transaction,
       (select count(*) from pg_stat_activity
         where pid <> pg_backend_pid() and query ilike '%MSPROBE%') as sessoes_com_msprobe;
