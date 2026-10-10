/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: F6 - decide + confirm de todos os jobs STAGED da 2ª fonte (Pokémon TCG API)
Versão......: 1.0
Status......: PRONTA — v_apply = false (dry-run, desfaz tudo) / true (aplica)
Data........: 2026-10-10
Mandato.....: ADR-034; CATALOG-VARIANT-COVERAGE-GAP-01, fatia F6. Mesmo runner do F5-01 (piloto XY1).

Escopo: todo job source = POKEMON_TCG_API em STAGED (os lotes F6/stage_*_apply.sql já gravados).
Por job: todas as linhas VALID/PENDING/PENDING (o carregador só cria esse estado), decididas
APPROVED e confirmadas pelas RPCs LIVE (2144 / 2145), com o admin real como ator.
Gates: nenhuma linha FAILED; cada job termina COMPLETED; delta de card_variant = soma das linhas;
       nenhuma carta casada fica sem variante.
Rodar depois de cada lote, ou uma vez no fim. Idempotente: sem job STAGED, não faz nada.
===============================================================================
*/

DO $f6$
DECLARE
    v_apply  CONSTANT BOOLEAN := false;   -- << trocar para true para aplicar
    v_admin  UUID;
    v_job    RECORD;
    v_ids    UUID[];
    v_n      INTEGER;
    v_ins    INTEGER; v_fail INTEGER;
    v_cv0    BIGINT;  v_cv1 BIGINT;
    v_tot    INTEGER := 0;
    v_jobs   INTEGER := 0;
    v_report JSONB := '[]'::jsonb;
BEGIN
    SELECT id INTO v_admin FROM public.admin_user;
    IF (SELECT count(*) FROM public.admin_user) <> 1 THEN RAISE EXCEPTION 'F6_ADMIN_AMBIGUOUS'; END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'F6_NOT_ADMIN_CONTEXT'; END IF;

    SELECT count(*) INTO v_cv0 FROM public.card_variant;

    FOR v_job IN
        SELECT j.id, cs.code
          FROM public.catalog_variant_import_job j
          JOIN public.card_set cs ON cs.id = j.card_set_id
         WHERE j.source = 'POKEMON_TCG_API' AND j.status = 'STAGED'
         ORDER BY cs.code
    LOOP
        SELECT array_agg(r.id ORDER BY r.id) INTO v_ids
          FROM public.catalog_variant_import_row r
         WHERE r.job_id = v_job.id AND r.validation_status = 'VALID'
           AND r.decision_status = 'PENDING' AND r.persistence_status = 'PENDING';
        IF v_ids IS NULL
           OR cardinality(v_ids) <> (SELECT count(*) FROM public.catalog_variant_import_row WHERE job_id = v_job.id) THEN
            RAISE EXCEPTION 'F6_JOB_NOT_PRISTINE: % (%)', v_job.code, v_job.id;
        END IF;
        IF cardinality(v_ids) > 1000 THEN
            RAISE EXCEPTION 'F6_JOB_TOO_LARGE: % tem % linhas (teto do confirm = 1000).', v_job.code, cardinality(v_ids);
        END IF;

        v_n := public.admin_decide_catalog_variant_import_row(v_ids, 'APPROVED');
        IF v_n <> cardinality(v_ids) THEN RAISE EXCEPTION 'F6_DECIDE_MISMATCH: %', v_job.code; END IF;

        PERFORM * FROM public.admin_confirm_catalog_variant_import(v_job.id, v_ids);

        SELECT count(*) FILTER (WHERE persistence_status = 'INSERTED'),
               count(*) FILTER (WHERE persistence_status <> 'INSERTED')
          INTO v_ins, v_fail
          FROM public.catalog_variant_import_row WHERE job_id = v_job.id;
        IF v_fail <> 0 THEN
            RAISE EXCEPTION 'F6_PERSIST: % — % linha(s) fora de INSERTED.', v_job.code, v_fail;
        END IF;
        IF (SELECT status FROM public.catalog_variant_import_job WHERE id = v_job.id) <> 'COMPLETED' THEN
            RAISE EXCEPTION 'F6_JOB_FINAL: %', v_job.code;
        END IF;
        IF EXISTS (SELECT 1 FROM public.catalog_variant_import_row r
                    WHERE r.job_id = v_job.id
                      AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = r.card_id)) THEN
            RAISE EXCEPTION 'F6_CARD_STILL_WITHOUT_VARIANT: %', v_job.code;
        END IF;

        v_tot := v_tot + v_ins;
        v_jobs := v_jobs + 1;
        v_report := v_report || jsonb_build_object('set', v_job.code, 'inserted', v_ins);
    END LOOP;

    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv1 - v_cv0 <> v_tot THEN RAISE EXCEPTION 'F6_DELTA: % -> %, inseridas %', v_cv0, v_cv1, v_tot; END IF;

    PERFORM set_config('request.jwt.claims', '', true);

    IF NOT v_apply THEN
        RAISE EXCEPTION 'F6_DRYRUN_OK (rollback): jobs %, inseridas %, card_variant % -> %, por coleção %', v_jobs, v_tot, v_cv0, v_cv1, v_report;
    END IF;
    RAISE NOTICE 'F6_CONFIRM_OK: jobs %, inseridas %, card_variant % -> %, por coleção %', v_jobs, v_tot, v_cv0, v_cv1, v_report;
END;
$f6$;
