/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5359 - Agendamento diário da captura da completude (R2-F, B1)
Versão......: 0.1
Status......: EXECUTADA / CANÔNICA. Aplicada no LIVE mimikyu-core em 2026-11-08,
              depois da 5358 e de A1–A4 PASS (ledger 20261108160640). Texto
              aplicado = arquivo integral de database/proposals/
              2026-11-08-r2f-completion-history/
              5359_schedule_collection_completion_capture_PROPOSAL.sql (md5
              e43108650f8438b0e36d62f30cc7540d); este arquivo difere dele só
              neste bloco Status. Job collection-completion-daily-capture ativo,
              '5 3 * * *', usuário postgres; md5 do comando no LIVE
              6b82e8d0501f1ac5f33bc34df381865c (igual ao deste arquivo).
              Primeira execução real (N1) pendente.
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
