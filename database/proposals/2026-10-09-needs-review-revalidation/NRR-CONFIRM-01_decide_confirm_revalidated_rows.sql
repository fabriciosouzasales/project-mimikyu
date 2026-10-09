-- =============================================================================
-- NRR-CONFIRM-01 — Decidir (APPROVED) e confirmar as linhas promovidas pela
--                  reavaliação NEEDS-REVIEW-REVALIDATION-01 (run 39390676…)
-- -----------------------------------------------------------------------------
-- Usa SOMENTE contratos LIVE:
--   public.admin_decide_catalog_variant_import_row(UUID[], TEXT)   (2144)
--   public.admin_confirm_catalog_variant_import(UUID, UUID[])      (2145 → 2218)
-- Nenhum objeto novo. Mesmo protocolo da BULK-STP-01 / Classe A:
--   * pertencimento = jobs auditados pelo run_id da reavaliação (59 jobs);
--   * universo por job = VALID / PENDING / PENDING (conjunto A);
--   * A>0 e B (VALID/APPROVED/PENDING) >0 no mesmo job ⇒ STOP RESUME_PARTIAL;
--   * p_row_ids SEMPRE explícito; delta medido por leitura, não pelos contadores;
--   * qualquer FAILED ⇒ STOP (o DO inteiro é desfeito).
-- Ator: o administrador real, via request.jwt.claims LOCAL à transação
-- (set_config(..., true)); limpo ao final. is_admin()/auth.uid() funcionam
-- exatamente como na chamada pela aplicação.
--
-- Parâmetros (editar no texto colado, nunca no arquivo):
--   c_mode     'CANARY' (1 job, o menor) | 'FULL' (todos os restantes)
--   c_expected total de linhas A esperado no escopo do modo
-- =============================================================================
DO $nrr$
DECLARE
    c_mode      CONSTANT TEXT := 'CANARY';
    c_run_id    CONSTANT TEXT := '39390676-f033-4000-a0e6-dc1a103f5921';
    c_expected  CONSTANT INTEGER := NULL;   -- obrigatório: preencher antes de rodar
    v_admin     UUID;
    v_job       RECORD;
    v_a         UUID[];
    v_b         INTEGER;
    v_n         INTEGER;
    v_ins       INTEGER;
    v_unc       INTEGER;
    v_fail      INTEGER;
    v_cv0       INTEGER;
    v_cv1       INTEGER;
    v_tot_a     INTEGER := 0;
    v_tot_ins   INTEGER := 0;
    v_tot_unc   INTEGER := 0;
    v_jobs      INTEGER := 0;
    v_scope     INTEGER;
    v_report    JSONB := '[]'::jsonb;
BEGIN
    IF c_expected IS NULL THEN RAISE EXCEPTION 'NRR_CONFIRM_EXPECTED_REQUIRED'; END IF;
    SELECT id INTO v_admin FROM public.admin_user;
    IF (SELECT count(*) FROM public.admin_user) <> 1 THEN
        RAISE EXCEPTION 'NRR_CONFIRM_ADMIN_AMBIGUOUS: esperado exatamente 1 admin_user.';
    END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'NRR_CONFIRM_NOT_ADMIN_CONTEXT'; END IF;

    IF EXISTS (SELECT 1 FROM public.catalog_variant_import_row WHERE persistence_status = 'FAILED') THEN
        RAISE EXCEPTION 'NRR_CONFIRM_PRE_FAILED_PRESENT';
    END IF;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;

    -- Escopo do modo
    CREATE TEMP TABLE nrr_scope ON COMMIT DROP AS
    SELECT j.id AS job_id, cs.code AS set_code,
           count(*) FILTER (WHERE r.validation_status='VALID' AND r.decision_status='PENDING' AND r.persistence_status='PENDING') AS a_n
      FROM public.catalog_variant_import_job j
      JOIN public.card_set cs ON cs.id = j.card_set_id
      JOIN public.catalog_variant_import_row r ON r.job_id = j.id
     WHERE j.id IN (SELECT entity_id FROM public.catalog_admin_action_log
                     WHERE action = 'CARD_VARIANT_IMPORT_ROWS_REVALIDATED' AND metadata->>'run_id' = c_run_id)
       AND j.status = 'STAGED'
     GROUP BY 1, 2
    HAVING count(*) FILTER (WHERE r.validation_status='VALID' AND r.decision_status='PENDING' AND r.persistence_status='PENDING') > 0;

    IF c_mode = 'CANARY' THEN
        DELETE FROM nrr_scope WHERE job_id NOT IN (SELECT job_id FROM nrr_scope ORDER BY a_n, set_code LIMIT 1);
    ELSIF c_mode <> 'FULL' THEN
        RAISE EXCEPTION 'NRR_CONFIRM_INVALID_MODE: %', c_mode;
    END IF;

    SELECT coalesce(sum(a_n),0) INTO v_scope FROM nrr_scope;
    IF v_scope IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION 'NRR_CONFIRM_SCOPE_DRIFT: escopo % linhas, esperado %.', v_scope, c_expected;
    END IF;

    FOR v_job IN SELECT * FROM nrr_scope ORDER BY a_n, set_code LOOP
        SELECT array_agg(r.id ORDER BY r.id) INTO v_a
          FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_job.job_id AND r.validation_status='VALID'
           AND r.decision_status='PENDING' AND r.persistence_status='PENDING';
        SELECT count(*) INTO v_b FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_job.job_id AND r.validation_status='VALID'
           AND r.decision_status='APPROVED' AND r.persistence_status='PENDING';
        IF v_b > 0 THEN RAISE EXCEPTION 'NRR_CONFIRM_RESUME_PARTIAL: job % (%).', v_job.job_id, v_job.set_code; END IF;

        v_n := public.admin_decide_catalog_variant_import_row(v_a, 'APPROVED');
        IF v_n <> cardinality(v_a) THEN
            RAISE EXCEPTION 'NRR_CONFIRM_DECIDE_MISMATCH: job % decidiu %, esperado %.', v_job.set_code, v_n, cardinality(v_a);
        END IF;

        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job.job_id, v_a);

        SELECT count(*) FILTER (WHERE persistence_status='INSERTED'),
               count(*) FILTER (WHERE persistence_status='UNCHANGED'),
               count(*) FILTER (WHERE persistence_status NOT IN ('INSERTED','UNCHANGED'))
          INTO v_ins, v_unc, v_fail
          FROM public.catalog_variant_import_row WHERE id = ANY (v_a);
        IF v_fail <> 0 THEN
            RAISE EXCEPTION 'NRR_CONFIRM_ROWS_NOT_PERSISTED: job % — % linha(s) fora de INSERTED/UNCHANGED.', v_job.set_code, v_fail;
        END IF;

        v_tot_a := v_tot_a + cardinality(v_a);
        v_tot_ins := v_tot_ins + v_ins;
        v_tot_unc := v_tot_unc + v_unc;
        v_jobs := v_jobs + 1;
        v_report := v_report || jsonb_build_object('set', v_job.set_code, 'a', cardinality(v_a), 'ins', v_ins, 'unc', v_unc,
                     'job_status', (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job.job_id));
    END LOOP;

    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv1 - v_cv0 <> v_tot_ins THEN
        RAISE EXCEPTION 'NRR_CONFIRM_CARD_VARIANT_DELTA: card_variant % -> %, inseridas %.', v_cv0, v_cv1, v_tot_ins;
    END IF;
    IF EXISTS (SELECT 1 FROM public.catalog_variant_import_row WHERE persistence_status = 'FAILED') THEN
        RAISE EXCEPTION 'NRR_CONFIRM_POST_FAILED_PRESENT';
    END IF;

    PERFORM set_config('request.jwt.claims', '', true);
    RAISE NOTICE 'NRR_CONFIRM_OK %', jsonb_build_object('mode', c_mode, 'jobs', v_jobs, 'rows', v_tot_a,
        'inserted', v_tot_ins, 'unchanged', v_tot_unc, 'card_variant_before', v_cv0, 'card_variant_after', v_cv1,
        'per_job', v_report);
END;
$nrr$;
