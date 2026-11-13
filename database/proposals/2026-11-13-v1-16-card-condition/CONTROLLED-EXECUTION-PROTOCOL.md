# V1-16 — Protocolo de execução controlada (S0–S4)

| Campo | Valor |
|---|---|
| **Origem** | `V1-16 \| CONTROLLED EXECUTION READINESS-01` (2026-11-13). Rodada documental e estática: **nada foi executado**, nenhum banco foi acessado. |
| **Substitui** | `OFFLINE-VALIDATION-RUNBOOK.md` (container descartável). Esse arquivo fica preservado como registro histórico, marcado SUBSTITUÍDO. Motivo: o proprietário proibiu ambientes isolados, containers, réplicas e bancos de teste. |
| **Ambiente** | **Um só**: o ambiente autorizado pelo proprietário, sob controle dele. É o banco de **produção**: não é isolado, não é réplica e não é banco de teste. Todo o texto abaixo parte dessa premissa. |
| **Executor** | Fabrício, **uma etapa por vez**. Cada etapa começa só depois de uma autorização explícita, concedida depois da análise da evidência da etapa anterior. A S1 **não** começa automaticamente depois da S0. |
| **Classificação** | **READY FOR S0** (ver §10). S1 teve STOP (42P01 na 5361 v1.0, §11) e foi **ENCERRADA como D2 — aplicada e validada** (§11, "Resolução"). **S2: READY FOR S2 AUTHORIZATION** (§12). |

## 1. Princípios desta execução

1. **ROLLBACK não torna um teste seguro para produção por si só.** Cada teste que escreve, mesmo desfeito, foi avaliado pelos efeitos que **sobrevivem** ao ROLLBACK ou que **acontecem durante** a transação (§6). Ele só roda se esses efeitos forem aceitáveis e estiverem sob controle.
2. **Um commit acidental tem de ser impossível, não apenas improvável.** Todo harness roda numa versão de **chamada única** (`controlled-execution/*_singlecall.sql`):
   - o arquivo não contém nenhum `COMMIT` (o gerador verifica);
   - o relatório sai por `RAISE EXCEPTION`, que aborta a transação por construção.
3. **Cada canal tem uma função.** Leitura, migração e harness têm canais permitidos diferentes (§2). Um harness **nunca** roda pelo SQL Editor nem por `apply_migration`.
4. **Toda falha é fechada.** As migrations recusam estado divergente e reaplicação (PRECHECK). Elas também abortam se o resultado não for o esperado (POSTCHECK). As recuperações fazem o mesmo (§7).
5. **A evidência não leva dados pessoais.** Nada de UUID, e-mail ou nome de usuário. Desde o `S0 READ-ONLY SAFETY CHECK`, a S0 e o POSTCHECK não trazem nenhuma linha que identifique usuário.

## 2. Canais

| Uso | Canal permitido | Proibido |
|---|---|---|
| **Leitura** (S0, POSTCHECK) | SQL Editor do Supabase **ou** psql em modo somente leitura | — |
| **5361 v1.1** (instrução única) | psql (recomendado) ou SQL Editor | `apply_migration`, salvo autorização explícita |
| **5362–5364** e **recuperação** (R4–R1), que têm várias instruções entre `begin;` e `commit;` | **psql apenas** (§11: a falha da 5361 v1.0 mostrou que o SQL Editor não garantiu uma transação única entre instruções) | SQL Editor; `apply_migration`, salvo autorização explícita por etapa |
| **Harness** (5887 recortes, 5822, 5823, 5824, 5826) | **psql**, só os arquivos de chamada única | SQL Editor; `apply_migration`; arquivos originais de três chamadas; `psql -1` / `--single-transaction` (acrescenta COMMIT) |
| Agente via MCP `execute_sql` | Só com autorização explícita do proprietário **por etapa** (precedente: 5822 em chamada única, 2026-09-09) | Qualquer chamada sem essa autorização |

**Por que psql para harness e de preferência para migrations:**

- **Sessão e erro.** Uma sessão psql é uma conexão única e verdadeira. Com `ON_ERROR_STOP=1`, qualquer erro encerra o psql. A conexão cai, o servidor desfaz a transação e solta as travas.
- **Transação abortada no SQL Editor.** Num script enviado de uma vez, um erro depois de um `BEGIN` explícito deixa a transação aberta em estado abortado: as instruções seguintes, incluindo o `ROLLBACK` final, não rodam.
  - Como o SQL Editor reaproveita a conexão, isso **não foi medido** neste projeto: é o risco residual RR-1. Uma transação abortada que fica aberta **mantém as travas**.
  - No caso da 5361, a trava seria ACCESS EXCLUSIVE em `physical_card`, o que bloqueia o acervo de todos os usuários.
- **Relatório escondido.** O SQL Editor mostra só o resultado da última instrução. Nos arquivos de três chamadas, essa instrução é o `ROLLBACK`.
- **Commit pela CALL 1.** Já foi medido que o MCP `execute_sql` não preserva sessão. O protocolo literal de três chamadas **comitaria a CALL 1** (README do BULK-02, §"Transporte").
- **Bytes do arquivo.** O psql `-f` envia os bytes do arquivo sem alteração. Os POSTCHECKs da 5362–5364 comparam o md5 dos corpos. Um canal que converta fim de linha (incidente CRLF da 2217) faz a etapa falhar fechada, sem dano, mas sem avanço.

**Conexão psql:**

- Use a conexão **direta** ou o **Session pooler** (porta 5432).
- **Nunca** use o Transaction pooler (6543).
- `sslmode=require`.
- A senha é digitada quando o psql pedir. Ela nunca vai para arquivo, variável persistida ou histórico.

## 3. Preparação (uma vez, na máquina do proprietário)

```powershell
$Repo = 'C:\Users\Administrador\Documents\Coleção Pokémon\00. Desenvolvimento do Sistema Mimikyu\02 - Repositório de Dados\project-mimikyu'
$P    = Join-Path $Repo 'database\proposals\2026-11-13-v1-16-card-condition'
$CE   = Join-Path $P 'controlled-execution'
$B02  = Join-Path $Repo 'database\proposals\2026-09-08-bulk-02-register-physical-cards'
$B04  = Join-Path $Repo 'database\proposals\2026-10-16-bulk-04-register-card-set'
$Ev   = 'C:\v116-evidence'                 # evidência local, FORA do repositório (não versionar)
New-Item -ItemType Directory -Force -Path $Ev | Out-Null
$Db   = '<URI do Session pooler ou da conexão direta, SEM senha, com ?sslmode=require>'

# leitura: transação somente leitura forçada pelo servidor
function V116-Read([string]$File, [string]$Tag) {
  $env:PGOPTIONS = '-c default_transaction_read_only=on'
  & psql -X -v ON_ERROR_STOP=1 -P pager=off -d $Db -f $File 2>&1 | Tee-Object -FilePath (Join-Path $Ev "$Tag.txt")
  $rc = $LASTEXITCODE; Remove-Item Env:PGOPTIONS; "rc=$rc" | Tee-Object -FilePath (Join-Path $Ev "$Tag.txt") -Append
}
# migration / recuperação / harness
function V116-Run([string]$File, [string]$Tag) {
  & psql -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -P pager=off -d $Db -f $File 2>&1 | Tee-Object -FilePath (Join-Path $Ev "$Tag.txt")
  "rc=$LASTEXITCODE" | Tee-Object -FilePath (Join-Path $Ev "$Tag.txt") -Append
}
```

Verificações locais antes de qualquer etapa:

- `psql --version` deve ser 15 ou mais (de preferência 17).
- Integridade dos derivados: `Get-FileHash -Algorithm SHA256 (Join-Path $CE '*.sql') | Format-Table Hash, Path`. Cada hash deve bater com `controlled-execution/MANIFEST.sha256`. Com Python disponível, o equivalente é `python derive_singlecall.py --check` (em `$CE`): deve terminar com `rc=0` e todos os arquivos `OK`, o que prova também que os derivados correspondem às origens atuais.
- `git status` não deve mostrar nenhuma alteração nos SQLs 5361–5364, no 5887 nem nos harnesses legados depois desta rodada.

Sem psql disponível, só a S0 e os POSTCHECKs podem rodar, pelo SQL Editor. As etapas S1 em diante dependem de uma decisão de canal (§10).

## 4. Classificação dos testes

| Classe | Itens | Pode rodar no ambiente autorizado? |
|---|---|---|
| **A — Somente leitura** | `S0_readonly_precheck.sql`, `POSTCHECK_readonly.sql` | **Sim.** Uma instrução `SELECT` cada. |
| **B — Mutação definitiva prevista** | `5361`–`5364` (são o objetivo) · `R4`–`R1` (só por decisão) | Sim, uma por etapa, com GO da anterior. |
| **C — Escrita desfeita por construção, segura sob condições** | `5887_S1…S4_singlecall`, `5822_singlecall`, `5823` (original, já de chamada única), `5824` (original, já de chamada única), `5826_singlecall` | Sim, **só** quando todas as condições abaixo valem. |
| **D — Exige adaptação (feita, por derivação)** | `5887` original, `5822` original, `5826` original (três chamadas) | Não diretamente. Rodam **somente** na versão derivada da classe C. |
| **E — Não executar** | `CONCURRENCY-5364-TWO-SESSIONS.sql`; `OFFLINE-VALIDATION-RUNBOOK.md`; qualquer harness pelo SQL Editor, por `apply_migration` ou com `psql -1` | **Não.** Ver §6.3. |

**Condições obrigatórias da classe C:**

1. Os usuários u1 e u2 dos harnesses (os dois primeiros de `auth.users`) são contas **controladas pelo proprietário**. A verificação de identidade saiu da S0 (S0-18/S0-19 removidas). Se um harness vier a ser autorizado, ela é feita numa verificação própria, nessa rodada. **Hoje nenhum harness está autorizado:** o uso de contas reais e a alteração temporária de variantes do catálogo não foram aprovados.
2. Janela sem uso do acervo nem do Catálogo Editorial: S0-25 e P-14 sem transações longas.
3. Arquivo de chamada única, rodado pelo psql.
4. POSTCHECK depois de cada harness, com P-12 igual ao baseline.

**Derivações (classe D → C).** O script `controlled-execution/derive_singlecall.py` gera os arquivos derivados.

- **Dois tipos de mudança.**
  - Os recortes da 5887 removem grupos inteiros ainda não aplicáveis.
  - Todos os derivados trocam o bloco "RELATÓRIO FINAL … ROLLBACK" por um `DO` que levanta o relatório com o **mesmo** gate.
- **Fidelidade à origem.** O script verifica que o corpo de cada derivado é uma subsequência literal, linha a linha, da origem. Também verifica que não há `COMMIT`. O SHA-256 da origem fica gravado no cabeçalho.
- **Defeito que motivou a derivação.** O transporte de três chamadas comita a CALL 1 em canal sem sessão (medido em 2026-09-09) e esconde o relatório no SQL Editor.
- **Nenhum caso de teste foi alterado.** O 5887 original **não** foi alterado.

| Derivado | Origem (SHA-256) | Gate |
|---|---|---|
| `5887_S1_singlecall.sql` (X01+F+A) | `5887` `e0eac792…` | 9/9/0/0 |
| `5887_S2_singlecall.sql` (+B, X02) | idem | 34/34/0/0 |
| `5887_S3_singlecall.sql` (+C) | idem | 41/41/0/0 |
| `5887_S4_singlecall.sql` (tudo) | idem | 66/66/0/0 |
| `5822_singlecall.sql` | `5822` `81e244cf…` | 64/64/0/0 |
| `5826_singlecall.sql` | `5826` `e052d6fe…` | 56/56/0/0 |

`5823` v2.3 (gate 60/60/0/0) e `5824` v1.1 (30/29/0/1, um NOT PROVEN por desenho) **já são** de chamada única por `RAISE EXCEPTION` e rodam sem derivação.

**Como ler o resultado de um harness (psql):**

- **Sucesso.** O psql termina com `rc=3` e um `ERROR`:
  - 5887, 5822, 5826 e 5823: SQLSTATE `55000`;
  - 5824: SQLSTATE `P0001`, mensagem "5824 GATE:".
- **Texto exigido para GO:**
  - 5887 e derivados: `GATE_OK = true` e `TOTAL=N PASS=N FAIL=0`;
  - 5823: `GATE_OK = true`;
  - 5824: `GATE OK`.
- **STOP:**
  - qualquer outro SQLSTATE;
  - `GATE_OK = false`, `GATE FALHOU` ou `rc=0`.
  - `rc=0` significa que o relatório não foi levantado. Isso é **anômalo**: rode o POSTCHECK imediatamente.

## 5. Etapas

Toda etapa segue o mesmo ritual:

1. **POSTCHECK de abertura** (P-14 e P-15 = `nenhuma`).
2. **Execução.**
3. **POSTCHECK de fechamento.**
4. **Evidência** em `$Ev`, redigida.
5. **Pausa.** O agente analisa e o proprietário decide a próxima etapa.

### S0 — baseline e pré-condições (somente leitura)

| | |
|---|---|
| **Pré-condição** | Nenhuma. É a primeira ação. |
| **Comando** | SQL Editor: colar e rodar `controlled-execution/S0_readonly_precheck.sql` **e depois** `controlled-execution/POSTCHECK_readonly.sql`. Ou, pelo psql: `V116-Read "$CE\S0_readonly_precheck.sql" S0` e `V116-Read "$CE\POSTCHECK_readonly.sql" S0-post`. |
| **Evidência** | As duas grades completas: 26 linhas da S0 (S0-01 a S0-17 e S0-20 a S0-28; 04–08 são as cinco funções; S0-18/S0-19 foram removidas) e 15 linhas do POSTCHECK. Informar também `psql --version`. |
| **GO** | Nenhuma linha STOP; P-01 = `S0 (nada aplicado)`; S0-20 = 0. |
| **STOP** | Qualquer STOP. |
| **Anotar** | S0-14 (baseline de contagens), P-13 (variantes inativas), S0-01 e S0-21 a S0-28. |

### S1 — 5361 e validação

| | |
|---|---|
| **Pré-condição** | S0 GO e autorização da S1; janela sem uso; backup/PITR do projeto confirmado no painel; P-14/P-15 `nenhuma`. |
| **Comandos** | 1) `V116-Run "$P\5361_add_physical_card_condition_code.sql" S1-mig` · 2) `V116-Read "$CE\POSTCHECK_readonly.sql" S1-post` · 3) `V116-Run "$CE\5887_S1_singlecall.sql" S1-h5887` · 4) `V116-Read "$CE\POSTCHECK_readonly.sql" S1-post2` |
| **Evidência** | 1) `rc=0` e `DO` na saída (5361 v1.1 é uma instrução única) · 2) P-01 = `S1 (5361)`, P-02 `fk=true`, P-03 = `0`, P-12 idêntico a S0-14 · 3) `rc=3`, 55000, `TOTAL=9 PASS=9 FAIL=0`, `GATE_OK = true` · 4) P-12 idêntico a S0-14 (zero resíduo), P-11 zeros, P-14/P-15 `nenhuma` · 5) frontend publicado: abrir Meu acervo e o detalhe de uma carta (só navegação). |
| **GO** | Todos os itens acima. |
| **STOP** | Ver a tabela de STOP abaixo. |

### S2 — 5362, testes e regressões legadas

| | |
|---|---|
| **Pré-condição** | S1 GO e autorização da S2. |
| **Comandos** | 1) `V116-Run "$P\5362_extend_bulk_registration_with_condition.sql" S2-mig` · 2) POSTCHECK `S2-post` · 3) `V116-Run "$CE\5887_S2_singlecall.sql" S2-h5887` · 4) `V116-Run "$CE\5822_singlecall.sql" S2-h5822` · 5) `V116-Run "$B04\5823_validate_preview_bulk_operation.sql" S2-h5823` · 6) `V116-Run "$B04\5824_validate_bulk_b1_inactive_card_variant.sql" S2-h5824` · 7) `V116-Run "$CE\5826_singlecall.sql" S2-h5826` · **depois de cada harness**: POSTCHECK. |
| **Evidência** | 1) `rc=0` · 2) P-01 = `S2 (5361+5362)`; P-04 `V1-16 (5362)`; P-09 com `auth_validacao=false` e `auth_helper=false` · 3) 34/34/0, `GATE_OK = true` · 4) 64/64/0 · 5) 60/60/0 · 6) `5824 GATE: TOTAL 30 / PASS 29 / FAIL 0 / NOT PROVEN 1 — GATE OK` · 7) 56/56/0 · P-12 idêntico a S0-14 e P-13 igual ao baseline depois de **cada** harness. |
| **GO** | Todos os gates e resíduo zero depois de cada um. |
| **STOP** | Qualquer FAIL. Não seguir para o harness seguinte. |
| **Notas** | A 5824 desativa temporariamente **três variantes reais** do catálogo dentro da transação, e o ROLLBACK as reativa. Por isso **nenhuma edição do Catálogo Editorial** pode ocorrer durante ela. A 5826 cria um Set sintético de 1001 cartas e é a mais demorada. |

### S3 — 5363 e validação

| | |
|---|---|
| **Pré-condição** | S2 GO e autorização da S3. |
| **Comandos** | 1) `V116-Run "$P\5363_evolve_get_my_inventory_item_copies_condition.sql" S3-mig` · 2) POSTCHECK · 3) `V116-Run "$CE\5887_S3_singlecall.sql" S3-h5887` · 4) POSTCHECK |
| **Evidência** | 1) `rc=0` · 2) P-01 = `S3 (5361–5363)`; P-05 `5363 (21 colunas, condition_code)`; P-08 `leitura=true`; P-09 `anon_leitura=false` · 3) 41/41/0 · 4) resíduo zero · 5) frontend publicado: Meu acervo e o detalhe de uma carta abrem normalmente (a coluna nova é ignorada). |
| **GO / STOP** | Como na S1. |
| **Nota** | O SQL Editor pede confirmação por causa do `DROP FUNCTION`. Esse DROP é intencional e fica na mesma transação do CREATE. |

### S4 — 5364 e validação final

| | |
|---|---|
| **Pré-condição** | S3 GO e autorização da S4. |
| **Comandos** | 1) `V116-Run "$P\5364_create_set_my_physical_cards_condition.sql" S4-mig` · 2) POSTCHECK · 3) `V116-Run "$CE\5887_S4_singlecall.sql" S4-h5887` · 4) POSTCHECK |
| **Evidência** | 1) `rc=0` · 2) P-01 = `S4 (5361–5364)`; P-07 = `b569ecdbe202428a6bdc9461c6d62e37`; P-08 `edicao=true`; P-09 `anon_edicao=false` · 3) **66/66/0**, `GATE_OK = true` · 4) resíduo zero; P-03 = `0` (nenhuma condição real foi alterada). |
| **GO** | Banco do V1-16 **validado**, com a concorrência em aberto (§6.3). A promoção para `database/schema/`, o frontend, a homologação e a publicação são rodadas próprias. |
| **STOP** | Como na S1. |

### Tabela de STOP (todas as etapas)

| Sinal | Significado | Ação |
|---|---|---|
| `PRECHECK …: JÁ APLICADA` | A etapa já estava no banco | Parar e rodar o POSTCHECK. Não repetir. |
| `PRECHECK …: ESTADO DIVERGENTE` ou outro PRECHECK | O banco difere do esperado | Parar, sem retry. Reportar a saída. |
| `canceling statement due to lock timeout` | Havia transação concorrente | Nada foi aplicado (a transação abortou). Conferir P-14 e repetir só com nova autorização. |
| `POSTCHECK …` | O resultado gravado difere do proposto | A transação abortou e nada ficou. Reportar. **Não** editar scripts. |
| Harness com FAIL, `GATE_OK = false`, outro SQLSTATE ou `rc=0` | Regressão ou anomalia | Parar a sequência e rodar o POSTCHECK. Reportar o relatório redigido. |
| P-12 diferente do baseline depois de um harness | Resíduo | **Incidente.** Nenhuma etapa nova. Reportar. |
| P-14/P-15 com sessão ou trava pendente | Transação deixada para trás | Ver §7.2. |
| Erro qualquer no SQL Editor (migration) | Possível transação abortada retida | Rodar `rollback;` imediatamente na mesma aba e depois o POSTCHECK (P-14/P-15). |

## 6. Segurança do harness no ambiente autorizado

### 6.1 O que o harness faz de fato

| Efeito | 5887 | Legados | Sobrevive ao ROLLBACK? |
|---|---|---|---|
| Catálogo sintético (`ZZV116_*`, `ZZB04_*`, game sintético na 5823) | sim | sim | **Não.** É invisível a outras sessões (MVCC) e o Realtime só decodifica COMMIT. |
| `physical_card` nos inventários de u1/u2 | sim | sim | Não |
| `bulk_operation` (claims de idempotência) | sim | sim | Não. A chave não fica consumida. |
| `collection` / `storage_container` de fixture (`… HARNESS …`) | não | 5822/5823/5826 | Não |
| `inventory` (só se u1/u2 não tiverem) | condicional | condicional | Não. O provisionamento por gatilho já cria. |
| **Catálogo real**: `UPDATE card_variant SET is_active` em 3 variantes | não | **5824** | Não, mas **trava** essas linhas durante a execução |
| Travas: `FOR UPDATE` do inventário de u1/u2 (5148), coleções/locais de fixture, linhas sintéticas | sim | sim | Liberadas no fim da transação ou na queda da conexão |
| Sequências, WAL, estatísticas, logs do Postgres com o texto do SQL | sim | sim | **Sim.** Inócuo: sem segredo e sem dado de usuário no texto. |
| `pg_notify` / fila do `pg_net` / webhooks | não chamados pelo harness; event triggers de DDL só veem objetos temporários | — | Transacionais e descartados. **S0-20 prova que não há gatilho com efeito externo nas tabelas tocadas.** |
| Leitura de dados reais | contagens, ids de u1/u2, 1000 variantes reais (5823 D03) | idem | Nada sai do banco, exceto o relatório. Os `got`/`want` de casos falhos podem conter UUID: **redigir**. |

### 6.2 Por que a chamada única fecha o risco de commit

- **Erro no meio ou relatório final.** Qualquer exceção não capturada aborta a transação. O psql com `ON_ERROR_STOP=1` encerra a conexão, e o servidor desfaz tudo e solta as travas.
- **Nenhum caminho até um COMMIT.** O arquivo começa com `BEGIN`, não contém `COMMIT` e termina em `RAISE`. Mesmo um canal que ignorasse o `BEGIN` comitaria no máximo instruções isoladas de infraestrutura temporária: as escritas de dados ficam dentro de blocos `DO` que só existem com a transação aberta.
  - **Isso não é desculpa para usar outro canal:** §2 continua valendo.
- **Ponto residual: queda de rede no meio do harness.** O servidor só desfaz a transação quando percebe a queda (keepalive), e até lá a transação continua aberta com as travas. Cobertura: P-14/P-15 e §7.2. Anotar S0-28 (`idle_in_transaction_session_timeout`).

### 6.3 Teste de concorrência — NÃO EXECUTAR como está

O `CONCURRENCY-5364-TWO-SESSIONS.sql` exige que duas sessões enxerguem os mesmos exemplares. Por isso o passo 0 **comita**:

- 3 `physical_card` no inventário real de u1;
- um `bulk_operation` permanente;

e a limpeza depende de um `DELETE` manual em produção. Isso viola o §1. O arquivo continua inalterado e seu próprio cabeçalho já proíbe uso fora do ambiente descartável.

**Estado: NOT PROVEN.**

- A garantia de tudo ou nada sob remoção concorrente (5364 v1.1: trava antes de contar) está provada **estaticamente**: `FOR UPDATE` ordenado por id e contagem sobre o conjunto travado.
- Os casos de sessão única da 5887 (D) estão **cobertos**.
- A interleaving de duas sessões **não** está provada.

**Decisão do proprietário, no fechamento da S4 (não bloqueia S0–S3):**

- (a) aceitar como risco conhecido, como o K01 do BULK-04; ou
- (b) abrir uma rodada própria de prontidão para uma prova adaptada à produção, com fixtures comitados só em conta do proprietário, limpeza explícita e STOP/GO próprios.

## 7. Recuperação

### 7.1 Desfazer etapas (só por decisão explícita do proprietário)

**Defeito encontrado nesta rodada.** A recuperação "reaplicar os arquivos de `database/schema`" do README **não funcionaria**:

- a 5153 e a 5157 usam `CREATE FUNCTION` e falhariam com "já existe";
- o PRECHECK da 5262 exige o corpo da 5162 e falharia com "assinatura ausente".

Por isso foram preparados scripts de recuperação **derivados dos corpos canônicos** pelo mesmo gerador. O corpo foi copiado byte a byte, só com `CREATE` → `CREATE OR REPLACE` nos dois casos. O md5 restaurado foi conferido estaticamente: `a5fd5107…`, `0b7221b6…`, `1526fd4d…`, `8dcf2656…` e `d8cce43b…`.

| Ordem | Arquivo | Desfaz | Recusa (PRECHECK) |
|---|---|---|---|
| 1 | `controlled-execution/R4_rollback_5364.sql` | DROP de `set_my_physical_cards_condition` (as condições já gravadas ficam) | corpo ≠ 5364 v1.1; dependentes |
| 2 | `controlled-execution/R3_rollback_5363.sql` | leitura de volta à 5262 (20 colunas, ACL) | R4 não feito; corpo ou retorno ≠ 5363 |
| 3 | `controlled-execution/R2_rollback_5362.sql` | corpos canônicos de 5153/5155/5157/5158 e DROP da validação | R4 não feito; qualquer md5 ≠ 5362 |
| 4 | `controlled-execution/R1_rollback_5361.sql` | DROP da FK e da coluna | R2/R3/R4 não feitos; **qualquer exemplar com condição ≠ NM** (desfazer apagaria dado do usuário — só com decisão explícita e outra rodada) |

Só se desfaz até a etapa necessária: falha em S3 → R3 apenas, se for decidido desfazer. Cada R roda com `V116-Run`, seguido do POSTCHECK; o P-01 deve mostrar o estágio anterior. As etapas S1–S4 só acrescentam, e o frontend publicado funciona em qualquer estágio intermediário. Por isso **parar** num estágio validado é sempre uma opção mais segura que desfazer.

### 7.2 Transação ou trava deixada para trás

Se P-14 ou P-15 mostrarem uma sessão do próprio proprietário (psql ou SQL Editor) parada `idle in transaction (aborted)` ou segurando trava em `physical_card`/`inventory`/`card_condition`:

1. Na mesma aba ou sessão, rodar `rollback;`.
2. Se a sessão não estiver acessível, o proprietário decide encerrá-la: `select pg_terminate_backend(<pid>);`.
   - Isso só encerra a sessão: a transação dela é desfeita e nenhum dado comitado é afetado.
3. Rodar o POSTCHECK de novo.

## 8. Riscos residuais

| # | Risco | Mitigação |
|---|---|---|
| RR-1 | O SQL Editor pode reter uma transação abortada depois de erro num script com `BEGIN` explícito (comportamento não medido) | psql recomendado para migrations; harness proibido no SQL Editor; `rollback;` imediato e P-14/P-15 |
| RR-2 | Queda de rede no meio de um harness ou migration mantém travas até o servidor perceber | P-14/P-15 depois de cada passo; §7.2; anotar S0-28 |
| RR-3 | 5361: ACCESS EXCLUSIVE em `physical_card` durante o `VALIDATE` (tempo proporcional a S0-14) bloqueia leituras do acervo | `lock_timeout 5s` dentro do DO da 5361 v1.1; no psql, `$env:PGOPTIONS='-c statement_timeout=120s'` só para aquela conexão; janela sem uso |
| RR-4 | Cache do PostgREST entre o COMMIT e o `notify pgrst` | Segundos; o frontend publicado não usa nada novo |
| RR-5 | Canal que altere fim de linha faz falhar o POSTCHECK de md5 (falha fechada) | psql `-f`; S0 prova que o LIVE bate com os canônicos em LF |
| RR-6 | Harnesses travam inventário de u1/u2 e, na 5824, três variantes reais do catálogo durante segundos | Contas do proprietário; janela sem uso do acervo e do Catálogo Editorial |
| RR-7 | Concorrência da 5364 NOT PROVEN | §6.3 (decisão na S4) |
| RR-8 | O canal psql/SQL Editor não registra o ledger `supabase_migrations` | Precedente 2217 ("ledger 0 = rastreabilidade"); a evidência em `$Ev`, o `docs/log.md` e o README da proposta são a trilha |
| RR-9 | R1 depois de condições reais declaradas apagaria dado | PRECHECK do R1 recusa; exige decisão e rodada própria |
| RR-10 | `pg_stat_activity` pode não mostrar o estado de sessões de outros papéis, conforme os privilégios do papel `postgres` no Supabase | P-14 é indicativo; P-15 (`pg_locks`) complementa |

## 9. Itens que esta rodada não altera

- 5361–5364 e o harness 5887: sem alteração. Os derivados são arquivos novos, e o gerador prova a fidelidade.
- Harnesses legados 5822–5826 e `CONCURRENCY-5364-TWO-SESSIONS.sql`: sem alteração.
- Nenhuma decisão de produto ou contrato foi reaberta.

## 10. Classificação e primeira ação

**READY FOR S0.** A S0 é somente leitura, roda por qualquer canal de leitura e não depende de nenhuma decisão pendente.

**Pendências que a S0 resolve ou que precisam de decisão antes da S1:**

1. Autorização de harness: hoje **não concedida** (contas reais e alteração temporária de variantes do catálogo não aprovadas). Sem ela, a S1 não fecha o próprio GO (a validação por harness é parte dele). A forma de validar sem harness, ou a autorização dele, é uma decisão própria do proprietário.
2. psql disponível na máquina do proprietário? Se não houver, decidir o canal das etapas: instalar só o cliente psql, ou autorizar o agente via MCP por etapa.
3. Janela sem uso e backup/PITR confirmados.

**Primeira ação do proprietário:**

1. No SQL Editor do Supabase, colar e rodar `controlled-execution/S0_readonly_precheck.sql`.
2. Em seguida, colar e rodar `controlled-execution/POSTCHECK_readonly.sql`.
3. Devolver as duas grades, mais `psql --version`.

Nada além disso.

## 11. Falha da S1 — 5361 v1.0 (`S1 EXECUTION FAILURE DIAGNOSIS-01`, 2026-11-13)

**Sintoma.** Rodada no SQL Editor do Supabase, a 5361 v1.0 terminou com:

```
ERROR: 42P01: relation "_v116_s1_before" does not exist
```

**STOP ATIVO.** Nenhuma reexecução está autorizada.

**Causa raiz.** A 1.0 criava uma tabela temporária numa instrução de topo e a lia em outra:

```sql
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
do $pre$ … $pre$;                                        -- 1
create temp table _v116_s1_before on commit drop as …;   -- 2
alter table … add column condition_code …;               -- 3
alter table … add constraint fk_… not valid;             -- 4
alter table … validate constraint fk_…;                  -- 5
comment on column …;                                     -- 6
do $post$ … select * into b from _v116_s1_before; …      -- 7  ← 42P01
commit;
```

- **Premissa da 1.0.** A tabela é `ON COMMIT DROP` e por isso só existe enquanto a transação que a criou está aberta, na sessão que a criou. A 1.0 contava com o `begin;` mantendo 1–7 numa única transação, na mesma sessão.
- **O que o erro prova.** No momento da instrução 7, a sessão que executava não via a tabela. Logo, a instrução 2 não estava aberta numa transação visível para ela: ou já tinha terminado (o que dispara o drop), ou rodou em outra sessão.
- **Consequência.** O `begin;` não garantiu uma transação única entre as instruções naquele canal. Uma alternativa compatível com o erro é a execução de só uma parte do texto (seleção parcial no editor).
- **Por que a falha pode não ter desfeito nada.** Em qualquer das hipóteses, as instruções 3–6 podem ter sido comitadas isoladamente, sem o POSTCHECK, e o `SET LOCAL` pode não ter tido efeito. Nenhuma delas falharia sozinha.
- **Por isso não se presume reversão.**

**O que mais foi afetado.**

- O PRECHECK (instrução 1) rodou: se tivesse falhado, a mensagem seria `PRECHECK 5361`.
- O POSTCHECK da 1.0 **nunca avaliou**.
- 5362, 5363, 5364 e R1–R4 não usam tabela temporária, mas também dependem de `begin;`…`commit;` para serem atômicos. No canal que falhou, essa garantia não existe.
  - Eles **não foram alterados**: não há defeito provado neles em psql.
  - Ficam restritos ao psql (§2).
- A 5887 e os derivados não são afetados (não foram executados).

**Correção (5361 v1.1, aplicada só localmente).**

- **Instrução única.** A etapa inteira virou **um único `DO`**: precheck, baseline em variáveis no lugar da tabela temporária, DDL, comentário e postcheck.
- **Atomicidade sem depender do canal.**
  - Um `DO` é atômico em qualquer canal: uma exceção em qualquer ponto desfaz tudo.
  - Sem `begin;` explícito, um erro também não deixa transação aberta segurando trava (RR-1).
- **lock_timeout.** Virou `set_config('lock_timeout','5s', true)` dentro do `DO`, com escopo só da transação da própria instrução.
- **statement_timeout.** Não pode ser armado de dentro da instrução em curso e saiu do arquivo. No psql, usar `$env:PGOPTIONS='-c statement_timeout=120s'` (vale só para aquela conexão).
- **Mantidos.** Precheck, mensagens JÁ APLICADA / ESTADO DIVERGENTE, baseline de três contagens e `max(updated_at)`, padrão NM, FK NOT VALID → VALIDATE, comentário e os três postchecks.
- **Verificação estática.** Os trechos de precheck e de DDL+comentário são textualmente iguais aos da 1.0, normalizando espaços. O postcheck é igual, trocando só `b.x` → `b_x`. Restou uma única instrução de topo. Não há tabela temporária nem `SET LOCAL`.
- **Nada mais mudou.** Nenhum outro SQL, o harness 5887 ou os derivados.

**Diagnóstico do estado atual (somente leitura, pelo proprietário).** Rodar `controlled-execution/POSTCHECK_readonly.sql` e `controlled-execution/S1_FAILURE_DIAGNOSIS_readonly.sql`:

| Caso | Sinais | Leitura | Próximo passo (decisão do proprietário) |
|---|---|---|---|
| **D1 — nada persistiu** | P-01 = `S0 (nada aplicado)`; D-01 e D-02 `ausente` | A tentativa não deixou resíduo | Revisar a 1.1; se aprovada, reexecutar com nova autorização |
| **D2 — DDL da 1.0 comitada sem postcheck** | D-01, D-02 e D-03 iguais à coluna "esperado (D2)"; P-01 = `S1 (5361)` | O schema da S1 está no banco, mas o POSTCHECK nunca rodou | **Não** reexecutar: a 1.1 recusaria com `JÁ APLICADA`. Validar o estado por leitura: D-04 = 0, D-05 = S0-14 (salvo uso legítimo do app) e D-06 anterior à tentativa. Se tudo passar, decidir se a S1 é aceita como aplicada. |
| **D3 — parcial ou divergente** | Qualquer outra combinação (por exemplo coluna sem FK, FK `validada=false`, comentário ausente) | Estado intermediário | **STOP.** A 1.1 recusaria com `ESTADO DIVERGENTE`; exige correção própria |
| **Em qualquer caso** | D-08/D-09 ou P-14/P-15 com sessão ou trava pendente | Transação abortada retida | §7.2: `rollback;` na mesma aba ou `pg_terminate_backend`, por decisão do proprietário. Depois repetir o diagnóstico. |

**Condições para uma futura reexecução segura (nenhuma autorizada agora):**

1. O diagnóstico classifica **D1**, sem sessão nem trava pendente.
2. A 5361 v1.1 foi revisada e aprovada pelo proprietário.
3. Há autorização expressa da S1.
4. Canal: psql (`V116-Run`, com `PGOPTIONS` de `statement_timeout`) ou SQL Editor colando **o arquivo inteiro**, sem seleção parcial.
5. Janela sem uso, e P-14/P-15 = `nenhuma` imediatamente antes.
6. Depois da execução: POSTCHECK com P-01 = `S1 (5361)`, P-03 = 0 e P-12 = S0-14.
7. **A validação por harness continua não autorizada.** O fechamento do GO da S1 sem harness depende de decisão própria (§10, item 1).

### Resolução (2026-11-13) — S1 ENCERRADA

O POSTCHECK e o `S1_FAILURE_DIAGNOSIS_readonly.sql`, rodados pelo proprietário, classificaram o caso **D2**: a estrutura da 1.0 está integralmente persistida.

**Evidência relatada pelo proprietário:**

- `condition_code text NOT NULL DEFAULT 'NM'`;
- FK `fk_physical_card_condition_code` presente e validada;
- 4.062 exemplares, todos NM;
- contagens idênticas às da S0;
- `updated_at` preservado;
- RLS e permissões inalteradas;
- nenhuma transação ou trava pendente.

**Decisão do proprietário:** S1 aceita como aplicada. **Não reexecutar a 5361 nem aplicar R1.**

**O que isso significa para os arquivos:**

- A 5361 v1.1 (instrução única) **não foi executada**. Fica como a forma corrigida do artefato: o resultado no banco equivale ao DDL dela, que é idêntico ao da 1.0.
- A escolha do texto a promover para `database/schema/` (o 1.0 executado ou o 1.1 equivalente) fica para a rodada de promoção.
- O erro 42P01 e a sua causa ficam registrados acima como histórico. A regra de canal derivada dele (§2) continua valendo para S2–S4 e R1–R4.

## 12. S2 — prontidão da 5362 (`S2 CONTROLLED EXECUTION READINESS-01`, 2026-11-13)

**Classificação: READY FOR S2 AUTHORIZATION.** Nada foi executado. O arquivo 5362 não foi alterado.

### 12.1 Revisão focada da 5362 (estática)

| Ponto | Verificação | Resultado |
|---|---|---|
| **Substituição coordenada** de 5153/5155/5157/5158 | Um único bloco `begin;`…`commit;`. O PRECHECK exige a 5361 íntegra, os quatro corpos canônicos (md5), uma sobrecarga cada e a validação ainda ausente. O POSTCHECK confere os quatro md5 novos e as ACLs, e emite `notify pgrst`. Assinaturas, `SECURITY DEFINER/INVOKER`, volatilidade e `search_path` dos quatro são **idênticos** aos canônicos (comparação do cabeçalho de cada `CREATE`). O diff de corpo fica restrito aos trechos V1-16. | OK |
| **Seis códigos** | `physical_card_unknown_condition_codes`: compara com `card_condition.code` (seis linhas, S0-02), com caixa sensível. Nulo e inexistente são devolvidos como lista. É fonte única para 5153 (passo 6.6, antes de qualquer INSERT) e 5158 (issue `CONDITION_NOT_FOUND`). | OK. Risco residual: um código novo cadastrado em `card_condition` pelo admin de Pricing passaria a ser aceito (a escala é a canônica, C-105) |
| **Ausente ≡ NM** | `COALESCE(…,'NM')` na validação, na duplicidade e no INSERT. Na intenção do `request_hash`, a condição só entra quando difere de NM, em B1 por item e em B2 no nível do pedido. | OK |
| **Hash histórico** | A intenção de um pedido NM (com a chave ou sem ela) é byte a byte a da versão canônica. | Provado só estaticamente (§12.4) |
| **Duplicidade pelo trio** | 5155 e 5158 usam `(variant, idioma, COALESCE(cond,'NM'))`, com a mesma regra na prévia e na confirmação. | OK |
| **B1/B2 publicados** | O frontend não envia `condition_code`. Os prefixos usados pelo app e pelos harnesses estão preservados: `excede o limite`, `aceita exatamente as chaves`, `duplicado(s)` e o código `DUPLICATE_ITEM`. A mudança de texto "par(es)" → "item(ns)" não é lida pelo app, que só testa `excede o limite`. | OK |

**Ajustes indispensáveis:** nenhum.

**Nota de cabeçalho, sem efeito em execução.** O cabeçalho da 5362 ainda diz "Execução só pelo proprietário" e "Recuperação: reaplicar canônicos". Isso foi superado pelo §7/§12 e pelo R2. Não foi editado: é só comentário, e editá-lo mudaria o artefato revisado sem necessidade.

### 12.2 Canal recomendado e garantias

**Recomendado:** Claude, pelo conector Supabase (MCP `execute_sql`), no projeto `qjfutqujxrbzgrtkpgkg`.

- O identificador vem da documentação do projeto. A ferramenta precisa confirmá-lo na rodada autorizada: nesta rodada, `list_projects` respondeu erro do servidor do conector duas vezes.
- A 5362 vai em **uma única chamada**, com o texto do arquivo **inalterado**, incluindo `begin;` e `commit;`.
- Essa chamada só acontece depois que o `S2_TX_PROBE_readonly.sql`, rodado no **mesmo canal**, provar que as instruções de uma chamada compartilham uma transação (`mesma_transacao=SIM`, `xid_atribuido=nao`).

**Garantias:**

| Garantia | Fonte |
|---|---|
| Várias instruções numa chamada = uma transação | Prova de canal sem escrita (TX probe). Precedente: 5822 e 5823 de chamada única no LIVE com resíduo zero (2026-09/10) |
| Erro em qualquer ponto antes do `commit;` desfaz tudo | Semântica do PostgreSQL dentro de uma transação, válida uma vez provada a transação única |
| Nada fica aberto segurando trava | O canal não preserva sessão entre chamadas (medido no BULK-02). Conferido por P-14/P-15 e F-16 logo depois |
| O texto executado é o revisado | Envio literal do arquivo (md5 dos corpos conferido pelo próprio POSTCHECK da 5362 e por F-*) |

**Alternativas e canais proibidos:**

- **Alternativa B, por decisão do proprietário:** `apply_migration`.
  - **Vantagem:** grava o ledger (precedente: BULK-04).
  - **Custos:** exige retirar `begin`/`commit`, então o texto enviado difere do revisado. E a transação da própria ferramenta não pode ser provada sem uma escrita.
- **Alternativa C:** psql pelo proprietário (`V116-Run`). Garante a transação explícita.
- **Proibido:** SQL Editor, por causa da evidência da S1.

**Não transformar a 5362 num único `DO`.** É tecnicamente viável, mas é desaconselhado:

- exigiria aninhar cinco `CREATE FUNCTION` com corpos de 200–700 linhas e `COMMENT`/`REVOKE`/`GRANT`/`NOTIFY` dentro de um bloco plpgsql;
- isso trocaria o artefato auditado (hash do arquivo e revisão independente) por outro ainda não revisado;
- com a transação única provada, não acrescentaria garantia.

### 12.3 Sequência da rodada autorizada (somente leitura, exceto o passo 3)

| Passo | Chamada (uma cada) | GO |
|---|---|---|
| 0 | Confirmação do projeto pela ferramenta (`list_projects`) | Projeto `qjfutqujxrbzgrtkpgkg` ativo |
| 1 | `S2_TX_PROBE_readonly.sql` | ERRO 55000 com `mesma_transacao=SIM` e `xid_atribuido=nao` |
| 2a | `POSTCHECK_readonly.sql` (PRE) | P-01 = `S1 (5361)`; P-03 = 0; P-14/P-15 = `nenhuma` |
| 2b | `S2_STATE_readonly.sql` (PRE) | F-5153…F-5158 `md5=ANTIGO`; F-VAL `ausente`; F-16 `sessoes=0 travas_fortes=0`. Guardar a grade como referência. |
| 2c | `S2_PREVIEW_PROBE_readonly.sql` (PRE) | ERRO 55000, `ESTÁGIO=S1`, 15/15, `GATE_OK = true`. Isso prova que o teste discrimina: a condição é recusada antes da 5362. |
| **3** | **`5362_extend_bulk_registration_with_condition.sql`, texto integral** | Retorno sem erro (o `commit;` executou) |
| 4a | `POSTCHECK_readonly.sql` (POST) | P-01 = `S2 (5361+5362)`; P-04 `V1-16 (5362)`; P-09 `auth_helper=false`, `auth_validacao=false`; P-12 = PRE |
| 4b | `S2_STATE_readonly.sql` (POST) | Ver §12.4 |
| 4c | `S2_PREVIEW_PROBE_readonly.sql` (POST) | ERRO 55000, `ESTÁGIO=S2`, 16/16, `GATE_OK = true` |

O passo 3 só acontece com autorização expressa. Os passos 0–2 podem ser autorizados separadamente.

### 12.4 STOP/GO

**Verificável por leitura (o GO da S2 exige todos):**

- **F-5153…F-5158:** `md5=NOVO(5362)`, e o restante de cada linha (assinatura, retorno, linguagem, `secdef`, volatilidade, `cfg`, dono, ACL) **idêntico ao PRE**.
- **F-VAL:** `md5=NOVO(5362) | p_codes text[] -> text[] | lang=sql secdef=false vol=s cfg=search_path="" owner=postgres`, com ACL sem `anon`, `authenticated` nem `service_role`.
- **F-10, F-11, F-12, F-14 e `pricing_condition_mapping` em F-15:** iguais ao PRE.
- **F-12:** só `NM=<total>`. A 5362 não escreve exemplares.
- **F-13:** igual ao PRE, salvo uso legítimo do app no intervalo, que precisa ser explicado.
- **Prova funcional sem escrita 16/16:**
  - seis códigos aceitos, `XX` e `nm` recusados;
  - ausente + NM tratado como duplicado; seis condições da mesma carta aceitas;
  - vazio e não-texto recusados;
  - B2 com condição no nível do pedido;
  - mesmas regras estruturais na prévia e na confirmação;
  - prefixos legados preservados;
  - validação interna isolada.
- **Sem pendências:** P-14/P-15 e F-16 sem sessão nem trava.

**STOP:**

- **Antes do passo 3** (TX probe ≠ SIM, PRE divergente, probe PRE ≠ 15/15): **não executar a 5362**.
- **Erro no passo 3:**
  - a transação foi abortada e nada ficou aplicado;
  - confirmar com o POSTCHECK (P-01 = `S1`);
  - reportar; não reexecutar.
- **POST divergente com P-01 = S2:** não seguir para a S3. Avaliar R2 (psql apenas, §7), por decisão do proprietário.

**Comprovável só por teste mutável (harness 5887 grupo B e regressões 5822–5826, não autorizados):**

1. Gravação efetiva de `condition_code` pelos INSERTs de B1/B2.
2. Hash histórico de idempotência: REPLAY de chaves NM antigas e CONFLICT quando só a condição muda (B07/B08/B23). **Prova atual: estática.**
3. Fingerprint inalterado pela condição (B05). **Prova atual: estática** — 5149/5156 não são tocadas.
4. Atomicidade de um `CONDITION_NOT_FOUND` que ocorra depois do claim e das travas (5153 passo 6.6). A exceção desfaz o claim. **Prova atual: estática.**
5. Regressão comportamental completa dos legados.

**Riscos residuais que dependem de decisão do proprietário:**

- (a) aceitar a S2 com a evidência estática + leitura + prova funcional sem escrita;
- ou (b) autorizar, numa rodada própria, testes mutáveis em produção (contas reais e alteração temporária de variantes — hoje **não aprovados**);
- ou (c) um primeiro uso real controlado pelo próprio proprietário no app, depois da S2. Isso já é uso normal do produto, não teste: registra exemplares reais na conta dele.

### 12.5 Capacidade real do agente (sem conexão nesta rodada)

**Ferramentas disponíveis:** o conector Supabase está presente na sessão. Inclui `list_projects`, `get_project`, `execute_sql`, `apply_migration`, `list_migrations`, `get_advisors` e `query_logs`.

**Uso nesta rodada:**

- Só foi chamado o `list_projects`, que não acessa o banco. O servidor do conector respondeu erro duas vezes, então o projeto **não foi confirmado pela ferramenta** nesta rodada.
- Nenhuma credencial foi usada fora do conector.
- `execute_sql` e `apply_migration` não foram chamados.

**Observações sobre o `execute_sql`:**

- A descrição da ferramenta diz que comandos destrutivos podem exigir confirmação do usuário.
- **Se o conector continuar indisponível,** o canal C (psql pelo proprietário) cobre a S2 com as mesmas garantias de transação.

## 13. S3 — prontidão da 5363 (`S3 READINESS-01`, 2026-11-13)

**Estado de partida.** S2 concluída: STRUCTURAL PASS e READ-ONLY FUNCTIONAL PASS 16/16 (`docs/log.md`).

**Classificação: READY FOR S3 AUTHORIZATION.** A 5363 não foi executada e não foi alterada.

### 13.1 Compatibilidade da 5363

- **Diff contra a 5262 canônica.** Entre o `drop function` e o `commit`, só mudam:
  - a 21ª coluna `condition_code text` no `RETURNS TABLE`;
  - `pc.condition_code` no CTE `mine`;
  - `m.condition_code` no fim do SELECT;
  - o texto do COMMENT;
  - um bloco `$post$` novo.

  Entrada, filtros de propriedade (`pc.inventory_id = v_inventory`, `co.owner_user_id = v_user`, `sc.inventory_id = v_inventory`), limite de 500, ordenação, `SECURITY DEFINER`, `STABLE`, `search_path = ''`, REVOKE/GRANT e as 20 colunas (nomes, tipos, ordem, origem) são **idênticos**.
- **Origem da coluna.** `condition_code` vem só de `physical_card` (via `mine`). Não toca preços, reservas, alocações nem locais. Ela também não multiplica linhas: o CTE `mine` já tinha uma linha por exemplar.
- **Mudança do tipo de retorno.** `CREATE OR REPLACE` **não** aceita mudar `RETURNS TABLE` (42P13). Por isso a 5363 faz `DROP` + `CREATE` na mesma transação, no padrão da 5262. O DROP apaga COMMENT e ACL, que são reaplicados.
- **Dependências (LIVE, leitura).** Nenhuma:
  - `pg_depend` = 0;
  - nenhum corpo de função cita a função, e nenhuma view também;
  - sobrecarga única.

  O PRECHECK da 5363 recusa se isso mudar.
- **Consumidores.** Quatro pontos no frontend:
  - `acervo-queries.ts`;
  - `actions.ts` (3 chamadas);
  - `free-collection.ts`;
  - `storage-locations-queries.ts`.

  Todos leem as linhas **por nome de coluna** (`row.physical_card_id`, …). Uma coluna a mais no fim é ignorada pelo frontend publicado.
- **ACL depois do CREATE.** O default ACL do papel `postgres` no schema `public` é só `postgres=X/postgres`. O default global dá EXECUTE a PUBLIC, mas a 5363 revoga esse EXECUTE logo depois. Resultado esperado: `postgres=X/postgres,authenticated=X/postgres`, igual ao atual. `service_role` e `anon` ficam sem EXECUTE.
  - O POSTCHECK interno da 5363 só confere `authenticated` e `anon`. A igualdade exata da ACL fica para o S3_STATE G-06/G-07.

### 13.2 Riscos

- **Chamadas durante a troca.**
  - Chamadas em andamento terminam com a definição antiga.
  - Chamadas que começam antes do COMMIT ainda veem a versão antiga (MVCC).
  - Chamadas depois do COMMIT veem a nova.
  - O PostgREST recarrega o schema por `notify pgrst`. Entre o COMMIT e a recarga (segundos), ele chama a função por nome e recebe a coluna extra, inofensiva.
- **Confirmação do conector.** O `DROP FUNCTION` faz o conector poder pedir confirmação de comando destrutivo.
- **Sem leitura com dados reais.** A montagem das 21 colunas com dados reais **não** é exercida por leitura com identidade sintética: a função retorna antes do `RETURN QUERY` quando não há inventário. Por isso, depois da S3, a leitura real fica para o seu uso normal no app (Meu acervo → detalhe de uma carta). Isso só lê; não é teste com escrita.
- **Harness.** O grupo C do harness 5887 (mutável) continua não autorizado.

### 13.3 Evidência atual (LIVE, leitura)

| Origem | Resultado |
|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (`mimikyu-core`, `ACTIVE_HEALTHY`), confirmado pelo conector |
| `S3_STATE_readonly.sql` (PRE) | G-02 `5262 d8cce43b…`; G-04 = as 20 colunas na ordem canônica; G-05 `(nenhuma)`; G-06 `plpgsql secdef=true vol=s cfg=search_path="" owner=postgres acl=postgres=X/postgres,authenticated=X/postgres`; G-07 `true,false,false,false`; G-09 `pg_depend=0 funcoes=0 views=0`; G-10 `text notnull=true` |
| `S3_PROBE_readonly.sql` (PRE) | 4/4, `GATE_OK = t`, `transaction_read_only=on`: G1 sem identidade → 28000; G2 item inválido → 22023; G3 identidade sintética → 0 linhas; G4 `anon` → 42501 |
| POSTCHECK da S2 | `S2 (5361+5362)`, sem sessões ou travas |
| Canal | `execute_sql` em chamada única, já demonstrado (§12 e S2) |

### 13.4 Protocolo (somente com autorização)

| Passo | Chamada | GO |
|---|---|---|
| 0 | `list_projects` | Projeto `qjfutqujxrbzgrtkpgkg` |
| 1 | `POSTCHECK_readonly.sql` | P-01 = `S2`; P-14/P-15 = `nenhuma` |
| 2 | `S3_STATE_readonly.sql` (PRE) | Igual a §13.3 |
| **3** | **`5363_…sql`, texto integral (`begin;`…`commit;`), uma chamada** | Sem erro |
| 4 | `POSTCHECK_readonly.sql` | P-01 = `S3 (5361–5363)`; P-05 `5363 (21 colunas, condition_code)`; P-08 `leitura=true`; P-09 `anon_leitura=false`; P-12 = antes |
| 5 | `S3_STATE_readonly.sql` (POST) | G-02 `5363 77abbb9a…`; G-04 **idêntico** ao PRE; G-05 `condition_code:text`; G-06 e G-07 **idênticos** ao PRE; G-08 `menciona 5363`; G-09 zeros |
| 6 | `S3_PROBE_readonly.sql` (POST) | 4/4, estágio `5363` |
| 7 | `S2_STATE_readonly.sql` | F-12–F-16 iguais ao baseline da S2 (sem escrita de dados) |
| 8 (proprietário) | App: Meu acervo → detalhe de uma carta | Abre normalmente, com as mesmas cópias |

**STOP:**

- Divergência antes do passo 3: não executar.
- Erro no passo 3: a transação foi abortada e nada foi aplicado. Confirmar com o POSTCHECK (P-01 = `S2`), sem retry.
- Divergência depois, com P-01 = `S3`: parar. Avaliar o R3 (`controlled-execution/R3_rollback_5363.sql`), que volta à 5262 com a mesma ACL, por decisão do proprietário.
  - Com a semântica de transação única do `execute_sql` já demonstrada, o R3 pode usar esse canal, mediante autorização.

## 14. S4 — prontidão da 5364 (`S4 READINESS-01`, 2026-11-13)

**Estado de partida.** S3 aplicada com STRUCTURAL PASS e homologada pelo proprietário no app (5/5 no Meu acervo).

**Classificação: READY FOR S4 AUTHORIZATION.** A 5364 v1.1 não foi executada nem alterada. md5 do corpo = `b569ecdbe202428a6bdc9461c6d62e37`, conferido localmente.

### 14.1 Contrato e segurança (revisão estática)

- **Assinatura:** `set_my_physical_cards_condition(p_physical_card_ids uuid[], p_condition_code text) → TABLE(requested_count int, changed_count int)`.
- **Configuração:** `SECURITY DEFINER`, `VOLATILE`, `search_path = ''` e `lock_timeout = '5s'` por cláusula `SET` da função. Todos os objetos são qualificados.
- **Ordem dos guards** (todos antes de qualquer leitura de exemplar):
  1. autenticação (28000);
  2. código obrigatório e não em branco;
  3. código existente na escala pela validação única da 5362 (sensível a caixa: `nm` é recusado);
  4. lote não nulo e não vazio;
  5. lote unidimensional;
  6. no máximo 500 entradas brutas;
  7. deduplicação.

  Depois dos guards vem o inventário do chamador. Sem inventário, a função para.
- **Titularidade, tudo ou nada:**
  - trava `FOR UPDATE` ordenada por id só nas linhas do inventário do chamador;
  - conta sobre o conjunto travado;
  - qualquer id nulo, alheio ou inexistente reprova o lote inteiro, com a mesma mensagem para alheio e inexistente (não deixa descobrir exemplares de outros usuários);
  - linhas de outros usuários nunca são travadas.
- **Escrita:**
  - só `condition_code`, e só onde muda (`is distinct from`);
  - repetir a chamada devolve `changed_count = 0` e não toca `updated_at`;
  - exemplares não selecionados ficam intactos.
- **Gatilhos de `physical_card` no LIVE:** só `trg_physical_card_set_updated_at` dispara num UPDATE de `condition_code`. Os outros dois são restritos a `card_variant_id` e `storage_container_id`. Nenhum escreve em outra tabela.
- **Isolamento:** a função não toca preços, reservas (`collection_layout_slot_expected_content`), alocações, Favoritos, Lista de Desejos nem coleções.
- **RLS e permissões:**
  - `physical_card` tem RLS ligada e não forçada, dono `postgres`;
  - o cliente `authenticated` só tem `SELECT` na tabela;
  - a escrita só acontece pela função `DEFINER`, que deriva o inventário de `auth.uid()`;
  - ACL esperada depois do CREATE: `postgres=X/postgres,authenticated=X/postgres`, com PUBLIC e `anon` revogados e `service_role` sem EXECUTE. Mesma mecânica de default ACL verificada na S3.

**Defeitos:** nenhum. Nenhuma correção é indispensável.

### 14.2 Concorrência e atomicidade

- **Remoção concorrente:** com a trava antes da contagem (v1.1), uma linha removida por outra transação comitada não é travada, porque o `FOR UPDATE` em READ COMMITTED pula a linha que deixou de existir. O lote é reprovado, sem sucesso parcial.
- **Edição concorrente da mesma linha:** espera a trava, relê a versão nova e grava só se ainda mudar.
- **Impasses (deadlocks):** as outras funções que travam vários exemplares (`apply_my_binder_auto_arrange`, `set_physical_cards_storage`) também ordenam por id. `organize_my_collection_storage` usa `NOWAIT` por linha. As que travam um exemplar (`remove_my_physical_card`, `place_my_physical_card_in_slot`) seguram uma linha só.
  - **Risco residual:** se uma função de linha única travar depois outra linha de exemplar, um impasse é possível. O PostgreSQL detecta (40P01) e aborta uma das transações inteira, sem efeito parcial. Só ocorre com ações simultâneas do mesmo usuário.
- **Atomicidade:** qualquer exceção desfaz o UPDATE inteiro. A atualização é uma única instrução set-based.
- **Prova com duas sessões:** **NOT PROVEN**. O `CONCURRENCY-5364-TWO-SESSIONS.sql` continua proibido no LIVE (§6.3).

### 14.3 Evidência atual (LIVE, leitura)

| Origem | Resultado |
|---|---|
| Projeto | `qjfutqujxrbzgrtkpgkg` (`mimikyu-core`), confirmado pelo conector |
| `S4_STATE_readonly.sql` (PRE) | H-01 0 sobrecargas; H-02 a H-05 `ausente`; H-06 validador `df223290…` e leitura `77abbb9a…`; H-07 `trg_physical_card_set_updated_at`; H-08 `true/false dono=postgres grants=authenticated:SELECT`; H-09 `total=4062 NM=4062`; H-10 sem sessões ou travas |
| `S4_PROBE_readonly.sql` (PRE) | Compila e relata "função AUSENTE (antes da 5364)", sem testar nada, como projetado |
| POSTCHECK | Estágio S3 (§13) |

**Correção no script de leitura:** a primeira versão da linha H-07 comparava `tgattr` vazio de forma incorreta e devolvia `(nenhum)`. Foi corrigida para `array_length` antes desta evidência. A correção é só no script de leitura.

### 14.4 Protocolo (somente com autorização)

| Passo | Chamada | GO |
|---|---|---|
| 0 | `list_projects` | `qjfutqujxrbzgrtkpgkg` |
| 1 | `POSTCHECK_readonly.sql` | P-01 = `S3`; P-14/P-15 = `nenhuma` |
| 2 | `S4_STATE_readonly.sql` (PRE) | Igual a §14.3 |
| **3** | **`5364_…sql`, texto integral (`begin;`…`commit;`), uma chamada `execute_sql`** | Sem erro |
| 4 | `POSTCHECK_readonly.sql` | P-01 = `S4 (5361–5364)`; P-07 = `b569ecdb…`; P-08 `edicao=true`; P-09 `anon_edicao=false`; P-03 = 0; P-12 = antes |
| 5 | `S4_STATE_readonly.sql` (POST) | H-01 = 1; H-02 = `5364 v1.1 b569ecdb…`; H-03 = `p_physical_card_ids uuid[], p_condition_code text -> TABLE(requested_count integer, changed_count integer)`; H-04 = `plpgsql secdef=true vol=v cfg=search_path="";lock_timeout=5s owner=postgres acl=postgres=X/postgres,authenticated=X/postgres`; H-05 = `true,false,false,false`; H-06 a H-10 = PRE |
| 6 | `S4_PROBE_readonly.sql` (POST) | 13/13, `GATE_OK = true`, `transaction_read_only=on` |
| 7 | `S2_STATE_readonly.sql` | Família Bulk, contagens e domínios iguais ao baseline |

**O probe comprova sem escrita:**

- autenticação;
- código nulo, em branco, inexistente e com caixa errada recusados;
- os seis códigos aceitos pela validação;
- lote nulo, vazio, 2D e com 501 entradas recusados;
- 500 entradas aceitas pelo limite;
- identidade sem inventário barrada antes de qualquer trava;
- `anon` sem EXECUTE.

**Só comprovável com escrita (harness 5887 grupo D ou uso real, não autorizados nesta etapa):**

- atualização efetiva;
- recusa de exemplar alheio ou inexistente num inventário real, sem efeito parcial;
- idempotência (`changed_count = 0`) e `updated_at` só onde muda;
- preservação dos não selecionados;
- concorrência real.

A primeira edição de condição pelo proprietário no app, depois do frontend do V1-16, é uso legítimo do produto e não teste. Ela pode servir de homologação desses pontos, por decisão dele.

**STOP:**

- Divergência antes do passo 3: não executar.
- Erro no passo 3: a transação foi abortada e nada foi aplicado. Confirmar com o POSTCHECK (P-01 = `S3`), sem retry.
- Divergência depois, com P-01 = `S4`: parar. Avaliar o R4 (`controlled-execution/R4_rollback_5364.sql`): faz só o DROP da função, com precheck de md5 e de dependentes, e preserva condições já gravadas. Pode usar o canal `execute_sql` mediante autorização.

