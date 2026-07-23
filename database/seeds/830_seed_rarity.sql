/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 830 - Seed Rarity
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18
Descrição resumida:
Cadastra e atualiza as raridades oficiais identificadas nas listas de
verificação dos Sets da expansão Megaevolução.
Descrição:
Insere na tabela rarity as classificações de raridade oficialmente utilizadas
pelos Sets atualmente cadastrados no catálogo do Pokémon TCG.
A carga é baseada na união das legendas das listas oficiais dos Sets:
- ME1   - Megaevolução
- ME2   - Fogo Fantasmagórico
- ME2.5 - Heróis Excelsos
- ME3   - Equilíbrio Perfeito
- ME4   - Caos Ascendente
Raridades cadastradas:
- Comum
- Incomum
- Rara
- Rara Dupla
- Rara Ultra
- Rara Mega Ataque
- Ilustração Rara
- Ilustração Rara Especial
- Mega Rara Hiper
Regras de Negócio:
- Somente raridades comprovadas pelas listas oficiais são cadastradas.
- A raridade deve pertencer ao Game POKEMON.
- O código representa a identificação técnica e estável da raridade.
- O nome preserva a nomenclatura oficial em português.
- A ordem de exibição segue a sequência apresentada nas legendas oficiais.
- A Query deve ser idempotente.
- Registros existentes devem ser atualizados para convergir ao modelo canônico.
- A execução deve falhar caso o Game POKEMON não esteja cadastrado.
Pré-requisitos:
- Query 100 - Create Game Table.
- Query 800 - Seed Game.
- Query 130 - Create Rarity Table.
- Query 131 - Create Rarity Trigger.
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
            'Não foi possível executar a Query 830: o Game POKEMON não está cadastrado.';
    END IF;

    INSERT INTO public.rarity (
        game_id,
        code,
        name,
        display_order
    )
    VALUES
        (v_game_id, 'COMMON',                    'Comum',                     1),
        (v_game_id, 'UNCOMMON',                  'Incomum',                   2),
        (v_game_id, 'RARE',                      'Rara',                      3),
        (v_game_id, 'DOUBLE_RARE',               'Rara Dupla',                4),
        (v_game_id, 'ULTRA_RARE',                'Rara Ultra',                5),
        (v_game_id, 'MEGA_ATTACK_RARE',          'Rara Mega Ataque',          6),
        (v_game_id, 'ILLUSTRATION_RARE',         'Ilustração Rara',           7),
        (v_game_id, 'SPECIAL_ILLUSTRATION_RARE', 'Ilustração Rara Especial',  8),
        (v_game_id, 'MEGA_HYPER_RARE',           'Mega Rara Hiper',           9)
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        display_order = EXCLUDED.display_order;
END;
$$;
