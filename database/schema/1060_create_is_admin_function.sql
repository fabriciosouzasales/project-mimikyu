/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 1060 - Create is_admin() Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Function SECURITY DEFINER que verifica se o usuário autenticado
da própria sessão é administrador. Não aceita parâmetro de
usuário — nenhum usuário pode consultar o status administrativo
de outro UUID (ajuste solicitado por Fabrício antes da
implementação, ver ADR-021).

Regras de Negócio:
- SET search_path = '' e referência totalmente qualificada
  (public.admin_user), mesmo padrão de handle_new_user() e
  username_available().
- EXECUTE revogado de PUBLIC, concedido apenas a authenticated.
================================================================
*/

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.admin_user WHERE id = auth.uid()
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
