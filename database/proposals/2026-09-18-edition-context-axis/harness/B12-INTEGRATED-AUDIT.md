# 2830H — Auditoria consolidada do pacote integrado (L5–L13)

| Campo | Valor |
|---|---|
| **Mandatos** | BATCH12 — INTEGRATED COMPLETION · INTEGRATED TECHNICAL RESOLUTION · INTEGRATED FINAL TECHNICAL GATES. Baseline HEAD `945caa32` + alterações locais do L4 (preservadas). |
| **Natureza** | Implementação LOCAL. Nenhum SQL (nem SELECT), nenhum acesso LIVE, nenhuma DDL, nenhum `git add/commit/push`. FREEZE ATIVO. |
| **Estado** | **IMPLEMENTADO — NÃO EXECUTADO — NÃO COMPILADO no PostgreSQL** (sem servidor e sem parser SQL/PL-pgSQL no ambiente; ver §2). |
| **Cobertura** | 75 casos automáticos novos (E07–E15). Reconhecida 60/135. Executáveis hoje: E11 e E12 (sem dependência de decisão); E07/E08/E09/E13/E14 exigem a 2234; E10 sem dependência; E15 bloqueado por B-5X. |
| **Fonte única** | `tools/b12gen/` (gerador, verificador `b12_check.py`, lint `b12_lint.py`). Todo `.sql` do pacote = saída byte a byte do gerador (R-1). Manifesto: `B12-INTEGRATED-MANIFEST.json`. |

## 1. Inventário

| Id | Lote | Arquivo | Casos | CONTEXT do H283P | md5 |
|---|---|---|---|---|---|
| E07 | L5 | `2830H_E07_game_sentinel_2_6_3_3.sql` | 2 | 234 | `8a31b5a6…` |
| E08 | L6 | `2830H_E08_section4_card_variant_identity.sql` | 8 | 639 | `23746882…` |
| E09 | L7 | `2830H_E09_section_s_staging.sql` | 12 | 1148 | `e4266fd6…` |
| E10 | L8 | `2830H_E10_section_r_routing_2211.sql` | 12 | 1615 | `c810a76e…` |
| E11 | L9 | `2830H_E11_section_k_confirm_static.sql` | 3 | 260 | `9ddaf49c…` |
| E12 | L10 | `2830H_E12_section_b_backfill_semantic.sql` | 14 | 712 | `232b8570…` |
| E13 | L11 | `2830H_E13_section_m_state_machine.sql` | 11 | 960 | `5907e85d…` |
| E14 | L12 | `2830H_E14_section_g_guard_2214.sql` | 8 | 741 | `28bc469d…` |
| E15 | L13 | `2830H_E15_section5_legacy_hold.sql` | 5 | 395 | `6db3d4a7…` |
| E07P–E14P, E15P, E98, P9A, P9B | — | prechecks, medição A4, resíduo estendido, plano, tempo (isolado) | — | — | manifesto |
| 2234 | D-P7X | `../2234_harden_search_path_edition_context_write_surface.sql` (PROPOSTA v1.1 + CORRECTION-01, não aplicada; 1ª submissão LIVE abortada, §10) | — | — | `991d77fd…` |

## 2. Validação

| Classe | Resultado |
|---|---|
| **Automática** | `python3 tools/static_check.py` rc = 0. Blocos anteriores idênticos (444; E03 88/79/6; E04 65/94/7; E05 58/54/6; E06 64/54/6). **B12-PERFIL 552/552 · B12-VERIFICADOR-NEG 52/52 · B12-VERIFICADOR-POS 21/21** (inclui o lint; +R-27/R-28 e 6 mutações dos gates finais; +lint de migration da 2234 — R-30, 31 regras M/L, 4 mutações e 5 controles positivos 2212/2230–2233 executadas no LIVE). |
| **Lint (substituto declarado de compilação)** | L-1 parênteses · L-2 BEGIN/END, IF/END IF, CASE · L-3 variáveis declaradas · L-4 `format()` marcadores = argumentos · L-5 `SELECT … INTO` expressões = alvos · L-6 `jsonb_build_object` par e ≤ 100 · L-7 relações · L-8 colunas (alias, INSERT, UPDATE) · L-9 funções e aridade · L-10 constraints/índices/triggers, contra o DDL do repositório. Calibrado: E03, E04, E05, E06 e E06P — compilados e executados no LIVE — passam em todas as regras; 10 mutações (uma por regra) são rejeitadas. **Não substitui compilação**: tipos de expressão, resolução de sobrecarga e semântica de planner não são verificados. |
| **Por inspeção** | semântica caso a caso contra 2830 v7.0, 2832 v3.1, 2833 v2.0, 2214 v3.1, 2218, 2211, 2176, 2831; tipos das UNIONs de controle (VREC/SMREC/V8/V11); INTO no fim de `WITH … SELECT` (aceito pelo PL/pgSQL: primeiro INTO de nível superior). |
| **Pendente** | compilação/execução PostgreSQL; P9A (forma do plano); P9B (tempo, ambiente isolado); medição A4 (E15P). |

## 3. Segurança — D-P7X resolvido por correção, não por mitigação

- Inventário LIVE (E00, registros L2/L3/L4, `search_path_unsafe = true`): `public.set_updated_at()` (`search_path=public, pg_temp`, 2132), `public.validate_card_variant_game_consistency()` (NULL, excluída da 2132), `public.normalize_catalog_variant_import_job()` e `…_row()` (NULL, 2137/2139, posteriores à 2132).
- A proposta citada antes tinha 3 ALTERs e deixava de fora `set_updated_at` (a 4ª). A **2234 v1.1** (proposta, NÃO executada) corrige as 4 com `SET search_path = ''`, em uma transação, com pré-condição de identidade (md5 LF do corpo + `proconfig` atual), relações qualificadas existentes e **alcance LIVE de `set_updated_at`** (todo trigger ligado a ela escreve `updated_at TIMESTAMPTZ`, sem cast), e pós-condição (4/4 `{search_path=""}` + impressões digitais de metadados, triggers e `pg_depend` idênticas às da pré-condição; só `proconfig` muda). Resolução sob search_path vazio auditada por corpo: CURRENT_TIMESTAMP/NULLIF são construções SQL; UPPER/BTRIM, `uuid`, `=`/`<>` em pg_catalog; relações qualificadas. Rollback exato (proconfig anterior) no rodapé, comentado. R-27 + 2 mutações.
- **P7X endurecido**: os prechecks E07P/E08P/E09P/E13P/E14P exigem `{search_path=""}` nas 8 raízes (`g_p7x_roots_pinned` + `g_p7x_search_path_empty`); a classe LEGACY_SP e a mitigação foram removidas. Esses prechecks falham até a 2234 rodar.
- Fora de escopo, registrado: as outras 12 funções da 2132 (`public, pg_temp`) não estão na superfície de escrita dos lotes.

## 4. Integridade, rollback e efeitos não transacionais

- Envelopes terminam SEMPRE em exceção; cada caso em subtransação (H283C). Tudo o que é transacional é desfeito.
- **O rollback NÃO desfaz**: WAL gerado; XIDs consumidos; tuplas mortas e crescimento de índices/heap (até vacuum); contadores de `pg_stat_*`/`pg_stat_statements`; entradas no log do servidor (a exceção terminal H283P/H283F é um ERROR registrado, com o marcador); esperas de lock impostas a outras sessões durante a execução; `clock_timestamp` e custo de CPU/IO. Nenhum envelope usa sequence, NOTIFY, dblink, `pg_sleep`, advisory lock ou escrita fora do banco.
- Resíduo: E99 (inalterado) + E98 (S6b).

## 5. Semântica — decisões

| Id | Requisito exato | Implementação | Contraprova | Decisão |
|---|---|---|---|---|
| **B-5X** | 5.2: READY_STRUCTURAL 365 = 285 + 80, "mesma derivação da 2831", constantes medidas antes | E15P mede C0 (predicado `b_total` da 2841 RECORTE 4), C1 (literal-2831), C2 (semântica 2211) e C3 (seletor histórico de 2026-09-19, STOP-7, `26a3cdb9`) contra a **impressão digital de A** (23 tipos nomeados = 320, 21 WORLDS/ASIA = 21, 19 avulsos = 24 com 5 duplos; SET_LOGO_REVERSE SVP 38 + DP1 2; SET_LOGO_STANDARDS DP1 4; a leitura "16 WORLDS/ASIA + 24 singletons" do MIGRATION-MAP confundia tipos com variantes) + 365/285/80 + 40/40 + exclusões; gate `g_5x_unique_candidate_equals_a`; E15 fail-closed no PREFLIGHT e o 5.2 exige a impressão digital (COALESCE fail-closed) | E15P LIVE S5 (2026-09-28): C0 21.938 variantes / 85 tipos, C1 23.166 / 84, C2 285 / 30 — divergem da impressão digital; somente C3 reproduz 365 / 63 e o censo histórico de 2026-09-19 (63/63 códigos) | **ADJUDICADO DOCUMENTALMENTE: `READY_DEF = C3`** (2026-09-28) — E15P LIVE: c3 único candidato conforme, 63/63 contra o censo de 19/09; ver `B5X-C3-ADJUDICATION-RECORD.md`. Aplicação no gerador, 5.3/5.7 e E15 pendentes |
| D-V1 | V1: divergência no universo operacional; "COUNT(esperado = 'UUID') = 0 ⇒ FAIL" (a 2832 conta na tabela inteira) | divergência: op; existência: VREC (op ∪ histórico com chave) e, se 0, complemento (histórico sem chave) com `LIMIT 1` | a leitura anterior (só VREC) podia dar FAIL falso; nunca PASS falso | **resolvido** — igual à 2832, custo proporcional |
| R6 | "ambos UNRESOLVED, residual intacto; contagens de trait/profile/mapping inalteradas" | Printing RESOLVED_NO_PRINTING, EC RESOLVED_NO_EDITION_CONTEXT; vetor de 8 contagens (EC 5 + Printing 3) antes/depois | não existe estado `UNRESOLVED` na 2176/2211 (vocabulário lido); `UNRESOLVED` da 2834 é abstração de fixture para "mapping sem profile", inaplicável a token desconhecido | **resolvido** — estados LIVE; contagem ampliada |
| R12 | "nas saídas NEEDS_REVIEW_*, residual_subtype e residual_stamp preservam o token real" | as 4 saídas A4 da 2211 (INACTIVE/INVALID × subtype/stamp) + contraprovas: residual **integral do Printing** mesmo com subtype já consumido pelo eixo 3 antes da saída (INACTIVE e INVALID via stamp); saída terminal NO_EC_PROFILE consome o token de EC e preserva o desconhecido | NO_EC_PROFILE/INACTIVE_EC_TRAIT/INACTIVE_EC_PROFILE consomem o token (E06 3.2 PASSOU no LIVE); nenhuma asserção anterior enfraquecida (R-22 exige 3+3+1 e o residual exato) | **resolvido** no escopo A4; a leitura literal integral contradiz a 2211 LIVE — mudança só por contrato |
| P13-V/SM | universo vazio ⇒ controle negativo | mesmo texto de predicado em rows reais e controles em memória; SM4/SM6/SM10/SM11 com fixture | avaliador offline prova que cada controle dispara o próprio predicado | implementado |

## 6. Concorrência

- `SET LOCAL lock_timeout = '5s'` + asserção em todo envelope. Escritas só em linhas novas; INSERTs com FK tomam `FOR KEY SHARE` nas Cards/jobs/profiles referenciados — o confirm (`FOR UPDATE` na Card) espera até o fim do envelope. SM6 referencia 16 Cards reais; G7 muda status só do job de fixture.
- K1, K2, K8b continuam MANUAIS (P14).

## 7. Performance — cenários (P9A forma, P9B tempo em ambiente isolado)

| Id | Consulta | Risco | Controle |
|---|---|---|---|
| M1 | VREC (E12): 2211 por row em op ∪ histórico com chave | **alto** se o universo com chave for grande | P9A-B / P9B-M1; divisão do E12 se > 60 s |
| M2 | V1-complemento: 2211 sobre histórico sem chave | **alto** só no caminho sem ocorrência (`LIMIT 1` corta no primeiro) | P9B-M2 mede o pior caso |
| M3 | SMREC (E13) + SM6 (512 INSERTs, 4 triggers cada, guard com SELECT do job) | baixo–médio | P9A-M / P9B-M3 e elapsed_ms do E13 |
| M4 | DERIV-5X C2 (E15P/E15): 2211 por variant com lineage e subtype/stamp | **alto** | P9A-5X / P9B-M4 |
| M5 | envelopes completos | limite 120 s | elapsed_ms do H283P no ambiente isolado |

## 8. Bloqueios

| Id | Estado | Saída |
|---|---|---|
| B-5X | **medido e adjudicado documentalmente (`READY_DEF = C3`, 2026-09-28)**; STOP-5/STOP-7 encerrados documentalmente — `B5X-C3-ADJUDICATION-RECORD.md`. C3 aplicado no gerador em `c74c55ae` (E15 regenerado, `E15_BLOCKED_53_57 = True`). **D1 (identidade por id de HOLD/PLAN/READY/CONDITIONED) medido no LIVE em 2026-09-29: `gate_pass = true`, 16/16; composições iguais às de 19/09; D2 (SLS 11 / SLR 59) confirmada** — `evidence/D1-2026-09-29/RELATORIO-EVIDENCIAS.md` | fixação dos quatro digests (53-d) e reescrita de 5.3/5.7 sob mandato próprio; E15 segue fail-closed até lá |
| D-P7X | **resolvido tecnicamente**; execução pendente | autorização específica para a 2234 (DDL) |
| R12 escopo | **resolvido (A4)** | só reabre por mudança de contrato |
| Compilação | não realizável aqui | primeiro contato no ambiente isolado (P9B) ou FAIL-closed no LIVE |
| P9b/A2 | pendente | P9B no ambiente isolado |

## 9. Execução controlada (um lote por mandato; S0–S7 + S6b)

S0 HEAD + `static_check` rc = 0 · S1 L1 · S2 L3 · S3 E00 24/24 · S4 precheck do lote (registrar `d_xbaseline`/`md5`) `gate_pass = true` · S5 envelope (uma chamada) · S6 E99 9/9 · S6b E98 5/5 (L5, L6, L7, L11, L12) · S7 L3 final. Ordem: L9 → L10 (após P9B-M1/M2) → L8 → [2234] → L5 → L6 → L7 → L11 (após P9B-M3) → L12 → [B-5X] → L13 (após P9B-M4).

## 10. Incidente de processo (registrado)

Na rodada INTEGRATED COMPLETION foi executado `git add -N` (intent-to-add) e revertido na hora com `git reset -q` (índice = HEAD). Nenhum commit ou push.

**Incidente BATCH12-2234-LIVE-01 (2026-09-28).** A 2234 v1.1 publicada (blob `c3a8cbce…`) foi submetida uma vez ao LIVE (`apply_migration`, HEAD `696caed2`) após L1/L3/E00/ledger/V0 conformes e falhou com `42601 syntax error at or near ")"` no `DO $post$`: um `)` excedente no `SELECT concat_ws('#', …) INTO v_dep`. Transação abortada integralmente: V1/V2 = V0 (4 funções com proconfig original, 51 triggers), ledger sem 2234; efeitos não transacionais: XID, WAL e ERROR no log. Causa de não detecção: R-26/R-27 só conferiam presença de trechos e o lint não cobria migrations. **CORRECTION-01:** removido só esse `)` (blob `447d9996…`); `b12_lint.lint_migration` (M-1 parênteses por statement de topo e PL/pgSQL, M-2 dollar-quotes, M-3 L-1..L-10 por bloco DO, M-4 LOOP, M-5 RAISE, M-6 BEGIN/COMMIT) + R-30; mutação que reintroduz o `)` = artefato anterior byte a byte ⇒ rejeitada (M-1); L-3 passou a reconhecer declarações na mesma linha do DECLARE. Nova execução exige nova autorização.
