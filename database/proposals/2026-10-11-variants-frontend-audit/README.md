# CARD-VARIANTS-FRONTEND-AUDIT-01 — o frontend cobre o backend atual de variantes?

| Campo | Valor |
|---|---|
| **Status** | AUDITORIA (somente leitura), 2026-10-11 — nada alterado |
| **Mandato** | Fabrício, 2026-10-11: "auditoria em todo módulo para garantir que o frontend tenha todas as funções necessárias para gerenciar as variantes" |
| **Método** | LIVE: funções `public` do domínio (variant / printing / edition context / trait), privilégios e políticas das 16 tabelas. Repositório: chamadas `.rpc(...)` e leituras em `web/app`, `web/components`, `web/lib` |

## 1. Como o backend está hoje

- Identidade da variante = 3 eixos: **Acabamento** (`card_variant_type`, 97), **Impressão** (`card_printing_profile`, 25, com traits) e **Contexto de edição** (`card_edition_context_profile`, 179, com traits), mais `is_default`.
- As 16 tabelas do domínio são **somente leitura** para `authenticated` (RLS `catalog_admin_select`, sem INSERT/UPDATE/DELETE). Toda escrita passa por RPC administrativa ou migration.
- Variantes de carta só nascem pela importação (`admin_confirm_catalog_variant_import` → `internal.write_card_variant`). Padrão por trigger (`2259`).

## 2. Matriz backend × frontend

| Capacidade | Backend | Frontend |
|---|---|---|
| Tipos de acabamento: criar, editar, desativar, reativar | `admin_create/update/deactivate/reactivate_card_variant_type` | **Sim** — Catálogo › Tipos de Variação |
| Importar variantes (iniciar, revisar, decidir, confirmar) | Edge `import-card-variants`, `admin_decide_…`, `admin_confirm_…` | **Sim** — Importar Variantes |
| Resolver acabamento desconhecido na importação | `admin_resolve_catalog_variant_import_mapping`, `…create_card_variant_type_with_import_mapping` | **Sim** |
| Resolver acabamento só para o Set | `admin_resolve_catalog_variant_import_mapping_for_set` | **Não** |
| Prever o impacto de um mapeamento antes de aplicar | `admin_preview_catalog_variant_import_mapping` | **Não** |
| Resolver **impressão** desconhecida na importação | `admin_resolve_catalog_variant_import_printing_mapping` | **Não** |
| Criar perfil de impressão (com backfill) | `admin_create_card_printing_profile_with_backfill` | **Não** |
| Resolver **contexto de edição** desconhecido na importação | — (só migration) | **Não** |
| Ver variantes da carta com os 3 eixos | leitura direta | **Sim** — galeria de Cartas, resumo, relatório Variantes por carta |
| Ver qual é a variante **padrão** | `is_default` | **Sim** (P1) — Cartas (popover, Editar), relatório Variantes por carta e Pricing |
| Definir/trocar a variante padrão de uma carta | `admin_set_card_variant_default` (Query `2264`, aguardando execução) | **Sim** (P1, 2026-10-11) — popover e Editar da carta |
| Adicionar, editar ou desativar uma variante de uma carta | — | **Não** (só reimportando o Set) |
| Gerir perfis de contexto de edição e traits | — | **Não** (só seed/migration) |
| Ver/editar mapeamentos externos (acabamento, impressão, contexto) | — | **Não** |
| Reconciliar produtos de preço × variante | `admin_reconcile_pricing_product_variants` | **Não** (rodado por SQL) |
| Resumo de preço por variante | `get_card_variants_pricing_summary` | Não usado — consumidor previsto é Collections (não é lacuna) |

## 3. Lacunas, por prioridade

**P1 — afetam a operação do catálogo hoje**

1. **Definir a variante padrão** (RPC nova + ação na carta). Fecha as 13 cartas com empate e permite corrigir padrões errados sem SQL. BULK-04 depende disso.
2. **Gerir as variantes de uma carta** (adicionar, desativar). Hoje uma variante que falta só entra reimportando o Set; os grupos B, F e H da fila de Pricing (≈ 180 produtos) são exatamente variantes que faltam.
3. **Resolver impressão e contexto de edição na revisão da importação.** A RPC de impressão existe sem tela; para contexto de edição não há RPC. Um Set novo com rótulo desconhecido trava em NEEDS_REVIEW e só sai por migration.

**P2 — produtividade/segurança operacional**

4. Ligar na tela de importação a prévia de impacto (`…preview…`) e a resolução por Set (`…for_set`), que já existem.
5. Criar perfil de impressão pela tela (RPC existe).
6. Botão "Reconciliar preços × variantes" no Pricing (RPC existe; dry-run por padrão).
7. Mostrar a variante padrão na galeria/detalhe de Cartas.

**P3 — vocabulário (raro)**

8. Telas de perfis de contexto de edição, traits e mapeamentos externos. Mudam pouco; migration é aceitável por ora.

## 4. Sem problemas encontrados

- Nenhuma tela escreve direto em tabela (todas as escritas passam por RPC com `is_admin`).
- As leituras de Cartas já trazem os 3 eixos (`queries.ts`, CV-02) e têm testes (`carta-variant-display-state.test.ts`, `carta-variant-summary.test.ts`).
- Nenhuma chamada do frontend aponta para RPC removida ou renomeada.
