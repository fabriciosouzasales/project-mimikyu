# LIVE — aplicação da 2237 v1.1 (mappings de finish SOURCE_SET) · Registro

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH13-2237-V11-LIVE-PRE-01` (PRE read-only) · `BATCH13-2237-V11-LIVE-APPLY-01` (execução) · `BATCH13-2237-V11-LIVE-APPLY-CLOSEOUT-01` (registro) |
| **Autorização** | Fabrício: "Autorizo a aplicação LIVE da 2237 v1.1." — explícita e posterior ao novo PRE read-only da v1.1. Cobre só a v1.1 (blob `3ddc54f1…`), PRE JIT, uma execução e POST read-only. Não cobre `2831`, `2213`, Edge, confirmação de staging, nenhum outro SQL mutável, nem `git add`/`commit`/`push`. A autorização da v1.0 havia sido consumida pela tentativa abortada e **não** foi reutilizada. |
| **Baseline Git** | HEAD `9a2d6944c2a663a293d1f23ad06fbf9f7ba08315` (`fix(batch13): harden 2237 post fingerprint gate`), parent `118f28c4`, árvore e índice limpos |
| **Artefato executado** | `../2237_forward_fix_b_semantic_finish_mappings.sql` **v1.1**, blob `3ddc54f11e78dd4fa1d03c127ba8094a85900d82` (9.537 B) |
| **Canal** | MCP Supabase, projeto `qjfutqujxrbzgrtkpgkg`: `execute_sql` — SELECT para PRE/POST; **uma** chamada com o conteúdo exato do blob, incluindo o `BEGIN`/`COMMIT` do próprio artefato. **Não** foi `apply_migration`. |
| **Resultado** | **APPLIED / PASS** — auditoria independente PASS |

Antes do envio, a transcrição do artefato foi gravada em arquivo e comparada ao blob: `git hash-object` = `3ddc54f1…` e `cmp` idêntico ao arquivo do repositório. O SQL permanece inalterado no repositório (cabeçalho "PROPOSTA — NÃO EXECUTADA · Versão 1.1"): o estado posterior vive neste registro, não no artefato aplicado.

## 0. Relação com a v1.0

A v1.0 (blob `2673bfc0…`) foi submetida uma vez em 2026-10-06 e abortou no gate `2237_POST_EXISTING_CHANGED` (P0001), com ROLLBACK integral e zero delta LIVE — **ATTEMPTED / ROLLED BACK / ZERO LIVE DELTA / SUPERSEDED**. Registro histórico, não alterado: `LIVE-2237-FAILED-ATTEMPT-RECORD.md`. A v1.1 corrige apenas o gate POST de fingerprint (conjunto PRE identificado por `id = ANY(fm_pre.ids)`, null-safe); alvos, escopo e demais gates são os mesmos.

## 1. Sequência

| # | Passo | Momento (servidor, UTC, 2026-10-06) | Resultado |
|---|---|---|---|
| 1 | PRE read-only da v1.1 (`BATCH13-2237-V11-LIVE-PRE-01`) | `02:22:46` → `02:24:07` | PASS |
| 2 | PRE JIT (SELECT) | `02:37:28` → `02:38:20` | PASS |
| 3 | Execução da 2237 v1.1 (`execute_sql`, uma vez, sem retry) | rows com `created_at = 2026-10-06 02:38:59.15009+00` | retorno `[]`, sem erro |
| 4 | POST (SELECT) | `02:39:33` → `02:40:44` | PASS |

O `RAISE NOTICE` final da 2237 não foi devolvido pelo canal. Os gates fail-loud internos (PASSO 1 e PASSO 3, por `RAISE EXCEPTION`) não abortaram, e o POST externo, lido em sessão separada, confirma o `COMMIT`.

## 2. PRE JIT

- Mappings: total 94 · GLOBAL 75 · SOURCE_SET 19 · fingerprint `aba31a17daca8b28a61b1fbeea013e6d` · rows-alvo 0 (rollback da v1.0 íntegro).
- Referências: Game `POKEMON` 1 · `TCGDEX` 1 · `HOLO` 1 · `COSMOS_REVERSE` 1. Scope: BASE3 → base3 = 1 · SV5 → sv05 = 1.
- Colisão scoped 0/0 · global 0/0. Lookup no set NULL/NULL · com `card_set_id` NULL NULL/NULL.
- Snapshot dos ids PRE: 94 ids, 94 distintos, md5 dos ids `cc4b339a5911d1e019f8a54be865e7ba`; recálculo por `id = ANY(ids)` = 94 rows, fp `aba31a17…`. As 2 GLOBAL `HOLO|NULL|NULL|NULL → HOLO` (`297710a2…`) e `REVERSE|NULL|NULL|NULL → REVERSE_HOLO` (`f5258327…`) incluídas.
- Plano: HOLD 107 · READY 365 · PRICING_CONDITIONED 80 (STAFF_HOLO 40 + SET_LOGO_REVERSE 40) · plano 285 · md5 `a53343fa38bbbe6f45fea7a4dba4bbdb` · lineage missing 0.
- B-SEMANTIC: NO_PROFILE 0 · NO_EC 11 · FINISH NULL 2 · blocked 13 · determinísticas 272/285. Os 2 FINISH NULL: PRERELEASE_HOLO BASE3 #01 (`EVENT_PRERELEASE`, `HOLO|STARLIGHT|NULL|{}`) e GAMESTOP_HOLO SV5 #119 (`CHANNEL_GAMESTOP`, `REVERSE|GALAXY|NULL|{}`).
- Blast radius: 3 rows; 0 PENDING em job operacional (a única PENDING é de job CANCELLED).
- Concorrência: 0 locks de outras sessões nas 3 tabelas · 0 locks em espera · 0 xid de escrita · 0 query/migration concorrente.

## 3. POST — mappings

| Escopo | PRE | POST | Delta |
|---|---:|---:|---:|
| Total | 94 | 96 | +2 |
| GLOBAL | 75 | 75 | 0 |
| SOURCE_SET | 19 | 21 | +2 |

| Row | id | Escopo | Combinação (external = normalized) | Destino |
|---|---|---|---|---|
| M1 | `9428e2ea-5e81-43a6-b9e1-ce6aca714815` | base3 | `HOLO \| STARLIGHT \| NULL \| NULL` | `HOLO` |
| M2 | `65fdd081-9c0d-4075-b762-5268ae13eefc` | sv05 | `REVERSE \| GALAXY \| NULL \| NULL` | `COSMOS_REVERSE` |

Game e asset_source corretos nas duas; 1 row por combinação; mapping GLOBAL equivalente = 0.

## 4. Preservação das 94 PRE (gate da v1.1 provado)

Excluindo apenas as 2 rows novas, o POST tem 94 rows com md5 dos ids `cc4b339a…` (= PRE) e fingerprint `id → variant_type_id` `aba31a17…` (= PRE). Nenhuma row PRE desapareceu, nenhum `variant_type_id` PRE mudou, e as 2 GLOBAL com foil NULL continuam no conjunto. A correção `fm_pre.ids` da v1.1 foi efetivamente provada no LIVE.

## 5. Lookup POST (fato LIVE)

| Card Set | Combinação | stamp NULL | stamp `[]` | `card_set_id` NULL |
|---|---|---|---|---|
| BASE3 | `HOLO\|STARLIGHT\|NULL` | `HOLO` | `HOLO` | NULL |
| SV5 | `REVERSE\|GALAXY\|NULL` | `COSMOS_REVERSE` | `COSMOS_REVERSE` | NULL |

Zero vazamento global.

## 6. B-SEMANTIC (fato LIVE)

| Componente das 46 | Baseline | Após `2236` | Após `2237` v1.1 |
|---|---:|---:|---:|
| NO_PROFILE | 33 | 0 | **0** |
| FINISH NULL | 2 | 2 | **0** |
| NO_EC | 11 | 11 | **11** |

Plano 285 (md5 `a53343fa…`, lineage missing 0): blocked genérico 13 → **11** · determinísticas genéricas 272 → **274/285**. Todos os 11 bloqueados são NO_EC:

| Tipo legado | n | Sets | Residual |
|---|---:|---|---|
| `STANDARD_PIKACHU_WORLD_2000` | 6 | BASEP | `NORMAL\|NULL\|NULL\|{PIKACHU-TAIL}` |
| `STANDARDS_LEAGUE` | 4 | PL3, SV5, SV7 | `NORMAL\|LEAGUE\|NULL\|{}` |
| `PLAYER_REWARD_REVERSE` | 1 | SV5 | `REVERSE\|PLAYER-REWARD\|NULL\|{}` |

Essas 11 dependem da camada HISTORICAL OVERRIDE da `2831` v3.1 (e, depois do Gate A, da `2213`). **Não** estão reconciliadas; 285/285 **não** é fato.

## 7. Casos individuais

| Variant | EC profile (inalterado) | Finish POST |
|---|---|---|
| PRERELEASE_HOLO BASE3 #01 (`1bbaf8e7…`) | `EVENT_PRERELEASE` | `HOLO` |
| GAMESTOP_HOLO SV5 #119 (`ee0e6742…`) | `CHANNEL_GAMESTOP` | `COSMOS_REVERSE` |

A 2237 não altera Edition Context.

## 8. 2236 sem regressão

traits 116 · profiles 175 · profile_trait 246 · EC mappings 122 · EC mapping links 122 · D2 33/33 `RESOLVED_WITH_EC_PROFILE` · D1 8/8 HOLD-safe · mapping `PIKACHU-TAIL` 0.

## 9. Não-escopo

- Estáveis antes/depois: `card_variant` 24.893 · `catalog_variant_import_row` 26.239 · `catalog_variant_import_job` 147. A 2237 não escreve nessas tabelas.
- Blast radius: as mesmas 3 rows, estado inalterado (md5 `b82762a4…` PRE = POST); 0 PENDING em job operacional ativo.
- Concorrência POST: 0 locks, 0 em espera, 0 xid, 0 idle in transaction.
- `2831` v3.1: não autorizada, não executada. `2213`: não criada. Edge e confirmação de staging: não.

## 10. Próximos gates

Publicar este closeout → PRE JIT próprio da `2831` v3.1 → nova autorização explícita → executar somente a simulação (com `ROLLBACK`) → Gate A. `2213` continua posterior ao Gate A.

## 11. Proibições remanescentes

Sem novo mandato: nenhuma execução da `2831` ou `2213`; nenhuma reexecução da `2237` (é fail-closed e abortaria em `2237_ALREADY_APPLIED_OR_COLLISION`) nem da `2236`; nenhum mapping GLOBAL `GALAXY = COSMOS`; nenhum Edge deploy ou confirmação de staging; nenhuma edição dos artefatos `2236`/`2237` aplicados nem do registro `LIVE-2237-FAILED-ATTEMPT-RECORD.md`.
