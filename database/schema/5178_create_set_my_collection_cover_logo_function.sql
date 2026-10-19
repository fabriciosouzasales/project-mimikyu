/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5178 - set_my_collection_cover_logo(): define ou remove a
              imagem da placa de uma Coleção livre do próprio usuário
              (FREE-COLLECTION-COVER-LOGO-01)
Versão......: 1.2 (5206: aceita também a coleção Pokédex). v1.1 READINESS-01: dono do arquivo por owner_id, com owner como reserva
Status......: v1.2 CONFIRMADO EXECUTADO no LIVE em 2026-10-19 pela 5206
              (autorização de Fabrício) — ledger 20261019034918; 5845 v1.1 15/15 PASS;
              corpo = LIVE (md5 de prosrc 5868fb1c8de760787d1128ac20a09507).
              Versão anterior: CONFIRMADO EXECUTADO no LIVE em 2026-10-18 (autorização
              de Fabrício) — ledger 20261018001031; 5833 v1.2 25/25 PASS
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-17

Contrato:
  set_my_collection_cover_logo(p_collection_id uuid, p_path text)
  RETURNS TABLE(cover_logo_path text, previous_path text)

  - p_path NULL → remove a imagem (placa volta ao nome da coleção).
  - p_path informado precisa:
      * começar por '<auth.uid()>/<p_collection_id>/' (a pasta é do dono
        e da coleção certa — nenhum arquivo de outra coleção ou pessoa);
      * existir em storage.objects no bucket 'collection-cover' enviado
        pelo próprio dono. Dono = owner_id (texto, coluna atual do Storage)
        ou owner (uuid, legada) — no LIVE as duas são preenchidas e iguais
        em 100% dos arquivos enviados por usuários (READINESS-01, leitura
        de 2026-10-17); conferir as duas mantém a regra se o Storage
        deixar de preencher a legada;
      * casar o formato do CHECK de 5177.
  - Coleção livre (completion_policy NONE e sem Collection Reference) ou,
    desde a v1.2 (5206), Pokédex (REFERENCE_POSITION + referência POKEDEX):
    coleção de Set continua com a identidade do Set.
  - Dono por auth.uid(); coleção alheia ou inexistente → mesma resposta
    (COLLECTION_NOT_FOUND), sem enumerar.
  - Vale para coleção ativa ou arquivada (é aparência, como a cor — 5172).
  - Idempotente: repetir com o mesmo caminho devolve o mesmo resultado.
  - Devolve o caminho anterior para o cliente apagar o arquivo antigo
    DEPOIS de a troca estar gravada (nunca antes). Esta função não apaga
    arquivos: nada é perdido se o cliente falhar no meio.
  - Não toca cartas, alocações, locais, referência nem progresso.

Erros: 28000 not_authenticated; 22023 INVALID_COVER_PATH;
       P0002 COLLECTION_NOT_FOUND; 55000 NOT_FREE_COLLECTION;
       P0002 COVER_FILE_NOT_FOUND.
Segurança: SECURITY DEFINER, search_path '', EXECUTE só authenticated.
Como validar: Query 5833 (Seção 3).
Como reverter: drop function public.set_my_collection_cover_logo(uuid, text).
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
