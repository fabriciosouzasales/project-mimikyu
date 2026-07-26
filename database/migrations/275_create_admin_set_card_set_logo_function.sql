/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 275 - Create admin_set_card_set_logo Function
Versão......: 1.0
Status......: MIGRATION
Autor.......: Fabrício Sales / Claude
Data........: 2026-07-26

Descrição...:
Cria admin_set_card_set_logo(), função SECURITY DEFINER que é a única via
de escrita autorizada de card_set.logo_storage_path — nenhuma política de
RLS de UPDATE é criada em card_set para este fim (ADR-022, ajuste 3 de
Fabrício). Mesmo padrão de função administrativa vetada já usado em
admin_grant_admin()/admin_revoke_admin() (ADR-021): verifica is_admin()
internamente, search_path vazio, EXECUTE restrito a authenticated.

Regras de Negócio:
- Só um administrador pode chamar esta função (verificado via is_admin()).
- Só é possível gravar logo_storage_path — nenhuma outra coluna de card_set
  é alterada por esta função.
- p_logo_storage_path aceita NULL, para remover/limpar a logo de um Card Set.
- p_logo_storage_path, quando não nulo, não pode ser uma URL absoluta —
  mesma regra já garantida pela constraint ck_card_set_logo_storage_path_not_url
  (Query 273); a função apenas antecipa o erro com uma mensagem mais clara.
- Se p_card_set_id não corresponder a um Card Set existente, a função levanta
  exceção — nunca falha silenciosamente com zero linhas afetadas (checado via
  GET DIAGNOSTICS ... ROW_COUNT).
================================================================
*/

begin;

create or replace function public.admin_set_card_set_logo(
    p_card_set_id uuid,
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
        raise exception 'ADMIN_SET_CARD_SET_LOGO_FORBIDDEN: apenas administradores podem alterar a logo de um Card Set.';
    end if;

    if p_logo_storage_path is not null
       and p_logo_storage_path ~* '^[a-z][a-z0-9+.-]*://' then
        raise exception 'ADMIN_SET_CARD_SET_LOGO_INVALID_PATH: logo_storage_path deve ser um caminho relativo, nunca uma URL absoluta.';
    end if;

    update public.card_set
        set logo_storage_path = p_logo_storage_path,
            updated_at = current_timestamp
        where id = p_card_set_id;

    get diagnostics v_rows_updated = row_count;

    if v_rows_updated <> 1 then
        raise exception 'ADMIN_SET_CARD_SET_LOGO_NOT_FOUND: nenhum Card Set encontrado para o id informado (%).', p_card_set_id;
    end if;
end;
$$;

revoke all on function public.admin_set_card_set_logo(uuid, text) from public;
grant execute on function public.admin_set_card_set_logo(uuid, text) to authenticated;

commit;

-- ================================================================
-- Validação executada e confirmada (2026-07-26):
-- - pg_proc: prosecdef = true, proconfig = {search_path=""}.
-- - has_function_privilege: authenticated pode executar; anon não pode.
-- - Teste de chamada em tempo real (id inexistente) bloqueado pelo
--   classificador automático do ambiente de execução por se parecer com uma
--   ação de escrita — não executado ao vivo; comportamento validado por
--   revisão do corpo da função (GET DIAGNOSTICS ROW_COUNT + RAISE EXCEPTION
--   nos três casos: não-admin, path inválido, Card Set inexistente).
-- ================================================================
