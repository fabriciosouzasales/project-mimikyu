# Master Set por acabamento (`5184`–`5197` + `5836`–`5839` + prova de concorrência)

| Campo | Valor |
|---|---|
| Rodada | `MASTER-SET-DOCUMENTATION-AND-CONTRACT-PROPOSAL-01` (2026-10-18); correções da `MASTER-SET-FINISH-SCOPE-AUDIT-CORRECTION-01` (2026-10-18, ver seção própria) |
| Status | **PROPOSTA — NÃO EXECUTADA.** Nada aplicado no LIVE. Aguarda auditoria independente e autorização de Fabrício. |
| Autoridade | `concept-decisions.md` C-187–C-190; `logical-model.md` LDM-191–LDM-195 (substituem LDM-21 e partes de C-01, B.4, LDM-19/20/22). North Star N9 revisado. |
| Substitui | Modelo físico 02F por `card_variant_id` (`5072`–`5084`, CLOSED em 2026-09-02). No LIVE: `collection_master_set_scope` com **0 linhas** e **0 coleções MASTER_SET** (conferido em 2026-10-18) — troca sem migração de dados. |
| Frontend | Nenhum consumidor das funções aposentadas (grep em `web/` e `supabase/`). Único ponto relacionado: rótulo `collectionKindLabel("MASTER_SET") = "Set completo"` em `web/lib/colecoes/colecoes.ts:289` — divergente do N9, a corrigir no incremento de frontend (fora desta rodada). |

## Regras que a proposta implementa

1. Unidade de completude: **carta + tipo de acabamento** (`card_variant_type`).
2. Persiste-se só o **conjunto de acabamentos escolhidos** (`collection_master_set_finish`); as posições são **derivadas do catálogo vigente** a cada leitura (`master_set_positions`, fonte única).
3. Combinação nova de um acabamento escolhido entra sozinha; combinação que deixa de existir sai sozinha (LDM-195).
4. Contexto de edição, perfil de impressão e idioma não criam posições nem impedem satisfação.
5. **Cartas secretas** (número só com dígitos > `card_set.base_set_size`) sempre no objetivo. Se nenhum acabamento escolhido as contempla, geram **uma posição de carta** (sem acabamento), satisfeita por qualquer exemplar da carta — **cuidado A**: nunca se exigem todos os acabamentos de uma secreta.
6. Repetidas não contam; só exemplares vinculados contam.
7. Edição a qualquer momento (`replace_master_set_finishes`), prévia sem gravação (`preview_my_master_set_finishes`), mesma validação na prévia e na gravação (`normalize_master_set_finishes`).
8. Voltar ao Set padrão preserva os acabamentos (`5081` inalterada); reativar sem lista restaura.
9. Nenhuma função toca `physical_card`, `collection_allocation`, local ou fichário.
10. **Cuidado B**: o Card Set continua universo editorial estável (B.3); o que evolui é a cobertura de variantes. O ramo `STANDARD_SET` do resumo é copiado byte a byte (5836 0.6 confere por md5).
11. **Cuidado C**: desativações/correções catalográficas são derivadas sem histórico novo; a evidência é o log administrativo do catálogo (`2270`) + a leitura `get_my_master_set_out_of_scope_copies` com motivo (`CARD_INACTIVE`, `PAIR_NOT_IN_CATALOG`, `FINISH_NOT_SELECTED`).

## Arquivos

| Query | Arquivo | O que faz | Reaproveita / substitui |
|---|---|---|---|
| `5184` | `5184_create_collection_master_set_finish_table.sql` | Tabela `(collection_id, variant_type_id)` + RLS SELECT do dono + bloqueio de UPDATE | padrão de `5072`/`5074`; substitui `5072` |
| `5185` | `5185_create_master_set_finish_eligibility_trigger.sql` | Gatilho: coleção CARD_SET, mesmo Game, acabamento com carta ativa no Set | padrão de `5073` |
| `5186` | `5186_update_master_set_presence_for_finish.sql` | `check_master_set_scope_presence` passa a olhar acabamentos + gatilho diferido de DELETE | **reaproveita** `5075` (mesma assinatura) e `5076` (inalterado) |
| `5187` | `5187_create_master_set_positions_function.sql` | Função interna: posições (acabamento + secretas) | nova |
| `5188` | `5188_update_collection_completion_summary_master_finish.sql` | `collection_completion_summary` v6.0 — só o ramo MASTER_SET muda | substitui ramo de `5102` |
| `5189` | `5189_create_get_my_master_set_positions_function.sql` | Grade da coleção Master Set (arte, satisfação, exemplares, acervo) | formato de `5169`; remove `5084` |
| `5190` | `5190_create_normalize_master_set_finishes_function.sql` | Validação única do conjunto | nova |
| `5191` | `5191_create_get_my_master_set_finish_options_function.sql` | Ajustes → Objetivo: acabamentos existentes, contagens, seleção, bloco de secretas | nova |
| `5192` | `5192_create_preview_my_master_set_finishes_function.sql` | Prévia sem gravação | nova |
| `5193` | `5193_create_apply_master_set_finishes_function.sql` | Diferença KEEP/ADD/REMOVE (interna) | desenho de `5079` |
| `5194` | `5194_replace_set_collection_completion_policy_to_master_set.sql` | Ativar (lista ou restaurar); idempotente | mesmo nome de `5080`, assinatura nova `(uuid, uuid[])` |
| `5195` | `5195_create_replace_master_set_finishes_function.sql` | Editar acabamentos | substitui `5082` |
| `5196` | `5196_create_get_my_master_set_out_of_scope_copies_function.sql` | Exemplares fora do objetivo, com motivo | nova (cuidado C) |
| `5197` | `5197_retire_collection_master_set_scope.sql` | v1.2 — remove tabela e funções exclusivas de 02F; 7 guardas fail-closed: tabela comum, sem dados, sem MASTER_SET sem acabamento, corpos de função, views, publicações e `pg_depend` classificado **por dono** (só objetos da própria tabela são aceitos) | aposenta `5072`–`5074`, `5077`, `5079`; evidência em `5197-DEPENDENCY-EVIDENCE.md` |
| `5836` | `5836_validate_master_set_finish_scope.sql` | Harness funcional/segurança/regressão/preservação — **74 checagens + GATE** (v1.1: seções 11 e 12; casos 2.3, 4.8, 9.4) | protocolo de `5830`–`5835` |
| `5837` | `5837_performance_master_set_finish_scope.sql` | Desempenho (maior Set do LIVE + Biblioteca com 20 Master Sets, incluindo `get_my_collections`) — **10 checagens + GATE** | — |
| `5838` | `5838_baseline_completion_snapshot.sql` | v1.3 — **script psql em duas fases** (coleção livre = resumo ausente esperado): (A) DDL temporária de sessão (`pg_temp`, transação própria); (B) snapshot em transação aberta como `REPEATABLE READ, READ ONLY`, que a função confere e sem a qual se recusa a rodar; md5 do resumo de cada coleção, antes × depois, sem expor ids; qualquer erro ou lacuna marca o resultado como `INVALIDO` | prova comportamental de regressão (Set padrão e Pokédex) |
| `5839` | `5839_validate_5197_dependency_guard.sql` | **Somente ambiente descartável** (opt-in `mmkyu.disposable_db`): 16 casos do guarda de dependências do 5197 (P1–P3, N1–N12, resíduo) | bloco do guarda idêntico ao 5197 |
| — | `CONCURRENCY-PROOF-MASTER-SET-FINISH.sql` | Roteiro manual K1–K5 (duas sessões psql) | formato da prova BULK-01 |
| — | `LIVE-EXECUTION-READINESS-01.md` | Pré-check do LIVE (só leitura), classificação A/B/C dos testes, plano, comandos, STOP e esforço | decisão: validação direto no LIVE |
| — | `RECOVERY-MASTER-SET-FINISH.sql` | v1.1 — roteiro de reversão (R0 guarda, R-B1, R-A, R-V) com ordem exata, convenção de ledger e gate por md5; não executado | — |
| — | `5197-DEPENDENCY-EVIDENCE.md` | Inventário de dependências dos objetos aposentados (LIVE + repositório) | — |

Permanecem sem mudança: `5076` (gatilho em `collection`), `5078` (CHECK de `completion_policy`), `5081` (voltar ao Set padrão), `5046`/`5047` (vincular/desvincular), `5169`/`5170` (Set padrão), `5182` (Biblioteca — herda o novo resumo).

## Contratos públicos (todos SECURITY DEFINER, `search_path` vazio, EXECUTE só `authenticated`)

| Função | Assinatura | Uso |
|---|---|---|
| Ativar | `set_collection_completion_policy_to_master_set(p_collection_id uuid, p_variant_type_ids uuid[] default null)` | Ajustes: ativar com acabamentos ou restaurar |
| Editar | `replace_master_set_finishes(p_collection_id uuid, p_variant_type_ids uuid[])` | Ajustes: trocar acabamentos |
| Voltar | `set_collection_completion_policy_to_standard_set(p_collection_id uuid)` | inalterada |
| Prévia | `preview_my_master_set_finishes(p_collection_id uuid, p_variant_type_ids uuid[])` | antes de confirmar |
| Opções | `get_my_master_set_finish_options(p_collection_id uuid)` | chips de acabamento + secretas |
| Grade | `get_my_master_set_positions(p_collection_id uuid, p_filter text, p_limit int, p_offset int)` | página da coleção |
| Fora do objetivo | `get_my_master_set_out_of_scope_copies(p_collection_id uuid, p_limit int, p_offset int)` | explicação de exemplares/progresso |
| Resumo | `collection_completion_summary(p_collection_id uuid)` | inalterada na assinatura |

Códigos de erro: `28000 not_authenticated`; `P0002 COLLECTION_NOT_FOUND` (alheia ou inexistente — mesma resposta); `P0001 COLLECTION_ARCHIVED`, `MASTER_SET_REQUIRES_SET_COLLECTION`, `MASTER_SET_NOT_ACTIVE`, `FINISH_NOT_IN_SET` (DETAIL = id), `NO_SAVED_FINISHES`, `EMPTY_OBJECTIVE`; `22023 INVALID_FINISHES`, `INVALID_FILTER`, `INVALID_PAGE`.

## Matriz de dependências

| Objeto | Depende de | É usado por |
|---|---|---|
| `5184` tabela | `collection`, `card_variant_type`, `auth.users` | 5185, 5186, 5188, 5189, 5191–5196 |
| `5185` gatilho | 5184; `collection_reference`, `collection_card_set_reference`, `card`, `card_variant` | inserções via 5193 |
| `5186` presença | 5184; gatilho 5076 já existente | COMMIT de 5194/5195/5081 |
| `5187` posições | `card_set`, `card`, `card_variant` | 5188, 5189, 5191, 5192, 5196 |
| `5188` resumo | 5184, 5187 | 5182 (Biblioteca), 5192, 5194, 5195, frontend |
| `5189` grade | 5184, 5187, `card_asset` | frontend (página da coleção) |
| `5190` validação | `card_variant_type`, `card`, `card_variant` | 5192, 5194, 5195 |
| `5191` opções | 5184, 5187 | frontend (Ajustes) |
| `5192` prévia | 5187, 5188, 5190 | frontend (Ajustes) |
| `5193` diferença | 5184 (+ gatilhos 5185/5186) | 5194, 5195 |
| `5194` ativar | 5188, 5190, 5193 | frontend |
| `5195` editar | 5188, 5190, 5193 | frontend |
| `5196` fora do objetivo | 5184, 5187 | frontend |
| `5197` aposentar | 5188, 5189, 5194, 5195 já aplicadas | — |

## Plano de aplicação controlada (quando autorizado)

**Pré-check (somente leitura, uma consulta):**
```sql
select
  (select count(*) from public.collection_master_set_scope)                       as scope_rows_must_be_0,
  (select count(*) from public.collection where completion_policy = 'MASTER_SET') as master_collections_must_be_0,
  to_regclass('public.collection_master_set_finish')                              as finish_table_must_be_null,
  (select md5(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', '', 'g'))
     from pg_proc where proname = 'collection_completion_summary')               as summary_md5_must_be_0a644fe6;
```
Esperado: `0`, `0`, `NULL`, `0a644fe65e044a352e1a8327e9373284`. Qualquer divergência → STOP.
Antes de tudo, em ambiente descartável: `5839` → esperado **16/16 PASS + GATE PASS**.
Linha de base: contagens e fingerprints de `collection`, `collection_allocation`, `physical_card`; **`5838` duas vezes seguidas** pelo protocolo da seção "Protocolo do 5838" (resultados idênticos e todos `OK`; anotar GATE e COBERTURA); Security Advisor.

**Aplicação** (uma migration por vez, conferindo corpo, ACL e ledger a cada passo):
`5184 → 5185 → 5186 → 5187 → 5188 → 5189 → 5190 → 5191 → 5192 → 5193 → 5194 → 5195 → 5196 → 5197`.
Entre `5188` e `5197` o LIVE fica com as duas tabelas; como não há coleção MASTER_SET, nenhuma leitura muda de resultado (o resumo de toda coleção existente deve continuar idêntico à linha de base).

**Validação:** `5838` de novo → todas as linhas `OK`, md5 global, md5 por grupo e contagens idênticos à linha de base; `5836` → esperado **74/74 PASS + GATE PASS**; depois `5837` → **10/10 PASS + GATE PASS** (limites recomendados no cabeçalho, ajustáveis por Fabrício); depois o roteiro K1–K5.

**Pós-check:** contagens e fingerprints iguais à linha de base; resumo de cada coleção existente idêntico; Advisor: saldo esperado em `0029` = +3 (6 funções públicas SECURITY DEFINER criadas ou recriadas — 5189, 5191, 5192, 5194, 5195, 5196 — menos 3 removidas — 5080 antiga, 5082, 5084); confirmar o saldo real.

**Promoção:** copiar `5184`–`5197` para `database/schema/` como canônicas (status CONFIRMADO EXECUTADO); marcar `5072`–`5084` canônicas como históricas/substituídas; registrar `5836`/`5837`/`5838`/`5839`/K1–K5 como evidência; atualizar `OFFLINE-MANIFEST-01` (lista 5072–5077); atualizar `05d` (§02F → nota de substituição + nova seção), North Star §7, HANDOFF, ROADMAP, INDEX e `log.md`.

**Reversão (se necessário antes de qualquer coleção MASTER_SET real):** reaplicar `5072`–`5084` canônicas e `5102`, e remover os objetos `5184`–`5196`. Depois que houver coleções MASTER_SET reais, a reversão exigiria migração de dados (decisão de Fabrício).

## Efeitos colaterais conhecidos

- A consulta "Como validar" da migration `2268` esperava 4 gatilhos `trg_guard_card_variant_active`; com `5197` passam a 3 (a tabela aposentada levava um). Registrar ao promover.
- `5194` muda o comportamento de reenvio em relação a `5080`: chamar a ativação numa coleção já MASTER_SET não falha mais (no-op ou aplica a lista).
- O ramo `STANDARD_SET` continua contando cartas sem filtrar `is_active` (comportamento atual, não alterado aqui); o Master Set filtra cartas e variantes ativas (LDM-195). Divergência registrada em LDM-195.
- O progresso de um Master Set pode mudar sem ação do colecionador quando o catálogo muda (decisão C-188). Aviso ao colecionador não faz parte desta rodada.

## Verificação estática feita nesta rodada

- Nenhuma execução no LIVE além de consultas de leitura (estado de `collection_master_set_scope`, coleções MASTER_SET, md5 do resumo, gatilhos e índices).
- `5188` gerado a partir de `5102` por substituição só do trecho MASTER_SET; os trechos STANDARD_SET e REFERENCE_POSITION têm md5 normalizado `e8e0de6f…` e `812240ec…`, os mesmos conferidos em `5836` 0.6.
- Sem ambiente PostgreSQL local disponível no sandbox (não tocar `b12-pg17`): a sintaxe só será provada na aplicação autorizada.

## Correções da AUDIT-CORRECTION-01 (2026-10-18)

| Achado | Correção | Evidência |
|---|---|---|
| Transições da secreta (genérica ↔ específica) sem prova | `5836` seção 11 (11.1–11.5): genérica sem acabamento; incluir Gold substitui as genéricas sem duplicar e preserva o progresso; retirar restaura; incluir Holo faz a Gold sair do objetivo | estática; execução pendente |
| Reativação com catálogo alterado sem prova | `5836` seção 12 (Set S3): ativar → Set padrão → catálogo ganha Reverse, Padrão 1ª Ed. e uma secreta → reativar restaurando; denominador, prévia = gravação, idempotência (xmin), exemplares preservados | estática; execução pendente |
| 5197 dependia só da tabela vazia | 5197 v1.1 com 6 guardas; `5197-DEPENDENCY-EVIDENCE.md` | LIVE só leitura + repositório |
| Lacunas de segurança | 2.3 (funções internas recusadas ao dono), 4.8 (UPDATE/DELETE direto), 9.4 (B escrevendo nos acabamentos de A) | estática; execução pendente |
| Regressão só estrutural | `5838` (md5 do resumo de cada coleção real, antes × depois) | estática; execução pendente |
| Biblioteca medida só pelo resumo | `5837` P2.2 (`get_my_collections`) | estática; execução pendente |
| Concorrência sem desvincular | K5 (`5195` × `5047`, nas duas ordens) | roteiro manual; não executado |
| Referências cruzadas erradas | 5184 (remoção em 5197; escrita via 5194/5195 + 5193), 5186 (até 5197), 5187 e 5188 (consumidores) | revisão textual |

Riscos residuais registrados:

- **Baixo:** corrida entre a validação de acabamento (5185/5190) e a desativação concorrente de uma variante no catálogo, que não trava a coleção. Pode deixar gravado um acabamento sem combinações ativas; o efeito é o mesmo de uma desativação posterior (LDM-195: posições saem sozinhas, exemplares aparecem como fora do objetivo). Sem correção nesta rodada.
- **Baixo:** scripts D2-01/D2-03 (históricos) e `OFFLINE-MANIFEST-01` citam a tabela antiga; ver evidência.

## Correções da AUDIT-CORRECTION-02 (2026-10-18)

| Achado | Correção | Evidência |
|---|---|---|
| BLOCKER 1 — guarda de `pg_depend` do 5197 classificava por classe: índice próprio disparava (falso positivo) e FK/policy de outra tabela passavam sem diagnóstico | 5197 v1.2: classificação **por dono** do objeto dependente; cobre tabela, tipo-linha, tipo array e as 4 funções removidas; classes não previstas bloqueiam; checagem (0) de tabela comum | LIVE (só leitura de catálogo): 19 dependências, todas internas, guarda v1.2 = NULL; `5839` com P1–P3 e N1–N12 (não executado); `5197-DEPENDENCY-EVIDENCE.md` §6–§9 |
| BLOCKER 2 — 5838 descrito como somente leitura mas cria função `pg_temp` | 5838 v1.1 reclassificado (DDL temporária de sessão, privilégios e autorização explícitos); `transaction_read_only = on` como primeira instrução; sem troca de papel (resumo é SECURITY DEFINER e só usa `auth.uid()`); claims locais por coleção, incluindo `request.jwt.claim.sub`; erro por coleção capturado; linha COBERTURA; protocolo com duas leituras antes | estática; execução pendente |
| K5 — pré-condições implícitas | Roteiro v1.2: Set precisa ter Padrão, Holo e Reverse (consulta de conferência); ids de acabamento por consulta; preparação da ordem 2 dentro da sequência; contratos citados | revisão textual |

Verificações complementares sem achado: 5836 com 74 ids distintos, iguais ao GATE (0.6 tem caminho alternativo, só um roda); todas as escritas do 5836 miram ids sintéticos ou usuários efêmeros e são desfeitas pela sentinela; o 5837 só insere exemplares no inventário do usuário efêmero e é desfeito pela sentinela; nenhum script altera exemplares reais.

## Protocolo do 5838 (v1.2, AUDIT-CORRECTION-03)

**Cliente:** `psql`, por conexão direta ou Session Pooler (porta 5432), a mesma dos roteiros de concorrência. O arquivo começa com o meta-comando `\set ON_ERROR_STOP on`: colado no SQL Editor, falha de propósito. O SQL Editor não é suportado porque não dá controle visível sobre os limites de sessão e de transação, nem exibe de forma garantida o resultado de uma instrução intermediária de um script com várias instruções. O Transaction Pooler (6543) também não serve: objetos `pg_temp` não sobrevivem entre transações nele.

**Uma execução** (autocontida; não depende de sessão anterior):

```
psql "<connection string, porta 5432>" -X -f 5838_baseline_completion_snapshot.sql
```

1. Fase A, em transação própria: cria `pg_temp.ms_5838_snapshot()` (DDL temporária de sessão; some ao desconectar).
2. Fase B: `START TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;` → `SELECT` do snapshot → `ROLLBACK`.
3. A função confere `transaction_read_only = on` e isolamento `repeatable read`/`serializable`; fora disso, erro 25000 `MS5838_REQUIRES_READ_ONLY_RR`, sem linhas de resultado.
4. Com `ON_ERROR_STOP`, qualquer erro fora do laço encerra o psql; a desconexão desfaz a transação aberta.

**Comparação:**

| Momento | Ação | Critério |
|---|---|---|
| Antes de 5184 | executar o arquivo 2 vezes (2 invocações do psql) | todas as linhas `OK` nas duas; saídas idênticas |
| Aplicação | 5184 → … → 5197 | — |
| Depois | executar o arquivo 1 vez, sem escritas em coleções, vínculos ou catálogo desde a linha de base | todas as linhas `OK`; GATE, md5 por grupo, contagens e COBERTURA idênticos aos de antes |

Qualquer linha `INVALIDO` (erro, resumo vazio ou cobertura incompleta) **não é resultado de regressão**: o GATE sai sem digest e a comparação não é feita até a causa ser entendida.

**Testes do próprio 5838 em ambiente descartável (pendentes, não executados):**

| # | Ação | Esperado |
|---|---|---|
| T1 | Fase A e depois `SELECT * FROM pg_temp.ms_5838_snapshot();` sem abrir transação | erro 25000 `MS5838_REQUIRES_READ_ONLY_RR`, nenhuma linha |
| T2 | `START TRANSACTION READ ONLY;` (isolamento padrão, read committed) + `SELECT` | erro 25000, nenhuma linha |
| T3 | arquivo completo | todas as linhas `OK`; COBERTURA `n/n, 0, 0` |
| T4 | T3 repetido em nova invocação do psql | saída idêntica a T3 |
| T5 | dentro da fase B, tentar `insert`/`update` numa tabela qualquer | erro 25006 (prova do modo somente leitura da transação) |
| T6 | colar o arquivo no SQL Editor | falha na primeira linha (`\set`) |

## Correções da AUDIT-CORRECTION-03 (2026-10-18)

| Achado | Correção | Evidência |
|---|---|---|
| BLOCKER — o 5838 v1.1 dependia de `set_config('transaction_read_only','on',true)` dentro da função, sem prova | 5838 v1.2: preparação (DDL temporária) e snapshot separados; snapshot numa transação aberta como `REPEATABLE READ, READ ONLY`; a função **confere** o modo e recusa rodar sem ele; sem `set_config` de `transaction_read_only`; erro, resumo vazio ou cobertura incompleta marcam todas as linhas como `INVALIDO` e anulam o digest do GATE; cliente definido (psql, porta 5432) e execução autocontida | estática; `auth.uid()` no LIVE (só leitura) lê `request.jwt.claim.sub` antes de `request.jwt.claims`, como o script presume; T1–T6 pendentes |

A linha da CORRECTION-02 sobre o 5838 (`transaction_read_only = on` como primeira instrução) fica como registro histórico, substituída por esta.

Verificações complementares sem achado: o guarda `<dep-guard v1.2>` continua idêntico no 5197 e no 5839; a classificação por dono e os 16 casos do 5839 foram revistos sem mudança.
