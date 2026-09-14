/*
================================================================
Projeto.....: Project Mimikyu
Query.......: 2194 - Create
              public.admin_preview_catalog_variant_import_mapping()
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE em 2026-09-14 (GATE-B-EXECUTION-01)
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-14
Mandato.....: CARD-VARIANTS — EDITORIAL-CONVERGENCE-16 /
              SOURCE-SET-SCOPED-FOUNDATION / GATE-A-STAGING-01

Descrição...:
PREVIEW administrativo. LEITURA PURA — zero escrita, garantido
estruturalmente: a função é STABLE e todo o seu corpo é uma única
chamada a internal.variant_type_mapping_decision(), que também é
STABLE.

--------------------------------------------------------------
POR QUE NÃO p_dry_run
--------------------------------------------------------------
O §6 do mandato pede para evitar p_dry_run se isso criar overload,
duplicação ou semântica pública ambígua. Criaria os três:

1. OVERLOAD — `admin_resolve_catalog_variant_import_mapping` tem
   hoje aridade 2 e é chamada pelo frontend. Acrescentar
   `p_dry_run BOOLEAN DEFAULT FALSE` cria uma segunda assinatura
   resolvível; PostgreSQL passaria a ter duas candidatas para
   chamadas de 2 argumentos se um dia alguém criasse a variante
   sem DEFAULT. Risco desnecessário.
2. DUPLICAÇÃO — o retorno útil de um preview (14 campos) não cabe
   no retorno de 3 colunas da RPC atual sem quebrá-la.
3. AMBIGUIDADE — uma função cujo nome diz "resolve" e que às
   vezes não resolve é uma armadilha de leitura.

Função separada + contrato interno comum resolve tudo isso:
preview e execute compartilham 100% da lógica via Query 2192, e
nenhuma assinatura pública fica ambígua.

--------------------------------------------------------------
GARANTIA DE PARIDADE COM O EXECUTE
--------------------------------------------------------------
`would_apply` e `block_reason` vêm literalmente de
internal.variant_type_mapping_decision(). O worker (Query 2193)
chama a MESMA função e só converte `ok = FALSE` em exceção.

Não existe caminho em que o preview diga "would_apply = TRUE" e o
execute aborte por regra de negócio. O harness 2826 (caso O)
prova isso comparando os dois lado a lado.

Pré-requisitos:
- Query 2192 - contrato de leitura (scope + impact + decision).
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
-- CONFIRMADO EXECUTADO em 2026-09-14 (GATE-B-EXECUTION-01). Cópia mantida em
-- proposals/ como evidência histórica do ciclo.
-- ================================================================
