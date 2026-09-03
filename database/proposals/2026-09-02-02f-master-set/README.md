# Staging — COLLECTIONS-PHYSICAL-INCREMENT-02F — Master_Set Scope & Completion

| Campo | Valor |
|---|---|
| Rodada | `COLLECTIONS-PHYSICAL-INCREMENT-02F-STAGING-01` → `-STAGING-REVISION-01` |
| Status | PROPOSTA — NÃO EXECUTADA. Nenhuma Query desta pasta foi aplicada ao banco físico. |
| Autoridade | `COLLECTIONS-MASTER-SET-MODELING-01` → `-MODELING-REVISION-01` → `-MODELING-FINAL-FIX-01` → `-MODELING-FINAL-FIX-02` (as quatro rodadas de modelagem, todas fechadas e aprovadas por Fabrício antes desta rodada — as últimas revisões prevalecem em caso de diferença). `MASTER_SET MODELING` permanece `CLOSED` — a `STAGING-REVISION-01` corrigiu apenas o staging físico (5079-5081, 5812, 5813), sem reabrir nenhuma decisão conceitual/lógica. |
| Precedido por | `2026-09-02-02e-completion/` (STANDARD_SET Completion & Progress, `CONFIRMADO EXECUTADO`) |

## STAGING-REVISION-01 — correções de auditoria fonte-a-fonte

Fabrício conduziu uma auditoria fonte-a-fonte do conteúdo integral dos 16 arquivos de `STAGING-01` (antes de qualquer autorização de implementação) e encontrou problemas reais, corrigidos nesta revisão — **sem alterar nenhuma decisão de MODELING** (que permanece `CLOSED`):

- `5079` (v2.0) — **BLOCKER**: `apply_master_set_scope_diff()` criava `TEMP TABLE ... ON COMMIT DROP`, o que quebrava na segunda chamada dentro da mesma transação (exatamente o padrão usado por `5812`). Reescrita para usar apenas CTEs, sem estado de sessão. Também ganhou um contrato de payload explícito: rejeita array vazio, não-array, elemento não-string, UUID malformado, UUID inexistente, Variant de outro Card Set e — decisão desta revisão — **UUID duplicado no payload é REJEITADO, nunca normalizado via `DISTINCT`**.
- `5080` (v2.0) — Caminho B (reaproveitar Scope persistido) agora retorna `kept_count` real (contagem das linhas reaproveitadas), não mais `0`. Comparação de `reference_kind` corrigida para `IS DISTINCT FROM` (NULL-safe).
- `5081` (v2.0) — **BLOCKER**: `set_collection_completion_policy_to_standard_set()` tratava qualquer Collection `ACTIVE` como candidata a idempotência silenciosa. Agora valida explicitamente `mode`/`reference_kind`/`completion_policy` atual antes de qualquer `UPDATE` — `OPEN_CURATION`/`NONE` e um futuro `REFERENCE_POSITION` falham explicitamente.
- `5082` (v1.1) — só documentação: esclarece que "VALIDATE ALL → KEEP → ADD → REMOVE" é ordem semântica, não física (o `DELETE` antes do `INSERT` dentro de `5079` é permitido pelos constraint triggers deferidos).
- `5812` (v2.0) — **dois BLOCKERs**: os `POSTCHECK-4..7` tinham os bits `BEFORE`/`AFTER` de `pg_trigger.tgtype` invertidos (bit `BEFORE` = 2, não 0); a checagem de `search_path=''` em `SEC-5` nunca casava com a representação física real (`search_path=""`), um falso negativo. Ambos corrigidos. Adicionado bloco `REG-STD-0..7` (regressão mínima de `STANDARD_SET` pós-`5083`) e bloco `PAYLOAD-*` (contrato de payload de `5079`). `ARCHIVED-MUT-3` corrigido para usar uma fixture genuinamente `STANDARD_SET`+`ARCHIVED`. `S2M-REUSE` ajustado para esperar `kept_count` real.
- `5813` (v2.0) — **BLOCKER**: a síntese de Card Variants duplicava cada Variant sintética no pool combinado (reconsulta de `card_variant` após o `INSERT` das sintéticas incluía as próprias). Corrigido com exclusão explícita + assertion de zero-duplicatas que aborta o benchmark se violada. `synth_buffer` deixou de ser uma constante fixa (400) e passou a ser calculado dinamicamente para que o pool combinado se aproxime do candidato a guard (10000) — os workloads C/D/E agora testam carga materialmente próxima do teto, em vez de extrapolar de um volume muito menor.

## Estado final

02F entrega exclusivamente **MASTER_SET Scope & Completion** — a segunda metade de `completion_policy` (LDM-08), deixada `CONCEPTUALLY READY. PHYSICALLY DEFERRED FOR SCOPE CONTROL` pelo incremento 02E. Nenhum arquivo desta pasta foi aplicado ao banco: MASTER_SET MODELING está oficialmente `CLOSED` (quatro rodadas de modelagem), 02F está em `STAGING` — não em implementação.

O modelo físico segue, sem reabertura, as decisões já fechadas nas quatro rodadas de modelagem: PK natural composta `(collection_id, card_variant_id)` em `collection_master_set_scope`; tabela insert/delete-only (nenhum `UPDATE` permitido, estruturalmente); semântica KEEP/ADD/REMOVE obrigatória em toda mutação de Scope (nunca `DELETE` total + `INSERT` total); enforcement bidirecional `MASTER_SET` ativo ↔ Scope não-vazio via dois `CONSTRAINT TRIGGER ... FOR EACH ROW DEFERRABLE INITIALLY DEFERRED`, ambos delegando a decisão a um helper único que sempre reconsulta o estado CORRENTE (nunca `NEW`/`OLD` capturado no evento); `replace_master_set_scope()` só permitida sobre `MASTER_SET` já `ACTIVE`; as duas RPCs de transição de policy (`set_collection_completion_policy_to_master_set()`/`_to_standard_set()`) comparam sempre contra o Scope efetivamente PERSISTIDO, nunca contra uma presunção de "vazio" baseada na policy corrente; `ARCHIVED` bloqueia toda mutação de Scope/policy, mas mantém leitura; teto de payload de `apply_master_set_scope_diff()` registrado como guard operacional provisório (não uma constante de domínio).

## Escopo físico desta rodada

Materializa exclusivamente:
- `collection_master_set_scope` (tabela + RLS + trigger de elegibilidade imediata + trigger de bloqueio de `UPDATE`);
- o enforcement diferido bidirecional (`check_master_set_scope_presence()` + os dois `CONSTRAINT TRIGGER`, lado Collection e lado Scope);
- `chk_collection_completion_policy` alargada para aceitar `REFERENCE_BASED`/`MASTER_SET`;
- `apply_master_set_scope_diff()` (helper interno compartilhado, KEEP/ADD/REMOVE) e as três RPCs públicas que o usam: `set_collection_completion_policy_to_master_set()`, `set_collection_completion_policy_to_standard_set()`, `replace_master_set_scope()`;
- extensão de `collection_completion_summary()` para o ramo `MASTER_SET` (contrato externo inalterado);
- o read model novo `collection_master_set_scope_positions()` (grão de 1 linha por `card_variant_id` adotada);
- planos de validação funcional e de performance.

**Não implementa nesta rodada** (por controle de escopo, não por limitação técnica ou de catálogo): `add_master_set_variants()`/`remove_master_set_variants()` (deferidos — só `replace` existe no V1); qualquer projeção de "Variants elegíveis do Card Set" para a UX de configuração de Scope (registrada como dependência futura de UX antes do Frontend, ver seção própria abaixo); `REFERENCE_POSITION`/Pokédex; cache/materialized view; frontend; qualquer canonização de teto numérico de payload além do guard operacional provisório.

## Gap de UX registrado — catálogo de Variants elegíveis

A frente de Frontend vai precisar de uma superfície segura para listar as Variants elegíveis de um Card Set durante a configuração do Master Scope (busca/seleção antes de chamar `set_collection_completion_policy_to_master_set()`/`replace_master_set_scope()`). Essa projeção **não foi incluída no núcleo físico do 02F** (decisão explícita de `MODELING-REVISION-01`, item 9) — será tratada em um bloco de Read Models/Contracts de UX, numa rodada própria, antes do trabalho de Frontend. Nenhum arquivo desta pasta tenta resolver esse gap.

## Arquivos desta pasta

| Arquivo | Conteúdo |
|---|---|
| `5072_create_collection_master_set_scope_table.sql` | Tabela `collection_master_set_scope` — PK composta `(collection_id, card_variant_id)`, sem `updated_at`, RLS (`SELECT` só do próprio Owner via join) |
| `5073_create_collection_master_set_scope_eligibility_trigger.sql` | `validate_master_set_scope_eligibility()` — `BEFORE INSERT`, imediato, independente de RPC: Collection `REFERENCE_BASED`/`CARD_SET` + Variant pertence ao Card Set referenciado |
| `5074_create_collection_master_set_scope_update_block_trigger.sql` | `reject_collection_master_set_scope_update()` — `BEFORE UPDATE`, rejeita incondicionalmente (identidade estrutural imutável, MODELING-FINAL-FIX-01 item 4) |
| `5075_create_check_master_set_scope_presence_function.sql` | Helper `check_master_set_scope_presence(p_collection_id)` — decisão centralizada, sempre reconsulta o estado CORRENTE (MODELING-FINAL-FIX-02) |
| `5076_create_collection_master_set_scope_presence_trigger.sql` | `CONSTRAINT TRIGGER` lado Collection — `AFTER INSERT OR UPDATE OF completion_policy ... FOR EACH ROW DEFERRABLE INITIALLY DEFERRED` |
| `5077_create_master_set_scope_presence_on_delete_trigger.sql` | `CONSTRAINT TRIGGER` lado Scope — `AFTER DELETE ... FOR EACH ROW DEFERRABLE INITIALLY DEFERRED` |
| `5078_alter_collection_widen_completion_policy_master_set.sql` | `DROP`/`ADD CONSTRAINT chk_collection_completion_policy` — libera `REFERENCE_BASED`/`MASTER_SET` |
| `5079_create_apply_master_set_scope_diff_function.sql` (v2.0) | Helper interno `apply_master_set_scope_diff()` — KEEP/ADD/REMOVE via CTEs (sem TEMP TABLE), contrato de payload completo (array/vazio/string/UUID/existência/Set/duplicata), guard operacional de payload (`c_max_variant_ids`, provisório) |
| `5080_create_set_collection_completion_policy_to_master_set_function.sql` (v2.0) | RPC `set_collection_completion_policy_to_master_set()` — dois caminhos (Scope requisitado vs. reaproveitar persistido, com `kept_count` real no caminho B), sempre compara contra o Scope PERSISTIDO, `reference_kind` NULL-safe |
| `5081_create_set_collection_completion_policy_to_standard_set_function.sql` (v2.0) | RPC `set_collection_completion_policy_to_standard_set()` — elegibilidade explícita (`mode`/`reference_kind`/`completion_policy` atual), idempotente só dentro dessa elegibilidade, preserva Scope integralmente |
| `5082_create_replace_master_set_scope_function.sql` (v1.1) | RPC `replace_master_set_scope()` — só sobre `MASTER_SET`/`ACTIVE`, mesma semântica KEEP/ADD/REMOVE de `5079` (ordem física vs. semântica esclarecida em comentário) |
| `5083_update_collection_completion_summary_function.sql` (v3.0) | `CREATE OR REPLACE` — ramo `MASTER_SET` novo via `UNION ALL`, contrato externo idêntico à v2.0 |
| `5084_create_collection_master_set_scope_positions_function.sql` | Read model novo — grão de 1 linha por `card_variant_id` adotada, `JOIN` explícito a `card_variant_type` (auditado, não assumido) |
| `5812_validate_collections_physical_increment_02f.sql` (v2.0) | Bateria de validação funcional — Casos A-J com sub-casos (elegibilidade, bloqueio de `UPDATE`, KEEP/ADD/REMOVE, duplicatas, correspondência exata de Variant, completo/incompleto, `ARCHIVED`, não-enumeração, anônimo, catálogo fechado, transições de policy, exclusão em cascata) + **Caso F** + **Caso G** + **REG-STD-0..7** (regressão mínima de `STANDARD_SET` pós-`5083`) + **PAYLOAD-\*** (contrato de payload de `5079`) — SQL executável, `BEGIN`/`ROLLBACK`, zero resíduo, `SET CONSTRAINTS ... IMMEDIATE`/`DEFERRED` nomeado para forçar/restaurar a avaliação dos dois `CONSTRAINT TRIGGER` sem nunca dar `COMMIT` |
| `5813_performance_checks_collections_physical_increment_02f.sql` (v2.0) | Plano de performance (workloads A-J) — Scope pequeno/centenas/pool combinado (real + síntese controlada dimensionada para se aproximar do candidato a guard de 10000, deliberadamente acima do maior Card Set observado no catálogo antes da síntese — nunca canonizado como limite), assertion de zero-duplicatas na síntese, `replace` de alta sobreposição e de alta troca, duplicatas, Inventory >= 20.000, múltiplas Collections, `only_missing`, abertura de tela combinada — dentro de transação revertida |

Numeração `5072-5084` contínua após `5071` (último arquivo do incremento 02E). Numeração `5812`/`5813` — próximo par livre na faixa `58XX`, após `5810`/`5811` (02E).

## Sequência de aplicação (rodada futura de implementação)

Os 15 arquivos SQL desta pasta são staging — nenhuma aplicação real ocorreu.

1. `5072` (tabela `collection_master_set_scope`);
2. `5073` (trigger de elegibilidade imediata);
3. `5074` (trigger de bloqueio de `UPDATE`);
4. `5075` (helper `check_master_set_scope_presence()`);
5. `5076` (constraint trigger lado Collection);
6. `5077` (constraint trigger lado Scope);
7. `5078` (`CHECK` alargado para `MASTER_SET`);
8. `5079` (helper `apply_master_set_scope_diff()`);
9. `5080` (RPC `set_collection_completion_policy_to_master_set()`);
10. `5081` (RPC `set_collection_completion_policy_to_standard_set()`);
11. `5082` (RPC `replace_master_set_scope()`);
12. `5083` (`collection_completion_summary()` v3.0);
13. `5084` (`collection_master_set_scope_positions()`);
14. `5812` (validação funcional) → **prosseguir somente se `falharam = 0` no `SELECT` consolidado de `test_results` E zero resíduo confirmado no Passo 14 pós-`ROLLBACK`** — mesmo gate de processo de `5810` (02E), fiscalizado pelo executor da rodada, nunca por exceção dentro da transação. Se `falharam > 0`: **IMPLEMENTATION STOP** — corrigir antes de repetir este passo;
15. `5813` (performance sob volume sintético, incluindo Card Variants sintetizadas acima do maior Card Set atual) → avaliar os planos capturados em `perf_results` e só então formar a recomendação real de teto operacional de payload para `apply_master_set_scope_diff()` (hoje provisório em `5079`);
16. Promoção canônica para `database/schema/` + documentação (`05d-colecoes-e-usuarios.md`, `README.md`, `log.md`, `INDEX.md`, handoff) no mesmo ciclo — só então, nunca nesta rodada.

## Banco físico

Nenhuma alteração aplicada. Toda a superfície física fechada em 01B-02E (`collection`, `collection_reference`, `collection_card_set_reference`, `collection_allocation`, `physical_card`, `storage_container`, `inventory`, `collection.completion_policy` no ramo `STANDARD_SET`) permanece exatamente como deixada pelo incremento 02E (`CONFIRMADO EXECUTADO`).
