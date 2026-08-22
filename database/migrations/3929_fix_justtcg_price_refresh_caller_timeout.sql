-- STATUS: CONFIRMADO EXECUTADO -- aplicada em producao via Supabase MCP em 2026-08-22
-- (Gate de timeout do scheduler P15, pos-R1/R5).
--
-- NOTA DE RASTREABILIDADE (2026-08-22): este arquivo foi reconstruido retroativamente.
-- A migration 3929 ja estava CONFIRMADAMENTE EXECUTADA em producao desde 2026-08-22 (aplicada
-- via ferramenta apply_migration do Supabase MCP), mas o arquivo fisico correspondente nao
-- havia sido criado no repositorio naquele momento -- lacuna de processo identificada na
-- Fase 0 de verificacao de rastreabilidade do gate de deploy/piloto do P15. A criacao deste
-- arquivo agora NAO representa uma nova execucao nem uma nova alteracao de banco: o SQL
-- abaixo reproduz exatamente o corpo ja aplicado, conferido linha a linha contra o texto
-- efetivamente enviado ao Supabase MCP na rodada original. cron.job, a Edge Function e a
-- documentacao normativa nao foram tocados nesta reconstrucao.
--
-- Testada em BEGIN/ROLLBACK antes da aplicacao real (30/0/30 dentro da transacao, 0/30/30
-- apos ROLLBACK, confirmando reversao correta). Introspeccao previa confirmou pg_cron 1.6.4,
-- assinatura de cron.alter_job(job_id, schedule, command, database, username, active) com
-- todos os parametros exceto job_id DEFAULT NULL (NULL = sem alteracao naquele campo),
-- exatamente 30 jobs justtcg-price-refresh-wave-% com timeout_milliseconds := 60000,
-- active=false nos 30, e o job ptax-fx-refresh-weekdays (jobid=1) fora do filtro e nao
-- afetado.
--
-- Contexto: evidencia real registrada nesta sessao de que o caller (pg_net, via
-- net.http_post) desiste em 60000 ms enquanto a Edge Function justtcg-price-refresh tem
-- deadline interno de 110000 ms -- criando uma janela em que o caller timeout ocorre antes
-- do deadline interno, e o job_run_details do pg_cron so registra o enqueue assincrono bem
-- sucedido, nao o resultado HTTP final. Esta migration corrige exclusivamente essa
-- divergencia, elevando o timeout do caller para 150000 ms (> 110000 ms + margem de
-- terminalizacao), sem alterar nada mais.
--
-- Escopo estritamente limitado a: substituir "timeout_milliseconds := 60000" por
-- "timeout_milliseconds := 150000" no command dos 30 jobs cujo jobname corresponde a
-- 'justtcg-price-refresh-wave-%'. Usa cron.alter_job(job_id, command) -- todos os demais
-- parametros (schedule, database, username, active) ficam NULL, preservando exatamente o
-- valor atual de cada um (jobid, jobname, schedule e active=false inalterados). Nao usa
-- cron.schedule()/cron.unschedule() -- nunca recria jobs. Nao toca waveNumber, URL, headers
-- ou Vault. O job ptax-fx-refresh-weekdays (fora do filtro por nome) nunca e alcancado.
--
-- Idempotente com guardas explicitas: se os 30 jobs ja estiverem em 150000 (nenhum em
-- 60000), a migration apenas emite um NOTICE e nao faz nada. Se o estado divergir do
-- esperado (nem 30/0 nem 0/30 nas contagens antigo/novo, ou contagem de jobs != 30), a
-- migration aborta com RAISE EXCEPTION antes de tocar qualquer job -- nunca aplica parcial
-- ou silenciosamente. Pos-condicao validada dentro do proprio bloco (30 com 150000, 0 com
-- 60000, 30 com active=false) tambem aborta com EXCEPTION se nao bater.
--
-- Nenhum job reativado nesta migration -- os 30 jobs JustTCG permanecem active=false,
-- exatamente como estavam contidos desde a auditoria adversarial P15/3927.

DO $$
DECLARE
  v_old_count integer;
  v_new_count_before integer;
  v_total_wave_jobs integer;
  v_after_new_count integer;
  v_after_old_count integer;
  v_active_false_count integer;
  r record;
BEGIN
  SELECT count(*) INTO v_total_wave_jobs
  FROM cron.job WHERE jobname LIKE 'justtcg-price-refresh-wave-%';

  IF v_total_wave_jobs <> 30 THEN
    RAISE EXCEPTION 'GUARD_FAILED_JOB_COUNT: esperado 30 jobs justtcg-price-refresh-wave-%%, encontrado %.', v_total_wave_jobs;
  END IF;

  SELECT count(*) INTO v_old_count
  FROM cron.job
  WHERE jobname LIKE 'justtcg-price-refresh-wave-%'
    AND command LIKE '%timeout_milliseconds := 60000%';

  SELECT count(*) INTO v_new_count_before
  FROM cron.job
  WHERE jobname LIKE 'justtcg-price-refresh-wave-%'
    AND command LIKE '%timeout_milliseconds := 150000%';

  IF v_old_count = 0 AND v_new_count_before = 30 THEN
    RAISE NOTICE 'MIGRATION_ALREADY_APPLIED: os 30 jobs ja estao com timeout_milliseconds := 150000. Nenhuma alteracao necessaria.';
  ELSIF v_old_count = 30 AND v_new_count_before = 0 THEN
    FOR r IN
      SELECT jobid, command
      FROM cron.job
      WHERE jobname LIKE 'justtcg-price-refresh-wave-%'
        AND command LIKE '%timeout_milliseconds := 60000%'
    LOOP
      PERFORM cron.alter_job(
        job_id := r.jobid,
        command := replace(r.command, 'timeout_milliseconds := 60000', 'timeout_milliseconds := 150000')
      );
    END LOOP;

    SELECT count(*) INTO v_after_new_count
    FROM cron.job
    WHERE jobname LIKE 'justtcg-price-refresh-wave-%'
      AND command LIKE '%timeout_milliseconds := 150000%';

    SELECT count(*) INTO v_after_old_count
    FROM cron.job
    WHERE jobname LIKE 'justtcg-price-refresh-wave-%'
      AND command LIKE '%timeout_milliseconds := 60000%';

    SELECT count(*) INTO v_active_false_count
    FROM cron.job
    WHERE jobname LIKE 'justtcg-price-refresh-wave-%'
      AND active = false;

    IF v_after_new_count <> 30 OR v_after_old_count <> 0 OR v_active_false_count <> 30 THEN
      RAISE EXCEPTION 'GUARD_FAILED_POSTCONDITION: new=% old=% active_false=% (esperado 30/0/30).',
        v_after_new_count, v_after_old_count, v_active_false_count;
    END IF;
  ELSE
    RAISE EXCEPTION 'GUARD_FAILED_UNEXPECTED_STATE: old_timeout_count=% new_timeout_count=% (esperado 30/0 ou 0/30).',
      v_old_count, v_new_count_before;
  END IF;
END $$;
