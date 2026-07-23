/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 181 - Create Card Asset Triggers
Versão......: 1.1
Status......: CANÔNICA
Autor.......: Fabrício Sales / ChatGPT
Data........: 2026-07-18

Descrição resumida:
Cria os triggers de manutenção de updated_at e de consistência de Game para a
tabela card_asset.

Descrição:
Esta Query garante que:
- updated_at seja atualizado automaticamente;
- a Card e o Card Asset Type pertençam ao mesmo Game.

Caminho de validação:
Card
  -> Card Set
  -> Expansion
  -> Game

Card Asset Type
  -> Game

A duplicação de game_id em card_asset foi evitada. A consistência é derivada
por meio das relações canônicas e protegida por trigger.

Pré-requisitos:
- Query 180 - Create Card Asset Table.
- Função public.set_updated_at().
- Tabelas card, card_set, expansion, game e card_asset_type.

===============================================================================

NOTA DE DOCUMENTAÇÃO: cabeçalho recebido já no padrão STD-001. Estrutura da
função/trigger de consistência de Game confirmada como estruturalmente
idêntica ao padrão já usado em 161_create_card_variant_triggers.sql (mesma
forma de DECLARE/SELECT/RAISE EXCEPTION). Diferente de 180, esta Query não
depende de "IF NOT EXISTS" contra uma tabela pré-existente incompatível — o
trigger referencia apenas card_id e asset_type_id, ambas colunas presentes na
estrutura física real confirmada — portanto a execução relatada por Fabrício
é tecnicamente consistente com uma criação real do trigger, ao contrário da
Query 180 (ver nota em 180_create_card_asset_table.sql).
===============================================================================
*/

BEGIN;

DO $$
BEGIN
    IF to_regprocedure('public.set_updated_at()') IS NULL THEN
        RAISE EXCEPTION
            'Não foi possível executar a Query 181: a função public.set_updated_at() não existe.';
    END IF;
END;
$$;


DROP TRIGGER IF EXISTS trg_card_asset_set_updated_at
ON public.card_asset;

CREATE TRIGGER trg_card_asset_set_updated_at
BEFORE UPDATE ON public.card_asset
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();


CREATE OR REPLACE FUNCTION public.validate_card_asset_game_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_card_game_id UUID;
    v_asset_type_game_id UUID;
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
            'Card Asset inválido: não foi possível determinar o Game da Card %.',
            NEW.card_id;
    END IF;

    SELECT cat.game_id
      INTO v_asset_type_game_id
      FROM public.card_asset_type AS cat
     WHERE cat.id = NEW.asset_type_id;

    IF v_asset_type_game_id IS NULL THEN
        RAISE EXCEPTION
            'Card Asset inválido: não foi possível determinar o Game do Card Asset Type %.',
            NEW.asset_type_id;
    END IF;

    IF v_card_game_id <> v_asset_type_game_id THEN
        RAISE EXCEPTION
            'Card Asset inválido: a Card pertence ao Game %, mas o Card Asset Type pertence ao Game %.',
            v_card_game_id,
            v_asset_type_game_id;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.validate_card_asset_game_consistency() IS
'Garante que Card e Card Asset Type associados ao Card Asset pertençam ao mesmo Game.';


DROP TRIGGER IF EXISTS trg_card_asset_validate_game_consistency
ON public.card_asset;

CREATE TRIGGER trg_card_asset_validate_game_consistency
BEFORE INSERT OR UPDATE OF card_id, asset_type_id
ON public.card_asset
FOR EACH ROW
EXECUTE FUNCTION public.validate_card_asset_game_consistency();

COMMIT;
