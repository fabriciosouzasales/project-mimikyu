/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2046 - Create admin_set_expansion_logo Function
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-31

Descrição...:
Cria admin_set_expansion_logo(), função SECURITY DEFINER que é a única
via de escrita autorizada de expansion.logo_storage_path — nenhuma
política de RLS de UPDATE é criada em expansion para este fim, mesmo
padrão de admin_set_card_set_logo() (Query 275, ADR-022): verifica
is_admin() internamente, search_path vazio, EXECUTE restrito a
authenticated.

Regras de Negócio:
- Só um administrador pode chamar esta função (verificado via is_admin()).
- Só é possível gravar logo_storage_path — nenhuma outra coluna de
  expansion é alterada por esta função.
- p_logo_storage_path aceita NULL, para remover/limpar a logo de uma
  Expansão.
- p_logo_storage_path, quando não nulo, não pode ser uma URL absoluta —
  mesma regra já garantida pela constraint
  ck_expansion_logo_storage_path_not_url (Query 2045); a função apenas
  antecipa o erro com uma mensagem mais clara.
- Se p_expansion_id não corresponder a uma Expansão existente, a função
  levanta exceção — nunca falha silenciosamente com zero linhas afetadas
  (checado via GET DIAGNOSTICS ... ROW_COUNT).
================================================================
*/

begin;

create or replace function public.admin_set_expansion_logo(
    p_expansion_id uuid,
    p_logo_storage_path text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_rows_updated integer;
begin
    if not public.is_admin() then
        raise exception 'ADMIN_SET_EXPANSION_LOGO_FORBIDDEN: apenas administradores podem alterar a logo de uma Expansão.';
    end if;

    if p_logo_storage_path is not null
       and p_logo_storage_path ~* '^[a-z][a-z0-9+.-]*://' then
        raise exception 'ADMIN_SET_EXPANSION_LOGO_INVALID_PATH: logo_storage_path deve ser um caminho relativo, nunca uma URL absoluta.';
    end if;

    update public.expansion
        set logo_storage_path = p_logo_storage_path,
            updated_at = current_timestamp
        where id = p_expansion_id;

    get diagnostics v_rows_updated = row_count;

    if v_rows_updated <> 1 then
        raise exception 'ADMIN_SET_EXPANSION_LOGO_NOT_FOUND: nenhuma Expansão encontrada para o id informado (%).', p_expansion_id;
    end if;
end;
$$;

revoke all on function public.admin_set_expansion_logo(uuid, text) from public;
grant execute on function public.admin_set_expansion_logo(uuid, text) to authenticated;

commit;

-- ================================================================
-- Validação: aguardando execução por Fabrício. Sugestão de roteiro:
-- - pg_proc: prosecdef = true, proconfig = {search_path=""}.
-- - has_function_privilege: authenticated pode executar; anon não pode.
-- ================================================================
