# P2b — Desativar e reativar Card Variant

| Campo | Valor |
|---|---|
| **Status** | Queries 2268–2270 **propostas**; frontend implementado. Ensaio e aplicação no LIVE aguardam autorização de Fabrício |
| **Mandato** | Fabrício, 2026-10-11: P2b aprovada (2268–2270 + evolução do diálogo "Gerenciar variações") |
| **Normativo** | `docs/05b-cartas-e-raridade.md`, revisão 1.14 |

## Arquivos

| Arquivo | O que é |
|---|---|
| `2268_card_variant_is_active.sql` | Coluna `is_active`, CHECK padrão-ativa e trava de vínculo novo (4 tabelas) |
| `2269_card_variant_active_consumers.sql` | Resolvedor de preço (`TARGET_INACTIVE`), trigger de vínculo da sincronização (repete em `MV001`), escolha automática da padrão, 2264, 2267 e view 2266 |
| `2270_admin_set_card_variant_active.sql` | CHECKs do log + RPC `admin_set_card_variant_active` |
| `2270_test_rollback.sql` | S1 S2 B1 C1 F1 G1 P1 D1 I1 B2 F2. Termina sempre em `RAISE EXCEPTION`. Passou = `P2B-TEST PASS` |

## Sequência mínima no LIVE

1. **Ensaio (desfeito):** 2268 + 2269 + 2270 + `2270_test_rollback.sql` num único envio. Esperado: `P2B-TEST PASS`; depois conferir que `card_variant.is_active` não existe.
2. **Aplicação:** 2268, 2269 e 2270, nessa ordem, cada uma seguida do "Como validar" do cabeçalho.
3. **Postcheck:** variantes 37.879+ todas ativas; `pricing_product` e "sem variante" iguais ao pré; pendências de padrão iguais; hashes das funções não alteradas iguais.
4. **Publicar o frontend** só depois da 2268 (a leitura passa a pedir `is_active`).

## Riscos tratados

- **Preço redirecionado:** o resolvedor recusa o alvo inativo em vez de excluí-lo das candidatas.
- **Desativação × sincronização:** trava com `FOR SHARE` + repetição única no trigger de vínculo; o lote não cai. A reconciliação global (admin) apenas falha e pode ser reexecutada.
- **Desativação × troca de padrão:** mesma trava da carta + CHECK.
- **Fora do teste de sessão única:** a repetição em `MV001` só ocorre sob concorrência real (coberta por inspeção).
