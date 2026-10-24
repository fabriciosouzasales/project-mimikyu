# BINDER-PHYSICAL-LOCATION — evidência da Fase A no LIVE (LIVE-PHASE-A-EXECUTION-01)

| | |
|---|---|
| Data | 2026-10-24, 12:08–12:25 UTC |
| Projeto | `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`), PostgreSQL 17.6, ACTIVE_HEALTHY |
| Autorização | Fabrício, expressa: migrations 5247–5255 + LIVE_50. Nenhuma outra escrita. |
| Executor | agente, via MCP `apply_migration` (uma chamada por migration) |
| Resultado | **Fase A CONFIRMADO EXECUTADO — 9/9 aplicadas; LIVE_50 PASS** |
| Não executado | 5256, harness 5854, R0/R1/R2A/R2B, deploy, git |

## 1. Gate de entrada (todas as leituras em `begin transaction read only; set local statement_timeout = '30s'`)

| Verificação | Resultado |
|---|---|
| Projeto correto | `mimikyu-core`, ACTIVE_HEALTHY, PG 17.6 |
| Janela sem uso | p11 = true; 0 outras sessões ativas/idle in transaction; última escrita em posições 01:56 UTC, em exemplares 23:14 UTC (dia anterior) |
| Ledger | nenhuma linha 5247–5256; ponta 5246 (`20261024002445`) |
| Arquivos | 9 arquivos, ordem 5247→5255, cada um com um único `begin;`/`commit;` e sem `begin/commit/rollback` internos |
| Limites | `lock_timeout 5s` próprio em 5247/5248/5249/5255 (e nas funções escritoras); `statement_timeout` padrão do servidor 30 s; 5250–5254 só criam/substituem funções (risco 6 do plano, aceito) |

Convenção de aplicação (precedente 5246): o texto enviado ao `apply_migration` é o corpo estritamente entre `begin;` e `commit;` do arquivo — o próprio `apply_migration` dá a transação atômica e grava o ledger. Cabeçalhos e blocos de validação comentados após `commit;` não são enviados.

## 2. Migrations (cada uma verificada antes da seguinte)

O md5 do texto gravado no ledger (`btrim` de espaços/quebras) foi comparado ao md5 do corpo do arquivo: **idênticos nas 9**.

| # | Ledger | md5 do corpo = ledger | Verificação pós-aplicação |
|---|---|---|---|
| 5247 | `20261024120931` | `db44b9db…e146` | 2/2 fichários com local; 2 gatilhos novos; `layout_md5` inalterado |
| 5248 | `20261024121040` | `5f7b4b59…efaa` | 155 posições, 155 exemplares distintos, 0 nulas; `assignments_md5` e `layout_md5` inalterados |
| 5249 | `20261024121212` | `d7456777…209b` | 4 funções novas; 5024/5222 intactas |
| 5250 | `20261024121312` | `842d80bf…22ce2` | `place_my_physical_card_in_slot` criada |
| 5251 | `20261024121421` | `cc87d51c…511b5a` | plano v2 ativo |
| 5252 | `20261024121613` | `fad9adda…7b46` | leituras novas + leitura de 3 args presente |
| 5253 | `20261024121715` | `d9a3a70c…31aa` | desassociação na versão 5253 |
| 5254 | `20261024121820` | `213f1a35…f18a` | `transfer_my_binder_ownership` criada |
| 5255 | `20261024121921` | `07e73554…c60b` | associação/candidatos pelo local do fichário |

Nenhum erro, nenhum precheck interno abortou, nenhum retry.

## 3. LIVE_50 (1ª execução, READ ONLY, 30 s)

**Consulta 1:** q01–q09 = **true** (9/9) — ledger 9, 5256 ausente, contratos antigos e novos presentes, posições dentro do local, layout F001 no local F001, backfill íntegro, ACL das 7 RPCs novas, 27 disponíveis em F001.

**Consulta 2 × LIVE_00:**

| item | LIVE_00 | LIVE_50 |
|---|---|---|
| assignments | 155 | 155 |
| `assignments_md5` | `63e36528f57559f281230abb90fab5fe` | **igual** |
| `layout_md5` | `b0906e79695b8a049b9120d99d4f7079` | **igual** |
| `allocations_md5` | `a180e923764e3b5a9cb225ee68f873c0` | **igual** |
| reservations | 158 | 158 |
| slot_images | 0 | 0 |
| regions | 1 | 1 |

**Confirmações adicionais (leitura):** layouts 2 · guests 1 · páginas 25 · bolsos 232 · travados 0 · alocações 211 · imagens de região 1 · exemplares em F001 182 · posições duplicadas por exemplar 0 · por bolso 0 · fichários no mesmo local 0 · posições de exemplar de outro dono 0 · nenhuma escrita em `physical_card`, posições ou alocações durante a janela (timestamps máximos iguais aos do gate).

## 4. Estado resultante

Expand concluído: o LIVE aceita o frontend atual e o novo. Próximo passo do plano (requer nova autorização): deploy do frontend → homologação → LIVE_50 (2ª) → 5256 → LIVE_90. Promoção para `database/schema/` só após o passo 8.
