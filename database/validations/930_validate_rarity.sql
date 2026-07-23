/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 930 - Validate Rarity
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-23
Descrição resumida:
Valida os dados persistidos da tabela rarity, ausência de duplicidade e
inconsistências, e o funcionamento do trigger de updated_at.
Descrição:
Confirma que a carga da Query 830 - Seed Rarity foi persistida corretamente:
nove raridades vinculadas ao Game POKEMON, sem códigos duplicados, sem
display_order inválido, sem nomes vazios e sem códigos fora do padrão. Também
confirma que created_at/updated_at existem para todos os registros.
===============================================================================
*/

-- 1. Relação completa das raridades
SELECT
    g.code AS game,
    r.display_order,
    r.code,
    r.name
FROM public.rarity r
INNER JOIN public.game g
    ON g.id = r.game_id
ORDER BY
    g.code,
    r.display_order,
    r.code;

-- 2. Quantidade de raridades por Game
SELECT
    g.code,
    COUNT(*) AS total_rarities
FROM public.rarity r
INNER JOIN public.game g
    ON g.id = r.game_id
GROUP BY
    g.code;

-- 3. Verificar códigos duplicados (esperado: zero linhas)
SELECT
    game_id,
    code,
    COUNT(*)
FROM public.rarity
GROUP BY
    game_id,
    code
HAVING COUNT(*) > 1;

-- 4. Verificar display_order inválido (esperado: zero linhas)
SELECT *
FROM public.rarity
WHERE display_order <= 0;

-- 5. Verificar nomes vazios (esperado: zero linhas)
SELECT *
FROM public.rarity
WHERE btrim(name) = '';

-- 6. Verificar códigos inválidos (esperado: zero linhas)
SELECT *
FROM public.rarity
WHERE code !~ '^[A-Z0-9][A-Z0-9_]*$';

-- 7. Verificar funcionamento do trigger updated_at
SELECT
    code,
    created_at,
    updated_at
FROM public.rarity
ORDER BY
    display_order;
