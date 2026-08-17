-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816232703
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3002 - Grant Service Role Select (Pricing P1 Foundation)
Versão......: 1.0
Status......: CANÔNICA (corrige, em versão 1.1, as Queries 3000/3010/3020 —
              GRANT SELECT a service_role já deveria nascer junto da tabela,
              conforme docs/05f-pricing.md v1.1: "service_role: SELECT
              (leitura durante sincronização)". Aplicado aqui como Query
              própria porque as três tabelas já haviam sido criadas; as
              Queries canônicas 3000/3010/3020 serão atualizadas em lugar
              para já nascerem com este GRANT em instalações novas.
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Concede SELECT a service_role em pricing_source, card_condition e
pricing_condition_mapping — leitura necessária para uma futura sincronização
(fora de escopo deste incremento) resolver fonte/condição. Validação de
grants (item 6/12 do Incremento P1) identificou a ausência deste GRANT
antes da conclusão do incremento — corrigido no mesmo ciclo.

Regras de Negócio:
- service_role não recebe INSERT/UPDATE/DELETE nestas três tabelas nesta
  Query — nenhuma função de sincronização é criada neste incremento.
================================================================
*/

GRANT SELECT ON public.pricing_source TO service_role;
GRANT SELECT ON public.card_condition TO service_role;
GRANT SELECT ON public.pricing_condition_mapping TO service_role;
