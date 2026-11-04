# V1-11 W7 — Faltantes em lote na Lista de desejos

| Campo | Valor |
|---|---|
| Status | **5352 CONFIRMADO EXECUTADO no LIVE** (2026-11-04 UTC, `LIVE SQL VALIDATION-04`; ledger `20261104005319`; corpo executado = arquivo, sem edição, md5 `8a7aed748a200d9575ef894327f344a7`). Harness `5878` v1.0: **GATE PASS 13/13**, sem X.1, resíduo zero; postcheck sem alteração em funções vizinhas nem em dados. **5352 promovida para `database/schema/` (2026-11-04, `FINAL COMMIT`)** com o corpo SQL idêntico ao executado — só o cabeçalho de comentário passou a registrar o status (por isso o md5 do arquivo promovido difere); harness `5878` permanece aqui. Confirmação revalidada no servidor (`CONFIRMATION ELIGIBILITY FIX-03`). **W7 homologada; publicação pendente.** |
| Data | 2026-11-03 |
| Pré-requisitos | 5345–5348 (W1, W3) no LIVE |
| Executor | Fabrício, com autorização explícita |

## Por que (lacuna comprovada)

O contrato (`wishlist-product-contract.md` §4.2) pede a inclusão de faltantes de Set e Master Set em lote, com prévia separando *inclusões diretas*, *já na lista* e *exigem escolha*. Faltavam duas peças no banco:

1. **Variantes candidatas em lote.** Só existem leituras de UMA carta (5163, 5348); `card_variant` não é legível pelo usuário final (RLS admin). Classificar 200 posições seriam 200 chamadas.
2. **Gravação em lote.** `add_my_wishlist_entry` (5346) grava um desejo por chamada; um lote viraria N idas ao banco, sem transação nem resultado único.

## O que muda

| Query | Objeto | Tipo |
|---|---|---|
| 5352 | `get_catalog_card_variants_for_cards(p_card_ids uuid[])` | leitura de catálogo: variantes ativas (com acabamento) de até 500 cartas ativas — as mesmas linhas de 5348 com acabamento NULL, por carta |
| 5352 | `add_my_wishlist_entries(p_card_variant_ids uuid[])` | inclusão em lote (até 500, uma transação), sempre "qualquer idioma"; idempotente; uma linha por variante: `CREATED` / `EXISTING` / `UNAVAILABLE` |
| 5878 | harness | 13 checagens (estrutura, ACL, anon, sem identidade, argumentos, lote = 5348 por carta, criação, idempotência, repetidos, indisponível no meio do lote, isolamento A×B, nada fora da Lista, resíduo zero) |

Sem tabela, sem índice, sem alterar 5163/5346/5348. Identidade só por `auth.uid()`; EXECUTE só `authenticated`. A gravação toca apenas `card_wishlist_entry` — nenhuma coleção, posição, exemplar, alocação, reserva ou progresso (C-211).

## Plano de aplicação

1. Aplicar `database/schema/5352_create_wishlist_bulk_functions.sql` (antes em `proposals/`).
2. Executar `5878_validate_wishlist_bulk_functions.sql` (uma chamada) — esperado `GATE PASS 13/13`.
3. Homologar. Antes da 5352, o botão "Desejar faltantes" aparece, mas a prévia mostra "Este recurso ainda não está disponível" (a leitura em lote não existe) — nada é gravado e nada mais muda.

## Rollback

```sql
drop function if exists public.add_my_wishlist_entries(uuid[]);
drop function if exists public.get_catalog_card_variants_for_cards(uuid[]);
```
Sem dados a desfazer além dos desejos que o próprio usuário incluiu (que continuam válidos, como qualquer desejo da W1).
