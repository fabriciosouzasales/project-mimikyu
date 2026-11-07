# V1-14 R1-G — localização física e desempenho

Origem: `R1-G — PERFORMANCE & LOCATION DESIGN APPROVAL-01` (2026-11-07). **Query 5354 CONFIRMADA EXECUTADA no LIVE em 2026-11-07 00:01 UTC** (ver "Aplicação no LIVE" no fim). Os harnesses 5881 e 5882 só rodaram em transação com ROLLBACK. O cabeçalho do arquivo `.sql` ainda diz "PROPOSTO — NÃO EXECUTADO" porque o conteúdo aplicado tinha de ser byte a byte o aprovado; a promoção do arquivo para `database/` (com status atualizado) fica para o ciclo do commit.

| Arquivo | Natureza |
|---|---|
| `5354_create_get_my_inventory_group_locations_PROPOSAL.sql` | RPC somente leitura, em lote, uma linha por grupo variante + idioma com a distribuição dos exemplares por local (recipiente, quantidade, páginas do fichário) |
| `5881_validate_get_my_inventory_group_locations_HARNESS.sql` | Harness em transação com ROLLBACK: segurança (S1–S3), isolamento entre titulares (I3), conciliação com os exemplares (I1/I2), ids inexistentes (I4), ordem (I5), desempenho (P1) |

## Evidências coletadas (somente leitura)

**Banco, isolado (titular simulado, 2026-11-07):** 5160 = 645 ms; 5159 = 14 páginas de 22–99 ms; 3989 = 14 blocos (1.302 variantes) de 427–1.436 ms (≈ 7,9 s em série, ≈ 4,3 s com 2 simultâneos).

**API (logs do gateway, `edge_logs`, tempo de origem por chamada):**

| Minuto (UTC) | Chamadas 5159 | origem média / máx. | Chamadas 3989 | origem média / máx. |
|---|---|---|---|---|
| 2026-11-06 22:49–22:50 (1 leitura) | 7 + 5 | 0,2–0,5 s / 1,6 s | 7 + 5 | 0,4–0,6 s / 1,2 s |
| 2026-11-06 22:54–22:55 (2 leituras simultâneas) | 14 + 14 | **1,2 s e 4,6 s / 7,4 s** | 11 + 14 | **3,4 s e 4,6 s / 8,7 s** |
| 2026-11-06 22:00 | — | — | 13 | 4,4 s / 10,1 s (1 erro) |
| 2026-11-06 22:11–22:12 | 29 + 28 | 0,3–0,4 s / 1,1 s | 29 + 28 | 0,7–0,8 s / 2,2 s |

Leitura: 28–29 chamadas por minuto de cada RPC = **duas leituras completas do relatório** (14 + 14), confirmando a chamada em dobro (`reactStrictMode: true` + `useEffect` de carga). Com as duas simultâneas (até 12 páginas da 5159 e 4 blocos da 3989 ao mesmo tempo), a 5159 sai de ~50 ms para até 7,4 s e a 3989 para até 8,7 s — **contenção no banco**. Soma das ondas: 5159 (3 ondas × 5–7 s) + 3989 (7 ondas × ~4,6 s) ≈ 45–55 s, compatível com os POSTs de 32 s e 56 s.

**Localização:** nos 448 grupos repetidos do titular, 444 têm exemplares em 2+ lugares (máx. 3), 4 sem local; 442 exemplares com página de fichário. Protótipo da consulta da 5354 sobre o acervo inteiro (2.955 exemplares): **≈130 ms** de execução.

**Miniaturas:** `card-front` tem 31.527 imagens, média 100 KB (p90 105 KB) → 448 ≈ 45 MB para imprimir. Transformação do Storage **disponível** (HTTP 200 em `/render/image/public/...`): `me2/en/001.webp` original 43.664 bytes; transformado `width=48&height=67&resize=cover&quality=60` = **7.940 bytes** (PNG, pedido sem `Accept: image/webp`; o navegador recebe WebP, menor), ~0,9–1,5 s na primeira geração (cache MISS), depois CDN. Custo: cota Pro de 100 imagens de origem/mês, depois US$ 5 por 1.000 imagens de origem (1 imagem de origem usada neste teste).

## Harness 5881 — execução controlada (2026-11-06 23:37 UTC, `QUERY 5354 READINESS & HARNESS 5881-01`)

Executado no LIVE `qjfutqujxrbzgrtkpgkg` em transação única terminada em **ROLLBACK** (2 execuções: harness íntegro; harness + bloco final de evidência somente leitura). Corpo da 5354 inserido no lugar do `\ir`, conforme instrução do próprio harness; nenhum outro trecho alterado. **5354 NÃO aplicada.**

- **S1–S3, I1–I5: PASS** (nenhuma exceção `Q5881_*`).
- **P1:** 448 variantes repetidas → 448 grupos, execução **18,6 ms** (174 buffers em cache).
- **Conciliação:** 448 grupos pedidos = 448 esperados = 448 devolvidos; 2.101 exemplares; Σ locais = exemplares em todos os grupos. Teste de 500 variantes (limite): 500 grupos esperados = 500 devolvidos — sem truncamento na função.
- **Distribuição:** 431 grupos com 2 locais, 13 com 3, 4 com 1; 65 grupos têm exemplares sem local (103 exemplares, sempre por último); 443 entradas de fichário, 442 com página (1 exemplar no fichário físico sem posição no digital — sem página, como esperado); nenhuma página em recipiente que não seja fichário.
- **Idiomas:** todos os grupos repetidos atuais são pt-BR — o caminho multi-idioma está coberto pela chave (variante, idioma) e por I1, mas não por dado real.
- **Isolamento (I3):** o 2º titular (inventário sem exemplares) pedindo as variantes do 1º não recebe nenhuma linha nem recipiente do 1º. Limitação: nenhum outro titular do LIVE tem exemplares; o cenário "dois titulares com exemplares das mesmas variantes" não foi exercido com dado real.
- **Pós-ROLLBACK:** função inexistente, 0 transações ociosas, 0 bloqueios em espera, 0 tabelas temporárias; contagens de exemplares, recipientes e posições inalteradas. Efeito externo: só o `NOTIFY pgrst` do `pgrst_ddl_watch`, transacional (descartado no ROLLBACK).

## Restrição de custo incremental zero (2026-11-07, `ZERO INCREMENTAL COST CORRECTION-01`)

A transformação de imagens do Storage fica **suspensa** (cobrança por imagem de origem acima da cota). Verificado: não existem miniaturas na infraestrutura (`card_asset` só tem `CARD_FRONT`, 31.517 ativos, ~100 KB; nenhum bucket de miniaturas; nenhuma URL externa); objetos do `card-front` com `Cache-Control: max-age=3600`. A 5354 é SQL comum (sem extensão nem serviço novo; 18,6 ms) e roda na instância atual sem recurso faturável adicional.

## Harness 5882 — gate final de isolamento e idiomas (2026-11-07, `QUERY 5354 FINAL SECURITY GATE-01`)

`5882_synthetic_isolation_languages_HARNESS.sql` executado no LIVE em transação única com **ROLLBACK**, dados 100% sintéticos (corpo da 5354 inalterado, md5 `39747031…`). **T1a, T1b, T1c e T2: PASS.**

- **Dois titulares, mesma variante:** A recebeu só os próprios exemplares (pt-BR 1 no Fichário, p. 14; en 2 = ETB 1 + sem local 1), sem nenhum recipiente, nome "Q5882 B" ou página de B. B recebeu exatamente o cenário sintético (pt-BR 3 = "Q5882 B ETB" 2 + "Q5882 B Fichário" 1 p. 7; en 2 = ETB 1 + sem local 1), sem recipiente ou página de A. Σ locais = exemplares nos dois.
- **Mesma variante em dois idiomas:** uma linha por (variante, idioma) para cada titular, contagens e locais independentes, sem duplicação (copies = exemplares físicos por idioma), total = exemplares da variante.
- **Pós-ROLLBACK:** contagens de exemplares, recipientes, coleções, fichários, páginas, bolsos, alocações, posições e marcadores iguais às de antes; 0 linhas "Q5882"; função inexistente; impressão digital de permissões das funções `public` idêntica (`e67e299a…`); 0 transações ociosas, 0 bloqueios em espera, 0 tabelas temporárias. Efeitos externos: nenhum (só `NOTIFY pgrst`, transacional, descartado).

## Aplicação no LIVE (2026-11-07, `QUERY 5354 LIVE APPLY-01`)

- **Quando / onde:** 2026-11-07 00:01:43 UTC (versão no ledger `20261107000143`, nome `5354_create_get_my_inventory_group_locations`), projeto `qjfutqujxrbzgrtkpgkg` (mimikyu-core, sa-east-1, PG 17.6). Transação única do `apply_migration`; nenhuma outra migration aplicada.
- **Conteúdo aplicado = arquivo aprovado:** md5 `3974703177e04f00953892063bb625a6`, sha256 `da681a7c52f818990446f3075f1aac1aadf213b8bb32c8a02e068a82b82db758` (6.910 bytes). Conferido no ledger: md5 das instruções gravadas = md5 do arquivo; md5 do corpo da função (`prosrc`, 3.095 caracteres) = md5 do trecho entre `$$` do arquivo (`8fa18f0d…`).
- **Precheck (antes da escrita), tudo conforme:** projeto correto; hashes iguais aos aprovados; função inexistente; impressão digital de permissões das 487 funções `public` = `e67e299a…`; sem DDL em andamento, transação ociosa ou bloqueio em espera; RLS de `physical_card` ativa; policy de `language` inalterada; 5354 ausente do ledger; ACL padrão do `postgres` no schema `public` = só `postgres=X`.

**Postcheck — todos PASS:**

| Verificação | Resultado |
|---|---|
| Assinatura | `get_my_inventory_group_locations(uuid[])` → `TABLE(card_variant_id uuid, language_code text, copies integer, locations jsonb)`, plpgsql, STABLE, dono `postgres`, comentário gravado |
| SECURITY DEFINER / search_path | `prosecdef = true`, `proconfig = {search_path=""}` |
| Permissões | ACL `{postgres=X/postgres,authenticated=X/postgres}` (igual às 5159/3989/5162); EXECUTE: authenticated sim; anon não (chamada real → 42501); PUBLIC não; service_role não |
| Sem sessão | 28000 |
| Entrada inválida | null, `{}`, 2 dimensões, 501 ids → 22023; ids inexistentes → 0 linhas |
| Titular | 448 variantes repetidas → 448 grupos (448 esperados), 2.101 exemplares; conciliação por (variante, idioma) com `physical_card`: 0 divergências; Σ locais = exemplares e "sem local" por último em todas as linhas; 0 chaves duplicadas; 0 recipientes fora do inventário do titular |
| Outro titular | pedindo 375 variantes do titular principal → 0 linhas (não tem exemplares; o cenário com exemplares nos dois lados está coberto pela 5882) |
| Variante + idioma | uma linha por chave; no LIVE os repetidos são todos pt-BR (multi-idioma provado pela 5882) |
| Desempenho | EXPLAIN ANALYZE com as 448 variantes: 23,5 / 16,9 / 16,7 ms (harness: 18,6 ms) |
| Nada mais mudou | 488 funções `public` (487 + 1); impressão digital das outras 487 = `e67e299a…` (idêntica à da precheck); dados idênticos (exemplares 2.955, recipientes 10, coleções 10, fichários 5, páginas 226, bolsos 2.496, alocações 724, posições 711, marcadores 6); RLS de `physical_card` ativa; 73 policies em `public` |
| Sessão | 0 transações ociosas, 0 bloqueios em espera, 0 chamadas ativas; ledger com 5354 logo após a 3989 |

Referências: harness 5881 (segurança, conciliação e desempenho, com ROLLBACK) e harness 5882 (isolamento entre titulares e idiomas, sintético, com ROLLBACK), nesta pasta. Pricing, 3989, 3990 e JustTCG não foram tocados. **A 5354 está pronta para ser consumida pelo R1-G**; a implementação do R1-G ainda não começou.
