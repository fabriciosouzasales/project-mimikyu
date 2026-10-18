# Ordem da Biblioteca escolhida pelo colecionador (`5181`–`5183` + `5835`)

| Campo | Valor |
|---|---|
| Rodada | `LIBRARY-ORDER-01` (2026-10-18) |
| Status | **CONFIRMADO EXECUTADO no LIVE e PROMOVIDA (2026-10-18, autorização de Fabrício).** 5181 → 5182 → 5183 aplicadas uma a uma; `5835` **22/22 PASS + GATE PASS**; canônicas em `database/schema/5181`–`5183`. Esta pasta fica como registro histórico. |
| Decisão de origem | Fabrício, 2026-10-18: em "Minhas coleções" a ordem deixa de depender da data de criação; o colecionador reordena **arrastando e soltando**. Coleção nova entra **no início**. Arrastar em **Cards e Lista**; o Carrossel só exibe a ordem escolhida. |
| Frontend | `LIBRARY_REORDER_ENABLED = true` só no working tree local, para homologação no navegador. Publicar (commit/deploy) depende dessa homologação funcional e visual. |

## Arquivos

| Query | Arquivo | O que faz |
|---|---|---|
| `5181` | `5181_add_collection_library_position.sql` | `collection.library_position` (nula) + CHECK `>= 1` |
| `5182` | `5182_recreate_get_my_collections_library_order.sql` | R1 v3: mesma assinatura e colunas da 5173; só a ordenação muda para `ativas → library_position NULLS FIRST → created_at DESC → id` |
| `5183` | `5183_create_move_my_collection_function.sql` | `move_my_collection(p_collection_id, p_after_collection_id, p_before_collection_id)` → nova posição. Uma âncora por vez; trava as coleções do dono; renumera 1..n; idempotente |
| `5835` | `5835_validate_library_order.sql` | Harness v1.0: 22 checagens + GATE, usuários efêmeros, sentinela LI000, resíduo zero |

## Desenho

- **Sem migração de dados e sem gatilho.** `NULL` = "ainda sem lugar". Enquanto ninguém reordena, a Biblioteca fica idêntica à de hoje (mais nova primeiro). A primeira reordenação numera todas as coleções do dono; daí em diante, toda coleção nova (posição `NULL`) aparece no início — exatamente a regra escolhida — sem tocar nos contratos de criação (`5034`/`5167`/`5175`).
- **Um movimento por gesto, ancorado na vizinha.** "Depois de" a anterior; na primeira posição de uma página, "antes de" a seguinte — funciona com paginação sem o cliente conhecer as outras páginas.
- **Integridade:** a função trava as linhas do dono em ordem de id (movimentos simultâneos serializam, sem deadlock), renumera sempre 1..n (sem buracos nem repetidos) e grava só o que mudou. Repetir o mesmo movimento não altera nada (5835 3.4).
- **Segurança:** SECURITY DEFINER, `search_path` vazio, EXECUTE só `authenticated`; coleção ou âncora alheia/inexistente → mesma resposta (`COLLECTION_NOT_FOUND`), nada muda; `authenticated` não tem UPDATE direto em `collection`.
- **Performance:** leitura e trava só das coleções do dono (índice existente em `owner_user_id`); sem índice novo — a ordenação é por dono e a cardinalidade por colecionador é pequena. R1 continua paginada (≤ 100).
- **Efeito colateral conhecido:** reordenar atualiza `collection.updated_at` das linhas renumeradas (gatilho 5031). Nenhuma tela usa esse campo hoje.
- Não toca cartas, alocações, locais, referência, progresso nem capa.

## Frontend (local, atrás da flag)

- `LibrarySortable` (só `@dnd-kit/core`, já no projeto): mouse arrasta a partir de 8 px (clique continua abrindo a coleção); toque longo (~¼ s) arrasta sem impedir a rolagem; teclado pela alça ⋮⋮ (Espaço pega, setas movem — ↑/↓ andam uma linha na grade —, Espaço solta, Esc cancela), com anúncios para leitor de tela.
- Prévia ao vivo durante o gesto; gravação otimista ao soltar; falha volta à ordem anterior com mensagem; "Ordem salva." confirma.
- A ordem vive no seletor de modos: Cards, Lista e Carrossel mostram a mesma sequência.

## Execução proposta (quando autorizada)

1. Pré-check: objetos inexistentes; R1 do LIVE idêntica à 5173 (md5 do corpo `4902ed72…`, conferido em 2026-10-18); linha de base (contagens + fingerprints; Advisor).
2. Aplicar `5181` → `5182` → `5183`, uma por vez, conferindo cada uma (5182: saída do R1 igual à de antes para todos os usuários, já que todas as posições são `NULL`).
3. Executar `5835` — esperado **22/22 PASS + GATE PASS**.
4. Security Advisor antes × depois: esperado só `0029` +1 (`move_my_collection`).
5. Promover para `database/schema/`, documentar e preparar `LIBRARY_REORDER_ENABLED = true` para homologação no navegador.

## Execução no LIVE (`LIBRARY-ORDER-LIVE`, 2026-10-18)

| Etapa | Evidência |
|---|---|
| Pré-check | Coluna, CHECK e função inexistentes; R1 do LIVE = 5173 (md5 `4902ed72…`). Linha de base: 3 usuários, 3 coleções, 210 vínculos, 1.351 exemplares, 1 local; fps coleções `f47996a4…` (inclui `updated_at`), vínculos `c7f59f24…`, exemplares `8baa9a08…`; fp da ordem atual da Biblioteca por dono `bb2ebd71…`; Advisor 0029 = 161. |
| 5181 | Ledger `20261018012416`. Coluna `integer` nula sem default; CHECK idêntico ao arquivo; 0 posições; fp das coleções inalterado; `authenticated` sem UPDATE em `collection`. |
| 5182 | Ledger `20261018012446`. Corpo idêntico ao arquivo (md5 `08fc4dd1…`, 2.709 caracteres); mesma assinatura e tipo de retorno; 1 versão da função; ACL `postgres` + `authenticated`. |
| 5183 | Ledger `20261018012519`. Corpo idêntico ao arquivo (md5 `3afa67df…`, 1.905 caracteres), SECURITY DEFINER, VOLATILE, `search_path` vazio, dona `postgres`, EXECUTE `postgres` + `authenticated`. |
| `5835` | **22/22 PASS + GATE PASS** — anon 42501; sem identidade 28000; ordem inicial sem posições; "antes de" → 1; "depois de" → 4, numeração 1..4; idempotente sem regravar; nova coleção no início; 3 movimentos inválidos (INVALID_MOVE); coleção/âncora alheia e inexistente (COLLECTION_NOT_FOUND, ordem intacta); paginação segue a ordem; B isolado; CHECK recusa 0; só a posição muda; resíduo zero. |
| Pós-check | Contagens e fingerprints iguais à linha de base (inclusive `updated_at`); ordem da Biblioteca por dono idêntica (`bb2ebd71…`); nenhuma posição gravada; 5175 intacta. |
| Advisor | Única diferença: 0029 161 → 162 (`move_my_collection`, esperado). |
