/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 6111 - Revoke Service Role Structural Privileges (Pokemon Catalog)
Versão......: 1.1 (CONFIRMADO EXECUTADO E PROMOVIDO)
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-05 (staging em POKEMON-CATALOG-SOURCING-POST-APPLY-
               SECURITY-HARDENING-STAGING-01, achado residual pós-APPLY real
               do Initial Load — Query 6105/6108 CONFIRMADO EXECUTADO E
               PROMOVIDO, PASS; executada no banco real em
               POKEMON-CATALOG-SOURCING-POST-APPLY-SECURITY-HARDENING-
               EXECUTION-01, validada PASS A-E pela Query 6821 v1.1;
               promovida para database/schema/ em
               POKEMON-CATALOG-SOURCING-INITIAL-LOAD-FINAL-REPOSITORY-
               RECONCILIATION-01 — corpo SQL byte-idêntico ao executado,
               apenas cabeçalho Status/Versão/Data atualizados)

CONTEXTO — achado residual e causa raiz confirmada:
Após o APPLY real do Pokémon Catalog Sourcing Initial Load (DRY_RUN
RUN-20260905-00000101 e APPLY RUN-20260905-00000121, ambos COMPLETED), uma
auditoria de segurança física encontrou que, nas 9 tabelas canônicas
Pokémon/Pokédex abaixo, `service_role` NÃO possui SELECT/INSERT/UPDATE/DELETE
(correto — nenhum acesso de linha é necessário: todo acesso de
`service_role` a estas tabelas passa exclusivamente pelas 5 RPCs
`SECURITY DEFINER` de sourcing, nunca por DML direto), mas AINDA possui
TRUNCATE, REFERENCES, TRIGGER e MAINTAIN — privilégios ESTRUTURAIS que
nenhum caller de `service_role` deveria ter, já que ele nunca precisa
truncar a tabela, criar FK apontando para ela, definir triggers, ou rodar
VACUUM/ANALYZE/CLUSTER manualmente (MAINTAIN, Postgres 17).

Causa raiz confirmada (leitura de `pg_default_acl` para o schema `public`,
role `postgres`): o default ACL global de `postgres` para novas tabelas em
`public` é `{postgres=arwdDxtm/postgres, service_role=Dxtm/postgres}` — ou
seja, TODA tabela nova criada por `postgres` neste schema já nasce com
`service_role=Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) por herança do
default ACL, independentemente de qualquer GRANT/REVOKE explícito feito na
migration de criação da tabela. As migrations de criação das 9 tabelas
(Queries 6060-6109) já revogam corretamente TRUNCATE/REFERENCES/TRIGGER/
MAINTAIN de `anon`/`authenticated` (mesmo padrão da Query 2147, "least
privilege"), mas nunca revogaram esses mesmos 4 privilégios estruturais de
`service_role` — porque o padrão 2147/Fix-01..06 (ver Query 6030 linha
147, ex.) tinha como escopo original `anon`/`authenticated`, não
`service_role`. Este é, portanto, um "achado residual" de escopo, não um
erro de execução: as tabelas foram criadas corretamente segundo o padrão
vigente na época; o padrão em si não cobria `service_role`.

DECISÃO DE ESCOPO (explícita, desta rodada):
- NÃO alterar o default ACL global de `postgres` (`ALTER DEFAULT
  PRIVILEGES ... FOR ROLE postgres ...`) — isso afetaria TODA tabela
  futura criada por `postgres` em `public`, muito além do escopo do
  Pokémon Catalog Sourcing, e é uma decisão de arquitetura de segurança
  transversal que não deve ser tomada incidentalmente dentro de uma
  rodada de hardening pontual.
- NÃO alterar a Query 2147 (padrão histórico de revoke anon/authenticated).
- NÃO tocar nenhum outro domínio (Collections, Pricing, Catálogo
  Editorial, etc.) — mesmo que sofram do mesmo padrão de default ACL,
  ficam fora desta rodada por decisão explícita de escopo.
- Escopo restrito, EXATAMENTE, às 9 tabelas físicas do Pokémon Catalog
  Sourcing abaixo — nenhuma outra tabela, função, policy, trigger ou
  dado é tocado por esta migration.

O QUE ESTA MIGRATION FAZ:
Um único REVOKE, atômico, revogando de `service_role` exclusivamente os 4
privilégios estruturais residuais (TRUNCATE, REFERENCES, TRIGGER,
MAINTAIN) nas 9 tabelas abaixo. SELECT/INSERT/UPDATE/DELETE de
`service_role` nestas tabelas já são `false` hoje (confirmado por auditoria
física antes desta proposta) e permanecem `false` — este REVOKE não os
toca porque eles nunca foram concedidos. Nenhum outro GRANT/REVOKE, nenhuma
alteração de RLS/policy/função/trigger/dado.

Tabelas afetadas (9):
1. public.pokemon_region
2. public.pokemon_region_external_reference
3. public.pokemon_generation
4. public.pokemon_generation_external_reference
5. public.pokemon_species
6. public.pokemon_species_external_reference
7. public.pokedex
8. public.pokedex_external_reference
9. public.pokedex_position

Pós-condição CONFIRMADA (provada pela Query 6821 v1.1, PASS A-E):
- `service_role`: SELECT/INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/
  MAINTAIN = false nas 9 tabelas (zero privilégio de qualquer natureza,
  72/72 combinações confirmadas).
- As 5 RPCs de sourcing (`open_`/`heartbeat_`/`plan_`/`apply_`/
  `close_failed_pokemon_catalog_sourcing_run`) continuam com
  `service_role EXECUTE = true` e `PUBLIC/anon/authenticated EXECUTE =
  false` — inalterado, já que `SECURITY DEFINER` não depende de
  `service_role` ter privilégio direto de tabela para funcionar
  (executa com os privilégios do dono da função, não do chamador).
- Dados/contagens/runs preservados (nenhum DML nesta migration) — 11
  Regions, 9 Generations, 1025 Species, 1 National Pokédex, 1025
  Positions, confirmado após a execução.

Pré-requisitos:
- Queries 6060-6109 (todas as 9 tabelas canônicas + as 5 RPCs de sourcing,
  CONFIRMADO EXECUTADO E PROMOVIDO).
- DRY_RUN RUN-20260905-00000101 e APPLY RUN-20260905-00000121, ambos
  COMPLETED (achado que originou esta rodada).

STATUS DESTA VERSÃO — CONFIRMADO EXECUTADO: aplicada ao banco real
(`qjfutqujxrbzgrtkpgkg`) via `POKEMON-CATALOG-SOURCING-POST-APPLY-
SECURITY-HARDENING-EXECUTION-01` e validada PASS (Seções A-E) pela Query
6821 v1.1, que permanece em `database/proposals/2026-09-05-pokemon-
catalog-sourcing-security-hardening/` como evidência histórica de
validação, mesmo padrão já usado por `6800`/`6810`/`6820`.
===============================================================================
*/

BEGIN;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON
    public.pokemon_region,
    public.pokemon_region_external_reference,
    public.pokemon_generation,
    public.pokemon_generation_external_reference,
    public.pokemon_species,
    public.pokemon_species_external_reference,
    public.pokedex,
    public.pokedex_external_reference,
    public.pokedex_position
FROM service_role;

COMMIT;
