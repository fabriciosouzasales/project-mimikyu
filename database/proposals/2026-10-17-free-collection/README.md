# Coleção livre — CT-01 estendido (`5175` + `5832`)

| Campo | Valor |
|---|---|
| Rodada | `COLLECTIONS-FUNCTIONAL-RECOVERY-01` (2026-10-17) |
| Status | **CONFIRMADO EXECUTADO no LIVE em 2026-10-17** (`FREE-COLLECTION-5175-LIVE`, autorização de Fabrício). `5175` aplicada (ledger `20261017222919`) e promovida para `database/schema/`; `5832` v1.1 **25/25 PASS + GATE PASS**. Interface ainda desligada (`FREE_COLLECTION_ENABLED = false`). |
| Autoridade | North Star v1.6 — NS-18, Fluxo 1.2/1.3, §2.6 (CT-01 itens 1–7 e nota 8), NS-13, NS-15 (D-A); C-02, C-20, C-26, C-36, C-57 |

## Objetivo

Permitir criar uma **Coleção livre** (curadoria aberta, sem referência a Set e sem progresso) com as mesmas garantias já provadas para "Completar um Set" (`5167`): transação única, idempotência por chave do cliente, regra D-A do local, isolamento por usuário e nenhuma carta tocada.

## Arquivos

| Query | Arquivo | Tipo | O que faz |
|---|---|---|---|
| `5175` | `5175_create_create_my_free_collection_function.sql` | DDL (função nova) | `create_my_free_collection(p_idempotency_key, p_name, p_storage_container_id)` |
| `5832` | `5832_validate_free_collection.sql` | Harness (somente teste, revertido) | v1.1: 25 checagens + GATE; resíduo zero |

## Menor proposta possível

- **Uma função nova, nenhuma tabela, coluna, índice, policy ou alteração de contrato existente.**
- Reutiliza sem alterar: `create_collection` (`5034`/`5068` — já grava `OPEN_CURATION` + `completion_policy = NONE`), `create_storage_container` (`5022`) e a tabela de idempotência `collection_creation_request` (`5166`).
- `5167` (Set) fica intacta. As duas portas usam **a mesma chave de advisory lock**, então a decisão D-A acontece em fila única: um "Completar um Set" e uma "Coleção livre" enviados ao mesmo tempo nunca criam dois "Local padrão".
- O hash do pedido livre começa com `FREE`; uma chave de idempotência usada numa porta não serve à outra (`IDEMPOTENCY_KEY_REUSED`).
- Game: o produto é Pokémon TCG (ADR-011) e a Coleção livre não pede jogo ao colecionador. O Game é resolvido pelo código estável `POKEMON` (mesmo critério de `5090`/`2247`); sem ele, `GAME_NOT_FOUND` e nada é gravado.

## Contrato

```
create_my_free_collection(
  p_idempotency_key      uuid,
  p_name                 text,
  p_storage_container_id uuid default null)
RETURNS TABLE(collection_id uuid, storage_container_id uuid,
              storage_container_created boolean, replayed boolean)
```

Erros: `28000` não autenticado · `22023` `INVALID_REQUEST` / `STORAGE_CONTAINER_INVALID` / `IDEMPOTENCY_KEY_REUSED` · `55000` `STORAGE_CONTAINER_REQUIRED` · `P0001` `GAME_NOT_FOUND`. Mesmos códigos e textos de `5167` (exceto `CARD_SET_NOT_FOUND`, que não se aplica) — o classificador do frontend já os trata.

Segurança: `SECURITY DEFINER`, `VOLATILE`, `search_path = ''`, dono por `auth.uid()`, `EXECUTE` só para `authenticated` (revogado de `PUBLIC` e `anon`), mesmo padrão de `5167`.

## Verificações preparadas (`5832`)

| Requisito | Checagens |
|---|---|
| Segurança e privilégios | 0.2, 0.3 (ACL idêntica à de `5167`), 1.1 (anon `42501`), 2.1 (sem identidade `28000`) |
| Isolamento entre usuários | 4.7 (local de outro usuário recusado), 4.11 (mesma chave usada por outro usuário cria coleção própria, sem devolver nada de A), 5.3 (B vê só a própria) |
| Atomicidade | 3.1 — falha induzida **depois** de criar o "Local padrão": nenhum local, coleção ou registro fica |
| Idempotência | 4.2 (replay), 4.3 (chave reutilizada), 4.4 (chaves não se cruzam entre `5167` e `5175`) |
| Regra D-A | 4.1 (sem local → "Local padrão"), 4.5 (com local → `55000`), 4.6 (escolha explícita, nada novo) |
| Curadoria aberta sem progresso | 4.1, 4.10 (sem referência), 5.1 (R1 devolve progresso nulo) |
| Nenhuma carta tocada | 0.4 (corpo não referencia `physical_card`/`collection_allocation`), 4.9 (nenhum exemplar nem vínculo dos usuários de teste), 9.1 (contagem global) |
| Integridade adiada | 4.12 — `SET CONSTRAINTS ALL IMMEDIATE` dentro do bloco: os gatilhos adiados de consistência de referência (`5057`–`5059`) são conferidos antes da reversão |
| Fila única com `5167` | 6.1 |
| Preservação dos dados reais / resíduo zero | Usuários de teste efêmeros; tudo revertido pela sentinela `LI000`; 9.1 compara 9 contagens com a linha de base |

Concorrência real (dois envios simultâneos) não é provável num único statement; a garantia vem do advisory lock compartilhado (6.1), o mesmo mecanismo já validado em `5830`.

## Execução proposta (quando autorizada)

1. Aplicar `5175` (uma migration).
2. Executar `5832` (`SELECT * FROM pg_temp.rc_5832_validate();`) — esperado **25/25 PASS + GATE PASS**.
3. Security Advisor antes × depois: esperado só `0029` +1 (a função nova, `SECURITY DEFINER` por desenho, como `5167`).
4. Promover `5175` para `database/schema/` e registrar em `05d`, HANDOFF e log.
5. Só então ligar a opção "Coleção livre" no frontend (`FREE_COLLECTION_ENABLED`, `web/lib/colecoes/colecoes.ts`) — ver dependências no 05d.

Quem executa é Fabrício, uma Query por vez, confirmando antes de avançar (STD-001 §10).

## Revisão de readiness (`FREE-COLLECTION-READINESS-01`, 2026-10-17)

`5175` revisada contra `5166`/`5167`, `5034`/`5068`, `5022`, os gatilhos adiados de referência (`5057`–`5059`) e as decisões C-02, C-20, C-26, C-34, C-36, C-57, NS-13, NS-15, NS-18 e CT-01. **Nenhuma alteração em `5175`.** `5832` passou a v1.1 (quatro reforços: ACL comparada com a de `5167`; restrições adiadas forçadas; mesma chave usada por outro usuário; checagem de exemplares restrita aos usuários de teste). Parecer: **pronta para execução mediante autorização**; nenhum bloqueio no SQL. A liberação da opção na interface depende de itens de frontend listados no 05d.

## Execução no LIVE (`FREE-COLLECTION-5175-LIVE`, 2026-10-17)

| Etapa | Evidência |
|---|---|
| Pré-check (somente leitura) | `5175` inexistente; Game `POKEMON` presente; última migration `20261017191335`. Corpos de `5167` (`e6bd4883…`), `5068` (`38ed7e8b…`) e `5022` (`01e6f2f2…`) registrados por md5; ACL de `5167` = `postgres`, `authenticated`. |
| Linha de base dos dados reais | 3 usuários/perfis/Inventories · 1.287 exemplares · 1 local · 2 coleções · 154 vínculos · 2 referências · 2 registros de criação; fingerprints md5 de coleções, locais, vínculos e exemplares. |
| Aplicação | Só `5175` (`apply_migration`), ledger `20261017222919`. Corpo no LIVE idêntico ao arquivo (md5 `2cd097d85a7cc50d310355aa94abca48`); `SECURITY DEFINER`, `VOLATILE`, `search_path` vazio; ACL igual à de `5167`. `5167`, `5068` e `5022` com md5 inalterado. |
| `5832` v1.1 | **25/25 PASS + GATE PASS**: anon `42501`, sem identidade `28000`, atomicidade (3.1), D-A (4.1/4.5/4.6), idempotência e não cruzamento com `5167` (4.2–4.4), isolamento (4.7/4.11/5.3), `SET CONSTRAINTS ALL IMMEDIATE` sem violação (4.12), lock compartilhado (6.1), resíduo zero (9.1). |
| Pós-check | Todas as contagens e os quatro fingerprints idênticos à linha de base; gatilho de teste ausente. Nenhuma coleção, exemplar, vínculo ou local real alterado. |
| Security Advisor | Antes × depois: única diferença `authenticated_security_definer_function_executable` 158 → 159 (`create_my_free_collection`, esperado por desenho, como `5167`). Demais lints idênticos item a item. |
