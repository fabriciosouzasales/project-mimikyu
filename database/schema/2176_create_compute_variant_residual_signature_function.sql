/*
===============================================================================
Projeto.....: Project Mimikyu
Query.......: 2176 - Create compute_variant_residual_signature() Function
Versão......: 1.1
Status......: CANÔNICA — CONFIRMADO EXECUTADO / LIVE / PROMOVIDO
Autor.......: Fabrício Sales / Claude
Data........: 2026-09-12
Promovida...: 2026-09-13 — TECHNICAL-CLOSEOUT-PROMOTION-01
Origem......: database/proposals/2026-09-12-card-variants-printing-routing/
              2176_create_compute_variant_residual_signature_function.sql
Mandato.....: CARD-VARIANTS — PRINTING-ROUTING — STAGING-GATE-A-01 (§8, §14)
               + STAGING-CORRECTION-03 (§1, §2, §3) — BLOCKER B-01

-------------------------------------------------------------------------------
VERSÃO 1.1 — BLOCKER B-01: O SELO É DEFERIDO, A COMPOSIÇÃO NÃO
-------------------------------------------------------------------------------
A v1.0 usava `m.traits_signature` para DUAS coisas ao mesmo tempo:

    (a) obter a composição do mapping;
    (b) decidir se existe mapping ATIVO para o token.

As duas estão erradas dentro da transação que CRIA o mapping.

trg_card_printing_external_mapping_seal é CONSTRAINT TRIGGER DEFERRABLE
INITIALLY DEFERRED: traits_signature só é gravada no COMMIT. Logo, na
propagação da Query 2181 — que roda na MESMA transação da criação — o
cabeçalho novo tem traits_signature NULL, mesmo com a N:N já completa.

Consequência real, medida na auditoria STAGING-FINAL-AUDIT-01:

    v_active_sig = NULL
      -> o teste `IS NOT NULL` falha
      -> cai no ramo "token já conhecido?"
      -> o PRÓPRIO mapping recém-criado satisfaz a busca
      -> retorna NEEDS_REVIEW_INACTIVE_MAPPING
      -> a CTE `resolved` da 2181 descarta tudo
      -> rows_revalidated = 0, SEM ERRO NENHUM

A ratificação editorial comitava criando o mapping e propagando NADA,
silenciosamente. Era exatamente a armadilha que o CONTRACT-CORRECTION §7
mandou fechar.

Correção — separar (a) de (b):

    (b) EXISTÊNCIA passa a ser decidida por m.id. Um mapping ativo existe
        se a linha existe, ponto. Nunca mais por um campo derivado que
        pode legitimamente estar NULL.

    (a) COMPOSIÇÃO passa a ser a ASSINATURA EFETIVA:

            COALESCE(traits_signature, composição atual da N:N ordenada)

        Selada -> usa a selada. Em montagem -> usa a N:N da própria
        transação. A fonte da verdade sempre foi a N:N; traits_signature
        é materialização.

E um estado novo, porque o caso patológico é REAL e distinto:

    mapping ATIVO + assinatura efetiva VAZIA
      -> NEEDS_REVIEW_INVALID_PRINTING_MAPPING

Não é RESOLVED_NO_PRINTING (o token TEM routing, só está quebrado) e não
é NEEDS_REVIEW_INACTIVE_MAPPING (o mapping está ATIVO; o defeito é a
composição). Fail-closed, com o nome certo.

Descrição resumida:
PONTO UNICO do routing: assinatura externa bruta -> Printing + assinatura
residual. Toda escrita SQL do pipeline passa por aqui.

Descrição:
Esta funcao existe para que NENHUM writer volte a raciocinar sobre a
assinatura RAW. Depois desta frente:

    RAW  -> (esta funcao) -> traits + profile   [eixo Printing]
                          -> residual           [eixo Acabamento]

Ter um ponto unico e o que fecha o blocker B3: a Query 2180 passa a
construir mapping de Variant Type a partir do RESIDUAL, e a 2158, que e
wrapper da 2180, herda a correcao sem logica paralela.

-------------------------------------------------------------------------------
ALGORITMO
-------------------------------------------------------------------------------
type  -> SEMPRE preservado no residual. Acabamento nunca vira Printing.
foil  -> SEMPRE preservado no residual. Idem.

subtype -> token INTEIRO ou nada. Igualdade exata, jamais parse.
    mapping ACTIVE            -> traits += ; residual_subtype := NULL
    so historico INACTIVE     -> NEEDS_REVIEW (token NAO volta ao residual)
    nunca conhecido           -> permanece no residual

stamp -> token a token, mesma regra.
    tokens consumidos saem; o resto e normalizado e ORDENADO.

-------------------------------------------------------------------------------
POR QUE "SO HISTORICO INATIVO" NAO VOLTA AO RESIDUAL
-------------------------------------------------------------------------------
CONTRACT-CORRECTION-02, §2. Se um token desativado voltasse ao residual,
ele seria reclassificado silenciosamente como ACABAMENTO — e um mapping
de Variant Type nasceria a partir dele, recriando dentro de
card_variant_type exatamente a composicao taxonomica que o Gate A do
modelo de Printing existe para impedir.

"Conhecido porem sem routing ativo" e um estado editorial, nao um estado
de desconhecimento. Fail-closed: para tudo e chama o editor.

-------------------------------------------------------------------------------
ESTADOS DE RETORNO (printing_state)
-------------------------------------------------------------------------------
RESOLVED_NO_PRINTING    nenhum token Printing -> profile NULL, VALID possivel
RESOLVED_WITH_PROFILE   traits -> profile exato e ativo -> VALID possivel
NEEDS_REVIEW_INACTIVE_MAPPING        token so com historico inativo
NEEDS_REVIEW_INVALID_PRINTING_MAPPING  mapping ATIVO com composicao efetiva
                                       vazia — estado estruturalmente
                                       invalido (v1.1)
NEEDS_REVIEW_INACTIVE_TRAIT     trait resolvido porem inativo
NEEDS_REVIEW_NO_PROFILE         traits validos, nenhum profile com assinatura exata
NEEDS_REVIEW_INACTIVE_PROFILE   profile encontrado porem inativo

Todos os consumidores (2179, 2180, 2181) testam por PERTENCIMENTO ao par
aceito ('RESOLVED_NO_PRINTING','RESOLVED_WITH_PROFILE'), nunca por
enumeracao fechada dos estados de erro. O estado novo e, portanto,
aditivo: cai automaticamente no lado da recusa.

Trait/profile inativo NUNCA e tratado como se o mapping nao existisse.
Nenhuma inferencia, nenhuma criacao automatica de Print Profile.

Regras de Negócio:
- Match de token por igualdade EXATA do valor normalizado.
- Print Profile por igualdade EXATA de traits_signature (UUID[] ordenado).
- Zero criacao automatica de Profile.
- STABLE: nao escreve nada; so le catalogo.

Pré-requisitos:
- Query 2095 - normalize_external_catalog_value().
- Query 2165/2166 - Print Trait / Print Profile.
- Query 2172/2173/2174 - external mapping + composicao + guards.

-------------------------------------------------------------------------------
REVISION HISTORY
-------------------------------------------------------------------------------
| 1.0 | **Versão inicial da função (2026-09-12).** Ponto único do routing de
        Printing. Substituída antes da execução por conta do BLOCKER B-01. |
| 1.1 | **Assinatura efetiva e estado INVALID_PRINTING_MAPPING (2026-09-12).**
        Separa existência (por `m.id`) de composição (COALESCE entre o selo e
        a N:N da própria transação), fechando o BLOCKER B-01. Esta é a versão
        executada e confirmada no banco físico. Promovida de
        database/proposals/ para database/schema/ em 2026-09-13
        (TECHNICAL-CLOSEOUT-PROMOTION-01). O SQL executável permanece
        idêntico ao artefato executado; só o cabeçalho registra o estado
        final. A proposal original é preservada como histórico. |
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
    'PONTO UNICO do routing de Printing. Recebe a assinatura externa bruta e devolve a assinatura RESIDUAL (que alimenta o Variant Type) + o resultado do eixo Printing (traits e profile). Nenhum writer do pipeline pode voltar a raciocinar sobre a assinatura RAW. v1.1: a composicao usada e a ASSINATURA EFETIVA — traits_signature selada OU a composicao atual da N:N —, porque o selo e deferido e a propagacao editorial da Query 2181 roda ANTES do COMMIT.';

COMMIT;

-- ============================================================================
-- Resultado esperado:
--   CREATE FUNCTION, REVOKE, COMMENT.
--
-- Como validar:
--   Query 2824 - Validate Card Printing Routing:
--     Secoes S7 e S8  — residual, token exato, inactive-only
--     Secao S14       — propagacao real (regressao direta do B-01)
--     Secao S27       — contrato temporal pre-COMMIT, testado diretamente
-- ============================================================================
