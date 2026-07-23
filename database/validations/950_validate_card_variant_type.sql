/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 950 - Validate Card Variant Type
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura, a integridade e o seed canônico da tabela
card_variant_type.

Descrição:
Esta Query verifica:
- relação completa dos tipos de variante;
- quantidade canônica do Game POKEMON;
- presença dos seis códigos esperados;
- aderência dos nomes e display_order canônicos;
- tipos adicionais fora do catálogo canônico;
- duplicidades;
- campos obrigatórios;
- formato dos códigos;
- sequência de display_order;
- relacionamento com Game;
- timestamps;
- trigger de updated_at;
- Row Level Security.

Catálogo canônico atual:
1. STANDARD
2. HOLO
3. REVERSE_HOLO
4. POKE_BALL_REVERSE
5. MASTER_BALL_REVERSE
6. PROMO_STAMPED

Alterações da versão 1.1:
- Inclusão do tipo HOLO.
- Atualização da quantidade esperada de 5 para 6.
- Atualização da sequência de display_order de 1 a 6.
- Atualização das listas canônicas de validação.

Regras de Validação:
- Consultas de inconsistência devem retornar zero registros.
- O Game POKEMON deve possuir exatamente seis tipos canônicos.
- Os seis códigos esperados devem estar presentes.
- display_order deve formar a sequência de 1 a 6.
- O trigger de updated_at deve existir.
- O Row Level Security deve estar habilitado.

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 151 - Create Card Variant Type Triggers.
- Query 850 - Seed Card Variant Type, versão 1.1.

===============================================================================
*/

-- ============================================================================
-- 1. Relação completa dos Card Variant Types
-- Resultado esperado: 6 registros para POKEMON
-- ============================================================================

SELECT
    g.code AS game_code,
    cvt.code,
    cvt.name,
    cvt.description,
    cvt.display_order,
    cvt.created_at,
    cvt.updated_at
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
ORDER BY
    g.code,
    cvt.display_order,
    cvt.code;


-- ============================================================================
-- 2. Quantidade canônica para o Game POKEMON
-- Resultado esperado:
-- expected_total = 6
-- registered_total = 6
-- status = COMPLETE
-- ============================================================================

SELECT
    6 AS expected_total,
    COUNT(cvt.id) AS registered_total,
    CASE
        WHEN COUNT(cvt.id) = 6 THEN 'COMPLETE'
        WHEN COUNT(cvt.id) < 6 THEN 'PENDING'
        ELSE 'EXCEEDED'
    END AS status
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
WHERE g.code = 'POKEMON';


-- ============================================================================
-- 3. Verificar tipos canônicos ausentes
-- Resultado esperado: nenhum registro
-- ============================================================================

WITH expected_type (
    code,
    name,
    description,
    display_order
) AS (
    VALUES
        (
            'STANDARD',
            'Padrão',
            'Versão principal da Card, conforme sua impressão editorial padrão.',
            1
        ),
        (
            'HOLO',
            'Holográfica',
            'Versão com acabamento holográfico.',
            2
        ),
        (
            'REVERSE_HOLO',
            'Holográfica Reversa',
            'Versão com acabamento holográfico reverso.',
            3
        ),
        (
            'POKE_BALL_REVERSE',
            'Poké Bola Reversa',
            'Versão holográfica reversa com padrão de Poké Bola.',
            4
        ),
        (
            'MASTER_BALL_REVERSE',
            'Master Bola Reversa',
            'Versão holográfica reversa com padrão de Master Bola.',
            5
        ),
        (
            'PROMO_STAMPED',
            'Promocional Estampada',
            'Versão que possui uma marca ou estampa promocional oficialmente aplicada.',
            6
        )
)
SELECT
    et.code,
    et.name,
    et.description,
    et.display_order
FROM expected_type AS et
LEFT JOIN public.game AS g
    ON g.code = 'POKEMON'
LEFT JOIN public.card_variant_type AS cvt
    ON cvt.game_id = g.id
   AND cvt.code = et.code
WHERE cvt.id IS NULL
ORDER BY et.display_order;


-- ============================================================================
-- 4. Verificar divergências nos valores canônicos
-- Resultado esperado: nenhum registro
-- ============================================================================

WITH expected_type (
    code,
    expected_name,
    expected_description,
    expected_display_order
) AS (
    VALUES
        (
            'STANDARD',
            'Padrão',
            'Versão principal da Card, conforme sua impressão editorial padrão.',
            1
        ),
        (
            'HOLO',
            'Holográfica',
            'Versão com acabamento holográfico.',
            2
        ),
        (
            'REVERSE_HOLO',
            'Holográfica Reversa',
            'Versão com acabamento holográfico reverso.',
            3
        ),
        (
            'POKE_BALL_REVERSE',
            'Poké Bola Reversa',
            'Versão holográfica reversa com padrão de Poké Bola.',
            4
        ),
        (
            'MASTER_BALL_REVERSE',
            'Master Bola Reversa',
            'Versão holográfica reversa com padrão de Master Bola.',
            5
        ),
        (
            'PROMO_STAMPED',
            'Promocional Estampada',
            'Versão que possui uma marca ou estampa promocional oficialmente aplicada.',
            6
        )
)
SELECT
    cvt.code,
    cvt.name AS registered_name,
    et.expected_name,
    cvt.description AS registered_description,
    et.expected_description,
    cvt.display_order AS registered_display_order,
    et.expected_display_order
FROM expected_type AS et
INNER JOIN public.game AS g
    ON g.code = 'POKEMON'
INNER JOIN public.card_variant_type AS cvt
    ON cvt.game_id = g.id
   AND cvt.code = et.code
WHERE cvt.name <> et.expected_name
   OR cvt.description IS DISTINCT FROM et.expected_description
   OR cvt.display_order <> et.expected_display_order
ORDER BY et.expected_display_order;


-- ============================================================================
-- 5. Verificar tipos adicionais fora do catálogo canônico atual
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cvt.code,
    cvt.name,
    cvt.description,
    cvt.display_order
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
WHERE g.code = 'POKEMON'
  AND cvt.code NOT IN (
      'STANDARD',
      'HOLO',
      'REVERSE_HOLO',
      'POKE_BALL_REVERSE',
      'MASTER_BALL_REVERSE',
      'PROMO_STAMPED'
  )
ORDER BY cvt.display_order;


-- ============================================================================
-- 6. Verificar códigos duplicados dentro do mesmo Game
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    g.code AS game_code,
    cvt.code,
    COUNT(*) AS duplicate_count
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
GROUP BY
    g.code,
    cvt.game_id,
    cvt.code
HAVING COUNT(*) > 1;


-- ============================================================================
-- 7. Verificar display_order duplicado dentro do mesmo Game
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    g.code AS game_code,
    cvt.display_order,
    COUNT(*) AS duplicate_count
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
GROUP BY
    g.code,
    cvt.game_id,
    cvt.display_order
HAVING COUNT(*) > 1;


-- ============================================================================
-- 8. Verificar códigos inválidos
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    game_id,
    code
FROM public.card_variant_type
WHERE code IS NULL
   OR btrim(code) = ''
   OR code !~ '^[A-Z][A-Z0-9_]*$';


-- ============================================================================
-- 9. Verificar nomes nulos ou vazios
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    game_id,
    code,
    name
FROM public.card_variant_type
WHERE name IS NULL
   OR btrim(name) = '';


-- ============================================================================
-- 10. Verificar descrições vazias
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    game_id,
    code,
    description
FROM public.card_variant_type
WHERE description IS NOT NULL
  AND btrim(description) = '';


-- ============================================================================
-- 11. Verificar display_order inválido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    game_id,
    code,
    display_order
FROM public.card_variant_type
WHERE display_order <= 0;


-- ============================================================================
-- 12. Verificar sequência de display_order do catálogo canônico
-- Resultado esperado: nenhum registro
-- ============================================================================

WITH expected_order AS (
    SELECT generate_series(1, 6) AS expected_display_order
)
SELECT
    eo.expected_display_order AS missing_display_order
FROM expected_order AS eo
LEFT JOIN public.game AS g
    ON g.code = 'POKEMON'
LEFT JOIN public.card_variant_type AS cvt
    ON cvt.game_id = g.id
   AND cvt.display_order = eo.expected_display_order
WHERE cvt.id IS NULL
ORDER BY eo.expected_display_order;


-- ============================================================================
-- 13. Verificar registros sem Game válido
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    cvt.id,
    cvt.game_id,
    cvt.code,
    cvt.name
FROM public.card_variant_type AS cvt
LEFT JOIN public.game AS g
    ON g.id = cvt.game_id
WHERE g.id IS NULL;


-- ============================================================================
-- 14. Verificar timestamps obrigatórios
-- Resultado esperado: nenhum registro
-- ============================================================================

SELECT
    id,
    code,
    created_at,
    updated_at
FROM public.card_variant_type
WHERE created_at IS NULL
   OR updated_at IS NULL;


-- ============================================================================
-- 15. Verificar o trigger updated_at
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
  AND event_object_table = 'card_variant_type'
  AND trigger_name = 'trg_card_variant_type_set_updated_at';


-- ============================================================================
-- 16. Verificar se o Row Level Security está habilitado
-- Resultado esperado:
-- rowsecurity = true
-- ============================================================================

SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
  AND tablename = 'card_variant_type';
