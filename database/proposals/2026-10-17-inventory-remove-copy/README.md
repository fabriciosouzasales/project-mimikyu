# Meu acervo — remover exemplar cadastrado por engano (INVENTORY-REMOVE-COPY-01)

| Campo | Valor |
|---|---|
| Data | 2026-10-17 |
| Origem | Pedido de Fabrício: ícone de lixeira por exemplar no detalhe da carta. |
| Status | **5165 CONFIRMADO EXECUTADO no LIVE** (2026-10-17, autorizado por Fabrício). **Promovida para `database/schema/` em 2026-10-17** (corpo idêntico ao LIVE, conferido por md5 de `prosrc`). **CLOSED.** |
| Contratos C-*/LDM-* | **Não alterados.** A operação é nova no domínio ("correção de cadastro") — ver §3: registrar como C-*/LDM-* exige autorização. |

## 1. Artefatos

| Query | Objeto | Papel |
|---|---|---|
| 5165 | `remove_my_physical_card(uuid) → boolean` | Remove um exemplar do próprio usuário, só se fora de coleção. `true` removido; `false` inexistente/alheio/já removido (não enumera, idempotente). `55000 PHYSICAL_CARD_ALLOCATED` se estiver em coleção. |
| 5829 | Harness | Estrutura/ACL, anon (42501), sem identidade (28000), usuário B sobre exemplar de A (`false`, intacto), id nulo (22023), remoção própria (`true`), repetição (`false`), inexistente (`false`), alocado (55000, intacto), resíduo zero. Gate 14/14. |

Ordem: 5165 → `SELECT * FROM pg_temp.rc_5829_validate('<A>', '<B>')`.

## 2. Segurança e integridade

- `SECURITY DEFINER`, `VOLATILE`, `search_path=''`, dono resolvido no servidor, `EXECUTE` só `authenticated`. Nenhuma policy/grant de tabela muda (`physical_card` continua sem DELETE para `authenticated`).
- Linha travada (`FOR UPDATE`) antes de checar alocação; FK `collection_allocation → physical_card` (RESTRICT) é a última barreira. Slot/Pokédex assignments dependem de alocação, então nunca são atingidos.
- Storage não bloqueia (localização corrente, sem histórico).
- Efeito esperado no Security Advisor: +1 em `0029` (mesma classe das RPCs de Meu acervo).
- Registro de lote (`bulk_operation.result_summary`) pode continuar citando o id removido: um REPLAY da mesma confirmação devolveria o resumo antigo, sem recriar a carta.

## 3. Decisão de domínio a registrar (pendente de autorização)

"Correção de cadastro" ≠ `Ownership Exit` (C-72). Exit é um fato real (venda, troca, descarte) e preserva a identidade da Physical Card; a correção apaga um registro que nunca deveria ter existido e, por isso, só vale para exemplar sem vínculos (sem Collection Allocation). Proposta de texto para um novo C-*/LDM-*: *"Um Physical Card registrado por engano pode ser removido pelo próprio dono enquanto não estiver alocado a nenhuma Collection; a remoção não é um evento de Lifecycle/Provenance e não gera Ownership Exit."*

## 4. Frontend (local)

`web/components/colecoes/acervo/copy-remove-button.tsx` (lixeira + confirmação na própria linha), `removeMyCopy` em `web/app/colecoes/acervo/actions.ts`, mensagem `allocated` em `web/lib/colecoes/acervo-add.ts`.

## 5. Execução no LIVE (2026-10-17)

- Pré-check: função ausente; ledger `20261017033443`; 0 alocações.
- 5165 aplicada: ledger `20261017034435`; `prosecdef=true`, `provolatile=v`, `search_path=""`, retorno `boolean`, ACL `{postgres, authenticated}` (anon sem EXECUTE), prosrc md5 `1322db0293d346dd1911240b44881e99`.
- 5829 v1.1: **14/14 PASS** (A = usuário sem cartas, B = Fabrício). A 1ª execução (v1.0) abortou no fixture — `create_collection` exige um Storage Container do próprio Inventory; corrigido no harness (cria e desfaz uma caixa), sem mudança na 5165.
- Resíduo zero (nenhuma coleção/caixa/exemplar de teste); os dois exemplares da Bulbasaur ME1 001/132 seguem intactos para a remoção pelo próprio Fabrício.
- Security Advisor: só `authenticated_security_definer_function_executable` (0029, WARN) para a nova função — intencional, igual às demais RPCs de Meu acervo.
