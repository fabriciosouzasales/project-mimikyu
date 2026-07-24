-- Project Mimikyu
-- Query 258 - Create Import Run ME4
-- Status: CONFIRMADA EXECUTADA (SQL Editor do Supabase Dashboard,
-- reconfirmada pela execução bem-sucedida da Edge Function
-- `import-card-assets` — 122/122 referências e imagens, 0 falhas)
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.22", para o contexto
-- completo.
--
-- Réplica das Queries 252 (ME1)/255 (ME2)/256 (ME2.5)/257 (ME3) para a ME4 —
-- última coleção da Fase 1 (catálogo editorial completo em inglês).

INSERT INTO public.asset_import_run (
    run_code,
    run_type,
    asset_source_id,
    card_set_id,
    status
)
SELECT
    'RUN-20260720-00000025',
    'FULL_CARD_SET',
    s.id,
    cs.id,
    'PENDING'
FROM public.asset_source s
JOIN public.card_set cs
    ON cs.code = 'ME4'
WHERE s.code = 'TCGDEX';
