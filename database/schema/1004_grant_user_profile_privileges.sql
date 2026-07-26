/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1004 - Grant User Profile Privileges
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Concede ao role "authenticated" os privilégios de tabela
necessários para que as políticas RLS de public.user_profile
(1003 - user_profile_select_own, user_profile_update_own)
possam de fato ser avaliadas. RLS restringe linhas, mas exige
que o privilégio de tabela já exista — sem o GRANT, o acesso é
negado antes da política ser avaliada (erro 42501).

Regras de Negócio:
- Apenas SELECT e UPDATE são concedidos, espelhando exatamente
  as duas políticas RLS existentes (nenhuma política de INSERT
  ou DELETE existe para authenticated nesta tabela).
- INSERT continua não concedido a authenticated: a criação da
  linha ocorre exclusivamente via handle_new_user(), que roda
  como SECURITY DEFINER com o privilégio do owner da função.
- Nenhum privilégio é concedido a "anon" — user_profile não é
  uma entidade pública neste incremento (ver ADR-020).
================================================================
*/

GRANT SELECT, UPDATE ON public.user_profile TO authenticated;
