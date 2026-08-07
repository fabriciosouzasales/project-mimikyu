/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2112 - Grant SELECT on asset_source to authenticated
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Concede SELECT em public.asset_source a authenticated — a tela
/catalogo/raridades ("Resolver raridade") precisa listar as Fontes
existentes (ex. TCGDEX) no formulário de mapeamento
(admin_create_rarity_external_mapping(), Query 2101), lido
diretamente pelo cliente autenticado via PostgREST.

Regras de Negócio:
- Sem este GRANT, a combo de Fonte na UI ficaria vazia mesmo com
  RLS liberado pela Query 2113 (GRANT e RLS são checados em
  conjunto — RLS restringe linhas visíveis, GRANT autoriza a
  operação em si; faltando qualquer um dos dois, o resultado é o
  mesmo: nenhuma linha visível).

Pré-requisitos:
- Query 990 (ou equivalente) - Create asset_source Table.
================================================================
*/

GRANT SELECT ON public.asset_source TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-07): information_schema.role_table_
-- grants confirma SELECT concedido a authenticated em produção.
-- Combo de Fonte populado corretamente na tela /catalogo/raridades.
-- ================================================================
