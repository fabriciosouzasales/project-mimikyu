# V1-13 · E1-A — artefato do ensaio P1 (para revisão independente)

| Campo | Valor |
|---|---|
| **Rodadas** | `P1 ARTIFACT PREPARATION-03` (2026-11-15); `P1 INDEPENDENT ARTIFACT AUDIT-04` (2026-11-15): achados corrigidos (§Auditoria) |
| **Estado** | **PREPARADO LOCALMENTE. NÃO EXECUTADO. EXECUÇÃO BLOQUEADA.** Nenhuma leitura ou escrita no LIVE foi feita. **E1-A sem prova dinâmica.** |
| **Desbloqueio** | (1) S0 (`P1_S0_POST_readonly.sql`) executada com autorização e aprovada; (2) revisão deste pacote; (3) janela fora de uso; (4) autorização expressa e específica do proprietário para o ensaio (hash, executor, canal, janela). A C-244 (revisão 1.38) não autoriza execução. |
| **Protocolo** | `../VALIDATION-STRATEGY-E1A.md` v1.3, §2 |

## Arquivos

| Arquivo | Papel |
|---|---|
| `P1_DRYRUN_E1A_rollback.sql` | Ensaio gerado (T0–T11). Não editar à mão |
| `P1_S0_POST_readonly.sql` | S0 (antes) e pós-estado (depois): um único SELECT |
| `P1_POST_txid_readonly.sql` | Prova, pelo servidor, de que a transação do ensaio foi desfeita (`txid_status` = `aborted`) |
| `build_p1_dryrun_e1a.py` | Gerador determinístico; `--check` |
| `verify_p1_dryrun_e1a.py` | Verificador estático independente (lexer próprio; não importa o gerador). Fica fora do MANIFEST: registrar o sha256 na revisão |
| `MANIFEST.sha256` | sha256 de 10 arquivos: fontes 5366–5370 e 5888, ensaio, S0, txid e gerador |

Verificação local, sem banco:

```
python3 -I build_p1_dryrun_e1a.py --check     # EM DIA
sha256sum -c MANIFEST.sha256                  # 10 × OK
python3 -I verify_p1_dryrun_e1a.py            # 34/34 + 30/30 mutações
python3 -I ../static_check_e1a.py             # 68/68
```

## Arquitetura do ensaio

```
\set ON_ERROR_STOP on                      só o psql entende; outro canal falha aqui, antes de tudo
\set VERBOSITY verbose                     o psql mostra SQLSTATE e linha de cada erro
T0  SET SESSION default_transaction_read_only = on
T1  BEGIN
T2  SET TRANSACTION READ WRITE
T3  SET LOCAL lock_timeout 2s / statement_timeout 20s / ociosidade 15s
    DO: recusa PG < 14; client_connection_check_interval 1s; transaction_timeout 60s se PG ≥ 17
T4  trava de COMMIT (FK temporária DEFERRABLE INITIALLY DEFERRED + linha órfã)
T5  evidência (tabelas temporárias)
T6  DO precheck no servidor (READ WRITE; T0 vigente; session_replication_role = origin;
    sem recuperação; executor postgres; trava adiada; sem gatilho com efeito externo;
    sem lock antigo ou de início invisível em collection_membership)
    LOCK TABLE public.collection_membership IN ACCESS EXCLUSIVE MODE NOWAIT  → obtém já ou falha
T7  5366 → 5370, texto aprovado entre begin;/commit;, nível superior (sha256 no marcador)
T8  5888: quatro funções pg_temp (texto aprovado) + INSERT do relatório na evidência
T9  DO postcheck (só leitura) + DO sentinela: UM RAISE incondicional
      SQLSTATE E1AOK + 'MSDRYRUN_E1A APROVADO {json}'   ou
      SQLSTATE E1ANO + 'MSDRYRUN_E1A REPROVADO {json}'
T10 ROLLBACK           (só alcançado fora do contrato)
T11 RESET default_transaction_read_only
```

## Classificação do desfecho

A classificação usa o **último** erro que o psql mostra (SQLSTATE e linha, por `VERBOSITY verbose`) e o código de saída (3 = parou em erro).

| Observado | Classificação |
|---|---|
| `E1AOK` + `MSDRYRUN_E1A APROVADO {...}` (`ok: true`, `gate: PASS`, 54/54, `trap_intact`, `duration_ms` ≤ 10000) | Ensaio concluído e aprovado. Ainda falta provar o rollback e o estado posterior (abaixo) |
| `E1ANO` + `MSDRYRUN_E1A REPROVADO {...}` | **Reprovado.** O harness rodou: `harness_concluido` e `failed`. Se a fixture falhou, o detalhe vem em `erro_na_fixture` (F.1/X.1) |
| `55P03` na linha do `LOCK … NOWAIT` (T6) | Recusa por ocupação: havia lock em `collection_membership`. Nada foi aplicado. Repetir só com nova autorização |
| Outro SQLSTATE ou mensagem | Falha **antes** da sentinela. A linha indica a fase: T3–T6 ambiente e prechecks; T7 migration (`PRECHECK/POSTCHECK 53xx`); T8 harness fora da fixture, inclusive `57014` de tempo; T9 postcheck |
| Nenhum erro, código 0, ou mais de uma mensagem `MSDRYRUN_E1A` | **Anomalia grave: STOP** |

Nenhum desfecho é PASS só porque a transação terminou. O ensaio só passa com os três itens abaixo:

1. Sentinela `E1AOK`.
2. `P1_POST_txid_readonly.sql`, com o `txid` do JSON, retornando `aborted`. O servidor confirma que nada foi confirmado. `committed` é um **incidente**.
3. `P1_S0_POST_readonly.sql` depois do ensaio com as chaves `[=]` iguais às da S0. Resíduos por marca sintética ficam em 0. As contagens `[~]` são só informativas.

## Garantias

**Comprovadas por inspeção do texto** (verificador 34/34; 30/30 mutações detectadas sem usar hash):

- **Ordem e transação:** a ordem T0…T11; uma única transação explícita READ WRITE; nenhum COMMIT, END, ABORT, SAVEPOINT, RELEASE, PREPARE ou SET CONSTRAINTS; um único ROLLBACK, no fim.
- **Nada escondido:**
  - nenhum controle de transação em corpos ou strings executáveis;
  - EXECUTE só com três strings fixas;
  - `set_config` só local e só com parâmetros de uma lista fechada (exclui `session_replication_role`);
  - SET LOCAL só dos três limites.
- **Passos gerados:** só as instruções previstas, com um único LOCK (`collection_membership`, NOWAIT). Corpos gerados só escrevem nas tabelas temporárias do ensaio, e a T9 só lê.
- **Trava e sentinela:**
  - a trava de COMMIT está presente, adiada e intocada;
  - a sentinela é incondicional, com SQLSTATE próprio, e as marcas do desfecho só existem nela.
- **Fidelidade:** migrations e 5888 idênticas byte a byte aos aprovados.
- **Conteúdo:**
  - nenhum comando externo ou administrativo;
  - GRANT/REVOKE só nas migrations;
  - nenhuma credencial, URI, token, UUID fixo ou e-mail real.
- **Arquivos de leitura:** S0 e txid são SELECT únicos.

**Dependem de execução real** (não comprovadas): a lista completa é impressa pelo verificador. Inclui:

- atomicidade e reversão pelo servidor;
- o veto da FK adiada;
- T0 vigorar na mesma sessão física;
- versão e ambiente do LIVE;
- duração real do lock;
- resultado da 5888;
- efeitos remanescentes;
- comportamento do psql e do executor;
- `txid_status`.

## Auditoria independente (`P1 INDEPENDENT ARTIFACT AUDIT-04`, 2026-11-15)

**Examinado:**

- os 10 arquivos do MANIFEST (`sha256sum -c`, 10 × OK);
- o ensaio, linha a linha nos pontos de controle;
- a T7, comparada com as fontes por extração independente (`awk`), 5/5 idênticas;
- o verificador, testado com mutações novas;
- a S0;
- o README e a estratégia.

| # | Achado | Classe | Correção |
|---|---|---|---|
| A1 | O desfecho era ambíguo: a sentinela usava `P0001`, o mesmo SQLSTATE de todos os prechecks e postchecks; o psql, por padrão, não mostra o SQLSTATE; uma aprovação e uma reprovação diferiam só dentro do JSON | **Bloqueante** | SQLSTATE próprio `E1AOK`/`E1ANO`, prefixo `APROVADO`/`REPROVADO`, um único RAISE com código por variável, `\set VERBOSITY verbose`, e a verificação S25 (as marcas só existem na sentinela) |
| A2 | O verificador tinha pontos cegos estruturais: instrução extra nos passos gerados (DELETE real na T5, UPDATE ou INSERT reais nos corpos da T6/T9, sentinela falsa antes da T7) só era detectada pelo hash. Confirmado com 4 mutações não detectadas | **Bloqueante** | S23 (inventário exato dos passos gerados), S24 (DML só em `pg_temp.p1_e1a_*`; T9 sem DML), S25, e 8 mutações novas no autoteste |
| A3 | O pós-estado exigia contagens "idênticas", que mudam com uso real (falso STOP ou conclusão impossível), e não havia prova do servidor de que a transação foi desfeita | **Bloqueante** | Contagens passam a `[~]` informativas; resíduos por marca também em `auth.users` e `card`; novo `P1_POST_txid_readonly.sql` (`txid_status`) |
| A4 | A T6 e a S0 ignoravam sessões cujo início de transação não é visível (sem `pg_read_all_stats`, `xact_start` vem NULL e a condição dava falso) | **Bloqueante** | NULL conta como risco; a S0 informa a visibilidade |
| A5 | Fila de lock: a 5366 esperava até 5 s pelo `ACCESS EXCLUSIVE`, e nesse tempo as novas leituras de `collection_membership` ficavam enfileiradas atrás dela | Não bloqueante (mitigado) | `LOCK … NOWAIT` na T6: obtém na hora ou falha com `55P03`, sem formar fila. A duração depois de obtido não muda (A6) |
| A6 | Duração do lock depois de obtido: da T6 ao aborto, cobrindo T7–T9 e toda a 5888. Por instrução, o teto é 20 s; no total, só há limite com PG ≥ 17. Ficam bloqueadas **todas** as consultas que referenciam a tabela: leituras do participante (via 5302 e 5310), "Compartilhadas com você" na Biblioteca (5311), painel, convites, respostas e saídas. A vitrine pública (5317/5318/5322/5327) não referencia a tabela e não é afetada, conforme inspeção das canônicas. Elas podem falhar pelo `statement_timeout` dos papéis da API | Não bloqueante para o **artefato**; **bloqueia a execução** até haver janela | Janela fora de uso decidida pelo proprietário; `lock_ms` medido no JSON; `papeis_api` na S0. Indisponibilidade **não** está descartada |
| A7 | A detecção de efeito externo é por padrão de texto no corpo da própria função de gatilho; chamadas indiretas não são seguidas | Não bloqueante | A S0 lista os gatilhos e as funções para revisão manual. Limite declarado |
| A8 | Conexão direta × pooler não é detectável por SQL de forma confiável | Não bloqueante | A T6 recusa, no servidor, se T0 não vigorar. A escolha do canal fica para a S0 (operacional) |
| A9 | `psql -1` também seria seguro (a sentinela aborta antes do COMMIT final), mas continua proibido pelo contrato | Informativo | — |

**Integridade transacional confirmada** (inspeção mais a semântica documentada do PostgreSQL; **não executada**):

- **Single statement stream:** o psql `-f` envia as instruções em sequência na mesma sessão.
- **READ ONLY × READ WRITE:** são compatíveis. T0 muda só o padrão da sessão. `SET TRANSACTION READ WRITE` é aceito como primeira instrução do bloco, antes de qualquer snapshot, fora de recuperação e fora de subtransação.
- **Trava de COMMIT:** a FK adiada é verificada no COMMIT antes da ação `ON COMMIT DROP`.
- **Neutralização da trava:** só editando o arquivo (todas as formas testadas são detectadas) ou por `session_replication_role` por padrão do papel (conferido na T6).
- **Erros cedo:** com `ON_ERROR_STOP`, um erro antes do BEGIN não deixa nada. Um erro na T1–T6 encerra o psql, a conexão fecha e o servidor desfaz.

## Pré-condições pendentes

1. Autorização para a S0 (leitura do LIVE). Ela precisa confirmar:
   - PG ≥ 14;
   - md5 canônicos;
   - E1-A não aplicada;
   - pré-requisitos da fixture;
   - nenhum gatilho com efeito externo, mais revisão manual da lista;
   - visibilidade de sessões;
   - nenhuma sessão antiga;
   - timeouts da API registrados.
2. Canal: psql em conexão direta ou pooler em modo sessão, nunca em modo transação.
3. Revisão deste pacote, registrando o sha256 do verificador.
4. Janela fora de uso e autorização expressa do ensaio.
5. Depois do ensaio: `txid_status` = `aborted` e pós-estado conforme.

**Continua valendo:**

- a E1-A não tem prova dinâmica;
- S8 concorrente e S10 estão pendentes;
- a PR-04B está aberta;
- não há ambiente isolado;
- a publicação da V1-13 está bloqueada (C-244).
