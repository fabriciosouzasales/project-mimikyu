# Meu acervo — leituras do colecionador (MY-INVENTORY-IMPLEMENTATION-01, Etapa A)

| Campo | Valor |
|---|---|
| Data | 2026-10-16 |
| Autoridade de experiência | `docs/domain-modeling/collections/north-star-2026-10-16.md` v1.4 (NS-13, N25, B4, B7) |
| Status | **5159–5163 APLICADAS NO LIVE e validadas (2026-10-17, `MY-INVENTORY-LIVE-DEPLOYMENT-01`, autorização de Fabrício).** Ledger `20261017024147`, `…024202`, `…024237`, `…024300`, `…024331`. `5827` v1.1 executado no LIVE: **GATE PASS, 52/52 PASS, 0 FAIL**, resíduo zero. **Promovida para `database/schema/` em 2026-10-17** (corpo idêntico ao LIVE, conferido por md5 de `prosrc`). **CLOSED.** |
| Contratos C-*/LDM-* | **Inalterados.** Grupo visual (Card Variant + idioma) é apresentação, não entidade; cada exemplar continua um Physical Card. |

## 1. Artefatos

| Query | Objeto | Papel |
|---|---|---|
| 5159 | `get_my_inventory_items(...)` | Galeria paginada (≤ 96), grupos Card Variant + idioma, filtros (busca, Set, idioma, coleção, sem coleção), ordem `RECENT` \| `SET_NUMBER`, imagem CARD_FRONT |
| 5160 | `get_my_inventory_summary()` | Exemplares, diferentes, Sets, repetidas (= exemplares além do primeiro de cada grupo) |
| 5161 | `get_my_inventory_filter_options()` | Sets, idiomas e coleções presentes no acervo do próprio usuário |
| 5162 | `get_my_inventory_item_copies(variant, idioma)` | Detalhe: cabeçalho + um registro por exemplar (coleção e local **gravados**; nunca inferidos — NS-13/N25) |
| 5163 | `get_catalog_card_variants_for_picker(card)` | Seletor (Etapa C): variantes ativas de uma carta. O passo "achar a carta" reutiliza `search_cards` (4032, LIVE) sem alteração |
| 5827 | Harness | Estrutura/privilégios, anon, sem identidade, contrato, isolamento A×B, usuário sem Inventory, Seção P (B4, opcional), resíduo zero |

Ordem de aplicação: 5159 → 5160 → 5161 → 5162 → 5163 → 5827 (CALL 1 com `p_perf = false`; depois `true` para B4) → POSTCHECK.

## 2. Segurança (B7)

- Todas: `SECURITY DEFINER`, `STABLE`, `SET search_path = ''`, objetos qualificados, `auth.uid()` obrigatório (28000), dono resolvido no servidor, `EXECUTE` só `authenticated` (revogado de PUBLIC e anon).
- Nenhuma RLS alterada; catálogo continua admin-only (ADR-022). As funções expõem apenas campos de exibição das cartas que o próprio usuário possui (5159–5162) ou das variantes ativas de uma carta (5163). Nenhum código interno, traço administrativo, legado ou id de eixo.
- Não enumeração: coleção, grupo ou carta alheia/inexistente → resultado vazio idêntico ao de um recurso próprio vazio.
- `card_variant_id` e `physical_card_id` são devolvidos porque as operações da Etapa C (5150, 5024, 5046/5047) os exigem; são ids do próprio usuário ou de catálogo, sem dado sensível.

## 3. Performance (B4)

- Entrada por `ix_physical_card_inventory_variant`; catálogo por PK; imagem via LATERAL só para as linhas da página.
- 5159 em duas fases: chaves da página → apresentação. Caminho rápido na visão padrão (RECENT, sem busca/Set) pagina sobre o agrupamento sem tocar o catálogo.
- Nenhum índice novo proposto: os existentes cobrem os caminhos (verificado por EXPLAIN no LIVE, somente leitura).
- **Medição B4 pendente:** Seção P do 5827 (VR 20.000 exemplares, 30 execuções, p95 ≤ 150 ms). Uma simulação somente leitura no LIVE (CTE sintética, sem escrita) mostrou o agrupamento + top-N de 20.000 exemplares em ~20 ms, mas o banco compartilhado teve latência de I/O muito variável (leituras frias de 1–2 ms por linha); **não vale como evidência B4**.

## 4. O que fica para depois

- Etapa C (adicionar cartas, Set inteiro, coleção, local) não foi integrada: depende destas leituras no LIVE e de validação própria. Nenhuma ação aparece na interface como funcional.

## 5. Execução no LIVE (2026-10-17)

- Hashes dos arquivos conferidos antes da aplicação; aplicados os corpos entre `begin;`/`commit;` (o canal `apply_migration` já é transacional). `prosrc` de cada função no LIVE confere (md5) com o corpo do arquivo.
- Pós-check: as 5 funções com proprietário `postgres`, `SECURITY DEFINER`, `STABLE`, `search_path=""`, ACL exatamente `postgres:EXECUTE, authenticated:EXECUTE` (sem PUBLIC, anon ou service_role).
- `5827` v1.1 (correção antes da 1ª execução: 4.11/4.12/6.2 leem o catálogo na fixture, como administrador): **52/52 PASS**, `p_perf = false`. Usuários A/B = dois usuários reais sem exemplares; toda a fixture revertida no próprio statement (savepoint + sentinela). Postcheck independente: `physical_card`, `collection`, `collection_allocation`, `storage_container` = 0; fixtures "Coleção 5827"/"Fichário 5827" = 0. A soma de linhas de todas as tabelas `public` variou +590 entre as fotografias; as únicas tabelas com inserções recentes são de Pricing/importação (`pricing_observation`, `pricing_sync_run`, `pricing_product`, `asset_import_run` — rotinas agendadas de produção, alheias ao teste). Atribuição por tabela não foi feita (a fotografia de base guardou só o total e o hash).
- Security Advisor: única diferença é `0029 authenticated_security_definer_function_executable` 146 → 151 — exatamente as 5 funções novas, por desenho (leituras do colecionador, mesmo padrão das demais RPCs). Nenhuma outra categoria mudou; `0028` (anon) continua 1.
- Performance (somente leitura, acervo vazio): p95 ≤ 6,6 ms em todas as leituras. A Seção P (VR 20.000 exemplares) **não foi executada no LIVE** — exige escrita em massa revertida e ANALYZE; fica para o ambiente isolado (R3). B4 permanece não comprovado.
