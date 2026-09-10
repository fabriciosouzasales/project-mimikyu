/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 921 - Validate Card Set Finalization (Promo Index + Release Order)
Arquivo.....: 921_validate_card_set_finalization.sql
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Criado em...: 2026-09-09, em CATALOG-HISTORICAL-BOOTSTRAP-02-CARD-SETS-FINALIZATION-CORRECTION-01

Objetivo....:
Confirmar, de forma 100% READ-ONLY e independente das Queries que executaram,
o estado final do fechamento técnico do STEP 2 — CARD SETS:

  - Query 2161: índice único parcial `uq_card_set_expansion_promo` presente
    e com a definição correta;
  - Query 2162: `release_order` definitivo nos 199 Card Sets Pokémon.

Numeração....:
`921` é livre. `920_validate_card_set.sql` já existe e permanece intocado —
este arquivo é complementar, específico desta rodada, não o substitui.

Uso.........:
Executar UMA VEZ, após 2161 e 2162. Não escreve nada, não cria objeto
temporário, não abre transação explícita. Devolve uma tabela: qualquer linha
com `resultado = 'FAIL'` reprova o gate.

Gate esperado: 14 verificações, 14 PASS, 0 FAIL.
===============================================================================
*/

WITH
game AS (
    SELECT id FROM public.game WHERE code = 'POKEMON'
),
pk AS (
    SELECT c.*, e.code AS exp_code, e.release_order AS exp_ro
    FROM public.card_set c
    JOIN public.expansion e ON e.id = c.expansion_id
    WHERE e.game_id = (SELECT id FROM game)
),
-- A lista de subsets é repetida literalmente (e não via CTE) para manter cada
-- expressão auto-contida e evitar subconsulta escalar dentro de ORDER BY de
-- window function.
esperado AS (
    SELECT p.id, p.exp_code, p.code, p.release_order,
           row_number() OVER (
               PARTITION BY p.expansion_id
               ORDER BY p.release_date,
                        CASE p.set_type
                            WHEN 'ENERGY' THEN 0
                            WHEN 'PROMO'  THEN 1
                            ELSE 2
                        END,
                        (p.code = ANY (ARRAY['EXU','RC','SMA','SWSH4.5SV','CEL25CC',
                                             'SWSH9TG','SWSH10TG','SWSH11TG','SWSH12TG','SWSH12.5GG'])),
                        p.code COLLATE "C"
           ) AS ro_esperado
    FROM pk p
),
-- Pares (principal, subset) que empatam em release_date dentro da mesma
-- Expansion. A regra editorial exige principal ANTES do subset.
pares_subset AS (
    SELECT a.exp_code, a.code AS principal, b.code AS subset,
           a.release_order AS ro_principal, b.release_order AS ro_subset
    FROM pk a
    JOIN pk b
      ON b.expansion_id = a.expansion_id
     AND b.release_date = a.release_date
     AND b.code = ANY (ARRAY['EXU','RC','SMA','SWSH4.5SV','CEL25CC',
                             'SWSH9TG','SWSH10TG','SWSH11TG','SWSH12TG','SWSH12.5GG'])
     AND NOT (a.code = ANY (ARRAY['EXU','RC','SMA','SWSH4.5SV','CEL25CC',
                                  'SWSH9TG','SWSH10TG','SWSH11TG','SWSH12TG','SWSH12.5GG']))
),
verificacoes AS (

    -- ---------- Query 2161 — índice PROMO ----------
    SELECT 1 AS n, '2161 índice uq_card_set_expansion_promo existe' AS verificacao,
           (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
             WHERE ns.nspname = 'public' AND c.relname = 'uq_card_set_expansion_promo'
               AND c.relkind = 'i')::text AS obtido,
           '1' AS esperado_txt

    -- Verificação #2 — critério ESTRUTURAL via catálogo (corrigido em
    -- IMPLEMENTATION-02). O casamento por string sobre pg_get_indexdef()
    -- falhava porque o Postgres injeta cast no predicado de coluna varchar:
    -- `WHERE ((set_type)::text = 'PROMO'::text)`, com DOIS parênteses.
    UNION ALL
    SELECT 2, 'índice é UNIQUE, sobre (expansion_id), parcial em set_type = PROMO',
           (SELECT count(*)
              FROM pg_index i
              JOIN pg_class ic ON ic.oid = i.indexrelid
              JOIN pg_class tc ON tc.oid = i.indrelid
              JOIN pg_namespace ns ON ns.oid = tc.relnamespace
             WHERE ns.nspname  = 'public'
               AND tc.relname  = 'card_set'
               AND ic.relname  = 'uq_card_set_expansion_promo'
               AND i.indisunique
               AND i.indpred IS NOT NULL
               AND i.indnkeyatts = 1
               AND i.indkey[0] = (
                   SELECT attnum FROM pg_attribute
                   WHERE attrelid = tc.oid AND attname = 'expansion_id' AND NOT attisdropped
               )
               AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%set_type%PROMO%')::text,
           '1'

    UNION ALL
    SELECT 3, 'card_set passa a ter exatamente 4 índices',
           (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'card_set')::text,
           '4'

    UNION ALL
    SELECT 4, 'zero Expansion com mais de um PROMO (todos os Games)',
           (SELECT count(*) FROM (
               SELECT expansion_id FROM public.card_set WHERE set_type = 'PROMO'
               GROUP BY expansion_id HAVING count(*) > 1) v)::text,
           '0'

    UNION ALL
    SELECT 5, 'PROMO: 10 Card Sets em 10 Expansions distintas',
           (SELECT count(*)::text || '/' || count(DISTINCT expansion_id)::text
              FROM public.card_set WHERE set_type = 'PROMO'),
           '10/10'

    UNION ALL
    SELECT 6, 'ck_card_set_promo_size satisfeito (base = total em todo PROMO)',
           (SELECT count(*) FROM public.card_set
             WHERE set_type = 'PROMO' AND base_set_size <> total_set_size)::text,
           '0'

    -- ---------- Query 2162 — release_order ----------
    UNION ALL
    SELECT 7, '2162 universo: 199 Card Sets Pokémon em 17 Expansions',
           (SELECT count(*)::text || '/' || count(DISTINCT expansion_id)::text FROM pk),
           '199/17'

    UNION ALL
    SELECT 8, 'zero release_order >= 1000 (resíduo do bootstrap eliminado)',
           (SELECT count(*) FROM pk WHERE release_order >= 1000)::text,
           '0'

    UNION ALL
    SELECT 9, 'toda Expansion começa em 1 e é contígua até N',
           (SELECT count(*) FROM (
               SELECT expansion_id FROM pk GROUP BY expansion_id
               HAVING min(release_order) <> 1
                   OR max(release_order) <> count(*)
                   OR count(DISTINCT release_order) <> count(*)) g)::text,
           '0'

    UNION ALL
    SELECT 10, 'unicidade (expansion_id, release_order)',
           (SELECT count(*) FROM (
               SELECT expansion_id, release_order FROM pk
               GROUP BY expansion_id, release_order HAVING count(*) > 1) d)::text,
           '0'

    UNION ALL
    SELECT 11, 'faixa global final é 1..28',
           (SELECT min(release_order)::text || '..' || max(release_order)::text FROM pk),
           '1..28'

    UNION ALL
    SELECT 12, 'regra determinística aplicada linha a linha (199/199)',
           (SELECT count(*) FROM esperado WHERE release_order <> ro_esperado)::text,
           '0'

    UNION ALL
    SELECT 13, 'regra 3: publicação principal antes do subset em todos os 10 pares',
           (SELECT count(*) FROM pares_subset WHERE ro_principal >= ro_subset)::text
           || '/' || (SELECT count(*) FROM pares_subset)::text,
           '0/10'

    UNION ALL
    SELECT 14, 'regra 2: em empate de data, ENERGY antes de PROMO antes do resto',
           (SELECT count(*) FROM pk a JOIN pk b
              ON b.expansion_id = a.expansion_id AND b.release_date = a.release_date
             WHERE (CASE a.set_type WHEN 'ENERGY' THEN 0 WHEN 'PROMO' THEN 1 ELSE 2 END)
                 < (CASE b.set_type WHEN 'ENERGY' THEN 0 WHEN 'PROMO' THEN 1 ELSE 2 END)
               AND a.release_order > b.release_order)::text,
           '0'
)
SELECT n AS "#",
       verificacao,
       esperado_txt AS esperado,
       obtido,
       CASE WHEN obtido = esperado_txt THEN 'PASS' ELSE 'FAIL' END AS resultado
FROM verificacoes
ORDER BY n;

/*
-------------------------------------------------------------------------------
CONFERÊNCIA VISUAL (opcional) — sequência final por Expansion.
Read-only, sem gate. Útil para inspeção humana do resultado.
-------------------------------------------------------------------------------

SELECT e.release_order AS exp_ordem, e.code AS expansao,
       c.release_order AS ordem, c.code, c.set_type, c.release_date, c.name
FROM public.card_set c
JOIN public.expansion e ON e.id = c.expansion_id
JOIN public.game g ON g.id = e.game_id
WHERE g.code = 'POKEMON'
ORDER BY e.release_order, c.release_order;
*/
