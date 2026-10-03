-- CN1-6-K2 SETUP S. Fixture sintetico K2 (ids fixos c16b0200-...). psql --single-transaction: qualquer RAISE/erro =>
-- ROLLBACK integral; COMMIT so ao fim sem erro. Somente INSERT de linhas novas. Estado K1 (c16b0100-...) intocado.
DO $k2_setup$
DECLARE
    c_game CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000001';
    c_exp  CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000002';
    c_set  CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000003';
    c_rar  CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000004';
    c_cat  CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000005';
    c_td   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000011';
    c_t1   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000012';
    c_t2   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000013';
    c_d    CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000021';
    c_b    CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000022';
    c_c    CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000023';
    c_jd   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000031';
    c_jb   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000032';
    c_jc   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000033';
    c_rd   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000041';
    c_rb   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000042';
    c_rc   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000043';
    c_vd   CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000051';
    c_vb2  CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000052';
    c_vc1  CONSTANT uuid := 'c16b0200-0000-4000-8000-000000000053';
    c_name CONSTANT text := 'ZZ CN1-6 K2 - FIXTURE SINTETICA, NAO E DADO REAL';
    c_raw  CONSTANT jsonb := '{"cn1_6_fixture":"K2"}';
    n      bigint;
BEGIN
    -- PRE: estado exato pos-K1 (1 variant, 2 jobs, 2 rows, 2 logs) e nenhum id K2 presente
    IF (SELECT count(*) FROM public.card_variant) <> 1 OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 2
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 2 OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 2
       OR (SELECT count(*) FROM public.game) <> 1 OR (SELECT count(*) FROM public.card) <> 1 THEN
        RAISE EXCEPTION 'K2_SETUP_PRE: estado diferente do pos-K1';
    END IF;
    IF EXISTS (SELECT 1 FROM public.game WHERE id = c_game OR code = 'ZZCN16_K2') THEN RAISE EXCEPTION 'K2_SETUP_PRE: fixture K2 ja presente'; END IF;

    INSERT INTO public.game (id, code, name) VALUES (c_game, 'ZZCN16_K2', c_name);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT game=%', n; END IF;
    INSERT INTO public.expansion (id, game_id, code, name, release_order) VALUES (c_exp, c_game, 'ZZCN16_K2', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT expansion=%', n; END IF;
    INSERT INTO public.rarity (id, game_id, code, name, display_order, symbol_code) VALUES (c_rar, c_game, 'ZZCN16_R', c_name, 1, 'ZZCN16_R');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT rarity=%', n; END IF;
    INSERT INTO public.card_category (id, game_id, code, name, display_order) VALUES (c_cat, c_game, 'ZZCN16_C', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT card_category=%', n; END IF;
    INSERT INTO public.card_variant_type (id, game_id, code, name, display_order) VALUES
        (c_td, c_game, 'ZZCN16_K2_TD', c_name, 1), (c_t1, c_game, 'ZZCN16_K2_T1', c_name, 2), (c_t2, c_game, 'ZZCN16_K2_T2', c_name, 3);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT card_variant_type=%', n; END IF;
    INSERT INTO public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
        VALUES (c_set, c_exp, 'ZZCN16-K2', c_name, 'REGULAR', 1, 3, 3);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT card_set=%', n; END IF;
    INSERT INTO public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name) VALUES
        (c_d, c_set, c_rar, c_cat, 'ZZD', 3, 1, 'ZZ CN1-6 K2 CARD D - FIXTURE SINTETICA'),
        (c_b, c_set, c_rar, c_cat, 'ZZB', 3, 2, 'ZZ CN1-6 K2 CARD B - FIXTURE SINTETICA'),
        (c_c, c_set, c_rar, c_cat, 'ZZC', 3, 3, 'ZZ CN1-6 K2 CARD C - FIXTURE SINTETICA');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT card=%', n; END IF;
    -- Variants pre-existentes (is_default no default = false)
    INSERT INTO public.card_variant (id, card_id, variant_type_id, variant_order, printing_profile_id, edition_context_profile_id) VALUES
        (c_vd,  c_d, c_td, 1, NULL, NULL),
        (c_vb2, c_b, c_t2, 1, NULL, NULL),
        (c_vc1, c_c, c_t1, 1, NULL, NULL);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT card_variant=%', n; END IF;
    INSERT INTO public.catalog_variant_import_job (id, card_set_id, source, external_set_id, status, initiated_by) VALUES
        (c_jd, c_set, 'TCGDEX', 'zzcn16-k2-d', 'STAGED', NULL),
        (c_jb, c_set, 'TCGDEX', 'zzcn16-k2-b', 'STAGED', NULL),
        (c_jc, c_set, 'TCGDEX', 'zzcn16-k2-c', 'STAGED', NULL);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT jobs=%', n; END IF;
    INSERT INTO public.catalog_variant_import_row (id, job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status) VALUES
        (c_rd, c_jd, c_d, c_raw, ('{"variant_type_id":"' || c_td::text || '","printing_profile_id":null,"edition_context_profile_id":null}')::jsonb, 'VALID', 'NEW', 'APPROVED', 'PENDING'),
        (c_rb, c_jb, c_b, c_raw, ('{"variant_type_id":"' || c_t1::text || '","printing_profile_id":null,"edition_context_profile_id":null}')::jsonb, 'VALID', 'NEW', 'APPROVED', 'PENDING'),
        (c_rc, c_jc, c_c, c_raw, ('{"variant_type_id":"' || c_t2::text || '","printing_profile_id":null,"edition_context_profile_id":null}')::jsonb, 'VALID', 'NEW', 'APPROVED', 'PENDING');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_SETUP_ROWCOUNT rows=%', n; END IF;

    -- POSTCHECK completo antes do COMMIT
    IF (SELECT count(*) FROM public.game) <> 2 OR (SELECT count(*) FROM public.expansion) <> 2
       OR (SELECT count(*) FROM public.card_set) <> 2 OR (SELECT count(*) FROM public.rarity) <> 2
       OR (SELECT count(*) FROM public.card_category) <> 2 OR (SELECT count(*) FROM public.card_variant_type) <> 4
       OR (SELECT count(*) FROM public.card) <> 4 OR (SELECT count(*) FROM public.card_variant) <> 4
       OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 5
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 5
       OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 2 THEN
        RAISE EXCEPTION 'K2_SETUP_POST: contagens divergentes';
    END IF;
    IF (SELECT count(*) FROM public.card_variant v WHERE v.printing_profile_id IS NULL AND v.edition_context_profile_id IS NULL AND v.is_default = false
          AND ((v.id = c_vd AND v.card_id = c_d AND v.variant_type_id = c_td AND v.variant_order = 1)
            OR (v.id = c_vb2 AND v.card_id = c_b AND v.variant_type_id = c_t2 AND v.variant_order = 1)
            OR (v.id = c_vc1 AND v.card_id = c_c AND v.variant_type_id = c_t1 AND v.variant_order = 1))) <> 3 THEN
        RAISE EXCEPTION 'K2_SETUP_POST: variants pre-existentes divergentes';
    END IF;
    IF (SELECT count(*) FROM public.catalog_variant_import_job WHERE id IN (c_jd, c_jb, c_jc) AND card_set_id = c_set AND status = 'STAGED') <> 3 THEN
        RAISE EXCEPTION 'K2_SETUP_POST: jobs nao STAGED';
    END IF;
    IF (SELECT count(*) FROM public.catalog_variant_import_row r
         WHERE r.id IN (c_rd, c_rb, c_rc) AND r.validation_status = 'VALID' AND r.decision_status = 'APPROVED'
           AND r.persistence_status = 'PENDING' AND r.match_status = 'NEW'
           AND r.matched_variant_id IS NULL AND r.resulting_variant_id IS NULL AND r.error_detail IS NULL
           AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') = 'null'
           AND jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null'
           AND ((r.id = c_rd AND r.job_id = c_jd AND r.card_id = c_d AND r.normalized_data ->> 'variant_type_id' = c_td::text)
             OR (r.id = c_rb AND r.job_id = c_jb AND r.card_id = c_b AND r.normalized_data ->> 'variant_type_id' = c_t1::text)
             OR (r.id = c_rc AND r.job_id = c_jc AND r.card_id = c_c AND r.normalized_data ->> 'variant_type_id' = c_t2::text))) <> 3 THEN
        RAISE EXCEPTION 'K2_SETUP_POST: rows fora do estado esperado';
    END IF;
END
$k2_setup$;
SELECT 'K2_SETUP_OK';