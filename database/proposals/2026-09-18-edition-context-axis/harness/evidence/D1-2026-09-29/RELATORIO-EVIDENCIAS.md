# D1 — Pacote de evidências da medição LIVE de 2026-09-29

| | |
|---|---|
| Mandato de execução | `BATCH12-E15-D1-LIVE-EXECUTION-01` |
| Mandato de encerramento | `BATCH12-E15-D1-EVIDENCE-CLOSEOUT-01` |
| Baseline | `c74c55ae7a140539a3db64cf1be7a7efdabc0cbd` |
| Projeto LIVE | `qjfutqujxrbzgrtkpgkg` |
| Canal | MCP `execute_sql`, sem invólucro psql, 1 statement por chamada; tempo não medido |
| Resultado | **D1 `gate_pass = true`, 16/16 gates `true`**. Uma única execução, sem erro, sem `57014`, sem bloqueio de integração |
| Estado | FREEZE ativo · E15 bloqueado (`E15_BLOCKED_53_57 = True`) · 130/135 preservado · 5.3/5.7 não implementados · digests **não** fixados no gerador |
| Pacote | **Imutável.** Nenhum arquivo deste diretório é reconstruído, reformatado ou corrigido |

## 1. Manifesto (md5 e bytes individuais)

| # | Arquivo | Bytes | md5 | Conteúdo |
|---|---|---|---|---|
| 1 | `S1/statement_submitted.sql` | 1.526 | `b7bc3700aeef278f6a79bd30e6a8d229` | L3 inicial (runbook §3.2; idêntico a `B5X-E15P-2026-09-28/S6/statement_submitted.sql`) |
| 2 | `S1/raw_response.txt` | 2.693 | `8a44be69fca451cec6777388453e19cc` | resposta MCP do S1 |
| 3 | `S2/statement_submitted.sql` | 16.728 | `efb3217e4b5ce9d227f412739c3e1b18` | D1 submetido. Gravado **antes** da submissão e conferido por `cmp` contra `instrument/D1-ID-IDENTITY.sql` |
| 4 | `S2/raw_response.txt` | 3.275 | `7fed42bb0b1dcdd53552d37fac7d3336` | resposta MCP do D1 |
| 5 | `S3/statement_submitted.sql` | 1.526 | `b7bc3700aeef278f6a79bd30e6a8d229` | L3 final (mesmo texto do S1) |
| 6 | `S3/raw_response.txt` | 2.695 | `2151a55cbaf3f7a6ca8e0150ce659e68` | resposta MCP do S3 |
| 7 | `instrument/D1-ID-IDENTITY.sql` | 16.728 | `efb3217e4b5ce9d227f412739c3e1b18` | instrumento (= arquivo 3) |
| 8 | `instrument/gen_d1.py` | 13.700 | `2de624c42bfffcb3f83d8657b26ade5c` | gerador; reproduz o arquivo 7 byte a byte a partir de `../B5X-E15P-2026-09-28/` |
| 9 | `instrument/d1_model.py` | 11.688 | `d14cfc1deb9b2ed37c55b029c640022b` | modelo lógico offline; todas as asserções PASS no S0 |
| 10 | `instrument/D1-READINESS.md` | 10.450 | `75f5e2b7a9a8213216b91466224bcbbc` | readiness auditada (protocolo, STOP, contraprovas CP-1…CP-7) |

**Classificação dos arquivos SQL (evidência histórica, não instrumento executável).**

- Os quatro arquivos SQL deste pacote (1, 3, 5 e 7) são **cópias históricas**:
  - `S1/`, `S2/` e `S3/statement_submitted.sql` são os textos submetidos ao LIVE em 2026-09-29;
  - `instrument/D1-ID-IDENTITY.sql` é o instrumento preparado.
- A presença deles neste pacote **não autoriza nova execução**. Qualquer repetição, total ou parcial, depende de mandato específico.
- Os cabeçalhos preservados, como "PREPARADO — NÃO EXECUTADO" no instrumento, retratam o estado anterior à execução. São mantidos byte a byte e não descrevem o estado atual.

**Natureza das respostas brutas.** Os arquivos `raw_response.txt` (2, 4, 6) são a transcrição literal do envelope `{"result": …}` retornado pela ferramenta MCP. O canal não grava a resposta em arquivo por conta própria. A transcrição foi feita na mesma sessão da execução e não sofreu nenhuma edição posterior.

## 2. Cronologia (UTC)

| Passo | Ação | `checked_at` | Critério | Resultado |
|---|---|---|---|---|
| S0 | verificação local | — | HEAD, md5 do instrumento, reprodução pelo gerador, modelo PASS, E15P/E15 inalterados, `E15_BLOCKED_53_57 = True` | conforme |
| S1 | L3 | 2026-09-29T01:41:11.89668Z | runbook §4.2 | 5 `client backend`, todas `idle`, 0 ativas ou em transação; `locks_on_scope = []` → conforme |
| S2 | D1 (única submissão) | 2026-09-29T01:43:25.72114Z | readiness §6 | `gate_pass = true`; nenhum gate `false`/NULL → conforme |
| S3 | L3 | 2026-09-29T01:43:54.213756Z | runbook §4.2 | 5 `client backend` `idle`; `locks_on_scope = []`; backend do D1 (3679965) ausente → conforme |

Sessão do D1: `snapshot` `451606:451606:` · `backend_pid` 3679965 · `current_user` postgres · `server_version_num` 170006 · `transaction_read_only` `off`. Esse último valor é registrado e não é gate (readiness §6). O texto é um SELECT único, sem DML/DDL.

## 3. Gates (S2)

Os 16 gates retornaram `true`:

- `g_join_complete`, `g_type_code_unique`, `g_universe_19_09`, `g_uraw_1027`;
- `g_partition_counts`, `g_partition_exact`;
- `g_ready_by_type_19_09`, `g_hold_by_type_set_19_09`, `g_nc_by_type_set_19_09`;
- `g_h6_types`, `g_conditioned_80_40_40`, `g_plan_contract_285`;
- `g_plan_x_pscid_zero`, `g_plan_x_psvm_zero`, `g_plan_equivalence`, `g_plan_x_hold_zero`.

## 4. Identidade D1 capturada

| Conjunto | n | md5 (`string_agg(id::text, ',' ORDER BY id)`) |
|---|---|---|
| HOLD | 107 | `0e56dfffc8cc9ef09b66d4f5fe958d91` |
| PLAN | 285 | `a53343fa38bbbe6f45fea7a4dba4bbdb` |
| READY | 365 | `ee0e4c54336179431797e602a358bb0e` |
| CONDITIONED | 80 | `288f9b45b8e95bfb7123fe9e8693d3a3` |

O plano derivado das tabelas de Pricing tem o mesmo md5 do plano por contrato (`a53343fa…`), com diferença simétrica 0.

**Captura D1 × identidade histórica de 19/09.**

- Estes quatro digests são a **primeira** identidade por id registrada. Não existe digest de 19/09.
- A medição prova que, em 2026-09-29, o LIVE é **indistinguível de 19/09 por contagem e composição** (§5). Ela **não** prova que os UUIDs de hoje são os mesmos de 19/09.
- Os digests congelam a participação dos UUIDs nos conjuntos, não os atributos individuais de cada variante (readiness §5, item 3).
- Fixar esses valores como constantes (53-d) depende de mandato posterior. Uma segunda medição sob FREEZE, se autorizada, deve reproduzi-los exatamente.

## 5. Confronto com 19/09

| Item | 19/09 | 29/09 | |
|---|---|---|---|
| `card_variant` total / FINISH | 24.893 / 23.866 | 24.893 / 23.866 (`cv_joined` 24.893) | = |
| U_raw = READY + HOLD + NC | 1.027 = 365 + 107 + 555 | idem; `n_bad_partition` 0 | = |
| READY por tipo (63) | `c3_expected_from_raw_19-09.json` | `ready_bt_diff` 0 | = |
| HOLD por tipo@Set (30 chaves) | `setlogo_by_set` + censo | `hold_bk_diff` 0; `d1_hold_by_key` = mapa de 19/09 (30 chaves, soma 107) | = |
| NC por tipo@Set (12 chaves) | idem | `nc_bk_diff` 0 | = |
| Pricing nos READY (H6) | STAFF_HOLO pscid 17 / psvm 1; SET_LOGO_REVERSE pscid 1 / psvm 0 | STAFF_HOLO 17 / 1; SET_LOGO_REVERSE 1 / `null` (sem linha) | = (`h6_type_diff` 0) |
| Condicionados | 80 = 40 + 40 | 80 = 40 + 40 | = |
| Plano | 285 | contrato 285 = derivado 285; `plan_x_pscid` 0, `plan_x_psvm` 0, `plan_x_hold` 0 | = |

Nenhuma divergência.

## 6. D2 — composição do HOLD por tipo

| Tipo | HOLD-MANIFEST H1 | LIVE 19/09 | **LIVE 29/09 (D1)** |
|---|---|---|---|
| PROMO_STAMPED | 33 | 33 | 33 |
| SET_LOGO_REVERSE | **55** | 59 | **59** |
| SET_LOGO_STANDARDS | **15** | 11 | **11** |
| SET_LOGO_COSMOS_HOLO | 3 | 3 | 3 |
| SET_LOGO_STAFF_HOLO | 1 | 1 | 1 |
| Total | 107 | 107 | 107 |

A D2 (referência do HOLD = SLS 11 / SLR 59) fica **confirmada** por uma segunda medição LIVE independente.

A divergência com o H1 (`HOLD-MANIFEST.md`, linhas 10–11: 15 / 55) continua **registrada e não corrigida**. `HOLD-MANIFEST.md` não foi alterado neste ciclo. A correção documental do H1 depende de um mandato próprio.

## 7. Integridade do repositório (no encerramento)

| Artefato | Estado |
|---|---|
| HEAD | `c74c55ae…`, sem commit novo |
| E15P `2830H_E15P_measure_section5.sql` | `f9fc6d81cd2c6272a04079368a46a49d` (inalterado) |
| E15 `2830H_E15_section5_legacy_hold.sql` | `7a2da69c4ded7556063fbc4e0c09a2d1` (inalterado) |
| Gerador `tools/b12gen/*`, `B12-INTEGRATED-MANIFEST.json`, `HOLD-MANIFEST.md`, contratos 2830/2831 | sem diff contra o HEAD |
| `E15_BLOCKED_53_57` | `True` (`tools/b12gen/l13.py:55`) |
