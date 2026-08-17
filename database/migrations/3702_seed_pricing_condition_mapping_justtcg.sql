-- Query 3702 — Seed pricing_condition_mapping: de-para JustTCG -> card_condition
-- Objetivo: mapear os códigos de condição exatamente como a JustTCG os reporta (campo
-- `condition` de cada variante, confirmado literal na prova técnica) para as cinco
-- condições canônicas semeadas na Query 3701. Pré-requisito para o conector resolver
-- pricing_observation.condition_id sem tabela de código hardcoded na aplicação.

INSERT INTO public.pricing_condition_mapping (pricing_source_id, external_condition_code, condition_id)
SELECT ps.id, v.external_condition_code, cc.id
FROM public.pricing_source ps
JOIN (VALUES
    ('Near Mint',         'NM'),
    ('Lightly Played',    'LP'),
    ('Moderately Played', 'MP'),
    ('Heavily Played',    'HP'),
    ('Damaged',           'DMG')
) AS v(external_condition_code, condition_code) ON TRUE
JOIN public.card_condition cc ON cc.code = v.condition_code
WHERE ps.code = 'JUSTTCG'
ON CONFLICT (pricing_source_id, external_condition_code) DO NOTHING;
