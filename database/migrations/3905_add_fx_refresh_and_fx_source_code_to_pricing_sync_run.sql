-- Query 3905 — CONFIRMADO EXECUTADO (Incremento P13.1 — Fundação de Orquestração Programada
-- de Pricing, 2026-08-18). Aplicada originalmente via Supabase MCP no mesmo dia; este arquivo
-- foi versionado retroativamente durante a auditoria final do P13.1 (mesmo ciclo, achado real:
-- as migrations 3905-3907 estavam CONFIRMADO EXECUTADO no Supabase mas ausentes deste
-- diretório, quebrando a convenção já estabelecida desde a Query 3700). SQL idêntico ao
-- efetivamente aplicado, extraído da própria chamada de apply_migration.
--
-- Contexto: pricing_sync_run.pricing_source_id era NOT NULL, incompatível com uma futura
-- execução SCHEDULED de PTAX, que não tem pricing_source (BCB não é e não deve virar uma linha
-- dessa tabela — ver ADR-031). Esta migration: (1) estende run_type com FX_REFRESH, sem
-- reaproveitar PRICE_REFRESH (semânticas distintas: preço de carta vs. câmbio); (2) adiciona
-- fx_source_code TEXT, identidade cambial explícita alinhada ao mesmo domínio já usado por
-- pricing_fx_rate.rate_source_code (valor real em produção: 'BCB_PTAX') — não é FK, pelo mesmo
-- motivo de rate_source_code também não ser; (3) torna pricing_source_id opcional; (4) adiciona
-- CHECK correlacionado garantindo que FX_REFRESH e os demais run_types nunca coexistam com a
-- identidade de fonte errada.
--
-- Nota: o guard de não-branco desta migration (ck_pricing_sync_run_fx_source_code_not_blank)
-- foi complementado pela Query 3908 (mesmo incremento, rodada de auditoria), que adiciona a
-- exigência de formato normalizado (maiúsculas, [A-Z][A-Z0-9_]*) já usada por pricing_source.code
-- e pricing_fx_rate.rate_source_code — achado real da auditoria, não coberto por esta migration.

-- 1. Estende o domínio de run_type (não reutiliza PRICE_REFRESH)
ALTER TABLE public.pricing_sync_run
  DROP CONSTRAINT ck_pricing_sync_run_type;

ALTER TABLE public.pricing_sync_run
  ADD CONSTRAINT ck_pricing_sync_run_type
  CHECK (run_type = ANY (ARRAY['SET_DISCOVERY'::text, 'CARD_SYNC'::text, 'PRICE_REFRESH'::text, 'FX_REFRESH'::text]));

-- 2. Identidade explícita de fonte cambial, alinhada ao código já usado em pricing_fx_rate.rate_source_code
ALTER TABLE public.pricing_sync_run
  ADD COLUMN fx_source_code TEXT;

COMMENT ON COLUMN public.pricing_sync_run.fx_source_code IS
  'Identifica a fonte cambial de uma execução FX_REFRESH (ex.: ''BCB_PTAX'', mesmo domínio de pricing_fx_rate.rate_source_code). NULL para execuções que não são FX_REFRESH.';

-- 3. pricing_source_id passa a ser opcional (BCB/PTAX não é uma linha de pricing_source)
ALTER TABLE public.pricing_sync_run
  ALTER COLUMN pricing_source_id DROP NOT NULL;

-- 4. Regra correlacionada: FX_REFRESH usa fx_source_code (nunca pricing_source_id); os demais run_types
--    usam pricing_source_id (nunca fx_source_code) — nenhum estado ambíguo ou duplamente identificado.
ALTER TABLE public.pricing_sync_run
  ADD CONSTRAINT ck_pricing_sync_run_source_identity
  CHECK (
    (run_type = 'FX_REFRESH' AND pricing_source_id IS NULL AND fx_source_code IS NOT NULL)
    OR
    (run_type <> 'FX_REFRESH' AND pricing_source_id IS NOT NULL AND fx_source_code IS NULL)
  );

-- 5. Guarda defensiva: fx_source_code, quando presente, nunca é string vazia/só espaços
ALTER TABLE public.pricing_sync_run
  ADD CONSTRAINT ck_pricing_sync_run_fx_source_code_not_blank
  CHECK (fx_source_code IS NULL OR length(btrim(fx_source_code)) > 0);
