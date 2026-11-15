# V1-13 · E1-A — Estratégia de validação sem ambiente isolado

| Campo | Valor |
|---|---|
| **Versão** | 1.3.1 (2026-11-15, `V1-13 / E1-A \| DOCUMENTATION RECONCILIATION AND LOCAL COMMIT-06`): só documentação (R3) — §2.2 T6/T9 e §2.6 alinhadas ao artefato auditado; nenhum artefato executável mudou. 1.3 (2026-11-15, `V1-13 / E1-A \| P1 INDEPENDENT ARTIFACT AUDIT-04`): desfecho com SQLSTATE próprio (E1AOK/E1ANO); `LOCK … NOWAIT` antes da T7; pós-estado com contagens informativas e prova de rollback por `txid_status`; sessões de início invisível contam como risco. Achados em `p1/README.md` §Auditoria. 1.2 (2026-11-15, `V1-13 / E1-A \| P1 ARTIFACT PREPARATION-03`): artefato P1, S0/pós-estado e verificador independente em `p1/` (§2.10); `lock_timeout` efetivo de 5 s durante a T7 (§2.6). 1.1 (2026-11-15, `V1-13 / E1-A \| VALIDATION PROTOCOL HARDENING-02`): corrige a inconsistência do P1 apontada pela auditoria (§2.1) e especifica o mecanismo transacional, as garantias, os locks, os efeitos remanescentes e os casos de recusa. 1.0 (2026-11-15, `VALIDATION STRATEGY CORRECTION-01`). |
| **Estado** | **E1-A: IMPLEMENTAÇÃO LOCAL PREPARADA / AUDITORIA ESTÁTICA PASS COM RESSALVAS / NÃO EXECUTADA. P1: NÃO AUTORIZADO PARA EXECUÇÃO.** Auditoria independente do pacote `V1-13_E1A_independent_review_2026-11-15.zip`: `P1 INDEPENDENT STATIC AUDIT PASS WITH RESERVATIONS` (integridade e reprodutibilidade estática confirmadas; nenhuma execução autorizada). Ressalvas: R1 bloqueio de usuários durante o ensaio; R2 efeitos externos indiretos a examinar; R3 divergências documentais (corrigidas na 1.3.1); R4 provas dinâmicas não executadas, inclusive S8 concorrente, S10 e PR-04B. Nenhuma prova dinâmica realizada; nenhum acesso ao LIVE; S0 e autorização específica obrigatórias antes de qualquer operação no LIVE (§2.9). |
| **Norma** | C-244 **revisada em 2026-11-15**, sem ambiente isolado (`concept-decisions.md`, revisões 1.37 e 1.38). A revisão não autoriza execução. C-234–C-243 inalteradas. |
| **Precedente** | Ensaio transacional no LIVE da P3-B S1 (`../2026-10-25-p3b-binder-activity-history/README.md` §21–§28 e `LIVE_DRYRUN_S1_rollback_v2.3.sql`, cabeçalho A–D), executado com reversão, e protocolo de canais da V1-16 (`../2026-11-13-v1-16-card-condition/CONTROLLED-EXECUTION-PROTOCOL.md` §2 e §11). |

## 1. Classificação das 54 verificações da 5888

Classes:

- **E** — verificável por inspeção ou validação estática (sem banco).
- **L** — verificável por leitura sem efeito colateral no banco existente.
- **W** — depende de escrita controlada, desfeita por transação (dados sintéticos, nunca confirmados).
- **X** — inadequado para produção na forma descrita.

| Verificações | Classe | Observação |
|---|---|---|
| 0.1 CHECK, default, RLS e privilégios de `collection_membership` | **L** (+E) | Leitura de catálogo. O lado do arquivo já está coberto pelo `static_check_e1a.py`; o lado do banco só existe com a migration aplicada (no P1 ou depois da P2). |
| 0.2 `collection_member_role` interna | **L** (+E) | idem |
| 0.3 sobrecarga única do convite, padrão, ACL | **L** (+E) | idem |
| 0.4 ACL da troca de papel | **L** (+E) | idem |
| 0.5 5302 e 5308 intocadas (md5) | **L** | Também roda antes da aplicação, como parte da S0 (§2.3). |
| 0.6 ACL das leituras 5368 | **L** (+E) | idem 0.1 |
| F fixture (catálogo sintético, 4 usuários, 2 coleções, fichário) | **W** | Insere em `auth.users`, `expansion`, `card_set`, `card`, `card_variant`, `physical_card`, coleções, fichário e histórico. **Se confirmada, é X**: o Set sintético apareceria no catálogo público. |
| 1.1–1.5 convite | **W** | Dependem das contas e coleções sintéticas. |
| 2.1–2.5 convite pendente e caixa | **W** | idem |
| 3.1–3.4 leitura VIEWER = EDITOR, `access`, lista | **W** | idem |
| 3.5–3.8 papel real × nível de leitura | **W** | Funções de leitura, mas sobre participações sintéticas. |
| 3.9 coleção PUBLIC sem sessão | **W** | `UPDATE` direto de uma coleção **sintética**, como dono do banco. |
| 4.1–4.8 troca de papel | **W** | |
| 5.1–5.5, 5.7–5.12 segurança | **W** | |
| 5.6 anon sem EXECUTE | **W** (equivalente **L**) | A mesma garantia sai de `has_function_privilege('anon', …)` (0.3/0.4). |
| 6.1–6.4 chaves e privacidade | **W** | |
| 7.1–7.3 EDITOR sem escrita | **W** | |
| 7.4 EDITOR sem acesso à tabela | **W** (equivalente **L**) | `has_table_privilege` (0.1). |
| 99.1 resíduo zero | **L** | Só tem significado junto com as W. |

**Totais:** 7 L e 47 W (duas com equivalente L). Nenhuma é X **enquanto desfeita**; **todas as W viram X se confirmadas.**

**Fora da cobertura:** concorrência entre sessões (§4).

**A 5888 não é ferramenta do LIVE:** ela pressupõe as migrations aplicadas. Por isso, a prova anterior à aplicação precisa de um arquivo próprio de ensaio (P1), ainda **não gerado**.

## 2. Protocolo P1 — ensaio transacional antes da aplicação

### 2.1 Inconsistência encontrada e correção

A v1.0 deste documento, e o relatório que a apresentou, descreviam o P1 com uma "sessão em somente leitura" e, ao mesmo tempo, com DDL (5366–5370) e DML (fixture da 5888). Tomadas ao pé da letra, as duas afirmações são incompatíveis: numa transação efetivamente READ ONLY, o PostgreSQL recusa `ALTER TABLE`, `CREATE FUNCTION` (inclusive em `pg_temp`), `DROP FUNCTION` e `INSERT` em tabelas permanentes, com SQLSTATE 25006.

Havia mais três defeitos:

- **Canal:** a v1.0 admitia o SQL Editor ou uma mensagem única, embora a V1-16 (§11) já tivesse mostrado que esse canal não garante transação única entre instruções.
- **P3:** a v1.0 previa a 5888 "em modo subtransação" com a guarda de somente leitura ligada. Assim ela não conseguiria nem criar as funções `pg_temp`, e a subtransação interna não reverte o que acontece fora dela.
- **`transaction_timeout`:** a v1.0 o tratava como limite garantido, mas ele só existe a partir do PostgreSQL 17, e a versão do LIVE não foi verificada nesta rodada.

**Correção:** a única transação que escreve é **explicitamente READ WRITE**. A configuração de somente leitura vale **para a sessão**, como padrão das transações que **não** forem a do ensaio. Ela só serve de guarda caso uma instrução escape do bloco explícito. O canal passa a ser só psql. A P3 passa a usar a mesma moldura transacional. Itens não verificados viram condição de S0 (§2.3).

### 2.2 Mecanismo transacional exato

As instruções abaixo ficam no nível superior, em um único arquivo gerado por script (no padrão do `build_live_dryrun_s1.py`), executado por `psql -X -v ON_ERROR_STOP=1 -f <arquivo>` em **conexão direta única**.

| Passo | Instrução | Função |
|---|---|---|
| T0 | `SET SESSION default_transaction_read_only = on;` | Fora de bloco explícito, é uma transação implícita de uma instrução. Muda só o **padrão da sessão**: qualquer transação seguinte que **não** declare `READ WRITE` nasce somente leitura. |
| T1 | `BEGIN;` | Abre o bloco explícito. Herdaria o padrão somente leitura de T0. |
| T2 | `SET TRANSACTION READ WRITE;` | Primeira instrução do bloco, antes de qualquer consulta, portanto permitida. Torna **esta** transação de escrita. Fora de um bloco, o PostgreSQL só emite um aviso e não tem efeito, e é isso que dá sentido a T0. |
| T3 | `SET LOCAL lock_timeout = '2s'; SET LOCAL statement_timeout = '20s'; SET LOCAL idle_in_transaction_session_timeout = '15s';` e, se a S0 confirmar o suporte, `SET LOCAL client_connection_check_interval = '1s'` (PG ≥ 14) e `SET LOCAL transaction_timeout = '60s'` (PG ≥ 17) | Limites aplicados pelo servidor. |
| T4 | Trava de COMMIT: tabelas temporárias `_e1a_trap_parent`/`_e1a_trap_child`, com FK `DEFERRABLE INITIALLY DEFERRED`, e **uma linha órfã** inserida em `_child` | A violação só é verificada no COMMIT. |
| T5 | Tabela temporária de evidência | Guarda o resultado da 5888 para a sentinela. |
| T6 | `DO` de precheck, só leitura, com a S0 repetida dentro da transação; em seguida `LOCK TABLE public.collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT` e registro do instante (`t_lock`) | Precheck diverge → erro → aborto. O `LOCK … NOWAIT` obtém o lock **na hora** ou falha com `55P03`, sem nada aplicado e sem entrar em fila. |
| T7 | Texto aprovado de 5366 → 5370, **instrução a instrução, no nível superior** | O gerador remove só os `begin;` e `commit;` de cada arquivo e recusa qualquer outro `BEGIN`/`COMMIT`/`END`/`SAVEPOINT`/`SET CONSTRAINTS`. Os `set local lock_timeout` e os `DO` de pre/postcheck das migrations ficam como estão. |
| T8 | Corpo da 5888 (criação das funções `pg_temp`) + `INSERT INTO <evidência> SELECT * FROM pg_temp.wh_5888_validate();` | Migrations e harness na **mesma transação**. A fixture é desfeita duas vezes: pela subtransação interna (MS888) e pelo aborto de T9. |
| T9 | `DO` de postcheck (só leitura) e `DO` sentinela: **um único** `RAISE`, sempre, com SQLSTATE **`E1AOK`** e mensagem `MSDRYRUN_E1A APROVADO {json}` quando 54/54, trava intacta e duração ≤ 10 s; caso contrário SQLSTATE **`E1ANO`** e `MSDRYRUN_E1A REPROVADO {json}` | Encerra o caminho normal em erro, com desfecho inequívoco (nenhuma outra instrução usa esses códigos; classificação completa em `p1/README.md`). |
| T10 | `ROLLBACK;` | Só é alcançado se o executor continuar depois do erro, o que o contrato proíbe. |
| T11 | `RESET default_transaction_read_only;` | idem |

**Como migrations e harness convivem na mesma transação:** T7 aplica o DDL dentro do bloco de T1. T8 cria funções `pg_temp`, o que é permitido em transação READ WRITE, chama a 5888 contra as funções que acabaram de ser criadas e grava o resultado em tabela temporária. Nada é confirmado em nenhum momento.

### 2.3 S0 — pré-condições, só leitura (antes de gerar e antes de executar)

1. `server_version_num`. Decide os opcionais de T3. Abaixo de 140000, o ensaio é **recusado**.
2. `SHOW default_transaction_read_only` = `off` e `session_replication_role` = `origin`.
3. md5 de 5302, 5303, 5308, 5309, 5311 e 5312 iguais aos canônicos (`static_check_e1a.py` §8). Os valores atuais foram derivados dos arquivos, não lidos no LIVE.
4. CHECK de papel ainda `('VIEWER')`, nenhuma participação com outro papel, uma única sobrecarga do convite e a ACL completa das funções afetadas registrada.
5. Gatilhos em `auth.users`, `collection_membership`, `collection`, `expansion`, `card_set`, `card`, `card_variant`, `physical_card` e nas tabelas do fichário e do histórico. Qualquer gatilho ou função que use `pg_net`, `http`, `dblink`, `pg_notify` ou webhook = **recusa**.
6. Publicações de replicação lógica que incluam essas tabelas. Só registro: transação abortada não é decodificada.
7. `log_statement` e `log_min_error_statement`. Registro de quais textos irão para o log (§2.7).
8. `pg_stat_activity` sem transação aberta há mais de 1 s tocando `collection_membership`.
9. Executor confirma conexão **direta** (não pooler em modo transação nem statement) e psql disponível.

### 2.4 O que impede uma confirmação acidental

| # | Situação | Mecanismo | Tipo |
|---|---|---|---|
| G1 | Caminho normal | T9 sempre levanta erro: a transação aborta, e com `ON_ERROR_STOP` o psql sai e fecha a conexão | **Demonstrável:** semântica do PostgreSQL (erro em bloco explícito aborta a transação; conexão encerrada com transação aberta é desfeita) |
| G2 | `COMMIT` enviado depois de qualquer erro | COMMIT em bloco abortado vira ROLLBACK | **Demonstrável** |
| G3 | T9 removido e `COMMIT` enviado com a transação ativa | A FK adiada de T4 falha no COMMIT e a transação é desfeita | **Demonstrável:** restrição `DEFERRABLE INITIALLY DEFERRED` checada no COMMIT. Anulada por `SET CONSTRAINTS … IMMEDIATE`, que erra na hora e também aborta, ou pela remoção de T4, que o gerador recusa |
| G4 | Executor ignora o `BEGIN` e confirma instrução a instrução | T0 deixou a sessão somente leitura. T2 vira aviso. O primeiro `ALTER TABLE` da 5366 falha com 25006 e nada é escrito | **Demonstrável se, e só se, T0 vigorar na mesma sessão física.** Num pooler em modo transação, T0 pode cair em outro backend e a guarda **não existe** → operacional (S0-9) |
| G5 | Erro, `lock_timeout` ou `statement_timeout` em qualquer passo | A transação aborta | **Demonstrável** |
| G6 | Executor parado no meio (sessão ociosa dentro do bloco) | `idle_in_transaction_session_timeout` encerra a sessão em 15 s e desfaz | **Demonstrável** (parâmetro do servidor) |
| G7 | Arquivo editado (sem T0, T4 ou T9, com COMMIT) | Hash conferido pelo gerador (`--check`) e verificador de mutações | **Operacional.** O banco não tem como saber que o arquivo foi alterado |
| G8 | Executor fora do contrato (trechos selecionados, `psql -1`, sessão interativa com `\i`) | Contrato do executor (P3-B §23, D1–D8) | **Operacional** |

**Garantia efetivamente demonstrável:** enquanto o arquivo for o gerado e verificado, e a conexão for direta e única, **nenhum caminho de execução confirma o DDL ou a fixture** (G1–G6). Fora dessas duas condições, a proteção depende do executor (G7–G8).

**O que não é garantia:**

- **T0 isolado:** não protege em pooler de transação.
- **A subtransação MS888 da 5888:** só desfaz a fixture, não o DDL.
- **`transaction_timeout`:** só existe a partir do PG 17, e o início da contagem não está comprovado.

### 2.5 Falhas, encerramento de sessão e interrupções

| Evento | Efeito | Ação |
|---|---|---|
| Erro em T0–T6 | Nada aplicado; transação abortada | STOP, registrar, não repetir |
| Erro em T7 (sintaxe, precheck da migration, `lock_timeout`) | DDL parcial descartado no aborto | STOP |
| Erro em T8 (fixture ou RPC) | Aborto; 5888 sem relatório | STOP |
| Sentinela com GATE ≠ 54/54 | Aborto (esperado), resultado reprovado | STOP; a E1-A volta à correção |
| Queda de rede ou cliente | O servidor desfaz quando detecta a desconexão: no próximo envio, ou em até 1 s com `client_connection_check_interval`, se a S0 confirmar o suporte. O statement corrente fica limitado a 20 s | Conferir pós-estado (§2.8); não repetir |
| Executor mantém a sessão depois do erro | Sessão em "idle in transaction (aborted)": as travas **já foram liberadas** no aborto, e T0 é a única coisa que persiste na sessão | `ROLLBACK;`, `RESET default_transaction_read_only;`, `SHOW` = `off`, fechar a conexão |
| Queda do servidor | Transação não confirmada é descartada na recuperação | Conferir pós-estado |

### 2.6 Locks e impacto sobre usuários

| Lock | Onde | Duração | Impacto |
|---|---|---|---|
| `ACCESS EXCLUSIVE` em `collection_membership` | **Aquisição:** `LOCK … NOWAIT` no fim da T6, antes da 5366. **Uso:** a 5366 (`ALTER TABLE … DROP/ADD CONSTRAINT`, com varredura curta para validar o CHECK) roda sobre o lock já obtido | **Aquisição:** imediata ou recusa (`55P03`), sem espera e sem fila. **Duração depois de obtido:** da T6 até o aborto, cobrindo T7, T8 (toda a 5888) e T9. Teto de 20 s por instrução; teto total só com PG ≥ 17 (`transaction_timeout`) | Enquanto durar, **todas** as consultas que referenciam a tabela esperam: leituras do participante (5302/5310), "Compartilhadas com você" na Biblioteca (5311), painel de compartilhamento, convites, respostas e saídas. Podem falhar pelo `statement_timeout` dos papéis da API. A vitrine pública não referencia a tabela e não é afetada. Indisponibilidade **não descartada** (risco R1): exige janela fora de uso. O `lock_timeout` de 5 s que cada migration define continua valendo só para os demais objetos que ela tocar |
| Atualização de linhas de `pg_proc`, `pg_constraint` e `pg_description` | 5367–5370 | Até o aborto | Ninguém bloqueia ao **executar** as funções antigas, que seguem visíveis pelo MVCC do catálogo. Só um `CREATE OR REPLACE` concorrente das mesmas funções esperaria |
| `ROW EXCLUSIVE` em `auth.users`, `expansion`, `card_set`, `card`, `card_variant`, `physical_card`, `inventory`, `user_profile`, tabelas de coleção e de fichário | Fixture da 5888 | Até o aborto | Não bloqueia leituras nem escritas de outras linhas. Conflito só em chave única idêntica, o que é improvável: sufixo aleatório e UUID novo |
| `KEY SHARE` em linhas **reais** referenciadas por FK (jogo, idioma, tipo de variante, raridade, categoria) | Fixture | Até o aborto | Só uma alteração de chave ou exclusão dessas mesmas linhas pelo administrador esperaria |
| Locks de linha nas coleções e participações sintéticas | RPCs da 5888 | Até o aborto | Nenhum: são linhas que ninguém mais vê |

**Duração esperada:** poucos segundos, sem medição. Teto: 20 s por instrução e 15 s de ociosidade. Por causa da primeira linha da tabela, o ensaio exige **janela fora de uso**.

### 2.7 Efeitos que persistem depois do rollback

| Efeito | Persiste? | Avaliação |
|---|---|---|
| DDL, fixture, funções `pg_temp`, tabelas temporárias, `SET LOCAL` | Não | Desfeitos no aborto |
| `default_transaction_read_only` da sessão (T0) | Só na sessão, se ela continuar aberta | Falha segura: a sessão só fica somente leitura. Fechar a conexão resolve |
| Valores de sequência e identidade consumidos (ex.: id de evento do histórico) e OIDs | **Sim** | Lacunas de numeração, sem efeito funcional |
| Tuplas mortas em `pg_proc`, `pg_constraint`, `auth.users` e demais tabelas tocadas | **Sim**, até o vacuum | Volume desprezível |
| Contadores de `pg_stat_*` e entradas em `pg_stat_statements` (texto do ensaio, com nomes sintéticos) | **Sim** | Sem dado real |
| Log do servidor: o erro da sentinela (JSON com resultados e nomes sintéticos) e, conforme `log_statement` (S0-7), o texto do DDL | **Sim** | Sem dado real nem credencial; registrar o que foi logado |
| WAL gerado (backup e PITR o contêm como transação abortada) | **Sim** | Sem efeito lógico |
| E-mail, evento do Auth, webhook, replicação lógica, Storage | **Não ocorrem** | Usuários inseridos direto em `auth.users`, sem GoTrue. A S0-5 exclui gatilhos externos. Transação abortada não é decodificada. A 5888 não grava no Storage |

### 2.8 Verificação posterior (só leitura, imediatamente depois)

Repetir a S0. Ela precisa ser **idêntica** à anterior em:

- md5;
- CHECK;
- ACL;
- número de sobrecargas;
- zero linhas com marcas sintéticas (`wh888*` em `user_profile` e `auth.users`, `EDR*`, `CO/CX 5888`, `EDR K1`).

As contagens gerais (`auth.users`, participações, coleções) são **informativas** (v1.3): o uso real pode mudá-las entre as duas leituras, e por isso não provam nem reprovam o ensaio.

Além disso:

- `pg_stat_activity` e `pg_locks` sem resto do ensaio;
- `SHOW default_transaction_read_only` = `off` em qualquer sessão que continue aberta;
- `P1_POST_txid_readonly.sql` com o `txid` da sentinela = `aborted`. Essa é a prova, dada pelo servidor, de que nada foi confirmado; `committed` é um incidente.

**Aprovação:**

- último erro com SQLSTATE **`E1AOK`** e mensagem `MSDRYRUN_E1A APROVADO {json}` (GATE 54/54). `E1ANO` = reprovado; qualquer outro SQLSTATE = falha antes da sentinela, com a fase indicada pela linha. A tabela completa está em `p1/README.md` (v1.3; antes era `P0001`, o mesmo código dos prechecks, o que deixava o desfecho ambíguo);
- `txid_status` = `aborted`;
- pós-estado igual à S0;
- duração dentro dos tetos.

**Válido não é PASS:** uma sentinela legível com algum `false` é um resultado válido e **reprovado**.

### 2.9 Quando o procedimento deve ser recusado

- Sem autorização específica do proprietário para aquela execução (hash, executor, canal e janela).
- Arquivo de ensaio não gerado pelo script, hash divergente ou verificador de mutações não aprovado.
- PostgreSQL abaixo de 14, ou suporte de T3 diferente do registrado no arquivo gerado.
- Qualquer item da S0 divergente, inclusive gatilho externo.
- Conexão por pooler em modo transação ou statement, SQL Editor, `apply_migration`, `psql -1` ou sessão interativa.
- Janela com uso real das superfícies compartilhadas, ou transação longa em `collection_membership`.
- Qualquer dado real exigido como fixture.
- Pedido para "repetir até passar" depois de um STOP sem diagnóstico.

**Estado atual: P1 especificado, pronto para revisão, NÃO pronto para execução.** Faltam:

- gerar o arquivo e o verificador, o que depende de autorização;
- rodar a S0, que exige leitura do LIVE;
- verificar a versão do PostgreSQL e o modo de conexão.

Não há comando pronto para produção nesta pasta.

### 2.10 Artefato preparado (`p1/`, 2026-11-15)

| Arquivo | Papel |
|---|---|
| `p1/build_p1_dryrun_e1a.py` | Gerador determinístico. `--check` confere que o artefato e o MANIFEST estão em dia |
| `p1/P1_DRYRUN_E1A_rollback.sql` | Ensaio gerado (T0–T11). **Não executado; bloqueado** até a S0, a revisão independente e a autorização |
| `p1/P1_S0_POST_readonly.sql` | S0 e pós-estado: um único SELECT, sem escrita. **Não executado** (leitura do LIVE não autorizada) |
| `p1/verify_p1_dryrun_e1a.py` | Verificador estático independente (lexer próprio, não importa o gerador). v1.3: 34 verificações de texto e autoteste com 30 mutações (antes: 30 e autoteste com 22 mutações |
| `p1/P1_POST_txid_readonly.sql` | Prova de rollback pelo servidor (`txid_status`), um SELECT. Não executado |
| `p1/MANIFEST.sha256` | sha256 das fontes, do artefato, da S0, do txid e do gerador (10 arquivos) |
| `p1/README.md` | Arquitetura, garantias, limites, bloqueios e pré-condições |

Diferenças em relação à §2.2:

- **ON_ERROR_STOP no arquivo:** a primeira linha é `\set ON_ERROR_STOP on`. Num canal que não seja o psql, essa linha falha antes de qualquer instrução SQL.
- **Precheck do servidor (T6):** confere no próprio servidor que a transação é READ WRITE, que T0 vigora na sessão, que os gatilhos estão ativos (`session_replication_role = origin`), que o executor é `postgres`, que a trava está adiada e que não há gatilhos externos nem locks antigos. Se uma instrução escapar do bloco, ou se a sessão trocar de backend, a T6 aborta **antes** de qualquer DDL.
- **Sentinela:** só aprova com 54/54, trava intacta e duração ≤ 10 s.

## 3. Fases da validação

| Fase | O quê | Estado |
|---|---|---|
| **P0** | `static_check_e1a.py` | **Feita:** 68/68 PASS. **Não é prova dinâmica** |
| **P1** | Ensaio da §2 | Especificado; depende de geração, S0 e autorização |
| **P2** | Aplicação de 5366 → 5370, uma por vez, por psql, com os pre/postchecks de cada arquivo (inclusive a paridade de ACL da v1.1) | Depende de P1 PASS, de S0 repetida e de autorização |
| **P3** | Aceite pós-aplicação: S0/pós-estado só leitura, mais a 5888, mais a regressão V1-12 (5861 v1.4, 5862, 5863, 5864). Cada harness com T0–T6, T8 e T9 da §2.2, ou seja, a mesma moldura **sem** T7 | Depende de P2 e de autorização |
| **P4** | Homologação pela tela atual: convite VIEWER e coleção compartilhada aberta como membro. Cobre a limitação L1, a resolução pelo PostgREST | Depende de P3 |

## 4. Concorrência — S8 concorrente e S10 (pendentes)

Os dois cenários continuam **pendentes**. Nenhuma conta, fixture confirmada ou sessão de escrita foi criada ou proposta para execução.

Uma transação desfeita não serve: a segunda sessão não enxerga a fixture não confirmada da primeira. Qualquer prova futura precisa, **no mínimo**:

1. **Autorização própria**, separada da P1/P3, depois de decisão expressa do proprietário sobre efeitos confirmados em produção.
2. **Dados visíveis às duas sessões**, portanto confirmados. Só com contas de teste criadas pelo proprietário (o agente não cria contas), coleções **privadas** dessas contas e **catálogo real** (catálogo sintético confirmado é vedado). Nenhum dado de usuário real.
3. **Separação inequívoca:** prefixo reservado, lista fechada de ids, verificação antes e depois de que nenhuma linha fora da lista mudou.
4. **Compensação definida antes:** exclusão em cascata das contas de teste e verificação de resíduo zero, incluindo o histórico do fichário (C-203: a exclusão da conta remove os eventos dela) e o Storage.
5. **Duas sessões coordenadas** por lock consultivo, com a ordem dos passos fixada e `lock_timeout`/`statement_timeout`. Critério: sem impasse (ou impasse detectado e uma das duas desfeita), sem estado parcial e com a regra de C-237 preservada.
6. **Alvo:** só existe depois da E1-B, quando o EDITOR passa a escrever. Na E1-A, a troca de papel, o convite e a resposta são serializados pela trava da coleção e da participação, o que foi verificado por inspeção.
7. A mesma prova serviria à **PR-04B** (5364), que continua aberta.

Sem essa prova, a publicação da V1-13 continua **bloqueada** pela C-244 revisada.

## 5. Estado S1–S10

| Cenário | Situação |
|---|---|
| S2 escrita fora da coleção | E1-A: parcial (o EDITOR não convida nem gerencia). Prova dinâmica pendente (P1/P3) |
| S6 ações do titular | E1-A: parcial (membros e papéis). Prova dinâmica pendente |
| S7 VIEWER, estranho e anon | E1-A: parcial (participação e papel). Prova dinâmica pendente |
| S8 troca, remoção e saída, sequencial | E1-A: coberto pela 5888 (4.3, 5.11, 5.12). Prova dinâmica pendente |
| S8 com escrita concorrente | **Pendente e sem caminho autorizado** (§4) |
| S9 privacidade | E1-A: parcial (chave `role`, cabeçalho). Prova dinâmica pendente |
| S10 concorrência titular × EDITOR | **Pendente e sem caminho autorizado** (§4) |
| S1, S3, S4, S5 | Fora da E1-A (E1-B/E1-C) |

**Nenhum cenário está comprovado dinamicamente.**

## 6. C-244 (aplicada nesta rodada)

Texto vigente em `concept-decisions.md` (revisão 1.37):

- sem ambiente isolado;
- prova dinâmica obrigatória;
- operação no banco existente só com protocolo controlado e autorização específica, dados sintéticos e efeitos reversíveis ou compensáveis;
- comprovação dinâmica suficiente de cada cenário S1–S10, sem substituição por aceitação de risco nem por análise estática (revisão 1.38);
- PR-04B aberta até a reavaliação;
- publicação com escrita entre contas bloqueada sem comprovação suficiente;
- a revisão não autoriza execução.

Ajustes correlatos aplicados:

- `05d` v3.14 (seção V1-13);
- `ROADMAP` v3.73 (linha V1-13);
- cabeçalho da 5888;
- verificação estática 11.3;
- README desta pasta;
- `log.md`.

## 7. Harness 5861 (V1-12)

**Inalterado nesta rodada.**

- **v1.4:** correção mínima, com as mesmas 51 verificações. Verificação estática 14.1–14.3.
- **Efeito da E1-A sobre a v1.3:** passaria a falhar em 0.1 e 3.1, e a 0.3 perderia em silêncio a cobertura do convite.
- **Outros harnesses:** 5862 e 5863 continuam válidos; 5864 não usa o convite.
- **`ROLLBACK_v1_12.sql`:** exige `ROLLBACK_E1A.sql` antes.
- **Execução:** a regressão da 5861 v1.4 roda na P3, com a moldura da §2.2.
