-- CN1-6-K8B SETUP S. Fixture sintetico K8b (ids fixos c16b8b00-...). Executado com psql --single-transaction:
-- qualquer RAISE/erro => ROLLBACK integral; COMMIT so ao fim sem erro. Somente INSERT de linhas novas.
DO $k8b_setup$
DECLARE
    c_game CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000001';
    c_exp  CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000002';
    c_set  CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000003';
    c_rar  CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000004';
    c_cat  CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000005';
    c_t    CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000011';
    c_x    CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000021';
    c_y    CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000022';
    c_job  CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000031';
    c_ry   CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000041';
    c_rx   CONSTANT uuid := 'c16b8b00-0000-4000-8000-000000000042';
    c_name CONSTANT text := 'ZZ CN1-6 K8B - FIXTURE SINTETICA, NAO E DADO REAL';
    c_raw  CONSTANT jsonb := '{"cn1_6_fixture":"K8B"}';
    v_nd   jsonb;
    v_t0   timestamptz := clock_timestamp() - interval '10 seconds';
    n      bigint;
BEGIN
    -- PRE: ordem dos ids, catalogo vazio, action_log vazio
    IF NOT (c_x < c_y) THEN RAISE EXCEPTION 'K8B_SETUP_PRE: id(X) < id(Y) violado'; END IF;
    IF (SELECT count(*) FROM public.game) <> 0 OR (SELECT count(*) FROM public.expansion) <> 0
       OR (SELECT count(*) FROM public.card_set) <> 0 OR (SELECT count(*) FROM public.rarity) <> 0
       OR (SELECT count(*) FROM public.card_category) <> 0 OR (SELECT count(*) FROM public.card_variant_type) <> 0
       OR (SELECT count(*) FROM public.card) <> 0 OR (SELECT count(*) FROM public.card_variant) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 0
       OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 0 THEN
        RAISE EXCEPTION 'K8B_SETUP_PRE: catalogo/action_log nao vazio';
    END IF;

    INSERT INTO public.game (id, code, name) VALUES (c_game, 'ZZCN16_K8B', c_name);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT game=%', n; END IF;
    INSERT INTO public.expansion (id, game_id, code, name, release_order) VALUES (c_exp, c_game, 'ZZCN16_K8B', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT expansion=%', n; END IF;
    INSERT INTO public.rarity (id, game_id, code, name, display_order, symbol_code) VALUES (c_rar, c_game, 'ZZCN16_R', c_name, 1, 'ZZCN16_R');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT rarity=%', n; END IF;
    INSERT INTO public.card_category (id, game_id, code, name, display_order) VALUES (c_cat, c_game, 'ZZCN16_C', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT card_category=%', n; END IF;
    INSERT INTO public.card_variant_type (id, game_id, code, name, display_order) VALUES (c_t, c_game, 'ZZCN16_K8B_T', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT card_variant_type=%', n; END IF;
    INSERT INTO public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
        VALUES (c_set, c_exp, 'ZZCN16-K8B', c_name, 'REGULAR', 1, 2, 2);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT card_set=%', n; END IF;
    INSERT INTO public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
        VALUES (c_x, c_set, c_rar, c_cat, 'ZZX', 2, 1, 'ZZ CN1-6 K8B CARD X - FIXTURE SINTETICA');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT card X=%', n; END IF;
    INSERT INTO public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
        VALUES (c_y, c_set, c_rar, c_cat, 'ZZY', 2, 2, 'ZZ CN1-6 K8B CARD Y - FIXTURE SINTETICA');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT card Y=%', n; END IF;
    INSERT INTO public.catalog_variant_import_job (id, card_set_id, source, external_set_id, status, initiated_by)
        VALUES (c_job, c_set, 'TCGDEX', 'zzcn16-k8b-b', 'STAGED', NULL);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT job=%', n; END IF;

    v_nd := ('{"variant_type_id":"' || c_t::text || '","printing_profile_id":null,"edition_context_profile_id":null}')::jsonb;
    -- ordem de ENTRADA invertida: row de Y primeiro (created_at = t0), row de X depois (t0 + 1 s)
    INSERT INTO public.catalog_variant_import_row (id, job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status, created_at)
        VALUES (c_ry, c_job, c_y, c_raw, v_nd, 'VALID', 'NEW', 'APPROVED', 'PENDING', v_t0);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT row Y=%', n; END IF;
    INSERT INTO public.catalog_variant_import_row (id, job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status, created_at)
        VALUES (c_rx, c_job, c_x, c_raw, v_nd, 'VALID', 'NEW', 'APPROVED', 'PENDING', v_t0 + interval '1 second');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_SETUP_ROWCOUNT row X=%', n; END IF;

    -- POSTCHECK completo antes do COMMIT
    IF (SELECT count(*) FROM public.game) <> 1 OR (SELECT count(*) FROM public.expansion) <> 1
       OR (SELECT count(*) FROM public.card_set) <> 1 OR (SELECT count(*) FROM public.rarity) <> 1
       OR (SELECT count(*) FROM public.card_category) <> 1 OR (SELECT count(*) FROM public.card_variant_type) <> 1
       OR (SELECT count(*) FROM public.card) <> 2 OR (SELECT count(*) FROM public.card_variant) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 1
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 2
       OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 0 THEN
        RAISE EXCEPTION 'K8B_SETUP_POST: contagens divergentes';
    END IF;
    IF (SELECT count(*) FROM public.card WHERE id IN (c_x, c_y) AND card_set_id = c_set) <> 2 THEN RAISE EXCEPTION 'K8B_SETUP_POST: cards'; END IF;
    IF (SELECT status FROM public.catalog_variant_import_job WHERE id = c_job) IS DISTINCT FROM 'STAGED' THEN RAISE EXCEPTION 'K8B_SETUP_POST: job nao STAGED'; END IF;
    IF (SELECT count(*) FROM public.catalog_variant_import_row r
         WHERE r.job_id = c_job AND r.validation_status = 'VALID' AND r.decision_status = 'APPROVED'
           AND r.persistence_status = 'PENDING' AND r.match_status = 'NEW'
           AND r.matched_variant_id IS NULL AND r.resulting_variant_id IS NULL AND r.error_detail IS NULL
           AND r.normalized_data ->> 'variant_type_id' = c_t::text
           AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') = 'null'
           AND jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null') <> 2 THEN
        RAISE EXCEPTION 'K8B_SETUP_POST: rows fora do estado esperado';
    END IF;
    IF NOT ((SELECT created_at FROM public.catalog_variant_import_row WHERE id = c_ry)
          < (SELECT created_at FROM public.catalog_variant_import_row WHERE id = c_rx)) THEN
        RAISE EXCEPTION 'K8B_SETUP_POST: ordem de entrada Y antes de X violada';
    END IF;
END
$k8b_setup$;
SELECT 'K8B_SETUP_OK';