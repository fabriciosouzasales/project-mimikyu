# V1-14 R2-D — favoritas por Card Set canônico

Origem: `R2-D — CONTRACT APPROVAL & QUERY 5356 PROPOSAL-01` (2026-11-07), decisão D1 (opção A) do contrato da R2-D (D7 §4l). **Query 5356 CONFIRMADA EXECUTADA no LIVE em 2026-11-07 19:28 UTC** (ver "Aplicação no LIVE" no fim). O harness 5884 só rodou em transação com ROLLBACK. O arquivo desta pasta é a **evidência exata aplicada** (md5 `bcab1c34…`, igual ao ledger) e não é alterado. **Arquivo canônico:** `database/schema/5356_create_get_my_favorite_cards_by_card_set.sql` (md5 `51cbbc0a…`) — idêntico a este exceto no bloco Status; corpo executável idêntico (`prosrc` `88a188c1…`, o do LIVE). Nenhuma reaplicação.

| Arquivo | Natureza |
|---|---|
| `5356_create_get_my_favorite_cards_by_card_set_PROPOSAL.sql` | RPC somente leitura `get_my_favorite_cards_by_card_set(p_card_set_id, p_limit, p_offset)`: as favoritas do titular de UM Card Set canônico, com as colunas da 5336 + `card_set_id`, na ordem do Set |
| `5884_validate_get_my_favorite_cards_by_card_set_HARNESS.sql` | Harness em transação com ROLLBACK: esquema e dependências (E1), propriedades e permissões (S1/S2), anon/sem sessão/entradas inválidas (S2/S3), equivalência com a 5336 (I1), pertencimento canônico (I2), uma linha por carta (I3), ordem/paginação/total (I4), isolamento entre titulares (I5), desempenho (P1), nada mais mudou (E2) |

## Por que existe

`get_my_favorite_cards` (5336) devolve `card_set_code`/`card_set_name`, mas não `card_set_id` nem filtro por Set; e `card_set.code` só é único dentro da expansão (`uq_card_set_expansion_code (expansion_id, code)`, Query 120) — o código não é identidade canônica. As posições da coleção também não servem (no Master Set só existem para os acabamentos escolhidos e as secretas). A 5356 filtra pelo vínculo canônico `card.card_set_id` no banco. **A 5336 não muda.**

## Equivalência com a 5336 (verificada no repositório)

Mesmas regras: favoritos de `auth.uid()`; só cartas ativas (`card.is_active`; o favorito de carta desativada permanece — C-90); imagens `CARD_FRONT` primária e ativa, pt-BR e en; página 1..100; offset 0..100000; SECURITY DEFINER porque `card`/`card_set`/`card_asset` só são legíveis por administrador. Diferenças deliberadas: filtro `c.card_set_id = p_card_set_id`; coluna `card_set_id`; ordem pelo número do Set (`collector_order` — `UNIQUE (card_set_id, collector_order)`, Query 140 — nome, id) em vez de data; `p_card_set_id` nulo → 22023 `INVALID_CARD_SET`; Card Set inexistente → 0 linhas.

## Condições para autorizar a simulação (harness 5884)

1. Projeto LIVE `qjfutqujxrbzgrtkpgkg` e hashes abaixo conferidos antes da execução.
2. Existir um titular com favoritas ativas, um **segundo titular existente** (`auth.users`) e outro Card Set com cartas ativas — o harness aborta com `Q5884_PRE_CONTEXT` se faltar algo (nenhum usuário é inventado).
3. Cenário de isolamento: **2 favoritos sintéticos** do segundo titular (uma carta do Set testado e uma de outro Set), inseridos e revertidos na própria transação.
4. Transação única terminada em ROLLBACK, corpo da 5356 colado no lugar do `\ir` sem alteração; nenhuma migration concorrente; 0 transações ociosas e bloqueios antes e depois.
5. Efeitos externos esperados: só o `NOTIFY` do `pgrst_ddl_watch` (transacional, descartado). Os favoritos sintéticos não disparam nada fora do banco (sem triggers de notificação conhecidos em `card_favorite` — conferir no precheck).

| Hash | Valor |
|---|---|
| 5356 md5 | `bcab1c342c6d26bc8bc920482fb3e178` |
| 5356 sha256 | `26587e6e76d51c22667ac0e21e78ed9362eabb9d3886be90c1ba7a5b550483e9` |
| 5884 md5 | `42320e9b6771b7454f97223b5996bf5a` |

## Harness 5884 — execução controlada (2026-11-07 19:19–19:21 UTC, `QUERY 5356 HARNESS 5884 EXECUTION-01`)

LIVE `qjfutqujxrbzgrtkpgkg` (mimikyu-core, PG 17.6). Hashes usados: 5356 md5 `bcab1c342c6d26bc8bc920482fb3e178`, 5884 md5 `42320e9b6771b7454f97223b5996bf5a`. Duas execuções, cada uma numa transação única: (1) harness íntegro, terminado em `ROLLBACK`; (2) o mesmo cenário (contexto, 5356, favoritos sintéticos, leituras) + bloco final de evidência somente leitura, que aborta a transação com `RAISE` antes do `ROLLBACK` (devolve os valores medidos; nada persiste). Corpo executável da 5356 inserido no lugar do `\ir` sem nenhuma alteração; só os comentários de cabeçalho foram omitidos no envio. **5356 NÃO aplicada.**

**Precheck (19:19 UTC, tudo conforme, antes de qualquer escrita):** projeto confirmado; hashes iguais; 5356 inexistente; corpo da 5336 `get_my_favorite_cards` no LIVE (md5 `9c9c76e8…`) idêntico ao do arquivo-base; impressão digital das quatro funções da 5336 `cbd7cefd…`; RLS de `card_favorite` ativa (`card_favorite_select_own`), policies de catálogo (`catalog_admin_select` em `card`, `card_set`, `card_asset`) com impressão digital `e1c90e23…`; ACL de `card_favorite` `{postgres=arwdDxtm,service_role=Dxtm,authenticated=r}`; `UNIQUE (card_set_id, collector_order)` presente; 85 favoritos de 2 titulares (impressão digital `c26802f9…`), 3 usuários em `auth.users`; **`card_favorite` sem triggers e fora de publicações (realtime)** — as inserções sintéticas não têm efeito externo; 489 funções `public` (permissões `bfa7d689…`); 0 DDL, transações ociosas ou bloqueios; última migration = 5355.

**Contexto real usado:** titular A = 25 favoritas ativas (5336), das quais **8 no Set ME5.5** (o Set com mais favoritas de um titular); titular B = outro titular existente, com 60 favoritas reais (5 no ME5.5); 2 favoritos **sintéticos** de B (uma carta de A no ME5.5 e uma carta de outro Card Set), inseridos e revertidos na transação (B passou a 62 favoritas e 6 no ME5.5 durante o teste).

| Teste | Resultado observado |
|---|---|
| E1 esquema e baseline | **PASS** — colunas de `card_favorite`/`card` com tipos e NOT NULL esperados; `collector_order` e `UNIQUE (card_set_id, collector_order)`; 5336 presente; 5356 ausente; baselines de policies, 5336 e permissões guardados |
| S1 propriedades | **PASS** — SECURITY DEFINER, `search_path=""`, STABLE, retorno com as 11 colunas |
| S2 permissões | **PASS** — anon e PUBLIC sem EXECUTE, authenticated com EXECUTE; chamada real como anon → 42501 |
| S3 sessão e entradas | **PASS** — sem sessão → 28000; Card Set nulo, limite 0 e 101, offset −1 → 22023 |
| I1 equivalência com a 5336 | **PASS** — as 8 favoritas de A no ME5.5 pela 5356 = as favoritas da 5336 (25, todas as páginas) cujo `card.card_set_id` é o ME5.5, nos dois sentidos (carta, nome, número, total, Set, imagens pt/en, data) |
| I2 pertencimento | **PASS** — todas as linhas com `card_set_id` = ME5.5 e carta ativa (1 Set distinto); Card Set inexistente → 0 linhas |
| I3 uma linha por carta | **PASS** — 8 linhas, 8 cartas |
| I4 ordem, paginação, total | **PASS** — ordem = `collector_order, nome, id`; páginas de 2 somadas = as 8, sem repetição nem falta; `total_count` = 8 em todas as páginas |
| I5 isolamento | **PASS** — B vê exatamente os 6 próprios favoritos no ME5.5 (5 reais + 1 sintético), nenhum que não seja dele; a carta sintética de outro Set não aparece no ME5.5; A não vê nenhum favorito de B |
| P1 desempenho | **PASS** — EXPLAIN ANALYZE como A: 0,406 / 0,501 / 0,361 ms de execução (limite 50 ms), planejamento ~0,02 ms |
| E2 nada mais mudou | **PASS** — policies, corpos e permissões da 5336 e permissões das demais funções idênticos ao início |

**Pós-ROLLBACK (19:21 UTC):** 5356 inexistente; `card_favorite` com 85 linhas e impressão digital `c26802f9…` (**nenhum favorito sintético persistiu**); 5336 `9c9c76e8…` e conjunto `cbd7cefd…` iguais; RLS ativa, policies `e1c90e23…` e ACL de `card_favorite` iguais; 489 funções `public` com permissões `bfa7d689…` (iguais); 0 tabelas temporárias `_q5884*`, 0 transações ociosas, 0 bloqueios em espera; nenhuma migration nova; hashes dos arquivos iguais.

**Limitações:**
- **Volume pequeno:** a equivalência (I1), a paginação (I4) e o desempenho (P1) foram exercidos com 8 favoritas num Set (o maior caso real hoje); o plano lê só as favoritas do titular pelo prefixo da PK, então o custo cresce com as favoritas do titular, não com o catálogo — volumes de centenas não foram observados.
- **Carta desativada:** não há carta desativada entre as favoritas do Set testado; a exclusão vem do filtro `c.is_active` (igual à 5336) e foi verificada só por construção e pela I2 (todas ativas).
- **Empate de ordem:** `collector_order` é único por Set, então o desempate por nome/id não ocorre com dado real.

**Parecer:** **pronta para aplicação definitiva** — segurança, isolamento entre titulares, equivalência com a 5336, pertencimento canônico, ordem, paginação e desempenho comprovados; nada persistiu.

## Aplicação no LIVE (2026-11-07, `QUERY 5356 LIVE APPLICATION-01`)

- **Quando / onde:** 2026-11-07 19:28:07 UTC (versão no ledger `20261107192807`, nome `5356_create_get_my_favorite_cards_by_card_set`), projeto `qjfutqujxrbzgrtkpgkg` (mimikyu-core, PG 17.6). Transação única do `apply_migration`; nenhuma outra migration; nenhuma correção ou otimização adicional.
- **Identidade e hash:** arquivo `5356_create_get_my_favorite_cards_by_card_set_PROPOSAL.sql` (6.356 bytes), md5 `bcab1c342c6d26bc8bc920482fb3e178`, sha256 `26587e6e76d51c22667ac0e21e78ed9362eabb9d3886be90c1ba7a5b550483e9`; md5 das instruções gravadas no ledger = `bcab1c342c6d26bc8bc920482fb3e178`; md5 do corpo da função no LIVE (`prosrc`) = md5 do trecho entre `$$` do arquivo (`88a188c1…`) — o mesmo SQL do harness 5884.
- **Precheck (19:27 UTC), tudo igual ao do harness:** projeto; hashes 5356/5884; função inexistente; 5336 `9c9c76e8…` e conjunto `cbd7cefd…`; RLS de `card_favorite` ativa, policies `e1c90e23…`, ACL de `card_favorite` inalterada; 85 favoritos (`c26802f9…`); 489 funções `public` (permissões `bfa7d689…`); ACL padrão do `postgres` em `public` = só `postgres=X`; 0 DDL, transações ociosas ou bloqueios; última migration = 5355.

**Postcheck — todos PASS (verificações direcionadas, sem repetir o harness):**

| Verificação | Resultado |
|---|---|
| Definição | `get_my_favorite_cards_by_card_set(uuid, integer, integer)` → as 11 colunas homologadas; SECURITY DEFINER, `search_path=""`, STABLE, dono `postgres`; corpo = SQL homologado |
| Permissões | ACL `{postgres=X/postgres,authenticated=X/postgres}`; anon sem EXECUTE (chamada real → 42501); PUBLIC e service_role sem EXECUTE |
| Sem sessão | 28000 |
| Titular A, Set ME5.5 | 8 favoritas = 8 esperadas pela tabela; todas do ME5.5 e dele; `total_count` 8 (igual ao harness) |
| Isolamento (titular B) | 5 favoritas = as 5 reais de B no ME5.5; nenhuma que não seja de B (sem os sintéticos do harness, revertidos) |
| Desempenho | EXPLAIN ANALYZE: 2,10 / 1,85 / 1,64 ms (limite 50 ms; no harness 0,36–0,50 ms com cache quente) |
| 5336 | `9c9c76e8…` e conjunto `cbd7cefd…` inalterados |
| RLS e policies | RLS ativa; policies `e1c90e23…` e ACL de `card_favorite` iguais |
| Dados de `card_favorite` | 85 linhas, impressão digital `c26802f9…` igual |
| Demais funções | 490 funções `public` (489 + 1); permissões das outras 489 = `bfa7d689…` |
| Sessão | 0 transações ociosas, 0 bloqueios em espera |

Referência: harness 5884 (seção anterior). Nenhuma divergência. **Estado final: Query 5356 aplicada e validada no LIVE**; a interface da R2-D não foi implementada. Pricing, JustTCG, 5336 e demais RPCs não foram tocados.
