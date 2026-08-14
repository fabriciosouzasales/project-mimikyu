/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2133 - Add simple indexes on card.rarity_id/card.category_id
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO (via MCP do Supabase, projeto qjfutqujxrbzgrtkpgkg)
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-14

Descrição...:
Finding 4 da auditoria de segurança/performance independente do
Catálogo Editorial (GitHub + Supabase de produção): public.card
não tinha nenhum índice em rarity_id nem category_id — só
card_pkey (id) e dois índices únicos compostos liderados por
card_set_id (uq_card_card_set_collector_number/_order). Qualquer
filtro/agregação por Raridade ou Categoria dependia de Seq Scan
completo na tabela.

Confirmado antes de aplicar (pg_indexes, tabela card): nenhum
índice equivalente ou redundante existente — nenhum dos dois
índices únicos compostos tem rarity_id/category_id como coluna
líder (ambos lideram por card_set_id), então não há sobreposição
nem duplicidade com os dois novos índices simples.

Validação (2026-08-14, confirmada nesta mesma sessão):
- pg_indexes confirma os dois índices presentes, sem conflito com
  os 3 pré-existentes (card_pkey, uq_card_card_set_collector_
  number, uq_card_card_set_collector_order) — 5 índices no total,
  nenhuma sobreposição de definição.
- Nenhuma constraint alterada — CREATE INDEX simples não toca
  chaves primária/únicas/estrangeiras nem colunas da tabela.
- EXPLAIN (ANALYZE, BUFFERS) em 6.867 Cards confirmou uso real
  pelo planner nos três padrões representativos:
  - Filtro seletivo por rarity_id (4 linhas): Index Scan using
    idx_card_rarity_id (Execution Time 0.102 ms).
  - Filtro por category_id (123 linhas): Index Scan using
    idx_card_category_id (Execution Time 0.708 ms).
  - Agregação GROUP BY rarity_id (20 grupos): GroupAggregate sobre
    Index Only Scan using idx_card_rarity_id (Execution Time
    1.687 ms) — o índice também serve group by/ordenação, não só
    filtro pontual.

Pré-requisitos:
- Query 140 - Create Card Table.
================================================================
*/

CREATE INDEX idx_card_rarity_id ON public.card USING btree (rarity_id);
CREATE INDEX idx_card_category_id ON public.card USING btree (category_id);

-- ================================================================
-- Confirmado executado (2026-08-14, via apply_migration/MCP do
-- Supabase) e validado: presença em pg_indexes sem conflito,
-- nenhuma constraint alterada, uso real confirmado via EXPLAIN
-- (ANALYZE, BUFFERS) em filtro seletivo por rarity_id/category_id
-- e em agregação GROUP BY rarity_id.
-- ================================================================
