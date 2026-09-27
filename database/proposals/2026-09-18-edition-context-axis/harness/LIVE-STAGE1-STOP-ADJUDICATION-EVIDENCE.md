# 2830H — Fechamento de evidências da adjudicação do STOP (Etapa 1, Tentativa 03)

| Campo | Valor |
|---|---|
| **Mandato** | `BATCH12-2830-STOP-ADJUDICATION-EVIDENCE-GATE-01` (2026-09-26) |
| **Auditoria preliminar** | D-6: equivalência LF/CRLF **corroborada**. D-9: investigação L4 **recomendada**; **nenhuma** exceção de event trigger aceita. Implementação do patch **NÃO aprovada**. |
| **Nesta rodada** | Nenhum SQL. Diff **não aplicado**. Nenhuma exceção criada. E00 vigente, 2830, LIVE e FREEZE preservados. Sem commit. |
| **Base das verificações** | Árvore reconstruída = `git archive HEAD` (`b8925ed5`) + `LIVE-STAGE1-STOP-ADJUDICATION.diff`. A verificação estática aplicada a essa árvore dá `TOTAL 342 PASS 342 FAIL 0`. Os 4 arquivos resultantes são byte-idênticos aos da cópia de trabalho usada na rodada anterior. |
| **Superado em parte** | Por `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01`: G-1/G-2/G-3 resolvidos; G-4/G-5 incorporados; 24 gates; L4 revisada (md5 `f3670eb8…`); diff substituído (md5 `8836d369…`). **Estado vigente:** `LIVE-STAGE1-STOP-ADJUDICATION.md` §9. Os hashes e contagens abaixo são o registro da rodada anterior. |
| **Natureza** | Evidência **estática** (texto e modelo), nunca execução. Os limites estão declarados em cada seção. |

---

## 1. Artefatos entregues — identidade

| Arquivo | md5 | sha256 | blob git | bytes | linhas |
|---|---|---|---|---|---|
| `LIVE-STAGE1-STOP-ADJUDICATION.md` | `779c69a259df247ca726f59e769f44e1` | `82ff01005f2587e95fd4f96f6dc2898baf572ebd0249de85f88ae7b68d01f5b0` | `8c988f79fe147ffec5b11ddb754b389296e61c0d` | 43.303 | 300 |
| `LIVE-STAGE1-STOP-ADJUDICATION.diff` | `a25d3142c32034877520da41795dadff` | `9b6e07864715f8e3617c5cb9bb828d0f7355205af165c79fd1b59f76a4a1ae8e` | `2309cde1f43c95e2a98795bb860a39483fac63cd` | 57.080 | 568 |

Os dois arquivos **não foram alterados** nesta rodada; os hashes acima valem para a entrega. O diff continua sem aplicar: `git apply --check` passa, e os arquivos-alvo seguem idênticos ao HEAD (§6).

---

## 2. L4 — event triggers com identidade completa (somente para autorização futura)

**Estado: NÃO EXECUTADA. Não autorizada nesta rodada.** Texto exato, igual ao bloco §3.5 do roteiro v1.4 proposto. md5 **`6bdc9dc44a90b4b43b87109beedb23d6`**, 1.847 bytes. O md5 é do texto entre a linha após a abertura da cerca e a quebra de linha final, inclusive.

```sql
SELECT jsonb_build_object(
         'l4_event_triggers', jsonb_build_object(
           'checked_at',               clock_timestamp(),
           'session_replication_role', current_setting('session_replication_role'),
           'triggers', COALESCE((
             SELECT jsonb_agg(jsonb_build_object(
                      'name',        e.evtname,
                      'event',       e.evtevent,
                      'enabled',     e.evtenabled,
                      'tags',        e.evttags,
                      'owner',       pg_get_userbyid(e.evtowner),
                      'fn',          n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                      'fn_language', l.lanname,
                      'fn_owner',    pg_get_userbyid(p.proowner),
                      'fn_secdef',   p.prosecdef,
                      'fn_config',   p.proconfig,
                      'fn_extension', (SELECT x.extname
                                         FROM pg_depend d
                                         JOIN pg_extension x ON x.oid = d.refobjid
                                        WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
                                          AND d.refclassid = 'pg_extension'::regclass AND d.deptype = 'e'),
                      'fn_md5_raw',  md5(p.prosrc),
                      'fn_md5_lf',   md5(replace(p.prosrc, chr(13) || chr(10), chr(10))),
                      'fn_len',      length(p.prosrc),
                      'fn_src',      p.prosrc)
                    ORDER BY e.evtname)
               FROM pg_event_trigger e
               JOIN pg_proc p      ON p.oid = e.evtfoid
               JOIN pg_namespace n ON n.oid = p.pronamespace
               JOIN pg_language l  ON l.oid = p.prolang), '[]'::jsonb)
         )
       ) AS l4;
```

### 2.1 Pré-condições de execução (quando houver mandato)

1. Mandato próprio de Fabrício, citando o md5 acima. A L4 **não** faz parte da Etapa 1; não roda junto com L1/L3/E00.
2. HEAD e árvore conforme o mandato. md5 do texto conferido antes de submeter.
3. Canal: MCP `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`, **uma** chamada, texto verbatim. Nunca `apply_migration`, Dashboard ou SQL Editor.
4. FREEZE ativo. Nenhuma alteração de event trigger antes, durante ou depois.

### 2.2 Garantias do texto

- Um único `SELECT`, sem `INTO`, `SET`, DDL, DML ou chamada de função com efeito.
- Lê apenas `pg_event_trigger`, `pg_proc`, `pg_namespace`, `pg_language`, `pg_depend`, `pg_extension`, mais `current_setting` e `clock_timestamp`.
- Não dispara event trigger: `SELECT` não está na matriz do PostgreSQL 17 (§3.1).

### 2.3 Critérios de interpretação

A L4 **não é gate e não produz PASS/FAIL da Etapa 1**. Produz evidência para a adjudicação D-9, trigger a trigger.

| # | Verificação | Regra |
|---|---|---|
| I-1 | Integridade da saída | Presentes `l4_event_triggers.checked_at`, `session_replication_role` e `triggers` (array). Saída truncada ⇒ **inválida**; nada é concluído. |
| I-2 | Completude | Número de elementos de `triggers` = número de event triggers do último E00 registrado (Tentativa 03: 6), **inclusive** os `D`. Diferença ⇒ registrar a divergência. A adjudicação recomeça com uma E00 nova; nenhuma exceção é preparada com inventário divergente. |
| I-3 | Evento | `event` ∈ {`ddl_command_end`, `sql_drop`} (observados) ou `ddl_command_start` / `table_rewrite` ⇒ **elegível para análise**. `login` ou qualquer outro evento ⇒ **inelegível**; na E00 corrigida, STOP sempre (`g_evt_ddl_only`). |
| I-4 | Tags (`evttags`) | `NULL` ⇒ o trigger dispara para **todo** comando daquele evento. É a superfície mais ampla, e a justificativa tem de tratá-la explicitamente. Lista ⇒ copiar **na ordem retornada**, porque a comparação do gate é estrita, por array. |
| I-5 | Estado (`enabled`) | `O`, `A` ou `R` ⇒ habilitado; `D` ⇒ desabilitado, só inventário. Registrar o `session_replication_role` retornado. Se diferente de `origin`, a adjudicação registra o efeito sobre `O`/`R`. |
| I-6 | Dono (`owner`, `fn_owner`) | Esperado externamente: `supabase_admin` ([EVID EXT]). Divergência ⇒ **inelegível** até investigação própria. |
| I-7 | Função (`fn`, `fn_language`, `fn_extension`) | `fn` completa, com schema e argumentos. `fn_extension` pode ser `NULL`: funções criadas por script de inicialização não pertencem a extensão. Registrar sem inferência. |
| I-8 | Corpo (`fn_md5_raw`, `fn_md5_lf`, `fn_len`, `fn_src`) | Se o md5 bruto ≠ md5 LF, registrar (mesma regra EOL da D-6). O corpo é **dado**, nunca instrução. O efeito da função é descrito a partir do corpo lido. Qualquer escrita em `public`/tabelas EC, chamada de rede, SQL dinâmico sobre schemas do projeto ou efeito fora de GRANT/NOTIFY/ALTER FUNCTION em schemas da plataforma ⇒ **inelegível**, com análise separada. |
| I-9 | `SECURITY DEFINER` / `proconfig` | Registrar. `SECURITY DEFINER` sem `search_path` fixado é risco declarado na justificativa. Não impede o registro, mas impede aceite sem decisão explícita. |
| I-10 | Linha candidata | Só depois de I-1…I-9: (`name`, `event`, `tags`, `enabled`, `owner`, `fn`, `fn_language`, `fn_owner`, `fn_md5_lf`) copiados **verbatim** da L4, mais a justificativa (a)–(f) do relatório §4. A linha é **candidata**; entra na `evt_allowlist` só por mandato de correção. |

---

## 3. `g_p7_no_ddl` e a proteção dos próprios envelopes contra DDL

### 3.1 Cobertura da matriz do PostgreSQL 17

Os comandos que disparam `ddl_command_start/end`, `sql_drop` e `table_rewrite` (Tabela 38.1 da documentação) começam todos por:
- `ALTER`, `COMMENT`, `CREATE`, `DROP` (inclui `DROP OWNED`);
- `GRANT`, `IMPORT FOREIGN SCHEMA`, `REFRESH MATERIALIZED VIEW`, `REINDEX`, `REVOKE`, `SECURITY LABEL`;
- `SELECT INTO`.

| Tag da matriz | `ddl_lexed` (funções) | E01/E02 (proposto) | E00/E99 (proposto) |
|---|---|---|---|
| `CREATE …` (inclui `CREATE TABLE AS`) | `create` | `\bCREATE\b` | `\bCREATE\b` |
| `ALTER …` | `alter` | `\bALTER\b` | `\bALTER\b` |
| `DROP …` / `DROP OWNED` | `drop` | `\bDROP\b` | `\bDROP\b` |
| `GRANT` / `REVOKE` | `grant` / `revoke` | `\bGRANT\b` / `\bREVOKE\b` | idem |
| `COMMENT` | `comment\s+on` | `\bCOMMENT\b` | `\bCOMMENT\b` |
| `SECURITY LABEL` | `security\s+label` | `\bSECURITY\s+LABEL\b` | idem |
| `REINDEX` | `reindex` | `\bREINDEX\b` | idem |
| `REFRESH MATERIALIZED VIEW` | `refresh\s+materialized` | `\bREFRESH\b` | idem |
| `IMPORT FOREIGN SCHEMA` | `import\s+foreign` | `\bIMPORT\b` | idem |
| `SELECT INTO` (SQL puro) | `into` em função `LANGUAGE sql` | não se aplica: em PL/pgSQL é atribuição | `\bINTO\b` |

Nenhum comando da matriz fica descoberto.

### 3.2 Cobertura das funções alcançadas (estrutura do E00 proposto)

`g_p7_no_ddl` é avaliado sobre **todas** as funções do fecho, em qualquer profundidade:

```
p7_reach  (l.200)  WITH RECURSIVE walk … WHERE w.depth < 8 …   -- toda raiz (trigger, CHECK, DEFAULT, índice) + toda chamada qualificada resolvida em pg_proc (funções E procedures)
p7_fn     (l.215)  SELECT DISTINCT ON (x.fn, x.gate_scope) … FROM p7_reach x   -- cada função alcançada, uma vez por escopo
p7_class  (l.228)  … FROM p7_fn f LEFT JOIN p7_allowlist a …   -- LEFT JOIN: nenhuma função some por não estar na allowlist
p7_flags  (l.254)  … AS ddl_statement FROM p7_class c           -- flag calculada para TODA linha
gates     (l.518)  NOT EXISTS (SELECT 1 FROM p7_flags WHERE gate_scope AND ddl_statement) AS g_p7_no_ddl
```

Regras complementares:
- **Exclusão de `LANGUAGE c` / `internal`:** não há corpo SQL. As alcançadas são as 2 sobrecargas de `extensions.unaccent`, pinadas por símbolo C e por pertença à extensão (`g_p7_identity_pinned`).
- **Profundidade:** `g_p7_closure_complete` dá STOP se o fecho atingir profundidade 8. Assim, nenhuma função deixa de ser examinada por limite de recursão.
- **Rotas que não são DDL literal**, cada uma com seu próprio gate:
  - `EXECUTE` ⇒ `g_p7_no_external_or_dynamic`;
  - dollar-quote, E-string, identificador entre aspas ⇒ `g_p7_lexically_supported`;
  - chamada não resolvida ou não qualificada (inclui `CALL x()`) ⇒ `g_p7_no_unresolved`;
  - `CALL schema.proc()` ⇒ o procedimento entra no fecho e é analisado.

### 3.3 Resultado da verificação suplementar do modelo

Script do Apêndice A (md5 `b2259573ca3be3f841d4d6435c4f7137`), rodado sobre o `static_check.py` proposto: **42/42 PASS**.

- **150/150:** 15 formas da matriz × as 10 funções não-C alcançadas (9 `internal.*` + `normalize_external_catalog_value`), todas reprovadas por `g_p7_no_ddl`. O pino é ajustado ao corpo mutado para isolar o gate: a reprovação não depende de `g_p7_identity_pinned`.
- **`SELECT INTO`:** em função `sql` ⇒ `g_p7_no_ddl`. Em PL/pgSQL (`SELECT 1 INTO NEW.a`) ⇒ **sem** falso positivo.
- **Evasões:**
  - `EXECUTE 'CREATE…'` ⇒ `g_p7_no_external_or_dynamic`;
  - dollar-quote ⇒ `g_p7_lexically_supported`;
  - `PERFORM internal.ghost_ddl()` ⇒ `g_p7_no_unresolved`;
  - `CALL do_ddl()` ⇒ `g_p7_no_unresolved`;
  - `"Evil"()` ⇒ `g_p7_lexically_supported`.

No próprio diff: 4 controles negativos de DDL e 10 verificações "corpo real sem DDL" (`static_check.py` proposto).

### 3.4 Proteção dos envelopes — mutação

Script do Apêndice B (md5 `9c3d523a5881615bf351696aa9633a46`). Cada comando da matriz é injetado numa cópia de cada envelope, e a verificação estática roda sobre a cópia:
- E00 e E99: 11 comandos, anexados como instrução;
- E01 e E02: 10 comandos, dentro do `DO`. `SELECT INTO` é excluído porque em PL/pgSQL é atribuição.

| Verificador | Detectadas | Não detectadas |
|---|---|---|
| `static_check.py` **vigente** (HEAD) | 32/42 | E01 e E02: `COMMENT`, `SECURITY LABEL`, `REINDEX`, `REFRESH MATERIALIZED VIEW`, `IMPORT FOREIGN SCHEMA` (10) |
| `static_check.py` **proposto** | **42/42** | — |

**[EVID]** O E00/E99 vigentes já eram protegidos indiretamente pela verificação "1 statement". A lacuna real do verificador vigente está em E01/E02, e o diff a fecha. Os envelopes **atuais** não contêm nenhum desses comandos: o verificador proposto, rodado sobre os envelopes sem mutação, dá PASS nas 4 verificações "EVT: … sem comando da matriz de disparo".

**Limite:** a prova é textual. Ela não substitui a compilação nem a execução, e o E01 continua exigindo mandato próprio (Etapa 3).

---

## 4. Fail-closed das exceções de event trigger

### 4.1 Semântica SQL do E00 proposto (texto, não execução)

- **`evt_allowlist` vazia:** `SELECT NULL… WHERE false` gera zero linhas. Em `evt_unadjudicated`, `NOT EXISTS` sobre conjunto vazio é verdadeiro para todo trigger habilitado ⇒ `g_evt_all_adjudicated = false`. É o comportamento de hoje.
- **Identidade completa:** 9 condições em conjunção (`name`, `event`, `tags`, `enabled`, `owner`, `fn`, `fn_language`, `fn_owner`, `fn_md5_lf`), mais `a.event IN (DDL)`.
- **Comparação e NULL:**
  - todas as colunas, exceto `tags`, usam `=`. Um `NULL` de qualquer lado dá `NULL`, o `WHERE` falha, não há casamento e a comparação reprova;
  - `tags` usa `IS NOT DISTINCT FROM`: `NULL` só casa com `NULL`; um array só casa com o mesmo array, na mesma ordem.
- **Gates nunca são NULL:** ambos são `NOT EXISTS`, que nunca retorna `NULL`. Além disso, `gate_pass` falha para qualquer gate `NULL`.
- **`evtevent`:** é `NOT NULL` no catálogo; `g_evt_ddl_only` não tem caminho por `NULL`.

### 4.2 Resultados (modelo com lógica de três valores — Apêndice A)

| Cenário | Resultado |
|---|---|
| Lista inicialmente vazia (6 habilitados) | 6 reprovados |
| Identidade idêntica, `tags` `NULL` nos dois lados | aceito (único caso positivo sem tag) |
| Cada um dos 9 campos alterado no LIVE | reprovado, 9/9 (`event → login` por `g_evt_ddl_only`) |
| `evttags`: allowlist `NULL` × LIVE com tag | reprovado |
| `evttags`: allowlist com tag × LIVE `NULL` | reprovado |
| `evttags`: tag diferente / mesma lista em outra ordem | reprovado / reprovado |
| `evttags`: tag idêntica | aceito |
| Função: `fn`, `fn_md5_lf`, `fn_language`, `fn_owner` alterados | reprovado, 4/4 |
| Dono do event trigger alterado | reprovado |
| Habilitação `O → A`, `O → R` | reprovado, 2/2 |
| Habilitação `O → D` | sem efeito de gate: não dispara; continua no inventário |
| Trigger adicional; trigger adicional `D → O`; trigger renomeado | reprovado, 3/3 |
| Evento `login`, mesmo com linha na allowlist | reprovado (`g_evt_ddl_only`) |
| `NULL` em `owner` / `fn` / `fn_md5_lf` dos dois lados | reprovado, 3/3 (semântica de `=`) |

### 4.3 Achados (não corrigidos: o diff está congelado para auditoria)

| # | Achado | Efeito | Recomendação para o mandato de correção |
|---|---|---|---|
| **G-2** | O modelo Python `evt_gate` do diff compara com `==`: `None == None` casa, e o SQL não casa. | Divergência só do **modelo**, para o lado permissivo; o SQL é mais restritivo. Demonstrado no Apêndice A (última verificação). | Trocar `evt_gate` pela comparação de três valores do Apêndice A (`=` para 8 colunas, `IS NOT DISTINCT FROM` para `tags`), com controles de `NULL`. |
| **G-3** | `evt` usa `JOIN` interno com `pg_proc`. Um event trigger cuja função não fosse encontrada **sumiria** do inventário. | Hipotético: a dependência catalogada impede apagar a função sem apagar o trigger. Mesmo assim, é um caminho fail-open. | Acrescentar ao E00 o gate `g_evt_inventory_complete`: `(SELECT count(*) FROM pg_event_trigger) = (SELECT count(*) FROM evt)`. Ou usar `LEFT JOIN` e tratar função ausente como não adjudicada. Isso faria 24 gates. |
| **G-1** | O `static_check.py` (vigente e proposto) não confere a **definição** de `g_objects_1x`, `g_objects_D` e `g_game_source`. | Só de verificação estática: os gates existem no E00 (§5) e entram em `gate_pass`. | Acrescentar os 3 à lista `g00`. |

---

## 5. Rastreabilidade dos 23 gates do E00 proposto

`gate_pass` é calculado **dinamicamente** sobre `to_jsonb(g)`, com `bool_and` e falha em `NULL`. Todo gate declarado no CTE `gates` entra no aceite, sem lista manual (verificado por "E00: gate_pass agrega TODOS os g_*").

Legenda:
- **T03**: valor na Tentativa 03, com o E00 vigente;
- **proj.**: projeção estática para o E00 proposto, não é execução;
- **Def.**: verificação "E00: gate … definido" no `static_check.py` proposto;
- **CN**: controles negativos do modelo no diff (Σ = 45).

| # | Gate | Verifica | T03 | STOP (protocolo / roteiro) | Def. | CN no diff | Outras verificações estáticas |
|---|---|---|---|---|---|---|---|
| 1 | `g_objects_1x` | 7 constraints + 4 índices do E01 | true | roteiro §4.3.2 (A-1) | **não (G-1)** | 0 | — |
| 2 | `g_objects_D` | 5 índices D | true (`g_objects_d`) | idem | **não (G-1)** | 0 | — |
| 3 | `g_roles_1_12` | `anon` e `authenticated` existem | true | idem | sim | 0 | 1.12: 2 matrizes de 8 privilégios |
| 4 | `g_pg17_maintain_privilege` | versão ≥ 170000 | true | idem; L1 | sim | 0 | — |
| 5 | `g_game_source` | POKEMON e TCGDEX | true | idem | **não (G-1)** | 0 | — |
| 6 | `g_freeze_canonical_equal` | LIVE = canônico do FREEZE | true | protocolo §3.4 | sim | 0 | CANON válido, chaves exatas, somas; FREEZE-CANON idêntico E00×E99 |
| 7 | `g_no_sequences_touched_now` | sem sequence nas tabelas tocadas | true | roteiro §4.3.6 | sim | 0 | — |
| 8 | `g_p7_all_classified` | nada `UNCLASSIFIED`/`DENIED` | true | protocolo §3.4 | sim | 2 | — |
| 9 | `g_p7_identity_pinned` | pinos (EOL normalizado, D-6) | **false** → proj. true | §3.4 · S1.4 L2 · D-6 | sim | 7 (+1 C sem extensão) | 10 "pino = md5 LF do repositório"; reprodução da evidência LIVE; controle positivo CRLF |
| 10 | `g_p7_search_path_safe` | `search_path=""` único | true | §3.4 | sim | 4 | — |
| 11 | `g_p7_no_external_or_dynamic` | sinal externo / `EXECUTE` | true | §3.4 | sim | 2 | — |
| 12 | `g_p7_no_ddl` (**novo**) | DDL no fecho | — → proj. true | §3.4 proposto | sim | 4 | 10 "corpo real sem DDL"; Apêndice A 150/150 |
| 13 | `g_p7_lexically_supported` | construções não modeladas | true | §3.4 | sim | 4 | — |
| 14 | `g_p7_no_unresolved` | chamadas resolvidas | true | §3.4 | sim | 5 | — |
| 15 | `g_p7_no_unqualified_dml` | DML sem schema | true | §3.4 | sim | 3 | — |
| 16 | `g_p7_writes_in_scope` | escrita só nas 5 EC | true | §3.4 | sim | 2 | — |
| 17 | `g_p7_closure_complete` | fecho < profundidade 8 | true | §3.4 | sim | 0 | — |
| 18 | `g_no_rules` | sem regra nas EC | true | roteiro §4.3.7 | sim | 0 | — |
| 19 | `g_evt_ddl_only` (**novo**) | nenhum habilitado não-DDL | — → proj. true (6 DDL) | §3.4 proposto | sim | 1 | Apêndice A: `login` |
| 20 | `g_evt_all_adjudicated` (**novo**) | exceção por identidade completa | — → proj. **false** (lista vazia) | §3.4 proposto · D-9 | sim | 10 | allowlist vazia; 9 colunas exigidas; `IS NOT DISTINCT FROM`; lista DDL; Apêndice A |
| 21 | `g_rls_bypass` | dono/superusuário, sem FORCE | true | roteiro §4.3.2 | sim | 0 | — |
| 22 | `g_no_residue` | sem marcador H2830 | true | idem | sim | 0 | — |
| 23 | `g_no_concurrency` | nenhuma outra sessão em transação | true | §3.4 · S1.3-R | sim | 0 | L3 |

- **Substituído:** `g_no_enabled_event_triggers` (T03 **false**). A verificação "gate antigo … substituído (não coexistem)" impede a coexistência dos dois.
- **Soma dos controles negativos: 45** = P7 34 (2+7+1+4+2+4+4+5+3+2) + EVT 11 (1+10).
- **Gates 1–7, 17, 18, 21–23:** são predicados de catálogo sem modelo offline; não têm controle negativo estático. A garantia deles vem da definição, da agregação em `gate_pass` e da leitura LIVE.
- **Resultado projetado da Tentativa 04** (E00 corrigido + allowlist ainda vazia): **STOP em `g_evt_all_adjudicated`**. É o comportamento esperado até D-9.

---

## 6. Preservação (conferida nesta rodada)

| Artefato | Blob (= HEAD) |
|---|---|
| `2830H_E00_precheck_inventory.sql` (vigente) | `97410c3a799d8fdec86cc6d3735993ab224f6c9e` |
| `2830H_E01_section1_structural.sql` | `c4118b8cc13872ecefa600d3c2225cca48f3c1b1` |
| `2830H_E02_identity_terminal_D1_D5.sql` | `3357ed46b77e3bfacbe5b1988820e495ce363dd1` |
| `2830H_E99_postcheck_residue.sql` | `49a71ecb4525697858110ee71a3f61f5eee74a34` |
| `tools/static_check.py` | `cabee40c0a459a976024dd3cbc61b946aeb110f0` |
| `LIVE-VALIDATION-PROTOCOL.md` (v1.4) | `51ebafe9428ae957796177963288c2c7bac2e4c1` |
| `LIVE-STAGE1-RUNBOOK.md` (v1.3) | `59a034d471ae9d13f25eb5e6c878a75367c7e203` |
| `2830_validate_edition_context_foundation.sql` | `b4647dcb59432405c8157e2733fd78678f35540e` |

LIVE: nenhum acesso nesta rodada. FREEZE: ativo. Etapa 1: STOP. Etapa 2: não autorizada.

---

## 7. Decisões pendentes

1. **Mandato de correção do harness:** aplicar o diff, com os achados G-1, G-2 e G-3 incorporados ou recusados explicitamente. Isso gera um blob novo do E00.
2. **Mandato da L4** (§2): só SELECT, fora da Etapa 1.
3. **Adjudicação individual D-9** a partir da L4. Até lá, nenhuma exceção.
4. **Tentativa 04:** só depois de 1–3, com novo mandato, desde S1.0.

---

## Apêndice A — `supp_model.py` (verificação suplementar do modelo; fora do diff)

md5 `b2259573ca3be3f841d4d6435c4f7137`. Uso: `python3 supp_model.py <harness da árvore com o diff aplicado>`. Resultado nesta rodada: `TOTAL 42 PASS 42 FAIL 0`.

```python
# Verificação suplementar (fora do diff proposto). Carrega o static_check.py PROPOSTO
# (árvore reconstruída = HEAD + diff) e exercita o modelo P7/EVT. Sem banco.
import io, contextlib, hashlib, sys, re
H=sys.argv[1]
ns={'__file__': H+'/tools/static_check.py'}
with contextlib.redirect_stdout(io.StringIO()):
    exec(open(H+'/tools/static_check.py',encoding='utf-8').read(), ns)
p7_gate=ns['p7_gate']; real=ns['real']; EXT=ns['EXT']; ALLOW=ns['ALLOW']; body_with=ns['body_with']; R=ns['R']
res=[]
def chk(n,c,d=''): res.append((n,bool(c),d))
# ---- 3. g_p7_no_ddl: cada forma da matriz × cada função não-C alcançada
FORMS=['CREATE TABLE public.x (a int);','create temp table x (a int);','CREATE OR REPLACE FUNCTION public.f() RETURNS int LANGUAGE sql AS 1;',
       'ALTER TABLE public.card_variant ADD COLUMN z int;','alter default privileges grant select on tables to anon;',
       'DROP TABLE public.x;','drop owned by anon;','GRANT SELECT ON public.card_variant TO anon;','REVOKE ALL ON public.card_variant FROM anon;',
       "COMMENT ON TABLE public.card_variant IS 'x';","SECURITY LABEL ON TABLE public.card_variant IS 'x';",'REINDEX TABLE public.card_variant;',
       'REFRESH MATERIALIZED VIEW public.mv;','IMPORT FOREIGN SCHEMA s FROM SERVER srv INTO public;','CREATE\n      INDEX ix ON public.x (a);']
nonc=[k for k,v in real.items() if v[3] not in ('c','internal')]
chk('funções não-C alcançadas no modelo = 10', len(nonc)==10, str(len(nonc)))
tot=ok_n=0
for fq in nonc:
    for form in FORMS:
        v=real[fq]; newsrc=body_with('    '+form) if v[3]=='plpgsql' else '\n    '+form+'\n'
        d=dict(real); t=list(d[fq]); t[7]=newsrc; d[fq]=tuple(t)
        key=(v[0],v[1],v[2]); saved=dict(ALLOW[key]); ALLOW[key]['md5']=hashlib.md5(newsrc.encode()).hexdigest()  # pino ajustado: isola o gate DDL
        ok,why=p7_gate(d,EXT); ALLOW[key]=saved
        tot+=1; ok_n+= (not ok) and any(w.startswith('g_p7_no_ddl:'+fq) for w in why)
chk(f'DDL da matriz bloqueado por g_p7_no_ddl em todas as funções (pino ajustado) {ok_n}/{tot}', ok_n==tot==150)
# SELECT INTO: sql ⇒ DDL; plpgsql ⇒ atribuição (não DDL)
nec='public.normalize_external_catalog_value'
src="\n    SELECT 1 INTO public.ghost;\n"; d=dict(real); t=list(d[nec]); t[7]=src; d[nec]=tuple(t)
k=('public','normalize_external_catalog_value','p_value text'); sv=dict(ALLOW[k]); ALLOW[k]['md5']=hashlib.md5(src.encode()).hexdigest()
ok,why=p7_gate(d,EXT); ALLOW[k]=sv
chk('função sql com SELECT INTO ⇒ g_p7_no_ddl', any(w.startswith('g_p7_no_ddl:') for w in why))
tg='internal.guard_edition_context_trait_active'; src=body_with('    SELECT 1 INTO NEW.a;')
d=dict(real); t=list(d[tg]); t[7]=src; d[tg]=tuple(t); k=('internal','guard_edition_context_trait_active',''); sv=dict(ALLOW[k]); ALLOW[k]['md5']=hashlib.md5(src.encode()).hexdigest()
ok,why=p7_gate(d,EXT); ALLOW[k]=sv
chk('plpgsql SELECT … INTO variável NÃO é DDL (sem falso positivo)', not any(w.startswith('g_p7_no_ddl:') for w in why), str(why))
# rotas de evasão ⇒ outro gate reprova
EV={"EXECUTE 'CREATE TABLE x (a int)';":'g_p7_no_external_or_dynamic',
    "NEW.a := $q$ x $q$; CREATE TABLE y (a int);":'g_p7_lexically_supported',
    'PERFORM internal.ghost_ddl();':'g_p7_no_unresolved',
    'CALL do_ddl();':'g_p7_no_unresolved',
    'PERFORM "Evil"();':'g_p7_lexically_supported'}
for stmt,gate in EV.items():
    src=body_with('    '+stmt); d=dict(real); t=list(d[tg]); t[7]=src; d[tg]=tuple(t)
    k=('internal','guard_edition_context_trait_active',''); sv=dict(ALLOW[k]); ALLOW[k]['md5']=hashlib.md5(src.encode()).hexdigest()
    ok,why=p7_gate(d,EXT); ALLOW[k]=sv
    chk(f'evasão [{stmt[:38]}] reprovada por {gate}', (not ok) and any(w.startswith(gate+':') for w in why), str(why[:2]))
# ---- 4. fail-closed das exceções (modelo com lógica de 3 valores do SQL)
DDL={'ddl_command_start','ddl_command_end','sql_drop','table_rewrite'}
KEYS=['name','event','tags','enabled','owner','fn','fn_language','fn_owner','fn_md5_lf']
def eq(a,b): return a is not None and b is not None and a==b          # SQL '='  (NULL ⇒ não casa)
def indf(a,b): return a==b                                              # IS NOT DISTINCT FROM
def gate3(live,allow):
    r=[]
    for e in live:
        if e['enabled']=='D': continue
        if e['event'] not in DDL: r.append('g_evt_ddl_only:'+e['name'])
        if not any(a['event'] in DDL and all((indf if k=='tags' else eq)(a[k],e[k]) for k in KEYS) for a in allow):
            r.append('g_evt_all_adjudicated:'+e['name'])
    return (not r, r)
T=[('issue_graphql_placeholder','sql_drop'),('pgrst_ddl_watch','ddl_command_end'),('pgrst_drop_watch','sql_drop'),
   ('issue_pg_cron_access','ddl_command_end'),('issue_pg_net_access','ddl_command_end'),('issue_pg_graphql_access','ddl_command_end')]
live=[dict(name=n,event=e,enabled='O',tags=None,owner='SYNTH',fn='SYNTH.'+n+'()',fn_language='plpgsql',fn_owner='SYNTH',fn_md5_lf='0'*32) for n,e in T]
allow=[dict(x) for x in live]
def neg(label,l,a,gate='g_evt_all_adjudicated'):
    ok,why=gate3(l,a); chk('EVT fail-closed: '+label,(not ok) and any(w.startswith(gate+':') for w in why),str(why[:2]))
def pos(label,l,a):
    ok,why=gate3(l,a); chk('EVT aceita: '+label, ok, str(why[:2]))
ok,why=gate3(live,[]); chk('lista inicialmente vazia ⇒ os 6 reprovados', (not ok) and len(why)==6)
pos('identidade completa idêntica (tags NULL nos dois lados)', live, allow)
for k in KEYS:
    l=[dict(x) for x in live]; l[0][k]=(['CREATE EXTENSION'] if k=='tags' else ('A' if k=='enabled' else ('login' if k=='event' else 'OUTRO')))
    neg(f'campo {k} alterado no LIVE', l, allow, 'g_evt_ddl_only' if k=='event' else 'g_evt_all_adjudicated')
# evttags NULL
l=[dict(x) for x in live]; l[1]['tags']=['CREATE EXTENSION']; neg('evttags: allowlist NULL × LIVE com tag', l, allow)
a=[dict(x) for x in allow]; a[1]['tags']=['CREATE EXTENSION']; neg('evttags: allowlist com tag × LIVE NULL', live, a)
l=[dict(x) for x in live]; a=[dict(x) for x in allow]; l[1]['tags']=['CREATE FUNCTION']; a[1]['tags']=['CREATE EXTENSION']; neg('evttags: tag diferente', l, a)
l=[dict(x) for x in live]; a=[dict(x) for x in allow]; l[1]['tags']=['B','A']; a[1]['tags']=['A','B']; neg('evttags: mesma lista em outra ordem (comparação estrita de array)', l, a)
l=[dict(x) for x in live]; a=[dict(x) for x in allow]; l[1]['tags']=['CREATE EXTENSION']; a[1]['tags']=['CREATE EXTENSION']; pos('evttags: tag idêntica', l, a)
# alteração de função / dono / habilitação
for k,v in [('fn','extensions.evil()'),('fn_md5_lf','f'*32),('fn_language','sql'),('fn_owner','postgres')]:
    l=[dict(x) for x in live]; l[2][k]=v; neg(f'função: {k} alterado', l, allow)
l=[dict(x) for x in live]; l[2]['owner']='postgres'; neg('dono do event trigger alterado', l, allow)
for st in ['A','R']:
    l=[dict(x) for x in live]; l[3]['enabled']=st; neg(f'habilitação O→{st}', l, allow)
l=[dict(x) for x in live]; l[3]['enabled']='D'; pos('habilitação O→D (desabilitado não dispara; fica no inventário)', l, allow)
nt=dict(live[0],name='new_hook',enabled='O'); neg('trigger adicional', live+[nt], allow)
neg('trigger adicional desabilitado e depois habilitado (D→O)', live+[dict(nt)], allow+[dict(nt,enabled='D')])
neg('trigger renomeado (nome é identidade)', [dict(x) for x in live[:-1]]+[dict(live[-1],name='issue_pg_graphql_access_v2')], allow)
lg=dict(live[0],name='on_login',event='login'); neg('evento login, mesmo com linha na allowlist', live+[lg], allow+[dict(lg)], 'g_evt_ddl_only')
for k in ['owner','fn','fn_md5_lf']:
    a=[dict(x) for x in allow]; l=[dict(x) for x in live]; a[4][k]=None; l[4][k]=None
    neg(f'NULL em {k} dos dois lados não casa (= do SQL)', l, a)
ok,_=ns['evt_gate'](live,allow); chk('modelo do diff (evt_gate) concorda no caso exato', ok)
a=[dict(x) for x in allow]; l=[dict(x) for x in live]; a[4]['owner']=None; l[4]['owner']=None
okm,_=ns['evt_gate'](l,a); chk('DIVERGÊNCIA DE MODELO: evt_gate do diff aceita NULL=NULL em owner (o SQL não aceita) — registrar', okm)
bad=[r for r in res if not r[1]]
for n,ok,d in res: print(('PASS ' if ok else 'FAIL ')+n+((' '+d) if d and not ok else ''))
print(f'TOTAL {len(res)} PASS {len(res)-len(bad)} FAIL {len(bad)}')
```

## Apêndice B — `env_mut.py` (mutação dos envelopes; fora do diff)

md5 `9c3d523a5881615bf351696aa9633a46`. Uso: `python3 env_mut.py <raiz da árvore> <rótulo>`. Resultados nesta rodada: HEAD `32 de 42`; proposto `42 de 42`.

```python
import sys,shutil,subprocess,os,re
root=sys.argv[1]; label=sys.argv[2]
H=root+'/database/proposals/2026-09-18-edition-context-axis/harness'
FORMS={'CREATE':"CREATE TABLE public.h2830_x (a int);",'ALTER':"ALTER TABLE public.card_variant ADD COLUMN z int;",
 'DROP':"DROP TABLE public.h2830_x;",'GRANT':"GRANT SELECT ON public.card_variant TO anon;",'REVOKE':"REVOKE ALL ON public.card_variant FROM anon;",
 'COMMENT':"COMMENT ON TABLE public.card_variant IS 'x';",'SECURITY LABEL':"SECURITY LABEL ON TABLE public.card_variant IS 'x';",
 'REINDEX':"REINDEX TABLE public.card_variant;",'REFRESH MV':"REFRESH MATERIALIZED VIEW public.mv;",
 'IMPORT FOREIGN SCHEMA':"IMPORT FOREIGN SCHEMA s FROM SERVER srv INTO public;",'SELECT INTO':"SELECT 1 AS a INTO public.h2830_y;"}
base=open(H+'/tools/static_check.py').read()
def run(tree):
    p=subprocess.run(['python3',tree+'/database/proposals/2026-09-18-edition-context-axis/harness/tools/static_check.py'],capture_output=True,text=True)
    fails=[l for l in p.stdout.splitlines() if l.startswith('FAIL')]
    return p.returncode, fails, p.stderr.strip().splitlines()[-1:] if p.stderr else []
rows=[]
for env,kind in [('2830H_E00_precheck_inventory.sql','sql'),('2830H_E99_postcheck_residue.sql','sql'),
                 ('2830H_E01_section1_structural.sql','do'),('2830H_E02_identity_terminal_D1_D5.sql','do')]:
    for name,stmt in FORMS.items():
        if kind=='do' and name=='SELECT INTO': continue   # em PL/pgSQL é atribuição, não DDL
        t='/tmp/mut_tree'; shutil.rmtree(t,ignore_errors=True); shutil.copytree(root,t)
        f=t+'/database/proposals/2026-09-18-edition-context-axis/harness/'+env
        s=open(f,encoding='utf-8').read()
        if kind=='sql': s=s.rstrip('\n')+'\n'+stmt+'\n'
        else:
            i=s.index('BEGIN', s.index('$h2830_e0')); s=s[:i+5]+'\n    '+stmt+s[i+5:]
        open(f,'w',encoding='utf-8').write(s)
        rc,fails,err=run(t)
        rows.append((env,name,len(fails),bool(err)))
det=sum(1 for r in rows if r[2]>0 or r[3]); print(label,'detectadas',det,'de',len(rows))
for r in rows:
    if not (r[2]>0 or r[3]): print('  NÃO DETECTADA:',r[0],r[1])
```

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-26, `BATCH12-2830-STOP-ADJUDICATION-EVIDENCE-GATE-01`, sem SQL).** Fechamento das evidências da adjudicação:<br>• hashes dos artefatos entregues;<br>• L4 com md5 e critérios de interpretação, só para autorização futura;<br>• cobertura de `g_p7_no_ddl` (matriz PG17, estrutura do fecho, 150/150) e proteção dos envelopes (mutação: 32/42 vigente, 42/42 proposto);<br>• fail-closed das exceções (42/42);<br>• rastreabilidade dos 23 gates;<br>• achados G-1, G-2 e G-3.<br>Diff não aplicado; E00 vigente, 2830, LIVE e FREEZE preservados. |
| 1.1 | **Nota de supersessão (2026-09-26, `…-CORRECTION-01`).** Linha de cabeçalho indicando o que foi superado e onde está o estado vigente. Conteúdo original preservado como registro. |
