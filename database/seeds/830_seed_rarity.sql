/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 830 - Seed Rarity
Versão......: 1.6
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18 (v1.0-1.2) / 2026-08-01 (v1.3) /
              2026-08-02 (v1.4-v1.5) / 2026-08-06 (v1.6)

Descrição resumida:
Cadastra e atualiza as raridades e seus símbolos oficiais identificados nas
listas de verificação dos Card Sets e nas fontes externas de catálogo.

Descrição:
Insere na tabela rarity as classificações de raridade oficialmente utilizadas
pelos Card Sets atualmente cadastrados no catálogo do Pokémon TCG.

O campo symbol_code identifica a representação visual da raridade, sem
armazenar arquivos de imagem, URLs, SVGs ou componentes visuais.

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
- Hiper Rara
- ACE SPEC Rara (v1.4)
- Shiny Rara (v1.4)
- Shiny Ultra Rara (v1.4)
- Rara Preto e Branco (v1.6)

Nota de versão (v1.6, 2026-08-06):
Gap real encontrado na revisão de importação (raw "Rara Preto e Branco",
RARIDADE_NAO_MAPEADA), cartas Victini (171/86) e Zekrom ex (172/86).
Código técnico definido: BLACK_WHITE_RARE. Símbolo oficial informado por
Fabrício (legenda "★☆ = Rara Preto e Branco"): uma estrela preenchida +
uma estrela vazada — código novo e dedicado, BLACK_WHITE_STAR (nenhum
symbol_code existente representa preenchimento parcial).

Nota de versão (v1.5, 2026-08-02):
Fabrício sinalizou, com referência visual oficial (print de carta real +
legenda "★★★ = Rara Hiper"), que o símbolo de HYPER_RARE está incorreto:
aparece hoje com uma única estrela dourada (symbol_code GOLD_STAR,
compartilhado com ILLUSTRATION_RARE desde a v1.0/v1.1), quando deveria
aparecer com três estrelas douradas.

symbol_code de HYPER_RARE alterado de GOLD_STAR para GOLD_TRIPLE_STAR (novo
código, dedicado — não reaproveita GOLD_STAR, que continua sendo o símbolo de
ILLUSTRATION_RARE, uma estrela só). Sem esta separação, qualquer ajuste na
contagem de estrelas de HYPER_RARE afetaria também ILLUSTRATION_RARE por
engano.

Nota de versão (v1.4, 2026-08-02):
Durante a revisão das cartas importadas via TCGdex, foram identificadas três
raridades ainda não cadastradas no catálogo:

- "ACE SPEC Rare"
- "Shiny rare"
- "Shiny ultra rare"

A ausência dessas raridades produz RARIDADE_NAO_MAPEADA no staging e impede
a confirmação das respectivas linhas.

Foram definidos os códigos técnicos estáveis:
- ACE_SPEC_RARE
- SHINY_RARE
- SHINY_ULTRA_RARE

Símbolos oficiais confirmados por Fabrício (referência visual oficial, não
reaproveitam nenhum symbol_code já cadastrado): "Rara ACE SPEC" é uma
estrela rosa/magenta (não dourada nem prateada); "Brilhante Rara" é um
sparkle dourado de 4 pontas (não a estrela clássica de 5 pontas já usada por
GOLD_STAR); "Brilhante Rara Ultra" é o mesmo sparkle dourado em dupla.
symbol_code definidos: ACE_SPEC_RARE → ACE_SPEC (mesmo código técnico,
semântico — mesmo padrão de MEGA_ATTACK, sem família de cor reaproveitável);
SHINY_RARE → GOLD_SPARKLE; SHINY_ULTRA_RARE → GOLD_DOUBLE_SPARKLE. Os três
são códigos novos, nenhum ainda tem representação no componente RaritySymbol
do frontend — pendente de implementação após a execução desta Query.

Nota de versão (v1.3, 2026-08-01):
Gap real descoberto na importação TCGdex de SV1 (Escarlate e Violeta) —
6 cartas vêm da TCGdex com raridade "Hiper Rara", distinta de
"Mega Rara Hiper" e sem cadastro correspondente.

Regras de Negócio:
- Somente raridades comprovadas nas fontes utilizadas pelo catálogo são
  cadastradas.
- A raridade deve pertencer ao Game POKEMON.
- O código representa a identificação técnica e estável da raridade.
- O nome preserva a nomenclatura principal em português.
- O symbol_code representa a classificação visual da raridade.
- A raridade PROMO utiliza o símbolo BLACK_STAR.
- RARE e PROMO podem compartilhar o mesmo símbolo visual.
- A ordem de exibição organiza as raridades em sequência lógica.
- A Query deve ser idempotente.
- Registros existentes devem ser atualizados para convergir ao modelo
  canônico.
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
            'GOLD_TRIPLE_STAR',
            11
        ),
        (
            v_game_id,
            'ACE_SPEC_RARE',
            'ACE SPEC Rara',
            'ACE_SPEC',
            12
        ),
        (
            v_game_id,
            'SHINY_RARE',
            'Shiny Rara',
            'GOLD_SPARKLE',
            13
        ),
        (
            v_game_id,
            'SHINY_ULTRA_RARE',
            'Shiny Ultra Rara',
            'GOLD_DOUBLE_SPARKLE',
            14
        ),
        (
            v_game_id,
            'BLACK_WHITE_RARE',
            'Rara Preto e Branco',
            'BLACK_WHITE_STAR',
            15
        )
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        symbol_code = EXCLUDED.symbol_code,
        display_order = EXCLUDED.display_order;
END;
$$;
