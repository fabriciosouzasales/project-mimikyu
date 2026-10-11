/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2256 - Seed Edition Context CAMPAIGN_30TH_ANNIVERSARY (ME5.5 / ME5.5CC)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
              Executada em 2026-10-10 via execute_sql DIRETO (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg. SEM ENTRADA DE LEDGER (mesmo regime das
              seeds 2240–2244, 2248–2250).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-10
Mandato.....: Fabrício, 2026-10-10: "Vamos fechar as variantes da ME5.5 e da ME5.5CC"
Origem......: database/proposals/2026-10-10-me55-30th-celebration/README.md (pendência 5)

Problema
  Os jobs TCGdex de ME5.5 (158 linhas) e ME5.5CC (30) estão STAGED com 100% NEEDS_REVIEW:
  a TCGdex marca todas as cartas com stamp "30th-anniversary" e não havia rota de
  Edition Context para esse token (precedentes: 10TH-ANNIVERSARY, 25TH-CELEBRATION).

O que faz (mesmo desenho do 25TH-CELEBRATION → CAMPAIGN_25TH_ANNIVERSARY)
  1. Trait  CAMPAIGN_30TH_ANNIVERSARY "Celebração de 30 Anos" (família CAMPAIGN, ordem 150).
  2. Perfil CAMPAIGN_30TH_ANNIVERSARY (ordem 1790) com esse único trait.
  3. Rota GLOBAL TCGDEX stamp "30TH-ANNIVERSARY" → trait.
  Não toca CAMPAIGN_POKEMON_DAY_30TH (Pokémon Day, campanha distinta).

Como validar:
    SELECT m.normalized_token, t.code FROM public.card_edition_context_external_mapping m
      JOIN public.card_edition_context_external_mapping_trait mt ON mt.mapping_id = m.id
      JOIN public.card_edition_context_trait t ON t.id = mt.trait_id
     WHERE m.normalized_token = '30TH-ANNIVERSARY';
    -- esperado: 1 linha, CAMPAIGN_30TH_ANNIVERSARY
===============================================================================
*/

DO $mig$
DECLARE
    v_game uuid; v_src uuid; v_trait uuid; v_prof uuid; v_n int;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code = 'POKEMON';
    SELECT id INTO v_src  FROM public.asset_source WHERE code = 'TCGDEX';
    IF v_game IS NULL OR v_src IS NULL THEN RAISE EXCEPTION '2256_G0_CONTEXT'; END IF;

    IF EXISTS (SELECT 1 FROM public.card_edition_context_trait WHERE code = 'CAMPAIGN_30TH_ANNIVERSARY' OR (family = 'CAMPAIGN' AND display_order = 150))
       OR EXISTS (SELECT 1 FROM public.card_edition_context_profile WHERE code = 'CAMPAIGN_30TH_ANNIVERSARY' OR display_order = 1790)
       OR EXISTS (SELECT 1 FROM public.card_edition_context_external_mapping WHERE raw_field = 'stamp' AND normalized_token = '30TH-ANNIVERSARY') THEN
        RAISE EXCEPTION '2256_G1_ALREADY_EXISTS';
    END IF;

    INSERT INTO public.card_edition_context_trait (game_id, family, code, name, description, display_order)
    VALUES (v_game, 'CAMPAIGN', 'CAMPAIGN_30TH_ANNIVERSARY', 'Celebração de 30 Anos',
            'Carta com o carimbo comemorativo dos 30 anos de Pokémon (coleção Celebração de 30 Anos e Coleção Clássica, 2026).', 150)
    RETURNING id INTO v_trait;

    INSERT INTO public.card_edition_context_profile (game_id, code, name, description, display_order)
    VALUES (v_game, 'CAMPAIGN_30TH_ANNIVERSARY', 'Celebração de 30 Anos',
            'Carta com o carimbo comemorativo dos 30 anos de Pokémon.', 1790)
    RETURNING id INTO v_prof;
    INSERT INTO public.card_edition_context_profile_trait (profile_id, trait_id, game_id) VALUES (v_prof, v_trait, v_game);

    INSERT INTO public.card_edition_context_external_mapping (game_id, asset_source_id, external_set_id, raw_field, normalized_token)
    VALUES (v_game, v_src, NULL, 'stamp', '30TH-ANNIVERSARY');
    INSERT INTO public.card_edition_context_external_mapping_trait (mapping_id, trait_id, game_id)
    SELECT m.id, v_trait, v_game FROM public.card_edition_context_external_mapping m
     WHERE m.raw_field = 'stamp' AND m.normalized_token = '30TH-ANNIVERSARY';
    SET CONSTRAINTS ALL IMMEDIATE;

    SELECT count(*) INTO v_n
      FROM public.card_edition_context_external_mapping m
      JOIN public.card_edition_context_external_mapping_trait mt ON mt.mapping_id = m.id
     WHERE m.normalized_token = '30TH-ANNIVERSARY' AND mt.trait_id = v_trait;
    IF v_n <> 1 THEN RAISE EXCEPTION '2256_P1_MAPPING: %', v_n; END IF;
    RAISE NOTICE '2256_OK';
END;
$mig$;
