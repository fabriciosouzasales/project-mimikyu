/*
================================================================
Projeto.....: Project Mimikyu
Arquivo.....: DIAG_sessions_readonly.sql — diagnóstico SOMENTE LEITURA das sessões
              contadas pelo G-PRE P.04 (gate v1.1)
Versão......: 1.0 (2026-10-26, P3-B S1 SESSION DIAGNOSTIC READONLY)
Status......: PROPOSTA. NÃO EXECUTADA. Exige autorização operacional específica.
              Não altera o gate v1.1. README §28.17.

Um único SELECT sobre pg_stat_activity. Não lê query, client_addr, client_hostname
nem nenhuma tabela de dados. Uma linha por sessão cliente; a coluna conta_no_p04
aplica, sem alteração, o predicado do P.04:
  pid <> pg_backend_pid() and backend_type = 'client backend'
  and state is not null and state <> 'idle'
As colunas total_p04 e total_clientes repetem-se em todas as linhas (mesmo snapshot
de pg_stat_activity, logo comparáveis entre si).
================================================================
*/
with a as (
  select pid, usename, application_name, backend_type, state,
         wait_event_type, wait_event,
         backend_start, xact_start, query_start, state_change
  from pg_stat_activity
  where backend_type = 'client backend'
)
select a.pid,
       a.pid = pg_backend_pid() as e_o_proprio_diagnostico,
       (a.pid <> pg_backend_pid() and a.backend_type = 'client backend'
        and a.state is not null and a.state <> 'idle') as conta_no_p04,
       a.usename as papel,
       a.application_name,
       a.backend_type,
       a.state,
       a.wait_event_type,
       a.wait_event,
       date_trunc('second', now() - a.backend_start) as idade_da_sessao,
       date_trunc('second', now() - a.xact_start) as idade_da_transacao,
       date_trunc('second', now() - a.query_start) as desde_inicio_do_comando,
       date_trunc('second', now() - a.state_change) as desde_mudanca_de_estado,
       count(*) filter (where a.pid <> pg_backend_pid() and a.backend_type = 'client backend'
                        and a.state is not null and a.state <> 'idle') over () as total_p04,
       count(*) over () as total_clientes,
       now() as lido_em
from a
order by conta_no_p04 desc, e_o_proprio_diagnostico desc, a.application_name, a.pid;
