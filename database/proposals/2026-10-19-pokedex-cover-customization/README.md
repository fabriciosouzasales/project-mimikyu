# Proposta — Capa e código no fichário da coleção Pokédex (`5206`, `5207`)

| Campo | Valor |
|---|---|
| **Status** | **EXECUTADA / CANÔNICA** (2026-10-19, autorização de Fabrício). `5206` (ledger `20261019034918`) e `5207` (ledger `20261019034933`) aplicadas; corpos idênticos aos arquivos; `5845` v1.1 **15/15 PASS**, resíduo zero. `database/schema/5178` → v1.2 e `5180` → v1.1. |
| **Origem** | `POKEDEX-COVER-CUSTOMIZATION-01` (2026-10-19), pedido do proprietário: o fichário da Pokédex tem as mesmas personalizações da Coleção livre (imagem da capa e código). |
| **Versões** | `5206` v1.0 (corpo de `5178` v1.1) · `5207` v1.0 (corpo de `5180` v1.1) · `5844`→ não afetado · `5845` v1.0 |

## O que muda

| Query | Arquivo | Mudança |
|---|---|---|
| `5206` | `5206_update_set_my_collection_cover_logo_for_pokedex.sql` | `set_my_collection_cover_logo` passa a aceitar também a coleção Pokédex (`REFERENCE_POSITION` + referência `POKEDEX`). |
| `5207` | `5207_update_set_my_collection_cover_code_for_pokedex.sql` | `set_my_collection_cover_code`: a mesma ampliação. |
| `5845` | `5845_validate_pokedex_cover_customization.sql` | Harness: 15 verificações + GATE; fixture desfeita pela sentinela `MS845`; resíduo zero. |

Só a regra de elegibilidade muda (`create or replace`, mesma assinatura e mesmos grants). Coleção de Set continua recusada com `55000 NOT_FREE_COLLECTION`, a mensagem que o frontend já trata — a capa do Set é a identidade oficial do Set. Tabela, colunas (`cover_logo_path` 5177, `cover_code` 5179), CHECKs, bucket `collection-cover` e políticas (5176, por dono e pela pasta `usuário/coleção`) não mudam.

## Plano de execução (só com autorização)

1. **Pré-checagem (leitura):** md5 de `prosrc` das duas funções igual ao canônico 5178/5180; 0 transações longas.
2. **Aplicar** `5206` → `5207` (uma migration por arquivo).
3. **Postcheck:** `SECURITY DEFINER`, `search_path ""`, ACL só `authenticated`; corpo = arquivo.
4. **Rodar `5845`** (um statement): GATE 15/15, `99.1` resíduo zero.
5. **Se PASS:** atualizar `database/schema/5178` e `5180` para v1.1 (corpo das propostas, cabeçalho com ledger) e `05d`/`log`.

**STOP:** erro ao aplicar, FAIL/`X.1` no 5845, resíduo, ACL ou corpo divergente.

## Recuperação

Reaplicar `database/schema/5178_create_set_my_collection_cover_logo_function.sql` e `5180_create_set_my_collection_cover_code_function.sql` (v1.0). Nenhum dado depende da ampliação; se alguma Pokédex já tiver capa/código gravados, eles continuam na coluna e só deixam de ser editáveis.

## Execução no LIVE (2026-10-19)

| Etapa | Resultado |
|---|---|
| Pré-checagem | md5 do corpo de 5178/5180 no LIVE = canônico; 0 transações longas. |
| Aplicação | `5206` → `5207`, sem erro. |
| Postcheck | `SECURITY DEFINER`, `search_path ""`, ACL só `authenticated`; md5 do corpo = arquivo (`5868fb1c…`, `d0d8cbfa…`). |
| `5845` v1.0 | 14/15 — **falso FAIL em 5.1**: o harness lia `collection_completion_summary` (só responde ao dono) com a identidade do usuário B e recebia nulo. Nenhuma função testada envolvida. |
| `5845` v1.1 | Correção só no harness (resumo lido com a identidade do dono, e 5.1 exige total > 0): **15/15 PASS + GATE PASS**, resíduo zero. |
| Promoção | `database/schema/5178` v1.2 e `5180` v1.1 com o corpo das propostas. |
