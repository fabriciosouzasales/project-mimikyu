# Staging — Pokédex Foundation (Fatia A)

Rodada: `COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-01` (2026-09-04).

**Status: CONFIRMADO EXECUTADO E PROMOVIDO.** As 6 Queries de estrutura (`6030`/`6031`/`6040`/`6041`/`6050`/`6051`) foram aplicadas ao banco real em 2026-09-04 (`COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01`) e, após auditoria pós-implementação com resultado PASS, promovidas para `database/schema/` em 2026-09-04 (`COLLECTIONS-POKEDEX-POSITION-PHYSICAL-CANONICAL-PROMOTION-01`) — ver seção "Promoção canônica" abaixo. `6800` (validação) foi executada integralmente com resultado PASS e **permanece nesta pasta como evidência histórica**, deliberadamente **não promovida** para `database/schema/` (é um script de validação pontual da implementação, não estrutura persistente do módulo).

Escopo desta rodada: exclusivamente a Fatia A ("Canonical Pokédex Foundation") do fluxo aprovado em `COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-REVISION-01`/`FINAL-01` (conversa corrente). Fatias B (Collection Pokédex Reference + Adopted Scope), C (Card → Primary Species / sourcing), D (Position Assignment + Primary Representative) e E (REFERENCE_POSITION Completion) não são antecipadas.

## Arquivos

| Query | Objetivo |
|-------|----------|
| 6030 | `pokedex` — tabela |
| 6031 | `pokedex` — triggers (normalize/govern/touch_updated_at) + REVOKE EXECUTE desde a origem |
| 6040 | `pokedex_position` — tabela |
| 6041 | `pokedex_position` — triggers (govern/touch_updated_at — sem normalize, decisão explícita) + REVOKE EXECUTE desde a origem |
| 6050 | `pokedex_external_reference` — tabela |
| 6051 | `pokedex_external_reference` — triggers (normalize/govern/touch_updated_at) + REVOKE EXECUTE desde a origem |
| 6800 | Validação estrutural + comportamental + privilégios de função + nota de performance — **executada em 2026-09-04, resultado PASS**; mantida aqui como evidência histórica, não promovida |

## Numeração escolhida e justificativa

Módulo `6000`–`6999` = Pokémon Catalog Foundation (`STD-001`, Seção 10, confirmado como o módulo correto para "extensões conceitualmente distintas que pertençam ao mesmo módulo" — Pokédex é uma continuação do domínio Pokémon canônico iniciado em 02G, não um módulo novo). Dentro de `6000`–`6699` (estrutura), cada entidade ocupa um bloco de dez; o último bloco ocupado antes desta rodada era `6020`–`6029` (`pokemon_species_external_reference`). Confirmado via `Glob`/`ls` em `database/schema/` antes de escolher os números (nenhum arquivo `603*`/`604*`/`605*` pré-existente):

- `6030`/`6031` — `pokedex` (próximo bloco de dez livre).
- `6040`/`6041` — `pokedex_position` (bloco seguinte).
- `6050`/`6051` — `pokedex_external_reference` (bloco seguinte).
- `6800` — Validações (`X800`–`X899`), primeiro número livre da faixa; escolhida uma única Query consolidada para as 3 tabelas da Fatia A, em vez de três Queries por deslocamento `+800`, porque a validação comportamental cobre invariantes que atravessam as três tabelas (CASCADE/RESTRICT entre elas) — não corresponde a uma única entidade isoladamente.

## Decisões congeladas honradas (ver mandatos completos na conversa)

- `pokedex`/`pokedex_position` como conceitos próprios, não colapsados em `pokemon_species` (LDM-176, decisão reafirmada em `COLLECTIONS-POKEDEX-POSITION-PHYSICAL-MODELING-REVISION-01`).
- `position_number` e `pokemon_species.national_dex_number` permanecem campos distintos — nenhum CHECK/trigger cross-tabela exigindo igualdade para o Pokédex Nacional.
- Em `pokedex_position`, protegidos apenas `id`/`pokedex_id`/`species_id`/`created_at`; `position_number` deliberadamente corrigível administrativamente (dado editorial canônico).
- `collection.completion_policy` **não** alterado nesta rodada — Fatia A é exclusivamente Canonical Pokédex Foundation.
- `pokedex_position_external_reference` **não** criada — decisão fundamentada em precedente real do repositório (ver header de `6050`): entidades compostas de duas FKs já ancoradas (precedente `card_variant`) não recebem external reference própria; apenas entidades-raiz (precedente `card_set`/`pokemon_species`) recebem.
- `REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated` aplicado em toda trigger function nova já na Query de criação — lição incorporada desde a origem (achado do fechamento de segurança do incremento anterior, `COLLECTIONS-PHYSICAL-INCREMENT-02G-SECURITY-CLOSEOUT-FIX-01`/Query `6701`), não como correção posterior.
- Nenhum índice além dos gerados pelas PK/UNIQUE — nenhum índice especulativo (confirmado na Query 6800, Seção 1.7).

## Revisão (2026-09-04, `COLLECTIONS-POKEDEX-POSITION-PHYSICAL-STAGING-REVISION-01`)

Auditoria externa concluída sobre a versão 1.0 desta pasta; modelo/DDL aprovados em essência, 6 pontos corrigidos **somente neste staging** (nenhuma mudança de modelagem, nenhuma execução, nenhuma promoção):

1. **Least privilege de tabela** (`6030`/`6040`/`6050`, agora v1.1): `REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ... FROM anon, authenticated`, mesmo padrão de Query `2147`. Nenhum GRANT novo.
2. **`6800` — 2.3.4 (CHECK metadata)**: reescrito para usar uma combinação (`pokedex`, `external_pokedex_id`) inédita, isolando o CHECK como única regra violada — a versão anterior colidia também com as duas UNIQUE.
3. **`6800` — 1.10 (privilégios)**: complementado com `has_table_privilege()` por role/tabela/privilégio (`SELECT`/`INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`/`REFERENCES`/`TRIGGER`/`MAINTAIN`), provando privilégio EFETIVO — `information_schema.role_table_grants` sozinho vira checagem preliminar, não a prova final.
4. **`6800` — 2.3.6 (RESTRICT `asset_source`)**: reescrito para usar uma fonte externa sintética dedicada (nunca a linha real `POKEAPI`, também referenciada por `pokemon_species_external_reference`) + `GET STACKED DIAGNOSTICS` confirmando que o `foreign_key_violation` veio especificamente de `pokedex_external_reference_asset_source_id_fkey`.
5. **`6050` — redação de `external_pokedex_id`**: corrigida (header + `COMMENT ON COLUMN`), sem alterar schema — o campo é o id numérico estável da PokéAPI serializado como TEXT (ex.: `"1"`), nunca o slug/name (`"national"`).
6. **`6800` — 1.5/1.6**: toda checagem de constraint por `conname` passou a escopar também por `conrelid`, evitando falso positivo de constraint homônima em outra tabela.

Status após a revisão permaneceu `PROPOSTA — NÃO EXECUTADA` para todos os 8 arquivos, até a implementação real registrada na seção abaixo.

## Implementação real (2026-09-04, `COLLECTIONS-POKEDEX-POSITION-PHYSICAL-IMPLEMENTATION-01`)

As 6 Queries de estrutura foram aplicadas ao banco real (projeto Supabase `qjfutqujxrbzgrtkpgkg`) na ordem exata `6030` → `6031` → `6040` → `6041` → `6050` → `6051`, sem nenhuma alteração em relação ao conteúdo v1.1 auditado. Em seguida, `6800` foi executada integralmente: Seção 1 (estrutural, incluindo a prova definitiva por `has_table_privilege()`), Seção 2 (comportamental, `BEGIN...ROLLBACK`) e Seção 3 (privilégios de função) resultaram **PASS**, sem nenhum FAIL. Zero resíduo confirmado após o `ROLLBACK` e por contagem direta pós-execução — as 3 tabelas voltaram a 0 linhas e toda a fixture sintética (incluindo o `asset_source` sintético dedicado ao teste isolado de RESTRICT) foi revertida. Advisors de segurança/performance pós-implementação não revelaram achado inesperado: os únicos itens tocando as 3 tabelas novas foram INFO `rls_enabled_no_policy` (design pretendido) e INFO `unindexed_foreign_keys` em `pokedex_position.species_id` (decisão explícita de não antecipar índice especulativo, já documentada no header de `6040`).

## Promoção canônica (2026-09-04, `COLLECTIONS-POKEDEX-POSITION-PHYSICAL-CANONICAL-PROMOTION-01`)

Após auditoria pós-implementação externa com resultado PASS, as 6 Queries de estrutura (`6030`/`6031`/`6040`/`6041`/`6050`/`6051`) foram promovidas para `database/schema/`, com equivalência total de estrutura/constraints/grants/triggers/functions/`COMMENT` em relação ao staging aqui presente — a única mudança entre a cópia promovida e esta cópia de staging é o cabeçalho de Status/Data (de `PROPOSTA` para `CONFIRMADO EXECUTADO`) e o rodapé, que passou a registrar a confirmação de execução em vez do aviso de não-execução. `6800` **não foi promovida** — permanece exclusivamente nesta pasta, com seu próprio cabeçalho/rodapé atualizados para `CONFIRMADO EXECUTADO — resultado PASS`, como evidência histórica de validação executada, sem nenhuma alteração na lógica de asserções/fixtures validada.

Estado final da Fatia A: `pokedex`, `pokedex_position` e `pokedex_external_reference` são estrutura canônica confirmada (`database/schema/`), com 0 linhas cada — nenhum seed de dado, nenhum sourcing PokéAPI iniciado. Fatias B (Collection Pokédex Reference + Adopted Scope), C (Card → Primary Species), D (Position Assignment + Primary Representative) e E (REFERENCE_POSITION Completion) permanecem não implementadas.
