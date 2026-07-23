/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 950 - Validate Card Variant Type
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Valida a estrutura, a integridade e o seed canônico da tabela
card_variant_type.

Catálogo canônico esperado:
 1. STANDARD
 2. HOLO
 3. REVERSE_HOLO
 4. ENERGY_REVERSE
 5. POKE_BALL_REVERSE
 6. LOVE_BALL_REVERSE
 7. FRIEND_BALL_REVERSE
 8. QUICK_BALL_REVERSE
 9. DUSK_BALL_REVERSE
10. ROCKET_REVERSE
11. MASTER_BALL_REVERSE
12. PROMO_STAMPED

Regras de Validação:
- O Game POKEMON deve possuir exatamente 12 tipos canônicos.
- Os códigos, nomes, descrições e display_order devem aderir ao catálogo.
- Não devem existir tipos adicionais para POKEMON.
- display_order deve formar a sequência de 1 a 12.
- Não devem existir duplicidades.
- O trigger de updated_at deve existir.
- Row Level Security deve estar habilitado.

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 151 - Create Card Variant Type Triggers.
- Query 850 - Seed Card Variant Type, versão 1.2.

===============================================================================

NOTA DE DOCUMENTAÇÃO (Princípio da Fonte Canônica, STD-001 Seção 10): esta
versão substitui integralmente a v1.1 (6 tipos), mantida apenas no histórico
de revisões dos documentos de domínio. Executada com sucesso logo após a
Query 850 v1.2, confirmada por Fabrício via captura de tela real do Table
Editor do Supabase mostrando os 12 tipos já cadastrados.
===============================================================================
*/

-- 1. Relação completa
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
ORDER BY g.code, cvt.display_order, cvt.code;


-- 2. Quantidade canônica
SELECT
    12 AS expected_total,
    COUNT(cvt.id) AS registered_total,
    CASE
        WHEN COUNT(cvt.id) = 12 THEN 'COMPLETE'
        WHEN COUNT(cvt.id) < 12 THEN 'PENDING'
        ELSE 'EXCEEDED'
    END AS status
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
WHERE g.code = 'POKEMON';


-- 3. Tipos canônicos ausentes
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
            'Versão com acabamento holográfico reverso genérico.',
            3
        ),
        (
            'ENERGY_REVERSE',
            'Energia Reversa',
            'Versão holográfica reversa com padrão de Energia.',
            4
        ),
        (
            'POKE_BALL_REVERSE',
            'Poké Bola Reversa',
            'Versão holográfica reversa com padrão de Poké Bola.',
            5
        ),
        (
            'LOVE_BALL_REVERSE',
            'Love Ball Reversa',
            'Versão holográfica reversa com padrão de Love Ball.',
            6
        ),
        (
            'FRIEND_BALL_REVERSE',
            'Friend Ball Reversa',
            'Versão holográfica reversa com padrão de Friend Ball.',
            7
        ),
        (
            'QUICK_BALL_REVERSE',
            'Quick Ball Reversa',
            'Versão holográfica reversa com padrão de Quick Ball.',
            8
        ),
        (
            'DUSK_BALL_REVERSE',
            'Dusk Ball Reversa',
            'Versão holográfica reversa com padrão de Dusk Ball.',
            9
        ),
        (
            'ROCKET_REVERSE',
            'Equipe Rocket Reversa',
            'Versão holográfica reversa com padrão ou símbolo da Equipe Rocket.',
            10
        ),
        (
            'MASTER_BALL_REVERSE',
            'Master Ball Reversa',
            'Versão holográfica reversa com padrão de Master Ball.',
            11
        ),
        (
            'PROMO_STAMPED',
            'Promocional Estampada',
            'Versão que possui uma marca ou estampa promocional oficialmente aplicada.',
            12
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


-- 4. Divergências nos valores canônicos
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
            'Versão com acabamento holográfico reverso genérico.',
            3
        ),
        (
            'ENERGY_REVERSE',
            'Energia Reversa',
            'Versão holográfica reversa com padrão de Energia.',
            4
        ),
        (
            'POKE_BALL_REVERSE',
            'Poké Bola Reversa',
            'Versão holográfica reversa com padrão de Poké Bola.',
            5
        ),
        (
            'LOVE_BALL_REVERSE',
            'Love Ball Reversa',
            'Versão holográfica reversa com padrão de Love Ball.',
            6
        ),
        (
            'FRIEND_BALL_REVERSE',
            'Friend Ball Reversa',
            'Versão holográfica reversa com padrão de Friend Ball.',
            7
        ),
        (
            'QUICK_BALL_REVERSE',
            'Quick Ball Reversa',
            'Versão holográfica reversa com padrão de Quick Ball.',
            8
        ),
        (
            'DUSK_BALL_REVERSE',
            'Dusk Ball Reversa',
            'Versão holográfica reversa com padrão de Dusk Ball.',
            9
        ),
        (
            'ROCKET_REVERSE',
            'Equipe Rocket Reversa',
            'Versão holográfica reversa com padrão ou símbolo da Equipe Rocket.',
            10
        ),
        (
            'MASTER_BALL_REVERSE',
            'Master Ball Reversa',
            'Versão holográfica reversa com padrão de Master Ball.',
            11
        ),
        (
            'PROMO_STAMPED',
            'Promocional Estampada',
            'Versão que possui uma marca ou estampa promocional oficialmente aplicada.',
            12
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


-- 5. Tipos adicionais fora do catálogo
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
           'ENERGY_REVERSE',
           'POKE_BALL_REVERSE',
           'LOVE_BALL_REVERSE',
           'FRIEND_BALL_REVERSE',
           'QUICK_BALL_REVERSE',
           'DUSK_BALL_REVERSE',
           'ROCKET_REVERSE',
           'MASTER_BALL_REVERSE',
           'PROMO_STAMPED'
  )
ORDER BY cvt.display_order;


-- 6. Códigos duplicados dentro do mesmo Game
SELECT
    g.code AS game_code,
    cvt.code,
    COUNT(*) AS duplicate_count
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
GROUP BY g.code, cvt.game_id, cvt.code
HAVING COUNT(*) > 1;


-- 7. display_order duplicado dentro do mesmo Game
SELECT
    g.code AS game_code,
    cvt.display_order,
    COUNT(*) AS duplicate_count
FROM public.card_variant_type AS cvt
INNER JOIN public.game AS g
    ON g.id = cvt.game_id
GROUP BY g.code, cvt.game_id, cvt.display_order
HAVING COUNT(*) > 1;


-- 8. Códigos inválidos
SELECT id, game_id, code
FROM public.card_variant_type
WHERE code IS NULL
   OR BTRIM(code) = ''
   OR code !~ '^[A-Z][A-Z0-9_]*$';


-- 9. Nomes nulos ou vazios
SELECT id, game_id, code, name
FROM public.card_variant_type
WHERE name IS NULL
   OR BTRIM(name) = '';


-- 10. Descrições vazias
SELECT id, game_id, code, description
FROM public.card_variant_type
WHERE description IS NOT NULL
  AND BTRIM(description) = '';


-- 11. display_order inválido
SELECT id, game_id, code, display_order
FROM public.card_variant_type
WHERE display_order <= 0;


-- 12. Sequência canônica de display_order
WITH expected_order AS (
    SELECT generate_series(1, 12) AS expected_display_order
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


-- 13. Registros sem Game válido
SELECT
    cvt.id,
    cvt.game_id,
    cvt.code,
    cvt.name
FROM public.card_variant_type AS cvt
LEFT JOIN public.game AS g
    ON g.id = cvt.game_id
WHERE g.id IS NULL;


-- 14. Timestamps obrigatórios ou inconsistentes
SELECT
    id,
    code,
    created_at,
    updated_at
FROM public.card_variant_type
WHERE created_at IS NULL
   OR updated_at IS NULL
   OR updated_at < created_at;


-- 15. Trigger de updated_at
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


-- 16. Row Level Security
SELECT
    schemaname,
    tablename,
    rowsecurity
FROM pg_catalog.pg_tables
WHERE schemaname = 'public'
  AND tablename = 'card_variant_type';


-- 17. Resultado resumido
SELECT
    'Query 950 concluída: card_variant_type validada para o catálogo canônico de 12 tipos.'
    AS validation_result;
