/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5164 - get_registrable_languages(): idiomas aceitos no
              cadastro de cartas de Meu acervo
              (INVENTORY-LANGUAGE-READ-01)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-17
              (autorização de Fabrício; ledger 20261017033443;
              corpo LIVE = arquivo, md5 de prosrc a8046bb7…)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contexto (bloqueio real, MY-INVENTORY-ACTIONS-01):
As RPCs de registro (5150/5155 B1, 5157 B2) e o Preview (5158) exigem
language_id. public.language está sob a RLS do Catálogo Editorial
(ADR-022, policy catalog_admin_select): um colecionador comum lê ZERO
linhas e não há leitura customer-facing de idiomas com id. Resultado:
"Adicionar cartas" e "Adicionar um Set inteiro" só funcionam para o
administrador.

Solução mínima (mesmo padrão de 5159–5163 e de search_cards/ADR-030):
uma leitura SECURITY DEFINER, estreita, que expõe só o necessário para
o seletor de idioma — sem tocar na RLS de public.language e sem abrir
o catálogo administrativo.

Contrato:
  get_registrable_languages()
  RETURNS TABLE(language_id uuid, code text, name text,
                language_order integer)

- Só idiomas ATIVOS (is_active), na ordem editorial (language_order,
  code). O cadastro continua validando o idioma no próprio banco
  (5153 §6.3); esta leitura não altera regra de domínio — só oferece
  na interface os idiomas vigentes do catálogo.
- Colunas administrativas fora (native_name, is_active, timestamps).
- Dado de referência, igual para todos os usuários: sem dono, sem
  enumeração de dados de terceiros.

Segurança: SECURITY DEFINER, STABLE, search_path '', auth.uid()
obrigatório (28000), EXECUTE só para authenticated (revogado de
PUBLIC e anon). Volume: dezenas de linhas no máximo (hoje 2).

Como validar: Query 5828.
================================================================
*/

begin;

create or replace function public.get_registrable_languages()
returns table (
  language_id    uuid,
  code           text,
  name           text,
  language_order integer
)
language plpgsql
security definer
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  return query
  select l.id, l.code, l.name, l.language_order
  from public.language l
  where l.is_active
  order by l.language_order, l.code;
end;
$$;

comment on function public.get_registrable_languages() is
  'Meu acervo (Query 5164): idiomas ativos aceitos no cadastro de cartas — id, código, nome e ordem. Sem colunas administrativas. Exige auth.uid().';

revoke all on function public.get_registrable_languages() from public;
revoke all on function public.get_registrable_languages() from anon;
grant execute on function public.get_registrable_languages() to authenticated;

commit;
