-- Query 3908 — CONFIRMADO EXECUTADO (Incremento P13.1, correção pós-auditoria, 2026-08-18).
-- Não edita a migration 3905 (já aplicada, instrução explícita de Fabrício) — aditiva.
--
-- Contexto: a auditoria final do P13.1 confirmou que pricing_source.code e
-- pricing_fx_rate.rate_source_code já exigem um formato normalizado (maiúsculas, começa por
-- letra, só [A-Z0-9_]) via ck_pricing_source_code_format / ck_pricing_fx_rate_source_code_format.
-- A Query 3905 garantia apenas NOT NULL (via ck_pricing_sync_run_source_identity, para
-- FX_REFRESH) e não-branco (ck_pricing_sync_run_fx_source_code_not_blank) para
-- pricing_sync_run.fx_source_code — nada impedia, por exemplo, 'bcb_ptax' (minúsculo),
-- 'BCB PTAX' (espaço interno) ou '1BCB' (começando por dígito). Esta migration fecha essa
-- lacuna, replicando exatamente o mesmo padrão de formato já usado nas duas colunas irmãs.
--
-- Validado transacionalmente (BEGIN/ROLLBACK) antes da aplicação: 'BCB_PTAX' (valor real)
-- continua aceito; minúsculas, espaço interno, hífen e início por dígito rejeitados; string
-- vazia e string só de espaços continuam rejeitadas (já cobertas pela 3905, revalidadas com a
-- 3908 presente); NULL continua rejeitado em FX_REFRESH (ck_pricing_sync_run_source_identity,
-- inalterada). Zero linhas reais afetadas — nenhuma linha em produção tinha fx_source_code
-- preenchido no momento da aplicação (todas as 5 linhas reais são CARD_SYNC/JustTCG).

ALTER TABLE public.pricing_sync_run
  ADD CONSTRAINT ck_pricing_sync_run_fx_source_code_format
  CHECK (
    fx_source_code IS NULL
    OR (fx_source_code = upper(fx_source_code) AND fx_source_code ~ '^[A-Z][A-Z0-9_]*$')
  );
