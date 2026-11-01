/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5337 - get_my_favorite_collection_count(): coleções com
              cartas favoritas (V1-10 — indicador da página Cartas favoritas)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (CONTROLLED LIVE EXECUTION-11, 2026-10-31;
              ledger 20261031224148; md5(prosrc) LIVE 56e50520… = arquivo; enviada via
              apply_migration sem as linhas `begin;`/`commit;` — só este bloco Status difere)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Por que existe
  O quarto indicador da página Cartas favoritas é "Coleções com favoritas":
  quantas coleções distintas têm pelo menos um exemplar físico de uma carta
  favoritada pelo usuário. Nenhuma leitura existente cruza card_favorite
  (5335) com collection_allocation (5040); e card_variant / collection_allocation
  não são legíveis pelo usuário fora das RPCs. Função aditiva, só leitura.

Contrato (decisão do proprietário, CORRECTION-09)
  - Conta collection_id distintos (uma coleção com dez exemplares favoritos
    conta uma vez; a mesma carta favorita em três coleções conta nas três).
  - Só cartas cujo card_id está nos favoritos do usuário da sessão.
  - Vínculo efetivo: exemplar físico alocado na coleção (collection_allocation).
    Carta favorita só no acervo, sem coleção, não conta; tipo, Set ou objetivo
    da coleção não contam (nada é inferido).
  - Coleções vazias ou sem favoritas não contam.

Regras propostas (explicitadas antes da implementação)
  - Arquivadas: FORA. Mesmo critério da estante principal de Minhas coleções
    (get_my_collections, p_include_archived = false — 5182) e do indicador
    anterior; coleção arquivada é só leitura e não aparece na estante.
  - Compartilhadas com você: FORA. Só coleções do próprio usuário
    (collection.owner_user_id = auth.uid()). Os exemplares de uma coleção
    compartilhada são do acervo de outra pessoa (C-157 — os agregados de
    cartas da Biblioteca também excluem as compartilhadas). Como a 5042 exige
    que o exemplar alocado seja do dono da coleção, "coleção do usuário" e
    "exemplar do usuário" coincidem.
  - Carta favorita desativada no catálogo: FORA, coerente com o indicador
    "Cartas favoritas" (get_my_favorite_cards só lista cartas ativas).

Desenho
  - SECURITY DEFINER (card_variant e collection_allocation são restritas por
    RLS), search_path '', identidade só de auth.uid() (28000 sem sessão),
    STABLE, EXECUTE só authenticated.
  - Uma única consulta: parte das coleções ACTIVE do usuário
    (ix (owner_user_id, lifecycle_status), 5030) e, por coleção, um EXISTS que
    percorre as alocações (ix (collection_id), 5040) → exemplar (PK) →
    variante (PK) → favorito (PK (user_id, card_id), 5335) → carta (PK). Para
    no primeiro exemplar favorito de cada coleção. Sem N+1, sem varrer o
    acervo fora das coleções, custo limitado às alocações do próprio usuário.

Resultado esperado
  Função criada; 5869 GATE PASS.
Como validar: Query 5869 (mesma pasta).
Como reverter: DROP FUNCTION public.get_my_favorite_collection_count();
================================================================
*/

begin;

create or replace function public.get_my_favorite_collection_count()
returns integer
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user  uuid := auth.uid();
  v_count integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select count(*)::integer into v_count
  from public.collection c
  where c.owner_user_id = v_user
    and c.lifecycle_status = 'ACTIVE'
    and exists (
      select 1
      from public.collection_allocation ca
      join public.physical_card pc on pc.id = ca.physical_card_id
      join public.card_variant cv  on cv.id = pc.card_variant_id
      join public.card_favorite f  on f.user_id = v_user and f.card_id = cv.card_id
      join public.card k           on k.id = f.card_id and k.is_active
      where ca.collection_id = c.id
    );

  return v_count;
end;
$$;

comment on function public.get_my_favorite_collection_count() is
  'V1-10 (Query 5337): quantas coleções ativas do usuário da sessão têm pelo menos um exemplar físico alocado de uma carta favoritada (ativa). Arquivadas e compartilhadas com você ficam fora.';

revoke all on function public.get_my_favorite_collection_count() from public;
revoke all on function public.get_my_favorite_collection_count() from anon;
grant execute on function public.get_my_favorite_collection_count() to authenticated;

commit;
