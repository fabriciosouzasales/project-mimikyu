# Binder / Layout Foundation — Staging (2026-09-06)

| Campo | Valor |
|--------|-------|
| **Rodada** | `...-REENTRY-01` → `...-STAGING-01` → `...-STAGING-HARNESS-COMPLETION-01` → `...-CORRECTION-01` … `...-CORRECTION-04` → `COLLECTIONS-BINDER-LAYOUT-FOUNDATION-CONSOLIDATED-CORRECTION-05` (esta) |
| **Status** | **IMPLEMENTED / VALIDATED (2026-09-07).** `5104`–`5137` e `5141` **aplicados** ao banco; `5818` v7.2 fechado em **196/196 runtime** (194 automáticos + `C04`/`R18` provados externamente); `5819` **22/22 HEALTHY**; hardening `5138`–`5140` aplicado e `5820` **27/27**. Zero resíduo. **Ainda não promovido** para `database/schema/`; **nenhum commit/push realizado.** O modelo conceitual/produto permanece CONGELADO: C-38–C-46, LDM-29–LDM-37 e DP-01–DP-10 não foram reabertos. Ver §10-bis e §10-ter para o registro de execução e o fechamento. |
| **Escopo** | Fundação física do Binder/Layout: Layout, Page, Slot, Expected Content, Slot Assignment, Layout Region + 14 RPCs. |
| **Baseline conceitual** | C-38–C-46 (`docs/domain-modeling/collections/concept-decisions.md`) |
| **Baseline lógico** | LDM-29–LDM-37 (`docs/domain-modeling/collections/logical-model.md`) |
| **Contrato de UX** | `docs/domain-modeling/collections/ux-exploration-2026-08-29.md`, `pkmnbindr-benchmark.md` §14/§15 |

---

## 1. Ordem de aplicação (OBRIGATÓRIA)

A ordem não é arbitrária — reflete dependências reais.

```
5104  card_variant UNIQUE(id, card_id)      <- constraint-supporting de 5113
5105  collection_layout                     (tabela)
5106  collection_layout updated_at
5108  collection_layout_page                (tabela)
5109  collection_layout_page updated_at
5107  grid immutability trigger             <- DEPOIS de 5108 (consulta Page)
5110  collection_layout_slot                (tabela)
5111  collection_layout_slot updated_at
5112  slot grid bounds trigger
5113  slot_expected_content                 (tabela)   <- exige 5104
5114  slot_expected_content updated_at
5115  slot_assignment                       (tabela)
5116  slot_assignment updated_at
5117  slot_assignment integrity trigger
5118  slot lock enforcement trigger
5119  collection_layout_region              (tabela)
5120  region updated_at
5121  region integrity trigger
5122  assert_collection_layout_mutable()    (helper interno)
5123..5135  as 13 RPCs originais
5136  structural FK immutability triggers   <- exige 5105/5108/5110
5137  set_collection_layout_grid()          <- exige 5122
```

**Atenção à inversão 5107 ↔ 5108:** o trigger de imutabilidade do grid
(`5107`) consulta `collection_layout_page`. Embora PL/pgSQL resolva
nomes em runtime, aplicá-lo antes da tabela existir deixaria uma janela
em que um `UPDATE` de grid falharia com erro de objeto inexistente em
vez da mensagem de domínio. Aplicar **depois** de `5108`.

---

## 2. Arquivo → objeto

| Arquivo | Objeto criado |
|---|---|
| `5104` | `uq_card_variant_id_card` (constraint em `card_variant`) |
| `5105` | tabela `collection_layout` + RLS + policy + grants |
| `5106` | `set_collection_layout_updated_at()` + trigger |
| `5107` | `enforce_collection_layout_grid_immutability()` + trigger |
| `5108` | tabela `collection_layout_page` + RLS + policy + grants |
| `5109` | `set_collection_layout_page_updated_at()` + trigger |
| `5110` | tabela `collection_layout_slot` + RLS + policy + grants |
| `5111` | `set_collection_layout_slot_updated_at()` + trigger |
| `5112` | `enforce_collection_layout_slot_grid_bounds()` + trigger |
| `5113` | tabela `collection_layout_slot_expected_content` + RLS + policy + grants |
| `5114` | `set_collection_layout_slot_expected_content_updated_at()` + trigger |
| `5115` | tabela `collection_layout_slot_assignment` + RLS + policy + grants |
| `5116` | `set_collection_layout_slot_assignment_updated_at()` + trigger |
| `5117` | `enforce_collection_layout_slot_assignment_integrity()` + trigger |
| `5118` | `enforce_collection_layout_slot_lock()` + trigger |
| `5119` | tabela `collection_layout_region` + RLS + policy + grants |
| `5120` | `set_collection_layout_region_updated_at()` + trigger |
| `5121` | `enforce_collection_layout_region_integrity()` + trigger |
| `5122` | `assert_collection_layout_mutable()` — **helper interno, sem EXECUTE de cliente** |
| `5123` | RPC `create_collection_layout(uuid, integer, integer)` |
| `5124` | RPC `delete_collection_layout(uuid)` |
| `5125` | RPC `add_layout_page(uuid)` |
| `5126` | RPC `remove_layout_page(uuid)` |
| `5127` | RPC `reorder_layout_pages(uuid, uuid[])` |
| `5128` | RPC `set_slot_expected_content(uuid, uuid, uuid)` |
| `5129` | RPC `clear_slot_expected_content(uuid[])` |
| `5130` | RPC `set_slot_lock(uuid[], boolean)` |
| `5131` | RPC `assign_card_to_slot(uuid, uuid)` — ADD + REPLACE |
| `5132` | RPC `move_slot_assignment(uuid, uuid)` — MOVE + SWAP |
| `5133` | RPC `remove_slot_assignment(uuid[])` — individual + bulk |
| `5134` | RPC `merge_layout_region(uuid, integer, integer, integer, integer)` |
| `5135` | RPC `unmerge_layout_region(uuid)` |
| `5136` | `enforce_collection_layout_structural_fk_immutability()` + **3 triggers** (`collection_layout.collection_id`, `collection_layout_page.layout_id`, `collection_layout_slot.page_id`) — **NOVO** |
| `5137` | RPC `set_collection_layout_grid(uuid, integer, integer)` — **NOVO** |
| `5818` | harness funcional **executável completo** (não é schema, não promover) |
| `5819` | harness de performance **executável completo** (não é schema, não promover) |

**Totais reais, contados a partir do SQL final:**
**6 tabelas · 12 trigger functions · 14 triggers · 1 helper interno · 14 RPCs públicas** (27 funções no total).

**Numeração:** `5136` e `5137` estavam livres — `database/schema/` ocupa `5000`–`5103` e esta proposal ocupava `5104`–`5135`. Precheck reexecutado nesta rodada.

---

## 3. Decisões materializadas (DP-01 … DP-10)

| DP | Decisão | Materialização |
|---|---|---|
| **DP-01** | V1 = **0..1 Layout por Collection** | `UNIQUE (collection_id)` em `5105` + guard em `5123`. **Sem `is_primary`.** Múltiplos Layouts = **DEFERRED** |
| **DP-02** | Page order = `page_number INTEGER >= 1` | `UNIQUE (layout_id, page_number) DEFERRABLE INITIALLY DEFERRED` em `5108`; contiguidade 1..N pelas RPCs `5125`/`5126`/`5127` com lock do Layout `FOR UPDATE`. **Sem rank/LexoRank/linked list** |
| **DP-03** | Grid 1..10, mutável só com **ZERO Pages** | CHECKs em `5105` + trigger `5107` (defesa estrutural) + **RPC `5137` `set_collection_layout_grid()`**, que é o único caminho de cliente para exercer essa permissão. **Grid Change com Pages = DEFERRED.** Sem escape "novo Layout" (DP-01 o proíbe): resolver/remover as Pages primeiro |
| **DP-04** | Region = **bounding box** | `5119` (4 colunas + CHECK `height*width >= 2`) + trigger `5121` v2.0, que agora cobre **INSERT, UPDATE e DELETE**, adquire `collection_layout_page … FOR UPDATE` ANTES de validar e torna `page_id` imutável; as RPCs `5134`/`5135` mantêm o lock como precheck amigável. **Sem junction. Sem GiST/EXCLUDE. Sem extensão nova** |
| **DP-05** | Artwork **FORA** | Nenhuma coluna de imagem, nenhum Storage asset, nenhum `VISUAL_ELEMENT` |
| **DP-06** | Expected Content 0..1, Card obrigatória, Variant opcional | `slot_id` como **PK** em `5113`; invariante Variant↔Card por **FK composta** apoiada em `5104` |
| **DP-07** | Assignment → **`collection_allocation`**, não `physical_card` | `5115`: `UNIQUE(slot_id) DEFERRABLE` + `UNIQUE(collection_allocation_id)` + FK CASCADE para Allocation + FK RESTRICT para Slot + trigger `5117` |
| **DP-08** | Lock = atributo do Slot **com enforcement estrutural** | `locked` em `5110` + **trigger `5118`** cobrindo INSERT/UPDATE/DELETE |
| **DP-09** | Page/Slot lifecycle | `5125` cria Page + capacity Slots atomicamente; `5126` recusa Page com dependências; cascades/restricts conforme §5 |
| **DP-10** | Audit/Undo-Redo **FORA** | Só `created_at`/`updated_at`. Sem `status`, sem `ended_at`, sem tabela de histórico |

### Ajustes vindos do MATERIALITY AUDIT (aplicados literalmente)

1. **Sem GiST/EXCLUDE, sem extensão nova** — overlap por trigger + lock de Page.
2. **Sem índice isolado em `collection_layout_slot(page_id)`** — a `UNIQUE (page_id, row_index, column_index)` já tem `page_id` como leading prefix.
3. **Lock com enforcement por trigger**, não só por RPC.
4. **`5104` como migration incremental explícita**, com precheck registrado — a constraint `UNIQUE (id, card_id)` **não existe** hoje em `card_variant` (confirmado read-only em 2026-09-06: só existem `card_variant_pkey`, `uq_card_variant_card_order`, `uq_card_variant_card_type`).
5. **Sem escape "crie outro Layout"** na mensagem de Grid Change.
6. **Concorrência real assumida** — duas abas do mesmo usuário; locks `FOR UPDATE` em ordem determinística.
7. **`5133` fail-fast em bulk** — um Slot locked rejeita a operação inteira.

---

## 4. Binder Slot Assignment ≠ Pokédex Position Assignment

**São relações de domínios diferentes. Nunca confundir, nunca unificar.**

| | `collection_layout_slot_assignment` (esta Foundation) | `collection_pokedex_position_assignment` (Fatia D, `6117`) |
|---|---|---|
| Representa | posição **visual** dentro do Layout | satisfação de uma **Pokédex Position** |
| Participa de completion? | **NÃO** | **SIM** — única fonte do numerator `REFERENCE_POSITION` |
| Chave | `id` + `UNIQUE(slot_id)` + `UNIQUE(collection_allocation_id)` | PK = `collection_allocation_id` |
| Criada automaticamente? | **Nunca** | **Sim**, quando o match de Species é inequívoco (`6119`) |
| `assignment_basis` | não existe | `SPECIES_MATCH` / `USER_OVERRIDE` |

Uma Physical Card pode ter as duas, uma, ou nenhuma. Elas não se implicam, não se sincronizam e não compartilham constraint alguma.

---

## 5. Constraints, FKs, RLS e grants

**Constraints declarativas:** 6 PK · 4 UNIQUE (2 delas `DEFERRABLE INITIALLY DEFERRED`) · 10 CHECK.

**FKs e política de delete** — CASCADE para dentro da estrutura, RESTRICT nas fronteiras de conteúdo e de agregado:

| FK | Delete |
|---|---|
| `slot → page` | **CASCADE** (estrutura; só alcança Page já provada vazia) |
| `assignment → collection_allocation` | **CASCADE** (desalocar remove a Assignment) |
| `assignment → slot` | RESTRICT |
| `expected_content → slot` | RESTRICT |
| `region → page` | RESTRICT |
| `page → layout` | RESTRICT |
| `layout → collection` | RESTRICT |
| `expected_content → card` / `→ card_variant` / FK composta | RESTRICT |

Nenhum DELETE privilegiado apaga conteúdo silenciosamente.

**RLS:** habilitada nas 6 tabelas. **Uma policy `SELECT` própria por tabela**, navegando até `collection.owner_user_id`. **Zero policy de DML.** `GRANT SELECT` para `authenticated`; `REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN` de `anon`/`authenticated`. Nenhum `INSERT`/`UPDATE`/`DELETE` para cliente — toda mutação por RPC.

**Segurança das funções:** todas `SECURITY DEFINER`, `SET search_path = ''` — valor **efetivamente vazio**, provado por `pg_temp._empty_search_path()` sobre `proconfig` (`search_path=public` reprova) —, owner `postgres`. As **14 RPCs**: `REVOKE FROM PUBLIC, anon` + `GRANT TO authenticated`. As **12 trigger functions** e o helper `5122`: `REVOKE FROM PUBLIC, anon, authenticated`.

`SECURITY DEFINER` em `5128` não é conveniência: `card`/`card_variant` estão sob RLS **admin-only** (policy `catalog_admin_select`), e uma função `SECURITY INVOKER` não conseguiria validar a Card para um usuário comum — foi o bloqueio real encontrado na Fatia 02E com `5070`/`5071`.

**Não-enumeração:** ownership provado **antes** de navegar por filhos. Objeto inexistente e objeto alheio produzem a **mesma** mensagem (`'... not found or not owned by caller'`).

**ARCHIVED:** toda mutação exige `lifecycle_status = 'ACTIVE'` (helper `5122`). Leitura permitida; único caminho é `reactivate_collection()` → editar → `archive_collection()`.

---

## 6. Índices

**Zero índice de performance criado previamente.** Apenas os estruturais, implícitos de PK/UNIQUE:

| Tabela | Índices |
|---|---|
| `collection_layout` | PK · `UNIQUE(collection_id)` |
| `collection_layout_page` | PK · `UNIQUE(layout_id, page_number)` |
| `collection_layout_slot` | PK · `UNIQUE(page_id, row_index, column_index)` |
| `collection_layout_slot_expected_content` | PK (`slot_id`) |
| `collection_layout_slot_assignment` | PK · `UNIQUE(slot_id)` · `UNIQUE(collection_allocation_id)` |
| `collection_layout_region` | PK |

`5104` cria `UNIQUE (id, card_id)` em `card_variant` — **constraint-supporting**, não índice de performance.

O harness `5819` decide, com plano real na mão, se algum índice adicional é necessário. Nenhuma proposta especulativa — e **nenhum índice é criado antes da medição**, por regra explícita do próprio `5819`.

---

## 6-B. Limites de lote em payload `UUID[]` (CORREÇÃO CONSOLIDADA 02)

**Motivo:** *bounded work* / proteção operacional. Uma RPC pública
`SECURITY DEFINER` não pode executar trabalho proporcional a um array
enviado pelo cliente antes de decidir se aceita a chamada. Alinhado aos
bulk RPCs canônicos já vigentes — `5024 set_physical_cards_storage()`,
`5046 allocate_physical_cards_to_collection()`,
`5047 deallocate_physical_cards_from_collection()`.

| RPC | Regra |
|---|---|
| `5129 clear_slot_expected_content(uuid[])` | **raw limit = 500** |
| `5130 set_slot_lock(uuid[], boolean)` | **raw limit = 500** |
| `5133 remove_slot_assignment(uuid[])` | **raw limit = 500** |
| `5127 reorder_layout_pages(uuid, uuid[])` | **sem cap** — ver abaixo |

- **CONTRATO UNIDIMENSIONAL.** As quatro RPCs aceitam somente
  `array_ndims(...) = 1`. Qualquer payload multidimensional é
  rejeitado **antes** de qualquer `unnest`/`DISTINCT`, resolve de
  ownership, lock ou mutação.
- O limite é avaliado sobre a **CARDINALIDADE REAL** do payload
  recebido — `cardinality(...)`, que conta TODOS os elementos em
  qualquer número de dimensões — e **antes da deduplicação**.
  **`array_length(x, 1)` não é usado em nenhuma das quatro RPCs**:
  ele mede apenas a primeira dimensão e `array_fill(u, ARRAY[2,300])`
  o faria devolver `2` para um payload de 600 elementos.
- Um array com 501 elementos **todos repetidos** também é rejeitado.
  Isso é condição **necessária, não suficiente**: sozinho, esse caso
  passaria mesmo com `array_length`. A prova de que o guard é
  realmente sobre o payload bruto vem do conjunto —
  `B02`/`B05`/`B08` (501 repetidos) **somados a**
  `B13`–`B18` (multidimensional, `dim1` pequena e cardinalidade
  grande) **e a** `B10`/`B11` (STATIC PROOF de que a rejeição efetiva
  precede o primeiro `unnest`/`DISTINCT` e de que `array_length`
  não existe mais no corpo executável).
- Mensagem canônica, idêntica à de 5024/5046/5047:
  `lote excede o limite de 500 itens por chamada`.
- **`reorder_layout_pages` não recebe cap arbitrário.** Seu contrato é
  "todas as Pages do Layout, na nova ordem"; um teto fixo quebraria
  produto num Binder grande. O que ela faz é **rejeitar forma e
  cardinalidade incompatíveis ANTES do `DISTINCT`/`unnest`**: valida
  `array_ndims = 1`, calcula `cardinality(...)` e, com o Layout já
  serializado pelo helper, compara com o total de Pages que o banco
  já conhece — falhando imediatamente se divergirem. Sem isso, um
  payload 2-D cuja **primeira dimensão coincidisse** com o total de
  Pages atravessaria o short-circuit (caso `B20`). A revalidação
  pós-lock de total e pertencimento foi preservada integralmente.
  `B12` prova a ausência de cap: zero literal `500` no corpo
  executável e zero comparação de cardinalidade contra literal
  numérico, e nenhuma comparação de `v_input_count` contra operando
  fora das whitelists — **em NENHUM dos dois lados da comparação**.
  Três varreduras: à direita de `v_input_count` (`{v_total_pages, 0}`),
  à esquerda de `v_input_count` (`{v_total_pages, 0, v_distinct_count,
  v_belong_count}`) e à direita de `cardinality(...)`
  (`{v_total_pages, 0}`). Um cap escrito como `c_max < v_input_count`
  ou `1000 <= v_input_count` — via literal, constante ou variável —
  também reprova o gate.
- `5819` **não muda**: o W9 (bulk lock) usa 400 Slots e permanece
  válido sob o teto de 500.

---

## 7. Riscos registrados

| # | Risco | Mitigação / status |
|---|---|---|
| R1 | **`5118` e o CASCADE de desalocação.** O trigger de Lock precisa distinguir "REMOVE pelo Layout" de "CASCADE da desalocação". A detecção usa a ausência da linha-pai de `collection_allocation` no momento em que o trigger da filha dispara. | **R1 permanece um risco a ser PROVADO pelo K12, não uma premissa aceita.** O `5818` prova por **comportamento real**, não por comentário sobre ordem de RI trigger: `K12` executa o `DELETE` da Allocation e exige que o CASCADE passe pelo Slot locked sem erro; `K12b` é a **contraprova** — com a Allocation viva, o `DELETE` direto da Assignment no mesmo Slot locked ainda é bloqueado. Se `K12` falhar, é **BLOCKER e achado real a reportar**, nunca a contornar. |
| R2 | **`UNIQUE(collection_allocation_id)` é V1.** Decorre de DP-01. Quando múltiplos Layouts forem habilitados, precisará ser revista junto da cardinalidade (Physical Card, Layout). | Registrado em COMMENT ON CONSTRAINT, no header de `5115` e aqui. |
| R3 | **`5104` altera tabela do Catálogo Editorial.** | Aditiva e não-rejeitante: `id` já é PK, logo `(id, card_id)` é trivialmente único. Nenhuma linha existente ou futura é recusada. Precheck obrigatório antes de aplicar. |
| R4 | **Overlap de Region depende de trigger + lock**, não de constraint declarativa (sem GiST por decisão). | Trigger `5121` fecha o caminho privilegiado; RPCs `5134`/`5135` lockam a Page `FOR UPDATE` antes de validar. Casos R7/R14 do `5818`. |
| R5 | **Concorrência real entre duas sessões** pode não ser demonstrável no ambiente de execução. | Caso **C4** do `5818` manda registrar **NOT PROVEN** explicitamente. Precedente: Caso 20b da Fatia D. |
| R6 | ~~`5818`/`5819` são contratos, ainda não SQL executável completo.~~ **RESOLVIDO em `...-STAGING-HARNESS-COMPLETION-01`.** | `5818` v2.0 e `5819` v2.0 são **harnesses executáveis completos**: nenhum pseudo-SQL, nenhuma seção "a executar depois", nenhum caso adiado para gate futuro. Ambos permanecem **NÃO EXECUTADOS** — o que falta é o GO, não o SQL. |
| R7 | **Grid Change fica sem caminho de produto na V1.** | Consequência aceita de DP-01 + DP-03. Registrado como DEFERRED; exige a política de reconciliação que C-40 não decidiu. |
| R8 | **MOVE via `UPDATE`** exige que o `id` da Assignment seja preservado. | `id` técnico próprio (não PK sobre `slot_id`) torna isso natural; casos **A5**/**A6** do `5818` verificam a preservação. |
| R9 | **Ordem de lock COLLECTION → LAYOUT é obrigatória em TODAS as RPCs.** Inverter em uma delas reintroduz deadlock e a corrida com `archive_collection()`. | Centralizada no helper `5122` v2.0, que nenhuma RPC contorna. Prova estática **C01** do `5818` lê `pg_get_functiondef()` e confere a sequência. |
| R10 | **`pg_locks` não prova serialização de LINHA.** Locks de tupla só aparecem sob contenção real, que uma única sessão não produz. | `5818` §13 separa STATIC PROOF (C01/C05), SUPPORTING EVIDENCE (C02/C03) e REAL TWO-SESSION (C04, **NOT PROVEN** sem duas sessões). Nunca se converte ausência de tuple lock em FAIL. |
| R11 | **Concorrência real entre duas sessões continua NÃO PROVADA** enquanto o canal de execução oferecer só uma sessão. | C04 e R18 do `5818` registram **NOT PROVEN** explicitamente. Só é `PROVEN` se duas sessões forem de fato executadas. |
| R13 | **Payload `UUID[]` ilimitado em RPC SECURITY DEFINER.** A mitigação da `CORRECTION-02` era ela própria contornável: media `array_length(x, 1)`. | **MITIGADO — e a mitigação agora é ela mesma verificada.** Contrato unidimensional (`array_ndims <> 1` rejeitado) + teto sobre `cardinality()` em `5129`/`5130`/`5133`; forma + short-circuit de cardinalidade antes do `unnest` em `5127`. Gates: `B01`–`B09` (500/501), `B13`–`B19` (multidimensional), `B20` (multidimensional que engana `array_length` no reorder), `B10`/`B11` (STATIC PROOF de ordem e de ausência de `array_length`), `B12` (ausência de cap no reorder). |
| R14 | **O padrão canônico citado como precedente (`5024`/`5046`/`5047`) tinha o MESMO defeito** — verificado no repositório, não presumido. | Hardening preparado como migrations incrementais **em staging separado**: `database/proposals/2026-09-06-bulk-payload-cardinality-hardening/` (`5138`/`5139`/`5140`) **+ harness executável `5820`**, cuja execução com PASS é pré-requisito do GO. **NADA executado.** Migrations históricas intactas. `2081`/`2144` reclassificados como **hardening de contrato / admin-only** e `5098`/`5099` como **baixa severidade** — registrados lá, para rodada própria, sem bloquear este GO. |
| R12 | **Não-enumeração cross-user depende de um segundo `auth.users`.** | A prova ESTRUTURAL (**Z09**, source-level) é obrigatória e sempre roda. As provas dinâmicas (Z11/Z12/U09) viram **NOT PROVEN** sem segundo usuário — nunca PASS. |

---

## 8. Explicitamente DEFERRED

1. Múltiplos Layouts por Collection (falta a decisão principal/alternativo).
2. Grid Change com Pages existentes (falta a política de reconciliação de Slots).
3. Artwork / conteúdo visual de Layout Region.
4. `VISUAL_ELEMENT` como tipo de Slot (hipótese do benchmark §15, nunca promovida).
5. Audit / Undo-Redo de Slot Assignment (frente Activity History/Audit, LDM-154–174).
6. Persistência da Bandeja — **não é pendência**: C-45/LDM-36 fecham que é estado transitório de UX. **A Bandeja não persiste.** "Slot A → Bandeja → Slot B" tem como único resultado persistente "A → B".
7. Storage Layout (organização interna de Container independente de Collection).
8. Colaboração/permissões de Layout — `collection.visibility` está travado em `PRIVATE` por CHECK.
9. Capacity planning ("faltam N slots" — benchmark §16).
10. Read models de UX / contratos de leitura — fase posterior, **não criados aqui**.

---

## 9. Estado desta pasta

| Artefato | Estado |
|---|---|
| `5104`–`5137` (34 arquivos) | **PROPOSTA — STAGING, NÃO EXECUTADO** |
| `5818` v7.1 | **COMPLETE EXECUTABLE VALIDATION HARNESS** — **205 rótulos de caso únicos** nos grupos S·L·G·P·E·A·B·K·R·D·Z·C·X·F·N·U; `BEGIN…ROLLBACK`; três estados (`PASS` / `FAIL` / `NOT PROVEN`). Gates `B10`/`B11` localizam o `RAISE EXCEPTION` real (não a string solta); `B12` reprova cap via constante/variável **em ambos os lados da comparação**; `C01` vincula cada `FOR UPDATE` ao MESMO `SELECT`; `S18`/`U00`/`Z08` provam `search_path` **efetivamente vazio** (não apenas presente). Executado em **duas chamadas** (ver §11). **v7.1 (`HARNESS-FIX-01`)**: `GRANT ALL ON _v, _fx TO authenticated` + `GRANT` na sequence, imediatamente após as `CREATE TEMP TABLE` — objetos TEMP não herdam privilégio de `PUBLIC` e, sem isso, o primeiro `pg_temp._rec` sob `SET LOCAL ROLE authenticated` abortava com `42501` (defeito real encontrado na primeira execução; padrão idêntico ao já aprovado em `5820`/`5819`/`5814`). Nenhum gate, caso ou regra foi alterado. |
| `5819` v3.0 | **COMPLETE EXECUTABLE PERFORMANCE HARNESS / NOT EXECUTED** — fixture de 1 Collection / 1 Layout 4×4 / 100 Pages / 1600 Slots / 800 Assignments / 400 Expected Content / 50 Regions + os **12 workloads** materializados (W1…W12), `BEGIN…ROLLBACK`. Nenhum pseudo-SQL. |
| Banco | **INTOCADO** — nenhum objeto criado |
| `database/schema/` | **INTOCADO** — nada promovido |
| Docs canônicos | **INTOCADOS** |
| Frontend / Edge Functions | **INTOCADOS** |
| Extensões PostgreSQL | **NENHUMA nova** |
| git | **Nenhum add/commit/push** |

**Numeração:** precheck reexecutado em 2026-09-06 — `database/schema/` ocupa `5000`–`5103`; `5104`–`5137` livres e agora ocupados por esta proposal. Validações `5800`–`5817` ocupadas; `5818`/`5819` desta proposal. Nenhum número reutilizado, nenhum gap inventado.

**Extensões PostgreSQL:** **NENHUMA nova.** Sem `btree_gist`, sem GiST, sem `EXCLUDE`.

**Índices de performance:** **NENHUM criado especulativamente.** `5104` é constraint-supporting. Qualquer índice novo só nasce de um BLOCKER **medido** pelo `5819`, em rodada própria.

**Concorrência:** serialização real entre duas sessões só será `PROVEN` se duas sessões forem de fato executadas. Enquanto isso, `NOT PROVEN` — nunca PASS.

---

## 10. CORREÇÃO CONSOLIDADA 01 — o que mudou e por quê

A SINGLE DIRECT AUDIT sobre os arquivos reais encontrou blockers. Todos
foram corrigidos nesta rodada, dentro da proposal e apenas nela.

| § | Blocker encontrado | Correção aplicada | Arquivos |
|---|---|---|---|
| 1 | **`min(uuid)` não existe no PostgreSQL.** As três RPCs de array chamavam `min(p.layout_id)`; a primeira execução abortaria com `function min(uuid) does not exist`. | Removido sem aggregate customizado e sem cast para `text`: conta-se `count(DISTINCT layout_id)`, exige-se 1, e o `layout_id` vem de consulta separada e determinística. | `5129` `5130` `5133` |
| 2 | **Race ARCHIVED + ordem de lock.** O helper fazia `FOR UPDATE OF l` (só o Layout) e lia `lifecycle_status` sem lock: `archive_collection()` concorrente passava despercebida. | Ordem canônica **COLLECTION → LAYOUT**, com o `lifecycle_status` avaliado sob o lock e revalidação pós-lock. Nenhuma RPC inverte a ordem. | `5122` |
| 3 | **Snapshot pré-lock usado após o lock.** O caso mais grave: `remove_layout_page()` lia `page_number` antes do lock e renumerava com o valor velho. | Disciplina obrigatória em todas as RPCs: OWNER-FILTERED RESOLVE → COLLECTION LOCK → LAYOUT LOCK → RE-READ/REVALIDATE → CALCULAR → MUTAR. | `5126`–`5135` |
| 4A | **Oráculo de existência em arrays.** `[próprio + alheio existente]` falhava diferente de `[próprio + inexistente]`. | Dedup → resolve owner-scoped → mensagem genérica única → só então "mesmo Layout" → revalidação pós-lock. | `5129` `5130` `5133` |
| 4B | **MOVE comparava Layouts antes de provar ownership** dos dois Slots. | Ambos resolvidos owner-scoped primeiro; qualquer um invisível dá a mesma mensagem. | `5132` |
| 4C | **ASSIGN carregava Allocation arbitrária** e revelava que era de outra Collection. | Allocation buscada já escopada ao `collection_id` do Layout; inexistente / outra Collection / outro Owner colapsam numa mensagem só. | `5131` |
| 5 | **DP-03 era inalcançável.** Alterar o grid com zero Pages era permitido pelo trigger, mas não havia RPC e não há DML para `authenticated`. | Nova RPC `set_collection_layout_grid()`. Sem novo Layout, sem rebuild, sem Grid migration. | `5137` (novo) |
| 6 | **`collection_allocation_id` era mutável por UPDATE** — violava REPLACE = delete+insert e permitia **bypass de Lock** (o `slot_id` não mudava, então o trigger de Lock não disparava). | UPDATE que altere `collection_allocation_id` é rejeitado, com ou sem Lock; a mensagem orienta ao REPLACE. MOVE/SWAP seguem permitidos (alteram `slot_id`). | `5117` |
| 7 | **Bypass estrutural pai→filho.** UPDATE privilegiado de `collection_layout.collection_id`, `page.layout_id` ou `slot.page_id` mudava a Collection efetiva do Slot sem disparar `5117`. | Três triggers de imutabilidade (uma função genérica). `region.page_id` idem, na defesa de Region. | `5136` (novo), `5121` |
| 8 | **Region sem defesa em DELETE e sem lock no trigger.** Unmerge dependia só da RPC; o trigger não serializava o overlap. | Trigger `BEFORE INSERT OR UPDATE OR DELETE`, lock da Page antes de validar, geometria OLD conferida no UPDATE, `page_id` imutável. | `5121` |
| 9 | **DML ausente por default privileges, não por REVOKE.** | `REVOKE INSERT, UPDATE, DELETE FROM PUBLIC, anon, authenticated` explícito nas SEIS tabelas. | `5105` `5108` `5110` `5113` `5115` `5119` |
| 10 | **Fragmentos sem acento** comparados com mensagens acentuadas → falso FAIL garantido. | `pg_temp._norm()` remove diacríticos dos DOIS lados. Substring não foi relaxada; erro inesperado continua FALSE. | `5818` |
| 11 | **E09 era PASS vazio** (fixture OPEN_CURATION/NONE devolve 0 linhas por contrato). | Fixture dedicada REFERENCE_BASED/CARD_SET/STANDARD_SET via RPC real, sob o Owner; **baseline vazio = FAIL**. | `5818` |
| 12 | **R13 podia ser vácuo** (digests `EMPTY` dos dois lados). | Expected Content real criado num Slot da Region; contagens de Assignment e EC viram gates; `EMPTY` = FAIL. | `5818` |
| 13 | **`pg_locks` tratado como prova de row lock.** | Três níveis: STATIC PROOF (C01/C05), SUPPORTING EVIDENCE (C02/C03), REAL TWO-SESSION (C04 = NOT PROVEN). | `5818` |
| 14 | **Protocolo de execução errado** — dizia que uma chamada devolveria o relatório. | Protocolo explícito em duas chamadas (§11). `X02` passa a ser evidência ESTÁTICA, não prova de zero resíduo. | `5818` |
| 15 | **Cobertura de segurança incompleta** (Z01 verificava 5 de 6 tabelas). | Seis tabelas; três grantees; owner das funções; provas estruturais Z09/Z10; casos negativos de não-enumeração. | `5818` |
| 16 | **W12-G3 incompleto e frágil** — omitia `collection_completion_positions()` e usava `ILIKE` (onde `_` é wildcard). | As 4 funções verificadas; comentários removidos do `pg_get_functiondef`; busca literal por `position()`. | `5819` |
| 17 | Higiene: referência a um workload `W_ADDPAGE` inexistente; W5 atribuído a DP-03 em vez de DP-02. | Corrigidos. | `5819` |

---

## 10-bis. Registro de execução — `IMPLEMENTATION-01` (2026-09-07)

### `5137` histórico × `5141` efetivo

| Query | Papel | Observação |
|---|---|---|
| `5137` | **DEFINIÇÃO HISTÓRICA APLICADA** | Aplicada em 2026-09-07 junto com `5104`–`5136`. **Não é editada.** Continha, no `UPDATE`, `WHERE id = p_layout_id` — `id` colidindo com a variável de saída homônima do `RETURNS TABLE`. Defeito **descoberto em runtime** pela primeira execução completa do `5818` (casos `U01`/`U01b`/`U02`/`U03`, `42702 column reference "id" is ambiguous`). Enquanto vigorou sozinha, `set_collection_layout_grid()` estava **quebrada**. |
| `5141` | **DEFINIÇÃO EFETIVA** | `CREATE OR REPLACE` incremental. Qualifica a coluna: `UPDATE public.collection_layout AS l ... WHERE l.id = p_layout_id`. Mesma assinatura, retorno, `SECURITY DEFINER`, `search_path=''`, grants e regras. Precedentes da mesma classe: `6109` (RETURNING ambíguo) e `6126` (ON CONFLICT ambíguo). |

**Migrations históricas não são reescritas.** A definição corrente da função é sempre a última aplicada — aqui, `5141`.

### Desvio documental do ledger (`5104`/`5105`)

As migrations `5104` e `5105` foram gravadas em `supabase_migrations.schema_migrations` **sem o cabeçalho de comentário integral** do arquivo de staging (`5104`: apenas o DDL; `5105`: cabeçalho abreviado). Da `5106` em diante o conteúdo íntegro foi gravado.

- O **SQL executável aplicado é idêntico** ao do arquivo em ambos os casos — verificável por `uq_card_variant_id_card` e pela estrutura de `collection_layout`.
- Os arquivos canônicos em `database/proposals/` estão **intactos**.
- O ledger **não é reescrito retroativamente**: a referência material é o SQL aplicado, e o desvio fica registrado aqui.

### Resultado do `5818` v7.2

`196 TOTAL · 194 PASS · 0 FAIL · 2 NOT PROVEN`, sendo os dois NOT PROVEN **exatamente** `C04` e `R18`. Zero resíduo confirmado por postcheck pós-execução. A prova de `C04`/`R18` é **externa**, em duas sessões reais — ver `CONCURRENCY-PROOF-C04-R18.sql` nesta pasta (roteiro manual, não é migration).

---

## 10-ter. FECHAMENTO — `IMPLEMENTATION-01` (2026-09-07)

**Status desta pasta: IMPLEMENTED / VALIDATED.** Promoção para `database/schema/` e commit/push **continuam não autorizados**.

### Evidência consolidada

| Artefato | Resultado | Observação |
|---|---|---|
| `5104`–`5137` | **APLICADOS** | ordem da §1; ledger `20260907130*`–`131647` |
| `5141` | **APLICADO** | ledger `20260907204231`; definição efetiva de `set_collection_layout_grid()` |
| `5818` v7.2 | **196 / 196 runtime** | 194 PASS automáticos + `C04` e `R18` provados externamente. `FAIL = 0`. |
| `CONCURRENCY-PROOF-C04-R18.sql` v2.0 | **C04 PASS · R18 PASS** | prova manual em duas sessões mutantes + uma observadora |
| `5819` v3.0 | **22 / 22 HEALTHY** | 0 BLOCKER, 0 UNKNOWN, 0 ATTENTION |
| `5138`/`5139`/`5140` | **APLICADOS** | ledger `20260907215740` / `215826` / `215905` |
| `5820` v1.2 | **27 / 27 runtime** | gate retificado; ver README do hardening §6-bis |

### `5818` — como os 196 fecham

Os 205 rótulos estáticos incluem 9 de ramo mutuamente exclusivo; o máximo de runtime é **196**. Destes, 194 fecharam automaticamente e 2 — `C04` (serialização real entre duas sessões) e `R18` (overlap concorrente de Region) — ficaram `NOT PROVEN` **por honestidade**: o canal MCP não sustenta duas sessões simultâneas. Nunca foram convertidos artificialmente em PASS.

Prova externa executada manualmente, com resultado registrado:

- **`C04` PASS** — B bloqueada por A; `pg_blocking_pids(B)` apontou `PID_A`; B só prosseguiu após o `COMMIT` de A; estado final do Slot `locked = false`.
- **`R18` PASS** — B bloqueada por A; `pg_blocking_pids(B)` apontou `PID_A`; após o `COMMIT` de A, B falhou com o erro de overlap de Region; `regions_na_page = 1`.
- Fixture `__C04R18__`: **zero resíduo**. Role temporária `mmkyu_concurrency_test`: **removida** (`count = 0`).

**Total funcional: `196 / 196` runtime, `FAIL = 0`.**

### `5819` — 22 workloads, todos HEALTHY

W1 `0,288 ms` · W2 `0,206` · W3 `0,783` · W4 `2,294` · W10a `0,025` · W11 `3,656` · W5 `17,450` · W6 `8,255` · W7 `2,695` · W8 `9,407` · W10b `3,689` · W9 `32,984` — todos com folga larga sobre o limiar HEALTHY declarado. `W12-G3` confirmou que **nenhuma** das 4 funções de Completion referencia `collection_layout*` no corpo executável. `W12-G1` payload idêntico antes/depois do Layout (`total_positions = 284`, `satisfied = 134`, `47,18 %`), `G2` cardinalidade `1 = 1`, `G4` buffers `1342 → 1342`, `G5` ruído `4,757 → 5,148 ms`. **Nenhum índice novo foi criado** — a regra de ouro do harness foi respeitada.

### Postcheck final

- **6 tabelas Binder**, todas owner `postgres`, RLS habilitado, 1 policy cada, `anon SELECT = false`.
- **15 funções Binder**, 1 overload cada, `SECURITY DEFINER`, `search_path` **efetivamente vazio**, owner `postgres`, `anon EXECUTE = false`. `assert_collection_layout_mutable` (5122) não concede `EXECUTE` a `authenticated` — helper interno, correto por desenho.
- **`set_collection_layout_grid()` = `5141`**: `update_aliasado = t`, `where_qualificado = t`, `ainda_tem_where_ambiguo = f`, assinatura e retorno preservados.
- **Zero resíduo**: `__5818_*`, `VAL-5818*`, `__5819_*`, `__5820_*`, `__C04R18__` = 0; layouts/pages/slots/assignments/expected/regions/allocations/physical_card = 0; role `mmkyu_concurrency_test` = 0.

### Hardening `5138`–`5140`

Aplicado e validado nesta mesma rodada — ver `database/proposals/2026-09-06-bulk-payload-cardinality-hardening/README.md`. As três funções (`set_physical_cards_storage`, `allocate_physical_cards_to_collection`, `deallocate_physical_cards_from_collection`) passaram a usar `cardinality()` + `array_ndims(...) <> 1`, com **zero `array_length`** no corpo executável.

### ESCOPO DA AFIRMAÇÃO DE SEGURANÇA — leia antes de citar

A classe do **bypass multidimensional** está fechada **nas RPCs do escopo desta implementação**, e apenas nelas:

- as 3 bulk canônicas (`5138`/`5139`/`5140`);
- as 4 RPCs do Binder com parâmetro `uuid[]`: `reorder_layout_pages`, `clear_slot_expected_content`, `set_slot_lock`, `remove_slot_assignment`.

**Não se afirma ausência do bypass em todo o sistema.**

### PENDÊNCIA ABERTA — achado adjacente não corrigido

O postcheck varreu **todas** as funções `public` com parâmetro `uuid[]`, não só as do escopo, e encontrou:

> **`get_cards_pricing_summary(p_card_ids uuid[])`** — `SECURITY DEFINER`, `search_path=""`, owner `postgres`, `EXECUTE` para `authenticated` — **mantém o bypass multidimensional preexistente**: o teto `IF array_length(p_card_ids, 1) > 100` é avaliado **antes** do `unnest(p_card_ids)`. `array_fill(uuid, ARRAY[2,300])` tem `array_length(x,1) = 2` (passa) e `cardinality(x) = 600` (o que é processado). Mesma classe de `5024`/`5046`/`5047`.

**Não corrigido nesta rodada, por decisão explícita.** Próxima ação obrigatória do projeto: **`PRICING-PAYLOAD-CARDINALITY-HARDENING-01`**.

**Bulk Collection Operations NÃO pode iniciar antes** desse hardening estar aplicado e validado.

Registrado **separadamente**, fora do hardening de Pricing, como **hardening de contrato `UUID[]` / admin**: `admin_decide_catalog_import_row` (o guard `array_length(...,1) <> 1` é burlável por array 2-D com dim1 = 1) e os usos que só checam `IS NULL` sem teto — `admin_decide_catalog_variant_import_row`, `create_reference_based_pokedex_collection`, `set_collection_pokedex_scope`, `admin_confirm_catalog_import`, `admin_confirm_catalog_variant_import`.

---

## 11. Protocolo de execução do `5818` (DUAS CHAMADAS)

O executor deste projeto devolve **apenas o resultado do último
statement**. Portanto:

```
CALL 1 → do `BEGIN;` até o `SELECT` final do relatório, INCLUSIVE.
          É esta chamada que devolve o relatório.
CALL 2 → `ROLLBACK;`
```

Executar em **uma única chamada que inclua também o `ROLLBACK;`** não
perde a garantia transacional, mas **não devolve o relatório** — o
último statement passa a ser o `ROLLBACK`, que não retorna linhas. Não
afirmar o contrário.

**Comportamento real do canal (medido em `IMPLEMENTATION-01`, não
presumido):** o executor **não preserva sessão nem transação entre
chamadas** — uma `TEMP TABLE` criada na CALL 1 já não existe na CALL 2.
Portanto **não se afirma** que a transação permanece aberta até a
CALL 2: ela é encerrada por **ROLLBACK implícito ao término da CALL 1**,
porque o script abre `BEGIN;` e nunca emite `COMMIT;`. A CALL 2
permanece no protocolo como confirmação explícita de que nada ficou
pendente, e é um **no-op** quando a sessão já foi encerrada. O efeito
sobre zero resíduo é o mesmo — se algo, mais forte, porque o descarte
não depende de a CALL 2 chegar.

`X02` é **evidência estática** de que o arquivo termina em `ROLLBACK` e
não contém `COMMIT`. **Zero resíduo real só pode ser afirmado após a
execução e o postcheck correspondente**, na rodada de IMPLEMENTAÇÃO.

---

## 12. GO/NO-GO — RESOLVIDO

O GO foi concedido e a rodada `IMPLEMENTATION-01` foi executada em
2026-09-07 (registro em §10-bis e §10-ter). Estado real ao final:

- `5104`–`5137` = **APLICADOS** (34 arquivos SQL de schema)
- `5141` = **APLICADO** — definição efetiva de
  `set_collection_layout_grid()`, corrigindo o defeito de ambiguidade
  descoberto em runtime no `5137`
- `5818` v7.2 = **EXECUTADO — 196/196 runtime, FAIL 0**
- `5819` v3.0 = **EXECUTADO — 22/22 HEALTHY**
- `5138`–`5140` = **APLICADOS**; `5820` v1.2 = **EXECUTADO — 27/27**
- `CONCURRENCY-PROOF-C04-R18.sql` v2.0 = **EXECUTADO manualmente —
  `C04` PASS e `R18` PASS**, ambos com bloqueio comprovado por
  `pg_blocking_pids`
- **R1** deixou de ser risco em aberto: foi **PROVADO** pelo `K12` do
  `5818` na execução real
- Concorrência real entre duas sessões: **PROVADA** — não é mais
  `NOT PROVEN`

**Ainda pendente e NÃO autorizado:** promoção para `database/schema/`
e commit/push. Ambos dependem de decisão explícita de Fabrício.

**Pendência de segurança fora desta pasta:** ver §10-ter — o bypass
multidimensional permanece vivo em `get_cards_pricing_summary()`, a ser
fechado por `PRICING-PAYLOAD-CARDINALITY-HARDENING-01`, que **precede
obrigatoriamente** o início de Bulk Collection Operations.
