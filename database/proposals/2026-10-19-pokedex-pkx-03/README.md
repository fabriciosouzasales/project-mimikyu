# Proposta — Pokédex PKX-03: vincular cartas às posições (`5208`–`5211`)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CANÔNICA** (2026-10-19, autorização de Fabrício). `5208`–`5211` aplicadas no LIVE (ledger `20261019033709`, `…033730`, `…033754`, `…033827`); corpos idênticos aos arquivos (md5 de `prosrc`); `5846` **27/27 PASS**, resíduo zero. Promovidas para `database/schema/`. |
| **Origem** | `POKEDEX-PKX-03-IMPLEMENTATION-01` (2026-10-19). |
| **Numeração** | `5206`/`5207` já estão reservadas pela proposta `2026-10-19-pokedex-cover-customization` (capa e código). Por isso a PKX-03 começa em `5208`, e o harness é o `5846` (`5845` é o da capa). |

## Contratos canônicos reutilizados (sem alteração)

| Contrato | Uso na PKX-03 |
|---|---|
| `5046` `allocate_physical_cards_to_collection` | Confirmação do lote (até 500, tudo ou nada) e, dentro da `5210`, a alocação do exemplar livre. |
| `6119` vínculo automático `SPECIES_MATCH` | Cria o vínculo à posição da espécie na mesma transação da `5046`. |
| `6122` `set_pokedex_position_assignment` | Dentro da `5210`: vínculo de exemplar já nesta coleção sem posição e a exceção (`USER_OVERRIDE`). |
| `6124` `remove_pokedex_position_assignment` | Retirar o vínculo da posição (o exemplar continua na coleção). |
| `6125`/`6126` `set_/clear_pokedex_position_primary_representative` | Escolher (ou desfazer) a carta representante. |
| `5047` `deallocate_physical_cards_from_collection` | Tirar o exemplar da coleção (o vínculo cai por cascata). |
| `5102` / `5204` / `5201` | Progresso, grade e gerações. |

## Contratos novos (estritamente necessários)

| Query | Arquivo | Por que é necessária |
|---|---|---|
| `5208` | `5208_create_get_my_pokedex_link_candidates_function.sql` | Nenhuma leitura existente filtra o acervo **pela espécie da posição** nem devolve a espécie da carta para o aviso de divergência. `SPECIES` = vínculo normal; `ACERVO` (com busca escapada) = vínculo excepcional. Livres + nesta coleção sem posição. |
| `5209` | `5209_create_get_my_pokedex_position_copies_function.sql` | Não há leitura dos exemplares vinculados a uma posição (base do vínculo, representante, atributos físicos). `card`/`card_variant` não são legíveis pelo cliente. |
| `5210` | `5210_create_link_my_pokedex_copy_function.sql` | **Única escrita nova.** Vincular um exemplar a uma posição escolhida exige `5046` (+ `6119`) e, para outra espécie, `6122`; em duas chamadas do cliente, uma falha no meio deixaria a carta na coleção sem a posição escolhida. Compõe as duas numa transação. Sem confirmação só aceita a mesma espécie (vínculo normal); outra espécie exige `p_confirm_exception = true` (fail-closed). Nunca move exemplar de outra coleção nem de outra posição. |
| `5211` | `5211_create_get_my_pokedex_bulk_link_preview_function.sql` | Prévia do lote: um exemplar livre sugerido por Pokémon que falta (até 500). A confirmação usa a `5046` + `6119`; nunca sugere exceção. |
| `5846` | `5846_validate_pokedex_pkx_03.sql` | Harness: 27 verificações + GATE; fixture desfeita pela sentinela `MS846`; resíduo zero. |

Nenhuma tabela, coluna, trigger, política ou regra canônica muda. Todas as funções novas são `SECURITY DEFINER`, `search_path ''`, `EXECUTE` só `authenticated`, dono por `auth.uid()` antes de qualquer outra tabela.

## Verificação estática feita nesta rodada

O corpo SQL das três leituras (`5208`, `5209`, `5211`) foi resolvido contra o esquema do LIVE com consultas **só de leitura** (`EXPLAIN` / `select count(*)` com ids nulos): nomes de tabela, colunas e tipos conferem. Isso **não** substitui o `5846`.

## Plano de execução (só com autorização)

1. **Pré-checagem (leitura):** as quatro funções não existem; `5046`/`6122`/`6124`/`6125` com o corpo canônico (md5 de `prosrc`); 0 transações longas.
2. **Aplicar** `5208` → `5209` → `5210` → `5211` (uma migration por arquivo).
3. **Postcheck:** `SECURITY DEFINER`, `search_path ""`, ACL só `authenticated`; corpo = arquivo.
4. **Rodar `5846`** (um statement): GATE 27/27, `99.1` resíduo zero.
5. **Se PASS:** promover para `database/schema/` com cabeçalho do ledger; `05d`, `log`, `INDEX`.

**STOP:** erro ao aplicar, FAIL/`X.1` no 5846, resíduo, ACL ou corpo divergente.

## Recuperação

`drop function if exists` das quatro (comando no cabeçalho de cada arquivo). Nenhum dado depende delas: vínculos criados pela `5210` são linhas canônicas da `6117` e continuam válidos sem a função.

## Execução no LIVE (2026-10-19)

| Etapa | Resultado |
|---|---|
| Pré-checagem | As quatro funções não existiam; 0 transações longas. |
| Aplicação | `5208` → `5209` → `5210` → `5211`, uma migration por arquivo, sem erro. |
| Postcheck | `SECURITY DEFINER`, `search_path ""`, ACL só `authenticated` (+ dono); md5 do corpo igual ao arquivo nas quatro. |
| `5846` | **27/27 PASS + GATE PASS**, `99.1` resíduo zero. |
| Desempenho (coleção Pokédex real, acervo de 1.351 exemplares) | Aquecido: `5208` SPECIES 27 ms; `5208` ACERVO 43–84 ms; `5209` 28 ms; `5211` (Pokédex inteira, 500 linhas) ~150 ms. A **primeira** chamada em cada conexão nova custou 0,7–1,1 s (compilação do plano PL/pgSQL e cache frio); as seguintes, os valores acima. |
