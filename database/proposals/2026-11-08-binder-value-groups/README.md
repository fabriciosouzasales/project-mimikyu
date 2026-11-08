# BINDER-VALUE — B2: leitura agregada dos bolsos (Query 5357) e harness 5885

| Campo | Valor |
|---|---|
| **Rodadas** | `BINDER VALUE — B2 AGGREGATED READ SQL PROPOSAL & HARNESS DESIGN-01` (2026-11-08) · `B2 — SQL & HARNESS STATIC AUDIT CORRECTION-01` (2026-11-08) |
| **Contrato** | `docs/05d-colecoes-e-usuarios.md` v2.73 — Valor do Fichário, D1–D9 (base física da 5248) |
| **Status** | **IMPLEMENTAÇÃO DO BANCO CONCLUÍDA (2026-11-08).** Query 5357 CONFIRMADA EXECUTADA no LIVE `mimikyu-core` (ledger `20261108042423`), validada (C1.0, C1, C2, C3a e C3b PASS; C3c dispensado). **Referência canônica:** `database/schema/5357_create_get_my_binder_value_groups.sql` (difere do arquivo desta pasta só no bloco Status; corpo `prosrc` md5 `e6cdae3e…`). O arquivo `5357_..._PROPOSAL.sql` desta pasta é a evidência exata aplicada (md5 `4a309a81…`) e não é alterado. Interface ainda não implementada |
| **Validação** | Sem ambiente isolado (decisão do proprietário): a estratégia e os resultados estão em `VALIDATION-STRATEGY-01.md` (§11–§15). O harness `5885` e a seção 6 deste README (ambiente local) ficaram **sem uso** neste incremento |
| **Arquivos** | `5357_create_get_my_binder_value_groups_PROPOSAL.sql` (v0.2, corpo igual à v0.1) · `5885_validate_get_my_binder_value_groups_HARNESS_LOCAL.sql` (v0.2) · `5357_P1_EXPLAIN_PROTOCOL.sql` (v0.2) · este README |

## 1. Base verificada (definições versionadas)

- Fichário `collection_layout` (5105: `collection_id` UNIQUE = proprietária; 5247: `storage_container_id` NOT NULL UNIQUE, local BINDER do mesmo dono) → páginas `collection_layout_page` (5108: UNIQUE `(layout_id, page_number)` DEFERRABLE) → bolsos `collection_layout_slot` (5110: UNIQUE `(page_id, row_index, column_index)`) → ocupação `collection_layout_slot_assignment` (5115 → **5248**: `slot_id` UNIQUE DEFERRABLE; `physical_card_id` NOT NULL UNIQUE, `ON DELETE CASCADE`; `collection_allocation_id` legado, anulável, `ON DELETE SET NULL`) → `physical_card` (5010/5023; `inventory_id` anulável, obrigatório quando há local) → `inventory` (5000: `owner_user_id` UNIQUE).
- Gatilho de integridade (5248): exemplar do **mesmo dono** do fichário e guardado no **local físico** do fichário; a coleção do exemplar não importa.
- Convidadas: `collection_layout_guest` (5229: PK `collection_id`; gatilho de mesmo dono; proprietária nunca é convidada). Compartilhamento com terceiros: `collection_membership` (5300, VIEWER).
- `collection_allocation` (5040): `physical_card_id` UNIQUE (0..1 coleção por exemplar) — o `filled_count` da 5252 (que junta a alocação) não duplica linhas.
- Imagens (5232), mesclagens/regiões (5119/5238/5239) e reservas (5113) não têm linha de ocupação.
- `filled_count` (5252) = `count(a.id)` sobre página → bolso → ocupação, o mesmo percurso da 5357.

## 2. Assinatura e retornos (5357)

`get_my_binder_value_groups(p_collection_id uuid, p_limit integer default 200, p_offset integer default 0)` → `card_variant_id, language_code, language_name, card_name, collector_number, collector_total, card_set_code, card_set_name, is_default_variant, variant_label, image_path, copies_count, total_count, total_copies`.

- **Subconjunto** das colunas da 5261, com os mesmos nomes e tipos. `toItem` (R2-E) lê todas as que exige; `rarity_code` (opcional em `toItem`) fica nulo, e a R2-E não usa `rarityCode`. Ficam de fora `last_added_at`, `copies_owned`, `variant_type_code`, `rarity_code`.
- `total_count` (grupos) e `total_copies` (exemplares nos bolsos) calculados no mesmo statement, antes da paginação, iguais em todas as páginas.
- Sem dados financeiros e sem ids de bolso, página, alocação ou exemplar.
- Ordem total SET_NUMBER, idêntica à da 5261: lançamento desc, ordem de lançamento desc, código, `collector_order`, `variant_order`, `language_order`, `card_variant_id`, `language_id`.
- Limites: `p_limit` 1..200, `p_offset` 0..10.000.

## 3. Autorização

1. `auth.uid()` obrigatório (sem sessão → `28000`); parâmetros inválidos → `22023`.
2. **Fronteira antes de qualquer outra tabela:** a coleção informada é do chamador; inexistente, de outro titular ou compartilhada com você → `COLLECTION_NOT_FOUND` (`P0002`), mesma mensagem — padrão da 5252. Coleção arquivada do próprio titular é aceita (como na 5252).
3. Fichário resolvido **só** a partir dessa coleção (proprietária ou convidada); coleção própria sem fichário → vazio.
4. **Defesa:** o dono da coleção proprietária do fichário é reconferido (= chamador).
5. Exemplares só pelo inventário do chamador (defesa além do gatilho 5248).
6. `SECURITY DEFINER` (catálogo só legível por administrador; RLS do fichário não cobre o caminho de convidada — mesmo motivo de 5252/5245/5356), `STABLE`, `search_path = ''`, objetos qualificados, sem SQL dinâmico, nenhuma escrita, nenhuma referência a `collection_allocation`; `REVOKE` de `PUBLIC` e `anon`; `GRANT EXECUTE` a `authenticated`; `service_role` segue o default privilege, como na 5252/5356 (registrado pelo S2, sem asserção).

## 4. Matriz de segurança (harness 5885 v0.2)

| # | Caso | Esperado |
|---|---|---|
| E0 | Sentinela local, objetos, `auth.uid()` Supabase, papéis, definer | aborta antes de qualquer escrita se faltar algo |
| F1 | Fidelidade da sessão | `auth.uid()` = A e = B com o claim; nulo sem `sub` |
| S1 | Configuração | DEFINER, STABLE, `search_path=""`, 14 colunas |
| S2 | `anon`/`PUBLIC`/`authenticated` | sem EXECUTE / sem EXECUTE / com EXECUTE; chamada real como `anon` → `42501`; `service_role` registrado |
| S3 | Autenticado sem `sub` | `28000` |
| S4 | Coleção nula; limite 0/201; offset −1/10001; uuid malformado | `22023`; `22P02` |
| S5 | B com a proprietária de A, a convidada de A e uuid inexistente | `P0002`, mesma mensagem |
| S5 | B com coleção própria sem fichário | 0 linhas |
| S6 | B VIEWER ACTIVE da proprietária de A | `P0002` |
| S7 | A pela convidada | idêntico ao resultado pela proprietária |
| I7 | Isolamento | o exemplar (v2,l2) de B não entra na contagem de A |

## 5. Matriz de integridade (harness 5885 v0.2)

| # | Cenário | Esperado |
|---|---|---|
| I1 | Exemplar da proprietária, da convidada, de coleção não participante, sem coleção, de coleção arquivada — todos em bolso | entram |
| I1 | Guardado no fichário sem bolso; de outro local; bolso vazio, reservado, com imagem, mesclado | fora |
| I2 | Duas cópias da mesma variante + idioma; idiomas diferentes | 1 grupo com 2; grupos distintos |
| I3 | Totais | Σ `copies_count` = `total_copies` = `filled_count` = 5; linhas = `total_count` (mesmo retrato, REPEATABLE READ) |
| I4 | Paginação de 1 em 1 | lista completa, sem repetição/falta, na ordem; totais iguais; além do fim → 0 |
| I5 | Desalocar exemplar posicionado | continua no bolso e na leitura |
| I6 | Referência do Acervo | 5261 **sem filtro de coleção**; prova explícita de que inclui exemplares sem coleção (7 exemplares/4 grupos; grupo (v2,l2) = 1, só o P4 sem coleção); depois, todo grupo do fichário existe no Acervo com cópias ≤ e total ≤ |

O fixture é conferido antes dos testes (`Q5885_FX_STATE`: 5 ocupações, 7 exemplares de A, 3 sem coleção, B VIEWER ACTIVE). Chamadas paginadas independentes não formam um retrato único; na aplicação, divergência → "incompleto" (regra da R2-E). A parte monetária de "valor do fichário ≤ valor do Acervo" é teste TS na implementação.

## 6. Ambiente de teste

### 6.1 Proteção contra execução fora do ambiente isolado

O gate é a **sentinela** `q5885_local_sandbox` (schema vazio criado só pela preparação local; proibido no LIVE). O endereço do servidor é defesa adicional e aceita socket, loopback e redes privadas — um contêiner Docker responde com o IP interno, e o LIVE também pode responder com IP privado, então o endereço sozinho não distingue os dois. Constraints e gatilhos adiados são forçados a imediatos (`SET CONSTRAINTS ALL IMMEDIATE`) para o ROLLBACK não esconder um fixture inválido.

### 6.2 Matriz de equivalência

A = Supabase real (LIVE, pelas definições versionadas; não consultado). B = réplica local existente (`C:\b12-pg17`, contêiner PG17 em `127.0.0.1:55432`, `dump/schema.sql` de 2026-09-28). C = ambiente local proposto.

| Componente | A | B | C (proposto) | Indispensável? |
|---|---|---|---|---|
| Tabelas do fichário, coleções, alocação, exemplar, inventário, locais, `storage_container_kind`, `collection_membership` | sim | **não** (22 tabelas só de catálogo) | estrutura extraída (schema-only), sem dados | sim |
| Catálogo usado pela 5357/5261 (`language`, `card_asset`, `card_asset_type`) | sim | **não** (`language`/`card_asset*` ausentes) | estrutura + dados de referência não pessoais | sim |
| Catálogo restante (`game`, `expansion`, `card_set`, `card`, `card_variant`, tipos e perfis) | sim | sim, com dados (2026-09-28) | reaproveitado ou reextraído | sim (≥ 2 variantes do mesmo Game, 2 idiomas) |
| Constraints (UNIQUE, FK, CHECK, DEFERRABLE) | sim | só do catálogo | extraídas com as tabelas | sim |
| Gatilhos de integridade (5042, 5057/5059, 5112, 5117/5248, 5229, 5247, 5256, 5263) e suas funções | sim | **não** | extraídos (schema-only traz funções e gatilhos das tabelas do escopo) | sim |
| Índices do percurso | sim | não | extraídos | sim para P1/M1; dispensável para S/I |
| Políticas RLS | sim | só do catálogo | extraídas | dispensável para a 5357 (DEFINER com BYPASSRLS); útil para provar que `authenticated` não lê as tabelas direto |
| Dono/definer | `postgres` não superusuário com BYPASSRLS | superusuário | `postgres` com BYPASSRLS; superusuário aceito, com lacuna registrada (superusuário também ignora GRANTs de tabela) | sim (E0 exige BYPASSRLS ou superusuário) |
| Papéis `anon`/`authenticated`/`service_role` sem BYPASSRLS, USAGE em `public` e `auth`, EXECUTE em `auth.uid()` | sim | não | criados no padrão Supabase | sim (`service_role` dispensável) |
| Default privileges (EXECUTE a `anon`/`authenticated`/`service_role` em funções novas de `public`) | sim | não | reproduzidos | sim — é o que torna o REVOKE de `anon` necessário e testável |
| `auth.users` | sim (completa) | não (só referências no corpo de funções; `auth_stub_ids.txt` com 1 id) | stub com `id` e FKs que apontam para ele | sim |
| `auth.uid()` lendo `request.jwt.claim.sub`/`request.jwt.claims` | sim | não | definição igual à do Supabase | sim (E0/F1) |
| Claims JWT | PostgREST define `request.jwt.claims` e `role` | n/a | `set_config` na transação | sim |
| Funções dependentes (5252 `get_my_collection_binder`, 5261 `get_my_inventory_items`) | sim | 5261 só como texto, sem tabelas | extraídas | sim (I3/I6) |
| Dados de usuários | reais | nenhum | **nenhum** (só sintéticos no 5885) | não — proibido |
| Storage, `pg_net`, `pg_cron`, Edge Functions, Pricing | sim | não | não | dispensáveis (5357 não usa) |

**Conjunto mínimo para executar o 5885 com fidelidade:** as tabelas do fichário/coleções/exemplar/inventário/locais/membership com constraints, gatilhos e funções de gatilho; o catálogo das tabelas acima com dados de referência; 5252 e 5261; `auth.users` stub, `auth.uid()` Supabase, os papéis com default privileges; definer com BYPASSRLS; a sentinela.

### 6.3 Alternativas e gate

- **Supabase CLI local (`supabase start`)** — o repositório já tem `supabase/config.toml` (usado para as Edge Functions). Ele já traz `auth.users`, `auth.uid()`, os papéis, os default privileges e o `postgres` com BYPASSRLS **idênticos ao Supabase**, eliminando a parte mais frágil da preparação. Ainda exige o esquema `public` (o repositório não tem `supabase/migrations`): o mesmo dump schema-only + dados de catálogo. Disponibilidade de Docker e da CLI no Windows não foi verificada nesta rodada. **Recomendada.**
- **Réplica B ampliada** — reutiliza o contêiner existente e o `extract_live_ro.sh` (read-only; `pg_dump --schema-only` com filtro de escopo), mas exige criar à mão `auth`, papéis e default privileges (risco de divergência de fidelidade).
- Branch do Supabase descartada (custo).
- Nas duas opções, o `extract_live_ro.sh` hoje também gera `--data-only` das tabelas do escopo: para as tabelas de usuário, o protocolo novo precisa **excluir dados** (só estrutura), mantendo dados apenas do catálogo de referência.

## 7. Desempenho

- Índices existentes no percurso: `uq_collection_layout_page_number`, `uq_collection_layout_slot_position`, `uq_collection_layout_slot_assignment_slot`, PKs de `physical_card` e `inventory`, `ix_collection_layout_guest_layout`, `ix_card_asset_card_id` (imagem). **Nenhum índice novo.**
- Protocolo `5357_P1_EXPLAIN_PROTOCOL.sql` v0.2: nível 1 estático (conferido), nível 2 EXPLAIN sem ANALYZE com critérios por seletividade e cardinalidade (custo é só informativo; Seq Scan em tabela pequena é aceito; plano genérico incluído), nível 3 medições reais futuras.

## 8. Compatibilidade com a R2-E

- `toItem` lê as linhas da 5357 sem mudança; a ordem de chegada vira `order`.
- `buildCollectionValueReport` reaproveitado sem mudança: itens + referências (`readVariantPrices` → `inventoryPriceInput`) + ids indisponíveis + `{ totalCount, totalCopies, duplicate, inconsistentPages }` + total esperado = `filled_count`.
- Textos do fichário separados; nada do núcleo da R2-E muda.

## 9. Alternativas descartadas

`get_my_collection_binder_pages` (N/4 chamadas pesadas) · 5159 por coleção (perímetro errado após a 5248) · soma do valor das coleções (idem) · contador mantido no banco · `SECURITY INVOKER` (catálogo inacessível; RLS sem caminho de convidada) · paginação por chave.

## 10. Riscos e decisões pendentes

- **Pendente:** escolha e autorização do ambiente local (§6.3) e do protocolo de extração somente de esquema.
- **Pendente:** autorização do 5885, do EXPLAIN e, depois, da aplicação no LIVE.
- Fixture por INSERT direto pode esbarrar em gatilho não previsto; com `SET CONSTRAINTS ALL IMMEDIATE` a falha aparece no statement, e o E0 de colunas obrigatórias aborta — ajuste só com nova auditoria.
- `filled_count` (5252) conta ocupações sem filtrar o dono; a 5357 filtra pelo inventário. São iguais pelo gatilho 5248; se divergirem, a aplicação mostra "incompleto".
- Numeração confirmada: `5357` (proposals até 5356; 5353–5355 usados por propostas) e `5885` (validações até 5884) não aparecem em `database/` nem em `docs/`.
