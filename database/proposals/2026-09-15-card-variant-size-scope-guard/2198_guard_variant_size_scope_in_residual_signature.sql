/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2198 - Guard Variant Size Scope in Residual Signature
Versão......: 1.0
Status......: CONFIRMADO EXECUTADO — LIVE (migration 20260916012057, 2026-09-16)
              Fechamento documental: DOCUMENTATION-CLOSEOUT-01 (2026-09-16).
              md5(pg_get_functiondef) pós-aplicação: 1c5b8352ab53b1e6d4f1c08537824a4b
              md5(prosrc) pós-aplicação..............: b15a527d3b6adb1e50cbaafae22431bc
              Validada pelo harness 2827 v1.1.1 — 29 PASS / 0 FAIL.
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-15
Origem......: derivada de database/schema/
              2176_create_compute_variant_residual_signature_function.sql v1.1
              (CANÔNICA / LIVE — md5 do pg_get_functiondef medido em
               2026-09-15: 5411b79a6b8e8c8d739a1f282bc43868)
Mandato.....: CARD-VARIANTS — JUMBO INCIDENT /
              SIZE-SCOPE-SERVER-GUARD-STAGING-01

-------------------------------------------------------------------------------
POR QUE ESTA MIGRATION EXISTE
-------------------------------------------------------------------------------
A TCGdex modela `size` no objeto de variante (`size: "jumbo"`). O extractor da
Edge `import-card-variants` lê apenas type/foil/subtype/stamp — `size` era
descartado silenciosamente (incidente JUMBO, 2026-09-15).

A correção do extractor (Gate A) passa a PRESERVAR `size` em `raw_data`. Mas
preservar não basta, e o motivo é estrutural:

    `size` está FORA da assinatura residual — por decisão editorial aprovada.

Logo uma linha com `size` desconhecido tem assinatura residual IDÊNTICA à da
sua gêmea sem `size`. Sem guard server-side:

  RISCO 1  ela pode ser ORIGEM de um mapping de Variant Type
           (variant_type_mapping_decision só exige NEEDS_REVIEW, e ela É
            NEEDS_REVIEW).

  RISCO 2  um mapping legítimo criado por OUTRA linha, com a mesma assinatura
           residual, a captura no universo de propagação e a promove a VALID.
           Ocorre mesmo com a UI perfeita.

  RISCO 3/4  os DOIS writers do eixo Printing
           (admin_resolve_catalog_variant_import_printing_mapping e
            internal.create_card_printing_profile_with_backfill)
           também promovem a VALID por conta própria, e nenhum dos dois
           filtrava a linha.

-------------------------------------------------------------------------------
POR QUE AQUI, E NÃO EM CADA WRITER
-------------------------------------------------------------------------------
Auditoria LIVE de 2026-09-15 — os SEIS consumidores desta função, e como cada
um trata `printing_state`:

  internal.variant_type_mapping_decision ......... l.81  NOT IN (RESOLVED_*) -> bloqueia
  internal.variant_type_mapping_impact ........... l.68  IN (RESOLVED_*)     -> filtra universo
  internal.apply_variant_type_mapping ............ l.101 IN (RESOLVED_*)     -> filtra universo
  internal.create_card_printing_profile_with_backfill l.266 NOT IN (RESOLVED_*) -> outcome C
  public.admin_resolve_catalog_variant_import_printing_mapping l.193 NOT IN (RESOLVED_*) -> outcome C
  public.admin_confirm_catalog_variant_import .... l.151 IS DISTINCT FROM
                                                   'RESOLVED_NO_PRINTING' -> RAISE

TODOS tratam o par ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE') como
WHITELIST — nenhum enumera os estados de erro. É a mesma propriedade que a
v1.1 já usou para introduzir NEEDS_REVIEW_INVALID_PRINTING_MAPPING de forma
aditiva (ver 2176 v1.1, seção "ESTADOS DE RETORNO").

Portanto UM estado novo fora da whitelist cobre os quatro riscos, sem tocar em
nenhum writer e sem espalhar exceções independentes que possam divergir.

-------------------------------------------------------------------------------
CONTRATO DE `size` — QUATRO RAMOS, FAIL-CLOSED
-------------------------------------------------------------------------------
size ausente / JSON null / string vazia -> comportamento atual, bit a bit
size normalizado = 'STANDARD'           -> comportamento atual, bit a bit
size normalizado = 'JUMBO'              -> BLOCKED_SIZE_OUT_OF_SCOPE
qualquer outro valor não vazio          -> BLOCKED_SIZE_UNSUPPORTED

O quarto ramo é o que impede o incidente de se repetir com um valor novo da
fonte: desconhecido NÃO segue o fluxo normal. Fail-closed, ruidoso, editorial.

-------------------------------------------------------------------------------
ONDE O GUARD ENTRA — E POR QUE EXATAMENTE AÍ
-------------------------------------------------------------------------------
DEPOIS da normalização de type/foil/subtype/stamp: o residual devolvido
precisa ser COERENTE (mesmo type, mesmo foil, mesmo subtype, mesmo array de
stamp normalizado e ordenado) para que preview e diagnóstico editorial mostrem
a combinação real da linha.

ANTES do roteamento de Printing: uma linha fora de escopo não pode consumir
tokens do eixo de Impressão, nem encostar em card_printing_external_mapping,
nem gerar traits. Economiza trabalho e, mais importante, não produz efeito
colateral de roteamento.

-------------------------------------------------------------------------------
O QUE ESTA MIGRATION NÃO FAZ
-------------------------------------------------------------------------------
- NÃO altera a assinatura residual: `size` continua fora de
  (residual_type, residual_foil, residual_subtype, residual_stamp).
- NÃO altera nenhum dos seis consumidores.
- NÃO altera constraint, índice, tabela ou grant.
- NÃO escreve um único dado: é CREATE OR REPLACE FUNCTION, mais nada.
- NÃO tem efeito sobre o corpus atual: medido em 2026-09-15,
  catalog_variant_import_row tem 6340 linhas e ZERO com a chave
  raw_data.size. Todas caem no ramo "ausente" -> comportamento idêntico.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Guard de escopo de `size` no ponto único do routing (2026-09-15).**
        Deriva da v1.1 canônica sem alterar uma linha do algoritmo existente:
        acrescenta apenas a declaração de `v_size`, a normalização e o bloco
        de guard entre a normalização e o eixo de Printing. Dois estados
        novos, ambos deliberadamente fora da whitelist RESOLVED_*. |
===============================================================================
*/

BEGIN;

CREATE OR REPLACE FUNCTION internal.compute_variant_residual_signature(
    p_raw_data JSONB,
    p_game_id UUID,
    p_asset_source_id UUID
)
RETURNS TABLE (
    residual_type       TEXT,
    residual_foil       TEXT,
    residual_subtype    TEXT,
    residual_stamp      TEXT[],
    printing_state      TEXT,
    trait_ids           UUID[],
    printing_profile_id UUID
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_type TEXT;
    v_foil TEXT;
    v_subtype TEXT;
    v_stamp TEXT[];
    v_res_subtype TEXT;
    v_res_stamp TEXT[] := '{}';
    v_traits UUID[] := '{}';
    v_state TEXT := 'RESOLVED_NO_PRINTING';
    v_profile UUID;
    v_tok TEXT;
    v_sig UUID[];
    v_active_sig UUID[];
    -- (v1.1) EXISTENCIA do mapping ativo e decidida por id, nunca pela
    -- assinatura — que pode estar legitimamente NULL antes do selo.
    v_active_id UUID;
    v_known BOOLEAN;
    -- (2198) ESCOPO DE TAMANHO. Metadado de proveniencia, nunca identidade.
    v_size TEXT;
BEGIN
    IF p_raw_data IS NULL OR p_game_id IS NULL OR p_asset_source_id IS NULL THEN
        RAISE EXCEPTION 'COMPUTE_VARIANT_RESIDUAL_SIGNATURE_MISSING_ARGS: p_raw_data, p_game_id e p_asset_source_id são obrigatórios.';
    END IF;

    -- ----------------------------------------------------------------
    -- Normalizacao da assinatura externa, mesma disciplina da 2150.
    -- ----------------------------------------------------------------
    v_type := public.normalize_external_catalog_value(p_raw_data ->> 'type');

    IF v_type IS NULL OR btrim(v_type) = '' THEN
        RAISE EXCEPTION 'COMPUTE_VARIANT_RESIDUAL_SIGNATURE_MISSING_TYPE: raw_data.type ausente — dado externo inconsistente.';
    END IF;

    v_foil := CASE WHEN p_raw_data ->> 'foil' IS NULL
                   THEN NULL
                   ELSE public.normalize_external_catalog_value(p_raw_data ->> 'foil') END;

    v_subtype := CASE WHEN p_raw_data ->> 'subtype' IS NULL
                      THEN NULL
                      ELSE public.normalize_external_catalog_value(p_raw_data ->> 'subtype') END;

    -- stamp pode vir como JSON array ou JSON null. Qualquer outro tipo e
    -- tratado como ausencia — nunca como escalar implicito.
    IF jsonb_typeof(p_raw_data -> 'stamp') = 'array' THEN
        SELECT array_agg(public.normalize_external_catalog_value(e)
                         ORDER BY public.normalize_external_catalog_value(e))
          INTO v_stamp
          FROM jsonb_array_elements_text(p_raw_data -> 'stamp') e;
    END IF;

    v_stamp := coalesce(v_stamp, '{}');
    v_res_subtype := v_subtype;

    -- ================================================================
    -- (2198) GATE DE ESCOPO DE TAMANHO — FAIL-CLOSED
    -- ----------------------------------------------------------------
    -- Posicao deliberada: DEPOIS da normalizacao (o residual devolvido
    -- precisa ser coerente com a linha real) e ANTES do eixo de Printing
    -- (uma linha fora de escopo nao consome token de Impressao, nao le
    -- card_printing_external_mapping e nao gera trait).
    --
    -- `size` NAO entra na assinatura residual. Ele decide APENAS o
    -- printing_state, que e ESTADO — nunca identidade. Por isso o residual
    -- devolvido aqui e o residual integral da linha: mesmo type, mesmo
    -- foil, mesmo subtype, mesmo array de stamp normalizado e ordenado.
    --
    -- Os dois estados sao deliberadamente FORA de
    -- ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE'). Todos os seis
    -- consumidores tratam esse par como whitelist, entao a recusa e
    -- herdada por construcao — nenhum writer precisa ser alterado.
    -- ================================================================
    v_size := CASE WHEN p_raw_data ->> 'size' IS NULL
                   THEN NULL
                   ELSE public.normalize_external_catalog_value(p_raw_data ->> 'size') END;

    IF v_size IS NOT NULL AND btrim(v_size) <> '' AND v_size <> 'STANDARD' THEN
        RETURN QUERY SELECT
            v_type,
            v_foil,
            v_subtype,
            v_stamp,
            CASE WHEN v_size = 'JUMBO'
                 THEN 'BLOCKED_SIZE_OUT_OF_SCOPE'
                 ELSE 'BLOCKED_SIZE_UNSUPPORTED'
            END::TEXT,
            '{}'::UUID[],
            NULL::UUID;
        RETURN;
    END IF;

    -- ----------------------------------------------------------------
    -- SUBTYPE — token inteiro ou nada.
    -- ----------------------------------------------------------------
    IF v_subtype IS NOT NULL AND btrim(v_subtype) <> '' THEN
        v_active_id := NULL;

        -- ASSINATURA EFETIVA (v1.1): selada, ou a composicao real da N:N
        -- desta mesma transacao. A N:N sempre foi a fonte da verdade;
        -- traits_signature e materializacao, e ela so existe no COMMIT.
        SELECT m.id,
               COALESCE(
                   m.traits_signature,
                   ARRAY(SELECT mt.trait_id
                           FROM public.card_printing_external_mapping_trait mt
                          WHERE mt.mapping_id = m.id
                          ORDER BY mt.trait_id))
          INTO v_active_id, v_active_sig
          FROM public.card_printing_external_mapping m
         WHERE m.game_id = p_game_id
           AND m.asset_source_id = p_asset_source_id
           AND m.raw_field = 'subtype'
           AND m.normalized_token = v_subtype
           AND m.is_active;

        IF v_active_id IS NOT NULL THEN
            -- Mapping ATIVO com composicao efetiva vazia e estado
            -- estruturalmente invalido. Nao e "sem Printing".
            IF v_active_sig IS NULL OR cardinality(v_active_sig) = 0 THEN
                RETURN QUERY SELECT v_type, v_foil, NULL::TEXT, '{}'::TEXT[],
                                    'NEEDS_REVIEW_INVALID_PRINTING_MAPPING'::TEXT,
                                    '{}'::UUID[], NULL::UUID;
                RETURN;
            END IF;

            v_traits := v_traits || v_active_sig;
            v_res_subtype := NULL;                       -- consumido
        ELSE
            SELECT TRUE INTO v_known
              FROM public.card_printing_external_mapping m
             WHERE m.game_id = p_game_id
               AND m.asset_source_id = p_asset_source_id
               AND m.raw_field = 'subtype'
               AND m.normalized_token = v_subtype
             LIMIT 1;

            IF v_known THEN
                -- Caso B: conhecido, sem routing ativo. NAO vai ao residual.
                RETURN QUERY SELECT v_type, v_foil, NULL::TEXT, '{}'::TEXT[],
                                    'NEEDS_REVIEW_INACTIVE_MAPPING'::TEXT,
                                    '{}'::UUID[], NULL::UUID;
                RETURN;
            END IF;
            -- Caso C: nunca conhecido -> permanece no residual.
        END IF;
    END IF;

    -- ----------------------------------------------------------------
    -- STAMP — token a token.
    -- ----------------------------------------------------------------
    FOREACH v_tok IN ARRAY v_stamp LOOP
        v_active_id := NULL;
        v_active_sig := NULL;

        -- Mesma assinatura efetiva do ramo de subtype (v1.1).
        SELECT m.id,
               COALESCE(
                   m.traits_signature,
                   ARRAY(SELECT mt.trait_id
                           FROM public.card_printing_external_mapping_trait mt
                          WHERE mt.mapping_id = m.id
                          ORDER BY mt.trait_id))
          INTO v_active_id, v_active_sig
          FROM public.card_printing_external_mapping m
         WHERE m.game_id = p_game_id
           AND m.asset_source_id = p_asset_source_id
           AND m.raw_field = 'stamp'
           AND m.normalized_token = v_tok
           AND m.is_active;

        IF v_active_id IS NOT NULL THEN
            IF v_active_sig IS NULL OR cardinality(v_active_sig) = 0 THEN
                RETURN QUERY SELECT v_type, v_foil, NULL::TEXT, '{}'::TEXT[],
                                    'NEEDS_REVIEW_INVALID_PRINTING_MAPPING'::TEXT,
                                    '{}'::UUID[], NULL::UUID;
                RETURN;
            END IF;

            v_traits := v_traits || v_active_sig;
        ELSE
            v_known := NULL;
            SELECT TRUE INTO v_known
              FROM public.card_printing_external_mapping m
             WHERE m.game_id = p_game_id
               AND m.asset_source_id = p_asset_source_id
               AND m.raw_field = 'stamp'
               AND m.normalized_token = v_tok
             LIMIT 1;

            IF v_known THEN
                RETURN QUERY SELECT v_type, v_foil, NULL::TEXT, '{}'::TEXT[],
                                    'NEEDS_REVIEW_INACTIVE_MAPPING'::TEXT,
                                    '{}'::UUID[], NULL::UUID;
                RETURN;
            END IF;

            v_res_stamp := v_res_stamp || v_tok;         -- residual
        END IF;
    END LOOP;

    -- Residual de stamp normalizado e ORDENADO — replica a disciplina do
    -- indice uq_card_variant_type_external_mapping_combo (Query 2140).
    v_res_stamp := ARRAY(SELECT s FROM unnest(v_res_stamp) s ORDER BY s);

    -- ----------------------------------------------------------------
    -- Nenhum token Printing: resolvido SEM profile.
    -- ----------------------------------------------------------------
    IF cardinality(v_traits) = 0 THEN
        RETURN QUERY SELECT v_type, v_foil, v_res_subtype, v_res_stamp,
                            'RESOLVED_NO_PRINTING'::TEXT, '{}'::UUID[], NULL::UUID;
        RETURN;
    END IF;

    -- Conjunto canonico: distinto e ordenado ascendente.
    v_sig := ARRAY(SELECT DISTINCT t FROM unnest(v_traits) t ORDER BY t);

    -- ----------------------------------------------------------------
    -- Trait inativo -> NEEDS_REVIEW. Nao e o mesmo que "nao existe".
    -- ----------------------------------------------------------------
    IF EXISTS (
        SELECT 1 FROM public.card_printing_trait t
         WHERE t.id = ANY (v_sig) AND NOT t.is_active
    ) THEN
        RETURN QUERY SELECT v_type, v_foil, v_res_subtype, v_res_stamp,
                            'NEEDS_REVIEW_INACTIVE_TRAIT'::TEXT, v_sig, NULL::UUID;
        RETURN;
    END IF;

    -- ----------------------------------------------------------------
    -- Print Profile por IGUALDADE EXATA de traits_signature.
    -- Nunca por code construido, substring, LIKE ou concatenacao.
    -- ----------------------------------------------------------------
    SELECT p.id INTO v_profile
      FROM public.card_printing_profile p
     WHERE p.game_id = p_game_id
       AND p.traits_signature = v_sig;

    IF v_profile IS NULL THEN
        -- Fail-closed. Jamais criar Profile durante importacao.
        RETURN QUERY SELECT v_type, v_foil, v_res_subtype, v_res_stamp,
                            'NEEDS_REVIEW_NO_PROFILE'::TEXT, v_sig, NULL::UUID;
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.card_printing_profile p
         WHERE p.id = v_profile AND p.is_active
    ) THEN
        RETURN QUERY SELECT v_type, v_foil, v_res_subtype, v_res_stamp,
                            'NEEDS_REVIEW_INACTIVE_PROFILE'::TEXT, v_sig, NULL::UUID;
        RETURN;
    END IF;

    RETURN QUERY SELECT v_type, v_foil, v_res_subtype, v_res_stamp,
                        'RESOLVED_WITH_PROFILE'::TEXT, v_sig, v_profile;
END;
$$;

REVOKE ALL ON FUNCTION internal.compute_variant_residual_signature(JSONB, UUID, UUID) FROM PUBLIC;

COMMENT ON FUNCTION internal.compute_variant_residual_signature(JSONB, UUID, UUID) IS
    'PONTO UNICO do routing de Printing E do escopo de TAMANHO. Recebe a assinatura externa bruta e devolve a assinatura RESIDUAL (que alimenta o Variant Type) + o resultado do eixo Printing (traits e profile). Nenhum writer do pipeline pode voltar a raciocinar sobre a assinatura RAW. v1.1: a composicao usada e a ASSINATURA EFETIVA — traits_signature selada OU a composicao atual da N:N —, porque o selo e deferido e a propagacao editorial da Query 2181 roda ANTES do COMMIT. Query 2198: `size` normalizado fora de {NULL, STANDARD} devolve BLOCKED_SIZE_OUT_OF_SCOPE (jumbo) ou BLOCKED_SIZE_UNSUPPORTED (valor desconhecido) — ambos FORA da whitelist RESOLVED_*, o que impede TODOS os writers de produzir identidade canonica a partir da linha. `size` NAO integra a assinatura residual.';

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE FUNCTION, REVOKE, COMMENT. Nenhuma linha de dado alterada.
--
-- Postcheck imediato (read-only, apos aplicar):
--   1. pg_get_functiondef ILIKE '%BLOCKED_SIZE_%'            -> TRUE
--   2. pg_get_functiondef ILIKE '%NEEDS_REVIEW_INVALID_PRINTING_MAPPING%'
--                                                            -> TRUE (v1.1 intacta)
--   3. provolatile = 's', prosecdef = TRUE, proconfig = {search_path=""}
--   4. count(*) FROM catalog_variant_import_row              -> 6340
--   5. count(*) FROM catalog_variant_import_row
--        WHERE raw_data ? 'size'                             -> 0
--
-- Como validar:
--   Query 2827 - Validate Variant Size Scope Guard (casos A-J + regressao).
-- ============================================================================
