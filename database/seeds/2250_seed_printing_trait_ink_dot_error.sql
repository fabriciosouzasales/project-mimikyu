/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2250 - Seed Printing Trait INK_DOT_ERROR (Team Rocket Charmander)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
              Executada em 2026-10-10 via execute_sql DIRETO (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg, junto com o perfil e o mapping descritos abaixo.
              SEM ENTRADA DE LEDGER (mesmo regime das 2240–2242, 2248, 2249).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-10
Mandato.....: Aprovação de Fabrício (2026-10-10) após pesquisa de evidência da última linha
              NEEDS_REVIEW (BASE5 Charmander).
Origem......: database/proposals/2026-10-09-needs-review-revalidation/README.md

Evidência:
  INK_DOT_ERROR  Team Rocket Charmander 50/82: "Black Dot Error", ponto de tinta preta sobre o
                 "d" do nome nas tiragens Unlimited (Bulbapedia, página "Error cards"); cópia
                 graduada pela CGC como "Black Dot" error. Nome genérico porque o mesmo tipo de
                 erro existe em outras cartas (ex.: Dark Charmeleon "Print Dot Error", PSA).

Executado no mesmo bloco (fora deste arquivo):
  - Perfil INK_DOT_ERROR (ordem 25) via admin_create_card_printing_profile_with_backfill.
  - Mapping subtype `d-ink-dot-error` -> trait via admin_resolve_catalog_variant_import_printing_mapping.

Regras: somente POKEMON; exatamente 1 trait, display_order 22.
Pré-requisito: 21 traits POKEMON (… + 2248 + 2249).
Como validar:
    SELECT code, display_order FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON' AND t.code = 'INK_DOT_ERROR';
    -- esperado: 1 linha, display_order 22
===============================================================================
*/

DO $mig$
DECLARE
    v_game_id UUID; v_n INTEGER;
BEGIN
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';
    IF v_game_id IS NULL THEN RAISE EXCEPTION '2250_G0_GAME_NOT_FOUND'; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 21 THEN RAISE EXCEPTION '2250_G1_BASELINE: esperado 21, encontrado %.', v_n; END IF;

    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES (v_game_id, 'INK_DOT_ERROR', 'Erro de Ponto de Tinta',
      'Ponto de tinta repetido em parte da tiragem, na mesma posição em várias cópias (ex.: Team Rocket Charmander 50/82 Unlimited, "Black Dot Error" sobre o "d" do nome; Bulbapedia, graduado pela CGC). Variedade de tiragem, não defeito de exemplar.', 22);

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 22 THEN RAISE EXCEPTION '2250_P1_TOTAL: %', v_n; END IF;
    RAISE NOTICE '2250_OK: 1 trait (22).';
END;
$mig$;
