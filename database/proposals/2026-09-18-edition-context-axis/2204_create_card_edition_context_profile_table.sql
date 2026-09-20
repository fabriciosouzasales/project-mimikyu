-- ============================================================================
-- Query 2204 — card_edition_context_profile
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.2
--
-- v1.2 (BATCH1-RUNTIME-CORRECTION-02) — só documentação
--   Corpo SQL IDÊNTICO à v1.1: os dois CHECKs escalares foram ACEITOS pela
--   auditoria e não mudaram. Alterado apenas o header — "173 profiles" era a
--   estimativa pré-curadoria, e o corpus canônico é 144 (ver nota em OBJETIVO).
--   A prova de CONTEÚDO da assinatura (correspondência com a N:N) passa a
--   existir de fato na 2206 v2.0, GUARD C — ver nota no CHECK de shape.
--
-- v1.1 (BATCH1-RUNTIME-CORRECTION-01) — CORREÇÃO DE RUNTIME
--   A v1.0 ABORTOU no LIVE via apply_migration com SQLSTATE 0A000
--   ("cannot use subquery in check constraint"). Zero resíduo: a tabela não
--   foi criada e a migration não entrou no ledger.
--
--   Causa raiz: `ck_cecp_signature_shape` tentava provar a canonicalização do
--   array DENTRO do CHECK, via
--       traits_signature = ARRAY(SELECT DISTINCT u FROM unnest(...) ORDER BY u)
--   O PostgreSQL recusa subquery em CHECK por definição — a restrição precisa
--   ser avaliável linha a linha, sem acesso ao resto do banco nem a um
--   conjunto derivado. Não é limitação de versão nem de permissão.
--
--   Correção: as invariantes ESTRUTURAIS foram separadas em dois CHECKs
--   escalares, idênticos aos que a card_printing_profile já carrega no LIVE
--   desde a Query 2166 (linhas 148-153):
--       ck_cecp_signature_not_empty  -> cardinality(...) >= 1
--       ck_cecp_signature_shape      -> array_ndims(...) = 1
--   Nenhuma função helper nova, nenhum hash, nenhuma ampliação de arquitetura.
--   A propriedade DISTINCT + ORDER BY trait_id permanece onde sempre esteve
--   de fato: no selo deferido da Query 2206.
--
-- OBJETIVO
--   Composição canônica por CONJUNTO EXATO de traits. É o componente que
--   entra na identidade de card_variant, nunca o trait isolado.
--
--   144 profiles no corpus CANÔNICO (autoridade: 2231 v3.1 + SEED-COVERAGE).
--   Aridade máxima observada: 3. Fator de combinação 144/115 = 1,25.
--   Distribuição medida (autoridade: 2231 gate P4 + SEED-COVERAGE §3):
--   96 de aridade 1 · 44 de aridade 2 · 4 de aridade 3 = 144.
--   NOTA (BATCH1-RUNTIME-CORRECTION-02): a v1.0 dizia "173 profiles medidos
--   na união A ∪ B (133 de A + 40 exclusivos de B)". 173 era a ESTIMATIVA
--   pré-curadoria; o corpus fechado tem 144, dos quais 7 de B PROVEN e 12
--   DEFERRED (B-PROFILE-AUDIT-19.md). Os documentos em editorial/ e
--   PENDING-ARTIFACTS.md preservam 173 como registro histórico da medição —
--   lá o número está certo; aqui, no DDL que vai LIVE, estava errado.
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

    -- Assinatura selada nunca pode ser vazia. A garantia principal é o trigger
    -- deferido da 2206 (que aborta com EDITION_CONTEXT_EMPTY_COMPOSITION); este
    -- CHECK impede o estado inválido mesmo por escrita direta.
    -- Paridade literal com ck_card_printing_profile_signature_not_empty (2166).
    CONSTRAINT ck_cecp_signature_not_empty
        CHECK (traits_signature IS NULL OR cardinality(traits_signature) >= 1),

    -- Um array unidimensional, sempre. Protege contra payload malformado.
    -- Paridade literal com ck_card_printing_profile_signature_shape (2166).
    --
    -- DISTINCT + ORDER BY trait_id NÃO são verificados aqui, e nunca foram
    -- verificáveis: um CHECK não aceita subquery (SQLSTATE 0A000). A
    -- canonicalização é responsabilidade EXCLUSIVA do selo da 2206, que monta
    -- o array com ARRAY(SELECT DISTINCT pt.trait_id ... ORDER BY pt.trait_id).
    CONSTRAINT ck_cecp_signature_shape
        CHECK (traits_signature IS NULL OR array_ndims(traits_signature) = 1),

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
'Composição canônica de Edition Context por conjunto exato de traits. Componente de identidade de card_variant. 144 profiles no corpus canonico; aridade maxima 3. Resolucao SEMPRE por igualdade exata de traits_signature.';

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
