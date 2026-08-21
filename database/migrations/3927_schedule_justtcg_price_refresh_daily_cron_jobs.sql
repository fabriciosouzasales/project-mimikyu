-- Query 3927 -- Agendamento automatico do refresh diario de precos JustTCG via pg_cron +
-- pg_net + Vault. Mesmo padrao real ja em producao para a PTAX (Query 3910,
-- ptax-fx-refresh-weekdays) -- ver ADR-031 e docs/05f-pricing.md.
--
-- STATUS: PROPOSTO -- ainda nao aplicada em producao nesta rodada (Incremento de
-- Atualizacao Diaria JustTCG, item E, 2026-08-21; capacidade elevada de 5 para 10 ondas
-- na rodada de escalabilidade do mesmo dia, e desta para 30 ondas de 10 paginas cada
-- nesta rodada de correcao pos-incidente, 2026-08-21, mesmo dia). Fabricio decide quando
-- aplicar via Supabase MCP, e so depois de provisionar os dois segredos no Vault (ver
-- rodape).
--
-- Contexto do incidente que motivou esta reescrita: o piloto real da onda com
-- WAVE_PAGE_CAP=30 (desenho anterior desta migration, nunca aplicado) disparou o
-- shutdown_reason=WallClockTime do worker da Edge Function aos 150s (HTTP 546), deixando
-- o run 6c2ca781-099d-4087-89bf-4cbd4818341c preso em PROCESSING com zero telemetria
-- (requests_made=0, zero pricing_sync_run_call) -- 2401 pricing_observation e 1
-- pricing_product ja haviam sido persistidos antes do corte. Confirmado via Management
-- API que o Supabase/Mimikyu Labs esta no plano Free (JustTCG, fonte de dados, esta no
-- Starter Plan -- planos distintos, nao confundir). Correcao: WAVE_PAGE_CAP caiu de 30
-- para 10 e MAX_WAVES subiu de 10 para 30 (_shared/pricing-justtcg-refresh/wave-plan.ts),
-- mesmo teto diario de 300 paginas, mais um deadline interno de seguranca de 110s
-- verificado entre Sets (core.ts/deadline.ts) -- nunca deixa um run preso em PROCESSING
-- de novo, mesmo que o worker seja encerrado de forma inesperada.
--
-- Contexto original (decisoes fechadas 2-7 do Incremento): "Execucao diaria, inclusive
-- sabados e domingos"; "Ondas independentes, nunca todas as paginas numa unica Edge
-- Function"; "Cada onda tem teto autoritativo de WAVE_PAGE_CAP requisicoes"; ondas fora
-- do plano do dia retornam NOOP sem criar run. Trinta jobs pg_cron INDEPENDENTES -- nunca
-- um unico job que chama as 30 ondas em sequencia -- cada um dispara UMA chamada HTTP a
-- justtcg-price-refresh (supabase/functions/justtcg-price-refresh), com payload
-- { "waveNumber": N } (N de 1 a 30), em intervalos de 5 minutos, 22:30-00:55 UTC. A
-- propria Edge Function decide, onda a onda, se ha trabalho a fazer (NOOP sem criar
-- pricing_sync_run quando a onda esta fora do plano do dia -- ver core.ts,
-- executePriceRefreshWave). Nenhuma logica de negocio mora nesta migration -- so o
-- agendamento.
--
-- URL e segredo NUNCA aparecem como valor literal aqui -- resolvidos em tempo de execucao
-- por nome, a partir do Supabase Vault (vault.decrypted_secrets), exatamente como a Query
-- 3910. Os 30 jobs compartilham a MESMA url/secret (uma unica Edge Function, um unico
-- segredo dedicado) -- so o corpo da requisicao (waveNumber) muda entre eles.
--
-- pg_cron (1.6.4) e pg_net (0.20.4) ja estao habilitadas no projeto desde a Query 3910
-- (confirmado via pg_extension nesta rodada) -- esta migration NAO repete
-- CREATE EXTENSION/GRANT: reexecutar CREATE EXTENSION IF NOT EXISTS pg_cron sobre uma
-- instalacao ja existente disparou, durante o teste transacional desta migration, o
-- after-create hook interno do Supabase para pg_cron (grants redundantes -> erro 2BP01
-- "dependent privileges exist"). Como as duas extensoes ja estao confirmadamente ativas,
-- reafirma-las aqui e desnecessario e ativamente prejudicial neste ambiente gerenciado --
-- a idempotencia desta migration cobre exclusivamente os 30 jobs (bloco DO abaixo).

-- Idempotencia: remove somente os 30 jobs com os nomes abaixo, se ja existirem, sem afetar
-- nenhum outro job agendado no projeto (inclusive ptax-fx-refresh-weekdays).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-1') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-1');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-2') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-2');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-3') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-3');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-4') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-4');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-5') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-5');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-6') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-6');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-7') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-7');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-8') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-8');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-9') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-9');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-10') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-10');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-11') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-11');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-12') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-12');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-13') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-13');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-14') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-14');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-15') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-15');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-16') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-16');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-17') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-17');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-18') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-18');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-19') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-19');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-20') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-20');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-21') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-21');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-22') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-22');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-23') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-23');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-24') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-24');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-25') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-25');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-26') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-26');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-27') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-27');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-28') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-28');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-29') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-29');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-wave-30') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-wave-30');
  END IF;
END $$;

-- Onda 1 -- todos os dias, 22:30 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-1',
  '30 22 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 1}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 2 -- todos os dias, 22:35 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-2',
  '35 22 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 2}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 3 -- todos os dias, 22:40 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-3',
  '40 22 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 3}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 4 -- todos os dias, 22:45 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-4',
  '45 22 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 4}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 5 -- todos os dias, 22:50 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-5',
  '50 22 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 5}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 6 -- todos os dias, 22:55 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-6',
  '55 22 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 6}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 7 -- todos os dias, 23:00 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-7',
  '0 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 7}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 8 -- todos os dias, 23:05 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-8',
  '5 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 8}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 9 -- todos os dias, 23:10 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-9',
  '10 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 9}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 10 -- todos os dias, 23:15 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-10',
  '15 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 10}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 11 -- todos os dias, 23:20 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-11',
  '20 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 11}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 12 -- todos os dias, 23:25 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-12',
  '25 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 12}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 13 -- todos os dias, 23:30 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-13',
  '30 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 13}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 14 -- todos os dias, 23:35 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-14',
  '35 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 14}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 15 -- todos os dias, 23:40 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-15',
  '40 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 15}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 16 -- todos os dias, 23:45 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-16',
  '45 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 16}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 17 -- todos os dias, 23:50 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-17',
  '50 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 17}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 18 -- todos os dias, 23:55 UTC.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-18',
  '55 23 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 18}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 19 -- todos os dias, 00:00 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-19',
  '0 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 19}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 20 -- todos os dias, 00:05 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-20',
  '5 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 20}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 21 -- todos os dias, 00:10 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-21',
  '10 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 21}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 22 -- todos os dias, 00:15 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-22',
  '15 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 22}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 23 -- todos os dias, 00:20 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-23',
  '20 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 23}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 24 -- todos os dias, 00:25 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-24',
  '25 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 24}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 25 -- todos os dias, 00:30 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-25',
  '30 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 25}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 26 -- todos os dias, 00:35 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-26',
  '35 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 26}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 27 -- todos os dias, 00:40 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-27',
  '40 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 27}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 28 -- todos os dias, 00:45 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-28',
  '45 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 28}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 29 -- todos os dias, 00:50 UTC (dia seguinte).
SELECT cron.schedule(
  'justtcg-price-refresh-wave-29',
  '50 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 29}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Onda 30 -- todos os dias, 00:55 UTC (dia seguinte). Com o catalogo atual (regra 6) as
-- ondas fora do plano do dia sempre retornam NOOP_WAVE_NOT_IN_PLAN (sem criar
-- pricing_sync_run) -- as ondas de teto (as que excedem o plano do dia) existem para
-- absorver crescimento futuro do catalogo sem exigir uma nova migration de Cron.
SELECT cron.schedule(
  'justtcg-price-refresh-wave-30',
  '55 0 * * *',
  $cron$
  select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_url'),
      body := '{"waveNumber": 30}'::jsonb,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
      ),
      timeout_milliseconds := 60000
  ) as request_id;
  $cron$
);

-- Como validar:
-- select jobid, jobname, schedule, active, command from cron.job
--   where jobname like 'justtcg-price-refresh-wave-%' order by
--   (regexp_match(jobname, '(\d+)$'))[1]::int;
-- (confirmar: 30 linhas, active = true, schedules em intervalos de 5 minutos de
-- '30 22 * * *' a '55 0 * * *' (22:30-00:55 UTC), cada command contendo somente nomes de
-- secrets do Vault e o waveNumber correspondente no body -- nunca URL/apikey em texto
-- literal.)
--
-- Pre-requisito antes de aplicar esta migration em producao: provisionar no Supabase Vault
-- (vault.create_secret) os dois segredos abaixo, com os nomes exatos usados acima:
--   justtcg_price_refresh_url    -> URL publica da Edge Function justtcg-price-refresh
--   justtcg_price_refresh_secret -> mesmo valor configurado como Function Secret
--                                   JUSTTCG_PRICE_REFRESH_SECRET (supabase secrets set)
-- Sem os dois secrets no Vault, os 30 jobs sao criados normalmente mas cada execucao real
-- falha ao resolver url/apikey (net.http_post recebe NULL) -- nunca um erro silencioso:
-- aparece em net._http_response com status de erro, correlacionavel por request_id.
