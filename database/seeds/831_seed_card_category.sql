/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 831 - Seed Card Category
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cadastra e atualiza as categorias editoriais atualmente utilizadas para
classificar as cartas do Pokémon TCG.

Descrição:
Insere na tabela card_category as três categorias principais identificadas nos
checklists oficiais do Pokémon TCG:
- Pokémon
- Treinador
- Energia

As categorias pertencem ao Game POKEMON e serão utilizadas posteriormente pela
tabela card.

Regras de Negócio:
- Somente categorias comprovadamente utilizadas pelo catálogo são cadastradas.
- A categoria deve pertencer ao Game POKEMON.
- O código representa a identificação técnica e estável da categoria.
- O nome preserva a nomenclatura principal em português.
- A ordem de exibição segue a sequência editorial adotada pelo catálogo.
- A Query deve ser idempotente.
- Registros existentes devem ser atualizados para convergir ao modelo canônico.
- A execução deve falhar caso o Game POKEMON não esteja cadastrado.

Pré-requisitos:
- Query 100 - Create Game Table.
- Query 800 - Seed Game.
- Query 132 - Create Card Category Table.
- Query 133 - Create Card Category Trigger.
===============================================================================
*/

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
            'Não foi possível executar a Query 831: o Game POKEMON não está cadastrado.';
    END IF;

    INSERT INTO public.card_category (
        game_id,
        code,
        name,
        display_order
    )
    VALUES
        (
            v_game_id,
            'POKEMON',
            'Pokémon',
            1
        ),
        (
            v_game_id,
            'TRAINER',
            'Treinador',
            2
        ),
        (
            v_game_id,
            'ENERGY',
            'Energia',
            3
        )
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        display_order = EXCLUDED.display_order;
END;
$$;
