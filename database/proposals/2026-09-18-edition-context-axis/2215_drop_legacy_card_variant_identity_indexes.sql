-- ============================================================================
-- Query 2215 — REMOÇÃO das identidades antigas de card_variant
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.1
-- CORREÇÃO 1 da GATE-A-FINAL-CORRECTION-01
--
-- v1.1 (BATCH11-2215-READINESS-CORRECTION-01, 2026-09-25) — hardening
-- fail-closed adjudicado sobre os achados F1–F6 da
-- BATCH11-2215-READINESS-AUDIT-01:
--   F1  DROP INDEX IF EXISTS removido. Ausencia previa de uma antiga = STOP
--       (PRE_LEGACY_STATE_DIVERGENT), nunca NO-OP.
--   F2  Deliberadamente NAO idempotente: reexecucao apos sucesso = STOP.
--   F3  PASSO 1 prova a assinatura fisica COMPLETA da identidade nova
--       (indice + constraint), nao apenas nome/unique/valid.
--   F4  Nenhuma checagem por pg_class.relname sem schema como autoridade:
--       tudo por to_regclass('public.<nome>') + indrelid = public.card_variant;
--       os nomes esperados sao exigidos no schema public; homonimos em
--       outros schemas NAO sao blocker (CORRECTION-02).
--   F5  Prova terminal por TOPOLOGIA EXATA (conjunto de indices UNIQUE,
--       9 indices saudaveis, ortogonais por definicao exata).
--   F6  Estado previo EXATO das duas antigas provado antes de qualquer DROP.
--   DROPs com schema explicito e RESTRICT explicito. Zero CASCADE.
--   Re-auditoria (BATCH11-2215-V1.1-READINESS-RE-AUDIT-01): removida a
--   exigencia de unicidade GLOBAL do nome de constraint
--   uq_card_variant_identity (PASSO 1 e PASSO 4) — nome de constraint nao e
--   autoridade global; a autoridade e conrelid = public.card_variant +
--   conname + conindid, ja provada. A contagem global so geraria falso STOP
--   por constraint homonima legitima em outra tabela, sem ganho de integridade.
--   Dependencias: a prova olha a direcao de ENTRADA (refobjid = indice antigo,
--   deptype <> 'i'); as dependencias automaticas de SAIDA do proprio indice
--   para as colunas (objid = indice, deptype 'a') nao sao contadas.
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
--   A ordem é: provar o estado exato (nova + duas antigas) -> remover UMA ->
--   provar de novo -> remover a OUTRA -> provar a topologia terminal exata.
--   Em nenhum instante a tabela fica sem constraint de identidade.
--
-- SEM CONCURRENTLY — coerente com 2209 v2.0
--   Locks reais (correcao v1.1 — a v1.0 dizia "por um instante"):
--   cada DROP INDEX normal toma AccessExclusiveLock na tabela
--   public.card_variant e no indice, MANTIDO ATE O COMMIT da transacao.
--   Bloqueia leitura E escrita durante a transacao inteira (milissegundos).
--   Por isso o LIVE PRECHECK exige concorrencia zero antes da execucao.
--   DROP INDEX CONCURRENTLY nao roda dentro de transacao e quebraria a
--   atomicidade dos dois DROPs.
--
-- ATOMICIDADE
--   Um unico BEGIN ... COMMIT. Qualquer RAISE EXCEPTION ou erro apos o DROP 1
--   desfaz o DROP 1; apos o DROP 2, desfaz os dois. Nunca persiste estado com
--   apenas uma antiga removida.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- PRE-CONDICAO FAIL-CLOSED: estado EXATO esperado apos a 2209, e nada alem.
DO $pre2215$
DECLARE
    v_tbl oid := to_regclass('public.card_variant');
    v_new oid := to_regclass('public.uq_card_variant_identity');
    v_np  oid := to_regclass('public.uq_card_variant_card_type_no_printing');
    v_p   oid := to_regclass('public.uq_card_variant_card_type_printing');
    v_n   int;
BEGIN
    IF v_tbl IS NULL THEN
        RAISE EXCEPTION 'PRE_TABLE_MISSING: public.card_variant ausente.';
    END IF;

    -- (a) prova agregada ESCOPADA ao schema public: os tres nomes de indice
    --     esperados existem em public. Homonimos em OUTROS schemas nao sao
    --     blocker (nao interferem em to_regclass('public.…'), nos DROP INDEX
    --     public.… nem em pg_index de public.card_variant). Nome de
    --     CONSTRAINT nao e global: autoridade = conrelid + conname, em (c).
    SELECT count(*) INTO v_n
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname IN ('uq_card_variant_identity',
                         'uq_card_variant_card_type_no_printing',
                         'uq_card_variant_card_type_printing');
    IF v_n <> 3 THEN
        RAISE EXCEPTION 'PRE_NAME_MISSING_IN_PUBLIC: esperado 3 relacoes (nova + 2 antigas) em public; encontrado %.', v_n;
    END IF;

    -- (b) identidade nova — indice: assinatura fisica completa
    IF v_new IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i
         WHERE i.indexrelid = v_new AND i.indrelid = v_tbl
           AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnullsnotdistinct
           AND i.indnatts = 4 AND i.indnkeyatts = 4
           AND i.indpred IS NULL AND i.indexprs IS NULL
           AND (SELECT array_agg(a.attname::text ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['card_id','variant_type_id','printing_profile_id','edition_context_profile_id']
    ) THEN
        RAISE EXCEPTION 'PRE_NEW_IDENTITY_INDEX_INVALID: public.uq_card_variant_identity ausente ou com assinatura divergente. Rode/valide a 2209.';
    END IF;

    -- (c) identidade nova — constraint: exatamente 1, imediata, validada, ligada ao indice
    SELECT count(*) INTO v_n FROM pg_constraint c
     WHERE c.conrelid = v_tbl AND c.conname = 'uq_card_variant_identity'
       AND c.contype = 'u' AND c.convalidated
       AND NOT c.condeferrable AND NOT c.condeferred
       AND c.conindid = v_new;
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'PRE_NEW_IDENTITY_CONSTRAINT_INVALID: esperado 1 constraint u validada/imediata ligada ao indice; encontrado %.', v_n;
    END IF;

    -- (d) as duas antigas: estado previo EXATO (ausencia = ja executada ou divergente)
    IF v_np IS NULL OR v_p IS NULL THEN
        RAISE EXCEPTION 'PRE_LEGACY_STATE_DIVERGENT: identidade antiga ausente (no_printing presente=%, printing presente=%). 2215 ja executada ou estado divergente — STOP, nunca NO-OP.',
              v_np IS NOT NULL, v_p IS NOT NULL;
    END IF;
    SELECT count(*) INTO v_n FROM pg_index i
     WHERE i.indrelid = v_tbl
       AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
       AND i.indexprs IS NULL
       AND (   (i.indexrelid = v_np
                AND pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX uq_card_variant_card_type_no_printing ON public.card_variant USING btree (card_id, variant_type_id) WHERE (printing_profile_id IS NULL)'
                AND pg_get_expr(i.indpred, i.indrelid) = '(printing_profile_id IS NULL)'
                AND (SELECT array_agg(a.attname::text ORDER BY k.o)
                       FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                       JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
                    = ARRAY['card_id','variant_type_id'])
            OR (i.indexrelid = v_p
                AND pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX uq_card_variant_card_type_printing ON public.card_variant USING btree (card_id, variant_type_id, printing_profile_id) WHERE (printing_profile_id IS NOT NULL)'
                AND pg_get_expr(i.indpred, i.indrelid) = '(printing_profile_id IS NOT NULL)'
                AND (SELECT array_agg(a.attname::text ORDER BY k.o)
                       FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                       JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
                    = ARRAY['card_id','variant_type_id','printing_profile_id']));
    IF v_n <> 2 THEN
        RAISE EXCEPTION 'PRE_LEGACY_STATE_DIVERGENT: % de 2 identidades antigas com tabela/definicao/predicado/chaves/flags exatos.', v_n;
    END IF;
    IF (SELECT count(*) FROM pg_constraint WHERE conindid IN (v_np, v_p)) <> 0 THEN
        RAISE EXCEPTION 'PRE_LEGACY_STATE_DIVERGENT: identidade antiga vinculada a pg_constraint.';
    END IF;
    IF (SELECT count(*) FROM pg_depend d
         WHERE d.refclassid = 'pg_class'::regclass
           AND d.refobjid IN (v_np, v_p)
           AND d.deptype <> 'i') <> 0 THEN
        RAISE EXCEPTION 'PRE_LEGACY_STATE_DIVERGENT: dependencia formal nao-interna sobre identidade antiga.';
    END IF;
END $pre2215$;

-- ---------------------------------------------------------------- PASSO 2 ---
-- Remocao da PRIMEIRA antiga. A segunda ainda protege seu proprio universo.
DROP INDEX public.uq_card_variant_card_type_no_printing RESTRICT;

DO $mid2215$
DECLARE
    v_tbl oid := to_regclass('public.card_variant');
    v_new oid := to_regclass('public.uq_card_variant_identity');
BEGIN
    IF to_regclass('public.uq_card_variant_card_type_no_printing') IS NOT NULL THEN
        RAISE EXCEPTION 'DROP_FAILED_1: public.uq_card_variant_card_type_no_printing ainda existe.';
    END IF;
    IF to_regclass('public.uq_card_variant_card_type_printing') IS NULL THEN
        RAISE EXCEPTION 'MID_LEGACY_2_LOST: public.uq_card_variant_card_type_printing desapareceu apos o DROP 1.';
    END IF;
    IF v_new IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i JOIN pg_constraint c ON c.conindid = i.indexrelid
         WHERE i.indexrelid = v_new AND i.indrelid = v_tbl
           AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnullsnotdistinct AND i.indnatts = 4 AND i.indnkeyatts = 4
           AND i.indpred IS NULL AND i.indexprs IS NULL
           AND (SELECT array_agg(a.attname::text ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['card_id','variant_type_id','printing_profile_id','edition_context_profile_id']
           AND c.conrelid = v_tbl AND c.conname = 'uq_card_variant_identity'
           AND c.contype = 'u' AND c.convalidated
           AND NOT c.condeferrable AND NOT c.condeferred
    ) THEN
        RAISE EXCEPTION 'MID_NEW_IDENTITY_INVALID: uq_card_variant_identity perdida ou alterada apos o DROP 1.';
    END IF;
END $mid2215$;

-- ---------------------------------------------------------------- PASSO 3 ---
DROP INDEX public.uq_card_variant_card_type_printing RESTRICT;

-- ---------------------------------------------------------------- PASSO 4 ---
-- PROVA TERMINAL por topologia exata (schema + relacao), nao por contagem
-- generica. Somente a identidade nova permanece; ortogonais intactas.
DO $post2215$
DECLARE
    v_tbl oid := to_regclass('public.card_variant');
    v_new oid := to_regclass('public.uq_card_variant_identity');
    v_set text[];
BEGIN
    IF to_regclass('public.uq_card_variant_card_type_no_printing') IS NOT NULL
       OR to_regclass('public.uq_card_variant_card_type_printing') IS NOT NULL THEN
        RAISE EXCEPTION 'POST_LEGACY_SURVIVED: identidade antiga ainda existe.';
    END IF;

    -- identidade nova: assinatura completa (indice + constraint)
    IF v_new IS NULL OR NOT EXISTS (
        SELECT 1 FROM pg_index i JOIN pg_constraint c ON c.conindid = i.indexrelid
         WHERE i.indexrelid = v_new AND i.indrelid = v_tbl
           AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
           AND i.indnullsnotdistinct AND i.indnatts = 4 AND i.indnkeyatts = 4
           AND i.indpred IS NULL AND i.indexprs IS NULL
           AND (SELECT array_agg(a.attname::text ORDER BY k.o)
                  FROM unnest(i.indkey) WITH ORDINALITY k(att, o)
                  JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.att)
               = ARRAY['card_id','variant_type_id','printing_profile_id','edition_context_profile_id']
           AND c.conrelid = v_tbl AND c.conname = 'uq_card_variant_identity'
           AND c.contype = 'u' AND c.convalidated
           AND NOT c.condeferrable AND NOT c.condeferred
    ) THEN
        RAISE EXCEPTION 'POST_NEW_IDENTITY_INVALID: uq_card_variant_identity perdida ou alterada.';
    END IF;

    -- topologia: exatamente 9 indices em public.card_variant, todos saudaveis
    IF (SELECT count(*) FROM pg_index WHERE indrelid = v_tbl) <> 9
       OR EXISTS (SELECT 1 FROM pg_index WHERE indrelid = v_tbl
                   AND NOT (indisvalid AND indisready AND indislive)) THEN
        RAISE EXCEPTION 'POST_INDEX_TOPOLOGY_DIVERGENT: esperado exatamente 9 indices saudaveis em public.card_variant.';
    END IF;

    -- conjunto EXATO de indices UNIQUE
    SELECT array_agg(c.relname::text ORDER BY c.relname) INTO v_set
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = v_tbl AND i.indisunique;
    IF v_set IS DISTINCT FROM ARRAY['card_variant_pkey','uq_card_variant_card_order',
                                    'uq_card_variant_id_card','uq_card_variant_identity',
                                    'uq_card_variant_one_default_per_card'] THEN
        RAISE EXCEPTION 'POST_UNIQUE_TOPOLOGY_DIVERGENT: %', v_set;
    END IF;

    -- ortogonais: definicao exata + flags + pertencem a public.card_variant
    IF (SELECT count(*) FROM pg_index i
         WHERE i.indrelid = v_tbl
           AND i.indisunique AND i.indisvalid AND i.indisready AND i.indislive
           AND (   (i.indexrelid = to_regclass('public.uq_card_variant_card_order')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX uq_card_variant_card_order ON public.card_variant USING btree (card_id, variant_order)')
                OR (i.indexrelid = to_regclass('public.uq_card_variant_one_default_per_card')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX uq_card_variant_one_default_per_card ON public.card_variant USING btree (card_id) WHERE (is_default = true)')
                OR (i.indexrelid = to_regclass('public.uq_card_variant_id_card')
                    AND pg_get_indexdef(i.indexrelid) = 'CREATE UNIQUE INDEX uq_card_variant_id_card ON public.card_variant USING btree (id, card_id)'))) <> 3 THEN
        RAISE EXCEPTION 'POST_ORTHOGONAL_DIVERGENT: indice ortogonal perdido ou alterado.';
    END IF;
END $post2215$;

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
-- (Historico v1.0: corpo auditado preservado byte a byte; a unica alteracao de
-- armamento foi ROLLBACK; -> COMMIT;. O corpo foi reescrito na v1.1 — ver topo.)
-- A protecao contra execucao prematura e GOVERNANCA (autorizacao de
-- Fabricio + ordem de batches), nao o terminador — mesma decisao ja aceita
-- em R1 para 2203-2211.
-- ============================================================================
COMMIT;
