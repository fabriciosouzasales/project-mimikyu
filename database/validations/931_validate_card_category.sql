/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 931 - Validate Card Category
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura, os dados canônicos e as regras de integridade da tabela
card_category.

Descrição:
Executa consultas de verificação para confirmar:
- os registros cadastrados;
- a quantidade de categorias por Game;
- o relacionamento com Game;
- a unicidade dos códigos;
- o formato dos códigos;
- o preenchimento dos nomes;
- a validade da ordem de exibição;
- a aderência aos dados canônicos do Pokémon TCG;
- a inexistência de categorias adicionais não previstas;
- os timestamps obrigatórios;
- a existência do trigger de atualização;
- a ativação do Row Level Security.

A validação considera três categorias canônicas para o Game POKEMON:
- POKEMON
- TRAINER
- ENERGY

Pré-requisitos:
- Query 132 - Create Card Category Table.
- Query 133 - Create Card Category Trigger.
- Query 831 - Seed Card Category.
===============================================================================
*/

-- ============================================================================
-- 1. Relação completa das categorias de cartas
-- Resultado esperado: 3 registros do Game POKEMON
-- ============================================================================
SELECT
    g.code AS game_code,
    cc.display_order,
    cc.code AS category_code,
    cc.name AS category_name,
    cc.created_at,
    cc.updated_at
FROM public.card_category AS cc
INNER JOIN public.game AS g
    ON g.id = cc.game_id
ORDER BY
    g.code,
    cc.display_order,
    cc.code;

-- ============================================================================
-- 2. Quantidade de categorias por Game
-- Resultado esperado para POKEMON: 3
-- ============================================================================
SELECT
    g.code AS game_code,
    COUNT(*) AS total_categories
FROM public.card_category AS cc
INNER JOIN public.game AS g
    ON g.id = cc.game_id
GROUP BY
    g.code
ORDER BY
    g.code;

-- ============================================================================
-- 3. Verificar categorias sem Game válido
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    cc.id,
    cc.game_id,
    cc.code,
    cc.name
FROM public.card_category AS cc
LEFT JOIN public.game AS g
    ON g.id = cc.game_id
WHERE g.id IS NULL;

-- ============================================================================
-- 4. Verificar códigos duplicados dentro do mesmo Game
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    g.code AS game_code,
    cc.code AS category_code,
    COUNT(*) AS duplicate_count
FROM public.card_category AS cc
INNER JOIN public.game AS g
    ON g.id = cc.game_id
GROUP BY
    g.code,
    cc.code
HAVING COUNT(*) > 1;

-- ============================================================================
-- 5. Verificar códigos de categoria inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code
FROM public.card_category
WHERE code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- ============================================================================
-- 6. Verificar nomes nulos ou vazios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    name
FROM public.card_category
WHERE name IS NULL
   OR btrim(name) = '';

-- ============================================================================
-- 7. Verificar ordens de exibição inválidas
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    display_order
FROM public.card_category
WHERE display_order <= 0;

-- ============================================================================
-- 8. Verificar ordens de exibição duplicadas dentro do mesmo Game
-- Resultado esperado para o catálogo canônico atual: nenhum registro
--
-- Observação:
-- A tabela não possui constraint de unicidade para display_order, pois duas
-- categorias poderão compartilhar a mesma prioridade no futuro. Esta consulta
-- identifica duplicidades para revisão editorial.
-- ============================================================================
SELECT
    g.code AS game_code,
    cc.display_order,
    COUNT(*) AS duplicate_count
FROM public.card_category AS cc
INNER JOIN public.game AS g
    ON g.id = cc.game_id
GROUP BY
    g.code,
    cc.display_order
HAVING COUNT(*) > 1;

-- ============================================================================
-- 9. Conferir os dados canônicos do Pokémon TCG
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_category (
    code,
    name,
    display_order
) AS (
    VALUES
        ('POKEMON', 'Pokémon',   1),
        ('TRAINER', 'Treinador', 2),
        ('ENERGY',  'Energia',   3)
)
SELECT
    e.code AS expected_code,
    e.name AS expected_name,
    e.display_order AS expected_display_order,
    cc.name AS persisted_name,
    cc.display_order AS persisted_display_order
FROM expected_category AS e
LEFT JOIN public.game AS g
    ON g.code = 'POKEMON'
LEFT JOIN public.card_category AS cc
    ON cc.game_id = g.id
   AND cc.code = e.code
WHERE cc.id IS NULL
   OR cc.name <> e.name
   OR cc.display_order <> e.display_order;

-- ============================================================================
-- 10. Verificar categorias adicionais não previstas para o Game POKEMON
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_category (code) AS (
    VALUES
        ('POKEMON'),
        ('TRAINER'),
        ('ENERGY')
)
SELECT
    cc.code,
    cc.name,
    cc.display_order
FROM public.card_category AS cc
INNER JOIN public.game AS g
    ON g.id = cc.game_id
LEFT JOIN expected_category AS e
    ON e.code = cc.code
WHERE g.code = 'POKEMON'
  AND e.code IS NULL;

-- ============================================================================
-- 11. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    code,
    created_at,
    updated_at
FROM public.card_category
WHERE created_at IS NULL
   OR updated_at IS NULL;

-- ============================================================================
-- 12. Verificar a existência do trigger updated_at
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
  AND event_object_table = 'card_category'
  AND trigger_name = 'trg_card_category_set_updated_at';

-- ============================================================================
-- 13. Verificar se o Row Level Security está habilitado
-- Resultado esperado:
-- rowsecurity = true
-- ============================================================================
SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
  AND tablename = 'card_category';
