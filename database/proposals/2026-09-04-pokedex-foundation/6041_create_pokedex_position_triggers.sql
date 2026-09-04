/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6041 - Pokedex Position Triggers
Versão......: 1.0
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging,
               COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-01)

Descrição...:
Governança de identidade e updated_at para pokedex_position (Query
6040).

Diferença deliberada em relação ao padrão de três triggers do módulo
(6001/6011/6021/6031): esta Query cria apenas DOIS triggers
(govern_/touch_updated_at), sem trg_010_normalize_. Justificativa:
pokedex_position não tem nenhum campo de texto livre a normalizar
(id, pokedex_id e species_id são UUID; position_number é INTEGER) —
um trigger de normalização aqui seria um no-op puramente especulativo,
o que contraria a diretriz explícita desta rodada de não criar nada
especulativo. Caso uma evolução futura da entidade introduza um campo
de texto, um trigger de normalização passa a fazer sentido e recebe o
próximo número livre do bloco (6042+).

Campos protegidos contra UPDATE por govern_pokedex_position() (decisão
congelada, COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-FINAL-01,
decisão 3): id, pokedex_id, species_id, created_at.

position_number permanece corrigível administrativamente —
deliberadamente NÃO protegido por este trigger (dado editorial
canônico, mesmo tratamento de pokemon_species.national_dex_number,
Query 6011).

Segurança: EXECUTE revogado de PUBLIC/anon/authenticated já nesta
Query, mesma disciplina de 6031 (lição incorporada desde a origem,
Query 6701).

Pré-requisitos:
- Query 6040 - Create Pokedex Position Table.

Como validar (após execução real, nunca antes):
Ver Query 6800 - Validate Pokedex Foundation, Seção 2 (comportamental)
e Seção 3 (privilégios de função) desta mesma pasta de staging.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.govern_pokedex_position()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'POKEDEX_POSITION_ID_IMMUTABLE';
    END IF;
    IF NEW.pokedex_id IS DISTINCT FROM OLD.pokedex_id THEN
        RAISE EXCEPTION 'POKEDEX_POSITION_POKEDEX_IMMUTABLE';
    END IF;
    IF NEW.species_id IS DISTINCT FROM OLD.species_id THEN
        RAISE EXCEPTION 'POKEDEX_POSITION_SPECIES_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'POKEDEX_POSITION_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokedex_position_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_020_govern_pokedex_position
BEFORE UPDATE
ON public.pokedex_position
FOR EACH ROW
EXECUTE FUNCTION public.govern_pokedex_position();

CREATE TRIGGER trg_030_touch_pokedex_position_updated_at
BEFORE UPDATE
ON public.pokedex_position
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokedex_position_updated_at();

REVOKE EXECUTE ON FUNCTION public.govern_pokedex_position() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokedex_position_updated_at() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ================================================================
-- PROPOSTA — NÃO EXECUTADA. Nenhuma migration foi aplicada ao banco
-- real por esta Query. Ver nota de status ao final de 6030.
-- ================================================================
