/*
===============================================================================
Query.......: 2270-T - Testes da desativação/reativação de Card Variant (sempre desfeitos)
Uso.........: ensaio = 2268 + 2269 + 2270 + este arquivo num único envio; ou sozinho depois da
              aplicação. Termina SEMPRE em RAISE EXCEPTION: nada fica gravado.
              Sucesso = 'P2B-TEST PASS ...'.
Cobre.......: S1 privilégios; S2 não-admin; F1 desativar (estado, log, idempotência, vínculos de
              preço intactos); G1 trava de vínculo novo + linhas antigas intactas; P1 resolvedor não
              liga nem redireciona para inativa; D1 padrão manual recusa inativa + escolha automática
              ignora inativa + view 2266 coerente; I1 duplicata inativa na 2267 + nenhuma outra função
              grava is_active; B1 padrão; B2 última ativa; C1 CHECK padrão-ativa; F2 reativar e
              AXIS_INACTIVE.
              A repetição do trigger de vínculo de preço (MV001) só ocorre sob concorrência real; é
              coberta por inspeção (2269 §2) e pela trava G1, não por este teste de sessão única.
===============================================================================
*/
DO $t$
DECLARE
  c_admin constant uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_card uuid; v_x uuid; v_def uuid; v_pp uuid; v_other_pp uuid;
  v_type uuid; v_pp_prof uuid; v_ec uuid;
  v_linked_before int; v_linked_after int; v_logs int;
  v_res jsonb; v_err text; v_r record; v_view int; v_direct int;
  v_t0 timestamptz; v_ms numeric;
BEGIN
  -- Fixture: carta ativa com exatamente 2 variantes (padrão + X); X tem produtos de preço ligados e
  -- o resolvedor, hoje, liga ao menos um deles a X por regra aceita.
  FOR v_r IN
    SELECT v.id, v.card_id
      FROM public.card_variant v
      JOIN public.card c ON c.id = v.card_id AND c.is_active
     WHERE NOT v.is_default AND v.is_active
       AND (SELECT count(*) FROM public.card_variant w WHERE w.card_id = v.card_id) = 2
       AND EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = v.card_id AND d.is_default)
       AND EXISTS (SELECT 1 FROM public.pricing_product pp WHERE pp.card_variant_id = v.id)
     ORDER BY v.id
     LIMIT 200
  LOOP
    SELECT r.pricing_product_id INTO v_pp
      FROM internal.resolve_pricing_product_card_variant(
             ARRAY(SELECT pp.id FROM public.pricing_product pp WHERE pp.card_variant_id = v_r.id)) r
     WHERE r.card_variant_id = v_r.id
       AND r.resolution IN ('UNIQUE', 'UNIQUE_FALLBACK', 'UNIQUE_INHERENT_CONTEXT', 'UNIQUE_SINGLE_PRINTING')
     LIMIT 1;
    IF v_pp IS NOT NULL THEN
      v_x := v_r.id; v_card := v_r.card_id;
      EXIT;
    END IF;
  END LOOP;
  IF v_x IS NULL THEN RAISE EXCEPTION 'P2B-TEST FAIL: sem fixture'; END IF;
  SELECT id INTO v_def FROM public.card_variant WHERE card_id = v_card AND is_default;
  SELECT variant_type_id, printing_profile_id, edition_context_profile_id INTO v_type, v_pp_prof, v_ec
    FROM public.card_variant WHERE id = v_x;
  SELECT count(*) INTO v_linked_before FROM public.pricing_product WHERE card_variant_id = v_x;
  SELECT pp.id INTO v_other_pp
    FROM public.pricing_product pp
    JOIN public.pricing_card_mapping m ON m.id = pp.pricing_card_mapping_id
   WHERE m.card_id = v_card AND pp.card_variant_id IS DISTINCT FROM v_x
   LIMIT 1;

  -- S1
  IF has_function_privilege('anon', 'public.admin_set_card_variant_active(uuid,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.admin_set_card_variant_active(uuid,boolean)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.card_variant', 'UPDATE')
     OR has_function_privilege('authenticated', 'internal.guard_card_variant_reference_active()', 'EXECUTE')
     OR (SELECT count(*) FROM pg_trigger WHERE tgname = 'trg_guard_card_variant_active' AND NOT tgisinternal) <> 4 THEN
    RAISE EXCEPTION 'P2B-TEST FAIL S1';
  END IF;

  -- S2
  PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_set_card_variant_active(v_x, false);
    RAISE EXCEPTION 'P2B-TEST FAIL S2';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c_admin, 'role', 'authenticated')::text, true);

  -- B1 padrão não pode ser desativada
  BEGIN
    PERFORM public.admin_set_card_variant_active(v_def, false);
    RAISE EXCEPTION 'P2B-TEST FAIL B1';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_SET_CARD_VARIANT_ACTIVE_DEFAULT%' THEN RAISE EXCEPTION 'P2B-TEST FAIL B1: %', v_err; END IF;
  END;

  -- C1 CHECK: nem escrita direta deixa a padrão inativa
  BEGIN
    UPDATE public.card_variant SET is_active = false WHERE id = v_def;
    RAISE EXCEPTION 'P2B-TEST FAIL C1';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- F1 desativar X
  SELECT count(*) INTO v_logs FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_DEACTIVATED';
  v_t0 := clock_timestamp();
  v_res := public.admin_set_card_variant_active(v_x, false);
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  SELECT count(*) INTO v_linked_after FROM public.pricing_product WHERE card_variant_id = v_x;
  IF NOT (v_res->>'changed')::boolean
     OR (SELECT is_active FROM public.card_variant WHERE id = v_x)
     OR (v_res->>'linked_pricing_products')::int <> v_linked_before
     OR v_linked_after <> v_linked_before
     OR (SELECT count(*) FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_DEACTIVATED') <> v_logs + 1
     OR NOT EXISTS (SELECT 1 FROM public.catalog_admin_action_log
                     WHERE action = 'CARD_VARIANT_DEACTIVATED' AND entity_type = 'CARD' AND entity_id = v_card
                       AND actor_id = c_admin AND (metadata->>'card_variant_id')::uuid = v_x) THEN
    RAISE EXCEPTION 'P2B-TEST FAIL F1: %', v_res;
  END IF;
  -- idempotência
  v_res := public.admin_set_card_variant_active(v_x, false);
  IF (v_res->>'changed')::boolean
     OR (SELECT count(*) FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_DEACTIVATED') <> v_logs + 1 THEN
    RAISE EXCEPTION 'P2B-TEST FAIL F1 idempotência: %', v_res;
  END IF;

  -- G1 trava: vínculo NOVO para X é recusado; linhas já ligadas a X seguem atualizáveis
  IF v_other_pp IS NOT NULL THEN
    BEGIN
      UPDATE public.pricing_product SET card_variant_id = v_x WHERE id = v_other_pp;
      RAISE EXCEPTION 'P2B-TEST FAIL G1';
    EXCEPTION WHEN SQLSTATE 'MV001' THEN NULL;
    END;
  END IF;
  UPDATE public.pricing_product SET is_active = is_active WHERE card_variant_id = v_x;  -- não muda card_variant_id
  IF (SELECT count(*) FROM public.pricing_product WHERE card_variant_id = v_x) <> v_linked_before THEN
    RAISE EXCEPTION 'P2B-TEST FAIL G1 histórico';
  END IF;

  -- P1 resolvedor: o produto que antes ia para X agora é TARGET_INACTIVE e não vai para outra variante
  SELECT r.* INTO v_r FROM internal.resolve_pricing_product_card_variant(ARRAY[v_pp]) r;
  IF v_r.resolution <> 'TARGET_INACTIVE' OR v_r.card_variant_id IS NOT NULL THEN
    RAISE EXCEPTION 'P2B-TEST FAIL P1: % %', v_r.resolution, v_r.card_variant_id;
  END IF;

  -- D1 padrão manual recusa inativa
  BEGIN
    PERFORM public.admin_set_card_variant_default(v_x);
    RAISE EXCEPTION 'P2B-TEST FAIL D1';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_SET_CARD_VARIANT_DEFAULT_INACTIVE%' THEN RAISE EXCEPTION 'P2B-TEST FAIL D1: %', v_err; END IF;
  END;

  -- I1 duplicata inativa na 2267
  BEGIN
    PERFORM public.admin_create_card_variant(v_card, v_type, v_pp_prof, v_ec);
    RAISE EXCEPTION 'P2B-TEST FAIL I1';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_CREATE_CARD_VARIANT_DUPLICATE_INACTIVE%' THEN RAISE EXCEPTION 'P2B-TEST FAIL I1: %', v_err; END IF;
  END;
  -- I1 nenhuma outra função grava is_active de card_variant
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'internal')
                AND p.proname <> 'admin_set_card_variant_active'
                AND p.prosrc ~* 'update\s+(public\.)?card_variant\s+(\w+\s+)?set[^;]*\mis_active\M') THEN
    RAISE EXCEPTION 'P2B-TEST FAIL I1: outra função grava card_variant.is_active';
  END IF;

  -- B2 última ativa + D1 escolha automática: tira a padrão (escrita direta de teste) e tenta
  --    desativar a única ativa que sobrou
  UPDATE public.card_variant SET is_default = false WHERE id = v_def;
  IF EXISTS (SELECT 1 FROM internal.pick_card_variant_default(ARRAY[v_card]) w WHERE w.card_variant_id = v_x) THEN
    RAISE EXCEPTION 'P2B-TEST FAIL D1 pick';
  END IF;
  SELECT count(*) INTO v_view FROM public.catalog_card_variant_default_pending;
  SELECT count(*) INTO v_direct
    FROM public.card c
   WHERE c.is_active
     AND EXISTS (SELECT 1 FROM public.card_variant v WHERE v.card_id = c.id AND v.is_active)
     AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = c.id AND d.is_default);
  IF v_view <> v_direct OR NOT EXISTS (SELECT 1 FROM public.catalog_card_variant_default_pending WHERE card_id = v_card) THEN
    RAISE EXCEPTION 'P2B-TEST FAIL D1 view: % vs %', v_view, v_direct;
  END IF;
  BEGIN
    PERFORM public.admin_set_card_variant_active(v_def, false);
    RAISE EXCEPTION 'P2B-TEST FAIL B2';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_SET_CARD_VARIANT_ACTIVE_LAST_ACTIVE%' THEN RAISE EXCEPTION 'P2B-TEST FAIL B2: %', v_err; END IF;
  END;
  UPDATE public.card_variant SET is_default = true WHERE id = v_def;

  -- F2 reativar: bloqueado com acabamento desativado; liberado depois
  UPDATE public.card_variant_type SET is_active = false WHERE id = v_type;
  BEGIN
    PERFORM public.admin_set_card_variant_active(v_x, true);
    RAISE EXCEPTION 'P2B-TEST FAIL F2 axis';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_SET_CARD_VARIANT_ACTIVE_AXIS_INACTIVE%' THEN RAISE EXCEPTION 'P2B-TEST FAIL F2 axis: %', v_err; END IF;
  END;
  UPDATE public.card_variant_type SET is_active = true WHERE id = v_type;
  v_res := public.admin_set_card_variant_active(v_x, true);
  IF NOT (v_res->>'changed')::boolean
     OR NOT (SELECT is_active FROM public.card_variant WHERE id = v_x)
     OR NOT EXISTS (SELECT 1 FROM public.catalog_admin_action_log
                     WHERE action = 'CARD_VARIANT_REACTIVATED' AND (metadata->>'card_variant_id')::uuid = v_x) THEN
    RAISE EXCEPTION 'P2B-TEST FAIL F2: %', v_res;
  END IF;
  SELECT r.* INTO v_r FROM internal.resolve_pricing_product_card_variant(ARRAY[v_pp]) r;
  IF v_r.card_variant_id IS DISTINCT FROM v_x THEN
    RAISE EXCEPTION 'P2B-TEST FAIL F2 resolvedor depois de reativar: % %', v_r.resolution, v_r.card_variant_id;
  END IF;

  RAISE EXCEPTION 'P2B-TEST PASS card=% variante=% precos_ligados=% tempo_desativar=% ms (S1 S2 B1 C1 F1 G1 P1 D1 I1 B2 F2) — tudo desfeito',
    v_card, v_x, v_linked_before, v_ms;
END
$t$;
