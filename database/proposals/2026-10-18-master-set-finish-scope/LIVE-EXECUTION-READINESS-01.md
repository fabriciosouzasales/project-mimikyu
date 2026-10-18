# Master Set por acabamento — plano de execução no LIVE (READINESS-01)

| Campo | Valor |
|---|---|
| Rodada | `MASTER-SET-LIVE-EXECUTION-READINESS-01` (2026-10-18) |
| Decisão vigente | Validação direto no Supabase LIVE (sem ambiente paralelo) — decisão de Fabrício |
| Status | **PLANO — nada aplicado.** Pré-check executado só com leituras. Aplicação depende de autorização expressa |
| Projeto | `qjfutqujxrbzgrtkpgkg`, PostgreSQL 17.6; repositório HEAD `db61330` |

## 1. Pré-check (executado nesta rodada, somente leitura)

| # | Verificação | Resultado no LIVE | Esperado | Status |
|---|---|---|---|---|
| P1 | Linhas em `collection_master_set_scope` | 0 | 0 | OK |
| P2 | Coleções `MASTER_SET` | 0 | 0 | OK |
| P3 | Coleções existentes | 3 (2 `STANDARD_SET/REFERENCE_BASED`, 1 `NONE/OPEN_CURATION`) | — | registrado |
| P4 | md5 normalizado de `collection_completion_summary` | `0a644fe65e044a352e1a8327e9373284` | igual ao 5102 | OK |
| P5 | `collection_master_set_finish` e as 11 funções novas | ausentes | ausentes | OK |
| P6 | Funções antigas presentes | `set_collection_completion_policy_to_master_set(uuid,jsonb)`, `replace_master_set_scope(uuid,jsonb)`, `collection_master_set_scope_positions(uuid,boolean)`, `apply_master_set_scope_diff`, `check_master_set_scope_presence`, 3 funções de gatilho, `enforce_collection_master_set_scope_presence`, `..._to_standard_set` | conforme proposta | OK |
| P7 | Funções cujo corpo cita objetos antigos | 7; todas substituídas (5186, 5188) ou removidas (5189, 5194, 5195, 5197) | todas com destino | OK |
| P8 | Guarda de dependências do 5197 v1.2 (rodado como SELECT) | 19 dependências, nenhuma bloqueante; sem publicação, herança ou TOAST | NULL | OK |
| P9 | Dono dos objetos afetados | `postgres` (tabelas e funções) | `postgres` | OK |
| P10 | Papel de execução | `postgres` (não superuser); TEMP no banco: sim; REFERENCES/INSERT/DELETE em `auth.users`: sim | suficiente | OK |
| P11 | Papéis `anon`, `authenticated`, `service_role` | existem | existem | OK |
| P12 | Último registro no ledger | `20261018012519 5183_create_move_my_collection_function` | 5183 | OK |
| P13 | Vocabulário usado pelos harnesses | 7 tipos de acabamento, raridade `COMMON`, categoria `POKEMON`, `pt-BR`/`en`, `FIRST_EDITION`, `PROGRAM_LEAGUE` | presentes | OK |
| P14 | Dependências do 5836/5837 | `create_my_card_set_collection`, `allocate_…`, `deallocate_…`, `get_my_collections` presentes, `search_path` vazio | presentes | OK |
| P15 | Efeitos colaterais não transacionais nos gatilhos das tabelas tocadas pelos harnesses | 24 gatilhos; nenhum usa `net.http`, `dblink`, `http`, `pg_notify` | nenhum | OK |
| P16 | Sequências em tabelas tocadas pelos harnesses | nenhuma (ids uuid) | — | sem lacunas de sequência |
| P17 | Transações abertas no momento | 0 em `idle in transaction`; nenhuma transação longa | — | registrado (repetir na hora) |
| P18 | `auth.uid()` | lê `request.jwt.claim.sub` e depois `request.jwt.claims` | como os scripts presumem | OK |
| P19 | Maior Set (base do 5837) | ME2.5: 295 cartas, 623 variantes ativas | — | registrado |

**Divergências entre o LIVE e a proposta:** nenhuma que bloqueie.

**Lacuna de evidência:** o LIVE não tem nenhuma coleção Pokédex (`REFERENCE_POSITION`). A regressão comportamental sobre dados reais (5838) cobre só Set padrão e coleção livre. Para a Pokédex há a identidade do código (5836 0.6), o caso 8.x e, opcionalmente, o `5814` antes e depois (seção 3).

**Ordem:** 5184 → 5197 é aplicável na ordem prevista. Cada arquivo é uma transação única (`begin … commit`), sem operação não transacional (sem `CONCURRENTLY`, `VACUUM` ou `ALTER TYPE … ADD VALUE`).

### Travas relevantes

| Migration | Trava | Em | Duração |
|---|---|---|---|
| 5184 | ShareRowExclusive (criação das FKs) | `collection`, `card_variant_type`, `auth.users` | milissegundos; bloqueia escritas nessas tabelas no instante do commit |
| 5185–5196 | travas de catálogo de funções e da tabela nova | — | desprezível |
| 5197 | **AccessExclusive** (DROP TABLE e remoção dos gatilhos RI) | `collection_master_set_scope`, `collection`, `card_variant`, `auth.users` | milissegundos, mas **bloqueia também leituras** e entra na fila atrás de qualquer transação aberta nessas tabelas |

Mitigação: repetir a consulta de transações abertas (P17) imediatamente antes de 5184 e de 5197; só aplicar com 0 transações longas. Com 3 usuários no LIVE o risco prático é baixo. Os arquivos são aplicados sem alteração, para o ledger ficar idêntico ao repositório.

### Limites de reversão

| Ponto | Reversível? | Como |
|---|---|---|
| Durante 5184–5196 | sim, sem perda | `RECOVERY-MASTER-SET-FINISH.sql`, caminho R-A |
| Depois de 5197 | sim, sem perda (tabela antiga estava vazia) | R-B1 e depois R-A |
| Depois de surgir coleção MASTER_SET real | não sem decisão de dados | só ocorre depois do frontend; fora desta rodada |

A janela entre 5188 e 5194 é segura: a ativação antiga ainda grava na tabela antiga, mas a presença diferida (5186) exige acabamento novo e recusa o COMMIT. Mesmo assim, recomenda-se aplicar 5184–5197 numa única sessão de trabalho.

## 2. Classificação dos testes

| Teste | Classe | Motivo | Condições |
|---|---|---|---|
| Pré-check, pós-check estrutural, guarda do 5197 como SELECT | **A** | só leitura de catálogo | — |
| `5838` T1, T2, T3, T4, T6 | **A** | DDL só temporária de sessão; snapshot em transação somente leitura; T1/T2 terminam em recusa; T6 falha no `\set` | psql, porta 5432, executado por Fabrício; autorização da DDL temporária |
| `5838` T5 (tentar escrever na fase B) | **C** | é um comando de escrita no LIVE, mesmo que recusado | substituído pela checagem que a função já faz (`transaction_read_only = on`) e pela recusa em T1/T2 |
| `5836` (74 checagens) | **A**, com autorização de escrita revertida | uma única instrução; dados sintéticos (expansão, 3 Sets, cartas, variantes) e 2 usuários temporários com sufixo aleatório; sentinela `MS000` desfaz tudo; resíduo conferido (99.1). Não há sequências nem efeito não transacional (P15/P16). O que fica: consumo de txid, WAL e tuplas mortas (autovacuum). Lê o resumo das 2 coleções reais de Set padrão (8.1) sem escrever nelas | depois de 5197; P17 limpo; `statement_timeout` padrão |
| `5837` (10 verificações) | **B** | mesmo isolamento do 5836, mas insere cerca de 3.000 exemplares temporários ligados a variantes reais do ME2.5 e cria 20 coleções temporárias; durante a execução, trava as linhas de `card_variant` referenciadas (KEY SHARE) e gera carga de escrita revertida | adaptação só no envelope: rodar fora de horário de uso, depois do 5836 PASS, uma única vez, e conferir resíduo; sem mudança no script |
| `5814` (Pokédex, Fatia E) antes e depois | **B** | regressão comportamental da Pokédex com dados de teste; escrito em 2026-09-06, antes de 5102 e de outras frentes, então pode ter falhas próprias | rodar antes de 5184 e depois de 5197; o critério é **saída idêntica** nas duas vezes, não 87/87 |
| `5839` | **C** | DDL real (schema, publicação, regra); destrutivo por construção | não executar no LIVE (opt-in impede) |
| K1–K5 | **B** | duas sessões com COMMIT; cria e apaga um usuário temporário, uma coleção e 2 exemplares reais (confirmados entre passos); depende de limpeza manual | só com autorização expressa; executado por Fabrício em psql; usuário temporário, nunca coleção real; resíduo zero conferido no fim |

## 3. Plano mínimo

| Etapa | Ação | Executor | Gate |
|---|---|---|---|
| E0 | Commit do estado documental atual (docs + pasta da proposta) | Fabrício | repositório limpo antes de tocar o LIVE |
| E1 | Pré-check (consulta da seção 4, bloco 1) + P17 | agente (leitura) | todos OK |
| E2 | Linha de base: `5838` duas vezes (psql); opcional `5814` (anotar saída) | Fabrício | 5838 todas as linhas `OK` e iguais nas duas execuções |
| E3 | Aplicar 5184 → 5196, um por vez, sem alteração (`apply_migration`) | agente, após autorização | cada uma conclui; após cada uma, confirmar no ledger |
| E4 | P17 de novo e aplicar 5197 | agente, após autorização | as checagens fail-closed passam; DROP conclui |
| E5 | Pós-check estrutural (seção 4, bloco 2) | agente (leitura) | todos os itens esperados |
| E6 | `5836` | agente (sentinela, sem resíduo) | **74/74 PASS + GATE PASS** |
| E7 | `5838` de novo; opcional `5814` | Fabrício | 5838 idêntico à linha de base; 5814 com saída idêntica à de E2 |
| E8 | `5837` fora de horário de uso | agente | 10/10 PASS + GATE (limites ajustáveis por Fabrício) |
| E9 | Security Advisor + performance advisor | agente (leitura) | saldo em `0029` = +3 conforme README; nenhum alerta novo de RLS |
| E10 | K1–K5 (opcional, autorização separada) | Fabrício | conforme roteiro; resíduo zero |
| E11 | Promoção canônica e documentação (05d, North Star, HANDOFF, ROADMAP, INDEX, log, OFFLINE-MANIFEST) | agente | depois de E6–E9 PASS; commit por Fabrício |

## 4. Comandos para aprovação

**Bloco 1 — pré-check (somente leitura):**
```sql
select
  (select count(*) from public.collection_master_set_scope)                       as scope_rows_0,
  (select count(*) from public.collection where completion_policy = 'MASTER_SET') as master_0,
  to_regclass('public.collection_master_set_finish')                              as finish_null,
  (select md5(regexp_replace(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\s+', '', 'g'))
     from pg_proc where proname = 'collection_completion_summary')               as summary_md5_0a644fe6,
  (select max(version) from supabase_migrations.schema_migrations)                as ledger_20261018012519,
  (select count(*) from pg_stat_activity
    where pid <> pg_backend_pid() and xact_start < now() - interval '30 seconds') as long_tx_0;
```

**Aplicação (E3/E4), uma chamada por arquivo, conteúdo sem alteração, nomes do ledger:**
`5184_create_collection_master_set_finish_table` · `5185_create_master_set_finish_eligibility_trigger` · `5186_update_master_set_presence_for_finish` · `5187_create_master_set_positions_function` · `5188_update_collection_completion_summary_master_finish` · `5189_create_get_my_master_set_positions_function` · `5190_create_normalize_master_set_finishes_function` · `5191_create_get_my_master_set_finish_options_function` · `5192_create_preview_my_master_set_finishes_function` · `5193_create_apply_master_set_finishes_function` · `5194_replace_set_collection_completion_policy_to_master_set` · `5195_create_replace_master_set_finishes_function` · `5196_create_get_my_master_set_out_of_scope_copies_function` · (P17) · `5197_retire_collection_master_set_scope`.

**Bloco 2 — pós-check estrutural (somente leitura):**
```sql
select
  to_regclass('public.collection_master_set_scope') is null                         as old_table_gone,
  (select relrowsecurity from pg_class where oid = 'public.collection_master_set_finish'::regclass) as rls_on,
  (select count(*) from pg_policy where polrelid = 'public.collection_master_set_finish'::regclass) as policies_1,
  has_table_privilege('authenticated', 'public.collection_master_set_finish', 'SELECT')
   and not has_table_privilege('authenticated', 'public.collection_master_set_finish', 'INSERT')
   and not has_table_privilege('anon', 'public.collection_master_set_finish', 'SELECT')      as table_grants_ok,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
     ('set_collection_completion_policy_to_master_set','replace_master_set_finishes','get_my_master_set_positions',
      'get_my_master_set_finish_options','preview_my_master_set_finishes','get_my_master_set_out_of_scope_copies')
     and p.prosecdef and p.proconfig = array['search_path=""']
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and not has_function_privilege('anon', p.oid, 'EXECUTE'))                          as public_contracts_6,
  (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
     ('master_set_positions','normalize_master_set_finishes','apply_master_set_finishes')
     and not has_function_privilege('authenticated', p.oid, 'EXECUTE'))                 as internal_closed_3,
  (select count(*) from pg_proc where proname = 'set_collection_completion_policy_to_master_set') as one_activation_1,
  (select count(*) from pg_trigger where tgname = 'trg_guard_card_variant_active')       as guard_triggers_3,
  (select count(*) from public.collection where completion_policy = 'MASTER_SET')       as master_0,
  (select count(*) from public.collection_master_set_finish)                            as finish_rows_0,
  (select count(*) from supabase_migrations.schema_migrations where name like '518%' or name like '519%') as ledger_entries;
```
Esperado: `true`, `true`, `1`, `true`, `6`, `3`, `1`, `3`, `0`, `0`, e 14 registros novos de 5184–5197 (mais os 5180–5183 já existentes no padrão `518%`, total 18).

**Harnesses:** `5836` e `5837` executados como estão (uma instrução, sentinela). **5838:** `psql "<string 5432>" -X -f 5838_baseline_completion_snapshot.sql`.

## 5. Critérios de interrupção (STOP) e recuperação

STOP imediato, sem seguir para a próxima etapa:

- qualquer divergência no pré-check ou transação longa em P17;
- erro em qualquer migration (a transação dela é desfeita; aplicar R-A no que já entrou);
- checagem do 5197 abortando (nada é removido; investigar a dependência apontada);
- pós-check fora do esperado;
- **qualquer FAIL do 5836 nas seções 0, 1, 2, 4, 9, 10 ou 99** (estrutura, segurança, validação, isolamento, preservação, resíduo) → R-A/R-B;
- FAIL do 5836 nas seções 3, 5, 6, 7, 8, 11 ou 12 (cálculo) → STOP e diagnóstico antes de qualquer reversão;
- 5838 com alguma linha `INVALIDO` ou md5 diferente da linha de base → STOP (regressão do Set padrão);
- resíduo diferente de zero em qualquer harness → STOP e limpeza;
- 5837 acima dos limites → PENDENTE, decisão de Fabrício (não é reversão automática).

Recuperação: `RECOVERY-MASTER-SET-FINISH.sql` (R0 guarda, R-B1 se 5197 entrou, R-A, R-V verificação), seguido de 5838 para provar o retorno à linha de base.

## 6. Riscos materiais remanescentes

| Severidade | Risco | Tratamento |
|---|---|---|
| Médio | Primeira execução real dos contratos e harnesses; erro de sintaxe ou de expectativa aparece só no LIVE | aplicação arquivo a arquivo; cada um é transacional; STOP + recuperação definidos |
| Médio | 5197 pega AccessExclusive em `collection`, `card_variant` e `auth.users` | P17 imediatamente antes; janela de baixo uso |
| Baixo | Regressão da Pokédex sem coleção real para comparar | 5836 0.6/8.x + `5814` antes/depois (B) |
| Baixo | 5837 gera carga de escrita revertida sobre variantes reais | fora de horário de uso, execução única |
| Baixo | K1–K5 confirmam dados temporários entre passos | opcional, autorização separada, limpeza e resíduo conferidos |

## 7. Esforço estimado (sem falhas)

| Bloco | Tempo |
|---|---|
| E0–E2 (commit, pré-check, linha de base) | 20–30 min (inclui 2 execuções psql de Fabrício) |
| E3–E5 (14 migrations + pós-check) | 30–40 min |
| E6–E9 (5836, 5838, 5837, advisors) | 30–45 min |
| E10 (K1–K5, opcional) | 45–60 min com Fabrício em duas sessões psql |
| E11 (promoção e documentação) | 45–60 min |
| **Total** | **cerca de 2h30 a 4h** — falha em qualquer gate acrescenta diagnóstico e não é estimável antes |

## 8. LIVE-EXECUTION-START-01 (2026-10-18)

- **E1 repetido (só leitura, 16:36 UTC):** sem mudança — 0 scope, 0 MASTER_SET, 3 coleções, md5 `0a644fe6…`, ledger `20261018012519`, 0 transações longas, 1.351 exemplares, 210 vínculos, 3 usuários, 4 gatilhos de 2268, nenhum objeto novo.
- **Recuperação confirmada:** os 9 corpos canônicos usados na reversão são equivalentes aos do LIVE (6 idênticos; 5079, 5080 e 5084 diferem só por comentários de linha); ACLs iguais. `RECOVERY-MASTER-SET-FINISH.sql` v1.1 traz a ordem exata dos dois caminhos, a convenção de ledger (`ms_finish_recovery_<NN>_<o-que>`, sem apagar histórico) e o gate com os md5 esperados.
- **Falha concreta corrigida no 5838 (v1.3):** o resumo (5102) não devolve linha para coleção livre (`NONE`); o LIVE tem 1, e a v1.2 marcaria o snapshot como `INVALIDO` sempre. A v1.3 registra `id|NONE|SEM_RESUMO` (entra no md5, não é lacuna). Nenhuma outra mudança.
- **Baseline esperado do 5838 no LIVE de hoje:** 4 linhas — `NONE × OPEN_CURATION` (1), `STANDARD_SET × REFERENCE_BASED` (2), COBERTURA `3/3, 0, 0`, GATE com digest — todas `OK`.
