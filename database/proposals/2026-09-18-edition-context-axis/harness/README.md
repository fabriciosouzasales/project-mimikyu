# 2830H — Harness executável da fundação Edition Context

| Campo | Valor |
|---|---|
| **Contrato** | `../2830_validate_edition_context_foundation.sql` — **v7.0**, blob `b4647dcb59432405c8157e2733fd78678f35540e`, publicado em `cab1495b`. Autoridade **imutável**: este diretório a implementa, nunca a altera. |
| **Status** | **FUNDAÇÃO IMPLEMENTADA LOCALMENTE — NÃO EXECUTADA** (`BATCH12-2830-HARNESS-FOUNDATION-01`, corrigida em `BATCH12-2830-HARNESS-FOUNDATION-CORRECTION-01` e `-CORRECTION-02`, 2026-09-26). Nenhum envelope foi rodado em nenhum banco. |
| **Cobertura desta rodada** | **17 / 135** automáticos: Seção 1 (1.1–1.12) e D1–D5. |
| **FREEZE** | ATIVO. Nada aqui autoriza importação, revisão ou UNFREEZE. |

## Arquivos

| Arquivo | Papel | Escreve? |
|---|---|---|
| `2830H_E00_precheck_inventory.sql` | Precheck JIT (P11): gate de igualdade com o **baseline canônico do FREEZE**; captura do **baseline da rodada** (`d_baseline` + `d_baseline_md5`) para o E99; inventários de sequences (P6), triggers e efeitos externos **com análise léxica das chamadas (qualificadas e não qualificadas), DML qualificado e não qualificado, identidade fixada da allowlist e `search_path` seguro** (P7), regras, event triggers, publicações, RLS/dono, sessão (P8), concorrência. Um SELECT, **24 gates**, `gate_pass`. **Versão corrigida localmente** (`BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01`, blob `88e9e7a4…`, não commitada, **não compilada nem executada**):<br>• pino P7 com EOL normalizado (D-6);<br>• `g_p7_no_ddl`;<br>• event triggers com inventário completo contra o catálogo (`g_evt_inventory_complete`);<br>• exceção só por identidade de 12 atributos e justificativa não vazia;<br>• `evt_allowlist` vazia. | não |
| `2830H_E01_section1_structural.sql` | Envelope E01 — casos 1.1–1.12. | **sim** (fixtures desfeitas) |
| `2830H_E02_identity_terminal_D1_D5.sql` | Envelope E02 — casos D1–D5. | não (catálogo) |
| `2830H_E99_postcheck_residue.sql` | Postcheck: **comparação integral, chave a chave, com o `d_baseline` do E00 da mesma rodada** (md5 = fidelidade da cópia, não origem da rodada; vinculação E00 → envelope → E99 é documental), recheck do canônico do FREEZE, resíduo zero, não persistência de sessão (P10/P8). Um SELECT. | não |
| `tools/static_check.py` | Verificação estática local (não conecta a banco). **420/420** na árvore corrigida. | — |
| `LIVE-STAGE1-EXECUTION-RECORD.md` | Registro das tentativas da Etapa 1. **Nenhum PASS formal.** Ocorrência 01: governança — L1 e tentativa de L3 executadas pelo ChatGPT, fora da atribuição de auditor; a L1 não é evidência; a L3 foi bloqueada pela ferramenta, sem resultado SQL. Tentativa 02 (Claude): STOP em PC-1 por árvore suja, nenhum SQL. Tentativa 03 (Claude, `…-EXECUTION-02`): L1 e L3 conformes; **STOP em S1.3 (E00)** por `g_p7_identity_pinned` (L2: TRANSPORT/EOL-ONLY em `normalize_external_catalog_value`, para D-6) e `g_no_enabled_event_triggers` (6 event triggers habilitados no LIVE); S1.5 não executado. Adjudicação do STOP (sem SQL): D-6 e D-9 pendentes. Alternativas de canal, retomada e saídas integrais. | — |
| `LIVE-STAGE1-STOP-ADJUDICATION.md` | Adjudicação documental do STOP da Tentativa 03 (sem SQL). **Correções aplicadas localmente** em `…-CORRECTION-01`; ver o estado vigente no Revision History do próprio arquivo. Contém:<br>• evidências integrais;<br>• prova de que `normalize_external_catalog_value` diverge só por CRLF;<br>• origem, eventos e possibilidade de disparo dos 6 event triggers;<br>• tratamento restritivo proposto (D-9/AD-10), implicações, riscos e decisões.<br>**Proposta — não aplicada.** | — |
| `LIVE-STAGE1-STOP-ADJUDICATION-EVIDENCE.md` | Fechamento das evidências da adjudicação (sem SQL). Contém:<br>• hashes dos artefatos;<br>• L4 com md5 e critérios de interpretação, **só para autorização futura**;<br>• cobertura de `g_p7_no_ddl` e proteção dos envelopes;<br>• fail-closed das exceções de event trigger;<br>• rastreabilidade dos 23 gates;<br>• achados G-1 a G-3 (**resolvidos** em `…-CORRECTION-01`, com G-4 e G-5). | — |
| `LIVE-STAGE1-STOP-ADJUDICATION.diff` | Diff **integral da correção aplicada localmente** (E00, `tools/static_check.py`, protocolo v1.5, roteiro v1.4) contra o HEAD `b8925ed5`. Substitui a proposta anterior (md5 `a25d3142…`). Não commitado; pendente de auditoria. | — |
| `LIVE-STAGE1-RUNBOOK.md` | Roteiro operacional da Etapa 1 (só SELECT), **v1.4 corrigida localmente**: passos, consultas exatas com md5 (L1, L3, L2 e L4 revisada), E00 vigente na PC-2, evidências esperadas, STOP e pontos de decisão. Não autoriza execução. | — |
| `LIVE-VALIDATION-PROTOCOL.md` | Protocolo de validação progressiva no LIVE, **v1.5 corrigida localmente** (ambiente isolado pago recusado; alternativa sem custo pendente em D-1): Etapa 1 só SELECT, Etapa 2 E02+E99, Etapa 3 E01 (mandato futuro), riscos, adaptações AD-1–AD-10 e decisões D-1–D-9. | — |

Ordem de uso, **quando autorizada**: `E00` → envelope → `E99`, um envelope por vez, cada um em statement próprio.

## Protocolo implementado (P1–P13 da 2830 v7.0)

- **P1** teste transacional com rollback integral — E01 **escreve** fixtures e as desfaz; não é SQL read-only.
- **P2** um `DO` por envelope; sem `COMMIT`, `TEMP`, `set_config`, `SET ROLE`, `SET LOCAL`, `EXECUTE`, `PERFORM`; término **sempre** por exceção:
  `H283P` = `H2830_ROLLBACK_PASS` · `H283F` = `H2830_FAIL`. Retorno `[]` do MCP = defeito (o envelope nunca termina "com sucesso").
- **P3** cada caso em subtransação que termina com o sinal `H283C` (desfaz as fixtures **do caso**; só então o caso conta). Negativos conferem `RETURNED_SQLSTATE` + `CONSTRAINT_NAME` + `TABLE_NAME`; positivos conferem efeito (`RETURNING`, contagem). Nenhum `NOTICE` existe nos envelopes. Erro inesperado vira `H2830_FAIL` com o id do caso. Gate final exige a lista de casos concluídos **idêntica e na mesma ordem** da lista esperada.
- **P4** não se aplica a E01/E02 (nenhum caso depende de trigger DEFERRED); os eventos deferidos enfileirados pela contraprova 1.9 são descartados pelo rollback da subtransação.
- **P5** marcador único por execução `H2830_<uuid>` em todo `code`/`normalized_token` de fixture; entidades reais só por código único (`game.code = 'POKEMON'`, `asset_source.code = 'TCGDEX'`, preflight exatamente-um).
- **P6/P7/P10/P11** em E00/E99 — ver as seções "Dois baselines" e "P7" abaixo.
- **P8** `SET LOCAL lock_timeout` — **decisão pendente**, não emitido (linha pronta, comentada, no cabeçalho de E01).
- **P13** não aplicável aos 17 casos: todos são asserções de catálogo com cardinalidade exata ou fixtures próprias — nenhum universo de dado LIVE.

## Matriz caso → asserção → evidência

| Caso | Tipo | Asserção implementada | Evidência produzida |
|---|---|---|---|
| 1.1 | RO | 5 tabelas EC em `public`, `relkind = 'r'` | contagem = 5 |
| 1.2 | RO | `pg_constraint(trait)` = 11; as 9 nomeadas presentes; PK = 1, FK = 1 | três contagens exatas |
| 1.3 | FX | `DECK_PLAYER` sem prefixo ⇒ `23514` / `ck_cect_code_family_prefix` / `card_edition_context_trait`; contraprova com `DECK_PLAYER_` aceita | SQLSTATE + constraint + tabela; `RETURNING id` |
| 1.4 | RO+FX | `uq_cect_game_family_order` = (`game_id`,`family`,`display_order`); mesma ordem em EVENT e CHANNEL coexiste (2 linhas); repetida em EVENT ⇒ `23505` / `uq_cect_game_family_order` | colunas; contagem = 2; SQLSTATE + constraint + tabela |
| 1.5 | RO | `uq_cecp_game_signature` único/válido/pronto, na tabela profile, predicado `(traits_signature IS NOT NULL)`, colunas (`game_id`,`traits_signature`) | predicado e colunas literais |
| 1.6 | FX | `traits_signature = '{}'` ⇒ `23514` / `ck_cecp_signature_not_empty` | SQLSTATE + constraint + tabela |
| 1.7 | FX | array 2×1 ⇒ `23514` / `ck_cecp_signature_shape` | SQLSTATE + constraint + tabela |
| 1.8 | RO | exatamente 2 FKs compostas: `fk_cecpt_profile` (`profile_id`,`game_id`)→profile(`id`,`game_id`) e `fk_cecpt_trait` (`trait_id`,`game_id`)→trait(`id`,`game_id`) | contagem = 2 com colunas ordenadas |
| 1.9 | FX | `raw_field` `type` e `size` ⇒ `23514` / `ck_cecem_raw_field` (cada um); contraprova `stamp` aceita | 2× SQLSTATE + constraint + tabela; `RETURNING id` |
| 1.10 | FX+RO | `foil` ⇒ `23514` / `ck_cecem_raw_field`; `ck_cecem_foil_allowlist` inexistente em qualquer schema | SQLSTATE + constraint + tabela; contagem = 0 |
| 1.11 | RO | `uq_cecem_active_global` pred `((external_set_id IS NULL) AND is_active)` + 4 colunas; `uq_cecem_active_scoped` pred `((external_set_id IS NOT NULL) AND is_active)` + 5 colunas; `ix_cecem_token` não único, sem predicado, 4 colunas; nomes antigos `uq_cecem_global/scoped` ausentes | predicados e colunas literais; contagens |
| 1.12 | RO | 5 tabelas × **8** privilégios de tabela do PostgreSQL 17 (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, **MAINTAIN**) × 2 papéis = **80 verificações**: `anon` nenhum; `authenticated` só SELECT; as 5 tabelas de fato avaliadas. E00 exige os dois papéis existentes e `server_version_num ≥ 170000` | violações = 0 (lista nominal se ≠ 0); 5 avaliadas |
| D1 | RO | `uq_card_variant_card_type_no_printing` ausente em `pg_class` e `pg_constraint` | 0 / 0 |
| D2 | RO | `uq_card_variant_card_type_printing` ausente | 0 / 0 |
| D3 | RO | `uq_cvir_job_card_type_no_printing` e `_printing` ausentes | 0 / 0 |
| D4 | RO | únicos de `card_variant` com `variant_type_id` = {`uq_card_variant_identity`}; únicos de staging com `job_id` (coluna ou expressão) = {`uq_cvir_row_identity`}; ambos válidos/prontos/vivos | conjuntos exatos + saúde |
| D5 | RO | `uq_card_variant_card_order`, `uq_card_variant_one_default_per_card`, `uq_card_variant_id_card` existem 1× cada, únicos, válidos, em `card_variant` | 3 / 3 |

## Dois baselines — não confundir

| | Baseline **canônico do FREEZE** | Baseline **da rodada** |
|---|---|---|
| O que é | Constantes fixas no bloco `FREEZE-CANON` (fonte registrada por chave) | `d_baseline`, capturado pelo E00 imediatamente antes do envelope |
| Quem compara | E00 (`g_freeze_canonical_equal`) e de novo o E99 | E99 (`g_baseline_equal`), chave a chave |
| Pergunta respondida | "O estado de partida é o estado congelado aprovado?" | "O envelope deixou alguma coisa diferente do que encontrou?" |
| Divergência | STOP — FREEZE violado ou deriva; nunca se ajusta a constante | STOP — resíduo ou escrita concorrente |
| Chaves | 17 com valor canônico registrado | as 17 + `mapping_trait`, `action_log`, `marker_*` |

O bloco `BASELINE-BUILDER` e o bloco `FREEZE-CANON` existem em E00 **e** E99 e são verificados como **idênticos byte a byte**. Timestamps saem em UTC com formato fixo, independentes do `TimeZone` da sessão.

**Procedimento do E99:** o operador substitui três marcadores com valores copiados da saída do **E00 da mesma rodada** — `__E00_D_BASELINE__` (JSON integral de `d_baseline`), `__E00_D_BASELINE_MD5__` (`d_baseline_md5`) e `__E00_ROLE_SETTING_ROWS__` (`d_session.db_role_setting_rows`). O E99 prova: marcadores substituídos; md5 da cópia = md5 declarado pelo E00 (cópia fiel); mesmo conjunto de chaves; todas as chaves iguais (diferenças listadas em `d_diff`); canônico ainda igual; marcador `H2830` ausente; nenhuma transação aberta de outra sessão; `lock_timeout = '0'`; `pg_db_role_setting` sem linha nova. Marcador não substituído ou JSON truncado ⇒ gate falso, nunca PASS.

**O que o md5 prova — e o que não prova.** O md5 prova apenas **fidelidade da cópia**: o JSON colado é byte a byte o que algum E00 declarou. **Não** prova de qual rodada ele veio — um par (`d_baseline`, `d_baseline_md5`) copiado inteiro de outra rodada passa no teste de md5. A proteção contra isso é a comparação chave a chave com o estado atual (qualquer deriva real diverge) somada à vinculação documental abaixo.

## Registro da rodada — vinculação documental E00 → envelope → E99

A amarração entre E00, envelope e E99 **não é criptográfica**; é documental e obrigatória. O registro de cada rodada contém, nesta ordem:

1. a saída integral do E00 (`checked_at`, `backend_pid`, `d_baseline`, `d_baseline_md5`, `gate_pass`);
2. a mensagem terminal integral do envelope (marcador `H2830_<uuid>`, `elapsed_ms`, SQLSTATE);
3. o texto exato do E99 com os três marcadores substituídos e a sua saída integral.

Regras: `checked_at(E00) < submissão do envelope < checked_at(E99)`; nenhum outro envelope entre o E00 e o E99; **um E00 novo para cada envelope** (um E00 nunca é reutilizado). Registro incompleto, fora de ordem ou com E00 reutilizado ⇒ a rodada não é evidência de PASS.

## P7 — triggers e efeitos externos (v3)

- **Raízes:** todo trigger não interno + toda função referenciada por CHECK, DEFAULT ou expressão de índice (`pg_depend`) das tabelas do escopo.
- **Pré-processamento léxico:** comentários (`--`, `/* */`) e literais `'...'` são removidos antes de qualquer análise; `FOR [NO KEY] UPDATE` e `ON CONFLICT DO UPDATE` são neutralizados (não são DML de alvo). Lexemas que o analisador não modela com segurança ⇒ **STOP** (`g_p7_lexically_supported`): E-string (`E'...'`), dollar-quote interno, identificador entre aspas duplas, nome em três partes.
- **Chamadas qualificadas** `schema.funcao(`: resolvidas em `pg_proc` e seguidas por fecho transitivo até profundidade 8 (não fechar ⇒ `g_p7_closure_complete` falso). Não resolvida ⇒ **STOP**.
- **Chamadas não qualificadas** `funcao(`: só passam se forem palavra-chave da linguagem, função de `pg_catalog` fora da lista negra, ou nome de tipo de `pg_catalog` (cast funcional). Qualquer outra ⇒ `UNRESOLVED`; `pg_catalog` na lista negra ⇒ `DENIED`. Ambos ⇒ **STOP** (`g_p7_no_unresolved`). Uma função não qualificada nunca é resolvida por `search_path`.
- **DML:** alvo qualificado (`INSERT INTO`, `UPDATE`, `DELETE FROM`, `MERGE INTO`, `TRUNCATE`, com ou sem `ONLY`) precisa existir **e** estar no escopo (`g_p7_writes_in_scope`). Alvo **não qualificado** ⇒ sempre **STOP** (`g_p7_no_unqualified_dml`) — sem tentativa de resolução.
- **Allowlist por identidade, não por nome** (`g_p7_identity_pinned`): cada uma das 12 entradas fixa `identity_args`, linguagem, `prosecdef`, volatilidade, `proconfig` exato e o md5 do corpo com **CRLF→LF** (D-6, opção A: normalização nos dois lados; o md5 bruto, `cr_count` e `crlf_count` são exportados e listados em `d_p7_eol_normalized`; CR isolado continua STOP). Funções C: símbolo + pertença à extensão. Qualquer divergência ⇒ `ALLOWLIST_MISMATCH` ⇒ **STOP**. Mesmo nome com outra assinatura ⇒ não classificada (`g_p7_all_classified`).
- **`search_path` seguro** (`g_p7_search_path_safe`): toda função não-C alcançada tem exatamente uma entrada `search_path` em `proconfig`, igual a `search_path=""`. Ausente, duplicada, com `public`, `pg_temp` ou qualquer outro valor ⇒ **STOP**.
- **Também STOP:**
  - sinal de efeito externo (`net.`, `http`, `pg_notify`, `dblink`, `pg_net`, `COPY`, `lo_*`, `pg_read_*`, `pg_ls_dir`, `set_config`, `pg_sleep`, terminate/cancel) ou `EXECUTE` dinâmico (`g_p7_no_external_or_dynamic`);
  - comando DDL no corpo (`g_p7_no_ddl`: toda a matriz de disparo de event triggers do PG 17; `INTO` em função `sql`);
  - regra `pg_rewrite` não-SELECT.
- **Event triggers (P7-EVT):**
  - inventário integral; `g_evt_inventory_complete` compara com `count(pg_event_trigger)` lido direto do catálogo;
  - evento não-DDL (`login`) ⇒ STOP sempre (`g_evt_ddl_only`);
  - evento DDL só com exceção por identidade de 12 atributos e justificativa não vazia (`g_evt_all_adjudicated`). `=` nos atributos obrigatórios; `IS NOT DISTINCT FROM` em tags, `proconfig` e extensão;
  - `evt_allowlist` **vazia**; os 6 triggers da Tentativa 03 **não** foram inseridos.
- **Escopo do gate nesta rodada:** as 5 tabelas EC. `card_variant`, staging, job, game e action log são inventariados (`d_p7_*`) para os próximos envelopes, sem bloquear E01/E02.
- A análise é **conservadora**: qualquer coisa não resolvida ou não modelada gera STOP para classificação humana — nunca PASS.

## Provas estáticas (`python3 tools/static_check.py`)

**420 / 420 PASS** na árvore corrigida (`…-CORRECTION-01`; eram 205 antes da adjudicação). Os itens abaixo continuam valendo; os acrescentados na correção estão no fim da lista. Incluindo:
- um `DO` por envelope, nada executável fora dele, dollar-quote íntegro;
- ausência de `COMMIT`, `ROLLBACK`, `CREATE`, `ALTER`, `DROP`, `TEMP`, `set_config`, `SET ROLE/LOCAL/SESSION`, `GRANT`, `REVOKE`, `TRUNCATE`, `DELETE`, `UPDATE`, `EXECUTE`, `PERFORM`, `RAISE NOTICE/WARNING/INFO`;
- casos na ordem e iguais a `c_expected`; `ERRCODE` só `H283C/F/P`; `H283P` exatamente 1 e último;
- estrutura de subtransação em cada um dos 17 casos; todo negativo com SQLSTATE + constraint;
- `BEGIN/END`, `IF/END IF` e parênteses balanceados; todo `INSERT` com marcador;
- 1.12: duas matrizes, cada uma exatamente com os 8 privilégios do PG 17 (inclui `MAINTAIN`), para `anon` e `authenticated`;
- `BASELINE-BUILDER` e `FREEZE-CANON` idênticos E00 × E99; canon JSON válido, 17 chaves exatas, somas internas coerentes (`staging_status` = 26.127; `jobs_by_status` = 145), sem chaves sem valor canônico; todas as chaves canônicas produzidas pelo builder;
- E00: **24** gates obrigatórios definidos e **exatamente** esses 24 no CTE `gates`, cada um com os termos efetivos do seu predicado e sem esvaziamento; `gate_pass` agregando todos com NULL = falha; exporta `d_baseline` + `d_baseline_md5`; P7 recursivo com 4 tipos de raiz;
- **modelo executável do P7** (`tools/static_check.py`): extrai do próprio E00 os 10 padrões, as palavras-chave, a lista negra e a allowlist e aplica o gate a corpos simulados. **2 controles positivos** (as definições reais de 2095/2206/2207 passam; comentário, literal e `FOR UPDATE` não geram dependência) e **27 controles negativos**, cada um exigindo que o gate específico esperado reprove: chamada não qualificada desconhecida; builtin negado não qualificado; DML não qualificado (`UPDATE`, `INSERT INTO`, `DELETE FROM ONLY`); DML qualificado fora do escopo e para relação inexistente; chamada qualificada não resolvida; allowlist com corpo, assinatura, `SECURITY DEFINER`, linguagem ou símbolo C divergentes; função C fora da extensão; `search_path` ausente, com `public`, duplicado ou com `pg_temp`; função não classificada; `EXECUTE`; E-string; dollar-quote interno; identificador entre aspas; nome em três partes; `x . f(`; chamada aninhada `f(g(x))`; `net.http_post`;
- E99: comentário declara três marcadores; md5 declarado como fidelidade da cópia e não origem; vinculação documental explícita;
- E99: 3 marcadores exatamente 1× cada, 9 gates definidos, `gate_pass` agregado, diff sobre a união das chaves;
- E00/E99: um statement, sem DML/DDL/`SET`/`DO`, sem comando da matriz de disparo de event triggers (inclui `INTO`, `COMMENT`, `GRANT`/`REVOKE`, `SECURITY LABEL`);
- **CORRECTION-01**, acrescentados na correção:
  - D-6: pinos = md5 LF do repositório; reprodução byte a byte do md5 bruto LIVE; controles de CR isolado, CRLF + conteúdo e CRLF + `SECURITY DEFINER`;
  - `g_p7_no_ddl`: 12 padrões extraídos; corpos reais sem DDL; 4 controles negativos;
  - EVT: allowlist vazia com 13 colunas tipadas; validador de linhas futuras (justificativa obrigatória; 8 controles negativos); casamento `=` / `IS NOT DISTINCT FROM` coluna a coluna; modelo com lógica de três valores; 30 controles negativos, incluindo os 3 atributos novos isolados, `NULL`, justificativa e inventário incompleto;
  - roteiro: PC-2, §0 e §3.3 com o E00 vigente e sem hash antigo; protocolo v1.5 citado; md5 dos 4 blocos SQL conferidos; L4 só leitura, com contagem direta e `LEFT JOIN`.
  - Total: **72 controles negativos** (34 P7 + 30 EVT + 8 validador).

**Controles negativos do verificador (mutação dos próprios arquivos, CORRECTION-02) — 23 mutações, 22 detectadas diretamente:** `COMMIT` injetado; `RAISE NOTICE`; sinal `H283C` removido; conferência de constraint removida; `set_config`; caso removido do esperado; `MAINTAIN` removido; builder alterado só no E99; canon alterado só no E99; `g_freeze_canonical_equal`, `g_p7_all_classified`, `g_p7_identity_pinned`, `g_p7_no_unqualified_dml`, `g_p7_search_path_safe`, `g_p7_lexically_supported` removidos; padrão de DML não qualificado sem `UPDATE`; pino md5 da allowlist trocado; `gate_pass` sem checagem de NULL; marcador MD5 removido do E99; `g_baseline_equal` removido; comentário do E99 voltando a “dois marcadores”; `d_baseline_md5` não exportado. A única não detectada isoladamente — retirar `pg_notify` do padrão de sinal externo — é camada redundante: o caso continua bloqueado pela lista negra de builtins; retirar **as duas** camadas é detectado.

**Mutação na CORRECTION-01** (scripts e resultados em `LIVE-STAGE1-STOP-ADJUDICATION.md`, Apêndice C):
- E00: 20/20 mutações detectadas, cada uma enfraquecendo um controle;
- 24/24 esvaziamentos de predicado de gate detectados;
- roteiro: 5/5;
- envelopes com comandos da matriz de disparo injetados: 42/42.

**Limite declarado:** não há parser PL/pgSQL neste ambiente. A compilação real só é provada executando — o que exige mandato. A primeira execução autorizada prevista é a Etapa 1 do protocolo LIVE (só SELECT); um ambiente isolado sem custo só entra se adotado em D-1, com P14 obrigatório.

## Dependências e decisões pendentes

1. **Mandato de execução**, por etapa, conforme `LIVE-VALIDATION-PROTOCOL.md`: Etapa 1 (E00 só leitura) → Etapa 2 (E00 → E02 → E99) → Etapa 3 (E00 → E01 → E99). Nenhum envelope foi executado.
2. **`SET LOCAL lock_timeout = '5s'`** — decisão operacional pendente (P8).
3. **Ambiente isolado** (P14) — **pago: recusado** (decisão do proprietário, 2026-09-26); **alternativa sem custo: PENDENTE** em D-1, com P14 (a, b, c) obrigatório. Não afeta E00/E01/E02/E99; torna K1/K2/K8b e o UNFREEZE da 2830 v7.0 inalcançáveis enquanto a decisão D-1 estiver **PENDENTE** (Batch 12 **ABERTO**, UNFREEZE **BLOQUEADO**, K2 **não dispensado**), e P9b só é cumprido por adaptação (AD-2) — ver `LIVE-VALIDATION-PROTOCOL.md`.
4. **Premissas a confirmar pelo E00 antes de E01:** estado = baseline canônico do FREEZE; papel executor superusuário ou dono das tabelas EC, sem `FORCE ROW LEVEL SECURITY`; nenhuma sequence nas tabelas tocadas; fecho P7 inteiramente classificado, sem efeito externo, sem SQL dinâmico, sem escrita fora do escopo; nenhuma regra nem event trigger habilitado; papéis `anon`/`authenticated` existentes; PG ≥ 17; marcador ausente; zero concorrência.
5. **Tempo (P9):** E01/E02 são leves (catálogo + 11 tentativas de INSERT no E01: 4 positivas e 7 negativas); medição formal P9b ainda assim é pré-requisito do critério A2 do contrato.

## Riscos

- Ordem de avaliação de CHECK × UNIQUE: os negativos de CHECK usam `display_order` fora da faixa existente para que uma colisão única não mascare o CHECK; se o PostgreSQL avaliar em outra ordem, o caso **falha** (nunca passa) e é investigado.
- Predicados literais (1.5, 1.11) dependem da forma canônica de `pg_get_expr` medida no LIVE em 2026-09-26; mudança de versão do PostgreSQL pode alterar a renderização ⇒ FAIL, não PASS.
- **Pinos md5 da allowlist derivados do repositório** (2095/2206/2207), não medidos no LIVE nesta rodada (SQL proibido). Se o `prosrc` LIVE diferir byte a byte (ex.: espaços finais, normalização de fim de linha), o E00 reporta `ALLOWLIST_MISMATCH` ⇒ STOP para adjudicação — nunca PASS. Os pinos não são ajustados sem mandato.
- O modelo do P7 em Python usa o motor `re` e uma lista simulada de `pg_catalog`; ele prova a lógica do gate, não a equivalência exata com o motor de regex do PostgreSQL (ARE). Divergência de motor tende a gerar STOP, não PASS, porque toda ocorrência não resolvida bloqueia.
- 1.12 usa `has_table_privilege` para os papéis `anon`/`authenticated`; se algum deles não existir, a função erra ⇒ `H2830_FAIL` com o erro.
