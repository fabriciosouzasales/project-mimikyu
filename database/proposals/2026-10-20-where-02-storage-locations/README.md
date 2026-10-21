# WHERE-02 — Meus locais (gestão de locais físicos) — EXECUTADA (canônica em database/schema/)

| Campo | Valor |
|---|---|
| Frente | Organização física — Onde guardo (roadmap item 4, P1) |
| Rodada | WHERE-02-PREPARAÇÃO (2026-10-20) |
| Status | **EXECUTADA / CANÔNICA** (2026-10-21 UTC, autorização de Fabrício). `5212`–`5219` aplicadas no LIVE uma por vez (ledger `20261021024045`, `…024104`, `…024126`, `…024143`, `…024206`, `…024214`, `…024221`, `…024228`); `5847` **26/26 PASS**, resíduo zero; contagens e quatro assinaturas dos dados existentes idênticas antes/depois; Security Advisor só com achados do padrão (+1 RLS sem policy na tabela de pedidos, +5 DEFINER executável por usuário logado). Promovidas para `database/schema/` com corpo idêntico ao aplicado (só o cabeçalho de status mudou). K1 dispensada pela auditoria (não bloqueante). Interface ainda não implementada. |
| Base | `HEAD 9d7a731`; READINESS WHERE-01 (aprovado com ressalvas) |

## Escopo

Listar locais com contagem de exemplares, total "Sem localização definida", criar local de forma idempotente, renomear/definir tipo, excluir local vazio e elegível. Tipos opcionais e extensíveis; **sem** hierarquia, capacidade ou arquivamento. **Fora** desta etapa: mover exemplares (WHERE-03), filtros do acervo (WHERE-04), movimentação em lote (WHERE-05).

## Verificações obrigatórias (resultado)

1. **NS-13 e "Local padrão" (redação integral lida, North Star v1.5).** NS-13: *"o CT-01 cria um local físico com nome provisório 'Local padrão', que representa um lugar físico real ainda não identificado pelo usuário. […] Toda operação que atribui carta ao local padrão […] exige confirmação explícita […]. Cartas sem local exibem 'Sem localização definida'"*. NS-15 usa "**local padrão da coleção**" para o Default Storage Container (C-36: "destino sugerido, alterável"), "distinto da localização física individual de cada exemplar". Significado canônico, portanto, **duplo**: (a) "Local padrão" = nome provisório e renomeável (N25) do local criado automaticamente pelo CT-01; (b) "local padrão da coleção" = preferência por coleção. WHERE-02 não atribui cartas, então a confirmação de NS-13 não se aplica aqui; a ambiguidade é tratada em WHERE-03 (D2). Nesta etapa, "Local padrão" é só um nome (renomeável, excluível se elegível) e a exclusão se baseia na referência real (`collection.default_storage_container_id`), nunca no nome.
2. **Referências a `storage_container` no LIVE:** `physical_card` (FK composta, RESTRICT), `collection.default_storage_container_id` (RESTRICT, NOT NULL, **sem índice**), `collection_creation_request.storage_container_id` (**CASCADE**, NOT NULL). Nenhuma outra tabela referencia locais; funções que escrevem local: só 5024 e 5036.
3. **Histórico de idempotência:** com o CASCADE atual, excluir o local de criação apagaria a linha de idempotência da coleção (retry duplicaria a coleção). Tratado por 5214 (R4, abaixo).
4. **Reutilização:** 5216 insere pela 5022; leitura reusa índices de 5023; 5024/5036/5175 são exercitadas pelo harness sem alteração; padrão de idempotência = D-B/5166.
5. **Sem arquivamento, hierarquia ou capacidade.** Nenhum campo ou função para isso.

## Contratos propostos (ordem de aplicação)

| Query | Objeto | Resumo |
|---|---|---|
| 5212 | `storage_container_kind` (tabela + 8 tipos) | Vocabulário aberto (C-55): Fichário físico, Caixa, Pasta, Deck box, ETB, Maleta, Cofre, Outro. Extensível por INSERT. SELECT só de ativos para authenticated. |
| 5213 | `storage_container.kind_code` + CHECK de nome + 2 índices | Tipo opcional (FK RESTRICT); nome aparado, 1–60; `ix_storage_container_inventory`; `ix_collection_default_storage` (FK de collection sem índice hoje). Pré-checagem falha alto se algum nome existente violar (LIVE: 0 violações). |
| 5214 | `collection_creation_request` FK → `ON DELETE SET NULL`, coluna anulável | **R4.** |
| 5215 | `storage_container_creation_request` | Idempotência da criação de local (mesmo padrão de 5166), FK SET NULL. |
| 5216 | `create_my_storage_container(key, name, kind)` | Idempotente; reusa 5022; códigos `INVALID_NAME`, `INVALID_KIND`, `IDEMPOTENCY_KEY_REUSED`, `INVENTORY_NOT_FOUND`. Replay de local já excluído → `storage_container_id` NULL, nunca recria. |
| 5217 | `update_my_storage_container(id, name, kind)` | Renomear/definir tipo; no-op não escreve; outro usuário/inexistente → `STORAGE_NOT_FOUND`. |
| 5218 | `delete_my_storage_container(id)` | Só vazio e não-padrão de coleção (`STORAGE_HAS_CARDS`, `STORAGE_IS_COLLECTION_DEFAULT`); corrida com atribuição/troca → `STORAGE_IN_USE` (FK). Pré-checagem exige 5214. |
| 5219 | `get_my_storage_locations()`, `get_my_storage_summary()` | Locais com `card_count`, `default_collection_count`, `can_delete`, `kind_label`; resumo com total, localizados, "Sem localização definida", nº de locais. Só contagens trafegam. |
| 5847 | Harness | 26 checagens + GATE (estrutura, segurança, criação/replay, renomear, leitura, exclusão, R4, isolamento, regressão D-A, resíduo zero). Prova manual K1 de concorrência descrita no cabeçalho. |

Todas as funções: `SECURITY DEFINER`, `search_path = ''`, objetos qualificados, `EXECUTE` só `authenticated` (revogado de PUBLIC/anon). Nenhuma escrita direta para papéis de cliente.

## R4 — tratamento

`5214`: `collection_creation_request.storage_container_id` passa a anulável com `ON DELETE SET NULL`. Excluir um local de criação preserva a linha (dono, chave, hash, `collection_id`); o replay de 5167/5175/5202 continua devolvendo **a mesma coleção** (`replayed = true`), agora com `storage_container_id` possivelmente NULL. Nenhuma função existente é alterada; o frontend não lê esse campo do retorno (verificado em `actions.ts`). A mesma regra vale para o novo `storage_container_creation_request` (5215). Prova: 5847 §6.3–6.5.

## Interface "Meus locais" (escopo para a implementação, após o LIVE)

- **Entrada:** item em Ajustes da conta/Coleções → página `Meus locais` (rota dentro de `/colecoes`), Server Component com leitura 5219; ações em Client Components nas folhas.
- **Topo:** resumo ("1.351 exemplares · 120 com local · 1.231 sem localização definida").
- **Lista:** um cartão por local — nome, tipo (rótulo humano), "N exemplares", selo "Local padrão de N coleções" quando aplicável. Ordem alfabética. Estado vazio que orienta criar o primeiro local.
- **Criar / Editar:** painel (mesmo Drawer/Dialog do DS usado em Ajustes) com Input "Nome" (60) e Select "Tipo (opcional)"; chave de idempotência gerada uma vez por abertura (mesmo padrão do CT-01).
- **Excluir:** só habilitado quando `can_delete`; senão o motivo explicado (`storageDeleteBlockMessage`); confirmação explícita; feedback de sucesso/erro com `aria-live`.
- **Texto:** nenhum termo técnico; "Trocar/excluir um local nunca move nenhuma carta".
- **Fora:** mover cartas, filtros do acervo, lote.
- **Preparado nesta rodada (testado):** `web/lib/colecoes/storage-locations.ts` (regra de nome, conversão da 5219, rótulos, bloqueio de exclusão, mapa de códigos → mensagens) + testes.

## Provas planejadas

1. Estáticas (feitas): `$$`/`begin`/`commit` balanceados, DEFINER + `search_path` + grants em todas as funções, 26 ids no harness. Pré-condições lidas no LIVE (só leitura): objetos novos ausentes, 0 nomes fora da regra, FK 5166 presente, 37.990 variantes ativas, `pt-BR` presente.
2. 5847 no LIVE após aplicar 5212–5219: GATE 26/26.
3. Prova manual K1 (duas sessões): exclusão × atribuição concorrente.
4. Frontend: typecheck, lint, testes unitários; depois Light/Dark, mobile, teclado, vazio, erro (homologação).

## Incompatibilidades / pontos de atenção

- **I1 — N24 (North Star):** "até haver atributo de tipo, a UI mostra só o nome". Com 5212/5213 o atributo passa a existir (diretriz de Fabrício, coerente com C-55 lista aberta). Atualizar N24 e 05d no ciclo de implementação.
- **I2 — Contrato de replay do CT-01:** `storage_container_id` pode voltar NULL depois de 5214 (documentado acima; sem consumidor afetado).
- **I3 — 5022 direta:** com a CHECK de 5213, um nome > 60 enviado diretamente à 5022 passa a falhar (23514). Nenhuma tela chama a 5022 diretamente.
- **I4 — "Local padrão" (D2):** pendente para WHERE-03; não bloqueia WHERE-02.
- **I5 — Nomes duplicados:** permitidos (nenhuma regra canônica exige unicidade).

## Rollback

Em ordem inversa: `drop function` de 5219→5216; `drop table storage_container_creation_request`; reverter 5214 (só se nenhuma linha estiver NULL); 5213 (`drop constraint`, `drop index` ×2, `drop column kind_code`); `drop table storage_container_kind`.
