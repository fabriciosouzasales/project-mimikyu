/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 820 - Seed Card Set
Versão......: 2.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Status......: CANÔNICA
Descrição...:
Insere e mantém atualizados os Card Sets iniciais da Expansion Mega Evolution,
incluindo o Set promocional Black Star Promos.
Os dados dos Sets regulares e especiais foram definidos com base nas folhas
oficiais de verificação e nas datas de lançamento validadas.
Card Sets contemplados:
- ME0   - ME Black Star Promos
- ME1   - Megaevolução
- ME2   - Fogo Fantasmagórico
- ME2.5 - Heróis Excelsos
- ME3   - Equilíbrio Perfeito
- ME4   - Caos Ascendente
Regras de Negócio:
- Os Card Sets devem ser vinculados ao Game POKEMON e à Expansion ME.
- Os UUIDs das entidades relacionadas não devem ser informados diretamente.
- A execução deve ser idempotente.
- Uma nova execução não pode gerar registros duplicados.
- Registros existentes devem ser atualizados conforme os dados definidos
  nesta Query.
- O Set promocional deve ser o primeiro Card Set da Expansion.
- O código do Set promocional deve ser formado pelo código da Expansion
  seguido de 0.
- O nome do Set promocional deve ser formado pelo código da Expansion
  seguido de " Black Star Promos".
- A data de lançamento do Set promocional deve ser igual à data de lançamento
  do primeiro Set não promocional da Expansion.
- A quantidade base do Set promocional deve ser igual à quantidade total.
- A quantidade do Set promocional representa a quantidade de cartas conhecidas
  no momento da atualização do catálogo.
- As quantidades dos Sets regulares e especiais devem corresponder às folhas
  oficiais de verificação.
- A quantidade de cartas secretas não é armazenada diretamente.
- A quantidade de cartas secretas é derivada da diferença entre
  total_set_size e base_set_size.
- ME2.5 é um Set especial.
- ME0 é um Set promocional.
- Os demais Sets cadastrados são regulares.
Pré-requisitos:
- A Query 122 - Adapt Card Set for Promo deve ter sido executada.
- O Game POKEMON deve existir.
- A Expansion ME deve existir.
Nota — Princípio da Fonte Canônica (STD-001, Seção 10):
esta versão consolida em um único snapshot o que antes era feito por duas
Queries separadas — 820 v1.0 (ME1-ME4) e 821 - Seed Promo Card Set (ME0, ver
database/seeds/821_seed_promo_card_set.sql, reclassificada como Status
MIGRATION — histórica). Troca ON CONFLICT ... DO NOTHING por
ON CONFLICT ... DO UPDATE: reexecutar esta Query também corrige registros
já existentes, caso algum dado oficial seja atualizado.
===============================================================================
*/

INSERT INTO public.card_set (
    expansion_id,
    code,
    name,
    set_type,
    release_order,
    release_date,
    base_set_size,
    total_set_size
)
SELECT
    expansion.id,
    seed.code,
    seed.name,
    seed.set_type,
    seed.release_order,
    seed.release_date,
    seed.base_set_size,
    seed.total_set_size
FROM public.expansion
INNER JOIN public.game
    ON game.id = expansion.game_id
CROSS JOIN (
    VALUES
        (
            'ME0',
            'ME Black Star Promos',
            'PROMO',
            1,
            DATE '2025-09-26',
            89,
            89
        ),
        (
            'ME1',
            'Megaevolução',
            'REGULAR',
            2,
            DATE '2025-09-26',
            132,
            188
        ),
        (
            'ME2',
            'Fogo Fantasmagórico',
            'REGULAR',
            3,
            DATE '2025-11-14',
            94,
            130
        ),
        (
            'ME2.5',
            'Heróis Excelsos',
            'SPECIAL',
            4,
            DATE '2026-01-30',
            217,
            295
        ),
        (
            'ME3',
            'Equilíbrio Perfeito',
            'REGULAR',
            5,
            DATE '2026-03-27',
            88,
            124
        ),
        (
            'ME4',
            'Caos Ascendente',
            'REGULAR',
            6,
            DATE '2026-05-22',
            86,
            122
        )
) AS seed (
    code,
    name,
    set_type,
    release_order,
    release_date,
    base_set_size,
    total_set_size
)
WHERE game.code = 'POKEMON'
  AND expansion.code = 'ME'
ON CONFLICT (expansion_id, code)
DO UPDATE SET
    name            = EXCLUDED.name,
    set_type        = EXCLUDED.set_type,
    release_order   = EXCLUDED.release_order,
    release_date    = EXCLUDED.release_date,
    base_set_size   = EXCLUDED.base_set_size,
    total_set_size  = EXCLUDED.total_set_size;
