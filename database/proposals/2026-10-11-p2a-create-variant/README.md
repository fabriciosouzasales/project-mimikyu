# P2a — Cadastro individual de Card Variant

| Campo | Valor |
|---|---|
| **Status** | Frontend implementado; Query 2267 **proposta, aguardando autorização** para o LIVE |
| **Mandato** | Fabrício, 2026-10-11 — P2 aprovada em duas etapas; P2a = cadastro, P2b = desativar/reativar |
| **Normativo** | `docs/05b-cartas-e-raridade.md`, revisão 1.13 |

| Arquivo | O que é |
|---|---|
| `2267_admin_create_card_variant.sql` | Migration: amplia 2 CHECKs do log (CARD_VARIANT_CREATED) e cria a RPC. Vai para `database/migrations/` só depois de executada |
| `2267_test_rollback.sql` | Testes S1 S2 I1 I2 I3 F1 P1. Sempre termina em RAISE EXCEPTION (nada gravado). Passou = `P2A-2267-TEST PASS` |

## Ordem de execução

1. Ensaio: `2267` + `2267_test_rollback.sql` num único envio (tudo desfeito). Esperado: `P2A-2267-TEST PASS`.
2. Aplicação: só `2267`; depois a query "Como validar" do cabeçalho.
3. Publicar o frontend (antes da 2267 o diálogo abre e lista, mas cadastrar devolve erro genérico).

## Pricing

A ligação de preços roda depois do cadastro, só para os `pricing_product` da carta sem variante, num bloco com tratamento de erro próprio: falha ali vira `pricing.status = ERROR` no retorno e no log, e a variante continua cadastrada. O P1 do teste prova que nenhum produto de outra carta é tocado.
