/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2113 - Create asset_source catalog_admin_select Policy
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-07

Descrição...:
Cria a política RLS catalog_admin_select em public.asset_source —
complementa o GRANT da Query 2112, liberando a leitura de Fontes
para usuários com is_admin() = true (mesmo padrão de política já
usado em outras tabelas de catálogo administrativo).

Regras de Negócio:
- USING (is_admin()) — sem WITH CHECK, pois a política é
  exclusivamente de leitura (SELECT); escrita em asset_source
  não passa pela UI hoje.
- Sem roles explícitas (polroles = '{-}', ou seja, PUBLIC) — a
  própria condição is_admin() já restringe o acesso; RLS
  permanece habilitado na tabela (pré-requisito para a política
  ter efeito).

Pré-requisitos:
- Query 990 (ou equivalente) - Create asset_source Table (com RLS
  habilitado).
- Query 2112 - Grant SELECT on asset_source to authenticated.
================================================================
*/

CREATE POLICY catalog_admin_select ON public.asset_source
    FOR SELECT
    USING (is_admin());

-- ================================================================
-- Confirmado executado (2026-08-07): pg_policy confirma a política
-- em produção (using_expr = 'is_admin()', sem roles restritas).
-- Combo de Fonte populado corretamente na tela /catalogo/raridades.
-- ================================================================
