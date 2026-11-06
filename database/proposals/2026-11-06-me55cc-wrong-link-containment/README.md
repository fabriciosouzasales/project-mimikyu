# ME5.5CC WRONG LINK CONTAINMENT-01 — Query 3990 (PROPOSTA — NÃO EXECUTADA)

**Problema (diagnóstico aprovado, 2026-11-06):** 5 vínculos `pricing_card_mapping` do Card Set ME5.5CC ("Celebração de 30 Anos Coleção Clássica") foram confirmados automaticamente (`SET_CONFIRMED_COLLECTOR_NUMBER_UNIQUE`, run `8d0b204b…`) casando o número **original** da reimpressão JustTCG (ex.: `4/102`) com a numeração local 001–030. Ex.: Genesect EX 004/30 recebe a cotação do Charizard 4/102 (US$ 148 → R$ 808,39). A 3989 seleciona corretamente; os vínculos é que estão errados.

| Local | Mapping | Identidade PRIMARY | External card (errado) | Produtos | Observações |
|---|---|---|---|---|---|
| 004 Genesect EX | `63ad9941-d8b2-495f-9260-5fc92f38bceb` | `36cd87da-d712-4d1f-b614-c34b92ad6a18` | Charizard 4/102 | 3 | 43 |
| 005 Misty | `1d3f88ea-3706-4763-90aa-70c8c20f668f` | `18ee0694-e6fa-4322-bdb0-f275752d3532` | Delcatty 5/109 | 4 | 44 |
| 018 Gengar | `61c330ab-dd73-4d4c-99e0-1c3ab0af8bbe` | `a2af489a-8697-4dfb-88dc-f1ba15bda0cd` | Misty 18/132 | 4 | 40 |
| 019 Darkrai & Cresselia LENDA | `bb3044be-7e6e-4e59-a2f1-98ef938e2740` | `5a0c9b04-2490-4249-a219-5dc427050726` | Dark Tyranitar 19/109 | 3 | 45 |
| 025 Scizor ex | `001152c1-b86c-4957-86a0-345fd09f0f4c` | `e51019f6-8e24-4090-bc74-c9324a9584d2` | Sneasel 25/111 | 5 | 41 |

## Contenção mínima

Uma única mudança de estado: **`pricing_card_mapping.match_status` CONFIRMED → REJECTED** nos 5 vínculos.

- Todas as leituras de preço exigem `pcm.match_status = 'CONFIRMED'`: 3989 (variante), 3972 (fallback "preço geral"), `get_card_pricing_snapshot`, `admin_get_pricing_report_card`, `admin_pricing_report_set_price_candidates`, `get_pricing_admin_overview`. Só `admin_get_pricing_mapping_detail` lê sem esse filtro (tela de auditoria — continua mostrando o vínculo, agora REJECTED).
- **Sem fallback residual:** 0 preços manuais nas 5 cartas; a 3972 também exige o vínculo CONFIRMED → as cartas ficam "sem cotação" (nunca zero).
- **Não toca** produtos (19, todos exclusivos dos 5 vínculos — nenhum `external_product_id` compartilhado), identidades (seguem CONFIRMED, inertes), observações (213 preservadas) nem a 3989.
- **REJECTED é terminal para a automação:** a promoção (`batch_update_pricing_card_mapping_status`) só altera PENDING/NOT_FOUND; o bootstrap (3957) nunca rebaixa nem reescreve CONFIRMED/REJECTED.
- **Rastreabilidade:** o CHECK de REJECTED exige decisão humana (`confirmed_by`) e `confirmed_sync_run_id` nulo — o run original, o método e o `confirmed_at` anterior ficam em `match_evidence.containment_3990`; `confirmed_at` é preservado pelo trigger; 5 linhas em `pricing_admin_action_log` (`PRICING_MAPPING_REJECTED`, query 3990).
- **Por que não pela RPC administrativa:** `admin_reclassify_pricing_card_mapping` bloqueia CONFIRMED → REJECTED quando há produto/observação (`CARD_MAPPING_HAS_DEPENDENT_PRICING_DATA`) — exatamente este caso.
- **Por que não rejeitar as identidades agora:** `pricing_source_card_identity` REJECTED é irreversível por desenho (`rejected_at` imutável; CONFIRMED exige `rejected_at` nulo). Fica para o ciclo de revinculação, junto da decisão das cartas corretas.

**Efeito colateral conhecido:** o refresh diário (`justtcg-price-refresh-set`, próximo para este Set em 2026-11-07 05:40 UTC) seleciona identidades CONFIRMED sem olhar o status do vínculo — continuará gravando observações nesses 19 produtos, que nenhuma leitura usa. Inofensivo para a exibição; resolvido quando as identidades forem rejeitadas no ciclo de revinculação.

## Arquivos

| Arquivo | Natureza |
|---|---|
| `3990A_baseline_readonly.sql` | Linha de base (somente leitura) |
| `3990B_containment_DRYRUN_rollback.sql` | Harness: corpo idêntico ao da aplicação, pré-condições, postchecks estruturais e funcionais (3989 como titular), **ROLLBACK** |
| `3990C_containment_APPLY.sql` | Aplicação: mesmo corpo, **COMMIT** (md5 do corpo `c1e24417…` idêntico ao da 3990B) |
| `3990D_containment_REVERSAL.sql` | Reversão exata (REJECTED → CONFIRMED com o run original) |
| `3990E_postcheck_readonly.sql` | Postcheck após a aplicação (estado, 3989, controles, acervo, permissões) |

Ordem: 3990A → 3990B (dry-run) → 3990A (confirma que nada mudou) → autorização → 3990C → 3990E.

## Prevenção (proposta separada, não implementada)

No casamento automático (`_shared/pricing-justtcg-matching/card-matching.ts`), antes de classificar `SAFE`/CONFIRMED por Set + número:

- se o número externo tem total (`N/T`) e `T ≠ collector_total` local **e** o nome diverge → **PENDING** (revisão humana), nunca CONFIRMED;
- se só o total diverge com nome igual (ex.: SV10 046 "Misty's Staryu" 046/180 × 182) → confirma, com o sinal registrado na evidência (diferenças legítimas de total existem);
- se só o nome diverge com total igual → comportamento atual (traduções pt-BR × inglês são a grande maioria dos casos).
Auditoria recorrente: a consulta de "total divergente" do diagnóstico, por Set.

Fora desta rodada: Haunter MEP 027 (correto, preservado), NP 27 (em investigação), SV10 046 (revisão contextual).

## Simulação controlada (2026-11-06, `3990 CONTROLLED SIMULATION-01`)

Executadas no LIVE `qjfutqujxrbzgrtkpgkg`: 3990A → 3990B (ROLLBACK) → 3990A. **3990C NÃO EXECUTADA.**

- **3990A inicial:** 5 vínculos CONFIRMED no estado esperado (run `8d0b204b…`, `confirmed_by` nulo), 19 produtos ativos, 213 observações, 0 aliases/preços manuais/produtos compartilhados; 3989: R$ 808,39 · 25,29 · 28,57 · 55,00 · 22,78 (VARIANT); globais 20.879 vínculos CONFIRMED, 0 REJECTED, 21.688 identidades CONFIRMED, 157.768 produtos, 1.207.079 observações, 294 registros de auditoria.
- **3990B (corpo idêntico ao da 3990C, md5 `49f7f37b…`, mais um bloco final de evidência somente leitura e uma chamada no-op à promoção, antes do ROLLBACK):** todas as pré-condições e postchecks passaram; 5 REJECTED, 5 vínculos tocados no total, 5 registros de auditoria (ator = admin, run original no metadado), `confirmed_at` e evidência preservados, identidades (5 CONFIRMED) / produtos (19 ativos) / observações (213) intactos, Δ CONFIRMED global = 5; 3989 sem preço nas 5 variantes; 3972 sem preço nas 5 cartas; Haunter MEP 027 R$ 215,75 (VARIANT); `batch_update_pricing_card_mapping_status` com CONFIRMED → 0 linhas (vínculos seguem REJECTED).
- **3990A final:** idêntica à inicial (5 CONFIRMED, sem a chave `containment_3990`, preços inalterados, contagens globais iguais, 0 registros de auditoria da 3990); sem transação ociosa, sem bloqueios exclusivos, sem tabelas temporárias remanescentes; 3989 com a mesma definição (md5 `c2411a54…`) e ACL.

## Aplicação no LIVE (2026-11-06 21:40 UTC, `3990C LIVE EXECUTION — AUTHORIZED`) — CONFIRMADO EXECUTADO

- **Precheck:** projeto `qjfutqujxrbzgrtkpgkg`; 5 vínculos e 5 identidades no estado esperado; 3990C íntegra (md5 do arquivo `0a91c61c…`, corpo `49f7f37b…` = 3990B, diferença só `commit`/`rollback`); 1 administrador; nenhum lease de refresh/bootstrap, bloqueio exclusivo ou transação ociosa; 3989/3972 e tabelas com a mesma definição, ACL e RLS.
- **3990C executada sem modificação** (30 s / 5 s); pré-condições e postchecks internos passaram; COMMIT.
- **3990E:** 5 vínculos REJECTED (`confirmed_at` preservado, run original na evidência), 5 registros `PRICING_MAPPING_REJECTED` (ator = admin); vínculos CONFIRMED 20.879 → 20.874, REJECTED 0 → 5, só 5 vínculos alterados; identidades (21.688 CONFIRMED), produtos (157.768 ativos) e as 213 observações dos 5 vínculos intactos — o total global de observações subiu por refresh legítimo de outros Sets; 3989 e 3972 sem preço nas 5 cartas; controles Haunter MEP 027 (R$ 215,75) e ME5.5 002 cotados (VARIANT); sem sessões/bloqueios/temporárias remanescentes; 3989 com a mesma definição (md5 `c2411a54…`) e ACL.
- **Impacto no acervo do titular:** saem do valor estimado os 3 exemplares afetados (Genesect EX R$ 808,39, Gengar R$ 28,57, Scizor ex R$ 22,78 = **−R$ 859,74**); estado após a contenção: **R$ 13.139,78**, 2.946 de 2.955 exemplares com preço, 1.293 de 1.302 grupos cotados (todos os 7 grupos do ME5.5CC agora sem cotação).
