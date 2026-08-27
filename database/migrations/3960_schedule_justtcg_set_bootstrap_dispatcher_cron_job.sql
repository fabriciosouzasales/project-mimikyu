-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao em 2026-08-26 via Supabase MCP.
-- P16.5.6, aprovado por Fabricio em 2026-08-26 apos a prova end-to-end real do bootstrap +
-- PRICE_REFRESH automatico do SWSH8 (P16.5.4/P16.5.5): bootstrap COMPLETE, 284/284 mappings
-- CONFIRMED, 284 identities, captura automatica pelo dispatcher de PRICE_REFRESH ja em
-- producao, 2.022 pricing_product/pricing_observation, 284/284 cartas com preco, valuation
-- R$ 11.934,96, Saude 46/46 consistente nas 4 telas administrativas. Secret
-- justtcg_set_bootstrap_url provisionado no Vault e job jobid=205 ativado (active=true) em
-- rodada controlada subsequente, com 3 ticks reais succeeded/HTTP 200/NO_WORK validados,
-- zero CARD_SYNC sem candidato, price dispatcher (jobid 202) intacto -- ver docs/05f-pricing.md
-- e ADR-032 para o fechamento completo.
--
-- Objetivo -- fechar o ultimo elo manual do fluxo de onboarding de Sets: agendar
-- automaticamente a Edge Function justtcg-set-bootstrap (P16.5.4), ate aqui disparada apenas
-- por 2 chamadas manuais controladas via net.http_post ad-hoc (nunca por cron). Mesmo padrao
-- pg_cron + pg_net + Vault ja em producao para o dispatcher irmao de PRICE_REFRESH (Query
-- 3935) -- ver ADR-032 e docs/05f-pricing.md.
--
-- Escopo estritamente limitado a: 1 job recorrente novo, chamado
-- 'justtcg-set-bootstrap-dispatcher', chamando a Edge Function justtcg-set-bootstrap (ja
-- deployada, verify_jwt=false, autorizacao via header apikey -- ver
-- supabase/functions/justtcg-set-bootstrap/auth.ts). Corpo da requisicao vazio ('{}'::jsonb)
-- -- a funcao nao aceita nenhum parametro de negocio; o Set (se houver algum com
-- pricing_set_bootstrap_state.status IN ('PENDING','ACQUIRING','MATCHING')) e decidido
-- inteiramente pela RPC open_pricing_set_bootstrap_attempt (migration 3955) do lado do banco
-- -- mesma disciplina "1 Set por invocacao, decisao 100% no banco" do dispatcher de
-- PRICE_REFRESH. NO_CANDIDATE (nenhum Set pendente) e SOURCE_BUSY (CARD_SYNC ou PRICE_REFRESH
-- ja ativo para a fonte) sao outcomes HTTP 200/409 normais desta funcao (ver handler.ts) --
-- nunca tratados como falha por este job.
--
-- Nenhuma mudanca no nucleo do bootstrap (_shared/pricing-justtcg-bootstrap/*), nenhuma
-- mudanca no dispatcher de PRICE_REFRESH (Edge Function justtcg-price-refresh-set nem seu
-- job 'justtcg-price-refresh-set-dispatcher', jobid 202) e nenhuma nova logica de matching --
-- esta migration e puramente uma amarracao de agendamento sobre uma Edge Function ja
-- existente e ja testada em producao real (P16.5.4).
--
-- Serializacao CARD_SYNC x PRICE_REFRESH -- ja garantida estruturalmente pela migration 3926
-- (indice unico parcial ux_pricing_sync_run_mutual_excl_card_sync_price_refresh, chaveado por
-- pricing_source_id, WHERE status IN ('RECEIVED','PROCESSING') AND run_type IN ('CARD_SYNC',
-- 'PRICE_REFRESH')). Essa garantia independe de agendamento: mesmo que os dois dispatchers
-- disparem no mesmo instante, o INSERT que chegar depois em pricing_sync_run sempre recebe
-- 23505 (unique_violation), que ambas as RPCs (open_pricing_set_bootstrap_attempt,
-- open_pricing_set_refresh_attempt) ja tratam retornando SOURCE_BUSY -- nenhuma alteracao
-- necessaria nem feita aqui.
--
-- Offset de horario -- escolhido apenas para reduzir contencao operacional/ruido de log (nao
-- para garantir correcao, que ja vem da 3926): dispatcher de PRICE_REFRESH roda em
-- '*/5 * * * *' (minutos 0,5,10,...,55); este novo job roda em '2-59/5 * * * *' (minutos
-- 2,7,12,...,57) -- sempre 2 minutos de defasagem, nunca no mesmo tick, mesma cadencia de 5
-- em 5 minutos. Cadencia igual (nao mais lenta) porque justtcg-set-bootstrap tambem processa
-- em paginas por invocacao (mesma disciplina de retomada sem estado em memoria do dispatcher
-- de Set, provada em P16.5.2/P16.5.3) -- um Set em ACQUIRING precisa de varias invocacoes
-- sucessivas para terminar a paginacao, entao um intervalo maior so alongaria
-- desnecessariamente o tempo de onboarding de um Set novo sem nenhum ganho de seguranca.
--
-- Nasce OBRIGATORIAMENTE active=false (cron.schedule() cria jobs active=true por padrao em
-- pg_cron 1.6.4 -- por isso o bloco abaixo captura o jobid retornado e chama
-- cron.alter_job(job_id, active := false) na sequencia, antes de qualquer commit visivel a
-- outras sessoes, mesmo padrao da Query 3935). Nenhum job existente (dispatcher de
-- PRICE_REFRESH, 30 jobs de onda, ptax-fx-refresh-weekdays) e tocado por este arquivo --
-- filtro exclusivamente por jobname = 'justtcg-set-bootstrap-dispatcher'.
--
-- URL e segredo NUNCA aparecem como valor literal aqui -- resolvidos em tempo de execucao por
-- nome, a partir do Supabase Vault (vault.decrypted_secrets), exatamente como as Queries
-- 3910/3927/3935. O segredo de autenticacao (apikey) REAPROVEITA justtcg_price_refresh_secret
-- -- mesmo segredo ja usado pelo dispatcher de PRICE_REFRESH e pelos 30 jobs de onda, pois a
-- Edge Function justtcg-set-bootstrap reaproveita a mesma variavel de ambiente
-- JUSTTCG_PRICE_REFRESH_SECRET (ver racional em supabase/functions/justtcg-set-bootstrap/
-- index.ts). A URL e nova (endpoint diferente: .../functions/v1/justtcg-set-bootstrap) e
-- PRECISA ser provisionada no Supabase Vault (via vault.create_secret) como
-- justtcg_set_bootstrap_url ANTES da aplicacao real desta migration -- ver "Pre-requisito" ao
-- final. Ainda NAO existe (confirmado via select name from vault.secrets nesta rodada) --
-- diferente da Query 3935, cujo secret ja havia sido provisionado antes da aplicacao.
--
-- caller timeout = 150000 ms -- igual ao dispatcher de PRICE_REFRESH e aos 30 jobs de onda; a
-- Edge Function justtcg-set-bootstrap reusa o mesmo deadline interno de seguranca de
-- deadline.ts (_shared/pricing-justtcg-refresh, WAVE_INTERNAL_DEADLINE_MS = 110_000), entao o
-- caller (pg_net) precisa de margem equivalente para nao desistir antes do deadline interno
-- terminalizar a resposta.
--
-- pg_cron (1.6.4) e pg_net (0.20.4) ja estao habilitadas no projeto -- esta migration NAO
-- repete CREATE EXTENSION.
--
-- Nasce active=false por desenho (ver acima). Ativacao ocorreu em rodada controlada separada,
-- posterior a esta aplicacao, com autorizacao explicita de Fabrício -- mesmo padrao ja seguido
-- pela Query 3935. Job jobid=205 confirmado active=true, 3 ticks reais validados (ver STATUS
-- no topo deste arquivo).

DO $$
DECLARE
  v_jobid bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'justtcg-set-bootstrap-dispatcher') THEN
    PERFORM cron.unschedule('justtcg-set-bootstrap-dispatcher');
  END IF;

  SELECT cron.schedule(
    'justtcg-set-bootstrap-dispatcher',
    '2-59/5 * * * *',
    $cron$
    select net.http_post(
        url := (select decrypted_secret from vault.decrypted_secrets where name = 'justtcg_set_bootstrap_url'),
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
--   where jobname = 'justtcg-set-bootstrap-dispatcher';
-- (confirmar: exatamente 1 linha, schedule = '2-59/5 * * * *', active = false, command
-- contendo somente nomes de secrets do Vault (justtcg_set_bootstrap_url e
-- justtcg_price_refresh_secret) e timeout_milliseconds := 150000 -- nunca URL/apikey em
-- texto literal.)
--
-- select jobid, jobname, schedule, active from cron.job
--   where jobname = 'justtcg-price-refresh-set-dispatcher';
-- (confirmar: jobid 202 inalterado, schedule = '*/5 * * * *', active = true.)
--
-- select count(*), count(*) filter (where active) from cron.job
--   where jobname like 'justtcg-price-refresh-wave-%';
-- (confirmar: 30 jobs de onda inalterados, todos active=false.)
--
-- Pre-requisito OBRIGATORIO antes da aplicacao real -- CUMPRIDO nesta rodada: secret
-- justtcg_set_bootstrap_url provisionado no Supabase Vault (vault.create_secret) apontando
-- para a URL publica da Edge Function ja deployada
-- (https://qjfutqujxrbzgrtkpgkg.supabase.co/functions/v1/justtcg-set-bootstrap), ANTES da
-- aplicacao desta migration.
