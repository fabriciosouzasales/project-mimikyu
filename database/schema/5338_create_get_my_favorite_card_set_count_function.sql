/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5338 - get_my_favorite_card_set_count(): Card Sets distintos
              das cartas favoritas (V1-10 — 4º indicador de Cartas favoritas)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (CONTROLLED LIVE EXECUTION-15, 2026-10-31;
              ledger 20261031230439; md5(prosrc) LIVE 9659f61d… = arquivo; enviada via
              apply_migration sem as linhas `begin;`/`commit;` — só este bloco Status difere)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Por que existe
  Correção de requisito (CORRECTION-13): o 4º indicador é "Card Sets — com
  cartas favoritas", ou seja, quantos Card Sets distintos têm pelo menos uma
  carta favoritada pelo usuário. Não é "coleções com favoritas" (5337, que
  continua no LIVE sem consumidor). Nenhuma leitura existente devolve a
  contagem: get_my_favorite_cards (5336) traz card_set_code por página e
  exigiria paginar todas as favoritas no cliente; card não é legível pelo
  usuário fora das RPCs (RLS do catálogo).

Contrato
  - Conta card_set_id distintos (vínculo canônico card.card_set_id, NOT NULL,
    FK card_set — Query 140), nunca o código textual do Set.
  - Só favoritos do usuário da sessão (card_favorite.user_id = auth.uid()).
  - Só cartas ativas (k.is_active), a mesma semântica da listagem 5336.
  - Independe de posse, Inventory, Physical Card, Collection ou Allocation.
  - Sem favoritas: 0.

Desenho
  - SECURITY DEFINER (card é restrita por RLS), search_path '', identidade só
    de auth.uid() (28000 sem sessão), STABLE, EXECUTE só authenticated.
  - Uma consulta: favoritos do usuário pelo prefixo da PK (user_id, card_id)
    (5335) → carta pela PK (140). Custo proporcional ao número de favoritas
    do próprio usuário; nenhuma tabela de acervo ou coleção é lida.

Resultado esperado
  Função criada; 5870 GATE PASS.
Como validar: Query 5870 (mesma pasta).
Como reverter: DROP FUNCTION public.get_my_favorite_card_set_count();
================================================================
*/

begin;

create or replace function public.get_my_favorite_card_set_count()
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

  select count(distinct k.card_set_id)::integer into v_count
  from public.card_favorite f
  join public.card k on k.id = f.card_id and k.is_active
  where f.user_id = v_user;

  return v_count;
end;
$$;

comment on function public.get_my_favorite_card_set_count() is
  'V1-10 (Query 5338): quantos Card Sets distintos (card.card_set_id) têm pelo menos uma carta ativa favoritada pelo usuário da sessão. Independe de posse e de coleção.';

revoke all on function public.get_my_favorite_card_set_count() from public;
revoke all on function public.get_my_favorite_card_set_count() from anon;
grant execute on function public.get_my_favorite_card_set_count() to authenticated;

commit;
