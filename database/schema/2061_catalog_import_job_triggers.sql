/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2061 - Catalog Import Job Triggers
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-01

Descrição...:
Cria os triggers de public.catalog_import_job (Query 2060):
normalização de campos textuais e manutenção automática de
updated_at. Sem trigger de governança de transição de estado — ver
justificativa na Query 2060 (as próprias funções SECURITY DEFINER e
a transação de admin_confirm_catalog_import(), com SELECT ... FOR
UPDATE, já tornam um estado inválido estruturalmente inalcançável).

Regras de Negócio:
- source, status e progress_step são normalizados para maiúsculas
  antes de gravar, mesmo padrão de normalize_asset_import_run()
  (Query 221) — protege contra divergência de caixa entre chamadas
  vindas de contextos diferentes (Edge Function vs. função SQL).
- error_summary vazio é normalizado para NULL.
- updated_at mantido por public.set_updated_at() (Query 001), mesmo
  padrão de todas as tabelas com updated_at deste projeto.

Pré-requisitos:
- Query 2060 - Create Catalog Import Job Table.
- Query 001 - Create updated_at Function.
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_catalog_import_job()
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

CREATE TRIGGER trg_catalog_import_job_normalize
BEFORE INSERT OR UPDATE
ON public.catalog_import_job
FOR EACH ROW
EXECUTE FUNCTION public.normalize_catalog_import_job();

CREATE TRIGGER trg_catalog_import_job_set_updated_at
BEFORE UPDATE
ON public.catalog_import_job
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

DO $$
BEGIN
    IF to_regprocedure('public.normalize_catalog_import_job()') IS NULL THEN
        RAISE EXCEPTION 'Query 2061 falhou: função de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_import_job'::REGCLASS
          AND tgname = 'trg_catalog_import_job_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2061 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'public.catalog_import_job'::REGCLASS
          AND tgname = 'trg_catalog_import_job_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION 'Query 2061 falhou: trigger de updated_at ausente.';
    END IF;

    RAISE NOTICE 'QUERY 2061 CONCLUÍDA: CATALOG IMPORT JOB TRIGGERS CRIADOS';
END;
$$;

COMMIT;
