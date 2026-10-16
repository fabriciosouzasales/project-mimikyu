# Pokédex P6.1 — Auditoria estática do ensaio transacional 6850

| Campo | Valor |
|---|---|
| **Artefato auditado** | `6850_dryrun_pokedex_species_favorite.sql` v1.0 (sha256 atual `29abf8376d8c9a17ccb5c5ae810d018d6f7cafbecbd8039ccd0757223c730cb3`; o gate final de §10 alterou apenas comentários) |
| **Gerado por** | `generate_6850.py` a partir de `6850.template.sql` + 6136/6137/6849 (regeneração byte-idêntica) |
| **Verificador** | `verify_6850_identity.py` (offline, sem banco) — **28/28 PASS**; 13/13 mutações detectadas |
| **Decisões vigentes** | D-B = Opção A (ensaio transacional com reversão); D-A **revisada** (§10): usar duas contas existentes não administrativas, escolhidas por Fabrício na execução; nenhuma conta criada |
| **Execução LIVE** | **Nenhuma.** Nenhum SQL foi executado nesta rodada. |
| **Data** | 2026-10-14 |

Legenda de evidência: **[INSP]** comprovado por inspeção/verificação estática; **[PG]** depende da primeira execução em PostgreSQL.

---

## 1. Identidade do conteúdo ensaiado

| Origem | sha256 do arquivo | sha256 do conteúdo ensaiado | Regra de extração |
|---|---|---|---|
| 6136 | `0d351bc1…9a64fbdd` | `d4d5c2d7…14d63223` | texto entre a linha `begin;` e a linha `commit;` |
| 6137 | `9c5173b2…2b4e` | `37ea65d7…22a195d6c7` | idem |
| 6849 v2.0 | `368bcc8d…2c9f` | `5944311b…7e044f027a` (prosrc) | função completa, do `create or replace` ao `$fn$;` |

Método de prova (dois pontos independentes):

1. **Offline [INSP].** I1–I3 comparam os trechos embutidos byte a byte com os arquivos de origem. I4–I8 exigem que as constantes e o cabeçalho citem exatamente esses hashes. As origens não foram alteradas nesta rodada, e os hashes dos três arquivos são os mesmos da auditoria anterior.
2. **Em execução [PG].**
   - D.0.1 e D.0.2 recalculam no banco o sha256 dos textos que de fato serão passados ao `EXECUTE`.
   - D.0.3 recalcula o sha256 do `prosrc` de `pg_temp.p6_6849_validate` que está compilado na sessão.
   - Qualquer divergência zera `v_pre_ok`, o ensaio não escreve nada e o GATE dá FAIL.

O único trecho de 6136/6137 que não vai para o ensaio são as linhas `begin;`/`commit;`, removidas porque a fronteira transacional passa a ser o savepoint. T1–T3 provam que o conteúdo ensaiado não tem controle de transação, `CONCURRENTLY`/`VACUUM` nem sequências **[INSP]**.

## 2. Relação com o 6849

- A Seção 1 do 6850 é uma cópia byte-idêntica da função `pg_temp.p6_6849_validate` do 6849 v2.0 (I3, D.0.3). Nada foi alterado para facilitar o ensaio.
- As **47 verificações** e o **GATE** do 6849 continuam integrais. O ensaio captura as 48 linhas numa variável jsonb e as devolve com `seq` = 1000 + seq original e `origem` = `'6849'`.
- **D.2.1** exige GATE do 6849 = `PASS` **e** exatamente 48 linhas. Sem isso, o GATE-ENSAIO dá FAIL.
- O savepoint interno do 6849 (sentinela `P6R00`) fica **aninhado** dentro do savepoint do ensaio (sentinela `P6D00`). As provas 10.1/10.2 do 6849 continuam valendo para os dados de teste; o savepoint externo acrescenta a reversão do DDL.

## 3. Segurança transacional — demonstração por caminhos

O artefato é um **único** envio com quatro statements: `begin`, os dois `set local`, os dois `create function pg_temp.*` e o `SELECT` final. Todas as escritas persistentes possíveis (DDL de 6136/6137 e linhas de teste) só ocorrem dentro do bloco `BEGIN … EXCEPTION` da função `p6_6850_dry_run`, chamada pelo `SELECT` (S5, S9).

| # | Caminho | O que acontece | Persiste algo em `public`? |
|---|---|---|---|
| P1 | Pré-condição falha (hash, objeto já existe, papel, timeouts, contas) | O bloco nem é executado. D.1.x/D.2.1/D.3.1 = `NOT_RUN`, GATE FAIL | **Não**: nenhuma escrita foi tentada [INSP] |
| P2 | Sucesso total | O 6849 roda e a sentinela `P6D00` reverte o savepoint. D.3.1 confirma a ausência e GATE PASS | **Não**: savepoint revertido [INSP lógica / PG mecânica] |
| P3 | Erro de sintaxe, privilégio ou execução em 6136, 6137 ou 6849 | `WHEN OTHERS` reverte o savepoint e grava `v_err`. Linha D.X FAIL, e D.1.x ou D.2.1 FAIL | **Não**: savepoint revertido [INSP] |
| P4 | Sentinela não alcançada sem erro | Impossível por construção (S7: sem `RETURN` no bloco). Mesmo assim, `P6_6850_SENTINEL_NOT_REACHED` aborta o statement | **Não**: abort atômico [INSP] |
| P5 | Resíduo após a reversão | D.3.1 FAIL e `P6_6850_REVERT_NOT_CONFIRMED` aborta o statement inteiro | **Não**: abort atômico [INSP] |
| P6 | `statement_timeout` ou cancelamento | `query_canceled` não é capturado por `WHEN OTHERS` e aborta o statement inteiro | **Não** [INSP: semântica documentada de PL/pgSQL; PG: confirmação empírica] |
| P7 | `lock_timeout` ao criar as FKs | Erro `55P03` capturado por `WHEN OTHERS`, igual a P3 | **Não** [INSP] |
| P8 | Erro fora do bloco (leituras D.0, montagem da saída) | O statement aborta antes de qualquer escrita ou depois da reversão | **Não** [INSP] |
| P9 | Queda de conexão no meio | O servidor aborta a transação aberta | **Não** [INSP: garantia do PostgreSQL] |

**Conclusão [INSP]:** nenhum caminho termina com sucesso e mudanças persistentes em `public`/`auth`. Isso vale porque toda escrita está dentro de um savepoint sempre revertido (pela sentinela ou pelo handler), e porque qualquer falha fora dele aborta o statement inteiro. O artefato não tem `COMMIT` (S1) nem `ROLLBACK` (S2) e não depende de reversão em outra chamada ou sessão (contrato 8).

### Itens do contrato

| # | Requisito | Situação |
|---|---|---|
| 1 | Conteúdo funcional exato de 6136/6137 e identidade por hash | Atendido [INSP] e reconferido em execução [PG] (§1) |
| 2 | 47 verificações e resultado consolidado do 6849 preservados | Atendido [INSP] (§2) |
| 3 | DDL e testes dentro de uma fronteira de reversão garantida | Atendido: savepoint com sentinela [INSP] e mecânica de DDL transacional [PG] |
| 4 | Relatório completo capturado antes da reversão | Atendido: variáveis PL/pgSQL sobrevivem ao rollback do savepoint [INSP; PG] |
| 5 | Objetos e linhas de teste desfeitos | Atendido: um único savepoint cobre os dois; D.3.1 verifica [INSP] |
| 6 | Falha inequívoca | Atendido: D.X com `step`/`sqlstate`/`sqlerrm` e GATE FAIL [INSP] |
| 7 | Nenhum erro inesperado convertido em PASS | Atendido (§5) [INSP] |
| 8 | Nenhuma dependência de `ROLLBACK` em outra chamada | Atendido (S1/S2) [INSP] |
| 9 | Postcheck independente somente leitura | Atendido: CALL 2 em `transaction read only` [INSP] |
| 10 | Nenhum objeto, permissão, policy, índice ou função residual | Atendido em `public`/`auth`. Há uma ressalva para funções `pg_temp` (R1, §4), detectada pela CALL 2 |

## 4. Segurança operacional

- **Espera por lock.** `SET LOCAL lock_timeout = '5s'`, exigido por D.0.5 (de 1 s a 10 s). Ao criar as FKs, o DDL pede `SHARE ROW EXCLUSIVE` em `auth.users` e `pokemon_species`. Esse lock bloqueia escritas concorrentes nessas tabelas (por exemplo, atualização de `last_sign_in_at` num login) **até o rollback do savepoint**, ou seja, segundos. Os locks obtidos dentro do savepoint são liberados quando ele é revertido [INSP: semântica de subtransação; PG: duração real]. Recomendação: executar em janela de baixo uso.
- **Duração máxima.** `SET LOCAL statement_timeout = '120s'`, exigido por D.0.5 (de 10 s a 5 min). Estouro leva ao caminho P6.
- **Concorrência.** Os objetos criados ficam invisíveis para outras sessões, porque nunca são commitados. O `NOTIFY pgrst` do event trigger `pgrst_ddl_watch` fica na fila do savepoint e é descartado com ele, então não há recarga do PostgREST [INSP; PG].
- **Falha durante a criação.** É o caminho P3, revertido como um todo; não há DDL parcial possível.
- **Falha do mecanismo de reversão.** Se a sentinela não for alcançada, vale P4; se houver resíduo, vale P5. As duas salvaguardas abortam o statement.
- **Fail-closed quanto ao canal.** Se o executor ignorar o `begin;` (autocommit por statement), o `SET LOCAL` não surte efeito. D.0.5 então lê os valores padrão do papel e dá FAIL se estiverem fora das faixas exigidas (o padrão do PostgreSQL para `lock_timeout` é 0, fora da faixa); nesse caso o ensaio não escreve nada [INSP; PG: valor efetivo do papel].

### R1 — resíduo temporário de sessão (ressalva ao item 10)

As duas funções `pg_temp.p6_6849_validate` e `pg_temp.p6_6850_dry_run` são criadas **na transação de topo**, fora do savepoint, pois precisam existir para o `SELECT`. O artefato não faz `COMMIT`, então o destino delas depende do executor:

- se o executor encerrar a transação sem commit, o que é esperado pelo comportamento já observado do canal (5818 §B), elas somem;
- se o executor fizer commit ou devolver a conexão ao pool com a transação aberta, elas ficam no esquema temporário **daquela sessão** até a conexão ser encerrada. Nesse caso, um `AccessShareLock` de leitura em `auth.users` também pode ficar retido enquanto a transação estiver *idle in transaction*.

Esse resíduo não é persistente: some quando a sessão termina, não fica em `public`, não tem grants e é invisível para outras sessões. A **CALL 2** inclui a contagem `funcoes_temporarias_residuais` e `transacoes_pendentes`, e o resultado esperado é 0 nas duas. Se alguma vier > 0, o resultado do ensaio continua válido; o tratamento (aguardar o reciclo da conexão ou encerrá-la) deve ser decidido por Fabrício antes de seguir.

## 5. Segunda revisão crítica (falhas procuradas)

| Falha procurada | Resultado | Evidência |
|---|---|---|
| Commit implícito | Ausente: o artefato não tem `COMMIT`; uma função chamada por `SELECT` não pode fazer commit; o DDL embutido não tem controle de transação, `CONCURRENTLY`, `VACUUM` ou `CREATE INDEX CONCURRENTLY` | S1, T1, T2 [INSP] |
| Bloco de exceção que não reverte tudo | Ausente: um único bloco cobre 6136, 6137 e 6849; os dois handlers (`P6D00` e `OTHERS`) revertem o savepoint inteiro | S5, S6 [INSP] |
| Erro ocultado | Ausente: `OTHERS` grava `v_err`, que gera D.X FAIL e reprova D.1.x/D.2.1. Erros fora do bloco abortam o statement | S11, P3, P8 [INSP] |
| Perda do relatório | Na reversão, não: relatório em variáveis jsonb. Em abort (P4/P5/P6/P8), o relatório se perde, mas o erro é explícito e nada persiste: falha inequívoca, sem falso PASS | [INSP; PG] |
| Dependência de sessão | Ausente: a reversão acontece dentro do mesmo statement; a CALL 2 é independente e só lê | S2, S4 [INSP] |
| Divergência de conteúdo | Ausente: verificação byte a byte offline e hash em execução | I1–I8, D.0.1–D.0.3 [INSP; PG] |
| Locks ou efeitos externos não revertidos | Locks do savepoint são liberados no rollback. `NOTIFY` é descartado. Não há sequências, `dblink`, `pg_net` nem NOTICE. Efeitos não transacionais aceitos: consumo de OID, contadores de estatística e linhas de log do servidor, nenhum deles alterando dados. Ressalva: R1 | T3, §4 [INSP; PG] |
| Falso PASS | Ausente: o GATE-ENSAIO exige exatamente as 11 ids esperadas, sem duplicatas nem extras, todas PASS. `NOT_RUN` e D.X reprovam. D.2.1 exige GATE 6849 = PASS e 48 linhas | S11 [INSP] |

**Achados desta revisão, já corrigidos no mesmo ciclo:**

- **D.0.6 adicionada.** Sem ela, o ensaio executaria DDL mesmo sem contas válidas.
- **I8 adicionada.** Uma troca de hash no cabeçalho passava sem detecção.
- **CALL 2 ampliada.** Passa a contar as funções `pg_temp` residuais (R1).
- **Falsos positivos do verificador (T1/S9) eliminados.** Os literais dollar-quoted agora são removidos antes da busca.

## 6. O que depende da primeira execução [PG]

1. **Sintaxe.** Nenhum parser PostgreSQL esteve disponível no sandbox; não há validação por parser. Com `check_function_bodies = on`, um erro nas Seções 1–2 falha no `CREATE` antes de qualquer escrita, porque a transação aborta. Um erro no DDL embutido cai no caminho P3.
2. **`EXECUTE` de string com vários comandos** (SPI). O esperado é que funcione; se falhar, cai em P3 e é revertido.
3. **Event triggers do Supabase dentro da subtransação.** O esperado é que tudo seja transacional; o efeito real será observado.
4. **Contenção de lock real** em `auth.users`/`pokemon_species` no momento da execução.
5. **Comportamento do canal** ao terminar com transação aberta (R1), medido pela CALL 2.
6. **Resultado funcional das 47 verificações** com as contas de teste reais.

## 7. Dependências relativas aos usuários de teste (D-A)

> **Superado por §10.4** (D-A revisada): não há criação de contas; usam-se duas contas existentes não administrativas.

- O ensaio exige **dois UUIDs distintos de contas de teste dedicadas**, existentes em `auth.users`. Hoje a Seção 3 tem placeholders (`…000A` e `…000B`), que fazem D.0.6 reprovar. Sem as contas, o resultado é P1: nenhuma escrita.
- As contas precisam ser criadas pelo Supabase Auth em **rodada própria, autorizada**. Esta rodada não cria usuários.
- As três contas existentes (1 admin e 2 não-admin) **não** devem ser usadas sem confirmação expressa.
- O 6849 cria e remove linhas de favoritos dessas contas apenas dentro do savepoint. As contas em si não são alteradas.

## 8. Protocolo de execução (quando autorizado)

1. Pré-requisito: as duas contas de teste dedicadas já criadas; Fabrício preenche os UUIDs na Seção 3.
2. Opcional: reexecutar `python3 verify_6850_identity.py` e confirmar 28/28.
3. **CALL 1:** enviar o arquivo inteiro numa única chamada. Esperado: GATE-ENSAIO = PASS, 11 linhas D.* PASS e 48 linhas 6849 com GATE PASS.
4. **CALL 2:** em nova chamada, enviar o postcheck somente leitura (bloco comentado no fim do arquivo). Esperado: todas as colunas booleanas `true`, `funcoes_temporarias_residuais = 0` e `transacoes_pendentes = 0`.
5. Qualquer resultado diferente leva a STOP e relato a Fabrício. A aplicação real de 6136/6137 é uma **decisão separada**, que não está autorizada por este ensaio.

## 9. Parecer

> **Superado por §10.6.**

**READY (condicionado) para autorização posterior.** Condições:

- (a) contas de teste dedicadas criadas em rodada autorizada (D-A);
- (b) autorização expressa de execução;
- (c) aceitação dos itens [PG] do §6 e da ressalva R1, que a CALL 2 detecta.

Nenhum BLOCKER foi identificado: os 10 itens do contrato estão atendidos por construção, e a única ressalva (R1) é não persistente e detectável.

---

## 10. Gate final pré-execução (revisão direcionada, 2026-10-14)

Escopo restrito: R1, segurança do rollback, contrato de falha e readiness. A auditoria integral (§1–§6) não foi repetida.

### 10.1 R1 — funções temporárias: **ACEITÁVEL**

| Aspecto | Conclusão | Evidência |
|---|---|---|
| Escopo | `pg_temp.p6_6849_validate` e `pg_temp.p6_6850_dry_run` vivem no esquema temporário da sessão da CALL 1. Não ficam em `public` nem em `auth`, e o PostgREST não as expõe (expõe só os esquemas configurados) | [INSP] |
| Privilégios | O dono é `postgres`. O esquema `pg_temp_N` de uma sessão não é acessível a outras sessões de papéis comuns, porque `anon`/`authenticated` não têm USAGE nele. As funções não usam `SECURITY DEFINER` e não concedem nada | [INSP; PG] |
| Resolução de nomes | O PostgreSQL nunca procura funções em `pg_temp` sem qualificação explícita. Uma query não relacionada, numa conexão reaproveitada, não as chama por acidente | [INSP] |
| Conexão reaproveitada | Mesmo que alguém da mesma sessão chame `pg_temp.p6_6850_dry_run` de novo, o efeito é o próprio ensaio: autorreversível, com pré-condições (D.0.4 bloqueia se os objetos existirem). O relatório não contém UUIDs | [INSP] |
| Colisão na mesma sessão | `create or replace` com a mesma assinatura substitui a versão anterior. D.0.3 recalcula o hash do corpo efetivamente compilado antes de qualquer escrita, então uma versão divergente impede o ensaio | [INSP] |
| Dependência de encerramento | Nenhuma. A reversão do DDL e dos dados acontece dentro do `SELECT` da CALL 1, não no fim da sessão | [INSP] |
| Risco concreto residual | Se o canal deixar a transação da CALL 1 aberta (*idle in transaction*), ela retém `AccessShareLock` de leitura de topo (por exemplo em `auth.users` e `pg_proc`) e segura o horizonte de VACUUM até a conexão fechar. Isso não altera dados, mas bloquearia DDL concorrente nessas tabelas. O comportamento já observado do canal (5818 §B) é encerrar sem persistir sessão | [PG] |

**Limitação registrada (postcheck).** A CALL 2 roda em outra conexão e por isso:

- **prova** a ausência de objetos permanentes (tabela, índice, funções `public`, policy, constraints) e de funções `pg_temp` **commitadas** em qualquer sessão;
- **não prova** que a sessão da CALL 1 deixou de existir, nem que suas funções `pg_temp` sumiram se aquela transação ainda estiver aberta (linhas de catálogo não commitadas são invisíveis para outras conexões);
- só detecta essa transação aberta por `transacoes_pendentes` enquanto a última query daquela sessão for o próprio 6850.

O comentário da CALL 2 no 6850 foi corrigido para dizer exatamente isso. Antes ele afirmava que as contagens "cobrem" o caso de conexão devolvida ao pool, o que era uma afirmação indevida (item 8 do contrato). A correção é só de comentário; o código ficou idêntico, com 28/28 PASS e 13/13 mutações detectadas.

### 10.2 Contrato de falha: **PASS**

| # | Requisito | Conclusão |
|---|---|---|
| 1 | Erro na criação de objetos não gera PASS | `WHEN OTHERS` registra `v_err` com step, sqlstate e mensagem, e `v_ran_*` fica falso. Resultado: D.1.x FAIL, D.X FAIL, GATE FAIL [INSP] |
| 2 | Erros do 6849 não são mascarados | Erros esperados dentro do 6849 são assertivos (sqlstate exigido), e um sqlstate diferente vira FAIL. Erro inesperado no bloco do 6849 vira `X.1` FAIL e faz o GATE do 6849 reprovar por id extra. O aborto `P6_6849_ROLLBACK_NOT_CONFIRMED` e erros fora do bloco do 6849 sobem para o `WHEN OTHERS` do 6850 e viram D.X FAIL. D.2.1 exige GATE 6849 = PASS **e** 48 linhas [INSP] |
| 3 | 47 verificações + GATE preservados | Corpo byte-idêntico (I3) e hash do `prosrc` conferido em execução (D.0.3). Só 7.7 pode ser `NOT_PROVEN`, regra do próprio 6849 [INSP] |
| 4 | Sucesso não deixa nada permanente | O caminho de sucesso termina sempre na sentinela, que reverte o savepoint. D.3.1 confirma a ausência ou aborta o statement [INSP] |
| 5 | Sentinela distinta de erro inesperado | `P6D00` é levantado uma única vez no artefato, e nenhum dos textos embutidos (6136/6137/6849) o usa (grep: 0). A sentinela do 6849 é outra (`P6R00`) e é consumida dentro do próprio 6849. Se `P6R00` escapasse, cairia em `OTHERS` e viraria FAIL [INSP] |
| 6 | Limites de 5 s e 120 s aplicados | `SET LOCAL` na Seção 0. **D.0.5 lê os valores efetivos em execução** e impede o ensaio se estiverem fora da faixa. O `lock_timeout` vale para qualquer espera de lock. O `statement_timeout` é armado por statement com o valor vigente, então cobre o `SELECT` [INSP; PG: confirmação empírica] |
| 7 | Rollback na mesma execução | Savepoint dentro da função chamada pelo `SELECT`. O artefato não tem `COMMIT` nem `ROLLBACK` e não precisa de chamada posterior (S1, S2) [INSP] |
| 8 | Postcheck sem afirmações indevidas | Corrigido nesta rodada (§10.1) [INSP] |

### 10.3 Usuários — não é necessário criar contas

- O requisito técnico continua: dois UUIDs distintos, existentes em `auth.users` (D.0.6 no 6850 e 0.2 no 6849).
- Contas existentes servem. O ensaio **só lê** `auth.users`. As linhas de favoritos de A e B são criadas e removidas dentro do savepoint, numa tabela que ainda não existe no LIVE. Nenhuma credencial, permissão ou perfil é tocado.
- Recomendação: usar as duas contas **não administrativas**. As verificações de isolamento usam o JWT simulado (`request.jwt.claims`), e contas comuns representam melhor o colecionador.
- Nenhum teste foi removido ou enfraquecido.

### 10.4 D-A revisada

A decisão do responsável é não criar contas. O ensaio usa duas contas existentes não administrativas, escolhidas na execução, e a homologação funcional entre usuários fica com Fabrício após a implantação. Os placeholders permanecem no arquivo versionado.

### 10.5 Procedimento para informar os UUIDs sem versioná-los

1. Opcional, só leitura, num SQL Editor separado: listar candidatos com e-mail mascarado.
   ```sql
   select u.id, left(u.email, 2) || '***@' || split_part(u.email, '@', 2) as email_mascarado
   from auth.users u
   where not exists (select 1 from public.admin_user a where a.id = u.id)
     and u.deleted_at is null
   order by email_mascarado;
   ```
2. Abrir o `6850_dryrun_pokedex_species_favorite.sql`, copiar **todo** o conteúdo para o editor de execução e, **na cópia**, trocar `00000000-0000-0000-0000-00000000000A` e `…00B` pelos dois UUIDs escolhidos. Não salvar a alteração no arquivo do repositório.
3. Antes de executar, conferir que o arquivo continua com o hash `29abf837…0cb3` (ou rodar `verify_6850_identity.py`, que deve dar 28/28) e que `git status` não mostra o 6850 modificado.
4. Executar a CALL 1. Os UUIDs não voltam no relatório: D.0.6 só mostra "2 de 2".
5. Executar a CALL 2 em nova chamada.

### 10.6 Parecer final: **READY** para execução controlada futura

Nenhum BLOCKER. Riscos concretos remanescentes:

- (i) transação da CALL 1 eventualmente deixada aberta pelo canal: locks de leitura e horizonte de VACUUM, sem alteração de dados; ver §10.1;
- (ii) sintaxe ainda não validada por parser, já que qualquer falha reverte e reprova o GATE;
- (iii) bloqueio de alguns segundos em escritas em `auth.users`/`pokemon_species` durante o DDL.

**Próxima operação que depende de autorização:** a CALL 1 do 6850 (o arquivo inteiro, com os dois UUIDs informados só na cópia), seguida da CALL 2 somente leitura. A aplicação permanente de 6136/6137 continua sendo uma decisão separada, posterior ao resultado do ensaio.
