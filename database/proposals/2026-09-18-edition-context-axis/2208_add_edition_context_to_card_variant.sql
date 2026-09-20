-- ============================================================================
-- Query 2208 — card_variant.edition_context_profile_id
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
--
-- Aditivo puro. NULLABLE por construção: a esmagadora maioria das 24.893
-- Variants não tem contexto de edição e nunca terá.
-- Semântica de NULL = "sem contexto de edição", um VALOR, não desconhecido.
-- É essa semântica que justifica NULLS NOT DISTINCT na Query 2209.
-- ============================================================================

-- Fronteira transacional EXPLÍCITA (TRANSACTION-BOUNDARY-CORRECTION-02).
-- Quatro statements: coluna, FK, índice parcial, COMMENT. Coluna sem FK, ou
-- FK sem índice, é estado parcial aplicável — e era representável enquanto a
-- atomicidade dependia do executor. Agora não é.
BEGIN;

ALTER TABLE public.card_variant
    ADD COLUMN edition_context_profile_id UUID NULL;

ALTER TABLE public.card_variant
    ADD CONSTRAINT fk_card_variant_edition_context
        FOREIGN KEY (edition_context_profile_id)
        REFERENCES public.card_edition_context_profile (id)
        ON UPDATE RESTRICT ON DELETE RESTRICT;

-- Índice parcial: só ~1,5% das linhas terão valor.
CREATE INDEX ix_card_variant_edition_context
    ON public.card_variant (edition_context_profile_id)
    WHERE edition_context_profile_id IS NOT NULL;

COMMENT ON COLUMN public.card_variant.edition_context_profile_id IS
'Terceiro eixo de identidade. NULL significa "sem contexto de edicao" — e um VALOR, nao desconhecido. Preenchido apenas quando a carta carrega marca fisica de evento/canal/programa/campanha/deck de campeao.';

COMMIT;
