-- Project Mimikyu
-- Query 257 - Create Import Run ME3
-- Status: CONFIRMADA EXECUTADA (SQL Editor do Supabase Dashboard,
-- reconfirmada pela execução bem-sucedida da Edge Function
-- `import-card-assets` — 124/124 referências e imagens, 0 falhas)
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.22", para o contexto
-- completo.
--
-- Réplica das Queries 252 (ME1)/255 (ME2)/256 (ME2.5) para a ME3 — já usando
-- o `run_type` correto (`FULL_CARD_SET`) desde a primeira tentativa.

INSERT INTO public.asset_import_run (
    run_code,
    run_type,
    asset_source_id,
    card_set_id,
    status
)
SELECT
    'RUN-20260720-00000024',
    'FULL_CARD_SET',
    s.id,
    cs.id,
    'PENDING'
FROM public.asset_source s
JOIN public.card_set cs
    ON cs.code = 'ME3'
WHERE s.code = 'TCGDEX';
