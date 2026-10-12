/*
===============================================================================
Query.......: 2274-T - Testes da P3a (2271–2274), sempre desfeitos
Uso.........: ensaio = 2271 + 2272 + 2273 + 2274 + este arquivo num único envio; ou sozinho depois
              da aplicação. Termina SEMPRE em RAISE EXCEPTION: nada fica gravado.
              Sucesso = 'P3A-TEST PASS ...'.
Fixture.....: um job STAGED fictício (TCGDEX) num Card Set com referência externa ativa e sem job
              ativo, com 4 linhas de cartas diferentes do Set:
                R1, R2  type 'normal' + stamp 'P3A TEST STAMP'   (item desconhecido)
                R3      type 'normal'                            (controle, não contém o item)
                R4      type 'normal' + stamp 'P3A TEST STAMP 2' (para o perfil novo)
Cobre.......: S1 privilégios; S2 não-admin (explain, preview, resolve, perfil);
              E1 diagnóstico: item UNRECOGNIZED, eixos admitidos, outcome B, sem presumir eixo;
              P1 prévia de Contexto (Set): ok, 2 linhas, 2 passam a válidas, nada gravado (linhas, job, mapeamentos, log);
              W1 resolver Contexto (Set): mapeamento com escopo do Set, R1/R2 VALID com o perfil,
                 R3 intocada, contadores do job, log;
              N1 NO_CHANGE; C1 conflito de eixos (prévia de Impressão do mesmo item: ok=false +
                 EDITION_CONTEXT_ACTIVE; trava MV002 na escrita direta);
              G1 global com override de Set: não substitui o específico, 0 linhas atingidas,
                 diagnóstico continua mostrando o específico;
              K1 perfil novo: item mapeado para composição sem perfil → R4 NEEDS_REVIEW
                 (NEEDS_REVIEW_NO_EC_PROFILE); criar o perfil → R4 VALID com o perfil novo, log;
              X1 Contexto do mesmo item em outro Set não é barrado pela trava;
              I1 identidade preservada: card_variant e mapeamentos de Impressão/acabamento intactos.
===============================================================================
*/
DO $t$
DECLARE
  c_admin constant uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  c_tok   constant text := 'P3A TEST STAMP';
  c_tok2  constant text := 'P3A TEST STAMP 2';
  v_set uuid; v_ext text; v_game uuid; v_src uuid;
  v_cards uuid[]; v_job uuid; v_r1 uuid; v_r2 uuid; v_r3 uuid; v_r4 uuid;
  v_trait uuid; v_profile uuid; v_trait_b uuid; v_pair uuid[]; v_ptrait uuid;
  v_cv_before bigint; v_pm_before bigint; v_vm_before bigint; v_logs bigint;
  v_res jsonb; v_rec record; v_err text; v_n int; v_new_profile uuid;
BEGIN
  SELECT id INTO v_src FROM public.asset_source WHERE code = 'TCGDEX';

  -- Fixture: Set com referência externa ativa, sem job ativo, ≥4 cartas ativas, e acabamento
  -- 'normal' mapeado para ele.
  SELECT cs.id, r.external_set_id, e.game_id INTO v_set, v_ext, v_game
    FROM public.card_set cs
    JOIN public.expansion e ON e.id = cs.expansion_id
    JOIN public.card_set_external_reference r ON r.card_set_id = cs.id AND r.asset_source_id = v_src AND r.is_active
   WHERE NOT EXISTS (SELECT 1 FROM public.catalog_variant_import_job j
                      WHERE j.card_set_id = cs.id AND j.status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING'))
     AND (SELECT count(*) FROM public.card c WHERE c.card_set_id = cs.id AND c.is_active) >= 4
     AND internal.lookup_variant_type_for_row(e.game_id, v_src, cs.id, 'NORMAL', NULL, NULL, '{}'::text[]) IS NOT NULL
   ORDER BY cs.id LIMIT 1;
  IF v_set IS NULL THEN RAISE EXCEPTION 'P3A-TEST FAIL: sem fixture de Set'; END IF;
  v_cards := ARRAY(SELECT c.id FROM public.card c WHERE c.card_set_id = v_set AND c.is_active ORDER BY c.id LIMIT 4);

  -- Característica de Contexto com perfil ativo de composição única; e um par sem perfil.
  SELECT t.id, p.id INTO v_trait, v_profile
    FROM public.card_edition_context_profile p
    JOIN public.card_edition_context_trait t ON t.id = p.traits_signature[1]
   WHERE p.game_id = v_game AND p.is_active AND t.is_active AND cardinality(p.traits_signature) = 1
   ORDER BY p.display_order LIMIT 1;
  SELECT t.id INTO v_trait_b FROM public.card_edition_context_trait t
   WHERE t.game_id = v_game AND t.is_active AND t.id <> v_trait
     AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile p
                      WHERE p.game_id = v_game
                        AND p.traits_signature = ARRAY(SELECT x FROM unnest(ARRAY[v_trait, t.id]) x ORDER BY x))
   ORDER BY t.display_order LIMIT 1;
  v_pair := ARRAY(SELECT x FROM unnest(ARRAY[v_trait, v_trait_b]) x ORDER BY x);
  SELECT t.id INTO v_ptrait FROM public.card_printing_trait t WHERE t.game_id = v_game AND t.is_active ORDER BY t.display_order LIMIT 1;
  IF v_trait IS NULL OR v_trait_b IS NULL OR v_ptrait IS NULL THEN RAISE EXCEPTION 'P3A-TEST FAIL: sem fixture de características'; END IF;

  SELECT count(*) INTO v_cv_before FROM public.card_variant;
  SELECT count(*) INTO v_pm_before FROM public.card_printing_external_mapping;
  SELECT count(*) INTO v_vm_before FROM public.card_variant_type_external_mapping;

  INSERT INTO public.catalog_variant_import_job (card_set_id, source, external_set_id, status)
  VALUES (v_set, 'TCGDEX', v_ext, 'STAGED') RETURNING id INTO v_job;
  INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status)
  VALUES (v_job, v_cards[1], jsonb_build_object('type','normal','foil',null,'subtype',null,'stamp',jsonb_build_array(lower(c_tok))), '{}', 'NEEDS_REVIEW', 'NEW', 'PENDING', 'PENDING')
  RETURNING id INTO v_r1;
  INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status)
  VALUES (v_job, v_cards[2], jsonb_build_object('type','normal','foil',null,'subtype',null,'stamp',jsonb_build_array(lower(c_tok))), '{}', 'NEEDS_REVIEW', 'NEW', 'PENDING', 'PENDING')
  RETURNING id INTO v_r2;
  INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status)
  VALUES (v_job, v_cards[3], jsonb_build_object('type','normal','foil',null,'subtype',null,'stamp',null), '{}', 'NEEDS_REVIEW', 'NEW', 'PENDING', 'PENDING')
  RETURNING id INTO v_r3;
  INSERT INTO public.catalog_variant_import_row (job_id, card_id, raw_data, normalized_data, validation_status, match_status, decision_status, persistence_status)
  VALUES (v_job, v_cards[4], jsonb_build_object('type','normal','foil',null,'subtype',null,'stamp',jsonb_build_array(lower(c_tok2))), '{}', 'NEEDS_REVIEW', 'NEW', 'PENDING', 'PENDING')
  RETURNING id INTO v_r4;

  -- S1 privilégios
  IF has_function_privilege('anon', 'public.admin_explain_catalog_variant_import_row(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_preview_catalog_variant_import_axis_mapping(uuid,text,text,text,uuid[],text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_resolve_catalog_variant_import_edition_context_mapping(uuid,text,text,uuid[],text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_create_card_edition_context_profile_with_backfill(text,text,text,integer,uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.admin_resolve_catalog_variant_import_edition_context_mapping(uuid,text,text,uuid[],text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'internal.reconcile_variant_import_rows(uuid[])', 'EXECUTE')
     OR has_function_privilege('authenticated', 'internal.variant_import_rows_with_token(uuid,uuid,text,text,text,text,boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'internal.guard_axis_mapping_overlap()', 'EXECUTE') THEN
    RAISE EXCEPTION 'P3A-TEST FAIL S1';
  END IF;

  -- S2 não-admin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  BEGIN PERFORM public.admin_explain_catalog_variant_import_row(v_r1); RAISE EXCEPTION 'P3A-TEST FAIL S2 explain';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.admin_preview_catalog_variant_import_axis_mapping(v_r1, 'EDITION_CONTEXT', 'stamp', c_tok, ARRAY[v_trait], 'SOURCE_SET'); RAISE EXCEPTION 'P3A-TEST FAIL S2 preview';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.admin_resolve_catalog_variant_import_edition_context_mapping(v_r1, 'stamp', c_tok, ARRAY[v_trait], 'SOURCE_SET'); RAISE EXCEPTION 'P3A-TEST FAIL S2 resolve';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.admin_create_card_edition_context_profile_with_backfill('P3A_X', 'x', NULL, 999999, v_pair); RAISE EXCEPTION 'P3A-TEST FAIL S2 profile';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c_admin, 'role', 'authenticated')::text, true);

  -- E1 diagnóstico
  v_res := public.admin_explain_catalog_variant_import_row(v_r1);
  IF v_res ->> 'outcome' <> 'B'
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_res -> 'items') i
                     WHERE i ->> 'field' = 'stamp' AND i ->> 'normalized' = c_tok AND i ->> 'status' = 'UNRECOGNIZED'
                       AND (i -> 'allowed_axes') @> '["FINISH","PRINTING","EDITION_CONTEXT"]'::jsonb
                       AND i -> 'printing_mapping' = 'null'::jsonb AND i -> 'edition_context_mapping' = 'null'::jsonb)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_res -> 'items') i
                     WHERE i ->> 'field' = 'type' AND (i -> 'allowed_axes') = '["FINISH"]'::jsonb) THEN
    RAISE EXCEPTION 'P3A-TEST FAIL E1: %', v_res;
  END IF;

  -- P1 prévia (nada gravado)
  SELECT count(*) INTO v_logs FROM public.catalog_admin_action_log;
  SELECT md5(string_agg(r.id::text || r.validation_status || r.normalized_data::text, '|' ORDER BY r.id))
         || coalesce((SELECT valid_rows::text FROM public.catalog_variant_import_job WHERE id = v_job), '-')
    INTO v_err FROM public.catalog_variant_import_row r WHERE r.job_id = v_job;
  v_res := public.admin_preview_catalog_variant_import_axis_mapping(v_r1, 'EDITION_CONTEXT', 'stamp', lower(c_tok), ARRAY[v_trait], 'SOURCE_SET');
  IF NOT (v_res ->> 'ok')::boolean
     OR (v_res -> 'impact' ->> 'rows_touched')::int <> 2
     OR (v_res -> 'impact' ->> 'newly_resolved')::int <> 2
     OR (v_res -> 'target' -> 'profile' ->> 'id')::uuid <> v_profile
     OR v_res ->> 'external_set_id' <> v_ext
     OR (SELECT validation_status FROM public.catalog_variant_import_row WHERE id = v_r1) <> 'NEEDS_REVIEW'
     OR EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping m WHERE m.normalized_token = c_tok)
     OR (SELECT count(*) FROM public.catalog_admin_action_log) <> v_logs
     OR (SELECT md5(string_agg(r.id::text || r.validation_status || r.normalized_data::text, '|' ORDER BY r.id))
                || coalesce((SELECT valid_rows::text FROM public.catalog_variant_import_job WHERE id = v_job), '-')
           FROM public.catalog_variant_import_row r WHERE r.job_id = v_job) IS DISTINCT FROM v_err THEN
    RAISE EXCEPTION 'P3A-TEST FAIL P1: %', v_res;
  END IF;
  v_err := NULL;

  -- W1 resolver Contexto no escopo do Set
  SELECT * INTO v_rec FROM public.admin_resolve_catalog_variant_import_edition_context_mapping(v_r1, 'stamp', lower(c_tok), ARRAY[v_trait], 'SOURCE_SET');
  IF v_rec.scope <> 'SOURCE_SET' OR v_rec.external_set_id <> v_ext OR v_rec.rows_touched <> 2 OR v_rec.rows_revalidated <> 2
     OR (SELECT count(*) FROM public.catalog_variant_import_row
          WHERE id IN (v_r1, v_r2) AND validation_status = 'VALID'
            AND normalized_data ->> 'edition_context_profile_id' = v_profile::text) <> 2
     OR (SELECT validation_status FROM public.catalog_variant_import_row WHERE id = v_r3) <> 'NEEDS_REVIEW'
     OR (SELECT valid_rows FROM public.catalog_variant_import_job WHERE id = v_job) <> 2
     OR NOT EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping m
                     WHERE m.id = v_rec.mapping_id AND m.external_set_id = v_ext AND m.is_active)
     OR NOT EXISTS (SELECT 1 FROM public.catalog_admin_action_log l
                     WHERE l.action = 'CARD_EDITION_CONTEXT_EXTERNAL_MAPPING_CREATED' AND l.entity_id = v_rec.mapping_id
                       AND l.actor_id = c_admin) THEN
    RAISE EXCEPTION 'P3A-TEST FAIL W1: %', row_to_json(v_rec);
  END IF;

  -- N1 mesma composição no mesmo escopo
  BEGIN
    PERFORM public.admin_resolve_catalog_variant_import_edition_context_mapping(v_r1, 'stamp', c_tok, ARRAY[v_trait], 'SOURCE_SET');
    RAISE EXCEPTION 'P3A-TEST FAIL N1';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_RESOLVE_EC_MAPPING_NO_CHANGE%' THEN RAISE EXCEPTION 'P3A-TEST FAIL N1: %', v_err; END IF;
  END;

  -- C1 conflito entre eixos: prévia de Impressão do mesmo item recusa; escrita direta barrada.
  v_res := public.admin_preview_catalog_variant_import_axis_mapping(v_r1, 'PRINTING', 'stamp', c_tok, ARRAY[v_ptrait], NULL);
  IF (v_res ->> 'ok')::boolean
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_res -> 'conflicts') c WHERE c ->> 'code' = 'EDITION_CONTEXT_ACTIVE')
     OR v_res ->> 'error' NOT LIKE '%AXIS_MAPPING_OVERLAP%' THEN
    RAISE EXCEPTION 'P3A-TEST FAIL C1 preview: %', v_res;
  END IF;
  BEGIN
    INSERT INTO public.card_printing_external_mapping (game_id, asset_source_id, raw_field, normalized_token, external_token, is_active)
    VALUES (v_game, v_src, 'stamp', c_tok, c_tok, true);
    RAISE EXCEPTION 'P3A-TEST FAIL C1 trava';
  EXCEPTION WHEN SQLSTATE 'MV002' THEN NULL;
  END;

  -- G1 global com override específico do Set: não substitui o específico, não atinge este Set.
  SELECT * INTO v_rec FROM public.admin_resolve_catalog_variant_import_edition_context_mapping(v_r1, 'stamp', c_tok, v_pair, 'GLOBAL');
  IF v_rec.superseded_mapping_id IS NOT NULL OR v_rec.rows_touched <> 0
     OR (SELECT count(*) FROM public.card_edition_context_external_mapping m
          WHERE m.normalized_token = c_tok AND m.is_active) <> 2 THEN
    RAISE EXCEPTION 'P3A-TEST FAIL G1: %', row_to_json(v_rec);
  END IF;
  v_res := public.admin_explain_catalog_variant_import_row(v_r1);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_res -> 'items') i
                  WHERE i ->> 'field' = 'stamp' AND i -> 'edition_context_mapping' ->> 'scope' = 'SOURCE_SET'
                    AND i ->> 'status' = 'EDITION_CONTEXT')
     OR v_res ->> 'outcome' <> 'A' THEN
    RAISE EXCEPTION 'P3A-TEST FAIL G1 explain: %', v_res;
  END IF;

  -- X1 Contexto do mesmo item em OUTRO Set: legítimo, a trava MV002 não pode barrar.
  BEGIN
    INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token, is_active)
    VALUES (v_game, v_src, 'p3a-other-set', 'stamp', c_tok, true);
  EXCEPTION WHEN SQLSTATE 'MV002' THEN
    RAISE EXCEPTION 'P3A-TEST FAIL X1: Contexto em outro Set barrado pela trava de eixos';
  END;

  -- K1 composição sem perfil → pendente; criar o perfil → válida
  SELECT * INTO v_rec FROM public.admin_resolve_catalog_variant_import_edition_context_mapping(v_r4, 'stamp', c_tok2, v_pair, 'SOURCE_SET');
  IF v_rec.rows_touched <> 1 OR v_rec.rows_still_pending <> 1
     OR (public.admin_explain_catalog_variant_import_row(v_r4) -> 'edition_context' ->> 'state') <> 'NEEDS_REVIEW_NO_EC_PROFILE' THEN
    RAISE EXCEPTION 'P3A-TEST FAIL K1 pendente: %', row_to_json(v_rec);
  END IF;
  SELECT * INTO v_rec FROM public.admin_create_card_edition_context_profile_with_backfill(
    'P3A_TEST_PROFILE', 'Teste P3a', NULL,
    (SELECT max(display_order) + 1 FROM public.card_edition_context_profile WHERE game_id = v_game), v_pair);
  v_new_profile := v_rec.profile_id;
  IF v_rec.traits_signature IS DISTINCT FROM v_pair OR v_rec.rows_revalidated < 1
     OR (SELECT validation_status FROM public.catalog_variant_import_row WHERE id = v_r4) <> 'VALID'
     OR (SELECT normalized_data ->> 'edition_context_profile_id' FROM public.catalog_variant_import_row WHERE id = v_r4) <> v_new_profile::text
     OR NOT EXISTS (SELECT 1 FROM public.catalog_admin_action_log l
                     WHERE l.action = 'CARD_EDITION_CONTEXT_PROFILE_CREATED' AND l.entity_id = v_new_profile) THEN
    RAISE EXCEPTION 'P3A-TEST FAIL K1 perfil: %', row_to_json(v_rec);
  END IF;
  BEGIN
    PERFORM public.admin_create_card_edition_context_profile_with_backfill('P3A_TEST_PROFILE_DUP', 'Dup', NULL, 999998, v_pair);
    RAISE EXCEPTION 'P3A-TEST FAIL K1 duplicado';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_CREATE_EC_PROFILE_DUPLICATE_SIGNATURE%' THEN RAISE EXCEPTION 'P3A-TEST FAIL K1 duplicado: %', v_err; END IF;
  END;

  -- I1 identidade preservada
  IF (SELECT count(*) FROM public.card_variant) <> v_cv_before
     OR (SELECT count(*) FROM public.card_printing_external_mapping) <> v_pm_before
     OR (SELECT count(*) FROM public.card_variant_type_external_mapping) <> v_vm_before THEN
    RAISE EXCEPTION 'P3A-TEST FAIL I1';
  END IF;

  RAISE EXCEPTION 'P3A-TEST PASS set=% ext=% (S1 S2 E1 P1 W1 N1 C1 G1 X1 K1 I1) — tudo desfeito', v_set, v_ext;
END
$t$;
