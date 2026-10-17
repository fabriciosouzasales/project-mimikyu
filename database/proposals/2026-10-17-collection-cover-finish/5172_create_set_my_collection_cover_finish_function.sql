/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5172 - set_my_collection_cover_finish(): grava a cor do
              fichário de uma coleção do próprio usuário
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contrato:
  set_my_collection_cover_finish(p_collection_id uuid, p_finish text)
  RETURNS text  -- acabamento gravado

  - Dono por auth.uid(); coleção alheia ou inexistente → mesma resposta
    (COLLECTION_NOT_FOUND), sem enumerar.
  - Vale para coleção ativa ou arquivada (é aparência, não conteúdo).
  - Idempotente: repetir com o mesmo valor devolve o mesmo valor.
  - Não toca cartas, alocações, locais nem progresso. Compatível com
    validate_collection_structural_identity (só imutáveis de identidade).

Erros: 28000 not_authenticated; 22023 INVALID_FINISH; P0002 COLLECTION_NOT_FOUND.
Segurança: SECURITY DEFINER, search_path '', EXECUTE só authenticated.
Como validar: Query 5831 (Seção 2).
================================================================
*/

begin;

create or replace function public.set_my_collection_cover_finish(
  p_collection_id uuid,
  p_finish        text
)
returns text
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user   uuid := auth.uid();
  v_finish text := lower(btrim(coalesce(p_finish, '')));
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if v_finish not in ('onix', 'vinho', 'floresta', 'marinho', 'caramelo', 'perola') then
    raise exception 'INVALID_FINISH' using errcode = '22023';
  end if;

  update public.collection c
  set cover_finish = v_finish   -- updated_at: trigger trg_collection_set_updated_at
  where c.id = p_collection_id
    and c.owner_user_id = v_user;

  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  return v_finish;
end;
$$;

comment on function public.set_my_collection_cover_finish(uuid, text) is
  'Minhas coleções (Query 5172): grava a cor do fichário de uma coleção do usuário da sessão. Idempotente; não toca cartas.';

revoke all on function public.set_my_collection_cover_finish(uuid, text) from public;
revoke all on function public.set_my_collection_cover_finish(uuid, text) from anon;
grant execute on function public.set_my_collection_cover_finish(uuid, text) to authenticated;

commit;
