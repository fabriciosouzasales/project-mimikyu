# V1-11 W4 — Lista de desejos a partir da Pokédex (lacuna L3)

| Campo | Valor |
|---|---|
| Status | **5349 CONFIRMADO EXECUTADO no LIVE** (2026-11-02, `LIVE SQL VALIDATION-02`; ledger `20261103003058`; corpo executado = arquivo, sem edição). Harness `5875` v1.0 executado: **GATE PASS 11/11**, sem X.1, resíduo zero. **5349 promovida byte-idêntica para `database/schema/` (2026-11-02, `FINAL COMMIT`)**; harness `5875` permanece aqui. W4 homologada (7/7); publicação pendente. |
| Data | 2026-11-02 (`V1-11 W4 | POKÉDEX INTEGRATION-01`) |
| Pré-requisitos | 5345–5347 (W1) e 6112 (`card_primary_species`) no LIVE |
| Executor | Fabrício, com autorização explícita |

## Por que

A posição da Pokédex é uma **espécie**; o desejo é por **Card Variant** (5345). Não existe leitura para o usuário final que liste as cartas do catálogo de uma espécie: `card`, `card_variant` e `card_primary_species` só são legíveis por admin (RLS), a 5208 lista só **exemplares do acervo** e `search_cards` não filtra por espécie. Sem esta leitura, a Pokédex não consegue oferecer a escolha explícita da carta (nunca presumir a carta pela espécie).

## O que muda

| Query | Objeto | Tipo |
|---|---|---|
| 5349 | `get_catalog_cards_for_species(p_species_id, p_limit = 24, p_offset = 0)` | leitura de catálogo, paginada (1..60): cartas **ativas**, categoria `POKEMON`, espécie primária = a pedida (regra de 5208), com ao menos uma variante **ativa**; imagem CARD_FRONT; contagem de variantes ativas; `total_count` |
| 5875 | harness | 11 checagens: estrutura, ACL, anon, sem identidade, argumentos, conjunto exato em até 120 espécies (paginado até o fim), exclusões, paginação estável, espécie inexistente, contagem de variantes, papel restaurado |

Sem tabela, sem escrita e sem dado de usuário. A variante continua em 5163 e a inclusão/remoção nas funções da W1 (5346), com as mesmas regras (idioma "qualquer", idempotência, remoção bloqueada com mais de um desejo da variante).

## Plano de aplicação

1. Aplicar `5349_create_get_catalog_cards_for_species_function.sql`.
2. Executar `5875_validate_get_catalog_cards_for_species.sql` (uma chamada) — esperado `GATE PASS 11/11`.
3. Só então homologar. Antes da 5349, abrir "Desejar uma carta de …" no painel da Pokédex mostra a mensagem de falha recuperável ("Não conseguimos carregar as cartas…"); nada é gravado e nenhuma outra tela muda.

## Execução no LIVE (2026-11-02, `LIVE SQL VALIDATION-02`)

| Passo | Resultado |
|---|---|
| Precheck | `mimikyu-core`; dependências presentes (card_primary_species, card, card_set, card_variant, card_asset, categoria POKEMON, CARD_FRONT); nenhuma função homônima |
| `5349` | sucesso; ledger `20261103003058` |
| `5875` | 11/11 `PASS` + `GATE PASS 11/11`; nenhuma `X.1`: conjunto exato em 120 espécies (5.027 cartas), 0 cartas inelegíveis, paginação estável, `active_variant_count` correto em 597 cartas, espécie inexistente = 0 |
| Postcheck | SECURITY DEFINER/STABLE/`search_path` vazio; EXECUTE só `authenticated`; 10 funções pré-existentes (W1, W3, 5163, 5208) com definição idêntica; contagens de cartas, variantes, espécies, desejos e usuários inalteradas |

## Rollback

```sql
drop function if exists public.get_catalog_cards_for_species(uuid, integer, integer);
```
Sem dados a desfazer (só leitura).
