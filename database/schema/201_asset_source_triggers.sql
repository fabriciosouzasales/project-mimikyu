/*
Project Mimikyu
Query 201 - Asset Source Triggers
Objetivo: criar normalização, updated_at e proteção de registros técnicos.
Pré-requisito: Query 200.
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_asset_source()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.code := UPPER(BTRIM(NEW.code));
    NEW.name := BTRIM(NEW.name);
    NEW.source_type := UPPER(BTRIM(NEW.source_type));
    NEW.base_url := NULLIF(BTRIM(NEW.base_url), '');
    NEW.api_base_url := NULLIF(BTRIM(NEW.api_base_url), '');
    NEW.documentation_url := NULLIF(BTRIM(NEW.documentation_url), '');
    NEW.terms_url := NULLIF(BTRIM(NEW.terms_url), '');
    NEW.attribution_text := NULLIF(BTRIM(NEW.attribution_text), '');
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_source_normalize
BEFORE INSERT OR UPDATE
ON public.asset_source
FOR EACH ROW
EXECUTE FUNCTION public.normalize_asset_source();

CREATE TRIGGER trg_asset_source_set_updated_at
BEFORE UPDATE
ON public.asset_source
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.protect_asset_source_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION
            'asset_source.id não pode ser alterado.';
    END IF;

    IF NEW.code IS DISTINCT FROM OLD.code THEN
        RAISE EXCEPTION
            'asset_source.code não pode ser alterado.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_asset_source_protect_identity
BEFORE UPDATE
ON public.asset_source
FOR EACH ROW
EXECUTE FUNCTION public.protect_asset_source_identity();

COMMENT ON FUNCTION public.normalize_asset_source() IS
    'Normaliza códigos, textos e URLs de asset_source.';
COMMENT ON FUNCTION public.protect_asset_source_identity() IS
    'Impede alteração dos identificadores id e code de asset_source.';

DO $$
BEGIN
    IF to_regprocedure('public.normalize_asset_source()') IS NULL THEN
        RAISE EXCEPTION
            'Query 201 falhou: normalize_asset_source() não foi criada.';
    END IF;

    IF to_regprocedure('public.protect_asset_source_identity()') IS NULL THEN
        RAISE EXCEPTION
            'Query 201 falhou: protect_asset_source_identity() não foi criada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_source'::regclass
          AND tgname = 'trg_asset_source_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 201 falhou: trg_asset_source_normalize não foi criado.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_source'::regclass
          AND tgname = 'trg_asset_source_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 201 falhou: trg_asset_source_set_updated_at não foi criado.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid = 'public.asset_source'::regclass
          AND tgname = 'trg_asset_source_protect_identity'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 201 falhou: trg_asset_source_protect_identity não foi criado.';
    END IF;

    RAISE NOTICE
        'QUERY 201 CONCLUÍDA: ASSET SOURCE TRIGGERS CRIADOS';
END;
$$;

COMMIT;
