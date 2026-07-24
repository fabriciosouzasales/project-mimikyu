-- ============================================================
-- Migration 270 - Create Card Set External Reference MEE
-- Status: MIGRATION (histórica).
-- Cadastra a referência externa de MEE na TCGdex, confirmada via
-- pesquisa real (https://api.tcgdex.net/v2/en/sets/mee):
-- external_set_id = 'mee', cardCount.total = 8 (sem lacunas de
-- numeração), abreviação oficial MEE.
-- metadata já nasce {} (regra da Migration 269 aplicada desde
-- o início).
-- Idempotente via NOT EXISTS.
-- Confirmada executada.
--
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 269-271".
-- ============================================================

BEGIN;

INSERT INTO public.card_set_external_reference (
    card_set_id,
    asset_source_id,
    external_set_id,
    source_url,
    metadata,
    is_active
)
SELECT
    cs.id,
    src.id,
    'mee',
    'https://api.tcgdex.net/v2/en/sets/mee',
    '{}'::jsonb,
    TRUE
FROM public.card_set cs
INNER JOIN public.expansion e
    ON e.id = cs.expansion_id
CROSS JOIN public.asset_source src
WHERE e.code = 'ME'
  AND cs.code = 'MEE'
  AND src.code = 'TCGDEX'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set_external_reference cser
      WHERE cser.card_set_id = cs.id
        AND cser.asset_source_id = src.id
  );

COMMIT;
