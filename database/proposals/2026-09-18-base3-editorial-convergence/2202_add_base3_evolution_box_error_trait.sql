/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2202 - Add BASE3 Printing Trait (EVOLUTION_BOX_ERROR)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE (2026-09-18 02:51:27 UTC)
              ATENÇÃO: execução direta no SQL Editor — NÃO há linha correspondente
              em supabase_migrations.schema_migrations (diferente de 2198/2199/
              2200/2201, que passaram por apply_migration). Divergência real de
              rastreabilidade, registrada e não mascarada.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-18
Mandato.....: BASE3 — IMPLEMENTATION STAGING-01

-------------------------------------------------------------------------------
POR QUE ESTA QUERY EXISTE
-------------------------------------------------------------------------------
`card_printing_trait` continua sendo a ÚNICA das cinco classes de objeto sem
writer canônico — nem público nem interno. Reauditado no LIVE nesta rodada:

    writers_de_trait = 0   (zero funções com INSERT INTO card_printing_trait)

Também não há `entity_type` para trait em `catalog_admin_action_log`. O modelo
trata trait como VOCABULÁRIO SEMEADO, não como objeto editorial de runtime.
Precedente direto e recente: a Query 2201 (BASEP), que acrescentou 3 termos
(`GREY_STAR_SYMBOL`, `GLOSSY_STOCK`, `AOKI_CREDIT`) exatamente por esta razão.

Esta Query é o mesmo caso, com UM termo. É o ÚNICO SQL fora do caminho canônico
em todo o fechamento de BASE3 — as demais escritas (Profile, Printing Mapping,
Variant Types, VT Mappings) passam pelas RPCs `public.admin_*` com sessão
administrativa real, via `base3-authenticated-runner.js`.

RELAÇÃO COM 2169 E 2201 — NENHUMA É ALTERADA
Ambas são histórico LIVE. Esta Query NÃO as edita, NÃO as reexecuta e NÃO as
substitui. É incremento, não reescrita — mesma disciplina de 6109/6110/6125/6126.

-------------------------------------------------------------------------------
Descrição resumida:
Insere EXATAMENTE 1 linha em `public.card_printing_trait`, Game POKEMON,
display_order 9. Nada além disso.

Descrição:
O trait foi ratificado em BASE3 — FINAL EDITORIAL RECONCILIATION-01, a partir de
evidência externa fechada (BASE3 — EXTERNAL EVIDENCE AUDIT-01):

  EVOLUTION_BOX_ERROR   Bulbapedia, Zapdos (Fossil 15), seção Trivia: as cartas
                        holográficas inglesas "lack Holofoil where the
                        Evolutionary Box for Stage 1 Pokémon and Stage 2 Pokémon
                        normally is" — Zapdos é Basic e não tem caixa de
                        evolução. Bulbapedia (Error cards) registra que o erro
                        foi "mass produced for unlimited print" E "mass produced
                        as a corrected unlimited print". Elite Fourum (guia
                        dedicado do Fossil Zapdos 15/62) detalha: a tiragem de
                        1ª Edição NUNCA foi corrigida; a Unlimited foi corrigida
                        tarde na tiragem.

                        Portanto: ERRO DE CHAPA, produzido em massa, corrigido
                        em tiragem posterior. Variedade de tiragem catalogada —
                        exatamente a classe semântica de AOKI_CREDIT (Query
                        2201), não defeito de exemplar.

                        RECONHECIMENTO POR GRADING — CONFIRMADO. O PSA Pokémon
                        Error Guide lista explicitamente "Zapdos-Holo Corrected
                        & Uncorrected Foil" e registra que a PSA reconhece AS
                        DUAS variações; existem certificados correntes rotulados
                        "1999 POKEMON FOSSIL #15 ZAPDOS-HOLO CORRECTED FOIL".
                        Isto REVOGA a leitura anterior — feita a partir de dois
                        links do guia comunitário que apontavam para o mesmo
                        spec — de que a PSA não separaria erro e corrigido. O
                        alinhamento com AOKI_CREDIT é, portanto, completo: erro
                        de tiragem, corrigido depois, reconhecido por grading.

DECOMPOSIÇÃO: o Profile `EVOLUTION_BOX_ERROR` (display_order 11, composto por
este único trait) NÃO é criado aqui. Ele é conhecimento DECLARATIVO e nasce na
fase seguinte, pela RPC canônica
`admin_create_card_printing_profile_with_backfill`.

DETERMINISMO: nenhum id é literal. O Game resolve por `game.code = 'POKEMON'`.

ATOMICIDADE: bloco `DO` único — uma única instrução SQL, portanto atômica mesmo
sob autocommit. Qualquer RAISE aborta a instrução inteira e nada é persistido.
Mesmo desenho das Queries 2200 e 2201.

-------------------------------------------------------------------------------
Regras de Negócio:
- Somente Game POKEMON.
- EXATAMENTE 1 trait inserido. Nem 0, nem 2.
- display_order 9 — contíguo ao 1..8 já existente, sem buracos.
- NÃO cria Profile. NÃO cria vínculo de composição. NÃO cria mapping externo.
- NÃO cria Variant Type nem mapping de Variant Type.
- NÃO toca job de importação, row de importação nem card_variant.
- NÃO altera nenhum dos 8 traits existentes.

Pré-requisitos:
- Query 2165 (tabela) aplicada.
- Query 2169 aplicada e íntegra (5 traits, display_order 1..5).
- Query 2201 aplicada e íntegra (3 traits, display_order 6..8).

Resultado esperado:
- 1 linha inserida.
- `card_printing_trait` POKEMON passa de 8 para 9 linhas.
- Contagem de card_printing_profile, card_printing_profile_trait,
  card_printing_external_mapping, card_variant_type,
  card_variant_type_external_mapping, card_variant e das rows NEEDS_REVIEW de
  BASE3: INALTERADAS (provado por fingerprint antes/depois).

Como validar (após execução, read-only):
    SELECT code, name, display_order, is_active
      FROM public.card_printing_trait t
      JOIN public.game g ON g.id = t.game_id
     WHERE g.code = 'POKEMON'
     ORDER BY t.display_order;
    -- esperado: 9 linhas, display_order 1..9 sem buracos, 9=EVOLUTION_BOX_ERROR
===============================================================================
*/

DO $mig$
DECLARE
    c_game_code   CONSTANT TEXT := 'POKEMON';
    c_job_id      CONSTANT UUID := 'd5b7a148-0459-40fd-a32f-13fdcb845026';

    v_game_id     UUID;
    v_affected    INTEGER;

    -- Fingerprints de NÃO-TOQUE (antes)
    v_n_profile_before        BIGINT;
    v_n_profile_trait_before  BIGINT;
    v_n_pem_before            BIGINT;
    v_n_vt_before             BIGINT;
    v_n_vtem_before           BIGINT;
    v_n_variant_before        BIGINT;
    v_n_residual_before       BIGINT;
    v_n_valid_before          BIGINT;
    v_n_trait_before          BIGINT;

    -- Fingerprints de NÃO-TOQUE (depois)
    v_n_profile_after         BIGINT;
    v_n_profile_trait_after   BIGINT;
    v_n_pem_after             BIGINT;
    v_n_vt_after              BIGINT;
    v_n_vtem_after            BIGINT;
    v_n_variant_after         BIGINT;
    v_n_residual_after        BIGINT;
    v_n_valid_after           BIGINT;
    v_n_trait_after           BIGINT;

    v_job_status_before       TEXT;
    v_job_total_before        INTEGER;
    v_job_valid_before        INTEGER;
    v_job_status_after        TEXT;
    v_job_total_after         INTEGER;
    v_job_valid_after         INTEGER;

    v_ok          BOOLEAN;
BEGIN
    -- =========================================================================
    -- G0. RESOLUÇÃO DETERMINÍSTICA DO GAME
    -- =========================================================================
    SELECT g.id INTO v_game_id
      FROM public.game g
     WHERE g.code = c_game_code;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'BASE3_2202_G0_GAME_NOT_FOUND: Game code=% inexistente. STOP.', c_game_code;
    END IF;

    -- =========================================================================
    -- G1. BASELINE — 8 traits (5 da Query 2169 + 3 da Query 2201), ordens 1..8
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_trait_before
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id;

    IF v_n_trait_before <> 8 THEN
        RAISE EXCEPTION 'BASE3_2202_G1_BASELINE_TRAIT_COUNT: esperado 8 traits POKEMON (2169 + 2201), encontrado %. Baseline divergente — STOP.', v_n_trait_before;
    END IF;

    SELECT COUNT(*) = 8 INTO v_ok
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id
       AND t.code IN ('FIRST_EDITION','SHADOWLESS','UNLIMITED','COPYRIGHT_1999_2000','RED_CHEEK',
                      'GREY_STAR_SYMBOL','GLOSSY_STOCK','AOKI_CREDIT');

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASE3_2202_G1_BASELINE_TRAIT_CODES: os 8 codes ratificados pelas Queries 2169/2201 não conferem. STOP.';
    END IF;

    SELECT NOT EXISTS (
        SELECT g FROM generate_series(1, 8) g
         WHERE NOT EXISTS (
            SELECT 1 FROM public.card_printing_trait t
             WHERE t.game_id = v_game_id AND t.display_order = g)
    ) INTO v_ok;

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASE3_2202_G1_BASELINE_ORDER_GAP: display_order 1..8 tem buraco ANTES da escrita. Baseline divergente — STOP.';
    END IF;

    -- =========================================================================
    -- G2. O CODE PRECISA ESTAR AUSENTE
    -- =========================================================================
    IF EXISTS (
        SELECT 1 FROM public.card_printing_trait t
         WHERE t.game_id = v_game_id
           AND t.code = 'EVOLUTION_BOX_ERROR'
    ) THEN
        RAISE EXCEPTION 'BASE3_2202_G2_CODE_ALREADY_EXISTS: EVOLUTION_BOX_ERROR já existe. Esta Query não é idempotente por desenho — STOP e reauditar.';
    END IF;

    -- =========================================================================
    -- G3. display_order 9 PRECISA ESTAR LIVRE
    --     (UNIQUE (game_id, display_order) — a colisão seria erro de constraint,
    --      mas o guard existe para falhar com mensagem legível, não com 23505.)
    -- =========================================================================
    IF EXISTS (
        SELECT 1 FROM public.card_printing_trait t
         WHERE t.game_id = v_game_id
           AND t.display_order = 9
    ) THEN
        RAISE EXCEPTION 'BASE3_2202_G3_DISPLAY_ORDER_TAKEN: display_order 9 não está livre em POKEMON. STOP.';
    END IF;

    -- =========================================================================
    -- G4. FINGERPRINTS DE NÃO-TOQUE — ANTES
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_profile_before       FROM public.card_printing_profile;
    SELECT COUNT(*) INTO v_n_profile_trait_before FROM public.card_printing_profile_trait;
    SELECT COUNT(*) INTO v_n_pem_before           FROM public.card_printing_external_mapping;
    SELECT COUNT(*) INTO v_n_vt_before            FROM public.card_variant_type;
    SELECT COUNT(*) INTO v_n_vtem_before          FROM public.card_variant_type_external_mapping;
    SELECT COUNT(*) INTO v_n_variant_before       FROM public.card_variant;

    SELECT COUNT(*) FILTER (WHERE r.validation_status = 'NEEDS_REVIEW'),
           COUNT(*) FILTER (WHERE r.validation_status = 'VALID')
      INTO v_n_residual_before, v_n_valid_before
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = c_job_id;

    IF v_n_residual_before <> 5 THEN
        RAISE EXCEPTION 'BASE3_2202_G4_RESIDUAL_BASELINE: esperado 5 rows NEEDS_REVIEW no job BASE3, encontrado %. STOP.', v_n_residual_before;
    END IF;

    IF v_n_valid_before <> 172 THEN
        RAISE EXCEPTION 'BASE3_2202_G4_VALID_BASELINE: esperado 172 rows VALID no job BASE3, encontrado %. STOP.', v_n_valid_before;
    END IF;

    SELECT j.status, j.total_rows, j.valid_rows
      INTO v_job_status_before, v_job_total_before, v_job_valid_before
      FROM public.catalog_variant_import_job j
     WHERE j.id = c_job_id;

    IF v_job_status_before IS NULL THEN
        RAISE EXCEPTION 'BASE3_2202_G4_JOB_NOT_FOUND: job BASE3 % inexistente. STOP.', c_job_id;
    END IF;

    IF v_job_status_before <> 'STAGED' OR v_job_total_before <> 177 OR v_job_valid_before <> 172 THEN
        RAISE EXCEPTION 'BASE3_2202_G4_JOB_BASELINE: esperado STAGED/177/172, obtido %/%/%. STOP.',
                        v_job_status_before, v_job_total_before, v_job_valid_before;
    END IF;

    -- =========================================================================
    -- W1. ESCRITA ÚNICA — 1 linha, valores literais e explícitos
    -- =========================================================================
    INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
    VALUES
        (v_game_id,
         'EVOLUTION_BOX_ERROR',
         'Erro da Caixa de Evolução',
         'Tiragem cuja chapa holográfica reserva o recorte da caixa de evolução no canto superior esquerdo, deixando essa área sem holofoil em uma carta que não evolui. Erro de chapa produzido em massa e corrigido em tiragem posterior — variedade de tiragem catalogada, não defeito de exemplar.',
         9);

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    IF v_affected <> 1 THEN
        RAISE EXCEPTION 'BASE3_2202_W1_INSERT_CARDINALITY: esperado 1 linha inserida, obtido %. STOP.', v_affected;
    END IF;

    -- =========================================================================
    -- P1. PÓS-CONDIÇÃO — total e contiguidade de display_order
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_trait_after
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id;

    IF v_n_trait_after <> 9 THEN
        RAISE EXCEPTION 'BASE3_2202_P1_TRAIT_TOTAL: esperado 9 traits POKEMON após a escrita, obtido %. STOP.', v_n_trait_after;
    END IF;

    SELECT NOT EXISTS (
        SELECT g FROM generate_series(1, 9) g
         WHERE NOT EXISTS (
            SELECT 1 FROM public.card_printing_trait t
             WHERE t.game_id = v_game_id AND t.display_order = g)
    ) INTO v_ok;

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASE3_2202_P1_DISPLAY_ORDER_GAP: display_order 1..9 tem buraco após a escrita. STOP.';
    END IF;

    -- =========================================================================
    -- P2. PÓS-CONDIÇÃO — valores EXATOS da linha nova, campo a campo
    -- =========================================================================
    SELECT COUNT(*) = 1 INTO v_ok
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id
       AND t.code = 'EVOLUTION_BOX_ERROR'
       AND t.display_order = 9
       AND t.is_active IS TRUE
       AND t.name = 'Erro da Caixa de Evolução'
       AND t.description = 'Tiragem cuja chapa holográfica reserva o recorte da caixa de evolução no canto superior esquerdo, deixando essa área sem holofoil em uma carta que não evolui. Erro de chapa produzido em massa e corrigido em tiragem posterior — variedade de tiragem catalogada, não defeito de exemplar.';

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASE3_2202_P2_VALUE_MISMATCH: a linha nova não confere em code/name/description/display_order/is_active. STOP.';
    END IF;

    -- =========================================================================
    -- P3. PÓS-CONDIÇÃO — os 8 traits originais permanecem intocados
    -- =========================================================================
    SELECT COUNT(*) = 8 INTO v_ok
      FROM public.card_printing_trait t
     WHERE t.game_id = v_game_id
       AND t.display_order BETWEEN 1 AND 8
       AND t.code IN ('FIRST_EDITION','SHADOWLESS','UNLIMITED','COPYRIGHT_1999_2000','RED_CHEEK',
                      'GREY_STAR_SYMBOL','GLOSSY_STOCK','AOKI_CREDIT');

    IF NOT v_ok THEN
        RAISE EXCEPTION 'BASE3_2202_P3_BASELINE_DRIFT: os 8 traits das Queries 2169/2201 foram alterados. STOP.';
    END IF;

    -- =========================================================================
    -- P4. PÓS-CONDIÇÃO — NÃO-TOQUE provado por fingerprint
    -- =========================================================================
    SELECT COUNT(*) INTO v_n_profile_after       FROM public.card_printing_profile;
    SELECT COUNT(*) INTO v_n_profile_trait_after FROM public.card_printing_profile_trait;
    SELECT COUNT(*) INTO v_n_pem_after           FROM public.card_printing_external_mapping;
    SELECT COUNT(*) INTO v_n_vt_after            FROM public.card_variant_type;
    SELECT COUNT(*) INTO v_n_vtem_after          FROM public.card_variant_type_external_mapping;
    SELECT COUNT(*) INTO v_n_variant_after       FROM public.card_variant;

    SELECT COUNT(*) FILTER (WHERE r.validation_status = 'NEEDS_REVIEW'),
           COUNT(*) FILTER (WHERE r.validation_status = 'VALID')
      INTO v_n_residual_after, v_n_valid_after
      FROM public.catalog_variant_import_row r
     WHERE r.job_id = c_job_id;

    SELECT j.status, j.total_rows, j.valid_rows
      INTO v_job_status_after, v_job_total_after, v_job_valid_after
      FROM public.catalog_variant_import_job j
     WHERE j.id = c_job_id;

    IF v_n_profile_after <> v_n_profile_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_PROFILE_TOUCHED: card_printing_profile mudou de % para %. STOP.', v_n_profile_before, v_n_profile_after;
    END IF;

    IF v_n_profile_trait_after <> v_n_profile_trait_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_PROFILE_TRAIT_TOUCHED: card_printing_profile_trait mudou de % para %. STOP.', v_n_profile_trait_before, v_n_profile_trait_after;
    END IF;

    IF v_n_pem_after <> v_n_pem_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_PEM_TOUCHED: card_printing_external_mapping mudou de % para %. STOP.', v_n_pem_before, v_n_pem_after;
    END IF;

    IF v_n_vt_after <> v_n_vt_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_VT_TOUCHED: card_variant_type mudou de % para %. STOP.', v_n_vt_before, v_n_vt_after;
    END IF;

    IF v_n_vtem_after <> v_n_vtem_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_VTEM_TOUCHED: card_variant_type_external_mapping mudou de % para %. STOP.', v_n_vtem_before, v_n_vtem_after;
    END IF;

    IF v_n_variant_after <> v_n_variant_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_CARD_VARIANT_TOUCHED: card_variant mudou de % para %. STOP.', v_n_variant_before, v_n_variant_after;
    END IF;

    IF v_n_residual_after <> v_n_residual_before OR v_n_valid_after <> v_n_valid_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_ROWS_TOUCHED: rows de BASE3 mudaram (NEEDS_REVIEW %->%, VALID %->%). STOP.',
                        v_n_residual_before, v_n_residual_after, v_n_valid_before, v_n_valid_after;
    END IF;

    IF v_job_status_after <> v_job_status_before
       OR v_job_total_after <> v_job_total_before
       OR v_job_valid_after <> v_job_valid_before THEN
        RAISE EXCEPTION 'BASE3_2202_P4_JOB_TOUCHED: cabeçalho do job BASE3 mudou de %/%/% para %/%/%. STOP.',
                        v_job_status_before, v_job_total_before, v_job_valid_before,
                        v_job_status_after, v_job_total_after, v_job_valid_after;
    END IF;

    RAISE NOTICE 'BASE3_2202_OK: 1 trait inserido (9=EVOLUTION_BOX_ERROR). Total POKEMON: % -> %. Profiles/links/mappings/VTs/variants/job BASE3 inalterados.',
                 v_n_trait_before, v_n_trait_after;
END;
$mig$;
