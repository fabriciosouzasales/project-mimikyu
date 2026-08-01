/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 830 - Seed Rarity
Versão......: 1.3
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18 (v1.0-1.2) / 2026-08-01 (v1.3)
Descrição resumida:
Cadastra e atualiza as raridades e seus símbolos oficiais identificados nas
listas de verificação dos Sets da expansão Megaevolução e no Set Promocional.
Descrição:
Insere na tabela rarity as classificações de raridade oficialmente utilizadas
pelos Sets atualmente cadastrados no catálogo do Pokémon TCG.
O campo symbol_code identifica a representação visual oficial da raridade,
sem armazenar arquivos de imagem, URLs, SVGs ou componentes visuais.
Raridades cadastradas:
- Comum
- Incomum
- Rara
- Promo
- Rara Dupla
- Rara Ultra
- Rara Mega Ataque
- Ilustração Rara
- Ilustração Rara Especial
- Mega Rara Hiper
- Hiper Rara (v1.3)
Nota de versão (v1.3, 2026-08-01):
Gap real descoberto na importação TCGdex de SV1 (Escarlate e Violeta) —
6 cartas (2 `ex`, 2 Treinador, 2 Energia Básica) vêm da TCGdex com raridade
"Hiper Rara", distinta de "Mega Rara Hiper" (exclusiva da Megaevolução) e
sem cadastro correspondente; a falta de rarity_id bloqueava a persistência
dessas 6 linhas em admin_confirm_catalog_import ("Não foi possível
identificar o Game da Rarity informada"). symbol_code reaproveita
`GOLD_STAR` (mesmo de Ilustração Rara) como escolha provisória — sinalizada
a Fabrício, não uma fonte oficial de símbolo confirmada, mesmo espírito da
divergência já registrada para Ilustração Rara (ver comentário de
RaritySymbol no frontend). display_order = 11 (acrescentada ao final, sem
reordenar as demais) — ajustar se a posição na hierarquia importar
visualmente.
Regras de Negócio:
- Somente raridades comprovadas por fontes oficiais são cadastradas.
- A raridade deve pertencer ao Game POKEMON.
- O código representa a identificação técnica e estável da raridade.
- O nome preserva a nomenclatura oficial ou principal em português.
- O symbol_code preserva a classificação visual oficial da raridade.
- A raridade PROMO utiliza o símbolo BLACK_STAR.
- RARE e PROMO podem compartilhar o mesmo símbolo visual.
- A ordem de exibição organiza as raridades em uma sequência lógica.
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
        symbol_code,
        display_order
    )
    VALUES
        (
            v_game_id,
            'COMMON',
            'Comum',
            'BLACK_CIRCLE',
            1
        ),
        (
            v_game_id,
            'UNCOMMON',
            'Incomum',
            'BLACK_DIAMOND',
            2
        ),
        (
            v_game_id,
            'RARE',
            'Rara',
            'BLACK_STAR',
            3
        ),
        (
            v_game_id,
            'PROMO',
            'Promo',
            'BLACK_STAR',
            4
        ),
        (
            v_game_id,
            'DOUBLE_RARE',
            'Rara Dupla',
            'BLACK_DOUBLE_STAR',
            5
        ),
        (
            v_game_id,
            'ULTRA_RARE',
            'Rara Ultra',
            'SILVER_DOUBLE_STAR',
            6
        ),
        (
            v_game_id,
            'MEGA_ATTACK_RARE',
            'Rara Mega Ataque',
            'MEGA_ATTACK',
            7
        ),
        (
            v_game_id,
            'ILLUSTRATION_RARE',
            'Ilustração Rara',
            'GOLD_STAR',
            8
        ),
        (
            v_game_id,
            'SPECIAL_ILLUSTRATION_RARE',
            'Ilustração Rara Especial',
            'GOLD_DOUBLE_STAR',
            9
        ),
        (
            v_game_id,
            'MEGA_HYPER_RARE',
            'Mega Rara Hiper',
            'GOLD_DIAMOND',
            10
        ),
        (
            v_game_id,
            'HYPER_RARE',
            'Hiper Rara',
            'GOLD_STAR',
            11
        )
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        symbol_code = EXCLUDED.symbol_code,
        display_order = EXCLUDED.display_order;
END;
$$;
