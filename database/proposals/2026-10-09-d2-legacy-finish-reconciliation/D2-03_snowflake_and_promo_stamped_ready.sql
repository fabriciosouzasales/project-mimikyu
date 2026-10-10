/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: D2-03 - Snowflake vira contexto; PROMO_STAMPED sem evidência é removido
Versão......: 1.0
Status......: PRONTA — v_apply = false (dry-run, desfaz tudo) / true (aplica)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: D2 parte 3, decisões de Fabrício em 2026-10-09:
              (1) snowflake = contexto novo e neutro; (2) remover as 33 PROMO_STAMPED.

Escreve
  S1 traço EC ARTWORK_SNOWFLAKE_STAMP (família ARTWORK_MARK, ordem 40) + perfil homônimo (ordem 1780)
  S2 rota EC GLOBAL stamp SNOWFLAKE -> ARTWORK_SNOWFLAKE_STAMP
  S3 27 variantes STANDARDS_SNOWFLAKE -> STANDARD + ARTWORK_SNOWFLAKE_STAMP (no lugar, mesmo id)
  S3b mesma regra para os acabamentos com snowflake embutido: SHOWFLAKE_HOLO (17) -> HOLO + floco;
      SNOWFLAKE_COSMOS_HOLO (5) -> COSMOS_HOLO + floco (sem isso a rota EC desviaria a reimportação)
  S4 remove as 3 rotas de Finish com {SNOWFLAKE}; desativa os 3 tipos
  P1 apaga as 33 variantes PROMO_STAMPED (ME2.5 10, MEP 23); desativa PROMO_STAMPED
Gates: contagens exatas, 0 colisão, 0 referência (cópias, preço, coleções, staging),
       prova de reimportação das linhas snowflake, total final = 26.524 - 33 = 26.491.
===============================================================================
*/

DO $d2c$
DECLARE
    v_apply CONSTANT BOOLEAN := false;   -- << trocar para true para aplicar
    v_game UUID; v_src UUID; v_n INTEGER; v_cv0 BIGINT; v_cv1 BIGINT;
    v_std UUID; v_snow_t UUID; v_promo_t UUID; v_prof UUID; v_trait UUID;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code = 'TCGDEX';
    SELECT id INTO v_std     FROM public.card_variant_type WHERE code = 'STANDARD';
    SELECT id INTO v_snow_t  FROM public.card_variant_type WHERE code = 'STANDARDS_SNOWFLAKE';
    SELECT id INTO v_promo_t FROM public.card_variant_type WHERE code = 'PROMO_STAMPED';
    IF v_game IS NULL OR v_src IS NULL OR v_std IS NULL OR v_snow_t IS NULL OR v_promo_t IS NULL THEN
        RAISE EXCEPTION 'D2C_G0_CONTEXT';
    END IF;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;
    IF v_cv0 <> 26524 THEN RAISE EXCEPTION 'D2C_G0_BASELINE: %', v_cv0; END IF;

    -- G1: nada pré-existente / ordens livres
    IF EXISTS (SELECT 1 FROM public.card_edition_context_trait WHERE code = 'ARTWORK_SNOWFLAKE_STAMP' OR (family = 'ARTWORK_MARK' AND display_order = 40))
       OR EXISTS (SELECT 1 FROM public.card_edition_context_profile WHERE code = 'ARTWORK_SNOWFLAKE_STAMP' OR display_order = 1780)
       OR EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping WHERE normalized_token = 'SNOWFLAKE') THEN
        RAISE EXCEPTION 'D2C_G1_ALREADY_EXISTS';
    END IF;

    -- G2: referências às 33 PROMO_STAMPED e às 27 snowflake
    IF EXISTS (SELECT 1 FROM public.card_variant v WHERE v.variant_type_id IN (v_promo_t, v_snow_t) AND (
                  EXISTS (SELECT 1 FROM public.physical_card x WHERE x.card_variant_id = v.id)
               OR EXISTS (SELECT 1 FROM public.pricing_product x WHERE x.card_variant_id = v.id)
               OR EXISTS (SELECT 1 FROM public.collection_master_set_scope x WHERE x.card_variant_id = v.id)
               OR EXISTS (SELECT 1 FROM public.collection_layout_slot_expected_content x WHERE x.card_variant_id = v.id)))
       OR EXISTS (SELECT 1 FROM public.catalog_variant_import_row r JOIN public.card_variant v
                    ON v.id IN (r.resulting_variant_id, r.matched_variant_id) WHERE v.variant_type_id = v_promo_t)
       OR EXISTS (SELECT 1 FROM public.pricing_source_card_identity i WHERE i.card_variant_type_id IN (v_promo_t, v_snow_t))
       OR EXISTS (SELECT 1 FROM public.pricing_source_variant_mapping p WHERE p.variant_type_id IN (v_promo_t, v_snow_t)) THEN
        RAISE EXCEPTION 'D2C_G2_REFERENCED';
    END IF;

    -- S1: traço + perfil
    INSERT INTO public.card_edition_context_trait (game_id, family, code, name, description, display_order)
    VALUES (v_game, 'ARTWORK_MARK', 'ARTWORK_SNOWFLAKE_STAMP', 'Carimbo Floco de Neve',
            'Carta com carimbo de floco de neve impresso (promoções de fim de ano). Não identifica a campanha.', 40)
    RETURNING id INTO v_trait;
    INSERT INTO public.card_edition_context_profile (game_id, code, name, description, display_order)
    VALUES (v_game, 'ARTWORK_SNOWFLAKE_STAMP', 'Carimbo Floco de Neve',
            'Carta com carimbo de floco de neve impresso.', 1780)
    RETURNING id INTO v_prof;
    INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id) VALUES (v_prof, v_trait, v_game);

    -- S2: rota EC
    INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
    VALUES (v_game, v_src, NULL, 'stamp', 'SNOWFLAKE');
    INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
    SELECT m.id, v_trait, v_game FROM public.card_edition_context_external_mapping m
     WHERE m.raw_field = 'stamp' AND m.normalized_token = 'SNOWFLAKE';
    SET CONSTRAINTS ALL IMMEDIATE;

    -- S3: decompor as 27 (colisão antes)
    IF EXISTS (SELECT 1 FROM public.card_variant v WHERE v.variant_type_id = v_snow_t AND EXISTS (
                 SELECT 1 FROM public.card_variant v2 WHERE v2.card_id = v.card_id AND v2.id <> v.id
                   AND v2.variant_type_id = v_std AND v2.edition_context_profile_id = v_prof
                   AND v2.printing_profile_id IS NOT DISTINCT FROM v.printing_profile_id)) THEN
        RAISE EXCEPTION 'D2C_S3_COLLISION';
    END IF;
    UPDATE public.card_variant SET variant_type_id = v_std, edition_context_profile_id = v_prof
     WHERE variant_type_id = v_snow_t AND edition_context_profile_id IS NULL AND printing_profile_id IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 27 THEN RAISE EXCEPTION 'D2C_S3: %', v_n; END IF;

    -- S3b: holo/cosmos com snowflake
    IF EXISTS (SELECT 1 FROM public.pricing_source_card_identity i JOIN public.card_variant_type t ON t.id = i.card_variant_type_id
                WHERE t.code IN ('SHOWFLAKE_HOLO','SNOWFLAKE_COSMOS_HOLO'))
       OR EXISTS (SELECT 1 FROM public.card_variant v JOIN public.card_variant_type t ON t.id = v.variant_type_id
                   WHERE t.code IN ('SHOWFLAKE_HOLO','SNOWFLAKE_COSMOS_HOLO') AND (
                         EXISTS (SELECT 1 FROM public.physical_card x WHERE x.card_variant_id = v.id)
                      OR EXISTS (SELECT 1 FROM public.pricing_product x WHERE x.card_variant_id = v.id))) THEN
        RAISE EXCEPTION 'D2C_S3B_REFERENCED';
    END IF;
    UPDATE public.card_variant v
       SET variant_type_id = (SELECT id FROM public.card_variant_type WHERE code =
                               CASE t.code WHEN 'SHOWFLAKE_HOLO' THEN 'HOLO' ELSE 'COSMOS_HOLO' END),
           edition_context_profile_id = v_prof
      FROM public.card_variant_type t
     WHERE t.id = v.variant_type_id AND t.code IN ('SHOWFLAKE_HOLO','SNOWFLAKE_COSMOS_HOLO')
       AND v.edition_context_profile_id IS NULL AND v.printing_profile_id IS NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 22 THEN RAISE EXCEPTION 'D2C_S3B: %', v_n; END IF;

    -- S4: rotas de Finish e tipos
    DELETE FROM public.card_variant_type_external_mapping m USING public.card_variant_type t
     WHERE t.id = m.variant_type_id AND t.code IN ('STANDARDS_SNOWFLAKE','SHOWFLAKE_HOLO','SNOWFLAKE_COSMOS_HOLO');
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 3 THEN RAISE EXCEPTION 'D2C_S4_MAP: %', v_n; END IF;
    UPDATE public.card_variant_type SET is_active = false
     WHERE code IN ('STANDARDS_SNOWFLAKE','SHOWFLAKE_HOLO','SNOWFLAKE_COSMOS_HOLO');
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 3 THEN RAISE EXCEPTION 'D2C_S4_TYPES: %', v_n; END IF;

    -- P1: remover as 33 PROMO_STAMPED
    DELETE FROM public.card_variant WHERE variant_type_id = v_promo_t;
    GET DIAGNOSTICS v_n = ROW_COUNT; IF v_n <> 33 THEN RAISE EXCEPTION 'D2C_P1: %', v_n; END IF;
    UPDATE public.card_variant_type SET is_active = false WHERE id = v_promo_t;

    -- Prova: linhas snowflake reimportam para a identidade gravada
    SELECT count(*) INTO v_n
      FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id AND j.status <> 'CANCELLED'
      JOIN public.card_variant v ON v.id = COALESCE(r.resulting_variant_id, r.matched_variant_id)
     CROSS JOIN LATERAL internal.resolve_variant_row_axes(r.raw_data, v_game, v_src, j.external_set_id) a
     WHERE r.raw_data->'stamp' ? 'snowflake'
       AND (internal.lookup_variant_type_for_row(v_game, v_src, j.card_set_id, a.residual_type, a.residual_foil, a.residual_subtype, a.residual_stamp) IS DISTINCT FROM v.variant_type_id
            OR a.edition_context_profile_id IS DISTINCT FROM v.edition_context_profile_id
            OR a.printing_profile_id IS DISTINCT FROM v.printing_profile_id);
    IF v_n <> 0 THEN RAISE EXCEPTION 'D2C_PROOF_SNOWFLAKE_DIVERGENCE: %', v_n; END IF;

    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF v_cv1 <> 26491 THEN RAISE EXCEPTION 'D2C_TOTAL: %', v_cv1; END IF;

    IF NOT v_apply THEN
        RAISE EXCEPTION 'D2C_DRYRUN_OK (rollback): snowflake 27 decompostas, promo_stamped 33 removidas, total % -> %', v_cv0, v_cv1;
    END IF;
    RAISE NOTICE 'D2-03_OK: total % -> %', v_cv0, v_cv1;
END;
$d2c$;
