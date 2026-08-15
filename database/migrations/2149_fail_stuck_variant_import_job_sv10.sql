/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2149 - Fail Stuck Variant Import Job (SV10)
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-15

Descrição...:
Correção pontual de dado — não é alteração de schema/RLS/grants.
Marca como FAILED o único job de Importar Variantes preso para o
Card Set SV10 (Rivais Predestinados), diagnosticado na investigação
do mesmo dia (relatório em chat, sem arquivo próprio — decisão
registrada em docs/log.md).

Causa raiz confirmada: a Edge Function import-card-variants travou
dentro de resolveSetSerieName() (chamada a api.tcgdex.net, sem
timeout até esta correção) e foi encerrada pela plataforma por
estouro do teto de execução (~150s) antes de alcançar o catch()
que chama failVariantJob() — confirmado pelos logs
(function_edge_logs): dois HTTP 409 (JOB_ALREADY_ACTIVE_FOR_CARD_SET,
em 19:11:54 e 19:12:11) seguidos de um HTTP 546 às 19:13:39 na
mesma URL, todos referentes à mesma invocação iniciada às 19:11:10.
O job nunca avançou de progress_step = RESOLVING_SOURCE (o valor
gravado no INSERT) e catalog_variant_import_row não tem nenhuma
linha para este job_id.

Efeito colateral do travamento: o índice único parcial de
catalog_variant_import_job (card_set_id, external_set_id, status
não-terminal — Query 2136) mantém este Card Set bloqueado para
qualquer nova tentativa de Importar Variantes enquanto o job
continuar em status não-terminal (RECEIVED/PROCESSING/STAGED/
CONFIRMING). Marcar como FAILED (status terminal) libera o
fingerprint e permite uma nova tentativa real de SV10 — agora já
com o timeout corrigido na Edge Function (mesmo ciclo de deploy).

Regras de Negócio:
- Atualiza SOMENTE o job bff18ea3-1b1f-4794-ab87-f67eff2ade1a — nenhum
  outro job de catalog_variant_import_job é tocado.
- Mesma forma de UPDATE já usada por failVariantJob() (services/
  database.ts): status = 'FAILED', progress_step = NULL (exigido pela
  constraint ck_catalog_variant_import_job_progress_step_scope:
  progress_step só pode ser não-nulo quando status = 'PROCESSING'),
  error_summary preenchido com o motivo real.
- total_rows/valid_rows/failed_rows permanecem 0 — reflete a
  realidade: nenhuma carta chegou a ser processada.
- Nenhuma policy de RLS, função ou grant é alterado.

Pré-requisitos:
- Query 2136 - Create Catalog Variant Import Job Table.
================================================================
*/

BEGIN;

UPDATE public.catalog_variant_import_job
SET
    status = 'FAILED',
    progress_step = NULL,
    error_summary = 'TCGDEX_SET_METADATA_TIMEOUT: invocação presa em RESOLVING_SOURCE, '
        || 'encerrada pela plataforma por estouro de tempo de execução (HTTP 546 nos '
        || 'logs, ~150s após o início) antes de failVariantJob() rodar. Corrigido '
        || 'retroativamente em 2026-08-15 após adicionar timeout explícito '
        || '(AbortController) a resolveSetSerieName()/listSetCardFiles()/'
        || 'fetchCardFileSource() na Edge Function import-card-variants.'
WHERE id = 'bff18ea3-1b1f-4794-ab87-f67eff2ade1a'
  AND status = 'PROCESSING'
  AND progress_step = 'RESOLVING_SOURCE';

COMMIT;

-- ================================================================
-- Confirmado executado (2026-08-15, via execute_sql/MCP do Supabase,
-- projeto qjfutqujxrbzgrtkpgkg), depois de dry-run em BEGIN...ROLLBACK
-- que confirmou: exatamente 1 linha afetada (id = bff18ea3-...),
-- nenhuma outra linha de catalog_variant_import_job tocada. Execução
-- real repetiu a mesma sequência com COMMIT e foi reverificada com
-- resultado idêntico: status = FAILED, progress_step = NULL,
-- error_summary preenchido, total_rows/valid_rows/failed_rows = 0
-- (inalterados).
-- ================================================================

-- ================================================================
-- Como validar:
-- SELECT id, status, progress_step, error_summary
-- FROM public.catalog_variant_import_job
-- WHERE id = 'bff18ea3-1b1f-4794-ab87-f67eff2ade1a';
-- Esperado: status = 'FAILED', progress_step IS NULL, error_summary
-- não nulo mencionando timeout.
--
-- SELECT count(*) FROM public.catalog_variant_import_job
-- WHERE card_set_id = (SELECT id FROM public.card_set WHERE code = 'SV10')
--   AND status IN ('RECEIVED','PROCESSING','STAGED','CONFIRMING');
-- Esperado: 0 (nenhum job ativo restante para SV10 — fingerprint liberado).
-- ================================================================
