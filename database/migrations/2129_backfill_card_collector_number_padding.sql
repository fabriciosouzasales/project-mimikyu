/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2129 - Backfill Card Collector Number Padding
Versão......: 1.0
Status......: MIGRATION — CONFIRMADO EXECUTADO
Autor.......: Fabrício Sales / Claude
Data........: 2026-08-11

Descrição...:
Backfill de public.card.collector_number para todas as linhas cujo
número tenha menos dígitos que collector_total — bug real
reportado por Fabrício: cartas apareciam na galeria como "#1/185"
em vez de "#001/185". Causa raiz: resolveCatalogImportRow()
(supabase/functions/_shared/catalog-normalization/resolve-row.ts)
gravava o localId da TCGdex sem nenhum preenchimento; corrigido no
mesmo ciclo com padCollectorNumber(), que preenche com zeros à
esquerda até a mesma quantidade de dígitos de collector_total (não
um número fixo — "01/88" para uma Coleção de 88 cartas, "001/185"
para uma de 185, nunca "010/88").

Regras de Negócio:
- Só atualiza collector_number puramente numérico
  (collector_number ~ '^[0-9]+$') — nunca toca formatos
  alfanuméricos que já venham formatados pela própria fonte
  (ex.: "TG01", "SWSH001").
- Só atualiza quando o número já é MAIS CURTO que os dígitos de
  collector_total (LENGTH(collector_number) <
  LENGTH(collector_total::text)) — LPAD nunca trunca, mas a
  condição evita qualquer UPDATE sem efeito real.
- collector_total NULL (Set sem total conhecido) fica de fora —
  sem largura de referência para calcular o padding.
- Risco de colisão avaliado antes da execução: só uma Coleção
  (SVP) tem collector_total inconsistente entre Cards (225 para as
  cartas originais, 226 para as 8 cadastradas manualmente depois da
  correção do total real) — mas as duas larguras são idênticas (3
  dígitos), então o padding resultante não diverge nem colide.

Pré-requisitos:
- Query 140 - Create Card Table.
================================================================
*/

UPDATE public.card
SET collector_number = LPAD(collector_number, LENGTH(collector_total::text), '0')
WHERE collector_total IS NOT NULL
  AND collector_total > 0
  AND collector_number ~ '^[0-9]+$'
  AND LENGTH(collector_number) < LENGTH(collector_total::text);

-- ================================================================
-- Resultado esperado: 837 linhas atualizadas.
--
-- Como validar:
-- SELECT count(*) AS restantes
-- FROM public.card
-- WHERE collector_total IS NOT NULL
--   AND collector_total > 0
--   AND collector_number ~ '^[0-9]+$'
--   AND LENGTH(collector_number) < LENGTH(collector_total::text);
-- -- esperado: 0
-- ================================================================
--
-- CONFIRMADO EXECUTADO (2026-08-11): validação de confirmação
-- rodada por Fabrício, "restantes" = 0.
-- ================================================================
