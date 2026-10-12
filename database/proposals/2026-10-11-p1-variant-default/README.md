# P1 — Gestão Administrativa da Variante Padrão

| Campo | Valor |
|---|---|
| **Status** | **Query 2264 CONFIRMADO EXECUTADA** no LIVE (2026-10-11, autorizada por Fabrício) → `database/migrations/2264_admin_set_card_variant_default.sql`; frontend implementado, pendente de validação visual |
| **Mandato** | Fabrício, 2026-10-11: proposta P1 aprovada, com os cuidados de concorrência (trigger 2259) e de origem manual identificável sem campo novo |
| **Normativo** | `docs/05b-cartas-e-raridade.md`, revisão 1.12 |

## Arquivos

| Arquivo | O que é |
|---|---|
| `../../migrations/2264_admin_set_card_variant_default.sql` | Migration executada: amplia as 2 CHECKs de ação do log e cria a RPC |
| `2264_test_rollback.sql` | Testes S1 S2 I1 I2 F1 F2 F3 A1 P1. Termina sempre em `RAISE EXCEPTION`, então nada é gravado. Passou = mensagem `P1-2264-TEST PASS` |
| `2265_fix_cracked_ice_holo_display_name.sql` | **Proposta.** Acento em "Holográfica Cracked Ice" pela RPC `admin_update_card_variant_type` (id e code inalterados, log CARD_VARIANT_TYPE_UPDATED) |
| `2266_create_catalog_card_variant_default_pending.sql` | **Proposta.** View das pendências de padrão (security_invoker), usada pelo relatório "Só cartas sem padrão" |

## Execução (2026-10-11)

- Ensaio (2264 + testes, desfeito): `P1-2264-TEST PASS`; conferido depois: função ausente, 0 logs, 13 cartas sem padrão.
- `apply_migration` 2264: sucesso. Validação: `auth_ok = true`, `anon = false`, 2 CHECKs com a ação nova; log intacto.
- Reteste sobre o LIVE migrado (desfeito): PASS; 1ª chamada 78 ms, seguinte 10 ms.
- Security Advisor: só o aviso genérico "SECURITY DEFINER executável por authenticated", o mesmo de todas as RPCs admin (autorização via `is_admin()` dentro da função).

## Ordem de execução (planejada)

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
