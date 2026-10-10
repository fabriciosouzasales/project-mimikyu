/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2248 - Seed Printing Trait FIRST_EDITION_SCRATCH_ERROR (Jungle Pinsir)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
              Executada em 2026-10-10 via execute_sql DIRETO (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg, junto com o perfil, o mapping e a rota EC
              descritos abaixo. SEM ENTRADA DE LEDGER (mesmo regime das 2240–2242).
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-10
Mandato.....: Aprovação de Fabrício (2026-10-10) após pesquisa de evidência das linhas
              DEFERRED da BASE2 (Pinsir scratch e Pikachu tail).
Origem......: database/proposals/2026-10-09-needs-review-revalidation/README.md

Evidência:
  FIRST_EDITION_SCRATCH_ERROR  Jungle Pinsir 9/64 Holo 1ª Edição com risco impresso sobre a
                               arte. PSA tem spec própria ("1st edition-scratch error",
                               spec 7961534) e o PSA Set Registry lista o card entre os erros
                               da Jungle, ao lado das 16 "No Symbol" e da Butterfree "d Edition".

Executado no mesmo bloco (fora deste arquivo, pelas RPCs canônicas / formato D2-02):
  - Perfil FIRST_EDITION_SCRATCH_ERROR (ordem 23) via admin_create_card_printing_profile_with_backfill.
  - Mapping stamp `1st-edition-scratch-error` -> trait, via
    admin_resolve_catalog_variant_import_printing_mapping (1 linha revalidada).
  - Rota EC base2 stamp PIKACHU-TAIL -> CAMPAIGN_PIKACHU_WORLD_2000 (Jungle Pikachu 60/64 é
    reimpressão do Pikachu World Collection 2000, carimbo dourado de cauda; Bulbapedia).

Regras: somente POKEMON; exatamente 1 trait, display_order 20.
Pré-requisito: 19 traits POKEMON (… + 2240 + 2241 + 2242).
Como validar:
    SELECT code, display_order FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON' AND t.code = 'FIRST_EDITION_SCRATCH_ERROR';
    -- esperado: 1 linha, display_order 20
===============================================================================
*/

DO $mig$
DECLARE
    v_game_id UUID; v_n INTEGER;
BEGIN
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';
    IF v_game_id IS NULL THEN RAISE EXCEPTION '2248_G0_GAME_NOT_FOUND'; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 19 THEN RAISE EXCEPTION '2248_G1_BASELINE: esperado 19, encontrado %.', v_n; END IF;

    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES (v_game_id, 'FIRST_EDITION_SCRATCH_ERROR', 'Erro de Risco (1ª Edição)',
      'Tiragem de 1ª Edição com uma linha/risco impresso sobre a arte (ex.: Jungle Pinsir 9/64). Variedade catalogada pela PSA ("1st edition-scratch error") e listada no PSA Set Registry de erros da Jungle; não defeito de exemplar.', 20);

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 20 THEN RAISE EXCEPTION '2248_P1_TOTAL: %', v_n; END IF;
    RAISE NOTICE '2248_OK: 1 trait (20).';
END;
$mig$;
