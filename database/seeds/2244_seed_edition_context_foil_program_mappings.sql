/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2244 - Seed Edition Context: mappings de `foil` de programa + profile Liga·Staff
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE (2026-10-09, execute_sql direto, SEM ledger — regime 2202/2240-2242)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: Decisão H3 de Fabrício (2026-10-09).
Depende de..: 2243 (CHECK aceita raw_field='foil' + 2211 lê o foil).

Escreve EXATAMENTE:
  3 mappings GLOBAIS (TCGDEX, POKEMON) em card_edition_context_external_mapping:
     foil LEAGUE             -> PROGRAM_LEAGUE
     foil PLAYER-REWARD      -> PROGRAM_PLAYER_REWARDS
     foil PROFESSOR-PROGRAM  -> PROGRAM_PROFESSOR
  1 profile em card_edition_context_profile:
     PROGRAM_LEAGUE__ROLE_STAFF (PROGRAM_LEAGUE + ROLE_STAFF), display_order 1760
     — necessário para as 7 linhas `league` + stamp `staff` (PL3, HGSS2).
Não cria trait. Não toca rows, jobs nem card_variant.

Padrão de escrita = seeds 2231/2232 (INSERT direto + composição + selo
deferido forçado com SET CONSTRAINTS ALL IMMEDIATE).
Como validar:
    SELECT m.raw_field, m.normalized_token, m.traits_signature IS NOT NULL
      FROM public.card_edition_context_external_mapping m WHERE m.raw_field = 'foil';
    -- esperado: 3 linhas, assinatura selada
    SELECT code FROM public.card_edition_context_profile WHERE code = 'PROGRAM_LEAGUE__ROLE_STAFF';
===============================================================================
*/

DO $seed$
DECLARE
    v_game UUID; v_src UUID; v_n INTEGER; v_cv0 BIGINT; v_cv1 BIGINT; v_rows0 BIGINT; v_rows1 BIGINT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_game IS NULL OR v_src IS NULL THEN RAISE EXCEPTION '2244_G0_CONTEXT_MISSING'; END IF;

    -- G1: 2243 aplicada (CHECK aceita 'foil')
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'ck_cecem_raw_field'
                      AND pg_get_constraintdef(oid) LIKE '%''foil''%') THEN
        RAISE EXCEPTION '2244_G1_2243_NOT_APPLIED';
    END IF;
    -- G2: nada pré-existente
    IF EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping WHERE raw_field = 'foil') THEN
        RAISE EXCEPTION '2244_G2_FOIL_MAPPING_ALREADY_EXISTS';
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_edition_context_profile WHERE code = 'PROGRAM_LEAGUE__ROLE_STAFF')
       OR EXISTS (SELECT 1 FROM public.card_edition_context_profile WHERE display_order = 1760) THEN
        RAISE EXCEPTION '2244_G2_PROFILE_OR_ORDER_TAKEN';
    END IF;
    -- G3: traits existem e ativos
    SELECT count(*) INTO v_n FROM public.card_edition_context_trait
     WHERE game_id = v_game AND is_active
       AND code IN ('PROGRAM_LEAGUE','PROGRAM_PLAYER_REWARDS','PROGRAM_PROFESSOR','ROLE_STAFF');
    IF v_n <> 4 THEN RAISE EXCEPTION '2244_G3_TRAITS: esperado 4 ativos, encontrado %.', v_n; END IF;

    SELECT count(*) INTO v_cv0 FROM public.card_variant;
    SELECT count(*) INTO v_rows0 FROM public.catalog_variant_import_row WHERE validation_status = 'VALID';

    -- W1: mappings
    INSERT INTO public.card_edition_context_external_mapping
        (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
    VALUES (v_game, v_src, NULL, 'foil', 'league'),
           (v_game, v_src, NULL, 'foil', 'player-reward'),
           (v_game, v_src, NULL, 'foil', 'professor-program');

    INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
    SELECT m.id, t.id, v_game
      FROM (VALUES ('LEAGUE','PROGRAM_LEAGUE'),
                   ('PLAYER-REWARD','PROGRAM_PLAYER_REWARDS'),
                   ('PROFESSOR-PROGRAM','PROGRAM_PROFESSOR')) s(tok, trait)
      JOIN public.card_edition_context_external_mapping m
        ON m.game_id = v_game AND m.asset_source_id = v_src AND m.raw_field = 'foil'
       AND m.normalized_token = s.tok AND m.external_set_id IS NULL
      JOIN public.card_edition_context_trait t ON t.game_id = v_game AND t.code = s.trait;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 3 THEN RAISE EXCEPTION '2244_W1_MAPPING_TRAITS: %', v_n; END IF;

    -- W2: profile Liga · Staff
    INSERT INTO public.card_edition_context_profile (game_id, code, name, description, display_order)
    VALUES (v_game, 'PROGRAM_LEAGUE__ROLE_STAFF', 'Liga · Staff',
            'Carta do programa de Liga com marcação de Staff.', 1760);
    INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id)
    SELECT p.id, t.id, v_game
      FROM public.card_edition_context_profile p
      JOIN public.card_edition_context_trait t
        ON t.game_id = v_game AND t.code IN ('PROGRAM_LEAGUE','ROLE_STAFF')
     WHERE p.code = 'PROGRAM_LEAGUE__ROLE_STAFF';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n <> 2 THEN RAISE EXCEPTION '2244_W2_PROFILE_TRAITS: %', v_n; END IF;

    -- Força os selos deferidos (padrão 2231/2232)
    SET CONSTRAINTS ALL IMMEDIATE;

    -- P1: assinaturas seladas
    SELECT count(*) INTO v_n FROM public.card_edition_context_external_mapping
     WHERE raw_field = 'foil' AND traits_signature IS NOT NULL AND cardinality(traits_signature) = 1 AND is_active;
    IF v_n <> 3 THEN RAISE EXCEPTION '2244_P1_MAPPING_UNSEALED: %', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.card_edition_context_profile
                    WHERE code = 'PROGRAM_LEAGUE__ROLE_STAFF' AND cardinality(traits_signature) = 2 AND is_active) THEN
        RAISE EXCEPTION '2244_P1_PROFILE_UNSEALED';
    END IF;
    -- P2: não-toque
    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    SELECT count(*) INTO v_rows1 FROM public.catalog_variant_import_row WHERE validation_status = 'VALID';
    IF v_cv0 <> v_cv1 OR v_rows0 <> v_rows1 THEN RAISE EXCEPTION '2244_P2_UNTOUCHED_DRIFT'; END IF;

    RAISE NOTICE '2244_OK: 3 mappings foil + 1 profile PROGRAM_LEAGUE__ROLE_STAFF.';
END;
$seed$;
