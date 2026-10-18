# Proposta — exemplares livres por posição do Master Set (`5199`)

| Campo | Valor |
|---|---|
| **Status** | `5199` CONFIRMADO EXECUTADO no LIVE (2026-10-18, `POSITION-COPIES-LIVE-GATE-01`, autorização de Fabrício; ledger `20261018204909`); `5842` v1.1 30/30 PASS, resíduo zero. Promovida para `database/schema/` em 2026-10-18 (`5199-CLOSEOUT`; corpo = LIVE, md5 `7b54d663…`). |
| **Origem** | `MASTER-SET-FRONTEND-PHASE-02` (2026-10-18) |
| **Versões** | `5199` v1.1 · `5842` v1.1 |

## Por que existe

O fluxo "Adicionar do acervo" da grade Master Set precisa vincular um exemplar que **realmente satisfaça** a posição (carta + acabamento, ou carta secreta genérica). A grade (`5189`/`5198`) só dá a contagem (`copies_available`). Os contratos do Meu acervo (`5159`/`5162`) não expõem o acabamento, e `card_variant` é admin-only (ADR-022). Sem esta leitura, a interface teria de adivinhar o acabamento pelo texto do rótulo — recusado por integridade.

## Arquivos

| Query | Arquivo | Natureza |
|---|---|---|
| `5199` | `5199_create_get_my_master_set_position_copies_function.sql` | Função nova, só leitura (SECURITY DEFINER, STABLE, `search_path ''`, EXECUTE só `authenticated`). Não altera nenhum contrato existente. |
| `5842` | `5842_validate_master_set_position_copies.sql` | Harness v1.1: 30 verificações + GATE, fixture sintética desfeita pela sentinela `MS842`, resíduo zero (protocolo da `5836`). |

## Contrato (`5199` v1.1)

`get_my_master_set_position_copies(p_collection_id uuid, p_card_id uuid, p_variant_type_id uuid default null, p_limit integer default 50, p_offset integer default 0)`
→ `physical_card_id, variant_label, is_default_variant, language_code, language_name, storage_name, added_at, total_count`

- Zero linhas, sem distinguir: coleção inexistente, de outro usuário, arquivada, livre, Pokédex, em Set padrão; posição fora do objetivo vigente.
- Elegível: exemplar do acervo do usuário, da carta, no acabamento da posição (qualquer acabamento na genérica), sem vínculo com nenhuma coleção. Idioma, edição e impressão não criam posição nem impedem.
- Mesma regra de `copies_available` da `5198` — `total_count` = `copies_available` da posição (provado pela `5842` 4.2).
- Ordem: variante padrão, `language_order`, `created_at`, `id`. Página: 1..100, offset 0..10000.
- Retorno mínimo: só `physical_card_id` como identificador (necessário para a `5046`).
- Erros: `28000`, `22023 INVALID_PAGE`, `22023 INVALID_POSITION`.

## Vínculo

Continua sendo a `5046` (`allocate_physical_cards_to_collection`), sem mudança. A `5199` não promete exclusividade — se outro dispositivo vincular o mesmo exemplar antes, a `5046` recusa e a interface relê (provado pela `5842` 7.3).

## Plano de aplicação no LIVE (só com autorização)

1. **Pré-checagem (leitura):** `select to_regprocedure('public.get_my_master_set_position_copies(uuid,uuid,uuid,integer,integer)')` → `null`; nenhuma sobrecarga com o mesmo nome.
2. **Aplicar `5199`** (DDL de uma função, sem tabela, sem dado). Registrar o ledger.
3. **Rodar `5842` v1.1** no SQL Editor, um statement. Esperado: `GATE PASS 30/30`; `99.1` resíduo zero.
4. **Se FAIL:** `drop function if exists public.get_my_master_set_position_copies(uuid, uuid, uuid, integer, integer);` — nenhum dado depende dela; registrar o motivo.
5. **Se PASS:** advisors de segurança; promover `5199` para `database/schema/`; atualizar 05d/log/HANDOFF.
6. **Frontend:** só então `MASTER_SET_ADD_FROM_ACERVO_ENABLED = true`, homologação local (com `MASTER_SET_OBJECTIVE_ENABLED = true` local) e publicação.

## Recuperação

`drop function if exists public.get_my_master_set_position_copies(uuid, uuid, uuid, integer, integer);`

## Execução no LIVE (2026-10-18, `POSITION-COPIES-LIVE-GATE-01`)

- Gate de entrada (só leitura): assinatura ausente, 0 sobrecargas; ledger com `5184`–`5198`; 0 transações > 1 min, 0 esperas de lock; nenhum resíduo sintético prévio; códigos de catálogo da fixture presentes e ativos.
- `5199` aplicada (parte executável do arquivo, sem alteração; md5 do arquivo `be59e765…`): ledger `20261018204909`; SECURITY DEFINER, STABLE, `search_path ""`, EXECUTE só `authenticated` (anon e PUBLIC sem acesso); corpo md5 `7b54d663a0dc05fd0707cb430b63bbfa`.
- `5842` v1.1 (md5 `caeb244f…`): **GATE PASS 30/30**; 99.1 resíduo zero. Conferência independente depois: 3 coleções, 210 vínculos, 1.351 exemplares, 1 local, 0 Master Set, 0 acabamentos, 0 usuários/expansões sintéticos — igual à linha de base.
- Desempenho (massa sintética revertida sobre o maior Set real — 300 cartas ativas, objetivo com 2 acabamentos, 300 posições; acervo sintético de 1.500 exemplares, 304 elegíveis na posição medida; página de 50; 20 execuções após aquecimento): p50 5,55 ms · p95 14,38 ms · máx. 15,24 ms. Posição inexistente (recusa): p50 2,2 ms · máx. 2,81 ms. Resíduo zero.
- Security Advisor (lido por inteiro, 6 lints): a 5199 aparece só em `authenticated_security_definer_function_executable` (WARN genérico que lista todas as 166 RPCs SECURITY DEFINER para `authenticated`, incluindo os 6 contratos do Master Set — por desenho). Não aparece em `anon_security_definer_function_executable` (só `username_available`) nem em `function_search_path_mutable`.
