/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 830 - Seed Rarity
Versão......: 2.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18
Descrição resumida:
Cadastra e atualiza as raridades oficiais identificadas nas listas de
verificação dos Sets da expansão Megaevolução, incluindo o símbolo visual
oficial de cada uma (symbol_code).
Descrição:
Insere na tabela rarity as classificações de raridade oficialmente utilizadas
pelos Sets atualmente cadastrados no catálogo do Pokémon TCG, incluindo o
identificador do símbolo visual oficial de cada raridade.
A carga é baseada na união das legendas das listas oficiais dos Sets:
- ME1   - Megaevolução
- ME2   - Fogo Fantasmagórico
- ME2.5 - Heróis Excelsos
- ME3   - Equilíbrio Perfeito
- ME4   - Caos Ascendente
Raridades cadastradas (código / symbol_code):
- Comum                     / BLACK_CIRCLE
- Incomum                   / BLACK_DIAMOND
- Rara                      / BLACK_STAR
- Rara Dupla                / BLACK_DOUBLE_STAR
- Rara Ultra                / SILVER_DOUBLE_STAR
- Rara Mega Ataque          / MEGA_ATTACK
- Ilustração Rara           / GOLD_STAR
- Ilustração Rara Especial  / GOLD_DOUBLE_STAR
- Mega Rara Hiper           / GOLD_DIAMOND
Regras de Negócio:
- Somente raridades comprovadas pelas listas oficiais são cadastradas.
- A raridade deve pertencer ao Game POKEMON.
- O código representa a identificação técnica e estável da raridade.
- O nome preserva a nomenclatura oficial em português.
- O symbol_code representa a identidade visual oficial (formato, quantidade
  e estilo/cor), conforme a legenda oficial do catálogo.
- A ordem de exibição segue a sequência apresentada nas legendas oficiais.
- A Query deve ser idempotente.
- Registros existentes devem ser atualizados para convergir ao modelo canônico.
- A execução deve falhar caso o Game POKEMON não esteja cadastrado.
Pré-requisitos:
- Query 100 - Create Game Table.
- Query 800 - Seed Game.
- Query 130 - Create Rarity Table (v2.0, com symbol_code).
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
        symbol_code,
        display_order
    )
    VALUES
        (v_game_id, 'COMMON',                    'Comum',                     'BLACK_CIRCLE',        1),
        (v_game_id, 'UNCOMMON',                  'Incomum',                   'BLACK_DIAMOND',       2),
        (v_game_id, 'RARE',                      'Rara',                      'BLACK_STAR',          3),
        (v_game_id, 'DOUBLE_RARE',               'Rara Dupla',                'BLACK_DOUBLE_STAR',   4),
        (v_game_id, 'ULTRA_RARE',                'Rara Ultra',                'SILVER_DOUBLE_STAR',  5),
        (v_game_id, 'MEGA_ATTACK_RARE',          'Rara Mega Ataque',          'MEGA_ATTACK',         6),
        (v_game_id, 'ILLUSTRATION_RARE',         'Ilustração Rara',           'GOLD_STAR',           7),
        (v_game_id, 'SPECIAL_ILLUSTRATION_RARE', 'Ilustração Rara Especial',  'GOLD_DOUBLE_STAR',    8),
        (v_game_id, 'MEGA_HYPER_RARE',           'Mega Rara Hiper',           'GOLD_DIAMOND',        9)
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        symbol_code = EXCLUDED.symbol_code,
        display_order = EXCLUDED.display_order;
END;
$$;
