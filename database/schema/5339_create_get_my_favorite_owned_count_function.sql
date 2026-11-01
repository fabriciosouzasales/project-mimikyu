/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5339 - get_my_favorite_owned_count(): cartas favoritas que o
              usuário possui (V1-10 — 3º indicador "No meu acervo")
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (CONTROLLED EXECUTION-20, 2026-10-31; ledger
              20261031233429; md5(prosrc) LIVE 3bade316… = arquivo; enviada via
              apply_migration sem as linhas `begin;`/`commit;` — só este bloco Status difere)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Por que existe
  Nenhuma leitura existente cruza favoritos (card_id, 5335) com o acervo
  (physical_card → card_variant.card_id). As leituras do Acervo (5159–5162)
  agrupam por variante + idioma e são paginadas; percorrê-las no frontend
  para intersectar com os favoritos seria varrer o acervo inteiro.
  card_variant e physical_card não são legíveis fora das RPCs.

Contrato
  - Conta card_id distintos favoritados pelo usuário da sessão para os quais
    existe pelo menos um physical_card no Inventory do próprio usuário
    (inventory.owner_user_id = auth.uid(), 1:1 — 5000).
  - Várias cópias, variantes ou idiomas da mesma carta contam uma vez
    (a unidade é a linha de card_favorite, PK (user_id, card_id)).
  - Independe de Collection, Binder ou Storage: nenhuma dessas tabelas é lida.
  - Exemplares de outros usuários nunca contam; coleções compartilhadas não
    são consultadas (a posse vem só do Inventory do próprio usuário).
  - Só cartas ativas (k.is_active), coerente com 5336/5338.
  - Sem Inventory ou sem favoritas: 0.

Desenho
  - SECURITY DEFINER (card, card_variant e physical_card restritos por RLS),
    search_path '', identidade só de auth.uid() (28000), STABLE, EXECUTE só
    authenticated.
  - Inventory resolvido uma vez (UNIQUE owner_user_id). Uma consulta:
    favoritos pelo prefixo da PK (user_id) → carta pela PK → EXISTS por
    card_variant (UNIQUE (card_id, variant_type_id) — 160) e physical_card
    (ix_physical_card_inventory_variant (inventory_id, card_variant_id) —
    5010). Para no primeiro exemplar. Custo proporcional às favoritas.

Resultado esperado: função criada; 5871 GATE PASS.
Como validar: Query 5871 (mesma pasta).
Como reverter: DROP FUNCTION public.get_my_favorite_owned_count();
================================================================
*/

begin;

create or replace function public.get_my_favorite_owned_count()
returns integer
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_user      uuid := auth.uid();
  v_inventory uuid;
  v_count     integer;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select i.id into v_inventory
  from public.inventory i
  where i.owner_user_id = v_user;

  if v_inventory is null then
    return 0;
  end if;

  select count(*)::integer into v_count
  from public.card_favorite f
  join public.card k on k.id = f.card_id and k.is_active
  where f.user_id = v_user
    and exists (
      select 1
      from public.card_variant cv
      join public.physical_card pc
        on pc.inventory_id = v_inventory
       and pc.card_variant_id = cv.id
      where cv.card_id = f.card_id
    );

  return v_count;
end;
$$;

comment on function public.get_my_favorite_owned_count() is
  'V1-10 (Query 5339): quantas cartas ativas favoritadas pelo usuário da sessão têm pelo menos um exemplar físico no Inventory do próprio usuário. Cópias, variantes e idiomas contam uma vez; independe de coleção.';

revoke all on function public.get_my_favorite_owned_count() from public;
revoke all on function public.get_my_favorite_owned_count() from anon;
grant execute on function public.get_my_favorite_owned_count() to authenticated;

commit;
