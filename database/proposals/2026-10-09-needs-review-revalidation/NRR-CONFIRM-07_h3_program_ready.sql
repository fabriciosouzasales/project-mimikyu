-- NRR-CONFIRM-07 — decide+confirm das 57 linhas H3 (foil de programa → acabamento + Edition Context)
-- Mesmo runner do NRR-CONFIRM-01/02 (2144/2145, ator = admin real).
-- Escopo POR LINHA: VALID/PENDING/PENDING com foil league | player-reward | professor-program,
-- em jobs STAGED. Outras linhas dos mesmos jobs não são tocadas.
-- Pré-condição: 2243 + 2244 + 2245 aplicadas e revalidação run 4627505e (57 linhas, 12 jobs) em 2026-10-09
-- Esperado: rows=57, inserted+unchanged=57; qualquer gate falho desfaz tudo. Colar no SQL Editor.

DO $nrr$
DECLARE
    c_expected  CONSTANT INTEGER := 57;
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

    SELECT count(*) INTO v_scope
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status = 'STAGED'
       AND r.validation_status='VALID' AND r.decision_status='PENDING' AND r.persistence_status='PENDING'
       AND r.raw_data->>'foil' IN ('league','player-reward','professor-program');
    IF v_scope IS DISTINCT FROM c_expected THEN
        RAISE EXCEPTION 'NRR_CONFIRM_SCOPE_DRIFT: escopo % linhas, esperado %.', v_scope, c_expected;
    END IF;

    FOR v_job IN
        SELECT j.id AS job_id, cs.code AS set_code, count(*) AS a_n
          FROM public.catalog_variant_import_row r
          JOIN public.catalog_variant_import_job j ON j.id = r.job_id
          JOIN public.card_set cs ON cs.id = j.card_set_id
         WHERE j.status = 'STAGED'
           AND r.validation_status='VALID' AND r.decision_status='PENDING' AND r.persistence_status='PENDING'
           AND r.raw_data->>'foil' IN ('league','player-reward','professor-program')
         GROUP BY 1, 2
         ORDER BY 3, 2
    LOOP
        SELECT array_agg(r.id ORDER BY r.id) INTO v_a
          FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_job.job_id
           AND r.validation_status='VALID' AND r.decision_status='PENDING' AND r.persistence_status='PENDING'
           AND r.raw_data->>'foil' IN ('league','player-reward','professor-program');
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
    RAISE NOTICE 'NRR_CONFIRM_OK %', jsonb_build_object('jobs', v_jobs, 'rows', v_tot_a,
        'inserted', v_tot_ins, 'unchanged', v_tot_unc, 'card_variant_before', v_cv0, 'card_variant_after', v_cv1,
        'per_job', v_report);
END;
$nrr$;
