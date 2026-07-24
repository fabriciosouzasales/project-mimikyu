-- ============================================================
-- Migration 266 - Create Card Set MEP
-- Status: MIGRATION (histórica).
-- Cadastra o Card Set MEP, set_type = PROMO, release_order = 2.
-- Nome e tamanho usados nesta execução eram estimativas iniciais,
-- corrigidas em seguida pela Migration 267 (tamanho) e por um
-- ajuste de nome não capturado como SQL (ver nota abaixo).
-- Idempotente via NOT EXISTS.
-- Confirmada executada.
--
-- NOTA: o nome foi posteriormente corrigido (confirmado por
-- Fabrício: "Veja que só ajustei o nome mais uma vez") de
-- 'Promos Estrela Negra Megaevolução' (tradução criada durante
-- o cadastro) para o nome oficial exato da TCGdex,
-- 'MEP Black Star Promos' — a instrução UPDATE exata desse ajuste
-- não foi capturada nas informações recebidas. O nome real e
-- atual de card_set.code = 'MEP' é 'MEP Black Star Promos'.
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
    'MEP',
    'Promos Estrela Negra Megaevolução',
    'PROMO',
    2,
    DATE '2025-09-26',
    52,
    52
FROM public.expansion e
WHERE e.code = 'ME'
  AND NOT EXISTS (
      SELECT 1
      FROM public.card_set cs
      WHERE cs.expansion_id = e.id
        AND cs.code = 'MEP'
  );

COMMIT;
