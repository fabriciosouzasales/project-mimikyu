# B3H — registro de closeout PASS-LOCAL e preparação de release do E15

| | |
|---|---|
| Mandato | `BATCH12-E15-B3H-PASS-LOCAL-CLOSEOUT-AND-RELEASE-PREP-01` (2026-09-30) |
| Baseline | `c19161b3cc8a9deda01062a4dadab1885bfc2d47` |
| Execução | Protocolo B local, B3H representativo, **uma única execução**, por Fabrício, em PG17 isolado (`b12-pg17`), sem acesso ao LIVE |
| Evidência | `B3H-LOCAL-EVIDENCE-20260930T231252.zip`, md5 `5bec60ad514c1de6efa84d12adce2fc5`. **Preservada no repositório desde 2026-10-03**, byte a byte, junto com o runner executado `3a0b1075…`: `evidence/B3H-2026-09-30/` (ver §5) |
| Origem dos números | **relatados pela auditoria independente.** O agente não abriu o ZIP; nada aqui foi reexecutado |
| Auditoria do ZIP (2026-10-03) | ZIP aberto e auditado sem reexecução (`BATCH12-PHASE6-A2-P9B-BR1-EVIDENCE-READINESS-01` / `-PRESERVATION-01`). Fato A `elapsed_ms=964` = **prova primária direta**. Fato B, E15 executado = `83e4d5d9…`, = **cadeia de custódia fail-closed indireta, aceita por adjudicação** (§5) |
| Decisão | **B3H = PASS-LOCAL** (auditoria independente) |
| Estado | E15 liberado **localmente** (artefato de release = artefato testado) · **E15 LIVE NÃO executado** · FREEZE ATIVO · 130/135 |

## 1. Provas relatadas pela auditoria

| Item | Resultado |
|---|---|
| Gate B-REP | 18/18 `true` |
| D1 local | 16/16 `true` |
| Sonda | 16/16, equivalente ao D1 |
| HOLD | 107 / `0e56dfffc8cc9ef09b66d4f5fe958d91` |
| PLAN | 285 / `a53343fa38bbbe6f45fea7a4dba4bbdb` |
| READY | 365 / `ee0e4c54336179431797e602a358bb0e` |
| CONDITIONED | 80 / `288f9b45b8e95bfb7123fe9e8693d3a3` |
| H6 | `STAFF_HOLO` PSCID=17, PSVM=1; `SET_LOGO_REVERSE` PSCID=1, PSVM=NULL |
| Envelope | `L_E15_unblocked.sql` (md5 `83e4d5d9a83958282cbc731725c8a298`): `H283P`, `pass=5/5`, casos 5.1, 5.2, 5.3, 5.6, 5.7 |
| C2 (O-1) | 4 nós, 0 executados, todos `never executed` |
| DERIV-D1X | `Execution Time` = 61,076 ms (1 amostra, local, com instrumentação; indicativo, não representativo do LIVE) |
| A3 | resíduo zero |
| Processo | `rc=0` |

Os quatro digests coincidem com a evidência D1 do LIVE (`evidence/D1-2026-09-29/`).

## 2. Defeito do runner (falso negativo)

O runner **efetivamente executado** no B3H — `C:\b12-pg17\B3H-LOCAL-RUN-BOM.ps1`, md5 `3a0b1075e66ac2c6bb3075f04b3a1121` (pino da auditoria independente) — classificou o resultado como **STOP**. A causa é a extração de SQLSTATE do stderr do psql:

- regex antigo: `(?m):\s+([0-9A-Z]{5}):\s`;
- linha real: `psql:/work/e15a/L_E15_unblocked.sql:NNNN: ERROR:  H283P: H2830_ROLLBACK_PASS: …`;
- o regex casou `: ERROR: ` e capturou **`ERROR`** (5 letras maiúsculas) como SQLSTATE. A condição de PASS exigia exatamente `H283P`, então o verdict caiu em STOP.

**Correção (offline, somente em cópia-fonte; nenhum runner executado).** A correção foi aplicada à cópia-fonte offline `B3H-LOCAL-RUN/B3H-LOCAL-RUN.ps1` (outputs do agente; md5 antes `6c2492ed04d8c4dc6a060cef8fe66c1d`, depois `aced0f9d0c6f5ddec84ca86fb1c09133`). **O artefato histórico executado `3a0b1075…` não foi corrigido e permanece imutável.** A linhagem `6c2492ed… → 3a0b1075…` **não foi provada**: o arquivo executado está fora das pastas acessíveis ao agente, e nenhuma de 30 transformações determinísticas da cópia-fonte (UTF-8 com/sem BOM, BOM duplicado, LF/CRLF, com/sem quebra final, UTF-16 LE/BE com/sem BOM, CP-1252) produz `3a0b1075…`. Nesta cópia-fonte, o SQLSTATE agora é ancorado depois do nível da mensagem: `(?m)\b(?:ERROR|FATAL|PANIC|ERRO):\s+([0-9A-Z]{5}):\s`. A exclusão das classes 00/01/02 foi mantida. A regressão é coberta pela prova sintética `RUNNER-REGEX-REGRESSION.py`, que lê o regex do `.ps1` adjacente (a cópia-fonte corrigida, não o artefato `3a0b1075…`):

- 12/12 com o regex novo;
- 5/12 com o regex antigo, reproduzindo a captura de `ERROR`.

A mesma linha foi corrigida em `PROTOCOL-B-EXPORT-PROPOSAL.md` §7 (fora do repositório). O defeito afetava só o verdict do runner, não o banco nem a evidência.

## 3. Promoção do E15 (release local)

- `tools/b12gen/l13.py`: `E15_BLOCKED_53_57 = False`. O gerador reproduz **byte a byte** o artefato testado: `2830H_E15_section5_legacy_hold.sql` passa a ter md5 `83e4d5d9a83958282cbc731725c8a298` (antes `e9fd0227…`).
- `B12-INTEGRATED-MANIFEST.json` foi regenerado. Nenhum outro artefato gerado mudou; E15P segue em `f9fc6d81…`.
- `tools/b12gen/b12_check.py`: o critério R-18/R-21 passou de "E15 bloqueado" para **"E15 = artefato do B3H PASS-LOCAL"**. As negativas cobrem:
  - bloqueio reintroduzido;
  - RAISE condicional;
  - `c2` no lugar de `c3`;
  - 1 byte alterado;
  - gerador com a flag `True`;
  - E15 bloqueado histórico, reconstruído com md5 `e9fd0227…` e rejeitado.

**Limitação conhecida (cosmética, deliberada).** O cabeçalho e os comentários do E15 continuam dizendo "BLOQUEADO pela pendência 5.3/5.7" e "enquanto `E15_BLOCKED_53_57 = True`". Eles foram mantidos para preservar o md5 validado no B3H. Qualquer mudança de texto muda o md5 e exige mandato e reauditoria próprios.

## 4. Fora do escopo

- **E15 não foi executado no LIVE.** A execução no LIVE exige mandato próprio.
- A4a/A4b não foram executados.
- B3H não foi reexecutado.
- Nenhum SQL foi executado nesta rodada.
- Nenhum `git add`/commit/push.
- Digests não fixados além do que já está em `l13.D1_DIGESTS`.
- FREEZE ativo.

## 5. Preservação e auditoria da evidência (2026-10-03, BR-1 do P9(b)′)

Mandatos: `BATCH12-PHASE6-A2-P9B-BR1-EVIDENCE-READINESS-01` e `-PRESERVATION-01`. Nenhum SQL, nenhum acesso ao LIVE, nada reexecutado.

**Preservação.** O ZIP de evidências (`5bec60ad…`, 16.582 B) e o runner executado `B3H-LOCAL-RUN-BOM.ps1` (`3a0b1075…`, 12.872 B) foram copiados byte a byte para `evidence/B3H-2026-09-30/raw/`. Origem = destino por bytes, MD5 e SHA-256. A pasta tem `MANIFEST.md5` no formato PG17 e `.gitattributes` com `raw/** -text`. O relatório completo está em `evidence/B3H-2026-09-30/RELATORIO-EVIDENCIAS.md`. Antes, a evidência ficava fora do repositório e os números acima eram só relatados; agora o ZIP foi aberto e auditado.

**Fato A — `elapsed_ms=964`: prova primária direta.**
- Fonte: linha 1 de `B3H_run.stderr` dentro do ZIP (md5 `bb6c067d…`), com o terminal `H283P` do envelope E15 (`pass=5/5`, rollback intencional).
- 964 ms é o relógio do servidor dentro do DO. 969,330 ms (cliente psql) e 1412 ms (wall do runner) não o substituem.

**Fato B — E15 executado = `83e4d5d9…`: cadeia de custódia fail-closed indireta, aceita por adjudicação.**
- O md5 **não** está dentro do ZIP.
- O runner preservado pina o E15 em `83e4d5d9…` (linha 40) e compara o arquivo real contra o pino no GATE A 3 (linha 61), com `$ErrorActionPreference = 'Stop'` e sem `try` até a execução. A única chamada do B3H (linha 114) só é alcançada depois desse gate, e o `B3H_run.stderr` do ZIP prova que ela foi alcançada.
- Corroboração, sem valor de prova primária:
  - pacote C03 `cae73876…` = `PKG_MD5`, com a entrada `e15a/L_E15_unblocked.sql` = `83e4d5d9…`;
  - o E15 canônico versionado tem o mesmo md5.

**Verdict.** O `STOP` de `B3H_verdict.txt` continua sendo o falso negativo da §2 e foi preservado sem correção. A adjudicação vigente segue **B3H = PASS-LOCAL**, que **não** é P9(b) v7.0 PASS. A afirmação da §2 sobre a linhagem `6c2492ed… → 3a0b1075…` (não provada) permanece inalterada.

**Estado.** **BR-1 = CLOSED por auditoria independente em 2026-10-03** (`BATCH12-PHASE6-A2-P9B-BR1-EVIDENCE-CLOSEOUT-01`). O BR-2 segue aberto.
