/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 5345 - Create card_wishlist_entry Table (V1-11 W1 Lista de desejos)
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO (V1-11 W1 IMPLEMENTATION-01, 2026-11-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-11-01

Descrição
  Persistência da Wishlist (C-91–C-102, C-210–C-219 / LDM-79–LDM-90,
  LDM-204–LDM-208; contrato `wishlist-product-contract.md` v1.1): a
  intenção pessoal e privada de um User de adquirir uma Card Variant
  específica, com preferência opcional de idioma.

Desenho
  - id uuid: identidade estável por desejo (§3; o futuro CI-N2 poderá
    referenciar a intenção). Nunca exposto como texto na interface.
  - user_id → auth.users ON DELETE CASCADE: intenção pessoal, não
    patrimônio (mesma regra de card_favorite, 5335).
  - card_variant_id → card_variant ON DELETE RESTRICT: o desejo nunca
    some em silêncio. Variante desativada NÃO remove o desejo (C-214 /
    LDM-205); a exigência de variante ativa vale só na inclusão (5346).
  - language_id → language, NULL = "qualquer idioma" (C-92). Nunca
    "nenhum".
  - Unicidade (user_id, card_variant_id, language_id) NULLS NOT DISTINCT:
    "qualquer" é um valor próprio (C-99); repetir a inclusão não cria
    segunda entrada; "PT ou EN" = duas entradas legítimas.
  - Sem quantidade, prioridade, ordem manual, preço-alvo, alerta,
    condição, graduação, visibilidade, consentimento ou vínculo com
    coleção/fichário/bolso/posição (C-210, C-211, C-217, LDM-204,
    LDM-207). Posse, preço, carta e Set são derivados na leitura.
  - Índices:
      uq (user_id, card_variant_id, language_id) — unicidade e "esta
        variante está na lista?" em lote (prefixo user_id, card_variant_id);
      ix (user_id, created_at desc, id) — página "recentes" sem ordenar a
        tabela inteira;
      ix (card_variant_id) — FK RESTRICT ao excluir variante do catálogo.
    "Por carta" (Pesquisa/Set/Pokédex) junta card_variant pela PK a partir
    das linhas do próprio usuário — o volume por usuário é pequeno e o
    prefixo user_id já recorta.
  - RLS ativa; uma policy de SELECT só das próprias linhas (C-217).
  - Grants: authenticated = SELECT (pela RLS, só as próprias linhas);
    nenhuma escrita direta pela API — escrita só pelas funções da 5346.
    anon/PUBLIC = nenhum.

Resultado esperado
  Tabela com PK, 3 FKs, 1 unique NULLS NOT DISTINCT, 2 índices, RLS ativa,
  1 policy SELECT.

Como validar: Query 5873 (mesma pasta), Parte 0.
Como reverter: DROP TABLE public.card_wishlist_entry; (só antes de haver
desejos a preservar; as funções 5346/5347 precisam ser removidas antes).
================================================================
*/

begin;

create table public.card_wishlist_entry (
  id              uuid        not null default gen_random_uuid(),
  user_id         uuid        not null,
  card_variant_id uuid        not null,
  language_id     uuid        null,
  created_at      timestamptz not null default now(),
  constraint pk_card_wishlist_entry
    primary key (id),
  constraint fk_card_wishlist_entry_user_id
    foreign key (user_id) references auth.users(id)
    on update restrict on delete cascade,
  constraint fk_card_wishlist_entry_card_variant_id
    foreign key (card_variant_id) references public.card_variant(id)
    on update restrict on delete restrict,
  constraint fk_card_wishlist_entry_language_id
    foreign key (language_id) references public.language(id)
    on update restrict on delete restrict,
  constraint uq_card_wishlist_entry_user_variant_language
    unique nulls not distinct (user_id, card_variant_id, language_id)
);

create index ix_card_wishlist_entry_user_recent
  on public.card_wishlist_entry (user_id, created_at desc, id);

create index ix_card_wishlist_entry_card_variant_id
  on public.card_wishlist_entry (card_variant_id);

comment on table public.card_wishlist_entry is
  'V1-11 W1 (Query 5345): Lista de desejos — intenção pessoal e privada de adquirir uma Card Variant, com idioma opcional (NULL = qualquer). Binária, sem quantidade/prioridade/vínculo com coleção. Leitura só das próprias linhas (RLS); escrita só via funções da 5346.';
comment on column public.card_wishlist_entry.language_id is
  'NULL = qualquer idioma (C-92). Faz parte da unicidade como valor próprio (NULLS NOT DISTINCT, C-99).';

alter table public.card_wishlist_entry enable row level security;

create policy card_wishlist_entry_select_own
  on public.card_wishlist_entry
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.card_wishlist_entry from public;
revoke all on table public.card_wishlist_entry from anon;
revoke all on table public.card_wishlist_entry from authenticated;
grant select on table public.card_wishlist_entry to authenticated;

commit;

-- Como validar (rápido; completo na 5873):
-- select relrowsecurity, (select count(*) from pg_policies where tablename = 'card_wishlist_entry') as policies,
--        has_table_privilege('authenticated', 'public.card_wishlist_entry', 'INSERT') as auth_insert,
--        has_table_privilege('anon', 'public.card_wishlist_entry', 'SELECT') as anon_select
-- from pg_class where oid = 'public.card_wishlist_entry'::regclass;
-- Esperado: t | 1 | f | f
