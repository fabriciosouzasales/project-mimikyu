-- ============================================================================
-- ARQUIVO RECONSTRUIDO RETROATIVAMENTE A PARTIR DO HISTORICO OFICIAL
-- (supabase_migrations.schema_migrations) -- nunca reexecutado; o SQL abaixo e
-- o statement armazenado, sem qualquer alteracao.
-- version: 20260816232430
-- Recuperado em: 2026-08-17
-- ============================================================================

/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 3020 - Create Pricing Condition Mapping Table
Versão......: 1.0
Status......: CANÔNICA
Autor.......: Claude (agente responsável pela documentação e schema)
Data........: 2026-08-16

Descrição...:
Cria a tabela public.pricing_condition_mapping — de-para entre o
código/texto de condição usado por uma fonte externa de preço e a
card_condition canônica (referência compartilhada). Esta tabela em si
permanece exclusiva de Pricing (é o de-para por fonte que só faz
sentido neste domínio); apenas a condição canônica que ela referencia
é compartilhada. Nenhuma linha é inserida nesta Query — nenhuma fonte
homologada existe ainda (JustTCG/TCGplayer permanecem fora de escopo).
Ver ADR-029 e docs/05f-pricing.md.

Regras de Negócio:
- único por (pricing_source_id, external_condition_code) — a mesma
  fonte nunca mapeia o mesmo texto para duas condições diferentes;
- external_condition_code preservado exatamente como veio da fonte,
  sem normalização;
- FKs para pricing_source e card_condition em ON DELETE RESTRICT —
  nenhuma das duas tem exclusão física prevista de qualquer forma;
- RLS habilitado desde a criação; única policy é leitura administrativa
  (pricing_admin_select); nenhuma função de escrita administrativa é
  criada nesta Query (fora de escopo deste incremento) — sincronização
  também fora de escopo;
- GRANT mínimo (authenticated: SELECT; anon: nenhum) e REVOKE de
  TRUNCATE/REFERENCES/TRIGGER/MAINTAIN de anon/authenticated, aplicados
  desde o nascimento da tabela (STD-001, revisão 1.19).
================================================================
*/

CREATE TABLE public.pricing_condition_mapping (
    id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pricing_source_id         UUID NOT NULL REFERENCES public.pricing_source (id) ON DELETE RESTRICT,
    external_condition_code   TEXT NOT NULL,
    condition_id              UUID NOT NULL REFERENCES public.card_condition (id) ON DELETE RESTRICT,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_pricing_condition_mapping_source_external
        UNIQUE (pricing_source_id, external_condition_code),
    CONSTRAINT ck_pricing_condition_mapping_external_code_not_blank
        CHECK (BTRIM(external_condition_code) <> '')
);

CREATE INDEX ix_pricing_condition_mapping_condition_id
    ON public.pricing_condition_mapping (condition_id);

COMMENT ON TABLE public.pricing_condition_mapping IS
    'De-para entre o código de condição de cada pricing_source e a card_condition canônica (referência compartilhada). Exclusiva de Pricing. Nenhuma linha inserida — nenhuma fonte homologada ainda. Ver ADR-029 e docs/05f-pricing.md.';

ALTER TABLE public.pricing_condition_mapping ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_admin_select
    ON public.pricing_condition_mapping
    FOR SELECT
    USING ((select is_admin()));

GRANT SELECT ON public.pricing_condition_mapping TO authenticated;

REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON public.pricing_condition_mapping FROM anon, authenticated;
