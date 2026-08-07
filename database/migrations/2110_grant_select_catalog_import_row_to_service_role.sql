/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2110 - Grant SELECT on catalog_import_row to service_role
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Concede SELECT em public.catalog_import_row a service_role — a
Edge Function revalidate-catalog-import-rows (chamada por
svc_apply_catalog_import_revalidation(), Query 2106) precisa ler
as linhas do job antes de recalculá-las, usando a service_role key
(fora do contexto de RLS de um usuário autenticado).

Regras de Negócio:
- Sem este GRANT, a leitura das linhas pendentes de revalidação
  pela Edge Function falharia silenciosamente (RLS/GRANT nega,
  não lança exceção) — sintoma observado antes da correção:
  "Revalidar tudo" reportava updated_count = 0 mesmo com linhas
  pendentes reais.
- INSERT/UPDATE em catalog_import_row já eram concedidos a
  service_role antes desta Query (o processador de importação
  grava linhas desde a Query 2071) — só o SELECT estava faltando.

Pré-requisitos:
- Query 2070/2071 - Create catalog_import_row Table.
================================================================
*/

GRANT SELECT ON public.catalog_import_row TO service_role;

-- ================================================================
-- Confirmado executado (2026-08-07): information_schema.role_table_
-- grants confirma SELECT concedido a service_role em produção.
-- Corrigiu o sintoma de updated_count = 0 na revalidação.
-- ================================================================
