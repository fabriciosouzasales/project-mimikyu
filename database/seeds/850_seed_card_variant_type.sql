/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 850 - Seed Card Variant Type
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cadastra e mantém os tipos de variante colecionável atualmente suportados para
o Pokémon Trading Card Game.

Descrição:
Esta Query cria e atualiza o catálogo canônico de Card Variant Types do Game
POKEMON.

Catálogo canônico atual:
1. STANDARD
2. HOLO
3. REVERSE_HOLO
4. POKE_BALL_REVERSE
5. MASTER_BALL_REVERSE
6. PROMO_STAMPED

Alterações da versão 1.1:
- Inclusão do tipo HOLO.
- Atualização da sequência de display_order para 1 a 6.
- Correção do bloco WITH para manter target_game e source_variant_type na
  mesma instrução INSERT.
- Tratamento seguro da restrição UNIQUE (game_id, display_order) durante a
  reorganização dos registros já existentes.
- Manutenção do comportamento idempotente por UPSERT.

Observação importante:
Como a versão 1.0 já pode ter sido executada, os registros existentes ocupam
as posições 1 a 5. A inclusão de HOLO na posição 2 causaria conflito imediato
com REVERSE_HOLO. Por isso, esta Query desloca temporariamente os registros
canônicos existentes para uma faixa de ordem reservada antes de executar o
UPSERT definitivo.

Regras de Negócio:
- O Game POKEMON deve existir.
- O seed deve ser idempotente.
- Registros existentes devem convergir para os valores desta Query.
- A Query não deve excluir tipos adicionais automaticamente.
- code é a chave natural dentro do Game.
- display_order determina a ordem de apresentação.
- A execução repetida não deve gerar duplicidades.
- Tipos adicionais fora do catálogo canônico não são alterados.

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 151 - Create Card Variant Type Triggers.
- Seed do Game POKEMON.

===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;
BEGIN
    SELECT id
      INTO v_game_id
      FROM public.game
     WHERE code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 850: o Game POKEMON não está cadastrado.';
    END IF;
END;
$$;

-- ============================================================================
-- 1. Liberar temporariamente as posições canônicas
--
-- Necessário para evitar conflito com:
-- UNIQUE (game_id, display_order)
--
-- Exemplo:
-- REVERSE_HOLO já está na posição 2 e HOLO precisa ser inserido na posição 2.
-- ============================================================================

UPDATE public.card_variant_type AS cvt
SET display_order = cvt.display_order + 1000
FROM public.game AS g
WHERE g.id = cvt.game_id
  AND g.code = 'POKEMON'
  AND cvt.code IN (
      'STANDARD',
      'HOLO',
      'REVERSE_HOLO',
      'POKE_BALL_REVERSE',
      'MASTER_BALL_REVERSE',
      'PROMO_STAMPED'
  )
  AND cvt.display_order < 1000;


-- ============================================================================
-- 2. Inserir ou atualizar o catálogo canônico
-- ============================================================================

WITH target_game AS (
    SELECT id AS game_id
    FROM public.game
    WHERE code = 'POKEMON'
),
source_variant_type (
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
INSERT INTO public.card_variant_type (
    game_id,
    code,
    name,
    description,
    display_order
)
SELECT
    tg.game_id,
    svt.code,
    svt.name,
    svt.description,
    svt.display_order
FROM target_game AS tg
CROSS JOIN source_variant_type AS svt
ON CONFLICT (game_id, code)
DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    display_order = EXCLUDED.display_order;


-- ============================================================================
-- 3. Validação interna da execução
-- ============================================================================

DO $$
DECLARE
    v_registered_total INTEGER;
    v_invalid_total INTEGER;
BEGIN
    SELECT COUNT(*)
      INTO v_registered_total
      FROM public.card_variant_type AS cvt
      INNER JOIN public.game AS g
          ON g.id = cvt.game_id
     WHERE g.code = 'POKEMON'
       AND cvt.code IN (
           'STANDARD',
           'HOLO',
           'REVERSE_HOLO',
           'POKE_BALL_REVERSE',
           'MASTER_BALL_REVERSE',
           'PROMO_STAMPED'
       );

    IF v_registered_total <> 6 THEN
        RAISE EXCEPTION
            'Falha na Query 850: esperados 6 tipos canônicos, encontrados %.',
            v_registered_total;
    END IF;

    SELECT COUNT(*)
      INTO v_invalid_total
      FROM public.card_variant_type AS cvt
      INNER JOIN public.game AS g
          ON g.id = cvt.game_id
     WHERE g.code = 'POKEMON'
       AND (
           (cvt.code = 'STANDARD'            AND cvt.display_order <> 1)
        OR (cvt.code = 'HOLO'                AND cvt.display_order <> 2)
        OR (cvt.code = 'REVERSE_HOLO'        AND cvt.display_order <> 3)
        OR (cvt.code = 'POKE_BALL_REVERSE'   AND cvt.display_order <> 4)
        OR (cvt.code = 'MASTER_BALL_REVERSE' AND cvt.display_order <> 5)
        OR (cvt.code = 'PROMO_STAMPED'       AND cvt.display_order <> 6)
       );

    IF v_invalid_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 850: existem % tipos canônicos com display_order incorreto.',
            v_invalid_total;
    END IF;
END;
$$;

COMMIT;
