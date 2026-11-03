# V1-11 W3 — Lista de desejos no Master Set (lacuna L2)

| Campo | Valor |
|---|---|
| Status | **5348 CONFIRMADO EXECUTADO no LIVE** (2026-11-02, `LIVE SQL VALIDATION-02`; ledger `20261102213912`; corpo executado = arquivo, sem edição). Harness `5874` v1.0 executado: **GATE PASS 14/14**, sem X.1, resíduo zero. **5348 promovida byte-idêntica para `database/schema/` (2026-11-02, `FINAL COMMIT`)**; harness `5874` permanece aqui. W3 homologada (8/8); publicação pendente. |
| Data | 2026-11-02 (`V1-11 W3 | MASTER SET INTEGRATION-01`) |
| Pré-requisitos | 5345–5347 (W1) no LIVE |
| Executor | Fabrício, com autorização explícita |

## Por que

A posição do Master Set é **carta + acabamento** (5189/5198). O desejo é por **Card Variant** (5345). As leituras da W1 não trazem o acabamento da variante: 5163 (seletor) oferece todas as variantes da carta e 5346 (`get_my_wishlist_state_by_card`) diz qual variante é desejada, mas não em qual acabamento. Como `card_variant` só é legível por admin (RLS), o frontend não consegue cruzar sozinho. Sem esta extensão, a grade ofereceria variantes incompatíveis com a posição, ou presumiria a variante padrão.

## O que muda

| Query | Objeto | Tipo |
|---|---|---|
| 5348 | `get_catalog_card_variants_for_finish(p_card_id, p_variant_type_id)` | leitura de catálogo: variantes **ativas** de carta **ativa** no acabamento da posição; `NULL` = posição de carta secreta (qualquer acabamento, regra de 5198) |
| 5348 | `get_my_wishlist_state_by_card_finish(p_card_ids)` | leitura do usuário: mesmas linhas de `get_my_wishlist_state_by_card` + `variant_type_id` |
| 5874 | harness | 14 checagens (estrutura, ACL, anon, sem identidade, argumentos, filtro por acabamento em até 300 pares, NULL = 5163, inativas, isolamento, equivalência com 5346, C-214, resíduo zero) |

Sem tabela, sem escrita, sem alteração em 5163/5345–5347. Inclusão e remoção continuam em `add_my_wishlist_entry` / `remove_my_wishlist_entries` (W1), com as mesmas regras (idempotência; remoção bloqueada com mais de um desejo da variante).

## Plano de aplicação

1. Aplicar `5348_create_wishlist_finish_functions.sql`.
2. Executar `5874_validate_wishlist_finish_functions.sql` (uma chamada) — esperado `GATE PASS 14/14`.
3. Só então homologar a grade do Master Set. Antes da 5348, o frontend já publicado **não mostra** o marcador no Master Set (leitura falha → sem marcador); nenhuma outra tela muda.

## Execução no LIVE (2026-11-02, `LIVE SQL VALIDATION-02`)

| Passo | Resultado |
|---|---|
| Precheck | `mimikyu-core`; dependências presentes; nenhuma função homônima |
| `5348` | sucesso; 2 funções; ledger `20261102213912` |
| `5874` | 14/14 `PASS` + `GATE PASS 14/14`; nenhuma `X.1`; `9.1` resíduo zero |
| Postcheck | 2 funções SECURITY DEFINER/STABLE/`search_path` vazio; EXECUTE só `authenticated`; 7 funções pré-existentes (5163, 5346, 5347) com definição idêntica (md5 antes = depois); contagens de desejos e usuários inalteradas |

Limitação registrada: a checagem `3.4` cobriu só **carta inexistente** (0 linhas). O caso **carta inativa** não foi exercitado — o catálogo LIVE não tem carta inativa com variante; a regra fica garantida pelo filtro `c.is_active` da função, sem prova em dado real.

## Rollback

```sql
drop function if exists public.get_catalog_card_variants_for_finish(uuid, uuid);
drop function if exists public.get_my_wishlist_state_by_card_finish(uuid[]);
```
Sem dados a desfazer (só leituras).
