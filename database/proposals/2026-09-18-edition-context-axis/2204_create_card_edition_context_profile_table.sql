-- ============================================================================
-- Query 2204 — card_edition_context_profile
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
--
-- OBJETIVO
--   Composição canônica por CONJUNTO EXATO de traits. É o componente que
--   entra na identidade de card_variant, nunca o trait isolado.
--
--   173 profiles medidos na união A ∪ B (133 de A + 40 exclusivos de B).
--   Aridade máxima observada: 2. Fator de combinação 173/115 = 1,50.
--
-- PRINCÍPIO HERDADO DE 2166 (Printing), deliberadamente
--   traits_signature é UUID[] DISTINTO e ORDENADO ASC, materializado por
--   trigger a partir da N:N — que é a fonte da verdade. Resolução por
--   IGUALDADE EXATA de array, nunca por code construído, LIKE ou substring.
--
-- DIFERENÇA SEMÂNTICA vs Printing (não copiar mecanicamente)
--   Em Printing, o conjunto de traits é praticamente fechado. Aqui não:
--   cada temporada competitiva acrescenta átomos. Por isso:
--     (a) display_order é global mas esparso (passo 10), para inserir
--         temporadas novas sem renumerar;
--     (b) is_active governa apenas disponibilidade para NOVAS resoluções —
--         jamais afeta card_variant já materializado.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-01).
-- Paridade com a Query 2166. Ver nota completa na Query 2203.
BEGIN;

CREATE TABLE public.card_edition_context_profile (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id          UUID NOT NULL REFERENCES public.game (id)
                          ON UPDATE RESTRICT ON DELETE RESTRICT,
    code             VARCHAR(140) NOT NULL,
    name             VARCHAR(200) NOT NULL,
    description      TEXT,
    display_order    INTEGER NOT NULL,
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    -- Materializada por trigger (2206). NULL somente dentro da transação de
    -- criação, antes do selo — nunca em estado COMMITADO.
    traits_signature UUID[],
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT ck_cecp_code_format  CHECK (code ~ '^[A-Z][A-Z0-9_]*$'),
    CONSTRAINT ck_cecp_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT ck_cecp_description_not_blank
        CHECK (description IS NULL OR btrim(description) <> ''),
    CONSTRAINT ck_cecp_display_order_positive CHECK (display_order > 0),
    -- Assinatura selada precisa ser não-vazia, distinta e ordenada.
    CONSTRAINT ck_cecp_signature_shape CHECK (
        traits_signature IS NULL OR (
            cardinality(traits_signature) > 0
            AND traits_signature = ARRAY(SELECT DISTINCT u FROM unnest(traits_signature) u ORDER BY u)
        )
    ),

    CONSTRAINT uq_cecp_game_code  UNIQUE (game_id, code),
    CONSTRAINT uq_cecp_game_order UNIQUE (game_id, display_order),
    CONSTRAINT uq_cecp_id_game    UNIQUE (id, game_id)
);

-- UM profile por conjunto exato de traits, dentro do Game.
-- É esta UNIQUE que impede duas composições idênticas com codes diferentes.
CREATE UNIQUE INDEX uq_cecp_game_signature
    ON public.card_edition_context_profile (game_id, traits_signature)
    WHERE traits_signature IS NOT NULL;

COMMENT ON TABLE public.card_edition_context_profile IS
'Composição canônica de Edition Context por conjunto exato de traits. Componente de identidade de card_variant. 173 profiles medidos em A uniao B; aridade maxima 2. Resolucao SEMPRE por igualdade exata de traits_signature.';

-- ----------------------------------------------------------------------------
-- SEGURANÇA — paridade EXATA com card_printing_profile (Query 2166)
-- ----------------------------------------------------------------------------
-- Corrigido em SECURITY-SEED-HARDENING-01 (B3): faltava RLS e havia
-- INSERT/UPDATE direto para service_role. Ver comentário completo na 2203.
ALTER TABLE public.card_edition_context_profile ENABLE ROW LEVEL SECURITY;

CREATE POLICY catalog_admin_select
    ON public.card_edition_context_profile
    FOR SELECT
    USING ((SELECT public.is_admin()));

REVOKE ALL ON public.card_edition_context_profile FROM anon, authenticated, service_role;
GRANT SELECT ON public.card_edition_context_profile TO authenticated;
-- service_role: SELECT e SÓ — a Edge lê id + traits_signature + is_active no
-- preload do eixo 3, espelhando o que a Query 2182 fez para
-- card_printing_profile. O selo de traits_signature continua exclusivo do
-- trigger deferido da Query 2206.
GRANT SELECT ON public.card_edition_context_profile TO service_role;

COMMIT;
