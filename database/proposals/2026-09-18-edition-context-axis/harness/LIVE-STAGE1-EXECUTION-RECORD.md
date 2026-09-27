# 2830H — Registro de execução da Etapa 1 (LIVE)

| Campo | Valor |
|---|---|
| **Natureza** | Registro das tentativas da Etapa 1 do `LIVE-VALIDATION-PROTOCOL.md` v1.4, executadas pelo `LIVE-STAGE1-RUNBOOK.md` v1.3. |
| **Estado atual** | **Etapa 1 não concluída. Nenhum PASS formal registrado.** Ocorrência 01: governança, consultas feitas fora da atribuição. Tentativa 02: STOP em PC-1, sem SQL. Etapa 2 **não autorizada**. |
| **Papéis** | **Claude**: único executor autorizado. **ChatGPT**: auditor independente, sem atribuição de execução. **Fabrício**: autorizações, commit e push. |
| **FREEZE** | ATIVO. |

---

## Ocorrência 01 — consultas executadas pelo auditor (ocorrência de governança)

**Registrada em:** `BATCH12-2830-LIVE-STAGE1-CHANNEL-BLOCKER-01`. **Reclassificada em:** `BATCH12-2830-LIVE-STAGE1-PC1-STOP-CLOSEOUT-01` (2026-09-26), a partir das informações de Fabrício no mandato `BATCH12-2830-LIVE-STAGE1-EXECUTION-01`.

### 1. Fatos

| Item | Registro |
|---|---|
| Quem executou | **ChatGPT**, fora de sua atribuição de auditor. Não houve mandato de execução em nome dele. |
| HEAD na ocasião | `44d8c5279b13972376b10254de01404053aa5cc4` (`44d8c52`), segundo a informação recebida |
| L1 (md5 `0836c36a…`) | executada via MCP `execute_sql`; retornou resultado **informado como conforme** |
| L3 (md5 `b7bc3700…`) | **tentativa bloqueada pela ferramenta** por configuração de segurança. **Nenhum resultado SQL** foi obtido. **Não há evidência de que a consulta tenha sido executada no PostgreSQL.** |
| E00 | **não executado** |
| Efeito no banco | nenhum conhecido. L1 é SELECT; da L3 não há evidência de chegada ao banco. |

A saída integral da L1, o texto literal da mensagem de bloqueio e os horários **não foram anexados** a este registro. Nada aqui os substitui.

### 2. Classificação

- **Ocorrência de governança, não rodada da Etapa 1.** As consultas foram feitas por quem não tinha atribuição de execução e sem mandato de execução.
- **A L1 não é PASS formal da Etapa 1.** O resultado não é evidência para nenhuma rodada, atual ou futura (decisão de Fabrício no mandato `…-EXECUTION-01`).
- **A L3 bloqueada não é erro do PostgreSQL**: não há SQLSTATE, não há resultado e não há evidência de execução no banco. Por analogia com o protocolo §3.4 ("saída truncada pelo canal") e com o roteiro §5 ("INVÁLIDA"), a tentativa fica como **INVÁLIDA — bloqueio de canal**.
- Nenhum caso da 2830 e nenhum gate do E00 foram avaliados.

### 3. Bloqueio de canal — alternativas (sem tocar no SQL nem no md5 da L3)

O diagnóstico da camada do bloqueio continua pendente e depende da mensagem literal. As camadas possíveis:
- (a) permissão do cliente;
- (b) política do conector ou da organização;
- (c) filtro de segurança do agente;
- (d) configuração do servidor MCP.

Como o bloqueio ocorreu na ferramenta usada pelo auditor, **não se sabe** se ele se repete no canal do executor autorizado. Só a execução formal da L3 pelo Claude, sob mandato, responde isso.

| # | Alternativa | Mantém canal MCP? | Revisão do protocolo? | Avaliação |
|---|---|---|---|---|
| A1 | Aprovar explicitamente a chamada no controle de permissão da ferramenta | sim | não | autorizável, se (a) |
| A2 | Ajustar a permissão do conector Supabase MCP para `execute_sql` no projeto `qjfutqujxrbzgrtkpgkg` | sim | não | autorizável, se (b) |
| A3 | Liberação explícita do conteúdo da L3 junto ao filtro do agente, com a consulta **inalterada** | sim | não | autorizável, se (c) |
| A4 | Revisar a configuração do servidor MCP, sem trocar de servidor | sim | não | autorizável, se (d) |
| A5 | Mesmo servidor Supabase MCP, outro cliente operado por Fabrício, mesmo `project_id` | sim | não; o registro deve identificar o cliente | autorizável |
| A6 | `psql` / Supabase CLI | **não** | **sim** (PC-3 / §2.2) | não recomendado agora |
| A7 | Dashboard / SQL Editor | não | — | **proibido** |
| A8 | Alterar, fragmentar ou substituir a L3 | — | — | **proibido** |

**Revisão formal do protocolo:**
- desnecessária para A1–A5;
- obrigatória para A6;
- **recomendada, não bloqueante:** uma linha explícita no §3.4 — *"chamada bloqueada pela ferramenta, sem SQLSTATE e sem resultado ⇒ rodada INVÁLIDA (STOP operacional); não é FAIL; retomada só com novo mandato, desde S1.0"*. **Não aplicada.**

---

## Tentativa 02 — Claude, mandato `BATCH12-2830-LIVE-STAGE1-EXECUTION-01`: STOP em PC-1

**Data:** 2026-09-27 01:04 UTC (verificação local do repositório).

| Item | Registro |
|---|---|
| Executor | **Claude** (autorizado pelo mandato) |
| PC-1 | **FALHOU.** HEAD = `44d8c5279b13972376b10254de01404053aa5cc4` (conforme), mas a **árvore não estava limpa**. Havia três alterações documentais não commitadas, vindas de `…-CHANNEL-BLOCKER-01`: `harness/README.md` (M), `docs/log.md` (M) e `harness/LIVE-STAGE1-EXECUTION-RECORD.md` (novo) |
| PC-2 (verificação local, sem SQL) | E00 blob `97410c3a…`, md5 `d00b7cec2523b2ee3de9565a93dbae57`; L1 `0836c36a…`, L3 `b7bc3700…` e L2 `81d3472e…`: todos conferem. Roteiro v1.3, protocolo v1.4 e 2830 (`b4647dcb`) idênticos ao HEAD. |
| PC-3 / PC-5 | não exercidas |
| SQL submetido | **nenhum**: L1, L3, E00 e L2 não foram executadas |
| Resultado | **STOP em PC-1** (roteiro §1). Não houve dispensa da PC-1. |
| Caminho escolhido (auditoria) | **publicação documental**: commit destes três arquivos por Fabrício, gerando novo baseline, e novo mandato de execução com o novo HEAD. Sem dispensa da PC-1. |

---

## Retomada

1. Fabrício faz o commit dos três arquivos documentais (`harness/LIVE-STAGE1-EXECUTION-RECORD.md`, `harness/README.md`, `docs/log.md`). O novo HEAD passa a ser o baseline.
2. Novo mandato de execução, citando:
   - o novo HEAD;
   - o `LIVE-STAGE1-RUNBOOK.md` v1.3;
   - o `LIVE-VALIDATION-PROTOCOL.md` v1.4;
   - este registro.
3. **Tentativa 03 pelo Claude, desde S1.0:**
   - PC-1…PC-5 integralmente, com a árvore limpa;
   - **L1 nova** (a L1 da Ocorrência 01 não é aproveitada);
   - depois L3 → E00 → (≥ 60 s) → E00, conforme o roteiro §2;
   - L2 só como diagnóstico após STOP de pino.
4. Se a L3 for bloqueada pela ferramenta do executor: STOP operacional (INVÁLIDA), diagnóstico da camada com a mensagem literal, e escolha entre A1–A5 por Fabrício. Nenhuma nova tentativa na mesma rodada.
5. `READY FOR STAGE 2` só com todos os critérios do roteiro §4 atendidos. A Etapa 2 continua exigindo mandato próprio.

---

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-26, `BATCH12-2830-LIVE-STAGE1-CHANNEL-BLOCKER-01`, HEAD `44d8c52`).** Registrava a "Rodada 01" como INVÁLIDA — STOP operacional por bloqueio de canal em S1.2 (L3), com a L1 descrita como conforme via MCP, sem identificar o executor. Alternativas A1–A8 e procedimento de retomada. |
| 1.1 | **Reclassificação (2026-09-26, `BATCH12-2830-LIVE-STAGE1-PC1-STOP-CLOSEOUT-01`).** A antiga "Rodada 01" passa a **Ocorrência 01 — governança**: L1 e tentativa de L3 executadas pelo **ChatGPT**, fora da atribuição de auditor. A L1 **não é PASS formal**; a L3 foi bloqueada pela ferramenta, sem resultado SQL e **sem evidência de execução no PostgreSQL**. Registrada a **Tentativa 02** do Claude: STOP em PC-1 (árvore suja), nenhum SQL submetido, sem dispensa da PC-1. Retomada ajustada: commit documental, novo mandato e Tentativa 03 desde S1.0. |
