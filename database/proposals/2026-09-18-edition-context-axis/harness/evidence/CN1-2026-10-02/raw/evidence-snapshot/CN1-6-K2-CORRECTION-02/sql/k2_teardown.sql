-- CN1-6-K2 TEARDOWN T (SOMENTE sob STOP antes de QUALQUER confirm HTTP). Remocao EXATA do fixture K2 por id fixo, em
-- ordem inversa das FKs, somente se o fixture estiver exatamente no estado pos-setup. Estado K1 nunca tocado.
DO $k2_teardown$
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
    n      bigint;
BEGIN
    IF (SELECT count(*) FROM public.game WHERE id = c_game AND code = 'ZZCN16_K2') <> 1 THEN RAISE EXCEPTION 'K2_TEARDOWN_PRE: game'; END IF;
    IF (SELECT count(*) FROM public.expansion WHERE game_id = c_game) <> 1
       OR (SELECT count(*) FROM public.rarity WHERE game_id = c_game) <> 1
       OR (SELECT count(*) FROM public.card_category WHERE game_id = c_game) <> 1
       OR (SELECT count(*) FROM public.card_variant_type WHERE game_id = c_game) <> 3
       OR (SELECT count(*) FROM public.card_set WHERE expansion_id = c_exp) <> 1
       OR (SELECT count(*) FROM public.card WHERE card_set_id = c_set) <> 3
       OR (SELECT count(*) FROM public.catalog_variant_import_job WHERE card_set_id = c_set) <> 3
       OR (SELECT count(*) FROM public.catalog_variant_import_job WHERE card_set_id = c_set AND status = 'STAGED') <> 3
       OR (SELECT count(*) FROM public.catalog_variant_import_row WHERE job_id IN (c_jd, c_jb, c_jc)) <> 3
       OR (SELECT count(*) FROM public.catalog_variant_import_row WHERE id IN (c_rd, c_rb, c_rc) AND persistence_status = 'PENDING' AND match_status = 'NEW') <> 3 THEN
        RAISE EXCEPTION 'K2_TEARDOWN_PRE: fixture fora do estado pos-setup ou dependencias fora do fixture';
    END IF;
    IF (SELECT count(*) FROM public.card_variant WHERE card_id IN (c_d, c_b, c_c)) <> 3
       OR (SELECT count(*) FROM public.card_variant v WHERE (v.id = c_vd AND v.card_id = c_d AND v.variant_type_id = c_td AND v.variant_order = 1)
             OR (v.id = c_vb2 AND v.card_id = c_b AND v.variant_type_id = c_t2 AND v.variant_order = 1)
             OR (v.id = c_vc1 AND v.card_id = c_c AND v.variant_type_id = c_t1 AND v.variant_order = 1)) <> 3 THEN
        RAISE EXCEPTION 'K2_TEARDOWN_PRE: variants K2 fora do estado pos-setup';
    END IF;
    IF (SELECT count(*) FROM public.catalog_admin_action_log WHERE entity_id IN (c_jd, c_jb, c_jc, c_set)) <> 0 THEN RAISE EXCEPTION 'K2_TEARDOWN_PRE: action_log K2 presente'; END IF;

    DELETE FROM public.catalog_variant_import_row WHERE id IN (c_rd, c_rb, c_rc) AND job_id IN (c_jd, c_jb, c_jc);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT rows=%', n; END IF;
    DELETE FROM public.catalog_variant_import_job WHERE id IN (c_jd, c_jb, c_jc) AND card_set_id = c_set;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT jobs=%', n; END IF;
    DELETE FROM public.card_variant WHERE id IN (c_vd, c_vb2, c_vc1) AND card_id IN (c_d, c_b, c_c);
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT card_variant=%', n; END IF;
    DELETE FROM public.card WHERE id IN (c_d, c_b, c_c) AND card_set_id = c_set;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT card=%', n; END IF;
    DELETE FROM public.card_variant_type WHERE id IN (c_td, c_t1, c_t2) AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 3 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT card_variant_type=%', n; END IF;
    DELETE FROM public.card_set WHERE id = c_set AND expansion_id = c_exp;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT card_set=%', n; END IF;
    DELETE FROM public.card_category WHERE id = c_cat AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT card_category=%', n; END IF;
    DELETE FROM public.rarity WHERE id = c_rar AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT rarity=%', n; END IF;
    DELETE FROM public.expansion WHERE id = c_exp AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT expansion=%', n; END IF;
    DELETE FROM public.game WHERE id = c_game AND code = 'ZZCN16_K2';
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K2_TEARDOWN_ROWCOUNT game=%', n; END IF;

    -- POST: de volta ao estado exato pos-K1
    IF (SELECT count(*) FROM public.card_variant) <> 1 OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 2
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 2 OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 2
       OR (SELECT count(*) FROM public.game) <> 1 OR (SELECT count(*) FROM public.card) <> 1 THEN
        RAISE EXCEPTION 'K2_TEARDOWN_POST: estado diferente do pos-K1';
    END IF;
END
$k2_teardown$;
SELECT 'K2_TEARDOWN_OK';