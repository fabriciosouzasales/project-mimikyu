-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816235514
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3030 - Create Pricing Set Mapping Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Cria a tabela public.pricing_set_mapping — correspondência entre um
card_set do catálogo e o Set identificado por uma fonte externa de
preço, com estado explícito de correspondência (CONFIRMED/PENDING/
NOT_FOUND/REJECTED). Nenhuma linha é inserida nesta Query — nenhuma
fonte homologada existe ainda. Ver ADR-029 e docs/05f-pricing.md.

Regras de Negócio:
- único por (card_set_id, pricing_source_id) — um Card Set tem no
  máximo um mapeamento por fonte; a linha evolui de estado via UPDATE
  (função administrativa futura, fora de escopo), nunca gera segunda
  linha;
- external_set_id obrigatório somente quando match_status = 'CONFIRMED';
- confirmed_at/confirmed_by obrigatórios em CONFIRMED/REJECTED, nulos
  em PENDING/NOT_FOUND (decisão administrativa explícita vs. estado
  automático);
- NOT_FOUND exige last_checked_at IS NOT NULL (nova regra de
  integridade deste incremento — falha técnica nunca gera NOT_FOUND,
  então todo NOT_FOUND representa uma consulta tecnicamente concluída,
  que deve ter data de verificação registrada);
- match_evidence sempre objeto JSON;
- unicidade de (pricing_source_id, external_set_id) restrita às linhas
  CONFIRMED via índice único parcial — candidatos PENDING/REJECTED
  podem repetir o mesmo external_set_id sem violar unicidade;
- RLS habilitado desde a criação; única policy é leitura administrativa
  (pricing_admin_select); nenhuma função de escrita administrativa ou
  de sincronização é criada nesta Query (fora de escopo deste
  incremento);
- GRANT mínimo (authenticated: SELECT; anon: nenhum; service_role:
  SELECT, somente leitura neste incremento — INSERT/UPDATE para a
  futura sincronização ficam para quando a rotina de escrita for
  implementada) e REVOKE de TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de
  anon/authenticated, aplicados desde o nascimento da tabela
  (STD-001, revisão 1.19).
================================================================
*/

CREATE TABLE public.pricing_set_mapping (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_set_id        UUID NOT NULL REFERENCES public.card_set (id) ON DELETE CASCADE,
    pricing_source_id  UUID NOT NULL REFERENCES public.pricing_source (id) ON DELETE RESTRICT,
    external_set_id    TEXT,
    external_set_name  TEXT,
    match_status       TEXT NOT NULL DEFAULT 'PENDING',
    match_method       TEXT,
    match_evidence     JSONB NOT NULL DEFAULT '{}'::JSONB,
    confirmed_at       TIMESTAMPTZ,
    confirmed_by       UUID,
    last_checked_at    TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pricing_set_mapping_card_set_source
        UNIQUE (card_set_id, pricing_source_id),
    CONSTRAINT ck_pricing_set_mapping_external_set_id_not_blank
        CHECK (external_set_id IS NULL OR BTRIM(external_set_id) <> ''),
    CONSTRAINT ck_pricing_set_mapping_status
        CHECK (match_status IN ('CONFIRMED', 'PENDING', 'NOT_FOUND', 'REJECTED')),
    CONSTRAINT ck_pricing_set_mapping_confirmed_requires_external_id
        CHECK (match_status <> 'CONFIRMED' OR external_set_id IS NOT NULL),
    CONSTRAINT ck_pricing_set_mapping_evidence_is_object
        CHECK (jsonb_typeof(match_evidence) = 'object'),
    CONSTRAINT ck_pricing_set_mapping_confirmation_consistency
        CHECK (
            (match_status IN ('PENDING', 'NOT_FOUND') AND confirmed_at IS NULL AND confirmed_by IS NULL)
            OR (match_status IN ('CONFIRMED', 'REJECTED') AND confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL)
        ),
    CONSTRAINT ck_pricing_set_mapping_not_found_requires_last_checked
        CHECK (match_status <> 'NOT_FOUND' OR last_checked_at IS NOT NULL)
);

-- Índice único parcial: unicidade de external_set_id por fonte só exigida para correspondências CONFIRMED.
CREATE UNIQUE INDEX uq_pricing_set_mapping_source_external_confirmed
    ON public.pricing_set_mapping (pricing_source_id, external_set_id)
    WHERE match_status = 'CONFIRMED';

CREATE INDEX ix_pricing_set_mapping_pricing_source_id
    ON public.pricing_set_mapping (pricing_source_id);
CREATE INDEX ix_pricing_set_mapping_status
    ON public.pricing_set_mapping (match_status);

COMMENT ON TABLE public.pricing_set_mapping IS
    'Correspondência entre card_set e o Set identificado por uma pricing_source (CONFIRMED/PENDING/NOT_FOUND/REJECTED). Nenhuma linha inserida — nenhuma fonte homologada. Ver ADR-029 e docs/05f-pricing.md.';

ALTER TABLE public.pricing_set_mapping ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
    ON public.pricing_set_mapping
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_set_mapping TO authenticated;
GRANT SELECT ON public.pricing_set_mapping TO service_role;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pricing_set_mapping FROM anon, authenticated;
