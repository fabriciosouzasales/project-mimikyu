/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5206 - set_my_collection_cover_logo(): aceita também a coleção Pokédex
Versão......: 1.0 (corpo = 5178 v1.1)
Status......: CONFIRMADO EXECUTADO no LIVE em 2026-10-19 — ledger 20261019034918;
              5845 v1.1 15/15 PASS. Corpo promovido para database/schema/5178_create_set_my_collection_cover_logo_function.sql.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-19 (POKEDEX-COVER-CUSTOMIZATION-01)

Por quê: decisão do proprietário (2026-10-19) — o fichário da coleção
"Completar a Pokédex" tem as mesmas personalizações da Coleção livre
(imagem da capa e código). Hoje 5178 só aceita Coleção livre.

O que muda (5178 → v1.1): SÓ a regra de elegibilidade. Passa a aceitar
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
Como reverter: reaplicar database/schema/5178_create_set_my_collection_cover_logo_function.sql (corpo v1.0).
================================================================
*/

begin;

create or replace function public.set_my_collection_cover_logo(
  p_collection_id uuid,
  p_path          text
)
returns table (
  cover_logo_path text,
  previous_path   text
)
language plpgsql
security definer
volatile
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user     uuid := auth.uid();
  v_path     text := nullif(btrim(coalesce(p_path, '')), '');
  v_prev     text;
  v_free     boolean;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if p_collection_id is null then
    raise exception 'INVALID_COVER_PATH' using errcode = '22023';
  end if;

  -- Trava a linha da coleção do dono (troca concorrente da capa serializa aqui).
  select c.cover_logo_path,
         ((c.completion_policy = 'NONE'
           and not exists (select 1 from public.collection_reference cr where cr.collection_id = c.id))
          or (c.completion_policy = 'REFERENCE_POSITION'
              and exists (select 1 from public.collection_reference cr
                          where cr.collection_id = c.id and cr.reference_kind = 'POKEDEX')))
    into v_prev, v_free
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

  if v_path is not null then
    if left(v_path, 74) <> v_user::text || '/' || p_collection_id::text || '/'
       or v_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(png|jpg|webp)$' then
      raise exception 'INVALID_COVER_PATH' using errcode = '22023';
    end if;

    if not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'collection-cover'
        and o.name = v_path
        and (o.owner_id = v_user::text or o.owner = v_user)
    ) then
      raise exception 'COVER_FILE_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  update public.collection c
  set cover_logo_path = v_path   -- updated_at: trigger trg_collection_set_updated_at
  where c.id = p_collection_id
    and c.owner_user_id = v_user;

  return query
  select v_path,
         case when v_prev is distinct from v_path then v_prev end;
end;
$$;

comment on function public.set_my_collection_cover_logo(uuid, text) is
  'Coleção livre e Pokédex (Query 5178, v1.1 pela 5206): define/remove a imagem da placa do fichário, a partir de arquivo já enviado pelo dono ao bucket collection-cover. Coleção de Set continua recusada (NOT_FREE_COLLECTION). Devolve o caminho anterior para limpeza pelo cliente. Não toca cartas.';

revoke all on function public.set_my_collection_cover_logo(uuid, text) from public;
revoke all on function public.set_my_collection_cover_logo(uuid, text) from anon;
grant execute on function public.set_my_collection_cover_logo(uuid, text) to authenticated;

commit;
