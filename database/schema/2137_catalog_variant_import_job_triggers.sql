/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2137 - Catalog Variant Import Job Triggers
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Triggers de public.catalog_variant_import_job (Query 2136): mesmo
padrão de normalização e updated_at de catalog_import_job (Query 2061).

Pré-requisitos:
- Query 2136 - Create Catalog Variant Import Job Table.
- Query 001 - Create updated_at Function.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_catalog_variant_import_job()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.source := UPPER(BTRIM(NEW.source));
    NEW.status := UPPER(BTRIM(NEW.status));
    IF NEW.progress_step IS NOT NULL THEN
        NEW.progress_step := UPPER(BTRIM(NEW.progress_step));
    END IF;
    NEW.error_summary := NULLIF(BTRIM(NEW.error_summary), '');
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_catalog_variant_import_job_normalize
BEFORE INSERT OR UPDATE
ON public.catalog_variant_import_job
FOR EACH ROW
EXECUTE FUNCTION public.normalize_catalog_variant_import_job();

CREATE TRIGGER trg_catalog_variant_import_job_set_updated_at
BEFORE UPDATE
ON public.catalog_variant_import_job
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DO $$
BEGIN
    IF to_regprocedure('public.normalize_catalog_variant_import_job()') IS NULL THEN
        RAISE EXCEPTION 'Query 2137 falhou: função de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_variant_import_job'::REGCLASS
          AND tgname = 'trg_catalog_variant_import_job_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2137 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_variant_import_job'::REGCLASS
          AND tgname = 'trg_catalog_variant_import_job_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2137 falhou: trigger de updated_at ausente.';
    END IF;

    RAISE NOTICE 'QUERY 2137 CONCLUÍDA: CATALOG VARIANT IMPORT JOB TRIGGERS CRIADOS';
END;
$$;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), junto com as Queries 2136/2138-2142.
-- ================================================================
