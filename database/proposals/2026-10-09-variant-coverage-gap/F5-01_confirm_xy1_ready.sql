/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: F5-01 - Piloto XY1: decide + confirm do job da 2ª fonte (Pokémon TCG API)
Versão......: 1.0
Status......: PRONTA — v_apply = false (dry-run, desfaz tudo) / true (aplica)
Data........: 2026-10-10
Mandato.....: ADR-034; CATALOG-VARIANT-COVERAGE-GAP-01, fatia F5 (piloto).
Runner......: mesmo padrão do NRR-CONFIRM (RPCs LIVE 2144 decide e 2145 confirm, admin real
              como ator, claims locais à transação).

Escopo: job 686f4ed4-28df-4ca1-81d9-fd2f0639249f (XY1, POKEMON_TCG_API, STAGED, 269 linhas).
Esperado: 269 INSERTED, 0 UNCHANGED, 0 FAILED; job COMPLETED; card_variant 26.491 -> 26.760;
          as 146 cartas da XY1 passam a ter variante (STANDARD 116, REVERSE_HOLO 123, HOLO 30).
===============================================================================
*/

DO $f5$
DECLARE
    v_apply  CONSTANT BOOLEAN := false;   -- << trocar para true para aplicar
    c_job    CONSTANT UUID := '686f4ed4-28df-4ca1-81d9-fd2f0639249f';
    c_rows   CONSTANT INTEGER := 269;
    v_admin  UUID;
    v_ids    UUID[];
    v_n      INTEGER;
    v_ins    INTEGER; v_unc INTEGER; v_fail INTEGER;
    v_cv0    BIGINT;  v_cv1 BIGINT;
    v_status TEXT;
    v_gap    INTEGER;
    v_types  JSONB;
BEGIN
    SELECT id INTO v_admin FROM public.admin_user;
    IF (SELECT count(*) FROM public.admin_user) <> 1 THEN RAISE EXCEPTION 'F5_ADMIN_AMBIGUOUS'; END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
    IF NOT public.is_admin() THEN RAISE EXCEPTION 'F5_NOT_ADMIN_CONTEXT'; END IF;

    -- Gates de entrada
    IF NOT EXISTS (SELECT 1 FROM public.catalog_variant_import_job j
                    WHERE j.id = c_job AND j.status = 'STAGED' AND j.source = 'POKEMON_TCG_API') THEN
        RAISE EXCEPTION 'F5_JOB_STATE';
    END IF;
    SELECT array_agg(r.id ORDER BY r.id) INTO v_ids
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = c_job AND r.validation_status = 'VALID'
       AND r.decision_status = 'PENDING' AND r.persistence_status = 'PENDING';
    IF cardinality(v_ids) IS DISTINCT FROM c_rows
       OR (SELECT count(*) FROM public.catalog_variant_import_row WHERE job_id = c_job) <> c_rows THEN
        RAISE EXCEPTION 'F5_SCOPE_DRIFT: % linha(s) pendentes, esperado %.', cardinality(v_ids), c_rows;
    END IF;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;

    -- Decide + confirm
    v_n := public.admin_decide_catalog_variant_import_row(v_ids, 'APPROVED');
    IF v_n <> c_rows THEN RAISE EXCEPTION 'F5_DECIDE_MISMATCH: %', v_n; END IF;

    PERFORM * FROM public.admin_confirm_catalog_variant_import(c_job, v_ids);

    -- Pós-condições
    SELECT count(*) FILTER (WHERE persistence_status = 'INSERTED'),
           count(*) FILTER (WHERE persistence_status = 'UNCHANGED'),
           count(*) FILTER (WHERE persistence_status NOT IN ('INSERTED', 'UNCHANGED'))
      INTO v_ins, v_unc, v_fail
      FROM public.catalog_variant_import_row WHERE job_id = c_job;
    IF v_fail <> 0 OR v_ins <> c_rows THEN
        RAISE EXCEPTION 'F5_PERSIST: inserted %, unchanged %, outros % (esperado % inseridas).', v_ins, v_unc, v_fail, c_rows;
    END IF;

    SELECT status INTO v_status FROM public.catalog_variant_import_job WHERE id = c_job;
    IF v_status <> 'COMPLETED' THEN RAISE EXCEPTION 'F5_JOB_FINAL: %', v_status; END IF;

    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv1 - v_cv0 <> c_rows THEN RAISE EXCEPTION 'F5_DELTA: % -> %', v_cv0, v_cv1; END IF;

    SELECT count(*) INTO v_gap
      FROM public.card c JOIN public.card_set cs ON cs.id = c.card_set_id
     WHERE cs.code = 'XY1' AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id);
    IF v_gap <> 0 THEN RAISE EXCEPTION 'F5_XY1_STILL_WITHOUT_VARIANT: %', v_gap; END IF;

    SELECT jsonb_object_agg(code, n) INTO v_types FROM (
        SELECT t.code, count(*) AS n
          FROM public.catalog_variant_import_row r
          JOIN public.card_variant v ON v.id = r.resulting_variant_id
          JOIN public.card_variant_type t ON t.id = v.variant_type_id
         WHERE r.job_id = c_job GROUP BY t.code) z;

    PERFORM set_config('request.jwt.claims', '', true);

    IF NOT v_apply THEN
        RAISE EXCEPTION 'F5_DRYRUN_OK (rollback): inseridas %, card_variant % -> %, XY1 sem variante 0, por tipo %', v_ins, v_cv0, v_cv1, v_types;
    END IF;
    RAISE NOTICE 'F5-01_OK: inseridas %, card_variant % -> %, por tipo %', v_ins, v_cv0, v_cv1, v_types;
END;
$f5$;
