-- Project Mimikyu
-- Query 255 - Create Import Run ME2
-- Status: CONFIRMADA EXECUTADA (SQL Editor do Supabase Dashboard,
-- reconfirmada por consulta real pós-execução e pela execução bem-sucedida
-- da Edge Function `import-card-assets` — 130/130 referências e imagens)
-- Ver docs/06-pipeline-importacao.md, seção "Sprint B3.21", para o contexto
-- completo.
--
-- Réplica da Query 252 (asset_import_run da ME1) para a ME2 — mesmo
-- princípio: um `asset_import_run` real para desbloquear o pipeline já
-- validado (Incrementos 1 e 2) para a segunda coleção.
--
-- Episódio real, registrado por transparência: a primeira tentativa desta
-- migration (sem a coluna run_type) FALHOU pelo mesmo motivo já documentado
-- na Query 252 — run_type é NOT NULL, sem DEFAULT. Corrigida sem adivinhar,
-- reconfirmando o valor real já usado no catálogo (`FULL_CARD_SET`) por
-- consulta direta a information_schema.columns + SELECT DISTINCT run_type.

INSERT INTO public.asset_import_run (
    run_code,
    run_type,
    asset_source_id,
    card_set_id,
    status
)
SELECT
    'RUN-20260720-00000022',
    'FULL_CARD_SET',
    s.id,
    cs.id,
    'PENDING'
FROM public.asset_source s
JOIN public.card_set cs
    ON cs.code = 'ME2'
WHERE s.code = 'TCGDEX';
