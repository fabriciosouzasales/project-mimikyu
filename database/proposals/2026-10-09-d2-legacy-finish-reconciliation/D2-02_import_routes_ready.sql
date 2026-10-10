/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: D2-02 - Rotas de importação: SET-LOGO / PIKACHU-TAIL no eixo certo,
              remoção das rotas legadas e desativação dos tipos sem variante
Versão......: 1.0
Status......: PRONTA — v_apply = false (dry-run, desfaz tudo) / true (aplica)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: D2 parte 2 aprovada por Fabrício em 2026-10-09 (A–E + SV5 galáxia = GALAXY_HOLO).

Escreve
  A  23 mappings EC por coleção  stamp SET-LOGO -> ARTWORK_SET_LOGO (coleções fora de EX
     que têm o carimbo; dp1/svp/swsh9 já existiam).
  B  12 mappings de Finish por coleção, ex11..ex16: NORMAL|{SET-LOGO} e HOLO|{SET-LOGO}
     -> REVERSE_HOLO (mesmo padrão H2 de ex7..ex10).
  C  1 variante SV5 (holo galaxy + set-logo): COSMOS_HOLO -> GALAXY_HOLO (+ ARTWORK_SET_LOGO).
  D  1 mapping EC basep  stamp PIKACHU-TAIL -> CAMPAIGN_PIKACHU_WORLD_2000.
  E  remove os 69 mappings de Finish legados (6 SET_LOGO_*, 1 PIKACHU, 62 já mortos)
     e desativa 63 tipos legados sem variante. STAFF_HOLO e SET_LOGO_REVERSE ficam
     ATIVOS: 18 identidades CONFIRMED de Pricing apontam para eles (Pricing 80).

Prova (fail-loud)
  Re-resolve, ANTES e DEPOIS, toda linha de staging com stamp/foil e variante persistida
  (resolve_variant_row_axes + lookup_variant_type_for_row) e compara com a identidade
  gravada em card_variant. Gate: nenhuma divergência NOVA (pós ⊆ pré).
===============================================================================
*/

DO $d2b$
DECLARE
    v_apply  CONSTANT BOOLEAN := false;   -- << trocar para true para aplicar
    v_game UUID; v_src UUID; v_n INTEGER; v_pre INTEGER; v_post INTEGER; v_new INTEGER; v_fixed INTEGER;
    v_nr_resolved INTEGER; v_cv0 BIGINT; v_cv1 BIGINT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_game IS NULL OR v_src IS NULL THEN RAISE EXCEPTION 'D2B_G0_CONTEXT'; END IF;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;

    -- conjunto de tipos que permanecem (acabamentos reais + ambíguos da parte 3)
    CREATE TEMP TABLE d2b_keep(code text PRIMARY KEY) ON COMMIT DROP;
    INSERT INTO d2b_keep VALUES ('STANDARD'),('HOLO'),('REVERSE_HOLO'),('COSMOS_HOLO'),('COSMOS_REVERSE'),
      ('GOLD_HOLO'),('RAINBOW_HOLO'),('GALAXY_HOLO'),('CRACKED_ICE_HOLO'),('TINSEL_HOLO'),('TINSEL_REVERSE'),
      ('SHOWFLAKE_HOLO'),('SNOWFLAKE_COSMOS_HOLO'),('METAL'),('METAL_GOLD'),('LENTICULAR'),('MASTER_BALL_HOLO'),
      ('POKE_BALL_REVERSE'),('MASTER_BALL_REVERSE'),('ENERGY_REVERSE'),('LOVE_BALL_REVERSE'),('FRIEND_BALL_REVERSE'),
      ('QUICK_BALL_REVERSE'),('DUSK_BALL_REVERSE'),('ROCKET_REVERSE'),('STANDARDS_SNOWFLAKE'),('PROMO_STAMPED'),
      ('MASTER_BALL_PATTERN'),('POKE_BALL_PATTERN'),('POKEMON_CENTER_EXCLUSIVE');

    -- universo de prova
    CREATE TEMP TABLE d2b_rows ON COMMIT DROP AS
    SELECT r.id, r.raw_data, j.card_set_id, j.external_set_id,
           v.variant_type_id AS cv_fin, v.printing_profile_id AS cv_pr, v.edition_context_profile_id AS cv_ec
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id AND j.status <> 'CANCELLED'
      JOIN public.card_variant v ON v.id = COALESCE(r.resulting_variant_id, r.matched_variant_id)
     WHERE (jsonb_typeof(r.raw_data->'stamp') = 'array' AND jsonb_array_length(r.raw_data->'stamp') > 0)
        OR r.raw_data->>'foil' IS NOT NULL;

    CREATE TEMP TABLE d2b_pre ON COMMIT DROP AS
    SELECT d.id FROM d2b_rows d
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(d.raw_data, v_game, v_src, d.external_set_id) a
     WHERE a.residual_type IS NULL
        OR internal.lookup_variant_type_for_row(v_game, v_src, d.card_set_id, a.residual_type, a.residual_foil, a.residual_subtype, a.residual_stamp) IS DISTINCT FROM d.cv_fin
        OR a.printing_profile_id IS DISTINCT FROM d.cv_pr
        OR a.edition_context_profile_id IS DISTINCT FROM d.cv_ec;
    SELECT count(*) INTO v_pre FROM d2b_pre;

    -- A: EC SET-LOGO por coleção
    INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
    SELECT v_game, v_src, s, 'stamp', 'SET-LOGO'
      FROM unnest(ARRAY['col1','dp2','hgss4','sv10','sv10.5b','sv10.5w','sv02','sv03','sv03.5','sv04','sv05','sv06',
                        'sv06.5','sv07','sv08','sv08.5','sv09','swsh10','swsh11','swsh12','swsh2','swsh3','swsh4']) s;
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 23 THEN RAISE EXCEPTION 'D2B_A: %', v_n; END IF;
    -- D: EC PIKACHU-TAIL basep
    INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
    VALUES (v_game, v_src, 'basep', 'stamp', 'PIKACHU-TAIL');
    INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
    SELECT m.id, t.id, v_game
      FROM public.card_edition_context_external_mapping m
      JOIN public.card_edition_context_trait t ON t.game_id = v_game
       AND t.code = CASE m.normalized_token WHEN 'SET-LOGO' THEN 'ARTWORK_SET_LOGO' ELSE 'CAMPAIGN_PIKACHU_WORLD_2000' END
     WHERE m.raw_field = 'stamp' AND m.normalized_token IN ('SET-LOGO','PIKACHU-TAIL') AND m.traits_signature IS NULL
       AND NOT EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping_trait x WHERE x.mapping_id = m.id);
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 24 THEN RAISE EXCEPTION 'D2B_AD_TRAITS: %', v_n; END IF;

    -- B: Finish SET-LOGO em ex11..ex16 -> REVERSE_HOLO
    INSERT INTO public.card_variant_type_external_mapping
        (game_id, asset_source_id, external_set_id, external_type, external_stamp, normalized_type, normalized_stamp, variant_type_id)
    SELECT v_game, v_src, s, ty, ARRAY['SET-LOGO'], ty, ARRAY['SET-LOGO'], (SELECT id FROM public.card_variant_type WHERE code='REVERSE_HOLO')
      FROM unnest(ARRAY['ex11','ex12','ex13','ex14','ex15','ex16']) s CROSS JOIN unnest(ARRAY['NORMAL','HOLO']) ty;
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 12 THEN RAISE EXCEPTION 'D2B_B: %', v_n; END IF;

    -- C: SV5 galáxia + logo -> GALAXY_HOLO
    UPDATE public.card_variant v
       SET variant_type_id = (SELECT id FROM public.card_variant_type WHERE code='GALAXY_HOLO')
     WHERE v.variant_type_id = (SELECT id FROM public.card_variant_type WHERE code='COSMOS_HOLO')
       AND v.edition_context_profile_id = (SELECT id FROM public.card_edition_context_profile WHERE code='ARTWORK_SET_LOGO')
       AND EXISTS (SELECT 1 FROM public.catalog_variant_import_row r
                    WHERE (r.resulting_variant_id = v.id OR r.matched_variant_id = v.id)
                      AND r.raw_data->>'foil' = 'galaxy');
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 1 THEN RAISE EXCEPTION 'D2B_C: %', v_n; END IF;

    -- E1: remover mappings de Finish legados
    DELETE FROM public.card_variant_type_external_mapping m
     USING public.card_variant_type t
     WHERE t.id = m.variant_type_id AND t.code NOT IN (SELECT code FROM d2b_keep);
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 69 THEN RAISE EXCEPTION 'D2B_E1: %', v_n; END IF;

    -- E2: desativar tipos legados sem variante e sem referência de Pricing
    UPDATE public.card_variant_type t SET is_active = false
     WHERE t.is_active AND t.code NOT IN (SELECT code FROM d2b_keep)
       AND NOT EXISTS (SELECT 1 FROM public.card_variant v WHERE v.variant_type_id = t.id)
       AND NOT EXISTS (SELECT 1 FROM public.pricing_source_card_identity i WHERE i.card_variant_type_id = t.id)
       AND NOT EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping p WHERE p.variant_type_id = t.id);
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 63 THEN RAISE EXCEPTION 'D2B_E2: %', v_n; END IF;

    SET CONSTRAINTS ALL IMMEDIATE;
    IF EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping
                WHERE raw_field='stamp' AND normalized_token IN ('SET-LOGO','PIKACHU-TAIL')
                  AND (traits_signature IS NULL OR cardinality(traits_signature) <> 1)) THEN
        RAISE EXCEPTION 'D2B_P0_EC_UNSEALED';
    END IF;

    -- Prova
    SELECT count(*) INTO v_post FROM d2b_rows d
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(d.raw_data, v_game, v_src, d.external_set_id) a
     WHERE a.residual_type IS NULL
        OR internal.lookup_variant_type_for_row(v_game, v_src, d.card_set_id, a.residual_type, a.residual_foil, a.residual_subtype, a.residual_stamp)
           IS DISTINCT FROM (SELECT v.variant_type_id FROM public.card_variant v JOIN public.catalog_variant_import_row r
                              ON v.id = COALESCE(r.resulting_variant_id, r.matched_variant_id) WHERE r.id = d.id)
        OR a.printing_profile_id IS DISTINCT FROM d.cv_pr
        OR a.edition_context_profile_id IS DISTINCT FROM d.cv_ec;

    SELECT count(*) INTO v_new FROM d2b_rows d
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(d.raw_data, v_game, v_src, d.external_set_id) a
     WHERE d.id NOT IN (SELECT id FROM d2b_pre)
       AND (a.residual_type IS NULL
        OR internal.lookup_variant_type_for_row(v_game, v_src, d.card_set_id, a.residual_type, a.residual_foil, a.residual_subtype, a.residual_stamp)
           IS DISTINCT FROM (SELECT v.variant_type_id FROM public.card_variant v JOIN public.catalog_variant_import_row r
                              ON v.id = COALESCE(r.resulting_variant_id, r.matched_variant_id) WHERE r.id = d.id)
        OR a.printing_profile_id IS DISTINCT FROM d.cv_pr
        OR a.edition_context_profile_id IS DISTINCT FROM d.cv_ec);
    v_fixed := v_pre - (v_post - v_new);

    -- NEEDS_REVIEW que passariam a resolver (informativo)
    SELECT count(*) INTO v_nr_resolved
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id AND j.status <> 'CANCELLED'
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, v_game, v_src, j.external_set_id) a
     WHERE r.validation_status = 'NEEDS_REVIEW'
       AND a.edition_context_state IN ('RESOLVED_NO_EDITION_CONTEXT','RESOLVED_WITH_EC_PROFILE')
       AND internal.lookup_variant_type_for_row(v_game, v_src, j.card_set_id, a.residual_type, a.residual_foil, a.residual_subtype, a.residual_stamp) IS NOT NULL;

    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv0 <> v_cv1 THEN RAISE EXCEPTION 'D2B_P2_TOTAL_DRIFT'; END IF;
    IF v_new <> 0 THEN
        RAISE EXCEPTION 'D2B_P1_NEW_DIVERGENCE: universo=% pre=% pos=% novas=%', (SELECT count(*) FROM d2b_rows), v_pre, v_post, v_new;
    END IF;

    IF NOT v_apply THEN
        RAISE EXCEPTION 'D2B_DRYRUN_OK (rollback): universo=% div_pre=% div_pos=% novas=% corrigidas=% needs_review_que_resolveriam=%',
            (SELECT count(*) FROM d2b_rows), v_pre, v_post, v_new, v_fixed, v_nr_resolved;
    END IF;
    RAISE NOTICE 'D2-02_OK: div_pre=% div_pos=% novas=0 needs_review_que_resolveriam=%', v_pre, v_post, v_nr_resolved;
END;
$d2b$;
