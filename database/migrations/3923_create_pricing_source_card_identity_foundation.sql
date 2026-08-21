-- 3923_create_pricing_source_card_identity_foundation
--
-- Cria pricing_source_card_identity: fundacao para identidades PENDING/CONFIRMED/REJECTED
-- de uma carta local numa fonte externa de precificacao (ex.: JustTCG), com suporte a
-- PRIMARY (identidade canonica, uma ativa por mapping), ALTERNATE (N confirmadas por
-- mapping) e ALIAS (N confirmadas, apontando para um canonical_identity_id PRIMARY ou
-- ALTERNATE confirmado da mesma mapping). Integra aditivamente com pricing_product via
-- pricing_source_card_identity_id nullable.
--
-- Validado integralmente em tres rodadas de BEGIN/ROLLBACK contra o baseline real de
-- producao (2026-08-20), a ultima delas apos revisao explicita de Fabricio restaurando
-- invariantes do desenho original que uma reconstrucao anterior (apos perda de contexto
-- de sessao) havia omitido ou enfraquecido. Autorizacao final de aplicacao concedida por
-- Fabricio nesta mesma data.
--
-- Requisitos obrigatorios cobertos (lista consolidada apos as rodadas de revisao):
--   1. LOCK TABLE pricing_sync_run IN EXCLUSIVE MODE NOWAIT + guarda RECEIVED/PROCESSING.
--   2. FK composta pricing_card_mapping_id+pricing_source_id -> pricing_card_mapping
--      (id, pricing_source_id), exigindo uq_pricing_card_mapping_id_source nova.
--   3. canonical_identity_id (FK composta self-referencing na mesma mapping) + trigger
--      validate_pricing_source_card_identity_canonical (FOR SHARE) validando que o alvo
--      e CONFIRMED e PRIMARY|ALTERNATE.
--   4. match_status PENDING/CONFIRMED/REJECTED (nao apenas CONFIRMED/REJECTED).
--   5. Apenas uma PRIMARY ativa (PENDING ou CONFIRMED) por mapping; N ALTERNATE e N ALIAS
--      confirmadas permitidas.
--   6. uq_pricing_source_card_identity_mapping_external incondicional (qualquer status) +
--      uq_pricing_source_card_identity_confirmed_source_external (CONFIRMED apenas).
--   7. Produto bloqueado para identidade PENDING/REJECTED/ALIAS via
--      validate_pricing_product_identity_confirmed (FOR SHARE).
--   8. uq_pricing_product_identity_external_product.
--   9. Backfill idempotente ANTES da criacao das triggers, preservando confirmed_at/by
--      byte a byte a partir de pricing_card_mapping (nao passa pela autoridade temporal).
--  10. Triggers criadas DEPOIS do backfill -- regem apenas o dual-write futuro do conector.
--  11. Grants column-scoped para service_role (UPDATE restrito as colunas de transicao;
--      id/pricing_card_mapping_id/pricing_source_id/created_at/updated_at fora da lista).
--  12. Asserções relacionais dinamicas de integridade pos-backfill embutidas no proprio
--      arquivo (contagens dinamicas, nao numeros fixos -- aborta a migration inteira se
--      o backfill nao for consistente).
--  13. guard_pricing_source_card_identity_target_integrity: identidade referenciada como
--      canonical_identity_id de algum ALIAS nao pode virar REJECTED/PENDING/ALIAS; e
--      identidade com pricing_product vinculado nao pode virar ALIAS.
--  14. CHECK last_checked_at obrigatorio quando match_status IN (CONFIRMED, REJECTED).
--  15. SECURITY INVOKER + search_path fixo + EXECUTE revogado de PUBLIC em todas as
--      funcoes novas; policy RLS somente SELECT para authenticated via is_admin().
--
-- Nenhuma instrucao BEGIN/COMMIT/ROLLBACK neste arquivo -- a ferramenta de aplicacao de
-- migration do Supabase MCP fornece a transacao implicita.
--
-- STATUS: CONFIRMADO EXECUTADO em 2026-08-20 via Supabase MCP (apply_migration),
-- projeto qjfutqujxrbzgrtkpgkg. Validacao pos-aplicacao detalhada no relatorio da
-- mesma rodada (docs/log.md e handoff vigente a atualizar em rodada de documentacao
-- separada, nao nesta rodada).

-- 0) Guarda de concorrencia: LOCK real + bloqueia se houver sync run ativo --
LOCK TABLE public.pricing_sync_run IN EXCLUSIVE MODE NOWAIT;

DO $$
DECLARE
  v_active_count int;
BEGIN
  SELECT count(*) INTO v_active_count FROM pricing_sync_run WHERE status IN ('RECEIVED','PROCESSING');
  IF v_active_count > 0 THEN
    RAISE EXCEPTION 'PRICING_MIGRATION_BLOCKED_ACTIVE_SYNC_RUN: % run(s) em RECEIVED/PROCESSING', v_active_count;
  END IF;
END $$;

-- 1) FK composta mapping<->source: exige uq(id, pricing_source_id) ---------
ALTER TABLE public.pricing_card_mapping
    ADD CONSTRAINT uq_pricing_card_mapping_id_source UNIQUE (id, pricing_source_id);

-- 2) Tabela pricing_source_card_identity -------------------------------------
CREATE TABLE public.pricing_source_card_identity (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    pricing_card_mapping_id uuid NOT NULL,
    pricing_source_id       uuid NOT NULL REFERENCES public.pricing_source(id) ON DELETE RESTRICT,
    external_card_id        text NOT NULL,
    external_card_name      text,
    match_status            text NOT NULL DEFAULT 'PENDING',
    identity_role           text NOT NULL DEFAULT 'PRIMARY',
    canonical_identity_id   uuid,
    match_method            text,
    match_evidence          jsonb NOT NULL DEFAULT '{}'::jsonb,
    last_checked_at         timestamptz,
    confirmed_at            timestamptz,
    confirmed_by            uuid,
    rejected_at             timestamptz,
    rejected_by             uuid,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT ck_pricing_source_card_identity_status
        CHECK (match_status IN ('PENDING', 'CONFIRMED', 'REJECTED')),
    CONSTRAINT ck_pricing_source_card_identity_role
        CHECK (identity_role IN ('PRIMARY', 'ALTERNATE', 'ALIAS')),
    CONSTRAINT ck_pricing_source_card_identity_canonical_role
        CHECK (
            (identity_role = 'ALIAS' AND canonical_identity_id IS NOT NULL)
            OR (identity_role IN ('PRIMARY', 'ALTERNATE') AND canonical_identity_id IS NULL)
        ),
    CONSTRAINT ck_pricing_source_card_identity_canonical_not_self
        CHECK (canonical_identity_id IS NULL OR canonical_identity_id <> id),
    CONSTRAINT ck_pricing_source_card_identity_external_card_id_not_blank
        CHECK (btrim(external_card_id) <> ''),
    CONSTRAINT ck_pricing_source_card_identity_evidence_is_object
        CHECK (jsonb_typeof(match_evidence) = 'object'),
    CONSTRAINT ck_pricing_source_card_identity_last_checked_required
        CHECK (match_status = 'PENDING' OR last_checked_at IS NOT NULL),
    CONSTRAINT ck_pricing_source_card_identity_status_fields
        CHECK (
            (match_status = 'PENDING'
                AND confirmed_at IS NULL AND confirmed_by IS NULL
                AND rejected_at IS NULL AND rejected_by IS NULL)
            OR
            (match_status = 'CONFIRMED'
                AND confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL
                AND rejected_at IS NULL AND rejected_by IS NULL)
            OR
            (match_status = 'REJECTED'
                AND confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL
                AND rejected_at IS NOT NULL AND rejected_by IS NOT NULL
                AND rejected_at >= confirmed_at)
        ),
    CONSTRAINT uq_pricing_source_card_identity_id_mapping
        UNIQUE (id, pricing_card_mapping_id),
    CONSTRAINT uq_pricing_source_card_identity_mapping_external
        UNIQUE (pricing_card_mapping_id, external_card_id),
    CONSTRAINT fk_pricing_source_card_identity_mapping_source
        FOREIGN KEY (pricing_card_mapping_id, pricing_source_id)
        REFERENCES public.pricing_card_mapping (id, pricing_source_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_pricing_source_card_identity_canonical
        FOREIGN KEY (canonical_identity_id, pricing_card_mapping_id)
        REFERENCES public.pricing_source_card_identity (id, pricing_card_mapping_id)
        ON DELETE RESTRICT
);

COMMENT ON TABLE public.pricing_source_card_identity IS
    'Identidade PENDING/CONFIRMED/REJECTED de uma carta local numa fonte externa de precificacao. PRIMARY/ALTERNATE sao identidades canonicas (confirmed_at/by e rejected_at/by imutaveis apos escritos); ALIAS aponta para um canonical_identity_id CONFIRMED/PRIMARY|ALTERNATE da mesma mapping. Apenas uma PRIMARY ativa por mapping; N ALTERNATE e N ALIAS permitidos.';

CREATE UNIQUE INDEX uq_pricing_source_card_identity_active_primary_per_mapping
    ON public.pricing_source_card_identity (pricing_card_mapping_id)
    WHERE match_status IN ('PENDING', 'CONFIRMED') AND identity_role = 'PRIMARY';

CREATE UNIQUE INDEX uq_pricing_source_card_identity_confirmed_source_external
    ON public.pricing_source_card_identity (pricing_source_id, external_card_id)
    WHERE match_status = 'CONFIRMED';

CREATE INDEX ix_pricing_source_card_identity_mapping_id
    ON public.pricing_source_card_identity (pricing_card_mapping_id);
CREATE INDEX ix_pricing_source_card_identity_pricing_source_id
    ON public.pricing_source_card_identity (pricing_source_id);
CREATE INDEX ix_pricing_source_card_identity_canonical_identity_id
    ON public.pricing_source_card_identity (canonical_identity_id)
    WHERE canonical_identity_id IS NOT NULL;

-- 3) Integracao com pricing_product -------------------------------------------
ALTER TABLE public.pricing_product
    ADD COLUMN pricing_source_card_identity_id uuid;

ALTER TABLE public.pricing_product
    ADD CONSTRAINT fk_pricing_product_identity_same_mapping
    FOREIGN KEY (pricing_source_card_identity_id, pricing_card_mapping_id)
    REFERENCES public.pricing_source_card_identity (id, pricing_card_mapping_id)
    ON DELETE RESTRICT;

CREATE INDEX ix_pricing_product_pricing_source_card_identity_id
    ON public.pricing_product (pricing_source_card_identity_id)
    WHERE pricing_source_card_identity_id IS NOT NULL;

CREATE UNIQUE INDEX uq_pricing_product_identity_external_product
    ON public.pricing_product (pricing_source_card_identity_id, external_product_id)
    WHERE pricing_source_card_identity_id IS NOT NULL;

-- 4) RLS somente authenticated admin + grants column-scoped ------------------
ALTER TABLE public.pricing_source_card_identity ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
    ON public.pricing_source_card_identity
    FOR SELECT
    TO authenticated
    USING (is_admin());

REVOKE ALL ON public.pricing_source_card_identity FROM PUBLIC;
REVOKE ALL ON public.pricing_source_card_identity FROM anon;
REVOKE ALL ON public.pricing_source_card_identity FROM authenticated;

GRANT SELECT ON public.pricing_source_card_identity TO authenticated;
GRANT SELECT, INSERT ON public.pricing_source_card_identity TO service_role;
GRANT UPDATE (
    match_status, identity_role, canonical_identity_id,
    confirmed_at, confirmed_by, rejected_at, rejected_by,
    last_checked_at, match_evidence, match_method,
    external_card_id, external_card_name
) ON public.pricing_source_card_identity TO service_role;

-- 5) Backfill idempotente, ANTES das triggers (preserva confirmed_at/by) -----
INSERT INTO public.pricing_source_card_identity (
    pricing_card_mapping_id, pricing_source_id, external_card_id, external_card_name,
    match_status, identity_role, match_method, match_evidence, last_checked_at,
    confirmed_at, confirmed_by
)
SELECT
    m.id, m.pricing_source_id, m.external_card_id, m.external_card_name,
    'CONFIRMED', 'PRIMARY', m.match_method, m.match_evidence, m.last_checked_at,
    m.confirmed_at, m.confirmed_by
FROM public.pricing_card_mapping m
WHERE m.match_status = 'CONFIRMED'
  AND NOT EXISTS (
      SELECT 1 FROM public.pricing_source_card_identity i
      WHERE i.pricing_card_mapping_id = m.id
        AND i.identity_role = 'PRIMARY'
        AND i.match_status = 'CONFIRMED'
  );

UPDATE public.pricing_product p
SET pricing_source_card_identity_id = i.id
FROM public.pricing_source_card_identity i
WHERE i.pricing_card_mapping_id = p.pricing_card_mapping_id
  AND i.identity_role = 'PRIMARY'
  AND i.match_status = 'CONFIRMED'
  AND p.pricing_source_card_identity_id IS NULL;

-- 6) Triggers criadas DEPOIS do backfill (regem so o dual-write futuro) ------
CREATE TRIGGER trg_pricing_source_card_identity_set_updated_at
    BEFORE UPDATE ON public.pricing_source_card_identity
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.set_pricing_source_card_identity_decision_authority()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.match_status = 'REJECTED' THEN
            RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_CANNOT_INSERT_AS_REJECTED';
        END IF;
        IF NEW.match_status = 'CONFIRMED' THEN
            NEW.confirmed_at := now();
        END IF;
        RETURN NEW;
    END IF;

    IF OLD.confirmed_at IS NOT NULL AND NEW.confirmed_at IS DISTINCT FROM OLD.confirmed_at THEN
        RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_CONFIRMED_AT_IMMUTABLE';
    END IF;
    IF OLD.confirmed_by IS NOT NULL AND NEW.confirmed_by IS DISTINCT FROM OLD.confirmed_by THEN
        RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_CONFIRMED_BY_IMMUTABLE';
    END IF;
    IF OLD.rejected_at IS NOT NULL AND NEW.rejected_at IS DISTINCT FROM OLD.rejected_at THEN
        RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_REJECTED_AT_IMMUTABLE';
    END IF;
    IF OLD.rejected_by IS NOT NULL AND NEW.rejected_by IS DISTINCT FROM OLD.rejected_by THEN
        RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_REJECTED_BY_IMMUTABLE';
    END IF;

    IF OLD.match_status = 'PENDING' AND NEW.match_status = 'REJECTED' THEN
        RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_CANNOT_REJECT_FROM_PENDING_DIRECTLY';
    END IF;

    IF OLD.match_status = 'PENDING' AND NEW.match_status = 'CONFIRMED' THEN
        NEW.confirmed_at := now();
    ELSIF OLD.match_status = 'CONFIRMED' AND NEW.match_status = 'REJECTED' THEN
        NEW.rejected_at := now();
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.set_pricing_source_card_identity_decision_authority() FROM PUBLIC;

CREATE TRIGGER trg_pricing_source_card_identity_decision_authority
    BEFORE INSERT OR UPDATE ON public.pricing_source_card_identity
    FOR EACH ROW EXECUTE FUNCTION public.set_pricing_source_card_identity_decision_authority();

CREATE OR REPLACE FUNCTION public.validate_pricing_source_card_identity_canonical()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_status text;
    v_role text;
BEGIN
    IF NEW.canonical_identity_id IS NOT NULL THEN
        SELECT match_status, identity_role INTO v_status, v_role
        FROM public.pricing_source_card_identity
        WHERE id = NEW.canonical_identity_id
        FOR SHARE;

        IF v_status IS DISTINCT FROM 'CONFIRMED' OR v_role NOT IN ('PRIMARY', 'ALTERNATE') THEN
            RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_CANONICAL_TARGET_INVALID: canonical=% status=% role=%',
                NEW.canonical_identity_id, v_status, v_role;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.validate_pricing_source_card_identity_canonical() FROM PUBLIC;

CREATE TRIGGER trg_pricing_source_card_identity_validate_canonical
    BEFORE INSERT OR UPDATE OF canonical_identity_id, identity_role, match_status
    ON public.pricing_source_card_identity
    FOR EACH ROW EXECUTE FUNCTION public.validate_pricing_source_card_identity_canonical();

-- Guarda de integridade do alvo -- canonical ja referenciado nao pode virar
-- REJECTED/PENDING/ALIAS; identidade com produto vinculado nao pode virar ALIAS.
CREATE OR REPLACE FUNCTION public.guard_pricing_source_card_identity_target_integrity()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_alias_ref_count int;
  v_product_ref_count int;
BEGIN
    IF NEW.match_status IN ('REJECTED', 'PENDING') OR NEW.identity_role = 'ALIAS' THEN
        SELECT count(*) INTO v_alias_ref_count FROM public.pricing_source_card_identity
        WHERE canonical_identity_id = OLD.id;
        IF v_alias_ref_count > 0 THEN
            RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_CANONICAL_TARGET_REFERENCED: id=% ainda referenciada por % ALIAS(es)',
                OLD.id, v_alias_ref_count;
        END IF;
    END IF;

    IF NEW.identity_role = 'ALIAS' AND OLD.identity_role <> 'ALIAS' THEN
        SELECT count(*) INTO v_product_ref_count FROM public.pricing_product
        WHERE pricing_source_card_identity_id = OLD.id;
        IF v_product_ref_count > 0 THEN
            RAISE EXCEPTION 'PRICING_SOURCE_CARD_IDENTITY_HAS_LINKED_PRODUCT_CANNOT_BECOME_ALIAS: id=% referenciada por % produto(s)',
                OLD.id, v_product_ref_count;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.guard_pricing_source_card_identity_target_integrity() FROM PUBLIC;

CREATE TRIGGER trg_pricing_source_card_identity_guard_target_integrity
    BEFORE UPDATE OF match_status, identity_role ON public.pricing_source_card_identity
    FOR EACH ROW EXECUTE FUNCTION public.guard_pricing_source_card_identity_target_integrity();

CREATE OR REPLACE FUNCTION public.validate_pricing_product_identity_confirmed()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY INVOKER
    SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_status text;
    v_role text;
BEGIN
    IF NEW.pricing_source_card_identity_id IS NOT NULL THEN
        SELECT match_status, identity_role INTO v_status, v_role
        FROM public.pricing_source_card_identity
        WHERE id = NEW.pricing_source_card_identity_id
        FOR SHARE;

        IF v_status IS DISTINCT FROM 'CONFIRMED' OR v_role NOT IN ('PRIMARY', 'ALTERNATE') THEN
            RAISE EXCEPTION 'PRICING_PRODUCT_IDENTITY_NOT_CONFIRMED: identity=% status=% role=%',
                NEW.pricing_source_card_identity_id, v_status, v_role;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.validate_pricing_product_identity_confirmed() FROM PUBLIC;

CREATE TRIGGER trg_pricing_product_validate_identity_confirmed
    BEFORE INSERT OR UPDATE OF pricing_source_card_identity_id ON public.pricing_product
    FOR EACH ROW EXECUTE FUNCTION public.validate_pricing_product_identity_confirmed();

-- 7) Asserções de integridade pos-backfill, embutidas no proprio arquivo
--    fisico -- se algo estiver inconsistente, a migration inteira aborta.
--    Usa contagens dinamicas, nunca numeros fixos.
DO $$
DECLARE
  v_confirmed_mappings int;
  v_identities int;
  v_products_null int;
  v_mismatched int;
  v_bad_pairs int;
  v_identical_ts int;
BEGIN
  SELECT count(*) INTO v_confirmed_mappings FROM pricing_card_mapping WHERE match_status='CONFIRMED';
  SELECT count(*) INTO v_identities FROM pricing_source_card_identity WHERE identity_role='PRIMARY' AND match_status='CONFIRMED';
  IF v_confirmed_mappings <> v_identities THEN
    RAISE EXCEPTION 'ASSERT FALHOU: confirmed_mappings(%) <> identidades PRIMARY/CONFIRMED(%)', v_confirmed_mappings, v_identities;
  END IF;

  SELECT count(*) INTO v_identical_ts
  FROM pricing_source_card_identity i JOIN pricing_card_mapping m ON m.id = i.pricing_card_mapping_id
  WHERE i.identity_role='PRIMARY' AND i.match_status='CONFIRMED' AND m.match_status='CONFIRMED'
    AND i.confirmed_at = m.confirmed_at AND i.confirmed_by = m.confirmed_by;
  IF v_identical_ts <> v_confirmed_mappings THEN
    RAISE EXCEPTION 'ASSERT FALHOU: timestamps historicos identicos(%) <> confirmed_mappings(%)', v_identical_ts, v_confirmed_mappings;
  END IF;

  SELECT count(*) INTO v_products_null FROM pricing_product WHERE pricing_source_card_identity_id IS NULL;
  IF v_products_null <> 0 THEN
    RAISE EXCEPTION 'ASSERT FALHOU: % produtos sem identity apos backfill', v_products_null;
  END IF;

  SELECT count(*) INTO v_mismatched
  FROM pricing_product p JOIN pricing_source_card_identity i ON i.id = p.pricing_source_card_identity_id
  WHERE i.pricing_card_mapping_id <> p.pricing_card_mapping_id;
  IF v_mismatched <> 0 THEN
    RAISE EXCEPTION 'ASSERT FALHOU: % produtos com identity de outra mapping', v_mismatched;
  END IF;

  SELECT count(*) INTO v_bad_pairs FROM pricing_source_card_identity
  WHERE (confirmed_at IS NULL) <> (confirmed_by IS NULL) OR (rejected_at IS NULL) <> (rejected_by IS NULL);
  IF v_bad_pairs <> 0 THEN
    RAISE EXCEPTION 'ASSERT FALHOU: % identidades com pares */_at/_by inconsistentes', v_bad_pairs;
  END IF;

  RAISE NOTICE 'OK: backfill integro -- % mappings = % identidades, timestamps historicos 100%% identicos, zero produto orfao, zero mismatch, zero par inconsistente',
    v_confirmed_mappings, v_identities;
END $$;
