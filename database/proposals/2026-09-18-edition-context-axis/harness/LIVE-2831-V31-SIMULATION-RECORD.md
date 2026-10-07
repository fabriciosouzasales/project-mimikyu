# LIVE — simulação da 2831 v3.1 (decomposição das 285 READY_UNCONDITIONED) · Registro

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH13-2831-V31-LIVE-PRE-01` (PRE read-only) · `BATCH13-2831-V31-LIVE-SIMULATION-01` (simulação) · `BATCH13-2831-V31-LIVE-SIMULATION-CLOSEOUT-01` (registro) |
| **Autorização** | Fabrício: "Autorizo a execução LIVE da simulação 2831 v3.1 com ROLLBACK." — cobre **somente** a submissão integral da simulação 2831 v3.1 (blob `65149642…`), que termina em `ROLLBACK`. **Não** autorizou a `2213`, nenhuma migration definitiva, nenhuma versão da 2831 sem `ROLLBACK`, alteração do arquivo, outro SQL mutável, `apply_migration`, Edge, confirmação de staging, nem `git add`/`commit`/`push`. |
| **Baseline Git** | HEAD `05269df47bd2489d5817d7f19f1a8161a8bc286f` (`docs(batch13): close 2237 v1.1 live apply`), parent `9a2d6944`, árvore e índice limpos |
| **Artefato executado** | `../2831_simulate_legacy_decomposition_365.sql` **v3.1**, blob `65149642b18c17d97fc54d5556ccac7032212215` (59.218 B, LF) |
| **Canal** | MCP Supabase, projeto `qjfutqujxrbzgrtkpgkg`: `execute_sql` — SELECT para PRE/POST; **uma** chamada com o conteúdo exato do blob. **Não** foi `apply_migration`. |
| **Resultado** | **EXECUTED / SIMULATION PASS / ROLLED BACK / ZERO PERSISTENT DELTA** — auditoria independente PASS · **Gate A = FINAL PASS** |

Antes do envio, a transcrição do artefato foi gravada em arquivo e comparada ao blob: `git hash-object` = `65149642…` e `cmp` idêntico ao arquivo publicado. O arquivo não foi alterado.

## 1. Contrato estático do artefato

`BEGIN;` 1 · `ROLLBACK;` 1 · `COMMIT` 0 (as 17 ocorrências de `ON COMMIT DROP` não são COMMIT; nenhum COMMIT dentro de bloco `$$`). `ROLLBACK;` é o último statement executável; depois dele só há comentário. UPDATE em `public.card_variant` 1 e em `public.catalog_variant_import_row` 1; INSERT 0 · DELETE 0 · DISABLE TRIGGER 0 · ALTER 0 · TRUNCATE 0. Collision gates antes dos UPDATEs.

## 2. Sequência

| # | Passo | Momento (servidor, UTC) | Resultado |
|---|---|---|---|
| 1 | PRE read-only (`BATCH13-2831-V31-LIVE-PRE-01`) | `2026-10-06 23:32:21` → `23:34:00` | PASS |
| 2 | PRE JIT (SELECT, mesmas fórmulas da PRE-01) | `2026-10-06 23:55:20` → `23:56:41` | PASS |
| 3 | Simulação 2831 v3.1 (`execute_sql`, uma vez, sem retry) | após o PRE JIT | retorno `[]`, sem erro (nenhum SQLSTATE) |
| 4 | POST externo (SELECT) | `2026-10-07 00:00:45` → `00:01:23` | zero delta persistente |

**NOTICE:** o canal **não devolveu** nenhum NOTICE (nem `LINEAGE_SCOPE` nem `2831_SIMULATION_PASS (v3.1)`). Nenhum NOTICE foi observado.

## 3. PRE JIT

- Plano: HOLD 107 · READY_STRUCTURAL 365 · PRICING_CONDITIONED 80 (STAFF_HOLO 40 + SET_LOGO_REVERSE 40) · plano 285 · md5 `a53343fa38bbbe6f45fea7a4dba4bbdb` · plano ∩ HOLD 0 · plano ∩ Pricing 0 · lineage missing 0.
- Genérico: NO_PROFILE 0 · FINISH NULL 0 · NO_EC 11 · bloqueadas 11 · determinísticas 274/285; bloqueadas = 6 `STANDARD_PIKACHU_WORLD_2000` + 4 `STANDARDS_LEAGUE` + 1 `PLAYER_REWARD_REVERSE`.
- HISTORICAL OVERRIDE: H-PIKACHU 6 · H-LEAGUE 4 · H-PLAYER-REWARD 1 · diferença simétrica 0 · finish drift 0 · shape miss 0 · overlap 0. Overlay read-only: 285/285 (bloqueadas 0, EC NULL 0, finish NULL 0).
- Lineage: 336 rows-alvo · 285 Variants · 51 Variants com >1 row · eixos 336/336 · card mismatch 0 · source mismatch 0 · PENDING operacional nas rows-alvo 0 · `LINEAGE_EVIDENCE_DIVERGENT` 0 · VALID sem chave de printing 0 · já reconciliadas 0 · `LINEAGE_INTRA_TARGET_COLLISION` 0 · `LINEAGE_STAGING_COLLISION` 0.
- Colisões / idempotência: NEW_IDENTITY 0 · INTRA_PLAN 0 · PRINTING_DRIFT 0 · Variants já decompostas 0.
- Referências de negócio às 285: `physical_card` 0 · `collection_master_set_scope` 0 · `collection_layout_slot_expected_content` 0 · `pricing_product` 0.
- Concorrência: locks de outras sessões nas 4 tabelas 0 · locks em espera 0 · xid 0 · clientes ativos 0 · migration/apply concorrente 0.
- Fingerprints PRE: `card_variant` 24.893 · `resulting` 23.955 · `matched` 1.193 · rows fora do lineage-alvo 25.903 / `d801514d9c60e0c5923c6578ca7fceff` · Variants fora do plano 24.608 / `dd7108a9282b39062271c447fc8b6c82` · plano `d2722ba677a641fb95c5c6e4b59120e9` · destino `8bffe89c161f5e9448c1d25db6fcd297` · lineage-alvo `bb87fe1c5c830d8e625d492af58f5daf`.

## 4. Gates dentro da simulação

O canal não expôs os NOTICEs internos. O artefato, porém, é fail-loud: toda divergência antes ou depois dos UPDATEs gera `RAISE EXCEPTION` e aborta a transação. A chamada terminou **sem exception**. Por consequência — e não por NOTICE observado — nenhum destes gates abortou:

- cardinalidades (plano 285, âncora md5, `PLAN_READY_CARDINALITY`);
- gates de forward-fix, B_SEMANTIC_RESIDUAL, regras 6/4/1, D1, D4;
- collision gates (card_variant e staging);
- `CV_UPDATE_COUNT` (UPDATE `card_variant` = 285) e `LINEAGE_UPDATE_COUNT` (UPDATE lineage = 336 rows-alvo);
- L1 · L2 · L3 · L4 · L8 · L9;
- HOLD_VIOLADO e PRICING_CONDITIONED_VIOLADO.

A execução alcançou o `ROLLBACK` final do próprio blob.

## 5. POST — zero delta persistente

| Medida | PRE | POST |
|---|---|---|
| `card_variant` | 24.893 | 24.893 |
| rows com `resulting_variant_id` | 23.955 | 23.955 |
| rows com `matched_variant_id` | 1.193 | 1.193 |
| rows fora do lineage-alvo | 25.903 / `d801514d…` | 25.903 / `d801514d…` |
| Variants fora do plano | 24.608 / `dd7108a9…` | 24.608 / `dd7108a9…` |
| snapshot do plano | `d2722ba6…` | `d2722ba6…` |
| snapshot de destino | `8bffe89c…` | `8bffe89c…` |
| snapshot do lineage-alvo | `bb87fe1c…` | `bb87fe1c…` |

- Plano 285, md5 `a53343fa…`; `edition_context_profile_id` não-NULL no plano 0 (e em toda a `card_variant` 0).
- Genérico persistente: 274/285, bloqueadas 11 (6/4/1), NO_EC 11, FINISH NULL 0.
- Lineage: 336 rows-alvo no estado PRE, reconciliadas persistentemente 0, `resulting` preservado, híbrido L2 0.
- Sem transação residual: locks 0 · xid 0 · idle in transaction 0.

**ZERO PERSISTENT DELTA.** O estado persistente continua 274/285; o 285/285 foi provado **somente** dentro da transação simulada.

## 6. D1 HOLD-safe intacto

| Row | Estado (PRE = POST) | md5 da row |
|---|---|---|
| BASE2 #60 | job STAGED · NEEDS_REVIEW / PENDING / PENDING · `resulting` NULL · `matched` NULL · fora do plano e do lineage-alvo | `a0acad95ae681cc607144681e42c718f` |
| BASEP #24 | job COMPLETED · fora do plano | `bd9d0118b2502f636b0d1d83dae31979` |

Mapping `PIKACHU-TAIL` = 0.

## 7. Forward-fixes intactos (pós-rollback)

traits 116 · profiles 175 · profile_trait 246 · EC mappings 122 · EC mapping links 122 · finish mappings 96 (GLOBAL 75 · SOURCE_SET 21) · alvos da `2237` 2.

## 8. Gate A — FINAL PASS

Auditoria independente do relatório: PASS. Fundamento: plano 285 preservado; 285/285 destinos determinísticos na camada simulada; HISTORICAL OVERRIDE 6/4/1 exato; collision gates 0; lineage de 336 rows coerente com as 285; simulação fail-loud terminou sem exception; L1/L2/L3/L4/L8/L9 não abortaram; `ROLLBACK` do próprio artefato; POST externo prova zero delta persistente.

**Limite:** Gate A PASS **não é** autorização da `2213`. A `2213` está **NÃO CRIADA / NÃO AUTORIZADA**.

## 9. Próximos gates

Publicar este closeout → especificar/preparar a `2213` → auditoria independente da `2213` → mandato próprio futuro (PRE JIT, autorização explícita) para qualquer execução.

## 10. Proibições remanescentes

Sem novo mandato: nenhuma execução da `2213` nem de qualquer versão da `2831` sem `ROLLBACK`; nenhuma reexecução da simulação; nenhuma edição dos artefatos `2236`/`2237`/`2831` nem dos registros históricos; nenhum Edge deploy ou confirmação de staging.
