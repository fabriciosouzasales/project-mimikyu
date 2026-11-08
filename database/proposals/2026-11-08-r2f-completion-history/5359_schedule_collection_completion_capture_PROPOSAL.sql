/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5359 - Agendamento diário da captura da completude (R2-F, B1)
Versão......: 0.1
Status......: PROPOSTO — NÃO EXECUTADO. Só depois da 5358 aplicada e das
              verificações A1–A4 (5886) em PASS, com autorização própria.
Data........: 2026-11-08

O que faz: agenda internal.capture_collection_completion() (5358) às 03h05
UTC = 00h05 de America/Sao_Paulo (sem horário de verão desde 2019), todos os
dias. O job roda como o papel que o agenda (postgres, dono da rotina).
statement_timeout de 10 min só para o comando do job.

Idempotente: se o job já existir com este nome, é recriado (padrão 3935).
O primeiro fechamento válido é o da primeira execução depois da aplicação
(D2): nada é capturado no momento do agendamento.

Reversão (só com autorização): select cron.unschedule('collection-completion-daily-capture');
================================================================
*/

do $$
begin
  if exists (select 1 from cron.job where jobname = 'collection-completion-daily-capture') then
    perform cron.unschedule('collection-completion-daily-capture');
  end if;
  perform cron.schedule(
    'collection-completion-daily-capture',
    '5 3 * * *',
    $cron$ set statement_timeout = '10min'; select internal.capture_collection_completion(); $cron$
  );
end $$;
