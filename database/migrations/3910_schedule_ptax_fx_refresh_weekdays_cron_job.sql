-- Query 3910 — Agendamento automático da PTAX via pg_cron + pg_net + Vault
-- Objetivo: habilitar pg_cron e pg_net (caso ainda não estejam habilitados) e criar,
-- de forma idempotente, o único job de Cron responsável por disparar periodicamente
-- a Edge Function de refresh da PTAX (ptax-fx-refresh), via net.http_post assíncrono.
-- URL e apikey nunca aparecem como valor literal aqui — são resolvidos em tempo de
-- execução por nome, a partir do Supabase Vault (vault.decrypted_secrets).
-- Referência: ADR-031 (revisão 1.8), docs/05f-pricing.md (Incremento P13.4).
-- Status: CONFIRMADO EXECUTADO em 2026-08-18.

-- Habilita pg_cron (agendador) e pg_net (chamadas HTTP assíncronas), caso ainda não
-- estejam habilitadas. Padrão oficial de instalação do Supabase.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
GRANT USAGE ON SCHEMA cron TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA cron TO postgres;

CREATE EXTENSION IF NOT EXISTS pg_net;

-- Idempotência: remove somente um job pré-existente com o mesmo nome, sem afetar
-- nenhum outro job já agendado no projeto.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ptax-fx-refresh-weekdays') THEN
    PERFORM cron.unschedule('ptax-fx-refresh-weekdays');
  END IF;
END $$;

-- Job único: segunda a sexta, 22:00 UTC (19:00 America/Sao_Paulo), chamando
-- net.http_post diretamente. URL e apikey resolvidos em tempo de execução via
-- nomes no Supabase Vault — nunca valores literais neste comando.
SELECT cron.schedule(
  'ptax-fx-refresh-weekdays',
  '0 22 * * 1-5',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'ptax_fx_refresh_url'),
      body := '{}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'ptax_fx_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Como validar:
-- select jobid, jobname, schedule, active, command from cron.job where jobname = 'ptax-fx-refresh-weekdays';
-- (confirmar: 1 linha, active = true, schedule = '0 22 * * 1-5', command contém somente
-- nomes de secrets do Vault, nunca valores.)
