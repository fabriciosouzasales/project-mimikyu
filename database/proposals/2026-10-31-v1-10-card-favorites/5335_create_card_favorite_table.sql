/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5335 - Create card_favorite Table (V1-10 Favoritos de cartas)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO no LIVE (V1-10 CONTROLLED LIVE EXECUTION-04, 2026-10-31;
              ledger 20261031213144 `5335_create_card_favorite_table`; enviada via
              apply_migration sem as linhas `begin;`/`commit;` — só este bloco Status difere)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-31

Descrição
  Persistência de Favorite (C-82–C-90 / LDM-70–LDM-78): preferência
  editorial pessoal de um User por uma Card. Binária, independente de
  posse (Inventory/Physical Card), de Collection, de variante e da
  Wishlist. Mesmo desenho da Espécie favorita da Pokédex (Query 6136),
  aplicado à Card.

Desenho
  - PK (user_id, card_id): no máximo um favorito por par User × Card
    (C-87); coluna líder user_id atende "a carta X é favorita?" em lote.
  - ix (user_id, created_at desc, card_id): página "Cartas favoritas",
    mais recentes primeiro, paginada sem ordenar a tabela inteira.
  - ix (card_id): verificação da FK RESTRICT quando o catálogo tenta
    excluir uma Card.
  - user_id → auth.users ON DELETE CASCADE: preferência pessoal, não
    patrimônio (mesma regra da 6136).
  - card_id → card ON DELETE RESTRICT: o favorito nunca some em
    silêncio (C-90: enquanto a Card existir, o favorito permanece). O
    catálogo não exclui uma Card favoritada sem tratar o favorito antes —
    mesmo comportamento dos exemplares físicos.
  - RLS ativa; uma policy de SELECT só das próprias linhas.
  - Grants: authenticated = SELECT (somente as próprias linhas, pela RLS);
    nenhuma escrita direta pela API — a única via de escrita é
    set_card_favorite() (Query 5336). anon/PUBLIC = nenhum.

Resultado esperado
  Tabela com PK, 2 FKs, 2 índices, RLS ativa, 1 policy SELECT.

Como validar: Query 5868 (mesma pasta), Parte 0.
Como reverter: DROP TABLE public.card_favorite; (só antes de haver
favoritos que se queira preservar; 5336 precisa ser removida antes).
================================================================
*/

begin;

create table public.card_favorite (
  user_id    uuid        not null,
  card_id    uuid        not null,
  created_at timestamptz not null default now(),
  constraint pk_card_favorite
    primary key (user_id, card_id),
  constraint fk_card_favorite_user_id
    foreign key (user_id) references auth.users(id)
    on update restrict on delete cascade,
  constraint fk_card_favorite_card_id
    foreign key (card_id) references public.card(id)
    on update restrict on delete restrict
);

create index ix_card_favorite_user_recent
  on public.card_favorite (user_id, created_at desc, card_id);

create index ix_card_favorite_card_id
  on public.card_favorite (card_id);

comment on table public.card_favorite is
  'V1-10 (Query 5335): Favorite — preferência editorial pessoal de um User por uma Card (C-82–C-90). Binária, independente de posse, Collection, variante e Wishlist. Leitura só das próprias linhas (RLS); escrita só via set_card_favorite().';

alter table public.card_favorite enable row level security;

create policy card_favorite_select_own
  on public.card_favorite
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.card_favorite from public;
revoke all on table public.card_favorite from anon;
revoke all on table public.card_favorite from authenticated;
grant select on table public.card_favorite to authenticated;

commit;

-- Como validar (rápido; completo na 5868):
-- select relrowsecurity, (select count(*) from pg_policies where tablename = 'card_favorite') as policies,
--        has_table_privilege('authenticated', 'public.card_favorite', 'INSERT') as auth_insert,
--        has_table_privilege('anon', 'public.card_favorite', 'SELECT') as anon_select
-- from pg_class where oid = 'public.card_favorite'::regclass;
-- Esperado: t | 1 | f | f
