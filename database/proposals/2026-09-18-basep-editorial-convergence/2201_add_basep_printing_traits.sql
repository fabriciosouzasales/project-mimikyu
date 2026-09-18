/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2201 - Add BASEP Printing Traits (GREY_STAR_SYMBOL, GLOSSY_STOCK, AOKI_CREDIT)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE (migration 20260918011647, 2026-09-18)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-18
Mandato.....: BASEP — IMPLEMENTATION STAGING-01

-------------------------------------------------------------------------------
POR QUE ESTA QUERY EXISTE
-------------------------------------------------------------------------------
`card_printing_trait` é a ÚNICA das cinco classes de objeto envolvidas no
fechamento de BASEP que NÃO possui writer canônico — nem público nem interno.
Auditoria do LIVE (BASEP — IMPLEMENTATION TRANSPORT AUDIT-01):

    writers_de_trait = []   (zero funções com INSERT INTO card_printing_trait)

Não há tampouco `entity_type` para trait em `catalog_admin_action_log`: o
CHECK admite CARD_PRINTING_PROFILE e CARD_PRINTING_EXTERNAL_MAPPING, mas não
CARD_PRINTING_TRAIT. Ou seja — o modelo tratou trait como VOCABULÁRIO SEMEADO,
não como objeto editorial criado em runtime. Os 5 traits atuais nasceram todos
no mesmo timestamp (2026-09-12 19:13:52), pela Query 2169.

Esta Query segue exatamente esse precedente: acrescenta 3 termos ao vocabulário
já ratificado. Ela é o ÚNICO SQL fora do caminho canônico em todo o fechamento
de BASEP — as outras quatro classes (Profile, Printing Mapping, Variant Type,
VT Mapping) passam pelas RPCs `public.admin_*` com sessão administrativa real.

RELAÇÃO COM A QUERY 2169 — NÃO ALTERADA
A Query 2169 (`database/schema/2169_seed_card_printing_traits_and_profiles.sql`)
é histórico LIVE e declara no próprio cabeçalho: "O SQL executavel permanece
INTOCADO desde a execucao". Esta Query 2201 NÃO a edita, NÃO a reexecuta e NÃO
a substitui. É incremento, não reescrita — mesma disciplina de 6109/6110/6125/6126.

-------------------------------------------------------------------------------
Descrição resumida:
Insere EXATAMENTE 3 linhas em `public.card_printing_trait`, Game POKEMON,
display_order 6, 7 e 8. Nada além disso.

Descrição:
Os 3 traits foram ratificados em BASEP — FINAL RECONCILIATION-01, a partir de
evidência externa fechada (BASEP — EXTERNAL EVIDENCE AUDIT-02):

  GREY_STAR_SYMBOL  Bulbapedia, Pikachu (Wizards Promo 1): a tiragem do Hyper
                    CoroCoro (Japão, 01/03/1999) traz "a gray star symbol with
                    a yellow PROMO superimposed" no lugar da estrela preta.
                    É SÍMBOLO DE COLEÇÃO, não selo aplicado.

  GLOSSY_STOCK      Bulbapedia, Mew (Wizards Promo 8): "a glossy version of the
                    initial English print" (Gotta Comic, Japão, 01/05/2000).
                    A mesma fonte descreve a tiragem Grey Star como estando
                    igualmente em "glossy Japanese card stock" — daí os dois
                    traits serem independentes e o Profile da Grey Star os
                    compor, em vez de existir um trait monolítico.

  AOKI_CREDIT       PSA, Pokémon Error Guide, verbatim: "An error crediting
                    illustrator Toshinao Aoki instead of Naoyo Kimura has been
                    found on all three Pokémon the Movie 2000 promos — Articuno,
                    Zapdos, and Moltres ... later corrected, which PSA also
                    recognizes." Erro de tiragem, corrigido depois; variedade
                    catalogada, não defeito de exemplar.

DECOMPOSIÇÃO — mesma regra da 2169: a composição
`grey-star -> GREY_STAR_SYMBOL + GLOSSY_STOCK` é conhecimento DECLARATIVO, e
não mora aqui. Ela será expressa pelo Profile GREY_STAR_GLOSSY, criado na fase
seguinte pela RPC canônica `admin_create_card_printing_profile_with_backfill`.
Nenhuma regra desta Query divide strings por hífen.

DETERMINISMO: nenhum id é literal. O Game resolve por `game.code = 'POKEMON'`.

ATOMICIDADE: bloco `DO` único — uma única instrução SQL, portanto atômica
mesmo sob autocommit. Qualquer RAISE aborta a instrução inteira e nada é
persistido. Mesmo desenho da Query 2200.

-------------------------------------------------------------------------------
Regras de Negócio:
- Somente Game POKEMON.
- EXATAMENTE 3 traits inseridos. Nem 2, nem 4.
- display_order 6, 7, 8 — contíguos ao 1..5 já existente, sem buracos.
- NÃO cria Profile. NÃO cria vínculo de composição. NÃO cria mapping externo.
- NÃO toca job de importação, row de importação nem card_variant.
- NÃO altera nenhum dos 5 traits existentes.

Pré-requisitos:
- Query 2165 (tabela) aplicada.
- Query 2169 aplicada e íntegra (5 traits POKEMON, display_order 1..5).

Resultado esperado:
- 3 linhas inseridas.
- `card_printing_trait` POKEMON passa de 5 para 8 linhas.
- Contagem de card_printing_profile, card_printing_profile_trait,
  card_printing_external_mapping, card_variant e das rows NEEDS_REVIEW de
  BASEP: INALTERADAS (provado por fingerprint antes/depois).

Como validar (após execução, read-only):
    SELECT code, name, display_order, is_active
      FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON'
     ORDER BY t.display_order;
    -- esperado: 8 linhas, display_order 1..8 sem buracos,
    --           6=GREY_STAR_SYMBOL, 7=GLOSSY_STOCK, 8=AOKI_CREDIT
===============================================================================
*/

DO $mig$
DECLARE
    c_game_code   CONSTANT TEXT := 'POKEMON';
    c_job_id      CONSTANT UUID := 'cf829d56-921c-4e97-983d-0aec56690464';

    v_game_id     UUID;
    v_affected    INTEGER;

    -- Fingerprints de NÃO-TOQUE (antes)
    v_n_profile_before        BIGINT;
    v_n_profile_trait_before  BIGINT;
    v_n_pem_before            BIGINT;
    v_n_variant_before        BIGINT;
    v_n_residual_before       BIGINT;
    v_n_trait_before          BIGINT;

    -- Fingerprints de NÃO-TOQUE (depois)
    v_n_profile_after         BIGINT;
    v_n_profile_trait_after   BIGINT;
    v_n_pem_after             BIGINT;
    v_n_variant_after         BIGINT;
    v_n_residual_after        BIGINT;
    v_n_trait_after           BIGINT;

    v_ok          BOOLEAN;
BEGIN
    -- =========================================================================
    -- G0. RESOLUÇÃO DETERMINÍSTICA DO GAME
    -- =========================================================================
    SELECT g.id INTO v_game_id
      FROM public.game g
     WHERE g.code = c_game_code;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'BASEP_2201_G0_GAME_NOT_FOUND: Game code=% inexistente. STOP.', c_game_code;
    END IF;

    -- =========================================================================
    -- G1. BASELINE — os 5 traits da Query 2169 precisam estar íntegros
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_trait_before
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id;

    IF v_n_trait_before <> 5 THEN
        RAISE EXCEPTION 'BASEP_2201_G1_BASELINE_TRAIT_COUNT: esperado 5 traits POKEMON (Query 2169), encontrado %. Baseline divergente — STOP.', v_n_trait_before;
    END IF;

    SELECT COUNT(*) = 5 INTO v_ok
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id
       AND t.code IN ('FIRST_EDITION','SHADOWLESS','UNLIMITED','COPYRIGHT_1999_2000','RED_CHEEK');

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASEP_2201_G1_BASELINE_TRAIT_CODES: os 5 codes ratificados pela Query 2169 não conferem. STOP.';
    END IF;

    -- =========================================================================
    -- G2. OS 3 CODES PRECISAM ESTAR AUSENTES
    -- =========================================================================
    IF EXISTS (
        SELECT 1 FROM public.card_printing_trait t
         WHERE t.game_id = v_game_id
           AND t.code IN ('GREY_STAR_SYMBOL','GLOSSY_STOCK','AOKI_CREDIT')
    ) THEN
        RAISE EXCEPTION 'BASEP_2201_G2_CODE_ALREADY_EXISTS: pelo menos um dos 3 codes já existe. Esta Query não é idempotente por desenho — STOP e reauditar.';
    END IF;

    -- =========================================================================
    -- G3. display_order 6, 7 e 8 PRECISAM ESTAR LIVRES
    --     (UNIQUE (game_id, display_order) — a colisão seria erro de constraint,
    --      mas o guard existe para falhar com mensagem legível, não com 23505.)
    -- =========================================================================
    IF EXISTS (
        SELECT 1 FROM public.card_printing_trait t
         WHERE t.game_id = v_game_id
           AND t.display_order IN (6, 7, 8)
    ) THEN
        RAISE EXCEPTION 'BASEP_2201_G3_DISPLAY_ORDER_TAKEN: display_order 6/7/8 não está livre em POKEMON. STOP.';
    END IF;

    -- =========================================================================
    -- G4. FINGERPRINTS DE NÃO-TOQUE — ANTES
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_profile_before       FROM public.card_printing_profile;
    SELECT COUNT(*) INTO v_n_profile_trait_before FROM public.card_printing_profile_trait;
    SELECT COUNT(*) INTO v_n_pem_before           FROM public.card_printing_external_mapping;
    SELECT COUNT(*) INTO v_n_variant_before       FROM public.card_variant;
    SELECT COUNT(*) INTO v_n_residual_before
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = c_job_id AND r.validation_status = 'NEEDS_REVIEW';

    IF v_n_residual_before <> 27 THEN
        RAISE EXCEPTION 'BASEP_2201_G4_RESIDUAL_BASELINE: esperado 27 rows NEEDS_REVIEW no job BASEP, encontrado %. STOP.', v_n_residual_before;
    END IF;

    -- =========================================================================
    -- W1. ESCRITA ÚNICA — 3 linhas, valores literais e explícitos
    -- =========================================================================
    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES
        (v_game_id,
         'GREY_STAR_SYMBOL',
         'Símbolo Estrela Cinza',
         'Tiragem cujo símbolo promocional é uma estrela CINZA com "PROMO" em amarelo, no lugar da estrela preta das Black Star Promos. Característica do símbolo de coleção impresso, não de selo aplicado após a impressão. Observada na tiragem japonesa do Hyper CoroCoro (março de 1999).',
         6),
        (v_game_id,
         'GLOSSY_STOCK',
         'Card Stock Brilhante',
         'Tiragem impressa em card stock japonês de superfície brilhante, distinta do acabamento fosco padrão da mesma impressão. Característica de tiragem, não de acabamento de arte nem de selo.',
         7),
        (v_game_id,
         'AOKI_CREDIT',
         'Crédito Toshinao Aoki',
         'Tiragem que credita o ilustrador Toshinao Aoki no lugar de Naoyo Kimura. Erro de conteúdo impresso herdado do texto japonês original, corrigido em tiragem posterior. Variedade catalogada — não é defeito de exemplar.',
         8);

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    IF v_affected <> 3 THEN
        RAISE EXCEPTION 'BASEP_2201_W1_INSERT_CARDINALITY: esperado 3 linhas inseridas, obtido %. STOP.', v_affected;
    END IF;

    -- =========================================================================
    -- P1. PÓS-CONDIÇÃO — total e contiguidade de display_order
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_trait_after
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id;

    IF v_n_trait_after <> 8 THEN
        RAISE EXCEPTION 'BASEP_2201_P1_TRAIT_TOTAL: esperado 8 traits POKEMON após a escrita, obtido %. STOP.', v_n_trait_after;
    END IF;

    SELECT NOT EXISTS (
        SELECT g FROM generate_series(1, 8) g
         WHERE NOT EXISTS (
            SELECT 1 FROM public.card_printing_trait t
             WHERE t.game_id = v_game_id AND t.display_order = g)
    ) INTO v_ok;

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASEP_2201_P1_DISPLAY_ORDER_GAP: display_order 1..8 tem buraco após a escrita. STOP.';
    END IF;

    -- =========================================================================
    -- P2. PÓS-CONDIÇÃO — valores EXATOS das 3 linhas novas
    -- =========================================================================
    SELECT COUNT(*) = 3 INTO v_ok
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id
       AND t.is_active IS TRUE
       AND (
             (t.code = 'GREY_STAR_SYMBOL' AND t.display_order = 6 AND t.name = 'Símbolo Estrela Cinza')
          OR (t.code = 'GLOSSY_STOCK'     AND t.display_order = 7 AND t.name = 'Card Stock Brilhante')
          OR (t.code = 'AOKI_CREDIT'      AND t.display_order = 8 AND t.name = 'Crédito Toshinao Aoki')
       );

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASEP_2201_P2_VALUE_MISMATCH: as 3 linhas novas não conferem em code/display_order/name/is_active. STOP.';
    END IF;

    -- =========================================================================
    -- P3. PÓS-CONDIÇÃO — os 5 traits originais permanecem intocados
    -- =========================================================================
    SELECT COUNT(*) = 5 INTO v_ok
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id
       AND t.display_order BETWEEN 1 AND 5
       AND t.code IN ('FIRST_EDITION','SHADOWLESS','UNLIMITED','COPYRIGHT_1999_2000','RED_CHEEK');

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASEP_2201_P3_BASELINE_DRIFT: os 5 traits da Query 2169 foram alterados. STOP.';
    END IF;

    -- =========================================================================
    -- P4. PÓS-CONDIÇÃO — NÃO-TOQUE provado por fingerprint
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_profile_after       FROM public.card_printing_profile;
    SELECT COUNT(*) INTO v_n_profile_trait_after FROM public.card_printing_profile_trait;
    SELECT COUNT(*) INTO v_n_pem_after           FROM public.card_printing_external_mapping;
    SELECT COUNT(*) INTO v_n_variant_after       FROM public.card_variant;
    SELECT COUNT(*) INTO v_n_residual_after
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = c_job_id AND r.validation_status = 'NEEDS_REVIEW';

    IF v_n_profile_after <> v_n_profile_before THEN
        RAISE EXCEPTION 'BASEP_2201_P4_PROFILE_TOUCHED: card_printing_profile mudou de % para %. STOP.', v_n_profile_before, v_n_profile_after;
    END IF;

    IF v_n_profile_trait_after <> v_n_profile_trait_before THEN
        RAISE EXCEPTION 'BASEP_2201_P4_PROFILE_TRAIT_TOUCHED: card_printing_profile_trait mudou de % para %. STOP.', v_n_profile_trait_before, v_n_profile_trait_after;
    END IF;

    IF v_n_pem_after <> v_n_pem_before THEN
        RAISE EXCEPTION 'BASEP_2201_P4_PEM_TOUCHED: card_printing_external_mapping mudou de % para %. STOP.', v_n_pem_before, v_n_pem_after;
    END IF;

    IF v_n_variant_after <> v_n_variant_before THEN
        RAISE EXCEPTION 'BASEP_2201_P4_CARD_VARIANT_TOUCHED: card_variant mudou de % para %. STOP.', v_n_variant_before, v_n_variant_after;
    END IF;

    IF v_n_residual_after <> v_n_residual_before THEN
        RAISE EXCEPTION 'BASEP_2201_P4_RESIDUAL_TOUCHED: rows NEEDS_REVIEW de BASEP mudaram de % para %. STOP.', v_n_residual_before, v_n_residual_after;
    END IF;

    RAISE NOTICE 'BASEP_2201_OK: 3 traits inseridos (6=GREY_STAR_SYMBOL, 7=GLOSSY_STOCK, 8=AOKI_CREDIT). Total POKEMON: % -> %. Profiles/links/mappings/variants/residuais inalterados.',
                 v_n_trait_before, v_n_trait_after;
END;
$mig$;
