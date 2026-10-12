/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 3987 - Custo a frio da Visão Geral de Valor de Mercado (get_pricing_admin_overview)
Versão......: 1.1
Status......: CONFIRMADO EXECUTADO (2026-10-12, 14:21–14:24 UTC) — autorizado por Fabrício.
Autor.......: Fabrício Sales / Claude
Data........: 2026-10-12

Registro de execução (LIVE)
  - Pré-check 14:21 UTC: 0 runs RECEIVED/PROCESSING, 0 leases; índice inexistente.
    Baseline: vis_pct observation 92% / product 93%; reloptions NULL.
  - Baseline da RPC (como admin): 5.712 ms (primeira chamada) / 207 ms (quente).
  - PASSO 1 aplicado; reloptions conferidas.
  - PASSO 2 (14:22, isolado, CONCURRENTLY): indisvalid/indisready = true, 40 kB;
    EXPLAIN = Index Only Scan using ix_pricing_product_active_without_variant.
  - PASSO 3 (pré-check reconfirmado 14:23:30, 0/0): VACUUM pricing_product às 14:23:48.
  - PASSO 4 (pré-check reconfirmado 14:24:06, 0/0): VACUUM pricing_observation às 14:24:16.
  - PASSO 5: vis_pct 100% nas duas; n_dead_tup 0 / 8; heap fetches 0 (product) e 201
    (observation). Buffers: observações 12.048 → 799; produtos 18.654 → 887; produtos sem
    variante 4.018 → 5.
  - RPC após a aplicação (como admin): 1.282 ms (primeira chamada) / 142 ms (quente).
    JSON idêntico ao baseline nos 17 indicadores comparáveis (excluídos só os blocos que
    variam com o relógio: api_budget, last_sync_run, refresh_policy, dispatcher).
  - Medição a cache totalmente frio não foi forçada (sem acesso a evicção de cache); fica
    coberta pelo log de servidor "[pricing] ... falhou" em web/lib/pricing/queries.ts.

Objetivo
  Fazer get_pricing_admin_overview() caber com folga no statement_timeout de 8 s do papel
  authenticated também com cache frio, sem alterar nenhum indicador, regra ou dado.

Diagnóstico (somente leitura, 2026-10-12)
  - Falha da Visão Geral = RPC cancelada por statement_timeout (8 s).
  - Soma das partes da função a frio ≈ 7 s: observações 2,1 s; produtos ativos sem variante
    2,5 s (seq scan de 4.018 páginas para 715 linhas); produtos 1,3 s (18 mil heap fetches);
    cartas ativas por Set 0,6 s; mappings 0,2 s.
  - pricing_observation: praticamente só INSERT (~10 mil/dia, picos de 86 mil). Com o padrão
    (insert_scale_factor 0,2) o autovacuum só dispara após ~144 mil inserções.
  - pricing_product: praticamente só UPDATE (1,17 milhão sobre 157 mil linhas, quase nenhum
    HOT). Com o padrão (scale_factor 0,2) o autovacuum só dispara após ~31 mil linhas mortas,
    e o visibility map se degrada entre uma passada e outra.

Alterações (v1.0 → v1.1)
  - Índice criado com CONCURRENTLY, em chamada isolada (não bloqueia escrita do refresh).
  - pricing_product passa a usar autovacuum_vacuum_scale_factor (dead tuples), não o
    parâmetro de inserção.
  - VACUUM separado por tabela, fora das janelas dos dispatchers.

Regras de execução
  - Cada PASSO numa chamada própria. Os PASSOS 2, 3 e 4 NÃO podem rodar dentro de transação
    (sem BEGIN, e não via apply_migration).
  - Não executar o PASSO 2 ao mesmo tempo que os PASSOS 3/4 (CREATE INDEX CONCURRENTLY e
    VACUUM conflitam entre si na mesma tabela).
  - Janelas a evitar: dispatchers pg_cron rodam nos minutos :00/:05/... (price refresh) e
    :02/:07/... (set bootstrap). Iniciar os PASSOS 3 e 4 entre :03 e :04 (ou :08–:09 etc.)
    e somente com o PRÉ-CHECK abaixo vazio.

Resultado esperado
  Índice válido; reloptions aplicadas; após os VACUUMs, páginas visíveis ≈ 100%; contagem de
  produtos sem variante usando o índice; JSON da Visão Geral idêntico ao de antes.
  Estimativa (não medida): função entre 1,5 e 2,5 s a frio.

Fora do escopo (registrado, não tratado aqui)
  - Contagem de cartas ativas por Set, feita duas vezes na função (~0,6 s a frio).
===============================================================================
*/


-- ============================================================================
-- PRÉ-CHECK (somente leitura) — rodar antes dos PASSOS 2, 3 e 4
-- Deve retornar zero nas duas colunas: nenhuma sincronização em andamento e nenhum
-- Set com lease ativo do dispatcher.
-- ============================================================================
SELECT
  (SELECT count(*) FROM public.pricing_sync_run
    WHERE status IN ('RECEIVED', 'PROCESSING')
      AND started_at > now() - interval '2 hours')          AS runs_em_andamento,
  (SELECT count(*) FROM public.pricing_set_refresh_state
    WHERE lease_until > now())                               AS leases_ativos;

-- Baseline para comparação no PASSO 5 (guardar o resultado)
SELECT relname, reloptions, relpages, relallvisible,
       round(relallvisible::numeric / nullif(relpages, 0) * 100) AS vis_pct
  FROM pg_class
 WHERE relname IN ('pricing_observation', 'pricing_product');


-- ============================================================================
-- PASSO 1 — Parâmetros de autovacuum (pode rodar em transação; lock breve)
-- ============================================================================
ALTER TABLE public.pricing_observation SET (autovacuum_vacuum_insert_scale_factor = 0.02);
ALTER TABLE public.pricing_product     SET (autovacuum_vacuum_scale_factor = 0.02);

-- Verificação 1
SELECT relname, reloptions
  FROM pg_class
 WHERE relname IN ('pricing_observation', 'pricing_product');
-- Esperado: pricing_observation {autovacuum_vacuum_insert_scale_factor=0.02}
--           pricing_product     {autovacuum_vacuum_scale_factor=0.02}


-- ============================================================================
-- PASSO 2 — Índice parcial (chamada isolada, FORA de transação)
-- ============================================================================
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_pricing_product_active_without_variant
  ON public.pricing_product (id)
  WHERE is_active AND card_variant_id IS NULL;

-- Verificação 2a — índice válido e pronto
SELECT c.relname, i.indisvalid, i.indisready, pg_get_indexdef(i.indexrelid)
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
 WHERE c.relname = 'ix_pricing_product_active_without_variant';
-- Esperado: indisvalid = true, indisready = true.
-- Se indisvalid = false (falha no meio do build): DROP INDEX CONCURRENTLY
-- public.ix_pricing_product_active_without_variant; e repetir o PASSO 2.

-- Verificação 2b — o planner usa o índice
EXPLAIN (COSTS OFF)
SELECT count(*) FROM public.pricing_product WHERE is_active AND card_variant_id IS NULL;
-- Esperado: Index Only Scan (ou Index Scan) using ix_pricing_product_active_without_variant.


-- ============================================================================
-- PASSO 3 — VACUUM de pricing_product (chamada isolada, FORA de transação,
-- após PRÉ-CHECK vazio, iniciar entre :03 e :04 de uma janela de 5 min)
-- ============================================================================
VACUUM (ANALYZE) public.pricing_product;


-- ============================================================================
-- PASSO 4 — VACUUM de pricing_observation (chamada isolada, FORA de transação,
-- mesmas condições do PASSO 3)
-- ============================================================================
VACUUM (ANALYZE) public.pricing_observation;


-- ============================================================================
-- PASSO 5 — Verificações finais (somente leitura)
-- ============================================================================

-- 5a — visibility map recomposto
SELECT relname, relpages, relallvisible,
       round(relallvisible::numeric / nullif(relpages, 0) * 100) AS vis_pct
  FROM pg_class
 WHERE relname IN ('pricing_observation', 'pricing_product');
-- Esperado: vis_pct próximo de 100 nas duas tabelas.

-- 5b — vacuum registrado
SELECT relname, last_vacuum, last_analyze, n_dead_tup, n_ins_since_vacuum
  FROM pg_stat_user_tables
 WHERE relname IN ('pricing_observation', 'pricing_product');
-- Esperado: last_vacuum/last_analyze com o horário da execução; n_dead_tup ≈ 0.

-- 5c — contagens sem heap fetches relevantes
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM public.pricing_observation;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT count(*) FROM public.pricing_product;
-- Esperado: Index Only Scan com "Heap Fetches" próximo de 0.

-- 5d — paridade funcional (executar autenticado como admin, pela aplicação ou SQL Editor
-- com sessão de admin): o JSON de get_pricing_admin_overview() deve ter os mesmos valores
-- de antes, exceto contagens que mudam naturalmente com o refresh em andamento.
-- SELECT public.get_pricing_admin_overview();

-- 5e — tempo real: abrir /pricing após reinício do servidor de desenvolvimento e conferir
-- que o log do servidor não registra "[pricing] get_pricing_admin_overview falhou".


-- ============================================================================
-- REVERSÃO (somente se necessário; cada linha em chamada própria)
-- ============================================================================
-- DROP INDEX CONCURRENTLY IF EXISTS public.ix_pricing_product_active_without_variant;  -- fora de transação
-- ALTER TABLE public.pricing_observation RESET (autovacuum_vacuum_insert_scale_factor);
-- ALTER TABLE public.pricing_product     RESET (autovacuum_vacuum_scale_factor);
-- Os VACUUMs não têm reversão (não alteram dados; só manutenção física).
--
-- Verificação da reversão:
-- SELECT relname, reloptions FROM pg_class WHERE relname IN ('pricing_observation','pricing_product');
--   -- esperado: reloptions = NULL
-- SELECT 1 FROM pg_class WHERE relname = 'ix_pricing_product_active_without_variant';
--   -- esperado: zero linhas
