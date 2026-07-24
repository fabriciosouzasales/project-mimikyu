-- Project Mimikyu
-- Query 259 - Create Import Run ME2 (pt-BR)
-- Status: CONFIRMADA EXECUTADA (SQL Editor do Supabase Dashboard,
-- reconfirmada pela confirmação direta de Fabrício — "Todas executadas com
-- sucesso" — e pela conferência agregada final do catálogo: 859 registros em
-- card_external_reference, 1.718 em card_asset (859 EN + 859 PT-BR), 1.718
-- imagens no Storage, 0 falhas nas 5 coleções).
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.26", para o contexto
-- completo.
--
-- Fase 2 (pt-BR) do plano de Fabrício — mesmo `card_set_id`/`asset_source_id`
-- da Query 255 (ME2, en), novo `run_code` próprio para a execução em
-- português (diferente da ME1, que reaproveitou o `run_code` original em vez
-- de criar uma nova linha — ver Sprint B3.23/B3.24).

INSERT INTO public.asset_import_run (
    run_code,
    run_type,
    asset_source_id,
    card_set_id,
    status
)
SELECT
    'RUN-20260720-00000026',
    'FULL_CARD_SET',
    s.id,
    cs.id,
    'PENDING'
FROM public.asset_source s
JOIN public.card_set cs
    ON cs.code = 'ME2'
WHERE s.code = 'TCGDEX';
