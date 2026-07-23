/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 870 - Seed Card Asset Type
Versão......: 1.2
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-23

Descrição resumida:
Cadastra os tipos canônicos de ativo digital associados às Cards do
Pokémon Trading Card Game.

Descrição:
Catálogo canônico atual:
1. CARD_FRONT — imagem completa da frente da Card.
2. ARTWORK    — ilustração isolada ou recortada, quando disponível.
3. CARD_BACK  — imagem do verso da Card, quando necessária.

CARD_FRONT é o tipo inicialmente utilizado para representar cada Card. Estes
tipos não representam STANDARD, HOLO, REVERSE_HOLO ou qualquer outra Card
Variant física — resolução, formato, dimensões e localização pertencem à
entidade card_asset, não a card_asset_type.

Histórico de correção (Princípio da Fonte Canônica, STD-001 Seção 10):
- v1.0: usava por engano o código de Game 'POKEMON_TCG', inexistente no
  projeto — falhou ao ser executada (RAISE EXCEPTION). Também usava
  name/description em inglês, quebrando o padrão do projeto (campos legíveis
  por humanos em português).
- v1.1: corrigiu apenas o idioma de name/description.
- v1.2 (esta versão): corrige simultaneamente o código de Game para 'POKEMON'
  (o único código real e já usado por todos os demais Seeds do projeto) e o
  idioma de name/description para português. Versão executada com sucesso.

Regras de Negócio:
- O Game POKEMON deve existir.
- O seed deve ser idempotente.
- Registros existentes devem convergir para os valores desta Query.
- code é a chave natural dentro do Game.
- asset_order determina a ordem de apresentação.

Pré-requisitos:
- Query 170 - Create Card Asset Type Table.
- Query 171 - Create Card Asset Type Triggers.
- Seed do Game POKEMON.

===============================================================================

NOTA DE DOCUMENTAÇÃO: cabeçalho reformatado para o padrão STD-001. Lógica SQL
idêntica à versão 1.2 efetivamente executada e confirmada por Fabrício
("Query 970 concluída com sucesso").
===============================================================================
*/

BEGIN;

DO $$
DECLARE
    v_game_id UUID;
BEGIN
    SELECT g.id
      INTO v_game_id
      FROM public.game g
     WHERE g.code = 'POKEMON';

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION
            'O Game com o código POKEMON não foi encontrado. A Query 870 não pode continuar.';
    END IF;

    INSERT INTO public.card_asset_type (
        game_id,
        code,
        name,
        description,
        asset_order,
        is_active
    )
    VALUES
        (
            v_game_id,
            'CARD_FRONT',
            'Frente da Carta',
            'Imagem completa da frente utilizada como representação visual canônica da Carta, independentemente de suas variações físicas.',
            1,
            TRUE
        ),
        (
            v_game_id,
            'ARTWORK',
            'Ilustração',
            'Ilustração isolada ou recortada a partir da imagem da Carta, quando disponível.',
            2,
            TRUE
        ),
        (
            v_game_id,
            'CARD_BACK',
            'Verso da Carta',
            'Imagem do verso da Carta, utilizada somente quando houver necessidade específica.',
            3,
            TRUE
        )
    ON CONFLICT (game_id, code)
    DO UPDATE SET
        name = EXCLUDED.name,
        description = EXCLUDED.description,
        asset_order = EXCLUDED.asset_order,
        is_active = EXCLUDED.is_active,
        updated_at = NOW();
END;
$$;

COMMIT;
