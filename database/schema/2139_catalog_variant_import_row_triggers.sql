/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2139 - Catalog Variant Import Row Triggers
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Triggers de public.catalog_variant_import_row (Query 2138): mesmo
padrão de catalog_import_row (Query 2071).

Pré-requisitos:
- Query 2138 - Create Catalog Variant Import Row Table.
- Query 001 - Create updated_at Function.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_catalog_variant_import_row()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.validation_status := UPPER(BTRIM(NEW.validation_status));
    NEW.match_status := UPPER(BTRIM(NEW.match_status));
    NEW.decision_status := UPPER(BTRIM(NEW.decision_status));
    NEW.persistence_status := UPPER(BTRIM(NEW.persistence_status));
    NEW.error_detail := NULLIF(BTRIM(NEW.error_detail), '');
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_catalog_variant_import_row_normalize
BEFORE INSERT OR UPDATE
ON public.catalog_variant_import_row
FOR EACH ROW
EXECUTE FUNCTION public.normalize_catalog_variant_import_row();

CREATE TRIGGER trg_catalog_variant_import_row_set_updated_at
BEFORE UPDATE
ON public.catalog_variant_import_row
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DO $$
BEGIN
    IF to_regprocedure('public.normalize_catalog_variant_import_row()') IS NULL THEN
        RAISE EXCEPTION 'Query 2139 falhou: função de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_variant_import_row'::REGCLASS
          AND tgname = 'trg_catalog_variant_import_row_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2139 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_variant_import_row'::REGCLASS
          AND tgname = 'trg_catalog_variant_import_row_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2139 falhou: trigger de updated_at ausente.';
    END IF;

    RAISE NOTICE 'QUERY 2139 CONCLUÍDA: CATALOG VARIANT IMPORT ROW TRIGGERS CRIADOS';
END;
$$;

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), junto com as Queries 2136-2138/
-- 2140-2142.
-- ================================================================
