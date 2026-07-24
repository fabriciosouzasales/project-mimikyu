-- ============================================================
-- Migration 269 - Fix Card Set External Reference MEP Metadata
-- Status: MIGRATION (histórica).
-- Padroniza metadata de MEP para {} — os campos anteriormente
-- guardados ali (official_code, external_name, release_date)
-- já existem como colunas relacionais em card_set, e
-- card_count_at_registration ficaria desatualizado rapidamente.
-- Mesmo padrão de todos os demais registros de
-- card_set_external_reference.
-- Confirmada executada.
--
-- Nova regra permanente (STD-001, Seção 3, revisão 1.14):
-- metadata nunca deve duplicar um atributo já coberto por
-- coluna relacional.
--
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 269-271".
-- ============================================================

UPDATE public.card_set_external_reference cser
SET
    metadata = '{}'::jsonb,
    updated_at = CURRENT_TIMESTAMP
FROM public.card_set cs,
     public.asset_source src
WHERE cser.card_set_id = cs.id
  AND cser.asset_source_id = src.id
  AND cs.code = 'MEP'
  AND src.code = 'TCGDEX';
