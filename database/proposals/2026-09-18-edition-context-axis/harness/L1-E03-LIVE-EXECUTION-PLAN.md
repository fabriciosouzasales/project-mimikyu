# 2830H — Lote L1: plano operacional de execução LIVE do E03

| Campo | Valor |
|---|---|
| **Documento** | `BATCH12-2830-P5-L1-E03-LIVE-EXECUTION-PLAN-01` (2026-09-27), baseline HEAD `d65c758345cd2d168a442ebfb89292c6297ae65b`. |
| **Natureza** | Plano operacional definitivo do E03. **Não é executável sem mandato específico de Fabrício.** Nenhum SQL foi executado para prepará-lo, nem SELECT; nenhum acesso ao LIVE. Nenhum envelope, protocolo, roteiro ou contrato alterado. |
| **Estado** | **AGUARDANDO AUDITORIA INDEPENDENTE E AUTORIZAÇÃO DE FABRÍCIO PARA EXECUÇÃO LIVE** (§13). E03 blob `ef24a3be…` **autorizável, ainda não autorizado**; **não executado**. Cobertura LIVE **17/135** (30/135 só potencial). **FREEZE ATIVO.** |
| **Autoridade normativa** | `L1-E03-LIVE-EXECUTION-READINESS.md` **v1.2** (blob `9080f2ad…`): decisões (§4), identidade e resposta esperada (§5.2), sequência (§5.3), postcheck e classificação (§5.4), riscos (§5.5), DP-4 = A (§5.6), `55P03` (§5.7). Classificação: `L1-EXECUTION-READINESS.md` **v1.3** (blob `76cca828…`) §4.4–§4.5 e §5, aplicada ao E03 pela readiness do E03. Este plano **não cria critério nem classe**: consolida como cumpri-los. Em divergência, prevalecem as readiness. |
| **Demais autoridades** | 2830 v7.0 (blob `b4647dcb…`, imutável) · `LIVE-VALIDATION-PROTOCOL.md` (`abe806d6…`) · `LIVE-STAGE1-RUNBOOK.md` (`9f454a96…`, textos L1 e L3) · `L1-E03T-LIVE-EXECUTION-PLAN.md` (`f71e6b38…`, precedente de forma) · `LIVE-L1-E03T-EXECUTION-RECORD.md` v1.1 (`eaffdb27…`, precedente de captura e de preparação do E99). |
| **Papéis** | **Claude**: executor. **ChatGPT**: auditor independente. **Fabrício**: autorizações, commit e push. |

---

## 0. Gate de entrada desta preparação (E, local, sem banco)

| Item | Verificação | Resultado |
|---|---|---|
| HEAD | `git rev-parse HEAD` | `d65c758345cd2d168a442ebfb89292c6297ae65b` = baseline ("feat: implement audited E03 transactional lock timeout") |
| Árvore e índice | `git status --porcelain --untracked-files=all`; `git diff --cached --name-only` | 0 e 0 linhas antes desta rodada |
| Commits | `git log --oneline -3` | `d65c758` → `aeeed59` → `a83f539`; nenhum commit inesperado. O `d65c758` contém exatamente os 6 arquivos da rodada DP-4 = A (E03, `static_check`, readiness de implementação v1.3, readiness do E03 v1.2, README, `docs/log.md`) |
| Blobs | `git hash-object` = `git ls-tree HEAD`, todos os arquivos do `harness/` | iguais (§3) |
| `static_check` | `python3 tools/static_check.py` | `TOTAL 444 PASS 444 FAIL 0` · `E03-PERFIL TOTAL 88 PASS 88 FAIL 0` · `E03-VERIFICADOR-NEG TOTAL 79 PASS 79 FAIL 0` · `E03-VERIFICADOR-POS TOTAL 6 PASS 6 FAIL 0` |
| Contrato 2830 | blob e último commit do arquivo | `b4647dcb…`; último commit `cab1495` ("define Batch 12 Edition Context validation contract"), inalterado |
| E03T | registro e auditoria | `LIVE-L1-E03T-EXECUTION-RECORD.md` v1.1 publicado (`eaffdb27…`, modo 100644): CONFORME (diagnóstico), auditoria independente PASS |
| Readiness do E03 | publicação | v1.2 publicada em `d65c758` (`9080f2ad…`) |
| L1 / L3 | md5 recalculado dos blocos do roteiro | `0836c36a8d3749b1e7718223e064caf9` (2.458 B) e `b7bc3700aeef278f6a79bd30e6a8d229` (1.526 B) |

**STOP: não houve.** Nenhuma divergência material.

## 1. Decisões vinculantes (texto integral na readiness do E03 §4; só para o E03)

| Decisão | Conteúdo | Efeito operacional |
|---|---|---|
| **DP-1 = A** | AD-2 exclusiva do E03: tempo medido no próprio LIVE; `statement_timeout = '2min'` comprovado na L1 da rodada; aceite só com `elapsed_ms ≤ 60000`. P9b e A2 **não** atendidos literalmente. `elapsed_ms = 133` do E03T não é medição do E03 | S1 exige `'2min'`; §5: `elapsed_ms > 60000` ⇒ NÃO CONFORME |
| **DP-4 = A** | `SET LOCAL lock_timeout = '5s'` como primeira instrução executável do `DO`, seguido de asserção fail-closed (`H283F caso=PREFLIGHT lock_timeout=…`) | S1 exige `lock_timeout = '0'` **na sessão**; o `'5s'` existe só dentro da transação do envelope. §5 distingue `55P03` capturado × original |
| **DP-5 = A** | escritas transitórias **exclusivamente** do blob `ef24a3be…`: 65 INSERTs, 4 UPDATEs, 1 DELETE, 9 selos efetivos, 2 tentativas que falham, 33 subtransações, só nas três tabelas EC; rollback obrigatório e verificação posterior (E99 + L3 final); condicionadas a mandato operacional próprio | uma única submissão; nenhuma outra escrita |
| **`MAX_L3_D = 2`** | até duas L3 diagnósticas, só leitura, só no fluxo excepcional; sem retry do E03 | §6 |
| **Reconhecimento contratual = SIM** | proposta de `2.1–2.5, 2.7–2.14 PASS` só depois de CONFORME + postcheck ÍNTEGRO + auditoria independente | §8, §11 |
| **Cobertura** | atual **17/135**; potencial após o E03 **30/135** | nunca antecipada (§8) |

Nenhuma delas se estende a outro lote. DP-1 = A′ e DP-4 = B do E03T não se aplicam ao E03.

## 2. Condições de entrada do mandato de execução (todas)

1. Mandato de execução **próprio e expresso** de Fabrício (T-6), citando este plano e a readiness do E03 v1.2 pelo blob, e declarando o **baseline HEAD** da rodada.
2. Neste baseline: este plano publicado (commit e push por Fabrício) **com parecer da auditoria independente**, e os blobs do §3 inalterados.
3. `MAX_L3_D = 2` (já decidido; o mandato só o confirma).
4. Canal: MCP Supabase `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`. Uma chamada = um statement. Nunca Dashboard, nunca `apply_migration`, nunca outro canal ou ferramenta.
5. FREEZE ativo e nenhuma mudança conhecida no ambiente desde o E03T (deploy, migration, importação, alteração de papel ou de configuração). Qualquer mudança conhecida ⇒ não iniciar.
6. Autoria: Claude executa; ChatGPT audita; Fabrício autoriza, faz commit e push.

## 3. Identidade dos textos a submeter

| Passo | Texto | Identidade exigida |
|---|---|---|
| S1 | L1 (`LIVE-STAGE1-RUNBOOK.md` §3.1, bloco literal) | md5 `0836c36a8d3749b1e7718223e064caf9`, 2.458 B |
| S2, L3-D, S7 | L3 (`LIVE-STAGE1-RUNBOOK.md` §3.2, bloco literal) | md5 `b7bc3700aeef278f6a79bd30e6a8d229`, 1.526 B |
| S3 | `2830H_E00_precheck_inventory.sql`, integral | blob `a4dd84381b928727611a51147ba1a4c1d11b89ab` · md5 `45b6c35cca849ffbf49d22ec18e8283c` · sha256 `2a9539fb48d2d8231da59240b7c9d8fe4aa5fe6201e97335cd2a0e8ec9009a8a` · 53.803 B |
| S4 | `2830H_E03P_precheck_section2.sql`, integral | blob `0fc2d83dff599fc6cc26e35399ebc519a5a51d0f` · md5 `10457d87d4c25c93ab04d0fadf43dddc` · sha256 `3f0e540939e2528aae70fabf7c1a83aaa07421bf30a529710ea6b12c4bc68c5d` · 13.335 B |
| **S5** | **`2830H_E03_section2_profile_composition.sql`, integral, uma única submissão** | blob **`ef24a3be7d7fd2f1081b1d13e6bf2d000d451d7e`** · md5 `e0aeb7e3dc4143d171cb4364d99069d8` · sha256 `e2949dc65a8215800af05bac209b5745287a755ad9e6a488e2ed00d08ce5215e` · 93.188 B · 1.772 linhas. O blob `4866eb97…` está **superado** e nunca pode ser submetido |
| S6 | E99 gerado de `2830H_E99_postcheck_residue.sql` com os 3 valores do S3 **desta** rodada (§7) | base: blob `49a71ecb4525697858110ee71a3f61f5eee74a34` · md5 `f0b91183a8649b990b080637dd56e74b` · sha256 `63f7e2e7fa2bd10fdd9bdd963e5e672d187580694bc467dabd1bc5af7165a66a` · 12.289 B; texto final difere só nas linhas 56–58; md5 registrado **antes** da submissão |
| S0 | `tools/static_check.py` | blob `79c4fd42335567caaac436370633c0302875e7d3` · md5 `052748be05f12636021ce0626090313e` · sha256 `759b8fe1eea946e5540f15a5715f875ce30b3a71a74f09538de93be5f8467b9c` · 99.493 B |
| — | contrato 2830 v7.0 (não submetido) | blob `b4647dcb59432405c8157e2733fd78678f35540e` · md5 `7d816d18bf6376c1fc29bc91c8bee2e9` |
| — | readiness do E03 v1.2 / readiness v1.3 (não submetidas) | `9080f2ad22b980322c31206f4dd2188cc7878b3a` / `76cca8281abc4ac3069e9bff611d8cd06a345a48` |

Nenhum SQL é reproduzido neste plano: os textos são os blobs acima, submetidos sem edição. Qualquer divergência de hash ⇒ não conectar (S0) ou não submeter (demais passos).

## 4. Matriz S0–S7

Sequência normal: `S0 → S1/L1 → S2/L3 → S3/E00 → S4/E03P → S5/E03 → S6/E99 → S7/L3 final`. Nenhuma outra chamada SQL entre elas; entre chamadas, só conferência local da resposta anterior.

| Passo | Texto | CONTINUE se (todos) | STOP se | Evidência a capturar | Falha ou resposta ambígua |
|---|---|---|---|---|---|
| **S0** | local, sem banco | HEAD = baseline do mandato; árvore e índice limpos; blobs e md5 do §3 conferidos (`git hash-object`, `md5sum`); `static_check` `444/444`, `88/88`, `79/79`, `6/6`; md5 de L1 e L3 recalculados | qualquer divergência; mandato sem baseline, sem citar este plano ou sem os blobs | saída integral de `git` e `static_check`; horário local só como referência | não conectar; STOP |
| **S1** | L1 | `transaction_read_only = off`; `default_transaction_read_only = off`; `in_recovery = false`; **`lock_timeout = '0'`** na sessão; **`statement_timeout = '2min'`**; `server_version_num ≥ 170000`; `standard_conforming_strings = on`; donos das 5 tabelas EC = `current_user` (ou superusuário); visibilidade provada (`is_superuser`, `reads_all_stats` ou `visible_foreign_sessions ≥ 1`) | qualquer critério falso; réplica; read-only; `lock_timeout ≠ '0'` (D-4); `statement_timeout ≠ '2min'` (DP-1); visibilidade não provada | JSON integral; `checked_at`, `backend_pid`, `current_user` | resposta incompleta, erro ou ambígua ⇒ STOP; não submeter o E00; nada foi escrito |
| **S2** | L3 | `locks_on_scope = []`; nenhuma outra sessão `client backend` em `active`, `idle in transaction` ou `idle in transaction (aborted)` | lock no escopo; sessão em transação; resposta incompleta | JSON integral; `checked_at` | STOP; não submeter o E00 |
| **S3** | E00 | resposta completa; `gate_pass = true` com os 24 gates `true` (incl. `g_no_residue`, `g_no_sequences_touched_now`, `g_rls_bypass`, `g_no_concurrency`, `g_freeze_canonical_equal`); `d_canon_diff = []` | gate falso ou `NULL`; `d_canon_diff ≠ []`; resposta incompleta | JSON integral; `d_baseline` **na forma literal do canal**, `d_baseline_md5`, `d_session.db_role_setting_rows`, `checked_at`, `backend_pid` | STOP; não submeter o E03P. Repetição só pelo protocolo §3.4 (`g_no_concurrency`), com L3 e E00 novos |
| **S4** | E03P | resposta completa; `gate_pass = true` e os 11 gates `true`: `g_s2_triggers`, `g_s2_constraints`, `g_s2_function_pins`, `g_s2_error_tokens`, `g_deferrable_only_seal`, `g_seal_constraint_names_unique`, `g_no_other_triggers_l1`, `g_game_pokemon_one`, `g_nn_no_sequence`, `g_nn_rls_bypass`, `g_marker_absent_now` | gate falso ou `NULL`; resposta incompleta | JSON integral; `d_session.checked_at` | STOP; não submeter o E03. Nada foi escrito: E99 não é necessário, mas é recomendado só para registro |
| **S5** | **E03**, uma chamada, logo após conferir o S4 | resposta **definida** (SQLSTATE e texto do PostgreSQL, ou retorno sem erro) | ver §5: qualquer resposta diferente de `H283P` conforme | resposta integral do canal, sem edição (`HttpException` inclusive): SQLSTATE, mensagem, `CONTEXT` | **definida** ⇒ §5; **ambígua** ⇒ §6; **nunca** reenviar |
| **S6** | E99 preparado conforme §7 | resposta completa; `gate_pass = true` (9 gates), `d_diff = []`, `d_canon_diff = []`, `g_marker_absent = true`, `g_captured_integrity = true`, `g_lock_timeout_default = true`, `g_role_setting_unchanged = true`, `d_baseline_now_md5 = d_baseline_md5` do S3 | qualquer critério falso ou `NULL`; erro; incompleto | texto submetido (md5, bytes) e JSON integral; `checked_at`, `backend_pid` | classificação da readiness v1.3 §4.4–§4.5, linhas (1)–(3); **sem reenvio** do E99 |
| **S7** | L3 final, **sempre depois** do S6 | resposta completa; `locks_on_scope = []`; nenhuma sessão ativa ou em transação; nenhum pid desta rodada | lock ou sessão no escopo; incompleta | JSON integral; `checked_at` | classificação da readiness v1.3 §4.5, linhas (4); **sem reenvio**; sem `pg_terminate_backend` |

**Ordem temporal a registrar:** `checked_at(L1) < checked_at(L3) < checked_at(E00) < checked_at(E03P) < S5 [< checked_at(L3-D)…] < checked_at(E99) < checked_at(L3 final)`. O canal não devolve horário para erro: a posição do S5 vem da sequência registrada.

## 5. Controles da resposta do E03 (S5)

**Aceite da resposta** (readiness do E03 §5.2), todos, conferidos localmente:

| # | Controle | Exigência |
|---|---|---|
| R-1 | SQLSTATE | `H283P` |
| R-2 | mensagem, não truncada | casa com `^H2830_ROLLBACK_PASS: envelope=E03_SECAO2_COMPOSICAO_PROFILE pass=13/13 casos=2\.1,2\.2,2\.3,2\.4,2\.5,2\.7,2\.8,2\.9,2\.10,2\.11,2\.12,2\.13,2\.14 marker=H2830_[0-9A-F]{32} elapsed_ms=[0-9]+$` |
| R-3 | `pass` | `13/13` |
| R-4 | casos | exatamente os 13, nessa ordem, cada um uma vez; `2.6` ausente |
| R-5 | marcador | `H2830_` + 32 hexadecimais maiúsculos (formato de `v_marker`, l. 70); registrado como elo E00 → E03 → E99 |
| R-6 | contexto | `PL/pgSQL function inline_code_block line 1703 at RAISE` (RAISE terminal l. 1767, `DO` l. 65) |
| R-7 | tempo | `elapsed_ms ≤ 60000` (DP-1 = A) |

**`H283P` isoladamente não constitui aceite.** Um S5 com R-1 a R-7 é só a primeira condição do CONFORME (§8).

**Distinção das respostas** (classes e ações da readiness v1.3 §4.5 e da readiness do E03 §5.4 e §5.7; nenhuma classe nova):

| Resposta observada | Como reconhecer | Linha aplicável | Ação |
|---|---|---|---|
| `H283P` conforme | R-1 a R-7 | "`H283P` conforme" ⇒ CONTINUE | S6 e S7; aceite só com postcheck ÍNTEGRO |
| `H283P` com `elapsed_ms > 60000` | R-1 a R-6, falha R-7 | "`elapsed_ms` acima do limite de DP-1" ⇒ **NÃO CONFORME** | S6, S7; registrar; STOP; não repetir |
| `H283P` com `pass ≠ 13/13` ou mensagem truncada | falha R-2/R-3 | "mensagem truncada, SQLSTATE ausente ou `pass ≠ n/n`" ⇒ **INCONCLUSIVO** | S6 imediato, S7; STOP; nunca conforme |
| `H283P` com lista de casos, marcador ou contexto divergentes (R-4, R-5 ou R-6) | falha só R-4/R-5/R-6 | **não conforme ao §5.2**; nunca CONFORME. A readiness não traz linha nominal para este caso (lacuna G-1, §12.3) | S6 imediato, S7; STOP; classificação pela regra "mais grave aplicável" com o postcheck, e adjudicação no registro |
| `H283F caso=PREFLIGHT lock_timeout=<v> (esperado 5s)` | asserção P8 falhou, antes de qualquer leitura ou escrita | "`H283F`" ⇒ **NÃO CONFORME**; STOP explícito da readiness do E03 §5.4 | S6 imediato, S7; STOP; sem retry |
| `H283F caso=PREFLIGHT game code=POKEMON count=…` | preflight de `game` falhou, antes de escrita | "`H283F`" ⇒ **NÃO CONFORME** | idem |
| `H283F caso=GATE …` | concluídos ≠ esperados, ou sondas ≠ 11 | "`H283F`" ⇒ **NÃO CONFORME** | idem |
| **`55P03` capturado** | `H283F` com `sqlstate=55P03` em `caso=<id> erro inesperado …`, `sonda n=… modo não DEFERRED ou erro inesperado …` ou `rejeição errada …` | "`H283F`" ⇒ **NÃO CONFORME** (readiness do E03 §5.7) | S6 imediato, S7; STOP; sem retry |
| outro `H283F` | qualquer outra mensagem `H2830_FAIL` (asserção de caso, sonda, selo, negativo aceito) | "`H283F`" ⇒ **NÃO CONFORME** | idem |
| **`55P03` original** | SQLSTATE `55P03` no próprio `ERROR` (espera de lock estourada fora de handler: leituras de preflight de `game`, antes do primeiro caso) | "outro SQLSTATE, `57014`, `55P03`, `25006`" ⇒ **NÃO CONFORME** | S6 imediato, S7; STOP |
| **`57014`** | SQLSTATE `57014` (`statement_timeout` de 120 s). `WHEN OTHERS` do PL/pgSQL não captura `query_canceled`, então chega sempre com o SQLSTATE original, de qualquer ponto do envelope (documentação do PostgreSQL; E, não observado) | idem ⇒ **NÃO CONFORME** | S6 imediato, S7; STOP |
| erro inesperado | qualquer outro SQLSTATE com texto do PostgreSQL (`P0001`, `23505`, `25006`, `42601`, etc.) fora de `H283x` | "outro SQLSTATE" ⇒ **NÃO CONFORME** | S6 imediato, S7; STOP |
| retorno sem erro (`[]`) | o `DO` terminou normalmente | "retorno `[]`" ⇒ **NÃO CONFORME, defeito grave** | S6 imediato, S7; STOP; INCIDENTE se houver resíduo |
| **resposta ambígua do canal** | timeout do cliente, perda de conexão, HTTP sem corpo, erro do canal sem texto do PostgreSQL | "timeout do cliente ou queda de conexão" / "resposta ambígua" ⇒ **INCONCLUSIVO** (teto) | **fluxo excepcional (§6)**; nunca S6 direto; nunca reenviar |

- **`lock_timeout`, rollback, postcheck e classificação** seguem integralmente a readiness do E03 §5.4–§5.7 e a readiness v1.3 §4.4–§4.5: o `SET LOCAL` é transacional e desfeito pelo término sempre em exceção; a não persistência fora da conexão do envelope é provada por `g_lock_timeout_default` e `g_role_setting_unchanged` no E99 e pela prova estática E03-20; a classificação final é a mais grave aplicável, INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME.
- Toda falha com postcheck ÍNTEGRO fica **NÃO CONFORME**; com `d_diff ≠ []`, marcador presente ou violação do FREEZE, **INCIDENTE**; com postcheck NÃO CONCLUÍDO, **INCONCLUSIVO**. Vale igualmente para `H283F`, `55P03` original e `57014`.

## 6. Fluxo excepcional — resposta ambígua do S5, `MAX_L3_D = 2`

`S5 (ambígua) → L3-D₁ [→ L3-D₂] → S6/E99 → S7/L3 final`, **só** com encerramento comprovado.

1. **Nunca reenviar o E03.** Nenhum `pg_terminate_backend`, nenhuma limpeza corretiva, nenhum outro SQL.
2. **L3-D₁:** a mesma L3 (md5 `b7bc3700…`), só leitura. É diagnóstico: não é postcheck, não sustenta resíduo zero e não substitui o S7.
3. **Encerramento comprovado** (todos): resposta completa; `locks_on_scope = []`; nenhuma sessão `client backend` em `active`, `idle in transaction` ou com `xact_start`/`backend_xid` além da própria consulta. O canal não devolve o pid do E03: qualquer sessão ativa ou em transação, ou qualquer lock no escopo, impede a confirmação.
4. **Confirmado na L3-D₁:** S6 (E99) e depois S7 (L3 final). A rodada é **no máximo INCONCLUSIVA**, qualquer que seja o postcheck; com resíduo ou marcador no E99, **INCIDENTE**.
5. **Não confirmado na L3-D₁:** **L3-D₂**, só leitura, sem **nenhum** outro SQL entre as duas. Confirmado na L3-D₂: item 4.
6. **Não confirmado na L3-D₂:** **não** submeter E99 nem S7; **INCONCLUSIVO; resíduo não verificado; STOP**; escalar a Fabrício. Postcheck posterior só com mandato próprio, só leitura e o mesmo `d_baseline` do S3.

Capturar: cada L3-D integral, com `checked_at`, e o número de L3-D usadas (0, 1 ou 2).

## 7. Preparação do E99 (entre S5 e S6, local, sem banco)

Mecânica idêntica à do E03T (registro do E03T §4.1), que é o precedente aprovado:

1. Gravar em arquivo de captura, a partir da resposta do **S3 desta rodada**: `d_baseline` na **forma literal devolvida pelo canal** ("colar, nunca redigitar"), `d_baseline_md5` e `d_session.db_role_setting_rows`.
2. Conferir: nenhum apóstrofo nos valores; `md5(jsonb::text)` do JSON capturado, recalculado localmente (chaves por comprimento e bytes, separadores `", "` e `": "`), igual a `d_baseline_md5`.
3. Gerar o texto por script que substitui só os três literais (`__E00_D_BASELINE__`, `__E00_D_BASELINE_MD5__`, `__E00_ROLE_SETTING_ROWS__`), exigindo exatamente uma ocorrência de cada; cabeçalho intacto.
4. Conferir: o texto difere do blob base só nas linhas 56–58. Registrar md5 e bytes **antes** de submeter.
5. **Nunca** baseline de outra rodada, E00 novo como referência, forma canônica reserializada em lugar da literal, ou edição manual. Divergência em 2–4 ⇒ readiness v1.3 §4.5 linha "(3)": não submeter; regenerar só da mesma saída do S3 e só se a causa for do script; persistindo, STOP.

Se o `d_baseline` do S3 for igual ao das rodadas anteriores (estado estável sob FREEZE), o texto do E99 pode coincidir byte a byte com o já submetido (md5 `00233aa6…`); isso é esperado, mas a origem dos valores continua sendo o S3 desta rodada.

## 8. Postcheck, classificação e efeito contratual

- **Postcheck ÍNTEGRO** (readiness v1.3 §4.4): E99 completo com todos os critérios do S6 **e** S7 completo e limpo. Só então se afirma resíduo zero.
- **CONFORME** exige todos: R-1 a R-7; postcheck ÍNTEGRO; ordem temporal registrada; nenhum evento de STOP.
- **Classificação final:** a mais grave aplicável, **INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME** (readiness v1.3 §4.5). Não reproduzida aqui para não criar segunda fonte.
- **Efeito contratual** (reconhecimento = SIM): um CONFORME permite ao registro **propor** `2.1–2.5, 2.7–2.14 PASS`, **sujeito à auditoria independente**. Até o parecer, a cobertura continua **17/135**; 30/135 nunca é declarado antes disso.
- Qualquer resultado diferente de CONFORME encerra a rodada, impede reenvio do E03 e impede avanço a outro lote.

## 9. Condições inegociáveis

1. Uma chamada SQL por passo, pelo canal autorizado.
2. Uma única submissão do E03; nenhum retry automático, nem do E99 nem do S7.
3. Nenhuma limpeza, `pg_terminate_backend` ou intervenção manual sem mandato próprio e SQL pareado.
4. Nenhum E99 elaborado com baseline de outra rodada.
5. Nenhuma interpretação de `H283P` isoladamente como CONFORME.
6. Nenhum avanço a outro lote por consequência automática do E03.
7. STOP diante de evidência incompleta, divergência de hash, alteração do ambiente ou falha de segurança, semântica, integridade, concorrência ou performance.
8. Nenhum `SET`, `set_config`, `ALTER ROLE`/`DATABASE` ou configuração de sessão fora do preâmbulo P8 já contido no blob.

**STOP adicionais** (readiness do E03 §5.4): blob do E03 ≠ `ef24a3be…`; asserção P8 falha; `55P03` em qualquer ponto; `statement_timeout ≠ '2min'`; qualquer necessidade de alterar SQL, protocolo ou critério.

## 10. Riscos residuais (readiness do E03 §5.5; nenhum novo)

- escrita real no LIVE sob FREEZE, ~6× o volume do E03T, sem ambiente descartável como última barreira; garantia estrutural (todo caminho do `DO` termina em exceção) e prova tripla (mensagem terminal, E99, L3 final);
- tempo sem medição prévia (P9b/A2 não literais); teto duro de 120 s;
- `SET LOCAL` dentro do `DO` nunca executado no LIVE (R); a asserção P8 é a prova de aplicação em runtime;
- limite **L-1**: o T3 provou ausência de contaminação observável, não a remoção do evento diferido; 2.7 (IMMEDIATE depois de sonda, `23505` em índice) nunca executado; divergência = FAIL, nunca PASS;
- `CONSTRAINT_NAME` de violação de índice único = nome do índice: esperado pela documentação, não observado neste harness;
- ramos PL/pgSQL de falha não percorridos num CONFORME: só verificação estática;
- canal caixa-preta (sem pid nem horário do erro; conexão por chamada); cliente pode expirar antes dos 120 s do servidor, o que leva ao §6;
- resíduo não-transacional declarado e não verificado: `pg_stat_*`, tuplas mortas, WAL, XIDs de subtransação, logs com o marcador;
- comentário do cabeçalho do E03 sobre `55P03` simplifica o caso do preflight; prevalece a readiness do E03 §5.7 (só comentário, sem efeito executável).

## 11. Modelo do registro da execução

Documento a criar **somente depois** da execução autorizada, no mesmo ciclo: `LIVE-L1-E03-EXECUTION-RECORD.md`. Não existe registro prévio e nenhum campo abaixo é preenchido por este plano.

| Seção | Campos obrigatórios |
|---|---|
| Cabeçalho | Natureza (caso da 2830, reconhecimento = SIM); Mandato (id, baseline HEAD); Decisões (DP-1 = A, DP-4 = A, DP-5 = A, `MAX_L3_D = 2`); Autorização (texto do mandato, escopo DP-5); Resultado (classe final, marcador, `elapsed_ms`, estado do postcheck, L3-D usadas); Estado (auditoria pendente/PASS; publicação; cobertura: **17/135** até o parecer); Papéis |
| 1. S0 | HEAD; árvore/índice; blob, md5, sha256 e bytes de cada texto do §3; saída do `static_check` (444/88/79/6); md5 de L1/L3; canal |
| 2. Sequência | por chamada: passo, texto (md5), `checked_at`, `backend_pid`, SQLSTATE, resultado; número total de chamadas; ordem temporal conferida; intervalos E00→E99 e L1→L3 final |
| 3. Resposta do E03 | texto literal (`ERROR` + `CONTEXT`) e resposta integral do canal; tabela R-1 a R-7 com observado × exigido; linha aplicável do §5 |
| 4. Postcheck | preparação do E99 (origem, controles 1–4 do §7, md5 e bytes do texto); 9 gates; `d_diff`, `d_canon_diff`; `d_baseline_now_md5` × `d_baseline_md5`; comparação chave a chave; S7; classificação ÍNTEGRO/REPROVADO/NÃO CONCLUÍDO; prova tripla de rollback |
| 5. Classificação final | classe pela regra da readiness v1.3 §4.5, com fundamentação; o que demonstra e o que não demonstra (L-1; ramos não percorridos) |
| 6. Efeito contratual | se CONFORME + ÍNTEGRO: **proposta** `2.1–2.5, 2.7–2.14 PASS`, sujeita à auditoria independente; senão: nenhum efeito. Cobertura declarada: **17/135** até o parecer |
| 7. Incidentes, desvios e limitações | STOP (sim/não, onde); desvios de procedimento; limitações do canal; resíduo não-transacional; relógio local × banco |
| 8. Governança | nada alterado além do registro; sem `git add`/commit/push; autorização DP-5 esgotada; FREEZE ATIVO |
| Apêndices | A: texto exato do E99 submetido (md5); B: saídas integrais de L1, L3, E00, E03P, E03, L3-D (se houver), E99, L3 final |
| Revision History | 1.0 da execução; linha correspondente em `docs/log.md` |

## 12. Quadro de fechamento do Batch 12

Fontes: `EXECUTION-BATCHES.md` (Batch 12), 2830 v7.0 (CRITÉRIOS DE ACEITE, l. 1126–1177), `LIVE-VALIDATION-PROTOCOL.md` §8, `PHASE5-AUTOMATED-COVERAGE-READINESS.md` §3–§5 e §8, registros LIVE do harness, `docs/log.md`.

**Conclusão do E03 ≠ conclusão do Batch 12.** O E03 fecha, no máximo, 13 das 118 posições automáticas restantes (lote L1). O Batch 12 só termina com os critérios A–E da 2830 e o UNFREEZE.

### 12.1 Estado

| Frente | Estado | Evidência |
|---|---|---|
| Batches 1–11 | executados; Batches 7–10 registrados como CLOSED e Batch 11 como "execução concluída · closeout documental registrado" (`2215` e `2216`) | `PACKAGE-STATUS.md`; `EXECUTION-BATCHES.md` |
| 2830 v7.0 | especificação vigente (135 AUTO + 3 HIST + manuais) | blob `b4647dcb…` |
| Harness base | E00, E01, E02, E99, `static_check`, protocolo, roteiro | publicados; reutilizáveis |
| Etapa 1 (E00 só leitura) | READY FOR STAGE 2 (Tentativa 04) | `LIVE-STAGE1-EXECUTION-RECORD.md` |
| **Gates contratuais LIVE aprovados** | **17/135**: D1–D5 (Etapa 2), 1.1–1.12 (Etapa 3) | registros das Etapas 2 e 3 |
| 6.3 (manual) | cumprido (2840 v2.0, 7/7, Batch 10) | 2830 D6 |
| P9a básico | P9A-01 (E00) e P9A-02 (E99) REGISTRADO; não são casos | `LIVE-P9A-EXECUTION-RECORD.md` |
| E03T (diagnóstico) | CONFORME, auditoria PASS, publicado; fora dos 135 | registro do E03T v1.1 |
| **E03 (L1, 13 casos)** | implementado, auditado, publicado (`d65c758`); **pendente de execução** (este plano) | readiness do E03 v1.2 |
| Lotes L2–L13 (105 casos) | não implementados; readiness de implementação e de execução, auditoria e mandatos próprios por lote | Fase 5 §5.4 |
| Evidências históricas C1–C3 (D6–D8) | sem registro de verificação localizado no harness; C1 é local (`git cat-file`), C2/C3 exigem SELECT no LIVE | 2830 C1–C3 |
| Manuais K1, K2, K8b + D4 (paridade) | bloqueados: exigem ambiente isolado com P14; **D-1 PENDENTE**; K2 não dispensável; proposta v7.1 em auditoria, não altera a v7.0 | protocolo §8; `2830-V7.1-PROPOSAL-ADMIN-CONCURRENCY.md` |
| Manuais 6.1 e 6.2 (EXPLAIN) | 6.1 NÃO DEMONSTRADO; 6.2 EVIDÊNCIA — CENÁRIO PEQUENO, aguardando decisão | `INDEX-6.2-ADJUDICATION-READINESS.md` (proposta não aprovada) |
| A2 (medição de tempo) | não cumprido literalmente; **D-2 pendente** (aceite formal de AD-2); só L1 tem DP-1 decidida | protocolo §8 |
| Trilha 960 (DP-6 da Fase 5) | divergência delimitada; não bloqueia lotes; recomendada antes do UNFREEZE | Fase 5 §6 |
| UNFREEZE | **BLOQUEADO** | 2830 E1–E5 |

### 12.2 Dependências obrigatórias até o UNFREEZE (2830 A–E)

| Critério | O que falta | Dependência |
|---|---|---|
| A1 / A5 | mandatos de implementação e execução por lote; decisão de `lock_timeout` por lote | Fabrício |
| A2 | medição de tempo por envelope (P9b) **ou** D-2 aceita; P9a (EXPLAIN) para B, M e 5.x (I-6) | D-2; readiness de seção pesada |
| A3 | precheck por lote (I-1); extensão do fecho P7 para `game`, `card_variant`, job/row (I-4) | DP-3; implementação |
| A4 | constantes de 5.x medidas antes de virar asserção (I-5) | mandato de medição, só SELECT |
| B1–B5 | 135/135 com postcheck verde por envelope; B5 para cada envelope que usar `lock_timeout` | lotes L1–L13 |
| C1–C3 | 3/3 evidências históricas registradas | mandato curto (C1 local; C2/C3 só leitura) |
| D1–D4 | K1, K2, K8b e paridade do ambiente isolado | **D-1** (ambiente isolado sem custo, P14) — hoje o bloqueio crítico |
| D5 | 6.1 e 6.2 registrados | decisão de Fabrício sobre a proposta 6.2 e encaminhamento de 6.1 |
| E1–E5 | tudo acima registrado; K2 aceito; baseline de FREEZE inalterado; mandato formal de UNFREEZE | Fabrício |

### 12.3 Sequência mínima segura

Reutilizando harness, verificadores, protocolo e evidências já aprovados, sem nova implementação onde os artefatos atuais atendem:

| # | Passo | Reutiliza | Novo necessário | Paralelizável com |
|---|---|---|---|---|
| 1 | **Executar o E03** por este plano; registro; auditoria; publicação | E00, E03P, E03, E99, L1/L3, plano | só o registro | 3, 4, 5 |
| 2 | Se CONFORME e auditado: cobertura 30/135 publicada | — | — | — |
| 3 | **D-1** decidida e, se adotado ambiente sem custo, P14 (a, b, c) provado; K1, K2, K8b | 2830 K1/K2/K8b; proposta v7.1 (se aprovada) | ambiente isolado | 1, 4, 5 |
| 4 | Decisões transversais uma vez, para os lotes restantes: D-2 (AD-2 global ou P9b), DP-2 (ordem; L5), DP-3 (precheck por lote × sucessor do E00), DP-4/DP-5 por lote | padrão do L1 (E03P + perfil no `static_check`, preâmbulo P8, matriz de escrita) | nenhum código nesta etapa | 1, 3 |
| 5 | C1–C3 (D6–D8); decisão sobre 6.2 e encaminhamento de 6.1 | blobs 2215/2216; evidências P9a; proposta 6.2 | mandato curto só leitura | 1, 3 |
| 6 | Lotes só-EC sem nova infraestrutura de resíduo: **L2 → L3 → L4**, depois **L8**; **L9** (sem escrita) | E00, E99, padrão E03/E03P/perfil, protocolo S0–S7 | envelope + precheck + perfil por lote | 7 |
| 7 | Infraestrutura I-3/I-4 (sucessor de E99 e fecho P7) para `game`, `card_variant`, job/row; I-5; I-6 | E00/E99 como base | I-3, I-4, I-5, I-6 | 6 |
| 8 | Lotes com nova infraestrutura: **L5, L6, L7, L11, L12**; seções pesadas **L10, L13** | I-3/I-4/I-5/I-6 do passo 7 | envelopes por lote | — |
| 9 | Critérios A–E conferidos; baseline de FREEZE inalterado; mandato formal de **UNFREEZE** | E00 (baseline) | — | — |

- **Caminho crítico:** D-1 (passo 3) — sem ele K1/K2/K8b e D4 são inalcançáveis, e o UNFREEZE também, qualquer que seja o avanço dos lotes.
- **Ganho de ritmo sem perda de controle:** decidir os itens do passo 4 **uma vez** para os lotes restantes evita uma rodada de decisão por lote; cada lote continua com readiness, auditoria e mandato próprios (A1).
- **Lacuna G-1 (§5):** a readiness v1.3 não tem linha nominal para `H283P` com casos, marcador ou contexto divergentes. Não bloqueia o E03 (nunca é CONFORME e sempre há STOP); recomenda-se classificá-la numa futura revisão da readiness, sem efeito sobre este plano.

## 13. Gate

**AGUARDANDO AUDITORIA INDEPENDENTE DESTE PLANO E AUTORIZAÇÃO DE FABRÍCIO PARA EXECUÇÃO LIVE DO E03.**

Este plano não autoriza nenhuma chamada. A execução só começa com o mandato do §2, sobre um baseline que contenha este plano publicado. E03 `ef24a3be…` autorizável e não autorizado; não executado; cobertura LIVE 17/135; FREEZE ATIVO.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L1-E03-LIVE-EXECUTION-PLAN-01`, baseline `d65c7583`), documental, sem SQL e sem LIVE.**<br>• gate de entrada conforme: HEAD, árvore e índice limpos, blobs, `static_check` 444/88/79/6, 2830 inalterado, E03T auditado e publicado, readiness do E03 v1.2 publicada;<br>• decisões vinculantes DP-1 = A, DP-4 = A, DP-5 = A, `MAX_L3_D = 2`, reconhecimento = SIM, por referência à readiness do E03;<br>• identidade completa dos textos (E03 `ef24a3be…`); matriz S0–S7 com CONTINUE, STOP, evidência e tratamento de falha;<br>• controles R-1 a R-7 da resposta e distinção `H283F` × `55P03` capturado × `55P03` original × `57014` × erro inesperado × resposta ambígua, sem classe nova;<br>• fluxo excepcional com até duas L3-D; preparação do E99; modelo do registro de execução (sem preenchimento);<br>• quadro de fechamento do Batch 12 e sequência mínima segura; lacuna G-1 declarada. FREEZE ATIVO. |
