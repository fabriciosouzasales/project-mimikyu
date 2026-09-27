# 2830H — Lote L1: plano operacional de execução LIVE do E03T

| Campo | Valor |
|---|---|
| **Documento** | `BATCH12-2830-P5-L1-E03T-LIVE-EXECUTION-PLAN-01`, preparado em `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01` (2026-09-27), baseline HEAD `d9e1b10ed47319e78e9ba06dccc99c1b65b5e034`. |
| **Natureza** | Plano operacional. **Não é executável sem mandato específico de Fabrício.** Nenhum SQL foi executado para prepará-lo, nem SELECT de preflight; nenhum acesso ao LIVE. |
| **Estado** | **AGUARDANDO AUTORIZAÇÃO DE FABRÍCIO PARA EXECUÇÃO LIVE** (§11). E03T **não executado**. E03 **não autorizado**. Cobertura LIVE **17/135**. **FREEZE ATIVO.** |
| **Autoridade normativa** | `L1-EXECUTION-READINESS.md` **v1.3**: decisões (§2, §2.5), sequência (§4.2), resposta esperada (§4.3), vínculo e postcheck (§4.4), STOP/CONTINUE (§4.5), aceite e limites (§5). Este plano **não cria critério**: detalha como cumpri-los. Em qualquer divergência, prevalece a readiness. |
| **Demais autoridades** | 2830 v7.0 (blob `b4647dcb…`, imutável) · `L1-E03-IMPLEMENTATION-READINESS.md` v1.2 · `PHASE5-AUTOMATED-COVERAGE-READINESS.md` · `LIVE-VALIDATION-PROTOCOL.md` · `LIVE-STAGE1-RUNBOOK.md` (textos L1 e L3) · registros das Etapas 2 e 3 (precedentes de captura e de preparação do E99). |

---

## 1. Decisões aplicáveis (resumo; texto literal na readiness v1.3 §2)

| Decisão | Efeito neste plano |
|---|---|
| **DP-1 = A′** | AD-2 só para o E03T: tempo medido no próprio LIVE; `statement_timeout` de 120 s comprovado na L1 da rodada (`'2min'`); aceite `elapsed_ms ≤ 60000`. P9b não é cumprido literalmente. |
| **DP-4 = B** | E03T publicado, sem `SET LOCAL lock_timeout`; `lock_timeout = '0'` e `statement_timeout = '2min'` na L1; nenhum `SET`, `set_config`, `ALTER ROLE` ou configuração de sessão. |
| **DP-5 = A** | Só as escritas transitórias do blob `9523bf23…`: 7 INSERTs de fixture, 4 de sonda, 2 selos, 8 subtransações, nas três tabelas EC (`trait`, `profile`, `profile_trait`); rollback obrigatório e verificação posterior. |
| **DP-7 = A** | E03T antes de considerar o E03. Diagnóstico T1–T3, fora dos 135 casos; não gera PASS contratual; limite L-1 preservado. |

Nenhuma delas se estende ao E03 nem a outros lotes.

## 2. Condições de entrada (todas; o mandato de execução deve declará-las)

1. Mandato de execução **próprio e expresso** de Fabrício, que cite este plano e a readiness v1.3 pelo blob, e declare o **baseline HEAD** da rodada.
2. Neste baseline, o plano, a readiness v1.3, o README e o `docs/log.md` desta preparação já publicados (commit e push por Fabrício).
3. Campo obrigatório do mandato: **número máximo de L3-D** no fluxo excepcional (§6). Sem esse campo, vale **uma** L3-D; sem confirmação nela, STOP.
4. Canal: MCP Supabase `execute_sql`, `project_id = qjfutqujxrbzgrtkpgkg`. Uma chamada = um statement. Nunca Dashboard, nunca `apply_migration`, nunca outro canal.
5. FREEZE ativo e sem mudança conhecida no ambiente desde a Etapa 3. Qualquer mudança conhecida (deploy, migration, importação, alteração de papel) ⇒ não iniciar.
6. Autoria: Claude executa; ChatGPT audita; Fabrício autoriza, faz commit e push.

## 3. Identidade dos textos a submeter

| Passo | Texto | Identidade exigida |
|---|---|---|
| S1 | L1 (`LIVE-STAGE1-RUNBOOK.md` §3.1, bloco literal) | md5 `0836c36a8d3749b1e7718223e064caf9`, 2.458 B |
| S2, L3-D, S7 | L3 (`LIVE-STAGE1-RUNBOOK.md` §3.2, bloco literal) | md5 `b7bc3700aeef278f6a79bd30e6a8d229`, 1.526 B |
| S3 | `2830H_E00_precheck_inventory.sql`, integral, sem edição | blob `a4dd84381b928727611a51147ba1a4c1d11b89ab` · md5 `45b6c35cca849ffbf49d22ec18e8283c` · sha256 `2a9539fb48d2d8231da59240b7c9d8fe4aa5fe6201e97335cd2a0e8ec9009a8a` · 53.803 B |
| S4 | `2830H_E03P_precheck_section2.sql`, integral | blob `0fc2d83dff599fc6cc26e35399ebc519a5a51d0f` · md5 `10457d87d4c25c93ab04d0fadf43dddc` · sha256 `3f0e540939e2528aae70fabf7c1a83aaa07421bf30a529710ea6b12c4bc68c5d` · 13.335 B |
| S5 | `2830H_E03T_n1_controlled_probe.sql`, integral | blob `9523bf23f68fe78a1e126dff1f85ccc8ece5c2dc` · md5 `34d3826e1e8b4a3d3871b87733c6538b` · sha256 `2eb3e2a46bd644dafeb2b2c8307fb1f39af9c5e2743a1ddebbd9011ae10ec1f0` · 25.029 B |
| S6 | E99 gerado de `2830H_E99_postcheck_residue.sql` com os 3 marcadores do S3 **desta** rodada | base: blob `49a71ecb4525697858110ee71a3f61f5eee74a34` · md5 `f0b91183a8649b990b080637dd56e74b` · sha256 `63f7e2e7fa2bd10fdd9bdd963e5e672d187580694bc467dabd1bc5af7165a66a` · 12.289 B; texto final: difere só nas linhas 56–58; md5 registrado **antes** da submissão |
| S0 | `tools/static_check.py` | blob `6b3689cc8ed959e5e78d46663d36b5ab13da27d0` · md5 `8a5d4b611bceaa9873ff4af7b9af012d` |
| — | contrato 2830 v7.0 (não submetido) | blob `b4647dcb59432405c8157e2733fd78678f35540e` · md5 `7d816d18bf6376c1fc29bc91c8bee2e9` |

Qualquer divergência de hash ⇒ não conectar (S0) ou não submeter (demais passos).

## 4. Sequência normal

`S0 → S1/L1 → S2/L3 → S3/E00 → S4/E03P → S5/E03T → S6/E99 → S7/L3 final`

Nenhuma outra chamada SQL entre elas. Entre chamadas, só conferência local da resposta anterior.

| Passo | Chamada | Continua se (todos) | Capturar integralmente | Se não |
|---|---|---|---|---|
| **S0** | verificação local, sem banco | HEAD = baseline do mandato; `git status --porcelain --untracked-files=all` vazio; blobs e md5 do §3 conferidos por `git hash-object` e `md5sum`; `static_check`: `TOTAL 444 PASS 444 FAIL 0`, `E03-PERFIL TOTAL 85 PASS 85`, `E03-VERIFICADOR-NEG TOTAL 56 PASS 56`, `E03-VERIFICADOR-POS TOTAL 4 PASS 4`; md5 de L1 e L3 recalculados dos blocos do roteiro | saída do `git` e do `static_check` | não conectar; STOP |
| **S1** | L1 | `transaction_read_only = off`; `default_transaction_read_only = off`; `in_recovery = false`; `lock_timeout = '0'`; **`statement_timeout = '2min'`** (readiness v1.3 §4.2); `server_version_num ≥ 170000`; `standard_conforming_strings = on` (roteiro §4.1); donos das 5 tabelas EC = `current_user` (ou superusuário); visibilidade de sessões provada (`is_superuser`, `reads_all_stats` ou `visible_foreign_sessions ≥ 1`) | JSON integral; `checked_at`, `backend_pid`, `current_user` | STOP; não submeter o E00 |
| **S2** | L3 | `locks_on_scope = []`; nenhuma outra sessão `client backend` em `active`, `idle in transaction` ou `idle in transaction (aborted)` | JSON integral; `checked_at` | STOP; não submeter o E00 |
| **S3** | E00 | resposta completa; `gate_pass = true` (24 gates), incluindo `g_no_residue`, `g_no_sequences_touched_now`, `g_rls_bypass`, `g_no_concurrency`, `g_freeze_canonical_equal`; `d_canon_diff = []` | JSON integral; `d_baseline`, `d_baseline_md5`, `d_session.db_role_setting_rows`, `checked_at`, `backend_pid` | STOP; não submeter o E03P. Repetição só pelo protocolo §3.4 (`g_no_concurrency`), com L3 e E00 novos |
| **S4** | E03P | resposta completa; `gate_pass = true` e os 11 gates `true`: `g_s2_triggers`, `g_s2_constraints`, `g_s2_function_pins`, `g_s2_error_tokens`, `g_deferrable_only_seal`, `g_seal_constraint_names_unique`, `g_no_other_triggers_l1`, `g_game_pokemon_one`, `g_nn_no_sequence`, `g_nn_rls_bypass`, `g_marker_absent_now` | JSON integral; `d_session.checked_at` | STOP; não submeter o E03T (nada foi escrito; E99 recomendado só para registro) |
| **S5** | **E03T**, uma chamada, logo após conferir o S4 | resposta **definida** (§5) | resposta integral do canal: SQLSTATE, mensagem, contexto | ver §5 e §6 |
| **S6** | E99 preparado conforme §7 | resposta completa; aceite do postcheck da readiness §4.4 | texto submetido (md5) e JSON integral; `checked_at`, `backend_pid` | classificação da readiness §4.4–§4.5; **sem reenvio** |
| **S7** | L3 final, **sempre depois** do S6 | nenhum lock no escopo; nenhuma sessão ativa ou em transação; nenhum pid desta rodada | JSON integral; `checked_at` | classificação da readiness §4.5 (linhas "(4)"); **sem reenvio** |

**Ordem temporal a registrar:** `checked_at(L1) < checked_at(L3) < checked_at(E00) < checked_at(E03P) < S5 < checked_at(E99) < checked_at(L3 final)`. O canal não devolve horário para erro: a posição do S5 vem da sequência registrada.

## 5. Resposta do E03T (S5)

**Resposta definida** é qualquer resposta do canal que traga SQLSTATE e texto do PostgreSQL, ou retorno sem erro.

| Resposta | Condição exata | Classificação provisória | Próximo passo |
|---|---|---|---|
| **Conforme** | SQLSTATE `H283P`; mensagem, não truncada, casando com `^H2830_ROLLBACK_PASS: envelope=E03T_N1_CONTROLE pass=3/3 casos=T1,T2,T3 marker=H2830_[0-9A-F]{32} elapsed_ms=[0-9]+$`; contexto `PL/pgSQL function inline_code_block line 454 at RAISE` (RAISE terminal na l. 482, `DO` na l. 29); `elapsed_ms ≤ 60000` | nenhuma: **H283P não é CONFORME sozinho** | S6, depois S7 |
| `H283P` com `elapsed_ms > 60000` | idem, fora do limite de DP-1 | NÃO CONFORME (não aceito) | S6, S7; STOP; investigar; não repetir |
| **Falha** | SQLSTATE `H283F`, `H2830_FAIL: envelope=E03T_N1_CONTROLE caso=<T1\|T2\|T3\|PREFLIGHT\|GATE> …` (com "sonda" = falha do padrão N-1) | NÃO CONFORME | S6 imediato, S7; STOP; sem retry |
| outro SQLSTATE | `P0001`, `23505`, `57014`, `55P03`, `25006`, `42601`, etc. | NÃO CONFORME | S6 imediato, S7; STOP |
| retorno sem erro (`[]`) | o `DO` terminou normalmente | NÃO CONFORME, **defeito grave** | S6 imediato, S7; STOP; INCIDENTE se houver resíduo |
| incompleta | mensagem truncada, SQLSTATE ausente com texto do PostgreSQL, ou `pass ≠ 3/3` | INCONCLUSIVO | S6 imediato, S7; STOP; nunca conforme |
| **ambígua** | timeout do cliente, perda de conexão, HTTP sem corpo, erro do canal sem texto do PostgreSQL | INCONCLUSIVO | **fluxo excepcional (§6)**; nunca S6 direto |

Capturar da mensagem: marcador `H2830_…` e `elapsed_ms`. O marcador é o elo documental E00 → E03T → E99.

## 6. Fluxo excepcional (resposta ambígua do E03T)

`S5 → L3-D → S6/E99 → S7/L3 final`, **só** com encerramento comprovado.

1. **Não reenviar o E03T.** Nenhum `pg_terminate_backend`, nenhuma limpeza, nenhum outro SQL.
2. **L3-D:** o mesmo texto da L3 (md5 `b7bc3700…`), só leitura. É diagnóstico: não é postcheck, não sustenta resíduo zero e não substitui o S7.
3. **Encerramento comprovado** (todos): resposta completa; `locks_on_scope = []`; nenhuma sessão `client backend` em `active`, `idle in transaction` ou com `xact_start`/`backend_xid` além da própria consulta. Como o canal não devolve o pid do E03T, qualquer sessão ativa ou em transação, ou qualquer lock no escopo, impede a confirmação.
4. **Com confirmação:** S6 (E99) e depois S7 (L3 final). A rodada é **no máximo INCONCLUSIVA**, qualquer que seja o resultado do postcheck; se o postcheck mostrar resíduo ou marcador, INCIDENTE.
5. **Sem confirmação:** repetir a L3-D, só leitura e sem nenhum outro SQL entre elas, até o limite do mandato (§2 item 3). Esgotado o limite: **não** submeter E99 nem S7; **STOP; INCONCLUSIVO; resíduo não verificado**; escalar a Fabrício. Postcheck posterior só com mandato próprio e o mesmo `d_baseline` do S3.

Capturar: cada L3-D integral, com `checked_at`, e o número de repetições.

## 7. Preparação do E99 (entre S5 e S6, local, sem banco)

Mesma mecânica da Etapa 3 (`LIVE-STAGE3-EXECUTION-RECORD.md` §4):

1. Gravar num arquivo de captura, a partir da resposta do **S3 desta rodada**: `d_baseline` (JSON integral), `d_baseline_md5` e `d_session.db_role_setting_rows`.
2. Conferir: nenhum apóstrofo nos valores; `md5(jsonb::text)` do JSON capturado, recalculado localmente (chaves ordenadas por comprimento e bytes, separadores `", "` e `": "`), igual a `d_baseline_md5`.
3. Gerar o texto por script que substitui só os três literais de `captured_raw` (`__E00_D_BASELINE__`, `__E00_D_BASELINE_MD5__`, `__E00_ROLE_SETTING_ROWS__`), exigindo exatamente uma ocorrência de cada; os comentários do cabeçalho ficam intactos.
4. Conferir: o texto difere do arquivo base só nas linhas 56–58. Registrar md5 e tamanho antes de submeter.
5. **Nunca** usar baseline de outra rodada, E00 novo como referência, ou edição manual do JSON. Divergência em 2–4 ⇒ readiness §4.5 linha "(3)": não submeter; regenerar só a partir da mesma saída do S3 e só se a causa for do script; persistindo, STOP.

## 8. Classificação

Integralmente a da readiness v1.3 (idêntica à v1.2): postcheck ÍNTEGRO / REPROVADO / NÃO CONCLUÍDO (§4.4), tabela STOP/CONTINUE (§4.5), aceite e limites (§5). Não é reproduzida aqui para não criar uma segunda fonte.

- **CONFORME** exige: resposta conforme (§5 acima), `elapsed_ms ≤ 60000`, postcheck **ÍNTEGRO** (E99 completo com os 9 gates `true`, `d_diff = []`, `d_canon_diff = []`, `g_marker_absent = true`, `d_baseline_now_md5 = d_baseline_md5`; e S7 completo e limpo) e ordem temporal registrada.
- Classificação final: a mais grave aplicável, **INCIDENTE > NÃO CONFORME > INCONCLUSIVO > CONFORME**.
- Resíduo zero só com postcheck ÍNTEGRO (S6 + S7).
- Um CONFORME **não** é PASS contratual, não altera 17/135 e **não autoriza o E03** (readiness §6).

## 9. Condições inegociáveis

1. Uma chamada SQL por etapa, pelo canal autorizado.
2. Nenhum retry automático do E03T.
3. Nenhuma limpeza ou intervenção manual sem mandato próprio.
4. Nenhum E99 elaborado com baseline de outra rodada.
5. Nenhuma interpretação de `H283P` isoladamente como resultado CONFORME.
6. Nenhum avanço ao E03 por consequência automática do E03T.
7. STOP diante de evidência incompleta, divergência de hash, alteração do ambiente ou falha de segurança, semântica, integridade, concorrência ou performance.

## 10. Registro, riscos residuais e STOP

**Registro a produzir** (documento novo `LIVE-L1-E03T-EXECUTION-RECORD.md`, no mesmo ciclo da execução): S0; cronologia com `checked_at` e SQLSTATE por chamada; respostas integrais (L1, L3, E00, E03P, E03T, L3-D se houver, E99, L3 final); texto exato do E99 e seu md5; verificação local; limitações do canal; classificação final pela readiness; Revision History e linha em `docs/log.md`.

**Riscos residuais (readiness §3.3 e §5):**
- escrita real no LIVE sob FREEZE, por milissegundos, sem ambiente descartável como última barreira; garantia estrutural (todo caminho do `DO` termina em exceção) e prova tripla;
- limite **L-1**: o T3 prova ausência de contaminação observável, não a remoção do evento diferido da fila;
- sem medição prévia de tempo (P9b não cumprido literalmente); teto duro de 120 s;
- espera por lock só limitada pelo `statement_timeout` (sem `lock_timeout`);
- canal caixa-preta: não devolve pid nem horário do erro; ambiguidade leva ao fluxo excepcional;
- resíduo não-transacional declarado: `pg_stat_*`, tuplas mortas, WAL, XIDs de subtransação, logs com o marcador;
- ramos PL/pgSQL não percorridos num CONFORME continuam só verificados estaticamente.

**Condições de STOP:** todas as da readiness §4.5, as do §9 item 7, e ainda: mandato sem baseline ou sem citar este plano; árvore suja; `static_check` diferente de 444/85/56/4; hash divergente em qualquer texto; `statement_timeout ≠ '2min'`; qualquer necessidade de `SET` ou de alterar SQL, protocolo ou critério.

## 11. Gate

**AGUARDANDO AUTORIZAÇÃO DE FABRÍCIO PARA EXECUÇÃO LIVE.**

Este plano não autoriza nenhuma chamada. A execução só começa com o mandato do §2. E03T não executado; E03 não autorizado; cobertura LIVE 17/135; FREEZE ATIVO.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-27, `BATCH12-2830-P5-L1-E03T-DECISION-RECORD-01`, baseline `d9e1b10e`), documental, sem SQL e sem LIVE.**<br>• decisões DP-1 = A′, DP-4 = B, DP-5 = A e DP-7 = A aplicadas ao E03T, por referência à readiness v1.3;<br>• condições de entrada do mandato, incluindo o número máximo de L3-D como campo obrigatório;<br>• identidade completa dos textos a submeter;<br>• sequência S0–S7 com gates, capturas e desvio por passo;<br>• respostas do E03T e fluxo excepcional S5 → L3-D → S6 → S7;<br>• preparação do E99;<br>• classificação por referência integral à readiness;<br>• condições inegociáveis, riscos residuais e STOP;<br>• gate final "AGUARDANDO AUTORIZAÇÃO DE FABRÍCIO PARA EXECUÇÃO LIVE". |
