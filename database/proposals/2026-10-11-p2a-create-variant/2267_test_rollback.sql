/*
===============================================================================
Query.......: 2267-T - Testes do cadastro individual de variante (sempre desfeitos)
Uso.........: depois da 2267, ou junto dela num único envio (ensaio). Termina SEMPRE em
              RAISE EXCEPTION: nada fica gravado. Sucesso = 'P2A-2267-TEST PASS ...'.
Cobre.......: S1 privilégios; S2 não-admin; I1 acabamento de outro jogo/inativo; I2 duplicata;
              I3 carta inativa; F1 cadastro (ordem max+1, não vira padrão se já há padrão, log);
              P1 Pricing restrito à carta e reportado à parte; T tempo.
===============================================================================
*/
DO $t$
DECLARE
  c_admin constant uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_card uuid; v_type uuid; v_dup_type uuid; v_dup_pp uuid; v_dup_ec uuid; v_bad_type uuid;
  v_max int; v_res jsonb; v_err text; v_logs int; v_t0 timestamptz; v_ms numeric;
  v_other_unlinked_before int; v_other_unlinked_after int;
BEGIN
  -- Fixture: carta ativa com padrão, com produtos de preço sem variante, e um acabamento ativo do
  -- mesmo jogo ainda não usado por ela (sem perfis).
  SELECT c.id, t.id INTO v_card, v_type
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    JOIN public.card_variant_type t ON t.game_id = e.game_id AND t.is_active
   WHERE c.is_active
     AND EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = c.id AND d.is_default)
     AND EXISTS (SELECT 1 FROM public.pricing_product pp JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
                  WHERE m.card_id = c.id AND pp.card_variant_id IS NULL)
     AND NOT EXISTS (SELECT 1 FROM public.card_variant x WHERE x.card_id = c.id AND x.variant_type_id = t.id
                       AND x.printing_profile_id IS NULL AND x.edition_context_profile_id IS NULL)
   ORDER BY c.id, t.display_order LIMIT 1;
  IF v_card IS NULL THEN RAISE EXCEPTION 'P2A-2267-TEST FAIL: sem fixture'; END IF;
  SELECT variant_type_id, printing_profile_id, edition_context_profile_id
    INTO v_dup_type, v_dup_pp, v_dup_ec FROM public.card_variant WHERE card_id = v_card LIMIT 1;
  SELECT max(variant_order) INTO v_max FROM public.card_variant WHERE card_id = v_card;
  SELECT t.id INTO v_bad_type FROM public.card_variant_type t WHERE NOT t.is_active LIMIT 1;

  -- S1
  IF has_function_privilege('anon', 'public.admin_create_card_variant(uuid,uuid,uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.admin_create_card_variant(uuid,uuid,uuid,uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.card_variant', 'INSERT') THEN
    RAISE EXCEPTION 'P2A-2267-TEST FAIL S1';
  END IF;

  -- S2
  PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_create_card_variant(v_card, v_type, NULL, NULL);
    RAISE EXCEPTION 'P2A-2267-TEST FAIL S2';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c_admin, 'role', 'authenticated')::text, true);

  -- I1 acabamento inativo (se existir algum)
  IF v_bad_type IS NOT NULL THEN
    BEGIN
      PERFORM public.admin_create_card_variant(v_card, v_bad_type, NULL, NULL);
      RAISE EXCEPTION 'P2A-2267-TEST FAIL I1';
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      IF v_err NOT LIKE 'ADMIN_CREATE_CARD_VARIANT_FINISH_INVALID%' THEN RAISE EXCEPTION 'P2A-2267-TEST FAIL I1: %', v_err; END IF;
    END;
  END IF;

  -- I2 duplicata exata de uma variante existente
  BEGIN
    PERFORM public.admin_create_card_variant(v_card, v_dup_type, v_dup_pp, v_dup_ec);
    RAISE EXCEPTION 'P2A-2267-TEST FAIL I2';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_CREATE_CARD_VARIANT_DUPLICATE%' THEN RAISE EXCEPTION 'P2A-2267-TEST FAIL I2: %', v_err; END IF;
  END;

  -- F1 + P1
  SELECT count(*) INTO v_logs FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_CREATED';
  SELECT count(*) INTO v_other_unlinked_before
    FROM public.pricing_product pp JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
   WHERE m.card_id <> v_card AND pp.card_variant_id IS NULL;
  v_t0 := clock_timestamp();
  v_res := public.admin_create_card_variant(v_card, v_type, NULL, NULL);
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  SELECT count(*) INTO v_other_unlinked_after
    FROM public.pricing_product pp JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
   WHERE m.card_id <> v_card AND pp.card_variant_id IS NULL;

  IF (SELECT variant_order FROM public.card_variant WHERE id = (v_res->>'card_variant_id')::uuid) <> v_max + 1
     OR (v_res->>'is_default')::boolean
     OR (SELECT count(*) FROM public.card_variant WHERE card_id = v_card AND is_default) <> 1 THEN
    RAISE EXCEPTION 'P2A-2267-TEST FAIL F1: %', v_res;
  END IF;
  IF (SELECT count(*) FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_CREATED') <> v_logs + 1
     OR NOT EXISTS (SELECT 1 FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_CREATED'
                      AND entity_type = 'CARD' AND entity_id = v_card AND actor_id = c_admin
                      AND (metadata->>'card_variant_id')::uuid = (v_res->>'card_variant_id')::uuid
                      AND metadata ? 'pricing') THEN
    RAISE EXCEPTION 'P2A-2267-TEST FAIL F1 log';
  END IF;
  IF v_res->'pricing'->>'status' NOT IN ('OK', 'NO_CANDIDATES')
     OR v_other_unlinked_after <> v_other_unlinked_before THEN
    RAISE EXCEPTION 'P2A-2267-TEST FAIL P1: % (outras cartas antes % depois %)', v_res->'pricing', v_other_unlinked_before, v_other_unlinked_after;
  END IF;

  -- I3 carta inativa
  UPDATE public.card SET is_active = false WHERE id = v_card;
  BEGIN
    PERFORM public.admin_create_card_variant(v_card, v_dup_type, v_dup_pp, v_dup_ec);
    RAISE EXCEPTION 'P2A-2267-TEST FAIL I3';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_CREATE_CARD_VARIANT_CARD_INACTIVE%' THEN RAISE EXCEPTION 'P2A-2267-TEST FAIL I3: %', v_err; END IF;
  END;

  RAISE EXCEPTION 'P2A-2267-TEST PASS card=% pricing=% tempo=% ms (S1 S2 I1 I2 I3 F1 P1) — tudo desfeito',
    v_card, v_res->'pricing', v_ms;
END
$t$;
