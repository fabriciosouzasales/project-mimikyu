# P2b — Desativar e reativar Card Variant

| Campo | Valor |
|---|---|
| **Status** | Queries 2268–2270 **CONFIRMADO EXECUTADAS** no LIVE (2026-10-12) → `database/migrations/`; frontend implementado, pendente de homologação funcional e visual |
| **Mandato** | Fabrício, 2026-10-11: P2b aprovada (2268–2270 + evolução do diálogo "Gerenciar variações") |
| **Normativo** | `docs/05b-cartas-e-raridade.md`, revisão 1.14 |

## Arquivos

| Arquivo | O que é |
|---|---|
| `../../migrations/2268_card_variant_is_active.sql` | Coluna `is_active`, CHECK padrão-ativa e trava de vínculo novo (4 tabelas) |
| `../../migrations/2269_card_variant_active_consumers.sql` | Resolvedor de preço (`TARGET_INACTIVE`), trigger de vínculo da sincronização (repete em `MV001`), escolha automática da padrão, 2264, 2267 e view 2266 |
| `../../migrations/2270_admin_set_card_variant_active.sql` | CHECKs do log + RPC `admin_set_card_variant_active` |
| `2270_test_rollback.sql` | S1 S2 B1 C1 F1 G1 P1 D1 I1 B2 F2. Termina sempre em `RAISE EXCEPTION`. Passou = `P2B-TEST PASS` |

## Sequência mínima no LIVE

1. **Ensaio (desfeito):** 2268 + 2269 + 2270 + `2270_test_rollback.sql` num único envio. Esperado: `P2B-TEST PASS`; depois conferir que `card_variant.is_active` não existe.
2. **Aplicação:** 2268, 2269 e 2270, nessa ordem, cada uma seguida do "Como validar" do cabeçalho.
3. **Postcheck:** variantes 37.879+ todas ativas; `pricing_product` e "sem variante" iguais ao pré; pendências de padrão iguais; hashes das funções não alteradas iguais.
4. Frontend independente da ordem: lê `card_variant(*)`, então funciona antes e depois da 2268.

## Riscos tratados

- **Preço redirecionado:** o resolvedor recusa o alvo inativo em vez de excluí-lo das candidatas.
- **Desativação × sincronização:** trava com `FOR SHARE` + repetição única no trigger de vínculo; o lote não cai. A reconciliação global (admin) apenas falha e pode ser reexecutada.
- **Desativação × troca de padrão:** mesma trava da carta + CHECK.
- **Fora do teste de sessão única:** a repetição em `MV001` só ocorre sob concorrência real (coberta por inspeção).

## Ensaio (2026-10-12, autorizado por Fabrício, desfeito)

- 2268 + 2269 + 2270 + `2270_test_rollback.sql` num único envio: `P2B-TEST PASS` (S1 S2 B1 C1 F1 G1 P1 D1 I1 B2 F2); fixture com 5 produtos de preço ligados à variante; desativação em 61,7 ms.
- Pós-ensaio idêntico ao pré: 37.881 variantes, 715 produtos sem variante, 2.017 linhas de log; coluna, funções novas, 4 triggers e CHECKs ausentes; hashes das 5 funções e da view 2266 inalterados.

## Aplicação (2026-10-12)

- `apply_migration` 2268 (`20261012031352`), 2269 (`20261012031506`) e 2270 (`20261012031548`), nessa ordem, sem erro.
- Validações dos cabeçalhos: 2268 → 0 inativas / CHECK 1 / 4 triggers; 2269 → pendentes 0, resolvedor/vínculo/escolha da padrão atualizados; 2270 → `authenticated` executa, `anon` não, 2 CHECKs com as ações novas.
- Pós: 37.881 variantes, todas ativas; 156.706 produtos de preço, 715 sem variante; log 2.017; Collections 0 vínculos; `authenticated` sem UPDATE direto em `card_variant` nem EXECUTE na trava; RPC `SECURITY DEFINER`, `search_path=''`, `lock_timeout=5s`; hash das demais funções de `public`/`internal` idêntico ao pré.
