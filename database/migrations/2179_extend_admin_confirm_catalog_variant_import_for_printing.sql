/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2179 - Extend admin_confirm_catalog_variant_import() for Printing
Versão......: 1.1
Status......: MIGRATION — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2179_extend_admin_confirm_catalog_variant_import_for_printing.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§17, §18)
               + STAGING-REVISION-01 (R2)
Sucede......: Query 2164 v1.1 (LIVE) — hardening de contrato bulk

Descrição resumida:
Adiciona Printing ao confirm. Fecha o BLOCKER B2 (falso MATCHED).

-------------------------------------------------------------------------------
VERSÃO 1.1 — BLOCKER R2: COMPATIBILIDADE TRANSITÓRIA DURANTE O BRIDGE
-------------------------------------------------------------------------------
A v1.0 tratava chave AUSENTE como rejeição incondicional, a partir do
instante em que fosse aplicada. Isso quebrava a janela real entre a
PHASE B e a PHASE D:

  - 5.653 linhas VALID legadas existem HOJE sem a chave;
  - enquanto a Edge ANTIGA estiver em produção, ela continua criando
    linhas VALID sem a chave.

Com a v1.0, qualquer confirmação nessa janela falharia em massa. Isso
não é fail-closed — é indisponibilidade auto-infligida, e a tentação
seguinte seria relaxar o guard permanentemente. Pior remédio que a
doença.

O que a v1.1 faz — e, principalmente, o que ela NÃO faz:

  A. Chave AUSENTE + bridge presente: a linha só é confirmada como
     "sem perfil" se for DEMONSTRÁVEL que a assinatura bruta dela não
     contém nenhum token de Impressão conhecido — nem ativo, nem
     histórico inativo. A prova é feita chamando
     internal.compute_variant_residual_signature() sobre o raw_data e
     exigindo printing_state = 'RESOLVED_NO_PRINTING'.

     'RESOLVED_NO_PRINTING' significa literalmente: o roteamento olhou
     e não encontrou nada de Impressão. Nenhum conhecimento está sendo
     ignorado.

  B. Chave AUSENTE + token de Impressão conhecido (ativo OU histórico
     inativo): RECUSADA. Este é o caso perigoso — a linha PARECE
     "sem perfil" só porque nasceu antes do roteamento existir.
     Confirmá-la criaria uma card_variant sem perfil que deveria ter
     perfil, e a correção posterior seria reconciliação de catálogo,
     não reimportação.

  C. A Edge NOVA sempre grava null explícito ou UUID. Para ela este
     caminho nunca é exercido.

  D. A compatibilidade EXPIRA SOZINHA. O ramo legado é condicionado à
     existência do índice uq_cvir_job_card_type_bridge_legacy. A
     PHASE E remove esse índice — e no mesmo instante, sem nenhuma
     migration adicional, chave ausente volta a ser rejeição
     incondicional.

     Isso é deliberado: o mandato exige que a compatibilidade
     transitória NÃO vire contrato permanente. Amarrá-la ao objeto
     físico que define a janela é a forma de garantir isso sem
     depender de alguém lembrar de removê-la.

     Depois da PHASE E o ramo vira código morto — e a constraint
     ck_catalog_variant_import_row_valid_requires_printing_key torna
     o próprio estado (VALID + chave ausente) impossível no banco.

O flag do bridge é lido UMA vez por chamada, antes do LOOP. Não há
custo por linha.

-------------------------------------------------------------------------------
DIFF FRENTE A 2164 v1.1 — QUATRO PONTOS, NADA MAIS
-------------------------------------------------------------------------------
Todo o hardening de contrato bulk da 2164 e preservado LITERALMENTE:
c_max_rows = 1000, GUARD 1..7, conjunto efetivo congelado com
ORDER BY created_at, id + LIMIT c_max_rows + 1, semantica de
p_row_ids = NULL, LOOP restrito ao conjunto congelado, recalculo de
contadores por agregacao, transicao de status e action log.

As quatro mudancas:

  1. v_printing_profile_id extraido de normalized_data.

  2. GUARD NOVO — Printing precisa estar RESOLVIDO. A chave
     printing_profile_id tem que EXISTIR no JSON (null explicito ou
     UUID). Chave AUSENTE = Printing nao resolvido = confirmacao
     recusada.

  3. Matching TRIPLO. O lookup passa a incluir
     printing_profile_id IS NOT DISTINCT FROM v_printing_profile_id.

  4. O perfil e repassado a internal.write_card_variant() (Query 2178).

-------------------------------------------------------------------------------
POR QUE `IS NOT DISTINCT FROM` E NAO `=`
-------------------------------------------------------------------------------
Para uma row RESOLVIDA SEM perfil, v_printing_profile_id e NULL.

    cv.printing_profile_id = NULL   -->  sempre NULL  -->  nunca verdadeiro

O ramo MATCHED jamais dispararia para variantes sem perfil, e o confirm
tentaria INSERT de uma variante que ja existe — violando
uq_card_variant_card_type_no_printing e marcando a row como FAILED.

`IS NOT DISTINCT FROM` trata NULL como valor comparavel, que e
exatamente a semantica de "sem perfil declarado" como parte da
identidade.

-------------------------------------------------------------------------------
BLOCKER B2 — o que estava errado
-------------------------------------------------------------------------------
A 2164 procura por (card_id, variant_type_id) apenas. Com Printing, uma
row STANDARD+SHADOWLESS encontraria a variante STANDARD sem perfil e a
marcaria MATCHED — silenciosamente tratando duas variantes REAIS e
DISTINTAS como a mesma.

Em BASE1 o defeito nao se materializa (as 102 Cards tem zero
card_variant hoje), mas ele e estrutural e ativa em qualquer Set ja
povoado. Corrigido aqui, antes de qualquer resolucao.

-------------------------------------------------------------------------------
NAO MUDA
-------------------------------------------------------------------------------
- Nenhuma criacao automatica de Print Profile.
- Nenhuma alteracao de card_variant ja persistida.
- MATCHED continua significando "ja existe, nao escreve".
- variant_order continua sendo o proximo inteiro livre por card_id,
  calculado so a partir de card_variant.
- is_default continua nascendo FALSE pelo default da coluna.

Pré-requisitos:
- Query 2164 v1.1 aplicada (LIVE).
- Query 2176 - internal.compute_variant_residual_signature() (usada pelo
  ramo de compatibilidade transitória).
- Query 2177 - indices de identidade de staging + bridge.
- Query 2178 - internal.write_card_variant() com p_printing_profile_id.

-------------------------------------------------------------------------------
ESTADO FINAL (registro pós-rollout)
-------------------------------------------------------------------------------
A PHASE E (Query 2184) removeu o índice uq_cvir_job_card_type_bridge_legacy.
Conforme previsto no item D acima, o ramo de compatibilidade transitória
deixou de ser alcançável no mesmo instante — sem nenhuma migration
adicional. Esta função permanece LIVE nesta forma; o ramo legado é código
morto por desenho, e a constraint
ck_catalog_variant_import_row_valid_requires_printing_key (Query 2184)
torna o estado que o justificava impossível no banco.

Por isso este arquivo é MIGRATION, não CANÔNICA. A forma canônica de
admin_confirm_catalog_variant_import() será consolidada na Query 2145 na
rodada CANONICAL-RECONCILIATION-01.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial (2026-09-12).** Tratava chave ausente como rejeição
        incondicional. Substituída antes da execução pelo BLOCKER R2. |
| 1.1 | **Compatibilidade transitória atrelada ao bridge (2026-09-12).**
        Esta é a versão executada e confirmada no banco físico na PHASE B da
        frente CARD-VARIANTS — PRINTING-ROUTING. Promovida de
        database/proposals/ para database/migrations/ em 2026-09-13
        (TECHNICAL-CLOSEOUT-PROMOTION-01). O SQL executável permanece
        idêntico ao artefato executado; só o cabeçalho registra o estado
        final. A proposal original é preservada como histórico. |
===============================================================================
*/

BEGIN;

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
    -- Teto de lote. Preservado da 2164 v1.1.
    c_max_rows CONSTANT INTEGER := 1000;

    v_job public.catalog_variant_import_job%ROWTYPE;
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_existing_variant public.card_variant%ROWTYPE;
    v_variant_type_id UUID;
    v_printing_profile_id UUID;          -- (1) NOVO
    v_printing_key_type TEXT;            -- (1) NOVO
    v_match_status TEXT;
    v_result_variant_id UUID;
    v_next_order INTEGER;
    v_error_message TEXT;
    v_pending_rows INTEGER;
    v_failed_rows INTEGER;
    v_decision_pending_rows INTEGER;
    v_final_status TEXT;
    v_card_set_name TEXT;
    v_card_set_code TEXT;
    v_id_count INTEGER;
    v_effective_row_ids UUID[];

    -- (R2) Janela de compatibilidade com o writer antigo.
    v_bridge_present BOOLEAN;
    v_game_id UUID;
    v_asset_source_id UUID;
    v_legacy_state TEXT;
BEGIN
    -- GUARD 1 — AUTORIZACAO.
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_FORBIDDEN: apenas administradores podem confirmar uma importação de variantes.';
    END IF;

    -- GUARD 2 — p_job_id obrigatorio.
    IF p_job_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_MISSING_JOB: p_job_id é obrigatório.';
    END IF;

    -- GUARD 3 — FORMA E TETO DE p_row_ids (2164). Validacao pura de
    -- payload: nenhum acesso a tabela, nenhum lock ainda tomado.
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

    -- GUARD 4/5/6.
    SELECT * INTO v_job FROM public.catalog_variant_import_job WHERE id = p_job_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_JOB_NOT_FOUND: nenhum job encontrado para o id informado (%).', p_job_id;
    END IF;

    IF v_job.status NOT IN ('STAGED', 'CONFIRMING') THEN
        RAISE EXCEPTION 'ADMIN_CONFIRM_CATALOG_VARIANT_IMPORT_INVALID_STATUS: o job está em % — só é possível confirmar a partir de STAGED ou CONFIRMING.', v_job.status;
    END IF;

    SELECT name, code INTO v_card_set_name, v_card_set_code
    FROM public.card_set WHERE id = v_job.card_set_id;

    -- =================================================================
    -- (R2) JANELA DE COMPATIBILIDADE — lida UMA vez, fora do LOOP.
    --
    -- O bridge é o objeto físico que DEFINE a janela em que linhas
    -- VALID sem a chave printing_profile_id ainda podem existir
    -- legitimamente. Enquanto ele existir, o ramo legado abaixo vale;
    -- quando a PHASE E o remover, ele deixa de valer no mesmo instante.
    -- =================================================================
    SELECT EXISTS (
        SELECT 1 FROM pg_catalog.pg_indexes
         WHERE schemaname = 'public'
           AND indexname = 'uq_cvir_job_card_type_bridge_legacy'
    ) INTO v_bridge_present;

    IF v_bridge_present THEN
        SELECT e.game_id INTO v_game_id
        FROM public.card_set cs
        JOIN public.expansion e ON e.id = cs.expansion_id
        WHERE cs.id = v_job.card_set_id;

        SELECT s.id INTO v_asset_source_id
        FROM public.asset_source s WHERE s.code = v_job.source;

        -- Sem Game/Fonte não há como PROVAR ausência de Impressão.
        -- Nesse caso o ramo legado não é oferecido — a linha cai na
        -- rejeição normal. Fail-closed.
        IF v_game_id IS NULL OR v_asset_source_id IS NULL THEN
            v_bridge_present := FALSE;
        END IF;
    END IF;

    -- GUARD 7 — CONJUNTO EFETIVO CONGELADO (2164 v1.1). Elimina o TOCTOU.
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

            IF v_row.validation_status <> 'VALID' THEN
                RAISE EXCEPTION 'NEEDS_REVIEW_CANNOT_BE_CONFIRMED: linha sem card_variant_type resolvido não pode ser confirmada.';
            END IF;

            v_variant_type_id := NULLIF(v_row.normalized_data->>'variant_type_id', '')::UUID;
            IF v_variant_type_id IS NULL THEN
                RAISE EXCEPTION 'MISSING_VARIANT_TYPE_ID: normalized_data não contém variant_type_id resolvido.';
            END IF;

            -- (2) GUARD NOVO — Printing precisa estar RESOLVIDO.
            --
            -- jsonb_typeof distingue os tres estados; `->>` nao:
            --   chave ausente -> SQL NULL   (Printing NAO resolvido)
            --   JSON null     -> 'null'     (resolvido SEM perfil)
            --   string        -> 'string'   (resolvido COM perfil)
            v_printing_key_type := jsonb_typeof(v_row.normalized_data -> 'printing_profile_id');

            IF v_printing_key_type IS NULL THEN
                -- (R2) CHAVE AUSENTE — só há um caminho legítimo, e ele
                -- exige PROVA, não suposição.
                IF NOT v_bridge_present THEN
                    RAISE EXCEPTION 'PRINTING_NOT_RESOLVED: normalized_data não contém a chave printing_profile_id. A janela de compatibilidade já foi encerrada (PHASE E) — toda linha VALID precisa da chave. Reprocesse a importação.';
                END IF;

                SELECT s.printing_state INTO v_legacy_state
                FROM internal.compute_variant_residual_signature(
                        v_row.raw_data, v_game_id, v_asset_source_id) s;

                IF v_legacy_state IS DISTINCT FROM 'RESOLVED_NO_PRINTING' THEN
                    RAISE EXCEPTION 'PRINTING_NOT_RESOLVED: linha legada sem a chave printing_profile_id cuja assinatura externa contém Impressão conhecida (estado: %). Confirmar agora criaria uma variante sem perfil que deveria ter perfil. Resolva o mapeamento de Impressão antes.', COALESCE(v_legacy_state, 'INDETERMINADO');
                END IF;

                -- PROVADO: nenhum token de Impressão, ativo ou histórico.
                -- Equivalente exato a "printing_profile_id": null.
                v_printing_profile_id := NULL;
            ELSIF v_printing_key_type = 'null' THEN
                v_printing_profile_id := NULL;      -- resolvido SEM perfil, explícito
            ELSIF v_printing_key_type = 'string' THEN
                v_printing_profile_id := (v_row.normalized_data->>'printing_profile_id')::UUID;
            ELSE
                RAISE EXCEPTION 'PRINTING_PROFILE_ID_INVALID_SHAPE: printing_profile_id tem tipo JSON % — esperado null ou string UUID.', v_printing_key_type;
            END IF;

            -- (3) MATCHING TRIPLO. match_status recalculado contra o
            -- catalogo real — nunca herdado.
            SELECT cv.* INTO v_existing_variant
            FROM public.card_variant cv
            WHERE cv.card_id = v_row.card_id
              AND cv.variant_type_id = v_variant_type_id
              AND cv.printing_profile_id IS NOT DISTINCT FROM v_printing_profile_id
            LIMIT 1;

            IF v_existing_variant.id IS NULL THEN
                v_match_status := 'NEW';
            ELSE
                v_match_status := 'MATCHED';
            END IF;

            IF v_match_status = 'MATCHED' THEN
                UPDATE public.catalog_variant_import_row
                    SET match_status = v_match_status,
                        persistence_status = 'UNCHANGED',
                        matched_variant_id = v_existing_variant.id,
                        resulting_variant_id = v_existing_variant.id,
                        error_detail = NULL
                    WHERE id = v_row.id;
                CONTINUE;
            END IF;

            SELECT COALESCE(MAX(variant_order), 0) + 1 INTO v_next_order
            FROM public.card_variant
            WHERE card_id = v_row.card_id;

            -- (4) Perfil repassado ao writer (Query 2178).
            v_result_variant_id := internal.write_card_variant(
                'CREATE', NULL, v_row.card_id, v_variant_type_id, v_next_order,
                v_printing_profile_id
            );

            UPDATE public.catalog_variant_import_row
                SET match_status = v_match_status,
                    persistence_status = 'INSERTED',
                    matched_variant_id = NULL,
                    resulting_variant_id = v_result_variant_id,
                    error_detail = NULL
                WHERE id = v_row.id;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
            UPDATE public.catalog_variant_import_row
                SET persistence_status = 'FAILED', error_detail = v_error_message
                WHERE id = v_row.id;
        END;
    END LOOP;

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

-- Grants reafirmados identicos aos da Query 2145/2164.
REVOKE ALL ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_confirm_catalog_variant_import(UUID, UUID[]) TO authenticated;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE OR REPLACE FUNCTION, REVOKE, GRANT.
--   Assinatura publica inalterada: (UUID, UUID[]).
--   Nenhum caller do web precisa mudar.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing:
--     Secao S12 (BLOCO I / GATE-A, matching triplo — H25/H26)
--     Secao S20 (BLOCO I / GATE-A, ramo de compatibilidade — R2)
--     Secao S25 (BLOCO IV / FINAL-E, chave ausente volta a ser rejeicao dura)
-- ============================================================================
