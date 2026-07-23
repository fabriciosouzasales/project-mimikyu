/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 840 - Seed Card
Versão......: 2.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cadastra e atualiza as 859 cartas oficiais em português do Brasil dos Card Sets
ME1, ME2, ME2.5, ME3 e ME4 da expansão Megaevolução.

Descrição:
Esta Query consolida o catálogo oficial atualmente suportado pelo Project
Mimikyu para a expansão Megaevolução.

Card Sets contemplados:
- ME1   - Megaevolução:             188 cartas;
- ME2   - Fogo Fantasmagórico:      130 cartas;
- ME2.5 - Heróis Excelsos:          295 cartas;
- ME3   - Equilíbrio Perfeito:      124 cartas;
- ME4   - Caos Ascendente:          122 cartas.

Total canônico: 859 cartas.

Para cada Card são cadastrados:
- Card Set;
- número oficial;
- total-base utilizado como denominador editorial;
- posição no checklist;
- nome oficial em português do Brasil;
- categoria;
- raridade.

O campo collector_total é derivado do base_set_size canônico de cada Card Set:
- ME1: 132;
- ME2: 94;
- ME2.5: 217;
- ME3: 88;
- ME4: 86.

Os checklists oficiais apresentam a numeração integral das cartas, mas não
exibem explicitamente o denominador em todos os registros. Por isso, o valor é
obtido diretamente de card_set.base_set_size após validação.

Regras de Negócio:
- O Game POKEMON deve existir.
- Os cinco Card Sets devem existir e pertencer ao Game POKEMON.
- base_set_size e total_set_size devem coincidir com os valores canônicos.
- As categorias POKEMON, TRAINER e ENERGY devem estar cadastradas.
- Todas as raridades utilizadas devem estar cadastradas.
- collector_number preserva três dígitos.
- collector_order corresponde à posição oficial no checklist.
- A Query deve ser idempotente.
- Registros existentes devem convergir para os dados desta Query.
- A Query não exclui registros automaticamente.
- A execução deve falhar se, ao final, algum Set não possuir exatamente a
  quantidade canônica de Cards.
- A execução deve falhar se existirem Cards adicionais nos Sets contemplados.

Fontes canônicas:
- P10346_ME01_Card_List_PTBR;
- P10347_ME02_Card_List_PTBR;
- ME02pt5_Card_List_PTBR;
- P11218_ME03_Card_List_PTBR;
- ME04_Card_List_PTBR.

Pré-requisitos:
- Query 120 - Create Card Set Table.
- Query 130 - Create Rarity Table.
- Query 132 - Create Card Category Table.
- Query 140 - Create Card Table.
- Query 141 - Create Card Triggers.
- Query 820 - Seed Card Set.
- Query 830 - Seed Rarity.
- Query 831 - Seed Card Category.

===============================================================================
*/

BEGIN;

-- ============================================================================
-- 1. Validar Game, Card Sets, categorias e raridades
-- ============================================================================

DO $$
DECLARE
    v_game_id UUID;
    v_missing_sets TEXT;
    v_invalid_sets TEXT;
    v_category_count INTEGER;
    v_rarity_count INTEGER;
BEGIN
    SELECT id
      INTO v_game_id
      FROM public.game
     WHERE code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 840: o Game POKEMON não está cadastrado.';
    END IF;

    WITH expected_set (
        code,
        base_set_size,
        total_set_size
    ) AS (
        VALUES
        ('ME1', 132, 188),
        ('ME2', 94, 130),
        ('ME2.5', 217, 295),
        ('ME3', 88, 124),
        ('ME4', 86, 122)
    )
    SELECT string_agg(es.code, ', ' ORDER BY es.code)
      INTO v_missing_sets
      FROM expected_set AS es
      LEFT JOIN public.card_set AS cs
        ON cs.code = es.code
      LEFT JOIN public.expansion AS e
        ON e.id = cs.expansion_id
       AND e.game_id = v_game_id
     WHERE e.id IS NULL;

    IF v_missing_sets IS NOT NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 840: Card Sets ausentes ou vinculados a outro Game: %.',
            v_missing_sets;
    END IF;

    WITH expected_set (
        code,
        base_set_size,
        total_set_size
    ) AS (
        VALUES
        ('ME1', 132, 188),
        ('ME2', 94, 130),
        ('ME2.5', 217, 295),
        ('ME3', 88, 124),
        ('ME4', 86, 122)
    )
    SELECT string_agg(
               format(
                   '%s [base=%s/%s; total=%s/%s]',
                   es.code,
                   cs.base_set_size,
                   es.base_set_size,
                   cs.total_set_size,
                   es.total_set_size
               ),
               ', '
               ORDER BY es.code
           )
      INTO v_invalid_sets
      FROM expected_set AS es
      INNER JOIN public.card_set AS cs
        ON cs.code = es.code
      INNER JOIN public.expansion AS e
        ON e.id = cs.expansion_id
       AND e.game_id = v_game_id
     WHERE cs.base_set_size <> es.base_set_size
        OR cs.total_set_size <> es.total_set_size;

    IF v_invalid_sets IS NOT NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 840: tamanhos divergentes: %.',
            v_invalid_sets;
    END IF;

    SELECT COUNT(*)
      INTO v_category_count
      FROM public.card_category
     WHERE game_id = v_game_id
       AND code IN ('POKEMON', 'TRAINER', 'ENERGY');

    IF v_category_count <> 3 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 840: as categorias POKEMON, TRAINER e ENERGY devem estar cadastradas.';
    END IF;

    SELECT COUNT(*)
      INTO v_rarity_count
      FROM public.rarity
     WHERE game_id = v_game_id
       AND code IN (
            'COMMON',
            'DOUBLE_RARE',
            'ILLUSTRATION_RARE',
            'MEGA_ATTACK_RARE',
            'MEGA_HYPER_RARE',
            'RARE',
            'SPECIAL_ILLUSTRATION_RARE',
            'ULTRA_RARE',
            'UNCOMMON'
       );

    IF v_rarity_count <> 9 THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 840: todas as raridades utilizadas pelos cinco Sets devem estar cadastradas.';
    END IF;
END;
$$;


-- ============================================================================
-- 2. Inserir ou atualizar o catálogo canônico de 859 Cards
-- ============================================================================

WITH source_card (
    card_set_code,
    collector_number,
    collector_order,
    name,
    category_code,
    rarity_code
) AS (
    VALUES
        ('ME1', '001', 1, 'Bulbasaur', 'POKEMON', 'COMMON'),
        ('ME1', '002', 2, 'Ivysaur', 'POKEMON', 'COMMON'),
        ('ME1', '003', 3, 'Mega Venusaur ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '004', 4, 'Exeggcute', 'POKEMON', 'COMMON'),
        ('ME1', '005', 5, 'Exeggutor', 'POKEMON', 'UNCOMMON'),
        ('ME1', '006', 6, 'Tangela', 'POKEMON', 'COMMON'),
        ('ME1', '007', 7, 'Tangrowth', 'POKEMON', 'UNCOMMON'),
        ('ME1', '008', 8, 'Chikorita', 'POKEMON', 'COMMON'),
        ('ME1', '009', 9, 'Bayleef', 'POKEMON', 'COMMON'),
        ('ME1', '010', 10, 'Meganium', 'POKEMON', 'RARE'),
        ('ME1', '011', 11, 'Shuckle', 'POKEMON', 'UNCOMMON'),
        ('ME1', '012', 12, 'Celebi', 'POKEMON', 'UNCOMMON'),
        ('ME1', '013', 13, 'Seedot', 'POKEMON', 'COMMON'),
        ('ME1', '014', 14, 'Nuzleaf', 'POKEMON', 'COMMON'),
        ('ME1', '015', 15, 'Shiftry', 'POKEMON', 'UNCOMMON'),
        ('ME1', '016', 16, 'Nincada', 'POKEMON', 'COMMON'),
        ('ME1', '017', 17, 'Ninjask', 'POKEMON', 'UNCOMMON'),
        ('ME1', '018', 18, 'Dhelmise', 'POKEMON', 'COMMON'),
        ('ME1', '019', 19, 'Vulpix', 'POKEMON', 'COMMON'),
        ('ME1', '020', 20, 'Ninetales', 'POKEMON', 'UNCOMMON'),
        ('ME1', '021', 21, 'Numel', 'POKEMON', 'COMMON'),
        ('ME1', '022', 22, 'Mega Camerupt ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '023', 23, 'Litleo', 'POKEMON', 'COMMON'),
        ('ME1', '024', 24, 'Pyroar', 'POKEMON', 'UNCOMMON'),
        ('ME1', '025', 25, 'Volcanion', 'POKEMON', 'UNCOMMON'),
        ('ME1', '026', 26, 'Scorbunny', 'POKEMON', 'COMMON'),
        ('ME1', '027', 27, 'Raboot', 'POKEMON', 'COMMON'),
        ('ME1', '028', 28, 'Cinderace', 'POKEMON', 'RARE'),
        ('ME1', '029', 29, 'Sizzlipede', 'POKEMON', 'COMMON'),
        ('ME1', '030', 30, 'Centiskorch', 'POKEMON', 'UNCOMMON'),
        ('ME1', '031', 31, 'Chi-Yu', 'POKEMON', 'UNCOMMON'),
        ('ME1', '032', 32, 'Mantine', 'POKEMON', 'COMMON'),
        ('ME1', '033', 33, 'Corphish', 'POKEMON', 'COMMON'),
        ('ME1', '034', 34, 'Kyogre', 'POKEMON', 'RARE'),
        ('ME1', '035', 35, 'Snover', 'POKEMON', 'COMMON'),
        ('ME1', '036', 36, 'Mega Abomasnow ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '037', 37, 'Clauncher', 'POKEMON', 'COMMON'),
        ('ME1', '038', 38, 'Clawitzer', 'POKEMON', 'RARE'),
        ('ME1', '039', 39, 'Sobble', 'POKEMON', 'COMMON'),
        ('ME1', '040', 40, 'Drizzile', 'POKEMON', 'COMMON'),
        ('ME1', '041', 41, 'Inteleon', 'POKEMON', 'UNCOMMON'),
        ('ME1', '042', 42, 'Snom', 'POKEMON', 'COMMON'),
        ('ME1', '043', 43, 'Frosmoth', 'POKEMON', 'UNCOMMON'),
        ('ME1', '044', 44, 'Eiscue', 'POKEMON', 'COMMON'),
        ('ME1', '045', 45, 'Magnemite', 'POKEMON', 'COMMON'),
        ('ME1', '046', 46, 'Magneton', 'POKEMON', 'COMMON'),
        ('ME1', '047', 47, 'Magnezone', 'POKEMON', 'UNCOMMON'),
        ('ME1', '048', 48, 'Raikou', 'POKEMON', 'RARE'),
        ('ME1', '049', 49, 'Electrike', 'POKEMON', 'COMMON'),
        ('ME1', '050', 50, 'Mega Manectric ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '051', 51, 'Pachirisu', 'POKEMON', 'COMMON'),
        ('ME1', '052', 52, 'Helioptile', 'POKEMON', 'COMMON'),
        ('ME1', '053', 53, 'Heliolisk', 'POKEMON', 'UNCOMMON'),
        ('ME1', '054', 54, 'Abra', 'POKEMON', 'COMMON'),
        ('ME1', '055', 55, 'Kadabra', 'POKEMON', 'UNCOMMON'),
        ('ME1', '056', 56, 'Alakazam', 'POKEMON', 'RARE'),
        ('ME1', '057', 57, 'Jynx', 'POKEMON', 'COMMON'),
        ('ME1', '058', 58, 'Ralts', 'POKEMON', 'COMMON'),
        ('ME1', '059', 59, 'Kirlia', 'POKEMON', 'COMMON'),
        ('ME1', '060', 60, 'Mega Gardevoir ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '061', 61, 'Shedinja', 'POKEMON', 'UNCOMMON'),
        ('ME1', '062', 62, 'Spoink', 'POKEMON', 'COMMON'),
        ('ME1', '063', 63, 'Grumpig', 'POKEMON', 'UNCOMMON'),
        ('ME1', '064', 64, 'Xerneas', 'POKEMON', 'RARE'),
        ('ME1', '065', 65, 'Greavard', 'POKEMON', 'COMMON'),
        ('ME1', '066', 66, 'Houndstone', 'POKEMON', 'UNCOMMON'),
        ('ME1', '067', 67, 'Gimmighoul', 'POKEMON', 'COMMON'),
        ('ME1', '068', 68, 'Sandshrew', 'POKEMON', 'COMMON'),
        ('ME1', '069', 69, 'Sandslash', 'POKEMON', 'COMMON'),
        ('ME1', '070', 70, 'Onix', 'POKEMON', 'COMMON'),
        ('ME1', '071', 71, 'Tyrogue', 'POKEMON', 'UNCOMMON'),
        ('ME1', '072', 72, 'Makuhita', 'POKEMON', 'COMMON'),
        ('ME1', '073', 73, 'Hariyama', 'POKEMON', 'RARE'),
        ('ME1', '074', 74, 'Lunatone', 'POKEMON', 'UNCOMMON'),
        ('ME1', '075', 75, 'Solrock', 'POKEMON', 'UNCOMMON'),
        ('ME1', '076', 76, 'Riolu', 'POKEMON', 'COMMON'),
        ('ME1', '077', 77, 'Mega Lucario ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '078', 78, 'Croagunk', 'POKEMON', 'COMMON'),
        ('ME1', '079', 79, 'Toxicroak', 'POKEMON', 'UNCOMMON'),
        ('ME1', '080', 80, 'Marshadow', 'POKEMON', 'UNCOMMON'),
        ('ME1', '081', 81, 'Stonjourner', 'POKEMON', 'UNCOMMON'),
        ('ME1', '082', 82, 'Nacli', 'POKEMON', 'COMMON'),
        ('ME1', '083', 83, 'Naclstack', 'POKEMON', 'COMMON'),
        ('ME1', '084', 84, 'Garganacl', 'POKEMON', 'UNCOMMON'),
        ('ME1', '085', 85, 'Crawdaunt', 'POKEMON', 'UNCOMMON'),
        ('ME1', '086', 86, 'Mega Absol ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '087', 87, 'Spiritomb', 'POKEMON', 'UNCOMMON'),
        ('ME1', '088', 88, 'Yveltal', 'POKEMON', 'RARE'),
        ('ME1', '089', 89, 'Nickit', 'POKEMON', 'COMMON'),
        ('ME1', '090', 90, 'Thievul', 'POKEMON', 'COMMON'),
        ('ME1', '091', 91, 'Shroodle', 'POKEMON', 'COMMON'),
        ('ME1', '092', 92, 'Grafaiai', 'POKEMON', 'UNCOMMON'),
        ('ME1', '093', 93, 'Steelix', 'POKEMON', 'RARE'),
        ('ME1', '094', 94, 'Mega Mawile ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '095', 95, 'Dialga', 'POKEMON', 'RARE'),
        ('ME1', '096', 96, 'Tinkatink', 'POKEMON', 'COMMON'),
        ('ME1', '097', 97, 'Tinkatuff', 'POKEMON', 'COMMON'),
        ('ME1', '098', 98, 'Tinkaton', 'POKEMON', 'UNCOMMON'),
        ('ME1', '099', 99, 'Gholdengo', 'POKEMON', 'UNCOMMON'),
        ('ME1', '100', 100, 'Mega Latias ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '101', 101, 'Latios', 'POKEMON', 'UNCOMMON'),
        ('ME1', '102', 102, 'Spearow', 'POKEMON', 'COMMON'),
        ('ME1', '103', 103, 'Fearow', 'POKEMON', 'COMMON'),
        ('ME1', '104', 104, 'Mega Kangaskhan ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME1', '105', 105, 'Delibird', 'POKEMON', 'COMMON'),
        ('ME1', '106', 106, 'Miltank', 'POKEMON', 'COMMON'),
        ('ME1', '107', 107, 'Buneary', 'POKEMON', 'COMMON'),
        ('ME1', '108', 108, 'Lopunny', 'POKEMON', 'COMMON'),
        ('ME1', '109', 109, 'Yungoos', 'POKEMON', 'COMMON'),
        ('ME1', '110', 110, 'Gumshoos', 'POKEMON', 'UNCOMMON'),
        ('ME1', '111', 111, 'Stufful', 'POKEMON', 'COMMON'),
        ('ME1', '112', 112, 'Bewear', 'POKEMON', 'COMMON'),
        ('ME1', '113', 113, 'Traquinagem da Acerola', 'TRAINER', 'UNCOMMON'),
        ('ME1', '114', 114, 'Ordem da Chefia (Ghetsis)', 'TRAINER', 'UNCOMMON'),
        ('ME1', '115', 115, 'Substituição de Energia', 'TRAINER', 'COMMON'),
        ('ME1', '116', 116, 'Gongo de Luta', 'TRAINER', 'UNCOMMON'),
        ('ME1', '117', 117, 'Floresta da Vitalidade', 'TRAINER', 'UNCOMMON'),
        ('ME1', '118', 118, 'Defensor Férreo', 'TRAINER', 'UNCOMMON'),
        ('ME1', '119', 119, 'Determinação da Lílian', 'TRAINER', 'UNCOMMON'),
        ('ME1', '120', 120, 'Barganha do Ten. Surge', 'TRAINER', 'UNCOMMON'),
        ('ME1', '121', 121, 'Megassinal', 'TRAINER', 'UNCOMMON'),
        ('ME1', '122', 122, 'Jardim Misterioso', 'TRAINER', 'UNCOMMON'),
        ('ME1', '123', 123, 'Dama do Centro Pokémon', 'TRAINER', 'COMMON'),
        ('ME1', '124', 124, 'Suplemento Premium Pro', 'TRAINER', 'UNCOMMON'),
        ('ME1', '125', 125, 'Doce Raro', 'TRAINER', 'COMMON'),
        ('ME1', '126', 126, 'Repelente', 'TRAINER', 'UNCOMMON'),
        ('ME1', '127', 127, 'Ruínas Arriscadas', 'TRAINER', 'UNCOMMON'),
        ('ME1', '128', 128, 'Relógio Insólito', 'TRAINER', 'UNCOMMON'),
        ('ME1', '129', 129, 'Praia de Surfista', 'TRAINER', 'UNCOMMON'),
        ('ME1', '130', 130, 'Substituição', 'TRAINER', 'COMMON'),
        ('ME1', '131', 131, 'Ultra Bola', 'TRAINER', 'COMMON'),
        ('ME1', '132', 132, 'Compaixão do Wally', 'TRAINER', 'UNCOMMON'),
        ('ME1', '133', 133, 'Bulbasaur', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '134', 134, 'Ivysaur', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '135', 135, 'Exeggutor', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '136', 136, 'Shuckle', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '137', 137, 'Ninjask', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '138', 138, 'Vulpix', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '139', 139, 'Litleo', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '140', 140, 'Snover', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '141', 141, 'Clawitzer', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '142', 142, 'Inteleon', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '143', 143, 'Helioptile', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '144', 144, 'Shedinja', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '145', 145, 'Houndstone', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '146', 146, 'Marshadow', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '147', 147, 'Garganacl', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '148', 148, 'Spiritomb', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '149', 149, 'Shroodle', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '150', 150, 'Steelix', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '151', 151, 'Spearow', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '152', 152, 'Delibird', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '153', 153, 'Gumshoos', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '154', 154, 'Stufful', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME1', '155', 155, 'Mega Venusaur ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '156', 156, 'Mega Camerupt ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '157', 157, 'Mega Abomasnow ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '158', 158, 'Mega Manectric ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '159', 159, 'Mega Gardevoir ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '160', 160, 'Mega Lucario ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '161', 161, 'Mega Absol ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '162', 162, 'Mega Mawile ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '163', 163, 'Mega Latias ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '164', 164, 'Mega Kangaskhan ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME1', '165', 165, 'Traquinagem da Acerola', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '166', 166, 'Balão de Ar', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '167', 167, 'Poffin de Colega', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '168', 168, 'Gongo de Luta', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '169', 169, 'Determinação da Lílian', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '170', 170, 'Barganha do Ten. Surge', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '171', 171, 'Megassinal', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '172', 172, 'Jardim Misterioso', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '173', 173, 'Maca Noturna', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '174', 174, 'Suplemento Premium Pro', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '175', 175, 'Doce Raro', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '176', 176, 'Compaixão do Wally', 'TRAINER', 'ULTRA_RARE'),
        ('ME1', '177', 177, 'Mega Venusaur ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '178', 178, 'Mega Gardevoir ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '179', 179, 'Mega Lucario ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '180', 180, 'Mega Absol ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '181', 181, 'Mega Latias ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '182', 182, 'Mega Kangaskhan ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '183', 183, 'Traquinagem da Acerola', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '184', 184, 'Determinação da Lílian', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '185', 185, 'Barganha do Ten. Surge', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '186', 186, 'Compaixão do Wally', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME1', '187', 187, 'Mega Gardevoir ex', 'POKEMON', 'MEGA_HYPER_RARE'),
        ('ME1', '188', 188, 'Mega Lucario ex', 'POKEMON', 'MEGA_HYPER_RARE'),
        ('ME2', '001', 1, 'Oddish', 'POKEMON', 'COMMON'),
        ('ME2', '002', 2, 'Gloom', 'POKEMON', 'COMMON'),
        ('ME2', '003', 3, 'Vileplume', 'POKEMON', 'RARE'),
        ('ME2', '004', 4, 'Mega Heracross ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '005', 5, 'Lotad', 'POKEMON', 'COMMON'),
        ('ME2', '006', 6, 'Lombre', 'POKEMON', 'COMMON'),
        ('ME2', '007', 7, 'Ludicolo', 'POKEMON', 'UNCOMMON'),
        ('ME2', '008', 8, 'Genesect', 'POKEMON', 'RARE'),
        ('ME2', '009', 9, 'Nymble', 'POKEMON', 'COMMON'),
        ('ME2', '010', 10, 'Lokix', 'POKEMON', 'UNCOMMON'),
        ('ME2', '011', 11, 'Charmander', 'POKEMON', 'COMMON'),
        ('ME2', '012', 12, 'Charmeleon', 'POKEMON', 'COMMON'),
        ('ME2', '013', 13, 'Mega Charizard X ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '014', 14, 'Moltres', 'POKEMON', 'RARE'),
        ('ME2', '015', 15, 'Darumaka', 'POKEMON', 'COMMON'),
        ('ME2', '016', 16, 'Darmanitan', 'POKEMON', 'UNCOMMON'),
        ('ME2', '017', 17, 'Reshiram', 'POKEMON', 'RARE'),
        ('ME2', '018', 18, 'Oricorio ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '019', 19, 'Charcadet', 'POKEMON', 'COMMON'),
        ('ME2', '020', 20, 'Ceruledge', 'POKEMON', 'UNCOMMON'),
        ('ME2', '021', 21, 'Seel', 'POKEMON', 'COMMON'),
        ('ME2', '022', 22, 'Dewgong', 'POKEMON', 'COMMON'),
        ('ME2', '023', 23, 'Swinub', 'POKEMON', 'COMMON'),
        ('ME2', '024', 24, 'Piloswine', 'POKEMON', 'COMMON'),
        ('ME2', '025', 25, 'Mamoswine', 'POKEMON', 'UNCOMMON'),
        ('ME2', '026', 26, 'Suicune', 'POKEMON', 'RARE'),
        ('ME2', '027', 27, 'Piplup', 'POKEMON', 'COMMON'),
        ('ME2', '028', 28, 'Prinplup', 'POKEMON', 'COMMON'),
        ('ME2', '029', 29, 'Rotom ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '030', 30, 'Yamper', 'POKEMON', 'COMMON'),
        ('ME2', '031', 31, 'Boltund', 'POKEMON', 'COMMON'),
        ('ME2', '032', 32, 'Pawmi', 'POKEMON', 'COMMON'),
        ('ME2', '033', 33, 'Pawmo', 'POKEMON', 'COMMON'),
        ('ME2', '034', 34, 'Pawmot', 'POKEMON', 'RARE'),
        ('ME2', '035', 35, 'Misdreavus', 'POKEMON', 'COMMON'),
        ('ME2', '036', 36, 'Mismagius ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '037', 37, 'Snubbull', 'POKEMON', 'COMMON'),
        ('ME2', '038', 38, 'Granbull', 'POKEMON', 'UNCOMMON'),
        ('ME2', '039', 39, 'Cresselia', 'POKEMON', 'UNCOMMON'),
        ('ME2', '040', 40, 'Meloetta', 'POKEMON', 'UNCOMMON'),
        ('ME2', '041', 41, 'Mega Diancie ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '042', 42, 'Mimikyu', 'POKEMON', 'COMMON'),
        ('ME2', '043', 43, 'Milcery', 'POKEMON', 'COMMON'),
        ('ME2', '044', 44, 'Alcremie', 'POKEMON', 'UNCOMMON'),
        ('ME2', '045', 45, 'Zacian', 'POKEMON', 'RARE'),
        ('ME2', '046', 46, 'Bramblin', 'POKEMON', 'COMMON'),
        ('ME2', '047', 47, 'Brambleghast', 'POKEMON', 'UNCOMMON'),
        ('ME2', '048', 48, 'Tauros de Paldea', 'POKEMON', 'UNCOMMON'),
        ('ME2', '049', 49, 'Gligar', 'POKEMON', 'COMMON'),
        ('ME2', '050', 50, 'Gliscor', 'POKEMON', 'UNCOMMON'),
        ('ME2', '051', 51, 'Trapinch', 'POKEMON', 'COMMON'),
        ('ME2', '052', 52, 'Vibrava', 'POKEMON', 'COMMON'),
        ('ME2', '053', 53, 'Flygon', 'POKEMON', 'RARE'),
        ('ME2', '054', 54, 'Gastly', 'POKEMON', 'COMMON'),
        ('ME2', '055', 55, 'Haunter', 'POKEMON', 'UNCOMMON'),
        ('ME2', '056', 56, 'Mega Gengar ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '057', 57, 'Murkrow', 'POKEMON', 'COMMON'),
        ('ME2', '058', 58, 'Honchkrow', 'POKEMON', 'UNCOMMON'),
        ('ME2', '059', 59, 'Sableye', 'POKEMON', 'COMMON'),
        ('ME2', '060', 60, 'Carvanha', 'POKEMON', 'COMMON'),
        ('ME2', '061', 61, 'Mega Sharpedo ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '062', 62, 'Seviper', 'POKEMON', 'UNCOMMON'),
        ('ME2', '063', 63, 'Absol', 'POKEMON', 'COMMON'),
        ('ME2', '064', 64, 'Sandile', 'POKEMON', 'COMMON'),
        ('ME2', '065', 65, 'Krokorok', 'POKEMON', 'COMMON'),
        ('ME2', '066', 66, 'Krookodile', 'POKEMON', 'UNCOMMON'),
        ('ME2', '067', 67, 'Toxel', 'POKEMON', 'COMMON'),
        ('ME2', '068', 68, 'Toxtricity', 'POKEMON', 'RARE'),
        ('ME2', '069', 69, 'Eternatus', 'POKEMON', 'UNCOMMON'),
        ('ME2', '070', 70, 'Empoleon ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '071', 71, 'Bronzor', 'POKEMON', 'COMMON'),
        ('ME2', '072', 72, 'Bronzong', 'POKEMON', 'UNCOMMON'),
        ('ME2', '073', 73, 'Togedemaru', 'POKEMON', 'COMMON'),
        ('ME2', '074', 74, 'Duraludon', 'POKEMON', 'COMMON'),
        ('ME2', '075', 75, 'Archaludon', 'POKEMON', 'UNCOMMON'),
        ('ME2', '076', 76, 'Jigglypuff', 'POKEMON', 'COMMON'),
        ('ME2', '077', 77, 'Wigglytuff', 'POKEMON', 'UNCOMMON'),
        ('ME2', '078', 78, 'Aipom', 'POKEMON', 'COMMON'),
        ('ME2', '079', 79, 'Ambipom', 'POKEMON', 'RARE'),
        ('ME2', '080', 80, 'Smeargle', 'POKEMON', 'COMMON'),
        ('ME2', '081', 81, 'Zigzagoon', 'POKEMON', 'COMMON'),
        ('ME2', '082', 82, 'Linoone', 'POKEMON', 'UNCOMMON'),
        ('ME2', '083', 83, 'Buneary', 'POKEMON', 'COMMON'),
        ('ME2', '084', 84, 'Mega Lopunny ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2', '085', 85, 'Jaula de Batalha', 'TRAINER', 'UNCOMMON'),
        ('ME2', '086', 86, 'Maçarico', 'TRAINER', 'UNCOMMON'),
        ('ME2', '087', 87, 'Dawn', 'TRAINER', 'UNCOMMON'),
        ('ME2', '088', 88, 'Vale Vertiginoso', 'TRAINER', 'UNCOMMON'),
        ('ME2', '089', 89, 'Cuspidor de Fogo', 'TRAINER', 'UNCOMMON'),
        ('ME2', '090', 90, 'Artimanha do Funesto', 'TRAINER', 'UNCOMMON'),
        ('ME2', '091', 91, 'Sorvetão Jumbo', 'TRAINER', 'UNCOMMON'),
        ('ME2', '092', 92, 'Capacete Punk', 'TRAINER', 'UNCOMMON'),
        ('ME2', '093', 93, 'Pingente Sagrado', 'TRAINER', 'UNCOMMON'),
        ('ME2', '094', 94, 'Fragmento Encantado', 'TRAINER', 'UNCOMMON'),
        ('ME2', '095', 95, 'Ludicolo', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '096', 96, 'Nymble', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '097', 97, 'Dewgong', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '098', 98, 'Piplup', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '099', 99, 'Yamper', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '100', 100, 'Zacian', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '101', 101, 'Flygon', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '102', 102, 'Wooper de Paldea', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '103', 103, 'Toxtricity', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '104', 104, 'Togedemaru', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '105', 105, 'Wigglytuff', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '106', 106, 'Meowth', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '107', 107, 'Ambipom', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2', '108', 108, 'Mega Heracross ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '109', 109, 'Mega Charizard X ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '110', 110, 'Oricorio ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '111', 111, 'Rotom ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '112', 112, 'Mismagius ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '113', 113, 'Mega Sharpedo ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '114', 114, 'Empoleon ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '115', 115, 'Mega Lopunny ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2', '116', 116, 'Jaula de Batalha', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '117', 117, 'Maçarico', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '118', 118, 'Dawn', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '119', 119, 'Cuspidor de Fogo', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '120', 120, 'Artimanha do Funesto', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '121', 121, 'Capacete Punk', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '122', 122, 'Pingente Sagrado', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '123', 123, 'Substituição', 'TRAINER', 'ULTRA_RARE'),
        ('ME2', '124', 124, 'Energia de Ignição', 'ENERGY', 'ULTRA_RARE'),
        ('ME2', '125', 125, 'Mega Charizard X ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2', '126', 126, 'Rotom ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2', '127', 127, 'Mega Sharpedo ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2', '128', 128, 'Mega Lopunny ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2', '129', 129, 'Dawn', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2', '130', 130, 'Mega Charizard X ex', 'POKEMON', 'MEGA_HYPER_RARE'),
        ('ME2.5', '001', 1, 'Oddish da Érica', 'POKEMON', 'COMMON'),
        ('ME2.5', '002', 2, 'Gloom da Érica', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '003', 3, 'Vileplume ex da Érica', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '004', 4, 'Bellsprout da Érica', 'POKEMON', 'COMMON'),
        ('ME2.5', '005', 5, 'Weepinbell da Érica', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '006', 6, 'Victreebel da Érica', 'POKEMON', 'RARE'),
        ('ME2.5', '007', 7, 'Tangela da Érica', 'POKEMON', 'COMMON'),
        ('ME2.5', '008', 8, 'Chikorita', 'POKEMON', 'COMMON'),
        ('ME2.5', '009', 9, 'Bayleef', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '010', 10, 'Mega Meganium ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '011', 11, 'Wurmple', 'POKEMON', 'COMMON'),
        ('ME2.5', '012', 12, 'Silcoon', 'POKEMON', 'COMMON'),
        ('ME2.5', '013', 13, 'Beautifly', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '014', 14, 'Cascoon', 'POKEMON', 'COMMON'),
        ('ME2.5', '015', 15, 'Dustox', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '016', 16, 'Budew', 'POKEMON', 'COMMON'),
        ('ME2.5', '017', 17, 'Grubbin', 'POKEMON', 'COMMON'),
        ('ME2.5', '018', 18, 'Tarountula da Equipe Rocket', 'POKEMON', 'COMMON'),
        ('ME2.5', '019', 19, 'Spidops da Equipe Rocket', 'POKEMON', 'RARE'),
        ('ME2.5', '020', 20, 'Charmander', 'POKEMON', 'COMMON'),
        ('ME2.5', '021', 21, 'Charmeleon', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '022', 22, 'Mega Charizard Y ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '023', 23, 'Slugma do Ethan', 'POKEMON', 'COMMON'),
        ('ME2.5', '024', 24, 'Magcargo do Ethan', 'POKEMON', 'RARE'),
        ('ME2.5', '025', 25, 'Entei', 'POKEMON', 'RARE'),
        ('ME2.5', '026', 26, 'Ho-Oh ex do Ethan', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '027', 27, 'Numel', 'POKEMON', 'COMMON'),
        ('ME2.5', '028', 28, 'Camerupt', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '029', 29, 'Tepig', 'POKEMON', 'COMMON'),
        ('ME2.5', '030', 30, 'Pignite', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '031', 31, 'Mega Emboar ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '032', 32, 'Darumaka do N', 'POKEMON', 'COMMON'),
        ('ME2.5', '033', 33, 'Darmanitan do N', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '034', 34, 'Salandit', 'POKEMON', 'COMMON'),
        ('ME2.5', '035', 35, 'Salazzle', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '036', 36, 'Scorbunny', 'POKEMON', 'COMMON'),
        ('ME2.5', '037', 37, 'Raboot', 'POKEMON', 'COMMON'),
        ('ME2.5', '038', 38, 'Cinderace ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '039', 39, 'Psyduck', 'POKEMON', 'COMMON'),
        ('ME2.5', '040', 40, 'Golduck', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '041', 41, 'Totodile', 'POKEMON', 'COMMON'),
        ('ME2.5', '042', 42, 'Croconaw', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '043', 43, 'Mega Feraligatr ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '044', 44, 'Sneasel', 'POKEMON', 'COMMON'),
        ('ME2.5', '045', 45, 'Weavile', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '046', 46, 'Snorunt', 'POKEMON', 'COMMON'),
        ('ME2.5', '047', 47, 'Mega Froslass ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '048', 48, 'Regice ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '049', 49, 'Vanillite do N', 'POKEMON', 'COMMON'),
        ('ME2.5', '050', 50, 'Vanillish do N', 'POKEMON', 'COMMON'),
        ('ME2.5', '051', 51, 'Vanilluxe do N', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '052', 52, 'Snom', 'POKEMON', 'COMMON'),
        ('ME2.5', '053', 53, 'Frosmoth', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '054', 54, 'Glastrier', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '055', 55, 'Pikachu', 'POKEMON', 'COMMON'),
        ('ME2.5', '056', 56, 'Raichu', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '057', 57, 'Pikachu ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '058', 58, 'Voltorb ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '059', 59, 'Tynamo', 'POKEMON', 'COMMON'),
        ('ME2.5', '060', 60, 'Eelektrik', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '061', 61, 'Mega Eelektross ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '062', 62, 'Stunfisk', 'POKEMON', 'COMMON'),
        ('ME2.5', '063', 63, 'Helioptile', 'POKEMON', 'COMMON'),
        ('ME2.5', '064', 64, 'Heliolisk', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '065', 65, 'Charjabug', 'POKEMON', 'COMMON'),
        ('ME2.5', '066', 66, 'Vikavolt', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '067', 67, 'Tapu Koko', 'POKEMON', 'RARE'),
        ('ME2.5', '068', 68, 'Pincurchin ex do Lupo', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '069', 69, 'Tadbulb da Kissera', 'POKEMON', 'COMMON'),
        ('ME2.5', '070', 70, 'Bellibolt ex da Kissera', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '071', 71, 'Wattrel da Kissera', 'POKEMON', 'COMMON'),
        ('ME2.5', '072', 72, 'Kilowattrel da Kissera', 'POKEMON', 'RARE'),
        ('ME2.5', '073', 73, 'Miraidon ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '074', 74, 'Clefairy', 'POKEMON', 'COMMON'),
        ('ME2.5', '075', 75, 'Clefable', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '076', 76, 'Clefairy ex da Lílian', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '077', 77, 'Exeggcute da Equipe Rocket', 'POKEMON', 'COMMON'),
        ('ME2.5', '078', 78, 'Exeggutor da Equipe Rocket', 'POKEMON', 'RARE'),
        ('ME2.5', '079', 79, 'Mewtwo ex da Equipe Rocket', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '080', 80, 'Togepi', 'POKEMON', 'COMMON'),
        ('ME2.5', '081', 81, 'Togetic', 'POKEMON', 'COMMON'),
        ('ME2.5', '082', 82, 'Togekiss', 'POKEMON', 'RARE'),
        ('ME2.5', '083', 83, 'Marill', 'POKEMON', 'COMMON'),
        ('ME2.5', '084', 84, 'Azumarill ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '085', 85, 'Misdreavus', 'POKEMON', 'COMMON'),
        ('ME2.5', '086', 86, 'Mismagius', 'POKEMON', 'RARE'),
        ('ME2.5', '087', 87, 'Ralts', 'POKEMON', 'COMMON'),
        ('ME2.5', '088', 88, 'Kirlia', 'POKEMON', 'COMMON'),
        ('ME2.5', '089', 89, 'Mega Gardevoir ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '090', 90, 'Shuppet', 'POKEMON', 'COMMON'),
        ('ME2.5', '091', 91, 'Banette', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '092', 92, 'Rotom', 'POKEMON', 'COMMON'),
        ('ME2.5', '093', 93, 'Swirlix', 'POKEMON', 'COMMON'),
        ('ME2.5', '094', 94, 'Slurpuff', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '095', 95, 'Phantump do Lupo', 'POKEMON', 'COMMON'),
        ('ME2.5', '096', 96, 'Trevenant do Lupo', 'POKEMON', 'RARE'),
        ('ME2.5', '097', 97, 'Mimikyu da Equipe Rocket', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '098', 98, 'Spectrier', 'POKEMON', 'RARE'),
        ('ME2.5', '099', 99, 'Munkidori', 'POKEMON', 'RARE'),
        ('ME2.5', '100', 100, 'Diglett da Equipe Rocket', 'POKEMON', 'COMMON'),
        ('ME2.5', '101', 101, 'Dugtrio da Equipe Rocket', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '102', 102, 'Hitmontop', 'POKEMON', 'COMMON'),
        ('ME2.5', '103', 103, 'Meditite', 'POKEMON', 'COMMON'),
        ('ME2.5', '104', 104, 'Medicham', 'POKEMON', 'COMMON'),
        ('ME2.5', '105', 105, 'Lunatone', 'POKEMON', 'RARE'),
        ('ME2.5', '106', 106, 'Solrock', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '107', 107, 'Regirock ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '108', 108, 'Groudon', 'POKEMON', 'RARE'),
        ('ME2.5', '109', 109, 'Gible da Cíntia', 'POKEMON', 'COMMON'),
        ('ME2.5', '110', 110, 'Gabite da Cíntia', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '111', 111, 'Garchomp ex da Cíntia', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '112', 112, 'Riolu', 'POKEMON', 'COMMON'),
        ('ME2.5', '113', 113, 'Mega Lucario ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '114', 114, 'Stunfisk ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '115', 115, 'Pancham', 'POKEMON', 'COMMON'),
        ('ME2.5', '116', 116, 'Mega Hawlucha ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '117', 117, 'Carbink', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '118', 118, 'Rolycoly', 'POKEMON', 'COMMON'),
        ('ME2.5', '119', 119, 'Carkol', 'POKEMON', 'COMMON'),
        ('ME2.5', '120', 120, 'Coalossal', 'POKEMON', 'RARE'),
        ('ME2.5', '121', 121, 'Koraidon ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '122', 122, 'Okidogi', 'POKEMON', 'RARE'),
        ('ME2.5', '123', 123, 'Gastly', 'POKEMON', 'COMMON'),
        ('ME2.5', '124', 124, 'Haunter', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '125', 125, 'Mega Gengar ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '126', 126, 'Murkrow da Equipe Rocket', 'POKEMON', 'COMMON'),
        ('ME2.5', '127', 127, 'Honchkrow da Equipe Rocket', 'POKEMON', 'RARE'),
        ('ME2.5', '128', 128, 'Poochyena', 'POKEMON', 'COMMON'),
        ('ME2.5', '129', 129, 'Mightyena', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '130', 130, 'Zigzagoon de Galar', 'POKEMON', 'COMMON'),
        ('ME2.5', '131', 131, 'Linoone de Galar', 'POKEMON', 'COMMON'),
        ('ME2.5', '132', 132, 'Obstagoon de Galar', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '133', 133, 'Spiritomb da Cíntia', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '134', 134, 'Scraggy', 'POKEMON', 'COMMON'),
        ('ME2.5', '135', 135, 'Mega Scrafty ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '136', 136, 'Zorua do N', 'POKEMON', 'COMMON'),
        ('ME2.5', '137', 137, 'Zoroark ex do N', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '138', 138, 'Vullaby', 'POKEMON', 'COMMON'),
        ('ME2.5', '139', 139, 'Mandibuzz ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '140', 140, 'Pangoro', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '141', 141, 'Hoopa', 'POKEMON', 'RARE'),
        ('ME2.5', '142', 142, 'Fezandipiti ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '143', 143, 'Pecharunt', 'POKEMON', 'RARE'),
        ('ME2.5', '144', 144, 'Mawile', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '145', 145, 'Registeel ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '146', 146, 'Pawniard', 'POKEMON', 'COMMON'),
        ('ME2.5', '147', 147, 'Bisharp', 'POKEMON', 'COMMON'),
        ('ME2.5', '148', 148, 'Kingambit', 'POKEMON', 'RARE'),
        ('ME2.5', '149', 149, 'Togedemaru ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '150', 150, 'Dratini', 'POKEMON', 'COMMON'),
        ('ME2.5', '151', 151, 'Dragonair', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '152', 152, 'Mega Dragonite ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '153', 153, 'Rayquaza', 'POKEMON', 'RARE'),
        ('ME2.5', '154', 154, 'Reshiram do N', 'POKEMON', 'RARE'),
        ('ME2.5', '155', 155, 'Zekrom do N', 'POKEMON', 'RARE'),
        ('ME2.5', '156', 156, 'Noibat', 'POKEMON', 'COMMON'),
        ('ME2.5', '157', 157, 'Noivern', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '158', 158, 'Dreepy', 'POKEMON', 'COMMON'),
        ('ME2.5', '159', 159, 'Drakloak', 'POKEMON', 'COMMON'),
        ('ME2.5', '160', 160, 'Dragapult ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '161', 161, 'Meowth da Equipe Rocket', 'POKEMON', 'COMMON'),
        ('ME2.5', '162', 162, 'Kangaskhan ex da Equipe Rocket', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '163', 163, 'Dunsparce do Lauro', 'POKEMON', 'COMMON'),
        ('ME2.5', '164', 164, 'Dudunsparce ex do Lauro', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '165', 165, 'Skitty', 'POKEMON', 'COMMON'),
        ('ME2.5', '166', 166, 'Delcatty', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '167', 167, 'Zangoose ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '168', 168, 'Starly do Lauro', 'POKEMON', 'COMMON'),
        ('ME2.5', '169', 169, 'Staravia do Lauro', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '170', 170, 'Staraptor do Lauro', 'POKEMON', 'RARE'),
        ('ME2.5', '171', 171, 'Rotom Ventilador', 'POKEMON', 'COMMON'),
        ('ME2.5', '172', 172, 'Mega Audino ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '173', 173, 'Rufflet do Lauro', 'POKEMON', 'COMMON'),
        ('ME2.5', '174', 174, 'Braviary do Lauro', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '175', 175, 'Komala do Lauro', 'POKEMON', 'COMMON'),
        ('ME2.5', '176', 176, 'Drampa', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '177', 177, 'Cramorant do Lupo', 'POKEMON', 'UNCOMMON'),
        ('ME2.5', '178', 178, 'Terapagos', 'POKEMON', 'RARE'),
        ('ME2.5', '179', 179, 'Terapagos ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME2.5', '180', 180, 'Traquinagem da Acerola', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '181', 181, 'Balão de Ar', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '182', 182, 'Amor e Paz', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '183', 183, 'Ordem da Chefia (Corbeau)', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '184', 184, 'Poffin de Colega', 'TRAINER', 'COMMON'),
        ('ME2.5', '185', 185, 'Canari', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '186', 186, 'Contra-ataque de Alcance', 'TRAINER', 'COMMON'),
        ('ME2.5', '187', 187, 'Gongo de Luta', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '188', 188, 'Floresta da Vitalidade', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '189', 189, 'Trompete de Vidro', 'TRAINER', 'COMMON'),
        ('ME2.5', '190', 190, 'Espírito de Luta da Iris', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '191', 191, 'Esfera de Luz', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '192', 192, 'Determinação da Lílian', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '193', 193, 'Megassinal', 'TRAINER', 'COMMON'),
        ('ME2.5', '194', 194, 'Jardim Misterioso', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '195', 195, 'PP Up do N', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '196', 196, 'Maca Noturna', 'TRAINER', 'COMMON'),
        ('ME2.5', '197', 197, 'Mina Noturna', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '198', 198, 'Poké Tablet', 'TRAINER', 'COMMON'),
        ('ME2.5', '199', 199, 'Suplemento Premium Pro', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '200', 200, 'Surfista', 'TRAINER', 'COMMON'),
        ('ME2.5', '201', 201, 'Apollo da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '202', 202, 'Athena da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '203', 203, 'Fábrica da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '204', 204, 'Giovanni da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '205', 205, 'Grande Bola da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '206', 206, 'Hipnotizador da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '207', 207, 'Petrel da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '208', 208, 'Próton da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '209', 209, 'Transmissor da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '210', 210, 'Torre de Vigia da Equipe Rocket', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '211', 211, 'Escama Espessa', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '212', 212, 'Sucateador de Ferramentas', 'TRAINER', 'COMMON'),
        ('ME2.5', '213', 213, 'Ultra Bola', 'TRAINER', 'COMMON'),
        ('ME2.5', '214', 214, 'Urbano', 'TRAINER', 'UNCOMMON'),
        ('ME2.5', '215', 215, 'Garçonete', 'TRAINER', 'COMMON'),
        ('ME2.5', '216', 216, 'Energia de Prisma', 'ENERGY', 'UNCOMMON'),
        ('ME2.5', '217', 217, 'Energia da Equipe Rocket', 'ENERGY', 'UNCOMMON'),
        ('ME2.5', '218', 218, 'Tangela da Érica', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '219', 219, 'Beautifly', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '220', 220, 'Dustox', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '221', 221, 'Budew', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '222', 222, 'Magcargo do Ethan', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '223', 223, 'Numel', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '224', 224, 'Salazzle', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '225', 225, 'Scorbunny', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '226', 226, 'Psyduck', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '227', 227, 'Snorunt', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '228', 228, 'Weavile', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '229', 229, 'Heliolisk', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '230', 230, 'Vikavolt', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '231', 231, 'Wattrel da Kissera', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '232', 232, 'Marill', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '233', 233, 'Misdreavus', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '234', 234, 'Banette', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '235', 235, 'Togekiss', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '236', 236, 'Slurpuff', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '237', 237, 'Trevenant do Lupo', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '238', 238, 'Mimikyu da Equipe Rocket', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '239', 239, 'Dugtrio da Equipe Rocket', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '240', 240, 'Hitmontop', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '241', 241, 'Medicham', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '242', 242, 'Carbink', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '243', 243, 'Mightyena', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '244', 244, 'Spiritomb da Cíntia', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '245', 245, 'Obstagoon de Galar', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '246', 246, 'Mawile', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '247', 247, 'Dreepy', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '248', 248, 'Drakloak', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '249', 249, 'Staraptor do Lauro', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '250', 250, 'Rotom Ventilador', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '251', 251, 'Sprigatito ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2.5', '252', 252, 'Stunfisk ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2.5', '253', 253, 'Mega Audino ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME2.5', '254', 254, 'Amor e Paz', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '255', 255, 'Treino de Faixa Preta', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '256', 256, 'Ordem da Chefia (Corbeau)', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '257', 257, 'Canari', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '258', 258, 'Cheren', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '259', 259, 'Contra-ataque de Alcance', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '260', 260, 'Trompete de Vidro', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '261', 261, 'Torre de Interferência', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '262', 262, 'PP Up do N', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '263', 263, 'Transmissor da Equipe Rocket', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '264', 264, 'Ultra Bola', 'TRAINER', 'ULTRA_RARE'),
        ('ME2.5', '265', 265, 'Mega Froslass ex', 'POKEMON', 'MEGA_ATTACK_RARE'),
        ('ME2.5', '266', 266, 'Mega Eelektross ex', 'POKEMON', 'MEGA_ATTACK_RARE'),
        ('ME2.5', '267', 267, 'Mega Diancie ex', 'POKEMON', 'MEGA_ATTACK_RARE'),
        ('ME2.5', '268', 268, 'Mega Hawlucha ex', 'POKEMON', 'MEGA_ATTACK_RARE'),
        ('ME2.5', '269', 269, 'Mega Gengar ex', 'POKEMON', 'MEGA_ATTACK_RARE'),
        ('ME2.5', '270', 270, 'Mega Scrafty ex', 'POKEMON', 'MEGA_ATTACK_RARE'),
        ('ME2.5', '271', 271, 'Mega Dragonite ex', 'POKEMON', 'MEGA_ATTACK_RARE'),
        ('ME2.5', '272', 272, 'Mega Meganium ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '273', 273, 'Mega Emboar ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '274', 274, 'Mega Feraligatr ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '275', 275, 'Mega Froslass ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '276', 276, 'Pikachu ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '277', 277, 'Pikachu ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '278', 278, 'Mega Eelektross ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '279', 279, 'Bellibolt ex da Kissera', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '280', 280, 'Clefairy ex da Lílian', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '281', 281, 'Mewtwo ex da Equipe Rocket', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '282', 282, 'Mega Diancie ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '283', 283, 'Mega Hawlucha ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '284', 284, 'Mega Gengar ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '285', 285, 'Mega Scrafty ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '286', 286, 'Zoroark ex do N', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '287', 287, 'Grimmsnarl ex da Marine', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME2.5', '288', 288, 'Fezandipiti ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '289', 289, 'Metagross ex do Steven', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '290', 290, 'Mega Dragonite ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '291', 291, 'Canari', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '292', 292, 'Espírito de Luta da Iris', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '293', 293, 'Surfista', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME2.5', '294', 294, 'Mega Charizard Y ex', 'POKEMON', 'MEGA_HYPER_RARE'),
        ('ME2.5', '295', 295, 'Mega Dragonite ex', 'POKEMON', 'MEGA_HYPER_RARE'),
        ('ME3', '001', 1, 'Spinarak', 'POKEMON', 'COMMON'),
        ('ME3', '002', 2, 'Ariados', 'POKEMON', 'COMMON'),
        ('ME3', '003', 3, 'Shaymin', 'POKEMON', 'UNCOMMON'),
        ('ME3', '004', 4, 'Snivy', 'POKEMON', 'COMMON'),
        ('ME3', '005', 5, 'Servine', 'POKEMON', 'COMMON'),
        ('ME3', '006', 6, 'Serperior', 'POKEMON', 'RARE'),
        ('ME3', '007', 7, 'Scatterbug', 'POKEMON', 'COMMON'),
        ('ME3', '008', 8, 'Spewpa', 'POKEMON', 'COMMON'),
        ('ME3', '009', 9, 'Vivillon', 'POKEMON', 'UNCOMMON'),
        ('ME3', '010', 10, 'Rowlet', 'POKEMON', 'COMMON'),
        ('ME3', '011', 11, 'Dartrix', 'POKEMON', 'COMMON'),
        ('ME3', '012', 12, 'Decidueye ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '013', 13, 'Fletchinder', 'POKEMON', 'COMMON'),
        ('ME3', '014', 14, 'Talonflame', 'POKEMON', 'UNCOMMON'),
        ('ME3', '015', 15, 'Salandit', 'POKEMON', 'COMMON'),
        ('ME3', '016', 16, 'Salazzle ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '017', 17, 'Turtonator', 'POKEMON', 'UNCOMMON'),
        ('ME3', '018', 18, 'Seel', 'POKEMON', 'COMMON'),
        ('ME3', '019', 19, 'Dewgong', 'POKEMON', 'RARE'),
        ('ME3', '020', 20, 'Staryu', 'POKEMON', 'COMMON'),
        ('ME3', '021', 21, 'Mega Starmie ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '022', 22, 'Lapras ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '023', 23, 'Amaura', 'POKEMON', 'COMMON'),
        ('ME3', '024', 24, 'Aurorus', 'POKEMON', 'RARE'),
        ('ME3', '025', 25, 'Volcanion', 'POKEMON', 'UNCOMMON'),
        ('ME3', '026', 26, 'Shinx', 'POKEMON', 'COMMON'),
        ('ME3', '027', 27, 'Luxio', 'POKEMON', 'UNCOMMON'),
        ('ME3', '028', 28, 'Luxray', 'POKEMON', 'RARE'),
        ('ME3', '029', 29, 'Dedenne', 'POKEMON', 'COMMON'),
        ('ME3', '030', 30, 'Clefairy', 'POKEMON', 'COMMON'),
        ('ME3', '031', 31, 'Mega Clefable ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '032', 32, 'Mawile', 'POKEMON', 'COMMON'),
        ('ME3', '033', 33, 'Espurr', 'POKEMON', 'COMMON'),
        ('ME3', '034', 34, 'Meowstic', 'POKEMON', 'UNCOMMON'),
        ('ME3', '035', 35, 'Spritzee', 'POKEMON', 'COMMON'),
        ('ME3', '036', 36, 'Aromatisse', 'POKEMON', 'UNCOMMON'),
        ('ME3', '037', 37, 'Nosepass', 'POKEMON', 'COMMON'),
        ('ME3', '038', 38, 'Probopass', 'POKEMON', 'COMMON'),
        ('ME3', '039', 39, 'Hippopotas', 'POKEMON', 'COMMON'),
        ('ME3', '040', 40, 'Hippowdon', 'POKEMON', 'UNCOMMON'),
        ('ME3', '041', 41, 'Landorus', 'POKEMON', 'RARE'),
        ('ME3', '042', 42, 'Binacle', 'POKEMON', 'COMMON'),
        ('ME3', '043', 43, 'Barbaracle', 'POKEMON', 'UNCOMMON'),
        ('ME3', '044', 44, 'Tyrunt', 'POKEMON', 'COMMON'),
        ('ME3', '045', 45, 'Tyrantrum', 'POKEMON', 'RARE'),
        ('ME3', '046', 46, 'Hawlucha', 'POKEMON', 'COMMON'),
        ('ME3', '047', 47, 'Mega Zygarde ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '048', 48, 'Gastly', 'POKEMON', 'COMMON'),
        ('ME3', '049', 49, 'Haunter', 'POKEMON', 'COMMON'),
        ('ME3', '050', 50, 'Gengar', 'POKEMON', 'RARE'),
        ('ME3', '051', 51, 'Skorupi', 'POKEMON', 'COMMON'),
        ('ME3', '052', 52, 'Drapion', 'POKEMON', 'UNCOMMON'),
        ('ME3', '053', 53, 'Yveltal ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '054', 54, 'Chien-Pao', 'POKEMON', 'RARE'),
        ('ME3', '055', 55, 'Mega Skarmory ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '056', 56, 'Honedge', 'POKEMON', 'COMMON'),
        ('ME3', '057', 57, 'Doublade', 'POKEMON', 'COMMON'),
        ('ME3', '058', 58, 'Aegislash', 'POKEMON', 'UNCOMMON'),
        ('ME3', '059', 59, 'Klefki', 'POKEMON', 'COMMON'),
        ('ME3', '060', 60, 'Rattata', 'POKEMON', 'COMMON'),
        ('ME3', '061', 61, 'Raticate', 'POKEMON', 'UNCOMMON'),
        ('ME3', '062', 62, 'Meowth ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME3', '063', 63, 'Snorlax', 'POKEMON', 'COMMON'),
        ('ME3', '064', 64, 'Bunnelby', 'POKEMON', 'COMMON'),
        ('ME3', '065', 65, 'Diggersby', 'POKEMON', 'UNCOMMON'),
        ('ME3', '066', 66, 'Fletchling', 'POKEMON', 'COMMON'),
        ('ME3', '067', 67, 'Furfrou', 'POKEMON', 'COMMON'),
        ('ME3', '068', 68, 'Fóssil de Mandíbula Arcaico', 'TRAINER', 'COMMON'),
        ('ME3', '069', 69, 'Fóssil de Vela Arcaico', 'TRAINER', 'COMMON'),
        ('ME3', '070', 70, 'Núcleo de Memória', 'TRAINER', 'UNCOMMON'),
        ('ME3', '071', 71, 'Martelo Esmagador', 'TRAINER', 'COMMON'),
        ('ME3', '072', 72, 'Busca de Energia', 'TRAINER', 'COMMON'),
        ('ME3', '073', 73, 'Mata-Energia', 'TRAINER', 'UNCOMMON'),
        ('ME3', '074', 74, 'Pá de Cavar', 'TRAINER', 'COMMON'),
        ('ME3', '075', 75, 'Jaci', 'TRAINER', 'UNCOMMON'),
        ('ME3', '076', 76, 'Juiz', 'TRAINER', 'UNCOMMON'),
        ('ME3', '077', 77, 'Cidade de Lumiose', 'TRAINER', 'UNCOMMON'),
        ('ME3', '078', 78, 'Crepe de Lumiose', 'TRAINER', 'UNCOMMON'),
        ('ME3', '079', 79, 'Naveen', 'TRAINER', 'UNCOMMON'),
        ('ME3', '080', 80, 'Poké Bola', 'TRAINER', 'COMMON'),
        ('ME3', '081', 81, 'Poké Tablet', 'TRAINER', 'UNCOMMON'),
        ('ME3', '082', 82, 'Pegador de Pokémon', 'TRAINER', 'COMMON'),
        ('ME3', '083', 83, 'Poção', 'TRAINER', 'COMMON'),
        ('ME3', '084', 84, 'Encorajamento da Rose', 'TRAINER', 'UNCOMMON'),
        ('ME3', '085', 85, 'Tarragon', 'TRAINER', 'UNCOMMON'),
        ('ME3', '086', 86, 'Energia Crescente', 'ENERGY', 'RARE'),
        ('ME3', '087', 87, 'Energia Rochosa', 'ENERGY', 'RARE'),
        ('ME3', '088', 88, 'Energia Telepática', 'ENERGY', 'RARE'),
        ('ME3', '089', 89, 'Spewpa', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '090', 90, 'Rowlet', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '091', 91, 'Talonflame', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '092', 92, 'Aurorus', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '093', 93, 'Dedenne', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '094', 94, 'Clefairy', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '095', 95, 'Espurr', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '096', 96, 'Probopass', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '097', 97, 'Drapion', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '098', 98, 'Doublade', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '099', 99, 'Raticate', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME3', '100', 100, 'Decidueye ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '101', 101, 'Salazzle ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '102', 102, 'Mega Starmie ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '103', 103, 'Mega Clefable ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '104', 104, 'Mega Zygarde ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '105', 105, 'Yveltal ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '106', 106, 'Mega Skarmory ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '107', 107, 'Meowth ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME3', '108', 108, 'Reciclador de Energia', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '109', 109, 'Floresta da Vitalidade', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '110', 110, 'Jaci', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '111', 111, 'Cidade de Lumiose', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '112', 112, 'Naveen', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '113', 113, 'Poké Tablet', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '114', 114, 'Encorajamento da Rose', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '115', 115, 'Cinza Sagrada', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '116', 116, 'Tarragon', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '117', 117, 'Fragmento Encantado', 'TRAINER', 'ULTRA_RARE'),
        ('ME3', '118', 118, 'Mega Starmie ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME3', '119', 119, 'Mega Clefable ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME3', '120', 120, 'Mega Zygarde ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME3', '121', 121, 'Meowth ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME3', '122', 122, 'Jaci', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME3', '123', 123, 'Encorajamento da Rose', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME3', '124', 124, 'Mega Zygarde ex', 'POKEMON', 'MEGA_HYPER_RARE'),
        ('ME4', '001', 1, 'Weedle', 'POKEMON', 'COMMON'),
        ('ME4', '002', 2, 'Kakuna', 'POKEMON', 'COMMON'),
        ('ME4', '003', 3, 'Beedrill ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '004', 4, 'Carnivine', 'POKEMON', 'COMMON'),
        ('ME4', '005', 5, 'Chespin', 'POKEMON', 'COMMON'),
        ('ME4', '006', 6, 'Quilladin', 'POKEMON', 'COMMON'),
        ('ME4', '007', 7, 'Chesnaught', 'POKEMON', 'RARE'),
        ('ME4', '008', 8, 'Vulpix', 'POKEMON', 'COMMON'),
        ('ME4', '009', 9, 'Ninetales', 'POKEMON', 'UNCOMMON'),
        ('ME4', '010', 10, 'Ho-Oh', 'POKEMON', 'RARE'),
        ('ME4', '011', 11, 'Fennekin', 'POKEMON', 'COMMON'),
        ('ME4', '012', 12, 'Braixen', 'POKEMON', 'COMMON'),
        ('ME4', '013', 13, 'Delphox', 'POKEMON', 'RARE'),
        ('ME4', '014', 14, 'Litleo', 'POKEMON', 'COMMON'),
        ('ME4', '015', 15, 'Mega Pyroar ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '016', 16, 'Remoraid', 'POKEMON', 'COMMON'),
        ('ME4', '017', 17, 'Octillery', 'POKEMON', 'COMMON'),
        ('ME4', '018', 18, 'Delibird', 'POKEMON', 'UNCOMMON'),
        ('ME4', '019', 19, 'Keldeo', 'POKEMON', 'RARE'),
        ('ME4', '020', 20, 'Froakie', 'POKEMON', 'COMMON'),
        ('ME4', '021', 21, 'Frogadier', 'POKEMON', 'COMMON'),
        ('ME4', '022', 22, 'Mega Greninja ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '023', 23, 'Bergmite', 'POKEMON', 'COMMON'),
        ('ME4', '024', 24, 'Avalugg', 'POKEMON', 'UNCOMMON'),
        ('ME4', '025', 25, 'Wimpod', 'POKEMON', 'COMMON'),
        ('ME4', '026', 26, 'Golisopod', 'POKEMON', 'UNCOMMON'),
        ('ME4', '027', 27, 'Mareep', 'POKEMON', 'COMMON'),
        ('ME4', '028', 28, 'Flaaffy', 'POKEMON', 'COMMON'),
        ('ME4', '029', 29, 'Ampharos', 'POKEMON', 'RARE'),
        ('ME4', '030', 30, 'Emolga', 'POKEMON', 'COMMON'),
        ('ME4', '031', 31, 'Deoxys', 'POKEMON', 'UNCOMMON'),
        ('ME4', '032', 32, 'Deoxys', 'POKEMON', 'UNCOMMON'),
        ('ME4', '033', 33, 'Deoxys', 'POKEMON', 'UNCOMMON'),
        ('ME4', '034', 34, 'Deoxys', 'POKEMON', 'UNCOMMON'),
        ('ME4', '035', 35, 'Mega Floette ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '036', 36, 'Espurr', 'POKEMON', 'COMMON'),
        ('ME4', '037', 37, 'Meowstic', 'POKEMON', 'UNCOMMON'),
        ('ME4', '038', 38, 'Phantump', 'POKEMON', 'COMMON'),
        ('ME4', '039', 39, 'Trevenant', 'POKEMON', 'RARE'),
        ('ME4', '040', 40, 'Pumpkaboo', 'POKEMON', 'COMMON'),
        ('ME4', '041', 41, 'Gourgeist ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '042', 42, 'Xerneas', 'POKEMON', 'RARE'),
        ('ME4', '043', 43, 'Sudowoodo', 'POKEMON', 'UNCOMMON'),
        ('ME4', '044', 44, 'Phanpy', 'POKEMON', 'COMMON'),
        ('ME4', '045', 45, 'Donphan', 'POKEMON', 'COMMON'),
        ('ME4', '046', 46, 'Baltoy', 'POKEMON', 'COMMON'),
        ('ME4', '047', 47, 'Claydol', 'POKEMON', 'UNCOMMON'),
        ('ME4', '048', 48, 'Mega Gallade ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '049', 49, 'Zubat', 'POKEMON', 'COMMON'),
        ('ME4', '050', 50, 'Golbat', 'POKEMON', 'COMMON'),
        ('ME4', '051', 51, 'Crobat', 'POKEMON', 'RARE'),
        ('ME4', '052', 52, 'Qwilfish', 'POKEMON', 'COMMON'),
        ('ME4', '053', 53, 'Stunky', 'POKEMON', 'COMMON'),
        ('ME4', '054', 54, 'Skuntank', 'POKEMON', 'UNCOMMON'),
        ('ME4', '055', 55, 'Krookodile ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '056', 56, 'Trubbish', 'POKEMON', 'COMMON'),
        ('ME4', '057', 57, 'Garbodor', 'POKEMON', 'UNCOMMON'),
        ('ME4', '058', 58, 'Skrelp', 'POKEMON', 'COMMON'),
        ('ME4', '059', 59, 'Beldum', 'POKEMON', 'COMMON'),
        ('ME4', '060', 60, 'Metang', 'POKEMON', 'COMMON'),
        ('ME4', '061', 61, 'Metagross', 'POKEMON', 'UNCOMMON'),
        ('ME4', '062', 62, 'Ferroseed', 'POKEMON', 'COMMON'),
        ('ME4', '063', 63, 'Ferrothorn', 'POKEMON', 'UNCOMMON'),
        ('ME4', '064', 64, 'Cobalion ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '065', 65, 'Mega Dragalge ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '066', 66, 'Goomy', 'POKEMON', 'COMMON'),
        ('ME4', '067', 67, 'Sliggoo', 'POKEMON', 'COMMON'),
        ('ME4', '068', 68, 'Goodra', 'POKEMON', 'RARE'),
        ('ME4', '069', 69, 'Tauros', 'POKEMON', 'UNCOMMON'),
        ('ME4', '070', 70, 'Patrat', 'POKEMON', 'COMMON'),
        ('ME4', '071', 71, 'Watchog', 'POKEMON', 'COMMON'),
        ('ME4', '072', 72, 'Minccino', 'POKEMON', 'COMMON'),
        ('ME4', '073', 73, 'Cinccino ex', 'POKEMON', 'DOUBLE_RARE'),
        ('ME4', '074', 74, 'Apólice de Adversidade', 'TRAINER', 'UNCOMMON'),
        ('ME4', '075', 75, 'Floette Ange', 'TRAINER', 'UNCOMMON'),
        ('ME4', '076', 76, 'Tranquilidade do AZ', 'TRAINER', 'UNCOMMON'),
        ('ME4', '077', 77, 'Emma', 'TRAINER', 'UNCOMMON'),
        ('ME4', '078', 78, 'Rede Grande de Arrasto', 'TRAINER', 'UNCOMMON'),
        ('ME4', '079', 79, 'Philippe', 'TRAINER', 'UNCOMMON'),
        ('ME4', '080', 80, 'Torre Prisma', 'TRAINER', 'UNCOMMON'),
        ('ME4', '081', 81, 'Show da Roxie', 'TRAINER', 'UNCOMMON'),
        ('ME4', '082', 82, 'Cartão Vermelho Especial', 'TRAINER', 'UNCOMMON'),
        ('ME4', '083', 83, 'Tomo da Transformação', 'TRAINER', 'UNCOMMON'),
        ('ME4', '084', 84, 'Energia Borbulhante', 'ENERGY', 'RARE'),
        ('ME4', '085', 85, 'Energia Magnética', 'ENERGY', 'RARE'),
        ('ME4', '086', 86, 'Energia Nitro', 'ENERGY', 'RARE'),
        ('ME4', '087', 87, 'Chespin', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '088', 88, 'Froakie', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '089', 89, 'Frogadier', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '090', 90, 'Ampharos', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '091', 91, 'Xerneas', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '092', 92, 'Claydol', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '093', 93, 'Crobat', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '094', 94, 'Metang', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '095', 95, 'Sliggoo', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '096', 96, 'Tauros', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '097', 97, 'Watchog', 'POKEMON', 'ILLUSTRATION_RARE'),
        ('ME4', '098', 98, 'Beedrill ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '099', 99, 'Mega Pyroar ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '100', 100, 'Mega Greninja ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '101', 101, 'Mega Floette ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '102', 102, 'Gourgeist ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '103', 103, 'Cobalion ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '104', 104, 'Mega Dragalge ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '105', 105, 'Cinccino ex', 'POKEMON', 'ULTRA_RARE'),
        ('ME4', '106', 106, 'Tranquilidade do AZ', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '107', 107, 'Emma', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '108', 108, 'Recuperação de Energia', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '109', 109, 'Sorvetão Jumbo', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '110', 110, 'Philippe', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '111', 111, 'Torre Prisma', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '112', 112, 'Show da Roxie', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '113', 113, 'Cartão Vermelho Especial', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '114', 114, 'Praia de Surfista', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '115', 115, 'Sucateador de Ferramentas', 'TRAINER', 'ULTRA_RARE'),
        ('ME4', '116', 116, 'Mega Greninja ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME4', '117', 117, 'Mega Floette ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME4', '118', 118, 'Mega Dragalge ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME4', '119', 119, 'Cinccino ex', 'POKEMON', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME4', '120', 120, 'Tranquilidade do AZ', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME4', '121', 121, 'Show da Roxie', 'TRAINER', 'SPECIAL_ILLUSTRATION_RARE'),
        ('ME4', '122', 122, 'Mega Greninja ex', 'POKEMON', 'MEGA_HYPER_RARE')
),
target_set AS (
    SELECT
        cs.id AS card_set_id,
        cs.code AS card_set_code,
        cs.base_set_size AS collector_total,
        e.game_id
    FROM public.card_set AS cs
    INNER JOIN public.expansion AS e
        ON e.id = cs.expansion_id
    INNER JOIN public.game AS g
        ON g.id = e.game_id
    WHERE g.code = 'POKEMON'
      AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
)
INSERT INTO public.card (
    card_set_id,
    rarity_id,
    category_id,
    collector_number,
    collector_total,
    collector_order,
    name
)
SELECT
    ts.card_set_id,
    r.id,
    cc.id,
    sc.collector_number,
    ts.collector_total,
    sc.collector_order,
    sc.name
FROM source_card AS sc
INNER JOIN target_set AS ts
    ON ts.card_set_code = sc.card_set_code
INNER JOIN public.rarity AS r
    ON r.game_id = ts.game_id
   AND r.code = sc.rarity_code
INNER JOIN public.card_category AS cc
    ON cc.game_id = ts.game_id
   AND cc.code = sc.category_code
ON CONFLICT (card_set_id, collector_number)
DO UPDATE SET
    rarity_id = EXCLUDED.rarity_id,
    category_id = EXCLUDED.category_id,
    collector_total = EXCLUDED.collector_total,
    collector_order = EXCLUDED.collector_order,
    name = EXCLUDED.name;


-- ============================================================================
-- 3. Validar a quantidade final de cada Card Set e o total consolidado
-- ============================================================================

DO $$
DECLARE
    v_invalid_counts TEXT;
    v_total_registered INTEGER;
BEGIN
    WITH expected_set (
        code,
        expected_total
    ) AS (
        VALUES
            ('ME1',   188),
            ('ME2',   130),
            ('ME2.5', 295),
            ('ME3',   124),
            ('ME4',   122)
    ),
    registered AS (
        SELECT
            cs.code,
            COUNT(c.id)::INTEGER AS registered_total
        FROM public.card_set AS cs
        INNER JOIN public.expansion AS e
            ON e.id = cs.expansion_id
        INNER JOIN public.game AS g
            ON g.id = e.game_id
        LEFT JOIN public.card AS c
            ON c.card_set_id = cs.id
        WHERE g.code = 'POKEMON'
          AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4')
        GROUP BY cs.code
    )
    SELECT string_agg(
               format(
                   '%s [cadastrado=%s; esperado=%s]',
                   es.code,
                   COALESCE(r.registered_total, 0),
                   es.expected_total
               ),
               ', '
               ORDER BY es.code
           )
      INTO v_invalid_counts
      FROM expected_set AS es
      LEFT JOIN registered AS r
        ON r.code = es.code
     WHERE COALESCE(r.registered_total, 0) <> es.expected_total;

    IF v_invalid_counts IS NOT NULL THEN
        RAISE EXCEPTION
            'A Query 840 foi interrompida: quantidades divergentes por Card Set: %.',
            v_invalid_counts;
    END IF;

    SELECT COUNT(*)::INTEGER
      INTO v_total_registered
      FROM public.card AS c
      INNER JOIN public.card_set AS cs
          ON cs.id = c.card_set_id
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
      INNER JOIN public.game AS g
          ON g.id = e.game_id
     WHERE g.code = 'POKEMON'
       AND cs.code IN ('ME1', 'ME2', 'ME2.5', 'ME3', 'ME4');

    IF v_total_registered <> 859 THEN
        RAISE EXCEPTION
            'A Query 840 foi interrompida: o catálogo consolidado possui % Cards, mas deveria possuir exatamente 859.',
            v_total_registered;
    END IF;
END;
$$;

COMMIT;
