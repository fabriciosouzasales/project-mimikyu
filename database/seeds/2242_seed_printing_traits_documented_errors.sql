/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2242 - Seed Printing Traits (erros de impressão documentados)
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
              Executada em 2026-10-09 via execute_sql DIRETO (MCP Supabase),
              projeto qjfutqujxrbzgrtkpgkg. SEM ENTRADA DE LEDGER (execução direta,
              não apply_migration) — mesmo regime das 2202, 2240 e 2241.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-09
Mandato.....: NEEDS_REVIEW — política "evidência caso a caso" e seleção de Fabrício
              em 2026-10-09 (8 famílias aprovadas; fracas = DEFERRED).
Origem......: database/proposals/2026-10-09-needs-review-revalidation/

Evidência (resumo; detalhe no README da proposta):
  NO_HOLO_ERROR          Team Rocket Dark Dragonite 5/82 sem holo (1ª Ed. e Unlimited);
                         PSA e CGC graduam a variedade.
  D_EDITION_ERROR        Jungle Butterfree 33/64 com selo "d EDITION"; PSA "D EDITION ERROR".
  ENERGY_SYMBOL_ERROR    Gym Challenge Blaine's Charizard 2/132: símbolo Lutador em vez de
                         Fogo; corrigido durante a tiragem Unlimited (artigo PSA).
  JAPANESE_BACK          Expedition Pichu e Hoppip: impressões de pré-lançamento (E3 2002)
                         com verso japonês (Bulbapedia).
  TEXT_ERROR             Texto impresso incorreto, corrigido em tiragem posterior:
                         Call of Legends Phanpy ("Phanphy") e Gym Challenge Rocket's
                         Minefield Gym (sem quantidade de contadores) (Bulbapedia).
  MISSING_RETREAT_COST   EX Sandstorm Marill 68/100 sem custo de recuo nas primeiras
                         tiragens; ruling oficial "play as printed" (Bulbapedia/PUI).
  SHIFTED_ENERGY_COST    Legendary Collection Exeggcute 75/110 reverse com camada de
                         impressão desalinhada sobre os custos de energia; lista CGC.

Todos: variedade de tiragem catalogada, não defeito de exemplar.

Regras: somente POKEMON; exatamente 7 traits, display_order 13..19. Não cria Profile,
mapping, Variant Type; não toca rows nem card_variant.
Pré-requisito: 12 traits POKEMON, display_order 1..12 contíguos (… + 2240 + 2241).
Como validar:
    SELECT code, display_order FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON' ORDER BY display_order;
    -- esperado: 19 linhas, 1..19 contíguos
===============================================================================
*/

DO $mig$
DECLARE
    v_game_id UUID; v_n INTEGER; v_aff INTEGER;
    v_p0 BIGINT; v_pem0 BIGINT; v_cv0 BIGINT;
    v_p1 BIGINT; v_pem1 BIGINT; v_cv1 BIGINT;
BEGIN
    SELECT id INTO v_game_id FROM public.game WHERE code = 'POKEMON';
    IF v_game_id IS NULL THEN RAISE EXCEPTION '2242_G0_GAME_NOT_FOUND'; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 12 THEN RAISE EXCEPTION '2242_G1_BASELINE: esperado 12, encontrado %.', v_n; END IF;
    IF EXISTS (SELECT 1 FROM generate_series(1,12) s WHERE NOT EXISTS
               (SELECT 1 FROM public.card_printing_trait t WHERE t.game_id = v_game_id AND t.display_order = s)) THEN
        RAISE EXCEPTION '2242_G1_ORDER_GAP';
    END IF;
    IF EXISTS (SELECT 1 FROM public.card_printing_trait WHERE game_id = v_game_id AND code IN
               ('NO_HOLO_ERROR','D_EDITION_ERROR','ENERGY_SYMBOL_ERROR','JAPANESE_BACK',
                'TEXT_ERROR','MISSING_RETREAT_COST','SHIFTED_ENERGY_COST')) THEN
        RAISE EXCEPTION '2242_G2_CODE_ALREADY_EXISTS';
    END IF;
    SELECT count(*) INTO v_p0 FROM public.card_printing_profile;
    SELECT count(*) INTO v_pem0 FROM public.card_printing_external_mapping;
    SELECT count(*) INTO v_cv0 FROM public.card_variant;

    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES
      (v_game_id, 'NO_HOLO_ERROR', 'Erro Sem Holo',
       'Carta do slot holográfico impressa sem holofoil. Erro de tiragem produzido em massa (ex.: Team Rocket Dark Dragonite 5/82); variedade catalogada e graduada separadamente, não defeito de exemplar.', 13),
      (v_game_id, 'D_EDITION_ERROR', 'Erro "d Edition"',
       'Selo de 1ª Edição impresso como "d EDITION" no lugar de "1 EDITION" em parte da tiragem (ex.: Jungle Butterfree 33/64). Variedade catalogada e graduada separadamente, não defeito de exemplar.', 14),
      (v_game_id, 'ENERGY_SYMBOL_ERROR', 'Erro de Símbolo de Energia',
       'Tiragem com símbolo de energia errado no texto de ataque, corrigido em tiragem posterior (ex.: Gym Challenge Blaine''s Charizard 2/132). Variedade catalogada, não defeito de exemplar.', 15),
      (v_game_id, 'JAPANESE_BACK', 'Verso Japonês',
       'Impressão de pré-lançamento com verso japonês em vez do verso inglês da tiragem de varejo (ex.: Expedition Pichu e Hoppip distribuídos na E3 2002). Variedade de tiragem catalogada.', 16),
      (v_game_id, 'TEXT_ERROR', 'Erro de Texto',
       'Tiragem inicial com texto impresso incorreto, corrigido em tiragem posterior (ex.: Call of Legends Phanpy "Phanphy"; Gym Challenge Rocket''s Minefield Gym). Variedade catalogada, não defeito de exemplar.', 17),
      (v_game_id, 'MISSING_RETREAT_COST', 'Sem Custo de Recuo',
       'Tiragem inicial impressa sem o custo de recuo, corrigida depois; regra oficial "jogar como impresso" (ex.: EX Sandstorm Marill 68/100). Variedade catalogada.', 18),
      (v_game_id, 'SHIFTED_ENERGY_COST', 'Custo de Energia Deslocado',
       'Tiragem com a camada de impressão dos custos de energia desalinhada em relação ao padrão reverse (ex.: Legendary Collection Exeggcute 75/110). Variedade catalogada e graduada, não defeito de exemplar.', 19);
    GET DIAGNOSTICS v_aff = ROW_COUNT;
    IF v_aff <> 7 THEN RAISE EXCEPTION '2242_W1_CARDINALITY: %', v_aff; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id = v_game_id;
    IF v_n <> 19 THEN RAISE EXCEPTION '2242_P1_TOTAL: %', v_n; END IF;
    SELECT count(*) INTO v_p1 FROM public.card_printing_profile;
    SELECT count(*) INTO v_pem1 FROM public.card_printing_external_mapping;
    SELECT count(*) INTO v_cv1 FROM public.card_variant;
    IF (v_p0, v_pem0, v_cv0) IS DISTINCT FROM (v_p1, v_pem1, v_cv1) THEN RAISE EXCEPTION '2242_P2_UNTOUCHED_DRIFT'; END IF;
    RAISE NOTICE '2242_OK: 7 traits (13..19).';
END;
$mig$;
