-- ============================================================
-- Migration 264 - Reorganize ME Release Order
-- Status: MIGRATION (histórica).
-- Reorganiza release_order dos Card Sets existentes da Expansion
-- ME (ME1-ME4/ME2.5), liberando as posições 1 e 2 para MEE/MEP,
-- conforme a convenção da ADR-015 (revisão 1.5): Energia = 1,
-- Promocional = 2, regulares a partir de 3.
-- Executada em duas fases para não violar a constraint
-- uq_card_set_expansion_release_order (UNIQUE (expansion_id, release_order))
-- durante a operação.
-- Confirmada executada e validada contra o Supabase real.
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 263-264", e docs/adr/ADR-015-promotional-card-set-model.md,
-- revisão 1.6.
-- ============================================================

BEGIN;

-- Fase 1: move temporariamente para valores altos, fora de qualquer colisão
UPDATE card_set
SET release_order = release_order + 100
WHERE expansion_id = (
    SELECT id
    FROM expansion
    WHERE code = 'ME'
);

-- Fase 2: define a nova sequência definitiva
UPDATE card_set
SET release_order =
CASE code
    WHEN 'ME1' THEN 3
    WHEN 'ME2' THEN 4
    WHEN 'ME2.5' THEN 5
    WHEN 'ME3' THEN 6
    WHEN 'ME4' THEN 7
END
WHERE expansion_id = (
    SELECT id
    FROM expansion
    WHERE code = 'ME'
);

COMMIT;
