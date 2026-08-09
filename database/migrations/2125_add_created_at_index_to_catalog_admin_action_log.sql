/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2125 - Add created_at Index to Catalog Admin Action Log
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-09

Descrição...:
Índice simples (uma coluna, não composto) em
public.catalog_admin_action_log.created_at — suporte à paginação
server-side da nova tela "Log de Atualizações"
(admin_list_catalog_action_log(), Query 2127), cujo ORDER BY
created_at DESC + LIMIT/OFFSET rodaria full scan + sort a cada
página sem este índice. Tabela é append-only (sem UPDATE/DELETE),
então o índice nunca precisa de manutenção por linha alterada.

Regras de Negócio:
- Índice simples, não composto — decisão explícita de Fabrício
  (2026-08-09): não antecipar um índice composto
  (ex. (entity_type, created_at) ou (action, created_at)) sem
  evidência real de necessidade; padrão de "menor mudança
  suficiente" já aplicado a outras decisões de índice do projeto.
- Btree padrão (sem DESC explícito): um índice ascendente é
  igualmente eficiente para ORDER BY ... DESC no Postgres (scan
  bidirecional), não há necessidade de declarar a ordem no índice.

Pré-requisitos:
- Query 2010 - Create Catalog Admin Action Log Table.
================================================================
*/

CREATE INDEX ix_catalog_admin_action_log_created_at
    ON public.catalog_admin_action_log (created_at);

-- ================================================================
-- Resultado esperado: "Success. No rows returned".
--
-- Como validar:
-- SELECT indexname FROM pg_indexes
-- WHERE tablename = 'catalog_admin_action_log'
--   AND indexname = 'ix_catalog_admin_action_log_created_at';
-- ================================================================
--
-- CONFIRMADO EXECUTADO (2026-08-09): índice presente em produção,
-- confirmado por Fabrício via pg_indexes.
-- ================================================================
