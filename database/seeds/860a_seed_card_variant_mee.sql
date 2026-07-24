/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 860A - Seed Card Variant MEE
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-20

Descrição resumida:
Cadastra e atualiza explicitamente as 16 variantes editoriais das 8 Cards do
Card Set MEE - Energia Básica Megaevolução.

Distribuição canônica:
- STANDARD: 8
- REVERSE_HOLO: 8
- Total: 16

Regras editoriais:
- Cada Card possui exatamente duas variantes.
- STANDARD:
    variant_order = 1
    is_default = TRUE
- REVERSE_HOLO:
    variant_order = 2
    is_default = FALSE
- A Query é idempotente.
- Variantes adicionais não são excluídas silenciosamente.
- Qualquer divergência provoca rollback integral.

Pré-requisitos:
- Query 840 - Seed Card.
- Query 850 - Seed Card Variant Type.
- Query 160 - Create Card Variant Table.
- Query 161 - Create Card Variant Triggers.
===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;
    v_card_set_id UUID;

    v_card_count INTEGER;
    v_variant_type_count INTEGER;

    v_matrix JSONB := $matrix$
[
    {
        "collector_number": "001",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "001",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    },
    {
        "collector_number": "002",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "002",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    },
    {
        "collector_number": "003",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "003",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    },
    {
        "collector_number": "004",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "004",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    },
    {
        "collector_number": "005",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "005",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    },
    {
        "collector_number": "006",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "006",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    },
    {
        "collector_number": "007",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "007",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    },
    {
        "collector_number": "008",
        "variant_type_code": "STANDARD",
        "variant_order": 1,
        "is_default": true
    },
    {
        "collector_number": "008",
        "variant_type_code": "REVERSE_HOLO",
        "variant_order": 2,
        "is_default": false
    }
]
$matrix$::JSONB;

    v_item JSONB;

    v_collector_number TEXT;
    v_variant_type_code TEXT;
    v_variant_order INTEGER;
    v_is_default BOOLEAN;

    v_card_id UUID;
    v_variant_type_id UUID;

    v_matrix_count INTEGER;
    v_distinct_card_count INTEGER;
    v_default_error_count INTEGER;
    v_duplicate_count INTEGER;

    v_registered_count INTEGER;
    v_standard_count INTEGER;
    v_reverse_holo_count INTEGER;

    v_additional_count INTEGER;
    v_divergent_count INTEGER;
    v_invalid_default_count INTEGER;
BEGIN
    -- ========================================================================
    -- 1. Localizar o Game POKEMON
    -- ========================================================================

    SELECT g.id
      INTO v_game_id
      FROM public.game AS g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Query 860A interrompida: o Game POKEMON não está cadastrado.';
    END IF;

    -- ========================================================================
    -- 2. Localizar o Card Set MEE
    -- ========================================================================

    SELECT cs.id
      INTO v_card_set_id
      FROM public.card_set AS cs
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE e.game_id = v_game_id
       AND cs.code = 'MEE';

    IF v_card_set_id IS NULL THEN
        RAISE EXCEPTION
            'Query 860A interrompida: o Card Set MEE não está cadastrado.';
    END IF;

    -- ========================================================================
    -- 3. Validar a quantidade de Cards de MEE
    -- ========================================================================

    SELECT COUNT(*)
      INTO v_card_count
      FROM public.card AS c
     WHERE c.card_set_id = v_card_set_id;

    IF v_card_count <> 8 THEN
        RAISE EXCEPTION
            'Query 860A interrompida: MEE possui % Cards, mas o esperado é 8.',
            v_card_count;
    END IF;

    -- ========================================================================
    -- 4. Validar os tipos de variante necessários
    -- ========================================================================

    SELECT COUNT(*)
      INTO v_variant_type_count
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND cvt.code IN (
            'STANDARD',
            'REVERSE_HOLO'
       );

    IF v_variant_type_count <> 2 THEN
        RAISE EXCEPTION
            'Query 860A interrompida: STANDARD e REVERSE_HOLO devem estar cadastrados para o Game POKEMON.';
    END IF;

    -- ========================================================================
    -- 5. Validar a quantidade de linhas da matriz
    -- ========================================================================

    v_matrix_count := jsonb_array_length(v_matrix);

    IF v_matrix_count <> 16 THEN
        RAISE EXCEPTION
            'A matriz editorial de MEE possui % linhas, mas o esperado é 16.',
            v_matrix_count;
    END IF;

    -- ========================================================================
    -- 6. Validar a quantidade de Cards distintas da matriz
    -- ========================================================================

    SELECT COUNT(
               DISTINCT item->>'collector_number'
           )
      INTO v_distinct_card_count
      FROM jsonb_array_elements(v_matrix) AS item;

    IF v_distinct_card_count <> 8 THEN
        RAISE EXCEPTION
            'A matriz editorial de MEE referencia % Cards distintas, mas o esperado é 8.',
            v_distinct_card_count;
    END IF;

    -- ========================================================================
    -- 7. Impedir duplicidades dentro da matriz
    -- ========================================================================

    SELECT COUNT(*)
      INTO v_duplicate_count
      FROM (
            SELECT
                item->>'collector_number' AS collector_number,
                item->>'variant_type_code' AS variant_type_code
            FROM jsonb_array_elements(v_matrix) AS item
            GROUP BY
                item->>'collector_number',
                item->>'variant_type_code'
            HAVING COUNT(*) > 1
      ) AS duplicated_items;

    IF v_duplicate_count <> 0 THEN
        RAISE EXCEPTION
            'A matriz editorial de MEE contém % combinações duplicadas de Card e variante.',
            v_duplicate_count;
    END IF;

    -- ========================================================================
    -- 8. Validar exatamente uma variante padrão por Card
    -- ========================================================================

    SELECT COUNT(*)
      INTO v_default_error_count
      FROM (
            SELECT
                item->>'collector_number' AS collector_number
            FROM jsonb_array_elements(v_matrix) AS item
            GROUP BY item->>'collector_number'
            HAVING COUNT(*) FILTER (
                WHERE (item->>'is_default')::BOOLEAN = TRUE
            ) <> 1
      ) AS invalid_defaults;

    IF v_default_error_count <> 0 THEN
        RAISE EXCEPTION
            'A matriz editorial contém % Cards sem exatamente uma variante padrão.',
            v_default_error_count;
    END IF;

    -- ========================================================================
    -- 9. Validar todas as referências antes de alterar os dados
    -- ========================================================================

    FOR v_item IN
        SELECT value
          FROM jsonb_array_elements(v_matrix)
    LOOP
        v_collector_number :=
            v_item->>'collector_number';

        v_variant_type_code :=
            v_item->>'variant_type_code';

        v_variant_order :=
            (v_item->>'variant_order')::INTEGER;

        v_is_default :=
            (v_item->>'is_default')::BOOLEAN;

        SELECT c.id
          INTO v_card_id
          FROM public.card AS c
         WHERE c.card_set_id = v_card_set_id
           AND c.collector_number = v_collector_number;

        IF v_card_id IS NULL THEN
            RAISE EXCEPTION
                'Query 860A interrompida: a Card % não foi encontrada em MEE.',
                v_collector_number;
        END IF;

        SELECT cvt.id
          INTO v_variant_type_id
          FROM public.card_variant_type AS cvt
         WHERE cvt.game_id = v_game_id
           AND cvt.code = v_variant_type_code;

        IF v_variant_type_id IS NULL THEN
            RAISE EXCEPTION
                'Query 860A interrompida: o Card Variant Type % não foi encontrado.',
                v_variant_type_code;
        END IF;

        IF v_variant_order <= 0 THEN
            RAISE EXCEPTION
                'Query 860A interrompida: variant_order inválido para a Card %.',
                v_collector_number;
        END IF;
    END LOOP;

    -- ========================================================================
    -- 10. Preparar registros existentes para convergência segura
    -- ========================================================================

    UPDATE public.card_variant AS cv
       SET variant_order = cv.variant_order + 1000,
           is_default = FALSE
      FROM public.card AS c
     WHERE cv.card_id = c.id
       AND c.card_set_id = v_card_set_id;

    -- ========================================================================
    -- 11. Inserir ou atualizar a matriz editorial
    -- ========================================================================

    FOR v_item IN
        SELECT value
          FROM jsonb_array_elements(v_matrix)
    LOOP
        v_collector_number :=
            v_item->>'collector_number';

        v_variant_type_code :=
            v_item->>'variant_type_code';

        v_variant_order :=
            (v_item->>'variant_order')::INTEGER;

        v_is_default :=
            (v_item->>'is_default')::BOOLEAN;

        SELECT c.id
          INTO STRICT v_card_id
          FROM public.card AS c
         WHERE c.card_set_id = v_card_set_id
           AND c.collector_number = v_collector_number;

        SELECT cvt.id
          INTO STRICT v_variant_type_id
          FROM public.card_variant_type AS cvt
         WHERE cvt.game_id = v_game_id
           AND cvt.code = v_variant_type_code;

        INSERT INTO public.card_variant (
            card_id,
            variant_type_id,
            variant_order,
            is_default
        )
        VALUES (
            v_card_id,
            v_variant_type_id,
            v_variant_order,
            v_is_default
        )
        ON CONFLICT (
            card_id,
            variant_type_id
        )
        DO UPDATE SET
            variant_order = EXCLUDED.variant_order,
            is_default = EXCLUDED.is_default;
    END LOOP;

    -- ========================================================================
    -- 12. Validar quantidade e distribuição finais
    -- ========================================================================

    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE cvt.code = 'STANDARD'
        ),
        COUNT(*) FILTER (
            WHERE cvt.code = 'REVERSE_HOLO'
        )
      INTO
        v_registered_count,
        v_standard_count,
        v_reverse_holo_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE c.card_set_id = v_card_set_id;

    IF v_registered_count <> 16 THEN
        RAISE EXCEPTION
            'Query 860A interrompida: MEE possui % Card Variants, mas deveria possuir exatamente 16.',
            v_registered_count;
    END IF;

    IF v_standard_count <> 8
       OR v_reverse_holo_count <> 8 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em MEE. STANDARD: %/8; REVERSE_HOLO: %/8.',
            v_standard_count,
            v_reverse_holo_count;
    END IF;

    -- ========================================================================
    -- 13. Detectar variantes adicionais fora da matriz canônica
    -- ========================================================================

    SELECT COUNT(*)
      INTO v_additional_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE c.card_set_id = v_card_set_id
       AND NOT EXISTS (
            SELECT 1
              FROM jsonb_array_elements(v_matrix) AS item
             WHERE item->>'collector_number' =
                   c.collector_number
               AND item->>'variant_type_code' =
                   cvt.code
       );

    IF v_additional_count <> 0 THEN
        RAISE EXCEPTION
            'Query 860A interrompida: MEE possui % variantes adicionais fora da matriz canônica.',
            v_additional_count;
    END IF;

    -- ========================================================================
    -- 14. Detectar divergências de ordem ou variante padrão
    -- ========================================================================

    SELECT COUNT(*)
      INTO v_divergent_count
      FROM jsonb_array_elements(v_matrix) AS item
      INNER JOIN public.card AS c
          ON c.card_set_id = v_card_set_id
         AND c.collector_number =
             item->>'collector_number'
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.game_id = v_game_id
         AND cvt.code =
             item->>'variant_type_code'
      INNER JOIN public.card_variant AS cv
          ON cv.card_id = c.id
         AND cv.variant_type_id = cvt.id
     WHERE cv.variant_order <>
           (item->>'variant_order')::INTEGER
        OR cv.is_default <>
           (item->>'is_default')::BOOLEAN;

    IF v_divergent_count <> 0 THEN
        RAISE EXCEPTION
            'Query 860A interrompida: % variantes divergem da matriz canônica.',
            v_divergent_count;
    END IF;

    -- ========================================================================
    -- 15. Confirmar exatamente uma variante padrão por Card
    -- ========================================================================

    SELECT COUNT(*)
      INTO v_invalid_default_count
      FROM (
            SELECT cv.card_id
              FROM public.card_variant AS cv
              INNER JOIN public.card AS c
                  ON c.id = cv.card_id
             WHERE c.card_set_id = v_card_set_id
             GROUP BY cv.card_id
            HAVING COUNT(*) FILTER (
                WHERE cv.is_default = TRUE
            ) <> 1
      ) AS invalid_defaults;

    IF v_invalid_default_count <> 0 THEN
        RAISE EXCEPTION
            'Query 860A interrompida: % Cards de MEE não possuem exatamente uma variante padrão.',
            v_invalid_default_count;
    END IF;

    RAISE NOTICE
        'Query 860A concluída: 16 variantes cadastradas em MEE — 8 STANDARD e 8 REVERSE_HOLO.';
END;
$$;

-- =============================================================================
-- Resultado final para conferência
-- Esperado:
-- STANDARD      | 8
-- REVERSE_HOLO  | 8
-- =============================================================================

SELECT
    cvt.code AS variant_type_code,
    COUNT(*) AS registered_total
FROM public.card_variant AS cv
INNER JOIN public.card AS c
    ON c.id = cv.card_id
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.card_variant_type AS cvt
    ON cvt.id = cv.variant_type_id
WHERE g.code = 'POKEMON'
  AND cs.code = 'MEE'
GROUP BY
    cvt.code,
    cvt.display_order
ORDER BY
    cvt.display_order;

COMMIT;
