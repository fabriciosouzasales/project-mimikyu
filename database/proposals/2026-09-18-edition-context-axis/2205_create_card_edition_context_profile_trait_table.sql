-- ============================================================================
-- Query 2205 — card_edition_context_profile_trait (N:N)
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
--
-- OBJETIVO
--   FONTE DA VERDADE da composição. traits_signature no profile é
--   MATERIALIZAÇÃO desta tabela, nunca o contrário.
--
-- SAME-GAME GUARD
--   game_id é carregado na própria N:N e amarrado por DUAS FKs compostas —
--   mesmo padrão de 2167. Torna estruturalmente impossível compor um profile
--   de um Game com trait de outro.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-01).
-- Paridade com a Query 2167. Ver nota completa na Query 2203.
BEGIN;

CREATE TABLE public.card_edition_context_profile_trait (
    profile_id UUID NOT NULL,
    trait_id   UUID NOT NULL,
    game_id    UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT pk_cecpt PRIMARY KEY (profile_id, trait_id),

    CONSTRAINT fk_cecpt_profile
        FOREIGN KEY (profile_id, game_id)
        REFERENCES public.card_edition_context_profile (id, game_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT,

    CONSTRAINT fk_cecpt_trait
        FOREIGN KEY (trait_id, game_id)
        REFERENCES public.card_edition_context_trait (id, game_id)
        ON UPDATE RESTRICT ON DELETE RESTRICT
);

CREATE INDEX ix_cecpt_trait ON public.card_edition_context_profile_trait (trait_id);

COMMENT ON TABLE public.card_edition_context_profile_trait IS
'N:N profile x trait. Fonte da verdade da composicao; traits_signature e materializacao. Same-Game garantido por duas FKs compostas.';

-- ----------------------------------------------------------------------------
-- SEGURANÇA — paridade EXATA com card_printing_profile_trait (Query 2167)
-- ----------------------------------------------------------------------------
-- Corrigido em SECURITY-SEED-HARDENING-01 (B3). Ver comentário na 2203.
ALTER TABLE public.card_edition_context_profile_trait ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_edition_context_profile_trait
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_edition_context_profile_trait FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_edition_context_profile_trait TO authenticated;
-- Deliberadamente SEM grant ao service_role — mesma decisão da Query 2173
-- para card_printing_profile_trait: a Edge resolve o eixo por
-- `traits_signature`, então a N:N é redundante para ela. Menos superfície.

COMMIT;
