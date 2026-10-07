# LIVE — migration 2213 v1.0 (decomposição das 285 READY_UNCONDITIONED) · Registro

| Campo | Valor |
|---|---|
| **Mandatos** | `BATCH13-2213-MIGRATION-PREP-01` (candidata) · `BATCH13-2213-MIGRATION-AUDIT-CORRECTION-01` (contrato L5) · `BATCH13-2213-V10-LIVE-PRE-01` (PRE read-only e evidência congelada) · `BATCH13-2213-V10-LIVE-EXECUTION-01` (execução) · `BATCH13-2213-V10-LIVE-EXECUTION-CLOSEOUT-01` (registro) |
| **Autorização** | Fabrício: "Autorizo a execução LIVE da migration 2213 v1.0, blob 4318ac9567b6489ca441e487e3ae8ebda0247ea6." — cobre **somente** uma submissão integral desse blob via `execute_sql`. **Não** autorizou retry, alteração do SQL, `apply_migration`, execução parcial, SQL corretivo, outra migration, Edge, confirmação de staging, nem `git add`/`commit`/`push`. |
| **Baseline Git** | HEAD `c7848edbd24046138b63d8e7f6b1cd9652220c5a` (`feat(batch13): add 2213 legacy decomposition migration`), parent `d2898812` (closeout do Gate A), árvore e índice limpos |
| **Artefato executado** | `../2213_decompose_legacy_card_variants.sql` **v1.0**, blob `4318ac9567b6489ca441e487e3ae8ebda0247ea6` (54.924 B, 1.043 linhas, LF) |
| **Canal** | MCP Supabase, projeto `qjfutqujxrbzgrtkpgkg`: `execute_sql` — **uma** chamada com o conteúdo exato do blob. **Não** foi `apply_migration`. |
| **Resultado** | **2213 v1.0 = APPLIED / FINAL PASS** — auditoria independente PASS |

O cabeçalho do artefato continua dizendo "PROPOSTA / NÃO EXECUTADA": artefatos aplicados não são reescritos para atualizar status. Este registro é a autoridade do estado de execução.

## 1. Artefato

A `2213` v1.0 é o corpo executável da `2831` v3.1 (blob `65149642…`, Gate A FINAL PASS) com **exatamente três** deltas executáveis:

1. contrato L5: `HOLD_LEAKED_INTO_PLAN` → `EDITION_CONTEXT_HOLD_VIOLATION` (mesmo predicado);
2. NOTICE final `2213_MIGRATION_PASS (v1.0) … COMMIT a seguir.`;
3. `ROLLBACK;` → `COMMIT;`.

Contrato estático (verificado antes do envio): `BEGIN` 1 · `COMMIT` 1 (último statement) · `ROLLBACK` executável 0 · UPDATE `card_variant` 1 · UPDATE `catalog_variant_import_row` 1 · INSERT/DELETE/ALTER/TRUNCATE/DISABLE TRIGGER 0 · `FOR UPDATE` 2 · `RAISE EXCEPTION` 61 · `RAISE NOTICE` 2 · `CREATE TEMP TABLE` 17 · `DO` 13 · `lock_timeout` 1 (`5s`) · exception handler 0.

Prova byte-exata: a transcrição enviada foi gravada em arquivo antes da chamada; `git hash-object` = `4318ac95…` e `cmp` idêntico ao arquivo do HEAD. O arquivo não foi alterado.

## 2. Evidência congelada (`BATCH13-2213-V10-LIVE-PRE-01`)

Arquivos locais de evidência (não versionados), autoridade do POST:

| Arquivo | md5 do arquivo | Conteúdo |
|---|---|---|
| `PLAN_285_IDS.txt` | `83a2fc8e5abc74772de9ab5a31f2739c` | 285 ids do plano (md5 dos ids `a53343fa38bbbe6f45fea7a4dba4bbdb`) |
| `LINEAGE_TARGET_336_IDS.txt` | `d359a0c7e3e09aed924b0092de3be6ce` | 336 rows-alvo (md5 dos ids `8ca1b0e0f8621be31850bf728cbb43a3`) |
| `EXPECTED_CV_POST_285.json` | `92cc0a9c7627724719cbda7492801ea6` | estado esperado por Variant |
| `EXPECTED_LINEAGE_POST_336.json` | `e60c24082913925375510adf680d9bd5` | estado esperado por row |
| `FORMULAS.md` | `d6a16c8c511de30f9f36211ddc6f1732` | fórmulas congeladas |

Fingerprints congelados: CV PRE `2941438df182cb2bbda4c644c9206680` → **EXPECTED_CV_POST_MD5 `c14f6fdbb838fa170db2c6db87dd54cc`**; lineage PRE `bb87fe1c5c830d8e625d492af58f5daf` → **EXPECTED_LINEAGE_POST_MD5 `a4b21ecda07ef7800bf0fdb74f18526d`**.

## 3. PRE JIT (SELECT, 2026-10-07)

| Query | Momento (UTC) | Resultado |
|---|---|---|
| A — plano / semântica / colisões / D1 / D4 | `02:13:36` | PASS |
| B — lineage / fora do escopo | `02:14:50` | PASS |
| C — forward-fixes / business refs / pikachu-tail | `02:15:26` | PASS |
| Concorrência 1 | `02:15:38` | limpa |
| Concorrência 2 (último gate) | `02:18:14.824556` | limpa |

- Plano: HOLD 107 · READY 365 · PRICING 80 (40/40) · READY ∩ HOLD 0 · plano 285 · md5 `a53343fa…` · plano ∩ HOLD 0 · plano ∩ Pricing 0 · lineage missing 0.
- Semântica: genérico 274/285; NO_PROFILE 0 · NO_EC 11 · FINISH NULL 0; bloqueadas 11 = 6 Pikachu + 4 League + 1 Player Reward; override 6/4/1 · overlap 0 · shape 0 · diferença simétrica 0 · finish drift 0; efetivo 285/285 (EC NULL 0, finish NULL 0).
- Idempotência / colisões: printing drift 0 · já decompostas 0 · EC não-NULL global 0 · colisões 0.
- D1: membros BASEP #01, #04, #25, #26, #27, #28; BASE2 #60 e BASEP #24 fora do plano. D4: 1 row SV5 #144, 0 violações, lookup estrutural `REVERSE_HOLO`.
- Comparação offline com a evidência congelada: 285 presentes, diferença simétrica 0, 0 mismatches nos 6 campos; lineage 336/285/51, 336 presentes, diferença simétrica 0, 0 mismatches.
- Fora do escopo PRE: rows fora do lineage-alvo 25.903 / `d801514d…` · Variants fora do plano 24.608 / `dd7108a9…` · `resulting` 23.955 · `matched` 1.193 · `card_variant` 24.893.
- Forward-fixes 116 / 175 / 246 / 122 / 122; finish mappings 96 (75 / 21); alvos `2237` 2; `PIKACHU-TAIL` 0. Referências de negócio às 285: 0/0/0/0.
- Último gate de concorrência: locks de outras sessões 0 · writers 0 · em espera 0 · xid 0 · idle in transaction 0 · clientes ativos 0.

## 4. Adjudicação do limite de 60 s

O mandato exigia ≤ 60 s entre o `checked_at` do gate de concorrência e a chamada mutável. O transporte do blob (≈ 55 KB) excede fisicamente esse limite. Fabrício adjudicou: repetir o gate imediatamente antes da chamada e submeter sem espera deliberada; o limite de 60 s ficou **SUPERSEDED somente para esta execução**.

A adjudicação **não** removeu: gate JIT, `FOR UPDATE`, `lock_timeout = 5s`, gates fail-loud nem fingerprints POST.

## 5. Execução

| Campo | Valor |
|---|---|
| Canal | MCP Supabase `execute_sql` |
| Submissões reportadas | **1** |
| Retry | NÃO |
| `apply_migration` | NÃO |
| Retorno bruto | `[]` |
| SQLSTATE | nenhum |
| NOTICE | **não devolvido pelo canal** (nem `LINEAGE_SCOPE` nem `2213_MIGRATION_PASS (v1.0)`) |
| SQL corretivo | NÃO |

Nenhum NOTICE foi observado. O artefato é fail-loud: qualquer divergência gera `RAISE EXCEPTION` e aborta a transação inteira. Sem exception, nenhum gate abortou e a transação chegou ao `COMMIT` do próprio blob — fato confirmado pelo POST (§7).

## 6. Timestamp

| Medida | Valor (UTC) |
|---|---|
| Último gate de concorrência do executor | `2026-10-07 02:18:14.824556` |
| Timestamp transacional das 285 (`updated_at = now()`) | `2026-10-07 02:21:39.898181` |
| `min(updated_at)` = `max(updated_at)` | `2026-10-07 02:21:39.898181` |
| `updated_at` distintos | 1 |
| Intervalo gate → timestamp transacional | **205,073625 s** (≈ 3 min 25,074 s) |

O intervalo > 60 s **não é falha**: o requisito estava formalmente SUPERSEDED antes da submissão (§4). O `updated_at` prova o instante da transação e sua unicidade; **não** é prova de ausência de concorrência — essa prova são o gate JIT, os locks `FOR UPDATE` e os fingerprints POST fora do escopo.

## 7. POST independente

A tentativa de POST pelo executor foi bloqueada pela camada de permissões do ambiente (nenhum SELECT executado por ele após a submissão). O POST abaixo foi executado de forma independente, read-only, contra os conjuntos congelados, e consolidado pela auditoria independente.

### 7.1 As 285 Variants

Conjunto autoritativo: `PLAN_285_IDS.txt`.

| Medida | Valor |
|---|---|
| count | 285 |
| ids preservados | 285/285 |
| EC não-NULL | 285/285 |
| `card_variant` global com EC não-NULL | 285 |
| `card_variant` total | 24.893 |
| CV POST md5 esperado | `c14f6fdbb838fa170db2c6db87dd54cc` |
| CV POST md5 real | `c14f6fdbb838fa170db2c6db87dd54cc` |

**PASS.**

### 7.2 As 336 rows de lineage

Conjunto autoritativo: `LINEAGE_TARGET_336_IDS.txt`.

| Medida | Valor |
|---|---|
| count | 336 |
| ids preservados | 336/336 |
| chave `edition_context_profile_id` | 336/336 |
| Lineage POST md5 esperado | `a4b21ecda07ef7800bf0fdb74f18526d` |
| Lineage POST md5 real | `a4b21ecda07ef7800bf0fdb74f18526d` |
| híbrido L2 | 0 |

**PASS.**

### 7.3 Fora do escopo

| Medida | PRE | POST |
|---|---|---|
| rows fora do lineage-alvo | 25.903 / `d801514d9c60e0c5923c6578ca7fceff` | 25.903 / `d801514d9c60e0c5923c6578ca7fceff` |
| Variants fora do plano | 24.608 / `dd7108a9282b39062271c447fc8b6c82` | 24.608 / `dd7108a9282b39062271c447fc8b6c82` |
| rows com `resulting_variant_id` | 23.955 | 23.955 |
| rows com `matched_variant_id` | 1.193 | 1.193 |
| `card_variant` | 24.893 | 24.893 |

**ZERO OUT-OF-SCOPE DRIFT.**

### 7.4 C3 residual

READY_STRUCTURAL 80 · READY_PRICING_CONDITIONED 80 (STAFF_HOLO 40 + SET_LOGO_REVERSE 40) · **READY_UNCONDITIONED residual 0** · HOLD 107 · das 285 congeladas ainda com tipo legado: 0.

### 7.5 Pricing

READY_STRUCTURAL ∩ `pricing_conditioned`: 80 (STAFF_HOLO 40 + SET_LOGO_REVERSE 40); `edition_context_profile_id` não-NULL 0 · NULL 80. **PRICING_CONDITIONED preservada.**

### 7.6 D1 HOLD-safe

| Row | Estado | md5 da row |
|---|---|---|
| BASE2 #60 | STAGED · NEEDS_REVIEW / PENDING / PENDING · `resulting` NULL · `matched` NULL | `a0acad95ae681cc607144681e42c718f` |
| BASEP #24 | inalterada | `bd9d0118b2502f636b0d1d83dae31979` |

Mapping `PIKACHU-TAIL` = 0. Nenhuma Variant criada. **D1 intacto.**

### 7.7 Forward-fixes

traits 116 · profiles 175 · profile_trait 246 · EC mappings 122 · EC mapping links 122 · finish mappings 96 (GLOBAL 75 · SOURCE_SET 21) · alvos da `2237` 2.

### 7.8 Transação e locks

Locks de outras sessões 0 · locks em espera 0 · writers materiais 0 · client xid 0 · idle in transaction 0 · clientes ativos 0.

## 8. B-SEMANTIC — antes e depois

| Momento | Estado |
|---|---|
| Antes da `2213` (persistente) | 274/285 genericamente determinísticas + 11 por camada histórica (6/4/1), 0 decompostas |
| Depois da `2213` (persistente) | **285/285 fisicamente decompostas** (Edition Context + finish puro), 336/336 rows de lineage reconciliadas |

## 9. Classificação

**2213 v1.0 = APPLIED / FINAL PASS** (auditoria independente PASS). Fundamento: submissão única do blob byte-exato; retorno sem exception; os dois fingerprints POST iguais aos esperados congelados; fora do escopo idêntico ao PRE; READY_UNCONDITIONED residual 0; Pricing 80 sem Edition Context; D1 e forward-fixes intactos; sem transação residual.

**Batch 13 não é declarado CLOSED neste registro.**

## 10. Próximos gates

Publicar este closeout → auditoria de encerramento do Batch 13 → só depois avançar para a próxima frente do roadmap.

## 11. Proibições remanescentes

Sem novo mandato: nenhuma reexecução da `2213` nem da `2831`; nenhuma edição dos artefatos `2213`/`2831`/`2236`/`2237` nem dos registros históricos; READY_PRICING_CONDITIONED (80) só em `PRICING-CATALOG-VARIANT-RECONCILIATION-01`; nenhum Edge deploy ou confirmação de staging.
