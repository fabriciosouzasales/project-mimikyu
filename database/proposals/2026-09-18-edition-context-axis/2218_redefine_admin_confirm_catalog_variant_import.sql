-- ============================================================================
-- Query 2218 — public.admin_confirm_catalog_variant_import() v3.0
-- Status: PROPOSTA — NÃO EXECUTADA · Versão 1.0
-- WRITE-PATH-STAGING-01 · itens 1, 2, 4, 5, 8
--
-- BASE: database/schema/2145_..._function.sql v2.0 (CANÔNICA / LIVE, 519 li).
-- Este arquivo é o ESTADO FINAL — corpo inteiro, não patch.
--
-- ----------------------------------------------------------------------------
-- O QUE MUDA — e SÓ isso
-- ----------------------------------------------------------------------------
--   (a) EIXO 3 tri-state: edition_context_profile_id lido com a MESMA
--       disciplina de jsonb_typeof já usada para printing (2145:333-356);
--   (b) MATCHING QUÁDRUPLO com IS NOT DISTINCT FROM nos dois eixos nuláveis;
--   (c) LOCK determinístico: todas as Cards do lote travadas ANTES do loop,
--       em ORDER BY id — elimina deadlock por ordem de aquisição;
--   (d) handler ESPECÍFICO de unique_violation, antes de WHEN OTHERS;
--   (e) writer chamado com SETE argumentos (Query 2217).
--
-- PRESERVADO LITERALMENTE — nada aqui regride:
--   SECURITY DEFINER · search_path='' · REVOKE de PUBLIC · is_admin()
--   c_max_rows = 1000 · GUARDs 1-7 · congelamento do conjunto efetivo
--   STAGED -> CONFIRMING · SKIPPED -> UNCHANGED sem escrita
--   variant_order = MAX+1 por Card · is_default nunca informado
--   recálculo de counters por agregação · audit log condicional
--   assinatura e RETURNS TABLE idênticos · todos os códigos de erro
--
-- ----------------------------------------------------------------------------
-- CONCORRÊNCIA — o desenho aprovado, implementado
-- ----------------------------------------------------------------------------
--   LOCK ......... public.card ... FOR UPDATE, todas as Cards do lote,
--                  ORDER BY id, ANTES do loop.
--   ORDEM ........ id crescente. Dois lotes que se cruzam adquirem na MESMA
--                  ordem ⇒ deadlock impossível por este caminho.
--   RECHECK ...... o matching quádruplo roda DEPOIS do lock. Uma T2 que
--                  esperou T1 enxerga a Variant criada e sai por MATCHED.
--   EXCEPTION .... WHEN unique_violation vem ANTES de WHEN OTHERS:
--                    relê pela identidade de 4 componentes;
--                      achou  ⇒ corrida benigna ⇒ UNCHANGED (indistinguível
--                               do caminho MATCHED normal);
--                      não achou ⇒ erro SISTÊMICO, com código de negócio
--                               CARD_VARIANT_IDENTITY_CONFLICT_UNRESOLVED.
--   O QUE NÃO SE FAZ: usar WHEN OTHERS para engolir 23505. O handler
--   genérico continua existindo (uma row com defeito não derruba o lote),
--   mas ele nunca mais é o primeiro a ver uma violação de identidade.
--
-- ----------------------------------------------------------------------------
-- FRONTEIRA (item 8) — nenhum writer novo reativa histórico
-- ----------------------------------------------------------------------------
--   GUARD 5 (linha 270 da canônica) já recusa job fora de STAGED/CONFIRMING.
--   Nada nesta versão o afrouxa: rows de job CANCELLED/COMPLETED continuam
--   inalcançáveis por este caminho. CONFIRMÁVEL permanece
--   job ∈ (STAGED,CONFIRMING) + PENDING + APPROVED + VALID.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- PASSO 1 ---
-- GATE: a coluna e o writer de 7 argumentos precisam existir.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema='public' AND table_name='card_variant'
           AND column_name='edition_context_profile_id') THEN
        RAISE EXCEPTION 'CONFIRM_V3_BLOCKED: card_variant.edition_context_profile_id ausente. Rode a Query 2208 antes.';
    END IF;
END $$;

-- ---------------------------------------------------------------- PASSO 2 ---
CREATE OR REPLACE FUNCTION public.admin_confirm_catalog_variant_import(
    p_job_id UUID,
    p_row_ids UUID[] DEFAULT NULL
)
RETURNS TABLE (
    inserted_count INTEGER,
    unchanged_count INTEGER,
    failed_count INTEGER,
    pending_count INTEGER,
    job_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    -- Teto de lote por chamada (Query 2164). INALTERADO.
    c_max_rows CONSTANT INTEGER := 1000;

    v_job public.catalog_variant_import_job%ROWTYPE;
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_existing_variant public.card_variant%ROWTYPE;
    v_variant_type_id UUID;
    v_printing_profile_id UUID;
    v_printing_key_type TEXT;
    -- v3.0 — EIXO 3.
    v_edition_context_profile_id UUID;
    v_edition_context_key_type TEXT;
    v_race_variant_id UUID;
    v_error_message TEXT;
    v_match_status TEXT;
    v_result_variant_id UUID;
    v_next_order INTEGER;
    v_pending_rows INTEGER;
    v_failed_rows INTEGER;
    v_decision_pending_rows INTEGER;
    v_final_status TEXT;
    v_card_set_name TEXT;
    v_card_set_code TEXT;
    v_id_count INTEGER;
    v_effective_row_ids UUID[];
BEGIN
    -- GUARD 1 — AUTORIZACAO.
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_FORBIDDEN: apenas administradores podem confirmar uma importação de variantes.';
    END IF;

    -- GUARD 2 — p_job_id obrigatorio.
    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    -- GUARD 3 — FORMA E TETO DE p_row_ids (Query 2164). Validacao pura
    -- de payload: nenhum acesso a tabela, nenhum lock ainda tomado.
    IF p_row_ids IS NOT NULL THEN
        IF array_ndims(p_row_ids) <> 1 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_ARRAY_SHAPE: p_row_ids deve ser um array de uma única dimensão (recebido: % dimensões).', array_ndims(p_row_ids);
        END IF;

        v_id_count := cardinality(p_row_ids);

        IF v_id_count = 0 THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_EMPTY_ROW_IDS: p_row_ids veio vazio. Envie NULL para confirmar todas as linhas elegíveis, ou pelo menos um id.';
        END IF;

        IF v_id_count > c_max_rows THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_TOO_MANY_ROWS: p_row_ids tem % ids, acima do teto de % por chamada. Divida em lotes menores.', v_id_count, c_max_rows;
        END IF;
    END IF;

    -- GUARD 4/5/6 — job existe, está em estado confirmável, e fica
    -- travado para o resto da transação.
    SELECT * INTO v_job FROM public.catalog_variant_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    -- FRONTEIRA OPERACIONAL. Job terminal (CANCELLED/COMPLETED/
    -- COMPLETED_WITH_ERRORS/FAILED) nunca chega ao writer por aqui —
    -- e esta versao NAO afrouxa a regra.
    IF v_job.status NOT IN ('STAGED', 'CONFIRMING') THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_STATUS: o job está em % — só é possível confirmar a partir de STAGED ou CONFIRMING.', v_job.status;
    END IF;

    SELECT name, code INTO v_card_set_name, v_card_set_code
    FROM public.card_set WHERE id = v_job.card_set_id;

    -- GUARD 7 — CONJUNTO EFETIVO CONGELADO (Query 2164). Elimina o
    -- TOCTOU: o que foi contado é exatamente o que será processado.
    IF p_row_ids IS NULL THEN
        v_effective_row_ids := ARRAY(
            SELECT r.id
            FROM public.catalog_variant_import_row r
            WHERE r.job_id = p_job_id
              AND r.persistence_status = 'PENDING'
              AND r.decision_status IN ('APPROVED', 'SKIPPED')
            ORDER BY r.created_at, r.id
            LIMIT c_max_rows + 1
        );

        IF cardinality(v_effective_row_ids) > c_max_rows THEN
            RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_TOO_MANY_ROWS: o job tem mais de % linhas elegíveis. Informe p_row_ids em lotes menores.', c_max_rows;
        END IF;
    ELSE
        v_effective_row_ids := p_row_ids;
    END IF;

    -- =====================================================================
    -- v3.0 — LOCK DETERMINÍSTICO DAS CARDS DO LOTE
    -- ---------------------------------------------------------------------
    -- Travar aqui, em ORDER BY id, resolve duas coisas de uma vez:
    --   1. serializa matching + alocação de variant_order por Card, que é
    --      o par que realmente compete;
    --   2. fixa a ORDEM de aquisição. Dois lotes concorrentes cujas Cards
    --      se cruzam adquirem na mesma sequência — deadlock por ordem
    --      invertida deixa de ser possível por este caminho.
    -- Travar antes do loop (e não dentro) é o que dá a ordem global; dentro
    -- do loop a ordem seria a de created_at, que difere entre lotes.
    -- =====================================================================
    PERFORM 1
       FROM public.card c
      WHERE c.id IN (
            SELECT DISTINCT r.card_id
              FROM public.catalog_variant_import_row r
             WHERE r.job_id = p_job_id
               AND r.id = ANY(v_effective_row_ids))
      ORDER BY c.id
        FOR UPDATE;

    IF v_job.status = 'STAGED' THEN
        UPDATE public.catalog_variant_import_job SET status = 'CONFIRMING' WHERE id = p_job_id;
    END IF;

    FOR v_row IN
        SELECT r.*
        FROM public.catalog_variant_import_row r
        WHERE r.job_id = p_job_id
          AND r.persistence_status = 'PENDING'
          AND r.decision_status IN ('APPROVED', 'SKIPPED')
          AND r.id = ANY(v_effective_row_ids)
        ORDER BY r.created_at
        FOR UPDATE OF r
    LOOP
        BEGIN
            IF v_row.decision_status = 'SKIPPED' THEN
                UPDATE public.catalog_variant_import_row
                    SET persistence_status = 'UNCHANGED'
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            -- decision_status = 'APPROVED' a partir daqui.
            -- Revalidação defensiva: o estado pode, em tese, ter mudado
            -- entre a decisão (Query 2144) e esta confirmação.
            IF v_row.validation_status <> 'VALID' THEN
                RAISE EXCEPTION 'NEEDS_REVIEW_CANNOT_BE_CONFIRMED: linha sem card_variant_type resolvido não pode ser confirmada.';
            END IF;

            v_variant_type_id := NULLIF(v_row.normalized_data->>'variant_type_id', '')::UUID;
            IF v_variant_type_id IS NULL THEN
                RAISE EXCEPTION 'MISSING_VARIANT_TYPE_ID: normalized_data não contém variant_type_id resolvido.';
            END IF;

            -- EIXO IMPRESSÃO — contrato TRI-ESTADO.
            --
            -- jsonb_typeof distingue os tres estados; `->>` nao:
            --   chave ausente -> SQL NULL   (Impressao NAO resolvida)
            --   JSON null     -> 'null'     (resolvido SEM perfil)
            --   string        -> 'string'   (resolvido COM perfil)
            v_printing_key_type := jsonb_typeof(v_row.normalized_data -> 'printing_profile_id');

            IF v_printing_key_type IS NULL THEN
                RAISE EXCEPTION 'PRINTING_NOT_RESOLVED: normalized_data não contém a chave printing_profile_id. Toda linha VALID precisa da chave — resolva o mapeamento de Impressão ou reprocesse a importação.';
            ELSIF v_printing_key_type = 'null' THEN
                v_printing_profile_id := NULL;      -- resolvido SEM perfil, explícito
            ELSIF v_printing_key_type = 'string' THEN
                v_printing_profile_id := (v_row.normalized_data->>'printing_profile_id')::UUID;
            ELSE
                RAISE EXCEPTION 'PRINTING_PROFILE_ID_INVALID_SHAPE: printing_profile_id tem tipo JSON % — esperado null ou string UUID.', v_printing_key_type;
            END IF;

            -- =============================================================
            -- v3.0 — EIXO CONTEXTO DE EDIÇÃO — MESMO contrato TRI-ESTADO.
            -- -------------------------------------------------------------
            -- Simetria deliberada com Impressão: mesma leitura por
            -- jsonb_typeof, mesmos três estados, mesma recusa fail-closed.
            -- Chave ausente é IMPOSSÍVEL para uma linha operacional VALID
            -- (guard trg_cvir_normalized_shape, Query 2214) e só seria
            -- alcançável por escrita direta fora do pipeline. Confirmar
            -- criaria uma Variant sem contexto que talvez devesse ter.
            -- =============================================================
            v_edition_context_key_type := jsonb_typeof(v_row.normalized_data -> 'edition_context_profile_id');

            IF v_edition_context_key_type IS NULL THEN
                RAISE EXCEPTION 'EDITION_CONTEXT_NOT_RESOLVED: normalized_data não contém a chave edition_context_profile_id. Toda linha VALID precisa da chave — resolva o eixo pelo routing (internal.resolve_variant_row_axes) ou reprocesse a importação.';
            ELSIF v_edition_context_key_type = 'null' THEN
                v_edition_context_profile_id := NULL;   -- resolvido SEM contexto
            ELSIF v_edition_context_key_type = 'string' THEN
                v_edition_context_profile_id := (v_row.normalized_data->>'edition_context_profile_id')::UUID;
            ELSE
                RAISE EXCEPTION 'EDITION_CONTEXT_PROFILE_ID_INVALID_SHAPE: edition_context_profile_id tem tipo JSON % — esperado null ou string UUID.', v_edition_context_key_type;
            END IF;

            -- =============================================================
            -- MATCHING QUÁDRUPLO. match_status recalculado contra o
            -- catálogo real — nunca herdado. IS NOT DISTINCT FROM nos DOIS
            -- eixos nuláveis, porque NULL faz parte da identidade:
            -- "sem tiragem" e "sem contexto" são VALORES, não desconhecidos.
            -- Roda DEPOIS do lock da Card — é o recheck da corrida.
            -- =============================================================
            SELECT cv.* INTO v_existing_variant
            FROM public.card_variant cv
            WHERE cv.card_id = v_row.card_id
              AND cv.variant_type_id = v_variant_type_id
              AND cv.printing_profile_id        IS NOT DISTINCT FROM v_printing_profile_id
              AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id
            LIMIT 1;

            IF v_existing_variant.id IS NULL THEN
                v_match_status := 'NEW';
            ELSE
                v_match_status := 'MATCHED';
            END IF;

            IF v_match_status = 'MATCHED' THEN
                -- Já existe: nenhuma escrita. Nunca sobrescreve silenciosamente.
                UPDATE public.catalog_variant_import_row
                    SET match_status = v_match_status,
                        persistence_status = 'UNCHANGED',
                        matched_variant_id = v_existing_variant.id,
                        resulting_variant_id = v_existing_variant.id,
                        error_detail = NULL
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            -- NEW: variant_order é sempre o próximo inteiro livre para o
            -- card_id, calculado só a partir do que já existe em
            -- card_variant — nunca lido da fonte. is_default nunca é
            -- informado (nasce FALSE pelo default da coluna).
            SELECT COALESCE(MAX(variant_order), 0) + 1 INTO v_next_order
            FROM public.card_variant
            WHERE card_id = v_row.card_id;

            -- Writer com SETE argumentos (Query 2217). Identidade completa
            -- já resolvida — o writer não infere nada.
            v_result_variant_id := internal.write_card_variant(
                'CREATE', NULL, v_row.card_id, v_variant_type_id, v_next_order,
                v_printing_profile_id, v_edition_context_profile_id
            );

            UPDATE public.catalog_variant_import_row
                SET match_status = v_match_status,
                    persistence_status = 'INSERTED',
                    matched_variant_id = NULL,
                    resulting_variant_id = v_result_variant_id,
                    error_detail = NULL
                WHERE id = v_row.id;

        -- =================================================================
        -- v3.0 — HANDLER ESPECÍFICO, ANTES do genérico.
        -- WHEN OTHERS nunca mais é o primeiro a ver uma violação de
        -- identidade: sem esta cláusula, uma corrida benigna viraria
        -- persistence_status='FAILED' com SQLSTATE cru no error_detail.
        -- =================================================================
        EXCEPTION
            WHEN unique_violation THEN
                -- Relê pela MESMA identidade de 4 componentes. Com o lock
                -- da Card em mãos, se a linha existe agora é porque outra
                -- transação a criou e commitou antes desta.
                SELECT cv.id INTO v_race_variant_id
                FROM public.card_variant cv
                WHERE cv.card_id = v_row.card_id
                  AND cv.variant_type_id = v_variant_type_id
                  AND cv.printing_profile_id        IS NOT DISTINCT FROM v_printing_profile_id
                  AND cv.edition_context_profile_id IS NOT DISTINCT FROM v_edition_context_profile_id
                LIMIT 1;

                IF v_race_variant_id IS NOT NULL THEN
                    -- CORRIDA BENIGNA. Resultado idêntico ao caminho
                    -- MATCHED normal — indistinguível para a UI, de propósito.
                    UPDATE public.catalog_variant_import_row
                        SET match_status = 'MATCHED',
                            persistence_status = 'UNCHANGED',
                            matched_variant_id = v_race_variant_id,
                            resulting_variant_id = v_race_variant_id,
                            error_detail = NULL
                        WHERE id = v_row.id;
                ELSE
                    -- ERRO SISTÊMICO. A violação veio de OUTRA constraint —
                    -- uq_card_variant_card_order ou one_default_per_card —
                    -- e mascarar isso como "já existia" esconderia um bug
                    -- de alocação de ordem. Vira FAILED com código de
                    -- NEGÓCIO nomeado, nunca 23505 cru.
                    GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
                    UPDATE public.catalog_variant_import_row
                        SET persistence_status = 'FAILED',
                            error_detail = 'CARD_VARIANT_IDENTITY_CONFLICT_UNRESOLVED: violação de unicidade na Card '
                                           || v_row.card_id
                                           || ' não explicada pela identidade de 4 componentes. Detalhe: '
                                           || v_error_message
                        WHERE id = v_row.id;
                END IF;

            WHEN OTHERS THEN
                -- Rede final: uma linha com defeito não derruba o lote.
                -- Inalterado frente à canônica.
                GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
                UPDATE public.catalog_variant_import_row
                    SET persistence_status = 'FAILED', error_detail = v_error_message
                    WHERE id = v_row.id;
        END;
    END LOOP;

    -- Recalcula os contadores do job inteiramente por agregação. INALTERADO.
    UPDATE public.catalog_variant_import_job j
        SET total_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id),
            valid_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND validation_status = 'VALID'),
            rejected_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND decision_status = 'REJECTED'),
            inserted_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'INSERTED'),
            unchanged_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'UNCHANGED'),
            skipped_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND decision_status = 'SKIPPED'),
            failed_rows = (SELECT COUNT(*) FROM public.catalog_variant_import_row WHERE job_id = j.id AND persistence_status = 'FAILED')
        WHERE j.id = p_job_id;

    SELECT COUNT(*)
    INTO v_decision_pending_rows
    FROM public.catalog_variant_import_row
    WHERE job_id = p_job_id
      AND decision_status = 'PENDING';

    SELECT
        COUNT(*) FILTER (WHERE persistence_status = 'PENDING'),
        COUNT(*) FILTER (WHERE persistence_status = 'FAILED')
    INTO v_pending_rows, v_failed_rows
    FROM public.catalog_variant_import_row
    WHERE job_id = p_job_id
      AND decision_status IN ('APPROVED', 'SKIPPED');

    IF v_decision_pending_rows > 0 THEN
        v_final_status := 'STAGED';
    ELSIF v_pending_rows > 0 THEN
        v_final_status := 'CONFIRMING';
    ELSIF v_failed_rows > 0 THEN
        v_final_status := 'COMPLETED_WITH_ERRORS';
    ELSE
        v_final_status := 'COMPLETED';
    END IF;

    UPDATE public.catalog_variant_import_job SET status = v_final_status WHERE id = p_job_id;

    IF v_final_status IN ('COMPLETED', 'COMPLETED_WITH_ERRORS') THEN
        INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
            VALUES (auth.uid(), 'CARD_VARIANT_IMPORT_CONFIRMED', 'CATALOG_VARIANT_IMPORT_JOB', p_job_id,
                    jsonb_build_object(
                        'card_set_id', v_job.card_set_id,
                        'card_set_name', v_card_set_name,
                        'card_set_code', v_card_set_code,
                        'final_status', v_final_status
                    ));
    END IF;

    RETURN QUERY
        SELECT j.inserted_rows, j.unchanged_rows, j.failed_rows, v_pending_rows, j.status
        FROM public.catalog_variant_import_job j
        WHERE j.id = p_job_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) FROM PUBLIC;

-- ---------------------------------------------------------------- PASSO 3 ---
-- POSTCHECK ESTRUTURAL.
DO $$
DECLARE v_sec BOOLEAN; v_cfg TEXT[]; v_src TEXT; v_n INT;
BEGIN
    SELECT p.prosecdef, p.proconfig, p.prosrc INTO v_sec, v_cfg, v_src
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='admin_confirm_catalog_variant_import';

    IF v_sec IS NOT TRUE THEN RAISE EXCEPTION 'CONFIRM_V3_NOT_SECDEF.'; END IF;
    IF NOT (v_cfg::TEXT LIKE '%search_path=%') THEN RAISE EXCEPTION 'CONFIRM_V3_NO_SEARCH_PATH.'; END IF;

    -- Matching quádruplo presente.
    IF v_src NOT LIKE '%edition_context_profile_id        IS NOT DISTINCT FROM%' THEN
        RAISE EXCEPTION 'CONFIRM_V3_NO_QUAD_MATCH: matching nao usa IS NOT DISTINCT FROM no 3o eixo.';
    END IF;
    -- Writer de 7 argumentos.
    IF v_src NOT LIKE '%v_printing_profile_id, v_edition_context_profile_id%' THEN
        RAISE EXCEPTION 'CONFIRM_V3_WRITER_ARITY: writer nao e chamado com 7 argumentos.';
    END IF;
    -- unique_violation ANTES de OTHERS.
    IF position('WHEN unique_violation' in v_src) = 0
       OR position('WHEN unique_violation' in v_src) > position('WHEN OTHERS' in v_src) THEN
        RAISE EXCEPTION 'CONFIRM_V3_HANDLER_ORDER: unique_violation ausente ou depois de WHEN OTHERS.';
    END IF;
    -- Lock determinístico.
    IF v_src NOT LIKE '%ORDER BY c.id%FOR UPDATE%' THEN
        RAISE EXCEPTION 'CONFIRM_V3_NO_DETERMINISTIC_LOCK: falta ORDER BY c.id no FOR UPDATE das Cards.';
    END IF;
    -- Fronteira operacional preservada.
    IF v_src NOT LIKE '%NOT IN (''STAGED'', ''CONFIRMING'')%' THEN
        RAISE EXCEPTION 'CONFIRM_V3_BOUNDARY_LOST: guard de job confirmavel removido.';
    END IF;
    -- Teto de lote preservado.
    IF v_src NOT LIKE '%c_max_rows CONSTANT INTEGER := 1000%' THEN
        RAISE EXCEPTION 'CONFIRM_V3_BOUNDS_LOST: teto de lote alterado.';
    END IF;

    SELECT COUNT(*) INTO v_n FROM information_schema.role_routine_grants
     WHERE routine_name='admin_confirm_catalog_variant_import' AND grantee = 'PUBLIC';
    IF v_n <> 0 THEN RAISE EXCEPTION 'CONFIRM_V3_GRANT_LEAK: grant para PUBLIC.'; END IF;

    RAISE NOTICE 'admin_confirm_catalog_variant_import v3.0 OK — 8/8 provas estruturais.';
END $$;

-- ============================================================================
-- PERFORMANCE
--   * Um único lock de Cards por chamada, set-based, em vez de N locks
--     dentro do loop. Menos round-trips e janela de lock mais curta.
--   * Nenhuma resolução de axes acontece aqui: o confirm LÊ normalized_data,
--     que já foi resolvido a montante por 2211/2219. Zero N+1 de trait.
--   * O matching quádruplo usa o prefixo de uq_card_variant_identity
--     (card_id, variant_type_id, printing_profile_id,
--     edition_context_profile_id) — index scan, não seq scan.
--   * Teto de 1000 rows por chamada preservado: a janela de lock continua
--     limitada por construção.
--
-- ARMADO PARA ROLLOUT (ROLLOUT-EXECUTION-READINESS-01). Terminador COMMIT.
-- Corpo auditado PRESERVADO byte a byte; a unica alteracao de armamento foi
-- ROLLBACK; -> COMMIT;. A protecao contra execucao prematura e GOVERNANCA
-- (autorizacao de Fabricio + ordem de batches), nao o terminador — mesma
-- decisao ja aceita em R1 para 2203-2211.
-- ============================================================================
COMMIT;
