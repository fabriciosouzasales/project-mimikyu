# Staging — Collections Pokédex Fatia C — Card Primary Species

| Campo | Valor |
|--------|-------|
| **Pasta** | `database/proposals/2026-09-05-fatia-c-card-primary-species/` |
| **Status** | **PROMOVIDO** — Esta pasta é mantida apenas como histórico do staging original (auditoria, revisões, riscos, alternativas rejeitadas) — a fonte canônica é `database/schema/2159_widen_catalog_admin_action_log_for_card_primary_species.sql`, `6112_create_card_primary_species_table.sql`, `6113_create_card_primary_species_triggers.sql`, `6114_create_admin_resolve_card_primary_species_function.sql` e `6115_create_resolve_card_primary_species_bulk_function.sql`. Promovido em `COLLECTIONS-POKEDEX-FATIA-C-CANONICAL-CLOSEOUT-01` (2026-09-05), após `IMPLEMENTATION-01-RESUME` (aplicação real) e `INCREMENTAL-IMPLEMENTATION-01` (integração com os dois callers reais + backfill, ver README irmão `2026-09-05-fatia-c-incremental-integration/`). |
| **Rodadas de origem** | `COLLECTIONS-POKEDEX-FATIA-C-PHYSICAL-MODELING-AUDIT-01`, `-REVISION-01`, `-REVISION-02`, `-GATE-4-PHYSICAL-AUDIT-01`, `-GATE-4-FIX-01`, `-IMPLEMENTATION-01` (interrompida por STOP legítimo), `-PREMISE-DIVERGENCE-FIX-01`, `-IMPLEMENTATION-01-RESUME` (aplicada com sucesso) |
| **Data** | 2026-09-05 |
| **HEAD canônico no início da rodada** | `c28a7700e9a9219aed746d56068ba6e360a6cac0` |

## IMPLEMENTATION-01-RESUME — resultado

As 5 Queries staged (`2159` v1.1, `6112` v1.1, `6113`, `6114`, `6115`
v1.2) foram aplicadas ao projeto Supabase real (`qjfutqujxrbzgrtkpgkg`)
via `apply_migration`, uma por vez, sem nenhuma alteração de SQL em
relação ao staging revisado — todas as 5 chamadas retornaram sucesso,
nenhum STOP foi necessário nesta rodada (a divergência de premissa já
havia sido corrigida e reauditada na rodada anterior).

Postcheck estrutural completo (tabela `card_primary_species`, PK/FKs/
CHECKs, os 3 triggers, RLS + policy `catalog_admin_select`, grants —
zero DML direto de qualquer papel, hardening `service_role` —, as 2
RPCs `SECURITY DEFINER` com `search_path=''`, `GRANT EXECUTE`
corretamente segregado entre `authenticated`
(`admin_resolve_card_primary_species`) e `service_role`
(`resolve_card_primary_species_bulk`), e as CHECKs de
`catalog_admin_action_log` ampliadas para 29 actions/11 entity_types/11
ramos preservando os 629 registros históricos) — todos os itens PASS,
nenhuma discrepância encontrada.

Testes funcionais: os 12 cenários mandatados foram executados em uma
única transação `BEGIN ... ROLLBACK` contra o banco real, usando Cards
e Species de produção como fixture e `SET LOCAL request.jwt.claim.sub`
para simular sessão de administrador autenticado. Todos os 12 PASS:
resolução automática válida; idempotência/`SAME_SPECIES`; desvio de
fonte automática/`CONFLICT` (linha original comprovadamente intacta,
`resolved_at` inalterado); reconciliação editorial via
`admin_resolve_card_primary_species()` com `catalog_admin_action_log`
registrando `old_pokemon_species_id=NULL`/`new_pokemon_species_id`
corretos; `EDITORIAL_PROTECTED` (decisão editorial comprovadamente não
sobrescrita por bulk divergente); `UNRESOLVED` por ausência de
evidência; `AMBIGUOUS` por múltiplos dexIds distintos; `UNRESOLVED` por
dexId desconhecido no catálogo; item isolado `FAILED` (Card ENERGY)
sem abortar o item bom no mesmo lote; guard de lote rejeitando 10001
itens com `RAISE EXCEPTION` antes de qualquer escrita; confirmação de
que `resolve_card_primary_species_bulk()` nunca executa `UPDATE` (prova
funcional via `resolved_at` intacto nos cenários de idempotência e
conflito, somada à prova estrutural já feita por grep no corpo da
função). Após o `ROLLBACK`, `card_primary_species` voltou a 0 linhas e
`catalog_admin_action_log` voltou exatamente a 629 linhas — zero
resíduo confirmado.

Não realizado nesta rodada (mandato explícito): backfill das Cards
existentes, integração com `import-catalog-cards`, promoção para
`database/schema/`, atualização de documentação canônica além deste
README, Fatia D/E, `git add`/`commit`/`push`.

## PREMISE-DIVERGENCE-FIX-01 — o que mudou e por quê

`IMPLEMENTATION-01` foi corretamente interrompida pela regra de parada
antes de qualquer escrita real: o pre-flight (`pg_get_constraintdef()`
direto no banco `qjfutqujxrbzgrtkpgkg`, 2026-09-05) encontrou as três
CHECKs de `catalog_admin_action_log` já ampliadas para **27 actions /
10 entity_types / 10 ramos de `action_entity_match`** — muito além do
baseline de `database/schema/2010_create_catalog_admin_action_log.sql`
v1.3 (14/5/5) sobre o qual `2159` v1.0 havia sido staged. A diferença
veio de outras frentes do projeto (Rarity, Rarity External Mapping,
Card Variant Type, Card Variant Type External Mapping, Card Asset
Manual Import, Catalog Variant Import Job, Catalog Import Rows
Revalidated) que já ampliaram essas CHECKs em produção sem que o
arquivo canônico `2010` fosse atualizado de volta — esse arquivo está
desatualizado frente ao banco real. Confirmado por consulta direta que
223 linhas reais usam exatamente os 9 pares action/entity_type que a
v1.0 de `2159` teria removido — executá-la teria falhado no
`ADD CONSTRAINT` (que valida linhas existentes) ou, na pior hipótese,
quebrado silenciosamente escritas futuras de funcionalidades alheias a
esta Fatia.

Corrigido nesta rodada: `2159` (v1.0 → v1.1) reescrita **estritamente
aditiva** sobre o estado físico real capturado nesta correção (não
sobre `database/schema/2010`) — os 27 actions/10 entity_types/10 ramos
vigentes preservados byte-semanticamente (verificado
programaticamente, branch a branch), com apenas os 2 actions + 1
entity_type + 1 ramo desta Fatia acrescentados ao final. Validação
cruzada contra `SELECT DISTINCT action, entity_type FROM
catalog_admin_action_log` confirmou que nenhuma das 23 combinações
reais hoje em uso fica fora do novo conjunto — a revisão é um
superconjunto estrito do que já valida hoje, nunca um subconjunto.
Nenhum valor foi removido, renomeado ou reordenado; nenhuma outra Query
desta Fatia (`6112`/`6113`/`6114`/`6115`) foi tocada. Nenhum SQL foi
executado nesta correção — o estado do banco real permanece
exatamente como estava ao final do STOP de `IMPLEMENTATION-01`.

Arquivo alterado: `2159_widen_catalog_admin_action_log_for_card_primary_species.sql`
(v1.0 → v1.1). `IMPLEMENTATION-01` pode ser retomada a partir desta
versão corrigida.

## GATE-4-FIX-01 — o que mudou e por quê

A auditoria física read-only `GATE-4-PHYSICAL-AUDIT-01` aprovou
`2159`/`6112`/`6113`/`6114` sem ressalvas e encontrou um único blocker
em `6115`: `details` diferenciava `CONFLICT` (com
`existing_species_id`/`candidate_species_id`) mas colapsava os dois
sub-casos de `UNCHANGED` — Species nova igual à existente
(`SAME_SPECIES`, verdadeiramente inerte) e Species nova divergente de
uma resolução `EDITORIAL_RECONCILIATION` protegida
(`EDITORIAL_PROTECTED`, uma divergência real, só que suprimida por
design) — em um único contador sem nenhuma entrada individual.
Consequência prática: o chamador não tinha como saber, a partir do
retorno da função, se uma Card ficou `UNCHANGED` porque nada mudou ou
porque a evidência automática nova diverge silenciosamente de uma
decisão editorial vigente.

Fechado nesta rodada (`6115` v1.1 → v1.2): os dois branches passam a
gravar entrada em `details` — `{"card_id", "outcome": "UNCHANGED",
"reason": "SAME_SPECIES"}` e `{"card_id", "outcome": "UNCHANGED",
"reason": "EDITORIAL_PROTECTED", "existing_species_id",
"candidate_species_id"}` (este último no mesmo formato do `CONFLICT`,
para dar ao chamador o suficiente para decidir se escala a Card a
`admin_resolve_card_primary_species()`, Query 6114). Mudança
estritamente aditiva: `unchanged_count` continua somando os dois casos
sob o mesmo nome, nenhum contador foi renomeado, nenhuma regra de
resolução, o guard de 10000, o invariante "bulk nunca faz UPDATE", nem
`2159`/`6112`/`6113`/`6114` foram tocados.

Arquivo alterado: `6115_create_resolve_card_primary_species_bulk_function.sql`
(v1.1 → v1.2). Nenhum outro arquivo SQL desta pasta foi tocado nesta
rodada.

## REVISION-02 — o que mudou e por quê

REVISION-01 ficou conceitualmente aprovada. Dois ajustes obrigatórios
antes do Gate 4:

1. **SOURCE DRIFT / CONFLICT.** A v1.0 de `6115` permitia que uma
   resolução `AUTOMATIC_DEXID` existente fosse sobrescrita quando o
   reprocessamento encontrava uma Species diferente ("reprocessamento
   legítimo"). Fechado: esse branch agora NUNCA escreve — classifica
   como `CONFLICT` (contador `conflict_count` + `details` com
   `existing_species_id`/`candidate_species_id`) e preserva a linha
   intacta. Só `admin_resolve_card_primary_species()` (Query 6114)
   pode alterar uma Species já resolvida a partir daqui — a garantia
   "MMKYU mantém a decisão canônica final" agora vale também para
   automático-vs-automático, não só editorial-vs-automático. Com este
   fechamento, `resolve_card_primary_species_bulk()` nunca mais
   executa `UPDATE` — só `INSERT` (linha nova) ou nenhuma escrita.
2. **BULK GUARD.** `p_evidence_batch` agora tem limite explícito de
   10000 itens (`c_max_batch_size`), checado via `jsonb_array_length()`
   ANTES de qualquer processamento — acima disso, `RAISE EXCEPTION`
   rejeita a chamada inteira (nunca truncamento silencioso). Mesmo
   valor e mesmo racional do guard já em produção no domínio
   (`c_max_variant_ids`, Query 5079/5813).

Arquivo alterado: `6115_create_resolve_card_primary_species_bulk_function.sql`
(v1.0 → v1.1). Nenhum outro arquivo desta pasta foi tocado nesta
rodada — `6112`/`6113`/`2159`/`6114` permanecem exatamente como em
REVISION-01.

## REVISION-01 — o que mudou e por quê

A modelagem-base (`6112`/`6113`) foi aprovada. Antes do Gate 4,
Fabrício pediu para fechar os dois fluxos operacionais que a
consomem — backfill do catálogo existente e resolução incremental
durante a importação de novos Sets — com um caminho de escrita
controlado (zero DML direto às tabelas), invariants fechados de
`resolution_basis`, e prova de rastreabilidade. Mudanças:

- `6112` (v1.0 → v1.1): `chk_card_primary_species_basis_requires_evidence`
  substituída por `chk_card_primary_species_automatic_evidence_shape` —
  contrato mínimo de `source_evidence` para `AUTOMATIC_DEXID` (`source`,
  `tcgdex_dex_ids`, `resolved_dex_id`), fechando o item "source_evidence
  não pode ser JSON opaco".
- `2159` (nova): amplia as 3 `CHECK`s de `catalog_admin_action_log`
  para `CARD_PRIMARY_SPECIES_RESOLVED`/`_CORRECTED` + `entity_type
  CARD_PRIMARY_SPECIES`.
- `6114` (nova): `admin_resolve_card_primary_species()` — caminho
  individual/editorial, `is_admin()`-gated, UPSERT, grava old/new em
  `catalog_admin_action_log`.
- `6115` (nova): `resolve_card_primary_species_bulk()` — caminho bulk
  automático, `service_role`-only, idempotente/reprocessável, nunca
  escolhe ambíguo, nunca sobrescreve decisão editorial, retorna
  contadores + detalhe.

Nenhum GRANT de INSERT/UPDATE/DELETE existe em `card_primary_species`
para nenhum papel, em nenhuma das duas rodadas — toda escrita passa
exclusivamente pelas duas funções `SECURITY DEFINER` acima, que
escrevem com os privilégios do dono da função, não do chamador.

Esta pasta é **staging**: SQL proposto, pronto para revisão, mas nada
aqui foi rodado contra o Supabase real. Nenhum arquivo entra em
`database/schema/` até ser **confirmadamente executado** — mesma
disciplina do `CLAUDE.md` (seção "Escrita de SQL") e do precedente
direto desta pasta, `database/proposals/2026-09-02-02d-reference/`.

## Por que este incremento existe

Fatia A (Pokédex catálogo) e Fatia B (Collection Pokédex Reference +
Scope) fecharam "qual Pokédex uma Collection referencia" e "como o
progresso é medido". Ficou em aberto a pergunta anterior a essas duas:
**como o catálogo editorial MMKYU determina a Primary Species canônica
de uma Card Pokémon**, evidência sem a qual nenhum Position Assignment
(LDM-178, fora de escopo aqui) tem o que comparar. Este incremento
modela exclusivamente esse vínculo Card → Species — não Position
Assignment, não Species Match/Mismatch, não USER_OVERRIDE.

## Autoridade conceitual

- `docs/domain-modeling/collections/logical-model.md` — LDM-175 a
  LDM-190, com ênfase em LDM-182/183 (Card Primary Species: Sourcing
  Estrutural) e LDM-178 (Position Assignment / Species Match —
  explicitamente NÃO modelado aqui).
- `docs/domain-modeling/collections/concept-decisions.md` — C-33
  (validação mínima de elegibilidade).
- `docs/adr/ADR-011-pokemon-tcg-domain-scope.md` — v1.0-v1.3: base da
  decisão de tabela própria (Pokémon TCG Domain específico) em vez de
  coluna em `card` (Catalog Domain genérico).
- `docs/05d-colecoes-e-usuarios.md` — estado físico confirmado de
  Card/Card External Reference/Pokémon Species.
- `docs/standards/STD-001-database-standards.md` — módulo "Pokémon
  Catalog Foundation" (6000-6999), que já antecipava `card_primary_species`
  por nome como entidade futura desta faixa.

## Estado físico confirmado (auditoria read-only, 2026-09-05)

- `public.card` (Query 140) não possui nenhuma coluna de
  species/pokemon. `internal.write_card()` (Query 2030) não expõe
  nenhum parâmetro de species — zero ponto de contato físico hoje.
- `public.card_external_reference` (Query 210, v2.0) tem `metadata
  JSONB` genérico, sem campo dedicado a dexId.
- `public.catalog_import_row` (Query 2070) tem `raw_data JSONB` — o
  detalhe completo por Card retornado pela TCGdex, incluindo `dexId`
  quando presente — mas é staging **efêmero**: Query 2111 já apagou 8
  jobs duplicados (e as `catalog_import_row` filhas) em produção em
  2026-08-07. Não há hoje nenhuma tabela durável contendo dexId.
- Auditoria SQL real (projeto `qjfutqujxrbzgrtkpgkg`) sobre as 6435
  Cards ativas de categoria POKEMON:
  - 5675 (88%) têm evidência de dexId sobrevivente em
    `catalog_import_row.raw_data`, todas com exatamente 1 elemento
    (nenhum caso multi-dexId ou array vazio observado).
  - Das 7100 linhas com dexId encontradas (algumas Cards com múltiplas
    linhas de staging), 0 divergem de
    `pokemon_species.national_dex_number` — validação empírica forte
    da premissa de LDM-182 (dexId único ⇒ resolução automática segura).
  - 760 Cards (~12%) não têm nenhuma evidência de dexId sobrevivente
    em lugar nenhum do banco — ver "Riscos" abaixo.
- `pg_policies`: `pokemon_species`/`pokemon_species_external_reference`
  usam RLS "fechada" (sem policy alguma); `card`/`card_category`/
  `catalog_import_job`/`catalog_import_row` usam `catalog_admin_select`
  (`USING (is_admin())` ou `(select is_admin())` na forma mais
  recente). `card_primary_species` segue este segundo padrão — é
  catálogo editorial, não integração pura.

## Decisões de desenho fechadas nesta rodada

**Tabela própria, não coluna em `card`.** Decisão direta de ADR-011:
o vínculo Card→Species é responsabilidade exclusiva do módulo
Pokémon-TCG-específico, nunca da tabela genérica multi-TCG.

**Cardinalidade via PK=FK, não UNIQUE.** `card_id` é ao mesmo tempo PK
e FK para `card.id` — 1:1 estrito estruturalmente garantido. Ausência
de linha é o estado "não resolvido" (LDM-182: dexId ausente/ambíguo
"segue para reconciliação editorial", não vira uma linha com valor
sentinela).

**Vocabulário deliberadamente distinto do de Position Assignment.**
`resolution_basis` usa `AUTOMATIC_DEXID`/`EDITORIAL_RECONCILIATION` —
nunca `SPECIES_MATCH`/`USER_OVERRIDE` (LDM-178). O mandato desta rodada
foi explícito sobre não misturar as duas responsabilidades; os dois
vocabulários são a barreira física contra a confusão conceitual.

**Evidência durável via `source_evidence` JSONB, não uma FK direta
para `catalog_import_row`.** Uma FK direta amarraria a durabilidade da
evidência à sobrevivência de uma tabela já comprovadamente efêmera
(Query 2111). O snapshot (`{"tcgdex_dex_id": ..., "catalog_import_row_id":
...}`) preserva o valor mesmo depois que a linha de origem for limpa,
mantendo o ponteiro como referência histórica best-effort, não como
dependência de integridade.

**Correção futura sem tabela de histórico dedicada (fechado em
REVISION-01).** Mesmo raciocínio que já levou LDM-179 a rejeitar uma
entidade de histórico própria para Position Assignment: correções
editoriais são registradas em `public.catalog_admin_action_log` (Query
2010, ampliada pela Query 2159) pela própria `admin_resolve_card_
primary_species()` (Query 6114) — old/new `pokemon_species_id`/
`resolution_basis`/`source_evidence` em `metadata`. Resoluções
automáticas em lote (Query 6115) não geram linha ali — a própria linha
resultante (`source_evidence` + `resolved_at`) já é a evidência
suficiente, reproduzível deterministicamente; não há decisão humana a
auditar num caso `AUTOMATIC_DEXID`. Mesmo padrão do pipeline 100%
automatizado de Pokémon Catalog Sourcing (Queries 6100-6111), que
também nunca escreve em `catalog_admin_action_log`.

**Escrita controlada, zero DML direto às tabelas (fechado em
REVISION-01).** `card_primary_species` nunca recebe `GRANT` de
`INSERT`/`UPDATE`/`DELETE` para nenhum papel — nem `authenticated`,
nem `service_role`. Toda escrita passa por duas funções `SECURITY
DEFINER`, cada uma para um dos dois fluxos operacionais pedidos:
`admin_resolve_card_primary_species()` (Query 6114, individual/
editorial, `is_admin()`-gated, `GRANT EXECUTE` só a `authenticated`) e
`resolve_card_primary_species_bulk()` (Query 6115, automática em lote,
`service_role`-only, mesmo padrão de `public.open_pokemon_catalog_
sourcing_run()`, Query 6103). `SECURITY DEFINER` executa com os
privilégios do dono da função — nenhum `GRANT` de tabela é necessário
nem desejável para nenhuma delas funcionar.

**`service_role` hardening desde a criação.** `card_primary_species`
já nasce com `REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ... FROM
anon, authenticated, service_role` (Query 6112) — mesmo padrão
corrigido de `collection_pokedex_reference` (Query 5087, Fatia B), não
o padrão mais antigo e incompleto de `pokedex` (Query 6030).

**Checagem de categoria sem precedente direto.** `trg_010` (Query
6113) é o primeiro trigger do projeto a impor "esta Card precisa ser
de `card_category.code = 'POKEMON'`" — auditoria desta rodada não
encontrou nenhum trigger equivalente em `database/schema/`. Roda só em
`BEFORE INSERT`; risco residual de `card.category_id` mudar depois de
resolvido está documentado como teórico (nenhum caminho de escrita
para isso existe hoje) em "Riscos".

## Alternativas consideradas e rejeitadas

- **Coluna `species_id` direto em `public.card`.** Rejeitada: viola
  ADR-011 (Catalog Domain genérico não pode carregar um conceito
  Pokémon-específico).
- **FK direta de `card_primary_species` para `catalog_import_row`**
  em vez de snapshot JSONB. Rejeitada: amarraria durabilidade da
  evidência a uma tabela comprovadamente efêmera (Query 2111).
- **Reaproveitar vocabulário `SPECIES_MATCH`/`USER_OVERRIDE`** (LDM-178)
  para `resolution_basis`. Rejeitada: mandato explícito de não
  misturar Primary Species da Card com Position Assignment do
  exemplar/Collection — vocabulários precisam ser fisicamente
  distintos, não só documentalmente.
- **Tabela de histórico dedicada** (ex.: `card_primary_species_history`).
  Rejeitada nesta rodada: `catalog_admin_action_log` já cobre o caso
  de uso (mesmo raciocínio de LDM-179); dedicada adicionaria
  complexidade sem necessidade demonstrada.
- **Soft delete (`is_active`)** em vez de DELETE físico para retratar
  uma resolução. Rejeitada: ausência de linha já é um estado válido e
  significativo ("não resolvido") nesta tabela — ao contrário de
  `card` (ADR-023), não há necessidade de preservar uma linha
  "desativada"; o motivo da retratação, se precisar ser auditado, vai
  para `catalog_admin_action_log`.
- **Uma única função de escrita cobrindo editorial e automático.**
  Rejeitada: os dois fluxos têm gates de autorização e semânticas de
  idempotência completamente diferentes (`is_admin()` vs.
  `service_role`; UPSERT auditado vs. bulk silencioso) — uma função
  única precisaria de um parâmetro "modo" só para bifurcar toda a
  lógica interna, replicando a confusão que `resolution_basis` já
  existe para evitar. Duas funções, cada uma com seu próprio contrato
  de autorização, seguem o mesmo racional de `internal.write_card()`
  ainda assim ser chamado por múltiplas funções públicas distintas.
- **Tabela de fila de reconciliação dedicada** para Cards
  `AMBIGUOUS`/`UNRESOLVED`. Rejeitada: a consulta "Cards Pokémon sem
  Primary Species resolvida" já é derivável por `NOT EXISTS` contra
  `card_primary_species` — ausência de linha já É a fila, sem
  necessidade de armazenamento duplicado. O array `details` retornado
  por `resolve_card_primary_species_bulk()` cobre a necessidade
  imediata de observabilidade por chamada.
- **ON CONFLICT DO UPDATE** em vez de `SELECT ... FOR UPDATE` +
  branch explícito em `admin_resolve_card_primary_species()`.
  Rejeitada: precisava capturar os valores ANTIGOS antes da escrita
  para montar `old_*` em `catalog_admin_action_log` — `ON CONFLICT`
  não exporia a linha antiga com a mesma clareza dentro da mesma
  instrução.

## Invariantes (finais, pós-REVISION-02)

1. Uma Card possui no máximo uma linha em `card_primary_species`
   (PK=FK em `card_id`).
2. `pokemon_species_id` sempre aponta para uma Species existente
   (FK RESTRICT) — nunca inferida por nome da Card.
3. `resolution_basis = AUTOMATIC_DEXID` exige `source_evidence` com o
   schema mínimo `{source: TCGDEX, tcgdex_dex_ids: array não-vazio,
   resolved_dex_id: number}` (`chk_card_primary_species_automatic_
   evidence_shape`, Query 6112 v1.1) e `resolved_by_user_id NULL`.
4. `resolution_basis = EDITORIAL_RECONCILIATION` exige
   `resolved_by_user_id NOT NULL`.
5. `card_id` e `created_at` são imutáveis após o INSERT (trg_020).
6. Uma Card só pode ter linha nesta tabela se
   `card.category_id` resolver para `card_category.code = 'POKEMON'`
   (trg_010, só em INSERT).
7. Ausência de linha é semanticamente "não resolvido" — nunca
   representado por um valor dentro da tabela.
8. Só duas funções `SECURITY DEFINER` podem escrever nesta tabela —
   nenhum papel tem `GRANT` de `INSERT`/`UPDATE`/`DELETE` direto
   (Queries 6114/6115).
9. Uma resolução automática nunca sobrescreve uma resolução editorial
   existente (`resolve_card_primary_species_bulk()`, branch
   `EDITORIAL_RECONCILIATION` → sempre `UNCHANGED`).
10. Evidência que regride (dexId que passa a estar ausente ou se
    tornar ambíguo numa reexecução) nunca desfaz uma resolução já
    feita — a linha existente não é tocada; só uma ação editorial
    explícita (Query 6114) substitui uma resolução por outra.
11. Um dexId com múltiplos valores distintos jamais gera resolução
    automática — sempre conta como `AMBIGUOUS`, nunca escolhido
    arbitrariamente.
12. **(REVISION-02)** `resolve_card_primary_species_bulk()` NUNCA
    executa `UPDATE` de `pokemon_species_id` — uma resolução
    `AUTOMATIC_DEXID` existente que diverge de uma nova evidência
    única não é sobrescrita, é classificada `CONFLICT` e preservada
    intacta. Bulk automático comprovadamente nunca substitui uma
    Species existente por outra, em nenhum cenário — só `INSERT`
    (linha nova) ou nenhuma escrita.
13. **(REVISION-02)** `p_evidence_batch` não pode exceder 10000 itens
    (`c_max_batch_size`) — acima disso, a chamada inteira é rejeitada
    antes de qualquer processamento, nunca truncada silenciosamente.

## Riscos

- **Cobertura de evidência incompleta (~12%, 760/6435 Cards POKEMON
  ativas).** A única fonte de evidência de dexId hoje
  (`catalog_import_row.raw_data`) é efêmera e não cobre 100% do
  universo. Isto **não é tratado como divergência que bloqueia este
  modelo** — é exatamente o caso que LDM-182/183 já antecipam
  ("casos ambíguos/ausentes seguem para reconciliação editorial
  MMKYU") e que a tabela suporta estruturalmente (ausência de linha =
  pendente). É, porém, um risco operacional real para a rodada de
  execução/sourcing futura: sem re-buscar a evidência na TCGdex antes
  de uma eventual limpeza adicional de `catalog_import_row`, esses 760
  casos podem precisar de reconciliação 100% manual, sem nenhum
  candidato automático.
- **`card.category_id` mutável no futuro sem trigger de re-checagem.**
  `trg_010` só valida a categoria no momento do INSERT. Se um caminho
  de UPDATE de `category_id` for criado depois (hoje não existe:
  `internal.write_card()` não expõe esse parâmetro), uma Card já
  vinculada poderia teoricamente mudar de categoria sem que
  `card_primary_species` seja notificada. Risco teórico no estado
  físico atual — não corrigido aqui por estar fora do escopo desta
  Card/entidade (tocaria `card`/`141_create_card_triggers.sql`).
- **Dependência de disponibilidade/estabilidade do contrato TCGdex**
  para qualquer resolução automática futura — mesma dependência já
  registrada para o restante do Pokémon Catalog Sourcing
  (`docs/06a-pokemon-catalog-sourcing.md`).
- **`resolve_card_primary_species_bulk()` ainda não é chamada por
  nada** (mandato item 5, "não implementar o pipeline agora"). O
  contrato existe e é estável, mas o Edge Function `import-catalog-
  cards` não foi alterado nesta rodada — a integração real (chamar a
  função ao final da importação, com try/catch não-bloqueante) fica
  para uma rodada futura de implementação.
- **Backfill do catálogo existente não foi executado** (mandato item
  8, "Não executar nada"). O contrato suporta o backfill (idempotente,
  reprocessável, aceita lotes de qualquer tamanho), mas nenhuma
  chamada real foi feita contra os 5675 Cards com evidência
  sobrevivente — isso é trabalho de uma rodada de execução futura,
  não desta.
- **Dedup de `tcgdex_dex_ids` idênticos tratada como não-ambígua** —
  decisão de design de `resolve_card_primary_species_bulk()` (Query
  6115): um array como `[25, 25]` é tratado como evidência única, não
  ambígua. Auditoria da rodada anterior não encontrou nenhum caso real
  de array com mais de 1 elemento (distinto ou repetido) em produção —
  esta é uma decisão preventiva sem caso real ainda observado que a
  force, revisável se o caso aparecer.
- **(REVISION-02; GATE-4-FIX-01 estende o mesmo risco a
  `EDITORIAL_PROTECTED`) Cards em `CONFLICT`/`EDITORIAL_PROTECTED` não
  têm fila persistida além do retorno da própria chamada.** Se o
  chamador (backfill script/Edge Function) não capturar e agir sobre
  `details` no momento da chamada, o `CONFLICT` ou o
  `EDITORIAL_PROTECTED` ficam visíveis de novo só na próxima vez que
  aquela Card reaparecer num lote — a linha existente permanece intacta
  e correta (nunca perdida), mas a lista "Cards com Species divergente
  entre TCGdex e o registrado" não é auto-descobrível por uma query
  simples como a lista de `UNRESOLVED` (que é ausência de linha).
  Mitigação operacional (não estrutural, fora desta rodada): o chamador
  deve logar/persistir `details` onde for conveniente (ex.: log do Edge
  Function, tabela de operação do backfill) se quiser um histórico de
  divergências entre chamadas.

## Divergências LDM × banco

Nenhuma divergência estrutural relevante encontrada entre LDM-175–190
e o estado físico real que justifique um STOP. O único ponto de
atenção — evidência de dexId hoje só sobrevive incidentalmente em
staging efêmero, não em local durável — é a lacuna que esta própria
Query 6112 fecha (o `source_evidence` snapshot); não é uma
contradição entre o que o LDM promete e o que o banco tem, é o motivo
de existir desta rodada.

## Sequência de migrations (próximos números livres)

Maior número usado no milhar 6000-6999: `6111`
(`6111_revoke_service_role_structural_privileges_pokemon_catalog.sql`).
Maior número usado no milhar 2000-2999: `2158`
(`2158_create_admin_create_card_variant_type_with_import_mapping_function.sql`).
Esta rodada (AUDIT-01 + REVISION-01 + REVISION-02 + GATE-4-FIX-01) usa:

| Query | Arquivo | Conteúdo |
|-------|---------|----------|
| 2159 | `2159_widen_catalog_admin_action_log_for_card_primary_species.sql` (v1.1) | Amplia as 3 CHECKs de `catalog_admin_action_log` — corrigida em PREMISE-DIVERGENCE-FIX-01 para partir do estado físico real (27/10/10), não do arquivo canônico `2010` desatualizado |
| 6112 | `6112_create_card_primary_species_table.sql` (v1.1) | Tabela, constraints (incl. contrato de evidência automática), índice, RLS, grants, hardening |
| 6113 | `6113_create_card_primary_species_triggers.sql` | 3 triggers (categoria, governança/imutabilidade, updated_at) |
| 6114 | `6114_create_admin_resolve_card_primary_species_function.sql` | Escrita individual/editorial, `is_admin()`-gated |
| 6115 | `6115_create_resolve_card_primary_species_bulk_function.sql` (v1.2) | Escrita bulk automática, `service_role`-only, `CONFLICT`/`conflict_count` + guard de 10000 itens + `details` diferencia `SAME_SPECIES`/`EDITORIAL_PROTECTED` dentro de `UNCHANGED` (GATE-4-FIX-01) |

`6116`/`2160` em diante permanecem livres para uma rodada futura de
execução (integração real com `import-catalog-cards`, execução do
backfill).

## Fora de escopo (confirmado não tocado nesta rodada)

Position Assignment, Species Match/Mismatch, USER_OVERRIDE, Primary
Representative, Completion REFERENCE_POSITION, frontend,
Forms/Varieties, inferência por nome da Card, Fatia D/E, edição de
`docs/`, implementação real do pipeline `import-catalog-cards`,
execução do backfill contra o banco real. Nenhum `git add`/`commit`/
`push` executado.
