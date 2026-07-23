/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 960 - Validate Card Variant
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura técnica, a integridade relacional e a carga editorial
consolidada da tabela public.card_variant após a execução da Query 860.

Escopo canônico:
- ME1:   188 Cards / 310 Card Variants
- ME2:   130 Cards / 214 Card Variants
- ME2.5: 295 Cards / 630 Card Variants
- ME3:   124 Cards / 203 Card Variants
- ME4:   122 Cards / 198 Card Variants

Totais:
- 5 Card Sets
- 859 Cards
- 1.555 Card Variants

Alterações da versão 2.0:
- Evolução da validação estrutural para validação completa pós-Seed 860.
- Inclusão das quantidades canônicas por Card Set.
- Inclusão da distribuição canônica por Card Variant Type.
- Validação da cobertura das 859 Cards.
- Validação de exatamente uma variante padrão por Card.
- Validação de variant_order contínuo dentro de cada Card.
- Validação da variante padrão na ordem 1.
- Validação de integridade, timestamps, triggers, funções e RLS.
- Falha explícita e rollback em qualquer inconsistência.

Pré-requisitos:
- Query 160 - Create Card Variant Table.
- Query 161 - Create Card Variant Triggers.
- Query 850 - Seed Card Variant Type, versão 1.3.
- Query 860 - Seed Card Variant, versão consolidada.

===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;

    v_missing_columns TEXT;
    v_missing_constraints TEXT;
    v_missing_indexes TEXT;
    v_missing_triggers TEXT;
    v_missing_functions TEXT;

    v_rls_enabled BOOLEAN;

    v_count INTEGER;
    v_registered_cards INTEGER;
    v_registered_variants INTEGER;
    v_expected_cards INTEGER := 859;
    v_expected_variants INTEGER := 1555;

    v_set_error_count INTEGER;
    v_distribution_error_count INTEGER;
BEGIN
    /*
    ===========================================================================
    1. Validar existência da tabela
    ===========================================================================
    */

    IF to_regclass('public.card_variant') IS NULL THEN
        RAISE EXCEPTION
            'Falha na Query 960: a tabela public.card_variant não existe.';
    END IF;

    /*
    ===========================================================================
    2. Validar colunas obrigatórias
    ===========================================================================
    */

    SELECT string_agg(required.column_name, ', ' ORDER BY required.column_name)
      INTO v_missing_columns
      FROM (
            VALUES
                ('id'),
                ('card_id'),
                ('variant_type_id'),
                ('variant_order'),
                ('is_default'),
                ('created_at'),
                ('updated_at')
      ) AS required(column_name)
     WHERE NOT EXISTS (
            SELECT 1
              FROM information_schema.columns AS c
             WHERE c.table_schema = 'public'
               AND c.table_name = 'card_variant'
               AND c.column_name = required.column_name
     );

    IF v_missing_columns IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na Query 960: colunas ausentes em card_variant: %.',
            v_missing_columns;
    END IF;

    /*
    ===========================================================================
    3. Validar constraints obrigatórias
    ===========================================================================
    */

    SELECT string_agg(required.constraint_name, ', ' ORDER BY required.constraint_name)
      INTO v_missing_constraints
      FROM (
            VALUES
                ('fk_card_variant_card'),
                ('fk_card_variant_variant_type'),
                ('uq_card_variant_card_type'),
                ('uq_card_variant_card_order'),
                ('ck_card_variant_order_positive')
      ) AS required(constraint_name)
     WHERE NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_constraint AS c
             WHERE c.conrelid = 'public.card_variant'::regclass
               AND c.conname = required.constraint_name
     );

    IF v_missing_constraints IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na Query 960: constraints ausentes em card_variant: %.',
            v_missing_constraints;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint AS c
         WHERE c.conrelid = 'public.card_variant'::regclass
           AND c.contype = 'p'
    ) THEN
        RAISE EXCEPTION
            'Falha na Query 960: card_variant não possui chave primária.';
    END IF;

    /*
    ===========================================================================
    4. Validar índices obrigatórios
    ===========================================================================
    */

    SELECT string_agg(required.index_name, ', ' ORDER BY required.index_name)
      INTO v_missing_indexes
      FROM (
            VALUES
                ('uq_card_variant_one_default_per_card'),
                ('ix_card_variant_card_id'),
                ('ix_card_variant_variant_type_id')
      ) AS required(index_name)
     WHERE NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_indexes AS i
             WHERE i.schemaname = 'public'
               AND i.tablename = 'card_variant'
               AND i.indexname = required.index_name
     );

    IF v_missing_indexes IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na Query 960: índices ausentes em card_variant: %.',
            v_missing_indexes;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_indexes AS i
         WHERE i.schemaname = 'public'
           AND i.tablename = 'card_variant'
           AND i.indexname = 'uq_card_variant_one_default_per_card'
           AND i.indexdef ILIKE '%WHERE (is_default = true)%'
    ) THEN
        RAISE EXCEPTION
            'Falha na Query 960: o índice uq_card_variant_one_default_per_card não possui o predicado esperado.';
    END IF;

    /*
    ===========================================================================
    5. Validar triggers e funções
    ===========================================================================
    */

    SELECT string_agg(required.trigger_name, ', ' ORDER BY required.trigger_name)
      INTO v_missing_triggers
      FROM (
            VALUES
                ('trg_card_variant_set_updated_at'),
                ('trg_card_variant_validate_game_consistency')
      ) AS required(trigger_name)
     WHERE NOT EXISTS (
            SELECT 1
              FROM pg_catalog.pg_trigger AS t
             WHERE t.tgrelid = 'public.card_variant'::regclass
               AND t.tgname = required.trigger_name
               AND t.tgenabled <> 'D'
               AND NOT t.tgisinternal
     );

    IF v_missing_triggers IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na Query 960: triggers ausentes ou desabilitados: %.',
            v_missing_triggers;
    END IF;

    SELECT string_agg(required.function_name, ', ' ORDER BY required.function_name)
      INTO v_missing_functions
      FROM (
            VALUES
                ('set_updated_at'),
                ('validate_card_variant_game_consistency')
      ) AS required(function_name)
     WHERE to_regprocedure(
               'public.' || required.function_name || '()'
           ) IS NULL;

    IF v_missing_functions IS NOT NULL THEN
        RAISE EXCEPTION
            'Falha na Query 960: funções ausentes: %.',
            v_missing_functions;
    END IF;

    /*
    ===========================================================================
    6. Validar Row Level Security
    ===========================================================================
    */

    SELECT c.relrowsecurity
      INTO v_rls_enabled
      FROM pg_catalog.pg_class AS c
      INNER JOIN pg_catalog.pg_namespace AS n
          ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'card_variant'
       AND c.relkind = 'r';

    IF v_rls_enabled IS DISTINCT FROM TRUE THEN
        RAISE EXCEPTION
            'Falha na Query 960: Row Level Security não está habilitado em public.card_variant.';
    END IF;

    /*
    ===========================================================================
    7. Validar Game e escopo canônico
    ===========================================================================
    */

    SELECT g.id
      INTO v_game_id
      FROM public.game AS g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Falha na Query 960: o Game POKEMON não está cadastrado.';
    END IF;

    /*
    ===========================================================================
    8. Validar integridade básica dos registros
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_variant
     WHERE variant_order <= 0;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % registros com variant_order inválido.',
            v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_variant
     WHERE created_at IS NULL
        OR updated_at IS NULL
        OR updated_at < created_at;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % registros com timestamps inválidos.',
            v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_variant AS cv
      LEFT JOIN public.card AS c
          ON c.id = cv.card_id
     WHERE c.id IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % referências órfãs para Card.',
            v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_variant AS cv
      LEFT JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE cvt.id IS NULL;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % referências órfãs para Card Variant Type.',
            v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_set AS cs
          ON cs.id = c.card_set_id
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE e.game_id <> cvt.game_id;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % inconsistências de Game.',
            v_count;
    END IF;

    /*
    ===========================================================================
    9. Validar unicidade lógica
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT card_id, variant_type_id
              FROM public.card_variant
             GROUP BY card_id, variant_type_id
            HAVING COUNT(*) > 1
      ) AS duplicate_card_type;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % combinações Card + Variant Type duplicadas.',
            v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT card_id, variant_order
              FROM public.card_variant
             GROUP BY card_id, variant_order
            HAVING COUNT(*) > 1
      ) AS duplicate_card_order;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % valores de variant_order duplicados dentro da mesma Card.',
            v_count;
    END IF;

    /*
    ===========================================================================
    10. Validar cobertura das Cards e quantidade total
    ===========================================================================
    */

    SELECT COUNT(DISTINCT cv.card_id)
      INTO v_registered_cards
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_set AS cs
          ON cs.id = c.card_set_id
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE e.game_id = v_game_id
       AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4');

    IF v_registered_cards <> v_expected_cards THEN
        RAISE EXCEPTION
            'Falha na Query 960: esperadas % Cards cobertas, encontradas %.',
            v_expected_cards,
            v_registered_cards;
    END IF;

    SELECT COUNT(*)
      INTO v_registered_variants
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_set AS cs
          ON cs.id = c.card_set_id
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE e.game_id = v_game_id
       AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4');

    IF v_registered_variants <> v_expected_variants THEN
        RAISE EXCEPTION
            'Falha na Query 960: esperadas % Card Variants, encontradas %.',
            v_expected_variants,
            v_registered_variants;
    END IF;

    /*
    ===========================================================================
    11. Validar quantidade de Cards e variantes por Card Set
    ===========================================================================
    */

    WITH expected_set (
        set_code,
        expected_cards,
        expected_variants
    ) AS (
        VALUES
            ('ME1',   188, 310),
            ('ME2',   130, 214),
            ('ME2.5', 295, 630),
            ('ME3',   124, 203),
            ('ME4',   122, 198)
    ),
    registered_set AS (
        SELECT
            cs.code AS set_code,
            COUNT(DISTINCT c.id)::INTEGER AS registered_cards,
            COUNT(cv.id)::INTEGER AS registered_variants
        FROM public.card_set AS cs
        INNER JOIN public.expansion AS e
            ON e.id = cs.expansion_id
           AND e.game_id = v_game_id
        INNER JOIN public.card AS c
            ON c.card_set_id = cs.id
        LEFT JOIN public.card_variant AS cv
            ON cv.card_id = c.id
        WHERE cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
        GROUP BY cs.code
    )
    SELECT COUNT(*)
      INTO v_set_error_count
      FROM expected_set AS expected
      FULL OUTER JOIN registered_set AS registered
          ON registered.set_code = expected.set_code
     WHERE COALESCE(registered.registered_cards, 0)
               <> COALESCE(expected.expected_cards, 0)
        OR COALESCE(registered.registered_variants, 0)
               <> COALESCE(expected.expected_variants, 0);

    IF v_set_error_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % Card Sets com quantidade divergente de Cards ou variantes.',
            v_set_error_count;
    END IF;

    /*
    ===========================================================================
    12. Validar exatamente uma variante padrão por Card
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT
                c.id AS card_id
              FROM public.card AS c
              INNER JOIN public.card_set AS cs
                  ON cs.id = c.card_set_id
              INNER JOIN public.expansion AS e
                  ON e.id = cs.expansion_id
              LEFT JOIN public.card_variant AS cv
                  ON cv.card_id = c.id
             WHERE e.game_id = v_game_id
               AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
             GROUP BY c.id
            HAVING COUNT(cv.id) FILTER (WHERE cv.is_default = TRUE) <> 1
      ) AS invalid_default;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % Cards sem exatamente uma variante padrão.',
            v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_set AS cs
          ON cs.id = c.card_set_id
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE e.game_id = v_game_id
       AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
       AND cv.is_default = TRUE
       AND cv.variant_order <> 1;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % variantes padrão fora da posição 1.',
            v_count;
    END IF;

    SELECT COUNT(*)
      INTO v_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_set AS cs
          ON cs.id = c.card_set_id
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE e.game_id = v_game_id
       AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
       AND cv.is_default = TRUE
       AND cvt.code NOT IN ('STANDARD', 'HOLO');

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % variantes padrão com tipo diferente de STANDARD ou HOLO.',
            v_count;
    END IF;

    /*
    ===========================================================================
    13. Validar sequência contínua de variant_order por Card
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_count
      FROM (
            SELECT
                cv.card_id,
                MIN(cv.variant_order) AS min_order,
                MAX(cv.variant_order) AS max_order,
                COUNT(*) AS variant_count
              FROM public.card_variant AS cv
              INNER JOIN public.card AS c
                  ON c.id = cv.card_id
              INNER JOIN public.card_set AS cs
                  ON cs.id = c.card_set_id
              INNER JOIN public.expansion AS e
                  ON e.id = cs.expansion_id
             WHERE e.game_id = v_game_id
               AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
             GROUP BY cv.card_id
            HAVING MIN(cv.variant_order) <> 1
                OR MAX(cv.variant_order) <> COUNT(*)
      ) AS invalid_sequence;

    IF v_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % Cards com sequência descontínua de variant_order.',
            v_count;
    END IF;

    /*
    ===========================================================================
    14. Validar distribuição canônica por Card Set e Variant Type
    ===========================================================================
    */

    WITH expected_distribution (
        set_code,
        variant_type_code,
        expected_total
    ) AS (
        VALUES
            ('ME1',   'STANDARD',             111),
            ('ME1',   'HOLO',                  77),
            ('ME1',   'REVERSE_HOLO',         122),

            ('ME2',   'STANDARD',              74),
            ('ME2',   'HOLO',                  56),
            ('ME2',   'REVERSE_HOLO',          84),

            ('ME2.5', 'STANDARD',             153),
            ('ME2.5', 'HOLO',                 142),
            ('ME2.5', 'COSMOS_HOLO',            7),
            ('ME2.5', 'REVERSE_HOLO',          38),
            ('ME2.5', 'ENERGY_REVERSE',       140),
            ('ME2.5', 'POKE_BALL_REVERSE',     34),
            ('ME2.5', 'LOVE_BALL_REVERSE',     25),
            ('ME2.5', 'FRIEND_BALL_REVERSE',   23),
            ('ME2.5', 'QUICK_BALL_REVERSE',    22),
            ('ME2.5', 'DUSK_BALL_REVERSE',     26),
            ('ME2.5', 'ROCKET_REVERSE',        10),
            ('ME2.5', 'PROMO_STAMPED',         10),

            ('ME3',   'STANDARD',              68),
            ('ME3',   'HOLO',                  56),
            ('ME3',   'REVERSE_HOLO',          79),

            ('ME4',   'STANDARD',              64),
            ('ME4',   'HOLO',                  58),
            ('ME4',   'REVERSE_HOLO',          76)
    ),
    registered_distribution AS (
        SELECT
            cs.code AS set_code,
            cvt.code AS variant_type_code,
            COUNT(*)::INTEGER AS registered_total
        FROM public.card_variant AS cv
        INNER JOIN public.card AS c
            ON c.id = cv.card_id
        INNER JOIN public.card_set AS cs
            ON cs.id = c.card_set_id
        INNER JOIN public.expansion AS e
            ON e.id = cs.expansion_id
        INNER JOIN public.card_variant_type AS cvt
            ON cvt.id = cv.variant_type_id
        WHERE e.game_id = v_game_id
          AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
        GROUP BY cs.code, cvt.code
    )
    SELECT COUNT(*)
      INTO v_distribution_error_count
      FROM expected_distribution AS expected
      FULL OUTER JOIN registered_distribution AS registered
          ON registered.set_code = expected.set_code
         AND registered.variant_type_code = expected.variant_type_code
     WHERE COALESCE(registered.registered_total, 0)
               <> COALESCE(expected.expected_total, 0);

    IF v_distribution_error_count <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 960: existem % divergências na distribuição canônica por coleção e tipo.',
            v_distribution_error_count;
    END IF;

    /*
    ===========================================================================
    15. Conclusão
    ===========================================================================
    */

    RAISE NOTICE
        'Query 960 concluída: 1.555 Card Variants validadas para 859 Cards em 5 Card Sets.';
END;
$$;


-- ============================================================================
-- Resultado resumido por Card Set e Card Variant Type
-- ============================================================================

SELECT
    cs.code AS card_set_code,
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
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
GROUP BY
    cs.code,
    cvt.code,
    cvt.display_order
ORDER BY
    CASE cs.code
        WHEN 'ME1' THEN 1
        WHEN 'ME2' THEN 2
        WHEN 'ME2.5' THEN 3
        WHEN 'ME3' THEN 4
        WHEN 'ME4' THEN 5
    END,
    cvt.display_order;


-- ============================================================================
-- Resultado consolidado
-- ============================================================================

SELECT
    COUNT(DISTINCT cv.card_id) AS covered_cards,
    COUNT(*) AS registered_variants,
    COUNT(*) FILTER (WHERE cv.is_default = TRUE) AS default_variants,
    CASE
        WHEN COUNT(DISTINCT cv.card_id) = 859
         AND COUNT(*) = 1555
         AND COUNT(*) FILTER (WHERE cv.is_default = TRUE) = 859
        THEN 'COMPLETE'
        ELSE 'DIVERGENT'
    END AS status
FROM public.card_variant AS cv
INNER JOIN public.card AS c
    ON c.id = cv.card_id
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4');

COMMIT;
