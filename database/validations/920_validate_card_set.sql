/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 920 - Validate Card Set
Versão......: 2.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Descrição...:
Valida a estrutura, os dados persistidos e as regras de negócio da entidade
card_set, incluindo o Card Set promocional Black Star.
Estrutura da validação:
1. Validação dos dados persistidos.
2. Validação das regras de negócio derivadas.
3. Validação de inconsistências.
4. Validação das constraints.
5. Validação do trigger de updated_at.
Resultado esperado:
- A consulta principal deve retornar os seis Card Sets da Expansion ME.
- As consultas de inconsistências devem retornar zero linhas.
- As constraints esperadas devem estar presentes.
- O trigger de updated_at deve estar presente e ativo.
===============================================================================
*/

------------------------------------------------------------------------------
-- 1. Validação dos dados persistidos
------------------------------------------------------------------------------
SELECT
    game.code                                          AS game_code,
    expansion.code                                     AS expansion_code,
    card_set.code                                      AS card_set_code,
    card_set.name                                      AS card_set_name,
    card_set.set_type,
    card_set.release_order,
    card_set.release_date,
    card_set.base_set_size,
    card_set.total_set_size,
    card_set.total_set_size - card_set.base_set_size   AS secret_set_size,
    card_set.created_at,
    card_set.updated_at
FROM public.card_set
INNER JOIN public.expansion
    ON expansion.id = card_set.expansion_id
INNER JOIN public.game
    ON game.id = expansion.game_id
WHERE game.code = 'POKEMON'
  AND expansion.code = 'ME'
ORDER BY card_set.release_order;

------------------------------------------------------------------------------
-- 2. Resumo da Expansion
------------------------------------------------------------------------------
SELECT
    game.code                                          AS game_code,
    expansion.code                                     AS expansion_code,
    COUNT(card_set.id)                                 AS card_set_count,
    COUNT(*) FILTER (
        WHERE card_set.set_type = 'PROMO'
    )                                                  AS promo_set_count,
    COUNT(*) FILTER (
        WHERE card_set.set_type = 'REGULAR'
    )                                                  AS regular_set_count,
    COUNT(*) FILTER (
        WHERE card_set.set_type = 'SPECIAL'
    )                                                  AS special_set_count,
    MIN(card_set.release_order)                        AS first_release_order,
    MAX(card_set.release_order)                        AS last_release_order
FROM public.card_set
INNER JOIN public.expansion
    ON expansion.id = card_set.expansion_id
INNER JOIN public.game
    ON game.id = expansion.game_id
WHERE game.code = 'POKEMON'
  AND expansion.code = 'ME'
GROUP BY
    game.code,
    expansion.code;

------------------------------------------------------------------------------
-- 3. Validação da sequência editorial
--
-- Resultado esperado:
-- zero linhas.
------------------------------------------------------------------------------
WITH ordered_card_sets AS (
    SELECT
        card_set.id,
        card_set.code,
        card_set.release_order,
        ROW_NUMBER() OVER (
            PARTITION BY card_set.expansion_id
            ORDER BY card_set.release_order
        ) AS expected_release_order
    FROM public.card_set
    INNER JOIN public.expansion
        ON expansion.id = card_set.expansion_id
    INNER JOIN public.game
        ON game.id = expansion.game_id
    WHERE game.code = 'POKEMON'
      AND expansion.code = 'ME'
)
SELECT
    code,
    release_order,
    expected_release_order
FROM ordered_card_sets
WHERE release_order <> expected_release_order
ORDER BY release_order;

------------------------------------------------------------------------------
-- 4. Validação das regras dos Card Sets promocionais
--
-- Regras:
-- - O tipo deve ser PROMO.
-- - O código deve ser o código da Expansion seguido de 0.
-- - O nome deve ser o código da Expansion seguido de " Black Star Promos".
-- - Deve ocupar a primeira posição.
-- - A quantidade base deve ser igual à quantidade total.
-- - A quantidade derivada de cartas secretas deve ser zero.
--
-- Resultado esperado:
-- zero linhas.
------------------------------------------------------------------------------
SELECT
    game.code                                          AS game_code,
    expansion.code                                     AS expansion_code,
    card_set.code                                      AS card_set_code,
    card_set.name                                      AS card_set_name,
    card_set.set_type,
    card_set.release_order,
    card_set.release_date,
    card_set.base_set_size,
    card_set.total_set_size,
    card_set.total_set_size - card_set.base_set_size   AS secret_set_size
FROM public.card_set
INNER JOIN public.expansion
    ON expansion.id = card_set.expansion_id
INNER JOIN public.game
    ON game.id = expansion.game_id
WHERE card_set.set_type = 'PROMO'
  AND (
        card_set.code <> expansion.code || '0'
        OR card_set.name <> expansion.code || ' Black Star Promos'
        OR card_set.release_order <> 1
        OR card_set.base_set_size <> card_set.total_set_size
        OR card_set.total_set_size - card_set.base_set_size <> 0
      );

------------------------------------------------------------------------------
-- 5. Validação da data de lançamento do Card Set promocional
--
-- Regra:
-- A data do Set promocional deve ser igual à menor data de lançamento entre
-- os Sets não promocionais da mesma Expansion.
--
-- Resultado esperado:
-- zero linhas.
------------------------------------------------------------------------------
WITH first_non_promo_release AS (
    SELECT
        expansion_id,
        MIN(release_date) AS first_release_date
    FROM public.card_set
    WHERE set_type IN ('REGULAR', 'SPECIAL')
    GROUP BY expansion_id
)
SELECT
    expansion.code                 AS expansion_code,
    promo.code                     AS promo_code,
    promo.release_date             AS promo_release_date,
    first_release.first_release_date
FROM public.card_set AS promo
INNER JOIN public.expansion
    ON expansion.id = promo.expansion_id
INNER JOIN first_non_promo_release AS first_release
    ON first_release.expansion_id = promo.expansion_id
WHERE promo.set_type = 'PROMO'
  AND promo.release_date IS DISTINCT FROM first_release.first_release_date;

------------------------------------------------------------------------------
-- 6. Validação da quantidade de Sets promocionais por Expansion
--
-- Regra:
-- Cada Expansion deve possuir no máximo um Card Set PROMO.
--
-- Resultado esperado:
-- zero linhas.
--
-- NOTA: não existe constraint de banco para esta regra (ver ADR-015 e
-- docs/05-modelo-de-dados.md, seção Set) — hoje é verificada apenas aqui.
------------------------------------------------------------------------------
SELECT
    expansion.code,
    COUNT(card_set.id) AS promo_set_count
FROM public.card_set
INNER JOIN public.expansion
    ON expansion.id = card_set.expansion_id
WHERE card_set.set_type = 'PROMO'
GROUP BY expansion.id, expansion.code
HAVING COUNT(card_set.id) > 1;

------------------------------------------------------------------------------
-- 7. Validação geral das quantidades
--
-- Regras:
-- - base_set_size deve ser maior que zero.
-- - total_set_size deve ser maior ou igual a base_set_size.
--
-- Resultado esperado:
-- zero linhas.
------------------------------------------------------------------------------
SELECT
    card_set.code,
    card_set.name,
    card_set.base_set_size,
    card_set.total_set_size
FROM public.card_set
WHERE card_set.base_set_size <= 0
   OR card_set.total_set_size < card_set.base_set_size;

------------------------------------------------------------------------------
-- 8. Validação dos tipos permitidos
--
-- Resultado esperado:
-- zero linhas.
------------------------------------------------------------------------------
SELECT
    card_set.code,
    card_set.name,
    card_set.set_type
FROM public.card_set
WHERE card_set.set_type NOT IN ('REGULAR', 'SPECIAL', 'PROMO');

------------------------------------------------------------------------------
-- 9. Validação das constraints da tabela
------------------------------------------------------------------------------
SELECT
    constraint_name,
    constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND table_name = 'card_set'
ORDER BY
    constraint_type,
    constraint_name;

------------------------------------------------------------------------------
-- 10. Definição das CHECK constraints
------------------------------------------------------------------------------
SELECT
    constraint_name,
    check_clause
FROM information_schema.check_constraints
WHERE constraint_schema = 'public'
  AND constraint_name IN (
      SELECT constraint_name
      FROM information_schema.table_constraints
      WHERE table_schema = 'public'
        AND table_name = 'card_set'
        AND constraint_type = 'CHECK'
  )
ORDER BY constraint_name;

------------------------------------------------------------------------------
-- 11. Validação do trigger de updated_at
------------------------------------------------------------------------------
SELECT
    trigger_name,
    event_manipulation,
    action_timing,
    event_object_schema,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'card_set'
ORDER BY trigger_name;
