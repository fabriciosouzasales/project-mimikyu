/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2071 - Catalog Import Row Triggers
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Cria os triggers de public.catalog_import_row (Query 2070):
normalização de campos textuais e manutenção automática de
updated_at. Mesmo padrão de Query 2061 (catalog_import_job).

Regras de Negócio:
- validation_status, match_status, decision_status e
  persistence_status são normalizados para maiúsculas.
- error_detail vazio é normalizado para NULL.
- updated_at mantido por public.set_updated_at() (Query 001).

Pré-requisitos:
- Query 2070 - Create Catalog Import Row Table.
- Query 001 - Create updated_at Function.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_catalog_import_row()
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

CREATE TRIGGER trg_catalog_import_row_normalize
BEFORE INSERT OR UPDATE
ON public.catalog_import_row
FOR EACH ROW
EXECUTE FUNCTION public.normalize_catalog_import_row();

CREATE TRIGGER trg_catalog_import_row_set_updated_at
BEFORE UPDATE
ON public.catalog_import_row
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DO $$
BEGIN
    IF to_regprocedure('public.normalize_catalog_import_row()') IS NULL THEN
        RAISE EXCEPTION 'Query 2071 falhou: função de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_import_row'::REGCLASS
          AND tgname = 'trg_catalog_import_row_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2071 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_import_row'::REGCLASS
          AND tgname = 'trg_catalog_import_row_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2071 falhou: trigger de updated_at ausente.';
    END IF;

    RAISE NOTICE 'QUERY 2071 CONCLUÍDA: CATALOG IMPORT ROW TRIGGERS CRIADOS';
END;
$$;

COMMIT;
