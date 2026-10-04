# LIVE — P14(a) captura LIVE × CN1 · Registro de execução

| Campo | Valor |
|---|---|
| **Mandato** | `BATCH12-P14A-LIVE-CAPTURE-EXECUTION-01` (execução, 2026-10-04 UTC) · fechamento: `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01` |
| **Baseline** | HEAD `b95f57e584a3c7899c8c09f02ba8cf3567ca5d1a` (`docs(batch12): close P9a A2 successor and phase 6`), árvore e índice limpos antes e depois da execução |
| **Instrumento** | `P14A_FINGERPRINT.sql` — md5 `2738566c55f7a4792159362ce29bb3e0`, sha256 `6c217243ec661677aefebeb72b776c0b9ec0f9af229ba9c093693c6e26fdbf24`, 14.610 B, CR = 0, LF final. É o mesmo SQL pinado e executado no CN-1 (`evidence/CN1-2026-10-02/raw/evidence-snapshot/CN1-4-P14A-LOCAL/06_sql_pin.txt`) |
| **Baseline de comparação** | `P14A_CN1_OUTPUT.csv` do CN-1 — md5 `07cbe1369cf2768f00a72f17bd5dfdb3`, sha256 `23e84e3156bea9ea0dbd98054cc9fd19860c14d0e51d82982a3384cff7e1a91e`, 10.900 B |
| **Comparador** | `p14a_compare.py` congelado — md5 `c1feb5076e281deaf0a67e722871900c`, sha256 `b4eb0baa73e099a5e9994b5321e2fec525cad8a2a67672752e4d8c6590161721` (forma 31/1/2 obrigatória, `sort_key` comparado, só `PASS_EXACT` retorna rc 0) |
| **Canal** | MCP Supabase `execute_sql`, projeto `qjfutqujxrbzgrtkpgkg`; uma chamada = um statement |
| **Chamadas autorizadas** | 2 (L3 + P14A). Executadas: 2 |
| **Evidência** | `evidence/P14A-LIVE-CAPTURE-2026-10-04/` — `MANIFEST.md5` (17 entradas, `md5sum -c` 17/17 OK) + o próprio manifesto + `.gitattributes` `* -text` = 19 arquivos |
| **Pacote de origem** | `P14A-LIVE-CAPTURE-2026-10-04.zip`, fora do repositório — md5 `affde3a06ae36313cee95040b96d695c`, sha256 `cda1fa6860dc07b1df27774a59c127223655cfc8238fb479baf9fb8a6b9b0833`, 29.046 B |
| **Resultado** | **P14(a) CLOSED** · **P14(e) CLOSED** (auditoria independente PASS; §6) |
| **FREEZE** | ATIVO. Nada aqui autoriza UNFREEZE. |

## 1. Sequência

| # | Chamada | Envio (cliente, UTC) | Resultado (cliente, UTC) | Resultado |
|---|---|---|---|---|
| S1 | L3 (verbatim de `LIVE-VALIDATION-PROTOCOL.md` §3.2) | 2026-10-04T00:58:26.615Z | 00:58:31.122Z | PASS |
| S2 | `P14A_FINGERPRINT.sql` (verbatim) | 2026-10-04T00:59:21.075Z | 00:59:25.411Z | 34 linhas |

Os horários de envio e de resultado são os do registro do cliente (`S1-L3.call_meta.json`, `S2-P14A.call_meta.json`). O `checked_at` do servidor na L3 é `2026-10-04T00:56:32.228183Z`: os relógios do cliente e do servidor diferem em cerca de dois minutos, e a ordem das chamadas é a do registro do cliente.

## 2. L3

- **Texto submetido:** `L3.sql` = `S1-L3.submitted.sql`, md5 `b7bc3700aeef278f6a79bd30e6a8d229`, 1.526 B; igual ao precedente de 2026-09-27 e de 2026-10-03.
- **Resposta original:** `S1-L3.response.json`, md5 `b4f964acc1452f99d4acbe44de306952`, sha256 `22b6f860a2e2090d6e607536a6ed6dec5de60ac34e11de05a104675d5c907863`, 8.755 B.
- **Resultado:**
  - 27 sessões no banco além da própria: 25 `client backend`, 1 `pg_cron launcher` e 1 `pg_net` worker;
  - `client backend`: 25/25 `idle`, 25/25 `xact_start = null` (PostgREST, pgbouncer, Storage API, `postgres_exporter`, `supabase_admin`). A classificação nominal é só diagnóstica;
  - `locks_on_scope = []`.
- **PASS.**

## 3. P14A

- **Identidade submetida:** o parâmetro `query` da chamada S2, recuperado do registro do cliente, foi gravado em `S2-P14A.submitted.sql` e é **byte a byte** igual a `P14A_FINGERPRINT.sql` (`cmp` sem diferença; md5 `2738566c…`, 14.610 B).
- **Resposta original:** `S2-P14A.response.json`, md5 `8824595d8da4a783c6e5a51033e95f0c`, sha256 `2b1076625f8e79346ba6215e3cb3dc23f4f3075defe1c27c9fe32e63742c0566`, 21.296 B.
- **Corpo:** `S2-P14A.body.json`, md5 `8b2f9ee699dc7a1a2c052383942cb9d0`, sha256 `da6c92b5bc136e7cb9995e604260abe0b9bc5e70b8b30c59d8b240e66c619e26`, 18.529 B.
- **Forma:** 34 linhas = **ITEM 31 · CONTEXT 1** (`session`, `sort_key` 90001) **· AGGREGATE 2** (`agg_raw` 90002, `agg_lf` 90003).

## 4. Comparação LIVE × CN1

`python3 p14a_compare.py cn1_P14A_CN1_OUTPUT.csv S2-P14A.response.json` (CLI real; saída integral em `COMPARE.stdout.txt`, stderr vazio, `COMPARE.rc.txt` = 0):

| Item | Resultado |
|---|---|
| Baseline CN1 | 31 itens, `{PRESENT: 27, ABSENT_OK: 4}`, agregados recalculados OK |
| Forma LIVE | `live_shape_ok=True` |
| Itens | 31 casados, 0 extra, integridade dos agregados = True |
| Classes | **EXACT 31** · EOL_ONLY 0 · RENDER_ONLY 0 · DIVERGENT 0 · MISSING 0 · EXTRA 0 |
| Contexto | `context_equal=True` — `search_path="\$user", public, extensions` · `server_version_num=170006` nos dois lados |
| `agg_raw` | CN1 `6e2ef02eb70c4c47103bb89d813288cd` = LIVE `6e2ef02eb70c4c47103bb89d813288cd` |
| `agg_lf` | CN1 `e926f44dc930f08cb81a65d8a72e1549` = LIVE `e926f44dc930f08cb81a65d8a72e1549` |
| **Veredito** | **`PASS_EXACT` / rc = 0** |

## 5. Custódia

- **Resposta → corpo:** `*.response.json` é o invólucro integral do canal, preservado sem alteração. `*.body.json` é o payload JSON bruto extraído desse invólucro (o conteúdo entre os marcadores do canal), seguido de um LF final. O corpo do P14A re-serializa byte a byte e tem as 34 linhas; não houve truncamento.
- **Comparador e baseline** foram copiados para a pasta com os mesmos bytes do pacote de readiness auditado (`p14a_compare.py`, `cn1_P14A_CN1_OUTPUT.csv`).
- **Manifesto:** `MANIFEST.md5` cobre os 17 arquivos originais da execução (inclusive `HASHES.txt` e `RESULT.txt`) e não inclui a si mesmo nem o `.gitattributes`, acrescentado só na preservação no repositório. Validação a partir da pasta: `md5sum -c MANIFEST.md5` → 17/17 OK. Os 17 arquivos são byte-idênticos à origem (`cmp`), sem CR.
- **Correção factual:** o relato da execução dizia "16/16". A auditoria independente do ZIP constatou 17 entradas, 17/17 OK e 18 arquivos contando o manifesto. Vale a contagem auditada; a evidência não foi alterada.

## 6. P14(e) — prova componente a componente

Texto literal (2830 v7.0, P14(e)): *"Evidência registrada: impressão digital LIVE × ambiente, prova de canal (c), script, saídas, pg_locks / pg_stat_activity / pg_blocking_pids nos pontos de espera."*

| # | Componente | Onde está registrado | Estado |
|---|---|---|---|
| 1 | Impressão digital LIVE × ambiente | lado ambiente: `evidence/CN1-2026-10-02/raw/evidence-snapshot/CN1-4-P14A-LOCAL/` (`P14A_CN1_OUTPUT.csv`, `RESULT.txt`); lado LIVE e comparação: `evidence/P14A-LIVE-CAPTURE-2026-10-04/` (`S2-P14A.*`, `COMPARE.stdout.txt` → `PASS_EXACT`) | registrado |
| 2 | Script | instrumento de impressão digital `P14A_FINGERPRINT.sql` (md5 `2738566c…`) versionado em `evidence/P14A-LIVE-CAPTURE-2026-10-04/` e pinado em `CN1-4-P14A-LOCAL/06_sql_pin.txt`; scripts SQL dos cenários em `CN1-5-P14BC-CORRECTION-02/sql/`, `CN1-6-K1/sql/`, `CN1-6-K2-CORRECTION-02/sql/`, `CN1-6-K8B-CORRECTION-04/sql/`; runners pinados por md5 em cada `RESULT.txt` | registrado |
| 3 | Saídas | `RESULT.txt` e transcritos de cada conjunto CN-1; `S1-L3.*`, `S2-P14A.*` e `COMPARE.*` do LIVE | registrado |
| 4 | Prova de canal (c) | `CN1-5-P14BC-CORRECTION-02/` (C1/C2, R1/R2 PASS; `22_c_observer.txt`, `30_transcript_*.txt`: `pg_backend_pid()`, `txid_current()`, `idle in transaction` com `backend_xid`); `S1-L3.*` registra o canal LIVE (MCP, projeto `qjfutqujxrbzgrtkpgkg`) | registrado |
| 5 | `pg_locks` | `CN1-6-K1/25_B_wait_snapshot.txt`, `CN1-6-K8B-CORRECTION-04/24_wait_snapshot.txt` (Q3 `pg_locks`), `CN1-6-K2-CORRECTION-02/24_K2b_http_blocked.txt`, `29_K2c_http_blocked.txt`; no LIVE, `locks_on_scope` da L3 | registrado |
| 6 | `pg_stat_activity` | mesmos snapshots de espera (Q1), `CN1-5-P14BC-CORRECTION-02/sql/q_sessions.sql` e `30_transcript_OBS.txt`; no LIVE, `sessions` da L3 | registrado |
| 7 | `pg_blocking_pids` nos pontos de espera | `CN1-6-K1/24_B_wait_observations.txt` (`bloqueador={35464}`), `CN1-6-K8B-CORRECTION-04/23_wait_observations.txt` (`bloqueador={33516}`) e os snapshots de espera (Q2) | registrado |

Os 7 componentes estão registrados no repositório. Os runners `.ps1` não fazem parte do requisito literal ("script" está coberto pelos scripts SQL versionados e pelo instrumento pinado); seguem fora do repositório, pinados por md5, como já registrado em `evidence/CN1-2026-10-02/RELATORIO-EVIDENCIAS.md` §2. **P14(e) = CLOSED.**

## 7. Integridade

Exatamente 2 chamadas LIVE (o registro do cliente tem 2 `execute_sql` desde 2026-10-04, ambas no projeto `qjfutqujxrbzgrtkpgkg`); só SELECT; zero escrita, zero DDL, zero `SET`/`set_config`, zero `PREPARE`/`TEMP`, zero EXPLAIN/ANALYZE, zero retry. Repositório inalterado durante a execução (HEAD `b95f57e…`, `git status --short` vazio).

## 8. Auditoria independente

**AUDIT PASS** — L3 PASS; P14A `PASS_EXACT`; 31/31 EXACT; zero EOL_ONLY, RENDER_ONLY, DIVERGENT, MISSING e EXTRA; `agg_raw` e `agg_lf` LIVE = CN1; contexto LIVE = CN1; SQL submetido byte-idêntico ao instrumento do CN-1.

Adjudicações:

- **P14(a) CLOSED** (P14(c) já CLOSED);
- **D4 CLOSED** (P14(a) + P14(c));
- **D1 / K1 CLOSED** — contratualmente aceito, sem reexecução;
- **D2 / K2 CLOSED** — contratualmente aceito, sem reexecução;
- **D3 / K8b CLOSED** — contratualmente aceito, sem reexecução. O RESULT bruto STOP por V5 continua preservado; V5 é falso positivo adjudicado mecanicamente; a execução comportamental é PASS;
- **E2 CLOSED** (K2 executado + D4 CLOSED);
- **P14(e) CLOSED** por §6.

E1 é avaliado na matriz de `EXECUTION-BATCHES.md`, não aqui.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-10-04).** Registro da execução LIVE `BATCH12-P14A-LIVE-CAPTURE-EXECUTION-01` (2 chamadas: L3 PASS; P14A `PASS_EXACT`, 31/31 EXACT contra o CN-1) e do fechamento `BATCH12-P14A-P14E-D4-E1-INDEPENDENT-CLOSEOUT-01` (auditoria independente PASS; P14(a), P14(e), D1–D4 e E2 CLOSED); evidência preservada em `evidence/P14A-LIVE-CAPTURE-2026-10-04/`. |
