-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816235603
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3040 - Create Pricing Card Mapping Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Cria a tabela public.pricing_card_mapping — correspondência entre uma
card do catálogo e a Card identificada por uma fonte externa de preço,
mesmo papel de pricing_set_mapping um nível abaixo (Card em vez de
Card Set), mesmo contrato de estados (CONFIRMED/PENDING/NOT_FOUND/
REJECTED). Nenhuma linha é inserida nesta Query — nenhuma fonte
homologada existe ainda. A regra "Card Mapping só quando o Set Mapping
da mesma fonte estiver CONFIRMED" permanece responsabilidade da futura
rotina de escrita administrativa — não expressável como CHECK entre
tabelas diferentes, e nenhuma trigger/função é criada para isso nesta
Query (fora de escopo deste incremento). Ver ADR-029 e
docs/05f-pricing.md.

Regras de Negócio:
- único por (card_id, pricing_source_id);
- external_card_id obrigatório somente quando match_status = 'CONFIRMED';
- confirmed_at/confirmed_by obrigatórios em CONFIRMED/REJECTED, nulos
  em PENDING/NOT_FOUND;
- NOT_FOUND exige last_checked_at IS NOT NULL (mesma regra nova de
  pricing_set_mapping, Query 3030);
- match_evidence sempre objeto JSON;
- unicidade de (pricing_source_id, external_card_id) restrita às
  linhas CONFIRMED via índice único parcial;
- RLS habilitado desde a criação; única policy é leitura administrativa
  (pricing_admin_select); nenhuma função de escrita administrativa ou
  de sincronização é criada nesta Query (fora de escopo);
- GRANT mínimo (authenticated: SELECT; anon: nenhum; service_role:
  SELECT, somente leitura neste incremento) e REVOKE de
  TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de anon/authenticated, aplicados
  desde o nascimento da tabela (STD-001, revisão 1.19).
================================================================
*/

CREATE TABLE public.pricing_card_mapping (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    card_id            UUID NOT NULL REFERENCES public.card (id) ON DELETE CASCADE,
    pricing_source_id  UUID NOT NULL REFERENCES public.pricing_source (id) ON DELETE RESTRICT,
    external_card_id   TEXT,
    external_card_name TEXT,
    match_status       TEXT NOT NULL DEFAULT 'PENDING',
    match_method       TEXT,
    match_evidence     JSONB NOT NULL DEFAULT '{}'::JSONB,
    confirmed_at       TIMESTAMPTZ,
    confirmed_by       UUID,
    last_checked_at    TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pricing_card_mapping_card_source
        UNIQUE (card_id, pricing_source_id),
    CONSTRAINT ck_pricing_card_mapping_external_card_id_not_blank
        CHECK (external_card_id IS NULL OR BTRIM(external_card_id) <> ''),
    CONSTRAINT ck_pricing_card_mapping_status
        CHECK (match_status IN ('CONFIRMED', 'PENDING', 'NOT_FOUND', 'REJECTED')),
    CONSTRAINT ck_pricing_card_mapping_confirmed_requires_external_id
        CHECK (match_status <> 'CONFIRMED' OR external_card_id IS NOT NULL),
    CONSTRAINT ck_pricing_card_mapping_evidence_is_object
        CHECK (jsonb_typeof(match_evidence) = 'object'),
    CONSTRAINT ck_pricing_card_mapping_confirmation_consistency
        CHECK (
            (match_status IN ('PENDING', 'NOT_FOUND') AND confirmed_at IS NULL AND confirmed_by IS NULL)
            OR (match_status IN ('CONFIRMED', 'REJECTED') AND confirmed_at IS NOT NULL AND confirmed_by IS NOT NULL)
        ),
    CONSTRAINT ck_pricing_card_mapping_not_found_requires_last_checked
        CHECK (match_status <> 'NOT_FOUND' OR last_checked_at IS NOT NULL)
);

CREATE UNIQUE INDEX uq_pricing_card_mapping_source_external_confirmed
    ON public.pricing_card_mapping (pricing_source_id, external_card_id)
    WHERE match_status = 'CONFIRMED';

CREATE INDEX ix_pricing_card_mapping_pricing_source_id
    ON public.pricing_card_mapping (pricing_source_id);
CREATE INDEX ix_pricing_card_mapping_status
    ON public.pricing_card_mapping (match_status);

COMMENT ON TABLE public.pricing_card_mapping IS
    'Correspondência entre card e a Card identificada por uma pricing_source (CONFIRMED/PENDING/NOT_FOUND/REJECTED). Nenhuma linha inserida — nenhuma fonte homologada. Ver ADR-029 e docs/05f-pricing.md.';

ALTER TABLE public.pricing_card_mapping ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
    ON public.pricing_card_mapping
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_card_mapping TO authenticated;
GRANT SELECT ON public.pricing_card_mapping TO service_role;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pricing_card_mapping FROM anon, authenticated;
