# SV5 — Correção do mapping Master Ball League (COSMOS)

| Campo | Valor |
|---|---|
| **Proposta** | `2026-09-16-sv5-master-ball-mapping-correction` |
| **Status** | **CONFIRMADO EXECUTADO — LIVE** (migration `20260916212542`, 2026-09-16) |
| **Versão da migration** | 1.1 (v1.0 abortou por defeito no guard G22 — ver §9) |
| **Mandato** | CARD-VARIANTS — EDITORIAL CONVERGENCE / `SV5-MASTER-BALL-CORRECTION-STAGING-01` |
| **Diagnóstico** | `SV5-EXTERNAL-EVIDENCE-AUDIT-02` (contradição material) + `SV5-MASTER-BALL-MAPPING-FORENSIC-01` (blast radius) |
| **Criado em** | 2026-09-16 |
| **Autor** | Fabrício Sales / Claude |

---

## 1. O problema

Um mapping editorial criado em 2026-09-15 afirma um acabamento físico que **nenhuma evidência externa sustenta**:

```
SCOPED sv05 · NORMAL + {MASTER-BALL-LEAGUE} → MASTER_BALL_LEAGUE_COSMOS_HOLO
```

A pesquisa externa foi encerrada como **EVIDENCE EXHAUSTED**: níveis 1 e 2 (Play! Pokémon, Bulbapedia) não documentam a variante; a única atestação de "Cosmos Holo" localizada pertence a **outro produto** (Play! Prize Pack Series); a única atestação específica do selo diz "Holo", em listing isolado — insuficiente por contrato.

Agrava: o mesmo selo já tinha interpretação anterior no corpus — mapping **GLOBAL** `d50c6a98` (2026-08-15), `holo + {master-ball-league} → MASTER_BALL_HOLO`.

Além de afirmar o que não se sabe, o mapping **bloqueia a correção futura**: `internal.apply_variant_type_mapping` recusa reprocessar linha que não esteja em `NEEDS_REVIEW` (guard `ORIGIN_NOT_NEEDS_REVIEW`) e recusa segunda interpretação da mesma assinatura residual (guard `DUPLICATE_GLOBAL`).

---

## 2. Objetos envolvidos

| Papel | UUID | Ação |
|---|---|---|
| mapping SCOPED sv05 | `d050cd63-099a-47c4-9a1c-46ad09e37e6a` | **REMOVIDO** |
| staging row | `64eeface-00f2-49a4-a093-cb3b6d033614` | **REVERTIDA** para NEEDS_REVIEW |
| job (sv05, STAGED) | `601f7c96-8118-4b97-a0f3-cbbf418e8c21` | `valid_rows` recalculado |
| variant type | `11f7c959-a063-4d43-9daf-1290f69c18db` | **PRESERVADO E ATIVO** (desativação é passo separado) |

**Protegidos (NÃO TOCAR, com guard de fingerprint na própria migration):**

| Papel | UUID |
|---|---|
| mapping GLOBAL Master Ball | `d50c6a98-fcfa-4c11-aaf4-07e6a1cb0b60` |
| row irmã (Master Ball + Judge) | `c2bc937a-270a-4ae6-8b82-c2448881b5fa` |
| EB Games | `aa9ba80b-9f83-45a4-8a50-ebf6472197d5` |

---

## 3. Arquivos

| Arquivo | Conteúdo |
|---|---|
| `2200_revoke_sv5_master_ball_league_cosmos_mapping.sql` | Migration corretiva **v1.1 — CONFIRMADO EXECUTADO**. Bloco `DO` único, 14 guards de pré-condição, 3 escritas com cardinalidade verificada, 12 guards de pós-condição. |
| `README.md` | Este documento. |

**Não foi criado script de validação `28xx`.** O mandato pede postcheck "somente se realmente necessário", e ele não é: a migration é um bloco `DO` único — portanto uma única instrução SQL, atômica — cujos guards de pós-condição rodam **dentro da mesma transação**. Qualquer desvio aborta e desfaz tudo. Um script separado só poderia confirmar depois do commit o que a própria migration já se recusaria a commitar. O postcheck read-only de conferência está na Seção 6 abaixo, para execução manual pós-commit se você quiser a evidência registrada.

---

## 4. Guards

### Pré-condição (fail-closed)

| # | Guard | Protege contra |
|---|---|---|
| G01 | Identidade **completa** do mapping (13 campos) | remover o mapping errado; drift de qualquer campo |
| G02 | VT existe com `code` esperado | id certo, objeto errado |
| G03 | O mapping é o **único** apontando para o VT | remover peça de conjunto maior |
| G04 | VT tem **0** `card_variant` | identidade já materializada → exigiria reconciliação editorial |
| G05 | VT tem **0** referência de pricing | dependência invisível |
| G06 | Row no estado exato VALID/NEW/PENDING/PENDING apontando para o VT | decisão/persistência já avançada |
| G07 | `raw_data` bate com a assinatura auditada | re-staging silencioso entre auditoria e execução |
| G08 | Exatamente **1** row no banco inteiro resolvida por esse VT | órfãos; atingir outro job |
| G09 | Job é o nominal, STAGED, TCGDEX, sv05 | job confirmado/cancelado |
| G10 | Baseline real do job: VALID 418 / NEEDS_REVIEW 10 / TOTAL 428 | banco mudou desde a auditoria |
| G10B | Contadores **gravados** coerentes com o real | corrigir sobre contador já derivado |
| G11 | 9 mappings SCOPED sv05 | escopo mudou |
| G12 | Mapping GLOBAL de Master Ball existe | confundir escopo global com scoped |
| G13 | Row irmã existe e está em NEEDS_REVIEW | alvo errado |
| G14 | Nenhum id alvo coincide com id protegido | erro de digitação nas constantes |

### Pós-condição (fail-closed, mesma transação)

| # | Guard |
|---|---|
| G15 | Mapping não existe mais |
| G16 | Mappings SCOPED sv05 = **8** |
| G17 | Nenhum mapping aponta para o VT |
| G18 | VT continua existindo **e ativo** (esta migration não desativa) |
| G19 | Row em NEEDS_REVIEW/NEW/PENDING/PENDING, `normalized_data = {}`, ids nulos |
| G19B | `raw_data` **não** foi mutado |
| G20 | Job: VALID **417**, NEEDS_REVIEW **11**, TOTAL **428** |
| G21 | `valid_rows` gravado = 417, `total_rows` = 428 |
| G22 | Distribuição decision/persistence **inalterada** (`APPROVED/INSERTED=408 \| PENDING/PENDING=20`) |
| G23 | `card_variant` inalterado (contagem antes = depois) |
| G24A–E | **Não-toque provado por md5**: mapping GLOBAL · row irmã · EB Games · todos os demais mappings · todas as demais rows |
| G25 | `catalog_admin_action_log` **intacto** |
| G26 | A row voltou a ser elegível ao fluxo canônico de resolução |

---

## 5. Efeito — esperado e CONFIRMADO no LIVE

Todos os valores da coluna "Depois" foram verificados no LIVE após a execução (2026-09-16).

| Métrica | Antes | Depois |
|---|---|---|
| mappings SCOPED sv05 | 9 | **8** |
| mappings apontando p/ o VT | 1 | **0** |
| job sv05 — VALID | 418 | **417** |
| job sv05 — NEEDS_REVIEW | 10 | **11** |
| `job.valid_rows` | 418 | **417** |
| `job.total_rows` | 428 | 428 |
| decision/persistence | 408 APPROVED/INSERTED + 20 PENDING/PENDING | inalterado |
| `card_variant` | — | inalterado |
| `catalog_admin_action_log` | — | inalterado |
| Variant Type | existe, `is_active = true` | existe, `is_active = true` |

Classificação editorial resultante: a variante **Master Ball League (base)** de SV5 volta a ser resíduo **classe B** — existência externa confirmada, acabamento indeterminado.

---

## 6. Postcheck read-only (opcional, pós-commit)

```sql
SELECT 'mappings_scoped_sv05'  AS k, COUNT(*)::TEXT AS v FROM public.card_variant_type_external_mapping WHERE external_set_id = 'sv05'
UNION ALL SELECT 'mapping_alvo_existe', COUNT(*)::TEXT FROM public.card_variant_type_external_mapping WHERE id = 'd050cd63-099a-47c4-9a1c-46ad09e37e6a'
UNION ALL SELECT 'mappings_para_o_vt', COUNT(*)::TEXT FROM public.card_variant_type_external_mapping WHERE variant_type_id = '11f7c959-a063-4d43-9daf-1290f69c18db'
UNION ALL SELECT 'vt_existe_ativo', COUNT(*)::TEXT FROM public.card_variant_type WHERE id = '11f7c959-a063-4d43-9daf-1290f69c18db' AND is_active
UNION ALL SELECT 'row_estado', r.validation_status||'/'||r.match_status||'/'||r.decision_status||'/'||r.persistence_status||' norm='||r.normalized_data::TEXT
            FROM public.catalog_variant_import_row r WHERE r.id = '64eeface-00f2-49a4-a093-cb3b6d033614'
UNION ALL SELECT 'job_real_valid/needs/total',
            (SELECT COUNT(*) FILTER (WHERE validation_status='VALID')::TEXT||'/'||COUNT(*) FILTER (WHERE validation_status='NEEDS_REVIEW')::TEXT||'/'||COUNT(*)::TEXT
               FROM public.catalog_variant_import_row WHERE job_id = '601f7c96-8118-4b97-a0f3-cbbf418e8c21')
UNION ALL SELECT 'job_gravado_valid/total', j.valid_rows::TEXT||'/'||j.total_rows::TEXT
            FROM public.catalog_variant_import_job j WHERE j.id = '601f7c96-8118-4b97-a0f3-cbbf418e8c21'
UNION ALL SELECT 'global_mbl_intacto', COUNT(*)::TEXT FROM public.card_variant_type_external_mapping WHERE id = 'd50c6a98-fcfa-4c11-aaf4-07e6a1cb0b60'
UNION ALL SELECT 'row_irma_estado', r.validation_status FROM public.catalog_variant_import_row r WHERE r.id = 'c2bc937a-270a-4ae6-8b82-c2448881b5fa';
```

Valores esperados: `8`, `0`, `0`, `1`, `NEEDS_REVIEW/NEW/PENDING/PENDING norm={}`, `417/11/428`, `417/428`, `1`, `NEEDS_REVIEW`.

---

## 7. Passo separado — desativação do Variant Type

**Não faz parte desta migration.** Executar **apenas depois** da migration aplicada e sob autorização própria, com **sessão administrativa real** (a RPC exige `public.is_admin()`; MCP/SQL Editor não satisfaz esse predicado).

```sql
SELECT public.admin_deactivate_card_variant_type('11f7c959-a063-4d43-9daf-1290f69c18db'::UUID);
```

Confirmação:

```sql
SELECT id, code, is_active, updated_at
  FROM public.card_variant_type
 WHERE id = '11f7c959-a063-4d43-9daf-1290f69c18db';
-- esperado: is_active = false
```

Reversível a qualquer momento, se evidência de COSMOS aparecer:

```sql
SELECT public.admin_reactivate_card_variant_type('11f7c959-a063-4d43-9daf-1290f69c18db'::UUID);
```

Esse caminho registra `CARD_VARIANT_TYPE_DEACTIVATED` / `_REACTIVATED` no `catalog_admin_action_log` — ambas já previstas no CHECK vigente, sem necessidade de ampliá-lo.

---

## 8. Dívidas e limites conhecidos

1. **A remoção do mapping não deixa rastro no `catalog_admin_action_log`.** Decisão aprovada foi não ampliar o CHECK, que só admite `CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED`. O rastro passa a ser esta migration versionada + os dois eventos de criação preservados. Registrado como dívida, não silenciado.
2. **Não existe mecanismo canônico de rollback de mapping.** Esta é uma correção pontual, deliberadamente não generalizada. Se o padrão se repetir, a decisão de criar RPC de revogação deve ser retomada.
3. **RLS:** `card_variant_type_external_mapping` tem apenas a policy `catalog_admin_select`. Não há caminho de aplicação para esta correção — ela só é executável como migration (papel owner).
4. **Lacuna aberta, fora deste escopo:** existem **9** mappings SCOPED sv05, dos quais apenas 4 foram auditados contra evidência externa. Os 5 restantes (`EBGAMES_HOLO`, `GAMESTOP_HOLO`, `PLAYER_REWARD_REVERSE`, `POKEMON_DAY_COSMOS_HOLO`, `SET_LOGO_COSMOS_HOLO`) **não** foram auditados e podem conter o mesmo padrão de falsa certeza.
5. **Os 10 resíduos NEEDS_REVIEW** permanecem intocados (classe A = 0, B = 2, C = 8). Após esta correção passam a **11**.

---

## 9. Histórico de execução

| Tentativa | Versão | Resultado |
|---|---|---|
| EXECUTION-01 (2026-09-16) | 1.0 | **ABORTOU** — `42803: aggregate functions are not allowed in GROUP BY` no guard G22 (`GROUP BY 1` referenciava expressão contendo `COUNT(*)`). Defeito exclusivo do guard; nenhuma pré-condição falhou. Como o corpo é um bloco `DO` único, o abort desfez as três escritas: **rollback provado TOTAL** (mapping presente, row em `VALID` com `updated_at` original de 2026-09-15, job 418/10/428, migration não registrada). |
| EXECUTION-02 (2026-09-16) | 1.1 | **SUCESSO.** Delta executável provado: exatamente 1 linha alterada (`GROUP BY 1` → `GROUP BY r.decision_status, r.persistence_status`); md5 de constantes, guards, escritas e de todas as demais linhas idênticos entre v1.0 e v1.1. Registrada como `20260916212542`. G01–G26 PASS. |

A v1.0 nunca chegou ao LIVE. O comportamento do abort é evidência direta de que o desenho atômico funciona: um defeito descoberto **depois** das escritas não deixou estado intermediário.
