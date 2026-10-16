/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6136 - Create pokedex_species_favorite Table
Versão......: 1.0
Status......: PROPOSTO — NÃO EXECUTADO (aguarda auditoria independente
              e autorização; quem executa é Fabrício)
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-14 (Pokédex P6.1)
Descrição...:
Persistência de "Espécie favorita" (Favorite Species — ADR-011 v1.6,
ubiquitous-language 1.26): preferência pessoal de um User por uma
Pokémon Species. Binária, sem ordem/nota, independente de posse de
cartas, de Collection e do Favorite de Card (C-82–C-90, que não é
alterado nem materializado aqui).

Desenho (padrões canônicos do projeto — inventory 5000, collection
5030/5034, leituras da Pokédex 6131/6135):
- PK composta (user_id, pokemon_species_id): no máximo um registro por
  par User × espécie; também serve à leitura "favoritos do usuário"
  (coluna líder user_id), sem índice extra para ela.
- user_id → auth.users ON DELETE CASCADE: preferência pessoal, não
  patrimônio (contraste deliberado com inventory.owner_user_id, que é
  RESTRICT). Ver limitação L3 no README: hoje a exclusão de um usuário
  já é bloqueada pelo RESTRICT de inventory; o CASCADE só age quando
  a conta puder de fato ser excluída.
- pokemon_species_id → pokemon_species ON DELETE RESTRICT: catálogo
  não é apagado (6010).
- Índice em pokemon_species_id: cobre a FK pelo lado da espécie
  (verificação do RESTRICT e o lint "unindexed foreign key" do Advisor).
- RLS ativada; uma única policy, de SELECT, só das próprias linhas.
- authenticated: apenas SELECT. INSERT/UPDATE/DELETE diretos negados —
  escrita exclusivamente por set_pokedex_species_favorite() (Query
  6137, SECURITY DEFINER, dono resolvido por auth.uid()).
- anon e PUBLIC: nenhum privilégio. (service_role mantém os privilégios
  padrão do Supabase e ignora RLS por definição — é chave de servidor,
  nunca usada no cliente; ver README.)
- Sem updated_at: a linha não é atualizada, só criada e removida.

Pré-requisitos:
- pokemon_species (6010) e auth.users existentes.
- Tabela public.pokedex_species_favorite AUSENTE (precheck abaixo).

Resultado esperado:
- Tabela criada com PK, 2 FKs, 1 índice, RLS ativa, 1 policy SELECT,
  grants: authenticated = SELECT; anon/PUBLIC = nenhum.

Como validar:
- Query 6849, Seção 1 (estrutura e privilégios).
================================================================
*/

-- Precheck (somente leitura): deve retornar 0 linhas antes da execução.
-- SELECT to_regclass('public.pokedex_species_favorite');

begin;

create table public.pokedex_species_favorite (
  user_id            uuid        not null,
  pokemon_species_id uuid        not null,
  created_at         timestamptz not null default now(),
  constraint pk_pokedex_species_favorite
    primary key (user_id, pokemon_species_id),
  constraint fk_pokedex_species_favorite_user_id
    foreign key (user_id) references auth.users(id)
    on update restrict on delete cascade,
  constraint fk_pokedex_species_favorite_pokemon_species_id
    foreign key (pokemon_species_id) references public.pokemon_species(id)
    on update restrict on delete restrict
);

create index ix_pokedex_species_favorite_pokemon_species_id
  on public.pokedex_species_favorite (pokemon_species_id);

comment on table public.pokedex_species_favorite is
  'Pokédex P6 (Query 6136): Espécie favorita — preferência pessoal de um User por uma Pokémon Species. Binária, independente de posse de cartas, de Collection e do Favorite de Card. Leitura só das próprias linhas (RLS); escrita só via set_pokedex_species_favorite().';

alter table public.pokedex_species_favorite enable row level security;

create policy pokedex_species_favorite_select_own
  on public.pokedex_species_favorite
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on table public.pokedex_species_favorite from public;
revoke all on table public.pokedex_species_favorite from anon;
revoke all on table public.pokedex_species_favorite from authenticated;
grant select on table public.pokedex_species_favorite to authenticated;

commit;
