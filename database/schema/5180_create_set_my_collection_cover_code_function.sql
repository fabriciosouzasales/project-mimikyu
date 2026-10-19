/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5180 - set_my_collection_cover_code(): define ou remove o
              Código opcional de uma Coleção livre do próprio usuário
              (FREE-COLLECTION-COVER-CODE-01)
Versão......: 1.1 (5207: aceita também a coleção Pokédex)
Status......: v1.1 CONFIRMADO EXECUTADO no LIVE em 2026-10-19 pela 5207
              (autorização de Fabrício) — ledger 20261019034933; 5845 v1.1 15/15 PASS;
              corpo = LIVE (md5 de prosrc d0d8cbfa517b9da3728a55af47de21cb).
              Versão anterior: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018005411; 5834 v1.0 21/21 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-18

Contrato:
  set_my_collection_cover_code(p_collection_id uuid, p_code text)
  RETURNS text  -- código gravado (NULL = sem código)

  - p_code NULL ou vazio → remove o código (campo opcional).
  - Normaliza: tira espaços nas pontas e passa a maiúsculas; precisa
    casar ^[A-Z0-9]{2,6}$ (mesmo formato do CHECK de 5179).
  - Coleção livre (completion_policy NONE e sem Collection Reference) ou,
    desde a v1.1 (5207), Pokédex (REFERENCE_POSITION + referência POKEDEX):
    a coleção de Set mostra o código do próprio Set.
  - Dono por auth.uid(); coleção alheia ou inexistente → mesma resposta
    (COLLECTION_NOT_FOUND), sem enumerar.
  - Vale para coleção ativa ou arquivada (é aparência — como 5172/5178).
  - Idempotente: repetir com o mesmo valor devolve o mesmo valor. Por
    isso a criação pode chamar 5175 e, em seguida, esta função: um retry
    da criação reaproveita a coleção (5175) e regrava o mesmo código.
  - Não toca cartas, alocações, locais, referência nem progresso.

Erros: 28000 not_authenticated; 22023 INVALID_COVER_CODE;
       P0002 COLLECTION_NOT_FOUND; 55000 NOT_FREE_COLLECTION.
Segurança: SECURITY DEFINER, search_path '', EXECUTE só authenticated.
Como validar: Query 5834 (Seção 3).
Como reverter: drop function public.set_my_collection_cover_code(uuid, text).
================================================================
*/

begin;

create or replace function public.set_my_collection_cover_code(
  p_collection_id uuid,
  p_code          text
)
returns text
language plpgsql
security definer
volatile
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_code text := nullif(upper(btrim(coalesce(p_code, ''))), '');
  v_free boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if v_code is not null and v_code !~ '^[A-Z0-9]{2,6}$' then
    raise exception 'INVALID_COVER_CODE' using errcode = '22023';
  end if;

  select ((c.completion_policy = 'NONE'
           and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
          or (c.completion_policy = 'REFERENCE_POSITION'
              and exists (select 1 from public.collection_reference cr
                          where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')))
    into v_free
  from public.collection c
  where c.id = p_collection_id
    and c.owner_user_id = v_user
  for update;

  if not found then
    raise exception 'COLLECTION_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not v_free then
    raise exception 'NOT_FREE_COLLECTION' using errcode = '55000';
  end if;

  update public.collection c
  set cover_code = v_code   -- updated_at: trigger trg_collection_set_updated_at
  where c.id = p_collection_id
    and c.owner_user_id = v_user;

  return v_code;
end;
$$;

comment on function public.set_my_collection_cover_code(uuid, text) is
  'Coleção livre e Pokédex (Query 5180, v1.1 pela 5207): define/remove o Código opcional mostrado na capa. Coleção de Set continua recusada (NOT_FREE_COLLECTION). Normaliza para maiúsculas; idempotente; não toca cartas.';

revoke all on function public.set_my_collection_cover_code(uuid, text) from public;
revoke all on function public.set_my_collection_cover_code(uuid, text) from anon;
grant execute on function public.set_my_collection_cover_code(uuid, text) to authenticated;

commit;
