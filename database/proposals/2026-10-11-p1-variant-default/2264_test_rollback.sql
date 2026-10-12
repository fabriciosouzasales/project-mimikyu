/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2264-T - Testes da variante padrão manual (sempre desfeitos)
Versão......: 1.0
Status......: PROPOSTA — executar só com autorização de Fabrício.
Uso.........: depois da 2264 (ou junto dela, num único envio, como ensaio). O bloco SEMPRE
              termina em RAISE EXCEPTION: nada do que ele faz — nem a 2264, se enviada junto —
              fica gravado. Sucesso = mensagem 'P1-2264-TEST PASS ...'; qualquer outra
              mensagem é falha.
Cobre.......: segurança (não admin, anon, escrita direta), integridade (um padrão por carta,
              variante inexistente, carta inativa, no-op sem log), preservação (variante nova
              inserida depois não troca a escolha manual — trigger 2259), log MANUAL e tempo.
===============================================================================
*/
DO $t$
DECLARE
  c_admin  constant uuid := 'fe316458-49dd-44e1-aac0-f4b7604ef8f2';
  v_card   uuid;
  v_a      uuid;
  v_b      uuid;
  v_type   uuid;
  v_new    uuid;
  v_res    jsonb;
  v_n      int;
  v_logs   int;
  v_t0     timestamptz;
  v_ms     numeric;
  v_err    text;
BEGIN
  -- Fixture: uma das cartas ativas com empate (sem padrão) e >= 2 variantes.
  SELECT c.id INTO v_card
    FROM public.card c
   WHERE c.is_active
     AND NOT EXISTS (SELECT 1 FROM public.card_variant d WHERE d.card_id = c.id AND d.is_default)
     AND (SELECT count(*) FROM public.card_variant v WHERE v.card_id = c.id) >= 2
   ORDER BY c.id LIMIT 1;
  IF v_card IS NULL THEN RAISE EXCEPTION 'P1-2264-TEST FAIL: nenhuma carta sem padrão com 2+ variantes'; END IF;
  SELECT id INTO v_a FROM public.card_variant WHERE card_id = v_card ORDER BY variant_order LIMIT 1;
  SELECT id INTO v_b FROM public.card_variant WHERE card_id = v_card ORDER BY variant_order OFFSET 1 LIMIT 1;

  -- S1 privilégios
  IF has_function_privilege('anon', 'public.admin_set_card_variant_default(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.admin_set_card_variant_default(uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.card_variant', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.card_variant', 'INSERT') THEN
    RAISE EXCEPTION 'P1-2264-TEST FAIL S1: privilégios';
  END IF;

  -- S2 autenticado que não é admin
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.admin_set_card_variant_default(v_a);
    RAISE EXCEPTION 'P1-2264-TEST FAIL S2: não admin conseguiu';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', c_admin, 'role', 'authenticated')::text, true);

  -- I1 variante inexistente
  BEGIN
    PERFORM public.admin_set_card_variant_default(gen_random_uuid());
    RAISE EXCEPTION 'P1-2264-TEST FAIL I1';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_SET_CARD_VARIANT_DEFAULT_NOT_FOUND%' THEN RAISE EXCEPTION 'P1-2264-TEST FAIL I1: %', v_err; END IF;
  END;

  -- F1 carta sem padrão recebe padrão (+ tempo)
  SELECT count(*) INTO v_logs FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_DEFAULT_SET';
  v_t0 := clock_timestamp();
  v_res := public.admin_set_card_variant_default(v_a);
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  SELECT count(*) INTO v_n FROM public.card_variant WHERE card_id = v_card AND is_default;
  IF NOT (v_res->>'changed')::boolean OR v_n <> 1
     OR NOT (SELECT is_default FROM public.card_variant WHERE id = v_a) THEN
    RAISE EXCEPTION 'P1-2264-TEST FAIL F1: %', v_res;
  END IF;

  -- F2 troca mantém exatamente um padrão
  v_res := public.admin_set_card_variant_default(v_b);
  SELECT count(*) INTO v_n FROM public.card_variant WHERE card_id = v_card AND is_default;
  IF v_n <> 1 OR NOT (SELECT is_default FROM public.card_variant WHERE id = v_b)
     OR (v_res->>'previous_card_variant_id')::uuid IS DISTINCT FROM v_a THEN
    RAISE EXCEPTION 'P1-2264-TEST FAIL F2: %', v_res;
  END IF;

  -- F3 mesma escolha: no-op, sem log
  v_res := public.admin_set_card_variant_default(v_b);
  IF (v_res->>'changed')::boolean THEN RAISE EXCEPTION 'P1-2264-TEST FAIL F3: %', v_res; END IF;

  -- A1 log: 2 linhas MANUAL, a última com anterior = A
  IF (SELECT count(*) FROM public.catalog_admin_action_log WHERE action = 'CARD_VARIANT_DEFAULT_SET') <> v_logs + 2
     OR NOT EXISTS (SELECT 1 FROM public.catalog_admin_action_log
                     WHERE action = 'CARD_VARIANT_DEFAULT_SET' AND entity_type = 'CARD' AND entity_id = v_card
                       AND actor_id = c_admin AND metadata->>'source' = 'MANUAL'
                       AND (metadata->>'card_variant_id')::uuid = v_b
                       AND (metadata->>'previous_card_variant_id')::uuid = v_a
                       AND coalesce(metadata->>'label', '') <> '') THEN
    RAISE EXCEPTION 'P1-2264-TEST FAIL A1: log';
  END IF;

  -- P1 variante nova inserida depois (caminho do trigger 2259) não troca a escolha manual.
  --    Tipo já usado no mesmo Set (consistência de Game) e ainda ausente nesta carta sem perfis.
  SELECT v.variant_type_id INTO v_type
    FROM public.card_variant v JOIN public.card c ON c.id = v.card_id
   WHERE c.card_set_id = (SELECT card_set_id FROM public.card WHERE id = v_card)
     AND NOT EXISTS (SELECT 1 FROM public.card_variant x
                      WHERE x.card_id = v_card AND x.variant_type_id = v.variant_type_id
                        AND x.printing_profile_id IS NULL AND x.edition_context_profile_id IS NULL)
   LIMIT 1;
  IF v_type IS NULL THEN
    SELECT t.id INTO v_type FROM public.card_variant_type t WHERE t.code = 'STANDARD'
       AND NOT EXISTS (SELECT 1 FROM public.card_variant x WHERE x.card_id = v_card AND x.variant_type_id = t.id
                         AND x.printing_profile_id IS NULL AND x.edition_context_profile_id IS NULL);
  END IF;
  IF v_type IS NULL THEN RAISE EXCEPTION 'P1-2264-TEST FAIL P1: sem tipo livre para o teste'; END IF;
  INSERT INTO public.card_variant (card_id, variant_type_id, variant_order)
  VALUES (v_card, v_type, (SELECT max(variant_order) + 1 FROM public.card_variant WHERE card_id = v_card))
  RETURNING id INTO v_new;
  IF NOT (SELECT is_default FROM public.card_variant WHERE id = v_b)
     OR (SELECT is_default FROM public.card_variant WHERE id = v_new)
     OR (SELECT count(*) FROM public.card_variant WHERE card_id = v_card AND is_default) <> 1 THEN
    RAISE EXCEPTION 'P1-2264-TEST FAIL P1: escolha manual não preservada';
  END IF;

  -- I2 carta inativa é recusada
  UPDATE public.card SET is_active = false WHERE id = v_card;
  BEGIN
    PERFORM public.admin_set_card_variant_default(v_a);
    RAISE EXCEPTION 'P1-2264-TEST FAIL I2';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    IF v_err NOT LIKE 'ADMIN_SET_CARD_VARIANT_DEFAULT_CARD_INACTIVE%' THEN RAISE EXCEPTION 'P1-2264-TEST FAIL I2: %', v_err; END IF;
  END;

  RAISE EXCEPTION 'P1-2264-TEST PASS card=% tempo_1a_chamada=% ms (S1 S2 I1 I2 F1 F2 F3 A1 P1) — tudo desfeito', v_card, v_ms;
END
$t$;
