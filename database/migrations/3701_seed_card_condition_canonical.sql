-- Query 3701 — Seed card_condition: vocabulário canônico de condições físicas
-- Objetivo: cadastrar as cinco condições canônicas de conservação (Near Mint até Damaged),
-- referência compartilhada (05f-pricing.md: "não exclusiva de Pricing" — reutilizável por
-- Collection no futuro), pré-requisito estrutural para qualquer pricing_observation (FK
-- NOT NULL condition_id -> card_condition). Vocabulário confirmado pela prova técnica real
-- da JustTCG (prova-justtcg-resultados.json, 2026-08-17): as cinco strings observadas nas
-- variantes de todas as 18 cartas consultadas foram exatamente "Near Mint", "Lightly
-- Played", "Moderately Played", "Heavily Played", "Damaged" — mesma escala padrão de
-- mercado usada por TCGplayer/Cardmarket/JustTCG, não uma invenção específica de fonte.
--
-- condition_order: 1 (melhor) a 5 (pior) — ordem de conservação decrescente, convenção já
-- usada em card_variant_type.variant_order (STD-002).

INSERT INTO public.card_condition (code, name, condition_order) VALUES
    ('NM',  'Near Mint',        1),
    ('LP',  'Lightly Played',   2),
    ('MP',  'Moderately Played',3),
    ('HP',  'Heavily Played',   4),
    ('DMG', 'Damaged',          5)
ON CONFLICT (code) DO NOTHING;
