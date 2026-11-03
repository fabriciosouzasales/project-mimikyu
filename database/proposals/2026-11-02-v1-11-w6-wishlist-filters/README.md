# V1-11 W6 — Filtros da Lista de desejos

| Campo | Valor |
|---|---|
| Status | **5350 CONFIRMADO EXECUTADO no LIVE** (2026-11-03 UTC, `LIVE SQL VALIDATION-02`; ledger `20261103015727`; corpo executado = arquivo, sem edição, md5 `8f10ab704ac2033b233f49c761dca356`). Harness `5876` v1.0 executado: **GATE PASS 17/17**, sem X.1, resíduo zero. **5351 CONFIRMADO EXECUTADO no LIVE** (2026-11-03, SQL Editor, por Fabrício); harness `5877`: **12/12 PASS**, resíduo zero. **5350 e 5351 promovidas para `database/schema/` (2026-11-03, `FINAL COMMIT`)** com o corpo SQL idêntico ao executado — só o cabeçalho de comentário passou a registrar o status (por isso o md5 do arquivo da 5350 difere do executado); harnesses `5876`/`5877` permanecem aqui. **W6 homologada (12/12); publicação pendente.** Fora desta entrega: filtro "Falta em alguma coleção". |
| Data | 2026-11-02 |
| Pré-requisitos | 5345–5347 (W1) no LIVE |
| Executor | Fabrício, com autorização explícita |

## Por que (lacuna comprovada)

`get_my_wishlist` (5346) só pagina (`p_limit`/`p_offset`): não aceita filtros e não devolve `card_set_id` nem raridade. Filtrar só as 60 linhas carregadas no cliente produziria resultados e contagens incompletos — proibido pelo pedido da W6. Não há outra leitura do usuário final que cruze desejos com Card Set/raridade (catálogo legível só por admin).

## O que muda

| Query | Objeto | Tipo |
|---|---|---|
| 5350 | `get_my_wishlist_filtered(p_limit, p_offset, p_search, p_card_set_id, p_rarity_id, p_language, p_ownership)` | leitura: mesmas colunas da 5346 + `card_set_id`, `rarity_id`, `rarity_name`; filtros aplicados ao conjunto inteiro do usuário antes de paginar; `total_count` = total filtrado; mesma ordem da 5346 |
| 5350 | `get_my_wishlist_filter_options()` | leitura: Card Sets, raridades, idiomas do desejo e posse **presentes na lista do usuário**, com contagem |
| 5876 | harness | 17 checagens (estrutura, ACL, anon, sem identidade, argumentos, igualdade com a 5346 sem filtro, Card Set, raridade, idioma qualquer/específico, posse, busca nome/número, combinação, paginação/total, isolamento A×B, opções, nenhuma escrita, resíduo zero) |

Sem tabela, sem índice, sem escrita. Identidade só por `auth.uid()`; EXECUTE só `authenticated`.

Regras: Card Set pela identidade canônica (`card.card_set_id`, nunca código nem Expansion); raridade = `card.rarity_id` do catálogo; idioma `'*'` = só desejos "qualquer idioma" (nunca um idioma específico); posse `OWNED` = `SAME_VARIANT_LANGUAGE` da derivação C-213 (mesma variante, idioma compatível — nunca só a carta), `NOT_OWNED` = o resto; busca = regra da 5159 (nome por trecho; número sem zeros à esquerda; "número/total").

## Plano de aplicação

1. Aplicar `database/schema/5350_create_wishlist_filter_functions.sql` (antes em `proposals/`).
2. Executar `5876_validate_wishlist_filters.sql` (uma chamada) — esperado `GATE PASS 17/17`.
3. Só então homologar. Antes da 5350, a página da Lista de desejos funciona exatamente como na W1: as opções de filtro não carregam e a barra não aparece; um link antigo com filtro mostra o erro recuperável "Não foi possível aplicar os filtros agora" com "Ver a lista completa".

## Execução no LIVE (2026-11-03 UTC, `LIVE SQL VALIDATION-02`)

| Passo | Resultado |
|---|---|
| Precheck | `mimikyu-core` (PG 17.6); nenhuma função homônima; dependências W1 (5345–5347) e tabelas/colunas usadas presentes (card, card_set, rarity, language, inventory, physical_card, card_asset, perfis de variante); idiomas en/pt-BR ativos |
| `5350` | sucesso; ledger `20261103015727` |
| `5876` | 17/17 `PASS` + `GATE PASS 17/17`: estrutura/ACL, anon 42501, sem identidade 28000, argumentos 22023; sem filtro = 5346; Card Set por `card_set_id`; raridade; '*' × en × pt-BR × inexistente; posse OWNED 2 / NOT_OWNED 1; busca nome/número com zeros/"número/total"; combinação; paginação = ordem da 5346 com total 3 em todas as páginas; isolamento A×B; opções; nenhuma escrita; resíduo zero |
| Performance | EXPLAIN (sem ANALYZE): posse por `ix_physical_card_inventory_variant`; carta/variante pela PK; desejos do usuário por `user_id` (seq scan só porque a tabela tem 34 linhas; índice `ix_card_wishlist_entry_user_recent` disponível). Nenhum problema concreto |
| Postcheck | 2 funções SECURITY DEFINER/STABLE/`search_path` vazio; EXECUTE só `authenticated`; 10 funções pré-existentes (W1–W4, 5159, 5163) com definição idêntica (md5); usuários 3, desejos 34, exemplares 2.954, cartas 21.246, variantes 38.011, coleções 10 — inalterados; única migration nova = 5350 |

## Ordenação (2026-11-03, `SORT-01`) — 5351 CONFIRMADO EXECUTADO no LIVE

| Query | Objeto | Tipo |
|---|---|---|
| 5351 | `get_my_wishlist_filtered(..., p_sort text default 'RECENT')` | substitui a assinatura de 7 argumentos da 5350 (drop + create na mesma transação; uma versão só). `RECENT` = ordem da 5350/5346; `SET_NUMBER` = regra do Meu acervo (5159/5261): Card Set mais recente → número → variante → "qualquer idioma" antes de idioma específico; desempate data/id. Inválido → 22023 `INVALID_SORT`. Resto idêntico à 5350 |
| 5877 | harness | 12 checagens (estrutura/versão única, ACL, anon, sem identidade, ordem inválida, RECENT = 5346 inclusive chamada antiga por nome, SET_NUMBER = ordem do catálogo, paginação/total, ordem + filtro, isolamento, nenhuma escrita, resíduo zero) |

Execução (2026-11-03): Fabrício aplicou a `5351` no SQL Editor, sem edição (a chamada via ferramenta foi bloqueada pela permissão do ambiente; por isso não há entrada no ledger de migrations). `5877` v1.0: **12/12 checagens PASS**, resíduo zero; GATE agregado FAIL só porque a constante esperada era 11 (erro do harness, não da função) — corrigida na v1.1, não reexecutada. Postcheck (leitura): uma versão só de `get_my_wishlist_filtered` (8 argumentos), SECURITY DEFINER/STABLE/`search_path` vazio, EXECUTE só `authenticated`; as 11 funções vizinhas (W1–W4, 5159, 5163, opções da 5350) com definição idêntica; usuários 3, desejos 34, exemplares 2.954, cartas 21.246, variantes 38.011, coleções 10 — inalterados.

Plano original: aplicar `5351` (hoje `database/schema/5351_add_wishlist_filtered_sort.sql`) → executar `5877`. Depois da 5351 a 5876 não serve mais de gate (procura a assinatura de 7 argumentos). Antes da 5351, "Mais recentes" funciona (o cliente só envia `p_sort` em "Set e número"); "Set e número" mostra o erro recuperável "Não foi possível ordenar sua lista agora" com "Ver a lista completa".

Rollback da 5351: `drop function if exists public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text, text);` e reaplicar a seção 1 da 5350.

## Rollback

```sql
drop function if exists public.get_my_wishlist_filtered(integer, integer, text, uuid, uuid, text, text);
drop function if exists public.get_my_wishlist_filter_options();
```
Sem dados a desfazer (só leitura).
