/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2131 - Revoke anon EXECUTE on admin_update_card()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (via MCP do Supabase, projeto qjfutqujxrbzgrtkpgkg)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-14

Descrição...:
Finding 2 da auditoria de segurança independente do Catálogo
Editorial (GitHub + Supabase de produção): admin_update_card()
(Query 2114) tinha GRANT EXECUTE só para authenticated, sem
nenhum REVOKE explícito de PUBLIC/anon — como Postgres concede
EXECUTE a PUBLIC por padrão na criação de uma function, o grant
implícito a anon nunca havia sido removido. Confirmado pelo
Advisor de segurança do Supabase (get_advisors, categoria
security): anon_security_definer_function_executable apontando
admin_update_card() via /rest/v1/rpc/admin_update_card.

Mesma classe de bug já corrigida em admin_create_card (Query
2115, "descoberta real" documentada no próprio arquivo) e
prevenida desde o início em admin_update_card_set (2048) e
admin_confirm_catalog_import (2082) — este script replica
exatamente o mesmo padrão, sem alterar assinatura nem corpo da
function (só GRANT/REVOKE, sem DROP/CREATE).

Validação (2026-08-14, confirmada nesta mesma sessão):
- has_function_privilege('anon', ..., 'EXECUTE') = false (era
  implicitamente true via PUBLIC antes desta Query).
- has_function_privilege('authenticated', ..., 'EXECUTE') = true
  (preservado, único role que deve executar).
- authenticated não-admin continua bloqueado pela lógica interna
  já existente (IF NOT public.is_admin() THEN RAISE EXCEPTION
  'ADMIN_UPDATE_CARD_FORBIDDEN', inalterada) — defesa em
  profundidade, não depende só do GRANT.
- pg_get_functiondef() após a Query idêntico ao corpo já
  documentado em database/schema/2114_create_admin_update_card_
  function.sql — nenhuma mudança de comportamento.
- Reexecução do Advisor de segurança: admin_update_card() não
  aparece mais em anon_security_definer_function_executable
  (lista caiu de 61 para 60 findings, exatamente o esperado).

Pré-requisitos:
- Query 2114 - Create admin_update_card() Function.
================================================================
*/

REVOKE ALL ON FUNCTION public.admin_update_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_update_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_update_card(UUID, TEXT, INTEGER, INTEGER, UUID, UUID) TO authenticated;

-- ================================================================
-- Confirmado executado (2026-08-14, via apply_migration/MCP do
-- Supabase) e validado: has_function_privilege(anon)=false,
-- has_function_privilege(authenticated)=true, corpo da function
-- inalterado (pg_get_functiondef idêntico), Advisor de segurança
-- sem mais apontar admin_update_card().
-- ================================================================
