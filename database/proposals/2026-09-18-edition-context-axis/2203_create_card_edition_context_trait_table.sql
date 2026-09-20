-- ============================================================================
-- Query 2203 — card_edition_context_trait
-- ----------------------------------------------------------------------------
-- Ciclo   : VARIANT-DISPLAY-SEMANTICS-01 / EDITION-CONTEXT-AXIS-STAGING-01
-- Status  : PROPOSTA — NÃO EXECUTADA
-- Versão  : 1.0
--
-- OBJETIVO
--   Átomo do TERCEIRO EIXO de identidade: Edition Context.
--   Responde "de qual edição/release esta cópia veio", quando a resposta está
--   FISICAMENTE IMPRESSA na carta (selo de evento, nome de jogador em deck de
--   campeão, marca de canal/campanha, papel, colocação).
--
--   NÃO é acabamento (card_variant_type) e NÃO é tiragem (card_printing_trait).
--
-- POR QUE NÃO É CÓPIA DE 2165
--   card_printing_trait descreve ESTADO DE PLACA (1st edition, shadowless).
--   Aqui o átomo descreve ORIGEM DE EDIÇÃO. Consequências de desenho:
--     (a) `family` existe aqui e NÃO existe em Printing — é o que permite
--         agrupar 115 átomos em facetas de UI sem denormalizar rótulo;
--     (b) o vocabulário cresce continuamente (um Worlds novo por ano), ao
--         contrário de Printing, que é praticamente fechado. Daí `is_active`
--         ganhar peso operacional maior e `display_order` ser por família.
--
-- VOCABULÁRIO MEDIDO (A ∪ B, 2026-09-18)
--   115 traits distintos · cobertura 100% de A (1.069) e 100% de B (365).
--
-- NOMENCLATURA — REGRA NORMATIVA
--   Nenhum `code` é derivado automaticamente de token TCGdex.
--   Tradução editorial obrigatória, uma a uma:
--     TOP-SIXTEEN            -> PLACEMENT_TOP_16
--     PRE-RELEASE            -> EVENT_PRERELEASE
--     JASON-KLACZYNSKI       -> DECK_PLAYER_JASON_KLACZYNSKI
--   Jogadores usam SEMPRE o prefixo DECK_PLAYER_. O átomo representa
--   "edição de deck de campeão atribuída a <jogador>" — contexto de edição,
--   NUNCA uma entidade Pessoa reutilizável.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-01).
-- Mesmo padrão das migrations equivalentes de Printing (2165/2166/2167),
-- já executadas com sucesso via apply_migration. Tudo abaixo é um único
-- statement lógico: falha em qualquer ponto desfaz o arquivo inteiro.
BEGIN;

CREATE TABLE public.card_edition_context_trait (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id       UUID NOT NULL REFERENCES public.game (id)
                       ON UPDATE RESTRICT ON DELETE RESTRICT,
    family        TEXT NOT NULL,
    code          VARCHAR(80) NOT NULL,
    name          VARCHAR(120) NOT NULL,
    description   TEXT,
    display_order INTEGER NOT NULL,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT ck_cect_family CHECK (family IN (
        'EVENT',        -- Worlds, Regionals, Prerelease, POP, Gym Challenge
        'PLACEMENT',    -- Winner, Finalist, Top 8/16/32
        'ROLE',         -- Staff
        'DECK_PLAYER',  -- deck de campeão atribuído a jogador
        'CHANNEL',      -- McDonalds, GameStop, Pokémon Center, Comic-Con
        'PROGRAM',      -- Player Rewards, Professor Program, League
        'CAMPAIGN',     -- First Movie, 4Ever, Pokémon Day, aniversários
        'ARTWORK_MARK'  -- set-logo, mascote, Poké Ball estampada
    )),
    CONSTRAINT ck_cect_code_format
        CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_cect_code_family_prefix
        CHECK (family <> 'DECK_PLAYER' OR code LIKE 'DECK_PLAYER_%'),
    CONSTRAINT ck_cect_name_not_blank
        CHECK (btrim(name) <> ''),
    CONSTRAINT ck_cect_description_not_blank
        CHECK (description IS NULL OR btrim(description) <> ''),
    CONSTRAINT ck_cect_display_order_positive
        CHECK (display_order > 0),

    CONSTRAINT uq_cect_game_code UNIQUE (game_id, code),
    -- display_order é único POR FAMÍLIA (difere de card_printing_trait, que é
    -- global): as facetas de UI ordenam dentro da própria família.
    CONSTRAINT uq_cect_game_family_order UNIQUE (game_id, family, display_order),
    -- Alvo da FK composta de card_edition_context_profile_trait (same-Game).
    CONSTRAINT uq_cect_id_game UNIQUE (id, game_id)
);

CREATE INDEX ix_cect_game_family
    ON public.card_edition_context_trait (game_id, family)
    WHERE is_active;

COMMENT ON TABLE public.card_edition_context_trait IS
'Átomo de Edition Context: marca fisicamente impressa que identifica a edição/release de origem da cópia. Não é acabamento (card_variant_type) nem tiragem (card_printing_trait). Vocabulário medido: 115 átomos cobrindo 100% de A(1.069 NEEDS_REVIEW) e B(365 legacy READY). Codes NUNCA derivados automaticamente da fonte externa.';

COMMENT ON COLUMN public.card_edition_context_trait.family IS
'Faceta de agrupamento para UI e i18n. Não participa da identidade — a identidade é o conjunto exato de trait_ids no profile.';

-- ----------------------------------------------------------------------------
-- SEGURANÇA — paridade EXATA com o eixo irmão Printing (Query 2165)
-- ----------------------------------------------------------------------------
-- Corrigido em SECURITY-SEED-HARDENING-01 (B3). A versão anterior fazia
-- GRANT SELECT para `authenticated` SEM habilitar RLS: qualquer usuário
-- autenticado leria o vocabulário editorial inteiro, contrariando o padrão
-- admin-only de ADR-028 que a Query 2165 segue. Também concedia INSERT/UPDATE
-- direto ao service_role — superfície de escrita que Printing não tem, e que
-- contornaria os guards SECURITY DEFINER da Query 2206.
--
-- GRANT sem RLS não é least privilege: é ACL sem política.
ALTER TABLE public.card_edition_context_trait ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_edition_context_trait
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_edition_context_trait FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_edition_context_trait TO authenticated;
-- service_role: SELECT e SÓ. O runtime da Edge (import-card-variants) lê esta
-- tabela para saber `is_active` no preload do eixo 3 — mesmo recorte que a
-- Query 2182 concedeu a card_printing_trait. Nenhuma escrita: os writers são
-- SECURITY DEFINER e não dependem de privilégio do chamador.
GRANT SELECT ON public.card_edition_context_trait TO service_role;

COMMIT;

-- ============================================================================
-- VALIDAÇÃO
--   SELECT COUNT(*) FROM public.card_edition_context_trait;              -- 0
--   SELECT conname FROM pg_constraint
--    WHERE conrelid = 'public.card_edition_context_trait'::regclass;     -- 9
-- ============================================================================
