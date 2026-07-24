-- ============================================================
-- Migration 265 - Create Card Set MEE
-- Status: MIGRATION (histórica).
-- Cadastra o Card Set MEE (Cartas de Energia Básica Megaevolução),
-- set_type = ENERGY, release_order = 1, dados editoriais confirmados
-- por fontes oficiais da Pokémon (sem referência externa TCGdex
-- equivalente encontrada nesta revisão).
-- Idempotente via NOT EXISTS.
-- Confirmada executada.
--
-- NOTA: após esta execução, o nome foi ajustado (confirmado por
-- diálogo direto com Fabrício) de 'Cartas de Energia Básica
-- Megaevolução' para 'Energia Básica Megaevolução' — a instrução
-- UPDATE exata desse ajuste não foi capturada nas informações
-- recebidas. O nome real e atual de card_set.code = 'MEE' é
-- 'Energia Básica Megaevolução'.
--
-- Ver docs/05-modelo-de-dados.md, seção Set/Card Set,
-- "Migration 265-268", e docs/adr/ADR-015-promotional-card-set-model.md,
-- revisão 1.7.
-- ============================================================

BEGIN;

INSERT INTO public.card_set (
    expansion_id,
    code,
    name,
    set_type,
    release_order,
    release_date,
    base_set_size,
    total_set_size
)
SELECT
    e.id,
    'MEE',
    'Cartas de Energia Básica Megaevolução',
    'ENERGY',
    1,
    DATE '2025-09-26',
    8,
    8
FROM public.expansion e
WHERE e.code = 'ME'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set cs
      WHERE cs.expansion_id = e.id
        AND cs.code = 'MEE'
  );

COMMIT;
