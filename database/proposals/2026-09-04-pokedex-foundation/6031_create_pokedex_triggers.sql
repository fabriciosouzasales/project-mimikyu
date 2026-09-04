/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6031 - Pokedex Triggers
Versão......: 1.0
Status......: PROPOSTA (staging — aguardando execução)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging,
               COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-01)

Descrição...:
Normalização, governança de identidade e updated_at para pokedex
(Query 6030). Mesmo padrão de três triggers já estabelecido no módulo
(Query 6001/6011/6021, por sua vez herdado de card_set_external_
reference, Query 241): normalize_/govern_/touch_..._updated_at,
trg_010_/020_/030_.

Campos protegidos contra UPDATE por govern_pokedex() (decisão
congelada, COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-FINAL-01):
id, code, created_at.

canonical_name e is_active permanecem corrigíveis administrativamente —
deliberadamente NÃO protegidos por este trigger, mesmo tratamento já
dado a pokemon_generation.canonical_name/is_active (Query 6001).

Segurança (lição incorporada desde a origem desta rodada, achado do
fechamento de segurança do incremento anterior,
COLLECTIONS-PHYSICAL-INCREMENT-02G-SECURITY-CLOSEOUT-FIX-01/Query
6701): as três funções abaixo só são chamadas pelos próprios triggers
trg_010_/020_/030_, nunca diretamente por client role — EXECUTE é
revogado de PUBLIC/anon/authenticated já nesta Query, não como
correção posterior.

Pré-requisitos:
- Query 6030 - Create Pokedex Table.

Como validar (após execução real, nunca antes):
Ver Query 6800 - Validate Pokedex Foundation, Seção 2 (comportamental)
e Seção 3 (privilégios de função) desta mesma pasta de staging.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_pokedex()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.code := UPPER(BTRIM(NEW.code));
    NEW.canonical_name := BTRIM(NEW.canonical_name);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.govern_pokedex()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION 'POKEDEX_ID_IMMUTABLE';
    END IF;
    IF NEW.code IS DISTINCT FROM OLD.code THEN
        RAISE EXCEPTION 'POKEDEX_CODE_IMMUTABLE';
    END IF;
    IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
        RAISE EXCEPTION 'POKEDEX_CREATED_AT_IMMUTABLE';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.touch_pokedex_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_010_normalize_pokedex
BEFORE INSERT OR UPDATE
ON public.pokedex
FOR EACH ROW
EXECUTE FUNCTION public.normalize_pokedex();

CREATE TRIGGER trg_020_govern_pokedex
BEFORE UPDATE
ON public.pokedex
FOR EACH ROW
EXECUTE FUNCTION public.govern_pokedex();

CREATE TRIGGER trg_030_touch_pokedex_updated_at
BEFORE UPDATE
ON public.pokedex
FOR EACH ROW
EXECUTE FUNCTION public.touch_pokedex_updated_at();

REVOKE EXECUTE ON FUNCTION public.normalize_pokedex() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.govern_pokedex() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.touch_pokedex_updated_at() FROM PUBLIC, anon, authenticated;

COMMIT;

-- ================================================================
-- PROPOSTA — NÃO EXECUTADA. Nenhuma migration foi aplicada ao banco
-- real por esta Query. Ver nota de status ao final de 6030.
-- ================================================================
