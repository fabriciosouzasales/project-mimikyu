/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2240 - Seed Printing Traits (NO_E_READER, MISSING_EXPANSION_SYMBOL)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
              Executada em 2026-10-09 via execute_sql DIRETO (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg. SEM ENTRADA DE LEDGER (execução direta,
              não apply_migration) — mesmo regime da 2202.
              Prova por dado: card_printing_trait POKEMON = 11; 10=NO_E_READER,
              11=MISSING_EXPANSION_SYMBOL.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: NEEDS_REVIEW — erros de impressão, decisão de Fabrício em 2026-10-09
              ("Duas famílias grandes agora").

-------------------------------------------------------------------------------
POR QUE ESTA QUERY EXISTE
-------------------------------------------------------------------------------
`card_printing_trait` é vocabulário semeado: não há writer canônico (RPC) para
trait. Precedentes diretos: Queries 2201 (3 traits) e 2202 (EVOLUTION_BOX_ERROR).
Profiles e mappings NÃO são criados aqui; eles nascem depois pelas RPCs
canônicas `admin_create_card_printing_profile_with_backfill` e
`admin_resolve_catalog_variant_import_printing_mapping`.

Evidência externa:
  NO_E_READER               Bulbapedia (EX Ruby & Sapphire; EX TCG Series
                            merchandise): as reimpressões de EX Ruby & Sapphire e
                            EX Sandstorm do EX Battle Stadium não têm a faixa de
                            dot code do e-Reader nem o logo "e". Fonte TCGdex:
                            subtype `no-e-reader` (41 linhas: EX1, EX2, NP).
  MISSING_EXPANSION_SYMBOL  Tiragem inicial Unlimited das 16 holos de Jungle sem
                            o símbolo da expansão; a PSA gradua como variedade
                            própria ("No Symbol"). Fonte TCGdex: subtype
                            `missing-expansion-symbol` (16 linhas: BASE2 1–16).

Os dois são variedades de tiragem catalogadas, não defeitos de exemplar: mesma
classe semântica de AOKI_CREDIT e EVOLUTION_BOX_ERROR.

-------------------------------------------------------------------------------
Regras:
- Somente Game POKEMON; exatamente 2 traits, display_order 10 e 11.
- Não cria Profile, vínculo, mapping, Variant Type; não toca rows nem card_variant.
Pré-requisito: 9 traits POKEMON, display_order 1..9 contíguos (2169+2201+2202).
Resultado esperado: 9 -> 11 traits; demais tabelas inalteradas.
Como validar:
    SELECT code, display_order FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON' ORDER BY display_order;
    -- esperado: 11 linhas; 10=NO_E_READER, 11=MISSING_EXPANSION_SYMBOL
===============================================================================
*/

DO $mig$
DECLARE
    v_game_id  UUID;
    v_n        INTEGER;
    v_aff      INTEGER;
    v_p0 BIGINT; v_pt0 BIGINT; v_pem0 BIGINT; v_cv0 BIGINT;
    v_p1 BIGINT; v_pt1 BIGINT; v_pem1 BIGINT; v_cv1 BIGINT;
BEGIN
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';
    IF v_game_id IS NULL THEN RAISE EXCEPTION '2240_G0_GAME_NOT_FOUND'; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 9 THEN RAISE EXCEPTION '2240_G1_BASELINE: esperado 9 traits, encontrado %.', v_n; END IF;
    IF EXISTS (SELECT 1 FROM generate_series(1,9) s
                WHERE NOT EXISTS (SELECT 1 FROM public.card_printing_trait t
                                   WHERE t.game_id = v_game_id AND t.display_order = s)) THEN
        RAISE EXCEPTION '2240_G1_ORDER_GAP';
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_printing_trait
                WHERE game_id = v_game_id AND code IN ('NO_E_READER','MISSING_EXPANSION_SYMBOL')) THEN
        RAISE EXCEPTION '2240_G2_CODE_ALREADY_EXISTS';
    END IF;

    SELECT count(*) INTO v_p0   FROM public.card_printing_profile;
    SELECT count(*) INTO v_pt0  FROM public.card_printing_profile_trait;
    SELECT count(*) INTO v_pem0 FROM public.card_printing_external_mapping;
    SELECT count(*) INTO v_cv0  FROM public.card_variant;

    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES
      (v_game_id, 'NO_E_READER', 'Sem Faixa e-Reader',
       'Reimpressão sem a faixa de dot code do e-Reader e sem o logo "e" no canto inferior esquerdo, presentes na tiragem original. Observada nas cartas de EX Ruby & Sapphire e EX Sandstorm reimpressas no EX Battle Stadium. Variedade de tiragem catalogada, não defeito de exemplar.',
       10),
      (v_game_id, 'MISSING_EXPANSION_SYMBOL', 'Sem Símbolo da Expansão',
       'Tiragem inicial Unlimited das holos de Jungle impressa sem o símbolo da expansão no canto inferior direito da arte. Erro produzido em massa e corrigido depois; graduado separadamente ("No Symbol"). Variedade de tiragem catalogada, não defeito de exemplar.',
       11);
    GET DIAGNOSTICS v_aff = ROW_COUNT;
    IF v_aff <> 2 THEN RAISE EXCEPTION '2240_W1_CARDINALITY: %', v_aff; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 11 THEN RAISE EXCEPTION '2240_P1_TOTAL: %', v_n; END IF;

    SELECT count(*) INTO v_p1   FROM public.card_printing_profile;
    SELECT count(*) INTO v_pt1  FROM public.card_printing_profile_trait;
    SELECT count(*) INTO v_pem1 FROM public.card_printing_external_mapping;
    SELECT count(*) INTO v_cv1  FROM public.card_variant;
    IF (v_p0, v_pt0, v_pem0, v_cv0) IS DISTINCT FROM (v_p1, v_pt1, v_pem1, v_cv1) THEN
        RAISE EXCEPTION '2240_P2_UNTOUCHED_DRIFT';
    END IF;

    RAISE NOTICE '2240_OK: 2 traits inseridos (10=NO_E_READER, 11=MISSING_EXPANSION_SYMBOL).';
END;
$mig$;
