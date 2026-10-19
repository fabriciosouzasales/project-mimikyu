# Proposta — "Adicionar cartas" em lote no Master Set (`5200`)

| Campo | Valor |
|---|---|
| **Status** | `5200` CONFIRMADO EXECUTADO no LIVE (2026-10-18, `MASTER-SET-LINK-CANDIDATES-LIVE-01`, autorização de Fabrício; ledger `20261019001438`); `5843` v1.0 25/25 PASS, resíduo zero. Promovida para `database/schema/` (corpo = LIVE, md5 `e3808d1c…`). |
| **Origem** | `MASTER-SET-LINK-CANDIDATES-01` (2026-10-18) |
| **Versões** | `5200` v1.0 · `5843` v1.0 |

## Por que existe

No Set padrão, o botão "Adicionar cartas (N)" usa a `5170`, que escolhe **um exemplar por carta** e só aceita coleção `STANDARD_SET`. No Master Set a unidade é a **posição** (carta + acabamento; carta secreta sem acabamento escolhido = posição genérica), então a `5170` não serve: devolveria zero linhas e, mesmo sem o filtro, ignoraria o acabamento. Sem uma leitura própria, a interface teria de chamar a `5199` uma vez por posição (N+1: 194 chamadas no ME5).

## Arquivos

| Query | Arquivo | Natureza |
|---|---|---|
| `5200` | `5200_create_get_my_master_set_link_candidates_function.sql` | Função nova, só leitura (SECURITY DEFINER, STABLE, `search_path ''`, EXECUTE só `authenticated`). Não altera nenhum contrato existente. |
| `5843` | `5843_validate_master_set_link_candidates.sql` | Harness v1.0: 25 verificações + GATE, fixture sintética da `5842`, sentinela `MS843`, resíduo zero. |

## Contrato (`5200` v1.0)

`get_my_master_set_link_candidates(p_collection_id uuid, p_limit integer default 500)`
→ `physical_card_id, card_id, variant_type_id, collector_number, card_name, variant_type_name, is_secret, language_code, image_path, total_count`

- Uma linha por posição do objetivo vigente **ainda não satisfeita** nesta coleção e com exemplar livre no acervo.
- Exemplar elegível = a regra da `5198`/`5199`. Escolha por posição = o 1º exemplar da `5199` (variante padrão, `language_order`, mais antigo, `id`) — provado pela `5843` 4.2.
- Nenhum exemplar aparece em duas posições (um exemplar tem um acabamento; uma carta tem posições por acabamento **ou** a genérica) → o lote inteiro é aceito pela `5046` numa chamada (`5843` 7.2).
- Ordem do Set; `total_count` antes do limite; limite 1..500 (teto da `5046`).
- Zero linhas, sem distinguir: coleção inexistente, alheia, arquivada, livre, Pokédex ou Set padrão.
- Erros: `28000`, `22023 INVALID_LIMIT`.

## Vínculo

Continua sendo a `5046`, sem mudança. A leitura recalcula do estado atual a cada chamada; reenviar o mesmo lote é recusado pela `5046` (`5843` 7.3), então retry não duplica.

## Desempenho (pré-medição, só leitura)

O corpo da `5200` foi executado como `EXPLAIN ANALYZE` (consulta equivalente, sem criar função) sobre a coleção real "Escuridão Absoluta" (ME5, 194 posições, 3 acabamentos, 0 vínculos): **93 candidatos, ~0,5 s** na primeira execução fria (planejamento 169 ms; `master_set_positions` 236 ms). Mesma forma da `5198`. Medição definitiva depois de aplicada.

## Plano de aplicação no LIVE (só com autorização)

1. **Pré-checagem (leitura):** `select to_regprocedure('public.get_my_master_set_link_candidates(uuid,integer)')` → `null`; nenhuma sobrecarga com o mesmo nome.
2. **Aplicar `5200`** (DDL de uma função, sem tabela, sem dado). Registrar o ledger.
3. **Rodar `5843` v1.0** num único statement. Esperado: `GATE PASS 25/25`; `99.1` resíduo zero.
4. **Se FAIL:** recuperação abaixo; registrar o motivo.
5. **Se PASS:** advisors de segurança; promover `5200` para `database/schema/`; atualizar 05d/log/HANDOFF.
6. **Frontend:** já preparado atrás de `MASTER_SET_ADD_FROM_ACERVO_ENABLED`. Antes da `5200` existir, o botão não aparece (a contagem falha e é tratada como zero).

## Recuperação

`drop function if exists public.get_my_master_set_link_candidates(uuid, integer);` — nenhum dado depende dela.

## Execução no LIVE (2026-10-18, `MASTER-SET-LINK-CANDIDATES-LIVE-01`)

- Pré-checagem (só leitura): assinatura ausente, 0 sobrecargas; `master_set_positions` e `5199` presentes; 0 transações > 1 min; nenhum resíduo sintético; linha de base 4 coleções, 210 vínculos, 1.351 exemplares, 3 acabamentos, 3 usuários.
- `5200` aplicada (parte executável do arquivo, sem alteração): ledger `20261019001438`; SECURITY DEFINER, STABLE, `search_path ""`, EXECUTE só `authenticated` (ACL `postgres, authenticated`); corpo md5 `e3808d1cac7f7e8fe87325ef63bc17f1` = arquivo.
- `5843` v1.0: **GATE PASS 25/25**; `99.1` resíduo zero. Conferência independente depois: mesmas contagens da linha de base, 0 expansões sintéticas.
- Coleção real "Escuridão Absoluta" (ME5, 194 posições, 3 acabamentos), leitura como o dono em transação `read only`: 93 candidatos (93 exemplares distintos, 12 secretas, todos com arte) = 93 posições faltantes com exemplar disponível na grade (`5198`). Tempo: 23,5 ms (500) e 7,2 ms (limite 1, a contagem do botão).
- Security Advisor (6 lints, mesmos de antes): a `5200` aparece só em `authenticated_security_definer_function_executable` (WARN genérico, por desenho); não aparece em `anon_security_definer_function_executable` nem em `function_search_path_mutable`.
