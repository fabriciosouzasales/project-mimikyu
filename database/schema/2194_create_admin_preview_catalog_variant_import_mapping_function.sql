/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2194 - Create admin_preview_catalog_variant_import_mapping()
Versão......: 1.0
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14 (execução) · 2026-09-18 (promoção canônica)
Ledger......: 20260914025000 / 2194_create_admin_preview_catalog_variant_import_mapping_function
Promovida...: 2026-09-18, BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01

Descrição...:
RPC pública de PRÉVIA (dry-run) da resolução de um mapping de Card
Variant Type. Não escreve nada: devolve o impacto que a aplicação teria
(rows_total, rows_class_a/b, canonical_class_c, rows_valid_reclassified,
jobs_affected), mais would_apply/block_reason/block_detail.

É o primitivo que permite decidir em massa por assinatura sem aplicar
nada antes de ver o alcance real.

Pré-requisitos:
- Query 2192 - Variant Type Mapping Scope Read Contract (v2.0).
- Query 1060 - Create is_admin() Function.

----------------------------------------------------------------
REVISION HISTORY
----------------------------------------------------------------
| 1.0 | **Criação da RPC de prévia (2026-09-14, GATE-B-EXECUTION-01).**
        Corpo idêntico ao executado. Promovido a CANÔNICA em 2026-09-18
        sem alteração de corpo. |
================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_preview_catalog_variant_import_mapping(
    p_row_id          UUID,
    p_variant_type_id UUID,
    p_scope_kind      TEXT
)
RETURNS TABLE(
    scope_kind                 TEXT,
    asset_source_id            UUID,
    external_set_id            TEXT,
    combo_type                 TEXT,
    combo_foil                 TEXT,
    combo_subtype              TEXT,
    combo_stamp                TEXT[],
    current_global_mapping_id  UUID,
    current_effective_scope    TEXT,
    current_variant_type_id    UUID,
    target_variant_type_id     UUID,
    rows_total                 INTEGER,
    rows_class_a               INTEGER,
    rows_class_b               INTEGER,
    canonical_class_c          INTEGER,
    rows_valid_reclassified    INTEGER,
    jobs_affected              INTEGER,
    would_apply                BOOLEAN,
    block_reason               TEXT,
    block_detail               TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $preview$
DECLARE
    v RECORD;
BEGIN
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'ADMIN_PREVIEW_CATALOG_VARIANT_IMPORT_MAPPING_FORBIDDEN: apenas administradores podem pre-visualizar um mapeamento de variante.';
    END IF;

    SELECT * INTO v
      FROM internal.variant_type_mapping_decision(p_row_id, p_variant_type_id, p_scope_kind);

    RETURN QUERY SELECT
        p_scope_kind,
        v.asset_source_id,
        v.external_set_id,
        v.residual_type, v.residual_foil, v.residual_subtype, v.residual_stamp,
        -- current_global_mapping_id: só faz sentido expor o GLOBAL,
        -- porque é o fallback que o override vai sobrepor. Se a
        -- interpretação vigente já for SOURCE_SET, este campo vem
        -- NULL e current_effective_scope revela o porquê.
        CASE WHEN v.current_effective_scope = 'GLOBAL'
             THEN v.current_effective_mapping_id ELSE NULL END,
        v.current_effective_scope,
        v.current_effective_variant_type_id,
        p_variant_type_id,
        v.rows_total, v.rows_class_a, v.rows_class_b,
        v.canonical_class_c, v.rows_valid_reclassified, v.jobs_affected,
        v.ok, v.block_reason, v.block_detail;
END;
$preview$;

COMMENT ON FUNCTION public.admin_preview_catalog_variant_import_mapping(UUID, UUID, TEXT) IS
    'PREVIEW administrativo de criacao de mapping de Card Variant Type (GLOBAL ou SOURCE_SET). LEITURA PURA: STABLE, corpo e uma unica chamada ao contrato interno STABLE da Query 2192 - o mesmo que o worker usa. would_apply/block_reason sao identicos aos que o execute aplicaria.';

REVOKE ALL ON FUNCTION public.admin_preview_catalog_variant_import_mapping(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_preview_catalog_variant_import_mapping(UUID, UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_catalog_variant_import_mapping(UUID, UUID, TEXT) TO authenticated;

COMMIT;

-- ================================================================
-- CONFIRMADO EXECUTADO / LIVE — ver a migration histórica correspondente
-- em database/migrations/ e o ledger supabase_migrations.schema_migrations.
--
-- Esta Query CANÔNICA foi promovida em 2026-09-18
-- (BULK-STP-01-CANONICAL-RECONCILIATION-IMPLEMENTATION-01) a partir do
-- corpo comprovadamente equivalente ao LIVE. NÃO foi reexecutada contra o
-- Supabase: promoção canônica é alteração de arquivo, não execução.
-- ================================================================
