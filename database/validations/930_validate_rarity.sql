/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 930 - Validate Rarity
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18
Descrição resumida:
Valida a estrutura, os dados, os símbolos e as regras de integridade da
tabela rarity.
Descrição:
Executa consultas de verificação para confirmar a integridade da entidade
rarity, incluindo:
- dados cadastrados;
- quantidade de registros;
- relacionamento com Game;
- unicidade dos códigos;
- preenchimento e formato dos símbolos;
- ordenação;
- nomes obrigatórios;
- timestamps;
- existência do trigger de atualização.
Pré-requisitos:
- Query 130 - Create Rarity Table.
- Query 131 - Create Rarity Trigger.
- Query 830 - Seed Rarity.
===============================================================================
*/

-- ============================================================================
-- 1. Relação completa das raridades
-- Resultado esperado: 9 registros do Game POKEMON
-- ============================================================================
SELECT
    g.code AS game_code,
    r.display_order,
    r.code AS rarity_code,
    r.name AS rarity_name,
    r.symbol_code,
    r.created_at,
    r.updated_at
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
ORDER BY
    g.code,
    r.display_order,
    r.code;

-- ============================================================================
-- 2. Quantidade de raridades por Game
-- Resultado esperado para POKEMON: 9
-- ============================================================================
SELECT
    g.code AS game_code,
    COUNT(*) AS total_rarities
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
GROUP BY
    g.code
ORDER BY
    g.code;

-- ============================================================================
-- 3. Verificar códigos duplicados dentro do mesmo Game
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    g.code AS game_code,
    r.code AS rarity_code,
    COUNT(*) AS duplicate_count
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
GROUP BY
    g.code,
    r.code
HAVING COUNT(*) > 1;

-- ============================================================================
-- 4. Verificar ordens de exibição inválidas
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    display_order
FROM public.rarity
WHERE display_order <= 0;

-- ============================================================================
-- 5. Verificar nomes vazios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    name
FROM public.rarity
WHERE btrim(name) = '';

-- ============================================================================
-- 6. Verificar códigos de raridade inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code
FROM public.rarity
WHERE code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- ============================================================================
-- 7. Verificar símbolos nulos ou vazios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    symbol_code
FROM public.rarity
WHERE symbol_code IS NULL
   OR btrim(symbol_code) = '';

-- ============================================================================
-- 8. Verificar códigos de símbolo inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    game_id,
    code,
    symbol_code
FROM public.rarity
WHERE symbol_code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- ============================================================================
-- 9. Conferir os dados canônicos do Pokémon TCG
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_rarity (
    code,
    name,
    symbol_code,
    display_order
) AS (
    VALUES
        ('COMMON',                    'Comum',                     'BLACK_CIRCLE',       1),
        ('UNCOMMON',                  'Incomum',                   'BLACK_DIAMOND',      2),
        ('RARE',                      'Rara',                      'BLACK_STAR',         3),
        ('DOUBLE_RARE',               'Rara Dupla',                'BLACK_DOUBLE_STAR',  4),
        ('ULTRA_RARE',                'Rara Ultra',                'SILVER_DOUBLE_STAR', 5),
        ('MEGA_ATTACK_RARE',          'Rara Mega Ataque',          'MEGA_ATTACK',        6),
        ('ILLUSTRATION_RARE',         'Ilustração Rara',           'GOLD_STAR',          7),
        ('SPECIAL_ILLUSTRATION_RARE', 'Ilustração Rara Especial',  'GOLD_DOUBLE_STAR',   8),
        ('MEGA_HYPER_RARE',           'Mega Rara Hiper',           'GOLD_DIAMOND',       9)
)
SELECT
    e.code AS expected_code,
    e.name AS expected_name,
    e.symbol_code AS expected_symbol_code,
    e.display_order AS expected_display_order,
    r.name AS persisted_name,
    r.symbol_code AS persisted_symbol_code,
    r.display_order AS persisted_display_order
FROM expected_rarity AS e
LEFT JOIN public.game AS g
    ON g.code = 'POKEMON'
LEFT JOIN public.rarity AS r
    ON r.game_id = g.id
   AND r.code = e.code
WHERE r.id IS NULL
   OR r.name <> e.name
   OR r.symbol_code <> e.symbol_code
   OR r.display_order <> e.display_order;

-- ============================================================================
-- 10. Verificar raridades adicionais não previstas para o Game POKEMON
-- Resultado esperado: nenhum registro
-- ============================================================================
WITH expected_rarity (code) AS (
    VALUES
        ('COMMON'),
        ('UNCOMMON'),
        ('RARE'),
        ('DOUBLE_RARE'),
        ('ULTRA_RARE'),
        ('MEGA_ATTACK_RARE'),
        ('ILLUSTRATION_RARE'),
        ('SPECIAL_ILLUSTRATION_RARE'),
        ('MEGA_HYPER_RARE')
)
SELECT
    r.code,
    r.name,
    r.symbol_code,
    r.display_order
FROM public.rarity AS r
INNER JOIN public.game AS g
    ON g.id = r.game_id
LEFT JOIN expected_rarity AS e
    ON e.code = r.code
WHERE g.code = 'POKEMON'
  AND e.code IS NULL;

-- ============================================================================
-- 11. Verificar a existência do trigger updated_at
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
  AND event_object_table = 'rarity'
  AND trigger_name = 'trg_rarity_set_updated_at';

-- ============================================================================
-- 12. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================
SELECT
    id,
    code,
    created_at,
    updated_at
FROM public.rarity
WHERE created_at IS NULL
   OR updated_at IS NULL;
