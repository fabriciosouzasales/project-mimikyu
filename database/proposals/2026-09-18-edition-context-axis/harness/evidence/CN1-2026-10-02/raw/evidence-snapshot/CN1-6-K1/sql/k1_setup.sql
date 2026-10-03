-- CN1-6-K1 SETUP S. Fixture sintetico K1 (ids fixos c16b0100-...). Executado com psql --single-transaction:
-- qualquer RAISE/erro => ROLLBACK integral; COMMIT so ao fim sem erro. Somente INSERT de linhas novas.
DO $k1_setup$
DECLARE
    c_game CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000001';
    c_exp  CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000002';
    c_set  CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000003';
    c_rar  CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000004';
    c_cat  CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000005';
    c_t    CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000011';
    c_c    CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000021';
    c_ja   CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000031';
    c_jb   CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000032';
    c_ra   CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000041';
    c_rb   CONSTANT uuid := 'c16b0100-0000-4000-8000-000000000042';
    c_name CONSTANT text := 'ZZ CN1-6 K1 - FIXTURE SINTETICA, NAO E DADO REAL';
    c_raw  CONSTANT jsonb := '{"cn1_6_fixture":"K1"}';
    v_nd   jsonb;
    n      bigint;
BEGIN
    -- PRE: catalogo vazio, action_log vazio
    IF (SELECT count(*) FROM public.game) <> 0 OR (SELECT count(*) FROM public.expansion) <> 0
       OR (SELECT count(*) FROM public.card_set) <> 0 OR (SELECT count(*) FROM public.rarity) <> 0
       OR (SELECT count(*) FROM public.card_category) <> 0 OR (SELECT count(*) FROM public.card_variant_type) <> 0
       OR (SELECT count(*) FROM public.card) <> 0 OR (SELECT count(*) FROM public.card_variant) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 0
       OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 0 THEN
        RAISE EXCEPTION 'K1_SETUP_PRE: catalogo/action_log nao vazio';
    END IF;

    INSERT INTO public.game (id, code, name) VALUES (c_game, 'ZZCN16_K1', c_name);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT game=%', n; END IF;
    INSERT INTO public.expansion (id, game_id, code, name, release_order) VALUES (c_exp, c_game, 'ZZCN16_K1', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT expansion=%', n; END IF;
    INSERT INTO public.rarity (id, game_id, code, name, display_order, symbol_code) VALUES (c_rar, c_game, 'ZZCN16_R', c_name, 1, 'ZZCN16_R');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT rarity=%', n; END IF;
    INSERT INTO public.card_category (id, game_id, code, name, display_order) VALUES (c_cat, c_game, 'ZZCN16_C', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT card_category=%', n; END IF;
    INSERT INTO public.card_variant_type (id, game_id, code, name, display_order) VALUES (c_t, c_game, 'ZZCN16_K1_T', c_name, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT card_variant_type=%', n; END IF;
    INSERT INTO public.card_set (id, expansion_id, code, name, set_type, release_order, base_set_size, total_set_size)
        VALUES (c_set, c_exp, 'ZZCN16-K1', c_name, 'REGULAR', 1, 1, 1);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT card_set=%', n; END IF;
    INSERT INTO public.card (id, card_set_id, rarity_id, category_id, collector_number, collector_total, collector_order, name)
        VALUES (c_c, c_set, c_rar, c_cat, 'ZZC', 1, 1, 'ZZ CN1-6 K1 CARD C - FIXTURE SINTETICA');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT card C=%', n; END IF;
    INSERT INTO public.catalog_variant_import_job (id, card_set_id, source, external_set_id, status, initiated_by)
        VALUES (c_ja, c_set, 'TCGDEX', 'zzcn16-k1-a', 'STAGED', NULL);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT job JA=%', n; END IF;
    INSERT INTO public.catalog_variant_import_job (id, card_set_id, source, external_set_id, status, initiated_by)
        VALUES (c_jb, c_set, 'TCGDEX', 'zzcn16-k1-b', 'STAGED', NULL);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT job JB=%', n; END IF;

    -- MESMA identidade de 4 componentes nas duas rows: (C, T, NULL, NULL)
    v_nd := ('{"variant_type_id":"' || c_t::text || '","printing_profile_id":null,"edition_context_profile_id":null}')::jsonb;
    INSERT INTO public.catalog_variant_import_row (id, job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status)
        VALUES (c_ra, c_ja, c_c, c_raw, v_nd, 'VALID', 'NEW', 'APPROVED', 'PENDING');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT row RA=%', n; END IF;
    INSERT INTO public.catalog_variant_import_row (id, job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status)
        VALUES (c_rb, c_jb, c_c, c_raw, v_nd, 'VALID', 'NEW', 'APPROVED', 'PENDING');
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K1_SETUP_ROWCOUNT row RB=%', n; END IF;

    -- POSTCHECK completo antes do COMMIT
    IF (SELECT count(*) FROM public.game) <> 1 OR (SELECT count(*) FROM public.expansion) <> 1
       OR (SELECT count(*) FROM public.card_set) <> 1 OR (SELECT count(*) FROM public.rarity) <> 1
       OR (SELECT count(*) FROM public.card_category) <> 1 OR (SELECT count(*) FROM public.card_variant_type) <> 1
       OR (SELECT count(*) FROM public.card) <> 1 OR (SELECT count(*) FROM public.card_variant) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 2
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 2
       OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 0 THEN
        RAISE EXCEPTION 'K1_SETUP_POST: contagens divergentes';
    END IF;
    IF (SELECT count(*) FROM public.catalog_variant_import_job WHERE id IN (c_ja, c_jb) AND card_set_id = c_set AND status = 'STAGED') <> 2 THEN
        RAISE EXCEPTION 'K1_SETUP_POST: jobs nao STAGED';
    END IF;
    IF (SELECT count(*) FROM public.catalog_variant_import_row r
         WHERE r.id IN (c_ra, c_rb) AND r.card_id = c_c AND r.validation_status = 'VALID' AND r.decision_status = 'APPROVED'
           AND r.persistence_status = 'PENDING' AND r.match_status = 'NEW'
           AND r.matched_variant_id IS NULL AND r.resulting_variant_id IS NULL AND r.error_detail IS NULL
           AND r.normalized_data ->> 'variant_type_id' = c_t::text
           AND jsonb_typeof(r.normalized_data -> 'printing_profile_id') = 'null'
           AND jsonb_typeof(r.normalized_data -> 'edition_context_profile_id') = 'null') <> 2 THEN
        RAISE EXCEPTION 'K1_SETUP_POST: rows fora do estado esperado';
    END IF;
    IF (SELECT job_id FROM public.catalog_variant_import_row WHERE id = c_ra) IS DISTINCT FROM c_ja
       OR (SELECT job_id FROM public.catalog_variant_import_row WHERE id = c_rb) IS DISTINCT FROM c_jb THEN
        RAISE EXCEPTION 'K1_SETUP_POST: row/job divergente';
    END IF;
END
$k1_setup$;
SELECT 'K1_SETUP_OK';