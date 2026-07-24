/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 860B - Seed Card Variant MEP
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-20

Descrição resumida:
Cadastra e atualiza explicitamente as 82 variantes editoriais das 60 Cards
atualmente suportadas no Card Set MEP - MEP Black Star Promos.

Correspondência:
- A relação com o catálogo é feita exclusivamente por collector_number.
- Somente Cards já cadastradas no Card Set MEP integram esta matriz.
- Cards promocionais futuras ainda ausentes da base não são carregadas.

Distribuição canônica:
- HOLO: 59
- PROMO_STAMPED: 23
- Total: 82

Regras editoriais:
- Todas as ocorrências STAMPED são consolidadas como PROMO_STAMPED.
- Variações JUMBO são desconsideradas.
- A Card 028 possui apenas PROMO_STAMPED na fonte utilizada.
- Nas demais Cards com duas variantes, HOLO é a principal.
- A Query é idempotente.
- A Query não exclui silenciosamente variantes adicionais.
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
[{"collector_number":"001","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"001","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"002","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"002","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"003","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"003","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"004","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"004","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"005","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"006","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"007","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"008","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"009","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"009","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"010","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"010","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"011","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"012","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"013","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"014","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"014","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"015","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"015","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"016","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"016","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"017","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"017","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"018","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"019","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"020","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"021","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"022","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"022","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"023","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"024","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"025","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"026","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"027","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"028","variant_type_code":"PROMO_STAMPED","variant_order":1,"is_default":true},{"collector_number":"029","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"030","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"031","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"031","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"032","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"033","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"034","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"035","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"036","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"037","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"038","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"039","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"040","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"041","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"042","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"043","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"044","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"045","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"064","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"064","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"065","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"065","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"066","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"066","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"067","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"067","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"068","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"069","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"070","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"070","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"071","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"074","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"074","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"075","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"075","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"076","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"076","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"077","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"077","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false},{"collector_number":"078","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"079","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"080","variant_type_code":"HOLO","variant_order":1,"is_default":true},{"collector_number":"080","variant_type_code":"PROMO_STAMPED","variant_order":2,"is_default":false}]
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
    v_holo_count INTEGER;
    v_promo_stamped_count INTEGER;
    v_additional_count INTEGER;
    v_divergent_count INTEGER;
    v_invalid_default_count INTEGER;
BEGIN
    SELECT g.id
      INTO v_game_id
      FROM public.game AS g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Query 860B interrompida: o Game POKEMON não está cadastrado.';
    END IF;

    SELECT cs.id
      INTO v_card_set_id
      FROM public.card_set AS cs
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE e.game_id = v_game_id
       AND cs.code = 'MEP';

    IF v_card_set_id IS NULL THEN
        RAISE EXCEPTION
            'Query 860B interrompida: o Card Set MEP não está cadastrado.';
    END IF;

    SELECT COUNT(*)
      INTO v_card_count
      FROM public.card AS c
     WHERE c.card_set_id = v_card_set_id;

    IF v_card_count <> 60 THEN
        RAISE EXCEPTION
            'Query 860B interrompida: MEP possui % Cards, mas o esperado é 60.',
            v_card_count;
    END IF;

    SELECT COUNT(*)
      INTO v_variant_type_count
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND cvt.code IN ('HOLO', 'PROMO_STAMPED');

    IF v_variant_type_count <> 2 THEN
        RAISE EXCEPTION
            'Query 860B interrompida: HOLO e PROMO_STAMPED devem estar cadastrados para POKEMON.';
    END IF;

    v_matrix_count := jsonb_array_length(v_matrix);

    IF v_matrix_count <> 82 THEN
        RAISE EXCEPTION
            'A matriz editorial de MEP possui % linhas, mas o esperado é 82.',
            v_matrix_count;
    END IF;

    SELECT COUNT(DISTINCT item->>'collector_number')
      INTO v_distinct_card_count
      FROM jsonb_array_elements(v_matrix) AS item;

    IF v_distinct_card_count <> 60 THEN
        RAISE EXCEPTION
            'A matriz editorial de MEP referencia % Cards distintas, mas o esperado é 60.',
            v_distinct_card_count;
    END IF;

    SELECT COUNT(*)
      INTO v_duplicate_count
      FROM (
            SELECT
                item->>'collector_number',
                item->>'variant_type_code'
            FROM jsonb_array_elements(v_matrix) AS item
            GROUP BY
                item->>'collector_number',
                item->>'variant_type_code'
            HAVING COUNT(*) > 1
      ) AS duplicated_items;

    IF v_duplicate_count <> 0 THEN
        RAISE EXCEPTION
            'A matriz editorial de MEP contém % combinações duplicadas.',
            v_duplicate_count;
    END IF;

    SELECT COUNT(*)
      INTO v_default_error_count
      FROM (
            SELECT item->>'collector_number'
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

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(v_matrix)
    LOOP
        v_collector_number := v_item->>'collector_number';
        v_variant_type_code := v_item->>'variant_type_code';
        v_variant_order := (v_item->>'variant_order')::INTEGER;
        v_is_default := (v_item->>'is_default')::BOOLEAN;

        SELECT c.id
          INTO v_card_id
          FROM public.card AS c
         WHERE c.card_set_id = v_card_set_id
           AND c.collector_number = v_collector_number;

        IF v_card_id IS NULL THEN
            RAISE EXCEPTION
                'Query 860B interrompida: a Card % não foi encontrada em MEP.',
                v_collector_number;
        END IF;

        SELECT cvt.id
          INTO v_variant_type_id
          FROM public.card_variant_type AS cvt
         WHERE cvt.game_id = v_game_id
           AND cvt.code = v_variant_type_code;

        IF v_variant_type_id IS NULL THEN
            RAISE EXCEPTION
                'Query 860B interrompida: o Card Variant Type % não foi encontrado.',
                v_variant_type_code;
        END IF;

        IF v_variant_order <= 0 THEN
            RAISE EXCEPTION
                'Query 860B interrompida: variant_order inválido para a Card %.',
                v_collector_number;
        END IF;
    END LOOP;

    UPDATE public.card_variant AS cv
       SET variant_order = cv.variant_order + 1000,
           is_default = FALSE
      FROM public.card AS c
     WHERE cv.card_id = c.id
       AND c.card_set_id = v_card_set_id;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(v_matrix)
    LOOP
        v_collector_number := v_item->>'collector_number';
        v_variant_type_code := v_item->>'variant_type_code';
        v_variant_order := (v_item->>'variant_order')::INTEGER;
        v_is_default := (v_item->>'is_default')::BOOLEAN;

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
        ON CONFLICT (card_id, variant_type_id)
        DO UPDATE SET
            variant_order = EXCLUDED.variant_order,
            is_default = EXCLUDED.is_default;
    END LOOP;

    SELECT
        COUNT(*),
        COUNT(*) FILTER (WHERE cvt.code = 'HOLO'),
        COUNT(*) FILTER (WHERE cvt.code = 'PROMO_STAMPED')
      INTO
        v_registered_count,
        v_holo_count,
        v_promo_stamped_count
      FROM public.card_variant AS cv
      INNER JOIN public.card AS c
          ON c.id = cv.card_id
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.id = cv.variant_type_id
     WHERE c.card_set_id = v_card_set_id;

    IF v_registered_count <> 82 THEN
        RAISE EXCEPTION
            'Query 860B interrompida: MEP possui % Card Variants, mas deveria possuir 82.',
            v_registered_count;
    END IF;

    IF v_holo_count <> 59 OR v_promo_stamped_count <> 23 THEN
        RAISE EXCEPTION
            'Distribuição incorreta em MEP. HOLO: %/59; PROMO_STAMPED: %/23.',
            v_holo_count,
            v_promo_stamped_count;
    END IF;

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
             WHERE item->>'collector_number' = c.collector_number
               AND item->>'variant_type_code' = cvt.code
       );

    IF v_additional_count <> 0 THEN
        RAISE EXCEPTION
            'Query 860B interrompida: MEP possui % variantes adicionais fora da matriz canônica.',
            v_additional_count;
    END IF;

    SELECT COUNT(*)
      INTO v_divergent_count
      FROM jsonb_array_elements(v_matrix) AS item
      INNER JOIN public.card AS c
          ON c.card_set_id = v_card_set_id
         AND c.collector_number = item->>'collector_number'
      INNER JOIN public.card_variant_type AS cvt
          ON cvt.game_id = v_game_id
         AND cvt.code = item->>'variant_type_code'
      INNER JOIN public.card_variant AS cv
          ON cv.card_id = c.id
         AND cv.variant_type_id = cvt.id
     WHERE cv.variant_order <> (item->>'variant_order')::INTEGER
        OR cv.is_default <> (item->>'is_default')::BOOLEAN;

    IF v_divergent_count <> 0 THEN
        RAISE EXCEPTION
            'Query 860B interrompida: % variantes divergem da matriz canônica.',
            v_divergent_count;
    END IF;

    SELECT COUNT(*)
      INTO v_invalid_default_count
      FROM (
            SELECT cv.card_id
              FROM public.card_variant AS cv
              INNER JOIN public.card AS c
                  ON c.id = cv.card_id
             WHERE c.card_set_id = v_card_set_id
             GROUP BY cv.card_id
            HAVING COUNT(*) FILTER (WHERE cv.is_default = TRUE) <> 1
      ) AS invalid_defaults;

    IF v_invalid_default_count <> 0 THEN
        RAISE EXCEPTION
            'Query 860B interrompida: % Cards de MEP não possuem exatamente uma variante padrão.',
            v_invalid_default_count;
    END IF;

    RAISE NOTICE
        'Query 860B concluída: 82 variantes cadastradas em MEP — 59 HOLO e 23 PROMO_STAMPED.';
END;
$$;

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
  AND cs.code = 'MEP'
GROUP BY
    cvt.code,
    cvt.display_order
ORDER BY
    cvt.display_order;

COMMIT;
