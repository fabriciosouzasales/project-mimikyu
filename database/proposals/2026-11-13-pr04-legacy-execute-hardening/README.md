# PR-04 · Hardening — EXECUTE dos escritores legados de `physical_card` (proposta 5365)

| Campo | Valor |
|---|---|
| **Estado** | **PR-04A CONCLUÍDA (2026-11-14): 5365 EXECUTADA NO LIVE e homologada pelo proprietário (6/6)** (`PR-04A \| 5365 LIVE CONTROLLED EXECUTION-01`), autorização expressa do proprietário, **G-D dispensado** com aceitação de risco; verificação PRE/POST PASS (ver "Execução no LIVE"). Promovida para `database/schema/5365_revoke_legacy_physical_card_writers_execute.sql`. R5365 disponível, **não executada**. 5365/R5365 v1.1; `5365_STATE` v1.2. Sem registro no ledger. |
| **Origem** | `PR-04 \| AUTHORIZATION SURFACE REVIEW-01` (TARGETED CORRECTION REQUIRED, severidade baixa). |
| **Execução** | Pelo proprietário, uma vez, depois de auditoria e autorização expressa (STD-001 §10). |

## Arquivos

| Arquivo | O que faz |
|---|---|
| `5365_STATE_readonly.sql` | Leitura pura. Consulta 1: as 8 assinaturas (md5, dono, ACL, EXECUTE efetivo por papel) — PRE e POST. Consulta 2: fotografia de `pg_stat_statements` para o gate G-D (T0 e T1). |
| `5365_revoke_legacy_physical_card_writers_execute.sql` | Um único `DO`: precheck → `REVOKE EXECUTE … FROM authenticated` nas 3 legadas → postcheck. |
| `R5365_rollback_regrant_authenticated.sql` | Um único `DO`: precheck do estado pós-5365 → `GRANT EXECUTE … TO authenticated` → postcheck da ACL anterior. Sem DROP, sem mudança de corpo. |

## Alvo e estado lido no LIVE (2026-11-13, somente leitura)

| Assinatura | Origem | md5(prosrc) | ACL | EXECUTE efetivo |
|---|---|---|---|---|
| `set_physical_cards_storage(uuid, uuid[])` | 5024 | `cf8d15bc…` | `{postgres=X/postgres,authenticated=X/postgres}` | authenticated ✔ · anon ✘ · service_role ✘ · PUBLIC ✘ |
| `organize_my_collection_storage(uuid, uuid, text, integer, text)` | 5222 | `595e5229…` | idem | idem |
| `add_physical_cards(jsonb)` | 5012 | `1a202850…` | idem | idem |

Os md5 batem com os corpos de `database/schema/5024`, `5222` e `5012`. Vigentes que a proposta confere e não toca: `set_physical_cards_storage(…, boolean)` `09e342a1…`, `organize_my_collection_storage(…, boolean)` `26ea92ac…`, `set_my_physical_cards_condition` `b569ecdb…`, `remove_my_physical_card` `d51b9264…`, `register_physical_cards_bulk` `d08dcc25…` — todas com a mesma ACL.

Papéis: `authenticated` não é herdado por nenhum papel além de `postgres` e `authenticator`; nenhum papel customizado. Privilégio padrão de funções do `postgres` em `public`: só `postgres` (o GRANT do rollback restaura exatamente a ACL anterior).

## Consumidores conhecidos

| Fonte | Resultado |
|---|---|
| Frontend (`web/`) | As 3 chamadas a `set_physical_cards_storage`/`organize_my_collection_storage` passam `p_unplace_from_binder` (sobrecargas novas) desde `0389498` (2026-10-24). `add_physical_cards`: nenhuma referência no histórico do `web/`. |
| Edge Functions (`supabase/functions/`) e `scripts/` | Nenhuma referência. |
| SQL no banco (funções, views, `cron.job`) | Nenhuma chamada. (Um falso positivo: comentário da 5364 cita a 5024.) |
| `pg_stat_statements` (desde 2026-07-17, sem data por chamada) | PostgREST chamou a 5024 de 2 argumentos **15 vezes** e a 5222 de 5 argumentos **3 vezes**, contra 1.111 da sobrecarga nova — compatível com o frontend anterior a 2026-10-24, mas **sem data não prova que pararam**. `add_physical_cards` só aparece em scripts administrativos (papel `postgres`), que continuam com EXECUTE. |
| Logs de API (últimas 24 h) | Nenhuma chamada a esses três endpoints. |

**Ausência de referência no repositório não prova ausência de consumidor externo:** qualquer portador de JWT `authenticated` pode chamar o PostgREST diretamente. Depois da 5365, uma chamada às legadas recebe `42501 permission denied for function`.

## Gates antes da execução

1. **G-A — Auditoria** desta proposta aprovada pelo proprietário.
2. **G-B — Autorização expressa** para executar 5365 no LIVE, com janela e canal definidos (um `DO` é atômico em qualquer canal; preferir o mesmo canal de chamada única usado em S2–S4).
3. **G-C — PRE**: `5365_STATE_readonly.sql` reproduz exatamente a tabela acima (md5, ACL, EXECUTE efetivo). Qualquer diferença → STOP.
4. **G-D — Janela de uso** (protocolo abaixo): PASS obrigatório. STOP ou EVIDENCE INSUFFICIENT impedem a execução.
5. **G-E — Rollback pronto**: `R5365` revisado e disponível antes de executar.
6. **G-F — Executor**: registrar o papel do canal; deve ser `postgres` (dono) ou superusuário. Outro papel → não executar.
7. **G-G — Harnesses históricos**: decisão registrada sobre D3 (abaixo) antes da execução.

## Gate G-D — protocolo de duas leituras de `pg_stat_statements` (v1.2)

Os logs da API não distinguem as sobrecargas: a URL `/rpc/<função>` é a mesma para a antiga e a nova, e o corpo da requisição não é registrado. O protocolo usa a **consulta 2** de `5365_STATE_readonly.sql` (somente leitura). **O gate não foi validado em operação.**

1. **Definir antes** T0, T1 e a duração mínima da janela (recomendado ≥ 24 h, com uso normal do app). Nada desta pasta é executado entre T0 e T1.
2. **T0 e T1**: rodar a consulta 2 com o **mesmo executor** e guardar a saída integral (linha META + todas as linhas DADO).
3. **Comparar** cada linha DADO pela chave completa `(dbid, papel, toplevel, queryid, classe)`.

**Origem.** `ADMIN` = papel `postgres` (rotinas administrativas conhecidas, que mantêm EXECUTE depois da 5365). `NAO_ADMIN` = qualquer outro papel — `authenticated`, `anon`, `service_role` ou desconhecido —, tratado como potencial consumidor. **Linha de consumidor** = DADO com origem `NAO_ADMIN` e classe `LEGACY_STORAGE`, `LEGACY_ORGANIZE` ou `LEGACY_ADD`. **Linha ambígua não-admin** = DADO com origem `NAO_ADMIN` e classe `AMBIGUOUS`.

**Estabilidade.** Uma linha é *estável* quando a mesma chave `(dbid, papel, toplevel, queryid, classe)` aparece em T0 e em T1 com o mesmo `calls`. Linhas históricas estáveis — de consumidor ou ambíguas — não bloqueiam: elas existem antes da janela e não registram atividade nela.

### Matriz de decisão

Avaliar na ordem: **STOP** prevalece (indício de consumidor); depois **EVIDENCE INSUFFICIENT**; **PASS** só se nada acima ocorrer.

| Resultado | Condição (T0 ou T1, conforme o caso) |
|---|---|
| **STOP** — investigar consumidor | Linha de consumidor presente em T1 e ausente em T0; ou `calls` em T1 maior que em T0 para a mesma chave. |
| **EVIDENCE INSUFFICIENT** | **Visibilidade (G2):** `visibilidade_total` = false, ou `linhas_ocultas` > 0, em T0 ou T1 — linha oculta pode ser chamada não observada. |
| | **Contagem:** `stats_reset` diferente; `dealloc` diferente; linha de consumidor presente em T0 e ausente em T1; `calls` menor em T1. |
| | **Identidade (G4):** `chave_repetida` > 1 em qualquer linha. |
| | **Ambiguidade (G1, por estabilidade):** linha ambígua não-admin **nova** em T1 (chave ausente em T0), com `calls` **maior** em T1, **ausente** em T1 (presente em T0) ou com `calls` **menor** em T1. Linha ambígua não-admin estável **não bloqueia**. |
| | **Execução:** consulta com erro, extensão ou view indisponível, executor diferente entre T0 e T1, saída incompleta, janela menor que a combinada. |
| **PASS** | Nenhuma das anteriores, com **todas** as verificações aplicadas: visibilidade comprovada nas duas leituras, mesmo `stats_reset` e `dealloc`, nenhuma chave repetida, toda linha de consumidor e toda linha ambígua não-admin estável (ou ausente nas duas leituras), mesmo executor e janela cumprida. |

Linhas `ADMIN` (inclusive `AMBIGUOUS` e `LEGACY_*` de `postgres`) e `CURRENT_*` são listadas como contexto e não decidem o gate.

**Referência do preflight** (`G-D OPERATIONAL READONLY PREFLIGHT-01`, 2026-11-13, leitura isolada — não é T0): duas linhas ambíguas não-admin históricas, `DO $$ …` de harnesses rodados como `authenticated` — `queryid 4472039671804551423` (`calls` 2) e `6264847537264826768` (`calls` 3), `dbid 5`, `toplevel true`. Se aparecerem iguais em T0 e T1, não bloqueiam; se uma delas subir, sumir ou cair, o resultado é EVIDENCE INSUFFICIENT. Linhas de consumidor históricas no mesmo preflight: `LEGACY_STORAGE` 15, `LEGACY_ORGANIZE` 3 e cinco `LEGACY_ADD` (13, 13, 3, 3, 3) — estáveis não bloqueiam; qualquer incremento ou linha nova é STOP.

### Limitações (G3/G5) — não viram aprovação

- **Chamadas com erro:** `pg_stat_statements` registra só comandos concluídos. Um consumidor cujas chamadas às legadas falham não é contado. **PASS não cobre esse caso.**
- **Capacidade:** a view estava com 4.912 de 5.000 entradas (2026-11-13). Qualquer aumento de `dealloc` na janela torna o resultado EVIDENCE INSUFFICIENT; o gate pode ficar inconclusivo de forma recorrente. Nesse caso **não executar** a 5365 sem decisão expressa e registrada do proprietário.
- **PASS não comprova inexistência de consumidores externos**: só mostra que nenhuma chamada concluída às legadas foi registrada naquela janela. Mitigação: `R5365`.

### Alternativa não validada (documentada, não implementada)

Reconciliação por URL: contar nos logs da API as requisições a `/rpc/set_physical_cards_storage`, `/rpc/organize_my_collection_storage` e `/rpc/add_physical_cards` na janela (incluindo respostas com erro) e comparar com o aumento de `calls` das entradas `CURRENT_*`. Excesso de requisições indicaria chamada às legadas; qualquer requisição a `/rpc/add_physical_cards` vinda de usuário seria STOP. **Não adotada:** a correspondência 1:1 entre requisição e execução (novas tentativas, erros antes da execução, cobertura dos logs) não foi comprovada.

## Interpretação operacional dos resultados (D6)

| Resultado no canal | Significado | Ação |
|---|---|---|
| NOTICE `5365 OK` / `R5365 OK` | Efeito aplicado e checagens finais aprovadas | Rodar a consulta 1 (POST) e o smoke test |
| EXCEPTION `PRECHECK 5365: JÁ APLICADA` | Estado já aplicado antes; nenhuma alteração nova | Não reexecutar; conferir com a consulta 1 |
| EXCEPTION `PRECHECK R5365: NADA A DESFAZER` | Reversão desnecessária; ACL já restaurada | Não reexecutar; conferir com a consulta 1 |
| EXCEPTION `… ESTADO DIVERGENTE …` ou `POSTCHECK …` | Estado inesperado; nada mudou (bloco desfeito) | **STOP**; investigar antes de qualquer nova tentativa |
| ERRO `55P03` (`lock_timeout` de 5 s) | Trava não obtida; a transação foi desfeita, nada mudou | **Interromper**; reavaliar (consulta 1, concorrência) antes de nova tentativa autorizada |

## Dependência D3 — harnesses históricos

`database/validations/5800_validate_collections_physical_increment_01a.sql`, `5801_performance_checks_collections_physical_increment_01a.sql` e `5803_performance_checks_collections_physical_increment_02a.sql` chamam `add_physical_cards(jsonb)` sob o papel `authenticated` (roteiros `SET LOCAL role authenticated`). Depois da 5365, reexecutá-los falharia com `42501 permission denied`. São harnesses históricos de validação (não fazem parte do aplicativo) e **não foram alterados**. Reproduzi-los exigiria um ambiente sem a 5365 ou ajuste próprio, decidido à parte.

## Critérios de aceite (POST)

- As 3 legadas: ACL `{postgres=X/postgres}`; EXECUTE `authenticated`/`anon`/`service_role` = false; `postgres` = true; md5 inalterado.
- As 5 vigentes: md5 e ACL idênticos ao PRE; `authenticated` = true.
- Aplicativo: mover cartas entre locais, organizar coleção, cadastrar e editar condição continuam funcionando (smoke test do proprietário).
- Documentação no mesmo ciclo (`05d`, `docs/log.md`); arquivo canônico novo em `database/schema/` só depois de CONFIRMADO EXECUTADO.

**STOP** — sem executar nada mais — se: o precheck acusar `ESTADO DIVERGENTE`; o postcheck abortar; aparecer consumidor das legadas; o smoke test falhar (avaliar `R5365`).

## Limites

- Reduz a superfície; **não** prova isolamento nem concorrência das funções vigentes. R1, R2, R3, R5 e R6 da 5364 continuam sem prova dinâmica (aceitação documentada, V5).
- Os corpos legados continuam no banco e executáveis pelo `postgres`; DROP fica fora desta proposta.
- O SQL foi revisado estaticamente e as constantes conferidas por leitura; **não foi executado em nenhum ambiente** (sintaxe sem prova de execução).

## Correções da versão 1.1 (auditoria PR-04A)

| Achado | Correção |
|---|---|
| D1 — G-D inverificável pelos logs da API | Protocolo de duas leituras de `pg_stat_statements` (consulta 2 do STATE). |
| D2 — comparações NULL-inseguras | 5365 e R5365: `IS DISTINCT FROM` / `IS NOT DISTINCT FROM` em md5, dono e ACL; ACL nula rejeitada explicitamente; `has_function_privilege(...) IS NOT FALSE / IS NOT TRUE`; `v_oid IS NULL` checado nos postchecks. A R5365 passou a reconferir md5 e o EXECUTE de `authenticated` no postcheck. |
| D3 — harnesses históricos | Seção "Dependência D3" e gate G-G. Harnesses não alterados. |
| D4 — qualificação | `pg_catalog.set_config`, `pg_catalog.md5`, `pg_catalog.regexp_replace`. |
| D5 — STD-001 §10 | Cabeçalhos com "Resultado esperado" e "Como validar". |

## Correções do G-D (auditoria AUDIT-02, `G-D TARGETED CORRECTION-02`)

| Achado | Correção |
|---|---|
| G1 — AMBIGUOUS de qualquer papel bloqueava sempre | Origem `ADMIN` (`postgres`) × `NAO_ADMIN` (qualquer outro); só `NAO_ADMIN` ambígua torna o gate INSUFFICIENT. Ajustado em `G-D FINAL PROTOCOL CORRECTION-03`: julgada por **estabilidade** entre T0 e T1 (a presença de linhas históricas estáveis bloqueava o gate para sempre, observado no preflight). |
| G2 — linhas invisíveis podiam gerar PASS falso | META com `visibilidade_total` (superusuário ou `pg_read_all_stats`) e `linhas_ocultas` em toda a view; qualquer falha → INSUFFICIENT. |
| G3/G5 — limitações do método | Documentadas; nunca viram aprovação. Reconciliação por URL registrada como alternativa não validada. |
| G4 — chave incompleta | Chave `(dbid, papel, toplevel, queryid, classe)` + `chave_repetida`; repetição → INSUFFICIENT. |
| D6 — interpretação | Tabela "Interpretação operacional dos resultados". |

5365 e R5365 não mudaram (v1.1, aprovadas estaticamente na AUDIT-02).

## Execução no LIVE (2026-11-14)

- **Autorização:** expressa, só para os 3 REVOKE desta proposta. **G-D (T0/T1) dispensado** por decisão do proprietário, que aceitou o risco de consumidor externo não identificado, sua possível interrupção e a incompatibilidade dos harnesses 5800/5801/5803. Esta dispensa prevalece sobre o "PASS obrigatório" do gate G-D descrito acima, exclusivamente para esta execução. T1 não executada.
- **Controles prévios:** MANIFEST 3/3; texto enviado idêntico ao arquivo (sha256 `747a1dea…`); consulta 1 PRE byte a byte igual à T0; logs da API (24 h): `/rpc/add_physical_cards` 0 chamadas, `/rpc/organize_my_collection_storage` 0, `/rpc/set_physical_cards_storage` 4 POST 200 não atribuíveis a uma sobrecarga.
- **Execução:** uma chamada `execute_sql` como `postgres`, 2026-11-14T17:31:45Z–17:32:19Z, sem erro. O canal não exibe NOTICE.
- **Verificação:** consulta 1 POST — só as 3 legadas mudaram (ACL `{postgres=X/postgres}`, `authenticated` sem EXECUTE); 5 vigentes idênticas; corpos, donos e config inalterados.
- **Pendências:** smoke test funcional do proprietário; monitoramento de 401/403 nos três endpoints e de 42501 por 7 dias; PR-04B (cenários R1, R2, R3, R5, R6 da 5364) aberta.
- **Evidências:** `execution-2026-11-14/` (`EXECUTION.md`, PRE/POST, `SHA256SUMS`).

## Homologação e encerramento da PR-04A (2026-11-14)

- **Homologação funcional — informada pelo proprietário (não é evidência capturada automaticamente):** executada e aprovada em 14/11/2026, **6/6 PASS, sem erros de permissão**: (1) Meu acervo — grade, filtros e detalhe; (2) movimentação de exemplar entre locais; (3) organização de coleção; (4) cadastro de carta avulsa; (5) edição de condição física; (6) Meus Locais e Encontrar carta. **Não** fazem parte desta homologação: cadastro por Set, +1/−1 de quantidade e testes de concorrência.
- **Decisões registradas:** G-D/T1 dispensado por decisão expressa; risco de consumidor externo desconhecido aceito; harnesses 5800/5801/5803 incompatíveis (chamam `add_physical_cards` como `authenticated`), aceitos.
- **Pós-execução:** monitoramento por 7 dias a partir de 2026-11-14 — respostas 401/403 em `/rpc/set_physical_cards_storage`, `/rpc/organize_my_collection_storage` e `/rpc/add_physical_cards` e erros `42501`, distinguindo-os de falhas de autenticação. Consumidor afetado → decisão do proprietário entre `R5365` e migração para a sobrecarga vigente.
- **Rollback:** `R5365_rollback_regrant_authenticated.sql` preservado (MANIFEST), não executado.
- **PR-04B continua aberta** (isolamento e concorrência da 5364 por execução: R1, R2, R3, R5, R6), com riscos próprios e aceitação documentada V5.

## Reconstrução do schema (dependência da 5365)

- Para reproduzir as permissões atuais do LIVE, a `database/schema/5365_revoke_legacy_physical_card_writers_execute.sql` deve ser aplicada **depois** de: 5012 (`add_physical_cards`), 5024 (`set_physical_cards_storage` de 2 argumentos), 5222 (`organize_my_collection_storage` de 5 argumentos) — que concedem EXECUTE a `authenticated` —, 5287/5288/5289 (corpos vigentes `09e342a1`, `26ea92ac`, `d51b9264`), 5362 e 5364 (`d08dcc25`, `b569ecdb`). A ordem numérica atende (5365 é a última da cadeia); ver também a ordem de reconstrução da PR-01 em `../2026-11-13-v1-16-card-condition/README.md`.
- Os prechecks da 5365 exigem esses corpos exatos (md5) e a ACL `{postgres=X/postgres,authenticated=X/postgres}` nas 8 assinaturas; uma reconstrução que divirja aborta com ESTADO DIVERGENTE (falha fechada). Os corpos acima foram conferidos por leitura dos arquivos de `database/schema/` (md5 iguais aos do LIVE).
- Os arquivos 5012, 5024 e 5222 continuam concedendo EXECUTE a `authenticated`; sem a 5365 a reconstrução não reproduz o LIVE. **Reconstrução limpa não comprovada.**
