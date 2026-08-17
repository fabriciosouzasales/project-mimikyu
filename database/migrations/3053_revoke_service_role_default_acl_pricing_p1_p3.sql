-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260817010710
-- Recuperado em: 2026-08-17
-- ============================================================================


-- Correção retroativa de segurança (hardening), aplicada no ciclo do Incremento P4 a
-- pedido explícito de Fabrício, após auditoria somente leitura confirmar que as sete
-- tabelas de Pricing implementadas nos Incrementos P1-P3 nunca tiveram TRUNCATE/
-- REFERENCES/TRIGGER/MAINTAIN revogados de service_role — privilégios que pg_default_acl
-- concede automaticamente em tabelas criadas pelo papel postgres (mesmo achado que já
-- motivou a revogação explícita destes quatro privilégios em pricing_product, Query 3050,
-- Incremento P4). Não altera SELECT/INSERT/UPDATE já concedidos, RLS, policies, estrutura,
-- índices ou dados. Cross-cutting: não pertence a nenhum bloco de dez de entidade
-- específica — mesmo padrão de correção transversal já usado em Query 2147 (Catálogo
-- Editorial).
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
    ON public.pricing_source,
       public.card_condition,
       public.pricing_condition_mapping,
       public.pricing_set_mapping,
       public.pricing_card_mapping,
       public.pricing_sync_run,
       public.pricing_sync_run_call
    FROM service_role;
