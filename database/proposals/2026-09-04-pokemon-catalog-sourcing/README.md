# Staging — Pokémon Catalog Sourcing (Initial Load)

| Campo | Valor |
|---|---|
| Rodada | `POKEMON-CATALOG-SOURCING-INITIAL-LOAD-PHYSICAL-STAGING-01` (base) + `...-REVISION-01` (11 correções GATE 4) + `...-REVISION-02` (6 correções residuais GATE 4) + `...-VALIDATION-REVISION-03` (2 correções finais, restritas a 6820) + `...-GATE-5-HOTFIX-6103-STAGING-01` (hotfix 6109, pós-primeira execução real) + `...-GATE-5-HOTFIX-6109-IMPLEMENTATION-01` (6109 aplicado; 6820 v2.2 executado até novo achado real) + `...-GATE-5-HOTFIX-6110-STAGING-01` (hotfix 6110, 2º achado runtime) + `...-GATE-5-HOTFIX-6110-IMPLEMENTATION-01` (6110 aplicado; `6820` v2.3 executado por completo, PASS) + `...-GATE-9-PROMOTION-RECONCILIATION-01` (promoção para `database/schema/` e reconciliação documental — esta rodada) |
| Data | 2026-09-04 |
| Status | **CLOSED / IMPLEMENTED / VALIDATED.** `6090`-`6110` (13 arquivos) **CONFIRMADO EXECUTADO** no banco real e **promovidos para `database/schema/`** (corpo SQL byte-idêntico ao desta pasta; apenas cabeçalho Status/Data atualizado na promoção). `6820` v2.3 **CONFIRMADO EXECUTADO — resultado PASS** (todas as 16 Seções, dentro de `BEGIN...ROLLBACK`, zero resíduo) — permanece nesta pasta como evidência histórica, **não promovido** para `database/schema/` (script de validação, mesmo padrão de `6800`/`6810`). Sourcing real via PokéAPI **ainda não executado** — pipeline fisicamente pronto, aguardando rodada própria de Initial Load. |
| Contrato canônico | `docs/06a-pokemon-catalog-sourcing.md` v1.2 (CANONICALIZED / AUDITED / COMMITTED / PUSHED, remote HEAD `807e5606aaded12e6c7ca60ed8d4035d6f90b69e`; v1.2 reconcilia o contrato com a sourcing foundation física implementada e promovida) |
| Gate | GATE 3 STAGING → GATE 4 (NO-GO, 11 correções) → GATE 3 REVISION-01 → GATE 4 (NO-GO residual, 6 correções, restrito a 6104/6105/6820) → GATE 3 REVISION-02 → GATE 4 FINAL AUDIT (6104/6105/6090-6108 PASS; 2 ajustes finais em 6820) → GATE 3 VALIDATION REVISION-03 → GATE 5 IMPLEMENTATION-01 (6090-6108 aplicados; erro real em 6103) → GATE 5 HOTFIX 6103 STAGING → GATE 5 HOTFIX 6109 IMPLEMENTATION (6109 aplicado; smoke test PASS; 6820 v2.2 avançou até novo erro real na Seção 9) → GATE 5 HOTFIX 6110 STAGING → GATE 5 HOTFIX 6110 IMPLEMENTATION (6110 aplicado; 6820 v2.3 executado por completo, PASS em todas as 16 Seções) → GATE 7 EVIDENCE AUDIT (PASS) → GATE 8 INDEPENDENT CLOSEOUT AUDIT (PASS) → **GATE 9 PROMOTION-RECONCILIATION-01** (promoção `database/schema/` + reconciliação documental — esta rodada) |

## O que esta pasta documenta — staging original e estado FINAL

**Histórico preservado sem reescrita**: esta pasta nasceu como staging puro —
a rodada original (`-PHYSICAL-STAGING-01` e as revisões `REVISION-01`/`02`/
`VALIDATION-REVISION-03`) materializou o contrato canônico em SQL de
proposta, pronta para auditoria pré-implementação, sem nenhuma execução real
de banco: nenhuma chamada a `apply_migration`/`execute_sql`, nenhuma
promoção, nenhuma chamada real à PokéAPI, nenhuma alteração de
`docs/06a-pokemon-catalog-sourcing.md`, nenhum commit/push. Essa descrição
era exata **naquele momento** e permanece válida como registro histórico das
seções REVISION-01/02/VALIDATION REVISION-03 abaixo.

**Estado FINAL desta proposta (pós `GATE-5-IMPLEMENTATION-01` + hotfixes
`6109`/`6110` + `GATE-9-PROMOTION-RECONCILIATION-01`), para eliminar
qualquer ambiguidade**:

- `6090`-`6110` (13 arquivos) foram **executados** no banco real
  (`qjfutqujxrbzgrtkpgkg`).
- Os 13 arquivos foram **promovidos** para `database/schema/` (corpo SQL
  byte-idêntico ao desta pasta; apenas cabeçalho Status/Data atualizado na
  promoção).
- `6820` v2.3 foi **executado por completo e resultou PASS** (16 Seções,
  dentro de `BEGIN...ROLLBACK`, zero resíduo) — **permaneceu nesta pasta**
  como evidência histórica, não promovido (mesmo padrão de `6800`/`6810`).
- **Sourcing real via PokéAPI ainda NÃO ocorreu** — a foundation física está
  pronta, mas a carga de dados em si é uma rodada futura própria
  (`POKEMON-CATALOG-SOURCING-INITIAL-LOAD`).

Ver seção "GATE 9 PROMOTION-RECONCILIATION-01 — promoção e fechamento",
abaixo, para o detalhamento completo do fechamento.

## REVISION-01 — resposta ao GATE 4 (NO-GO)

GATE 4 auditou os SQL reais desta proposta e retornou **NO-GO para
implementação**, com 11 correções obrigatórias. Esta rodada aplica as 11
correções, mantendo `6090`/`6091`/`6102` intocados (GATE 4 confirmou PASS
para os três). Resumo das mudanças por arquivo — ver a matriz completa de
correção no relatório de entrega desta rodada (não repetida aqui para evitar
duplicação/divergência entre os dois textos):

- `6106` — reescrito (v2.0): reconciliação "lockstep" para Initial Load
  (Region/Generation/Species NEW podem validar-se mutuamente dentro do MESMO
  snapshot, não apenas contra `external_reference` já existente) e checagem
  independente dos dois eixos UNIQUE de `pokemon_generation` (`code` e
  `ordinal_number` tratados como colisões separadas, nunca exigindo conflito
  simultâneo na mesma linha).
- `6100`/`6101` — `pokemon_catalog_sourcing_run` ganha um novo CHECK
  (`ck_..._dry_run_never_applying`) e a máquina de estados (6101) passa a ser
  `run_type`-aware: os grafos de transição de DRY_RUN e APPLY são
  explicitamente disjuntos (DRY_RUN nunca entra em APPLYING; APPLY nunca
  entra em ACQUIRING/PLANNING), reforçado em CHECK e trigger (defesa em
  profundidade).
- `6103` — o handler de `unique_violation` do claim passa a inspecionar
  `CONSTRAINT_NAME` via `GET STACKED DIAGNOSTICS`: só traduz para
  `SOURCE_BUSY` a violação do índice parcial de run ativo; qualquer outra
  colisão UNIQUE é relançada sem modificação.
- `6104` — reescrito (v2.0): pré-condição passa a exigir `status = 'ACQUIRING'`
  (não mais `PENDING`) — a transição PENDING→ACQUIRING agora é
  responsabilidade exclusiva do novo `heartbeat_pokemon_catalog_sourcing_run`
  (6107). Ganha 13 blocos de validação estrutural do snapshot (IDs
  ausentes/vazios/não numéricos, duplicidade de external_id/entry/position,
  S≠P, `national_dex_number` = `position_number`, `external_pokedex_id`/`code`
  do National Pokédex, resolução de `main_region_external_id`/
  `generation_external_id`, números ≤0) antes de qualquer PLAN válido.
- `6105` — reescrito (v2.0): lock de linhas canônicas (`FOR UPDATE`) em ordem
  fixa determinística (Region→Generation→Species→Pokedex, cada família por
  `id ASC`) entre a reconciliação fresca e a escrita, fechando a janela de
  corrida; grava `source_url`/`metadata` do snapshot nas External References;
  pós-condição dupla (contagem de DML vs. reconciliação prévia + reconciliação
  final exigindo 100% UNCHANGED) antes de permitir COMPLETED.
- `6107` (NOVO, auxiliar) — `heartbeat_pokemon_catalog_sourcing_run`:
  mecanismo SERVICE_ROLE ONLY para o caller manter/registrar
  `heartbeat_at` durante aquisição HTTP longa, e efetivar a transição real
  PENDING→ACQUIRING no momento em que a aquisição de fato começa (não dentro
  da transação do PLAN).
- `6108` (NOVO, auxiliar) — `close_failed_pokemon_catalog_sourcing_run`:
  mecanismo SERVICE_ROLE ONLY para o caller marcar imediatamente como FAILED
  um run ATIVO cujo erro já foi capturado (ex.: exceção de APPLY), liberando
  o guard de run ativo sem esperar os 30 minutos do stale recovery.
- `6820` — reescrito (v2.0) como prova executável real (ver Seção própria
  abaixo), sem placeholders nos itens obrigatórios.

## REVISION-02 — resposta ao segundo GATE 4 (NO-GO residual)

O GATE 4 re-auditou os SQL da REVISION-01 e retornou **NO-GO residual**,
restrito a `6104`/`6105`/`6820` — `6090`, `6091`, `6100`, `6101`, `6102`,
`6103`, `6106`, `6107`, `6108` permanecem intocados desde a REVISION-01.
Nenhum objeto novo foi criado nesta rodada (apenas edições em arquivos
já existentes).

- `6104` (v2.1) — 5 novas categorias de VALIDATION FAILURE (itens 14-18,
  totalizando 18): `REGION_CODE_INVALID`/`GENERATION_CODE_INVALID` (mesmo
  formato `^[A-Z][A-Z0-9_]*$` dos CHECKs físicos de 6060/6000, replicado
  aqui para que nenhum PLAN COMPLETED só descubra o problema durante o
  INSERT do APPLY); `NATURAL_KEY_DUPLICATE_IN_SNAPSHOT` (Region.code,
  Generation.code, Generation.ordinal_number ou Species.national_dex_number
  duplicados DENTRO do próprio snapshot — distinto de EXTERNAL_ID_DUPLICATE,
  que checa a identidade externa, não a chave natural); `SOURCE_URL_INVALID`/
  `METADATA_INVALID` (agora que 6105 persiste essas evidências, sua ausência
  ou malformação também vira defeito de snapshot). O item 13
  (`NON_POSITIVE_NUMBER`) foi corrigido: a comparação `<= 0` deixava um valor
  `NULL` passar (lógica de três valores do SQL); agora é `IS NULL OR <= 0`.
- `6105` (v2.1) — corrigido o cálculo de `apply_summary.unchanged`: a v2.0
  usava a reconciliação PÓS-escrita (`v_post`), que a essa altura já
  reclassifica a própria linha recém-inserida/atualizada como UNCHANGED,
  produzindo dupla contagem (`inserted + updated + unchanged` somava mais do
  que o total processado). Corrigido para usar a reconciliação PRÉ-escrita
  (`v_fresh`, calculada na fase (c) do protocolo de locks). `v_post`
  permanece exclusivamente como prova da postcondition "100% UNCHANGED",
  nunca mais como fonte de números do summary. Nenhuma mudança no protocolo
  de locks nem nas demais postconditions.
- `6820` (v2.1) — três correções estruturais: (1) removida a renomeação
  temporária de `asset_source.code` (`code` é imutável por desenho, Query
  201 — o script agora opera diretamente sobre a linha POKEAPI real,
  resolvida uma única vez na Seção 0, com uma pré-condição explícita de
  ambiente idle antes de prosseguir); (2) corrigida uma violação real de
  role choreography na Seção 13 (o fixture de "divergência concorrente"
  fazia INSERT/SELECT direto em `pokemon_region` enquanto a sessão ainda
  estava sob `SET LOCAL ROLE service_role` — que não tem NENHUM grant nessa
  tabela; executado de verdade, teria falhado por permissão antes do teste
  que importa); (3) Seção 2 reescrita como prova programática (loop sobre as
  8 tabelas canônicas × 4 privilégios, mais `pokedex_position`, mais a
  matriz completa de EXECUTE das 6 RPCs/auxiliares e das 6 funções de
  trigger). Nova Seção 15 prova via PLAN real as 5 categorias novas de 6104;
  Seção 13 ganhou asserções de "sem dupla contagem" no primeiro APPLY; Seção
  14 (idempotência) passou a exigir inserted=0/updated=0/unchanged=total em
  TODAS as famílias (antes só regions/positions eram checados nesse nível).

## Ordem de aplicação real (diferente da numeração de arquivo)

A numeração de arquivo reflete a família do objeto (Seção 15 do contrato:
tabela → triggers → funções → auxiliares 6106+ → validação), não
necessariamente a ordem cronológica de `apply_migration`. A ordem real de
aplicação, quando esta proposta for implementada, é:

1. `6090` — tabela `pokemon_generation_external_reference`
2. `6091` — triggers de `pokemon_generation_external_reference`
3. `6100` — tabela `pokemon_catalog_sourcing_run` (+ sequence + índice parcial)
4. `6101` — triggers/máquina de estados de `pokemon_catalog_sourcing_run`
5. `6102` — `compute_pokemon_catalog_sourcing_snapshot_hash()`
6. `6103` — `open_pokemon_catalog_sourcing_run()`
7. **`6106`** — `reconcile_pokemon_catalog_sourcing_snapshot()` (AUXILIAR — deve
   existir antes de 6104/6105, que a chamam; ver nota no próprio arquivo)
8. **`6107`** — `heartbeat_pokemon_catalog_sourcing_run()` (AUXILIAR — deve
   existir antes de 6104, que agora exige `status = 'ACQUIRING'` como
   pré-condição de PLAN; é 6107 quem efetiva essa transição)
9. `6104` — `plan_pokemon_catalog_sourcing_run()`
10. `6105` — `apply_pokemon_catalog_sourcing_run()`
11. **`6108`** — `close_failed_pokemon_catalog_sourcing_run()` (AUXILIAR —
    independente de 6104/6105 em termos de dependência de objeto, mas
    logicamente parte do mesmo ciclo de closeout do APPLY; pode ser aplicado
    a qualquer momento após 6101)
12. `6820` — validação (não executado nesta rodada)

## VALIDATION REVISION-03 — resposta ao GATE 4 FINAL AUDIT

GATE 4 FINAL AUDIT confirmou **PASS** para `6104` v2.1, `6105` v2.1 e para
todos os demais `6090-6108` (preservados sem alteração nesta rodada). Restaram
2 ajustes, ambos restritos a `6820` (validação; não afeta nenhum SQL
funcional):

1. **SECURITY EXECUTE MATRIX**: a Seção 2 (2.5/2.6) de `6820` provava
   `service_role EXECUTE = TRUE` nas 6 RPCs client-facing, mas testava
   `anon`/`authenticated` apenas num subconjunto parcial das 6 funções, não a
   matriz completa. Corrigido com um duplo `FOREACH` sobre dois arrays novos
   (`v_client_functions`, `v_client_roles`): para cada uma das 6 funções,
   prova `service_role=TRUE` e, para cada role em `{anon, authenticated}`,
   prova `EXECUTE=FALSE` — as 18 combinações (6 × 3), sem duplicar código.
2. **GENERATION_CODE_INVALID**: a Seção 15 já provava `REGION_CODE_INVALID`
   (15.5) mas não tinha teste real equivalente para `GENERATION_CODE_INVALID`
   — categoria irmã, também presente em `6104` desde a REVISION-02 (item
   15/18). Adicionada Seção 15.6 (snapshot com `generations[].code` fora do
   formato `^[A-Z][A-Z0-9_]*$`), provando via PLAN real `outcome =
   VALIDATION_FAILURE` e `error_summary` contendo `GENERATION_CODE_INVALID`.
   15.5 foi preservado integralmente — os dois testes coexistem.

`6820` passa de v2.1 para v2.2. Nenhum objeto novo foi criado; nenhuma outra
Seção de `6820` foi tocada.

## Resumo de cada objeto

| Arquivo | Objeto | Papel |
|---|---|---|
| 6090 | `pokemon_generation_external_reference` (tabela) | Identidade externa de Generation; resolve `species[].generation_external_id`. Não resolve `main_region_external_id` (já coberto por 6070). PASS no GATE 4 — inalterado. |
| 6091 | 3 triggers de 6090 | Normalização, imutabilidade de identidade, `touch_updated_at` — mesmo padrão de 6071. PASS no GATE 4 — inalterado. |
| 6100 | `pokemon_catalog_sourcing_run` (tabela + sequence + índice parcial) | Run ledger dual DRY_RUN/APPLY (Seção 7). Índice parcial `uq_pokemon_catalog_sourcing_run_active_source` é o próprio mecanismo de concorrência (não é índice de performance). REVISION-01: novo CHECK `ck_..._dry_run_never_applying`. |
| 6101 | 3 triggers de 6100 | Máquina de estados `run_type`-aware (REVISION-01): DRY_RUN e APPLY têm grafos de transição explicitamente disjuntos (DRY_RUN nunca APPLYING; APPLY nunca ACQUIRING/PLANNING); imutabilidade de identidade; `started_at`/`finished_at` automáticos. |
| 6102 | `compute_pokemon_catalog_sourcing_snapshot_hash(jsonb)` | Autoridade única do hash SHA-256 lowercase (Seção 6). PASS no GATE 4 — inalterado. |
| 6103 | `open_pokemon_catalog_sourcing_run(text, uuid)` | Claim de run: stale recovery (30 min) → validação de preflight (se APPLY) → INSERT com tradução SELETIVA (REVISION-01) de `unique_violation` em `SOURCE_BUSY` — só para a constraint do índice parcial de run ativo; qualquer outra colisão UNIQUE é relançada. |
| 6104 | `plan_pokemon_catalog_sourcing_run(uuid, jsonb)` | PLAN do DRY_RUN: pré-condição exige `status = 'ACQUIRING'` (REVISION-01). 18 validações estruturais do snapshot antes de qualquer PLAN válido (13 da REVISION-01 + 5 da REVISION-02: códigos fora de formato, natural key duplicada no snapshot, source_url/metadata inválidos). Reconciliação read-only via 6106. |
| 6105 | `apply_pokemon_catalog_sourcing_run(uuid, jsonb)` | APPLY: valida preflight + hash, fresh reconciliation via 6106, lock determinístico das linhas canônicas casadas (REVISION-01, item 7), escrita atômica com evidência de origem (`source_url`/`metadata`, item 8), pós-condição dupla antes de COMPLETED (item 9). `apply_summary.unchanged` vem da reconciliação pré-escrita (REVISION-02 — corrige dupla contagem). |
| 6106 | `reconcile_pokemon_catalog_sourcing_snapshot(uuid, jsonb)` (AUXILIAR) | Classificação NEW/UNCHANGED/UPDATE_NAME/DIVERGENT por família — centralizada para ser usada IDENTICAMENTE por PLAN e APPLY. REVISION-01: reconciliação "lockstep" para Initial Load (item 1) + eixos UNIQUE de Generation checados independentemente (item 2). |
| 6107 | `heartbeat_pokemon_catalog_sourcing_run(uuid)` (AUXILIAR, NOVO REVISION-01) | Efetiva PENDING→ACQUIRING no início real da aquisição HTTP e atualiza `heartbeat_at` durante aquisição longa. SERVICE_ROLE ONLY. Ver item 4 do GATE 4. |
| 6108 | `close_failed_pokemon_catalog_sourcing_run(uuid, text)` (AUXILIAR, NOVO REVISION-01) | Fecha imediatamente como FAILED um run ATIVO cujo erro já foi capturado pelo caller, liberando o guard de run ativo sem esperar o stale recovery de 30 min. SERVICE_ROLE ONLY. Ver item 5 do GATE 4. |
| 6820 | Script de validação | Reescrito (v2.3) como prova executável real dentro de `BEGIN...ROLLBACK`, operando diretamente sobre a linha POKEAPI real (sem swap/rename — REVISION-02), com matriz completa de EXECUTE (6 funções x 3 roles), teste real de GENERATION_CODE_INVALID (VALIDATION REVISION-03) e fixture da Seção 9 corrigido para `CLOCK_TIMESTAMP()` (HOTFIX 6110). **CONFIRMADO EXECUTADO — resultado PASS** em `GATE-5-HOTFIX-6110-IMPLEMENTATION-01`: todas as 16 Seções, dentro de `BEGIN...ROLLBACK`, zero resíduo. Não promovido para `database/schema/` — permanece nesta pasta como evidência histórica (mesmo padrão de `6800`/`6810`). |

## Auxiliares 6106+ — justificativa da numeração "6106+"

O contrato (Seção 15) reserva a faixa 6106+ para "funções auxiliares
(reconciliação de run stale/órfão etc.), conforme desenho de GATE 3". Esta
proposta usa **três** auxiliares, todos com justificativa objetiva de
necessidade (nenhuma criação especulativa de objeto):

1. **`reconcile_pokemon_catalog_sourcing_snapshot` (6106)** — a lógica de
   classificação por família (Seção 9) é idêntica entre PLAN (somente
   leitura) e APPLY ("fresh reconciliation", Seção 10), e agora também é
   chamada uma terceira vez dentro do próprio APPLY como pós-condição final
   (item 9 do GATE 4). Duplicar essa lógica criaria risco real de os pontos
   divergirem silenciosamente — exatamente o tipo de falha que o contrato
   existe para prevenir. Centralizado em um único helper interno (sem GRANT
   EXECUTE a nenhum role — só é chamado internamente por 6104/6105, que já
   são SECURITY DEFINER de owner `postgres`).

2. **`heartbeat_pokemon_catalog_sourcing_run` (6107, NOVO REVISION-01)** —
   exigido pelo item 4 da auditoria GATE 4: a v1.0 fazia PLAN (6104) mover o
   run de PENDING para ACQUIRING internamente, dentro da própria transação de
   PLAN — o que significa que o run "aparentava" estar em aquisição só
   durante a chamada de PLAN, não durante a aquisição HTTP real (que ocorre
   ANTES, no script Deno chamador). GATE 4 exigiu que a observabilidade de
   ACQUIRING reflita a aquisição HTTP de fato, e que exista um mecanismo
   SERVICE_ROLE ONLY para manter `heartbeat_at` vivo durante essa janela
   potencialmente longa. Como essa responsabilidade é ortogonal a PLAN (que
   agora exige `status = 'ACQUIRING'` como pré-condição, em vez de fazer a
   transição ele mesmo) e a nenhuma outra função existente cobre esse
   propósito, um auxiliar novo e dedicado é a opção correta — inseri-la em
   `open_run` (6103) misturaria a responsabilidade de claim com a de
   acompanhamento de progresso de uma aquisição já em andamento.

3. **`close_failed_pokemon_catalog_sourcing_run` (6108, NOVO REVISION-01)** —
   exigido pelo item 5 da auditoria GATE 4: `apply_pokemon_catalog_sourcing_run`
   (6105) preserva, por desenho aprovado, o comportamento
   "divergência/erro → RAISE EXCEPTION → rollback canônico total" (nenhuma
   escrita parcial sobrevive). Mas isso também reverte a própria transição
   PENDING→APPLYING, deixando o run "preso" em PENDING e bloqueando a Fonte
   (via o índice UNIQUE parcial de run ativo) por até 30 minutos, até o
   stale recovery de `open_run` agir. Esta função dá ao caller (que já
   capturou a exceção em seu próprio try/catch) um meio imediato de marcar
   aquele run como FAILED, sem esperar o threshold. Não foi absorvida por
   nenhuma função existente porque nenhuma delas roda DEPOIS que a exceção do
   APPLY já reverteu a transação — só pode existir como uma chamada nova e
   independente do caller.

Nenhum quarto auxiliar foi criado: a reconciliação de run stale/órfão
permanece inline em `open_run` (6103), por ser uma única instrução `UPDATE`
sem lógica compartilhada com outra função — extraí-la para um arquivo à parte
não reduziria duplicação nem risco.

## Grants e Revokes — auditoria explícita (Seção 13/14 do contrato)

| Objeto | service_role | PUBLIC/anon/authenticated |
|---|---|---|
| `pokemon_generation_external_reference` (tabela) | Nenhum grant direto (RLS sem policy fecha tudo) | REVOKE TRUNCATE/REFERENCES/TRIGGER/MAINTAIN |
| `pokemon_catalog_sourcing_run` (tabela) | **GRANT SELECT apenas** (decisão explícita desta rodada — ver justificativa abaixo) | REVOKE TRUNCATE/REFERENCES/TRIGGER/MAINTAIN; nenhum SELECT/INSERT/UPDATE/DELETE |
| `compute_pokemon_catalog_sourcing_snapshot_hash` | GRANT EXECUTE | REVOKE ALL |
| `open_pokemon_catalog_sourcing_run` | GRANT EXECUTE | REVOKE ALL |
| `plan_pokemon_catalog_sourcing_run` | GRANT EXECUTE | REVOKE ALL |
| `apply_pokemon_catalog_sourcing_run` | GRANT EXECUTE | REVOKE ALL |
| `reconcile_pokemon_catalog_sourcing_snapshot` (6106, auxiliar) | **Nenhum grant** (chamado internamente por 6104/6105, que já são SECURITY DEFINER de owner `postgres` — não depende de GRANT) | REVOKE ALL |
| `heartbeat_pokemon_catalog_sourcing_run` (6107, auxiliar, NOVO) | GRANT EXECUTE | REVOKE ALL |
| `close_failed_pokemon_catalog_sourcing_run` (6108, auxiliar, NOVO) | GRANT EXECUTE | REVOKE ALL |
| 6 funções de trigger (6091 + 6101; 3 de cada) | Nenhum grant (disparadas implicitamente) | REVOKE ALL |

**Decisão explícita — `pokemon_catalog_sourcing_run` recebe `GRANT SELECT` a
`service_role`, e é a ÚNICA tabela desta proposta com qualquer grant direto**:
o contrato (Seção 14) permite explicitamente que o run ledger "possua grants
próprios mínimos, explicitamente definidos e auditados no GATE 3 STAGING —
nunca acesso irrestrito". O caso de uso real: o script chamador (Deno) precisa
poder consultar o estado de um run (polling, diagnóstico, encontrar o
`preflight_run_id` de um DRY_RUN anterior) sem depender de as RPCs
retornarem tudo em toda chamada. Nenhum `INSERT`/`UPDATE`/`DELETE` direto é
concedido — toda escrita flui exclusivamente por `open_run`/`PLAN`/`APPLY`
(SECURITY DEFINER, executam como owner `postgres`, não dependem de GRANT de
tabela). Como `service_role` no Supabase possui `BYPASSRLS`, este grant de
SELECT é um privilégio real (não cosmético) e por isso está documentado aqui
explicitamente, conforme exigido.

**Decisão explícita — REVOKE EXECUTE sempre nomeando `PUBLIC, anon,
authenticated`** (não apenas `PUBLIC`): o precedente mais recente do
repositório (`6071`) sempre nomeia os três explicitamente; um precedente
anterior (`3933`) usa apenas `GRANT ... TO service_role` sem `REVOKE`
explícito, confiando em privilégio padrão. Como não há certeza documentada de
que o Supabase nunca concede `EXECUTE` padrão a `anon`/`authenticated` em
funções novas, esta rodada segue o padrão mais rigoroso (`6071`) em todas as
13 funções desta proposta (7 RPCs/auxiliares — 6102, 6103, 6104, 6105, 6106,
6107, 6108 — mais 6 funções de trigger — 3 de 6091 + 3 de 6101), como defesa
em profundidade — para satisfazer sem ambiguidade a exigência literal do 06a
("PUBLIC/anon/authenticated sem EXECUTE em nenhuma delas"). **Correção
REVISION-01**: a v1.0 deste README afirmava "9 funções" e "9 funções de
trigger (6091 + 6101)" — ambas as contagens estavam erradas; 6091 + 6101
somam **6** funções de trigger (3 cada), não 9. Corrigido nesta rodada
(item 11 da auditoria GATE 4).

## Índices propostos — justificativa individual

| Índice | Tipo | Justificativa |
|---|---|---|
| `uq_pokemon_generation_external_reference_generation_source` | UNIQUE (implícito de constraint) | Identidade: uma Generation não pode ter duas referências para a mesma Fonte. |
| `uq_pokemon_generation_external_reference_source_external` | UNIQUE (implícito de constraint) | Identidade: um `external_generation_id` não aponta para duas Generations na mesma Fonte. |
| `uq_pokemon_catalog_sourcing_run_code` | UNIQUE (implícito de constraint) | `run_code` é identificador público do run. |
| **`uq_pokemon_catalog_sourcing_run_active_source`** | UNIQUE parcial | **Não é um índice de performance** — é o mecanismo de concorrência exigido pela Seção 7.2 (no máximo um run ativo por Fonte; base do `SOURCE_BUSY`). |

Nenhum índice especulativo foi adicionado (nenhum índice isolado por
`status`, `run_type` ou `asset_source_id` fora do parcial acima) — ausência de
padrão de acesso PLAN/APPLY que o justifique nesta rodada, mesma disciplina já
aplicada em 6020/6040/6050/6070.

## Mapa contrato (06a) → arquivo SQL

| Seção do 06a | Arquivo(s) |
|---|---|
| 4.0 (canonical_name / VALIDATION FAILURE) | 6104 |
| 4.2 (Region não resolvida → DIVERGENT) | 6106 (generations) |
| 4.3 (Species: `external_species_id` exclusivo; cross-check nacional; S=P) | 6104 (S=P), 6106 (generation_id de species) |
| 5.1 (payload guard ≤ 25.000) | 6104 |
| 6 (hash determinístico SHA-256) | 6102 |
| 7.1 (fluxo DRY_RUN/APPLY, ACTIVE/TERMINAL, disjunção run_type-aware) | 6100, 6101 |
| 7.2 (open run, stale 30min, SOURCE_BUSY seletivo, heartbeat) | 6103, 6107 |
| 8 (DRY_RUN: discovery→PLAN, pré-condição ACQUIRING, validação estrutural) | 6104, 6107 |
| 9 (reconciliação por família, natural keys — incl. eixos independentes de Generation, DIVERGENT nunca auto-bind, lockstep Initial Load) | 6106 |
| 9.4 (Positions, dois eixos UNIQUE) | 6106, 6105 |
| 10 (APPLY: fresh reconciliation, lock determinístico, evidência de origem, escrita atômica, pós-condição dupla, ordem exata) | 6105 |
| 10 (closeout de falha do APPLY sem esperar stale recovery) | 6108 |
| 13 (SERVICE_ROLE ONLY, sem DML direto de service_role em tabelas canônicas) | Grants de 6090/6100/6104/6105/6106/6107/6108 |
| 14 (Security PASS, grants mínimos do run ledger) | Grants de 6100 |
| 15 (numeração 6090-6108, 6820) | Todos os arquivos |

## Riscos e divergências identificados nesta rodada

**Nota REVISION-01**: o item abaixo sobre ausência de lock explícito na
janela fresh-reconciliation→escrita (antiga entrada 1 da v1.0 deste README)
foi classificado incorretamente como "item de hardening para uma futura
revisão". GATE 4 (item 7 da auditoria) rejeitou essa classificação
explicitamente: a ausência de lock formal é um **requisito
pré-implementação**, não um refinamento opcional pós-implementação — uma
condição de corrida silenciosa sobre escrita canônica é, por definição, um
bloqueio de GO/NO-GO, não um "nice to have". O item foi **RESOLVIDO** nesta
rodada (6105 v2.0): lock de linhas canônicas (`FOR UPDATE OF <alias>`) em
ordem fixa determinística — Region → Generation → Species → Pokedex, cada
família ordenada por `id ASC` — aplicado entre a reconciliação fresca e a
escrita, fechando formalmente a janela TOCTOU para linhas EXISTENTES.
Colisão de linhas NEW permanece protegida apenas pelas UNIQUEs (aceito
explicitamente pelo GATE 4, desde que qualquer conflito aborte a transação
inteira — o que já é o comportamento de UNIQUE violation não capturado).
Ordem de lock fixa e idêntica em toda execução de `apply_pokemon_catalog_sourcing_run`
evita deadlock por definição (nenhuma outra função adquire essas linhas em
ordem diferente).

1. **(RESOLVIDO nesta rodada — ver nota acima)** Concorrência na janela
   fresh-reconciliation→escrita do APPLY. Antes: sem lock formal,
   classificado incorretamente como hardening futuro. Agora: lock
   determinístico `FOR UPDATE` em ordem fixa (Region→Generation→Species→
   Pokedex, por `id ASC`), fechando a janela para linhas existentes.
2. **`6820` (v2.0, REVISION-01) passou a exercer as RPCs reais fim a fim**,
   incluindo as Seções 8, 9, 12, 13 e 14 que na v1.0 estavam documentadas como
   "PENDENTE DE EXECUÇÃO REAL". **Nota REVISION-02 (item 3 do segundo GATE 4,
   NO-GO residual)**: a técnica original de swap temporário do
   `asset_source.code = 'POKEAPI'` foi **REJEITADA e removida** — `code` é
   imutável por Query 201 e o GATE 4 não aceitou nem uma alteração revertida
   via `ROLLBACK` envolvente como prática válida em script de prova. `6820`
   v2.1 passou a operar diretamente sobre a linha `POKEAPI` real (resolvida
   por `SELECT`, sem qualquer `UPDATE`), com uma pré-condição que aborta o
   script caso já exista um run `ACTIVE` para essa Fonte — eliminando a
   necessidade de mascarar `code` para evitar colisão com HTTP/produção. O
   script inteiro continua rodando dentro de `BEGIN ... ROLLBACK`, garantindo
   zero resíduo mesmo em execução bem sucedida (item 10 do primeiro GATE 4).
   Continua **NÃO EXECUTADO nesta rodada** — apenas escrito/revisado — por
   instrução explícita de NÃO executar banco nesta REVISION-02; a execução
   real fica para a rodada de implementação.
3. **PLAN (6104) usa `RETURN` normal (persiste FAILED) para VALIDATION
   FAILURE estrutural do snapshot, mas `RAISE EXCEPTION` (rollback total,
   inclusive da transição de status) para erros de chamada inválida
   (precondição, hash NULL, payload malformado).** Esta assimetria foi
   **explicitamente APROVADA por Fabrício nesta REVISION-01**: "VALIDATION
   FAILURE de PLAN pode persistir FAILED via RETURN; APPLY continua RAISE
   para rollback total; falha do APPLY ganha closeout separado." Não é mais
   um ponto em aberto para confirmação do auditor — é uma decisão de
   engenharia fechada, preservando auditoria de runs que genuinamente
   tentaram rodar e falharam por dado ruim, versus descartar por completo
   chamadas estruturalmente inválidas.
4. **APPLY (6105) usa `RAISE EXCEPTION` (rollback total, inclusive da
   transição PENDING→APPLYING) para QUALQUER divergência detectada na fresh
   reconciliation ou na pós-condição final** — isto segue a letra do
   contrato ("Divergência detectada → RAISE EXCEPTION antes de qualquer
   commit canônico", Seção 10) e foi confirmado como comportamento desejado
   pelo item 5 do GATE 4. A consequência antes apontada como risco (run
   "preso" em PENDING, bloqueando a Fonte por até 30 min) está **RESOLVIDA**
   nesta rodada: `close_failed_pokemon_catalog_sourcing_run` (6108) dá ao
   caller, que já capturou a exceção em seu try/catch, um meio imediato
   SERVICE_ROLE ONLY de marcar aquele run como FAILED e liberar o guard de
   run ativo, sem esperar o stale recovery.
5. **Seção 11 do relatório de entrega desta rodada confirma zero atividade
   de banco/sourcing real** — todos os arquivos foram apenas escritos/editados
   em disco via `Write`/`Edit`, nenhum `apply_migration`/`execute_sql` foi
   chamado nesta REVISION-01, assim como na rodada base. **Nota REVISION-02**:
   mesma disciplina mantida — zero `apply_migration`/`execute_sql`, zero
   commit/push, apenas edições em arquivos já existentes (nenhum objeto novo).
6. **`6820` (REVISION-02, itens 4 e 5 do segundo GATE 4)**: auditoria
   apontou dois defeitos que só se manifestariam em execução real (não
   detectáveis por leitura superficial): (a) Seção 13 alternava
   `SET LOCAL ROLE service_role` com DML direto de fixture em
   `pokemon_region` sem `RESET ROLE` intermediário — como `service_role` não
   tem grants diretos nessa tabela, a execução real falharia com erro de
   permissão; corrigido com pares explícitos `SET LOCAL ROLE`/`RESET ROLE`
   isolando cada chamada de entrypoint de cada acesso direto de fixture. (b)
   Não havia prova programática de que `service_role` tem zero DML direto
   nas 8 tabelas canônicas Pokémon/Pokédex nem de que apenas os 6 entrypoints
   corretos têm `EXECUTE` para `service_role` — adicionada na nova Seção 2
   via `FOREACH` sobre arrays de tabelas/privilégios/funções.

## HOTFIX 6109 — resposta ao erro real de execução em 6103

`6090-6108` foram aplicados com sucesso ao banco real (GATE 5
IMPLEMENTATION-01). Na primeira chamada real e efetiva de
`open_pokemon_catalog_sourcing_run()` (dentro da execução de `6820` v2.2,
Seção 6), o PostgreSQL retornou `42702: column reference "run_code" is
ambiguous` — a função declara `run_code` como OUT parameter (via
`RETURNS TABLE`) e a tabela `pokemon_catalog_sourcing_run` também tem uma
coluna física `run_code`; o `RETURNING id, run_code` do INSERT de claim,
sem qualificação, era ambíguo entre os dois. Isso só se manifesta em
execução real — `CREATE FUNCTION` não detecta essa classe de erro
estaticamente, por isso passou incólume por três rodadas de GATE 4.

`6109` (hotfix incremental, `CREATE OR REPLACE FUNCTION` sobre a mesma
assinatura) corrige exclusivamente isso: alias explícito `AS inserted_run`
na tabela-alvo do INSERT e qualificação de `id`/`run_code` por esse alias na
cláusula `RETURNING`. Nenhuma outra linha do corpo da função foi tocada —
stale recovery, validação de `p_run_type`, validação de preflight, a
tradução seletiva de `unique_violation` em `SOURCE_BUSY` por
`CONSTRAINT_NAME` (Fix 6 da REVISION-01), grants e comentário funcional
permanecem idênticos a `6103`. O arquivo `6103` em si **não foi editado**
— seu histórico de migration já aplicado permanece intocado; `6109` é uma
correção numerada à parte, no mesmo padrão já usado no projeto para hotfixes
pontuais (`3944b`, `5035`/`5036`, `3904_fix_ambiguous_card_id_...`).

Zero execução de banco nesta rodada — `6109` está em staging, aguardando
auditoria externa antes de ser aplicado.

## GATE 5 HOTFIX 6109 IMPLEMENTATION — aplicação real e novo achado (6110)

`6109` foi auditado externamente com **PASS** e aplicado como migration nova
ao banco real (registrada no histórico de migrations; `6103` não foi editado
nem reexecutado). Um smoke test transacional (`BEGIN`/`SET LOCAL ROLE
service_role`/`ROLLBACK`) confirmou que o erro `42702` não ocorre mais, com
`outcome = CLAIMED`, `run_id`/`run_code` não nulos e `run_code` no formato
`^RUN-[0-9]{8}-[0-9]{8,}$` — zero resíduo após o `ROLLBACK`.

A re-execução completa de `6820` v2.2 (desde a Seção 0, dentro de `BEGIN
... ROLLBACK`) avançou com sucesso pelas Seções 0-8 — incluindo a matriz de
segurança (Seção 2) e o teste de `SOURCE_BUSY` (Seção 6), que exercitam
`open_run` diretamente — mas abortou na Seção 9 com um **segundo erro real,
distinto do primeiro**:

```
ERROR: 23514: new row for relation "pokemon_catalog_sourcing_run"
       violates check constraint "ck_pokemon_catalog_sourcing_run_period"
```

**Causa confirmada** (diagnóstico read-only via `pg_constraint`,
`information_schema.columns` e `pg_get_functiondef` do trigger de governança
`govern_pokemon_catalog_sourcing_run`, 6101): a CHECK exige `finished_at IS
NULL OR started_at IS NULL OR finished_at >= started_at`. O trigger preenche
`started_at` via `CLOCK_TIMESTAMP()` (hora real, avança a cada instrução) na
transição para `ACQUIRING`/`APPLYING`, mas os fechamentos terminais em
`6104`/`6105`/`6108` usam `finished_at = NOW()` (hora de início da
*transação*, congelada). Em uma transação suficientemente longa — como a
própria execução completa de `6820`, ou um `APPLY` real com aquisição HTTP
prévia — o `started_at` real (mais tarde) pode ultrapassar o `finished_at`
congelado (mais cedo), violando a CHECK. O trigger só usa `COALESCE(NEW.
finished_at, CLOCK_TIMESTAMP())`, ou seja, um `finished_at` explícito
fornecido pela função chamadora não é substituído — o defeito está nas três
funções que fecham o run, não no trigger.

`6110` (hotfix incremental, `CREATE OR REPLACE FUNCTION` sobre as mesmas três
assinaturas) corrige exclusivamente isso: toda atribuição explícita de
`finished_at = NOW()` em `plan_pokemon_catalog_sourcing_run` (3 ocorrências),
`apply_pokemon_catalog_sourcing_run` (1 ocorrência) e
`close_failed_pokemon_catalog_sourcing_run` (1 ocorrência) passa a
`finished_at = CLOCK_TIMESTAMP()`, alinhando a hora de fechamento à mesma
fonte de tempo real já usada pelo trigger para `started_at`. Nenhuma outra
linha de nenhuma das três funções foi tocada — lifecycle, hash, validação
estrutural do PLAN, protocolo de locks/reconciliação do APPLY,
`apply_summary`, sanitização do closeout, assinaturas, `SECURITY DEFINER`,
`search_path` e grants permanecem idênticos às versões atualmente aplicadas.
Os arquivos `6104`/`6105`/`6108` em si **não foram editados** — seu histórico
de migration já aplicado permanece intocado.

**Fora de escopo, explicitamente, nesta rodada**: `open_pokemon_catalog_sourcing_run`
(`6103`/`6109`) tem o mesmo padrão (`finished_at = NOW()` na reconciliação de
stale recovery), mas **não foi corrigido** — por instrução explícita de
Fabrício, permanece como achado residual conhecido, não corrigido neste
hotfix.

Em paralelo, `6820` recebeu uma correção equivalente e restrita à própria
Seção 9 (fixture de teste, não SQL funcional): a única linha do fixture que
fazia `finished_at = NOW()` passa a `finished_at = CLOCK_TIMESTAMP()`.
Nenhuma outra Seção de `6820` foi tocada nesta rodada; `6820` passa de v2.2
para v2.3.

Zero execução de banco nesta rodada — `6110` está em staging, aguardando
auditoria externa antes de ser aplicado. A re-execução real de `6820` v2.3
(pós-aplicação de `6110`) fica para uma rodada futura autorizada.

## GATE 9 PROMOTION-RECONCILIATION-01 — promoção e fechamento

Estado confirmado por auditoria independente antes desta rodada: GATE 5
IMPLEMENTED — PASS; GATE 7 EVIDENCE AUDIT — PASS; GATE 8 INDEPENDENT
CLOSEOUT AUDIT — PASS. Nenhuma alteração funcional nova foi autorizada ou
feita nesta rodada — escopo exclusivamente de promoção e documentação.

**Promoção**: os 13 arquivos efetivamente aplicados/auditados no banco real
(`6090`, `6091`, `6100`, `6101`, `6102`, `6103`, `6104`, `6105`, `6106`,
`6107`, `6108`, `6109`, `6110`) foram promovidos para `database/schema/`,
cada um como seu **próprio arquivo separado** — `6109`/`6110` permanecem
migrations incrementais próprias, **não foram dobradas** de volta em
`6103`/`6104`/`6105`/`6108` (decisão explícita desta rodada, diferente do
precedente mais antigo de dobra em `5035`). Nenhum arquivo já executado foi
reescrito historicamente: o corpo SQL de cada promoção é byte-idêntico ao
desta pasta — apenas o cabeçalho (`Status` e `Data`) foi atualizado na cópia
de `database/schema/`, confirmado por `diff` linha a linha nesta rodada.
`6820` **não foi promovido** — permanece nesta pasta como evidência de
validação/proposal, com seu próprio cabeçalho atualizado para `CONFIRMADO
EXECUTADO — resultado PASS` (mesmo padrão de `6800`/`6810`).

**Residual conhecido — classificação formal**: `open_pokemon_catalog_sourcing_run`
(`6103`/`6109`) mantém `finished_at = NOW()` no passo de stale recovery (ver
seção "GATE 5 HOTFIX 6109 IMPLEMENTATION" acima, parágrafo "Fora de escopo").
Classificação: **KNOWN / ACCEPTED / NON-BLOCKING** — não corrigido nesta
rodada, por instrução explícita; não impede a promoção nem o fechamento do
módulo.

**Nota de fechamento**: todos os 13 arquivos de DDL/função foram aplicados ao
banco real (projeto `qjfutqujxrbzgrtkpgkg`) via `GATE-5-IMPLEMENTATION-01`,
`GATE-5-HOTFIX-6109-IMPLEMENTATION-01` e `GATE-5-HOTFIX-6110-IMPLEMENTATION-01`,
validados por `6820` v2.3 (PASS integral, 16 Seções) e por auditorias
independentes (GATE 7 evidence audit, GATE 8 closeout audit), e promovidos
para `database/schema/` com corpo SQL idêntico ao desta pasta. Esta pasta é
preservada como evidência histórica completa de staging/revisão/hotfix/
validação — não apagada. Sourcing real via PokéAPI **continua não
executado** — próximo checkpoint é a rodada própria de Initial Load.

## Pré-requisitos físicos (já CONFIRMADO EXECUTADO)

`asset_source` (200/6700), `pokemon_region`/`pokemon_region_external_reference`
(6060/6070), `pokemon_generation` (6000), `pokemon_species`/`pokemon_species_external_reference`
(6010/6020), `pokedex`/`pokedex_external_reference` (6030/6050), `pokedex_position`
(6040), `pokemon_generation.main_region_id` (6080).
