/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 821 - Seed Promo Card Set
Versão......: 1.0
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-17
Status......: MIGRATION (reclassificação retroativa — ver STD-001, Seção 10,
               Princípio da Fonte Canônica). Esta Query inseriu ME0
               separadamente, em um banco onde os demais Sets já existiam.
               Não é mais necessária em uma instalação nova: a Query canônica
               820 v2.0 (ver database/seeds/820_seed_card_set.sql) já inclui
               ME0 junto com os demais Sets em um único snapshot. Preservada
               apenas como registro histórico.
Descrição...:
Insere o Card Set promocional Black Star da Expansion Mega Evolution.
Regras de Negócio:
- O código do Set promocional é formado pelo código da Expansion seguido de 0.
- O nome é formado pelo código da Expansion seguido de "Black Star Promos".
- O Set promocional ocupa a primeira posição da Expansion.
- A data de lançamento é igual à data do primeiro Set da Expansion.
- A quantidade base é igual à quantidade total.
- A execução deve ser idempotente.
NOTA (ver docs/05-modelo-de-dados.md, seção Set): após a reescrita planejada
de 820_seed_card_set.sql para incluir este registro no snapshot completo da
Expansion, esta Query 821 passa a ser mantida apenas como histórico de
migrations já executadas — deixa de fazer parte do fluxo principal de
instalação.
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
    'ME0',
    'ME Black Star Promos',
    'PROMO',
    1,
    DATE '2025-09-26',
    89,
    89
FROM public.expansion
INNER JOIN public.game
    ON game.id = expansion.game_id
WHERE game.code = 'POKEMON'
  AND expansion.code = 'ME'
ON CONFLICT (expansion_id, code)
DO NOTHING;
