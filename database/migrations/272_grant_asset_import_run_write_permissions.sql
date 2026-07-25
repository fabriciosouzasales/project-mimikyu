-- Project Mimikyu
-- Query 272 - Grant Asset Import Run Write Permissions
-- Status: CONFIRMADA EXECUTADA ("Success", reconfirmada pela reinvocação
-- bem-sucedida de RUN-20260725-00000081 — PENDING → RUNNING →
-- COMPLETED_WITH_ERRORS, 60/60/0/60, timestamps corretos)
--
-- Causa raiz real: mesmo gap já visto nas Queries 250
-- (card_set_external_reference), 253 (card_external_reference) e 254
-- (Incremento 2 — language/card_asset_type/card_asset/expansion) — RLS
-- habilitado não substitui o GRANT de nível de tabela do PostgreSQL.
--
-- Descoberto ao testar a v2.6.0 de supabase/functions/import-card-assets/
-- index.ts (correção do bug real de asset_import_run nunca transicionar de
-- PENDING — ver docs/05-modelo-de-dados.md, seção Asset Import Run):
-- `transitionImportRunToRunning` falhou com
-- "IMPORT_RUN_TRANSITION_TO_RUNNING_FAILED: permission denied for table
-- asset_import_run" na primeira vez que a função tentou um UPDATE nessa
-- tabela — até então, só SELECT (findImportRun) tinha sido usado.
--
-- Confirmado por consulta direta a information_schema.role_table_grants
-- antes de qualquer correção: service_role tinha apenas SELECT/TRUNCATE/
-- REFERENCES/TRIGGER, nenhum INSERT/UPDATE/DELETE.
--
-- Concede também INSERT (não apenas UPDATE) nesta mesma migration, de forma
-- deliberada: scripts/import-manual-assets.ts (v1.1) passou a criar suas
-- próprias linhas em asset_import_run (createImportRun) para dar
-- rastreabilidade às importações manuais — ainda não executado de verdade
-- (aguardando MEP completa), mas seria o mesmo gap reaparecendo em um
-- segundo ciclo se concedêssemos só UPDATE agora.

begin;

grant insert, update
    on table public.asset_import_run
    to service_role;

commit;
