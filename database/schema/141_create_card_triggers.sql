/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 141 - Create Card Triggers
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria os triggers responsáveis pela atualização automática de updated_at e pela
validação da consistência do Game nas relações da tabela card.

Descrição:
A tabela card não armazena game_id porque essa informação pode ser obtida pelo
relacionamento:

Card
→ Card Set
→ Expansion
→ Game

Entretanto, a Rarity e a Card Category também pertencem a um Game.

Esta Query cria uma função e um trigger para garantir que:
- o Card Set pertença ao mesmo Game da Rarity;
- o Card Set pertença ao mesmo Game da Card Category.

Também cria o trigger responsável pela atualização automática de updated_at.

Regras de Negócio:
- Card Set, Rarity e Card Category devem pertencer ao mesmo Game.
- A validação deve ocorrer antes de INSERT ou UPDATE.
- A operação deve falhar quando houver divergência entre os Games.
- O campo updated_at deve refletir a última alteração do registro.
- Os triggers não devem depender da aplicação.
- A Query pode ser executada novamente sem criar triggers duplicados.

Pré-requisitos:
- Query 000 - Infrastructure.
- Query 140 - Create Card Table.
===============================================================================
*/

CREATE OR REPLACE FUNCTION public.validate_card_game_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_card_set_game_id UUID;
    v_rarity_game_id UUID;
    v_category_game_id UUID;
BEGIN
    SELECT e.game_id
      INTO v_card_set_game_id
      FROM public.card_set AS cs
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE cs.id = NEW.card_set_id;

    SELECT r.game_id
      INTO v_rarity_game_id
      FROM public.rarity AS r
     WHERE r.id = NEW.rarity_id;

    SELECT cc.game_id
      INTO v_category_game_id
      FROM public.card_category AS cc
     WHERE cc.id = NEW.category_id;

    IF v_card_set_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível identificar o Game do Card Set informado.';
    END IF;

    IF v_rarity_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível identificar o Game da Rarity informada.';
    END IF;

    IF v_category_game_id IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível identificar o Game da Card Category informada.';
    END IF;

    IF v_card_set_game_id <> v_rarity_game_id THEN
        RAISE EXCEPTION
            'Inconsistência de Game: o Card Set e a Rarity pertencem a Games diferentes.';
    END IF;

    IF v_card_set_game_id <> v_category_game_id THEN
        RAISE EXCEPTION
            'Inconsistência de Game: o Card Set e a Card Category pertencem a Games diferentes.';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_card_game_consistency() IS
    'Garante que Card Set, Rarity e Card Category associados a uma Card pertençam ao mesmo Game.';

DROP TRIGGER IF EXISTS trg_card_validate_game_consistency
ON public.card;

CREATE TRIGGER trg_card_validate_game_consistency
BEFORE INSERT OR UPDATE OF card_set_id, rarity_id, category_id
ON public.card
FOR EACH ROW
EXECUTE FUNCTION public.validate_card_game_consistency();

DROP TRIGGER IF EXISTS trg_card_set_updated_at
ON public.card;

CREATE TRIGGER trg_card_set_updated_at
BEFORE UPDATE ON public.card
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();
