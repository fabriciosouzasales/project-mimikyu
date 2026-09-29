# D1 — Readiness da medição de identidade por id (HOLD 107 · plano 285)

| | |
|---|---|
| Mandato | `BATCH12-E15-D1-MEASUREMENT-READINESS-01` |
| Baseline | `c74c55ae7a140539a3db64cf1be7a7efdabc0cbd` (árvore limpa, exceto `harness/local-pg17/` e `tools/b12gen/__pycache__/`, ambos não rastreados e preexistentes) |
| Estado | **PREPARADO, NÃO EXECUTADO.** Não houve SQL nem acesso ao LIVE. |
| Invariantes | FREEZE ativo · `E15_BLOCKED_53_57=True` · E15P `f9fc6d81…` e E15 `7a2da69c…` intocados · 130/135 preservado · sem git |
| Decisões | **D1** aprovada: identidade congelada por id de HOLD e plano. **D2**: a referência do HOLD é a de 19/09 (SLS 11, SLR 59). A divergência com o H1 (SLS 15, SLR 55) fica registrada; o H1 não é sobrescrito. |

## 1. Artefatos e hashes

| Artefato | md5 | bytes | Papel |
|---|---|---|---|
| `D1-ID-IDENTITY.sql` | `efb3217e4b5ce9d227f412739c3e1b18` | 16.728 | Instrumento: **um único SELECT**, só leitura, terminado em `;` |
| `gen_d1.py` | `2de624c42bfffcb3f83d8657b26ade5c` | 13.700 | Gerador. `python3 gen_d1.py <evidence> <saida.sql>` reproduz o md5 acima byte a byte (verificado) |
| `d1_model.py` | `d14cfc1deb9b2ed37c55b029c640022b` | 11.688 | Modelo lógico offline (§5) |

Entradas do gerador, todas em `harness/evidence/B5X-E15P-2026-09-28/`:

| Arquivo | md5 |
|---|---|
| `census_19-09_original/census_raw_response_2026-09-19T01-27-53Z.txt` | `cf27772b9e71b76c1c60d191b2291907` |
| `census_19-09_original/setlogo_by_set_raw_response_2026-09-19T01-37-39Z.txt` | `c6b03190e22abccbd34a6a2f834b15d1` |
| `c3_expected_from_raw_19-09.json` | `a68bcba326063409d5578aba13f05e41` |

Instrumento L3 reutilizado sem alteração: runbook §3.2, o mesmo de S6 (`S6/statement_submitted.sql`, md5 `b7bc3700aeef278f6a79bd30e6a8d229`, 1.526 bytes).

**Verificação estática do instrumento**

- b12_lint: L-1 (347/347), L-4, L-6, L-7, L-8, L-9 e L-10 PASS.
- Um único `;` fora de comentários e literais; parênteses balanceados.
- Sem DML/DDL, sem `2211`/`2192`/`resolve_*`, sem DERIV-5X.
- Correção feita nesta rodada: os `EXCEPT … UNION ALL … EXCEPT` das diferenças simétricas passaram a ter os operandos entre parênteses. Sem os parênteses, a precedência de conjuntos avaliaria `((A−B) ∪ B′) − A′`, o que mascararia a diferença.

## 2. O que o instrumento mede

Tudo é calculado num único statement, portanto num único snapshot MVCC:

- **Um único scan** de `card_variant ⨝ card_variant_type ⨝ card ⨝ card_set` (`d1_cv MATERIALIZED`).
- Cada classe tem **o próprio predicado**:
  - FINISH: lista de 28;
  - HOLD: 2831 PASSO 0, verbatim;
  - NÃO_CONT: `SET_LOGO%` em EX7–16;
  - READY: `d5_c3`, verbatim.
- A partição é **conferida** (`n_cls ≠ 1 → 0`), não presumida.
- Os dois planos são construídos de forma independente:
  - `plano_contrato` = READY ∖ {STAFF_HOLO, SET_LOGO_REVERSE}, por código, sem ler Pricing;
  - `plano_derivado` = READY ∖ tipos com qualquer linha em `pricing_source_card_identity` ou `pricing_source_variant_mapping`.

| Requisito | Gate(s) |
|---|---|
| 1. Universo 1.027 e partição 365/107/555 | `g_join_complete`, `g_type_code_unique`, `g_universe_19_09` (24.893/23.866), `g_uraw_1027`, `g_partition_counts`, `g_partition_exact` |
| 2. Composições | `g_ready_by_type_19_09` (63 tipos), `g_hold_by_type_set_19_09` (30 chaves, D2), `g_nc_by_type_set_19_09` (12 chaves) |
| 2. Digests por id | `d1_identity.{hold, plan, ready, conditioned}`: `md5(string_agg(id::text, ',' ORDER BY id))` |
| 4. H6 e pscid/psvm | `g_h6_types` (padrão de presença por tipo = 19/09), `g_conditioned_80_40_40`, `g_plan_x_pscid_zero` e `g_plan_x_psvm_zero` **separados**, `g_plan_equivalence` (symdiff 0 **e** md5 iguais) |
| Consistência de código | `g_plan_contract_285`, `g_plan_x_hold_zero` (rotulado como consistência, não prova) |

`gate_pass` = `bool_and` de todos os gates, e exige que nenhum seja NULL.

**Identidade nova × composição histórica.** As composições por tipo e por (tipo, Set) são **comparadas** com 19/09 e funcionam como gate. Os digests **não têm referência histórica**, porque em 19/09 nenhum digest foi capturado. Por isso a primeira medição apenas os **captura**. Um PASS em composição significa que o estado atual é indistinguível de 19/09 por contagem. Não significa que os ids sejam os mesmos de 19/09, e essa afirmação não é demonstrável com a evidência existente.

## 3. Custo esperado (estimado, não medido)

- Um scan de cerca de 24.893 linhas com hash join sobre as três tabelas pequenas de dimensão. Cada tabela de Pricing é agregada uma vez por tipo.
- Os CTEs derivados são materializados (usados mais de uma vez) e relidos em memória, cerca de 20 passagens sobre 24,9 mil linhas.
- `string_agg` sobre no máximo 365 ids (cerca de 14 KB).
- Resposta de aproximadamente 5 KB.
- Ordem de grandeza: **abaixo de 1 s — ESTIMATIVA, NÃO MEDIDA** (o canal MCP não mede tempo e não houve EXPLAIN ANALYZE) e de uma fração de MB de `work_mem`. É muito menor que o E15P c2, que fez 23.166 chamadas.
- Não há escrita, lock além de `AccessShareLock`, chamada de função de catálogo nem rede.

## 4. Protocolo de execução (mandato LIVE próprio)

| Passo | Ação | Critério |
|---|---|---|
| S0 | Local: HEAD `c74c55ae`; md5 do SQL = `efb3217e…` e 16.728 bytes; regenerar com `gen_d1.py` + evidência e obter o mesmo md5; `d1_model.py` → `MODELO: todas as asserções PASS`; E15P `f9fc6d81…` e E15 `7a2da69c…` inalterados | Qualquer divergência: STOP |
| S1 | L3 antes: runbook §3.2 (`b7bc3700…`), 1 `execute_sql` no projeto `qjfutqujxrbzgrtkpgkg` | Mesmo gate §4.2 de S6 (0 em `active` ou em transação, `locks_on_scope=[]`) |
| S2 | **Uma** chamada `execute_sql` com o texto integral de `D1-ID-IDENTITY.sql`, sem editar, sem invólucro psql. Guardar `statement_submitted.sql` (md5 igual a S0) e `raw_response.txt` | Ver §6 |
| S3 | L3 depois | Igual a S1. Backend de S2 ausente |
| S4 | Registro: md5 dos brutos, `d_session.snapshot`, `backend_pid`, `checked_at`, os 4 pares (n, md5) de `d1_identity` e `d1_hold_by_key` | — |
| S5 | **Não** pinar nada neste mandato. Os digests passam a constante (53-d) só num mandato posterior de implementação e auditoria | — |

## 5. Contraprovas (modelo offline `d1_model.py`)

O modelo lê as constantes **do próprio SQL** (blocos `VALUES`) e as re-deriva de forma independente da evidência bruta, afirmando igualdade. Depois monta um universo sintético com as composições de 19/09 (24.893 linhas e ids UUID determinísticos) e espelha os predicados e gates. Os digests do modelo são sintéticos e não são referência LIVE.

| Cenário | Gates que falham | Digests que mudam |
|---|---|---|
| BASE | — (`gate_pass`) | — |
| CP-1: troca de tipo PROMO_STAMPED ↔ REWARDS_HOLO | **nenhum** | hold, plan, ready |
| CP-2: troca de Set SLR SV8.5 ↔ SVP | **nenhum** | hold, ready, **cond** (plan não muda) |
| CP-2b: troca de Set SLS SV5 ↔ SVP | **nenhum** | hold, plan, ready |
| CP-5a: EX ↔ HOLD para Sets sem evidência | `hold_by_type_set`, `nc_by_type_set` | hold |
| CP-5b: troca pura EX11 ↔ SV5 (mesmas chaves) | **nenhum** | hold |
| CP-6: DELETE+INSERT compensado no plano | **nenhum** | plan, ready |
| CP-7: troca de tipo STAFF_HOLO (READY condicionado) ↔ HOLO (FINISH) | **nenhum** | ready, **cond** (hold e plan não mudam) |
| CP-4: tipo READY ganha psvm | `h6_types`, `conditioned`, `plan_x_psvm`, `plan_equivalence` | cond |
| M-1: HOLD sem PROMO_STAMPED (mutação) | `partition_counts`, **`partition_exact`**, `hold_by_type_set` | hold |
| M-2: HOLD sem exceção DP1/SWSH9/SVP | `partition_counts`, **`partition_exact`**, `hold_by_type_set`, `plan_x_hold` | hold |
| M-3: plano exclui só STAFF_HOLO | `plan_contract_285`, `plan_x_pscid`, `plan_equivalence` | plan |
| M-4: +1 SLR@SV10 (deriva) | `universe`, `uraw`, `partition_counts`, `hold_by_type_set` | hold |

**Consequências para o desenho do 53-d, a decidir no mandato de implementação:**

1. CP-1, CP-2, CP-2b, CP-5b, CP-6 e CP-7 só são detectáveis por digest. Isso confirma o limite estrutural das contagens.
2. **O CP-2 não demonstra insuficiência de HOLD + PLAN.** O digest de HOLD já detecta essa troca. A insuficiência de HOLD + PLAN é demonstrada pelo **CP-7**: a troca compensada entre uma variante READY condicionada (STAFF_HOLO) e uma FINISH (HOLO) preserva os digests de HOLD e PLAN e todos os gates, e só altera READY e CONDITIONED. Por isso recomenda-se pinar os quatro: hold, plan, ready e conditioned.
3. **Alcance dos digests.** Cada digest congela apenas a **participação dos UUIDs** no conjunto (quais ids pertencem a HOLD, PLAN, READY ou CONDITIONED). Não congela a totalidade dos atributos individuais de cada variante. Uma alteração que mantenha o id na mesma classe fica fora do digest: por exemplo, mudança de Card ou Set entre Sets da mesma classe, ou de tipo entre dois tipos do plano. Essas alterações só são pegas pelos gates de composição quando mudam contagens por tipo ou por (tipo, Set).
4. O CP-5a corrige a auditoria anterior: uma troca EX ↔ HOLD **para Sets sem evidência** falha em 53-c. Uma troca pura entre chaves existentes (CP-5b) só é pega pelo 53-d.
5. `g_partition_exact` falha em qualquer sobreposição ou lacuna de predicado (M-1, M-2) e em NULL de join. Sem mutação de código ou NULL, ela é consistência de código, o mesmo rótulo de `plan_x_hold`.

## 6. Critérios de STOP

- S0 divergente, ou md5 do texto submetido diferente de `efb3217e…`.
- L3 antes ou depois fora do gate §4.2, ou mais de uma chamada de D1.
- Erro SQL de qualquer natureza. `57014` (timeout) = **INCONCLUSIVO**, sem repetição no mesmo mandato.
- Resposta incompleta, truncada ou sem `d_session.snapshot`.
- `gate_pass` diferente de `true`, ou qualquer gate `false` ou NULL. Registrar `d1_measured` e `d1_hold_by_key` sem reinterpretar. Não há ajuste nem nova medição no mesmo mandato.
- `d_session.transaction_read_only` não precisa ser `on` (canal MCP sem invólucro): registrar, não gatear. A garantia de só leitura vem do texto, que é um SELECT sem funções voláteis de escrita.
- **Não é STOP, é regra:** os digests não são comparados com nada nesta primeira execução, apenas registrados. Uma segunda medição sob FREEZE (se autorizada) deve reproduzir os quatro md5 exatamente. Qualquer diferença será STOP.
