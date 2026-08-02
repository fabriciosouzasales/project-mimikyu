/*
Project Mimikyu
Query 211 - Card External Reference Triggers
Versão 2.0 (2026-08-02, Migration 277) — protect_card_external_reference_identity()
passa a proteger também language_id (nova coluna de identidade da linha,
Query 210 v2.0) contra alteração pós-INSERT, mesmo tratamento já dado a
id/card_id/asset_source_id.
Pré-requisito: Query 210.
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.normalize_card_external_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.external_card_id := BTRIM(NEW.external_card_id);
    NEW.external_set_id := NULLIF(BTRIM(NEW.external_set_id), '');
    NEW.source_number := NULLIF(BTRIM(NEW.source_number), '');
    NEW.source_url := NULLIF(BTRIM(NEW.source_url), '');
    NEW.image_source_url := NULLIF(BTRIM(NEW.image_source_url), '');
    IF NEW.metadata IS NULL THEN
        NEW.metadata := '{}'::JSONB;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_card_external_reference_normalize
BEFORE INSERT OR UPDATE
ON public.card_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.normalize_card_external_reference();

CREATE TRIGGER trg_card_external_reference_set_updated_at
BEFORE UPDATE
ON public.card_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.protect_card_external_reference_identity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id IS DISTINCT FROM OLD.id THEN
        RAISE EXCEPTION
            'card_external_reference.id não pode ser alterado.';
    END IF;

    IF NEW.card_id IS DISTINCT FROM OLD.card_id THEN
        RAISE EXCEPTION
            'card_external_reference.card_id não pode ser alterado.';
    END IF;

    IF NEW.asset_source_id IS DISTINCT FROM OLD.asset_source_id THEN
        RAISE EXCEPTION
            'card_external_reference.asset_source_id não pode ser alterado.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_card_external_reference_protect_identity
BEFORE UPDATE
ON public.card_external_reference
FOR EACH ROW
EXECUTE FUNCTION public.protect_card_external_reference_identity();

COMMENT ON FUNCTION public.normalize_card_external_reference() IS
    'Normaliza identificadores, números, URLs e metadata de card_external_reference.';
COMMENT ON FUNCTION public.protect_card_external_reference_identity() IS
    'Protege id, card_id e asset_source_id contra alteração.';

DO $$
BEGIN
    IF to_regprocedure(
        'public.normalize_card_external_reference()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 211 falhou: normalize_card_external_reference() ausente.';
    END IF;

    IF to_regprocedure(
        'public.protect_card_external_reference_identity()'
    ) IS NULL THEN
        RAISE EXCEPTION
            'Query 211 falhou: protect_card_external_reference_identity() ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid =
              'public.card_external_reference'::regclass
          AND tgname =
              'trg_card_external_reference_normalize'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 211 falhou: trigger de normalização ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid =
              'public.card_external_reference'::regclass
          AND tgname =
              'trg_card_external_reference_set_updated_at'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 211 falhou: trigger de updated_at ausente.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgrelid =
              'public.card_external_reference'::regclass
          AND tgname =
              'trg_card_external_reference_protect_identity'
          AND NOT tgisinternal
    ) THEN
        RAISE EXCEPTION
            'Query 211 falhou: trigger de proteção ausente.';
    END IF;

    RAISE NOTICE
        'QUERY 211 CONCLUÍDA: CARD EXTERNAL REFERENCE TRIGGERS CRIADOS';
END;
$$;

COMMIT;
