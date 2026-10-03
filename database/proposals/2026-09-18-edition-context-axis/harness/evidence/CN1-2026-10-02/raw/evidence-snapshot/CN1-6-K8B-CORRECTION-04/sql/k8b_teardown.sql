-- CN1-6-K8B TEARDOWN T. Remocao EXATA do fixture K8b por id fixo, em ordem inversa das FKs.
-- psql --single-transaction: qualquer RAISE/erro => ROLLBACK integral; COMMIT so ao fim sem erro.
DO $k8b_teardown$
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
    n      bigint;
BEGIN
    -- PRE: identidade exata do fixture e nenhuma dependencia fora dele
    IF (SELECT count(*) FROM public.game WHERE id = c_game AND code = 'ZZCN16_K8B') <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_PRE: game'; END IF;
    IF (SELECT count(*) FROM public.expansion WHERE game_id = c_game) <> 1
       OR (SELECT count(*) FROM public.rarity WHERE game_id = c_game) <> 1
       OR (SELECT count(*) FROM public.card_category WHERE game_id = c_game) <> 1
       OR (SELECT count(*) FROM public.card_variant_type WHERE game_id = c_game) <> 1
       OR (SELECT count(*) FROM public.card_set WHERE expansion_id = c_exp) <> 1
       OR (SELECT count(*) FROM public.card WHERE card_set_id = c_set) <> 2
       OR (SELECT count(*) FROM public.catalog_variant_import_job WHERE card_set_id = c_set) <> 1
       OR (SELECT count(*) FROM public.catalog_variant_import_row WHERE job_id = c_job) <> 2 THEN
        RAISE EXCEPTION 'K8B_TEARDOWN_PRE: dependencias fora do fixture';
    END IF;
    IF (SELECT count(*) FROM public.card_variant WHERE card_id IN (c_x, c_y) OR variant_type_id = c_t) <> 0 THEN RAISE EXCEPTION 'K8B_TEARDOWN_PRE: card_variant presente'; END IF;
    IF (SELECT count(*) FROM public.catalog_admin_action_log WHERE entity_id IN (c_job, c_set)) <> 0 THEN RAISE EXCEPTION 'K8B_TEARDOWN_PRE: action_log do fixture presente'; END IF;

    DELETE FROM public.catalog_variant_import_row WHERE id IN (c_ry, c_rx) AND job_id = c_job;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 2 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT rows=%', n; END IF;
    DELETE FROM public.catalog_variant_import_job WHERE id = c_job AND card_set_id = c_set AND external_set_id = 'zzcn16-k8b-b';
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT job=%', n; END IF;
    DELETE FROM public.card WHERE id IN (c_x, c_y) AND card_set_id = c_set;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 2 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT card=%', n; END IF;
    DELETE FROM public.card_variant_type WHERE id = c_t AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT card_variant_type=%', n; END IF;
    DELETE FROM public.card_set WHERE id = c_set AND expansion_id = c_exp;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT card_set=%', n; END IF;
    DELETE FROM public.card_category WHERE id = c_cat AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT card_category=%', n; END IF;
    DELETE FROM public.rarity WHERE id = c_rar AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT rarity=%', n; END IF;
    DELETE FROM public.expansion WHERE id = c_exp AND game_id = c_game;
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT expansion=%', n; END IF;
    DELETE FROM public.game WHERE id = c_game AND code = 'ZZCN16_K8B';
    GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'K8B_TEARDOWN_ROWCOUNT game=%', n; END IF;

    -- POST: catalogo novamente vazio e action_log vazio
    IF (SELECT count(*) FROM public.game) <> 0 OR (SELECT count(*) FROM public.expansion) <> 0
       OR (SELECT count(*) FROM public.card_set) <> 0 OR (SELECT count(*) FROM public.rarity) <> 0
       OR (SELECT count(*) FROM public.card_category) <> 0 OR (SELECT count(*) FROM public.card_variant_type) <> 0
       OR (SELECT count(*) FROM public.card) <> 0 OR (SELECT count(*) FROM public.card_variant) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_job) <> 0
       OR (SELECT count(*) FROM public.catalog_variant_import_row) <> 0
       OR (SELECT count(*) FROM public.catalog_admin_action_log) <> 0 THEN
        RAISE EXCEPTION 'K8B_TEARDOWN_POST: catalogo/action_log nao vazio';
    END IF;
END
$k8b_teardown$;
SELECT 'K8B_TEARDOWN_OK';