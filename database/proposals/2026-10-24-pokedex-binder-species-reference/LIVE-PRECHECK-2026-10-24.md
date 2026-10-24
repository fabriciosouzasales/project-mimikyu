# POKEDEX-BINDER-SPECIES-REFERENCE — precheck LIVE (LIVE-PRECHECK-01)

| | |
|---|---|
| Data | 2026-10-24 |
| Projeto | `mimikyu-core` (`qjfutqujxrbzgrtkpgkg`), sa-east-1, PG 17.6, ACTIVE_HEALTHY |
| Autorização | Fabrício: somente leitura |
| Proteção | cada consulta em `begin transaction read only; set local statement_timeout = '30s'` (confirmado `transaction_read_only = on`, `30s`); uma consulta por vez |
| Escritas | nenhuma. Migrations 5257–5260, harness 5857 e scripts de recuperação **não executados** |
| Veredito | **GO** para uma futura autorização da implantação (nenhuma divergência bloqueante) |

## 1. Ledger e ausência dos objetos novos

| Verificação | Resultado |
|---|---|
| Ledger | 524 linhas; ponta `20261024132349 5256_binder_physical_location_contract` |
| 5257–5260 / 5857 no ledger | 0 |
| Tabelas `collection_layout_slot_species_reference` e `…_setting` | ausentes |
| Funções novas (9 nomes de 5257–5259) | 0 |
| `remove_layout_page` | só a assinatura `(p_page_id uuid)`; `(uuid, integer)` ausente |
| Nomes de constraint, índice e gatilho da 5257 | nenhuma colisão |

## 2. Dependências dos contratos

- 15 tabelas e 23 colunas usadas por 5257–5260: todas presentes (0 ausentes).
- Funções de apoio presentes: `assert_collection_layout_mutable(uuid)` (5122), `binder_slot_image_resolve_layout(uuid)` (5234), `add_layout_page(uuid)` (5125).
- `remove_layout_page(uuid)` no LIVE: md5 do corpo `5342bc105765151faf5a9d43e9a9d3c2`, **idêntico** ao corpo de `database/schema/5235`. A preservação da 5235 dentro da 5260 (static check S6) vale para o LIVE.
- `reference_kind` no LIVE: `CARD_SET`, `POKEDEX`; `scope_kind`: `GENERATION_FILTERED`. Os valores usados pelos contratos existem.

## 3. F002 — Minha Pokédex

| Item | Valor |
|---|---|
| Layout | `bd2c0834-1310-4239-9aed-012df74ae97b`, grade 4×4 |
| Proprietária | `01352192-af60-4f97-9394-4dc5b5418bcc` "Minha Pokédex", REFERENCE_BASED / REFERENCE_POSITION / ACTIVE |
| Local | `0cc2006b-fca0-4dd7-b576-2b818d10bc32` "F002 - Fichário Pokédex" |
| Páginas | 66 (1–66, contíguas); 0 páginas com quantidade diferente de 16 bolsos |
| Bolsos | 1.056 |
| Cartas / reservas / imagens / mesclagens / travas / convidadas | 0 / 0 / 0 / 0 / 0 / 0 |
| Escopo | 1 referência POKEDEX, `GENERATION_FILTERED`; 1.025 posições (#1–#1025), 1.025 espécies distintas |
| Arte | 1.025/1.025 com `IMPORTED` e `display_storage_path` no formato aceito pelo frontend (`official-artwork/NNNN/w320-<hash>.webp`) |
| Plano simulado (mesma regra da 5258, só leitura) | 1.025 pares, 0 fora de ordem (bolso *n* ↔ #n), páginas 1–65, 31 bolsos livres, último par no bolso 1.025 (página 65) |
| `plan_token` esperado | `28649da348c218fd4be497ee2cab633e0df5b567fe3e6c4c52856efa622eca9e` (deve coincidir com a prévia da 5258 se nada mudar no fichário) |

## 4. Os dois fichários

| | F001 "Celebração de 30 Anos" | F002 "Minha Pokédex" |
|---|---|---|
| Layout | `0d550088-…e6b7`, 3×3 | `bd2c0834-…e97b`, 4×4 |
| Páginas / bolsos | 40 / 360 | 66 / 1.056 |
| Posições | 182 | 0 |
| Posições fora do local físico | 0 | 0 |
| Números de página duplicados | 0 | 0 |
| Numeração contígua | sim | sim |

Outras sessões ativas: 0. Últimas escritas: `physical_card` 2026-10-23 23:14 UTC; posições 2026-10-24 13:02 UTC; páginas 2026-10-24 14:45 UTC (páginas do F002, já conhecidas).

## 5. Fingerprints de referência (comparar no postcheck)

| Fingerprint | Valor | vs. baseline Fase B |
|---|---|---|
| `assignments_md5` | `b010d1de3453373f741d994e3f2f839b` | = |
| `layout_md5` | `b0906e79695b8a049b9120d99d4f7079` | = |
| `allocations_md5` | `a180e923764e3b5a9cb225ee68f873c0` | = |
| `physical_storage_md5` (`md5(string_agg(id‖':'‖coalesce(storage_container_id,''), ',' order by id))` de `physical_card`) | `a4ff5a068ba232d1e16665ec5e209b1e` | ver §6 |
| `pages_md5` (`id:layout_id:page_number`) | `6ab7dc636d36efe68810ea1ab015b7d4` | novo |
| `slots_md5` (`id:page_id:row:column:locked`) | `c449aceb97ba62460d023cbe50fb42cc` | novo |
| `reservations_md5` (`slot:card:variant:variant_type`) | `3d13a7f2dcbd99ef0a842602543368ef` | novo |

Contagens: fichários 2 · páginas 106 · bolsos 1.416 · posições 182 · reservas 158 · alocações 211 · imagens de bolso 0 · regiões 1 · travados 0 · convidadas 1 · exemplares 1.352.

`assignments_md5`, `layout_md5` e `allocations_md5` usam as mesmas fórmulas do LIVE_00/LIVE_50 da proposta BINDER-PHYSICAL-LOCATION.

## 6. Divergências

- **Não bloqueante:** o `physical_storage_md5` desta rodada (`a4ff5a06…`) é diferente do registrado na Fase B (`b7f9597e…`). A fórmula da Fase B não ficou documentada no repositório, e a desta rodada foi escrita agora. A última escrita em `physical_card` (2026-10-23 23:14 UTC) é **anterior** ao baseline da Fase B, então a diferença é de fórmula, não de dado. A partir de agora vale a fórmula explícita do §5.
- Nenhuma outra divergência. Nenhuma incompatibilidade encontrada com 5257–5260.

## 7. Parecer

**GO** para uma futura autorização de aplicação, na ordem 5257 → 5258 → 5259 → 5260, uma por vez. Ressalvas já registradas no README §9.5:

- SQL nunca executado em PostgreSQL real;
- harness 5857 não executado;
- homologação visual pendente.

Imediatamente antes de aplicar, repetir as consultas 1 e 5 (ledger e fingerprints) e conferir 0 sessões ativas.

## 8. Gate de entrada de LIVE-MIGRATIONS-01 — STOP antes de qualquer escrita

Releitura (somente leitura, 30 s), antes de aplicar 5257:

- Inalterados: ledger (524, ponta 5256); 5257–5260 ausentes; `layout_md5`, `pages_md5`, `slots_md5` e `reservations_md5` iguais; F002 igual.
- Arquivos SQL íntegros e na ordem: static check PASS. md5 dos corpos entre `begin;`/`commit;`:
  - 5257 `b1da4fbd683b53fa26417bf4e2a068af`
  - 5258 `3ae8c0058d7330393a174c880a6539f5`
  - 5259 `ffdb616cfc0163766e2278c0b374fe08`
  - 5260 `218262ea7e44745ba8fb44694faebabe`
- **Divergente no F001:** posições 182 → **183**; alocações 211 → **212**; `assignments_md5` → `9f155ab8…`; `allocations_md5` → `85388eaf…`; `physical_storage_md5` → `c01951e6…`. Causa identificada pelos timestamps (uso normal pela interface, entre 16:14 e 16:17 UTC):
  1. troca de 2 cartas na página 5 (linha 2, colunas 1 e 3);
  2. novo exemplar `fadb90be…` criado no local F001;
  3. alocação desse exemplar à "Celebração de 30 Anos";
  4. posicionamento dele na página 18 (linha 2, coluna 1).
- Nada no F002 foi afetado. Sessões concorrentes: 0.

Como o gate exige reconfirmar os números do precheck e o postcheck espera 182/211, a execução foi **interrompida antes de qualquer escrita**. Para prosseguir são necessárias duas coisas: aceitar o novo baseline (183 posições / 212 alocações e os 3 fingerprints novos) e a autorização expressa de aplicar 5257–5260.

## 9. Gate de LIVE-EXECUTION-01 — STOP antes de qualquer escrita (2ª vez)

Releitura (somente leitura, 30 s):

- Arquivos íntegros: static check PASS; md5 dos corpos iguais aos do §8.
- Ledger 524, ponta 5256; 5257–5260 ausentes.
- Sem sessões concorrentes.
- Contagens iguais ao baseline aprovado: 183 posições, 212 alocações, 158 reservas, 1.353 exemplares, 106 páginas, 1.416 bolsos, 0 imagens, 1 região, 0 travados.
- Fingerprints iguais ao baseline aprovado: `allocations_md5` `85388eaf…`, `physical_storage_md5` `c01951e6…`, `layout_md5`, `pages_md5`, `slots_md5` e `reservations_md5`. F002 intacto.
- **Divergente:** `assignments_md5` `9f155ab8…` → **`b2e7c925…`**. Às 16:21:30 UTC, depois do gate do §8, as mesmas 2 cartas da página 5 (linha 2, colunas 1 e 3) foram **destrocadas**, voltando às posições originais. A contagem não muda, mas o `updated_at` das 2 posições muda.
- Fingerprints extras capturados: `regions_md5` `6bb7a8d89af10191668fe1e648c44e44`; `slot_images_md5` = NULL (0 imagens).

A autorização determina interromper diante de movimentações novas desde o último precheck, sem presumir que estejam autorizadas. **Nenhuma migration foi aplicada.**
