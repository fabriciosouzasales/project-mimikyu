/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6091 - Create Pokemon Generation External Reference Triggers
Versão......: 1.0 (PROPOSTA — GATE 3 STAGING)
Status......: PROPOSTO / NÃO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-04 (staging em POKEMON-CATALOG-SOURCING-INITIAL-LOAD-
               PHYSICAL-STAGING-01)

Descrição resumida:
Cria os 3 triggers de governança de pokemon_generation_external_reference,
mesmo padrão físico de pokemon_region_external_reference (Query 6071):
normalização, imutabilidade de identidade e touch de updated_at.

Regras de Negócio:
- normalize_pokemon_generation_external_reference(): BTRIM em
  external_generation_id/source_url; metadata nunca nulo (mantém o DEFAULT já
  garantido pela coluna — normalização aqui só protege contra UPDATE explícito
  para NULL).
- govern_pokemon_generation_external_reference(): id, pokemon_generation_id,
  asset_source_id, external_generation_id e created_at são imutáveis após
  INSERT — a correção de um vínculo errado é DELETE + INSERT, nunca UPDATE
  silencioso de identidade (mesmo racional de 6071/6021/6051).
- touch_pokemon_generation_external_reference_updated_at(): atualiza
  updated_at a cada UPDATE.
- Nenhuma das 3 funções de trigger recebe EXECUTE de nenhum role client-side —
  triggers são disparados implicitamente pelo mecanismo de trigger, nunca
  chamados diretamente.

Pré-requisitos:
- Query 6090 - Create Pokemon Generation External Reference Table.
===============================================================================
*/

BEGIN;

-- 1. Normalização ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.normalize_pokemon_generation_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.external_generation_id := BTRIM(NEW.external_generation_id);
    IF NEW.source_url IS NOT NULL THEN
        NEW.source_url := NULLIF(BTRIM(NEW.source_url), '');
    END IF;
    IF NEW.metadata IS NULL THEN
        NEW.metadata := '{}'::JSONB;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.normalize_pokemon_generation_external_reference()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_normalize_pokemon_generation_external_reference
    BEFORE INSERT OR UPDATE ON public.pokemon_generation_external_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.normalize_pokemon_generation_external_reference();

-- 2. Governança de imutabilidade de identidade -------------------------------

CREATE OR REPLACE FUNCTION public.govern_pokemon_generation_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.id IS DISTINCT FROM OLD.id THEN
            RAISE EXCEPTION 'POKEMON_GENERATION_EXTERNAL_REFERENCE_ID_IMMUTABLE';
        END IF;
        IF NEW.pokemon_generation_id IS DISTINCT FROM OLD.pokemon_generation_id THEN
            RAISE EXCEPTION 'POKEMON_GENERATION_EXTERNAL_REFERENCE_GENERATION_IMMUTABLE';
        END IF;
        IF NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id THEN
            RAISE EXCEPTION 'POKEMON_GENERATION_EXTERNAL_REFERENCE_ASSET_SOURCE_IMMUTABLE';
        END IF;
        IF NEW.external_generation_id IS DISTINCT FROM OLD.external_generation_id THEN
            RAISE EXCEPTION 'POKEMON_GENERATION_EXTERNAL_REFERENCE_EXTERNAL_ID_IMMUTABLE';
        END IF;
        IF NEW.created_at IS DISTINCT FROM OLD.created_at THEN
            RAISE EXCEPTION 'POKEMON_GENERATION_EXTERNAL_REFERENCE_CREATED_AT_IMMUTABLE';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.govern_pokemon_generation_external_reference()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_govern_pokemon_generation_external_reference
    BEFORE UPDATE ON public.pokemon_generation_external_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.govern_pokemon_generation_external_reference();

-- 3. Touch updated_at ---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.touch_pokemon_generation_external_reference_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.touch_pokemon_generation_external_reference_updated_at()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_touch_pokemon_generation_external_reference_updated_at
    BEFORE UPDATE ON public.pokemon_generation_external_reference
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_pokemon_generation_external_reference_updated_at();

COMMIT;
