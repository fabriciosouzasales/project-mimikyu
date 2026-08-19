-- Query 3912 — CONFIRMADO EXECUTADO (Incremento P14.3 — persistência em lotes).
-- Aplicada via Supabase MCP em 2026-08-19.
--
-- Conceder UPDATE restrito por coluna a service_role em pricing_set_mapping
-- e pricing_card_mapping.
--
-- Contexto: introspecção do Incremento P14.3 (persistência em lotes) encontrou uma
-- divergência real entre o comportamento esperado do conector e os privilégios efetivos
-- do banco. A Query 3091 (P8) concedeu apenas INSERT a service_role nessas duas tabelas e
-- revogou UPDATE explicitamente, deixando registrado: "Corrigir um mapeamento (REJECTED ->
-- nova tentativa, etc.) permanece fora de escopo deste incremento e exigiria uma decisão
-- própria no futuro (função SECURITY DEFINER dedicada ou GRANT UPDATE adicional), não
-- decidida aqui." Esta migration é essa decisão, agora que o P14.3 precisa dela: o
-- upsertSetMapping()/upsertCardMapping() de scripts/sync-justtcg-pricing.ts já dependem de
-- um UPDATE bem-sucedido para promover mapeamentos PENDING/NOT_FOUND -> CONFIRMED em uma
-- reexecução, e hoje esse UPDATE falha silenciosamente (o cliente Supabase JS não lança
-- exceção por padrão e o código não checava { error }) — confirmado por teste direto:
-- SET LOCAL ROLE service_role; UPDATE pricing_card_mapping SET match_status = match_status
-- WHERE false; --> ERROR 42501: permission denied for table pricing_card_mapping.
--
-- Escopo deliberadamente restrito por coluna, replicando o mesmo padrão já usado em
-- pricing_sync_run (Query 3080): apenas as colunas que upsertSetMapping()/
-- upsertCardMapping() de fato escrevem em seu payload de UPDATE. Permanecem
-- estruturalmente inalteráveis pelo fluxo normal (nenhum GRANT UPDATE nessas colunas):
-- id, card_id/card_set_id, pricing_source_id, created_at, updated_at. Nenhum GRANT DELETE
-- concedido (histórico permanente, mesmo padrão já usado em todas as tabelas pricing_*).
--
-- Testado transacionalmente (BEGIN/ROLLBACK) antes desta aplicação real: UPDATE nas 8
-- colunas concedidas bem-sucedido; UPDATE em id/card_id/card_set_id/pricing_source_id/
-- created_at/updated_at continua negado (42501); nenhuma linha real alterada durante o
-- teste. Confirmado pós-aplicação via information_schema.column_privileges: exatamente
-- estas 8 colunas têm UPDATE para cada tabela.

GRANT UPDATE (
    match_status,
    match_method,
    match_evidence,
    last_checked_at,
    external_set_id,
    external_set_name,
    confirmed_at,
    confirmed_by
) ON public.pricing_set_mapping TO service_role;

GRANT UPDATE (
    match_status,
    match_method,
    match_evidence,
    last_checked_at,
    external_card_id,
    external_card_name,
    confirmed_at,
    confirmed_by
) ON public.pricing_card_mapping TO service_role;
