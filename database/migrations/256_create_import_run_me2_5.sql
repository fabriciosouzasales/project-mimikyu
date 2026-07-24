-- Project Mimikyu
-- Query 256 - Create Import Run ME2.5
-- Status: CONFIRMADA EXECUTADA (SQL Editor do Supabase Dashboard,
-- reconfirmada por consulta real pós-execução e pela execução bem-sucedida
-- da Edge Function `import-card-assets` — 295/295 referências e imagens, a
-- maior coleção do catálogo até o momento)
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.21", para o contexto
-- completo.
--
-- Réplica das Queries 252 (ME1) e 255 (ME2) para a ME2.5 — já usando o
-- `run_type` correto (`FULL_CARD_SET`) desde a primeira tentativa, sem
-- repetir o erro real das duas migrations anteriores.

INSERT INTO public.asset_import_run (
    run_code,
    run_type,
    asset_source_id,
    card_set_id,
    status
)
SELECT
    'RUN-20260720-00000023',
    'FULL_CARD_SET',
    s.id,
    cs.id,
    'PENDING'
FROM public.asset_source s
JOIN public.card_set cs
    ON cs.code = 'ME2.5'
WHERE s.code = 'TCGDEX';
