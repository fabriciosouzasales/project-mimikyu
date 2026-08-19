-- Query 3911 — Ativação comercial de JUSTTCG (Incremento P14.1)
-- Objetivo: registrar que a condição comercial (assinatura paga, requires_commercial_agreement)
-- foi satisfeita, permitindo pricing_source.is_active = TRUE para a fonte JUSTTCG.
-- Confirmado por Fabrício: assinatura comercial ativa (10.000 requests/mês, 1.000 requests/dia,
-- 50 requests/minuto, até 100 cards/request). Credencial e contrato da API confirmados por uma
-- única chamada real mínima e sem escrita (HTTP 200 em GET /v1/sets?game=pokemon, feita localmente
-- por Fabrício) antes desta migration. Segredo (JUSTTCG_API_KEY) nunca visto, solicitado, exibido
-- ou registrado por este agente em nenhum momento.
-- CONFIRMADO EXECUTADO em 2026-08-19 (projeto qjfutqujxrbzgrtkpgkg).

UPDATE pricing_source
SET is_active = TRUE
WHERE code = 'JUSTTCG'
  AND is_active = FALSE
  AND requires_commercial_agreement = TRUE;
