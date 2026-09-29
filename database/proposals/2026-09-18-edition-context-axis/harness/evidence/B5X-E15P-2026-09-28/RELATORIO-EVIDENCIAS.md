# B-5X / E15P — Pacote de evidências para auditoria independente

Mandato: `BATCH12-B5X-E15P-ADJUDICATION-EVIDENCE-HANDOFF-01` · baseline `26a3cdb913b27a73c812d7f73ce081d45ce267e1` · FREEZE ativo · `READY_DEF=None`.

Relatório de evidência apenas. Não adjudica `READY_DEF`, não encerra STOP-5/STOP-7, nenhum SQL executado nesta rodada, nenhum arquivo versionado alterado.

## 1. Arquivos

| # | Arquivo (relativo a esta pasta) | Bytes | MD5 | Natureza |
|---|---|---:|---|---|
| 1 | `S5/raw_response.txt` | 10902 | `6cee998c129dfa0bdd285e90718930a5` | resposta MCP original do S5 (com invólucro do canal) |
| 2 | `S5/e15p_precheck.json` | 11103 | `4f5fccc86ad59815d3a8e81c3990aa95` | extração do objeto `e15p_precheck` de `raw_response.txt` (reformatado, indentado; derivado, não original) |
| 3 | `S5/census_c3_expected_19-09.json` | 4183 | `24c18f9674405ea072633e31f495407b` | esperado por código usado no S5 (derivado de G11B + `d5_map`) |
| 4 | `S5/statement_submitted.sql` | 25601 | `f9fc6d81cd2c6272a04079368a46a49d` | texto submetido no S5 (= E15P versionado) |
| 5 | `G11B/G11B-MEASURE.sql` | 22521 | `f0ec78538f63305d10e120deabf875a4` | instrumento G11B com o censo 19/09 embutido (fonte do esperado anterior) |
| 6 | `census_19-09_original/census_raw_response_2026-09-19T01-27-53Z.txt` | 13363 | `cf27772b9e71b76c1c60d191b2291907` | resposta MCP original do censo LIVE de 19/09 (registro de sessão) |
| 7 | `census_19-09_original/census_query_2026-09-19T01-27-48Z.sql` | 750 | `fa64ed9f39173e7a6eb24451a750be04` | query submetida no censo de 19/09 |
| 8 | `census_19-09_original/setlogo_by_set_raw_response_2026-09-19T01-37-39Z.txt` | 1337 | `c6b03190e22abccbd34a6a2f834b15d1` | resposta MCP original do detalhe SET_LOGO por Set, 19/09 |
| 9 | `census_19-09_original/setlogo_by_set_query_2026-09-19T01-37Z.sql` | 767 | `7991765d6dc172284ea2a4b8630fcd40` | query correspondente |
| 10 | `c3_expected_from_raw_19-09.json` | 2114 | `a68bcba326063409d5578aba13f05e41` | esperado recomputado nesta rodada direto das duas respostas originais de 19/09 |
| 11 | `S6/raw_response.txt` | 2695 | `55a9031dab5c06ce636b97aeed30b48d` | resposta MCP original do S6 (L3 final) |
| 12 | `S6/statement_submitted.sql` | 1526 | `b7bc3700aeef278f6a79bd30e6a8d229` | texto submetido no S6 |

Os arquivos 1, 3, 4, 11 e 12 são cópias byte a byte (`cmp`) dos originais em `outputs/S5` e `outputs/S6`. Os arquivos 6–9 foram extraídos literalmente do registro da sessão (`tool_use`/`tool_result` de 2026-09-19, projeto `qjfutqujxrbzgrtkpgkg`).

## 2. S5 — identidade e completude

- Texto submetido: md5 `f9fc6d81cd2c6272a04079368a46a49d`, 25601 bytes; igual ao blob `3bf6245b…` do HEAD; parâmetro `query` do registro de sessão idêntico.
- Resposta: JSON válido, 1 linha, objeto `e15p_precheck` completo; `checked_at` `2026-09-28T23:16:15.283825+00:00`; `backend_pid` 3669221; sem erro.
- `e15p_precheck.json` igual ao objeto extraído do bruto: **True**.
- Sessão: `current_user` postgres, `server_version_num` 170006, `lock_timeout` 0, `search_path` "\$user", public, extensions.

## 3. Gates

| Gate | Valor |
|---|---|
| `g_5x_adjudicated_candidate_ok` | false |
| `g_5x_constants_measured` | true |
| `g_5x_ready_adjudicated` | false |
| `g_5x_type_code_unique` | true |
| `g_5x_unique_candidate_equals_a` | true |
| `g_game_source_one` | true |
| `g_pricing_tables` | true |
| `g_scope_unique` | true |
| `gate_pass` | false |

Gates nulos: nenhum. Gates falsos: ['g_5x_ready_adjudicated', 'g_5x_adjudicated_candidate_ok']. `d_5x_ready_def`: null.

## 4. Candidatos C0–C3

`d_5x_candidate_ok`: `{"c0": false, "c1": false, "c2": false, "c3": true}`

| Campo | Referência | C0 | C1 | C2 | C3 | C3 = ref |
|---|---:|---:|---:|---:|---:|---|
| structural | 365 | 21938 | 23166 | 285 | 365 | sim |
| unconditioned | 285 | 12643 | 12858 | 241 | 285 | sim |
| conditioned | 80 | 9295 | 10308 | 44 | 80 | sim |
| cond_staff_holo | 40 | 40 | 40 | 4 | 40 | sim |
| cond_set_logo_reverse | 40 | 185 | 126 | 40 | 40 | sim |
| plan_x_hold | 0 | 15 | 0 | 0 | 0 | sim |
| plan_x_pricing | 0 | 0 | 0 | 0 | 0 | sim |
| fp_n_types | 63 | 85 | 84 | 30 | 63 | sim |
| fp_named_bad | 0 | 2 | 2 | 3 | 0 | sim |
| fp_worlds_types | 21 | 21 | 21 | 0 | 21 | sim |
| fp_worlds_n | 21 | 21 | 21 | 0 | 21 | sim |
| fp_single_types | 19 | 41 | 40 | 9 | 19 | sim |
| fp_single_n | 24 | 20972 | 22270 | 11 | 24 | sim |
| fp_single_non1 | 5 | 23 | 22 | 2 | 5 | sim |
| fp_slr_svp | 38 | 38 | 38 | 38 | 38 | sim |
| fp_slr_dp1 | 2 | 2 | 2 | 2 | 2 | sim |
| fp_sls_dp1 | 4 | 4 | 4 | 4 | 4 | sim |
| cond_by_pscid | — | 9295 | 10308 | 44 | 80 | n/a |
| cond_by_psvm | — | 693 | 694 | 4 | 40 | n/a |

`cond_by_pscid`/`cond_by_psvm` são referências de 19/09 (80/40), não gates.

### 21 campos de referência (constantes + C3)

| Campo | Esperado | Medido | Resultado |
|---|---:|---:|---|
| `hold` | 107 | 107 | conforme |
| `lineage_resulting` | 23955 | 23955 | conforme |
| `lineage_matched` | 1129 | 1129 | conforme |
| `type_code_dup` | 0 | 0 | conforme |
| `c3_structural` | 365 | 365 | conforme |
| `c3_unconditioned` | 285 | 285 | conforme |
| `c3_conditioned` | 80 | 80 | conforme |
| `c3_cond_staff_holo` | 40 | 40 | conforme |
| `c3_cond_set_logo_reverse` | 40 | 40 | conforme |
| `c3_plan_x_hold` | 0 | 0 | conforme |
| `c3_plan_x_pricing` | 0 | 0 | conforme |
| `c3_fp_n_types` | 63 | 63 | conforme |
| `c3_fp_named_bad` | 0 | 0 | conforme |
| `c3_fp_worlds_types` | 21 | 21 | conforme |
| `c3_fp_worlds_n` | 21 | 21 | conforme |
| `c3_fp_single_types` | 19 | 19 | conforme |
| `c3_fp_single_n` | 24 | 24 | conforme |
| `c3_fp_single_non1` | 5 | 5 | conforme |
| `c3_fp_slr_svp` | 38 | 38 | conforme |
| `c3_fp_slr_dp1` | 2 | 2 | conforme |
| `c3_fp_sls_dp1` | 4 | 4 | conforme |

Total: 21 campos; divergências: 0. `lineage_not_hold` = 23166 (informativo; = S4). `g_scope_unique` = true.

## 5. `d_5x_c3_by_type` × censo histórico de 19/09

Duas bases de comparação:

- **(A) Esperado usado no S5** (`S5/census_c3_expected_19-09.json`): grupos nominais de G11B + contagens do censo; SET_LOGO_REVERSE/STANDARDS pelos valores de `d5_map`.
- **(B) Esperado recomputado nesta rodada só a partir das respostas originais de 19/09**: censo 01:27:53Z (97 tipos / 24.893) menos a lista FINISH (28 códigos, texto do seletor histórico) e PROMO_STAMPED; para tipos `SET_LOGO%`, apenas a parcela em DP1/SWSH9/SVP do detalhe por Set de 01:37:39Z.

Resultado (B) bruto: 66 códigos, soma 365; 3 códigos com 0 variantes no censo (`MASTER_BALL_LEAGUE_COSMOS_HOLO`, `POKEMON_CENTER_EXCLUSIVE`, `POKEMON_DAY_COSMOS_HOLO`), ausentes da saída por construção (`GROUP BY` não gera linha zero). Sem esses três: 63 códigos, soma 365.

- S5 × (A): chaves iguais **True**, valores iguais **True**.
- S5 × (B, sem zeros): chaves iguais **True**, valores iguais **True**.

| # | Código | S5 | (A) | (B) | Igual |
|---|---|---:|---:|---:|---|
| 1 | `COSMOS_PROFESSOR_REVERSE` | 16 | 16 | 16 | sim |
| 2 | `COSMOS_REWARDS_HOLO` | 18 | 18 | 18 | sim |
| 3 | `COSMOS_REWARDS_REVERSE` | 17 | 17 | 17 | sim |
| 4 | `COSMO_HOLO_EBGAMES` | 1 | 1 | 1 | sim |
| 5 | `EBGAMES_HOLO` | 8 | 8 | 8 | sim |
| 6 | `EBGAMES_REVERSE` | 2 | 2 | 2 | sim |
| 7 | `GAMESTOP_HOLO` | 9 | 9 | 9 | sim |
| 8 | `GYM_CHALLENGE_HOLO` | 3 | 3 | 3 | sim |
| 9 | `HORIZONS_HOLO` | 1 | 1 | 1 | sim |
| 10 | `INTERNATIONAL_CHAMPIONSHIPS_EUROPE_HOLO` | 1 | 1 | 1 | sim |
| 11 | `INTERNATIONAL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE` | 1 | 1 | 1 | sim |
| 12 | `INTL_CHAMPIONSHIPS_NORTH_AMERICA_REVERSE_STAFF` | 1 | 1 | 1 | sim |
| 13 | `NATIONAL_CHAMPIONSHIPS_REVERSE` | 1 | 1 | 1 | sim |
| 14 | `NATIONAL_CHAMPIONSHIPS_REVERSE_STAFF` | 1 | 1 | 1 | sim |
| 15 | `PLAYER_REWARD_REVERSE` | 1 | 1 | 1 | sim |
| 16 | `POKEDAY_HOLO` | 1 | 1 | 1 | sim |
| 17 | `POKEMON_CENTER_HOLO` | 19 | 19 | 19 | sim |
| 18 | `PRERELEASE_COSMOS_HOLO` | 1 | 1 | 1 | sim |
| 19 | `PRERELEASE_HOLO` | 1 | 1 | 1 | sim |
| 20 | `REWARDS_HOLO` | 30 | 30 | 30 | sim |
| 21 | `SATANDARD_REWARDS` | 51 | 51 | 51 | sim |
| 22 | `SET_LOGO_REVERSE` | 40 | 40 | 40 | sim |
| 23 | `SET_LOGO_STANDARDS` | 4 | 4 | 4 | sim |
| 24 | `STAFF_HOLO` | 40 | 40 | 40 | sim |
| 25 | `STANDARDS_ASIA_2023_2024` | 1 | 1 | 1 | sim |
| 26 | `STANDARDS_GAMESTOP` | 2 | 2 | 2 | sim |
| 27 | `STANDARDS_HORIZONS` | 3 | 3 | 3 | sim |
| 28 | `STANDARDS_LEAGUE` | 4 | 4 | 4 | sim |
| 29 | `STANDARDS_POKEMON_CENTER` | 1 | 1 | 1 | sim |
| 30 | `STANDARDS_POKEMON_TOGETHER` | 2 | 2 | 2 | sim |
| 31 | `STANDARDS_TEACHER_PROGRAM` | 14 | 14 | 14 | sim |
| 32 | `STANDARDS_WORLDS_2023` | 1 | 1 | 1 | sim |
| 33 | `STANDARDS_WORLDS_2023_STAFF` | 1 | 1 | 1 | sim |
| 34 | `STANDARDS_WORLDS_2023_TOP_16` | 1 | 1 | 1 | sim |
| 35 | `STANDARDS_WORLDS_2023_TOP_2` | 1 | 1 | 1 | sim |
| 36 | `STANDARDS_WORLDS_2023_TOP_32` | 1 | 1 | 1 | sim |
| 37 | `STANDARDS_WORLDS_2023_TOP_4` | 1 | 1 | 1 | sim |
| 38 | `STANDARDS_WORLDS_2023_TOP_8` | 1 | 1 | 1 | sim |
| 39 | `STANDARDS_WORLDS_2024_STAFF` | 1 | 1 | 1 | sim |
| 40 | `STANDARDS_WORLDS_2024_TOP_16` | 1 | 1 | 1 | sim |
| 41 | `STANDARDS_WORLDS_2024_TOP_2` | 1 | 1 | 1 | sim |
| 42 | `STANDARDS_WORLDS_2024_TOP_32` | 1 | 1 | 1 | sim |
| 43 | `STANDARDS_WORLDS_2024_TOP_4` | 1 | 1 | 1 | sim |
| 44 | `STANDARDS_WORLDS_2024_TOP_8` | 1 | 1 | 1 | sim |
| 45 | `STANDARDS_WORLDS_2025` | 1 | 1 | 1 | sim |
| 46 | `STANDARDS_WORLDS_2025_STAFF` | 1 | 1 | 1 | sim |
| 47 | `STANDARDS_WORLDS_2025_TOP_16` | 1 | 1 | 1 | sim |
| 48 | `STANDARDS_WORLDS_2025_TOP_2` | 1 | 1 | 1 | sim |
| 49 | `STANDARDS_WORLDS_2025_TOP_32` | 1 | 1 | 1 | sim |
| 50 | `STANDARDS_WORLDS_2025_TOP_4` | 1 | 1 | 1 | sim |
| 51 | `STANDARDS_WORLDS_2026_TOP_8` | 1 | 1 | 1 | sim |
| 52 | `STANDARD_FIRST_MOVIE` | 4 | 4 | 4 | sim |
| 53 | `STANDARD_FIRST_MOVIE_INVERTED` | 4 | 4 | 4 | sim |
| 54 | `STANDARD_GYM_CHALLENGE` | 9 | 9 | 9 | sim |
| 55 | `STANDARD_PIKACHU_WORLD_2000` | 6 | 6 | 6 | sim |
| 56 | `STANDARD_POKEMON_4EVER` | 2 | 2 | 2 | sim |
| 57 | `STANDARD_POKEMON_CENTER_NY` | 2 | 2 | 2 | sim |
| 58 | `STANDARD_POKETOUR_1999` | 1 | 1 | 1 | sim |
| 59 | `STANDARD_REGIONAL_CHAMPIONSHIPS` | 8 | 8 | 8 | sim |
| 60 | `STANDARD_REGIONAL_CHAMPIONSHIPS_STAFF` | 4 | 4 | 4 | sim |
| 61 | `STANDARD_ULTRA_BALL_LEAGUE` | 1 | 1 | 1 | sim |
| 62 | `STANDARD_WORLDS_2024` | 3 | 3 | 3 | sim |
| 63 | `W_PROMO_STAMPED` | 6 | 6 | 6 | sim |
| | **Total** | **365** | **365** | **365** | |

Limite de independência: a lista FINISH e as regras de exclusão SET_LOGO vêm do seletor histórico (texto recuperado do registro de 19/09), não de uma terceira fonte. As contagens por código vêm exclusivamente das respostas LIVE de 19/09.

## 6. S6 — L3 final

- Texto submetido: md5 `b7bc3700aeef278f6a79bd30e6a8d229`, 1526 bytes (= runbook §3.2 no HEAD).
- `checked_at` `2026-09-28T23:19:35.558483+00:00`; `locks_on_scope` = `[]`.

| pid | backend_type | usename | application_name | state | xact_start | backend_xid |
|---|---|---|---|---|---|---|
| 2819340 | client backend | authenticator | 'PostgREST 14.5' | idle | None | None |
| 2819351 | client backend | supabase_admin | 'postgres_exporter' | idle | None | None |
| 2867551 | client backend | supabase_admin | '' | idle | None | None |
| 3669229 | client backend | authenticator | 'PostgREST 14.5' | idle | None | None |
| 3669230 | client backend | authenticator | 'PostgREST 14.5' | idle | None | None |
| 2819328 | pg_cron launcher | supabase_admin | 'pg_cron scheduler' | None | None | None |
| 2819327 | pg_net 0.20.4 worker | supabase_admin | 'pg_net 0.20.4' | idle | None | None |

`client backend`: 5; em `active`/transação: 0. Backend do S5 (pid 3669221) ausente. Gate §4.2: conforme.

## 7. Divergências e observações (sem correção nem reinterpretação)

1. Nenhuma divergência de valor entre S5 e os critérios do mandato.
2. O esperado (B) contém 3 códigos com 0 variantes em 19/09, que não aparecem em `d_5x_c3_by_type`. É diferença de representação (ausência × zero), registrada aqui para o auditor decidir.
3. `S5/e15p_precheck.json` é derivado (extração reformatada) do bruto; o original é `S5/raw_response.txt`.
4. O S5 rodou sem o invólucro psql (sem `BEGIN READ ONLY`/`ROLLBACK`/`lock_timeout` locais); `lock_timeout` da sessão MCP = 0. Tempo de execução não medido.
5. C0/C1/C2 divergem da impressão digital (contraprovas), como esperado pela readiness.
