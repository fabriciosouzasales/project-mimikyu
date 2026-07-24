-- ============================================================
-- Migration 263 - Add ENERGY to Card Set Type
-- Status: MIGRATION (histórica) — incorporada à versão canônica
-- de `120 - Create Card Set Table` a partir da v2.1.
-- Confirmada executada e validada contra o Supabase real.
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 263-264", e docs/adr/ADR-015-promotional-card-set-model.md,
-- revisão 1.6.
-- ============================================================

BEGIN;

ALTER TABLE public.card_set
    DROP CONSTRAINT ck_card_set_type;

ALTER TABLE public.card_set
    ADD CONSTRAINT ck_card_set_type
    CHECK (
        set_type IN (
            'REGULAR',
            'SPECIAL',
            'PROMO',
            'ENERGY'
        )
    );

COMMIT;
