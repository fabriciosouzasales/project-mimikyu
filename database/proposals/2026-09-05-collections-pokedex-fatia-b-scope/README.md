# Staging — Collections Pokédex Fatia B (Collection Pokédex Reference + Adopted Scope)

| Campo | Valor |
|--------|-------|
| **Mandato** | `COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-MODELING-AUDIT-01` → corrigido em `COLLECTIONS-POKEDEX-FATIA-B-PHYSICAL-MODELING-REVISION-01` |
| **Data** | 2026-09-05 |
| **Status** | **PROPOSTA — STAGING, NÃO EXECUTADO.** Nenhuma Query desta pasta foi aplicada ao banco real. |
| **Escopo** | Modelagem física mínima para: (1) ligar uma Collection à Pokédex canônica; (2) representar o Scope declarado (`FULL_REFERENCE`/`GENERATION_FILTERED`); (3) representar quais Generations compõem o filtro; (4) coerência com `collection.mode`/`completion_policy`/`collection_reference`/Pokédex canônica; (5) preservar a decisão conceitual de que Positions são **derivadas** do Scope, nunca adotadas manualmente. |
| **Fora de escopo (explícito)** | Card → Primary Species (Fatia C), Position Assignment / Primary Representative (Fatia D), **cálculo** de `REFERENCE_POSITION` Completion — denominator/numerator/read models/status derivado (Fatia E), frontend/UX, sourcing externo. Nenhum arquivo desta pasta toca essas frentes. |

## REVISION-01 — correção de blocker físico (2026-09-05)

A rodada AUDIT-01 havia proposto `completion_policy = 'NONE'` para Collections Pokédex, para evitar tocar `chk_collection_completion_policy` antes da Fatia E. Fabrício identificou que isso é um **blocker físico real**: `NONE` é um estado semanticamente falso — a Collection TEM uma política de completude (`REFERENCE_POSITION`, LDM-181), só o cálculo ainda não existe. A correção obrigatória:

1. **Novo valor `REFERENCE_POSITION` materializado nesta Fatia B**, via alargamento de `chk_collection_completion_policy` (Query nova `5086`).
2. **Invariant correto**: `REFERENCE_BASED + REFERENCE_POSITION` para toda Collection Pokédex.
3. Isto **NÃO implementa** a Completion da Fatia E — apenas materializa a identidade/policy correta para a Collection existir sem estado semântico falso.
4. Fatia E continua integralmente responsável por: cálculo de completion; denominator/numerator; read models; status derivado.
5. Todas as migrations/RPCs afetadas foram revisadas e a sequência inteira foi renumerada (ver abaixo) — nenhum arquivo antigo (`5086`–`5098` da rodada AUDIT-01) sobrevive sob o mesmo nome; a pasta foi recriada do zero com os números finais.
6. Mantido sem alteração: `scope_kind` em `collection_pokedex_reference`; `FULL_REFERENCE`/`GENERATION_FILTERED`; filtro de Generation em tabela filha; Positions derivadas, nunca selecionadas manualmente; Game gate `POKEMON` centralizado (Query `5090`); Fatias C/D/E fora de escopo.
7. O achado de `service_role` nas tabelas Collection pré-existentes permanece **registrado como débito separado**, não tratado nesta rodada (ver "Achado colateral" abaixo) — por instrução explícita de Fabrício.

## Arquivos afetados por esta correção

| Arquivo (nome final) | O que mudou vs. AUDIT-01 |
|---|---|
| `5086_alter_collection_widen_completion_policy_reference_position.sql` | **NOVO** — não existia na rodada AUDIT-01. Alarga `chk_collection_completion_policy` para aceitar `(REFERENCE_BASED, REFERENCE_POSITION)`. |
| `5087`–`5093` | Conteúdo técnico **idêntico** ao da rodada AUDIT-01 (antigos `5086`–`5092`) — apenas renumerados e com referências cruzadas internas corrigidas para os novos números. |
| `5094`–`5097` | Conteúdo técnico **idêntico** ao da rodada AUDIT-01 (antigos `5093`–`5096`) — apenas renumerados. |
| `5098_create_reference_based_pokedex_collection_function.sql` | **Corrigido (v1.1)** — antigo `5097`. `completion_policy` gravado passa de `'NONE'` para `'REFERENCE_POSITION'`. Cabeçalho reescrito para documentar a correção e a divisão de responsabilidade com a Fatia E. |
| `5099_create_set_collection_pokedex_scope_function.sql` | Conteúdo técnico **idêntico** ao antigo `5098` (esta RPC nunca tocou `completion_policy`) — apenas renumerado, com nota explícita no cabeçalho confirmando que não foi afetada pela correção. |

Todos os arquivos antigos com nomes `5086`–`5098` da rodada AUDIT-01 foram **removidos** da pasta antes da reescrita — não sobra nenhum arquivo órfão ou duplicado.

## Sequência final (números confirmados livres em `database/schema/` — último arquivo do milhar era `5084`)

```text
5085 - Alter Collection Reference: widen reference_kind for POKEDEX
5086 - Alter Collection: widen completion_policy for REFERENCE_POSITION           [NOVO — REVISION-01]
5087 - Create Collection Pokedex Reference table
5088 - Create Collection Pokedex Reference updated_at trigger
5089 - Create Collection Pokedex Reference Structural Identity trigger
5090 - Create Collection Pokedex Reference Game and Lock Guard trigger
5091 - Create Collection Pokedex Scope Generation table
5092 - Extensão do check_collection_reference_subtype_consistency() (dobra em 5057) — branch POKEDEX
5093 - Create Collection Pokedex Reference Consistency trigger
5094 - Create check_collection_pokedex_scope_presence() helper
5095 - Create Collection Pokedex Scope Generation Eligibility trigger
5096 - Create Collection Pokedex Scope Presence trigger (lado Reference)
5097 - Create Collection Pokedex Scope Presence trigger On Delete (lado Generation)
5098 - Create create_reference_based_pokedex_collection() function                [CORRIGIDO v1.1 — REVISION-01]
5099 - Create set_collection_pokedex_scope() function
```

Ordem de aplicação (se/quando autorizada): exatamente a sequência acima. `5086` é independente das demais (só toca `collection`) mas precisa existir antes de `5098` (que grava `REFERENCE_POSITION`). `5090` depende de `5087` já existir. `5092` faz `CREATE OR REPLACE` sobre a função criada em `5057` (já `CONFIRMADO EXECUTADO` em `database/schema/`). `5095`/`5096`/`5097` dependem de `5091`/`5094`. `5098`/`5099` dependem de tudo anterior.

## Modelo físico resultante (resumo)

```text
collection
├── chk_collection_completion_policy: NONE|OPEN_CURATION, STANDARD_SET|REFERENCE_BASED,
│                                      MASTER_SET|REFERENCE_BASED, REFERENCE_POSITION|REFERENCE_BASED  [alargado por 5086]
└── collection_reference (existente, 5049)
    ├── chk_collection_reference_kind: 'CARD_SET' | 'POKEDEX'  [alargado por 5085]
    ├── collection_card_set_reference (existente, 5052)
    └── collection_pokedex_reference (NOVO, 5087)
        ├── pokedex_id       → public.pokedex               (imutável após lock)
        ├── scope_kind       'FULL_REFERENCE' | 'GENERATION_FILTERED'  (mutável sempre, LDM-177)
        └── collection_pokedex_scope_generation (NOVO, 5091, tabela filha)
            └── generation_id → public.pokemon_generation   (N linhas quando GENERATION_FILTERED)
```

Nenhuma tabela de "Positions adotadas" é criada — o conjunto de Positions em Scope permanece **derivado** em tempo de leitura (LDM-177, ponto 5 do escopo), via `pokedex_position JOIN pokemon_species ON species_id` filtrado por `pokemon_species.generation_id IN (Generations do filtro)` quando `GENERATION_FILTERED`, ou sem filtro quando `FULL_REFERENCE`. Nenhum read-model dessa derivação é entregue nesta rodada.

## Estado físico confirmado (auditoria read-only, 2026-09-05 — reconfirmado nesta REVISION-01)

- `pokemon_generation`: 9 linhas · `pokemon_species`: 1.025 linhas · `pokedex`: 1 linha (`NATIONAL`) · `pokedex_position`: 1.025 linhas · `pokemon_region`: 11 linhas.
- `collection`, `collection_reference`, `collection_card_set_reference`, `collection_allocation`, `collection_master_set_scope`: 0 linhas cada.
- `collection_pokedex_reference` e quaisquer nomes candidatos de tabela de Scope: nenhum existe.
- `chk_collection_reference_kind` atual: `CHECK (reference_kind = 'CARD_SET')`.
- `chk_collection_completion_policy` atual: aceita apenas `(OPEN_CURATION, NONE)`, `(REFERENCE_BASED, STANDARD_SET)`, `(REFERENCE_BASED, MASTER_SET)` — **este é exatamente o blocker corrigido nesta rodada** (Query `5086`).
- `game`: 2 linhas — `POKEMON` e `LORCANA`.
- **Achado colateral (fora do escopo da Fatia B, registrado como débito separado por instrução explícita — item 7 da REVISION-01):** `pg_default_acl` do role `postgres`/schema `public` ainda concede `service_role=Dxtm` (TRUNCATE/REFERENCES/TRIGGER/MAINTAIN) a toda tabela nova — as 5 tabelas existentes do domínio Collection ainda têm essas 4 permissões concedidas a `service_role`, nunca revogadas (o hardening da Query `6111` cobriu só as 9 tabelas do Pokémon Catalog). As 3 tabelas novas desta proposta (`5087`/`5091`) já nascem com `REVOKE ... FROM anon, authenticated, service_role` incluído. **Não tratado nesta rodada.**

## Decisões (aguardando confirmação explícita)

**Decisão 1 (REVISADA) — `completion_policy = 'REFERENCE_POSITION'` para Collections Pokédex.** Substituída a decisão original (`'NONE'`) por instrução direta de Fabrício. `create_reference_based_pokedex_collection()` (5098) agora grava sempre `completion_policy = 'REFERENCE_POSITION'`. `chk_collection_completion_policy` é alargado (5086) para aceitar essa combinação. `collection_completion_summary()`/`collection_completion_positions()` (5070/5071/5083) **não são tocadas** nesta rodada — continuam sem nenhum ramo para `REFERENCE_POSITION`, retornando resultado vazio se chamadas contra uma Collection assim (não é erro; é lacuna aceita, de responsabilidade integral da Fatia E). Diferente do precedente de `MASTER_SET` (onde CHECK e read models foram entregues na mesma rodada, 02F), aqui a materialização do valor antecede deliberadamente a Fatia E, por decisão explícita de Fabrício nesta REVISION-01.

**Decisão 2 (mantida) — Game Gate (`game.code = 'POKEMON'`).** `pokedex` não tem nenhum vínculo com `game` (LDM-175). A Query 5090 (trigger) e a Query 5098 (RPC, early check) comparam `collection.game_id` contra o Game de `code = 'POKEMON'`. Trade-off reconhecido: primeira vez que o módulo genérico de Collection Reference amarra um comportamento a um `code` específico de Game.

**Decisão 3 (mantida) — Scope mutável mesmo após `reference_locked_at`.** `pokedex_id` trava após o lock (mesma disciplina de `card_set_id`); `scope_kind` e o conjunto de Generations permanecem mutáveis a qualquer momento enquanto `ACTIVE` (LDM-177/LDM-185).

**Decisão 4 (mantida) — Troca de Scope é DELETE+INSERT total, não diff KEEP/ADD/REMOVE.** `collection_pokedex_scope_generation` não carrega `adopted_at`/`adopted_by_user_id` por linha.

**Decisão 5 (mantida) — nenhum read-model de "Positions em Scope" nesta rodada.** Ponto 5 do escopo satisfeito estruturalmente (nenhuma tabela de Positions adotadas existe). Uma função de leitura pura seria adição futura de baixo risco, não incluída aqui.

## Riscos restantes

- **R1 (baixo).** Decisão 2 hardcoda a string `'POKEMON'` numa trigger e numa RPC — acoplamento único, sem mecanismo central de "Game canônico Pokémon".
- **R2 (baixo).** Nenhuma trigger impede que um `UPDATE` direto (bypass de RPC) grave `completion_policy = 'REFERENCE_POSITION'` numa Collection cujo `collection_reference.reference_kind` seja `CARD_SET` (o CHECK em `collection` não enxerga `reference_kind`, que mora em outra tabela) — mesmo nível de rigor já aceito pelo `chk_collection_completion_policy` existente antes desta rodada.
- **R3 (baixo, NOVO nesta REVISION-01, esperado e aceito).** `collection_completion_summary()`/`collection_completion_positions()` retornam resultado vazio (não erro) se chamadas contra uma Collection `REFERENCE_POSITION` antes da Fatia E existir — comportamento correto por desenho (nenhum ramo definido ainda), mas requer que o frontend não ofereça UI de completion para Collections Pokédex antes da Fatia E, sob risco de exibir "0/0" ou tela vazia em vez de "em breve". Puramente uma responsabilidade de camada de apresentação — nenhuma inconsistência de dado.
- **R4 (médio, achado colateral, não desta Fatia, registrado como débito).** As 5 tabelas Collection pré-existentes permanecem com privilégios estruturais de `service_role` não revogados. Recomendação: rodada de hardening dedicada, mesmo padrão de `6111`.

## Divergências entre LDM e banco

Nenhuma divergência real encontrada — o blocker desta REVISION-01 não foi uma divergência entre LDM e banco, foi um erro de modelagem física da rodada AUDIT-01 (evitar tocar o CHECK em vez de alargá-lo corretamente), corrigido nesta rodada por instrução direta de Fabrício.

## Não realizado nesta rodada (lembrete)

Nenhuma migration foi executada. Nenhum `docs/*.md` foi editado. Nenhum `git add`/`commit`/`push` foi realizado. Nenhuma extrapolação para Fatia C/D/E. Nenhum tratamento do achado de `service_role` nas tabelas Collection pré-existentes (registrado como débito separado, item 7 da REVISION-01).
