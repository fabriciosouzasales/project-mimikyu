/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2249 - Seed Printing Trait RARITY_SYMBOL_ERROR (EX6 Magikarp)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
              Executada em 2026-10-10 via execute_sql DIRETO (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg, junto com o perfil, o mapping e a rota de
              Finish descritos abaixo. SEM ENTRADA DE LEDGER (mesmo regime das 2240–2242, 2248).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-10
Mandato.....: Aprovação de Fabrício (2026-10-10) após pesquisa de evidência das 4 linhas
              NEEDS_REVIEW da EX6.
Origem......: database/proposals/2026-10-09-needs-review-revalidation/README.md

Evidência:
  RARITY_SYMBOL_ERROR  EX FireRed & LeafGreen Magikarp 67/112: primeiras tiragens com símbolo
                       de Incomum (a carta é Comum), corrigido depois (Bulbapedia). Existe em
                       normal e reverse holo; cópias graduadas pela CGC como "error rarity".

Executado no mesmo bloco (fora deste arquivo):
  - Perfil RARITY_SYMBOL_ERROR (ordem 24) via admin_create_card_printing_profile_with_backfill.
  - Mapping subtype `rarity-error` -> trait via admin_resolve_catalog_variant_import_printing_mapping
    (2 linhas: STANDARD e ENERGY_REVERSE).
  - Rota de Finish ex6: type HOLO + foil ENERGY -> ENERGY_REVERSE. A TCGdex rotula como "holo + energy"
    as reverse holo de Dewgong 3/112 e Drowzee 32/112; eram as duas únicas cartas não-ex da EX6 sem
    ENERGY_REVERSE, e o padrão só ocorre nessas 2 linhas em todo o staging.

Regras: somente POKEMON; exatamente 1 trait, display_order 21.
Pré-requisito: 20 traits POKEMON (… + 2248).
Como validar:
    SELECT code, display_order FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON' AND t.code = 'RARITY_SYMBOL_ERROR';
    -- esperado: 1 linha, display_order 21
===============================================================================
*/

DO $mig$
DECLARE
    v_game_id UUID; v_n INTEGER;
BEGIN
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';
    IF v_game_id IS NULL THEN RAISE EXCEPTION '2249_G0_GAME_NOT_FOUND'; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 20 THEN RAISE EXCEPTION '2249_G1_BASELINE: esperado 20, encontrado %.', v_n; END IF;

    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES (v_game_id, 'RARITY_SYMBOL_ERROR', 'Erro de Símbolo de Raridade',
      'Tiragem inicial impressa com o símbolo de raridade errado, corrigido em tiragem posterior (ex.: EX FireRed & LeafGreen Magikarp 67/112, comum impressa como incomum; Bulbapedia). Variedade catalogada e graduada (CGC), não defeito de exemplar.', 21);

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 21 THEN RAISE EXCEPTION '2249_P1_TOTAL: %', v_n; END IF;
    RAISE NOTICE '2249_OK: 1 trait (21).';
END;
$mig$;
