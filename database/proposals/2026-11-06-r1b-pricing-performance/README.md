# R1-B — Correção de desempenho de preços (3983 → 3989)

| Campo | Valor |
|---|---|
| Status | **3989 CONFIRMADO EXECUTADO no LIVE em 2026-11-06** (ledger `20261106141505`). Harness 5880 v1.0 não completou (limites do conector; ambas as tentativas desfeitas); substituído pelo **5880 v1.1** — B, C, D e E executados (somente leitura, todos PASS); **A autorizado e executado, interrompido por 57014 na seleção do fixture antes de qualquer escrita (sem veredito; aguarda decisão)**. Rollback R3989 não executado (não necessário até aqui). |
| Origem | Diagnóstico R1-B INVENTORY PERFORMANCE DIAGNOSIS-01 (aprovado): `57014` (statement_timeout 8 s do papel `authenticated`) na etapa de preços do Inventário detalhado por Card Set. |
| Pré-requisito | 3983 em vigor **exatamente** como versionada (md5 do corpo `de9088a98c8e09a8b65180286a50547e`) — a 3989 confere e aborta se divergir. |
| Executor | Fabrício, com autorização explícita |

## Arquivos

| Arquivo | O quê |
|---|---|
| `3989_optimize_get_card_variants_pricing_summary.sql` | `CREATE OR REPLACE` só de `get_card_variants_pricing_summary(uuid[])`: a observação elegível mais recente é escolhida **por produto** (índice existente `ix_pricing_observation_latest_lookup`) e depois a melhor entre os produtos; NM resolvido uma vez. Pré-check (md5 da 3983) e pós-check (md5 da 3989, contrato e ACL idênticos ao anterior, SECURITY DEFINER, STABLE, `search_path` vazio, anon sem EXECUTE). |
| `5880_validate_pricing_summary_optimization.sql` | Harness (uma chamada, `pg_temp`): compara a 3989 com a **definição anterior copiada byte a byte** (`pg_temp.ref_3983_…`, md5 conferido) — 20 checagens, GATE 20/20. |
| `R3989_restore_3983_get_card_variants_pricing_summary.sql` | Rollback: restaura o corpo exato da 3983 (pós-check por md5). |

Diferença de código 3983 → 3989 (somente o trecho que escolhe a observação): o `JOIN pricing_observation … JOIN card_condition cc ON cc.code = 'NM' … ORDER BY … LIMIT 1` vira `CROSS JOIN LATERAL (… WHERE pricing_product_id = pp.id AND condition_id = v_nm_condition_id AND price_type = 'MARKET' ORDER BY observed_at DESC, created_at DESC, id DESC LIMIT 1)`, seguido do mesmo `ORDER BY … LIMIT 1` entre produtos. Câmbio, fallback por carta, validações, mensagens, retorno, segurança: inalterados.

**Por que é equivalente:** a chave (observed_at, created_at, id) é total (id é PK); o máximo de uma união é o máximo dos máximos por produto. Prova prévia somente leitura (2026-11-06): 1.301 variantes do acervo real, 0 divergências; buffers do trecho de observações 6.797 → 1.148 por lote de 100.

## Harness 5880 — o que cobre

| # | Pedido | Checagem |
|---|---|---|
| 1 | Vários produtos e observações | 2.1 (fixture real) e 1.1 (conjunto real) |
| 2 | Empates e desempate | 2.2 (created_at) e 2.3 (id) |
| 3 | Preço ausente | 3.1 (sem produto, id inexistente, id repetido) |
| 4 | Fallback por carta | 4.1 (moeda sem PTAX) |
| 5 | Câmbio | 5.1 (USD × PTAX ≤ data) e 5.2 (BRL) |
| 6 | Produtos inativos / observações inelegíveis | 6.1 (LP, LOW mais novas) e 6.2 (produto inativo) |
| 7 | Isolamento e permissões | 0.3, 7.1–7.4 |
| 8 | Equivalência monetária | 8.1 (Σ BRL, Σ origem, contagem por base) |
| 9 | Desempenho com o conjunto real | 9.1 (pior lote < 8.000 ms; total ≤ 110% da referência) |
| 10 | Nenhuma alteração de dados | 10.1 (somas de controle antes = depois; fase real em transação somente leitura) |

Fixtures (observações sintéticas, um produto desativado) ficam dentro da sentinela TR000 — tudo desfeito. Conjunto real: variantes de todos os acervos ∪ até 1.500 com ≥ 2 produtos ativos ∪ até 300 com produto inativo ∪ até 300 sem produto.

## Harness 5880 v1.1 (substitui a execução monolítica do v1.0)

O v1.0 (uma chamada, 20 checagens + comparação 3983 × 3989 sobre o acervo inteiro) não cabe no limite de ~2 min do conector. O v1.1 mantém os objetivos e divide em execuções curtas; o v1.0 fica como registro.

| Parte | Arquivo | Natureza | Checagens v1.0 | Resultado LIVE 2026-11-06 |
|---|---|---|---|---|
| A | `5880A_v1.1_synthetic_PLAN_NOT_EXECUTED.sql` | Escrita transacional + TR000 + ROLLBACK | 0.1, 2.1–2.3, 3.1, 4.1, 5.1, 5.2, 6.1, 6.2 (corpo idêntico ao v1.0) | Autorizado e executado em 2026-11-06: **interrompido por 57014** (timeout local de 30 s) na consulta que escolhe a variante do fixture, **antes de qualquer escrita**; transação desfeita; postcheck D limpo. **0/11 — sem veredito funcional**; nenhuma correção improvisada |
| B | `5880B_v1.1_compare_real_sample.sql` | Somente leitura, REPEATABLE READ, 1 fatia ≤ 100 ids por execução | 1.1, 8.1 | 6 fatias, 366 ids (364 distintos), **0 divergências**, Σ BRL/origem idênticas |
| C | `5880C_v1.1_security.sql` | Somente leitura | 0.2, 0.3, 7.1–7.4 + isolamento | **PASS** (todas as colunas) |
| D | `5880D_v1.1_integrity_postcheck.sql` | Somente leitura | 10.1 | **PASS** (contagens = baseline; 0 resíduo) |
| E | `5880E_v1.1_performance.sql` | Somente leitura, só a 3989 | 9.1 | **PASS** — 42 chamadas, 0 erro, pior 1.179 ms (< 8.000) |

**5880A v1.2** (`5880A_v1.2_synthetic_PLAN_NOT_EXECUTED.sql`, md5 `1da40292…`, **CONFIRMADO EXECUTADO no LIVE em 2026-11-06: GATE 11/11 PASS**, ROLLBACK, postcheck D limpo): muda só a descoberta do fixture. O critério da v1.1 (2 produtos elegíveis com observação NM real nos dois) não existe no LIVE; a v1.2 usa listas fixas de candidatas (3 variantes com 2 produtos PRIMARY e observação NM utilizável em um deles; 3 variantes sem produto nem mapping), revalidadas na transação antes de qualquer escrita.

Limite da evidência: a equivalência com a 3983 foi provada **na amostra** (364 variantes distintas; inclui toda a população real com ≥ 2 produtos com observação e os 2 empates reais) e, antes da aplicação, sobre as 1.301 variantes do acervo (prova somente leitura do CORRECTION-01). Não é prova sobre todas as 38.011 variantes. Desempate por `id` e câmbio indisponível só existem nos casos sintéticos (parte A).

## Plano de aplicação (quando autorizado)

1. Conferir que o arquivo é aplicado com quebras de linha LF (o md5 do pós-check depende do corpo exato).
2. Aplicar `3989_…sql` (uma transação; aborta sozinha se a 3983 em vigor divergir).
3. Executar `5880_…sql` — esperado `GATE PASS 20/20`.
4. Homologar o Inventário detalhado por Card Set (sem 57014).
5. Se qualquer passo falhar: `R3989_…sql`.

## Rollback

`R3989_restore_3983_get_card_variants_pricing_summary.sql` — sem dados a desfazer (a 3989 não altera tabelas, índices nem linhas).

## Mudança no app (B, local)

`web/lib/reports/acervo-set-inventory-queries.ts`: leituras da 3983 com no máximo **2** chamadas simultâneas (`PRICE_PARALLEL`); páginas da 5159 seguem com 6. Cálculo, aparência e impressão inalterados.
