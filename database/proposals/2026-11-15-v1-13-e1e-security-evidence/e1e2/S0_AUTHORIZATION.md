# V1-13 · E1-E — Pacote de decisão para a S0 (`S0_G2_readonly.sql`)

| Campo | Valor |
|-------|-------|
| **Rodada** | `V1-13 / E1-E \| S0 AUTHORIZATION READINESS-01` (2026-11-15); reconciliado em `S0 V1.1 LOCAL CLOSEOUT AND COMMIT-02` (procedimento Windows PowerShell §5.1, segurança do canal §5.2, governança de evidências §5.3) |
| **Status** | **S0 NÃO EXECUTADA. Este documento não autoriza a execução.** |
| **Arquivo** | `database/proposals/2026-11-15-v1-13-e1e-security-evidence/e1e2/S0_G2_readonly.sql` v1.1 |
| **SHA-256** | `142d1492fe9ebb1ac34a62f7c92f247eab7ee2ee30e74a2725bd5dc8992ceed2` (registrado em `G2_MANIFEST.sha256`) |
| **Base** | `main` em `2bd0024` |

## 1. Correções mínimas desta rodada (v1.0 → v1.1)

| Defeito | Correção |
|---|---|
| `papeis_api` devolvia o `rolconfig` inteiro de anon, authenticated, authenticator e service_role — pode conter configurações sensíveis | só as chaves `statement_timeout`, `lock_timeout` e `idle_in_transaction_session_timeout`; service_role fora |
| faltavam pré-condições que os ensaios G2 exigem | `executor`: pode assumir `anon` e `authenticated` (os harnesses usam `SET LOCAL ROLE`); superusuário/bypass de RLS (informativo); escrita em `auth.users` e `storage.objects` (fixtures); leitura de `storage.buckets` |
| não havia prova, no servidor, do que o canal configurou | `ambiente.transaction_read_only`, `statement_timeout_sessao`, `lock_timeout_sessao` |
| verificação 5.1 não pegava `pg_sleep`, `SET`, segunda instrução nem efeitos por função | 5.1 analisa o texto fora de literais, recusa funções com efeito e exige uma única instrução; nova 5.3 (chaves de timeout, pré-condições do executor, nenhuma coluna privada na saída). Mutações: rolconfig inteiro, `pg_sleep`, segunda instrução, e-mails na saída — todas detectadas |

Ensaios G2_A/B/C e a variante 5863 **inalterados** (sha256 conferido); só o `G2_MANIFEST.sha256` mudou (entrada da S0).

## 2. Parecer sobre a segurança da consulta

1. **Só leitura:** uma única instrução `SELECT jsonb_build_object(...)`; sem DO, sem `set_config`, sem DML/DDL, sem `nextval`, sem tabela temporária.
2. **Funções:** só catálogo e informação (`current_setting`, `pg_has_role`, `has_table_privilege`, `pg_get_constraintdef`, `pg_get_userbyid`, `to_regclass`, `md5`, `jsonb_*`). Nenhuma com efeito colateral conhecido.
3. **Não altera** configuração, privilégio nem dado.
4. **Travas:** `AccessShareLock` nas tabelas lidas (inclui `auth.users`, `storage.objects`, `collection_membership`, histórico, `physical_card`) — só conflita com ACCESS EXCLUSIVE. **Impacto não nulo:** as contagens fazem varredura completa (`storage.objects`, histórico, `physical_card`, `auth.users`) e, se houver um ACCESS EXCLUSIVE na fila, a S0 espera; por isso o canal define `lock_timeout` e `statement_timeout` (§5).
5. **Objetos que podem não existir:** referências diretas só a objetos da V1-12 e anteriores e do Supabase (`storage.buckets`, `storage.objects`, `supabase_migrations.schema_migrations`); objetos da V1-13 só por `to_regclass`/`to_regprocedure`/`pg_proc` (não falham se ausentes). Se o ledger não existir, a consulta inteira falha → **INCONCLUSIVE**.
6. **Detecção:** chave `v113` (barreira, CHECK, sobrecargas do convite, funções novas, colunas da 5379, gatilho da 5381, participações EDITOR) e `md5` (24 funções por nome, todas as sobrecargas) mostram aplicação parcial, definição inesperada ou migration ausente.
7. **Hashes:** 24 md5 canônicos iguais aos corpos vigentes de `database/schema/` (verificação 5.2), inclusive `set_pokedex_position_assignment` = `8c57…` (6123).
8. **PostgreSQL e privilégios:** versão, `transaction_timeout`, `client_connection_check_interval`, executor, dono/pertença/privilégio por tabela travada, SET ROLE, escrita das fixtures.
9. **Privacidade:** só contagens, nomes de objetos, md5 e chaves de configuração filtradas; e-mails e nomes de usuário aparecem só em filtros de contagem; nenhuma credencial nem texto de consulta de outras sessões.
10. **Falha identificável:** objeto ausente ou privilégio de leitura insuficiente → erro do servidor, a S0 não produz JSON → INCONCLUSIVE com a mensagem do erro.

**Conclusão:** segura para execução sob as condições do §5.

## 3. Matriz de evidências

| Condição | Fonte | Chave | Referência | PASS | FAIL | INCONCLUSIVO | Impacto no G2 |
|---|---|---|---|---|---|---|---|
| Versão do PostgreSQL | `server_version_num` | `ambiente.server_version_num` | ≥ 140000 | ≥ 140000 | < 140000 | consulta falhou | < 14: NO-GO; < 17: sem teto total de transação (só sentinela/operador) |
| Teto de transação | `pg_settings` | `ambiente.transaction_timeout_disponivel` | — | registrado | — | — | define o limite dos ensaios |
| Sessão só leitura e timeouts efetivos | `current_setting` | `ambiente.transaction_read_only`, `*_timeout_sessao` | `on`, valores do canal | iguais ao canal | `off` | — | prova que o canal aplicou os controles |
| Executor | `current_user` | `ambiente.current_user` | `postgres` | `postgres` | outro | — | T6 dos ensaios recusa outro executor |
| SET ROLE dos harnesses | `pg_has_role` | `executor.assume_anon`, `assume_authenticated` | true | true | false | — | false: ensaios inexequíveis |
| Fixtures | `has_table_privilege` | `executor.auth_users_escrita`, `storage_objects_escrita` | true | true | false | — | false: harnesses falham na fixture |
| Travas e políticas em Storage | `pg_class`, `pg_has_role`, `has_table_privilege` | `privilegios["storage.objects"]` | dono ou membro; UPDATE/DELETE/TRUNCATE | true/true | false | — | false: 5377 e LOCK NOWAIT inviáveis → G2_B/C NO-GO (G2_A não depende) |
| Travas nas tabelas compartilhadas | idem | `privilegios[...]` de membership, histórico | idem | true | false | — | LOCK NOWAIT da T6 |
| Funções canônicas | `pg_proc` | `md5[*].confere` | md5 de `database/schema` | todas true | alguma false ou duplicada | — | divergência = estado diverge do baseline: G2 NO-GO até reconciliar |
| Nada da V1-13 aplicado | `pg_proc`, `pg_constraint`, `information_schema`, `pg_trigger` | `v113` | barreira false; CHECK só VIEWER; 1 sobrecarga; lista vazia; colunas 0; gatilho false; EDITOR 0 | tudo como referência | qualquer desvio | — | aplicação parcial = STOP |
| Políticas de Storage | `pg_policies` | `storage.politicas` | 9 nos dois buckets + políticas do logo | exatamente as esperadas | ausente ou extra | — | divergência invalida 5863/5890 |
| Buckets | `storage.buckets` | `storage.buckets` | collection-cover privado, limites da 5176 | conforme | divergente | — | idem |
| Gatilhos com efeito externo | `pg_trigger` + `prosrc` | `gatilhos[*].externo` | todos false | todos false | algum true | — | true: NO-GO |
| Gatilhos de evento | `pg_event_trigger` | `eventos` | sem `externo` true | conforme | algum true | — | idem |
| Publicações | `pg_publication_tables` | `publicacoes` | registrado | — | — | — | informativo (transação abortada não é decodificada) |
| Extensões | `pg_extension` | `extensoes` | registrado | — | — | — | com pg_net/http: revisar gatilhos (já cobertos) |
| Ledger | `supabase_migrations.schema_migrations` | `ledger` | últimas conhecidas; nenhuma da V1-13 | conforme | migration da V1-13 presente | tabela ausente | baseline |
| Sessões | `pg_locks`, `pg_stat_activity` | `sessoes` | 0 com trava; poucas longas | registrado | — | — | define a janela (não decide sozinho) |
| Timeouts da API | `pg_roles.rolconfig` (filtrado) | `papeis_api` | registrado | — | — | — | impacto das esperas O1–O3 sobre a API |
| Fixtures (catálogo) | tabelas de catálogo | `fixture` | todos true | todos true | algum false | — | false: harness falha na fixture |
| Resíduo sintético | `auth.users`, `user_profile`, `collection`, `storage.objects` | `residuo` | 0 | 0 | > 0 | — | > 0: STOP (execução anterior não autorizada?) |
| Volumes | contagens | `contagens` | — | — | — | — | informativo; base para M1–M7 e para o pós-estado |

## 4. Limitações de observabilidade (exigem outro procedimento)

- Se o executor consegue de fato `CREATE POLICY`/`LOCK` em `storage.objects` (pertença e privilégio são indícios, não prova) → ensaio.
- Retenção real das travas, duração dos harnesses, comportamento das versões protegidas → ensaio G2.
- Integrações externas fora do catálogo (webhooks do painel, funções de borda, replicação externa, integrações do Auth/Storage): **ausência de registro não prova ausência** → confirmação do proprietário no painel.
- Tráfego e janela de uso → monitoramento do proprietário no momento.
- PostgREST, JWT real, API do Storage → G3/G4.

## 5. Condições para uma autorização futura

| Item | Condição |
|---|---|
| Executor | o proprietário, como `postgres`, sem `SET ROLE` |
| Canal | psql, conexão **direta** (porta 5432 do banco, não pooler em modo transação/statement), não interativo |
| Comando | Unix: `PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=60s -c lock_timeout=3s -c idle_in_transaction_session_timeout=30s' psql -X -v ON_ERROR_STOP=1 -c 'BEGIN READ ONLY' -f S0_G2_readonly.sql -c 'ROLLBACK'`. **Windows PowerShell: §5.1.** Os controles ficam no canal, não no arquivo (a S0 continua um SELECT único); a saída `ambiente` mostra, no servidor, o que vigorou (§5.2) |
| Arquivo | conferir `sha256sum` = `142d1492…ceed2` imediatamente antes |
| Duração e espera | 60 s por instrução; 3 s para obter trava; acima disso o servidor cancela → INCONCLUSIVE, sem repetir na mesma janela |
| Indisponibilidade | conexão recusada, timeout ou erro → INCONCLUSIVE; nenhuma outra tentativa sem nova decisão |
| Dados sensíveis | saída só com contagens, nomes de objetos, md5 e timeouts; guardar sem credenciais (a senha nunca vai ao comando nem ao log; usar `.pgpass` ou variável local do executor) |
| Destino | arquivo JSON da saída + data/hora + sha256 do arquivo da S0, anexado ao relatório da próxima rodada |
| Interrupção | `transaction_read_only` ≠ `on`, timeouts divergentes do canal, executor ≠ `postgres` ou conexão por pooler → STOP; erros de conexão, timeout ou privilégio → INCONCLUSIVE (§5.2) |
| Evidências | o JSON completo, o comando exato (sem segredo), a versão do psql e o código de saída (lista completa em §5.3) |

### 5.1 Procedimento Windows PowerShell (modelo — não executado)

Compatível com **Windows PowerShell 5.1** (o que acompanha o Windows 11) e com **PowerShell 7.x**: não usa `&&`/`||`, `?:` nem nenhum recurso exclusivo do 7. O próprio bloco registra a versão em uso (`$PSVersionTable`). Colar o bloco inteiro de uma vez numa janela nova, com `$ErrorActionPreference` no padrão (`Continue`). Os valores entre `< >` são preenchidos pelo proprietário no momento e **não** são registrados no repositório.

```powershell
# --- S0 v1.1 · modelo de execução única · NÃO executar sem autorização expressa ---
$esperado = '142d1492fe9ebb1ac34a62f7c92f247eab7ee2ee30e74a2725bd5dc8992ceed2'
$s0       = '<repositório>\database\proposals\2026-11-15-v1-13-e1e-security-evidence\e1e2\S0_G2_readonly.sql'
$destino  = Join-Path $env:USERPROFILE ('mmkyu-evidencias\s0-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$obtido   = (Get-FileHash -Algorithm SHA256 -LiteralPath $s0).Hash.ToLowerInvariant()
if ($obtido -ne $esperado) {
    Write-Host "STOP: sha256 divergente ($obtido). Nada foi executado."
} else {
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    # Parâmetros de conexão NÃO sensíveis. Nenhuma senha aqui.
    $env:PGHOST           = '<host da "Direct connection" do projeto>'   # nunca o host do pooler
    $env:PGPORT           = '5432'
    $env:PGUSER           = 'postgres'                                   # direto: "postgres"; "postgres.<ref>" indica pooler
    $env:PGDATABASE       = 'postgres'
    $env:PGSSLMODE        = 'verify-full'                                # mínimo aceitável: require
    $env:PGSSLROOTCERT    = '<caminho do certificado raiz do projeto>'   # omitir só se PGSSLMODE=require
    $env:PGAPPNAME        = 'mmkyu-s0-v1.1'
    $env:PGCLIENTENCODING = 'UTF8'                                       # o arquivo é UTF-8; evita conversão pela página de código do console
    $env:PGOPTIONS        = '-c default_transaction_read_only=on -c statement_timeout=60s -c lock_timeout=3s -c idle_in_transaction_session_timeout=30s'
    $registro = [ordered]@{
        powershell = $PSVersionTable.PSVersion.ToString()
        psql       = (& psql --version)
        sha256     = $obtido
        host       = $env:PGHOST; porta = $env:PGPORT; usuario = $env:PGUSER; banco = $env:PGDATABASE
        sslmode    = $env:PGSSLMODE; pgoptions = $env:PGOPTIONS
        comando    = "psql -X -q -A -t -v ON_ERROR_STOP=1 -o <destino>\s0_saida.json -c 'BEGIN READ ONLY' -f S0_G2_readonly.sql -c 'ROLLBACK'"
        inicio_utc = (Get-Date).ToUniversalTime().ToString('o')
    }
    # Execução única. A senha, se pedida, é digitada no prompt do psql (não vai ao histórico do PowerShell).
    & psql -X -q -A -t -v ON_ERROR_STOP=1 -o (Join-Path $destino 's0_saida.json') -c 'BEGIN READ ONLY' -f $s0 -c 'ROLLBACK' 2>&1 |
        Out-File -Encoding utf8 -FilePath (Join-Path $destino 's0_erros.txt')
    $registro.codigo_saida = $LASTEXITCODE
    $registro.fim_utc      = (Get-Date).ToUniversalTime().ToString('o')
    $registro | ConvertTo-Json | Out-File -Encoding utf8 -FilePath (Join-Path $destino 's0_registro.json')
    Remove-Item Env:PGHOST, Env:PGPORT, Env:PGUSER, Env:PGDATABASE, Env:PGSSLMODE, Env:PGSSLROOTCERT,
                Env:PGAPPNAME, Env:PGCLIENTENCODING, Env:PGOPTIONS -ErrorAction SilentlyContinue
    Write-Host "Código de saída: $($registro.codigo_saida). Evidências em $destino"
}
```

Notas do procedimento:

- **Mesma instrução SQL:** o arquivo é passado por `-f` sem alteração; `-q -A -t` só mudam a formatação no cliente (o arquivo de saída fica só com o JSON). `-X`, `ON_ERROR_STOP=1`, `BEGIN READ ONLY` e `ROLLBACK` preservados.
- **Falha no meio:** com `ON_ERROR_STOP=1`, o psql termina antes do `ROLLBACK`; ao desconectar, o servidor aborta a transação. Nada fica aberto.
- **Código de saída do psql:** `0` concluiu; `1` erro do próprio psql (ex.: arquivo não encontrado); `2` conexão falhou; `3` erro do servidor durante a S0. Classificação em §5.2.
- **Integridade do arquivo no Windows:** o `.gitattributes` fixa `eol=lf` para `*.sql`, então o checkout no Windows não troca o fim de linha e o sha256 não muda. Divergência mesmo assim → STOP.
- **Credenciais:** proibido `$env:PGPASSWORD = ...`, senha na URI (`postgresql://...:senha@`) ou em qualquer parâmetro da linha de comando — tudo isso vai para o histórico do PSReadLine (`(Get-PSReadLineOption).HistorySavePath`). Permitidos: o prompt interativo do psql, ou `%APPDATA%\postgresql\pgpass.conf` com acesso restrito ao usuário. Depois da execução, conferir que o histórico do PSReadLine não contém a senha.
- **Destino das evidências:** pasta do perfil do usuário, **fora do repositório**. Nada é versionado sem nova autorização.

### 5.2 Segurança do canal

- **Conexão direta autorizada:** só o host de "Direct connection" do projeto, porta 5432, usuário `postgres`. Pooler (qualquer modo, inclusive sessão), SQL Editor do painel, MCP, PostgREST ou outra ferramenta → canal inadequado: **não executar**; se executado, **STOP**.
- **Sem conexão direta disponível** (ex.: rede sem rota para o host direto): **INCONCLUSIVE**; não trocar de canal por conta própria.
- **Identidade do executor:** confirmada antes (o proprietário, `PGUSER=postgres`) e depois (`ambiente.current_user` e `ambiente.session_user` = `postgres`). Divergência → STOP.
- **Limites do cliente × servidor:** a saída precisa mostrar `ambiente.default_transaction_read_only = on`, `ambiente.transaction_read_only = on`, `ambiente.statement_timeout_sessao = 1min` (o PostgreSQL exibe 60 s como `1min`) e `ambiente.lock_timeout_sessao = 3s`. Divergência → STOP. **Limite de observação:** a S0 v1.1 não devolve o `idle_in_transaction_session_timeout` da sessão; ele é inferido porque vai no mesmo `PGOPTIONS` (uma opção recusada impede a conexão inteira) e só importa se o cliente travar entre o `BEGIN` e o `ROLLBACK`. Não justifica alterar a S0 aprovada; se uma revisão futura for necessária por outro motivo, incluir essa chave.
- **Classificação de falhas:**

| Situação | Resultado |
|---|---|
| sha256 divergente, canal ou executor fora do protocolo, sessão não somente leitura, timeouts divergentes do canal | **STOP** |
| código 2 (conexão recusada, TLS, autenticação), timeout de instrução (`57014`), espera por trava (`55P03`), objeto ausente (`42P01`/`42883`), privilégio de leitura insuficiente (`42501`) | **INCONCLUSIVE**, sem nova tentativa na mesma janela |
| código 1 (erro do psql) | **INCONCLUSIVE** |
| código 0 com JSON | avaliar a matriz (§3) → PASS / FAIL / STOP |

- **Impacto operacional não nulo:** mesmo somente leitura, a S0 pode esperar por trava (até 3 s) se houver DDL concorrente, enquanto espera pode atrasar outras sessões que entrarem na fila depois dela, e faz varreduras completas nas contagens (até 60 s). Executar fora de horário de uso e de qualquer migration.

### 5.3 Governança de evidências

Preservar, numa execução futura autorizada (em `s0_registro.json`, `s0_saida.json` e `s0_erros.txt`):

| Registro | Fonte |
|---|---|
| sha256 do arquivo realmente executado | `Get-FileHash` antes da execução |
| horário de início e fim (UTC) | `inicio_utc`, `fim_utc` |
| identidade do executor | o proprietário (declarado no relatório) + `ambiente.current_user`/`session_user` |
| canal | "psql, conexão direta" + host/porta/sslmode (não sensíveis) |
| parâmetros de conexão não sensíveis | host, porta, usuário, banco, sslmode, `PGOPTIONS` |
| comando sem credenciais | `comando` |
| versão do PowerShell e do psql | `powershell`, `psql` |
| saída completa da S0 | `s0_saida.json` |
| código de saída | `codigo_saida` |
| mensagens de erro | `s0_erros.txt` |

Não guardar senha, `pgpass.conf`, certificados privados, e-mails nem qualquer dado de usuário. Nenhum resultado simulado ou presumido é evidência: só os três arquivos produzidos pela execução autorizada.

## 6. Decisões após a S0

| Resultado | Quando |
|---|---|
| **S0 PASS** | todas as linhas [=] da matriz em PASS e nenhuma em FAIL |
| **S0 FAIL** | qualquer divergência material comprovada (md5, aplicação parcial, privilégio ausente, gatilho externo, resíduo) |
| **S0 INCONCLUSIVE** | consulta falhou (objeto ausente, privilégio de leitura insuficiente, timeout) ou informação insuficiente |
| **S0 STOP** | executor/canal fora do protocolo, sessão não somente leitura, resíduo sintético, aplicação parcial da V1-13 ou risco operacional |

**S0 PASS não autoriza** P1, G2_A/B/C, persistência restrita (G3) nem provas G4; **não comprova** S1–S10; **não encerra** a PR-04B; **não libera** a etapa 7. Cada autorização posterior é independente.

## 7. Riscos residuais

Varredura das contagens em horário de uso; espera por trava se houver DDL concorrente (limitada pelo `lock_timeout`); a S0 é uma fotografia (o estado pode mudar até o ensaio — por isso a S0 se repete imediatamente antes de qualquer G2); integrações externas não visíveis no catálogo; S1–S10, S8/S10 concorrentes, PR-04B, P4-A/P4-B, API real do Storage, O1–O7, desempenho não medido — inalterados.

## 8. Recomendação

A S0 v1.1 está adequada para um **pedido de autorização explícita** de execução única, nas condições do §5. Nenhuma outra operação deriva dela.
