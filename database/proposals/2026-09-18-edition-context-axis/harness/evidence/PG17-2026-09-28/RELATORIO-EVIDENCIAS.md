# Evidência PG17 — rodada de 2026-09-28 (réplica isolada: Parity, P9B, E12, E13)

| Campo | Valor |
|---|---|
| Objetivo | Preservar no repositório a evidência primária mínima da rodada PG17 de 2026-09-28, para que a prova não dependa de `C:\b12-pg17`. |
| Escopo | Só preservação: bytes originais copiados sem alteração. Nenhum SQL, nenhum acesso ao LIVE, nenhum caso reauditado. |
| Data da rodada | 2026-09-28 (horários em UTC) |
| Origem | `C:\b12-pg17` (workspace local). O runner veio de `harness/local-pg17/` (workspace local, não versionado). |
| Ambiente | Container local da imagem `supabase/postgres:17.6.1.147`, image id `sha256:ac581882596ed0e46937ea6dd53a627d09f53e005d7264c2082a7ff7b62eaaca`; PostgreSQL 17.6 (`server_version_num` 170006), igual ao LIVE. |
| Conteúdo | `MANIFEST.md5` (md5, bytes, origem e mtime original de cada arquivo) e `raw/` (50 arquivos, 435.829 bytes). |
| Cópia fria | `C:\b12-pg17\archive\PG17-2026-09-28-EVIDENCE.zip`: 123.593 bytes, md5 `61bf3738718652b2e55613d297c8d23b`, 50 entradas = `raw/` byte a byte. Fora do Git. |
| Estado | **Homologado**: Parity PASS; P9B M1/M2/M3 PASS local; E12 14/14 e E13 11/11 PASS local (25/25). **P9B LOCAL PASS ≠ A2/P9(b) global CLOSED**: o A2/P9(b) da 2830 v7.0 continua OPEN (`../../../EXECUTION-BATCHES.md`, Batch 12). |

## 1. Sequência

Os horários vêm do mtime dos arquivos originais (coluna `source_mtime_utc` do manifesto) e, onde existe, do `checked_at` do banco.

| UTC | Passo | Evidência em `raw/` | Resultado |
|---|---|---|---|
| 17:02:02 (`checked_at` LIVE) | impressão digital do LIVE, lida com `b12_export_ro` | `out/fp_live.json` | `d_fp_core_md5 = 4f035e129221d0647259e9083599035e` |
| 17:56:57 | md5 do SQL montado no container | `out/md5_in_container.txt` | identidade do SQL executado (§4) |
| 18:15:42 | CkRepair (o CkProof anterior, 18:13Z, fica só na origem) | `sql/run/ckrepair.sql`, `ckrepair.sh`, `out/ckrepair.log` | `BEGIN … COMMIT` |
| 18:21:53 | verificação do CkRepair | `out/ck_repair.json` | `pass: true`, 2 constraints conformes (`repaired: 0`) |
| 18:22:03.93 (`checked_at`) | Parity | `out/fp_local.json`, `out/parity_result.json`, `out/deps_parity.json`, `sql/run/parity.sh`, `sql/parity_fingerprint.sql` | **PASS** (§2) |
| 18:23:58 | P9B M1/M2/M3 | `out/p9b.txt`, `out/p9b_result.json`, `sql/P9B_M1_M3.sql`, `sql/run/p9b.sh` | **PASS local** (§2) |
| 18:24:50.23 → 18:24:51.65 (`checked_at`) | E12: E00 → E12P → envelope → E99 | `out/E12_*`, `sql/run/*E12*` | **14/14** (§3) |
| 18:24:51.82 → 18:24:53.29 (`checked_at`) | E13: E00 → E13P → envelope → E99 → E98 | `out/E13_*`, `sql/run/*E13*` | **11/11** (§3) |
| 18:24:53 | consolidação | `out/envelopes_result.json` | E12 e E13 com `pass: true` |

A ordem Parity → P9B → E12/E13 também está imposta pelo runner (`raw/runner/B12-LOCAL-PG17.ps1`): o P9B falha se `parity_result.json` não estiver PASS, e os envelopes falham se `p9b_result.json` não estiver PASS. O runner preservado é a versão do workspace com mtime 18:06Z, anterior à rodada. O vínculo com a execução é por mtime e conteúdo; o hash do runner não foi registrado no momento da execução.

## 2. Parity e P9B

- **Parity:**
  - gates `P1_pg_version`, `P2_live_no_drift`, `P3_core_identical`, `P4_planner_settings`, `P5_E12P_gate_pass`, `P5_E13P_gate_pass`, `P6_E00_viable`, `P7_no_scoped_restore_error`, `P8_restore_rls_triggers` todos `true`;
  - `diff: []`;
  - `live_md5 = local_md5 = 4f035e129221d0647259e9083599035e`;
  - ambiente de planner igual nos dois lados (jit off, `work_mem` 2184kB, `random_page_cost` 1.1, `shared_buffers` 224MB).
- **P9B:** `M1_VREC_ms = 212.219`, `M2_V1c_ms = 722.642`, `M3_SMREC_ms = 47.715`, `pass: true`, com uma execução de cada.

## 3. E12 e E13 (terminais literais)

```
psql:/work/sql/2830H_E12_section_b_backfill_semantic.sql:733: ERROR:  H2830_ROLLBACK_PASS: envelope=E12_SECAO_B_BACKFILL_SEMANTICO pass=14/14 casos=V1,V2,V3,V4,V5,V6,V7,V8,V9,V10,V11,V12,V13,V14 marker=H2830_6B73C7582B6740B09D704B65E0B31CE3 elapsed_ms=402 u_total=26127 u_op=1642 u_rechecked=1642 u_v1_occ=1092 v1_occ_total=1092 u_v5=24372 u_hist_null=0 u_cancel_vp=415 v7_skip=95
CONTEXT:  PL/pgSQL function inline_code_block line 712 at RAISE
```
```
psql:/work/sql/2830H_E13_section_m_state_machine.sql:981: ERROR:  H2830_ROLLBACK_PASS: envelope=E13_SECAO_M_STATE_MACHINE pass=11/11 casos=SM1,SM2,SM3,SM4,SM5,SM6,SM7,SM8,SM9,SM10,SM11 marker=H2830_A82D47E9C25D4162803E4EDB7DD69C7B elapsed_ms=78 u_rows=26127 u_mut=1642 u_conf=0 u_nr_mut=1642 u_hist_nokey=24485 u_cancel=847
CONTEXT:  PL/pgSQL function inline_code_block line 960 at RAISE
```

Pós-checks:

| Envelope | Precheck | E99 | E98 |
|---|---|---|---|
| E12 | E12P `gate_pass = true` | `gate_pass = true`, `d_diff = []`, `d_canon_diff = []` | — |
| E13 | E13P `gate_pass = true` | `gate_pass = true`, `d_diff = []`, `d_canon_diff = []` | `gate_pass = true` |

Todos os `.err` estão vazios.

## 4. Identidade dos artefatos executados

**SQL canônico versionado** (não duplicado aqui). O md5 de cada um é o registrado em `out/md5_in_container.txt` e é igual ao arquivo em `harness/`:

| Artefato executado | Caminho canônico | md5 |
|---|---|---|
| E00 | `harness/2830H_E00_precheck_inventory.sql` | `45b6c35cca849ffbf49d22ec18e8283c` |
| E12P | `harness/2830H_E12P_precheck_section_b.sql` | `79a647ec2f03e3a94f09f2e2e07f5c9a` |
| E12 | `harness/2830H_E12_section_b_backfill_semantic.sql` | `232b857087aa63732a7be5ade55108f8` |
| E13P | `harness/2830H_E13P_precheck_section_m.sql` | `50b5c1227b69f59f417b68bd42eb0a6f` |
| E13 | `harness/2830H_E13_section_m_state_machine.sql` | `5907e85df7fbe9545e97c4584b446827` |
| E98 | `harness/2830H_E98_postcheck_extended_residue.sql` | `094d1bc4db7d6abee6f91f6a236ab708` |
| E99 (base) | `harness/2830H_E99_postcheck_residue.sql` | `f0b91183a8649b990b080637dd56e74b` |

**SQL executado sem cópia canônica** (preservado em `raw/sql/`):

| Arquivo | md5 | Papel |
|---|---|---|
| `L_E00_precheck_inventory.sql` | `8539badcf7a637e59948858538dfcca7` | E00 local, usado antes de E12 e E13 |
| `L_E99_postcheck_residue.sql` | `4fbb939b2b805ef3007f83afda1cbbe4` | base local do E99 |
| `run/E12_E99.sql` = `run/E13_E99.sql` | `928109cb5810a9250c302e742180c210` | E99 preenchido com os marcadores da rodada |
| `run/E13_E98.sql` | `f92293dffc1406bbebe39e1e41cdb895` | E98 preenchido |
| `P9B_M1_M3.sql` | `9da8bd45ce76adc1bcbca0922ccea8f3` | P9B executado; não é o `2830H_P9B_isolated_timing.sql` do repositório |
| `parity_fingerprint.sql` | `bc11f919941e449381a1000d5730c217` | impressão digital da Parity, a mesma consulta no LIVE e no local |

Os scripts de chamada (`raw/sql/run/*.sh`) registram o comando exato de cada passo. A relação completa entre arquivos, bytes e mtimes está em `MANIFEST.md5`.

## 5. Ressalvas ambientais (homologadas, sem conversão em PASS)

- **Gate do E00 local:** `g_evt_all_adjudicated = false`, admitido como limitação da réplica (`parity_result.json`, `e00_env_allowed`; `envelopes_result.json`, `e00_false_gates`).
- **Tabela fora do export:** `public.catalog_admin_action_log` não fez parte do export de 22 tabelas. Ficou `NOT_EXECUTED_LOCAL` (`envelopes_result.json`, `not_executed_local`).
- **Erros ambientais de restore:** listados em `out/load_schema_errors.txt`; o `parity_result.json` os registra sem bloqueio (`restore_errors_blocking = []`).
- **Versões adaptadas:** E00, E99 e P9B rodaram em versões locais (§4).
- **Execução única:** uma execução de cada passo, sem cache frio controlado. Por isso esta evidência **não** satisfaz o P9(b) literal da 2830 v7.0.

## 6. Role `b12_export_ro` (proveniência)

- O role **já existia no LIVE** antes desta rodada, conforme o estado LIVE observado no cabeçalho do script de operação do role (workspace local, `B12-EXPORT-RO-ROLE.sql`, md5 `6c9667d9ba706c60564bd4e60dc55e54`). Não foi criado por esta preservação.
- Na rodada, foi usado só em leitura para capturar a impressão digital do LIVE (`fp_live.json`) e os dados da réplica.
- **Estado final do role — registro histórico, não demonstrado por este pacote.** O estado final do role no LIVE (`NOLOGIN`, sem password, sem grants nem políticas residuais, zero sessões) é um registro histórico previamente homologado, mas **não é demonstrado pelos artefatos deste pacote**. A saída original dessa verificação final não foi encontrada nos artefatos locais inventariados (`C:\b12-pg17`, `harness/local-pg17/`). Por isso não foi preservada e nenhuma prova nova foi produzida (sem acesso ao LIVE).
- **Não confundir com o reset SCRAM local.** O único registro local de reset de role (`out/scram_local_reset.log`, 13:11Z) refere-se ao container local e não ao LIVE. Por isso não serve como prova desse estado e não foi preservado.
- **Indícios indiretos, não conclusivos.** São posteriores (2026-10-01) e não substituem a prova: o E00 LIVE registra `db_role_setting_rows = 10`, coerente com o role existente; os L3 do E15 não mostram sessão desse role.
- **O que este pacote prova sobre o role:** apenas o uso em leitura na rodada (`fp_live.json`, `checked_at` 17:02:02Z).

## 7. Fora deste pacote (não versionar)

`secrets/`, verificadores SCRAM, `container_inspect.json` (contém a senha do container local), `dump/` (dados e schema do LIVE), bancos e imagens locais, `__pycache__`, iterações do runner e sondas posteriores (`harness/local-pg17/`).
