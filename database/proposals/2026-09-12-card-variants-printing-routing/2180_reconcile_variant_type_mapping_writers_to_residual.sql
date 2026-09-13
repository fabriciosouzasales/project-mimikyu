/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2180 - Reconcile Variant Type Mapping Writers to Residual
Versão......: 1.0
Status......: PROPOSTA — NÃO EXECUTADA
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§19)
Sucede......: Query 2150 (LIVE)

Descrição resumida:
Fecha o BLOCKER B3. admin_resolve_catalog_variant_import_mapping() passa
a criar mapping de Variant Type a partir da assinatura RESIDUAL, nunca
mais da RAW.

-------------------------------------------------------------------------------
O BLOCKER
-------------------------------------------------------------------------------
A 2150 LIVE monta o mapping direto de r.raw_data (linhas 184-232). Depois
que o Printing existir, uma row como

    type=normal  subtype=shadowless  stamp=[1st-edition]

geraria um card_variant_type_external_mapping COMPOSTO — recriando dentro
da taxonomia de acabamento exatamente a explosao combinatoria que o
modelo de Printing foi criado para eliminar.

Correcao: a assinatura usada tanto para criar o mapping quanto para
casar as rows passa a vir de
internal.compute_variant_residual_signature() (Query 2176).

-------------------------------------------------------------------------------
UM PONTO DE MUDANCA, DOIS WRITERS COBERTOS
-------------------------------------------------------------------------------
admin_create_card_variant_type_with_import_mapping() (Query 2158) e
wrapper desta funcao — chama admin_create_card_variant_type() e depois
esta. Ele herda a correcao SEM logica paralela, e por isso NAO e alterado
nesta Query. Auditado: 2158 linhas 122 e 126.

-------------------------------------------------------------------------------
NOVO GUARD — Printing precisa estar resolvido
-------------------------------------------------------------------------------
Se a row estiver em NEEDS_REVIEW por causa do PRINTING (token so com
historico inativo, trait inativo, profile inexistente ou inativo), criar
um mapping de Variant Type nao resolve nada e ainda registra uma
combinacao residual possivelmente errada. A funcao recusa, com o estado
exato no erro, e manda o editor resolver o Printing primeiro.

-------------------------------------------------------------------------------
PRESERVADO DA 2150
-------------------------------------------------------------------------------
- Autorizacao admin como primeira instrucao.
- game_id resolvido a partir da propria linha, nunca por parametro.
- asset_source resolvido pelo source do job.
- Variant Type precisa pertencer ao mesmo Game.
- Guarda anti-duplicata antes do INSERT.
- Revalidacao SET-BASED, cross-job e cross-Card Set dentro do mesmo
  Game+Fonte (decisao explicita de Fabricio, 2026-08-15).
- catalog_admin_action_log com rows_updated/jobs_affected.
- Assinatura publica (UUID, UUID) inalterada.

Pré-requisitos:
- Query 2150 aplicada (LIVE).
- Query 2176 - compute_variant_residual_signature().
- Query 2177 - contrato de normalized_data.
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_resolve_catalog_variant_import_mapping(
    p_row_id UUID,
    p_variant_type_id UUID
)
RETURNS TABLE (
    mapping_id UUID,
    rows_updated INTEGER,
    jobs_affected INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_row public.catalog_variant_import_row%ROWTYPE;
    v_job_source TEXT;
    v_game_id UUID;
    v_asset_source_id UUID;
    v_sig RECORD;                      -- resultado da 2176
    v_mapping_id UUID;
    v_rows_updated INTEGER;
    v_jobs_affected INTEGER;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_FORBIDDEN: apenas administradores podem resolver um mapeamento de variante.';
    END IF;

    IF p_row_id IS NULL OR p_variant_type_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_MISSING_IDS: p_row_id e p_variant_type_id são obrigatórios.';
    END IF;

    SELECT r.* INTO v_row FROM public.catalog_variant_import_row r WHERE r.id = p_row_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_ROW_NOT_FOUND: nenhuma linha encontrada para o id informado (%).', p_row_id;
    END IF;

    SELECT j.source INTO v_job_source FROM public.catalog_variant_import_job j WHERE j.id = v_row.job_id;

    IF v_job_source IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_JOB_NOT_FOUND: não foi possível resolver o job desta linha.';
    END IF;

    IF v_row.validation_status <> 'NEEDS_REVIEW' THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_NOT_NEEDS_REVIEW: só linhas sem mapeamento (NEEDS_REVIEW) podem ser resolvidas por aqui.';
    END IF;

    SELECT e.game_id INTO v_game_id
    FROM public.card c
    JOIN public.card_set cs ON cs.id = c.card_set_id
    JOIN public.expansion e ON e.id = cs.expansion_id
    WHERE c.id = v_row.card_id;

    IF v_game_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_GAME_NOT_FOUND: não foi possível resolver o Game desta linha.';
    END IF;

    SELECT id INTO v_asset_source_id FROM public.asset_source WHERE code = v_job_source;

    IF v_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_SOURCE_NOT_FOUND: nenhuma Fonte encontrada para o código % do job desta linha.', v_job_source;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.card_variant_type WHERE id = p_variant_type_id AND game_id = v_game_id) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_VARIANT_TYPE_MISMATCH: o Card Variant Type informado não existe ou não pertence ao Game desta combinação.';
    END IF;

    -- =================================================================
    -- RESIDUAL, NAO RAW. Este e o fechamento do B3.
    -- =================================================================
    SELECT * INTO v_sig
    FROM internal.compute_variant_residual_signature(v_row.raw_data, v_game_id, v_asset_source_id);

    IF v_sig.printing_state NOT IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE') THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_PRINTING_UNRESOLVED: esta linha está pendente pelo eixo de IMPRESSÃO (estado: %), não pelo acabamento. Resolva o mapeamento de Printing antes — criar um Card Variant Type aqui registraria uma combinação residual possivelmente incorreta.', v_sig.printing_state;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.card_variant_type_external_mapping
        WHERE game_id = v_game_id
          AND asset_source_id = v_asset_source_id
          AND normalized_type = v_sig.residual_type
          AND COALESCE(normalized_foil, '') = COALESCE(v_sig.residual_foil, '')
          AND COALESCE(normalized_subtype, '') = COALESCE(v_sig.residual_subtype, '')
          AND COALESCE(normalized_stamp, '{}'::TEXT[]) = COALESCE(v_sig.residual_stamp, '{}'::TEXT[])
    ) THEN
        RAISE EXCEPTION 'ADMIN_RESOLVE_CATALOG_VARIANT_IMPORT_MAPPING_DUPLICATE: já existe um mapeamento para esta combinação residual nesta Fonte/Game.';
    END IF;

    -- external_* guardam a assinatura RESIDUAL, nao a bruta: o mapping
    -- descreve acabamento, e o que foi consumido pelo Printing nao
    -- pertence mais a este eixo.
    INSERT INTO public.card_variant_type_external_mapping (
        game_id, asset_source_id,
        external_type, external_foil, external_subtype, external_stamp,
        normalized_type, normalized_foil, normalized_subtype, normalized_stamp,
        variant_type_id
    ) VALUES (
        v_game_id, v_asset_source_id,
        v_sig.residual_type, v_sig.residual_foil, v_sig.residual_subtype,
        NULLIF(v_sig.residual_stamp, '{}'::TEXT[]),
        v_sig.residual_type, v_sig.residual_foil, v_sig.residual_subtype,
        NULLIF(v_sig.residual_stamp, '{}'::TEXT[]),
        p_variant_type_id
    ) RETURNING id INTO v_mapping_id;

    -- =================================================================
    -- Revalidacao SET-BASED, cross-job/cross-Card Set no mesmo
    -- Game+Fonte. Agora comparando RESIDUAL contra RESIDUAL, e gravando
    -- TAMBEM printing_profile_id — chave presente e o que torna a row
    -- elegivel a VALID sob o contrato novo.
    --
    -- LATERAL avalia a 2176 uma vez por row candidata. O universo ja e
    -- estreito (mesmo Game+Fonte, STAGED, NEEDS_REVIEW, PENDING), e o
    -- catalogo de Printing e minusculo — sem risco de O(n) patologico.
    -- =================================================================
    WITH candidates AS (
        SELECT r.id, r.job_id, s.*
        FROM public.catalog_variant_import_row r
        JOIN public.catalog_variant_import_job j ON j.id = r.job_id
        CROSS JOIN LATERAL internal.compute_variant_residual_signature(
            r.raw_data, v_game_id, v_asset_source_id
        ) s
        WHERE j.status = 'STAGED'
          AND j.source = v_job_source
          AND j.card_set_id IN (
              SELECT cs2.id FROM public.card_set cs2
              JOIN public.expansion e2 ON e2.id = cs2.expansion_id
              WHERE e2.game_id = v_game_id
          )
          AND r.decision_status = 'PENDING'
          AND r.validation_status = 'NEEDS_REVIEW'
    ),
    matched AS (
        SELECT c.id, c.job_id, c.printing_profile_id
        FROM candidates c
        WHERE c.printing_state IN ('RESOLVED_NO_PRINTING', 'RESOLVED_WITH_PROFILE')
          AND c.residual_type = v_sig.residual_type
          AND COALESCE(c.residual_foil, '')    = COALESCE(v_sig.residual_foil, '')
          AND COALESCE(c.residual_subtype, '') = COALESCE(v_sig.residual_subtype, '')
          AND COALESCE(c.residual_stamp, '{}'::TEXT[]) = COALESCE(v_sig.residual_stamp, '{}'::TEXT[])
    ),
    updated AS (
        UPDATE public.catalog_variant_import_row r
        SET normalized_data =
                jsonb_set(
                    jsonb_set(r.normalized_data,
                              '{variant_type_id}', to_jsonb(p_variant_type_id::TEXT), true),
                    '{printing_profile_id}',
                    CASE WHEN m.printing_profile_id IS NULL
                         THEN 'null'::JSONB
                         ELSE to_jsonb(m.printing_profile_id::TEXT) END,
                    true),
            validation_status = 'VALID'
        FROM matched m
        WHERE r.id = m.id
        RETURNING r.id, r.job_id
    )
    SELECT count(*), count(DISTINCT job_id) INTO v_rows_updated, v_jobs_affected FROM updated;

    INSERT INTO public.catalog_admin_action_log (actor_id, action, entity_type, entity_id, metadata)
        VALUES (
            auth.uid(), 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING_CREATED', 'CARD_VARIANT_TYPE_EXTERNAL_MAPPING', v_mapping_id,
            jsonb_build_object(
                'game_id', v_game_id, 'asset_source_id', v_asset_source_id, 'variant_type_id', p_variant_type_id,
                'residual_type', v_sig.residual_type, 'residual_foil', v_sig.residual_foil,
                'residual_subtype', v_sig.residual_subtype, 'residual_stamp', v_sig.residual_stamp,
                'signature_basis', 'RESIDUAL',
                'origin_row_id', p_row_id, 'rows_updated', v_rows_updated, 'jobs_affected', v_jobs_affected
            )
        );

    RETURN QUERY SELECT v_mapping_id, v_rows_updated, v_jobs_affected;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_resolve_catalog_variant_import_mapping(UUID, UUID) TO authenticated;

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE OR REPLACE FUNCTION, REVOKE, GRANT.
--   Assinatura publica inalterada: (UUID, UUID).
--   Query 2158 (wrapper) herda o comportamento sem alteracao propria.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing, Secao S14.
-- ============================================================================
