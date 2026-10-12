# P2a — Cadastro individual de Card Variant

| Campo | Valor |
|---|---|
| **Status** | **Query 2267 CONFIRMADO EXECUTADA** no LIVE (2026-10-11, autorizada por Fabrício) → `database/migrations/2267_admin_create_card_variant.sql`; frontend implementado, pendente de homologação funcional e visual |
| **Mandato** | Fabrício, 2026-10-11 — P2 aprovada em duas etapas; P2a = cadastro, P2b = desativar/reativar |
| **Normativo** | `docs/05b-cartas-e-raridade.md`, revisão 1.13 |

| Arquivo | O que é |
|---|---|
| `../../migrations/2267_admin_create_card_variant.sql` | Migration executada: amplia 2 CHECKs do log (CARD_VARIANT_CREATED) e cria a RPC |
| `2267_test_rollback.sql` | Testes S1 S2 I1 I2 I3 F1 P1 P2 (P2 = falha simulada do resolvedor de preço). Sempre termina em RAISE EXCEPTION (nada gravado). Passou = `P2A-2267-TEST PASS` |

## Ensaio (2026-10-11, autorizado por Fabrício, tudo desfeito)

- 1ª rodada: FAIL no P2 por defeito do próprio teste (o F1 já tinha ligado os 2 produtos pendentes da carta, então o P2 não chegou a chamar o resolvedor). Teste corrigido para usar uma segunda carta com preço pendente; nenhuma mudança na 2267.
- 2ª rodada: `P2A-2267-TEST PASS` (S1 S2 I1 I2 I3 F1 P1 P2), 139 ms. F1: pricing `OK`, 2 candidatos, 2 ligados à nova variante. P2: variante criada e mantida, pricing `ERROR` com `SIMULATED_PRICING_FAILURE`, 1 candidato preservado sem vínculo.
- Pós-ensaio, igual à linha de base: função inexistente, `card_variant` 37.879, produtos sem variante 716, log 2.015 linhas, hash do resolvedor e das CHECKs inalterados, carta do teste ativa.

## Aplicação (2026-10-11)

- `apply_migration` 2267 (versão `20261012023852`): sucesso, idêntica à versão do ensaio.
- Validação do cabeçalho: `auth_ok = true`, `anon = false`, 2 CHECKs com a ação nova. RPC `SECURITY DEFINER`, `search_path=''`, `lock_timeout=5s`.
- Sem efeito colateral: `card_variant` 37.879, `pricing_product` 156.706, 716 sem variante, log 2.015 linhas e 0 `CARD_VARIANT_CREATED` — tudo igual ao pré-aplicação; hash do resolvedor de preço inalterado.

## Ordem de execução

1. Ensaio: `2267` + `2267_test_rollback.sql` num único envio (tudo desfeito). Esperado: `P2A-2267-TEST PASS`.
2. Aplicação: só `2267`; depois a query "Como validar" do cabeçalho.
3. Publicar o frontend (antes da 2267 o diálogo abre e lista, mas cadastrar devolve erro genérico).

## Pricing

A ligação de preços roda depois do cadastro, só para os `pricing_product` da carta sem variante, num bloco com tratamento de erro próprio: falha ali vira `pricing.status = ERROR` no retorno e no log, e a variante continua cadastrada. O P1 do teste prova que nenhum produto de outra carta é tocado.
