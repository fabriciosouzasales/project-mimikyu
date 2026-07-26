/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2802 - Validate Card is_active
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Validação de public.card.is_active (Query 2020): coluna, tipo,
default e estado real das 927 Cards existentes (esperado: todas
ativas, sem backfill necessário).
================================================================
*/

-- 1. Coluna, tipo, nulidade, default
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'card' AND column_name = 'is_active';

-- 2. Estado real (esperado: 927/927 ativas)
SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE is_active) AS ativas
FROM public.card;

-- 3. uq_card_card_set_collector_number intacta (não alterada por esta Query)
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'public.card'::regclass
  AND conname = 'uq_card_card_set_collector_number';

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
-- - is_active: boolean, NOT NULL, default true.
-- - 927/927 Cards ativas (nenhuma perda, nenhum backfill necessário).
-- - uq_card_card_set_collector_number inalterada.
-- ================================================================
