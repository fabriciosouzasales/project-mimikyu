-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817195051
-- Recuperado em: 2026-08-17
-- ============================================================================


-- Query 3082 — Add confirmed_by column to pricing_sync_run
-- Objetivo: registrar, na própria execução, qual admin_user confirmou o piloto/sync run
-- (preparação para a Query 3083, que valida esse UUID via trigger BEFORE INSERT —
-- substitui a checagem antiga por SELECT direto em admin_user, que o service_role
-- não tem privilégio para fazer, e que o ADR-021 já registra como padrão indesejado
-- caso fosse exposta como função RPC com parâmetro UUID livre).
-- Sem FK para admin_user — mesmo precedente já usado em
-- pricing_set_mapping.confirmed_by / pricing_card_mapping.confirmed_by (UUID solto,
-- sem FK, para não impedir a auditoria de sobreviver a uma futura revogação do admin).
-- Tabela vazia no momento desta migration — NOT NULL direto, sem necessidade de
-- backfill/DEFAULT.

ALTER TABLE public.pricing_sync_run
    ADD COLUMN confirmed_by UUID NOT NULL;

COMMENT ON COLUMN public.pricing_sync_run.confirmed_by IS
    'UUID do admin_user que confirmou esta execução — validado por trigger BEFORE INSERT (ver Query 3083), nunca por função RPC com parâmetro UUID livre (ADR-021).';
