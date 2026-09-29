# B-5X — Adjudicação documental de `READY_DEF = C3` e encerramento de STOP-5 / STOP-7

| Campo | Valor |
|---|---|
| **Mandato** | `BATCH12-B5X-E15P-C3-ADJUDICATION-DOCUMENTATION-01` (2026-09-28). Autorização de Fabrício para a adjudicação documental e a preparação do encerramento. |
| **Baseline** | HEAD `26a3cdb913b27a73c812d7f73ce081d45ce267e1`. |
| **Natureza** | **Somente documental.** Nenhum SQL, nenhuma alteração de lógica SQL ou do gerador, nenhuma execução de E15, nenhum `git add/commit/push`. FREEZE ATIVO; UNFREEZE não autorizado. |
| **Estado** | **AUDITORIA INDEPENDENTE PASS** (adjudicação documental + `…-CORRECTION-01`; fechamento editorial em `BATCH12-B5X-C3-ADJUDICATION-CLOSEOUT-01`). Closeout documental concluído; STOP-5/STOP-7 encerrados exclusivamente no plano documental. |

## 1. Decisão

**`READY_DEF = C3`** — decisão de Fabrício, registrada documentalmente em 2026-09-28, com base na evidência homologada por auditoria independente (§3).

C3 é o **seletor histórico de 2026-09-19** que originou a classificação READY 365/63 (recuperado verbatim do registro LIVE de 02:04:20Z; ver o comentário B-5X de `tools/b12gen/l13.py`): complemento da lista FINISH literal (28 códigos) ∖ `SET_LOGO%` em EX7–EX16 ∖ `SET_LOGO%` fora de DP1/SWSH9/SVP ∖ `PROMO_STAMPED`, sem escopo de Game (exige `type_code_dup = 0`).

Definição exata, tal como executada no LIVE — trechos literais de `2830H_E15P_measure_section5.sql` (blob `3bf6245b…`, md5 `f9fc6d81cd2c6272a04079368a46a49d`):

Linhas 67–96 (md5 do trecho, com LF final: `de364a24d7b6f84a45440a9d06d018d9`):

```sql
d5_finish(code) AS (
    VALUES ('STANDARD'),
           ('HOLO'),
           ('COSMOS_HOLO'),
           ('REVERSE_HOLO'),
           ('ENERGY_REVERSE'),
           ('POKE_BALL_REVERSE'),
           ('LOVE_BALL_REVERSE'),
           ('FRIEND_BALL_REVERSE'),
           ('QUICK_BALL_REVERSE'),
           ('DUSK_BALL_REVERSE'),
           ('ROCKET_REVERSE'),
           ('MASTER_BALL_REVERSE'),
           ('GOLD_HOLO'),
           ('TINSEL_HOLO'),
           ('TINSEL_REVERSE'),
           ('CRACKED_ICE_HOLO'),
           ('GALAXY_HOLO'),
           ('RAINBOW_HOLO'),
           ('METAL'),
           ('METAL_GOLD'),
           ('LENTICULAR'),
           ('COSMOS_REVERSE'),
           ('MASTER_BALL_PATTERN'),
           ('POKE_BALL_PATTERN'),
           ('MASTER_BALL_HOLO'),
           ('SNOWFLAKE_COSMOS_HOLO'),
           ('STANDARDS_SNOWFLAKE'),
           ('SHOWFLAKE_HOLO')
),
```

Linhas 123–133 (md5 do trecho, com LF final: `e629762169fbe070e7d06fc2e87598b1`):

```sql
d5_c3 AS (
    SELECT cv.id, cv.variant_type_id, c.card_set_id
      FROM public.card_variant cv
      JOIN public.card_variant_type vt ON vt.id = cv.variant_type_id
      JOIN public.card c  ON c.id  = cv.card_id
      JOIN public.card_set cs ON cs.id = c.card_set_id
     WHERE vt.code NOT IN (SELECT code FROM d5_finish)
       AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code ~ '^EX(7|8|9|10|11|12|13|14|15|16)$')
       AND NOT (vt.code LIKE 'SET_LOGO%' AND cs.code NOT IN ('DP1','SWSH9','SVP'))
       AND vt.code <> 'PROMO_STAMPED'
),
```

C0, C1 e C2 permanecem como **contraprovas** (divergem da impressão digital no LIVE) e não são descartadas do instrumento.

## 2. Decisão documental × aplicação operacional

| Item | Estado após este registro |
|---|---|
| Decisão `READY_DEF = C3` | **registrada** (este documento) |
| `tools/b12gen/l13.py` (`READY_DEF = None`, md5 `2403b6ee…`) | **inalterado.** Fixar `READY_DEF = 'c3'` no gerador, regenerar os artefatos e reexecutar as provas estáticas (R-21/R-18 ao estado "adjudicado") é **aplicação operacional**, fora deste mandato. |
| `2830H_E15_section5_legacy_hold.sql` (md5 `55521eaf…`) | **inalterado; continua fail-closed** (PREFLIGHT `H283F` enquanto o gerador tiver `READY_DEF = None`). |
| `2830H_E15P_measure_section5.sql` executado (md5 `f9fc6d81…`) | **registro histórico imutável.** Resultado permanece `gate_pass = false`, `d_5x_ready_def = null`, `g_5x_ready_adjudicated = false`, `g_5x_adjudicated_candidate_ok = false`. O cabeçalho do arquivo ("C3 … STOP-7; não adjudicado") descreve o estado no momento da execução e **não é reescrito**. Nenhum gate histórico é alterado. |
| Pendência 5.3/5.7 (tautologias) | **aberta** — reescrever antes de qualquer execução do E15 (readiness final). |
| Cinco testes do E15 (5.1, 5.2, 5.3, 5.6, 5.7) | **pendentes**; não executados. |
| R4 (2831 sem filtro de tipo; dependência da 2213) | **aberta**, fora deste escopo. |

## 3. Evidência (sequência S2–S6, LIVE `qjfutqujxrbzgrtkpgkg`, 2026-09-28)

| Passo | Instrumento submetido (md5 / bytes) | Resultado | Auditoria |
|---|---|---|---|
| S2 L3 | runbook §3.2, `b7bc3700…` / 1.526 | `locks_on_scope = []`; `client backend` só `idle` | PASS |
| S3A EXPLAIN A | `EXPLAIN (COSTS ON, FORMAT TEXT)` + corpo DERIV-5X `3fdddf53…`, `3296a032…` / 17.154 | plano 789 linhas; 2211/2192 em `d5_c2` materializado uma vez; sem risco material de forma | PASS |
| S4 COSTPROBE B | `17945f20…` / 1.173 (corpo `69fad66d…`) | `d5_ev_rows` 23.166; `c2_2211_calls` 23.166 (projetadas, não executadas); `d5_ev_card_sets` 128 | PASS |
| S5 E15P C | E15P versionado `f9fc6d81…` / 25.601 | ver §3.1 | homologado |
| S6 L3 final | `b7bc3700…` / 1.526 | `locks_on_scope = []`; 5 `client backend` `idle`, sem transação; backend do S5 ausente | PASS |

### 3.1 S5 — resultado (`checked_at` `2026-09-28T23:16:15.283825+00:00`)

- Gates `true`: `g_game_source_one`, `g_5x_constants_measured`, `g_5x_unique_candidate_equals_a`, `g_scope_unique`, `g_5x_type_code_unique`, `g_pricing_tables`. Gates `false`: só `g_5x_ready_adjudicated` e `g_5x_adjudicated_candidate_ok` (falsos por construção). Nenhum nulo. `gate_pass = false` (diagnóstico).
- `d_5x_candidate_ok = {c0: false, c1: false, c2: false, c3: true}` — **C3 é o único candidato conforme**.
- C3: estrutural 365, sem condição 285, condicionado 80; STAFF_HOLO 40, SET_LOGO_REVERSE 40; `plan_x_hold` 0, `plan_x_pricing` 0.
- Impressão digital C3: 63 tipos, `named_bad` 0, WORLDS/ASIA 21/21, avulsos 19/24, `single_non1` 5, SET_LOGO SVP 38 / DP1 2 / SLS DP1 4.
- Constantes: HOLD 107; lineage 23.955 / 1.129; `type_code_dup` 0.
- `d_5x_c3_by_type`: 63 códigos, 365 variantes, **zero divergências** contra (A) o esperado usado no S5 e (B) o esperado recomputado só das respostas LIVE originais de 2026-09-19 (01:27:53Z e 01:37:39Z).

### 3.2 Pacote de evidências (byte a byte, homologado)

Diretório `evidence/B5X-E15P-2026-09-28/` — cópia integral do pacote `outputs/HANDOFF-B5X-E15P/` auditado; `md5sum` idêntico arquivo a arquivo.

| Arquivo | MD5 |
|---|---|
| `RELATORIO-EVIDENCIAS.md` | `b9eb28194a1848369a32cf5067e8c09f` |
| `S5/raw_response.txt` | `6cee998c129dfa0bdd285e90718930a5` |
| `S5/e15p_precheck.json` (derivado do bruto) | `4f5fccc86ad59815d3a8e81c3990aa95` |
| `S5/census_c3_expected_19-09.json` | `24c18f9674405ea072633e31f495407b` |
| `S5/statement_submitted.sql` (= E15P versionado) | `f9fc6d81cd2c6272a04079368a46a49d` |
| `S6/raw_response.txt` | `55a9031dab5c06ce636b97aeed30b48d` |
| `S6/statement_submitted.sql` (= runbook §3.2) | `b7bc3700aeef278f6a79bd30e6a8d229` |
| `G11B/G11B-MEASURE.sql` | `f0ec78538f63305d10e120deabf875a4` |
| `census_19-09_original/census_raw_response_2026-09-19T01-27-53Z.txt` | `cf27772b9e71b76c1c60d191b2291907` |
| `census_19-09_original/census_query_2026-09-19T01-27-48Z.sql` | `fa64ed9f39173e7a6eb24451a750be04` |
| `census_19-09_original/setlogo_by_set_raw_response_2026-09-19T01-37-39Z.txt` | `c6b03190e22abccbd34a6a2f834b15d1` |
| `census_19-09_original/setlogo_by_set_query_2026-09-19T01-37Z.sql` | `7991765d6dc172284ea2a4b8630fcd40` |
| `c3_expected_from_raw_19-09.json` | `a68bcba326063409d5578aba13f05e41` |

Os `.sql` deste diretório são **evidência** (textos submetidos), não artefatos executáveis do harness. Os arquivos brutos de S2, S3A e S4 permanecem nos relatórios de execução da sessão e não integram este pacote.

## 4. Encerramento de STOP-5 e STOP-7

| STOP | Objeto | Critério de encerramento (readiness E15P §5) | Prova | Estado |
|---|---|---|---|---|
| **STOP-5** | split de Pricing do READY (285/80) | uma única saída do E15P em EVIDÊNCIA ADJUDICÁVEL com, no mesmo snapshot, `g_pricing_tables = true`, `c3_structural` 365, `c3_unconditioned` 285, `c3_conditioned` 80, STAFF_HOLO 40, SET_LOGO_REVERSE 40 e HOLD 107 | S5 §3.1 — todos presentes no mesmo `checked_at` | **ENCERRADO (documental)**, com as ressalvas do §5 |
| **STOP-7** | decisão de `READY_DEF` | `g_5x_unique_candidate_equals_a = true`; `d_5x_candidate_ok` só c3; `d_5x_c3_by_type` = censo de 19/09 | S5 §3.1 + comparação 63/63 homologada | **ENCERRADO (documental)** — `READY_DEF = C3` decidido; aplicação operacional pendente (§2) |

`c3_plan_x_hold` e `c3_plan_x_pricing` **não** contam como prova (zero por construção; pendência 5.3/5.7).

## 5. Ressalvas (preservadas)

1. **Canal:** S3A, S4 e S5 foram submetidos pelo MCP `execute_sql` **sem o invólucro psql** (sem `BEGIN READ ONLY`, `SET LOCAL`, `lock_timeout` local e `ROLLBACK`). A sessão do S5 registrou `lock_timeout = 0`. Não há equivalência integral com os arquivos psql originais.
2. **Tempo:** não houve medição direta de tempo no LIVE; o custo real do c2 (23.166 chamadas da 2211 e da 2192) não foi medido.
3. **Independência do esperado:** a lista FINISH e as regras de exclusão SET_LOGO vêm do texto do seletor histórico; só as contagens por código vêm das respostas LIVE originais de 19/09.
4. **Representação:** 3 tipos com 0 variantes em 19/09 (`MASTER_BALL_LEAGUE_COSMOS_HOLO`, `POKEMON_CENTER_EXCLUSIVE`, `POKEMON_DAY_COSMOS_HOLO`) não aparecem em `d_5x_c3_by_type` (`GROUP BY`); aceito pela auditoria como diferença de representação.
5. **`e15p_precheck.json`** é extração reformatada; o original é `S5/raw_response.txt`.

## 6. Pendências que este registro não resolve

- Aplicação operacional de `READY_DEF = 'c3'` no gerador + regeneração + provas estáticas.
- Reescrita de 5.3/5.7 antes de qualquer E15.
- Readiness e execução do E15 (cinco testes), sob mandato próprio.
- R4 (2831/2213). FREEZE ativo; UNFREEZE não autorizado.

## Revision History

| Versão | Descrição |
|---|---|
| 1.0 | **Criação (2026-09-28, `BATCH12-B5X-E15P-C3-ADJUDICATION-DOCUMENTATION-01`).** Registro documental de `READY_DEF = C3` e do encerramento de STOP-5/STOP-7 com base em S2–S6 homologados; pacote de evidências versionado em `evidence/B5X-E15P-2026-09-28/`. Nenhum SQL, nenhuma alteração de lógica. Pendente de auditoria independente. |
| 1.1 | **Fechamento editorial (2026-09-28, `BATCH12-B5X-C3-ADJUDICATION-CLOSEOUT-01`).** Auditoria independente PASS da adjudicação documental e da `BATCH12-B5X-C3-ADJUDICATION-DOCUMENTATION-CORRECTION-01` (linha B-5X do `B12-INTEGRATED-AUDIT.md` com a evidência S5 de C0/C1/C2; modo `100644` confirmado). Só o campo Estado mudou; decisão, provas, hashes e os 13 arquivos de evidência inalterados. |
