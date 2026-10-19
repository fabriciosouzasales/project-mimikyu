/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5207 - set_my_collection_cover_code(): aceita também a coleção Pokédex
Versão......: 1.0 (corpo = 5180 v1.1)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-19 — ledger 20261019034933;
              5845 v1.1 15/15 PASS. Corpo promovido para database/schema/5180_create_set_my_collection_cover_code_function.sql.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-COVER-CUSTOMIZATION-01)

Por quê: decisão do proprietário (2026-10-19) — o fichário da coleção
"Completar a Pokédex" tem as mesmas personalizações da Coleção livre
(imagem da capa e código). Hoje 5180 só aceita Coleção livre.

O que muda (5180 → v1.1): SÓ a regra de elegibilidade. Passa a aceitar
  - Coleção livre: completion_policy NONE e sem Collection Reference
    (como antes), OU
  - Pokédex: completion_policy REFERENCE_POSITION e Collection Reference
    do tipo POKEDEX.
Coleção de Set (STANDARD_SET/MASTER_SET) continua recusada com a mesma
mensagem NOT_FREE_COLLECTION (o frontend já a trata; a capa do Set é a
identidade oficial do Set). Assinatura, retorno, grants, validação de
formato/caminho/arquivo, trava de linha e dono: idênticos.

Não toca cartas, alocações, escopo, vínculos nem progresso.
Como validar: 5845 v1.1.
Como reverter: reaplicar database/schema/5180_create_set_my_collection_cover_code_function.sql (corpo v1.0).
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
