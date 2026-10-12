# P1 — Gestão Administrativa da Variante Padrão

| Campo | Valor |
|---|---|
| **Status** | Frontend implementado; SQL **proposto, aguardando autorização de Fabrício** para o LIVE |
| **Mandato** | Fabrício, 2026-10-11: proposta P1 aprovada, com os cuidados de concorrência (trigger 2259) e de origem manual identificável sem campo novo |
| **Normativo** | `docs/05b-cartas-e-raridade.md`, revisão 1.12 |

## Arquivos

| Arquivo | O que é |
|---|---|
| `2264_admin_set_card_variant_default.sql` | Migration: amplia as 2 CHECKs de ação do log e cria a RPC. Vai para `database/migrations/` só depois de executada |
| `2264_test_rollback.sql` | Testes S1 S2 I1 I2 F1 F2 F3 A1 P1. Termina sempre em `RAISE EXCEPTION`, então nada é gravado. Passou = mensagem `P1-2264-TEST PASS` |

## Ordem de execução

1. Ensaio: enviar `2264` + `2264_test_rollback.sql` juntos, num único envio. Tudo é desfeito, inclusive a 2264. Esperado: `P1-2264-TEST PASS`.
2. Aplicação: enviar só `2264`. Depois rodar a query "Como validar" do cabeçalho.
3. Opcional: rodar `2264_test_rollback.sql` de novo, sozinho, sobre o LIVE já migrado.
4. Publicar o frontend. Antes da 2264, a tela já mostra o padrão, mas salvar retorna erro genérico.

## Concorrência (cuidado 1 de Fabrício)

Sem risco concreto, então o trigger 2259 não foi alterado.

- A confirmação de importação trava as cartas do lote em `FOR UPDATE`, em ordem, e só faz INSERT.
- O trigger 2259 trava em `FOR NO KEY UPDATE` e reconfere "sem padrão" na própria UPDATE.
- A RPC usa o mesmo modo de trava. Ela trava uma única carta antes de tocar nas variantes dela. Por isso não há ordem cruzada de travas nem deadlock, e as três escritas de `is_default` ficam serializadas por carta.
- A espera é limitada a 5 s, com mensagem legível.

## Origem manual (cuidado 2)

Sem campo novo.

- **Log:** `catalog_admin_action_log.action = 'CARD_VARIANT_DEFAULT_SET'`, `metadata.source = 'MANUAL'`, com o padrão anterior e o novo.
- **Preservação:** nada escreve `is_default` depois do insert, exceto esta RPC. Inventário LIVE das funções: só o trigger 2259 e a RPC escrevem o campo. O teste P1 prova isso inserindo uma variante depois da escolha manual.
