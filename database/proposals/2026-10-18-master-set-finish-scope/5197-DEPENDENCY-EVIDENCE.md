# 5197 — Evidência de dependências dos objetos 02F aposentados

| Campo | Valor |
|---|---|
| Rodada | MASTER-SET-FINISH-SCOPE-AUDIT-CORRECTION-01 (2026-10-18); seções 6–9 na AUDIT-CORRECTION-02 |
| Alvo | `5197_retire_collection_master_set_scope.sql` v1.2 |
| Fontes | LIVE `qjfutqujxrbzgrtkpgkg` (somente leitura, 2026-10-18) e repositório no HEAD `db61330` + esta proposta |
| Status | Levantamento concluído. A remoção **não** foi executada. |

Premissa corrigida: uma tabela vazia não basta para removê-la. Este documento lista o que referencia os objetos antigos, onde cada referência fica e como 5197 se protege.

## 1. Objetos removidos por 5197

| Objeto | Origem | Remoção |
|---|---|---|
| `public.collection_master_set_scope` (tabela) | 5072 | `DROP TABLE` — leva junto PK, FKs, policy, gatilhos 5073/5074/5077 e `trg_guard_card_variant_active` (2268) |
| `validate_master_set_scope_eligibility()` | 5073 | `DROP FUNCTION` |
| `reject_collection_master_set_scope_update()` | 5074 | `DROP FUNCTION` |
| `enforce_scope_master_set_presence_on_delete()` | 5077 | `DROP FUNCTION` |
| `apply_master_set_scope_diff(uuid, jsonb)` | 5079 | `DROP FUNCTION` |

Substituídos antes, por `CREATE OR REPLACE` / `DROP` nas migrations anteriores da proposta: `collection_master_set_scope_positions` (5084 → 5189), `set_collection_completion_policy_to_master_set(uuid, jsonb)` (5080 → 5194), `replace_master_set_scope` (5082 → 5195), `check_master_set_scope_presence` (5075 → 5186, corpo novo), `collection_completion_summary` (5102 → 5188).

## 2. LIVE (somente leitura)

| Verificação | Resultado |
|---|---|
| Linhas em `collection_master_set_scope` | 0 |
| Coleções `MASTER_SET` | 0 |
| Funções cujo corpo cita algum objeto antigo | Todas têm destino na proposta (substituídas em 5186/5188/5189/5194/5195 ou removidas em 5197). Nenhuma fica órfã. |
| Views / materialized views | nenhuma referência |
| Publicações (Realtime/replicação) | a tabela não está em nenhuma |
| `pg_cron` / regras (`pg_rewrite` fora de views) | nenhuma referência |
| Grants da tabela | `authenticated` SELECT · `service_role` REFERENCES/TRIGGER/TRUNCATE · `postgres` ALL — somem com o DROP |
| Gatilho de 2268 na tabela | removido junto com a tabela; a função `internal.guard_card_variant_reference_active` é preservada (usada por mais 3 tabelas) |

Efeito colateral documentado: a consulta "Como validar" de 2268 passa de 4 para 3 gatilhos `trg_guard_card_variant_active` (`pricing_product`, `physical_card`, `collection_layout_slot_expected_content`).

## 3. Repositório

| Onde | O que | Risco | Tratamento |
|---|---|---|---|
| Corpos das funções 5184–5196 desta proposta | busca por palavra inteira dos 7 nomes antigos | — | **0 ocorrências** (verificado nesta rodada) |
| `database/schema` 5091, 5098, 5099, 5101, 5113, 6115 | apenas comentários citando o 02F | nenhum | nada a fazer; o guarda (c) de 5197 olha `prosrc` do banco, não comentários de arquivo |
| Scripts D2-01 / D2-03 (executados em 2026-10-09) | consultam a tabela antiga | baixo | falhariam se reexecutados depois de 5197; são registros históricos, não rotinas |
| `OFFLINE-MANIFEST-01` | lista 5072–5077 | baixo | o ambiente offline ficará desatualizado; atualizar o manifesto na promoção canônica |
| `IMPACTED-CONTRACTS.md` | menciona 5084 | nenhum | registro histórico |
| Frontend (`web/`) | nenhuma chamada às RPCs antigas | — | o frontend do Master Set ainda não existe |

## 4. Guardas fail-closed em 5197 v1.2

A migration aborta antes de qualquer `DROP` se:

- (0) a tabela não existir ou não for tabela comum (partição ou herança);
- (a) a tabela tiver qualquer linha;
- (b) existir coleção `MASTER_SET` sem acabamento;
- (c) algum corpo de função, fora das quatro removidas, citar um dos 7 nomes antigos (regex `\m…\M`);
- (d) alguma view ou materialized view citar a tabela;
- (e) a tabela estiver em alguma publicação;
- (f) houver em `pg_depend`, sobre a tabela, seu tipo-linha, seu tipo array ou as quatro funções removidas, um objeto que **não pertença à própria tabela** (critério na seção 7).

## 5. Pendente (requer PostgreSQL)

- Executar `5839` (16 casos) num ambiente descartável e anexar a saída.
- Executar 5197 numa base com 5184–5196 aplicadas e confirmar que as 7 checagens passam e o `DROP` conclui.

## 6. BLOCKER 1 da AUDIT-CORRECTION-02 — diagnóstico

O guarda (f) da v1.1 excluía dependências **por classe** (`pg_constraint`, `pg_trigger`, `pg_policy`, `pg_attrdef`, `pg_type`) e tratava todo o resto como externo. Dois defeitos:

1. **Falso positivo.** Objetos próprios registrados em outras classes faziam o guarda disparar: índice comum ou de expressão (`pg_class`, deptype `a`), tabela TOAST (`pg_class`, `i`), sequência de identity/serial (`pg_class`, `a`/`i`), estatística estendida (`pg_statistic_ext`, `a`). No LIVE de hoje a tabela só tem o índice da PK (que depende da constraint, não da tabela) e não tem TOAST, por isso a v1.1 não dispararia agora. Bastaria, porém, um índice de FK criado antes de 5197 para bloquear a remoção sem motivo. O `5839` P3 reproduz isso.
2. **Mascaramento.** Por excluir a classe inteira, a v1.1 também deixava passar FK e policy **de outra tabela** que apontassem para a antiga. O `DROP TABLE` sem `CASCADE` (RESTRICT) ainda recusaria esses casos, mas sem o diagnóstico do guarda.

Também não basta trocar a classe pelo `deptype` (`a`/`i` próprios, `n` externo). No LIVE, a policy e o gatilho de 2268 da própria tabela têm dependência `n` sobre uma coluna, porque a coluna aparece na expressão da policy e no `UPDATE OF` do gatilho. Um guarda baseado só em deptype dispararia indevidamente no LIVE.

## 7. Critério da v1.2 — classificação por dono

Para cada linha de `pg_depend` cujo objeto referenciado seja a tabela (qualquer coluna), o tipo-linha, o tipo array ou uma das quatro funções removidas, o objeto dependente é **interno** só se pertencer à própria tabela:

| Classe do dependente | Interno quando | Cai com o DROP? |
|---|---|---|
| `pg_constraint` | `conrelid` = tabela (PK, FK, UNIQUE, CHECK, constraint trigger) | sim |
| `pg_trigger` | `tgrelid` = tabela, ou gatilho RI cuja constraint tem `conrelid` = tabela | sim |
| `pg_policy` | `polrelid` = tabela | sim |
| `pg_attrdef` | `adrelid` = tabela | sim |
| `pg_type` | o próprio tipo-linha ou tipo array | sim |
| `pg_class` (índice) | deptype `a`/`i` e `pg_index.indrelid` = tabela | sim |
| `pg_class` (TOAST) | deptype `i` e é o `reltoastrelid` da tabela | sim |
| `pg_class` (sequência) | deptype `a`/`i` e `relkind = 'S'` (a dependência é o OWNED BY de uma coluna) | sim |
| `pg_statistic_ext` | `stxrelid` = tabela | sim |
| qualquer outra combinação | — **bloqueia** | — |

"Qualquer outra" inclui as classes não previstas, então o padrão é negar: regra (`pg_rewrite`), view, publicação (`pg_publication_rel`), função com corpo SQL-padrão ou parâmetro do tipo-linha (`pg_proc`), tabela filha ou coluna do tipo-linha em outra tabela (`pg_class`), FK/policy/gatilho de outra tabela. Nenhuma exclusão é genérica: cada uma exige prova de pertença à tabela.

O mesmo critério cobre as funções removidas: os únicos dependentes aceitos são os gatilhos da própria tabela. Um gatilho em outra tabela usando uma delas bloqueia (`5839` N10).

O bloco `<dep-guard v1.2>` é idêntico em 5197 e 5839. A comparação textual nesta rodada deu igual: 52 linhas, md5 `97a0b630aeca…`.

## 8. Evidência obtida

**LIVE (somente leitura de catálogo, PostgreSQL 17.6, 2026-10-18):**

| Dependente | Classe / deptype | Classificação |
|---|---|---|
| 4 constraints (PK, 3 FKs) + constraint trigger 5077 | `pg_constraint` / a | interno (`conrelid`) |
| gatilhos 5073, 5074, 5077 e `trg_guard_card_variant_active` (2268) | `pg_trigger` / a | interno (`tgrelid`) |
| `trg_guard_card_variant_active` (coluna `card_variant_id`) | `pg_trigger` / **n** | interno (`tgrelid`) |
| policy `collection_master_set_scope_select_own` | `pg_policy` / a e **n** (coluna 1) | interno (`polrelid`) |
| default de `adopted_at` | `pg_attrdef` / a | interno |
| tipo-linha e tipo array | `pg_type` / i | interno |
| gatilhos das 3 funções removidas (dependência na função) | `pg_trigger` / n | interno (gatilho da própria tabela) |
| 6 gatilhos RI em `collection`, `card_variant`, `auth.users` | sem dependência sobre a tabela (dependem da constraint) | caem com as FKs |

Outras leituras do LIVE: 19 linhas examinadas; o critério da v1.2, rodado como SELECT, devolveu **NULL** (nada bloqueia); 0 publicações; 0 herança; `relkind` `r`, não particionada; sem TOAST; único índice = PK.

**Repositório:** seção 3.

## 9. Limites da prova

- O LIVE só mostra o estado de hoje, antes de 5184–5196. Os guardas rodam de novo na aplicação e é isso que vale.
- `pg_depend` não registra referências dentro de corpos plpgsql ou SQL em string, nem SQL dinâmico. O guarda (c) cobre o texto dos corpos por palavra inteira; SQL montado em tempo de execução (`format('… %I …')`) com o nome dividido escaparia de ambos. Nenhuma ocorrência desse tipo foi encontrada no repositório (seção 3).
- Dependências fora do banco (frontend, Edge Functions, scripts) não aparecem no catálogo; seção 3.
- Objetos em outros bancos do cluster não são vistos (não há).
- Os casos negativos do `5839` ainda não foram executados.
