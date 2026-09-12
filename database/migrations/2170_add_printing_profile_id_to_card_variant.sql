/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2170 - Add printing_profile_id to Card Variant
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01 (§12, §13)

-------------------------------------------------------------------------------
EXECUÇÃO CONFIRMADA — 2026-09-12
-------------------------------------------------------------------------------
Executado via apply_migration no projeto Supabase qjfutqujxrbzgrtkpgkg.
Ordem de aplicacao: 2165 -> 2166 -> 2167 -> 2168 -> 2169 -> 2170 -> 2171.
Todas as sete aplicadas sem erro. Pos-execucao: card_variant = 7002 linhas,
printing_profile_id preenchido = 0.
Estado final validado integralmente pela Query 2823 v1.2:
    12 PASS / 0 FAIL / 0 NOT PROVEN, zero residuo.
O SQL executavel permanece INTOCADO desde a execucao.
-------------------------------------------------------------------------------

Descrição resumida:
Adiciona card_variant.printing_profile_id (NULLABLE, FK RESTRICT) e o guard
estrutural de same-Game.

-------------------------------------------------------------------------------
SEMANTICA DO NULL — LITERAL, RATIFICADA
-------------------------------------------------------------------------------
printing_profile_id IS NULL significa EXATAMENTE:

    "sem perfil de impressão declarado"

NAO significa Unlimited.
NAO significa desconhecido.
NAO significa padrão.
NAO significa erro.

E a verdade literal dos 7.002 card_variant existentes e de todo Card Set
moderno — a fonte só emite `subtype` na era WOTC. Nenhum backfill, nenhuma
reescrita, nenhuma inferência.

-------------------------------------------------------------------------------
SAME-GAME (§13)
-------------------------------------------------------------------------------
Uma Card Variant de POKEMON nao pode apontar para um Print Profile de outro
Game. A FK simples nao prova isso: card_variant nao tem game_id, e o Game
so e alcancavel por card -> card_set -> expansion -> game.

Duas FKs compostas nao resolvem aqui (seria preciso desnormalizar game_id
para dentro de card_variant, alterando uma tabela de 7.002 linhas por um
motivo que vale para uma fracao dela). O projeto ja usa trigger para esta
classe na Fatia 02D.

DESENHO: trigger BEFORE INSERT OR UPDATE, que so faz trabalho quando
printing_profile_id IS NOT NULL. Custo ZERO para os 7.002 existentes e
para todo Set moderno; um lookup indexado por linha apenas na era WOTC.

Fail-closed: divergencia de Game levanta excecao. Nao confia no caller.

Regras de Negócio:
- Coluna NULLABLE; nenhum DEFAULT.
- ON DELETE RESTRICT: um Profile em uso nao pode ser apagado.
- Game da Card e do Profile devem coincidir quando o Profile estiver presente.
- Nenhum backfill. Nenhum UPDATE em linha existente.

Pré-requisitos:
- Query 2166 - Create Card Printing Profile Table.
- Tabela public.card_variant (Query 152).
===============================================================================
*/

BEGIN;

ALTER TABLE public.card_variant
    ADD COLUMN printing_profile_id UUID NULL;

ALTER TABLE public.card_variant
    ADD CONSTRAINT fk_card_variant_printing_profile
        FOREIGN KEY (printing_profile_id)
        REFERENCES public.card_printing_profile (id)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT;

COMMENT ON COLUMN public.card_variant.printing_profile_id IS
    'Perfil de Impressão desta variante. NULL significa EXATAMENTE "sem perfil de impressão declarado" — não significa Unlimited, desconhecido, padrão nem erro. Acabamento continua em variant_type_id; impressão é eixo separado.';

-- Indice parcial: so as linhas COM perfil entram. Os 7.002 legados (todos
-- NULL) nao ocupam espaco no indice. Suporta o lookup Profile -> Variants.
CREATE INDEX ix_card_variant_printing_profile_id
    ON public.card_variant (printing_profile_id)
    WHERE printing_profile_id IS NOT NULL;

COMMENT ON INDEX public.ix_card_variant_printing_profile_id IS
    'Parcial por desenho: hoje 100% das linhas têm printing_profile_id NULL. Só indexa o que existe.';

-- ---------------------------------------------------------------------------
-- SAME-GAME GUARD
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION internal.enforce_card_variant_printing_profile_game()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_card_game_id UUID;
    v_profile_game_id UUID;
BEGIN
    -- Caminho sem perfil: zero trabalho. E o caso dos 7.002 existentes e de
    -- todo Card Set moderno.
    IF NEW.printing_profile_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT e.game_id INTO v_card_game_id
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    WHERE c.id = NEW.card_id;

    IF v_card_game_id IS NULL THEN
        RAISE EXCEPTION 'CARD_VARIANT_PRINTING_PROFILE_GAME_NOT_FOUND: não foi possível resolver o Game da Card % desta variante.', NEW.card_id;
    END IF;

    SELECT p.game_id INTO v_profile_game_id
    FROM public.card_printing_profile p
    WHERE p.id = NEW.printing_profile_id;

    IF v_profile_game_id IS NULL THEN
        RAISE EXCEPTION 'CARD_VARIANT_PRINTING_PROFILE_NOT_FOUND: Perfil de Impressão % não encontrado.', NEW.printing_profile_id;
    END IF;

    IF v_card_game_id <> v_profile_game_id THEN
        RAISE EXCEPTION 'CARD_VARIANT_PRINTING_PROFILE_GAME_MISMATCH: a Card pertence ao Game % e o Perfil de Impressão ao Game % — combinação inválida.', v_card_game_id, v_profile_game_id;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION internal.enforce_card_variant_printing_profile_game() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_card_variant_printing_profile_game
    ON public.card_variant;

CREATE TRIGGER trg_card_variant_printing_profile_game
BEFORE INSERT OR UPDATE OF card_id, printing_profile_id ON public.card_variant
FOR EACH ROW
EXECUTE FUNCTION internal.enforce_card_variant_printing_profile_game();

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   ALTER TABLE x2, COMMENT x2, CREATE INDEX, CREATE FUNCTION, REVOKE,
--   DROP TRIGGER, CREATE TRIGGER.
--   card_variant continua com 7.002 linhas, todas printing_profile_id NULL.
--
-- Como validar:
--   Query 2823 - Validate Card Printing Model, Secoes 1, 3 e 7.
-- ============================================================================
