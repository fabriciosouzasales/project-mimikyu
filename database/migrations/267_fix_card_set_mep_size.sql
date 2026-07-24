-- ============================================================
-- Migration 267 - Fix Card Set MEP Size
-- Status: MIGRATION (histórica).
-- Corrige base_set_size/total_set_size de MEP de 52 (estimativa
-- inicial usada na Migration 266) para 60 — contagem real
-- confirmada via consulta direta ao endpoint público da TCGdex
-- (https://api.tcgdex.net/v2/en/sets/mep, campo cardCount.total),
-- distinta tanto da estimativa inicial (52) quanto do maior
-- localId impresso (080, que possui lacunas de numeração).
-- Confirmada executada.
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 265-268".
-- ============================================================

UPDATE public.card_set cs
SET
    base_set_size = 60,
    total_set_size = 60,
    updated_at = CURRENT_TIMESTAMP
FROM public.expansion e
WHERE e.id = cs.expansion_id
  AND e.code = 'ME'
  AND cs.code = 'MEP';
