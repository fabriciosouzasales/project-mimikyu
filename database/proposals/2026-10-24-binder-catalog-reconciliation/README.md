# Fichário Digital × Catálogo — incorporação de novidades (MASTER_SET)

| Campo | Valor |
|---|---|
| Rodada | `BINDER-CATALOG-RECONCILIATION-PROPOSAL-01` (2026-10-24) |
| Status | **EXECUTADA / CANÔNICA / ENCERRADA (2026-10-25).** 5263–5266 aplicadas no LIVE (§16) e promovidas para `database/schema/` (§18); frontend homologado pelo proprietário; harness 5859 não executado (estratégia H-A). Os arquivos SQL desta pasta são a proposta aprovada, preservada como evidência (cabeçalhos "PROPOSTA" mantidos de propósito). |
| Migrations | `5263` (estruturas: registro de incorporações W5 + marco de participação A7) → `5264` (internas) → `5265` (leituras) → `5266` (aplicação). Renumeradas em W5-FOUNDATION-01: internas/leituras/aplicação eram 5263/5264/5265 nas rodadas anteriores (§1–§10 já usam a numeração nova). |
| Harness | `5859` (nunca no LIVE) · verificação estática `static_check_catalog_reconciliation.py` |
| Origem | `BINDER-CATALOG-VARIANT-SYNCHRONIZATION-DIAGNOSTIC-01` → `-RECONCILIATION-DESIGN-02` → `-SCOPE-CORRECTION-04` |

## 1. Problema e decisões

Reservas do fichário são gravadas uma única vez, na montagem (5224, D3); o progresso da coleção é dinâmico (`master_set_positions`, 5187). Variante criada no Catálogo depois da montagem aparece como "Falta" na coleção e não tem lugar no fichário (caso real: Chi-Yu ME5 059 Holográfica Reversa, criada às 20:02 de 24/10; fichário montado às 19:32).

Regras aprovadas por Fabrício:

1. Só **MASTER_SET**. Pokédex excluída da detecção e da incorporação; as 1.025 referências e 5257–5260 intocadas.
2. Novidade = posição elegível nascida após o marco do fichário (montagem; entrada da convidada).
3. Bolso vazio na posição natural primeiro; ocupado → deslocar as seguintes (regra do Inserir Espaço), com prévia e confirmação.
4. Ordem do Master Set preservada; nunca usar bolsos fora da ordem.
5. Reserva liberada não é restaurada.
6. Seleção das novidades.
7. Atômica e idempotente; só o proprietário.
8. Regras de participantes e fichários compartilhados preservadas.

## 2. Contratos

| Objeto | Tipo | Acesso |
|---|---|---|
| `collection_layout_catalog_incorporation` (5263) | tabela; RLS sem políticas | ninguém (escrita só pela aplicação; leitura só por `binder_catalog_novelties`) |
| `collection_layout_catalog_marker` (5263) | tabela; RLS sem políticas | ninguém (escrita só pelos 5 gatilhos da 5263; leitura só por `binder_catalog_context`) |
| `binder_catalog_marker_on_layout_insert` · `_on_owner_change` · `_on_guest_insert` · `_cleanup` (5263) | funções de gatilho | ninguém |
| `binder_catalog_context(collection)` | interna, STABLE | ninguém |
| `binder_catalog_assert_eligible(collection)` | interna, STABLE | ninguém |
| `binder_catalog_positions(set, finishes)` | interna, STABLE | ninguém |
| `binder_catalog_novelties(collection)` | interna, STABLE | ninguém |
| `binder_catalog_plan(collection, keys)` | interna, STABLE (simulação) | ninguém |
| `get_my_binder_catalog_novelties(collection)` | RPC, STABLE | authenticated |
| `preview_my_binder_catalog_reconciliation(collection, keys text[] = null)` | RPC, STABLE | authenticated |
| `apply_my_binder_catalog_reconciliation(collection, keys, plan_token, confirm_cross_page, confirm_add_page)` | RPC, VOLATILE, `lock_timeout 5s` | authenticated |

Chave de novidade = `card_id:variant_type_id` (ou `card_id:*` para secreta sem acabamento), a mesma `pos_key` da 5224.

**Aviso (`get_my_binder_catalog_novelties`):** inelegível → `eligible=false` com `reason` (NOT_MASTER_SET · BINDER_NOT_FOUND · OWNERSHIP_MISMATCH · BINDER_OWNER_POKEDEX · SPECIES_REFERENCES_PRESENT · COLLECTION_REFERENCE_MISSING · COLLECTION_ARCHIVED · MARKER_MISSING); elegível → uma linha por novidade com `placed_in_binder`.
**Prévia (HEADER):** `outcome` (READY · BLOCKED · NEEDS_REVIEW · NO_ANCHOR · OVER_LIMIT · NOTHING_TO_DO · NOT_ELIGIBLE; precedência BLOCKED > NEEDS_REVIEW > NO_ANCHOR > OVER_LIMIT > READY), `reason` (ITEM_LIMIT · ROW_LIMIT; em NOT_ELIGIBLE, o motivo), `total_items`, `total_rows_moved`, `row_limit` 500, `item_limit` 100, `requires_cross_page`, `requires_add_page`, `pages_added`, `added_page_numbers` (números exatos), `capacity_before`/`capacity_after` (bolsos), `free_pockets_after`, `plan_token`.
**Prévia (ITEM):** `kind` (IN_PLACE · RESERVE_PLACED · SHIFT · UPGRADE_RESERVATION · BLOCKED · REVIEW_REQUIRED · OUT_OF_ORDER · NO_ANCHOR · NOT_EVALUATED), destino, fim da cadeia, âncora, `pockets_moved`, `rows_moved`, `other_reserves_moved`, `crosses_page`, `adds_page`, barreira (página/linha/coluna/tipo: LOCKED · REGION · PLACED_OUT_OF_ORDER · GENERIC_RESERVATION).

**Erros públicos:** `INVALID_ARGUMENT` 22023 · `not_authenticated` 28000 · `NOT_MASTER_SET` 22023 · `BINDER_NOT_ELIGIBLE` 22023 (hint: BINDER_OWNER_POKEDEX | SPECIES_REFERENCES_PRESENT | OWNERSHIP_MISMATCH | MARKER_MISSING) · `COLLECTION_REFERENCE_MISSING` P0001 · `BINDER_NOT_FOUND` P0002 · `COLLECTION_NOT_FOUND` P0002 · `COLLECTION_ARCHIVED` 55000 · `SELECTION_INVALID` 22023 · `RECONCILE_PLAN_CHANGED` 40001 · `RECONCILE_BLOCKED` 55000 · `RECONCILE_NEEDS_REVIEW` 55000 · `RECONCILE_NO_ANCHOR` 55000 · `RECONCILE_OVER_LIMIT` 54000 · `RECONCILE_CONFIRMATION_REQUIRED` 55000 (CROSS_PAGE | ADD_PAGE) · `RECONCILE_INCONSISTENT` P0001.

**Aplicação:** `outcome` APPLIED · ALREADY_APPLIED (chaves já reservadas ou já incorporadas — W5, mesmo com a reserva liberada) · NOTHING_TO_DO (sem chaves e sem novidades); `items_applied`, `reservations_created`, `reservations_upgraded` (W3), `pockets_moved`, `rows_moved`, `pages_added`, `added_page_numbers`.

## 3. Ajustes obrigatórios da aprovação

| # | Ajuste | Onde |
|---|---|---|
| 1 | Detecção temporal **não cobre**: variante reativada (`is_active` false→true, `created_at` antigo), carta reatribuída por mesclagem editorial, acabamento acrescentado depois ao objetivo, posição secreta que muda de `*` para tipada. Essas posições continuam sem reserva e aparecem como "Falta" na coleção; o usuário pode reservar manualmente. | cabeçalho 5264, §1 deste README |
| 2 | Ordem: `binder_catalog_positions` usa textualmente a chave de `collection_binder_plan` (5251, ramo MASTER_SET). Provas: static check **S8**; harness **1.1/1.2** (CM e 623 posições de CB); **ensaio somente leitura no LIVE** (§7): 194/194 posições da Escuridão Absoluta na mesma ordem. | 5264, harness, §7 |
| 3 | A prévia informa páginas adicionadas (`pages_added`, `added_page_numbers`) e capacidade resultante (`capacity_before/after`, `free_pockets_after`). Harness 4.2/4.4. | 5264/5265 |
| 4 | Limite global sem ambiguidade: **500 linhas movidas = Σ sobre os SHIFT de (posições de exemplar + reservas de qualquer coleção + imagens de bolso) dos bolsos que andam**, a unidade `rows_moved` da 5243. Reservas novas e páginas criadas não contam. Separado: **100 novidades por operação**. Harness 7.1–7.3. | 5264 |
| 5 | Propriedade: contexto exige dono da coleção = dono da coleção dona do fichário (5229 já impõe "convidada do mesmo dono"); a aplicação exige também dono = sessão e fichário travado = fichário do contexto. | 5264, 5266 |
| 6 | `plan_token` = sha256(versão, coleção, fichário, dona, marco, acabamentos, grade, maior página, nº de bolsos, **assinatura de todos os bolsos** (id, fixado, mesclado, posição+exemplar, linha inteira da reserva, imagem), **assinatura da lista ordenada de posições**, seleção resolvida, resultado e todos os passos). Superconjunto conservador: qualquer mudança no fichário ou no Catálogo que afete a coleção invalida a prévia. | 5264 |
| 7 | Concorrência: prévia sem trava; aplicação trava coleção dona → fichário (5240/5122, a mesma trava de Inserir Espaço, mover, colocar, reservar, páginas, imagens), recalcula sob a trava e compara o token; diferença → `RECONCILE_PLAN_CHANGED`. Harness 6.2 prova a detecção; protocolo manual de duas sessões em §6. | 5266 |
| 8 | Controles preservados: nenhuma função/tabela/política existente alterada (S4/S5); os únicos acréscimos em tabelas homologadas são os 5 gatilhos AFTER da 5263 em `collection_layout`/`collection_layout_guest`, que só escrevem na tabela de marcos (A7, §12); deslocamento só por `binder_gap_move_pocket` (5243); gatilhos de reserva (participante, acabamento do jogo, variante ativa, fora de mesclagem, sem imagem) e de posição (trava, mesclagem, integridade) continuam valendo; SECURITY DEFINER + `search_path = ''` + grants mínimos (S2/S3); `lock_timeout 5s`. | todas |

## 4. Algoritmo (resumo)

Para cada novidade selecionada, em ordem crescente do Master Set, sobre o estado simulado:

1. Exemplar da posição já num bolso sem reserva → **RESERVE_PLACED** (reserva ali, nada anda).
2. Âncora = posição anterior materializada para a coleção (reserva preferida; senão exemplar colocado). Sem anterior → a seguinte (entra antes dela). Sem nenhuma → **NO_ANCHOR**.
3. Bolso natural = seguinte à âncora: livre → **IN_PLACE**; fixado/mesclado → **BLOCKED**; ocupado → **SHIFT**: cadeia até o primeiro bolso livre (barreira antes → BLOCKED; nenhum livre até o fim → página nova; âncora no último bolso → página nova sem deslocamento).

Qualquer BLOCKED/NO_ANCHOR/OVER_LIMIT recusa a operação inteira. A aplicação executa exatamente os passos simulados (página nova pelo `add_layout_page`; deslocamento do fim para o começo; reserva com acabamento, `collection_id` NULL para a dona, id da convidada para convidada) e confere linhas movidas e ausência de novidades pendentes ao fim.

### Caso real (Escuridão Absoluta)

Chi-Yu 059 Holográfica Reversa: âncora Chi-Yu 059 Holo (exemplar colocado em 13·1·2, sem reserva) → bolso natural **13·1·3, livre → IN_PLACE**, 0 deslocamentos, sem página nova. A Chi-Yu Holo **não** é oferecida (variante de 15/08, anterior ao fichário — regra 5).

## 5. Incompatibilidades e riscos

- **Inserir Espaço × referências da Pokédex (risco independente, não tratado):** `binder_gap_move_pocket` não move `collection_layout_slot_species_reference` e o critério de bolso livre ignora a referência. Afeta só fichários de dona Pokédex quando se usa Inserir Espaço manualmente. Esta proposta não é afetada (fichário com referência é inelegível, conferido sob a trava) e não corrige a 5243 (decisão de escopo).
- **Rótulo de bolso livre** segue a 5243: espaço vazio deixado de propósito mais adiante é absorvido pela cadeia (a ordem fica preservada; a prévia mostra onde a cadeia termina).
- **Exemplar "desta coleção"** (âncora/RESERVE_PLACED): alocado a ela; ou, sendo ela a dona, não alocado a nenhuma participante (5249: a posição é do exemplar).
- **Cálculo:** a simulação percorre os bolsos do fichário por novidade (até 100 × N bolsos) e usa um mapa de posições; adequado para os volumes atuais, a medir na execução do harness (CB: 524 bolsos, 623 posições).
- **Desfazer** não existe para a incorporação (decisão: prévia + confirmação bastam nesta rodada).
- **Sintaxe**: não validada por parser/servidor nesta rodada (sem ambiente; DDL proibido no LIVE). Mitigação: static check, revisão linha a linha, ensaio somente leitura da lógica de detecção e ordem no LIVE.

## 6. Concorrência — protocolo manual (duas sessões, quando autorizado)

1. S1: `begin;` → `apply_my_binder_catalog_reconciliation(...)` (sem `commit`).
2. S2: `insert_my_binder_gap(...)` no mesmo fichário → aguarda a trava do fichário (ou `lock_timeout` 5s).
3. S1: `commit;` → S2 prossegue e recusa por `GAP_PLAN_CHANGED` (o plano dela foi calculado antes).
4. Inverso: S2 insere espaço e confirma antes; S1 aplica com o token antigo → `RECONCILE_PLAN_CHANGED`, nada gravado.

## 7. Verificações desta rodada

- `static_check_catalog_reconciliation.py`: **PASS** (S0–S17 na rev. 1.4; histórico das regras em §10.4, §11.4, §12.5 e §13.4).
- Ensaio **somente leitura** no LIVE (sem criar objeto), reproduzindo a detecção e a ordem da 5264 para a Escuridão Absoluta: 194 posições, **ordem idêntica** à de `collection_binder_plan`; 2 posições sem reserva (Chi-Yu Holo e Reversa); **1 novidade detectada: Chi-Yu 059 REVERSE_HOLO** (nascimento 20:02:22 > marco 19:32:54).
- Harness 5859: preparado (79 checagens + GATE na rev. 1.4), **não executado**.

## 8. Plano de aplicação (futuro, só com autorização)

LIVE_00 (somente leitura): ausência das 12 funções e das 2 tabelas; presença de 5187/5240/5243/5125/5234; ensaio da §7 repetido; consulta do indício de transferência (M6) = 0; **verificação histórica por `updated_at` × ledger da 5254 (§13.3) sem linhas** — havendo linha, revisão manual antes de aplicar. Aplicar 5263 → 5264 → 5265 → 5266 (cada uma na sua transação). LIVE_90: estrutura/ACL equivalentes a 0.1–0.6 do harness; **participantes × marcos ativos = 0 | 0 | 0** (consulta no rodapé da 5263); Advisor. Harness 5859 só fora do LIVE, com autorização. Frontend em rodada própria.

## 9. Parecer

Parecer vigente: §12.7. (O parecer original desta seção valia para a rev. 1.0.)

## 10. Rodada `BINDER-CATALOG-RECONCILIATION-AUDIT-CORRECTION-01` (2026-10-24)

Correção local dos achados da auditoria independente (`-INDEPENDENT-AUDIT-01`). **Nada executado.** NO-GO para o LIVE mantido.

### 10.1 Decisões de Fabrício aplicadas

| Achado | Decisão | Onde |
|---|---|---|
| W1 | token independente de TimeZone/DateStyle | 5264 `binder_catalog_plan`: marco em `extract(epoch …)`; reserva assinada por carta/variante/acabamento/coleção (sem `e::text`, sem datas); versão interna `rc1-r1` |
| W2 | limite de novidades antes do token | 5266: `OVER_LIMIT` → `RECONCILE_OVER_LIMIT` antes de comparar o token |
| W3 | reserva genérica de secreta que ganhou acabamento: atualizar a existente; se ambígua, revisão | 5264: `UPGRADE_RESERVATION` (1 reserva genérica da coleção e 1 novidade tipada da carta) ou `REVIEW_REQUIRED` (qualquer outro caso); 5266: `UPDATE` de exatamente 1 linha no próprio bolso (`reservations_upgraded`) |
| W4 | documentar limites | cabeçalho 5264 (reativação de variante e de carta, mesclagem editorial, acabamento novo no objetivo, corrida no marco) |
| W5 | não reaparecer indefinidamente | estrutura proposta em §10.2, aprovada e implementada localmente em §11 (5263) |
| W6 | carta fora da ordem não ganha reserva automática | 5264: exemplar no bolso natural → `RESERVE_PLACED`; em qualquer outro bolso → `OUT_OF_ORDER` (carta preservada, item vai para revisão); 5265: `placed_in_binder` substitui `placed_unreserved` |
| Elegibilidade | Master Set convidada em fichário de dona Set/Livre: elegível (mesmo dono, sem referências) | já era o comportamento (5264 `binder_catalog_context`); registrado |

Novo resultado do plano: `NEEDS_REVIEW` (precedência: BLOCKED > NEEDS_REVIEW > NO_ANCHOR > OVER_LIMIT > READY) → aplicação recusa com `RECONCILE_NEEDS_REVIEW` (55000).

### 10.2 W5 — mudança estrutural necessária (aprovada; implementada localmente em §11)

**Investigação:** o modelo atual não guarda nenhum rastro de que uma reserva foi criada pela incorporação e depois liberada. `clear_slot_expected_content` (5129) apaga a linha; não existe log de ações do usuário no fichário (só `admin_action_log`, `catalog_admin_action_log`, `pricing_admin_action_log`); `collection_layout_guest` é imutável. Um marco por coleção (data da última incorporação) não serve: com seleção parcial, as novidades não escolhidas sumiriam.

**Menor estrutura proposta:** uma tabela `public.collection_layout_catalog_incorporation`:

| Coluna | Tipo | Regra |
|---|---|---|
| `layout_id` | uuid | FK `collection_layout` ON DELETE CASCADE |
| `collection_id` | uuid | FK `collection` ON DELETE CASCADE |
| `item_key` | text | `card_id:variant_type_id` (ou `:*`), CHECK de formato |
| `incorporated_at` | timestamptz | default `now()` |
| PK | (`layout_id`, `collection_id`, `item_key`) | |

RLS ligada, sem políticas e sem grants (padrão das tabelas 5257). Escrita só pela aplicação 5266 (`insert … on conflict do nothing` para cada item incorporado, inclusive `UPGRADE_RESERVATION`); leitura só por `binder_catalog_novelties`, que deixa de oferecer chaves já incorporadas. Desmontagem do fichário e exclusão de coleção limpam por cascata, sem alterar funções existentes. Volume: no máximo o número de novidades incorporadas. Impacto: 1 tabela + ajustes em 5264/5266 (sem mudar contratos públicos além do comportamento decidido).

### 10.3 Harness 5859 v1.1 — 52 checagens (era 36)

| Cobertura pedida | Checagens |
|---|---|
| Mais de 100 novidades (prévia e aplicação) | 7.1, **7.4** |
| Fusos horários diferentes | **4.6** (3 combinações) e 6.4 (aplicação em Asia/Tokyo com token de America/Sao_Paulo) |
| Reserva genérica → específica | **9.1–9.4** (inequívoca e ambígua) |
| Incorporada e depois liberada | **W5.1** (prova real desde §11) |
| Carta fora da ordem | **10.2, 10.3** |
| Falha após escrita parcial | **6.10** (gatilho de teste recusa o 3º item depois de reserva, deslocamento de 10 bolsos e página nova; fichário idêntico ao anterior) |
| Fichário com referências de espécie | **8.2** (referências aplicadas no fichário Pokédex; Master Set convidada inelegível; referências intactas por md5) |
| Aplicação por convidada | **10.1** |
| Seleção parcialmente aplicada | **10.4** |
| Autorização e isolamento | 3.1, 3.2, **11.1–11.4** |

Lacunas declaradas: L1 (SET LOCAL ROLE), L2 (concorrência real), L3 (imagem na cadeia), L4 (RESERVE_PLACED positivo), L5 (referências com dona não-Pokédex são inalcançáveis), L6 (gatilho de teste).

### 10.4 Verificações estáticas

`static_check_catalog_reconciliation.py`: **PASS** (S0–S13). Novas regras: S11 (token sem texto dependente de sessão), S12 (OVER_LIMIT antes do token), S13 (W3/W6 no plano e na aplicação).

### 10.5 Riscos residuais

- Sintaxe ainda não validada por servidor (sem ambiente; DDL proibido no LIVE).
- W5: resolvido em §11.
- `UPGRADE_RESERVATION` depende de a reserva genérica ser desta coleção e sem variante específica; qualquer outra forma vira revisão.
- Desempenho (W7): sem otimização especulativa; os pontos de repetição continuam documentados na auditoria.

### 10.6 Parecer

**GO para a próxima auditoria das correções W1–W4 e W6.** Para o LIVE continua **NO-GO**, até: (a) decisão sobre a estrutura W5 (§10.2) e sua implementação; (b) nova auditoria; (c) definição de como validar a sintaxe sem ambiente isolado.

## 11. Rodada `BINDER-CATALOG-RECONCILIATION-W5-FOUNDATION-01` (2026-10-24)

Fabrício aprovou a estrutura mínima da §10.2, restrita à preparação local. **Nada executado** (sem SQL, migrations, harness ou rollback em qualquer banco).

### 11.1 Estrutura e invariantes — 5263 Parte A (arquivo hoje `5263_create_binder_catalog_reconciliation_structures.sql`, §12)

| Coluna | Regra |
|---|---|
| `layout_id` uuid | FK `collection_layout` ON DELETE CASCADE |
| `collection_id` uuid | FK `collection` ON DELETE CASCADE; sempre a coleção **real** (dona ou convidada), nunca NULL |
| `item_key` text | CHECK `uuid:uuid` ou `uuid:*` (mesma chave de `binder_catalog_positions`) |
| `incorporated_at` timestamptz | default `now()` |
| PK | (`layout_id`, `collection_id`, `item_key`) · índice extra em `collection_id` (cascata da exclusão de coleção) |

RLS ligada, sem políticas, sem gatilhos, `REVOKE ALL` de PUBLIC, anon, authenticated **e service_role**, nenhum GRANT. Invariantes I1–I7 no cabeçalho da 5263: só incorporações bem-sucedidas (criação **e** conversão W3); histórico separado do estado atual (a linha fica quando a reserva é liberada); prévia, recusa e falha não registram; limpeza pelo ciclo de vida do fichário/coleção; escrita só pela 5266.

Numeração: a tabela precisa existir antes de `binder_catalog_novelties` (LANGUAGE sql, validada na criação), por isso entrou como **5263** e as demais andaram uma posição (5264 internas, 5265 leituras, 5266 aplicação). Prechecks, cabeçalhos, harness, static check e docs atualizados.

### 11.2 Integração

| Ponto | Mudança | Arquivo |
|---|---|---|
| Detecção de novidades | `is_novelty` = sem reserva da coleção **e** sem registro; nova coluna interna `is_incorporated` | 5264 (`binder_catalog_novelties`, v1.2) |
| Prévia / aviso | corpo inalterado; herdam a detecção (incorporada e liberada não aparece; selecioná-la → `SELECTION_INVALID`) | 5265 (só cabeçalho) |
| Aplicação | pós-condição passa a exigir **reserva** de cada chave; depois, `INSERT … ON CONFLICT DO NOTHING` com contagem exata (= itens) na mesma transação; divergência → `RECONCILE_INCONSISTENT` | 5266 v1.2 |
| Repetição | chave reservada ou registrada → `ALREADY_APPLIED`/`NOTHING_TO_DO`, sem gravar e sem restaurar reserva | 5266 (lógica existente, documentada) |
| Liberação posterior | `clear_slot_expected_content` (5129) inalterada: apaga a reserva; o registro permanece | — |
| Reserva genérica (W3) | `UPGRADE_RESERVATION` registra a chave tipada | 5266 |
| Fichário compartilhado | registro por (fichário, coleção): dona e convidada independentes; desassociar/reassociar cria marco novo, posterior a todo registro antigo (inerte) | 5264 |
| Exclusão do fichário / coleção | cascata; 5226/5229/5236/5242 e `delete_collection` inalteradas | 5263 |

Nenhuma função homologada é alterada; nenhum contrato público muda de assinatura.

### 11.3 Harness 5859 v1.2 — 64 checagens (era 52)

| Cobertura | Checagens |
|---|---|
| Persistência e não reaparecimento (substitui o W5.1 que falhava por construção) | **W5.1** (reserva liberada; registro persiste com o mesmo `incorporated_at`; aviso não oferece), **W5.2** (prévia completa sem a chave; seleção explícita → `SELECTION_INVALID`; aplicação → `ALREADY_APPLIED` sem restaurar) |
| Estrutura e ACL da tabela | **0.5** (RLS, sem políticas/gatilhos, sem privilégio para PUBLIC/anon/authenticated/service_role, PK, FKs CASCADE, CHECK) |
| Nada registrado em prévia/recusa/falha | **I.1** (prévias, BLOCKED, PLAN_CHANGED, confirmação, 6.10), **I.4** (OVER_LIMIT, mesclagem), **I.5** (NEEDS_REVIEW), **I.7** (W6 e seleção recusada) |
| Registro correto | **I.2** (3 chaves, coleção real), **I.5** (UPGRADE), **I.6** (convidada), **I.7** (seleção parcial) |
| Idempotência | **I.3** (repetição não regrava) |
| Integridade | **I.9** (CHECK 23514, PK 23505, FK 23503) |
| Autorização | **11.5** (dono authenticated não lê/insere/altera/apaga; anon não lê/insere) |
| Ciclo de vida | **I.8** (desmontagem canônica do fichário B apaga o registro por cascata) · cascata por coleção: estrutural (0.5) |
| Resíduo | 99.1 passa a contar 15 tabelas |

### 11.4 Verificações estáticas

`static_check_catalog_reconciliation.py`: **PASS** (S0–S15). Novas: S14 (tabela: PK, FKs CASCADE, CHECK, RLS, REVOKE de 4 papéis, sem GRANT/política), S15 (só a aplicação insere, ON CONFLICT + contagem exata depois das pós-condições, sem UPDATE/DELETE; só as novidades leem; 5264 exige 5263). S5 passou a admitir a tabela nova e DDL apenas na 5263. Controles negativos (cópia temporária mutada): sem alvo no ON CONFLICT, service_role não revogado, FK RESTRICT, novidades ignorando o registro, GRANT acrescentado e INSERT antes das pós-condições → todos **FAIL**; controle positivo → PASS. `git diff --check` limpo.

### 11.5 Riscos residuais

- Sintaxe ainda não validada por servidor; harness não executado.
- Sem gatilho de pertinência (coleção = dona ou convidada do fichário): garantida pela única escritora sob a trava; escrita direta exige papel privilegiado (`postgres`).
- Transferência de fichário (5254) — **texto corrigido na A7-CORRECTION-01**: a 5254 NÃO repassa as reservas à nova dona — as reservas implícitas da antiga (NULL) são fixadas nela (`collection_id` explícito) e ela vira convidada. O risco real (BLOCKER A7 da auditoria final) era o marco: derivado do papel atual, recuava para a criação do fichário na nova dona e avançava para a transferência na antiga. Resolvido pelo marco persistente (§12).
- Cascata por exclusão de coleção provada só estruturalmente (0.5); `delete_collection` recusa coleção com fichário, então o caminho real passa antes pela desmontagem (I.8).

### 11.6 Parecer

**GO para a auditoria final** da proposta (5263–5266 + 5859 v1.2). Para o LIVE continua **NO-GO** até: auditoria final, definição de como validar sintaxe e harness fora do LIVE, e autorização expressa.

## 12. Rodada `BINDER-CATALOG-RECONCILIATION-A7-CORRECTION-01` (2026-10-24)

Fabrício aprovou a opção A da auditoria final: marco de participação persistente por (fichário, coleção), independente do papel. **Nada executado** no LIVE; uma única consulta somente leitura (contagens) para dimensionar o preenchimento.

**Correção de premissa da auditoria final (A7):** a auditoria afirmou que a convidada recebe reservas materializadas ao entrar. A leitura integral mostrou o contrário: a associação vigente (5255, D3) não toca bolsos nem reservas; a linha 622 da 5229 é `set_slot_expected_content` (reserva manual com coleção). O BLOCKER permanece, por dois caminhos: (a) reserva **manual** da convidada numa posição anterior à sua entrada, liberada, volta como novidade depois que ela vira dona; (b) mesmo sem reserva alguma, a nova dona passaria a receber como "novidades" todas as posições nascidas entre a criação do fichário e a sua entrada.

### 12.1 Mecanismo (5263 v2.0, Parte B)

| Evento (operação homologada, inalterada) | Gatilho da 5263 | Efeito no marco |
|---|---|---|
| Fichário criado (5224) | AFTER INSERT `collection_layout` | (fichário, dona) = `created_at` do fichário, papel OWNER |
| Convidada associada (5229/5255) | AFTER INSERT `collection_layout_guest` | sem linha → `created_at` da associação, GUEST; linha de **dona** → papel GUEST, marco preservado (transferência); linha de **convidada** → marco substituído (reassociação na mesma transação) |
| Transferência (5254): apaga a convidada destino, troca a dona, insere a origem como convidada | AFTER UPDATE OF `collection_id` | destino: papel OWNER, marco que já tinha; sem participação anterior → instante da transferência |
| Fim da participação (desassociação 5229/5253; troca de dona) | AFTER DELETE / UPDATE OF `collection_id` (**imediatos desde a rev. 1.4**, §13) | ao fim do comando, se a coleção não é mais dona nem convidada, a linha é **encerrada** (`ended_xact`), não apagada |
| Desmontagem (5242) / exclusão de coleção | FK ON DELETE CASCADE | linha apagada |

- (rev. 1.3, substituído em §13) A limpeza era diferida porque, dentro da 5254, o destino fica sem papel entre o DELETE da convidada e o UPDATE da dona. O texto original dizia que `SET CONSTRAINTS ALL IMMEDIATE` levaria a `MARKER_MISSING`; **estava errado** — o efeito real seria marco recriado com a data da transferência (§13.2). A rev. 1.4 elimina a dependência de diferimento.
- **Reassociação:** em outra transação, a linha foi apagada no commit da desassociação e nasce de novo com a data da nova associação; na mesma transação, o gatilho de inserção substitui o marco de convidada.
- **Existentes (M6):** preenchidos com `collection_layout.created_at` (donas) e `collection_layout_guest.created_at` (convidadas), as mesmas datas usadas até aqui; nenhuma data inventada. Antes do preenchimento a migration trava as duas tabelas e **falha** se houver indício de transferência anterior: convidada com reserva própria mais antiga que a sua entrada. Só a 5254 produz isso, porque a desassociação apaga as reservas da convidada. LIVE (somente leitura, 2026-10-24): 3 fichários, 1 convidada, **0 indícios**.
- **Leitura:** `binder_catalog_context` (5264 v1.3) passa a ler o marco só dessa tabela; o token (W1) continua usando o marco em epoch.

### 12.2 Prova de que a transferência preserva os marcos

Transferência CM → CG (5254), rev. 1.4: `DELETE` convidada CG → CG encerrada nesta transação → `UPDATE` dona = CG → CG reativada como OWNER com o mesmo marco (encerrada **nesta** transação) → CM encerrada (não participa até o próximo comando) → `INSERT` convidada CM → reativada como GUEST com o marco de dona (último papel OWNER, encerrada nesta transação). Nenhum `marker_at` muda (harness T.1, T.4, T.5).

### 12.3 Arquivos

| Arquivo | Mudança |
|---|---|
| `5263_create_binder_catalog_reconciliation_structures.sql` | **renomeado** (era `5263_create_collection_layout_catalog_incorporation.sql`), v2.0: Parte B (tabela de marcos, preenchimento com recusa por indício, 4 funções e 5 gatilhos) |
| `5264_…internals.sql` v1.3 | contexto lê o marco persistente; `MARKER_MISSING`; precheck exige a tabela |
| `5265_…reads.sql` v1.3 | só cabeçalho (motivo `MARKER_MISSING`) |
| `5266_…apply.sql` | inalterado |
| `5859_…sql` v1.3 | 78 checagens (§12.4) |
| `static_check_catalog_reconciliation.py` | S16, S17; S0/S3/S5/S6 cobrem as funções de gatilho e a DDL da 5263 |
| README (§2, §3, §7, §8, §9, §11.5, §12) | contratos completos, textos desatualizados corrigidos |

### 12.4 Harness 5859 v1.3 — 78 checagens (eram 64)

| Cobertura pedida | Checagens |
|---|---|
| Estrutura, integridade e permissões dos marcos | **0.6**, **M.1** (gatilhos preenchem pela criação/associação canônicas), **M.2** (CHECK/PK/FK), **11.6** (authenticated/anon negados), **I.8** (cascata na desmontagem) |
| Transferência para a convidada, preservando os dois marcos | **T.1**, e de volta **T.4** |
| Reserva liberada não reaparece | **T.0** (pré-condição: janela entre a criação do fichário e a entrada de CG; reserva manual liberada) + **T.2** |
| Novidade não incorporada continua detectável | **T.3** (antiga dona, agora convidada, ainda vê 1-HOLO, nascida entre o marco dela e a transferência) |
| Desassociação e reassociação | **D.1** (marco apagado no fim da participação), **D.2** (novo marco), **D.3** (mesma transação) |
| Falha durante a gravação W5 | **6.11** (gatilho de teste na tabela de incorporações → fichário idêntico, nenhum registro) |
| Fail-closed | **M.3** (sem marco → `MARKER_MISSING`) |

Limitações: L7 (histórico simulado ajustando datas com privilégio) e L8 (rev. 1.4: não há mais gatilho diferido; "outra transação" é simulada gravando `ended_xact = '1'` em T.5).

### 12.5 Verificações estáticas

- `static_check_catalog_reconciliation.py`: **PASS** (S0–S17).
- Controles negativos em cópia temporária, todos **FAIL** como esperado: limpeza não diferida; fallback para `collection_layout.created_at` no contexto; REVOKE ausente; recusa por indício removida; `MARKER_MISSING` removido. Controle positivo: PASS.
- Delimitadores `$tag$` pareados e parênteses balanceados nos 5 SQL; `git diff --check` limpo.

### 12.6 Limitações e riscos residuais

- **Reserva incorporada à mão (registrada, não resolvida nesta rodada):** se o usuário reservar manualmente uma novidade fora da operação, ela não entra no registro W5; se depois liberar, a posição volta a ser oferecida (por ser posterior ao marco e nunca incorporada). Decisão de produto pendente.
- Transferência anterior à aplicação **seguida de desassociação da antiga dona** apaga as reservas dela e não deixa indício: o marco da dona atual seria preenchido com a criação do fichário. Mitigação: confirmação explícita no LIVE_00.
- (rev. 1.3, corrigido em §13.2) `SET CONSTRAINTS ALL IMMEDIATE` não leva a `MARKER_MISSING`; na rev. 1.3 recriaria os dois marcos com a data da transferência (perda silenciosa de novidades). Eliminado na rev. 1.4.
- Gatilhos novos em duas tabelas homologadas: só escrevem na tabela de marcos; uma falha neles (ex.: violação de FK impossível pelo fluxo) abortaria a operação homologada. Nenhum caminho conhecido.
- Sintaxe não validada por servidor; harness não executado; desempenho não medido (os gatilhos rodam só em criação, associação, desassociação e transferência; a leitura do marco é por PK).

### 12.7 Parecer

**GO para nova auditoria** da proposta rev. 1.3 (5263 v2.0, 5264 v1.3, 5265 v1.3, 5266, 5859 v1.3). Para o LIVE continua **NO-GO**.

## 13. Rodada `BINDER-CATALOG-RECONCILIATION-A7-FINAL-CORRECTION-01` (2026-10-24)

Correção local dos WARNINGs da auditoria incremental A7. **Nada executado** (sem SQL, migration, harness ou rollback).

### 13.1 Correções

| # | WARNING | Correção |
|---|---|---|
| 1 | Ordem de travas da 5263 invertida em relação à 5254 | `LOCK TABLE collection_layout_guest, collection_layout` (convidadas → fichários, mesma ordem da transferência: DELETE da convidada antes do UPDATE da dona) |
| 2 | `LOCK TABLE` fora de bloco | movido para dentro do bloco `$pre2$` (PL/pgSQL sempre roda em transação; a trava vale até o fim dela) |
| 3 | Verificação histórica | LIVE_00 com a consulta de §13.3 |
| 4 | T.0/T.2 sem controle positivo | T.0: a RG 3 é posição do objetivo de CG com `born_at` esperado, e a RG 4 (nascida depois da entrada de CG) é novidade; T.2: a RG 4 continua novidade depois da transferência |
| 5 | Documentação de `SET CONSTRAINTS ALL IMMEDIATE` errada | §12.1/§12.6 corrigidos; comportamento real e solução em §13.2 |
| 6 | Proteção contra antecipação de gatilhos | §13.2 — diferimento eliminado |

### 13.2 `SET CONSTRAINTS ALL IMMEDIATE` — análise e solução

- **Comportamento da rev. 1.3 (lido no código):** com a limpeza antecipada, o marco do destino era apagado ao fim do DELETE da convidada e recriado pelo gatilho de troca de dona com a data da transferência; o da antiga dona era apagado depois do UPDATE e recriado na inserção como convidada. Resultado: os dois marcos avançavam para a transferência (novidades legítimas deixariam de aparecer, sem aviso). Não havia restauração de reserva, mas havia alteração silenciosa.
- **Solução (5263 v2.1):** nenhum gatilho é diferido ou de restrição. O fim da participação **não apaga**: grava `ended_xact = pg_current_xact_id()` (id da transação de nível superior). A reativação compara esse id com a transação atual:
  - nova dona (gatilho de troca de dona): linha ativa ou encerrada **nesta** transação → mantém o marco; encerrada em transação anterior (ou inexistente) → marco = instante da transferência;
  - nova convidada (gatilho de associação): último papel OWNER e linha ativa ou encerrada nesta transação → mantém o marco (é a antiga dona na transferência); qualquer outro caso → marco novo da associação.
- **Consequência:** o resultado não depende de `SET CONSTRAINTS`, porque não há o que antecipar. Os gatilhos rodam ao fim de cada comando, e o harness exercita exatamente esse modo (T.1, T.4, T.5). O contexto (5264 v1.4) só aceita linha com `ended_xact` nulo.
- **Limite remanescente:** com `session_replication_role = replica` nenhum gatilho de usuário dispara: participante sem marco → `MARKER_MISSING` (falha segura). Linhas encerradas permanecem como histórico, uma por participação encerrada, e somem com o fichário ou a coleção (cascata).

### 13.3 Verificação histórica (LIVE_00, somente leitura)

```sql
-- Fichários atualizados depois da instalação da 5254: candidatos a transferência (revisão manual).
-- Correto porque trg_collection_layout_updated_at (5106) grava updated_at em todo UPDATE, e antes
-- da 5254 a 5136 proibia trocar collection_id.
select l.id, l.collection_id, l.created_at, l.updated_at
from public.collection_layout l
where l.updated_at <> l.created_at
  and l.updated_at >= (select to_timestamp(m.version, 'YYYYMMDDHH24MISS')::timestamp at time zone 'UTC'
                       from supabase_migrations.schema_migrations m where m.name like '5254%');
-- esperado: nenhuma linha. Linha presente = alguma alteração (transferência, nome, logomarca ou
-- local físico) depois da 5254: decidir manualmente antes de aplicar a 5263.
```

Resultado conhecido (consulta somente leitura de 24/10, na auditoria incremental): nenhum fichário seria listado (L1 atualizado às 00:34, antes do ledger 12:18:20; L2 e L3 nunca atualizados). Isso é evidência forte de ausência de transferência até aquela data, não certeza absoluta: depende de o gatilho 5106 nunca ter sido desativado. A consulta precisa ser repetida no dia da aplicação.

### 13.4 Harness 5859 v1.4 — 79 checagens

| Mudança | Checagens |
|---|---|
| Controles positivos | **T.0** (RG 3 é posição do objetivo de CG; RG 4 é novidade), **T.2** (RG 4 continua novidade) |
| Transferência para coleção que não era convidada (a 5254 permite: destino ativo, sem fichário próprio, não convidado de outro fichário) com participação anterior encerrada em outra transação | **T.5** — marco novo, o antigo (−5 dias) não revive; na volta, a dona original mantém o marco |
| Gatilhos antecipados | coberto por construção: **0.6** prova que não há gatilho diferido nem de restrição; T.1/T.4/T.5 rodam no modo imediato |
| Participantes × marcos | **M.4** (mesmo critério do LIVE_90) |
| Desassociação/reassociação | **D.1** (encerrada, sem marco ativo), **D.2** (marco novo); D.3 removido por ter ficado redundante (o último papel GUEST dá marco novo em qualquer transação) |

Os comandos `SET CONSTRAINTS` do harness foram removidos.

### 13.5 Verificações estáticas

- `static_check_catalog_reconciliation.py`: **PASS** (S0–S17; S16/S17 revistos).
- Controles negativos em cópia temporária, todos **FAIL** como esperado: gatilho diferido reintroduzido; reativação sem comparação de transação; `LOCK TABLE` fora do bloco e na ordem antiga; contexto sem filtro de `ended_xact`; limpeza que apaga. Controle positivo: PASS.
- `git diff --check` limpo.
- Sintaxe e desempenho continuam **pendentes**: nada foi validado por servidor.

### 13.6 Parecer

**GO para preparar a execução controlada** (definição do ambiente e do roteiro de validação de sintaxe e harness, sujeita à sua autorização). LIVE: **NO-GO** até sintaxe validada, harness executado com GATE PASS e LIVE_00 limpo.

## 14. Rodada `BINDER-CATALOG-RECONCILIATION-LIVE-READINESS-H-A-01` (2026-10-24)

Fabrício decidiu pela estratégia **H-A**: aplicar no LIVE com pré e pós-check somente leitura; o harness 5859 **não será executado** e suas 79 checagens ficam sem resultado. Sem ambientes isolados.

- Roteiro definitivo: [`LIVE-RUNBOOK-H-A.md`](LIVE-RUNBOOK-H-A.md) — LIVE_00 (Q00.1–Q00.6 + STOP), aplicação 5263 → 5266 com nomes de ledger, pré-condições, efeitos e interrupções, LIVE_90 (Q90.1–Q90.9 + STOP), evidências de homologação e limitações aceitas.
- Verificações somente leitura desta rodada no LIVE: Q00.1, Q00.2, Q00.3, Q00.4 a/b, Q00.5 e Q00.6 executadas e conformes (objetos ausentes, dependências presentes, nenhum indício de transferência, 7 gatilhos e 15 md5 registrados, única novidade = Chi-Yu 059 REVERSE_HOLO). O resultado esperado da prévia (Q90.8: IN_PLACE em 13·1·3, âncora 13·1·2) foi derivado do estado lido, não executado.
- Parecer: **GO para solicitar autorização operacional**; execução só com autorização expressa.

## 15. Gate operacional `BINDER-CATALOG-RECONCILIATION-LIVE-EXECUTION-GATE-01` (2026-10-25)

LIVE_00 refeito integralmente (somente leitura) em 2026-10-25 14:31 UTC; **nenhuma divergência** em relação à linha de base de 2026-10-24. Nada aplicado.

| Item | Resultado |
|---|---|
| Integridade dos artefatos (sha256) | 5263 `168de767…c0bb` · 5264 `a6a4aa5b…ee25` · 5265 `4a1b4357…78bf` · 5266 `bdcfb3dc…94ce` · runbook `067ee2f5…28ac3`; últimas alterações em 2026-10-24 ≤ 23:36 −03 (rodadas anteriores); versões 2.1/1.4/1.3/1.2; static check PASS |
| Q00.1 / Q00.2 | objetos ausentes, ledger sem 526x; dependências presentes; PG 170006; `check_function_bodies = on` |
| Q00.3 | 3 · 1 · 146 · 1776 · 349 · 350 · 2 · 1025 · último ledger `20261024185943` (idêntico) |
| Q00.4 a / b | 0 / nenhuma linha |
| Q00.5 | 7 gatilhos 'O' e 15 md5 idênticos à referência |
| Q00.6 | 194 posições; única novidade Chi-Yu 059 REVERSE_HOLO; 13·1·1 ocupado+reserva, 13·1·2 ocupado sem reserva, 13·1·3 livre (expectativa de Q90.8 mantida) |
| Movimentação desde a linha de base | nenhuma: últimos registros em fichário/reserva/posição/página ≤ 2026-10-24 20:02 UTC; último ledger inalterado |
| Concorrência (instantâneo) | 0 sessões ativas, 0 idle in transaction, 0 locks de terceiros nas tabelas do fichário — vale só para o instante lido |

Parecer: **GO para autorização operacional**. Execução só com autorização expressa de Fabrício, seguindo `LIVE-RUNBOOK-H-A.md` §2–§3.

## 16. Execução no LIVE `BINDER-CATALOG-RECONCILIATION-LIVE-EXECUTION-AUTHORIZATION-01` (2026-10-25)

**CONFIRMADO EXECUTADO** no LIVE (projeto `qjfutqujxrbzgrtkpgkg`), com autorização expressa de Fabrício, conforme `LIVE-RUNBOOK-H-A.md`. Harness 5859 **não executado** (H-A); RPC de incorporação **não executada**.

Antes da aplicação: sha256 dos 4 arquivos e do runbook idênticos aos do §15; LIVE_00 revalidado às 14:47 UTC sem mudança (contagens, ledger, md5 agregado das 15 funções `f9d195010933c0a45ac60bcb9e39b3ac`, 0 sessões ativas).

| Ordem | Ledger (versão real) | Nome | Resultado | md5 do texto registrado = corpo sem `begin;`/`commit;` |
|---|---|---|---|---|
| 1 | `20261025145025` | `5263_create_binder_catalog_reconciliation_structures` | sem erro | `6db5a5695167266882cdcde5089f7be8` ✔ |
| 2 | `20261025145257` | `5264_create_binder_catalog_reconciliation_internals` | sem erro | `66979526da1b5ca0565776a5a5f71f6b` ✔ |
| 3 | `20261025145358` | `5265_create_binder_catalog_reconciliation_reads` | sem erro | `1f234e6acd7a1703a06e85956bcd72e3` ✔ |
| 4 | `20261025145504` | `5266_create_binder_catalog_reconciliation_apply` | sem erro | `b5f45279b44adfae06db1d054aa6a3f4` ✔ |

LIVE_90 (somente leitura, `begin transaction read only`):

| Consulta | Resultado | Situação |
|---|---|---|
| Q90.1 | 2 tabelas: owner postgres, RLS on, force off, 0 políticas, sem privilégio para anon/authenticated/service_role, sem ACL PUBLIC; restrições e índices exatamente os esperados; `ended_xact` xid8 anulável | conforme (consulta reexecutada com casts `::text` — ver divergência 1) |
| Q90.2 | 12 funções, owner postgres, SECURITY DEFINER, `search_path=""`, sem ACL PUBLIC; 4 de gatilho `v` e 5 internas `s` sem EXECUTE para clientes; `get_my_…`/`preview_…` `s` e `apply_…` `v` + `lock_timeout=5s` com EXECUTE só para authenticated; **service_role = false** nas 3 RPCs (registrado) | conforme |
| Q90.3 | 12 gatilhos = 7 antigos + 5 novos, todos 'O', nenhum diferível, nenhum de restrição; definições conforme | conforme |
| Q90.4 | 0 · 0 · 0 · `BACKFILL_GUEST/GUEST, 3× BACKFILL_OWNER/OWNER` · marco Escuridão `2026-10-24 19:32:54.619369+00` · 0 incorporações | conforme |
| Q90.5 | 3 · 1 · 146 · 1776 · 349 · 350 · 2 · 1025 (idênticas); 7 gatilhos antigos inalterados; 15 funções com md5 agregado `f9d195010933c0a45ac60bcb9e39b3ac` (idêntico); último ledger passou a `20261025145504` | conforme |
| Q90.6 | 4 linhas na ordem 5263 → 5266, nomes exatos, versões > `20261024185943` | conforme |
| Q90.7 | contexto: elegível, sem motivo, marco 19:32:54.619369+00; 1 novidade `433d73eb-7f25-4488-9b51-7b6719bc46cc:b4c6000e-61e4-4fc3-8d58-cae137a7181a`, nascida 20:02:22.822219+00, `is_reserved` false, `is_novelty` true, `is_incorporated` false | conforme |
| Q90.8 | HEADER READY · 1 item · 0 linhas · sem outra página · sem página nova · 360 → 360 · 164 livres · token presente; ITEM IN_PLACE destino 13·1·3, âncora 13·1·2, 0 linhas | conforme |
| Q90.9 | Security: novos achados = "RLS sem política" (INFO) nas 2 tabelas **e** `authenticated_security_definer_function_executable` (WARN) nas 3 RPCs; Performance: só `unused_index` (INFO) nos 2 índices novos; nenhuma escrita além das migrations | conforme com ressalva (divergência 2) |

Divergências e limitações:

1. **Q90.1 do runbook não executa como escrito**: `k.conname || ':' || k.contype` falha com `42725 operator is not unique: text || "char"`. Reexecutada com `::text` em `conname`/`contype`/`confdeltype`, mesma semântica. O runbook aprovado não foi alterado (restrição da rodada); corrigir na próxima revisão documental.
2. **Q90.9 previa só "RLS sem política"**: o Security Advisor também lista as 3 RPCs como SECURITY DEFINER executáveis por `authenticated` (WARN). É o desenho aprovado (EXECUTE só para authenticated, autorização interna por `auth.uid()` e 5234) e o mesmo padrão de 221 funções já existentes nessa categoria; a expectativa do runbook estava incompleta, não houve permissão a mais que a prevista.
3. Os cabeçalhos dos 4 arquivos ainda dizem "PROPOSTA — NÃO EXECUTADA" (arquivos aprovados, não alterados nesta rodada); a promoção canônica para `database/schema/` e a atualização dos cabeçalhos ficam para a rodada de fechamento.
4. Limitações H-A mantidas: harness 5859 sem resultado; RPCs públicas (`get_my_…`, `preview_…`, `apply_…`) não exercitadas por SQL administrativo (exigem sessão); comportamento dos gatilhos em transferência/desassociação real não exercitado no LIVE.

Parecer: **GO para a frente de frontend** (aviso, prévia e aplicação pela interface), com a homologação funcional do runbook §4 item 5 como primeira verificação real das RPCs.


## 17. Interface local `BINDER-CATALOG-RECONCILIATION-FRONTEND-01` (2026-10-25)

Implementada localmente sobre os contratos LIVE da 5265/5266 (assinaturas conferidas no LIVE por leitura antes de escrever a interface). Nenhuma incorporação executada; nenhum SQL de escrita; migrations, Catálogo Editorial e componentes da Pokédex intocados.

- `web/lib/colecoes/binder-catalog.ts` (+ `.test.ts`, 16 testes): leitura validada do aviso, da prévia (HEADER + ITEMs) e do resultado da aplicação; seleção sempre explícita; confirmações exigidas; classificação de falhas (mensagem antes do código, porque 22023/55000/P0001/P0002 são compartilhados); textos na linguagem do colecionador. Gate `mayHaveCatalogNovelties`: fichário existente + coleção MASTER_SET + editável — Pokédex, Set, Livre e arquivada não fazem chamada.
- `app/colecoes/colecoes/[id]/fichario/actions.ts`: `readCatalogNovelties`, `previewCatalogReconciliation`, `applyCatalogReconciliation` (sessão do colecionador; aplicação revalida fichário e coleção só em APPLIED).
- `components/colecoes/fichario/binder-catalog-dialog.tsx` + `.module.css`: seleção → prévia (capacidade antes/depois, livres depois, itens movidos, páginas afetadas, destino de cada item) → confirmação explícita, com caixas de "outra página"/"página nova" quando exigidas; bloqueios com motivo e atalho para desmarcar; PLAN_CHANGED/SELECTION_INVALID/INCONSISTENT relêem lista e prévia.
- `binder-tool-rail.tsx`: botão "Novidades do Catálogo" com contador, presente só quando há novidade elegível (aviso discreto); `binder-workspace.tsx`: leitura leve ao abrir, diálogo, releitura das páginas afetadas e da lista após incorporar, anúncio `aria-live`; `binder-view.tsx`/`binder-overlay.tsx`: passam o gate.
- Validação: typecheck PASS; ESLint (`next/core-web-vitals`, modo legado) 0 avisos nos 8 arquivos; `lib/colecoes/*.test.ts` 346/346; `git diff --check` limpo. `npm run lint`/`npm run build` pelo proprietário.
- Testes de interface e homologação controlada (começando pela Chi-Yu): [`FRONTEND-HOMOLOGATION.md`](FRONTEND-HOMOLOGATION.md).

## 18. Encerramento `BINDER-CATALOG-RECONCILIATION-FINAL-CLOSEOUT-01` (2026-10-25)

Funcionalidade **Incorporar Novidades do Catálogo** homologada pelo proprietário (funcional e visual) e encerrada. Rodada só documental e de promoção; nenhum SQL de escrita, migration, harness ou rollback.

**Promoção canônica.** `5263`–`5266` copiadas para `database/schema/` com **apenas o bloco `Status`** do cabeçalho trocado (ledger real, autorização, equivalência, harness não executado, homologação). Os arquivos desta pasta permanecem intactos (sha256 `168de767…`/`a6a4aa5b…`/`4a1b4357…`/`bdcfb3dc…`, os mesmos do gate e da execução).

| Migration | Ledger | md5 do texto gravado no LIVE = md5 do corpo da proposta (sem `begin;`/`commit;`) | SQL executável (após o comentário de cabeçalho), proposta × canônica |
|---|---|---|---|
| 5263 | `20261025145025` | `6db5a5695167266882cdcde5089f7be8` ✔ | idêntico (md5 `fe87d1a6…`) |
| 5264 | `20261025145257` | `66979526da1b5ca0565776a5a5f71f6b` ✔ | idêntico (md5 `8715ee1b…`) |
| 5265 | `20261025145358` | `1f234e6acd7a1703a06e85956bcd72e3` ✔ | idêntico (md5 `a8b4ac5f…`) |
| 5266 | `20261025145504` | `b5f45279b44adfae06db1d054aa6a3f4` ✔ | idêntico (md5 `28538d4d…`) |

Prova adicional: em cada canônica, devolver a linha `Status` original reproduz a proposta byte a byte; o diff proposta × canônica tem exatamente 1 linha removida e 9 acrescentadas, todas no bloco Status. Ledger relido nesta rodada (somente leitura): 4 linhas 526x, último ledger `20261025145504`.

**Ressalvas do LIVE_90 corrigidas documentalmente** (histórico da execução em §16 preservado): errata em `LIVE-RUNBOOK-H-A.md` §6 — (E1) Q90.1 com casts `::text` nas colunas `"char"`; (E2) Q90.9 passa a prever o WARN `authenticated_security_definer_function_executable` nas 3 RPCs e o INFO `unused_index` dos índices novos.

**Documentação canônica:** decisões registradas como **C-200** (`concept-decisions.md` 1.27); `05d` 2.22 (item reescrito para o estado final, com limitações conhecidas); `INDEX.md` 2.60; `HANDOFF-2026-10-15.md` 1.71; `docs/log.md`; `FRONTEND-HOMOLOGATION.md` marcado como homologado.

**Limitações conhecidas (mantidas):** detecção temporal (reativação de variante ou carta, mesclagem editorial, acabamento acrescentado depois, corrida de importação no marco); reserva manual de novidade fora da operação não entra no registro de incorporações; concorrência resolvida por trava do fichário + `plan_token` (recusa e nova prévia); desempenho medido só no volume atual (360 bolsos), sem benchmark de carga; harness 5859 sem resultado; Inserir Espaço continua não movendo referências de espécie (risco independente).

