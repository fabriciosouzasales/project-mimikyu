/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 6136 - Create pokedex_species_favorite Table
Versão......: 1.0 (canônica — P6.3)
Status......: CONFIRMADO EXECUTADO em 2026-10-14 (Pokédex P6.2), no LIVE
              (projeto qjfutqujxrbzgrtkpgkg), via Supabase MCP execute_sql com o
              arquivo de proposta integral — SEM registro em apply_migration /
              supabase_migrations.schema_migrations (decisão da P6.2: a promoção
              canônica ainda não estava autorizada). Promovido para
              database/migrations/ na P6.3 (2026-10-15). Código (de "begin;"
              a "commit;") byte-idêntico à proposta ensaiada e implantada:
              sha256 do conteúdo begin..commit = d4d5c2d75ea24771f4d56ee5bbc160e812ddcc1b98b07f1c598eb7e014d63223.
Validação...: ensaio reversível 6850 (GATE-ENSAIO 11/11 PASS) antes da
              implantação; após implantar, 6849 v2.1 = 46 PASS, 0 FAIL,
              1 NOT_PROVEN (7.7: não há espécie inativa no banco), GATE PASS;
              postcheck independente sem resíduos (0 favoritos, contas e
              entidades inalteradas). Security Advisor: única novidade é o WARN
              conhecido authenticated_security_definer_function_executable nas
              duas RPCs da Query 6137 (mesmo padrão das demais RPCs do produto).
              Evidência: database/proposals/2026-10-14-pokedex-p6-favorites/
              README.md §5.5–§5.8.
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
