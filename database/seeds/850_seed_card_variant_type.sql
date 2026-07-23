/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 850 - Seed Card Variant Type
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cadastra e mantém os tipos de variante colecionável atualmente suportados para
o Pokémon Trading Card Game.

Catálogo canônico atual:
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

Alterações da versão 1.2:
- Inclusão de ENERGY_REVERSE.
- Inclusão de LOVE_BALL_REVERSE.
- Inclusão de FRIEND_BALL_REVERSE.
- Inclusão de QUICK_BALL_REVERSE.
- Inclusão de DUSK_BALL_REVERSE.
- Inclusão de ROCKET_REVERSE.
- Reorganização da sequência de display_order para 1 a 12.
- Tratamento seguro da restrição UNIQUE (game_id, display_order).
- Manutenção da idempotência por UPSERT.

Motivação da versão 1.2:
A análise editorial da coleção ME2.5 (Heróis Excelsios) revelou que a reversa
holográfica das Cards do conjunto base não segue um único padrão genérico —
cada Pokémon elegível recebe uma reversa com o padrão de uma Poké Bola
específica de sua linha evolutiva (Poké Ball, Love Ball, Friend Ball, Quick
Ball, Dusk Ball), Pokémon da Equipe Rocket usam o símbolo "R", e Pokémon não
`ex` também possuem uma reversa de Energia. Nenhuma variante Master Ball
Reverse foi encontrada nesta coleção. O catálogo de seis tipos (v1.1) tratava
esses padrões como equivalentes ao já existente POKE_BALL_REVERSE, o que
violaria a regra de negócio de que card_variant deve representar cada
variante colecionável oficialmente existente (ver Query 160).

Pré-requisitos:
- Query 150 - Create Card Variant Type Table.
- Query 151 - Create Card Variant Type Triggers.
- Seed do Game POKEMON.

===============================================================================

NOTA DE DOCUMENTAÇÃO (Princípio da Fonte Canônica, STD-001 Seção 10): esta
versão substitui integralmente a v1.1 (6 tipos), mantida apenas no histórico
de revisões dos documentos de domínio (04-domain-model.md/05-modelo-de-dados.md).
Confirmada executada por Fabrício via captura de tela real do Table Editor do
Supabase, mostrando os 12 tipos já cadastrados fisicamente.
===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;
    v_registered_total INTEGER;
    v_invalid_total INTEGER;
BEGIN
    SELECT id
      INTO v_game_id
      FROM public.game
     WHERE code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 850: o Game POKEMON não está cadastrado.';
    END IF;

    /*
    ===========================================================================
    1. Liberar temporariamente as posições canônicas
    ===========================================================================
    */

    UPDATE public.card_variant_type
       SET display_order = display_order + 1000
     WHERE game_id = v_game_id
       AND code IN (
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
       AND display_order < 1000;

    /*
    ===========================================================================
    2. Inserir ou atualizar o catálogo canônico
    ===========================================================================
    */

    INSERT INTO public.card_variant_type (
        game_id,
        code,
        name,
        description,
        display_order
    )
    VALUES
        (
            v_game_id,
            'STANDARD',
            'Padrão',
            'Versão principal da Card, conforme sua impressão editorial padrão.',
            1
        ),
        (
            v_game_id,
            'HOLO',
            'Holográfica',
            'Versão com acabamento holográfico.',
            2
        ),
        (
            v_game_id,
            'REVERSE_HOLO',
            'Holográfica Reversa',
            'Versão com acabamento holográfico reverso genérico.',
            3
        ),
        (
            v_game_id,
            'ENERGY_REVERSE',
            'Energia Reversa',
            'Versão holográfica reversa com padrão de Energia.',
            4
        ),
        (
            v_game_id,
            'POKE_BALL_REVERSE',
            'Poké Bola Reversa',
            'Versão holográfica reversa com padrão de Poké Bola.',
            5
        ),
        (
            v_game_id,
            'LOVE_BALL_REVERSE',
            'Love Ball Reversa',
            'Versão holográfica reversa com padrão de Love Ball.',
            6
        ),
        (
            v_game_id,
            'FRIEND_BALL_REVERSE',
            'Friend Ball Reversa',
            'Versão holográfica reversa com padrão de Friend Ball.',
            7
        ),
        (
            v_game_id,
            'QUICK_BALL_REVERSE',
            'Quick Ball Reversa',
            'Versão holográfica reversa com padrão de Quick Ball.',
            8
        ),
        (
            v_game_id,
            'DUSK_BALL_REVERSE',
            'Dusk Ball Reversa',
            'Versão holográfica reversa com padrão de Dusk Ball.',
            9
        ),
        (
            v_game_id,
            'ROCKET_REVERSE',
            'Equipe Rocket Reversa',
            'Versão holográfica reversa com padrão ou símbolo da Equipe Rocket.',
            10
        ),
        (
            v_game_id,
            'MASTER_BALL_REVERSE',
            'Master Ball Reversa',
            'Versão holográfica reversa com padrão de Master Ball.',
            11
        ),
        (
            v_game_id,
            'PROMO_STAMPED',
            'Promocional Estampada',
            'Versão que possui uma marca ou estampa promocional oficialmente aplicada.',
            12
        )
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        display_order = EXCLUDED.display_order;

    /*
    ===========================================================================
    3. Validação interna
    ===========================================================================
    */

    SELECT COUNT(*)
      INTO v_registered_total
      FROM public.card_variant_type
     WHERE game_id = v_game_id
       AND code IN (
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
       );

    IF v_registered_total <> 12 THEN
        RAISE EXCEPTION
            'Falha na Query 850: esperados 12 tipos canônicos, encontrados %.',
            v_registered_total;
    END IF;

    SELECT COUNT(*)
      INTO v_invalid_total
      FROM public.card_variant_type AS cvt
     WHERE cvt.game_id = v_game_id
       AND (
           (cvt.code = 'STANDARD' AND cvt.display_order <> 1)
        OR (cvt.code = 'HOLO' AND cvt.display_order <> 2)
        OR (cvt.code = 'REVERSE_HOLO' AND cvt.display_order <> 3)
        OR (cvt.code = 'ENERGY_REVERSE' AND cvt.display_order <> 4)
        OR (cvt.code = 'POKE_BALL_REVERSE' AND cvt.display_order <> 5)
        OR (cvt.code = 'LOVE_BALL_REVERSE' AND cvt.display_order <> 6)
        OR (cvt.code = 'FRIEND_BALL_REVERSE' AND cvt.display_order <> 7)
        OR (cvt.code = 'QUICK_BALL_REVERSE' AND cvt.display_order <> 8)
        OR (cvt.code = 'DUSK_BALL_REVERSE' AND cvt.display_order <> 9)
        OR (cvt.code = 'ROCKET_REVERSE' AND cvt.display_order <> 10)
        OR (cvt.code = 'MASTER_BALL_REVERSE' AND cvt.display_order <> 11)
        OR (cvt.code = 'PROMO_STAMPED' AND cvt.display_order <> 12)
       );

    IF v_invalid_total <> 0 THEN
        RAISE EXCEPTION
            'Falha na Query 850: existem % tipos canônicos com display_order incorreto.',
            v_invalid_total;
    END IF;
END;
$$;

COMMIT;
