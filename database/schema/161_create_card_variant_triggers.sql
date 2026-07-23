/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 161 - Create Card Variant Triggers
Versão......: 1.0
Status......: CANÔNICA
Data........: 2026-07-18

Descrição resumida:
Cria os triggers de manutenção de updated_at e de consistência de Game para a
tabela card_variant.

Descrição:
Esta Query garante que:
- updated_at seja atualizado automaticamente;
- a Card e o Card Variant Type pertençam ao mesmo Game.

Caminho de validação:
Card
  -> Card Set
  -> Expansion
  -> Game

Card Variant Type
  -> Game

A duplicação de game_id em card_variant foi evitada. A consistência é derivada
por meio das relações canônicas e protegida por trigger.

Pré-requisitos:
- Query 160 - Create Card Variant Table.
- Função public.set_updated_at().
- Tabelas card, card_set, expansion, game e card_variant_type.

===============================================================================
*/

BEGIN;

DROP TRIGGER IF EXISTS trg_card_variant_set_updated_at
ON public.card_variant;

CREATE TRIGGER trg_card_variant_set_updated_at
BEFORE UPDATE ON public.card_variant
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


CREATE OR REPLACE FUNCTION public.validate_card_variant_game_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_card_game_id UUID;
    v_variant_type_game_id UUID;
BEGIN
    SELECT e.game_id
      INTO v_card_game_id
      FROM public.card AS c
      INNER JOIN public.card_set AS cs
          ON cs.id = c.card_set_id
      INNER JOIN public.expansion AS e
          ON e.id = cs.expansion_id
     WHERE c.id = NEW.card_id;

    IF v_card_game_id IS NULL THEN
        RAISE EXCEPTION
            'Card Variant inválida: não foi possível determinar o Game da Card %.',
            NEW.card_id;
    END IF;

    SELECT cvt.game_id
      INTO v_variant_type_game_id
      FROM public.card_variant_type AS cvt
     WHERE cvt.id = NEW.variant_type_id;

    IF v_variant_type_game_id IS NULL THEN
        RAISE EXCEPTION
            'Card Variant inválida: não foi possível determinar o Game do Card Variant Type %.',
            NEW.variant_type_id;
    END IF;

    IF v_card_game_id <> v_variant_type_game_id THEN
        RAISE EXCEPTION
            'Card Variant inválida: a Card pertence ao Game %, mas o Card Variant Type pertence ao Game %.',
            v_card_game_id,
            v_variant_type_game_id;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_card_variant_game_consistency() IS
'Garante que Card e Card Variant Type associados à Card Variant pertençam ao mesmo Game.';


DROP TRIGGER IF EXISTS trg_card_variant_validate_game_consistency
ON public.card_variant;

CREATE TRIGGER trg_card_variant_validate_game_consistency
BEFORE INSERT OR UPDATE OF card_id, variant_type_id
ON public.card_variant
FOR EACH ROW
EXECUTE FUNCTION public.validate_card_variant_game_consistency();

COMMIT;
