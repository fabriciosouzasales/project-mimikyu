# LIVE — aplicação da 2236 (catálogo de Edition Context, B-SEMANTIC D1/D2) · Registro

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH13-2236-LIVE-PRE-01` (PRE read-only) · `BATCH13-2236-LIVE-APPLY-01` (execução) · `BATCH13-2236-LIVE-APPLY-CLOSEOUT-01` (registro) |
| **Autorização** | Fabrício: "Autorizo a aplicação LIVE da 2236." — cobre só a 2236, PRE JIT, uma execução e POST read-only. Não cobre `2237`, `2831`, `2213`, Edge, confirmação de staging, nenhum outro SQL mutável, nem `git add`/`commit`/`push`. |
| **Baseline Git** | HEAD `432c613f8e7451f0db1c73c25f9ef87998ce51eb` (`fix(batch13): prepare B-semantic remediation and 2831 v3.1`), parent `ffd22543`, árvore e índice limpos |
| **Artefato executado** | `../2236_forward_fix_b_semantic_edition_context_catalog.sql` blob `d3acb58140612ce0207390748148cb28b1fe27b1` (26.417 B, md5 `bbaf8c355e4cad5c258d618184a55325`). Registrados, **não** executados: `2237` blob `2673bfc0…`, `2831` v3.1 blob `65149642…` |
| **Canal** | MCP Supabase, projeto `qjfutqujxrbzgrtkpgkg`: `execute_sql` — SELECT para PRE/POST; **uma** chamada com o conteúdo exato do blob, incluindo o `BEGIN`/`COMMIT` do próprio artefato. **Não** foi `apply_migration` (ledger não registra a 2236 — rastreabilidade, não "não executada"). |
| **Resultado** | **APPLIED / PASS** — auditoria independente PASS |

Antes do envio, a transcrição do artefato foi gravada em arquivo e comparada ao blob: md5 e `git hash-object` idênticos (`d3acb581…`). O SQL permanece inalterado no repositório, inclusive o cabeçalho "PROPOSTA — NÃO EXECUTADA": o estado posterior vive neste registro, não no artefato aplicado.

## 1. Sequência

| # | Passo | Momento (servidor, UTC) | Resultado |
|---|---|---|---|
| 1 | PRE read-only (`BATCH13-2236-LIVE-PRE-01`) | `2026-10-06 00:04:48` → `00:06:59` | PASS |
| 2 | Checagem da convenção do selo (SELECT) | antes do PRE JIT | 48/48 assinaturas compostas existentes ordenadas por uuid — a mesma que o gate POST da 2236 assume |
| 3 | PRE JIT (SELECT, sem CREATE TEMP) | `00:33:45` → `00:35:31` | PASS |
| 4 | Execução da 2236 (`execute_sql`, uma vez, sem retry) | objetos com `created_at = 2026-10-06 00:39:00.38976+00` | retorno `[]`, sem erro |
| 5 | POST (SELECT) | `00:39:58` e `00:40:26` | PASS |

O `RAISE NOTICE` final da 2236 não foi devolvido pelo canal. Os gates fail-loud internos (PASSO 1 e PASSO 4, por `RAISE EXCEPTION`) não abortaram, e o POST externo, lido em sessão separada, confirma o `COMMIT`.

## 2. PRE JIT

- Referências: Game `POKEMON` = 1 · asset_source `TCGDEX` = 1.
- Idempotência: trait `CAMPAIGN_PIKACHU_WORLD_2000` = 0 · profiles-alvo (1 D1 + 30 D2) = 0 · mapping `PIKACHU-TAIL` = 0.
- Slots: CAMPAIGN 140 livre · profiles 1450–1750 livres.
- Forma D2 (CTE literal extraída do blob): 30 assinaturas · 49 links · 11 de aridade 1 · 19 de aridade 2 · 0 violação da regra de code · 0 duplicata.
- Traits D2: 18 distintos · 0 ausentes, inativos ou sem termo `(en)`.
- Assinaturas existentes com qualquer das 30: 0.
- Cobertura: 33 Variants · 30 tipos legados · soma declarada 33 · 0 divergência por tipo · 0 sem lineage · 0 divergência de resolução/assinatura · 30 assinaturas cobertas.
- Rows `pikachu-tail`: 8, todas `RESOLVED_NO_EDITION_CONTEXT`, profile NULL, residual `{PIKACHU-TAIL}`.
- Counts: traits 115 · profiles 144 · links 196 · external mappings 122 · links de mapping 122.
- Blast radius: 62 rows passariam a encontrar profile D2; 0 PENDING em job operacional (as 5 PENDING são de jobs CANCELLED). A 2236 não escreve em nenhuma row de staging.
- Concorrência: 0 locks de outras sessões nas 5 tabelas-alvo · 0 locks em espera · 0 xid de escrita · 0 query/migration concorrente.

## 3. POST

| Tabela | PRE | POST | Delta |
|---|---:|---:|---:|
| `card_edition_context_trait` | 115 | 116 | +1 |
| `card_edition_context_profile` | 144 | 175 | +31 |
| `card_edition_context_profile_trait` | 196 | 246 | +50 |
| `card_edition_context_external_mapping` | 122 | 122 | 0 |
| `card_edition_context_external_mapping_trait` | 122 | 122 | 0 |

Objetos criados:

- Trait `CAMPAIGN_PIKACHU_WORLD_2000`: família CAMPAIGN, ordem 140, ativo, nome "Pikachu World Collection 2000".
- Profile D1 `CAMPAIGN_PIKACHU_WORLD_2000`: aridade 1, ordem 1450.
- 30 profiles D2: 11 de aridade 1 + 19 de aridade 2, ordens 1460–1750.
- 50 links novos (1 + 11 + 19×2).
- Nos 31 profiles: assinatura NULL = 0 · assinatura × N:N divergente = 0 · code × traits divergente = 0 · nome/descrição fora da regra da `2231` = 0. Grupos de assinatura duplicada no catálogo inteiro = 0.

## 4. D2 — prova LIVE

As 33 Variants consumidoras resolvem agora `RESOLVED_WITH_EC_PROFILE` = **33/33**, comparadas uma a uma contra o profile esperado: divergências de estado = 0 · divergências de profile = 0.

## 5. D1 — HOLD-safe após aplicação

- Mapping `PIKACHU-TAIL` = 0.
- Rows `pikachu-tail` = 8: `RESOLVED_NO_EDITION_CONTEXT` 8/8 · `edition_context_profile_id` NULL 8/8 · residual `{PIKACHU-TAIL}` 8/8.

| Row | Raw | Variant | Job | validation / decision / persistence |
|---|---|---|---|---|
| BASEP #01, #04, #25, #26, #27, #28 (lineage-alvo) | normal | sim (`STANDARD_PIKACHU_WORLD_2000`) | COMPLETED | VALID / APPROVED / INSERTED |
| BASEP #24 | holo | não | COMPLETED | NEEDS_REVIEW / SKIPPED / UNCHANGED |
| BASE2 #60 | normal | não | STAGED | NEEDS_REVIEW / PENDING / PENDING |

BASE2 #60 **não** foi resolvida: continua sem Variant e sem Edition Context por `PIKACHU-TAIL`.

## 6. Não-escopo

- Estáveis antes/depois: `card_variant` 24.893 · `catalog_variant_import_row` 26.239 · `catalog_variant_import_job` 147 · `card_variant_type_external_mapping` 94.
- `2237` **não aplicada**: base3 `HOLO|STARLIGHT|NULL|{}` = 0 · sv05 `REVERSE|GALAXY|NULL|{}` = 0.
- `2831`: não autorizada, não executada.
- `2213`: não criada.

## 7. Efeito real até aqui (fato × projeção)

- **Fato LIVE:** NO_PROFILE das 285 = 33 → 0 (as 33 Variants D2 resolvem seu profile).
- **Ainda não fato:** FINISH NULL = 2 depende da `2237`, não aplicada; os 11 NO_EC continuam e só se fecham na camada histórica da `2831` v3.1.
- O funil 46 → 11 → 0 continua **projeção**; nenhuma prova genérica de B-SEMANTIC = 11 foi feita no LIVE.

## 8. Próximos gates

Publicar este closeout → PRE read-only da `2237` → mandato próprio para a `2237` → POST → só então provar B-SEMANTIC genérico = 11 → PRE JIT da `2831` v3.1 → só então considerar autorizar a simulação (com `ROLLBACK`). `2213` continua posterior ao Gate A.

## 9. Proibições remanescentes

Sem novo mandato: nenhuma execução da `2237`, `2831` ou `2213`; nenhuma reexecução da `2236` (é fail-closed e abortaria em `2236_ALREADY_APPLIED`); nenhum mapping `PIKACHU-TAIL`; nenhum Edge deploy ou confirmação de staging; nenhuma edição do artefato `2236` aplicado.
