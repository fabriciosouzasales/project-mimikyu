# Evidência B3H — execução local de 2026-09-30 (PG17 isolado, Protocolo B)

| Campo | Valor |
|---|---|
| Objetivo | Preservar no repositório a evidência primária do B3H (BR-1 do P9(b)′), para que a prova não dependa de `C:\b12-pg17`. |
| Mandato | `BATCH12-PHASE6-A2-P9B-BR1-EVIDENCE-PRESERVATION-01` (readiness em `…-BR1-EVIDENCE-READINESS-01`). |
| Escopo | Só preservação: bytes originais copiados sem alteração. Nenhum SQL, nenhum acesso ao LIVE, nada reexecutado. |
| Origem | `C:\b12-pg17` (workspace local, não versionado). |
| Conteúdo | `MANIFEST.md5` (md5, bytes, origem e mtime original) e `raw/` (2 arquivos, 29.454 bytes). `.gitattributes` impede normalização de fim de linha em `raw/`. |
| Estado | **B3H = PASS-LOCAL** (adjudicação vigente, `../../B3H-PASS-LOCAL-RECORD.md`). **Não é** P9(b) v7.0 PASS: P9(b) v7.0 e A2 v7.0 seguem NOT SATISFIED AS WRITTEN; o P9(b)′ ainda depende do BR-2. |

## 1. Arquivos preservados

| Arquivo em `raw/` | Bytes | MD5 | SHA-256 | Papel |
|---|---|---|---|---|
| `B3H-LOCAL-EVIDENCE-20260930T231252.zip` | 16.582 | `5bec60ad514c1de6efa84d12adce2fc5` | `df980fa2e16ed80379ef986f0d239244b5024e47417b428fc2e1ea9c8c93b1d6` | evidência primária gerada pelo runner (19 entradas, `MANIFEST.md5` interno) |
| `B3H-LOCAL-RUN-BOM.ps1` | 12.872 | `3a0b1075e66ac2c6bb3075f04b3a1121` | `f2170f2b987c93e811302d307c387603f298ebddb98b5bf00f5c8f2b3e13bc5b` | runner histórico executado (pino da auditoria independente), base da cadeia de custódia do fato B |

Origem = destino por bytes, MD5 e SHA-256 (`cmp` sem diferença). O ZIP preservado passa em `testzip` com 19 entradas. Ambos foram copiados como estão: o runner mantém o BOM UTF-8 e os terminadores CRLF originais.

**Conteúdo do ZIP.** Todos os nomes são planos: sem diretórios, `..`, caminhos absolutos ou symlinks. O `MANIFEST.md5` interno (`f561a1b0…`) cobre as outras 18 entradas, e todas conferem.

**Varredura de segredos (estrita, antes e depois da cópia).**
- ZIP: 0 ocorrências de JWT, chave anon/service, `PGPASSWORD` literal, `SCRAM`, connection string com credencial, `password=`, `token=`, chave privada ou blob base64 longo.
- Runner: nenhum segredo literal. Ele só referencia o caminho `secrets\local_pw.txt` (linha 87), injeta a variável em memória (linha 95) e a remove (linha 202). O arquivo de senha **não** foi copiado.

## 2. Fato A — `elapsed_ms=964`: DIRECT PRIMARY EVIDENCE

Fonte: entrada `B3H_run.stderr` do ZIP (395 bytes, md5 `bb6c067d0882fa01dd129b3173547465`). É a captura bruta do stderr do psql feita pelo runner. Terminal na linha 1:

```
psql:/work/e15a/L_E15_unblocked.sql:1105: ERROR:  H283P: H2830_ROLLBACK_PASS: envelope=E15_SECAO_5_LEGADO_HOLD pass=5/5 casos=5.1,5.2,5.3,5.6,5.7 marker=H2830_C6D63E7D764345F886913C9EAA31041F elapsed_ms=964 hold=107 structural=365 unconditioned=285 conditioned=80 by_pscid=80 by_psvm=40
CONTEXT:  PL/pgSQL function inline_code_block line 1080 at RAISE
LOCATION:  exec_stmt_raise, pl_exec.c:3911
```

- **Envelope E15:** `E15_SECAO_5_LEGADO_HOLD`, `pass=5/5`, casos 5.1, 5.2, 5.3, 5.6 e 5.7.
- **Rollback intencional:** `H283P` é o SQLSTATE do `RAISE` terminal de sucesso, que aborta a transação de propósito. Nada persistiu, e o A3 confirmou resíduo zero (§5).
- **Corroboração no mesmo ZIP:** `B3H_4_envelope_result.txt` (md5 `6ed8c56c…`) tem `sqlstate= H283P` e a mesma mensagem.

São três medidas diferentes, e só a primeira é o `elapsed_ms` do envelope:

| Valor | Origem | O que mede |
|---|---|---|
| **964 ms** | `B3H_run.stderr` | relógio do servidor dentro do bloco DO (`clock_timestamp`), emitido pelo `RAISE` |
| 969,330 ms | `B3H_run.stdout` (`Time:`) | tempo do comando medido pelo cliente psql |
| 1412 ms | `B3H_wall.txt` (`wall_ms=1412 rc=0`) | relógio de parede do runner em volta do processo psql inteiro, incluindo `docker exec` |

Nem 969,330 ms nem 1412 ms substituem 964 ms.

## 3. Fato B — E15 executado = md5 `83e4d5d9a83958282cbc731725c8a298`: INDIRECT FAIL-CLOSED CUSTODY PROOF — ACCEPTED BY ADJUDICATION

**B não está diretamente dentro do ZIP.** A string `83e4d5d9` não aparece em nenhuma das 19 entradas. O manifesto interno cobre só as saídas, não os insumos. A evidência primária registra apenas o **caminho** executado (`/work/e15a/L_E15_unblocked.sql`) e a linha do terminal (1105).

A prova vem do runner preservado (`raw/B3H-LOCAL-RUN-BOM.ps1`). As linhas abaixo são as do arquivo.

**Por que o runner é fail-closed:**

| Linha | Controle |
|---|---|
| 22 | `$ErrorActionPreference = 'Stop'` |
| 25 | `Stop-B` faz `throw "STOP (B3H): …"` |
| 45–114 | Não há `try`/`catch`/`trap` neste trecho; o primeiro `try` está na linha 121, depois da execução. Qualquer `Stop-B` antes da linha 114 encerra o script antes do B3H. |

**Ordem de controle:**

| Linha | Etapa |
|---|---|
| 33–42 | `$Pins`; **linha 40**: `'e15a\L_E15_unblocked.sql' = '83e4d5d9a83958282cbc731725c8a298'` |
| 46–48 | GATE A 1: HEAD = baseline |
| 50–54 | GATE A 2: árvore rastreada limpa |
| 56–57 | GATE A 3: md5 do pacote = `PKG_MD5 cae73876909240bb8ae08602fc097835` |
| 58 | md5 do ZIP B1H |
| 59 | `out\e15b` vazio |
| 60 | `Expand-Archive` do pacote pinado sobre `C:\b12-pg17` (`-Force`), que põe `e15a\L_E15_unblocked.sql` no lugar |
| **61** | **GATE A 3, pinos:** `foreach ($k in $Pins.Keys) { $m = Md5 (Join-Path $W $k); if ($m -ne $Pins[$k]) { Stop-B "pino $k = $m" } }`. Compara o md5 real de cada arquivo extraído, incluindo o E15 e o `e15b\B3H_representative.psql` (`0dfba7d5…`), contra o pino. Divergência encerra antes de qualquer execução. |
| 63–109 | GATE A 6, A 4, A 5 e A 8. Nenhum deles escreve em `e15a\`: a linha 68 grava só `e15b\B1H_export.json`, e a linha 105 grava só em `out\e15b`. |
| **114** | **Única** chamada que executa o B3H: `Invoke-LocalPsqlCapture 'postgres' '/work/e15b/B3H_representative.psql' '/work/out/e15b/B3H_run'`. Só é alcançada depois das linhas 61 e 109. |
| 115 | `B3H_wall.txt` |
| 122 | A3 (resíduo) |
| 164–191 | verdict |
| 195–199 | `MANIFEST.md5` e ZIP |

**Ligação com a evidência primária.** `B3H_run.stderr` é a saída escrita pela linha 114. A linha 93 redireciona `2> $Base.stderr`, com `$Base = /work/out/e15b/B3H_run`. Como esse arquivo existe e contém o terminal do envelope E15, o fluxo chegou à linha 114. Portanto o gate da linha 61 passou, e o `e15a\L_E15_unblocked.sql` em disco tinha md5 `83e4d5d9…` imediatamente antes da execução.

**Corroboração (não é autoridade primária):**

- O pacote `E15-PG17-RECOVERY-C03.zip` (md5 `cae73876909240bb8ae08602fc097835` = `PKG_MD5`) contém:
  - `e15a/L_E15_unblocked.sql` com md5 `83e4d5d9…`, 79.913 bytes e 1105 linhas; a última linha coincide com o `:1105` do terminal;
  - `e15b/B3H_representative.psql` com md5 `0dfba7d5…`, que na linha 43 tem `\ir ../e15a/L_E15_unblocked.sql`.
- O E15 canônico versionado, `../../2830H_E15_section5_legacy_hold.sql`, tem o mesmo md5 `83e4d5d9…`.
- `C:\b12-pg17\out\container_inspect.json` (2026-09-28, não preservado) registra o bind `C:\b12-pg17 → /work` do container `b12-pg17`.

O C03 não foi copiado e o SQL do E15 não foi duplicado.

**Limites declarados da prova indireta:**
- nenhum log do runner registra o gate da linha 61 passando; a passagem é inferida pela chegada à linha 114;
- o GATE A 4 (linha 79) verifica o destino `/work`, mas não a origem do bind, que só é corroborada pelo `container_inspect.json`;
- a ligação entre este runner (`3a0b1075…`) e o ZIP vem do pino da auditoria independente, da coerência de formato das saídas (`B3H_wall.txt` e `B3H_verdict.txt` seguem as linhas 115 e 176–191) e da cronologia (runner com mtime 22:59:35Z, ZIP nomeado e com mtime 23:12:52Z, linha 198).

## 4. Falso STOP histórico

`B3H_verdict.txt` (md5 `10500291…`) diz `verdict=STOP`. É um **falso negativo do runner histórico**, causado pela extração de SQLSTATE da linha 135:

- o regex `(?m):\s+([0-9A-Z]{5}):\s` casou `: ERROR: ` e capturou `ERROR`;
- por isso o arquivo traz `first_err=ERROR` e `all_err_sqlstates=ERROR`;
- a condição de PASS-LOCAL (linha 168) exigia `($errS -join ',') -eq 'H283P'`.

O defeito está descrito em `../../B3H-PASS-LOCAL-RECORD.md` §2. A evidência histórica não foi apagada nem corrigida.

| Camada | Conteúdo |
|---|---|
| Verdict mecânico histórico | `STOP` (`B3H_verdict.txt`, linha 1) |
| Evidência material | `H283P` `pass=5/5` (§2); processo `rc=0` (`B3H_run.rc`); `env_sqlstate=H283P`; `gate18_all_true=True`; `explain_ok=True`; `c2_nodes=4`, `c2_executed=0`; `a3_residue_ok=True` (`B3H_residue.stdout`: `cv_total 24893`, `open_xacts_other 0`, stubs ausentes); GATE A 8 `true\|170006\|127.0.0.1` |
| Adjudicação vigente | **B3H = PASS-LOCAL**. Não é P9(b) v7.0 PASS. |

## 5. Fora do escopo

- Nenhum SQL executado, nenhum acesso ao LIVE, banco e Docker inalterados.
- `C:\b12-pg17` só foi lido.
- Arquivos não copiados:
  - `E15-PG17-RECOVERY-C03.zip`;
  - `secrets\`;
  - `container_inspect.json`;
  - `B3H-LOCAL-RUN.ps1` (`540a3e2c…`, outra versão, não é o pino).
- Sem `git add`, commit ou push.
- Não alterados: 2830 v7.0, proposta v7.2, `EXECUTION-BATCHES.md` e o documento de adjudicação A2/P9(b).
- O BR-1 só fecha após a auditoria desta preservação. O BR-2 segue aberto. FREEZE ATIVO.
