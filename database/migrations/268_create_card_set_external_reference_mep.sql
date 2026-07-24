-- ============================================================
-- Migration 268 - Create Card Set External Reference MEP
-- Status: MIGRATION (histórica).
-- Cadastra a referência externa de MEP na TCGdex, seguindo o
-- mesmo padrão já usado para ME1-ME4 (Query 910): external_set_id
-- exatamente como a TCGdex o registra ('mep', sem invenção).
-- Idempotente via NOT EXISTS.
-- Confirmada executada.
--
-- NOTA: MEE deliberadamente NÃO recebe uma referência externa
-- equivalente nesta revisão — nenhuma fonte oficial com
-- external_set_id confirmado foi encontrada para MEE. Isso é
-- comportamento intencional da arquitetura (existência editorial
-- de um card_set é independente de ele já ter uma referência
-- externa confirmada), não uma pendência esquecida.
--
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 265-268".
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
    'mep',
    'https://api.tcgdex.net/v2/en/sets/mep',
    jsonb_build_object(
        'official_code', 'MEP',
        'external_name', 'MEP Black Star Promos',
        'release_date', '2025-09-26',
        'card_count_at_registration', 60
    ),
    TRUE
FROM public.card_set cs
INNER JOIN public.expansion e
    ON e.id = cs.expansion_id
CROSS JOIN public.asset_source src
WHERE e.code = 'ME'
  AND cs.code = 'MEP'
  AND src.code = 'TCGDEX'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set_external_reference cser
      WHERE cser.card_set_id = cs.id
        AND cser.asset_source_id = src.id
  );

COMMIT;
