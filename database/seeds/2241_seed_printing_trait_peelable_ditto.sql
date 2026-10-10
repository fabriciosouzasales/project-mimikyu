/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2241 - Seed Printing Trait (PEELABLE_DITTO)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
              Executada em 2026-10-09 via execute_sql DIRETO (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg. SEM ENTRADA DE LEDGER (execução direta,
              não apply_migration) — mesmo regime das 2202 e 2240.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: NEEDS_REVIEW — decisão de Fabrício em 2026-10-09 ("REVERSE_HOLO + Printing").
Origem......: database/proposals/2026-10-09-needs-review-revalidation/

Evidência:
  PEELABLE_DITTO  Pokémon GO (SWSH10.5): reverse holos de Spinarak 006, Numel 013
                  e Bidoof 059 cobertas por um adesivo removível de Ditto; listadas
                  e precificadas como variante própria (TCGplayer / PokeInvesting:
                  "Peelable Ditto ... Reverse Holofoil"). Fonte TCGdex: subtype
                  `peelable-ditto` (3 linhas).

Regras: somente POKEMON; exatamente 1 trait, display_order 12. Não cria Profile,
mapping, Variant Type; não toca rows nem card_variant.
Pré-requisito: 11 traits POKEMON, display_order 1..11 contíguos (… + 2240).
Como validar:
    SELECT code, display_order FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON' ORDER BY display_order;
    -- esperado: 12 linhas; 12=PEELABLE_DITTO
===============================================================================
*/

DO $mig$
DECLARE
    v_game_id UUID; v_n INTEGER; v_aff INTEGER;
    v_p0 BIGINT; v_pem0 BIGINT; v_cv0 BIGINT;
    v_p1 BIGINT; v_pem1 BIGINT; v_cv1 BIGINT;
BEGIN
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';
    IF v_game_id IS NULL THEN RAISE EXCEPTION '2241_G0_GAME_NOT_FOUND'; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 11 THEN RAISE EXCEPTION '2241_G1_BASELINE: esperado 11, encontrado %.', v_n; END IF;
    IF EXISTS (SELECT 1 FROM generate_series(1,11) s WHERE NOT EXISTS
               (SELECT 1 FROM public.card_printing_trait t WHERE t.game_id = v_game_id AND t.display_order = s)) THEN
        RAISE EXCEPTION '2241_G1_ORDER_GAP';
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_printing_trait WHERE game_id = v_game_id AND code = 'PEELABLE_DITTO') THEN
        RAISE EXCEPTION '2241_G2_CODE_ALREADY_EXISTS';
    END IF;
    SELECT count(*) INTO v_p0 FROM public.card_printing_profile;
    SELECT count(*) INTO v_pem0 FROM public.card_printing_external_mapping;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;

    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES (v_game_id, 'PEELABLE_DITTO', 'Ditto Destacável',
            'Tiragem coberta por um adesivo removível com a arte de Ditto sobre a carta original. Observada nas reverse holos de Spinarak, Numel e Bidoof da coleção Pokémon GO. Variedade de tiragem catalogada, não defeito de exemplar.',
            12);
    GET DIAGNOSTICS v_aff = ROW_COUNT;
    IF v_aff <> 1 THEN RAISE EXCEPTION '2241_W1_CARDINALITY: %', v_aff; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 12 THEN RAISE EXCEPTION '2241_P1_TOTAL: %', v_n; END IF;
    SELECT count(*) INTO v_p1 FROM public.card_printing_profile;
    SELECT count(*) INTO v_pem1 FROM public.card_printing_external_mapping;
    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF (v_p0, v_pem0, v_cv0) IS DISTINCT FROM (v_p1, v_pem1, v_cv1) THEN RAISE EXCEPTION '2241_P2_UNTOUCHED_DRIFT'; END IF;
    RAISE NOTICE '2241_OK: 12=PEELABLE_DITTO.';
END;
$mig$;
