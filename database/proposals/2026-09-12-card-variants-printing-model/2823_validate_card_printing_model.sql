/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2823 - Validate Card Printing Model
Versão......: 1.2
Status......: VALIDATED / PASS — EXECUTADO EM 2026-09-12
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-MODEL-STAGING-01 — GATE-A-01 (§19)
               + GATE-A-CORRECTION-01 (§6) (v1.1)
               + HARNESS-CORRECTION-01 (§3) (v1.2)
Valida......: Queries 2165, 2166 v1.1, 2167, 2168 v1.1, 2169, 2170, 2171

v1.2 (HARNESS-CORRECTION-01) sobre a v1.1:
- S2.05 era DEPENDENTE DE COLLATION e deu FALSO FAIL contra um banco
  correto. A assercao comparava uma unica string montada com
  string_agg(... ORDER BY x): em datcollate 'en_US.UTF-8' a pontuacao e
  desprezada na primeira passada, entao 'SHADOWLESS_FIRST_EDITION=...'
  ordena ANTES de 'SHADOWLESS=...', ao contrario do que ocorreria em
  COLLATE "C". A composicao do banco estava exata; o comparador e que
  nao era.
- Corrigido NAO por COLLATE "C" — isso apenas trocaria uma dependencia de
  locale por outra. A composicao e um CONJUNTO relacional, entao a prova
  passa a ser SET-BASED: EXCEPT nos dois sentidos, mais contagem de pares
  e de profiles distintos. Independente de collation, de ordem, de
  display_order e da ordem fisica de INSERT.
- SEPARACAO DE RESPONSABILIDADES: S2.05 prova a COMPOSICAO SEMANTICA
  (quais traits cada profile tem). traits_signature continua provado
  SEPARADAMENTE por S2.06/07/08/09 (selamento, igualdade com recalculo,
  ordenacao canonica, unicidade) e por S1.14/S1.16 (tipo e forma). As
  duas responsabilidades nao voltam a se misturar.
- Nenhuma logica de modelo mudou. 2165-2171 permanecem intocadas.

v1.1 (GATE-A-CORRECTION-01) sobre a v1.0:
- S5b deixou de ser "limite documentado" e virou assercao REAL: Profile
  vazio DEVE abortar no COMMIT (Secao 5, caso B).
- Toda referencia a traits_fingerprint/md5 foi substituida por
  traits_signature UUID[], com prova explicita de que NAO ha hash.
- Novos casos: composicoes diferentes ({A,B} vs {A,C}) ambas aceitas;
  selo nao destravavel por UPDATE; idempotencia da seed reexecutada de
  verdade dentro de transacao revertida.

-------------------------------------------------------------------------------
SEMANTICA DE EXECUCAO — LEIA ANTES DE RODAR
-------------------------------------------------------------------------------
TODAS as Secoes sao FAIL-CLOSED: cada assercao e um RAISE EXCEPTION dentro
de um bloco DO. PASS = ausencia de excecao; FAIL = excecao nomeando o caso.

As Secoes 4 a 7 rodam dentro de BEGIN ... ROLLBACK: criam fixtures e as
descartam. NADA e persistido. A Secao 8 prova zero residuo.

Para provar comportamento DEFERIDO sem encerrar a Secao, os casos usam
SET CONSTRAINTS ALL IMMEDIATE dentro de um sub-bloco com EXCEPTION — e a
forma canonica de forcar a avaliacao de um CONSTRAINT TRIGGER DEFERRED.
Cada caso desses vive em sua propria transacao revertida.

ATENCAO — o MCP do Supabase NAO propaga RAISE NOTICE.

BASELINE AUTORIZADO (medido em 2026-09-12, pos BLOCK-01):
    card_variant = 7002 · Variant Types = 79 · mappings = 69
    NEEDS_REVIEW/PENDING = 505 · jobs STAGED = 4
Se o baseline legitimo mudar: STOP / reauditar. NAO suavizar.
===============================================================================
*/

-- =============================================================================
-- SECAO 1 — SCHEMA (read-only, FAIL-CLOSED)
-- =============================================================================
DO $s1$
DECLARE
    v_n INTEGER;
BEGIN
    SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind='r'
       AND c.relname IN ('card_printing_trait','card_printing_profile','card_printing_profile_trait');
    IF v_n <> 3 THEN RAISE EXCEPTION 'S1.01 FALHOU: esperadas 3 tabelas do dominio PRINTING, encontradas %.', v_n; END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='card_variant'
           AND column_name='printing_profile_id'
           AND is_nullable='YES' AND column_default IS NULL AND data_type='uuid'
    ) THEN RAISE EXCEPTION 'S1.02 FALHOU: card_variant.printing_profile_id ausente, NOT NULL, com default ou de tipo errado.'; END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid='public.card_variant'::regclass
           AND conname='fk_card_variant_printing_profile'
           AND confdeltype='r' AND confupdtype='r'
    ) THEN RAISE EXCEPTION 'S1.03 FALHOU: FK fk_card_variant_printing_profile ausente ou sem RESTRICT.'; END IF;

    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.card_printing_profile_trait'::regclass
       AND contype='f' AND array_length(conkey,1)=2;
    IF v_n <> 2 THEN RAISE EXCEPTION 'S1.04 FALHOU: esperadas 2 FKs compostas na N:N, encontradas %.', v_n; END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid='public.card_printing_profile_trait'::regclass
           AND contype='p' AND array_length(conkey,1)=2
    ) THEN RAISE EXCEPTION 'S1.05 FALHOU: PK composta (profile_id, trait_id) ausente.'; END IF;

    SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relrowsecurity
       AND c.relname IN ('card_printing_trait','card_printing_profile','card_printing_profile_trait');
    IF v_n <> 3 THEN RAISE EXCEPTION 'S1.06 FALHOU: RLS habilitado em apenas % das 3 tabelas.', v_n; END IF;

    IF EXISTS (
        SELECT 1 FROM information_schema.role_table_grants
         WHERE table_schema='public'
           AND table_name IN ('card_printing_trait','card_printing_profile','card_printing_profile_trait')
           AND NOT (grantee='postgres' OR (grantee='authenticated' AND privilege_type='SELECT'))
    ) THEN RAISE EXCEPTION 'S1.07 FALHOU: grant inesperado nas tabelas do dominio PRINTING.'; END IF;

    -- S1.08 — indices do modelo (v1.1: signature, nao fingerprint).
    SELECT count(*) INTO v_n FROM pg_indexes
     WHERE schemaname='public' AND indexname IN (
        'uq_card_printing_profile_game_signature',
        'ix_card_printing_profile_trait_trait_id',
        'ix_card_variant_printing_profile_id');
    IF v_n <> 3 THEN RAISE EXCEPTION 'S1.08 FALHOU: esperados 3 indices do modelo, encontrados %.', v_n; END IF;

    -- S1.09 — a UNIQUE CONSTRAINT antiga de card_variant foi removida.
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE conrelid='public.card_variant'::regclass AND conname='uq_card_variant_card_type')
    THEN RAISE EXCEPTION 'S1.09 FALHOU: uq_card_variant_card_type ainda existe — a troca de unicidade nao ocorreu.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_card_variant_card_type_no_printing'
                    AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%printing_profile_id IS NULL%')
    THEN RAISE EXCEPTION 'S1.10a FALHOU: indice parcial do universo SEM perfil ausente ou sem predicado.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_card_variant_card_type_printing'
                    AND indexdef LIKE '%UNIQUE%' AND indexdef LIKE '%printing_profile_id IS NOT NULL%')
    THEN RAISE EXCEPTION 'S1.10b FALHOU: indice parcial do universo COM perfil ausente ou sem predicado.'; END IF;

    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.card_variant'::regclass
       AND conname IN ('card_variant_pkey','uq_card_variant_card_order',
                       'uq_card_variant_id_card','ck_card_variant_order_positive',
                       'fk_card_variant_card','fk_card_variant_variant_type');
    IF v_n <> 6 THEN RAISE EXCEPTION 'S1.11 FALHOU: apenas % das 6 constraints preexistentes de card_variant sobreviveram.', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                    AND indexname='uq_card_variant_one_default_per_card')
    THEN RAISE EXCEPTION 'S1.11b FALHOU: uq_card_variant_one_default_per_card desapareceu.'; END IF;

    -- S1.12 — os quatro triggers do modelo (v1.1: o deferido migrou para o
    -- Profile e surgiu o guard de escrita do selo).
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid='public.card_printing_profile'::regclass
                      AND tgname='trg_card_printing_profile_seal'
                      AND tgconstraint <> 0 AND tgdeferrable AND tginitdeferred)
    THEN RAISE EXCEPTION 'S1.12a FALHOU: trigger de selamento ausente ou nao e CONSTRAINT TRIGGER DEFERRABLE INITIALLY DEFERRED sobre card_printing_profile.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid='public.card_printing_profile_trait'::regclass
                      AND tgname='trg_card_printing_profile_trait_immutable')
    THEN RAISE EXCEPTION 'S1.12b FALHOU: trigger de imutabilidade da N:N ausente.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid='public.card_printing_profile'::regclass
                      AND tgname='trg_card_printing_profile_signature_write')
    THEN RAISE EXCEPTION 'S1.12c FALHOU: trigger de escrita do selo ausente.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger
                    WHERE tgrelid='public.card_variant'::regclass
                      AND tgname='trg_card_variant_printing_profile_game')
    THEN RAISE EXCEPTION 'S1.12d FALHOU: trigger de same-Game em card_variant ausente.'; END IF;

    -- S1.13 — as quatro funcoes de guard sao SECURITY DEFINER, search_path travado.
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='internal' AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
       AND p.proname IN ('seal_printing_profile_composition',
                         'enforce_printing_profile_composition_immutable',
                         'enforce_printing_profile_signature_write',
                         'enforce_card_variant_printing_profile_game');
    IF v_n <> 4 THEN RAISE EXCEPTION 'S1.13 FALHOU: apenas % das 4 funcoes de guard sao SECURITY DEFINER com search_path vazio.', v_n; END IF;

    -- S1.14 (v1.1) — traits_signature e UUID[], NAO texto/hash.
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='card_printing_profile'
           AND column_name='traits_signature' AND data_type='ARRAY' AND udt_name='_uuid'
    ) THEN RAISE EXCEPTION 'S1.14a FALHOU: traits_signature nao e UUID[].'; END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='card_printing_profile'
           AND column_name='traits_fingerprint'
    ) THEN RAISE EXCEPTION 'S1.14b FALHOU: coluna traits_fingerprint (md5) ainda existe — a v1.0 nao foi substituida.'; END IF;

    -- S1.15 (v1.1) — NENHUM guard usa hash como autoridade.
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='internal'
           AND p.proname IN ('seal_printing_profile_composition',
                             'enforce_printing_profile_signature_write')
           AND (p.prosrc ILIKE '%md5(%' OR p.prosrc ILIKE '%sha256(%' OR p.prosrc ILIKE '%digest(%')
    ) THEN RAISE EXCEPTION 'S1.15 FALHOU: guard de composicao usa hash — integridade deve ser por igualdade exata.'; END IF;

    -- S1.16 (v1.1) — CHECKs de forma da assinatura.
    SELECT count(*) INTO v_n FROM pg_constraint
     WHERE conrelid='public.card_printing_profile'::regclass
       AND conname IN ('ck_card_printing_profile_signature_not_empty',
                       'ck_card_printing_profile_signature_shape');
    IF v_n <> 2 THEN RAISE EXCEPTION 'S1.16 FALHOU: CHECKs de forma da assinatura ausentes (%/2).', v_n; END IF;
END;
$s1$;

SELECT 'SECAO 1 — SCHEMA: 16 grupos de assercao PASS' AS resumo;


-- =============================================================================
-- SECAO 2 — SEED (read-only, FAIL-CLOSED)
-- =============================================================================
DO $s2$
DECLARE
    v_game UUID;
    v_n INTEGER;
    v_bad TEXT;
    -- v1.2 — contadores da prova set-based de S2.05.
    v_missing  INTEGER;
    v_extra    INTEGER;
    v_pairs    INTEGER;
    v_profiles INTEGER;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    IF v_game IS NULL THEN RAISE EXCEPTION 'S2.00 FALHOU: Game POKEMON nao encontrado.'; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id=v_game;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S2.01 FALHOU: % traits, esperados 5.', v_n; END IF;

    SELECT string_agg(code, ',' ORDER BY code) INTO v_bad
      FROM public.card_printing_trait WHERE game_id=v_game;
    IF v_bad <> 'COPYRIGHT_1999_2000,FIRST_EDITION,RED_CHEEK,SHADOWLESS,UNLIMITED' THEN
        RAISE EXCEPTION 'S2.02 FALHOU: conjunto de traits inesperado (%).', v_bad;
    END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_profile WHERE game_id=v_game;
    IF v_n <> 6 THEN RAISE EXCEPTION 'S2.03 FALHOU: % profiles, esperados 6.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_profile_trait WHERE game_id=v_game;
    IF v_n <> 10 THEN RAISE EXCEPTION 'S2.04 FALHOU: % vinculos, esperados 10.', v_n; END IF;

    -- ------------------------------------------------------------------
    -- S2.05 (v1.2) — COMPOSICAO SEMANTICA, prova SET-BASED.
    --
    -- A composicao e um CONJUNTO relacional de pares
    -- (profile_code, trait_code). A prova e por EXCEPT nos DOIS sentidos,
    -- mais contagem — nunca por igualdade de string agregada.
    --
    -- Por que NAO string_agg: qualquer concatenacao ordenada depende do
    -- datcollate do banco. Em 'en_US.UTF-8' a pontuacao e ignorada na
    -- primeira passada e a ordem difere de COLLATE "C". Isso produziu um
    -- FALSO FAIL na v1.1 contra um banco correto. COLLATE "C" nao e a
    -- correcao — apenas trocaria uma dependencia de locale por outra.
    --
    -- Esta forma e independente de: collation, ordem de agregacao,
    -- display_order e ordem fisica de INSERT.
    --
    -- ESCOPO: prova QUAIS traits cada profile tem. NAO prova
    -- traits_signature — isso e S2.06/07/08/09 e S1.14/S1.16.
    -- ------------------------------------------------------------------
    WITH expected(profile_code, trait_code) AS (
        VALUES
            ('UNLIMITED',                          'UNLIMITED'),
            ('SHADOWLESS',                         'SHADOWLESS'),
            ('SHADOWLESS_FIRST_EDITION',           'SHADOWLESS'),
            ('SHADOWLESS_FIRST_EDITION',           'FIRST_EDITION'),
            ('COPYRIGHT_1999_2000',                'COPYRIGHT_1999_2000'),
            ('SHADOWLESS_RED_CHEEK',               'SHADOWLESS'),
            ('SHADOWLESS_RED_CHEEK',               'RED_CHEEK'),
            ('SHADOWLESS_RED_CHEEK_FIRST_EDITION', 'SHADOWLESS'),
            ('SHADOWLESS_RED_CHEEK_FIRST_EDITION', 'RED_CHEEK'),
            ('SHADOWLESS_RED_CHEEK_FIRST_EDITION', 'FIRST_EDITION')
    ),
    actual(profile_code, trait_code) AS (
        SELECT p.code::TEXT, t.code::TEXT
          FROM public.card_printing_profile p
          JOIN public.card_printing_profile_trait pt ON pt.profile_id = p.id
          JOIN public.card_printing_trait        t  ON t.id = pt.trait_id
         WHERE p.game_id = v_game
    )
    SELECT
        -- A: esperado que o banco NAO tem (par faltando)
        (SELECT count(*) FROM (SELECT * FROM expected EXCEPT SELECT * FROM actual) a),
        -- B: que o banco tem e NAO era esperado (par sobrando)
        (SELECT count(*) FROM (SELECT * FROM actual EXCEPT SELECT * FROM expected) b),
        -- C: total de pares
        (SELECT count(*) FROM actual),
        -- D: profiles distintos representados
        (SELECT count(DISTINCT profile_code) FROM actual)
      INTO v_missing, v_extra, v_pairs, v_profiles;

    IF v_missing <> 0 THEN
        RAISE EXCEPTION 'S2.05a FALHOU: % par(es) (profile, trait) ratificado(s) AUSENTE(S) no banco.', v_missing;
    END IF;
    IF v_extra <> 0 THEN
        RAISE EXCEPTION 'S2.05b FALHOU: % par(es) (profile, trait) EXCEDENTE(S) — composicao alem do ratificado.', v_extra;
    END IF;
    IF v_pairs <> 10 THEN
        RAISE EXCEPTION 'S2.05c FALHOU: % pares de composicao, esperados 10.', v_pairs;
    END IF;
    IF v_profiles <> 6 THEN
        RAISE EXCEPTION 'S2.05d FALHOU: % profiles distintos com composicao, esperados 6.', v_profiles;
    END IF;

    -- S2.06 — os 6 foram SELADOS pelo trigger deferido.
    SELECT count(*) INTO v_n FROM public.card_printing_profile
     WHERE game_id=v_game AND traits_signature IS NOT NULL;
    IF v_n <> 6 THEN RAISE EXCEPTION 'S2.06 FALHOU: % de 6 profiles selados.', v_n; END IF;

    -- S2.07 (v1.1) — a assinatura corresponde EXATAMENTE ao conjunto
    -- ordenado da N:N. Recalculo independente, igualdade de array.
    IF EXISTS (
        SELECT 1 FROM public.card_printing_profile p
         WHERE p.game_id = v_game
           AND p.traits_signature IS DISTINCT FROM (
               SELECT ARRAY(SELECT pt.trait_id FROM public.card_printing_profile_trait pt
                             WHERE pt.profile_id = p.id ORDER BY pt.trait_id))
    ) THEN RAISE EXCEPTION 'S2.07 FALHOU: traits_signature divergente do conjunto real.'; END IF;

    -- S2.08 (v1.1) — a assinatura esta ORDENADA ascendente.
    IF EXISTS (
        SELECT 1 FROM public.card_printing_profile p
         WHERE p.traits_signature IS NOT NULL
           AND p.traits_signature IS DISTINCT FROM
               (SELECT ARRAY(SELECT u FROM unnest(p.traits_signature) u ORDER BY u))
    ) THEN RAISE EXCEPTION 'S2.08 FALHOU: traits_signature nao esta ordenada ascendente.'; END IF;

    -- S2.09 (v1.1) — nenhuma assinatura duplicada.
    IF EXISTS (
        SELECT 1 FROM public.card_printing_profile WHERE traits_signature IS NOT NULL
         GROUP BY game_id, traits_signature HAVING count(*) > 1
    ) THEN RAISE EXCEPTION 'S2.09 FALHOU: duas assinaturas identicas no mesmo Game.'; END IF;

    -- S2.10 — same-Game em 100% dos vinculos.
    IF EXISTS (
        SELECT 1 FROM public.card_printing_profile_trait pt
          JOIN public.card_printing_profile p ON p.id = pt.profile_id
          JOIN public.card_printing_trait   t ON t.id = pt.trait_id
         WHERE p.game_id <> pt.game_id OR t.game_id <> pt.game_id
    ) THEN RAISE EXCEPTION 'S2.10 FALHOU: vinculo cross-game na seed.'; END IF;

    -- S2.11 — nenhum profile vazio sobreviveu.
    IF EXISTS (
        SELECT 1 FROM public.card_printing_profile p
         WHERE NOT EXISTS (SELECT 1 FROM public.card_printing_profile_trait pt WHERE pt.profile_id = p.id)
    ) THEN RAISE EXCEPTION 'S2.11 FALHOU: existe Profile sem nenhum trait.'; END IF;

    -- S2.12 — nada fora de POKEMON.
    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE game_id <> v_game;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S2.12a FALHOU: % traits fora do Game POKEMON.', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_profile WHERE game_id <> v_game;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S2.12b FALHOU: % profiles fora do Game POKEMON.', v_n; END IF;
END;
$s2$;

SELECT 'SECAO 2 — SEED: 5/6/10 exatos, composicao set-based exata, 6 selados, assinatura exata PASS' AS resumo;


-- =============================================================================
-- SECAO 3 — LEGADO (read-only, FAIL-CLOSED)
-- =============================================================================
DO $s3$
DECLARE
    v_n BIGINT;
BEGIN
    SELECT count(*) INTO v_n FROM public.card_variant;
    IF v_n <> 7002 THEN RAISE EXCEPTION 'S3.01 FALHOU: card_variant = %, baseline = 7002. STOP / reauditar.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant WHERE printing_profile_id IS NOT NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S3.02 FALHOU: % card_variant com perfil — esta migration nao preenche nenhuma.', v_n; END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant WHERE printing_profile_id IS NULL
                GROUP BY card_id, variant_type_id HAVING count(*) > 1)
    THEN RAISE EXCEPTION 'S3.03 FALHOU: duplicidade (card_id, variant_type_id) no universo sem perfil.'; END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant GROUP BY card_id, variant_order HAVING count(*) > 1)
    THEN RAISE EXCEPTION 'S3.04a FALHOU: duplicidade (card_id, variant_order).'; END IF;
    SELECT count(*) INTO v_n FROM public.card_variant WHERE is_default;
    IF v_n <> 927 THEN RAISE EXCEPTION 'S3.04b FALHOU: % defaults, baseline = 927.', v_n; END IF;
    IF EXISTS (SELECT 1 FROM public.card_variant WHERE variant_order IS NULL OR variant_order < 1)
    THEN RAISE EXCEPTION 'S3.04c FALHOU: variant_order invalido.'; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant_type t
      JOIN public.game g ON g.id = t.game_id AND g.code='POKEMON';
    IF v_n <> 79 THEN RAISE EXCEPTION 'S3.05 FALHOU: % Variant Types, baseline = 79.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant_type_external_mapping;
    IF v_n <> 69 THEN RAISE EXCEPTION 'S3.06 FALHOU: % mappings, baseline = 69.', v_n; END IF;

    IF EXISTS (SELECT 1 FROM public.card_variant_type_external_mapping m
                WHERE NOT EXISTS (SELECT 1 FROM public.card_variant_type t WHERE t.id = m.variant_type_id))
    THEN RAISE EXCEPTION 'S3.07a FALHOU: mapping apontando para Variant Type inexistente.'; END IF;
    SELECT count(*) INTO v_n FROM public.card_variant_type_external_mapping WHERE external_subtype IS NOT NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S3.07b FALHOU: % mappings com external_subtype — este Gate nao cria routing.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status='STAGED' AND r.validation_status='NEEDS_REVIEW'
       AND r.decision_status='PENDING' AND r.persistence_status='PENDING';
    IF v_n <> 505 THEN RAISE EXCEPTION 'S3.08 FALHOU: % rows NEEDS_REVIEW, baseline = 505.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_variant_import_job WHERE status='STAGED';
    IF v_n <> 4 THEN RAISE EXCEPTION 'S3.09 FALHOU: % jobs STAGED, baseline = 4.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.catalog_variant_import_row r
      JOIN public.catalog_variant_import_job j ON j.id = r.job_id
     WHERE j.status='STAGED' AND r.validation_status='VALID' AND r.decision_status='PENDING';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S3.10 FALHOU: % rows VALID/PENDING, esperado 0.', v_n; END IF;
END;
$s3$;

SELECT 'SECAO 3 — LEGADO: 7002 / 79 / 69 / 505 / 4 intactos PASS' AS resumo;


-- =============================================================================
-- SECAO 4 — UNICIDADE DE CARD_VARIANT (transacional, revertida, FAIL-CLOSED)
-- =============================================================================
BEGIN;

DO $s4$
DECLARE
    v_game UUID; v_card UUID; v_type UUID; v_p2 UUID; v_p3 UUID; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';

    SELECT c.id INTO v_card
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id AND e.game_id = v_game
    WHERE c.is_active
      AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id)
    ORDER BY c.id LIMIT 1;
    IF v_card IS NULL THEN RAISE EXCEPTION 'S4.FIXTURE: nenhuma Card POKEMON ativa sem variantes encontrada.'; END IF;

    SELECT id INTO v_type FROM public.card_variant_type WHERE game_id=v_game AND code='STANDARD';
    SELECT id INTO v_p2 FROM public.card_printing_profile WHERE game_id=v_game AND code='SHADOWLESS';
    SELECT id INTO v_p3 FROM public.card_printing_profile WHERE game_id=v_game AND code='SHADOWLESS_FIRST_EDITION';
    IF v_type IS NULL OR v_p2 IS NULL OR v_p3 IS NULL THEN
        RAISE EXCEPTION 'S4.FIXTURE: STANDARD / SHADOWLESS / SHADOWLESS_FIRST_EDITION nao encontrados.';
    END IF;

    -- S4.1 — sem perfil: primeira insercao aceita.
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order)
    VALUES (v_card, v_type, 1);

    -- S4.2 — sem perfil: duplicata REJEITADA.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order)
        VALUES (v_card, v_type, 2);
    EXCEPTION WHEN unique_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S4.2 FALHOU: duplicata sem perfil foi aceita.'; END IF;

    -- S4.3 — mesma Card + mesmo Type + perfis DIFERENTES: PERMITIDO.
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id)
    VALUES (v_card, v_type, 2, v_p2);
    INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id)
    VALUES (v_card, v_type, 3, v_p3);
    IF (SELECT count(*) FROM public.card_variant WHERE card_id=v_card) <> 3 THEN
        RAISE EXCEPTION 'S4.3 FALHOU: esperadas 3 variantes.';
    END IF;

    -- S4.4 — MESMO perfil: REJEITADO.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id)
        VALUES (v_card, v_type, 4, v_p2);
    EXCEPTION WHEN unique_violation THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S4.4 FALHOU: duplicata do mesmo perfil foi aceita.'; END IF;

    -- S4.5 — nenhuma nasceu default.
    IF EXISTS (SELECT 1 FROM public.card_variant WHERE card_id=v_card AND is_default) THEN
        RAISE EXCEPTION 'S4.5 FALHOU: variante nova nasceu com is_default = TRUE.';
    END IF;
END;
$s4$;

SELECT 'SECAO 4 — UNICIDADE: 5 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 5A — PROFILE VAZIO E FAIL-CLOSED  (§3 do GATE-A-CORRECTION-01)
-- =============================================================================
BEGIN;

DO $s5a$
DECLARE
    v_game UUID; v_new UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';

    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
        VALUES (v_game, 'HARNESS_EMPTY', 'Harness — sem traits', 9001)
        RETURNING id INTO v_new;
        -- NENHUM vinculo de proposito.
        SET CONSTRAINTS ALL IMMEDIATE;   -- forca o COMMIT logico do deferido
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%EMPTY_COMPOSITION%';
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S5A.1 FALHOU: Profile sem nenhum trait chegou ao COMMIT (msg: %).', v_msg;
    END IF;
END;
$s5a$;

SELECT 'SECAO 5A — PROFILE VAZIO: rejeitado no COMMIT PASS' AS resumo;

ROLLBACK;


-- Secao 5A.2 — criar e REMOVER o profile na mesma transacao nao deve gerar
-- falso positivo.
BEGIN;

DO $s5a2$
DECLARE
    v_game UUID; v_new UUID; v_msg TEXT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
    VALUES (v_game, 'HARNESS_TRANSIENT', 'Harness — transitorio', 9002)
    RETURNING id INTO v_new;
    DELETE FROM public.card_printing_profile WHERE id = v_new;
    BEGIN
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S5A.2 FALHOU: criar+remover na mesma transacao gerou falso positivo (msg: %).', v_msg;
    END;
END;
$s5a2$;

SELECT 'SECAO 5A.2 — CRIAR+REMOVER: sem falso positivo PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 5B — COMPOSICAO UNICA, IGUALDADE EXATA (transacional, revertida)
-- =============================================================================
BEGIN;

DO $s5b$
DECLARE
    v_game UUID; v_new UUID; v_sl UUID; v_fe UUID; v_rc UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_sl FROM public.card_printing_trait WHERE game_id=v_game AND code='SHADOWLESS';
    SELECT id INTO v_fe FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';
    SELECT id INTO v_rc FROM public.card_printing_trait WHERE game_id=v_game AND code='RED_CHEEK';

    -- S5B.1 — conjunto JA EXISTENTE ({SHADOWLESS, FIRST_EDITION} = P3),
    -- inserido em ORDEM INVERSA e com code diferente: REJEITADO.
    -- Prova simultaneamente: independencia de ordem + independencia do code.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
        VALUES (v_game, 'HARNESS_DUPE_SET', 'Harness — conjunto duplicado', 9003)
        RETURNING id INTO v_new;
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_new, v_fe, v_game), (v_new, v_sl, v_game);   -- ordem inversa
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := TRUE;
    END;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'S5B.1 FALHOU: Profile com conjunto de traits duplicado foi aceito.';
    END IF;
END;
$s5b$;

SELECT 'SECAO 5B — CONJUNTO DUPLICADO (ordem inversa, code diferente): rejeitado PASS' AS resumo;

ROLLBACK;


-- Secao 5C — composicoes DIFERENTES sao ambas aceitas: {A,B} != {A,C}.
BEGIN;

DO $s5c$
DECLARE
    v_game UUID; v_x UUID; v_y UUID; v_sl UUID; v_un UUID; v_cp UUID; v_msg TEXT;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_sl FROM public.card_printing_trait WHERE game_id=v_game AND code='SHADOWLESS';
    SELECT id INTO v_un FROM public.card_printing_trait WHERE game_id=v_game AND code='UNLIMITED';
    SELECT id INTO v_cp FROM public.card_printing_trait WHERE game_id=v_game AND code='COPYRIGHT_1999_2000';

    BEGIN
        INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
        VALUES (v_game, 'HARNESS_SET_AB', 'Harness — {SHADOWLESS, UNLIMITED}', 9004)
        RETURNING id INTO v_x;
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_x, v_sl, v_game), (v_x, v_un, v_game);

        INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
        VALUES (v_game, 'HARNESS_SET_AC', 'Harness — {SHADOWLESS, COPYRIGHT}', 9005)
        RETURNING id INTO v_y;
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_y, v_sl, v_game), (v_y, v_cp, v_game);

        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S5C.1 FALHOU: composicoes DIFERENTES foram rejeitadas (msg: %).', v_msg;
    END;

    -- Os dois foram selados, com assinaturas distintas.
    IF (SELECT traits_signature FROM public.card_printing_profile WHERE id=v_x)
       IS NOT DISTINCT FROM
       (SELECT traits_signature FROM public.card_printing_profile WHERE id=v_y) THEN
        RAISE EXCEPTION 'S5C.2 FALHOU: conjuntos diferentes produziram a mesma assinatura.';
    END IF;
    IF (SELECT traits_signature FROM public.card_printing_profile WHERE id=v_x) IS NULL
       OR (SELECT traits_signature FROM public.card_printing_profile WHERE id=v_y) IS NULL THEN
        RAISE EXCEPTION 'S5C.3 FALHOU: algum dos dois nao foi selado.';
    END IF;
END;
$s5c$;

SELECT 'SECAO 5C — COMPOSICOES DIFERENTES: ambas aceitas, assinaturas distintas PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 6 — SELAMENTO / IMUTABILIDADE (transacional, revertida, FAIL-CLOSED)
-- =============================================================================
BEGIN;

DO $s6$
DECLARE
    v_game UUID; v_p2 UUID; v_fe UUID; v_sl UUID; v_new UUID; v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_p2 FROM public.card_printing_profile WHERE game_id=v_game AND code='SHADOWLESS';
    SELECT id INTO v_fe FROM public.card_printing_trait WHERE game_id=v_game AND code='FIRST_EDITION';
    SELECT id INTO v_sl FROM public.card_printing_trait WHERE game_id=v_game AND code='SHADOWLESS';

    -- Pre-condicao: P2 esta SELADO.
    IF (SELECT traits_signature FROM public.card_printing_profile WHERE id=v_p2) IS NULL THEN
        RAISE EXCEPTION 'S6.PRE FALHOU: o Profile SHADOWLESS nao esta selado — a seed nao rodou corretamente.';
    END IF;

    -- S6.1 — ADD trait em Profile selado: REJEITADO.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p2, v_fe, v_game);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%COMPOSITION_SEALED%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.1 FALHOU: trait adicionado a Profile selado (msg: %).', v_msg; END IF;

    -- S6.2 — DELETE trait em Profile selado: REJEITADO.
    v_ok := FALSE;
    BEGIN
        DELETE FROM public.card_printing_profile_trait WHERE profile_id=v_p2 AND trait_id=v_sl;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%COMPOSITION_SEALED%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.2 FALHOU: trait removido de Profile selado (msg: %).', v_msg; END IF;

    -- S6.3 — UPDATE de vinculo: SEMPRE rejeitado.
    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_profile_trait SET trait_id=v_fe
         WHERE profile_id=v_p2 AND trait_id=v_sl;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%UPDATE_FORBIDDEN%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.3 FALHOU: UPDATE de vinculo aceito (msg: %).', v_msg; END IF;

    -- S6.4 — DESTRAVAR o selo por UPDATE comum: REJEITADO.
    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_profile SET traits_signature = NULL WHERE id=v_p2;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%SIGNATURE_IMMUTABLE%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.4 FALHOU: o selo foi destravado por UPDATE (msg: %).', v_msg; END IF;

    -- S6.5 — FALSIFICAR o selo por UPDATE comum: REJEITADO.
    v_ok := FALSE;
    BEGIN
        UPDATE public.card_printing_profile SET traits_signature = ARRAY[v_fe] WHERE id=v_p2;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%SIGNATURE_IMMUTABLE%' OR v_msg LIKE '%SIGNATURE_MISMATCH%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S6.5 FALHOU: assinatura falsificada aceita (msg: %).', v_msg; END IF;

    -- S6.6 — reinsercao IDENTICA em Profile selado: ACEITA (idempotencia).
    BEGIN
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_p2, v_sl, v_game)
        ON CONFLICT (profile_id, trait_id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S6.6 FALHOU: reinsercao identica rejeitada — a seed deixaria de ser idempotente (msg: %).', v_msg;
    END;

    -- S6.7 — Profile EM MONTAGEM (signature NULL) aceita composicao.
    BEGIN
        INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
        VALUES (v_game, 'HARNESS_BUILDING', 'Harness — em montagem', 9006)
        RETURNING id INTO v_new;
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_new, v_fe, v_game);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S6.7 FALHOU: composicao bloqueada em Profile ainda nao selado (msg: %).', v_msg;
    END;
END;
$s6$;

SELECT 'SECAO 6 — SELAMENTO: 7 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 6B — IDEMPOTENCIA REAL DA SEED (transacional, revertida)
-- =============================================================================
BEGIN;

DO $s6b$
DECLARE
    v_game UUID; v_msg TEXT; v_t INTEGER; v_p INTEGER; v_l INTEGER;
BEGIN
    SELECT id INTO v_game FROM public.game WHERE code='POKEMON';

    -- Reaplica os tres INSERTs da Query 2169, na integra.
    BEGIN
        INSERT INTO public.card_printing_trait (game_id, code, name, description, display_order)
        SELECT g.id, v.code, v.name, v.description, v.display_order
        FROM public.game g
        CROSS JOIN (VALUES
            ('FIRST_EDITION','1ª Edição',1,'x'), ('SHADOWLESS','Sem Sombra',2,'x'),
            ('UNLIMITED','Tiragem Ilimitada',3,'x'), ('COPYRIGHT_1999_2000','Copyright 1999–2000',4,'x'),
            ('RED_CHEEK','Bochecha Vermelha',5,'x')
        ) AS v(code,name,display_order,description)
        WHERE g.code='POKEMON'
        ON CONFLICT (game_id, code) DO NOTHING;

        INSERT INTO public.card_printing_profile (game_id, code, name, description, display_order)
        SELECT g.id, v.code, v.name, v.description, v.display_order
        FROM public.game g
        CROSS JOIN (VALUES
            ('UNLIMITED','Tiragem Ilimitada',1,'x'), ('SHADOWLESS','Sem Sombra',2,'x'),
            ('SHADOWLESS_FIRST_EDITION','Sem Sombra · 1ª Edição',3,'x'),
            ('COPYRIGHT_1999_2000','Copyright 1999–2000',4,'x'),
            ('SHADOWLESS_RED_CHEEK','Sem Sombra · Bochecha Vermelha',5,'x'),
            ('SHADOWLESS_RED_CHEEK_FIRST_EDITION','Sem Sombra · Bochecha Vermelha · 1ª Edição',6,'x')
        ) AS v(code,name,display_order,description)
        WHERE g.code='POKEMON'
        ON CONFLICT (game_id, code) DO NOTHING;

        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        SELECT p.id, t.id, g.id
        FROM public.game g
        JOIN public.card_printing_profile p ON p.game_id = g.id
        JOIN public.card_printing_trait   t ON t.game_id = g.id
        CROSS JOIN LATERAL (VALUES
            ('UNLIMITED','UNLIMITED'), ('SHADOWLESS','SHADOWLESS'),
            ('SHADOWLESS_FIRST_EDITION','SHADOWLESS'), ('SHADOWLESS_FIRST_EDITION','FIRST_EDITION'),
            ('COPYRIGHT_1999_2000','COPYRIGHT_1999_2000'),
            ('SHADOWLESS_RED_CHEEK','SHADOWLESS'), ('SHADOWLESS_RED_CHEEK','RED_CHEEK'),
            ('SHADOWLESS_RED_CHEEK_FIRST_EDITION','SHADOWLESS'),
            ('SHADOWLESS_RED_CHEEK_FIRST_EDITION','RED_CHEEK'),
            ('SHADOWLESS_RED_CHEEK_FIRST_EDITION','FIRST_EDITION')
        ) AS v(profile_code, trait_code)
        WHERE g.code='POKEMON' AND p.code=v.profile_code AND t.code=v.trait_code
        ON CONFLICT (profile_id, trait_id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S6B.1 FALHOU: reaplicar a seed levantou excecao — nao e idempotente (msg: %).', v_msg;
    END;

    SELECT count(*) INTO v_t FROM public.card_printing_trait;
    SELECT count(*) INTO v_p FROM public.card_printing_profile;
    SELECT count(*) INTO v_l FROM public.card_printing_profile_trait;
    IF v_t <> 5 OR v_p <> 6 OR v_l <> 10 THEN
        RAISE EXCEPTION 'S6B.2 FALHOU: apos reaplicar a seed, %/%/% em vez de 5/6/10.', v_t, v_p, v_l;
    END IF;

    -- Nenhuma assinatura foi alterada pela reaplicacao.
    IF EXISTS (
        SELECT 1 FROM public.card_printing_profile p
         WHERE p.traits_signature IS DISTINCT FROM (
             SELECT ARRAY(SELECT pt.trait_id FROM public.card_printing_profile_trait pt
                           WHERE pt.profile_id = p.id ORDER BY pt.trait_id))
    ) THEN RAISE EXCEPTION 'S6B.3 FALHOU: a reaplicacao alterou alguma assinatura.'; END IF;
END;
$s6b$;

SELECT 'SECAO 6B — IDEMPOTENCIA DA SEED: reaplicada sem falha, 5/6/10 estavel PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 7 — SAME-GAME (transacional, revertida, FAIL-CLOSED)
-- =============================================================================
BEGIN;

DO $s7$
DECLARE
    v_pokemon UUID; v_other UUID; v_card UUID; v_type UUID;
    v_foreign_profile UUID; v_foreign_trait UUID; v_pkm_profile UUID;
    v_msg TEXT; v_ok BOOLEAN;
BEGIN
    SELECT id INTO v_pokemon FROM public.game WHERE code='POKEMON';
    SELECT id INTO v_other FROM public.game WHERE code <> 'POKEMON' ORDER BY code LIMIT 1;
    IF v_other IS NULL THEN
        RAISE EXCEPTION 'S7.FIXTURE: nenhum Game alem de POKEMON — cenario cross-game nao testavel. STOP / reauditar.';
    END IF;

    INSERT INTO public.card_printing_trait (game_id, code, name, display_order)
    VALUES (v_other, 'HARNESS_FOREIGN', 'Harness — outro Game', 9001)
    RETURNING id INTO v_foreign_trait;

    INSERT INTO public.card_printing_profile (game_id, code, name, display_order)
    VALUES (v_other, 'HARNESS_FOREIGN', 'Harness — outro Game', 9001)
    RETURNING id INTO v_foreign_profile;

    INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
    VALUES (v_foreign_profile, v_foreign_trait, v_other);

    -- S7.1 — vinculo CROSS-GAME: rejeitado pela FK COMPOSTA, sem trigger.
    SELECT id INTO v_pkm_profile FROM public.card_printing_profile
     WHERE game_id=v_pokemon AND code='SHADOWLESS';
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_printing_profile_trait (profile_id, trait_id, game_id)
        VALUES (v_pkm_profile, v_foreign_trait, v_pokemon);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S7.1 FALHOU: vinculo cross-game aceito.'; END IF;

    SELECT c.id INTO v_card
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id AND e.game_id = v_pokemon
    WHERE c.is_active
      AND NOT EXISTS (SELECT 1 FROM public.card_variant cv WHERE cv.card_id = c.id)
    ORDER BY c.id LIMIT 1;
    SELECT id INTO v_type FROM public.card_variant_type WHERE game_id=v_pokemon AND code='STANDARD';

    -- S7.2 — card_variant POKEMON com Profile de outro Game: rejeitado.
    v_ok := FALSE;
    BEGIN
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id)
        VALUES (v_card, v_type, 1, v_foreign_profile);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        v_ok := v_msg LIKE '%PRINTING_PROFILE_GAME_MISMATCH%';
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'S7.2 FALHOU: card_variant aceitou Profile de outro Game (msg: %).', v_msg; END IF;

    -- S7.3 — caminho feliz.
    SELECT id INTO v_pkm_profile FROM public.card_printing_profile
     WHERE game_id=v_pokemon AND code='UNLIMITED';
    BEGIN
        INSERT INTO public.card_variant (card_id, variant_type_id, variant_order, printing_profile_id)
        VALUES (v_card, v_type, 1, v_pkm_profile);
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        RAISE EXCEPTION 'S7.3 FALHOU: Profile do mesmo Game foi rejeitado (msg: %).', v_msg;
    END;
END;
$s7$;

SELECT 'SECAO 7 — SAME-GAME: 3 assercoes PASS' AS resumo;

ROLLBACK;


-- =============================================================================
-- SECAO 8 — ZERO RESIDUO (read-only, FAIL-CLOSED)
-- =============================================================================
DO $s8$
DECLARE
    v_n BIGINT;
BEGIN
    SELECT count(*) INTO v_n FROM public.card_printing_trait WHERE code LIKE 'HARNESS%';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S8.1a FALHOU: % trait(s) HARNESS residual(is) — o ROLLBACK nao aconteceu.', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_profile WHERE code LIKE 'HARNESS%';
    IF v_n <> 0 THEN RAISE EXCEPTION 'S8.1b FALHOU: % profile(s) HARNESS residual(is).', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_printing_trait;
    IF v_n <> 5 THEN RAISE EXCEPTION 'S8.2a FALHOU: % traits, esperados 5.', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_profile;
    IF v_n <> 6 THEN RAISE EXCEPTION 'S8.2b FALHOU: % profiles, esperados 6.', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_profile_trait;
    IF v_n <> 10 THEN RAISE EXCEPTION 'S8.2c FALHOU: % vinculos, esperados 10.', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.card_printing_profile WHERE traits_signature IS NOT NULL;
    IF v_n <> 6 THEN RAISE EXCEPTION 'S8.2d FALHOU: % de 6 profiles selados apos o harness.', v_n; END IF;

    SELECT count(*) INTO v_n FROM public.card_variant;
    IF v_n <> 7002 THEN RAISE EXCEPTION 'S8.3a FALHOU: card_variant = %, esperado 7002.', v_n; END IF;
    SELECT count(*) INTO v_n FROM public.card_variant WHERE printing_profile_id IS NOT NULL;
    IF v_n <> 0 THEN RAISE EXCEPTION 'S8.3b FALHOU: % card_variant com perfil apos o harness.', v_n; END IF;
END;
$s8$;

SELECT 'SECAO 8 — ZERO RESIDUO: 3 grupos PASS' AS resumo,
       (SELECT count(*) FROM public.card_printing_trait)         AS traits,
       (SELECT count(*) FROM public.card_printing_profile)       AS profiles,
       (SELECT count(*) FROM public.card_printing_profile_trait) AS links,
       (SELECT count(*) FROM public.card_printing_profile WHERE traits_signature IS NOT NULL) AS selados,
       (SELECT count(*) FROM public.card_variant)                AS card_variant;
