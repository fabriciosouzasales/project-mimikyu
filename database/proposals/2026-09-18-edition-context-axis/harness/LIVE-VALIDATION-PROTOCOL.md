# 2830H — Protocolo de validação progressiva no LIVE

| Campo | Valor |
|---|---|
| **Mandato** | `BATCH12-2830-LIVE-VALIDATION-READINESS-01` (2026-09-26) |
| **Status** | **v1.12 vigente** (2026-10-04, `BATCH12-FORMAL-UNFREEZE-CLOSEOUT-01`): só estado — Fabrício autorizou formalmente o UNFREEZE (`UNFREEZE-AUTHORIZATION-RECORD.md`); **E4 SATISFIED · Batch 12 / `2830` CLOSED · FREEZE ENCERRADO · UNFREEZE COMPLETED** · canary não executado · **NEXT = canary real pós-UNFREEZE**; queries L1/L2/L3 e critérios operacionais inalterados. *Anterior:* **v1.11** (2026-10-04, `BATCH12-E3-INDEPENDENT-CLOSEOUT-01`): só estado — E3 CLOSED e próximo = decisão formal de UNFREEZE por Fabrício (E4 é o rótulo contratual dessa autorização, não etapa); queries L1/L2/L3 e critérios operacionais inalterados. *Anterior:* **v1.10** (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`): só reconciliação de estado; queries L1/L2/L3 e critérios operacionais inalterados. **Estado corrente (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`):** CN-1 executado e descartado (2026-10-02/03; evidência `evidence/CN1-2026-10-02/`); **P14(a) CLOSED** (nova captura LIVE com o mesmo instrumento pinado, `PASS_EXACT` 31/31 contra o CN1 — `LIVE-P14A-EXECUTION-RECORD.md`) · P14(b1)/(b2)/(c)/(d) CLOSED · **P14(e) CLOSED**; K1/K2/K8b executados no CN-1 e **D1/D2/D3 CLOSED / CONTRACTUALLY ACCEPTED**; **D4 CLOSED**; P9(a), A2′ e Fase 6 CLOSED (2026-10-03); **E2 CLOSED**; **E1 CLOSED** (A/B/C/D CLOSED e registrados em EXECUTION-BATCHES, HANDOFF e log); **E3 CLOSED** (E3 JIT 2026-10-04: L1, L3 inicial, E00 e L3 final PASS; S3 por adjudicação — `LIVE-E3-JIT-EXECUTION-RECORD.md`); **próximo = decisão formal de UNFREEZE por Fabrício** — E4 é o rótulo contratual dessa autorização, não etapa operacional. Batch 12 **ABERTO**; FREEZE ATIVO; UNFREEZE **não autorizado**. *Anterior:* **v1.9** (2026-10-03, `BATCH12-PHASE6-6.1-V73-FORMALIZATION-01`): 6.1 tratado formalmente pela sucessora v7.3 (`../2830-V7.3-SUCCESSOR-6.1.md`) — 6.1′ CLOSED; 6.1 v7.0 NOT SATISFIED AS WRITTEN; 6.2 OPEN; D5 OPEN/PARTIAL. *Anterior:* **v1.8** (2026-10-03, `BATCH12-PHASE6-A2-P9B-V72-FORMALIZATION-01`): lacuna contratual de P9(b) tratada formalmente pela sucessora v7.2 (`../2830-V7.2-SUCCESSOR-A2-P9B.md`) — P9(b)′ CLOSED; P9(b)/A2 v7.0 NOT SATISFIED AS WRITTEN; P9a, A2′ e E1 OPEN. *Anterior:* **v1.7 — D-1 DECIDIDA** (2026-10-01, `BATCH12-PHASE6-D1-CN1-DECISION-AND-P14-READINESS-01` + `…-CLOSEOUT-01`): CN-1/I-L, fonte estrutural S-A; P14 não executado; 2830 v7.0 inalterada. *Histórico:* **v1.6 — D-9 incorporada LOCALMENTE** (`BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01`), não commitada, pendente de auditoria independente. A v1.5 foi publicada em `9a4cff16`. A Etapa 1 foi tentada pela v1.4 (Tentativa 03: STOP em S1.3). O E00 vigente **não foi compilado nem executado**. Cada etapa exige mandato próprio. |
| **Baseline do repositório** | **Original do protocolo (v1.0):** `97380747a18db7e38b10b0720a8b2d1f9b0c28ed` (HEAD confirmado, árvore limpa antes da rodada de criação). **Decisão D-1 / v1.7:** `dd96e8ff506a1eb5105d0462ce4b00c00a0d62cc`. |
| **Decisão do proprietário** | **Ambiente isolado pago: recusado.** Validação progressiva de E00/E02/E99/E01 no banco LIVE existente. **Alternativa isolada sem custo: DECIDIDA em 2026-10-01 (D-1 = CN-1/I-L, Supabase local via CLI + Docker, escopo P14/K2/K1/K8b; v1.7)**, com **P14 (a, b, c) obrigatório** — ver `../2830-V7.1-PROPOSAL-ADMIN-CONCURRENCY.md`. *Redação original (v1.0/v1.1): "Não haverá ambiente isolado"; refinada pela decisão de produto registrada em `BATCH12-2830-ADMIN-CONCURRENCY-REASSESSMENT-01`.* |
| **Autoridade** | `2830_validate_edition_context_foundation.sql` v7.0, blob `b4647dcb…` — **imutável**. Este documento **não** a altera: registra, à parte, o que a decisão acima muda e o que continua valendo (seção 7). Para P9(b), R-P9 e o componente de performance de A2 vale, desde 2026-10-03, o delta `../2830-V7.2-SUCCESSOR-A2-P9B.md` (v7.2), que preserva a v7.0 como baseline. Para 6.1 e o componente correspondente de D5 vale, desde 2026-10-03, o delta `../2830-V7.3-SUCCESSOR-6.1.md` (v7.3). |
| **FREEZE** | **ENCERRADO** (2026-10-04, UNFREEZE autorizado formalmente por Fabrício — `UNFREEZE-AUTHORIZATION-RECORD.md`). Nenhuma etapa deste protocolo autoriza importação, revisão editorial ou canary. *(Texto anterior: ATIVO. Nenhuma etapa deste protocolo autoriza importação, revisão editorial ou UNFREEZE.)* |
| **Batch 12** | **CLOSED** (2026-10-04). **E4 SATISFIED** pela autorização formal de Fabrício; **UNFREEZE COMPLETED**; **NEXT = canary real pós-UNFREEZE** (mandato próprio). *Texto anterior (v1.11): "ABERTO. UNFREEZE não autorizado. … P14(a)–(e) CLOSED; D1–D4 CLOSED; E1 CLOSED; E2 CLOSED (K2 executado e aceito); E3 CLOSED; próximo = decisão formal de UNFREEZE por Fabrício (critério E4, não etapa) — 2026-10-04."* D-1 **DECIDIDA** (CN-1/I-L, v1.7). *Texto anterior (v1.9): "P14 ainda não homologado. K2 não é dispensado (seção 8)."* |

Artefatos cobertos (blobs em `9738074`):

| Artefato | Blob | Natureza |
|---|---|---|
| `2830H_E00_precheck_inventory.sql` | vigente: `a4dd84381b928727611a51147ba1a4c1d11b89ab` (24 gates, `evt_allowlist` com as 6 exceções de D-9, não commitado); histórico: `88e9e7a4…` (publicado em `9a4cff16`, allowlist vazia) e `97410c3a…` (executado na Tentativa 03) | 1 SELECT |
| `2830H_E02_identity_terminal_D1_D5.sql` | `3357ed46b77e3bfacbe5b1988820e495ce363dd1` | 1 DO, só catálogo, sem DML |
| `2830H_E99_postcheck_residue.sql` | `49a71ecb4525697858110ee71a3f61f5eee74a34` | 1 SELECT (3 marcadores a substituir) |
| `2830H_E01_section1_structural.sql` | `c4118b8cc13872ecefa600d3c2225cca48f3c1b1` | 1 DO, **escreve fixtures** e desfaz |

---

## 1. Divergências sinalizadas antes de qualquer etapa

**DIV-1 — Sem ambiente isolado (pago recusado; sem custo pendente), o UNFREEZE previsto pela 2830 v7.0 fica inalcançável.**
- Os casos K1, K2 e K8b só podem ser executados no ambiente isolado (P14). O critério D4 exige, além deles, paridade provada desse ambiente.
- K2 é obrigatório para o UNFREEZE (E2) e não admite dispensa. Ele precisa de identidade admin real, que chama `admin_confirm_catalog_variant_import` e grava em `catalog_admin_action_log`.
- No LIVE, isso exigiria ou claims injetadas (proibido em qualquer hipótese) ou uma chamada HTTP que **comita** sob FREEZE (proibido).
- A decisão atual não afeta E00/E01/E02/E99, que não usam P14. Afeta o **fechamento** do Batch 12.
- A alternativa isolada **sem custo** foi **adotada**: D-1 = CN-1/I-L (Supabase local via CLI + Docker, 2026-10-01). É o único caminho registrado para K1/K2/K8b sem violar as proibições acima e continua exigindo P14 (a, b, c) **integral**; K1/K2/K8b só podem começar após a homologação de P14 no CN-1.
- **Estado registrado:** D-1 **DECIDIDA** em 2026-10-01 (CN-1/I-L; P14 ainda não homologado); Batch 12 **ABERTO**; UNFREEZE **BLOQUEADO**. *(Superado em 2026-10-04: P14(a)–(e) CLOSED, K1/K2/K8b aceitos (D1–D3 CLOSED), D4, E1, E2 e E3 CLOSED. Depois, em 2026-10-04: E4 SATISFIED pela autorização formal de Fabrício; Batch 12 CLOSED; UNFREEZE COMPLETED; NEXT = canary real pós-UNFREEZE.)* K2 continua obrigatório e **não é dispensado** por este protocolo nem por nenhuma de suas etapas. Nenhuma etapa aqui descrita conta como avanço sobre K1/K2/K8b ou D4.

**DIV-2 — P9b ("tempo real … nunca no LIVE") não pode ser cumprido como escrito.**
- A adaptação proposta está em AD-2: medir no LIVE os envelopes somente-leitura e limitar os que escrevem.
- O critério A2 da 2830 fica **não satisfeito literalmente** até decisão (D-2).

**DIV-3 — O marcador de fixture no harness difere do texto da 2830.**
- O P5 da 2830 especifica `'H2830-' || gen_random_uuid()`. O E01 usa `H2830_` seguido do uuid em maiúsculas, sem hífens.
- O motivo é que o hífen violaria `ck_cect_code_format` / `ck_cecp_code_format` (`^[A-Z][A-Z0-9_]*$`): todo positivo falharia.
- A divergência já estava implementada, mas não registrada como adaptação. Registrada agora em AD-6. A detecção de resíduo (`LIKE '%H2830%'`) cobre as duas formas.

**DIV-4 — A ordem de execução registrada no README do harness mudou.**
- A ordem registrada era `E00 → E01 → E99 → E00 → E02 → E99`. A decisão atual inverte: primeiro E02 (sem escrita) e, só depois, E01.
- README atualizado nesta rodada.

---

## 2. Pré-condições comuns a todas as etapas

1. **Repositório.** HEAD = baseline declarado no mandato da etapa; `git status` limpo; os blobs do quadro acima conferidos por `git hash-object`. O texto submetido é o do arquivo, **integral e verbatim**: nada de reformatar, recortar comentários ou colar via Dashboard.
2. **Canal.** Somente MCP Supabase `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`.
   - Uma chamada = um statement.
   - Nunca o SQL Editor do Dashboard: ele converte LF em CRLF e já anexou SQL próprio ao payload (regra permanente em EXECUTION-BATCHES / STD-001 §10).
3. **Sem alteração de sessão.** Nenhum `SET`/`set_config`/`ALTER ROLE`/`ALTER DATABASE`, nenhum `CREATE TEMP`, nenhuma sonda experimental. As consultas complementares abaixo são SELECT puro.
4. **Registro da rodada** (README do harness, seção homônima): saída **integral** de cada chamada, na ordem, com horário. Uma saída truncada invalida a rodada: não é FAIL do sistema, mas também não é evidência.
5. **Sem retry automático.** Qualquer STOP encerra a etapa. Uma nova tentativa exige novo mandato, exceto a única repetição prevista em 3.4.

---

## 3. Etapa 1 — somente SELECT: E00, inventários, baseline, P7, md5

**Objetivo.** Provar no LIVE, sem escrever nada, que:
- o E00 compila e roda;
- o estado ainda é o canônico do FREEZE;
- o fecho P7 é inteiramente classificado;
- os pinos de identidade conferem;
- o canal tem as propriedades de que as etapas 2 e 3 dependem.

Nenhum caso da 2830 é declarado PASS nesta etapa.

### 3.1 Sequência

| Passo | Chamada | Registrar |
|---|---|---|
| S1.0 | (local) verificação do repositório — seção 2.1 | HEAD, status, blobs |
| S1.1 | **Query L1** — canal e sessão | saída integral |
| S1.2 | **Query L3** — concorrência detalhada | saída integral |
| S1.3 | **E00** verbatim | saída integral (`e00_precheck`). Qualquer STOP (3.4) encerra a etapa aqui. |
| S1.4 | **Query L2** — pinos da allowlist, bruto × EOL — **somente após STOP** por `g_p7_identity_pinned = false`, **somente para diagnóstico** | saída integral. A etapa **permanece em STOP**: nenhum passo seguinte é executado, nenhuma continuidade automática. |
| S1.5 | **E00** verbatim, 2ª leitura, ≥ 60 s após S1.3 — só se S1.3 não deu STOP | saída integral |
| S1.6 | (opcional, P9a) `EXPLAIN (COSTS OFF)` + texto integral do E00 | plano |

As duas leituras do E00 (S1.3 e S1.5) seguem o precedente das "duas leituras" do Batch 3. A igualdade de `d_baseline_md5` entre elas prova estabilidade do estado sob FREEZE. `checked_at` e `backend_pid` diferirem é esperado: o canal não garante a mesma conexão.

### 3.2 Consultas complementares (SELECT puro, fora do harness, não são casos)

**Query L1 — Canal e sessão**
- **Objetivo:** registrar quem executa, com que permissões e em que modo. Detectar os pressupostos que invalidariam as etapas 2 e 3: réplica em vez de primário, transação só-leitura, `lock_timeout` diferente de `'0'` e falta de visibilidade de `pg_stat_activity`.

```sql
SELECT jsonb_build_object(
    'current_user',                        current_user,
    'session_user',                        session_user,
    'is_superuser',                        (SELECT rolsuper FROM pg_roles WHERE rolname = current_user),
    'reads_all_stats',                     pg_has_role(current_user, 'pg_read_all_stats', 'USAGE'),
    'in_recovery',                         pg_is_in_recovery(),
    'transaction_read_only',               current_setting('transaction_read_only'),
    'default_transaction_read_only',       current_setting('default_transaction_read_only'),
    'statement_timeout',                   current_setting('statement_timeout'),
    'lock_timeout',                        current_setting('lock_timeout'),
    'idle_in_transaction_session_timeout', current_setting('idle_in_transaction_session_timeout'),
    'standard_conforming_strings',         current_setting('standard_conforming_strings'),
    'server_version_num',                  current_setting('server_version_num'),
    'application_name',                    current_setting('application_name'),
    'backend_pid',                         pg_backend_pid(),
    'activity_rows_state_hidden',          (SELECT count(*) FROM pg_stat_activity
                                             WHERE pid <> pg_backend_pid()
                                               AND backend_type = 'client backend'
                                               AND state IS NULL),
    'visible_foreign_sessions',            (SELECT count(*) FROM pg_stat_activity a
                                             WHERE a.pid <> pg_backend_pid()
                                               AND a.backend_type = 'client backend'
                                               AND a.usename IS NOT NULL
                                               AND NOT pg_has_role(current_user, a.usename, 'MEMBER')
                                               AND a.state IS NOT NULL),
    'ec_table_owner',                      (SELECT jsonb_object_agg(c.relname, pg_get_userbyid(c.relowner) ORDER BY c.relname)
                                              FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                             WHERE n.nspname = 'public' AND c.relkind = 'r'
                                               AND c.relname LIKE 'card\_edition\_context%'),
    'checked_at',                          clock_timestamp()
) AS l1_channel;
```
- **Resultado esperado:**
  - `in_recovery = false`;
  - `standard_conforming_strings = on`;
  - `server_version_num ≥ 170000`;
  - `lock_timeout = '0'`;
  - **visibilidade de `pg_stat_activity` provada** por uma de três vias, nesta ordem:
    1. `is_superuser = true`; ou
    2. `reads_all_stats = true` (membro efetivo de `pg_read_all_stats`, inclusive via `pg_monitor`); ou
    3. **controle positivo explícito**: `visible_foreign_sessions ≥ 1` — ao menos uma sessão `client backend` de um papel do qual `current_user` **não** é membro aparece com `state` preenchido. O PostgreSQL só expõe `state` de sessão de papel alheio a superusuário ou a quem tem `pg_read_all_stats`; ver essa linha prova o privilégio **efetivo**. A via 3 é registrada como tal, com a linha que serviu de controle (L3).
  - `activity_rows_state_hidden = 0` **não prova acesso**: zero linhas ocultas também ocorre quando simplesmente não há sessão alheia. É só diagnóstico. Com `activity_rows_state_hidden > 0` e nenhuma das três vias, a falta de acesso está demonstrada;
  - `ec_table_owner` = `current_user` nas 5 tabelas, ou `is_superuser = true`;
  - `transaction_read_only` registrado. `on` não bloqueia as etapas 1–2, mas bloqueia a 3.
- **Como validar:** cada item acima é lido direto do JSON. Qualquer divergência é tratada em 3.4.

**Query L2 — Pinos da allowlist: bruto × normalizado por EOL**
- **Objetivo:** **diagnóstico apenas**, executado **depois** de um STOP por `g_p7_identity_pinned = false`: classificar o `ALLOWLIST_MISMATCH` como causado só por fim de linha (CRLF) ou como divergência real, sem tocar nos pinos. Precedente: `2217`, LIVE com CRLF e md5 normalizado idêntico — regra permanente do EXECUTION-BATCHES.
- **Não é critério de aceite e não reabre a etapa.** Qualquer que seja o resultado da L2, a Etapa 1 termina em STOP. Continuar exige adjudicação de Fabrício (D-6), mandato de correção do harness quando couber e **novo mandato** para refazer a Etapa 1 desde S1.0.

```sql
SELECT n.nspname || '.' || p.proname                                 AS fn,
       pg_get_function_identity_arguments(p.oid)                      AS identity_args,
       l.lanname                                                      AS language,
       p.prosecdef,
       p.provolatile::text                                            AS vol,
       p.proconfig,
       md5(p.prosrc)                                                  AS md5_raw,
       md5(replace(p.prosrc, chr(13) || chr(10), chr(10)))            AS md5_lf,
       length(p.prosrc)                                               AS len_raw,
       length(p.prosrc) - length(replace(p.prosrc, chr(13), ''))      AS cr_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language  l ON l.oid = p.prolang
 WHERE (n.nspname = 'internal' AND p.proname IN (
            'seal_edition_context_composition','guard_edition_context_composition_immutable',
            'enforce_edition_context_signature_write','guard_edition_context_trait_active',
            'normalize_edition_context_external_mapping','enforce_edition_context_mapping_header',
            'seal_edition_context_external_mapping','guard_edition_context_mapping_composition_immutable',
            'enforce_edition_context_mapping_signature_write'))
    OR (n.nspname = 'public'     AND p.proname = 'normalize_external_catalog_value')
    OR (n.nspname = 'extensions' AND p.proname = 'unaccent')
 ORDER BY 1, 2;
```
- **Resultado esperado:** 12 linhas.
  - As 10 não-C devem ter `md5_raw` igual ao pino do E00.
  - As 2 `unaccent` devem ser `language = c`.
- **Adjudicação por linha:**

| `md5_raw` = pino | `md5_lf` = pino | `cr_count` | Classificação | Consequência |
|---|---|---|---|---|
| sim | — | 0 | IDÊNTICO | nenhuma |
| não | sim | > 0 | **TRANSPORT/EOL-ONLY** (regra permanente) | a etapa segue em STOP. Registro para D-6: adjudicação explícita de Fabrício e, se aceita, mandato de correção do harness (pinar o md5 bruto do LIVE com proveniência, ou normalizar EOL antes do md5 nos dois lados). Nunca editar pino em silêncio. |
| não | não | qualquer | **DIVERGÊNCIA REAL** | a etapa segue em STOP — o corpo LIVE não é o do repositório |

- **Como validar:** contar 12 linhas e confrontar cada md5 com a tabela `p7_allowlist` do E00. O resultado vai ao registro como diagnóstico do STOP.

**Query L3 — Concorrência detalhada**
- **Objetivo:** dar conteúdo ao `g_no_concurrency` do E00, que só expõe uma contagem. A identificação nominal de uma sessão (ex.: pooler, Realtime, PostgREST) é **exclusivamente diagnóstica** e não altera o resultado.

```sql
SELECT jsonb_build_object(
    'sessions', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'pid', a.pid, 'usename', a.usename, 'application_name', a.application_name,
                    'backend_type', a.backend_type, 'state', a.state,
                    'wait_event_type', a.wait_event_type, 'wait_event', a.wait_event,
                    'xact_start', a.xact_start, 'state_change', a.state_change,
                    'backend_xid', a.backend_xid::text) ORDER BY a.backend_type, a.state, a.pid)
                  FROM pg_stat_activity a
                 WHERE a.pid <> pg_backend_pid() AND a.datname = current_database()), '[]'::jsonb),
    'locks_on_scope', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'pid', l.pid, 'relation', c.relname, 'mode', l.mode, 'granted', l.granted) ORDER BY c.relname, l.pid)
                  FROM pg_locks l JOIN pg_class c ON c.oid = l.relation
                 WHERE l.pid <> pg_backend_pid()
                   AND c.relname IN ('card_edition_context_trait','card_edition_context_profile',
                                     'card_edition_context_profile_trait','card_edition_context_external_mapping',
                                     'card_edition_context_external_mapping_trait','card_variant',
                                     'catalog_variant_import_job','catalog_variant_import_row',
                                     'catalog_admin_action_log','game')), '[]'::jsonb),
    'checked_at', clock_timestamp()
) AS l3_concurrency;
```
- **Resultado esperado:**
  - `locks_on_scope = []`;
  - nenhuma **outra** sessão `client backend` em `active`, `idle in transaction` ou `idle in transaction (aborted)`. A própria sessão já é excluída pela consulta (`pid <> pg_backend_pid()`).
- **Como validar:** leitura direta. **Qualquer** outra sessão `client backend` ativa ou em transação ⇒ **STOP**, **mesmo quando identificada como plataforma**. A classificação nominal — feita só com os campos que a L3 retorna: `usename`, `application_name`, `backend_type`, `state`, `wait_event_type`/`wait_event`, `xact_start`, `state_change` — é registrada só para diagnóstico. Ela **não** dispensa o STOP e **não** dispensa `g_no_concurrency = true` no E00, que continua condição obrigatória.

### 3.3 Critério de aceite da Etapa 1 — `READY FOR STAGE 2`

Todos os itens abaixo, cumulativos:
- L1 conforme 3.2.
- E00 (S1.3 e S1.5) com `gate_pass = true`.
- `d_canon_diff = []`.
- `d_baseline_md5` idêntico nas duas leituras.
- **Identidades P7 alcançadas = identidades da allowlist.** De `d_p7_functions`, tomar as entradas com `gate_scope = true` cujo schema **não** é `pg_catalog`, e delas o conjunto de **identidades distintas** — o campo `fn`, que já vem como `schema.nome(argumentos de identidade)`. Esse conjunto precisa ser **igual**, elemento a elemento, ao conjunto das 12 identidades da `p7_allowlist`:
  - `internal.seal_edition_context_composition()`
  - `internal.guard_edition_context_composition_immutable()`
  - `internal.enforce_edition_context_signature_write()`
  - `internal.guard_edition_context_trait_active()`
  - `internal.normalize_edition_context_external_mapping()`
  - `internal.enforce_edition_context_mapping_header()`
  - `internal.seal_edition_context_external_mapping()`
  - `internal.guard_edition_context_mapping_composition_immutable()`
  - `internal.enforce_edition_context_mapping_signature_write()`
  - `public.normalize_external_catalog_value(p_value text)`
  - `extensions.unaccent(text)`
  - `extensions.unaccent(regdictionary, text)`

  Regras:
  - A comparação é por **identidade**: schema, nome **e** argumentos. Mesmo nome com outra assinatura conta como elemento diferente.
  - Identidade **a mais** (alcançada e fora da lista) ⇒ STOP. É uma raiz ou chamada não prevista, mesmo que algum gate a tenha aceitado.
  - Identidade **a menos** (na lista e não alcançada) ⇒ STOP. Indica trigger ou chamada ausente no LIVE: divergência estrutural a adjudicar. Os gates do E00 não detectam essa falta — este critério documental a detecta.
  - Funções de `pg_catalog` ficam **fora desta comparação**. Elas são governadas por `BUILTIN`/`DENIED` (`g_p7_all_classified`, `g_p7_no_unresolved`) e não constam da allowlist.
  - Entradas com `gate_scope = false` (inventário de `card_variant`, staging, job, action log e game) são registradas, mas não entram nesta comparação — mesmo escopo do gate do E00.
- `d_p7_unqualified_calls` sem `UNRESOLVED`/`DENIED`.
- `d_p7_writes` com alvos só nas 5 tabelas EC.
- **EOL (D-6).** O pino de corpo é comparado com `md5(replace(prosrc, CRLF, LF))`. `d_p7_eol_normalized` é registrado; cada item listado tem `body_md5_lf` = pino, `crlf_count = cr_count` e o md5 bruto (`body_md5`) citado como evidência. Nada é aceito em silêncio.
- **Event triggers (D-9).**
  - `d_event_triggers` registrado integralmente;
  - `d_evt_catalog_count` = número de linhas do inventário (`g_evt_inventory_complete`);
  - `d_evt_unadjudicated = []`;
  - a `evt_allowlist` contém **exatamente** as 6 exceções aprovadas em D-9 (identidades literais da L4);
  - toda exceção vem de uma linha da `evt_allowlist` com identidade de 12 atributos (nome, evento, tags, estado, dono, função, linguagem, dono da função, `SECURITY DEFINER`, `proconfig`, extensão, md5 LF) e justificativa **não vazia**, só para evento DDL;
  - evento não-DDL (`login`) habilitado ⇒ STOP sempre.
- L3 limpo.

### 3.4 STOP da Etapa 1 e única repetição admitida

| Condição | Tratamento |
|---|---|
| E00 com erro de compilação/execução (qualquer SQLSTATE) | STOP · defeito de harness · mandato de correção |
| `g_freeze_canonical_equal = false` | STOP · FREEZE violado ou deriva · nunca atualizar constante |
| `g_p7_identity_pinned = false` | STOP · L2 **somente para diagnóstico** (S1.4) · a etapa não continua · D-6. Com o pino normalizado (D-6), só diverge por conteúdo, CR isolado ou atributo pinado — nunca por CRLF |
| `g_p7_no_ddl = false` | STOP · comando DDL no fecho P7: dispararia event triggers e alteraria catálogo · classificação humana |
| `g_evt_ddl_only = false` | STOP · event trigger habilitado em evento não-DDL (`login` etc.) · sem exceção possível |
| `g_evt_inventory_complete = false` | STOP · inventário de event triggers diferente da contagem direta de `pg_event_trigger` (trigger perdido no JOIN) · classificação humana · sem repetição |
| `g_evt_all_adjudicated = false` | STOP · event trigger habilitado sem exceção adjudicada por identidade completa (12 atributos) e justificativa · L4 sob mandato próprio · D-9 · sem repetição |
| `g_p7_all_classified` / `g_p7_no_unresolved` / `g_p7_search_path_safe` / `g_p7_lexically_supported` / `g_p7_no_unqualified_dml` / `g_p7_writes_in_scope` / `g_p7_no_external_or_dynamic` / `g_p7_closure_complete` falsos | STOP · classificação humana do item listado em `d_p7_*` |
| `g_no_concurrency = false` | **Uma** repetição admitida: L3 → E00 novo, após ≥ 60 s. Persistindo, STOP. As duas saídas são registradas. |
| visibilidade de `pg_stat_activity` **não provada** pelas vias 1–3 da L1 (independentemente de `activity_rows_state_hidden`) | STOP · `g_no_concurrency` / `g_no_open_txn_others` poderiam ser **vácuos** (P13) · decisão D-5 |
| conjunto de identidades P7 não-nativas ≠ allowlist (a mais ou a menos) | STOP · adjudicação da identidade listada |
| `lock_timeout ≠ '0'` na L1 | STOP · o E99 compara com a constante `'0'` e falharia sempre · decisão D-4 |
| `d_baseline_md5` diferente entre S1.3 e S1.5 | STOP · estado instável sob FREEZE |
| saída truncada pelo canal | rodada inválida (não é FAIL) · repetir só com novo mandato |

---

## 4. Etapa 2 — E02 (sem DML) e E99, com evidência completa

**Pré-requisito:** Etapa 1 `READY FOR STAGE 2` em registro, e mandato próprio.

### 4.1 Sequência (uma rodada = um E00 novo)

| Passo | Chamada | Registrar |
|---|---|---|
| S2.0 | verificação do repositório (2.1) | HEAD, blobs |
| S2.1 | **L3** | saída integral |
| S2.2 | **E00** verbatim — o E00 **desta** rodada | saída integral; `gate_pass` precisa ser `true`, senão STOP antes do E02 |
| S2.3 | **E02** verbatim | resposta integral do canal: SQLSTATE, mensagem, horário |
| S2.4 | **E99** com os 3 marcadores substituídos a partir de S2.2 | o **texto exato submetido** e a saída integral |

**Substituição dos marcadores do E99:**
- `__E00_D_BASELINE__` recebe o JSON de `d_baseline` copiado da saída de S2.2, **colado**, não redigitado.
- `__E00_D_BASELINE_MD5__` recebe `d_baseline_md5`.
- `__E00_ROLE_SETTING_ROWS__` recebe `d_session.db_role_setting_rows`.
- Antes de submeter, conferir que o JSON colado não contém `'`. Os valores esperados são contagens, datas e chaves de status; um apóstrofo quebraria o literal e resultaria em erro de sintaxe, nunca em PASS.

**Nota sobre o md5.** O E99 recalcula `md5(capturado::jsonb::text)`. Como o JSON é reinterpretado como `jsonb`, uma reformatação do canal (espaços, ordem de chaves) **não** altera o md5. O md5 prova conteúdo idêntico ao declarado, não a origem da rodada. A origem é garantida pelo registro, conforme o README do harness.

### 4.2 Critério de aceite do E02 — `D1–D5 PASS`

1. A resposta de S2.3 é um **erro** com SQLSTATE `H283P` e mensagem exatamente no formato abaixo, com `N` inteiro:

   ```
   H2830_ROLLBACK_PASS: envelope=E02_SECAO_D_IDENTIDADE_TERMINAL pass=5/5 casos=D1,D2,D3,D4,D5 elapsed_ms=N
   ```

   - Se o canal não expuser o SQLSTATE, a mensagem literal com o prefixo `H2830_ROLLBACK_PASS` é aceita, e a limitação é registrada.
   - Mensagem truncada = inconclusivo.
2. `elapsed_ms ≤ 60000` (margem P9b; ver AD-2).
3. E99 de S2.4:
   - `gate_pass = true`;
   - `d_diff = []`;
   - `d_canon_diff = []`;
   - `g_captured_integrity = true`.
4. Ordem temporal no registro: `checked_at(E00) < S2.3 < checked_at(E99)`, sem outro envelope entre eles.

**Diferença de registro em relação ao E01.** O E02 não gera marcador `H2830_<uuid>`, porque não tem fixture. O item 2 da vinculação documental do README ("mensagem terminal com marcador") se aplica a ele sem o marcador — adaptação AD-7.

### 4.3 STOP da Etapa 2

| Resposta de S2.3 | Classificação |
|---|---|
| `H283P` com mensagem conforme | PASS (sujeito ao E99) |
| `H283F` / `H2830_FAIL: …` | FAIL do caso indicado · STOP · sem retry |
| outro SQLSTATE (ex.: `42601`, `42P01`, `42883`) | FAIL de harness (compilação/execução) · STOP · mandato de correção |
| **retorno `[]`** (sem erro) | **DEFEITO** — o DO nunca termina normalmente · STOP · E99 imediato |
| `57014` (statement_timeout) | FAIL · STOP · rever P9 |
| queda de conexão | inconclusivo · L3 para confirmar ausência de backend remanescente · E99 · STOP |

Qualquer E99 com `gate_pass = false` depois do E02 é **incidente**, porque o E02 não escreve. A causa só pode ser concorrência ou deriva externa. O operador registra, não corrige nada e dá STOP.

---

## 5. Etapa 3 — mandato futuro E01 (escrita transitória no LIVE)

**Preparado aqui, não autorizado.** O E01 é o único envelope desta fundação que **escreve** no LIVE: 11 tentativas de INSERT de fixture em 3 tabelas EC (4 aceitas, 7 negativas esperadas), todas desfeitas por subtransação e pelo término em exceção.

### 5.1 Pré-requisitos (todos, antes do mandato)

1. Etapa 2 aceita em registro.
2. **Decisão A5 / P8 — `lock_timeout`** (D-3):
   - **(a) autorizar `SET LOCAL lock_timeout = '5s'`.** Exige um mandato de correção **prévio** do E01: descomentar a linha como primeira instrução, acrescentar a asserção `current_setting('lock_timeout') = '5s'`, atualizar `tools/static_check.py`, que hoje proíbe `SET LOCAL`, e produzir um novo blob. O E01 só vai ao LIVE com o blob novo auditado.
   - **(b) rodar sem ele.** Nesse caso a decisão fica registrada; uma espera de lock fica limitada apenas pelo `statement_timeout` (120 s).
   - *Histórico, anterior à decisão D-3/A5:* recomendação técnica: **(a)** — sem ambiente isolado, a proteção contra espera inesperada importa mais. Superada pela decisão abaixo.
   - **DECIDIDO — opção (b) aprovada por Fabrício (`BATCH12-2830-D3-A5-DECISION-CLOSEOUT-01`, 2026-09-27).** O E01 será executado **sem** `SET LOCAL lock_timeout`, com o blob original `c4118b8cc13872ecefa600d3c2225cca48f3c1b1` preservado (nenhum mandato de correção do E01 nem do `tools/static_check.py`).
     - **Risco aceito:** espera por lock limitada somente pelo `statement_timeout` da sessão, observado em `2min` (120 s) na L1 das Tentativas 03 e 04.
     - **Aceite inalterado (5.3):** `elapsed_ms ≤ 60000`, rollback integral e E99 sem resíduo.
     - **D-4 continua obrigatório (item 5):** se a L1 da Etapa 3 mostrar `lock_timeout ≠ '0'`, STOP antes do E01; nenhuma alteração automática de sessão.
     - A Etapa 3 continua dependendo de mandato independente e da autorização expressa do item 4.
3. **Canal gravável:** L1 com `transaction_read_only = off` e `default_transaction_read_only = off`. Se estiver `on`, o E01 falharia com `25006` em todo INSERT — FAIL, nunca PASS, mas inútil.
4. **Autorização explícita no mandato** de que escrita **transitória e integralmente desfeita** nas tabelas EC é permitida sob FREEZE. A 2830 P1 pressupõe isso, mas o FREEZE vigente não o diz.
5. Decisão D-4 resolvida se `lock_timeout` da sessão MCP ≠ `'0'`.

### 5.2 Sequência JIT

| Passo | Chamada | Gate |
|---|---|---|
| S3.0 | verificação do repositório | blob do E01 = o auditado |
| S3.1 | **L1** | 5.1 itens 3 e 5 |
| S3.2 | **L3** | limpo |
| S3.3 | **E00** verbatim (desta rodada) | `gate_pass = true`, `g_no_residue = true`, `g_no_sequences_touched_now = true`, `g_rls_bypass = true` |
| S3.4 | **E01** verbatim, **imediatamente** após S3.3 | ver 5.3 |
| S3.5 | **E99** com marcadores de S3.3, **imediatamente** após S3.4 | ver 5.3 |
| S3.6 | **L3** | nenhum backend com a query do E01, nenhum lock residual |

### 5.3 Aceite, rollback e tempo

**PASS de E01 (1.1–1.12)** exige todos:
- SQLSTATE `H283P` e mensagem `H2830_ROLLBACK_PASS: envelope=E01_SECAO1_ESTRUTURAL pass=12/12 casos=1.1,…,1.12 marker=H2830_… elapsed_ms=N`;
- `elapsed_ms ≤ 60000`;
- E99 com `gate_pass = true`, `d_diff = []`, `g_marker_absent = true`;
- S3.6 limpo.

**Por que o rollback é estrutural, não opcional.** Nenhum caminho do DO termina normalmente:
- todo caso termina em `H283C`, que desfaz a subtransação do caso;
- o envelope termina em `H283P` ou `H283F`;
- qualquer erro não previsto escapa e também aborta.

Timeout (`57014`), `lock_timeout` (`55P03`) e queda de conexão abortam a transação no servidor. Em todos os casos, nenhuma linha de fixture sobrevive.

**Resíduo não-transacional aceito e declarado:**
- contadores de `pg_stat_*` (`n_tup_ins`, `n_dead_tup`);
- tuplas mortas até o autovacuum;
- WAL;
- linhas de log do servidor com o marcador.

Nenhum desses é dado de negócio. Sequences: nenhuma — ids UUID, provado por `g_no_sequences_touched_now`. Os eventos DEFERRED (`trg_cecp_seal` / `trg_cecem_seal`) enfileirados pela contraprova 1.9 são descartados com a subtransação do caso.

**Prova de rollback — três fontes independentes:**
1. a mensagem terminal, com o marcador da execução;
2. o E99: contagens das 5 tabelas EC iguais às do E00 e marcador ausente em `code`/`normalized_token`;
3. a L3 de S3.6: nenhuma sessão ou lock remanescente.

**Tempo:**
- `statement_timeout` da sessão MCP (120 s) é o teto duro, sem alteração;
- `elapsed_ms > 60000` torna o resultado **não aceito**, mesmo com PASS, e dispara investigação;
- a previsão é de milissegundos (12 casos, 11 tentativas de INSERT, consultas de catálogo), mas não há medição prévia (AD-2).

### 5.4 STOP da Etapa 3

| Evento | Ação |
|---|---|
| E00 de S3.3 com gate falso | não submeter o E01 |
| `H283F` | FAIL do caso · E99 imediato · STOP · sem retry |
| outro SQLSTATE, `57014`, `55P03` | FAIL · E99 imediato · STOP |
| retorno `[]` | **DEFEITO GRAVE** · E99 imediato · se houver resíduo, ver incidente abaixo |
| queda de conexão | L3 (aguardar, só leitura, o fim do backend — **sem** `pg_terminate_backend`) · E99 · STOP |
| E99 com `g_marker_absent = false` ou `d_diff ≠ []` | **INCIDENTE** (abaixo) |

**Incidente de resíduo:**
- não apagar nada;
- não repetir;
- registrar o marcador da execução, as linhas encontradas (SELECT por marcador nas 5 tabelas) e o `d_diff`;
- a limpeza exige mandato explícito de Fabrício, com SQL pareado e verificação por identidade.

---

## 6. Riscos identificados

### 6.1 Compilação / execução PostgreSQL

| # | Risco | Onde | Efeito se ocorrer | Como a etapa detecta |
|---|---|---|---|---|
| C-1 | Pinos md5 derivados do repositório × `prosrc` LIVE com **CRLF** (precedente real na `2217`; **ocorrido** na Tentativa 03 em `public.normalize_external_catalog_value`) | E00 `p7_allowlist` | antes de D-6: `ALLOWLIST_MISMATCH` ⇒ STOP. Com D-6: pino comparado ao md5 normalizado (só CRLF); o bruto fica em `d_p7_functions.body_md5` e `d_p7_eol_normalized` | E00; L2 como diagnóstico de STOP de pino |
| C-2 | Motor de regex ARE × modelo Python `re`: semântica POSIX "mais longo à esquerda" em alternâncias; lookbehind `(?<!…)` (existe desde PG 9.6); `\m`/`\M` | E00 `p7_re` | falso STOP (classificação `UNRESOLVED`); falso PASS exigiria o padrão **deixar de achar** uma chamada/escrita real | `d_p7_unqualified_calls` / `d_p7_writes` completos no registro permitem conferência humana contra o corpo do repositório — que, com `g_p7_identity_pinned = true`, é byte-idêntico ao LIVE |
| C-3 | `gen_random_uuid` como DEFAULT resolvido para `extensions.gen_random_uuid` (pgcrypto) em vez de `pg_catalog` | raízes P7 (default) | função não classificada ⇒ STOP | `d_p7_functions` |
| C-4 | Trigger/raiz não prevista nas 5 tabelas EC (ex.: trigger genérico de `updated_at` adicionado fora do repositório) | E00 | `UNCLASSIFIED` ⇒ STOP | `d_p7_functions` |
| C-5 | PL/pgSQL planeja cada SQL interno **só quando executado**: ramos de falha nunca percorridos num PASS não ficam provados em runtime | E01, E02 | um defeito em ramo de falha aparece só quando o caso falha — vira erro diferente de `H283P`, nunca PASS | limite declarado; `plpgsql_check` exigiria extensão nova (proibido) |
| C-6 | `server_version_num < 170000` ⇒ `has_table_privilege(..., 'MAINTAIN')` inválido | E01 1.12 | `g_pg17_maintain_privilege = false` no E00 ⇒ STOP antes do E01 | L1 + E00 |
| C-7 | Renderização de `pg_get_expr` (predicados 1.5/1.11) | E01 | FAIL, não PASS | mensagem do caso |
| C-8 | Apóstrofo no JSON colado no E99 | E99 | erro de sintaxe ⇒ não é PASS | conferência antes da submissão |

### 6.2 Efeitos externos

- **P7 é o gate.** Função com sinal externo (`net.`, `http`, `pg_notify`, `dblink`, `pg_net`, `COPY`, `lo_*`, `set_config`, `pg_sleep`…) ou SQL dinâmico no fecho ⇒ STOP antes de qualquer escrita.
- **Realtime / replicação lógica:** transação abortada não é decodificada; publicações registradas em `d_publications`.
- **Webhooks de banco do Supabase** são triggers e, portanto, entram no fecho P7.
- **Event triggers da plataforma.** O LIVE tem event triggers habilitados (Tentativa 03: 6, em `ddl_command_end`/`sql_drop`). Event triggers só disparam nos comandos da matriz do PostgreSQL (DDL, `GRANT`/`REVOKE`, `COMMENT`, `SECURITY LABEL`, `SELECT INTO`), e o evento `login` na conexão. Os envelopes autorizados não contêm esses comandos (prova estática em `tools/static_check.py`) e o fecho P7 não pode contê-los (`g_p7_no_ddl`). Cada event trigger habilitado precisa de exceção individual, por identidade completa (D-9); `login` nunca é excepcionado. O canal `apply_migration` do MCP executa DDL próprio antes da migration (relato público, não verificado aqui) e é proibido nestas etapas; só `execute_sql` é usado.
- **Logs do servidor e `pgaudit`** registram os statements e o marcador. É resíduo de observabilidade, não de dado.
- **Nenhuma RPC administrativa** é chamada; `catalog_admin_action_log` entra no baseline e precisa ficar igual.

### 6.3 Concorrência

- Sob FREEZE não há escritor legítimo. `g_no_concurrency` / `g_no_open_txn_others` provam isso **somente se** o papel do MCP enxergar `pg_stat_activity` de outros papéis. Caso contrário os gates passam **vazios** — risco de falso PASS por vácuo, tratado pela L1 — exige superusuário, `pg_read_all_stats` ou controle positivo explícito (`visible_foreign_sessions ≥ 1`); `activity_rows_state_hidden = 0` sozinho não prova acesso — e pela decisão D-5.
- Conexões de plataforma (pooler, Realtime, PostgREST) podem estar `active` num instante. O resultado é **STOP**, conservador, mesmo com a sessão identificada. A única repetição admitida é a do E00 por `g_no_concurrency = false` (3.4), e ela exige L3 e E00 novos, ambos limpos.
- As fixtures do E01 tomam, por milissegundos:
  - `RowExclusiveLock` em 3 tabelas EC;
  - entradas novas em índices únicos;
  - `FOR KEY SHARE` na linha `game` POKEMON, via FK.

  Isso não bloqueia leitores; bloquearia apenas um escritor concorrente das mesmas chaves, o que o FREEZE proíbe.
- **Canal:** cada chamada MCP pode cair em outro backend. Nada no protocolo depende de continuidade entre chamadas — um envelope é uma chamada. E00 e E99 são amarrados pelo registro, não pela conexão.

### 6.4 Rollback

- É estrutural (5.3) e não depende do cliente.
- Resíduo não-transacional declarado: estatísticas, tuplas mortas, WAL, logs.
- O pior caso é um defeito que faça o DO terminar normalmente (retorno `[]`). Pelo código isso é impossível; pelo protocolo, é tratado como incidente com E99 imediato.

### 6.5 Canal e evidência

- O canal pode não expor o SQLSTATE custom (`H283P`/`H283F`) ou pode truncar a mensagem ou o JSON do E00. Mensagem truncada = inconclusivo, nunca PASS. A primeira execução do E02 prova, de passagem, o que o canal transmite.
- Se `transaction_read_only = on` no MCP: as etapas 1–2 funcionam; a 3 é inútil até mudar o canal. A troca de canal é decisão de Fabrício e não pode ser feita pelo agente.

---

## 7. Adaptações ao protocolo documental (propostas — a 2830 não é alterada)

Cada linha abaixo é uma **proposta** que só vale depois de aceite explícito de Fabrício (seção 8). O aceite deve ficar registrado aqui e no EXECUTION-BATCHES. Nenhuma delas é aplicada em silêncio, e a 2830 v7.0 permanece o texto de referência.

| # | Texto da 2830 v7.0 | Pressuposto | Proposta sem ambiente isolado | Efeito no aceite |
|---|---|---|---|---|
| AD-1 | P14; D1–D4; E2 (K2 obrigatório para UNFREEZE) | K1/K2/K8b em ambiente descartável com paridade | **Nenhuma adaptação proposta.** No LIVE, K2 exige claims (proibido) ou commit sob FREEZE (proibido). K2 **não é dispensado**; D-1 **DECIDIDA** (CN-1/I-L, 2026-10-01): K1/K2/K8b só no CN-1, após P14 homologado. | Batch 12 ABERTO · UNFREEZE BLOQUEADO |
| AD-2 | P9b "tempo real … nunca no LIVE"; A2 | medir antes de ir ao LIVE | **Envelopes só-leitura** (E00, E02, E99): a própria execução no LIVE é a medição, inofensiva. **Envelopes que escrevem** (E01 e futuros): sem medição prévia; limite duro pelo `statement_timeout` de 120 s, rejeição acima de 60 s, `lock_timeout` 5 s se D-3(a), EXPLAIN (COSTS OFF) prévio quando houver consulta pesada. As seções pesadas (B, M, 5.2/5.3/5.7) exigem readiness própria antes de irem ao LIVE. | AD-2 é **adaptação operacional**: **não** cumpre o A2 da 2830 v7.0 e **não** satisfaz E1; **A2/P9(b) permanece OPEN**. O fechamento exige alteração formal da especificação (v7.1 ou sucessora), conforme `../EXECUTION-BATCHES.md` (Batch 12, linha P9b/A2). A 2830 v7.0 não é alterada por este protocolo. *2026-10-03 (v1.8): a lacuna contratual de P9(b) foi tratada formalmente pela v7.2 (`../2830-V7.2-SUCCESSOR-A2-P9B.md`), com P9(b)′ CLOSED. AD-2 permanece fato histórico de adaptação operacional e **não** se torna, retroativamente, cumprimento de P9(b)/A2 v7.0 (NOT SATISFIED AS WRITTEN); A2′ continua OPEN até o P9a.* |
| AD-3 | P1 "teste transacional com rollback integral" | ambiente onde uma falha de rollback é descartável | mantém-se, com prova tripla (5.3) e incidente definido; exige autorização explícita de escrita transitória sob FREEZE (5.1.4) | nenhum, se aceito |
| AD-4 | P13 controle negativo "plantar em fixture" | idem | mesma disciplina do E01, envelope a envelope, com readiness própria | nenhum |
| AD-5 | P14(d) "dados de fixture sintéticos; ambiente descartado" | descarte do ambiente como garantia final | a garantia final passa a ser o rollback estrutural + E99. Fixtures que envolvem job, row, `card_variant` ou Game sentinela (2.6/3.3) ganham risco maior no LIVE e precisam de readiness própria | nenhum para E01/E02 |
| AD-6 | P5 marcador `'H2830-' ‖ uuid` | — | marcador efetivo `H2830_` + uuid sem hífens em maiúsculas, porque os CHECKs de formato de `code` recusam hífen; detecção de resíduo por `LIKE '%H2830%'` cobre as duas formas | nenhum (formaliza o implementado) |
| AD-7 | Vinculação E00 → envelope → E99 com marcador | todo envelope tem fixture | para envelopes sem fixture (E02), o item 2 do registro é a mensagem terminal sem marcador | nenhum |
| AD-8 | Regra permanente EOL (bruto ≠, normalizado =) × gate de pino bruto do E00 | corpo LIVE byte-idêntico ao repositório | **proposta D-6:** pino comparado ao md5 com CRLF→LF nos dois lados (o repositório é LF); CR isolado continua STOP; md5 bruto, `cr_count` e `crlf_count` exportados e registrados; `d_p7_eol_normalized` lista cada caso. Vale só após mandato de correção e novo blob do E00 | nenhum |
| AD-10 | `g_no_enabled_event_triggers` (nenhum event trigger habilitado) | LIVE sem event triggers | **APROVADA (D-9, `BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01`), restrita aos envelopes atuais.** Inventário integral com completude contra a contagem direta do catálogo (`g_evt_inventory_complete`); `login`/evento não-DDL ⇒ STOP sempre; evento DDL só com exceção individual por identidade de 12 atributos e justificativa não vazia. A `evt_allowlist` contém exatamente as 6 exceções da L4 (`pgrst_ddl_watch` e `pgrst_drop_watch`: aceite ordinário, inclusive `tags` NULL; `issue_pg_cron_access`, `issue_graphql_placeholder`, `issue_pg_graphql_access` e `issue_pg_net_access`: aceite excepcional). **Não** autoriza novas operações, migrations nem DDL; nova linha exige nova L4, nova decisão e mandato de correção | nenhum: com a identidade LIVE igual à L4, `g_evt_all_adjudicated` passa; qualquer divergência reprova |
| AD-9 | P8/G15 "zero sessão concorrente" | visibilidade total de `pg_stat_activity` | exigir superusuário **ou** `pg_read_all_stats` **ou** controle positivo explícito de visibilidade (L1, via 3); `activity_rows_state_hidden = 0` isolado não basta; senão o gate pode ser vácuo (P13) | nenhum, se a visibilidade for provada |

---

## 8. Decisões pendentes do proprietário

| # | Decisão | Bloqueia |
|---|---|---|
| D-1 | **DECIDIDA (2026-10-01, `BATCH12-PHASE6-D1-CN1-DECISION-AND-P14-READINESS-01`): CN-1 / I-L — Supabase local via CLI + Docker, sem custo**, ambiente isolado oficial para P14a/b/c, K2, K1 e K8b; P9b/A2 fora do escopo (frente separada). A decisão não demonstra P14: K1/K2/K8b seguem bloqueados até P14 (a, b, c) homologado no CN-1. **Fonte estrutural do CN1-2 = S-A** (dump estrutural de 28/09 + definições canônicas necessárias para objetos faltantes); nenhuma definição canônica é presumida equivalente ao LIVE antes da P14a, que é a prova final; divergência na P14a = STOP. *Texto anterior:* como executar K1/K2/K8b (e D4) sem ambiente isolado **pago** (recusado); opção registrada: ambiente isolado **sem custo**, **P14 (a, b, c) obrigatório** (proposta v7.1, canal CN-1). Batch 12 **ABERTO**, UNFREEZE **BLOQUEADO**. Restrição fixa: **K2 não é dispensado** (2830 E2) — qualquer resolução futura precisa executá-lo com identidade admin real, sem claims injetadas no LIVE e sem commit sob FREEZE. A resolução está registrada acima (D-1 DECIDIDA); este protocolo não altera a 2830 v7.0 nem a obrigatoriedade de P14 e K2. | fechamento do Batch 12 / UNFREEZE |
| D-2 | Aceitar AD-2 (tempo medido no LIVE para só-leitura; limites duros para escrita) **somente como adaptação operacional** dos envelopes: **não** substitui o cumprimento de P9b/A2 da 2830 v7.0 e **não** autoriza declarar A2 cumprido. *Redação histórica (v1.0–v1.7 antes da Correção 03):* "no lugar de P9b". | operação dos envelopes sob AD-2; **A2/P9(b) permanece OPEN** — o fechamento contratual depende de alteração formal da especificação (v7.1 ou sucessora), conforme `../EXECUTION-BATCHES.md` · *2026-10-03 (v1.8): alteração formal feita pela v7.2 — P9(b)′ CLOSED; D-2 não vira cumprimento da v7.0; A2′ OPEN (P9a)* |
| D-3 | **DECIDIDA — opção (b) aprovada por Fabrício (`BATCH12-2830-D3-A5-DECISION-CLOSEOUT-01`).** E01 sem `SET LOCAL lock_timeout`, blob `c4118b8c…` preservado. Risco aceito: espera por lock limitada só pelo `statement_timeout` (120 s observados). Aceite do E01 inalterado (5.3). D-4 continua obrigatório. Ver 5.1 item 2. | Etapa 3 (resolvida; não autoriza a Etapa 3) |
| D-4 | Se `lock_timeout` da sessão MCP ≠ `'0'`: corrigir o E99 para comparar com o valor do E00 (mandato de correção) | Etapas 2 e 3 |
| D-5 | Se a visibilidade de `pg_stat_activity` não for provada pelas vias 1–3 da L1: conceder `pg_read_all_stats` ao papel do canal ou mudar o canal (decisão de Fabrício; o agente não altera papéis) | Etapas 1–3 |
| D-6 | Após STOP por pino, se a L2 (diagnóstico) mostrar TRANSPORT/EOL-ONLY: adjudicação e forma da correção dos pinos; a Etapa 1 só recomeça com novo mandato. **Ocorrido na Tentativa 03** (`public.normalize_external_catalog_value`, só CRLF, provado byte a byte). Proposta: AD-8 (normalização nos dois lados), em `LIVE-STAGE1-STOP-ADJUDICATION.md` | Etapas 1–3 |
| D-9 | **APROVADA por Fabrício (`BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01`), restrita aos envelopes atuais.** L4 executada (`…-L4-EVENT-TRIGGER-INVENTORY-01`, leitura válida). As 6 exceções foram incorporadas à `evt_allowlist` com identidade de 12 atributos e justificativa (a)–(f). **Não** é autorização genérica para novas operações ou migrations | — (resolvida) |
| D-7 | Aceite de AD-3 a AD-10 | registro formal |
| D-8 | Mandato de cada etapa (1, 2 e 3), separados | cada etapa |

---

## 9. Riscos residuais (mesmo com o protocolo seguido)

1. **Escrita no LIVE sob FREEZE.** O E01 escreve de verdade, por milissegundos. A garantia é estrutural e tripla, mas não existe mais um ambiente descartável como última barreira.
2. **Rollback provado por contagem e marcador, não por varredura total.** Fixtures fora das colunas marcadas não existem neste envelope (a leitura do E01 confirma), mas a prova é pelo que o harness conhece.
3. **Caminhos PL/pgSQL não executados** permanecem só verificados estaticamente (C-5).
4. **Equivalência ARE × modelo Python** do P7 não é provada; divergência tende a STOP. Um falso PASS exigiria o padrão LIVE deixar de detectar uma chamada que o modelo detecta — mitigado pela conferência humana de `d_p7_*` contra o corpo do repositório, byte-idêntico ao LIVE quando os pinos conferem.
5. **Pinos md5 do repositório** podem divergir do LIVE por EOL (C-1). O resultado é STOP e adjudicação, com atraso de uma rodada, nunca PASS indevido.
6. **O canal é caixa-preta.** SQLSTATE custom, truncamento e modo só-leitura só são conhecidos executando (Etapas 1–2).
7. **Sem medição prévia de tempo** para envelopes que escrevem. Hoje o risco é baixo (E01 leve); cresce nas seções pesadas futuras.
8. **Batch 12 aberto e UNFREEZE bloqueado** até K1/K2/K8b serem aceitos no CN-1 (D-1 decidida em 2026-10-01; P14 ainda não homologado); K2 segue obrigatório. *(2026-10-04: K1/K2/K8b aceitos, P14 CLOSED, E1, E2 e E3 CLOSED; E4 SATISFIED pela autorização formal de Fabrício; Batch 12 CLOSED; UNFREEZE COMPLETED; NEXT = canary real pós-UNFREEZE.)*

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-26, `BATCH12-2830-LIVE-VALIDATION-READINESS-01`).** Protocolo de validação progressiva no LIVE após a decisão do proprietário de não criar ambiente isolado: Etapa 1 (só SELECT: E00 ×2, L1 canal, L2 pinos bruto × EOL, L3 concorrência), Etapa 2 (E00 → E02 → E99), Etapa 3 preparada como mandato futuro (E01 com JIT, rollback estrutural e prova tripla, limites de tempo, STOP e incidente). Divergências DIV-1 a DIV-4 sinalizadas; adaptações AD-1 a AD-9 propostas sem alterar a 2830 v7.0; decisões D-1 a D-8. Nenhum SQL executado. |
| 1.1 | **Correção documental (2026-09-26, `BATCH12-2830-LIVE-VALIDATION-READINESS-CORRECTION-01`).** (1) L1: a visibilidade de `pg_stat_activity` exige superusuário, `pg_read_all_stats` ou controle positivo explícito (`visible_foreign_sessions ≥ 1`, sessão de papel alheio com `state` visível); `activity_rows_state_hidden = 0` passa a ser só diagnóstico. (2) S1.4/L2: executada somente após STOP por pino, só para diagnóstico; a etapa permanece em STOP, sem continuidade automática; L2 removida do critério de aceite. (3) Critério P7: o conjunto de identidades distintas (`schema.nome(args)`) das funções não nativas alcançadas no escopo do gate deve ser igual às 12 identidades da allowlist; `pg_catalog` excluído da comparação; identidade a mais ou a menos = STOP. (4) D-1 registrada como PENDENTE, Batch 12 ABERTO, UNFREEZE BLOQUEADO, K2 não dispensado; removidas as opções que redefiniam D1–D4/E2. SQL dos envelopes, 2830 e decisões D-2 a D-8 preservados. Nenhum SQL executado. |
| 1.2 | **Reconciliação (2026-09-26, `BATCH12-2830-LIVE-STAGE1-EXECUTION-READINESS-01`, baseline `1f3b72dc`).** Decisão do proprietário, DIV-1 e D-1 alinhados à decisão refinada: ambiente isolado **pago recusado**; alternativa isolada **sem custo** **PENDENTE** em D-1, com P14 obrigatório. Nenhum critério, consulta, sequência ou STOP das etapas alterado. O roteiro operacional da Etapa 1 está em `LIVE-STAGE1-RUNBOOK.md`. |
| 1.3 | **Alinhamento (2026-09-26, `BATCH12-2830-LIVE-STAGE1-READINESS-CLOSEOUT-01`).** §3.2 (L3: objetivo, resultado esperado e "Como validar") e §6.3: qualquer outra sessão `client backend` ativa ou em transação implica **STOP**, mesmo identificada como plataforma; a classificação nominal é exclusivamente diagnóstica; `g_no_concurrency = true` segue obrigatório. Elimina o conflito A-4 do roteiro da Etapa 1. SQL e md5 de L1/L2/L3 inalterados; nenhum outro critério alterado. |
| 1.4 | **Ajuste referencial (2026-09-26, `BATCH12-2830-LIVE-STAGE1-READINESS-CLOSEOUT-02`).** §3.2 (L3, "Como validar"): removida a menção a "query curta", porque a L3 não retorna o texto da query. A classificação nominal passa a citar só os campos efetivamente retornados. Nenhum SQL, md5, critério ou STOP alterado. |
| 1.5 | **Correção local (2026-09-26, `BATCH12-2830-LIVE-STAGE1-STOP-ADJUDICATION-01` → `BATCH12-2830-STOP-ADJUDICATION-CORRECTION-01`), não commitada, pendente de auditoria.** Após o STOP da Tentativa 03:<br>• §3.3: critérios de EOL (D-6, opção A com o bruto como evidência) e de event triggers (D-9: completude, identidade de 12 atributos, justificativa não vazia).<br>• §3.4: `g_p7_no_ddl`, `g_evt_inventory_complete`, `g_evt_ddl_only` e `g_evt_all_adjudicated`.<br>• §6.1 C-1 atualizado (CRLF ocorrido); §6.2 com event triggers da plataforma.<br>• §7: AD-8 reescrita e AD-10 nova. §8: D-6 atualizada, D-9 nova, D-7 passa a cobrir AD-10.<br>• Tabela de artefatos com o blob vigente do E00.<br>2830 v7.0 inalterada. |
| 1.6 | **D-9 aprovada e incorporada localmente (2026-09-27, `BATCH12-2830-D9-EVENT-TRIGGER-ALLOWLIST-01`), não commitada, pendente de auditoria.** AD-10 e D-9 registradas como APROVADAS, restritas aos envelopes atuais, sem autorização genérica para novas operações ou migrations. §3.3 com a `evt_allowlist` de 6 linhas e a tabela de artefatos com o blob vigente do E00. 2830 v7.0 inalterada. |
| 1.6.1 | **Registro da decisão D-3/A5 (2026-09-27, `BATCH12-2830-D3-A5-DECISION-CLOSEOUT-01`, baseline `d320bd85`), local, sem alterar SQL.** Opção (b) aprovada:<br>• E01 sem `SET LOCAL lock_timeout`, blob `c4118b8c…` preservado;<br>• risco aceito: espera por lock limitada só pelo `statement_timeout` (120 s observados);<br>• aceite do E01 inalterado (`elapsed_ms ≤ 60000`, rollback integral, E99 sem resíduo);<br>• D-4 obrigatório: `lock_timeout ≠ '0'` na L1 ⇒ STOP antes do E01, sem alteração automática de sessão;<br>• Etapa 3 depende de mandato independente e autorização expressa de escrita transitória sob FREEZE.<br>§5.1 item 2 e §8 (D-3) atualizados. Versão normativa referida pelo roteiro permanece v1.6. |
| 1.7 | **Decisão D-1 (2026-10-01, `BATCH12-PHASE6-D1-CN1-DECISION-AND-P14-READINESS-01`, baseline `dd96e8ff`), só documental.** D-1 = CN-1 / I-L (Supabase local via CLI + Docker, sem custo), ambiente isolado oficial para P14a/b/c, K2, K1 e K8b; P9b/A2 fora do escopo. Cabeçalho, estado registrado, AD-1, §8 (D-1) e risco 8 atualizados. Closeout (`…-CLOSEOUT-01`): Status passa a refletir a v1.7; S-A registrada na linha D-1; removida a frase histórica que negava a resolução. Correção 02 (`…-CLOSEOUT-CORRECTION-02`): AD-2 deixa de afirmar A2 cumprido (AD-2 não cumpre A2 nem satisfaz E1; A2/P9(b) OPEN); cabeçalho distingue baseline original (`97380747`) e baseline da v1.7 (`dd96e8ff`); §1 deixa de tratar a adoção da alternativa sem custo como condicional. Correção 03 (`…-CLOSEOUT-CORRECTION-03`): §8 D-2 alinhada à AD-2 — adaptação operacional apenas, não substitui P9b/A2 nem autoriza declarar A2 cumprido; A2/P9(b) OPEN. P14 não executado; K1/K2/K8b seguem bloqueados até P14 homologado. Etapas, consultas, critérios e 2830 v7.0 inalterados. |
| 1.8 | **Sucessora v7.2 de A2/P9(b) (2026-10-03, `BATCH12-PHASE6-A2-P9B-V72-FORMALIZATION-01`, baseline `e0a011d`), só documental.** Status, Autoridade, AD-2 e D-2 passam a apontar para `../2830-V7.2-SUCCESSOR-A2-P9B.md`: a lacuna contratual de P9(b) foi tratada formalmente (P9(b)′ CLOSED por adjudicação sucessora, sem nova execução). AD-2/D-2 preservadas como fato histórico; **não** viram cumprimento de P9(b)/A2 v7.0 (NOT SATISFIED AS WRITTEN). P9a, A2′ e E1 OPEN. Etapas, consultas, critérios operacionais e 2830 v7.0 inalterados. |
| 1.9 | **Sucessora v7.3 de 6.1 (2026-10-03, `BATCH12-PHASE6-6.1-V73-FORMALIZATION-01`, baseline `4f9753d`), só documental.** Status e Autoridade passam a apontar para `../2830-V7.3-SUCCESSOR-6.1.md`: 6.1′ CLOSED com a evidência já versionada do P9A-03/P9A-00 (2026-09-27); 6.1 v7.0 NOT SATISFIED AS WRITTEN; 6.2 OPEN; D5 OPEN/PARTIAL. Nenhum EXPLAIN novo, nenhuma alteração de índice. Etapas, consultas, critérios operacionais, 2830 v7.0 e v7.2 inalterados. |
| 1.10 | **Reconciliação de estado (2026-10-04, `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01`, concluída em `BATCH12-E1-HANDOFF-REGISTRATION-CLOSEOUT-01`, baseline `b95f57e`), só documental.** Status, linha Batch 12, §1 ("Estado registrado") e §9 item 8 passam a registrar: CN-1 executado; P14(a) CLOSED pela nova captura LIVE `PASS_EXACT` 31/31 (`LIVE-P14A-EXECUTION-RECORD.md`); P14(b1)/(b2)/(c)/(d)/(e) CLOSED; K1/K2/K8b executados e D1–D4 CLOSED; P9(a)/A2′/Fase 6 CLOSED; E1 CLOSED (A/B/C/D registrados em EXECUTION-BATCHES, HANDOFF v1.21 e log); E2 CLOSED; próxima frente = E3 JIT. Fatos históricos preservados como texto anterior. Queries L1/L2/L3, md5 e critérios operacionais inalterados. |
| 1.11 | **E3 CLOSED (2026-10-04, `BATCH12-E3-INDEPENDENT-CLOSEOUT-01`), só documental.** Revisão nova porque a v1.10 já estava publicada (`e1ac679b`). Status, linha Batch 12, §1 ("Estado registrado") e §9 item 8 passam a registrar: E3 CLOSED (E3 JIT com L1, L3 inicial, E00 e L3 final PASS; S3 por adjudicação independente — `action_log` +2 fora do FREEZE-CANON; `LIVE-E3-JIT-EXECUTION-RECORD.md`); próximo = decisão formal de UNFREEZE por Fabrício; E4 descrito como critério contratual de autorização, não etapa operacional. Queries L1/L2/L3, md5 e critérios operacionais inalterados. |
| 1.12 | **UNFREEZE formal (2026-10-04, `BATCH12-FORMAL-UNFREEZE-CLOSEOUT-01`), só documental.** Revisão nova porque a v1.11 já estava publicada (`1c10ef23`). Status, FREEZE, linha Batch 12, §1 e §9 item 8 passam a registrar: Fabrício autorizou formalmente o UNFREEZE (`UNFREEZE-AUTHORIZATION-RECORD.md`); E4 SATISFIED; Batch 12 / `2830` CLOSED; FREEZE encerrado; UNFREEZE COMPLETED; canary não executado; NEXT = canary real pós-UNFREEZE. Queries L1/L2/L3, md5 e critérios operacionais inalterados. |
