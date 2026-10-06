# LIVE — tentativa da 2237 v1.0 (mappings de finish SOURCE_SET) · Registro de falha

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH13-2237-LIVE-PRE-01` (PRE read-only) · `BATCH13-2237-LIVE-APPLY-01` (execução) · `BATCH13-2237-POST-FINGERPRINT-CORRECTION-01` (correção offline e este registro) |
| **Autorização** | Fabrício: "Autorizo a aplicação LIVE da 2237." — cobria só a 2237 v1.0, PRE JIT, uma execução e POST read-only; em erro, STOP sem retry. **Consumida** por esta tentativa: não vale para a v1.1. |
| **Baseline Git** | HEAD `118f28c45a2ec69e9512975257766941cc1560a2` (`docs(batch13): close 2236 live apply`), árvore e índice limpos |
| **Artefato submetido** | `../2237_forward_fix_b_semantic_finish_mappings.sql` **v1.0**, blob `2673bfc01b4dd6e715edcaf082033d087c6266fb` (8.061 B, md5 `94d130a0dce3d42eb198a9b2e81cae37`) |
| **Canal** | MCP Supabase, projeto `qjfutqujxrbzgrtkpgkg`: `execute_sql` — SELECT para PRE/POST; **uma** chamada com o conteúdo exato do blob, incluindo o `BEGIN`/`COMMIT` do próprio artefato. Não foi `apply_migration`. |
| **Resultado** | **ATTEMPTED / ROLLED BACK / NOT APPLIED** — zero delta LIVE. Não é registro de APPLY PASS. |

Antes do envio, a transcrição do artefato foi gravada em arquivo e comparada ao blob: `git hash-object` idêntico (`2673bfc0…`).

## 1. Sequência

| # | Passo | Momento (servidor, UTC) | Resultado |
|---|---|---|---|
| 1 | PRE read-only (`BATCH13-2237-LIVE-PRE-01`) | 2026-10-06, antes do mandato de execução | PASS |
| 2 | PRE JIT (SELECT) | `2026-10-06 01:34:55` → `01:35:57` | PASS em todos os gates |
| 3 | Execução da 2237 v1.0 (`execute_sql`, uma vez) | logo após o PRE JIT | **erro P0001** — abortada |
| 4 | Verificação de rollback (SELECT) | `01:37:26` | ROLLBACK integral confirmado |
| 5 | Diagnóstico da causa (SELECT) | após o passo 4 | causa isolada (§3) |
| 6 | Prova da lógica corrigida (SELECT, CTE simulada) | `01:42:28` | PASS (§4) |

**Zero retry.** Nenhuma segunda submissão da v1.0, nem de variante dela.

## 2. Erro

```
ERROR: P0001: 2237_POST_EXISTING_CHANGED: mapping pré-existente alterado.
CONTEXT: PL/pgSQL function inline_code_block line 19 at RAISE
```

O gate que falhou é o do PASSO 3 que compara o fingerprint `id → variant_type_id` das rows pré-existentes com o fingerprint PRE (`fm_pre.fp`). Os gates anteriores do PASSO 3 (`2237_POST_DELTA`, `2237_POST_GLOBAL_TOUCHED`) passaram. Como o erro ocorre dentro da transação aberta pelo próprio artefato, o `COMMIT` nunca foi alcançado.

## 3. Causa raiz — gate não null-safe

Na v1.0, as rows "pré-existentes" eram reconhecidas por exclusão da forma dos 2 alvos:

```sql
WHERE NOT (external_set_id IN ('base3', 'sv05')
           AND normalized_subtype IS NULL AND normalized_stamp IS NULL
           AND (normalized_type, normalized_foil) IN (('HOLO','STARLIGHT'), ('REVERSE','GALAXY')))
```

Sobre as 94 rows PRE, esse predicado avalia **92 TRUE / 0 FALSE / 2 NULL**. As 2 rows NULL são mappings **GLOBAL** pré-existentes (`external_set_id IS NULL`, `normalized_foil IS NULL`), para os quais `external_set_id IN (…)` e o `IN` de pares dão NULL, e `NOT (NULL AND …)` continua NULL — a row cai fora do `WHERE`:

| id | Escopo | Combinação normalizada | Destino |
|---|---|---|---|
| `297710a2-7395-4f2a-8953-edac830be2b2` | GLOBAL | `HOLO \| NULL \| NULL \| NULL` | `HOLO` |
| `f5258327-c4b9-41b7-85cc-84bd0f2b2cbe` | GLOBAL | `REVERSE \| NULL \| NULL \| NULL` | `REVERSE_HOLO` |

O fingerprint filtrado das 92 rows é `92f9087517e14384be0addb8f583e34f`, diferente de `fm_pre.fp` = `aba31a17daca8b28a61b1fbeea013e6d` (94 rows). O gate falharia **sempre**, com ou sem as 2 rows novas: defeito do artefato, não alteração real de dado.

## 4. Estado LIVE após o rollback (`01:37:26`, read-only)

- `card_variant_type_external_mapping`: total **94** · GLOBAL **75** · SOURCE_SET **19** — iguais ao PRE.
- Fingerprint `id → variant_type_id` das 94: `aba31a17daca8b28a61b1fbeea013e6d` — igual ao PRE.
- Rows-alvo: base3 `HOLO|STARLIGHT|NULL|NULL` = 0 · sv05 `REVERSE|GALAXY|NULL|NULL` = 0.
- Sem transação aberta nem lock remanescente da tentativa.

**Delta LIVE = zero.**

Prova da lógica corrigida (`01:42:28`, read-only, CTE simulada com as 94 rows PRE + 2 rows sintéticas de forma idêntica aos alvos):

- `fm_pre` com `ids`: n 94 · n_global 75 · ids 94 · fp `aba31a17…`.
- Recálculo LIVE por `id = ANY(ids)`: 94 rows · fp `aba31a17…`.
- Simulação: total 96 · recálculo por `id = ANY(ids)` = 94 · fp `aba31a17…` · 2 rows novas ignoradas · 0 NULL na seleção · as 2 rows GLOBAL `297710a2…` e `f5258327…` mantidas.

## 5. Correção — `2237` v1.1 (PROPOSTA / NÃO EXECUTADA)

- `fm_pre` passa a capturar também `array_agg(id ORDER BY id) AS ids`.
- O gate POST seleciona as rows pré-existentes por `m.id = ANY(f.ids)`: exige contagem = `f.n` (`2237_POST_EXISTING_MISSING`) e fingerprint `IS NOT DISTINCT FROM f.fp` (`2237_POST_EXISTING_CHANGED`). Não depende de set, type ou foil, e é null-safe.
- Semântica inalterada: M1 base3 `HOLO|STARLIGHT|NULL|NULL` → `HOLO`; M2 sv05 `REVERSE|GALAXY|NULL|NULL` → `COSMOS_REVERSE`; +2 SOURCE_SET, +0 GLOBAL; demais gates, `lock_timeout` e `BEGIN`/`COMMIT` mantidos; sem `catalog_admin_action_log`, resolver, constraint ou índice.

## 6. Não-escopo

- `2236`: inalterada — continua APPLIED / PASS; a tentativa não tocou nas tabelas de Edition Context.
- `2831` v3.1: não executada.
- `2213`: não criada.
- B-SEMANTIC LIVE inalterado: NO_PROFILE 0 · NO_EC 11 · FINISH NULL 2 · blocked 13 · determinísticas 272/285.

## 7. Próximos gates

Auditar a candidata v1.1 → publicar → novo PRE LIVE read-only da v1.1 → **nova autorização explícita** de Fabrício → novo APPLY. A autorização de `BATCH13-2237-LIVE-APPLY-01` foi consumida e não pode ser reutilizada.
