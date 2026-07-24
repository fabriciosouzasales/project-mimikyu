-- ============================================================
-- Migration 271 - Fix Card Set MEE Release Date
-- Status: MIGRATION (histórica).
-- Corrige card_set.release_date de MEE de 2025-09-26 (herdado
-- da Migration 265) para 2025-09-25, conforme confirmado pela
-- TCGdex (releaseDate real do set 'mee') e por Fabrício.
-- Confirmada executada.
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 269-271".
-- ============================================================

UPDATE public.card_set cs
SET
    release_date = DATE '2025-09-25',
    updated_at = CURRENT_TIMESTAMP
FROM public.expansion e
WHERE e.id = cs.expansion_id
  AND e.code = 'ME'
  AND cs.code = 'MEE';
