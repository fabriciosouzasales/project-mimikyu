-- Query 3935 -- Agendamento do novo dispatcher por Set (justtcg-price-refresh-set, P15) via
-- pg_cron + pg_net + Vault. Mesmo padrao ja em producao para o refresh diario por onda
-- (Query 3927) e para o PTAX (Query 3910) -- ver ADR-032 e docs/05f-pricing.md.
--
-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao em 2026-08-22 via Supabase MCP
-- (apply_migration, projeto qjfutqujxrbzgrtkpgkg), a pedido explicito de Fabricio, apos o
-- piloto real PRIMARY+ALTERNATE do dispatcher por Set (ME2.5, syncRunId
-- c7ee7a50-9c91-4557-aca8-297eee077334) ter sido concluido com sucesso.
--
-- Escopo estritamente limitado a: 1 job recorrente novo, chamado
-- 'justtcg-price-refresh-set-dispatcher', agenda '*/5 * * * *' (a cada 5 minutos, 24/7 --
-- ao contrario dos 30 jobs de onda, este dispatcher escolhe 1 Set por invocacao via RPC
-- open_pricing_set_refresh_attempt, migration 3933, e por isso nao depende de uma janela
-- fixa noturna), chamando a Edge Function justtcg-price-refresh-set (ja deployada, v1
-- ACTIVE, verify_jwt=false preservado -- ver supabase/functions/justtcg-price-refresh-set/
-- index.ts). Corpo da requisicao vazio ('{}'::jsonb) -- a funcao nao aceita nenhum
-- parametro de negocio, o Set e decidido inteiramente pela RPC do lado do banco.
--
-- Nasce OBRIGATORIAMENTE active=false (cron.schedule() cria jobs active=true por padrao em
-- pg_cron 1.6.4 -- por isso o bloco abaixo captura o jobid retornado e chama
-- cron.alter_job(job_id, active := false) na sequencia, antes de qualquer commit visivel a
-- outras sessoes). Nenhum dos 30 jobs justtcg-price-refresh-wave-% nem o job
-- ptax-fx-refresh-weekdays sao tocados por este arquivo -- filtro exclusivamente por
-- jobname = 'justtcg-price-refresh-set-dispatcher'.
--
-- URL e segredo NUNCA aparecem como valor literal aqui -- resolvidos em tempo de execucao
-- por nome, a partir do Supabase Vault (vault.decrypted_secrets), exatamente como as Queries
-- 3910/3927. O segredo de autenticacao (apikey) REAPROVEITA justtcg_price_refresh_secret --
-- mesmo segredo ja usado pelos 30 jobs de onda, pois a Edge Function justtcg-price-refresh-
-- set reaproveita a mesma variavel de ambiente JUSTTCG_PRICE_REFRESH_SECRET (ver racional em
-- supabase/functions/justtcg-price-refresh-set/index.ts). A URL e nova (endpoint diferente:
-- .../functions/v1/justtcg-price-refresh-set, nao .../justtcg-price-refresh) e foi
-- provisionada nesta mesma rodada, antes desta migration, como um novo segredo dedicado no
-- Vault: justtcg_price_refresh_set_url (via vault.create_secret, mesmo mecanismo ja
-- aprovado -- nenhum valor sensivel novo, apenas a URL publica da funcao ja deployada).
--
-- caller timeout = 150000 ms (igual aos 30 jobs de onda pos-Query 3929) -- a Edge Function
-- justtcg-price-refresh-set reusa o mesmo deadline interno de seguranca de
-- set-refresh-core.ts, entao o caller (pg_net) precisa de margem equivalente para nao
-- desistir antes do deadline interno terminalizar a resposta.
--
-- pg_cron (1.6.4) e pg_net (0.20.4) ja estao habilitadas no projeto -- esta migration NAO
-- repete CREATE EXTENSION (mesma razao ja documentada na Query 3927: reexecutar sobre uma
-- instalacao gerenciada existente e desnecessario e ativamente prejudicial).
--
-- Nao ativa o dispatcher. Ativacao fica para uma janela controlada futura, com autorizacao
-- explicita separada.

DO $$
DECLARE
  v_jobid bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-price-refresh-set-dispatcher') THEN
    PERFORM cron.unschedule('justtcg-price-refresh-set-dispatcher');
  END IF;

  SELECT cron.schedule(
    'justtcg-price-refresh-set-dispatcher',
    '*/5 * * * *',
    $cron$
    select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_set_url'),
        body := '{}'::jsonb,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_price_refresh_secret')
        ),
        timeout_milliseconds := 150000
    ) as request_id;
    $cron$
  ) INTO v_jobid;

  PERFORM cron.alter_job(job_id := v_jobid, active := false);
END $$;

-- Como validar:
-- select jobid, jobname, schedule, active, command from cron.job
--   where jobname = 'justtcg-price-refresh-set-dispatcher';
-- (confirmar: exatamente 1 linha, schedule = '*/5 * * * *', active = false, command
-- contendo somente nomes de secrets do Vault (justtcg_price_refresh_set_url e
-- justtcg_price_refresh_secret) e timeout_milliseconds := 150000 -- nunca URL/apikey em
-- texto literal.)
--
-- select count(*) from cron.job where jobname like 'justtcg-price-refresh-wave-%';
-- select active from cron.job where jobname = 'ptax-fx-refresh-weekdays';
-- (confirmar: 30 jobs de onda inalterados, todos active=false; PTAX inalterado, active=true.)
--
-- Pre-requisito ja cumprido nesta mesma rodada, antes desta migration: provisionar no
-- Supabase Vault (vault.create_secret) o segredo justtcg_price_refresh_set_url -> URL
-- publica da Edge Function justtcg-price-refresh-set. Sem esse secret, o job seria criado
-- normalmente mas cada execucao real falharia ao resolver a URL (net.http_post recebe
-- NULL) -- nunca um erro silencioso: apareceria em net._http_response com status de erro,
-- correlacionavel por request_id.
