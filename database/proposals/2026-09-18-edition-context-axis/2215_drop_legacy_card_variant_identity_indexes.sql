-- ============================================================================
-- Query 2215 — REMOÇÃO das identidades antigas de card_variant
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- CORREÇÃO 1 da GATE-A-FINAL-CORRECTION-01
--
-- O DEFEITO QUE ESTA QUERY CORRIGE
--   Até a v1.x, os dois DROPs viviam COMENTADOS no rodapé da Query 2209.
--   Consequência: 2209 criava a identidade nova e o pacote se declarava
--   "identidade de 4 componentes" — mas as duas antigas continuavam ATIVAS.
--
--   uq_card_variant_card_type_no_printing (card_id, variant_type_id)
--       WHERE printing_profile_id IS NULL
--   uq_card_variant_card_type_printing    (card_id, variant_type_id, printing_profile_id)
--       WHERE printing_profile_id IS NOT NULL
--
--   As duas IGNORAM edition_context_profile_id. Enquanto existirem, duas
--   Variants da mesma Card, mesmo acabamento e mesma tiragem, que difiram
--   SOMENTE em contexto de edição, continuam sendo rejeitadas com 23505.
--   Ou seja: **o eixo não existe na prática.** Era um blocker real, não
--   uma questão de redação.
--
-- POR QUE EM QUERY PRÓPRIA, E NÃO DENTRO DE 2209
--   Para que a remoção seja um passo AUDITÁVEL e com prova de pré-condição.
--   A ordem é: provar que a nova existe e é válida -> remover UMA -> provar
--   de novo -> remover a OUTRA -> provar que só a nova restou.
--   Em nenhum instante a tabela fica sem constraint de identidade.
--
-- SEM CONCURRENTLY — coerente com 2209 v2.0
--   DROP INDEX toma AccessExclusiveLock por um instante. Sob o FREEZE da
--   etapa 0 do rollout não há concorrência. DROP INDEX CONCURRENTLY exigiria
--   autocommit, que este projeto nunca usou.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRÉ-CONDIÇÃO: a identidade NOVA existe, é única e está válida.
DO $$
DECLARE v_ok BOOLEAN;
BEGIN
    SELECT (i.indisunique AND i.indisvalid AND NOT i.indpred IS NOT NULL)
      INTO v_ok
      FROM pg_index i
     WHERE i.indexrelid = 'public.uq_card_variant_identity'::REGCLASS;

    IF v_ok IS NOT TRUE THEN
        RAISE EXCEPTION 'NEW_IDENTITY_NOT_READY: uq_card_variant_identity ausente, nao-unico, invalido ou parcial. Rode a Query 2209 antes.';
    END IF;

    -- Também precisa estar materializada como CONSTRAINT, não só índice.
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
         WHERE c.conrelid = 'public.card_variant'::REGCLASS
           AND c.conname  = 'uq_card_variant_identity'
           AND c.contype  = 'u'
    ) THEN
        RAISE EXCEPTION 'NEW_IDENTITY_NOT_CONSTRAINT: uq_card_variant_identity existe como indice mas nao como UNIQUE constraint. Passo 2 da Query 2209 nao rodou.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- Remoção da PRIMEIRA antiga. A segunda ainda protege seu próprio universo.
DROP INDEX IF EXISTS public.uq_card_variant_card_type_no_printing;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'uq_card_variant_card_type_no_printing') THEN
        RAISE EXCEPTION 'DROP_FAILED_1: uq_card_variant_card_type_no_printing ainda existe.';
    END IF;
    -- A nova continua de pé (não foi derrubada por engano junto).
    PERFORM 1 FROM pg_index WHERE indexrelid = 'public.uq_card_variant_identity'::REGCLASS;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'NEW_IDENTITY_LOST: uq_card_variant_identity desapareceu durante o passo 2.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 3 ---
DROP INDEX IF EXISTS public.uq_card_variant_card_type_printing;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'uq_card_variant_card_type_printing') THEN
        RAISE EXCEPTION 'DROP_FAILED_2: uq_card_variant_card_type_printing ainda existe.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 4 ---
-- PROVA TERMINAL: somente a nova identidade permanece, e as constraints
-- ORTOGONAIS (ordem, default, FK composta) continuam intactas.
DO $$
DECLARE
    v_ident   INT;
    v_legado  INT;
    v_ordem   INT;
    v_default INT;
    v_idcard  INT;
BEGIN
    -- Índices ÚNICOS sobre card_variant que contêm variant_type_id.
    -- Depois desta Query deve existir EXATAMENTE UM: a identidade nova.
    SELECT COUNT(*) INTO v_ident
      FROM pg_index i
      JOIN pg_class ic ON ic.oid = i.indexrelid
     WHERE i.indrelid = 'public.card_variant'::REGCLASS
       AND i.indisunique
       AND EXISTS (
           SELECT 1 FROM unnest(i.indkey) k
            JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k
           WHERE a.attname = 'variant_type_id'
       );
    IF v_ident <> 1 THEN
        RAISE EXCEPTION 'IDENTITY_NOT_UNIQUE_SOURCE: esperado 1 indice unico de identidade, encontrado %.', v_ident;
    END IF;

    SELECT COUNT(*) INTO v_legado FROM pg_class
     WHERE relname IN ('uq_card_variant_card_type_no_printing',
                       'uq_card_variant_card_type_printing');
    IF v_legado <> 0 THEN
        RAISE EXCEPTION 'LEGACY_INDEX_SURVIVED: % indices antigos ainda existem.', v_legado;
    END IF;

    -- Preservados INTACTOS — não são identidade, são invariantes ortogonais.
    SELECT COUNT(*) INTO v_ordem   FROM pg_class WHERE relname = 'uq_card_variant_card_order';
    SELECT COUNT(*) INTO v_default FROM pg_class WHERE relname = 'uq_card_variant_one_default_per_card';
    SELECT COUNT(*) INTO v_idcard  FROM pg_class WHERE relname = 'uq_card_variant_id_card';
    IF v_ordem <> 1 OR v_default <> 1 OR v_idcard <> 1 THEN
        RAISE EXCEPTION 'ORTHOGONAL_CONSTRAINT_LOST: card_order=% one_default=% id_card=% (esperado 1/1/1).',
              v_ordem, v_default, v_idcard;
    END IF;

    RAISE NOTICE 'IDENTIDADE card_variant: somente uq_card_variant_identity permanece. 4/4 provas OK.';
END $$;

-- ============================================================================
-- ROLLBACK
--   Recriar qualquer uma das antigas é possível enquanto os dados ainda as
--   satisfizerem — o que é verdade ATÉ a primeira Variant com contexto ser
--   gravada (Query 2213). Depois disso a recriação falha, e isso é correto:
--   é o sinal de que o eixo passou a existir de fato.
--
--     CREATE UNIQUE INDEX uq_card_variant_card_type_no_printing
--         ON public.card_variant (card_id, variant_type_id)
--      WHERE printing_profile_id IS NULL;
--     CREATE UNIQUE INDEX uq_card_variant_card_type_printing
--         ON public.card_variant (card_id, variant_type_id, printing_profile_id)
--      WHERE printing_profile_id IS NOT NULL;
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
