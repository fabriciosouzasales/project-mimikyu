/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 940 - Validate Card
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura, os relacionamentos, as regras de integridade e a aderência
canônica do catálogo de Cards atualmente suportado pelo Project Mimikyu.

Descrição:
Esta Query valida a tabela card após a execução da Query 840 - Seed Card.

O catálogo canônico atualmente suportado contempla:

- ME1   - Megaevolução:          188 Cards;
- ME2   - Fogo Fantasmagórico:   130 Cards;
- ME2.5 - Heróis Excelsos:       295 Cards;
- ME3   - Equilíbrio Perfeito:   124 Cards;
- ME4   - Caos Ascendente:       122 Cards.

Total canônico esperado: 859 Cards.

A validação verifica:

- relação completa das Cards;
- quantidade cadastrada por Card Set;
- quantidade canônica por Card Set;
- total consolidado do catálogo;
- números e ordens duplicados;
- campos obrigatórios e formatos;
- relacionamentos com Card Set, Rarity e Card Category;
- consistência de Game;
- continuidade da ordem editorial;
- aderência de collector_total ao base_set_size;
- correspondência entre quantidade cadastrada e total_set_size;
- distribuição por categoria e raridade;
- existência dos triggers;
- timestamps obrigatórios;
- ativação do Row Level Security.

Regras de Validação:
- Consultas de inconsistência devem retornar zero registros.
- Os cinco Card Sets devem apresentar status COMPLETE.
- O total consolidado deve ser exatamente 859.
- Cada Card Set deve possuir exatamente a quantidade canônica definida.
- collector_total deve coincidir com card_set.base_set_size.
- collector_order deve formar uma sequência contínua de 1 até total_set_size.
- Card Set, Rarity e Card Category devem pertencer ao mesmo Game.

Pré-requisitos:
- Query 140 - Create Card Table.
- Query 141 - Create Card Triggers.
- Query 840 - Seed Card.

===============================================================================
*/

-- ============================================================================
-- 1. Relação completa das Cards
-- Resultado esperado:
-- 859 registros ordenados por Card Set e collector_order
-- ============================================================================

SELECT
    g.code AS game_code,
    e.code AS expansion_code,
    cs.code AS card_set_code,
    c.collector_number,
    c.collector_total,
    c.collector_order,
    c.name AS card_name,
    cc.code AS category_code,
    r.code AS rarity_code,
    cs.code || '-' || c.collector_number AS derived_card_code,
    c.created_at,
    c.updated_at
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.card_category AS cc
    ON cc.id = c.category_id
INNER JOIN public.rarity AS r
    ON r.id = c.rarity_id
ORDER BY
    g.code,
    e.release_order,
    cs.release_order,
    c.collector_order,
    c.collector_number;


-- ============================================================================
-- 2. Quantidade de Cards por Card Set
-- Resultado esperado:
-- ME1 = 188
-- ME2 = 130
-- ME2.5 = 295
-- ME3 = 124
-- ME4 = 122
-- ============================================================================

SELECT
    g.code AS game_code,
    e.code AS expansion_code,
    cs.code AS card_set_code,
    cs.name AS card_set_name,
    COUNT(c.id) AS registered_total,
    cs.base_set_size,
    cs.total_set_size
FROM public.card_set AS cs
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
LEFT JOIN public.card AS c
    ON c.card_set_id = cs.id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
GROUP BY
    g.code,
    e.code,
    e.release_order,
    cs.code,
    cs.name,
    cs.release_order,
    cs.base_set_size,
    cs.total_set_size
ORDER BY
    e.release_order,
    cs.release_order;


-- ============================================================================
-- 3. Validar quantidades canônicas por Card Set
-- Resultado esperado: nenhum registro
-- ============================================================================

WITH expected_set (
    card_set_code,
    expected_total
) AS (
    VALUES
        ('ME1',   188),
        ('ME2',   130),
        ('ME2.5', 295),
        ('ME3',   124),
        ('ME4',   122)
),
registered AS (
    SELECT
        cs.code AS card_set_code,
        COUNT(c.id)::INTEGER AS registered_total
    FROM public.card_set AS cs
    INNER JOIN public.expansion AS e
        ON e.id = cs.expansion_id
    INNER JOIN public.game AS g
        ON g.id = e.game_id
    LEFT JOIN public.card AS c
        ON c.card_set_id = cs.id
    WHERE g.code = 'POKEMON'
      AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
    GROUP BY cs.code
)
SELECT
    es.card_set_code,
    es.expected_total,
    COALESCE(r.registered_total, 0) AS registered_total
FROM expected_set AS es
LEFT JOIN registered AS r
    ON r.card_set_code = es.card_set_code
WHERE COALESCE(r.registered_total, 0) <> es.expected_total
ORDER BY es.card_set_code;


-- ============================================================================
-- 4. Validar o total consolidado do catálogo
-- Resultado esperado:
-- expected_total = 859
-- registered_total = 859
-- status = COMPLETE
-- ============================================================================

SELECT
    859 AS expected_total,
    COUNT(c.id) AS registered_total,
    CASE
        WHEN COUNT(c.id) = 859 THEN 'COMPLETE'
        WHEN COUNT(c.id) < 859 THEN 'PENDING'
        ELSE 'EXCEEDED'
    END AS status
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4');


-- ============================================================================
-- 5. Verificar Cards adicionais em Card Sets fora do catálogo canônico atual
-- Resultado esperado:
-- Pode haver registros somente se outros Sets já tiverem sido oficialmente
-- incorporados à Query 840.
-- ============================================================================

SELECT
    g.code AS game_code,
    cs.code AS card_set_code,
    COUNT(c.id) AS registered_total
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
WHERE g.code = 'POKEMON'
  AND cs.code NOT IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
GROUP BY
    g.code,
    cs.code
ORDER BY
    cs.code;


-- ============================================================================
-- 6. Verificar números duplicados dentro do mesmo Card Set
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    c.collector_number,
    COUNT(*) AS duplicate_count
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
GROUP BY
    cs.code,
    c.card_set_id,
    c.collector_number
HAVING COUNT(*) > 1;


-- ============================================================================
-- 7. Verificar ordens editoriais duplicadas dentro do mesmo Card Set
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    c.collector_order,
    COUNT(*) AS duplicate_count
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
GROUP BY
    cs.code,
    c.card_set_id,
    c.collector_order
HAVING COUNT(*) > 1;


-- ============================================================================
-- 8. Verificar números nulos, vazios ou com formato inválido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_set_id,
    collector_number
FROM public.card
WHERE collector_number IS NULL
   OR btrim(collector_number) = ''
   OR collector_number !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$';


-- ============================================================================
-- 9. Verificar nomes nulos ou vazios
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_set_id,
    collector_number,
    name
FROM public.card
WHERE name IS NULL
   OR btrim(name) = '';


-- ============================================================================
-- 10. Verificar collector_total inválido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_set_id,
    collector_number,
    collector_total
FROM public.card
WHERE collector_total IS NULL
   OR collector_total <= 0;


-- ============================================================================
-- 11. Verificar divergência entre collector_total e base_set_size
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    c.collector_number,
    c.collector_total,
    cs.base_set_size AS expected_collector_total
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
WHERE c.collector_total <> cs.base_set_size
ORDER BY
    cs.code,
    c.collector_order;


-- ============================================================================
-- 12. Verificar collector_order inválido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_set_id,
    collector_number,
    collector_order
FROM public.card
WHERE collector_order <= 0;


-- ============================================================================
-- 13. Verificar collector_order superior ao total_set_size
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    c.collector_number,
    c.collector_order,
    cs.total_set_size
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
WHERE c.collector_order > cs.total_set_size
ORDER BY
    cs.code,
    c.collector_order;


-- ============================================================================
-- 14. Verificar Cards sem Card Set válido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    c.id,
    c.card_set_id,
    c.collector_number,
    c.name
FROM public.card AS c
LEFT JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
WHERE cs.id IS NULL;


-- ============================================================================
-- 15. Verificar Cards sem Rarity válida
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    c.id,
    c.rarity_id,
    c.collector_number,
    c.name
FROM public.card AS c
LEFT JOIN public.rarity AS r
    ON r.id = c.rarity_id
WHERE r.id IS NULL;


-- ============================================================================
-- 16. Verificar Cards sem Card Category válida
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    c.id,
    c.category_id,
    c.collector_number,
    c.name
FROM public.card AS c
LEFT JOIN public.card_category AS cc
    ON cc.id = c.category_id
WHERE cc.id IS NULL;


-- ============================================================================
-- 17. Verificar inconsistências de Game
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    c.id,
    cs.code AS card_set_code,
    c.collector_number,
    c.name,
    g_set.code AS card_set_game,
    g_rarity.code AS rarity_game,
    g_category.code AS category_game
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g_set
    ON g_set.id = e.game_id
INNER JOIN public.rarity AS r
    ON r.id = c.rarity_id
INNER JOIN public.game AS g_rarity
    ON g_rarity.id = r.game_id
INNER JOIN public.card_category AS cc
    ON cc.id = c.category_id
INNER JOIN public.game AS g_category
    ON g_category.id = cc.game_id
WHERE g_set.id <> g_rarity.id
   OR g_set.id <> g_category.id;


-- ============================================================================
-- 18. Verificar posições ausentes na sequência editorial
-- Resultado esperado: nenhum registro
-- ============================================================================

WITH expected_order AS (
    SELECT
        cs.id AS card_set_id,
        cs.code AS card_set_code,
        generate_series(1, cs.total_set_size) AS expected_collector_order
    FROM public.card_set AS cs
    INNER JOIN public.expansion AS e
        ON e.id = cs.expansion_id
    INNER JOIN public.game AS g
        ON g.id = e.game_id
    WHERE g.code = 'POKEMON'
      AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
)
SELECT
    eo.card_set_code,
    eo.expected_collector_order AS missing_collector_order
FROM expected_order AS eo
LEFT JOIN public.card AS c
    ON c.card_set_id = eo.card_set_id
   AND c.collector_order = eo.expected_collector_order
WHERE c.id IS NULL
ORDER BY
    eo.card_set_code,
    eo.expected_collector_order;


-- ============================================================================
-- 19. Comparar quantidade cadastrada com total_set_size
-- Resultado esperado:
-- status = COMPLETE para os cinco Card Sets
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    cs.name AS card_set_name,
    cs.total_set_size AS expected_total,
    COUNT(c.id) AS registered_total,
    CASE
        WHEN COUNT(c.id) = cs.total_set_size THEN 'COMPLETE'
        WHEN COUNT(c.id) < cs.total_set_size THEN 'PENDING'
        ELSE 'EXCEEDED'
    END AS catalog_status
FROM public.card_set AS cs
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
LEFT JOIN public.card AS c
    ON c.card_set_id = cs.id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
GROUP BY
    cs.id,
    cs.code,
    cs.name,
    cs.total_set_size,
    cs.release_order
ORDER BY
    cs.release_order,
    cs.code;


-- ============================================================================
-- 20. Distribuição de Cards por categoria
-- Resultado esperado:
-- Distribuição coerente com os checklists oficiais
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    cc.code AS category_code,
    COUNT(*) AS total_cards
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.card_category AS cc
    ON cc.id = c.category_id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
GROUP BY
    cs.code,
    cs.release_order,
    cc.code,
    cc.display_order
ORDER BY
    cs.release_order,
    cc.display_order,
    cc.code;


-- ============================================================================
-- 21. Distribuição de Cards por raridade
-- Resultado esperado:
-- Distribuição coerente com os símbolos dos checklists oficiais
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    r.code AS rarity_code,
    COUNT(*) AS total_cards
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.rarity AS r
    ON r.id = c.rarity_id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
GROUP BY
    cs.code,
    cs.release_order,
    r.code,
    r.display_order
ORDER BY
    cs.release_order,
    r.display_order,
    r.code;


-- ============================================================================
-- 22. Verificar categorias não previstas para o Pokémon TCG atual
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    c.collector_number,
    c.name,
    cc.code AS category_code
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.card_category AS cc
    ON cc.id = c.category_id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
  AND cc.code NOT IN ('POKEMON', 'TRAINER', 'ENERGY')
ORDER BY
    cs.code,
    c.collector_order;


-- ============================================================================
-- 23. Verificar raridades não previstas no catálogo atual
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    c.collector_number,
    c.name,
    r.code AS rarity_code
FROM public.card AS c
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.expansion AS e
    ON e.id = cs.expansion_id
INNER JOIN public.game AS g
    ON g.id = e.game_id
INNER JOIN public.rarity AS r
    ON r.id = c.rarity_id
WHERE g.code = 'POKEMON'
  AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
  AND r.code NOT IN (
      'COMMON',
      'UNCOMMON',
      'RARE',
      'DOUBLE_RARE',
      'ULTRA_RARE',
      'MEGA_ATTACK_RARE',
      'ILLUSTRATION_RARE',
      'SPECIAL_ILLUSTRATION_RARE',
      'MEGA_HYPER_RARE'
  )
ORDER BY
    cs.code,
    c.collector_order;


-- ============================================================================
-- 24. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    collector_number,
    created_at,
    updated_at
FROM public.card
WHERE created_at IS NULL
   OR updated_at IS NULL;


-- ============================================================================
-- 25. Verificar o trigger de consistência de Game
-- Resultado esperado:
-- 2 registros, um para INSERT e outro para UPDATE
-- ============================================================================

SELECT
    event_object_schema,
    event_object_table,
    trigger_name,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'card'
  AND trigger_name = 'trg_card_validate_game_consistency'
ORDER BY
    event_manipulation;


-- ============================================================================
-- 26. Verificar o trigger updated_at
-- Resultado esperado: 1 registro
-- ============================================================================

SELECT
    event_object_schema,
    event_object_table,
    trigger_name,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'card'
  AND trigger_name = 'trg_card_set_updated_at';


-- ============================================================================
-- 27. Verificar se o Row Level Security está habilitado
-- Resultado esperado:
-- rowsecurity = true
-- ============================================================================

SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
  AND tablename = 'card';
