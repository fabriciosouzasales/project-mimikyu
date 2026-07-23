/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 960 - Validate Card Variant Structure
Versão......: 1.0
Status......: CANÔNICA
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura técnica e as regras de integridade da tabela card_variant.

Descrição:
Esta versão valida somente a estrutura da entidade, antes da construção e
execução do Seed 860.

Após o Seed 860, esta Query também poderá ser evoluída para validar:
- quantidade esperada de variantes por Card Set;
- existência de exatamente uma variante padrão por Card;
- sequência completa de variant_order;
- cobertura editorial das Cards suportadas.

Regras de leitura:
- Consultas de inconsistência devem retornar zero registros.
- Consultas de objetos esperados devem retornar os objetos indicados.
- Antes do Seed 860, a tabela pode estar vazia.

Pré-requisitos:
- Query 160 - Create Card Variant Table.
- Query 161 - Create Card Variant Triggers.

===============================================================================
*/

-- ============================================================================
-- 1. Confirmar existência da tabela
-- Resultado esperado: 1 registro
-- ============================================================================

SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = 'card_variant';


-- ============================================================================
-- 2. Confirmar estrutura das colunas
-- Resultado esperado: 7 registros
-- ============================================================================

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'card_variant'
ORDER BY ordinal_position;


-- ============================================================================
-- 3. Confirmar constraints da tabela
-- Resultado esperado:
-- - PRIMARY KEY
-- - 2 FOREIGN KEY
-- - 2 UNIQUE
-- - 1 CHECK
-- ============================================================================

SELECT
    tc.constraint_name,
    tc.constraint_type
FROM information_schema.table_constraints AS tc
WHERE tc.table_schema = 'public'
  AND tc.table_name = 'card_variant'
ORDER BY
    tc.constraint_type,
    tc.constraint_name;


-- ============================================================================
-- 4. Confirmar índices
-- Resultado esperado:
-- - PK
-- - uniques das constraints
-- - índice único parcial da variante padrão
-- - índices auxiliares de FK
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'card_variant'
ORDER BY indexname;


-- ============================================================================
-- 5. Confirmar índice único parcial da variante padrão
-- Resultado esperado: 1 registro
-- ============================================================================

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_catalog.pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'card_variant'
  AND indexname = 'uq_card_variant_one_default_per_card'
  AND indexdef ILIKE '%WHERE (is_default = true)%';


-- ============================================================================
-- 6. Confirmar triggers
-- Resultado esperado: 2 registros
-- ============================================================================

SELECT
    event_object_schema,
    event_object_table,
    trigger_name,
    action_timing,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table = 'card_variant'
ORDER BY
    trigger_name,
    event_manipulation;


-- ============================================================================
-- 7. Confirmar funções utilizadas pelos triggers
-- Resultado esperado: 2 registros
-- ============================================================================

SELECT
    n.nspname AS function_schema,
    p.proname AS function_name
FROM pg_catalog.pg_proc AS p
INNER JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'set_updated_at',
      'validate_card_variant_game_consistency'
  )
ORDER BY p.proname;


-- ============================================================================
-- 8. Confirmar Row Level Security
-- Resultado esperado:
-- rowsecurity = true
-- ============================================================================

SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
  AND tablename = 'card_variant';


-- ============================================================================
-- 9. Verificar combinações duplicadas Card + Variant Type
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    card_id,
    variant_type_id,
    COUNT(*) AS duplicate_count
FROM public.card_variant
GROUP BY
    card_id,
    variant_type_id
HAVING COUNT(*) > 1;


-- ============================================================================
-- 10. Verificar variant_order duplicado dentro da Card
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    card_id,
    variant_order,
    COUNT(*) AS duplicate_count
FROM public.card_variant
GROUP BY
    card_id,
    variant_order
HAVING COUNT(*) > 1;


-- ============================================================================
-- 11. Verificar Cards com mais de uma variante padrão
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    card_id,
    COUNT(*) AS default_variant_count
FROM public.card_variant
WHERE is_default = TRUE
GROUP BY card_id
HAVING COUNT(*) > 1;


-- ============================================================================
-- 12. Verificar variant_order inválido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    card_id,
    variant_type_id,
    variant_order
FROM public.card_variant
WHERE variant_order <= 0;


-- ============================================================================
-- 13. Verificar referências inválidas para Card
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cv.id,
    cv.card_id
FROM public.card_variant AS cv
LEFT JOIN public.card AS c
    ON c.id = cv.card_id
WHERE c.id IS NULL;


-- ============================================================================
-- 14. Verificar referências inválidas para Card Variant Type
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cv.id,
    cv.variant_type_id
FROM public.card_variant AS cv
LEFT JOIN public.card_variant_type AS cvt
    ON cvt.id = cv.variant_type_id
WHERE cvt.id IS NULL;


-- ============================================================================
-- 15. Verificar inconsistência de Game
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cv.id AS card_variant_id,
    c.id AS card_id,
    cs.code AS card_set_code,
    e.game_id AS card_game_id,
    cvt.code AS variant_type_code,
    cvt.game_id AS variant_type_game_id
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


-- ============================================================================
-- 16. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    created_at,
    updated_at
FROM public.card_variant
WHERE created_at IS NULL
   OR updated_at IS NULL;


-- ============================================================================
-- 17. Visão estrutural dos registros existentes
-- Antes do Seed 860, o resultado pode estar vazio.
-- ============================================================================

SELECT
    cs.code AS card_set_code,
    c.collector_number,
    c.name AS card_name,
    cvt.code AS variant_type_code,
    cv.variant_order,
    cv.is_default,
    cv.created_at,
    cv.updated_at
FROM public.card_variant AS cv
INNER JOIN public.card AS c
    ON c.id = cv.card_id
INNER JOIN public.card_set AS cs
    ON cs.id = c.card_set_id
INNER JOIN public.card_variant_type AS cvt
    ON cvt.id = cv.variant_type_id
ORDER BY
    cs.release_order,
    c.collector_order,
    cv.variant_order;
